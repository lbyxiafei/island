---
type: feat
name: mvp-agent-detection-core
title: "MVP: 统一 agent 任务检测内核（Claude Code / pi / Codex）"
status: solved
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:34:10-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Scope / VERSION — MVP（「帮我按照 design 和 scope 的描述，进行 调研、试验性改动、验证」）。授权来源：用户在会话中明确指令「我新增了version mvp，你去执行下」。不触发 Ask first（零新依赖）。

## 调研结论

完整版见 `hai/reference/agents/README.md`。要点：

| agent | 完成信号 | 身份 | 标题 | 宿主 |
|---|---|---|---|---|
| Claude Code (terminal) | `~/.claude/sessions/<pid>.json` 的 `status == idle` | `sessionId` | `name`（或正文 `ai-title`） | 文件里的 `pid`（实测全部挂在 tmux 下） |
| pi (terminal) | 会话 jsonl 最后一条 assistant 的 `stopReason == "stop"` | 首行 `session.id` | 第一条 user message（截断） | 没有 pid 落盘 |
| Codex | `~/.codex/session_index.jsonl` 的 `updated_at`（rollout 里有 `task_complete` 事件） | `threadId` | `thread_name` | 桌面 `ChatGPT.app` / CLI |

## 实现

- `IslandCore/AgentTask.swift`：统一模型（agent / sessionID / title / cwd / completedAt / host / resumeCommand），`id` 按 `sessionID + completedAt` 构造，所以同一 session 的下一轮是新条目
- `IslandCore/AgentActivity.swift`：`AgentActivitySource` 协议 + 三个实现 + `AgentActivityScanner`。全部是「吃一个 URL、只读文件」的纯逻辑；缺失目录 / 半写文件 / 坏行都只少出任务，不崩
- `IslandCore/AgentInbox.swift`：增量入库、已读/未读、未读优先 + 时间倒序、条数上限 N（`TaskLimit`，env `ISLAND_TASK_LIMIT`，默认 10）、容量超限先丢最旧的已读
- `Sources/Island/main.swift`：`--scan-agents` 打印本机检测到的全部已完成 run（调试用，故意不按增量过滤）

## 验证

- 单元测试：新增 `AgentActivityTests` / `AgentInboxTests`（含 fixture 目录、坏行、缺文件、标题兜底、时区/小数秒解析），总计 92+ 个测试全绿，覆盖率维持 100
- 真机 `--scan-agents`：一次性列出 5 条 Claude Code、多条 pi、多条 Codex 的真实 run，字段（标题/目录/宿主/resume 命令）与调研一致
- 增量语义由 `AgentMonitor`（见 `mvp-menubar-unread-badge`）落实：只取 `completedAt >= 启动时间`

## 未覆盖 / 后续

- Codex 桌面版与 Claude 桌面版的数据源 → `mvp-desktop-agent-sources`
- 非 tmux 终端（Ghostty / Terminal / iTerm2 / VS Code 内终端）的窗口定位 → `mvp-open-or-focus-task`
