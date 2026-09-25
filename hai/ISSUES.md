# ISSUES

> 本文件由 `make issue-sync` 从 `./issue/*.md` 的 frontmatter 全量重建，请勿手工编辑。

| type | name | title | status | created_ts | updated_ts |
|---|---|---|---|---|---|
| feat | [claude-desktop-source](./issue/2026-09-25-14-38-22-claude-desktop-source.md) | Claude 桌面版（聊天）完成后不弹 island：尚无数据源 | new | 2026-09-25T14:38:22-07:00 | 2026-09-25T14:49:43-07:00 |
| chore | [brew-distribution](./issue/2026-09-13-14-20-51-brew-distribution.md) | 调研 brew install 分发路径（等本地 MVP 走通后再做） | new | 2026-09-13T14:20:51-07:00 | 2026-09-24T15:47:33-07:00 |
| bug | [settings-recorder-steals-keys](./issue/2026-09-25-14-37-03-settings-recorder-steals-keys.md) | 打开 settings 时焦点在快捷键录制框，cmd+w 被录成快捷键 | solved | 2026-09-25T14:37:03-07:00 | 2026-09-25T14:40:01-07:00 |
| feat | [overlay-header-and-hints](./issue/2026-09-25-14-26-45-overlay-header-and-hints.md) | [ux] drop the island label, fix footer spacing, cmd+comma settings, hints toggle | solved | 2026-09-25T14:26:45-07:00 | 2026-09-25T14:29:47-07:00 |
| feat | [island-capsule-look](./issue/2026-09-25-13-09-21-island-capsule-look.md) | [ux] overlay looks too much like alfred; switch to an island capsule look | solved | 2026-09-25T13:09:21-07:00 | 2026-09-25T13:13:45-07:00 |
| feat | [dropdown-alfred-ux](./issue/2026-09-25-12-39-11-dropdown-alfred-ux.md) | [ux] improve dropdown ux in alfred way | solved | 2026-09-25T12:39:11-07:00 | 2026-09-25T12:57:05-07:00 |
| bug | [dropdown-title-ux](./issue/2026-09-25-11-47-19-dropdown-title-ux.md) | [ux] title at island dropdown not meeting expectation | solved | 2026-09-25T11:47:19-07:00 | 2026-09-25T12:44:54-07:00 |
| feat | [dropdown-task-title-and-dismiss](./issue/2026-09-24-16-00-27-dropdown-task-title-and-dismiss.md) | 下拉框 task 标题兜底 last msg，点击后随即消失 | solved | 2026-09-24T16:00:27-07:00 | 2026-09-24T16:04:00-07:00 |
| bug | [pi-task-cannot-reopen](./issue/2026-09-24-15-53-00-pi-task-cannot-reopen.md) | 点击 pi 任务无法回到宿主（pi 无 tmux 且无 host pid） | solved | 2026-09-24T15:53:00-07:00 | 2026-09-24T15:57:00-07:00 |
| feat | [mvp-open-or-focus-task](./issue/2026-09-24-15-28-55-mvp-open-or-focus-task.md) | MVP: 点击任务回到宿主窗口 / 兜底贴 clipboard | solved | 2026-09-24T15:28:55-07:00 | 2026-09-24T15:48:00-07:00 |
| feat | [mvp-overlay-task-list](./issue/2026-09-24-15-28-55-mvp-overlay-task-list.md) | MVP: 悬浮窗展示任务列表 + 未读红点 | solved | 2026-09-24T15:28:55-07:00 | 2026-09-24T15:48:00-07:00 |
| chore | [mvp-desktop-agent-sources](./issue/2026-09-24-15-28-57-mvp-desktop-agent-sources.md) | MVP: 调研 Codex 桌面版与 Claude 桌面版的活动数据源 | solved | 2026-09-24T15:28:57-07:00 | 2026-09-24T15:48:00-07:00 |
| feat | [mvp-agent-detection-core](./issue/2026-09-24-15-28-55-mvp-agent-detection-core.md) | MVP: 统一 agent 任务检测内核（Claude Code / pi / Codex） | solved | 2026-09-24T15:28:55-07:00 | 2026-09-24T15:34:10-07:00 |
| feat | [mvp-menubar-unread-badge](./issue/2026-09-24-15-28-55-mvp-menubar-unread-badge.md) | MVP: menu bar 未读任务数角标 | solved | 2026-09-24T15:28:55-07:00 | 2026-09-24T15:34:10-07:00 |
| bug | [hotkey-should-hide-overlay](./issue/2026-09-24-13-58-41-hotkey-should-hide-overlay.md) | 快捷键只能召唤悬浮窗，再次按下无法 toggle off | solved | 2026-09-24T13:58:41-07:00 | 2026-09-24T14:00:00-07:00 |
| feat | [hotkey-toggle-and-recorder](./issue/2026-09-24-13-33-42-hotkey-toggle-and-recorder.md) | 快捷键需要可 on/off，配置需改为键盘组合捕获并支持清空 | solved | 2026-09-24T13:33:42-07:00 | 2026-09-24T13:36:36-07:00 |
| feat | [hotkey-settings-in-menu](./issue/2026-09-13-14-13-40-hotkey-settings-in-menu.md) | 菜单栏无法设置快捷键（改快捷键只能靠环境变量重启） | solved | 2026-09-13T14:13:40-07:00 | 2026-09-13T14:16:49-07:00 |
| feat | [menubar-icon-design](./issue/2026-09-13-14-13-40-menubar-icon-design.md) | 设计 menubar 图标并把设计资产放进 reference | solved | 2026-09-13T14:13:40-07:00 | 2026-09-13T14:16:49-07:00 |
| feat | [launch-at-login](./issue/2026-09-13-14-08-40-launch-at-login.md) | island 不会开机自启，重启后需要手动拉起 | solved | 2026-09-13T14:08:40-07:00 | 2026-09-13T14:12:27-07:00 |
| feat | [menubar-status-item](./issue/2026-09-13-14-00-51-menubar-status-item.md) | 无法感知 island 是否在运行，也没有退出入口 | solved | 2026-09-13T14:00:51-07:00 | 2026-09-13T14:12:26-07:00 |
| feat | [poc-hotkey-overlay](./issue/2026-09-13-13-34-39-poc-hotkey-overlay.md) | POC: global hotkey 调出的悬浮窗 | solved | 2026-09-13T13:34:39-07:00 | 2026-09-13T13:49:41-07:00 |
