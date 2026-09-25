---
type: bug
name: reopen-stranger-hardening
title: "点击跳转对陌生环境的加固：VS Code 受限模式/远程、主线程阻塞、自动化授权被拒无提示"
status: solved
created_ts: 2026-09-25T16:24:20-07:00
updated_ts: 2026-09-25T16:27:26-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

`reopen-precise-terminal-tab` 只在作者本机验证过。评估"陌生用户能否开箱即用"时发现三处会在别的环境出问题（2026-09-25 用户要求先修）：

1. VS Code 扩展没声明 `capabilities.untrustedWorkspaces`，在受限模式（未信任的文件夹）下不会激活，只能退回窗口级；也没声明 `extensionKind`，Remote-SSH / 容器窗口里会被放到远端跑，pid 对不上
2. 点击任务后的 `ps` / `tmux` / `osascript` / VS Code 握手全在主线程；首次触发 macOS 自动化授权弹窗时，osascript 会一直等用户回答，期间 island 整个无响应
3. 用户在授权弹窗点了 "Don't Allow" 之后，island 只会默默退回"激活 app"，用户不知道为什么切不到 tab，也不知道去哪里改

## 期望结果

1. 扩展声明 `untrustedWorkspaces.supported: true`、`virtualWorkspaces: true`、`extensionKind: ["ui"]`，版本 bump 到 0.1.1，已装用户由 `VSCodeExtensionInstaller` 自动升级
2. `AgentReopenExecutor` 不再是 `@MainActor`，`selectTask` 把 plan + perform 丢到串行后台队列
3. 识别 osascript 的 `-1743` / `-1744`，菜单栏出现 `⚠ Allow island to control <app>…`，点击打开 系统设置 → 隐私与安全性 → 自动化；之后同一 app 授权成功则自动消失

Scope-check: 属于 `reopen-precise-terminal-tab` 的收尾加固，用户会话明确指令

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T16:27:26-07:00: new -> in-progress

开始实现三项加固

## 2026-09-25T16:27:26-07:00: in-progress -> solved

三项都已完成：扩展 0.1.1 声明受限模式、虚拟工作区、`extensionKind: ui`；点击后的整条链放到串行后台队列 `island.reopen`；osascript 的 -1743/-1744 进入 `AutomationDenials`，菜单栏出现提示项，点击打开 系统设置 → 自动化，同一 app 授权成功后提示自动消失。验证：`make verify` 全过（248 个测试，IslandCore 覆盖率 100，新增 AppleScriptOutcomeTests / AutomationDenialsTests）；实机回归 tmux+cmux、VS Code 编辑器区终端 tab 仍然命中。未实测：真实的"拒绝授权 → 菜单提示"链路（需要人在弹窗里点 Don't Allow）；受限模式和 Remote 窗口下的扩展行为只是按 VS Code 文档声明，没有逐一跑过。
