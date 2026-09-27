---
type: bug
name: cmd-comma-under-pinyin
title: "拼音输入法下悬浮窗内 ⌘, 打不开设置"
status: solved
created_ts: 2026-09-27T14:56:40-07:00
updated_ts: 2026-09-27T14:59:42-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

键盘模式的悬浮窗（热键召唤）里按 ⌘, 应该打开设置（69f327b 引入）。用户输入法为简体拼音（`com.apple.inputmethod.SCIM.ITABC`）时按下没有任何反应；切到 ABC/US 布局则正常。

加临时日志实测，拼音下 ⌘, 的 NSEvent 为：`keyCode=43 characters="," charactersIgnoringModifiers="，"`（全角逗号）。`OverlayContentView.performKeyEquivalent` 比较的是 `charactersIgnoringModifiers == ","`，于是永远不命中。⌘1–9 在拼音下是半角数字，未受影响，但中文全角模式下同样可能拿到全角数字。

## 期望结果

任何输入源下，键盘模式悬浮窗里 ⌘, 都能打开设置，⌘1–9 都能打开对应行。

## 方案

把 ⌘ 快捷键判定抽成 `IslandCore/OverlayShortcut.swift`（纯函数，可单测）：先对 `charactersIgnoringModifiers` 做 `fullwidthToHalfwidth` 归一，再匹配 `,` / `1…9`。`OverlayContentView` 只负责调用与派发。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-27T14:58:48-07:00: new -> in-progress

Scope-check: PLAN § Design / Settings（悬浮窗快捷键打开设置属已有功能的 bug 修复）。用户明确要求修好。

## 2026-09-27T14:59:42-07:00: in-progress -> solved

根因：拼音等 CJK 输入源下 ⌘, 的 charactersIgnoringModifiers 是全角「，」，旧代码直接比较 , 不命中。新增 IslandCore/OverlayShortcut（全角→半角归一后匹配 , 与 1–9），OverlayContentView 改为调用它；7 条单测覆盖半角/全角逗号与数字、非法键、非 ⌘ 修饰。验证：拼音输入法下真机召唤悬浮窗按 ⌘, 成功打开 island settings；make verify 全过（覆盖率 100%）。
