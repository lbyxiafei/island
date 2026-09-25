---
type: feat
name: island-capsule-look
title: "[ux] overlay looks too much like alfred; switch to an island capsule look"
status: solved
created_ts: 2026-09-25T13:09:21-07:00
updated_ts: 2026-09-25T13:13:45-07:00
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

## 处理结果

- 面板贴着菜单栏下沿垂下（平顶、底部 26pt 圆角，`CapsuleShapeView` + `maskImage`），宽 520
- 标题行 `● island · N new`（圆点用主题强调色）；键盘模式右侧是内联小搜索框（放大镜 + `filter`），被动模式右侧显示快捷键键帽；去掉了顶部大搜索框
- 行：左侧数字键帽 `1…9`（⌘N 直达）→ agent 图标（未读红点）→ 标题 / `目录 • agent` → 右侧短时间（`ShortAge`：now / 3m / 2h / 1d）；选中是强调色半透明胶囊 + 描边
- 底部操作提示只在键盘模式出现
- 主题：System（浅 Sand / 深 Lagoon）/ Lagoon / Coral / Sand / Midnight；旧存值 `light→sand`、`dark→midnight`、`modern-dark→midnight`、`frosty→lagoon`
- 测试变更：`testShortcutLabels`（↩ / ⌘N 标注）随该样式删除，换成 `testKeycapLabels`；Alfred 配色断言 `testPalettesMatchTheirReferenceLooks` 随旧主题删除，换成 `testPalettesHaveTheirOwnIdentity` 与迁移测试

# History

## 2026-09-25T13:09:29-07:00: new -> in-progress

## 2026-09-25T13:13:45-07:00: in-progress -> solved
