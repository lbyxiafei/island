---
type: feat
name: dropdown-alfred-ux
title: "[ux] improve dropdown ux in alfred way"
status: solved
created_ts: 2026-09-25T12:39:11-07:00
updated_ts: 2026-09-25T12:57:05-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

我想对 island dropdown 进行一次大的升级：
![alt text](image-1.png)

参考 alfred 的ux：
![alt text](image-2.png)

![alt text](image-3.png)


![alt text](image-4.png)

![alt text](image-5.png)

![alt text](image-6.png)


## 期望结果

我希望在 settings 里也有这些风格的支持。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

## Decision

2026-09-25，用户（binyan.li）在会话中确认：

1. **键盘交互**：热键（及菜单 `Summon overlay`）召唤时悬浮窗成为 key window，可 ↑↓ 选择、Enter 打开、⌘1–9 直达、Esc 关闭、顶部输入框按标题/目录/agent 过滤；任务完成**自动弹出时仍然不抢焦点**，只能鼠标点击
2. **主题**：settings 里提供一组 Alfred 式预设：System（跟随系统）/ Light（紫色高亮）/ Dark（青色高亮）/ Modern Dark（圆角描边）/ Frosty（毛玻璃，原风格），选中立即生效并持久化
3. **行图标**：每行左侧显示 agent 的 app 图标，未读用图标角上的小红点

Scope-check: PLAN § Design / Island 下拉框 UX、Island 展示 UX；主题设置不在 PLAN 明文内，依据用户在 issue「期望结果」与会话中的明确指令

## 处理结果

- **外观**：悬浮窗改成 Alfred 布局——顶部大号查询框、每行左侧 agent app 图标（Claude / Codex(ChatGPT.app)，pi 用 `terminal` 符号）+ 图标角上的未读红点、标题 + `agent · 时间 · 目录` 副标题、选中行 `↩`、其余行 `⌘2…⌘9`，宽度 560
- **键盘模式**（热键 / 菜单 `Summon overlay`）：面板成为 key（non-activating，不激活 island），打字按标题 / 目录名 / agent 名多词过滤，`↑↓` 选择、`↩` 打开、`⌘1–9` 直达、`esc` 或点别处关闭，不再自动隐藏；鼠标 hover 同步高亮
- **被动模式**（任务完成自动弹出）：保持原行为——不抢焦点、鼠标点击、hover 暂停自动隐藏；查询框位置显示 `island — N unread`。自动弹出不会把正在使用的键盘模式降级
- **主题**：`Settings…` 新增 `Overlay theme`：System（跟随系统深浅色）/ Light（紫色高亮）/ Dark（青色高亮）/ Modern Dark（圆角 + 描边）/ Frosty（毛玻璃，原风格），立即生效并弹出预览，存于 `UserDefaults` `IslandOverlayTheme`
- 决策逻辑都在 IslandCore 并有测试：`TaskFilter` / `OverlaySelection`（过滤、选中、刷新保持选中、⌘N、↩ 标注）、`OverlayTheme`（取值回落、System 跟随、各预设特征）、`UserDefaultsThemeStore`、`AgentIcon`

已知限制：键盘模式下若当前输入法是中文，打字会先进拼音候选（Alfred 会在召唤时切到英文输入源，本次未做）。
