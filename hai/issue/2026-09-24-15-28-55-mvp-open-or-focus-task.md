---
type: feat
name: mvp-open-or-focus-task
title: "MVP: 点击任务回到宿主窗口 / 兜底贴 clipboard"
status: new
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:34:10-07:00
---

Scope-check: PLAN § Scope / VERSION — MVP；PLAN § Design / Agents 交互 interface 第 3 条。

## 背景

`AgentTask` 已经带 `host`（`.terminal(processID)` / `.desktop(bundleID)` / `.unknown`）与 `resumeCommand`。缺的是「点一下真的回到那个任务」。

## 调研结论（详见 `hai/reference/agents/README.md`）

1. **tmux 最靠谱**：本机 Claude Code 全部是 `claude → zsh → tmux`。可由 pid 沿父进程链上溯到 tmux，再 `tmux list-panes -a -F '#{pane_pid} ...'` 反查到 `session:window.pane`，`tmux select-window/select-pane` 之后激活终端 app。pane 标题已经带 claude 会话标题，可直接复用
2. **桌面 app**：按 bundle id 激活（`com.openai.codex` / `com.anthropic.claudefordesktop`）
3. **非 tmux 终端**：Ghostty 无脚本接口，Terminal/iTerm2 的 AppleScript 定位不到具体 tab，VS Code 内终端无法可靠定位 → 一律把 `resumeCommand` 贴到 clipboard

## 期望结果

- 点击 task：优先「精确聚焦」（tmux pane / 桌面 app），做不到就激活兜底 app，再做不到就 `resumeCommand` → clipboard，并给用户一句反馈
- 每种情况都要有明确 fallback 链，不能点了没反应

## 备注

- 需要研究 `NSWorkspace` / `NSRunningApplication` 激活的正确姿势（accessory app 激活别的 app 有额外限制）
- 需要把「pid → tmux target」做成可测的纯逻辑（父进程链解析吃 `ps`/`sysctl` 输出）
