---
type: feat
name: menubar-status-item
title: "无法感知 island 是否在运行，也没有退出入口"
status: solved
created_ts: 2026-09-13T14:00:51-07:00
updated_ts: 2026-09-13T14:12:26-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

当前 app 是 accessory（`LSUIElement=true` + `setActivationPolicy(.accessory)`）：没有 Dock 图标、没有菜单栏、没有 status item。好处是绝不打扰用户，代价是**用户无法判断进程是否在运行**。

2026-09-13 人工验收 POC 时实际踩到：实例被结束后，用户按 `⌃⌘,` 没有反应，且没有任何视觉线索能说明"是 app 没跑"而不是"功能坏了"。当前只能靠命令行确认：

```bash
pgrep -fl Island    # 看活着没有
pkill -x Island     # 退出
```

## 期望结果

- 菜单栏有一个 island status item，常驻显示"我在运行"
- 点开至少有：当前配置（hotkey / 停留秒数）、退出
- 不破坏"不抢焦点、不打扰"的核心属性（悬浮窗行为不变）

## 备注

- **超出当前 PLAN scope**：`PLAN.md` 的 `Scope` 目前只写了 POC 两件事，本 issue 属于 POC 之后的产品化需求，需要人确认后再推进（status 停在 `new`）
- 备选方案（待讨论，不预设结论）：
  1. 菜单栏 status item（最直观，但会在菜单栏占位）
  2. 只在启动时用系统通知提示一次 + 保持无图标
  3. Dock 图标（`NSApplicationActivationPolicy.regular`），但会出现在 ⌘Tab 与 Dock 里，打扰度最高
- 若采纳方案 1，退出入口顺带解决，无需再为"怎么退出"单独设计

## Decision

- 2026-09-13，binyanli 在会话中明确指令「poc3、4 go」：授权实施本 issue 与配套的 ``launch-at-login`（开机自启）` 两项。这两项超出 `PLAN.md` § Scope（当前仅 POC）的范围，按 AGENTS.md「用户在会话中的明确指令 > PLAN 的 scope」执行。
- 授权范围**仅限这两项功能**；`PLAN.md` 的 scope / design 仍由人回写，Agent 不改。

## 实现

- `Sources/Island/StatusItemController.swift`：`NSStatusItem`，图标 SF Symbol `capsule.portrait.fill`（template image，自动跟随深浅色），鼠标悬停显示当前快捷键
- 菜单结构：
  - `Summon overlay (⌃⌘,)` —— 手动召唤，快捷键不再是唯一入口
  - `hides itself after 5s`（禁用项，展示当前配置）
  - `Launch at login`（勾选项 → 见 `launch-at-login`）
  - 状态需要解释时追加一行提示（例如"去系统设置里允许"）
  - `Quit island ⌘Q` —— 退出入口，不再需要 `pkill`
- 唯一带决策的逻辑（登录项状态 → 是否勾选 / 是否需要提示）落在 `IslandCore/LoginItemMenuPresentation`，由 3 个测试覆盖；`StatusItemController` 本身是 AppKit wiring，计入 `coverage.config` 排除项

## 验证

- 启动日志：`[island] menu bar item installed; launch at login: enabled`
- 运行实例 PID `22716`，菜单栏图标与菜单如上
