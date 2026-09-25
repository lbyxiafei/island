---
type: feat
name: overlay-header-and-hints
title: "[ux] drop the island label, fix footer spacing, cmd+comma settings, hints toggle"
status: solved
created_ts: 2026-09-25T14:26:45-07:00
updated_ts: 2026-09-25T14:29:47-07:00
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

## 处理结果

- 标题行去掉 `island` 字样：被动模式 `● N new` / `All caught up`（`OverlayStatus`）+ 右侧快捷键键帽；键盘模式整行是搜索框（`Search N tasks`，15pt）+ 右侧强调色 `N new` 胶囊
- 底部提示放进 28pt 的独立区域并垂直居中，下方只留 4pt；关掉提示时底边回到正常 10pt
- 键盘模式 `⌘,`：收起悬浮窗并打开 settings；提示文案加了 `⌘, settings`
- settings 新增 `Show keyboard hints`（`IslandOverlayShowsHints`，缺省开），立即生效；`UserDefaultsThemeStore` 改名 `UserDefaultsOverlayStore` 统一存放悬浮窗偏好
- 真机验证：⌃⌘E 召唤 → ⌘, 打开设置（日志 `overlay hidden to open settings`），设置窗口里勾选项正常显示

# History

## 2026-09-25T14:26:45-07:00: new -> in-progress

## 2026-09-25T14:29:47-07:00: in-progress -> solved
