---
type: feat
name: overlay-header-and-hints
title: "[ux] drop the island label, fix footer spacing, cmd+comma settings, hints toggle"
status: in-progress
created_ts: 2026-09-25T14:26:45-07:00
updated_ts: 2026-09-25T14:26:45-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

用户反馈（截图见会话）：

1. 标题行的 `island` 字样没有信息量，希望去掉并想一个更好的 UX
2. 底部提示上下没有居中，下方留白太多
3. 键盘模式下希望 `⌘,` 直接打开 settings
4. 底部提示希望能在 settings 里开关

## 期望结果

- 标题行去掉品牌字样：键盘模式下整行就是搜索框（放大镜 + 输入），右侧是强调色的 `N new` 小胶囊；被动模式下是 `● N new`（或 `All caught up`）+ 右侧快捷键键帽
- 底部提示在自己的区域内垂直居中，下方留白收紧
- 键盘模式 `⌘,` 收起悬浮窗并打开 settings
- settings 新增 `Show keyboard hints` 勾选项（缺省开），持久化

Scope-check: PLAN § Design / Island 下拉框 UX；依据用户会话中的明确指令

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T14:26:45-07:00: new -> in-progress
