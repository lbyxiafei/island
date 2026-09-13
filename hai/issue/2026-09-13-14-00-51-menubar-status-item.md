---
type: feat
name: menubar-status-item
title: "无法感知 island 是否在运行，也没有退出入口"
status: new
created_ts: 2026-09-13T14:00:51-07:00
updated_ts: 2026-09-13T14:00:51-07:00
---

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
