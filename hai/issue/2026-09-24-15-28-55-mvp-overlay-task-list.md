---
type: feat
name: mvp-overlay-task-list
title: "MVP: 悬浮窗展示任务列表 + 未读红点"
status: solved
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:48:00-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Scope / VERSION — MVP；PLAN § Design / Island 展示 UX。授权来源：用户会话指令「把未完成的 issues 都自主处理了」。

## 实现

- `OverlayContent.swift` 从占位文案改成真列表：`OverlayContentView`（标题 + 未读计数 + 行列表 + 底部提示）与 `OverlayTaskRowView`（红点 / 标题 / `agent · 相对时间 · 目录`）
- 行数 = `AgentInbox.visibleEntries`（未读优先，再按完成时间倒序），条数上限 `ISLAND_TASK_LIMIT`
- **点击**：行自己实现 `mouseUp` + `resetCursorRects`，不依赖窗口变成 key——`OverlayPanel` 仍是 `canBecomeKey = false`，POC 的「悬浮窗绝不抢焦点」约束没有被破坏
- **hover**：`OverlayContentView` / 行都装 `NSTrackingArea`；`AppDelegate.setOverlayHovered` 在 hover 时取消 `hideTask`，移出后重新计时
- **保底入口**：菜单栏菜单里挂着同一份任务列表（`StatusItemController.setTasks`），万一非 key 窗口的鼠标事件有意外，用户仍可点击
- 任务完成时 `AgentMonitor` 回调会 `refreshAgentUI()` + `showOverlay()`，满足 PLAN § Goal「完成任务后 pop up 悬浮窗」

## 验证

- 单元测试：列表顺序 / 未读优先 / 条数上限在 `AgentInboxTests`（新增前一个 issue 已覆盖）；116 个测试全绿，覆盖率 100
- 真机：注入合成 idle 会话后日志为 `agent tasks: 1 unread, 1 tracked` → `overlay shown`，即「新任务 → 更新内容 → 弹出悬浮窗」链路通
- 未做的验证：真实鼠标点击 / hover 只能人工体验（无法在无头环境模拟）。**请验收时实际点一下列表行和菜单项**。

## 备注

- 「hover 后扩展展示历史」的具体形态没有做（PLAN 原文的交互扩展），当前是固定高度列表 + 未读优先排序
