---
type: bug
name: terminal-reopen-stops-working
title: "开机自启的 island 点击终端任务不跳转（重启 island 后正常）"
status: solved
created_ts: 2026-10-01T13:18:16-07:00
updated_ts: 2026-10-21T16:31:51-07:00
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
- 2026-10-20 第一步（证据收集）已实现：GUI 实例日志落盘 `~/Library/Logs/island.log`（带时间戳），reopen 路径每一步记结果（tmux 退出码 / 宿主 app 查找 / osascript 失败 / `activate()` 返回值）。随 0.2.4 发布；下次开机自启实例复现后读日志定位
- 2026-10-20 `publish.sh 0.2.4` 卡在公证：notarytool 返回 HTTP 403「A required agreement is missing or has expired」，需要账号持有人在 developer.apple.com 签署新协议后 `macos-signing restore` 再发版。代码已 ship 到 master（292bd29）
- 2026-10-20 用户签署新版 Program License Agreement，约 2 分钟后公证恢复；0.2.4 已发布（app 与 dmg 公证 Accepted，tag `v0.2.4`，tap Release `island-v0.2.4`）。下一步：用户升级后重启电脑，复现时读 `~/Library/Logs/island.log`

## 根因（2026-10-21 定位）

重启电脑后用户仍在 0.2.3（未升级），直接对故障中的开机自启实例（pid 3196）取证：

- 临时把 `/opt/homebrew/bin/tmux` 换成只记录 island 调用的包装脚本（取证后已恢复原软链）。点击那一刻 island 只调用了 `tmux list-panes -a`（成功，4 个 pane），**之后没有 select-window / switch-client，也没有 osascript**
- 用户剪贴板里出现 `claude --resume 74b3e379-…`：reopen 走到了 `focusHostApp` → 找不到宿主 → `copyResumeCommand` 兜底
- 同一 session 当前 pid 50722（`claude -c`，16:00:18 启动，父进程是 tmux pane `island:1.1` 的 shell 4262）；CLI `--reopen-plan 50722` 得到 `focusTmux(island:1.1)`，正常

即：**inbox 里的行带着入库那一刻的 `AgentHost.terminal(pid)`，之后从不更新**。session 被恢复（`claude -c` / `--resume`，重启电脑后几乎必然）或入库时读到了重启前残留的 `~/.claude/sessions/<旧pid>.json`，行里的 pid 就是死的（或被别的进程复用），进程链对不上任何 tmux pane，也对不上任何终端 app。重启 island 会清空 inbox，新行带当前 pid，所以"重启 island 就好了"。与通知开关无关。

修法：点击前与每轮 poll 用 session 文件里**仍在运行**的 pid 刷新行的 host（`AgentActivitySource.liveHosts` + `AgentInbox.refreshHosts`），行的 id / 已读状态不变。

## 可能方向（已被上面的根因取代）

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

## 2026-10-21T16:31:51-07:00: in-progress -> solved

根因：inbox 行的 `AgentHost.terminal(pid)` 在入库时定死，session 被恢复（`claude -c` / 重启后 resume）后 pid 失效，进程链对不上 tmux pane，点击退到复制 `claude --resume`。与通知开关无关；重启 island 清空 inbox 所以"重启就好"。

修复：`AgentActivitySource.liveHosts`（Claude Code：session 文件里仍在运行的 pid）+ `AgentActivityScanner.liveHosts` + `AgentInbox.refreshHosts`（按 sessionKey 换 host，保留 id / 已读）；`AgentMonitor.refreshHosts` 每轮 poll 与点击前调用。新增 4 个测试。

验证：`make verify` 全过；端到端用 worktree 构建 + `ISLAND_AGENT_HOME` 假 session：行以 pid A 入库 → 杀 A、同 sessionId 换成 tmux `island:2` 里的 pid C → 日志 `refreshed task hosts` → 用户点击 → `tmux client /dev/ttys000 -> island:2.1` + cmux tab 聚焦，剪贴板为空。随 0.2.5 发布（PLAN § 开发指南）。

未覆盖：pi / Codex 不记录 pid（host 为 unknown 或 desktop），不受影响；同一 session 在两个终端同时运行时取任一个活着的 pid。
