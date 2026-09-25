---
type: feat
name: reopen-precise-terminal-tab
title: "点击任务精确跳到 tmux session / cmux tab / VS Code 终端 tab"
status: solved
created_ts: 2026-09-25T15:43:43-07:00
updated_ts: 2026-09-25T16:07:45-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

`eeac75c` 之后，点击终端类任务（Claude Code / pi / Codex CLI）只能把**宿主 app** 拉到前台。用户希望像 Codex / Claude 桌面版那样直接落到那一个对话：tmux 的 session + window、cmux 的 workspace/tab、VS Code 的终端 tab、Terminal/iTerm 的 tab。桌面版已满足，不在本 issue 范围。

## 期望结果

点击任务后，屏幕上直接就是跑那个 agent 的 tab / pane，不用再手动找。

## 调研（2026-09-25，本机实测）

**1. tmux —— 现在有 bug，零成本可修**
- 现状 `focusTmux` 只做 `select-window` + `select-pane`：改的是目标 session 的"当前 window"，**client 并没有切过去**。实测 client `/dev/ttys000` 挂在 `job`，目标是 `island:1.1`，点完屏幕上仍是 `job`
- 修法：`tmux list-clients -F '#{client_tty} #{client_pid} #{client_session}'` 选一个 client（优先已经在目标 session 的，否则最近活跃的 `#{client_activity}`），`tmux switch-client -c <tty> -t <session>:<win>.<pane>`。不需要任何权限

**2. cmux —— 用 AppleScript，免配置（取代下面的 socket 方案）**
- cmux 带 AppleScript 字典（`cmux.sdef`）：`terminal` 的 `id` == `CMUX_SURFACE_ID`，`tab` 的 `id` == `CMUX_WORKSPACE_ID`。实测新开 tab 并选中后，`focus (first terminal whose id is "<surface>")` 能切回原 tab。**不走 socket，不需要改 cmux 设置**，只有首次 macOS 自动化授权弹窗
- 以下 socket 方案作废，仅留作记录：
- cmux 给每个终端注入 `CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID`（= `CMUX_PANEL_ID`）。同用户进程可用 `ps eww -o command= -p <pid>` 读到；tmux 场景读 **tmux client** 的 env（agent 自己继承的是 tmux server 的 env，不可靠）
- 跳转：`cmux select-workspace --workspace <id>` + `cmux focus-panel --panel <surface-id>`（socket 方法 `workspace.select` / `surface.focus`）
- 阻碍：socket 默认 `cmuxOnly`（`defaults read com.cmuxterm.app socketControlMode`），只允许 cmux 内启动的进程连接，island 实测 `Access denied`。解法二选一：cmux Settings 改成 password 模式并把密码交给 island（CLI 认 `--password` / `CMUX_SOCKET_PASSWORD`），或 `CMUX_SOCKET_MODE=allowAll`。**不要**借用终端 env 里的 `CMUX_SOCKET_CAPABILITY`（那是别人的凭据）
- CLI 路径：`/Applications/cmux.app/Contents/Resources/bin/cmux`（`CMUX_BUNDLED_CLI_PATH`）

**3. VS Code 终端 tab —— 需要一个自写的小扩展**
- VS Code 没有"按 pid 聚焦终端"的 CLI；agent 进程 env 里也没有终端 id（只有 `VSCODE_NONCE` 等）
- Claude Code 扩展的 `vscode://anthropic.claude-code/open?session=<id>` 会在**扩展的 webview 面板**里打开该 session，不是聚焦现有的 CLI 终端 tab，会出现同一 session 两个前端，不采用
- 方案：repo 内一个零依赖扩展（`registerUriHandler`），`vscode://<publisher>.island/focus?pids=<祖先链>` → 遍历 `vscode.window.terminals`，`await t.processId` 命中祖先链的那个 `t.show()`。多窗口时先 `open -b com.microsoft.VSCode <cwd>` 把对的窗口顶上来，再发 URI
- 需要把扩展装进用户的 VS Code（Ask first #1）

**4. Terminal.app / iTerm2 —— AppleScript 按 tty**
- `ps -o tty= -p <agent pid>` 拿 tty；Terminal：遍历 windows/tabs 找 `tty` 相同的 tab，`set selected tab` + `set index of window to 1`；iTerm2：`sessions` 的 `tty` 属性，`select`
- 首次会弹 Automation（TCC）授权。本机目前没在用，优先级低
- Ghostty 单独版：未调研

**5. Ghostty（独立版 1.3.1）—— AppleScript + tty 标题探针**
- 同样有 `Ghostty.sdef`：`terminal` 有 `id` / `name` / `working directory` 和 `focus` 命令（实测能跨 tab 切回，但不会把 app 提到前台，需另外 activate）
- 独立 Ghostty **不导出任何终端 id**（`GHOSTTY_SURFACE_ID` 只有 cmux 里有），终端也没有 `tty` 属性
- 解法：往 agent（或 tmux client）的 tty 写 OSC 2 `ESC ] 2 ; <探针> BEL` 临时改标题，AppleScript 找 `name` 等于探针的 terminal 取 `id` 后 `focus`，再把原标题写回。实测可行
- 读别的进程 env：`ps eww` 对系统签名二进制（`/bin/sleep`、登录 shell）读不到，对 claude / node / tmux 这类可以

## 建议顺序

1 tmux switch-client（纯修 bug）→ 2 cmux（等用户改 socket 模式）→ 3 VS Code 扩展 → 4 Terminal/iTerm

## Decision

- 2026-09-25，用户（binyan.li）在会话中授权：「放心大胆去做……安装过程就把这些东西一次性搞定，装好就符合预期」。范围：
  1. island 自带一个 VS Code 扩展（repo 内源码，零第三方依赖），island 启动时检测到 VS Code 就用 `code --install-extension` 自动装/升级到用户的 VS Code
  2. island 通过 AppleScript 控制 cmux / Ghostty / Terminal / iTerm2，并往 agent 所在 tty 写 OSC 标题探针
  3. tmux `switch-client` 切换用户当前 attach 的 client
- 用户要求：未来用户装好 island 即生效，不需要手动改设置或写脚本（macOS 自动化授权弹窗属于系统行为，无法绕过）

Scope-check: PLAN § Design / Agents 交互 interface 第 3 条（"尽量打开到指定窗口"）+ 用户明确指令

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T15:57:56-07:00: new -> in-progress

用户授权全部方案，开始实现（tmux switch-client / cmux / Ghostty / Terminal / iTerm2 / VS Code 扩展自动安装）

## 2026-09-25T16:07:45-07:00: in-progress -> solved

点击终端类任务现在直接落到具体 tab：tmux `switch-client` 切到目标 session/window/pane；宿主 app 为 cmux（`CMUX_SURFACE_ID` + AppleScript）、Ghostty（tty 标题探针 + AppleScript，事后写回原标题）、Terminal / iTerm2（AppleScript 按 tty）时切到对应 tab；VS Code 由 island 自带的扩展（`vscode-extension/`，启动时自动安装）通过文件握手切到对应终端 tab，并把对应窗口提到前面。全程不需要用户改设置或写脚本，只有首次控制某个终端 app 时有一次 macOS 自动化授权。验证：`make verify` 全过（新增 TerminalFocusTests，IslandCore 覆盖率 100）；`--reopen-plan <pid> --perform` 在本机实测 tmux 跨 session（job ↔ island）、cmux、VS Code 编辑器区终端 tab、Ghostty 跨 tab（含标题恢复）、Terminal.app 跨窗口全部命中。未覆盖：iTerm2 本机未安装，脚本未实测；Cursor 等 VS Code 衍生版未支持。
