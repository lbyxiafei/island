# Agents 调研（VERSION — MVP）

本目录是 PLAN § Scope / VERSION — MVP 的调研底稿：本机四类 agent 的**任务完成信号**、**任务身份/标题**、**宿主进程**、以及**回到任务的可行手段**。
所有路径都是在本机 macOS 26.6.2 上实测的，样本来自 2026-09-24 的运行。

> 结论先行：三类 CLI agent（Claude Code / pi / Codex）都有**结构化落盘**，能稳定拿到「谁、什么时候、哪件事、在哪个目录」；
> 唯一缺的是「把用户送回对应窗口」那一步 —— tmux 可行，桌面 app 依赖 AppleScript / `open`，非 tmux 的终端窗口最弱。

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
| 宿主 | **没有 pid 落盘**（`~/.pi/agent` 下无状态/锁文件）→ 目前只能靠 `cwd` 猜，或后续用 `lsof` 反查 |
| resume | `pi --session <id>` |

实测 `stopReason` 分布：`toolUse: 105, stop: 3` —— 信号清晰。

## 3. Codex（桌面 + CLI 共用 `~/.codex`）

| 项 | 值 |
|---|---|
| 完成信号 | rollout jsonl 里 `event_msg` → `payload.type == "task_complete"`（带 `last_agent_message`） |
| rollout | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<threadId>.jsonl` |
| 目录索引 | `~/.codex/session_index.jsonl`：`{"id","thread_name","updated_at"}` —— 现成的 id + 标题 + 时间 |
| 身份 | `threadId` |
| 标题 | `session_index.jsonl` 的 `thread_name` |
| 宿主 | 桌面：`ChatGPT.app`（进程 `codex app-server`）；CLI：同 `claude` 思路 |
| resume | CLI `codex resume <id>`；桌面直接激活 `ChatGPT.app` |

实测 `session_index.jsonl` 里线程只到 2026-09-11，而桌面 app 明显还在用（`ChatGPT.app` 常驻）——**桌面版的活动可能没写进这个 index**，需要补查 `state_5.sqlite` / `thread_history_1.sqlite`。

## 4. Claude 桌面版

`~/Library/Application Support/Claude/`（Electron）。目前只看到 `IndexedDB/`、`Local Storage/`、`Session Storage/`，**没有可读的结构化任务列表**。
属最难的一档：需要 `computer use` / AppleScript UI 抓取，或逆向 Electron 的 IndexedDB。**MVP 建议先只做「检测到窗口 + 激活」，不做任务级解析。**

## 5. 回到任务的可行手段（按可靠性排序）

1. **tmux**（本机最常见）：`claude → zsh → tmux`。可由 pid 沿父进程链上溯到 tmux server pid，再 `tmux list-panes -a -F '#{pane_pid} ...'` 反查 `session:window.pane`，然后 `tmux select-window -t <target>` + `tmux select-pane -t <target>`，最后激活终端 app。实测 pane 标题已经带上 claude 的会话标题（`✳ 多Agent工作流框架`），可直接用于展示。
2. **桌面 app**：`NSRunningApplication` / `open -a`，按 bundle id 激活（`com.openai.chat` / `com.anthropic.claudefordesktop`）。
3. **非 tmux 终端**（Ghostty / Terminal / iTerm2 / VS Code 内终端）：Ghostty 无脚本接口；Terminal/iTerm2 有 AppleScript 但难以定位到具体 tab；VS Code 内终端无法可靠定位。→ **兜底一律把 `resumeCommand` 贴到 clipboard**（PLAN § Design 已认可这是 second best）。

## 6. 未决问题（下一轮调研）

- Codex 桌面版的活动到底落在哪张 sqlite，是否有「turn 完成」时间戳
- Claude 桌面版有没有可读的本地任务状态（否则只能 computer use）
- 非 tmux 终端窗口的定位手段（iTerm2 AppleScript 的 session 匹配、Ghostty 未来是否有 CLI）
- 一个 agent 在 VS Code 内运行时，如何把焦点给到正确 terminal 面板
