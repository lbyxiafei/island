---
type: feat
name: mvp-overlay-task-list
title: "MVP: 悬浮窗展示任务列表 + 未读红点"
status: new
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:34:10-07:00
---

Scope-check: PLAN § Scope / VERSION — MVP；PLAN § Design / Island 展示 UX。

## 背景

检测内核（`AgentTask` / `AgentInbox`）与菜单栏未读数已落地（见 `mvp-agent-detection-core`、`mvp-menubar-unread-badge`）。悬浮窗目前还是 `OverlayContent` 里的占位文案，没有把 inbox 渲染出来。

## 期望结果（照 PLAN § Design）

- 悬浮窗列出 `AgentInbox.visibleEntries`（未读优先，再按 last update ts 倒序），条数 = `ISLAND_TASK_LIMIT`（默认 10）
- 未点过的 task 左侧有红点；点击 task title 后红点消失，但 title 仍留在列表里
- hover 到浮窗后进入交互、扩展展示更多历史 —— 具体交互形态需要先确认（POC 的悬浮窗是「不抢焦点」的 `NSPanel`，要 click 任务就得重新想焦点策略）
- 角标随已读变化

## 备注

- 点击后的行为在 `mvp-open-or-focus-task`
- 悬浮窗「绝不抢焦点」是 POC 的硬约束（见 `hai/CONTEXT.md` Gotchas）；要做可点击列表，必须先确认是否允许可成为 key window，否则先用菜单栏承载列表
