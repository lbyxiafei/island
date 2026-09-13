---
type: feat
name: poc-hotkey-overlay
title: "POC: global hotkey 调出的悬浮窗"
status: solved
created_ts: 2026-09-13T13:34:39-07:00
updated_ts: 2026-09-13T13:49:41-07:00
---

Scope-check: PLAN § Scope / VERSION — POC。以下改动全部落在该节范围内（验证 macOS 做 app 的流程 + hotkey 悬浮窗），不涉及 agent 检测与交互。

## 背景

`PLAN.md` § Scope / VERSION — POC 要求验证两件事：

1. 在 macOS 上做 app 的流程有没有手续、账号、资格限制
2. 若可行，做一个用 global hotkey（暂定 `cmd+ctrl+,`）调出的悬浮窗，弹出后 5 秒自动消失

动工前 repo 是空 scaffold（无代码、无 issue）。

## 期望结果

- 全局快捷键能召唤一个屏幕中央上方的悬浮窗，5 秒后自隐，时长可配置
- 全程不需要 Apple Developer 账号，不需要系统权限授权

## 结论 — POC 问题 1：macOS 做 app 的流程

- 本机 `macOS 26.6.2` + `Xcode 26.6` / `Swift 6.3.3` 即可，无额外安装
- **零第三方依赖**：`Package.swift` 里没有任何 external dependency
- 打包一个 `.app` 就是「可执行文件 + `Info.plist` + `codesign --sign -`」，**不需要任何账号**。证据（`scripts/build-app.sh` 每次构建都会打印）：

  ```
  Identifier=com.binyanli.island.poc
  Format=app bundle with Mach-O thin (arm64)
  CodeDirectory v=20400 size=560 flags=0x2(adhoc)
  Signature=adhoc
  TeamIdentifier=not set
  valid on disk / satisfies its Designated Requirement
  ```

- 结论：**POC 阶段无门槛**。唯一需要付费开发者账号的是「对外分发」（公证 notarization、TestFlight、App Store），本机自用不涉及

## 结论 — POC 问题 2：hotkey + 悬浮窗

- 全局快捷键用 Carbon `RegisterEventHotKey` 注册成功，**没有任何权限弹窗**。对照方案 `NSEvent.addGlobalMonitorForEvents` 需要用户在「隐私与安全性 → 输入监控」里授权，故选 Carbon
- 悬浮窗用 `NSPanel`，关键属性：`.nonactivatingPanel`、`canBecomeKey = false`、`level = .statusBar`、`canJoinAllSpaces`、`LSUIElement`。既浮在最上层又不抢终端焦点
- 已用日志实测（`ISLAND_OVERLAY_SECONDS=2`）：`overlay shown, hiding in 2.0s` → `overlay hidden`，自动隐藏生效；进程继续常驻等待快捷键，且未出现 `failed to register`
- **人工验收通过（2026-09-13）**：本机实测按 `⌃⌘,` 召唤成功。捕获到的日志里共 8 次 `overlay shown`：1 次启动自动弹出 + 7 次按键触发，且每一次都按配置的 2 秒后 `overlay hidden`：

  ```
  [island] overlay shown, hiding in 2.0s   <- 启动自动弹出
  [island] overlay hidden
  [island] overlay shown, hiding in 2.0s   <- 以下 7 次均由按键触发
  [island] overlay hidden
  [island] overlay shown, hiding in 2.0s
  [island] overlay shown, hiding in 2.0s   <- 连按：新召唤取消上一次的隐藏计时
  [island] overlay hidden
  ```

  连续两次召唤时只出现一次 `overlay shown` 而没有配对的 `overlay hidden`，符合「重新召唤会取消上一个隐藏任务」的设计
- Agent 侧无法自行完成这一步：合成按键需要 `AXIsProcessTrusted() == true`（本机为 `false`），且会弹系统授权框，故留给人验收。若要自动化复验，需要先给终端/agent 进程授辅助功能权限

## 验证

`make verify`（6 个 gate 全部 `[run]`，无 `[skip]`）、`make verify-strict` 通过：

- `swift test`：17 passing
- coverage：`100`（`IslandCore` 65 行全部覆盖）；排除项见 `coverage.config` + `CONTEXT.md § Test`
- 增量覆盖率：无可用 Swift delta-coverage 工具

## 备注

- 配置走环境变量 `ISLAND_HOTKEY` / `ISLAND_OVERLAY_SECONDS`，非法值回落默认并在 stderr 报 warning
- 悬浮窗内容是占位文案（标题 + 快捷键 + 停留时长）
- hover 展开历史 session、点击跳转终端等交互属于后续版本，不在 POC 范围

## Decision

- 2026-09-13，binyanli 同意修改 `.gitignore`：新增 `.build/` 与 `build/` 两行（SwiftPM scratch 目录与打包出来的 app bundle）。依据：`.build/` 有 322MB / 2768 个文件，不排除会被 `git add -A` 一并提交。授权范围**仅限这两行**，不含 `.gitignore` 的其他改动。
