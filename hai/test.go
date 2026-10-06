package main

import (
	"container/heap"
	"context"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// ---------- 延迟消息用的最小堆（按到期时间排序） ----------

type item struct {
	msg string
	at  time.Time
}
type delayHeap []item

func (h delayHeap) Len() int           { return len(h) }
func (h delayHeap) Less(i, j int) bool { return h[i].at.Before(h[j].at) }
func (h delayHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *delayHeap) Push(x any)        { *h = append(*h, x.(item)) }
func (h *delayHeap) Pop() any {
	old := *h
	it := old[len(old)-1]
	*h = old[:len(old)-1]
	return it
}

// ---------- Broker ----------

type Broker struct {
	mu      sync.Mutex
	ready   []string      // 已可见、还没人取的消息
	waiters []chan string // 正挂着等消息的 receive 请求
	delayed delayHeap     // 还没到点的消息
	wake    chan struct{} // 插入了更早的延迟消息时，叫醒计时器
}

func NewBroker() *Broker {
	b := &Broker{wake: make(chan struct{}, 1)}
	go b.timerLoop()
	return b
}

// 调用方必须持有锁。有人在等就直接交给他，否则存进 ready。
func (b *Broker) deliverLocked(msg string) {
	if len(b.waiters) > 0 {
		w := b.waiters[0]
		b.waiters = b.waiters[1:]
		w <- msg // 有 1 个缓冲，不会阻塞
		return
	}
	b.ready = append(b.ready, msg)
}

func (b *Broker) Send(msg string, delay time.Duration) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if delay <= 0 {
		b.deliverLocked(msg)
		return
	}
	heap.Push(&b.delayed, item{msg, time.Now().Add(delay)})
	select { // 非阻塞地叫醒计时器，让它重新计算该睡多久
	case b.wake <- struct{}{}:
	default:
	}
}

// Long polling 的核心：没数据就挂起，等 deliverLocked 往 channel 里塞消息。
func (b *Broker) Receive(ctx context.Context) (string, bool) {
	b.mu.Lock()
	if len(b.ready) > 0 {
		msg := b.ready[0]
		b.ready = b.ready[1:]
		b.mu.Unlock()
		return msg, true
	}
	ch := make(chan string, 1)
	b.waiters = append(b.waiters, ch) // 登记：我在等
	b.mu.Unlock()

	select {
	case msg := <-ch: // 被叫醒
		return msg, true
	case <-ctx.Done(): // 超时或客户端断开
		b.mu.Lock()
		removed := false
		for i, w := range b.waiters {
			if w == ch {
				b.waiters = append(b.waiters[:i], b.waiters[i+1:]...)
				removed = true
				break
			}
		}
		b.mu.Unlock()
		if !removed { // 竞态：超时的同一瞬间消息已经塞进来了，不能丢
			return <-ch, true
		}
		return "", false
	}
}

// 全系统唯一的"计时检查"：睡到堆顶到期，或被新插入的更早消息叫醒。
func (b *Broker) timerLoop() {
	for {
		b.mu.Lock()
		now := time.Now()
		for b.delayed.Len() > 0 && !b.delayed[0].at.After(now) {
			it := heap.Pop(&b.delayed).(item)
			b.deliverLocked(it.msg) // 到点了，变成可见并叫醒等待者
		}
		wait := time.Hour
		if b.delayed.Len() > 0 {
			wait = time.Until(b.delayed[0].at)
		}
		b.mu.Unlock()

		t := time.NewTimer(wait)
		select {
		case <-t.C:
		case <-b.wake:
			t.Stop()
		}
	}
}

// ---------- HTTP ----------

func main() {
	b := NewBroker()

	// POST /send?delay=5s   body = 消息内容
	http.HandleFunc("/send", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		delay, _ := time.ParseDuration(r.URL.Query().Get("delay"))
		b.Send(string(body), delay)
		w.WriteHeader(http.StatusAccepted)
	})

	// GET /receive?wait=20   最多挂 20 秒
	http.HandleFunc("/receive", func(w http.ResponseWriter, r *http.Request) {
		sec, err := strconv.Atoi(r.URL.Query().Get("wait"))
		if err != nil || sec <= 0 || sec > 20 {
			sec = 20
		}
		ctx, cancel := context.WithTimeout(r.Context(), time.Duration(sec)*time.Second)
		defer cancel()
		if msg, ok := b.Receive(ctx); ok {
			fmt.Fprintln(w, msg)
			return
		}
		w.WriteHeader(http.StatusNoContent) // 等满了也没有，返回空
	})

	fmt.Println("listening on :8080")
	http.ListenAndServe(":8080", nil)
}
