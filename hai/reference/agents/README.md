# Agents 调研（VERSION — MVP）

本目录是 PLAN § Scope / VERSION — MVP 的调研底稿：本机四类 agent 的**任务完成信号**、**任务身份/标题**、**宿主进程**、以及**回到任务的可行手段**。
所有路径都是在本机 macOS 26.6.2 上实测的，样本来自 2026-09-24 的运行。

> 结论先行：三类 CLI agent（Claude Code / pi / Codex）都有**结构化落盘**，能稳定拿到「谁、什么时候、哪件事、在哪个目录」；
> “把用户送回对应窗口”也能做到大多数情况：tmux 精确命中，VS Code 可聚焦到对应文件夹，桌面 app 直接激活；
> 只有非 tmux、非 VS Code 的终端（Ghostty / Terminal / iTerm2）只能到 app 级别，其余兑底 resume 命令进 clipboard。

## 0. 通用中间层（提议）

```
AgentActivitySource (protocol)          # 每种 agent 一个实现，只负责「读出已完成任务」
  └─ completedTasks() -> [AgentTask]

AgentTask                               # 统一模型，UI 只认这个
  id            String                  # 全局唯一（agent + 原生 session id）
  agent         AgentKind               # claudeCode / pi / codex
  title         String                  # 展示用
  cwd           String?                 # 工作目录
  completedAt   Date                    # 该次 turn 完成时间
  host          AgentHost               # .terminal(processID) / .desktop / .unknown
  resumeCommand String?                 # 兜底：贴到 clipboard 就能回到任务
```

`AgentInbox` 负责「增量 + 已读/未读 + 排序 + 上限 N」这套纯逻辑（见 §5）。

## 1. Claude Code（terminal）

| 项 | 值 |
|---|---|
| 完成信号 | `~/.claude/sessions/<pid>.json` 里 `status` 从 `busy` → `idle` |
| 会话状态文件 | `~/.claude/sessions/<pid>.json`（每个活着的 claude 进程一份） |
| 会话正文 | `~/.claude/projects/<slug>/<sessionId>.jsonl`，含 `ai-title` 条目 |
| 身份 | `sessionId`（= 正文文件名） |
| 标题 | 状态文件里的 `name`（如 `island-6d`）；更语义化的是正文里的 `ai-title`（如 `vscode space m md preview功能`） |
| 宿主 | 状态文件里的 `pid`；实测 5 个 claude 进程全部挂在 tmux 下（`claude → zsh → tmux`） |
| resume | `claude --resume <sessionId>`（实测同一 sessionId 可被正文文件名对上） |

状态文件实测样本：

```json
{"pid":83859,"sessionId":"7ce513b7-...","cwd":"/Users/binyanli/Repos/island",
 "name":"island-6d","status":"busy","startedAt":1790288079652,"updatedAt":1790288825080,
 "entrypoint":"cli","messagingSocketPath":"/tmp/cc-socks/83859.sock"}
```

**坑**：`sessions/` 里还有一堆 `<pid>.<hash>.key`，只认 `.json`。进程退出后状态文件不会立刻消失，`status` 可能停在 `idle`，需要按 `updatedAt` 做增量判定。

## 2. pi（terminal）

| 项 | 值 |
|---|---|
| 完成信号 | 会话 jsonl 里**最后一条 assistant message 的 `stopReason == "stop"`**（`toolUse` 表示还在跑） |
| 会话文件 | `~/.pi/agent/sessions/<cwd-slug>/<ISO-ts>_<session-uuid>.jsonl` |
| 身份 | 首行 `{"type":"session","id":...,"cwd":...}` 的 `id` |
| 标题 | 没有专门字段；取第一条 user message 的文本（截断），兜底用 `cwd` basename |
| 宿主 | 没有 pid 落盘。改为**点击时反查**：`ps -axo pid=,comm=` 筛出命令名为 `pi` 的进程，再用 `lsof -a -p <pids> -d cwd -Fpn` 取各自 cwd，按 session 的 cwd 匹配。实测 `pi` 是 node 脚本，`lsof -c pi` **匹配不到**（lsof 看到的是 node），所以必须走 `ps` 拿 pid |
| 实测宿主链 | `pi → zsh → Code Helper → Code`，即 **VS Code 集成终端**，不在 tmux 里 |
| resume | `pi --session <id>` |

实测 `stopReason` 分布：`toolUse: 105, stop: 3` —— 信号清晰。

## 3. Codex（桌面 + CLI 共用 `~/.codex`）

| 项 | 值 |
|---|---|
| **完成信号（权威）** | `~/.codex/thread_history_1.sqlite` 的 `thread_turns.status == 'completed'`，带 `completed_at`（秒） |
| **任务元数据** | `~/.codex/state_5.sqlite` 的 `threads` 表：`id` / `name`（短标题）/ `title`（首条 user message）/ `cwd` / `updated_at_ms` / `source` / `archived` |
| 轻量索引（兜底） | `~/.codex/session_index.jsonl`：`{"id","thread_name","updated_at"}` |
| 身份 | `threads.id`（= `thread_turns.thread_id`） |
| 标题 | `threads.name`，没有时用 `title`，再没有用 `cwd` basename |
| 宿主 | 桌面 `ChatGPT.app`（bundle id `com.openai.codex`）；CLI 同样写这张表（`source='vscode'`） |
| resume | `codex resume <id>` |

实测可用的查询（两个库靠 `attach` 连起来，`sqlite3 -json` 直出 JSON，省得处理分隔符）：

```sql
attach database '~/.codex/thread_history_1.sqlite' as history;
select threads.id as id, threads.name as name, threads.title as title,
       threads.cwd as cwd, max(history.thread_turns.completed_at) as completed_at
from history.thread_turns
join threads on threads.id = history.thread_turns.thread_id
where history.thread_turns.status = 'completed'
group by threads.id
order by completed_at desc limit 100;
```

**坑（重要）**：这两个库用 `sqlite3 -readonly` 打不开（`unable to open database file (14)`，WAL 无法在只读连接下恢复）；去掉 `-readonly`、只跑 SELECT 即可。实测 `thread_turns.status` 取值只有 `completed`(857) 与 `interrupted`(2)。

> 说明：截至调研时，`threads` 里最新的线程也是 2026-09-11，`source` 全是 `vscode`。即**本机最近没用过 Codex 桌面版**，所以桌面路径无法用真实新数据验证；实现用的是同一张表，桌面线程只是 `source` 不同。

## 4. Claude 桌面版

`~/Library/Application Support/Claude/`（Electron）。聊天在服务端，本地没有 JSON / sqlite 形式的会话列表。

**已解决（2026-09-25，issue `claude-desktop-source`）**：claude.ai 前端把 react-query 缓存持久化进 IndexedDB 的外部 blob：

- 路径：`IndexedDB/https_claude.ai_0.indexeddb.blob/<db>/<xx>/<blob id>`。每次持久化都**写一个新文件**（id 递增），旧的会被回收，所以取 mtime 最新的那个
- 编码：`ff 11 02`（Blink 的 snappy 包装）+ snappy 原始流；解压后是 Blink envelope `ff 15 fe …`，再后面是 `ff 10` + V8 structured clone。顶层是 `{buster: "conversations_v2:…", timestamp, clientState: {queries: [...]}}`；V8 数组基本是 sparse（`a … @`）
- 用得上的 query：
  - `["hub_transcript", {orgUuid}, {uuid}]` → `state.data.messages`：最后一条 `sender == "assistant"` 且 `stop_reason == "end_turn"` 即回复完成（点停止是 `user_canceled`）；时间取 `updated_at`
  - `["chat_conversation_list", …]` → `state.data.pages[].data[]`（或 `state.data.data[]`）：`uuid` → `name`（对话标题）
  - `sessions_api_list_sessions`：看到的是 CLI 会话的 remote-control 镜像（`origin: claude_code_cli`、`environment_kind: bridge`），不作为数据源，避免与 Claude Code CLI 重复
- 实测写盘延迟约 5s；生成中不会写入半截回复
- 回到对话：`claude://claude.ai/chat/<uuid>`（app 注册了 `claude` scheme）
- 局限：只有**当前打开 / 最近打开**的对话才有 `hub_transcript`；格式无公开文档，桌面版升级可能改动

## 5. 回到任务的可行手段（按可靠性排序）

1. **tmux**（本机最常见）：`claude → zsh → tmux`。可由 pid 沿父进程链上溯到 tmux server pid，再 `tmux list-panes -a -F '#{pane_pid} ...'` 反查 `session:window.pane`，然后 `tmux select-window -t <target>` + `tmux select-pane -t <target>`，最后激活终端 app。实测 pane 标题已经带上 claude 的会话标题（`✳ 多Agent工作流框架`），可直接用于展示。
2. **终端 app（非 tmux）**：在 agent 的祖先链里找已知终端的 bundle id。实测 pi 的链是 `pi → zsh → Code Helper → Code`，即 `com.microsoft.VSCode`；VS Code 可以用 `open -b com.microsoft.VSCode <cwd>` 直接聚焦到对应文件夹的窗口（最接近“回到那个会话”）。Ghostty / Terminal / iTerm2 只能 `activate()` 到 app 级别，定位不到具体 tab。
3. **桌面 app**：`NSRunningApplication` / `open -a`，按 bundle id 激活（`com.openai.codex` / `com.anthropic.claudefordesktop`）。
4. **都定位不到**：把 `resumeCommand` 贴到 clipboard（PLAN § Design 已认可这是 second best）。

## 6. 未决问题（下一轮调研）

- ~~Codex 桌面版的活动到底落在哪张 sqlite~~ → 已解决，见 § 3
- ~~Claude 桌面版有没有可读的本地任务状态~~ → 已解决，见 § 4
- Claude 桌面版的 Code 标签页：自带一份 Claude Code（`Claude/claude-code/<ver>/claude.app`），推测也写 `~/.claude/sessions`，待真实数据验证
- 非 tmux 终端窗口的定位手段（iTerm2 AppleScript 的 session 匹配、Ghostty 未来是否有 CLI）
- 一个 agent 在 VS Code 内运行时，如何把焦点给到正确 terminal 面板
