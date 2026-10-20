---
type: bug
name: terminal-reopen-stops-working
title: "开机自启的 island 点击终端任务不跳转（重启 island 后正常）"
status: in-progress
created_ts: 2026-10-01T13:18:16-07:00
updated_ts: 2026-10-20T10:07:48-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

2026-10-01 用户反馈：正在运行的 brew 版 island 0.2.3（pid 2174，09:55 左右随登录启动），下拉框里点 Claude 桌面版的行能跳转，点终端（Claude Code in tmux / cmux）的行不跳转。此前用户刚在 Settings → Notifications 把完成弹出关掉（`IslandPopupEnabled = 0`）。

## 排查记录

- 代码层面：`PopupSettings` 只影响自动弹出（`AppDelegate.showOverlay` 的两处 `popup.isEnabled`），不参与 `selectTask` → `reopenQueue` → `AgentReopenExecutor.perform`，判断与弹出开关无关
- 同一二进制 CLI 复现：`Island --reopen-plan 11407 --perform` → `focusTmux(chore:2.1)`，tmux client 切换成功，cmux tab 也聚焦成功
- 杀掉旧进程、用 `nohup /Applications/Island.app/Contents/MacOS/Island > scratchpad/island.log` 重启后，用户在 GUI 里点终端行**跳转正常**（日志：`tmux client /dev/ttys000 -> job:2.1` + `focused scriptable(com.cmuxterm.app ...)`）
- 旧进程由 launchd 启动，stderr 无处可去，点击时走了哪条路径**没有留下证据**；进程已被杀，现场丢失。**根因未定位**

- 2026-10-20 第二次：用户重启电脑后，开机自启的 island（21:12:29 启动，早于 cmux 21:13:04、tmux server 21:24:15）**每次**点终端行都回不去；`pkill` 后用 `open --stderr <log> /Applications/Island.app`（同样经 LaunchServices、环境同开机自启）重启，点击正常：`tmux client /dev/ttys000 -> island:1.1` + `focused scriptable(com.cmuxterm.app ...)`
- 两次故障的共同点：island 启动早于 cmux / tmux server。重启 island（晚于二者）即恢复
- 已排除：Automation 授权（TCC 里 island → com.cmuxterm.app = allowed）；tmux socket（`/tmp/tmux-501/default`，无 `TMUX_TMPDIR`）；`AgentReopenExecutor` / `TerminalTabFocuser` 无启动期缓存；`NSWorkspace.runningApplications` 在后台队列也能看到 island 之后才启动的 app（scratchpad 小实验验证）
- 仍缺故障进程的日志，根因未定位

## 可能方向（未验证）

1. `reopenQueue` 是串行队列，`Subprocess.run` 没有超时：某次 osascript / tmux 卡住会让之后所有 reopen 排队不动。但 Claude 桌面版的 openURL 也在同一队列，与"桌面版正常"矛盾，除非桌面版的点击发生在卡住之前
2. 旧进程里点击前的 `pruneClosed` 把行判为已关闭（但这会让行消失，用户应能察觉）
3. 长时间运行后 tmux / cmux 状态与 island 缓存不一致（tmux server 12:04 才启动，晚于 island）

## Decision

- 2026-10-20，用户（仓库作者）在会话中同意：先做日志落盘（`~/Library/Logs/island.log`，带时间戳，reopen 每一步记结果），ship 后跑 `./scripts/publish.sh 0.2.4` 发版（含 tag 与 brew tap 更新）；用户重启电脑复现后再据日志定位根因修复

## 期望结果

- 复现时能拿到证据：GUI 运行时的日志要落盘（例如 `~/Library/Logs/island.log`），否则下次仍然无从判断
- 定位根因后修复，并补上能覆盖该路径的 `IslandCore` 测试

## 备注

- 当前（2026-10-01）island 由 Agent 以 nohup 方式前台启动，日志在会话 scratchpad；用户再遇到时先别重启，直接看日志
- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-10-20T10:07:48-07:00: new -> in-progress

用户确认方案（见 Decision）。第一步：日志落盘 + reopen 路径逐步记录，发 0.2.4 收集故障现场证据。
