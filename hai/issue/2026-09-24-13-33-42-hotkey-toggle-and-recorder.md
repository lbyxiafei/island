---
type: feat
name: hotkey-toggle-and-recorder
title: "快捷键需要可 on/off，配置需改为键盘组合捕获并支持清空"
status: solved
created_ts: 2026-09-24T13:33:42-07:00
updated_ts: 2026-09-24T13:36:36-07:00
---

Scope-check: PLAN § Scope / VERSION — POC #5（「设置好的悬浮窗快捷键，可以 toggle on，也可以 toggle off」+「快捷键配置的时候，现在是 text 输入模式，改成监听键盘组合，并增加清空按钮」）。授权来源：用户在会话中明确指令「version poc 5去实现下」，且该范围已由人写进 `hai/PLAN.md` § Scope / VERSION — POC #5（commit `bba59d4`）。不触发 Ask first。

## 背景

当前快捷键（PLAN #5 之前的状态）：

- 只能通过 `Settings…` 的文本框手打 `cmd+ctrl+,` 这类字面量，用户得记住语法，容易打错
- 快捷键一旦设好就永远生效，没有"暂时关掉"的办法。用户切到别的 app（比如另一个也吃 ⌃⌘, 的软件）时只能改键或退出 island

## 期望结果

1. **toggle on/off**：已设置的快捷键可以启用/停用。停用后不再注册全局键（键位还给系统），但配置本身保留，随时可以再打开。
   - 入口：菜单栏勾选项；设置窗口里同一个状态也有对应控件（两边一致）
2. **键盘组合捕获**：设置窗口不再让人手打文本，而是"点一下、按组合键"直接录进去，实时显示组合（`⌃⌘,`）
   - 至少要有一个 modifier，否则拒绝并提示（裸键会全局吞键）
   - 捕获到的组合与现有 `HotkeySpec` 兼容，落盘仍是可解析的 `specText`
3. **清空按钮**：一键把当前录到的组合清掉；效果等同停用快捷键（让"想彻底不要快捷键"有个明确出口）

## 不变量

- 停用是用户显式意图，允许"没有可用快捷键"；但**只要处于启用状态**，`HotkeySettingsCoordinator` 原有的回滚不变量依然成立：换绑失败必须恢复旧键，非法输入不触碰任何状态
- 开启（toggle on）失败（键被别的 app 占用）时，保持停用状态并提示，不能假装成功

## 备注

- 决定逻辑继续放 `IslandCore`（可测、覆盖率要维持 100）；`NSEvent` 捕获等 AppKit 部分放 `Sources/Island/HotkeyRecorderView.swift`，并加进 `coverage.config`
- 启用状态存 `UserDefaults`（key `IslandHotkeyEnabled`，默认 true）
- 不新增第三方依赖

## 实现

IslandCore（有测试，覆盖率 100）：

- `HotkeySpec.captured(keyCode:modifiers:)`：从 `NSEvent` 的 `keyCode` + 修饰键集合构造 `HotkeySpec`。反向表由 `virtualKeyCodes` 派生，两者不会漂移；无 modifier 或未知键返回 nil
- `HotkeySettingsCoordinator` 新增 `isEnabled` / `start()` / `setEnabled(_:) -> HotkeyToggleOutcome`，以及 `initialEnabled(stored:)`（`nil` = 开启）；`apply` 在关闭状态下只记不注册
- `HotkeyStoring` 增加 `loadHotkeyEnabled()` / `saveHotkeyEnabled(_:)`，`UserDefaultsHotkeyStore` 用 `IslandHotkeyEnabled`

Sources/Island（AppKit 装配，已列入 `coverage.config`）：

- 新增 `HotkeyRecorderView`：点击成为 first responder 后捕获 `keyDown`，并吞掉 `performKeyEquivalent`（否则 `⌘Q` 等会被 window/菜单先取走）；非法组合 beep + 提示
- `HotkeySettingsWindow` 改成录制框 + `Enabled` 勾选框 + `Clear` / `Reset to default` / `Apply`；Clear = 清空并停用
- `StatusItemController` 新增 `Summon hotkey` 勾选项与 `setHotkeyEnabled(_:)`，tooltip/信息行随状态变化；关闭时不再显示快捷键来源
- `AppDelegate` 用 `settings.start()` 代替直接 `registrar.register`，菜单与设置窗口两个开关都汇到 `setHotkeyEnabled`，并以 coordinator 的实际状态回写 UI（拒绝开启时不会假装成功）
- `ResolvedConfiguration` 读取 `hotkeyEnabled`，`--print-config` 在关闭时输出 `(default, disabled)`

## 验证

自动化：`make verify` 全绿（build / fmt / lint / test / coverage / cycles / issue-check）。测试 50 个（新增 1 个 `captured` 系列 + 7 个开关/持久化，`HotkeySpecTests` 里还有一个遍历全部可绑键位的往返测试）；覆盖率维持 `100`（新增 `guard` 分支由“重复设置同一状态”测试覆盖）。

真机端到端（`.app` 内可执行文件）：

```
$ .../Island --print-config
hotkey            ⌃⌘,  (default)

$ defaults write com.binyanli.island.poc IslandHotkeyEnabled -bool false
$ .../Island --print-config
hotkey            ⌃⌘,  (default, disabled)

$ defaults write com.binyanli.island.poc IslandHotkeyText "cmd+shift+k"
$ defaults write com.binyanli.island.poc IslandHotkeyEnabled -bool true
$ .../Island --print-config
hotkey            ⇧⌘K  (set in island)
```

启动日志断言（已运行两次，分别为启用 / 停用）：`hotkey registered: ⌃⌘,` vs `hotkey is switched off; summon from the menu bar icon`。

未覆盖：设置窗口的鼠标点击与真实按键录制只能人工体验（无法在无头环境模拟输入），请验收时点开 `Settings…` 实际录一次。
