---
type: bug
name: settings-recorder-steals-keys
title: "打开 settings 时焦点在快捷键录制框，cmd+w 被录成快捷键"
status: in-progress
created_ts: 2026-09-25T14:37:03-07:00
updated_ts: 2026-09-25T14:37:03-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

打开 settings 时焦点自动落在快捷键录制框上，用户按 ⌘W 想关窗，结果 ⌘W 被当成新快捷键录进去。原因：`HotkeySettingsWindow.show()` 把 recorder 设为 first responder，而 recorder 一旦是 first responder 就吞掉所有按键（含 `performKeyEquivalent`）；另外 island 是 accessory app，没有主菜单，⌘W 本来就关不了窗口。

## 期望结果

- 打开 settings 时不进入录制；点击录制框才开始录制，录到一个组合后自动结束
- 录制中 Esc / 点别处取消录制并恢复原值
- 非录制状态下 ⌘W / Esc 关闭 settings 窗口

Scope-check: PLAN § Design / Settings；用户会话中报告的缺陷

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T14:37:03-07:00: new -> in-progress
