---
type: feat
name: island-capsule-look
title: "[ux] overlay looks too much like alfred; switch to an island capsule look"
status: in-progress
created_ts: 2026-09-25T13:09:21-07:00
updated_ts: 2026-09-25T13:09:29-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

`dropdown-alfred-ux` 之后悬浮窗和 Alfred 太像（顶部大搜索框、整行实色高亮、右侧 ⌘N、Alfred 原版配色与主题名），用户同时在用 Alfred，打开 island 会串台出戏。

## 期望结果

island 有自己的视觉身份，键盘操作、过滤、主题设置功能全部保留。

## Decision

2026-09-25，用户（binyan.li）在会话中选定「灵动岛胶囊」方向：

- 面板紧贴屏幕顶边（菜单栏下沿）垂下，深色、底部大圆角
- 没有大搜索框：标题行 `◉ island · N new`，键盘模式下右侧是内联的小搜索
- 选中行是半透明胶囊 + 描边，不是实色条；快捷键是行左侧的小数字键帽；右侧是短相对时间（now / 3m / 2h）
- 主题改名、换 island 自己的配色：System / Lagoon / Coral / Sand / Midnight；旧的已存主题值自动迁移

Scope-check: PLAN § Design / Island 下拉框 UX；依据用户会话中的明确指令

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T13:09:29-07:00: new -> in-progress
