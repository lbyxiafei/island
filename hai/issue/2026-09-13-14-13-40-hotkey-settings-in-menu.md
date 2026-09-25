---
type: feat
name: hotkey-settings-in-menu
title: "菜单栏无法设置快捷键（改快捷键只能靠环境变量重启）"
status: solved
created_ts: 2026-09-13T14:13:40-07:00
updated_ts: 2026-09-13T14:16:49-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Scope / VERSION — POC #3（「打开图标后可以有设置，设置目前就设置快捷键，以及退出选项」）。授权来源：用户在会话中明确指令「poc3、4 go」。

## 背景

快捷键目前只能通过环境变量 `ISLAND_HOTKEY` 在启动时指定，改一次要重启进程。PLAN #3 要求「打开图标后可以有设置，设置目前就设置快捷键」。退出选项已在 `menubar-status-item` 里做完。

## 期望结果

- 菜单栏点开后可以修改召唤快捷键，立即生效（不需要重启）
- 选择会被记住，重启后仍然是新快捷键
- 输入非法时给出明确反馈，**且不能把原来的快捷键弄丢**（改坏了必须还能用旧键）
- 生效优先级与来源要能看见：应用内设置 > 环境变量 `ISLAND_HOTKEY` > 内置默认 `cmd+ctrl+,`

## 备注

- 存储用 `UserDefaults`（bundle id 作为 suite），不引入第三方依赖
- 复用已有解析器 `HotkeySpec.parse`，不新写一套键位解析
- 换绑失败（新键被其它 app 占用）时必须回滚到旧键并提示，否则 app 会变成"快捷键全废"

## Decision

- 2026-09-13，binyanli 在会话中明确指令「poc3、4 go」，且已把该范围写进 `hai/PLAN.md` § Scope / VERSION — POC #3。本 issue 与该 PLAN 条目、以及配套 issue `menubar-icon-design` 一一对应，无需额外授权。
- 环境变量优先级、存储位置（`UserDefaults`）、图标风格由 Agent 决定（PLAN 原文「图标你来定」）。

## 实现

- 菜单栏新增 `Settings…`（⌘,），打开一个常规（可成为 key window）设置窗口：快捷键输入框、实时校验反馈、`Apply`、`Reset to default`
- 存储：`UserDefaultsHotkeyStore`（key `IslandHotkeyText`，bundle id 域），落盘写的是**规范化形式** `HotkeySpec.specText`（`ctrl+cmd+,`），保证重新解析得到同一个键
- 取值优先级：应用内设置 > 环境变量 `ISLAND_HOTKEY` > 内置默认，来源会在菜单里显示（`set in island` / `from ISLAND_HOTKEY` / `default`）
- 换绑安全：`HotkeySettingsCoordinator` 保证 app 不会陷入"没有可用快捷键"——解析失败不动任何状态；macOS 拒绝新键（被占用）时把旧键重新注册回来并提示
- 解析器顺手补强：现在同时接受 `cmd+ctrl+,` 与 macOS 菜单里的紧凑写法 `⌃⌘,`（后者是 `displayString` 的输出，用户很自然会照抄）

## 验证

新增 13 个测试（合计 36 个全绿），覆盖：优先级与来源、`specText`/`displayString` 往返、非法输入不触碰任何状态、换绑失败回滚旧键、重复设置同一个键不做无谓重注册、UserDefaults 存取。

真机（`.app` 内可执行文件）端到端验证：

```
$ .../Island --print-config
hotkey            ⌃⌘,  (default)

$ defaults write com.binyanli.island.poc IslandHotkeyText "cmd+shift+k"
$ .../Island --print-config
hotkey            ⇧⌘K  (set in island)

$ ISLAND_HOTKEY=cmd+opt+j .../Island --print-config
hotkey            ⇧⌘K  (set in island)          # 用户设置胜出

$ defaults delete com.binyanli.island.poc IslandHotkeyText
$ .../Island --print-config
hotkey            ⌃⌘,  (default)
```

覆盖率维持 `100`（新增逻辑全部落在 `IslandCore` 并被测试覆盖）。
