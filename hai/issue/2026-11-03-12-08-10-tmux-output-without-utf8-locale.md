---
type: bug
name: tmux-output-without-utf8-locale
title: "开机启动的 island 解析不到 tmux pane（无 UTF-8 locale 时 tab 被转成 _）"
status: solved
created_ts: 2026-11-03T12:08:10-08:00
updated_ts: 2026-11-03T12:09:36-08:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

0.2.5 修好"恢复会话后 pid 过期"之后，2026-11-03 开机又复现：点终端任务只复制 `claude --resume …`。日志：

```
plan for terminal(processID: 6166): 885 processes, 0 tmux panes
no app hosts pid 6166: chain [6166, 5917, 1587], 12 regular apps
```

pid 6166 是活的、确实在 tmux pane `job:1.1` 里，但 `list-panes` 解析出 0 个 pane，且 tmux 没报错。

根因：开机自启（login item）的 island 环境里没有 `LANG` / `LC_*`。tmux client 认为不支持 UTF-8，把输出里的控制字符替换成 `_`——`-F` 格式里的 tab 变成 `1682_island:1.1`，`TmuxPane.parse` 一行都解析不出来。命令行跑 `--reopen-plan` 带着 shell 的 UTF-8 locale，所以看起来正常；`env -i` 下复现 0 panes。`TaskVisibilityProbe` 走同一个 `tmuxArguments`，同样受影响。

与 [terminal-reopen-stops-working](2026-10-01-13-18-16-terminal-reopen-stops-working.md)（pid 过期）是两个独立的 bug，现象相同。

## 期望结果

每次调用 tmux 都带 `-u`（`TmuxCommand.arguments`），无论 island 从哪里启动都拿到原样的 tab。

## 验证

`env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME <Island> --reopen-plan 6166`：0.2.5 → `0 tmux panes` / `focusHostApp`；新构建 → `8 tmux panes` / `focusTmux(job:1.1)`。

Scope-check: PLAN § Design（点击任务回到原 tmux pane）

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-11-03T12:09:35-08:00: new -> in-progress

Scope-check: PLAN § Design；根因已定位（无 UTF-8 locale 时 tmux 输出的 tab 被替换成 _），开始修复

## 2026-11-03T12:09:36-08:00: in-progress -> solved

所有 tmux 调用加 -u（TmuxCommand.arguments，新增 1 个测试）。env -i 模拟开机环境：旧版 0 panes，新版 8 panes 并规划到 focusTmux。随 0.2.6 发布。
