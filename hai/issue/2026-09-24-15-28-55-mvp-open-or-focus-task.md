---
type: feat
name: mvp-open-or-focus-task
title: "MVP: 点击任务回到宿主窗口 / 兜底贴 clipboard"
status: solved
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:48:00-07:00
---

Scope-check: PLAN § Scope / VERSION — MVP；PLAN § Design / Agents 交互 interface 第 3 条。授权来源：用户会话指令「把未完成的 issues 都自主处理了」。

## 实现

可测的决策层 `IslandCore/AgentReopen.swift`：

- `ProcessTree.parse` / `ancestors(of:in:)`：吃 `ps -axo pid=,ppid=`，沿父进程链上溯（到 launchd 停，带环保护）
- `TmuxPane.parse`：吃 `tmux list-panes -a -F '#{pane_pid} #{session_name}:#{window_index}.#{pane_index}'`
- `AgentReopen.plan(for:processNodes:tmuxPanes:)`：agent pid 的祖先链命中某个 pane → `.focusTmux`；否则桌面 host → `.activateApp`；否则 `.copyToClipboard(resumeCommand)`；都没有 → `.nothing`

执行层 `Sources/Island/AgentReopenExecutor.swift`：

- `.focusTmux`：`tmux select-window` + `select-pane`，再找出 tmux client 的祖先里第一个真实 GUI app（`NSRunningApplication`）并激活；找不到就按 Ghostty / Terminal / iTerm2 / Warp / VS Code 的顺序激活
- `.activateApp`：未运行就 `NSWorkspace.openApplication`
- `.copyToClipboard`：`NSPasteboard`
- tmux 路径按 `/opt/homebrew` → `/usr/local` → `/opt/local` → `/usr/bin` 探测（`open` 启动的 app 没有 Homebrew PATH）

## 验证

- 单元测试 `AgentReopenTests`：tmux 命中 / 无 tmux 兑底 clipboard / terminal 无 resume / 桌面 app / unknown，以及 `ps`、`tmux` 输出的解析与环保护
- 真机：新增调试命令 `--reopen-plan <pid>`，对 5 个真实 claude 进程的输出与 `tmux list-panes` 完全对应：

```
83859 -> focusTmux(windowTarget: "island:1",   paneTarget: "island:1.1")
11639 -> focusTmux(windowTarget: "job:3",      paneTarget: "job:3.1")
 9408 -> focusTmux(windowTarget: "job:1",      paneTarget: "job:1.1")
43569 -> focusTmux(windowTarget: "job:2",      paneTarget: "job:2.1")
14052 -> focusTmux(windowTarget: "dalaoshi:1", paneTarget: "dalaoshi:1.1")
```

- 未验证：真正的 `select-window` + 激活终端（会抢焦点，不适合在无头环境自动跑，会打扰用户）。**请验收时实际点一个 Claude Code 任务**，确认 tmux 切过去了。

## 备注

- 非 tmux 终端（Ghostty 本身 / VS Code 内终端）仍然只能兑底 clipboard —— 与 PLAN 认可的 second best 一致
- `.focusTmux` 后若 tmux 客户端在多个终端里 attach，激活的是祖先链里第一个 app，不保证是最前台的那个
