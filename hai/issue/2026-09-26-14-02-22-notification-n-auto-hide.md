---
type: chore
name: notification-n-auto-hide
title: "[ux] make notification configurable and auto hide notification when user focus on ai agent panel"
status: solved
created_ts: 2026-09-26T14:02:22-07:00
updated_ts: 2026-09-26T15:24:09-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

两个要求：
1. 当 agent 运行完成，如果用户的页面已经是当前的agent的运行界面，就没有必要notify提示了 — 没有提示，但是当用户打开drop down，要在list里能看到这个agent刚刚运行完成 just now，只是没有未读的提示圆点。这里有一个更加 advanced 的要求：如果用户没有通过点击 island pop up msg的方式自己切换窗口回到了刚完成的 agent window，island“最好”能够检测出来并且把menu bar上图标的msg减一，同时消掉未读圆圈。
2. 我们要重新定义下 island 的 notification 的行为，并且收录到 settings，详情看下一章。

## 期望结果

我们定义如下 notification 的种类：
1. menu bar 的图标msg+1，这个是default 的，应该永远都是保持这样，setting也改不了
2. 在island pop up处进行即时展示（x秒，x默认5秒，在settings里有一个专门的设置），当鼠标hover到这个即时pop up的时候，就停止计时，即不消失。这一个 notification setting是可以toggle on/off 在settting 配置里。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-26T15:14:52-07:00: new -> in-progress

Scope-check: PLAN § Design / Island 展示 UX（未读标记、菜单栏数字）与 § Goal（弹出 5 秒可配置）；用户在会话中明确要求实现。开始在 worktree 实现。

## 2026-09-26T15:24:09-07:00: in-progress -> solved

实现了两部分：

1. **正看着的任务不通知**：`TaskVisibility`（IslandCore）+ `TaskVisibilityProbe`（Sources/Island）判断完成时任务所在 tab 是否就在眼前；是则直接记为已读——不弹出、不计数、列表里有但无红点。未读项每轮（3s）以及切换 app 时重查一次，用户自己切回去就自动消红点、菜单栏减一（advanced 要求）。判据宁可漏判：tmux（当前 pane + 挂着的 client + 宿主 tab）、cmux（surface id）、Terminal / iTerm2（tty）、Ghostty（唯一 cwd 匹配）、VS Code（扩展 0.2.0 发布窗口 focused + 当前终端 pid）、桌面 app（前台即算，只能到 app 级）。AppleScript 前先确认已授权，绝不弹授权框。
2. **弹出可配置**：`Settings…` → `Notifications`：弹出开关 + 停留秒数（默认 5，覆盖 `ISLAND_OVERLAY_SECONDS`），hover 暂停沿用原逻辑；菜单栏计数不受开关影响。

验证：`make verify` 全过（273+ 测试，覆盖率 100%）；`--in-view` 实测 VS Code（模拟 window 文件）、tmux-in-cmux（当前 pane 在眼前 / 无 client 的 session 不在）判断正确；设置窗口实测开关与秒数即时落盘。

未覆盖：Ghostty 本机未运行，只有单测；VS Code 需 reload 一次窗口扩展才会开始发布状态；没有跑一次真实 agent 完成的端到端（会花 API 钱）；桌面 app 只到 app 级粒度（前台看的是别的对话也会算已读）。
