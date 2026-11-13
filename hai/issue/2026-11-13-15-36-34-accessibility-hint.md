---
type: feat
name: accessibility-hint
title: "Menu hint when island lacks Accessibility for DeepSeek"
status: solved
created_ts: 2026-11-13T15:36:34-08:00
updated_ts: 2026-11-13T15:38:40-08:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

用户（2026-11-13）：没给辅助功能权限时，dsh 的提示不会自动消失、点击也跳不到 session，island 却没有任何提示，用户看不出原因。同意加一个菜单提示。

## 期望结果

缺辅助功能权限、装了 DeepSeek 且 DeepSeek 场景开着时，菜单栏菜单出现「Allow Accessibility to open DeepSeek sessions…」，点击把 Island 加进列表并打开 隐私与安全性 → 辅助功能；收件箱变化与切换 app 时重新判断，授权后自动消失。权限状态变化写日志（`accessibility: granted / not granted`）。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-11-13T15:38:12-08:00: new -> in-progress

Scope-check: 用户明确同意（「加」）。

## 2026-11-13T15:38:40-08:00: in-progress -> solved

新增 AccessibilityHint（2 个测试）与菜单项、权限变化日志。真机：debug 包被系统视为已授权，日志「accessibility: granted」、菜单无该项（符合预期）；「缺权限时显示」只有单测覆盖，本机无法在不撤销用户权限的前提下复现。make verify 全过、覆盖率 100%。
