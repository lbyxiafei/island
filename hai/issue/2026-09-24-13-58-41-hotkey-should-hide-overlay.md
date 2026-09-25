---
type: bug
name: hotkey-should-hide-overlay
title: "快捷键只能召唤悬浮窗，再次按下无法 toggle off"
status: solved
created_ts: 2026-09-24T13:58:41-07:00
updated_ts: 2026-09-24T14:00:00-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Scope / VERSION — POC #5 第一条「设置好的悬浮窗快捷键，可以 toggle on，也可以 toggle off」。授权来源：用户在会话中明确指令「version poc 5去实现下」及后续「还是没有 toggle off 的功能 / 继续」。不触发 Ask first。

## 背景

上一轮把 #5 的第一条理解成了「快捷键的启用 / 停用开关」（已实现，保留），但用户在真机验收时指出：**按快捷键只能召唤，悬浮窗显示期间再按一次不会收起**。这才是 PLAN 里 toggle on / toggle off 的原意 —— 快捷键 toggle 的是悬浮窗本身。

原先的行为：`HotkeyRegistrar` 的回调直接调 `showOverlay()`，显示中再按只是 `hideTask?.cancel()` 后重新计时 5 秒，永远等自动隐藏。

## 期望结果

- 按快捷键时：悬浮窗不在屏幕上 → 显示，并照常 5 秒后自动隐藏
- 悬浮窗已经在屏幕上 → 立刻收起（toggle off），不再等待自动隐藏
- 自动隐藏之后 `isVisible == false`，下一次按键又回到「显示」
- 菜单里的 `Summon overlay` 仍是明确的「显示」入口，不参与 toggle

## 实现

- 新增 `IslandCore/OverlayToggle.swift`：`hotkeyPress(isOverlayVisible:) -> .show / .hide`，把 toggle 规则放在可测层（覆盖率维持 100）
- `AppDelegate`：hotkey 回调由 `showOverlay()` 改为 `toggleOverlay()`；新增 `hideOverlay()`（取消 `hideTask` + `orderOut`），判断依据是 `panel.isVisible`

## 验证

- 单元测试：`OverlayToggleTests`（显示中→hide，未显示→show），共 52 个测试全绿，覆盖率维持 100
- 真机端到端：用 CGEvent 合成三次 `⌃⌘,` 按键，日志依次为
  ```
  overlay shown, hiding in 30.0s
  overlay hidden by hotkey
  overlay shown, hiding in 30.0s
  overlay hidden by hotkey
  ```
  即 show → hide → show → hide，toggle 生效
