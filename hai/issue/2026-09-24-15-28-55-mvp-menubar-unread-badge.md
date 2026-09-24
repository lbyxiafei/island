---
type: feat
name: mvp-menubar-unread-badge
title: "MVP: menu bar 未读任务数角标"
status: solved
created_ts: 2026-09-24T15:28:55-07:00
updated_ts: 2026-09-24T15:34:10-07:00
---

Scope-check: PLAN § Scope / VERSION — MVP；PLAN § Design / Island 展示 UX（「island 需要在 menu bar 上展示一个数字，例如微信这种」）。授权来源：用户会话指令「我新增了version mvp，你去执行下」。

## 实现

- `Sources/Island/AgentMonitor.swift`：每 3 秒轮询一次 `AgentActivityScanner.standard()`，过滤掉 `completedAt < 启动时间` 的历史 run，喂给 `AgentInbox`；有新条目时回调
- `StatusItemController.setUnreadCount(_:)`：把未读数写在图标右侧（`imagePosition = .imageLeading`，等宽数字字体）
- `AppDelegate.startAgentMonitor()`：接线，并在每次变化时打日志 `agent tasks: N unread, M tracked`
- 增量语义放在这里（`Sources/Island`），`IslandCore` 不掺时间过滤，方便 `--scan-agents` 复用同一套解析

## 验证

真机端到端：app 前台运行期间，往 `~/.claude/sessions/` 注入一个 `status: idle`、`updatedAt = 当前毫秒` 的合成会话，日志随即出现

```
[island] agent tasks: 1 unread, 1 tracked
```

即「检测 → 入库 → 未读计数 → 状态栏」整条链路打通。注入的文件用完已删除。

未覆盖：角标样式的视觉验收（需要人眼看菜单栏），以及「点开菜单/悬浮窗后角标清零」——后者属于 `mvp-overlay-task-list`。
