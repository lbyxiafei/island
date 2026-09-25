---
type: feat
name: menubar-icon-design
title: "设计 menubar 图标并把设计资产放进 reference"
status: solved
created_ts: 2026-09-13T14:13:40-07:00
updated_ts: 2026-09-13T14:16:49-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Scope / VERSION — POC #3（「打开图标后可以有设置，设置目前就设置快捷键，以及退出选项」）。授权来源：用户在会话中明确指令「poc3、4 go」。

## 背景

PLAN #3：「帮我做一个 menubar 的图标，**图标你来定**，做好了放到 `reference` 里面」。

当前菜单栏显示的是系统 SF Symbol `capsule.portrait.fill` —— 可用但不表达 island 自己的语义，也没有任何设计资产可查阅。

## 期望结果

- 一个有明确设计意图的 island 图标，作为 menubar 模板图（单色，跟随深浅色与菜单栏高亮自动着色）
- 设计资产（矢量源文件 + PNG 预览 + 设计说明）放进 `reference/`，便于人查看与迭代
- app 运行时使用同一形状

## 备注

- AGENTS.md 约束：`reference/` 内容**不得被编译、打包或作为运行时依赖**。因此 `reference/` 只放设计资产与说明，运行时图标由代码用 `NSBezierPath` 画同一形状，避免构建流程与 reference 耦合，也避免两份位图漂移
- 图标需同时满足：16pt 左右的可读性（菜单栏实际尺寸）、纯单色、在浅色/深色菜单栏都清晰

## Decision

- 2026-09-13，binyanli 在会话中明确指令「poc3、4 go」，且已把该范围写进 `hai/PLAN.md` § Scope / VERSION — POC #3。本 issue 与该 PLAN 条目、以及配套 issue `hotkey-settings-in-menu` 一一对应，无需额外授权。
- 环境变量优先级、存储位置（`UserDefaults`）、图标风格由 Agent 决定（PLAN 原文「图标你来定」）。

## 实现

- 设计资产：`hai/reference/icon/`
  - `menubar-icon.svg` —— 矢量源（18×18）：一块圆角面板悬在一条细横线（屏幕顶边）之上
  - `menubar-icon.png` —— 128px 预览
  - `README.md` —— 设计意图、规格表、以及"为什么不用带缺口的胶囊"（16pt 下会糊）
- 运行时：`Sources/Island/IslandGlyph.swift` 用 `NSBezierPath` 按同一组坐标绘制，产出 `isTemplate = true` 的 `NSImage`，由 macOS 自动着色（浅色/深色/高亮）
- 遵守 AGENTS.md § Reference：`reference/` 只放设计资产，**运行时完全不读该目录**，避免构建流程与 reference 耦合

## 验证

- 菜单栏图标已从 SF Symbol `capsule.portrait.fill` 换成自绘 glyph，见运行日志 `menu bar item installed`
- 关于"两处真源"（SVG 与绘制代码必须同步修改）已写进 `CONTEXT.md § Gotchas`
