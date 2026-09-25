---
type: bug
name: pi-task-cannot-reopen
title: "点击 pi 任务无法回到宿主（pi 无 tmux 且无 host pid）"
status: solved
created_ts: 2026-09-24T15:53:00-07:00
updated_ts: 2026-09-24T15:57:00-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Design / Agents 交互 interface 第 3 条（「尽量打开到指定窗口」）。授权来源：用户会话中报障「我点击这个，没有帮我回到 pi（vscode？）」，属 MVP 范围内 bug。

## 现象

用户在悬浮窗点 pi 任务（标题 `version poc 5去实现下`，cwd `island`），没有任何「回到那个 pi」的效果。

## 根因（实测）

1. `PiActivitySource` 一直把 `host` 写成 `.unknown` —— pi 不落盘 pid，所以 `AgentReopen.plan` 只能走 `copyToClipboard("pi --session …")`，不会激活任何窗口。
2. pi 的实际进程链是：

```
30824 30405 pi                  <- 命令名是 pi，但它是 node 脚本
30405 30389 /bin/zsh
30389 30260 Code Helper          <- VS Code 扩展宿主
30260     1 Code                  <- /Applications/Visual Studio Code.app
```

即 **VS Code 集成终端，且不在 tmux 里**——即使有 pid，旧的 `plan` 也只会兑底 clipboard。
3. 取 pid 时踩到一个坑：`lsof -c pi` **匹配不到**（pi 是带 `#!/usr/bin/env node` 的脚本，lsof 看到的命令名是 `node`）。必须先 `ps -axo pid=,comm=` 过滤命令名 `pi` 拿到 pid，再 `lsof -a -p <pids> -d cwd -Fpn` 取 cwd。

## 修复

**IslandCore**

- `AgentProcess`：`pids(fromProcessList:names:)` 解析 `ps -axo pid=,comm=`；`parseLsof` 解析 `lsof -Fpn`（注意中间的 `f` 行、以及 cwd 出现在 pid 之前要丢弃）；`match(_:cwd:)` 按 cwd 匹配
- `AgentKind.processNames`：claude / pi / codex
- `AgentTask.withHost(_:)`
- `AgentReopenAction` 新增 `.focusHostApp(processID:cwd:)`；`plan` 对「terminal host 但不在 tmux」返回它（原来是直接 clipboard）

**Sources/Island**

- `AgentReopenExecutor.resolveHost`：任务 `host == .unknown` 时按上面 ps + lsof 反查，命中就 `withHost(.terminal(pid))`
- `focusHostApp`：沿祖先链匹配已知终端 bundle id（VS Code / Ghostty / Terminal / iTerm2 / Warp）；如果是 VS Code 就 `open -b com.microsoft.VSCode <cwd>`（**聚焦到对应文件夹的窗口**），其他终端 `activate()` 到 app 级
- 找不到 app 时兑底 `resumeCommand` 进 clipboard（不再静默失败）
- `--reopen-plan` 增加两个参数的形式：`--reopen-plan <agent> <cwd>`，专门验证无 pid 的反查

## 验证

真机（新构建 `.app`）：

```
$ Island --reopen-plan pi /Users/binyanli/Repos/island
[island] resolved pi host for "debug": pid 30824
focusHostApp(processID: 30824, cwd: Optional("/Users/binyanli/Repos/island"))

$ Island --reopen-plan 83859          # claude，仍走 tmux
focusTmux(windowTarget: "island:1", paneTarget: "island:1.1")

$ Island --reopen-plan pi /tmp/nowhere
copyToClipboard("pi --resume debug")   # 兜底仍有效
```

`NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode")` 返回 pid 30260，正好是 30824 的祖先，所以 `focusHostApp` 能命中。

单元测试：新增 `AgentProcessTests`（ps 过滤 / lsof 解析 / 噪声丢弃 / cwd 匹配）、`AgentKindProcessTests`、`withHost` 保真，共 122 个测试全绿，覆盖率维持 100。

未验证：真实的 `open -b com.microsoft.VSCode <cwd>` 聚焦效果（会抢焦点，不适合自动跑）。**请验收时点一下 pi 任务**，确认 VS Code 切到 island 那个窗口。
