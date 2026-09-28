# CONTEXT

面向**接手本 repo、没有任何 context 的新 Agent**。每一项都应当是可直接复制执行的命令。

## Overview

island —— 一个 macOS 常驻小工具：监视本机 AI AGENT 的运行活动，session/task 完成时在屏幕中央上方弹出悬浮窗。

当前处于 **MVP 阶段**（见 `hai/PLAN.md` § Scope / VERSION — MVP）：已经能检测本机 Claude Code / Claude 桌面版聊天 / pi / Codex 的**已完成 agent run**，并在菜单栏显示未读数；悬浮窗列表、回到宿主窗口等 UX 仍在做。POC 阶段已完成的悬浮窗、global hotkey、菜单栏、开机自启继续沿用。

实现形态：SwiftPM 工程 + AppKit。accessory app（无 Dock 图标），菜单栏有一个 status item 常驻；global hotkey 用 Carbon `RegisterEventHotKey`，悬浮窗是 `NSPanel`，开机自启用 `SMAppService.mainApp`。**零第三方依赖**。

Agent 检测的调研结论（各类 agent 的落盘格式、完成信号、宿主进程、回到任务的手段）在 `hai/reference/agents/README.md`；实现分两层：`IslandCore` 里是纯解析 + 状态（`AgentTask` / `AgentActivitySource` / `AgentInbox`），`Sources/Island/AgentMonitor.swift` 负责轮询并把未读数推到菜单栏。

快捷键行为（PLAN § Scope #5）：它 summon 悬浮窗；悬浮窗已经显示时再按一次会立刻收起（toggle），而不仅是重置自动隐藏计时。菜单里的 `Summon overlay` 始终是“显示”。

## Setup

```bash
# 前置：Xcode（本机验证版本 Xcode 26.6 / Swift 6.3.3 / macOS 26.6.2）
xcrun --find swift                 # 确认工具链可用
git clone https://github.com/lbyxiafei/island.git && cd island
make hooks                         # 装 pre-push 钩子（每次 push 前跑 make verify）

swift build                        # 编译
./scripts/build-app.sh             # 打成 build/Island.app（Developer ID 优先，否则 ad-hoc）；版本号 $ISLAND_VERSION，缺省 0.0.0
./scripts/build-app.sh --debug     # 同上，debug 构建
./scripts/release.sh 0.2.0         # 签名 + 公证 + staple，产出 build/dist/island-0.2.0.dmg
./scripts/publish.sh 0.2.0         # 发布到 brew：release.sh + tap 仓库 Release + Casks/island.rb + tag v0.2.0
./scripts/demo.sh                  # ISLAND_AGENT_HOME 指向临时目录里的假 session，逐个完成触发弹出，录演示用；--check 不开窗只打印检测结果

# 运行（开发机日常跑的是 brew 装的 /Applications/Island.app，见下方 Gotchas「开发流程」）
./build/Island.app/Contents/MacOS/Island    # 前台运行，配置与事件日志走 stderr
open build/Island.app                       # 后台运行（无日志输出）

# 退出：点菜单栏 island 图标 → Quit island，或者
pkill -x Island
```

菜单栏 island 图标（点开）提供：`Summon overlay (⌃⌘,)`、`Summon hotkey` on/off 勾选项、当前配置展示（快捷键 + 来源）、`Settings…`（录制快捷键 + `Enabled` + `Clear`）、`Launch at login` 勾选项、`Quit island`。图标右侧的**数字**是未读 agent 任务数（PLAN § Design 的微信式角标）。

启动日志里 `hotkey registered: ...`（关掉时是 `hotkey is switched off; ...`）与 `menu bar item installed; launch at login: <status>` 两行可以确认快捷键注册与菜单栏挂载。

**快捷键的取值优先级**：应用内设置（`Settings…`，存在 `UserDefaults`）> 环境变量 `ISLAND_HOTKEY` > 内置默认 `cmd+ctrl+,`。快捷键可以整体开关：关掉后不再向系统注册（键位还给其他 app），但配置保留，随时可再打开。开关状态也存在 `UserDefaults`（`IslandHotkeyEnabled`，缺省即开启）。

```bash
# 看/改/清用户设置（app 退出后生效；菜单栏里改则立即生效并写入同一处）
defaults read com.commallama.island IslandHotkeyText
defaults read com.commallama.island IslandHotkeyEnabled
defaults delete com.commallama.island IslandHotkeyText   # 回到环境变量或默认
defaults delete com.commallama.island IslandHotkeyEnabled   # 回到默认开启
```

配置全部走环境变量，无需重新构建：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ISLAND_HOTKEY` | `cmd+ctrl+,` | 召唤快捷键。见下方语法；被应用内设置覆盖 |
| `ISLAND_OVERLAY_SECONDS` | `5` | 自动弹出的停留秒数，正数；被应用内设置（`IslandPopupSeconds`）覆盖 |
| `ISLAND_TASK_LIMIT` | `10` | 悬浮窗展示的任务条数（PLAN § Design 里的 N），正数 |
| `ISLAND_AGENT_HOME` | `~` | agent 数据根目录（`AgentHome`）。macOS 上改 `HOME` 无效（`homeDirectoryForCurrentUser` 不读环境变量），所以单独开这个口子 |

```bash
./build/Island.app/Contents/MacOS/Island --print-config   # 只解析并打印配置后退出，不开窗
./build/Island.app/Contents/MacOS/Island --scan-agents    # 列出本机检测到的所有已完成 agent run（调试用）
./build/Island.app/Contents/MacOS/Island --live-sessions  # 每个 agent 当前仍“开着”的 session（下拉框据此移除已关闭的行）
./build/Island.app/Contents/MacOS/Island --in-view <pid> [cwd]   # 此刻该 pid 的 tab 是否在用户眼前（先把宿主 app 切到前台再跑）
./build/Island.app/Contents/MacOS/Island --help

# 登录项（开机自启）：必须用 .app 包内的可执行文件调用
./build/Island.app/Contents/MacOS/Island --login-item-status
./build/Island.app/Contents/MacOS/Island --login-item-enable
./build/Island.app/Contents/MacOS/Island --login-item-disable
```

快捷键语法：modifier 可写 `cmd`/`command`/`⌘`、`ctrl`/`control`/`⌃`、`opt`/`option`/`alt`/`⌥`、`shift`/`⇧`，用 `+` 连接；也接受 macOS 菜单里那种紧凑写法（`⌃⌘,`）。key 为 US 布局单字符或 `space`/`tab`/`return`/`escape`。**至少要有一个 modifier**（否则会全局吞掉那个键）。

值非法时不会崩也不会静默：跳过该值并在 stderr 打印 `warning`；若用户设置非法则退到环境变量，都非法才用默认。

## Test

**所有 gate 的唯一入口是 `make verify`**；`make verify-strict` 会把任何未配置的 gate 升级为失败，本 repo 当前 6 个 gate 全部已配置，strict 应当通过。

| gate | 命令（同时写在 `makefile.local`） | 状态 |
|---|---|---|
| build | `swift build` | 已配置 |
| fmt | `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` | 已配置 |
| lint | `./scripts/check-layering.sh` | 已配置 |
| test | `swift test` | 已配置 |
| coverage | `./scripts/coverage.sh` | 已配置 |
| cycles | `swift build`（SwiftPM 自身拒绝 cyclic target dependency） | 已配置 |

- 全量测试：`swift test`
- 单个测试：`swift test --filter HotkeySpecTests/testParsesModifiersAndKeyIntoDisplayString`
- 覆盖率：`./scripts/coverage.sh` 把**单行百分数**写进 `coverage.txt`；`make verify` 的 coverage gate 先刷新它，再与 `coverage-baseline.txt` 比对（当前基线 `100`，即 `IslandCore` 的 65 行全部被覆盖）
- 覆盖率排除项声明在 **`coverage.config`**（`llvm-cov -ignore-filename-regex`，一行一条正则），理由如下：
  1. `Tests/`、`\.derived/runner\.swift` —— 测试自身与 SwiftPM 自动生成的测试入口（AGENTS 排除类 1：自动生成的代码）
  2. `Sources/Island/*.swift`（逐文件列出，含 `StatusItemController.swift` / `LoginItemController.swift` / `IslandGlyph.swift` / `HotkeySettingsWindow.swift` / `AgentSettingsView.swift` / `HotkeyRecorderView.swift` / `AgentMonitor.swift` / `AgentReopenExecutor.swift` / `TerminalTabFocuser.swift` / `TaskVisibilityProbe.swift` / `ApplicationsMover.swift` / `Subprocess.swift` / `VSCodeExtensionInstaller.swift` / `ProcessSQLite.swift` / `ProcessInspector.swift` / `UpdateController.swift` / `UpdateSettingsView.swift` / `FeedbackSettingsView.swift`）—— 可执行 target 的全部内容，即 `main()` 与 AppKit / Carbon / ServiceManagement 的 wiring（AGENTS 排除类 2）。**该目录下新增文件必须显式加进 `coverage.config`**；任何决策逻辑都不该写在里面，应放 `IslandCore`
  - 没有类 3（纯数据结构）、类 4（平台分支）的排除项
- 增量覆盖率：本 repo 没有可用的 Swift delta-coverage 工具（`xcrun llvm-cov` 没有 diff 模式）。改动达到增量门槛时，用 `xcrun llvm-cov show` 人工核对改动行，并在 commit body 说明；`IslandCore` 的基线是 100%，任何新增未覆盖行都会在下次 `make verify` 里暴露

## Layout

```
Package.swift                  # 两个 target：IslandCore（库）、Island（可执行）
Sources/IslandCore/            # 纯逻辑，不 import 任何 UI 框架；被测试完整覆盖
  HotkeySpec.swift             #   hotkey 文案解析 + US 布局 keycode + 展示串
  HotkeyConfiguration.swift    #   环境变量取值，非法时回落并上报
  OverlayDuration.swift        #   悬浮窗停留时长，同上
  OverlayToggle.swift          #   按快捷键时“显示还是收起”的决策
  SettingsKey.swift            #   设置窗口按键路由：录制 / 取消录制 / ⌘W·Esc 关窗 / 放行
  LoginItem.swift              #   登录项状态 + 菜单勾选/提示的映射
  HotkeySettings.swift         #   换绑协调器（失败回滚）+ on/off 开关 + UserDefaults 存储
  AgentTask.swift              #   统一任务模型（agent / sessionID / title / cwd / completedAt / host / resume / scenario）+ TaskTitle 标题兑底
  AgentProfile.swift           #   每个 agent 的差异集中处：AgentProfile（名称 / 进程名 / 图标 / scenarios）+ AgentScenario 目录 + AgentScenarioSettings（开关）+ UserDefaults 存储
  AgentActivity.swift          #   Claude Code / pi 的落盘解析 + AgentActivityScanner（按 AgentScenarioSettings 过滤、跳过全关的 agent）；pi 的 session 扫描按 (mtime, size) 缓存在 PiScanCache
  ClaudeDesktopActivity.swift  #   Claude 桌面版：IndexedDB blob（react-query 缓存）-> 已完成的聊天
  Snappy.swift                 #   snappy 原始流解压 + ByteReader
  V8Value.swift                #   V8 structured clone 反序列化（只覆盖 island 用到的类型）
  CodexTurns.swift             #   Codex：turn 历史（sqlite，注入 runner）+ session_index 兑底
  AgentReopen.swift            #   点击任务后“回到它”的决策（ps 父链 + tmux pane → action）+ HostApp.nearest
  LegacySettings.swift         #   旧 bundle id（com.binyanli.island.poc）的设置迁移，只跑一次
  AutomationPermission.swift   #   osascript 结果分类（-1743 = 未授权）+ 被拒 app 列表 → 菜单提示
  TerminalFocus.swift          #   精确到 tab：tmux client 挑选、按宿主选定位手段（TerminalTabFocus）、AppleScript 文本、VS Code 请求/响应、扩展版本判断
  SessionPresence.swift        #   session 是否还开着：ProcessInspecting（注入的进程探测）+ SessionPresence（按 agent 的 live 集合，缺席即“无法判断”）+ AgentActivityScanner.presence
  AgentInbox.swift             #   增量入库 + 已读/未读 + 排序 + 条数上限（N）
  OverlaySelection.swift       #   悬浮窗查询过滤（TaskFilter）+ 键盘选中行 / ⌘N / ↩ 标注
  OverlayShortcut.swift        #   悬浮窗键盘模式的 ⌘, / ⌘1–9 判定（全角→半角归一，兼容 CJK 输入源）
  OverlayTheme.swift           #   主题预设 → 配色（OverlayPalette）+ UserDefaults 存储 + agent 图标选择
  TaskVisibility.swift         #   “用户是否正看着这个任务”：TaskVisibility.plan（前台 app / tmux 当前 pane）+ FocusedTab（只读 AppleScript 问当前 tab）
  PopupSettings.swift          #   完成时的弹出：开关 + 秒数 + UserDefaults 存储（缺省回落到 ISLAND_OVERLAY_SECONDS）
  AppUpdate.swift              #   版本号解析/比较、cask 里的 version、UpdateStatus（红点与文案）、UpgradeMethod（brew / 下载页）与脱离进程的升级命令、升级日志结果、自动检查开关
  Feedback.swift               #   FeedbackReport：正文 + 环境信息、mailto / GitHub new issue URL（严格百分号编码）、剪贴板文本
  AppLocation.swift            #   bundle 路径分类（translocated / dmg / installed）+ 移到 /Applications 的提示文案、xattr 与重启命令
Sources/Island/                # 可执行 target：NSApplication / NSPanel / Carbon 装配
  main.swift                   #   入口 + --help / --print-config / --scan-agents / --reopen-plan
  AppDelegate.swift            #   启动、注册 hotkey、显示与自动隐藏
  OverlayPanel.swift           #   不抢焦点的悬浮 NSPanel
  OverlayContent.swift         #   岛式悬浮窗：CapsuleShapeView（平顶圆底）+ 标题行（被动 `● N new` / 键盘模式整行搜索 + `N new` 胶囊）+ 行（键帽/agent 图标/未读点/短时间）+ 键盘处理 + 主题上色
  AgentReopenExecutor.swift    #   执行 reopen 计划：tmux select + switch-client / 找宿主 app / 写剪贴板
  TerminalTabFocuser.swift     #   执行 TerminalTabFocus：AppleScript（cmux/Ghostty/Terminal/iTerm2）、tty 标题探针、VS Code 文件握手
  TaskVisibilityProbe.swift    #   执行 TaskVisibility：ps / tmux / 只读 AppleScript / VS Code window-<pid>.json，得出“在眼前”的任务 id
  VSCodeExtensionInstaller.swift # 启动时把包内 island-vscode.vsix 装/升级进 VS Code（版本不同才装）
  Subprocess.swift             #   子进程 + osascript 的公共封装
  ProcessInspector.swift       #   ProcessInspecting 的实现：kill(pid, 0) 判活，ps + lsof 取进程 cwd
  ProcessSQLite.swift          #   /usr/bin/sqlite3 -json 包装（Codex turn 历史用）
  HotkeyRegistrar.swift        #   Carbon RegisterEventHotKey 包装
  StatusItemController.swift   #   菜单栏图标与菜单
  IslandGlyph.swift            #   菜单栏图标绘制（对应 reference/icon/menubar-icon.svg）
  HotkeySettingsWindow.swift   #   设置窗口（NSTabView）：General 快捷键 / Appearance / Notifications / Agents
  AgentSettingsView.swift      #   Settings → Agents：每个 agent 一个总开关（可 mixed）+ 每个场景一个开关，附检测方式与点击行为
  HotkeyRecorderView.swift     #   点击录制：NSEvent -> HotkeySpec
  LoginItemController.swift    #   SMAppService.mainApp 包装
  ApplicationsMover.swift      #   启动时从 dmg / 迁移路径运行则弹框：复制到 /Applications、去 quarantine、等本进程退出后重开
  AgentMonitor.swift           #   轮询 agent 落盘，把未读数推到菜单栏；每轮 pruneClosed 移除已关闭 session 的行
  ResolvedConfiguration.swift  #   环境变量 -> 配置对象
  UpdateController.swift       #   拉 tap 的 cask 判断新版本（启动 / 每 6 小时 / 打开 settings）+ 执行升级
  UpdateSettingsView.swift     #   Settings → Updates
  FeedbackSettingsView.swift   #   Settings → Feedback
Tests/IslandCoreTests/         # IslandCore 的行为测试（XCTest）
scripts/build-app.sh           # 打包 .app + 签名（Developer ID 优先，否则 ad-hoc）
scripts/release.sh             # 签名 + 公证 + dmg
scripts/demo.sh                # 假数据演示；替身进程是 ad-hoc 重签的 /bin/sleep 拷贝（不重签会被 SIGKILL），目录要 pwd -P（lsof 报 /private/tmp）
scripts/publish.sh             # dmg -> lbyxiafei/homebrew-tap（Release + cask）+ tag
scripts/Island.entitlements    # hardened runtime 下允许 Apple events（控制终端）
scripts/coverage.sh            # 刷新 coverage.txt
scripts/check-layering.sh      # 依赖方向检查
hai/reference/icon/            # 菜单栏图标的设计资产（SVG + 预览 + 说明），非运行时依赖
hai/reference/agents/          # MVP 调研：各 agent 的完成信号 / 任务身份 / 宿主 / 回到任务的手段
hai/reference/workflow/        # 开发与发布流程：issue → agent 实现 → 本地验收 → publish.sh → brew
vscode-extension/              # island 自带的 VS Code 扩展（纯 JS，零依赖）：按 pid 聚焦终端 tab；scripts/build-vscode-extension.sh 用系统 zip 打成 vsix，build-app.sh 放进 Resources
scripts/build-vscode-extension.sh # 打 vsix（不需要 vsce / npm）
coverage.config                # 覆盖率排除项
.swift-format                  # 格式化配置（4 空格缩进）
```

依赖方向：`Island` → `IslandCore`，`IslandCore` 不依赖任何 UI 框架。

```bash
# 循环依赖 / 依赖方向检查
swift build                  # SwiftPM 自身拒绝 cyclic target dependency
./scripts/check-layering.sh  # IslandCore 不得 import AppKit/SwiftUI/Carbon；Island 只允许 AppKit/Foundation/Carbon/ServiceManagement/IslandCore
```

## Conventions

- Swift 6 严格并发：`AppKit` / `NSPanel` 相关代码都在 `MainActor` 上；`IslandCore` 的类型一律 `Sendable`，方便从任何上下文使用
- 直接 touch AppKit 的代码一律放 `Sources/Island/`，并同步加进 `coverage.config` 的排除项
- 所有行为开关走环境变量（`ISLAND_*`），不引入配置文件——POC 阶段要的是"改一个数就能重验"
- **agent 检测分两层**：`IslandCore` 只做纯解析（`AgentActivitySource.completedTasks()` 吃 URL、只读文件，不碰 AppKit）；`Sources/Island/AgentMonitor.swift` 负责定时轮询。**每个 agent 的差异只放两处**：声明式的 `AgentProfile`（名称、`ps` 进程名、图标、`scenarios`）和检测用的 `AgentActivitySource`（给每个 task 打上 `scenario`）。不要再在别处 `switch AgentKind`。新增一个 agent = `AgentKind` 加 case + `profile` 里加一项（至少一个 `AgentScenario`）+ 一个 source 并在 `AgentActivityScanner.standard(home:)` 注册，UI（含 Settings → Agents）不用动；新增场景 = 加一个 `AgentScenario` 静态值、放进 profile、让 source 按落盘字段归类
- Swift 源码 4 空格缩进，格式由 `.swift-format` 定义；`swift-format` 随 Xcode 提供，不额外安装
- comment / docstring / log 一律英文（见 AGENTS.md § Comments）；菜单项等 UI 字符串同样用英文，保持代码内单一语言
- 新增 `Sources/Island/` 下的文件后，记得把路径加进 `coverage.config`，否则覆盖率基线（100）会掉

## Gotchas

- **hotkey 用 Carbon 而不是 `NSEvent.addGlobalMonitorForEvents`**。后者需要用户在「隐私与安全性 → 输入监控/辅助功能」里授权，Carbon 的 `RegisterEventHotKey` 不需要任何授权。这是 POC 要验证的结论之一，改动前先想清楚
- Carbon 的 keycode 是 **US 布局**的物理键位；真正的产品阶段要考虑非 US 布局下的键位映射（POC 不管）
- 悬浮窗靠 `NSPanel` + `.nonactivatingPanel` + `level = .statusBar` + `canJoinAllSpaces` 浮在最上层。**是否拿键盘由 `OverlayPanel.acceptsKeyboard` 决定**（`canBecomeKey` 读它）：热键 / 菜单 `Summon overlay` 召唤时为 true，面板 `makeKey` 但因为 non-activating 不会激活 island，底下的 app 仍是前台；任务完成自动弹出时为 false，绝不抢焦点。改这里务必保住"自动弹出不抢焦点"
- 按键 toggle 的依据是 `panel.isVisible`（由 `OverlayToggle.hotkeyPress` 决策）：显示中则 `orderOut` 并取消 `hideTask`，否则走 `showOverlay` 重新计时。自动隐藏后 `isVisible` 变回 false，所以下一次按键又是"显示"
- **悬浮窗里匹配 ⌘ 快捷键不要直接比 `charactersIgnoringModifiers`**：简体拼音等 CJK 输入源下 ⌘, 报的是全角 `"，"`（`characters` 反而是 `","`），直接 `== ","` 会静默失效。统一走 `OverlayShortcut.parse`，它先做全角→半角归一
- 进程是 accessory（`LSUIElement=true` 且 `setActivationPolicy(.accessory)`）：**没有 Dock 图标**，唯一的界面是菜单栏 status item。退出走菜单的 `Quit island`，前台运行也可以 Ctrl-C，或者 `pkill -x Island`
- 菜单栏 status item 是 2026-09-13 才加的。在那之前 app 完全不可见，导致"按快捷键没反应"时无法判断是没进程还是功能坏了（见 issue `menubar-status-item`）
- 开机自启用 `SMAppService.mainApp`（不是 LaunchAgent plist）。已实测 **ad-hoc 签名 + 非 `/Applications` 路径下可用**，但：
  - `unregister()` 只把 BTM 记录标成 `disabled`，不删除（`sfltool dumpbtm` 仍能看到）；`status` 会正确返回 `notRegistered`
  - 注册的 URL 是本 repo 的构建目录 `build/Island.app`；要长期稳定使用，把 app 拷到 `/Applications` 后重新注册，否则 bundle 被移动后状态可能变 `notFound`
  - 从未注册过的机器上首次查询返回 `notFound` 而非 `notRegistered`（macOS 行为），菜单里都按未勾选处理
- **快捷键换绑**：`HotkeySettingsCoordinator` 保证"app 不会变成没有可用快捷键"——解析失败什么都不动；macOS 拒绝新键（被别的 app 占用）时会把旧键重新注册回来并提示。改这一块务必保住这条不变量
- `HotkeySpec.displayString`（`⌃⌘,`，给人看）与 `HotkeySpec.specText`（`ctrl+cmd+,`，可持久化）是两个不同的东西。两者都能被 `parse` 接受，但落盘只写 `specText`
- 设置窗口是全 app 唯一会主动抢焦点的东西（`NSApp.activate(ignoringOtherApps:)`）。它由用户点菜单触发，属于预期行为；悬浮窗绝不能这样
- 设置窗口里录快捷键的是 `HotkeyRecorderView`：**录制是显式的**——打开设置时不聚焦它（`makeFirstResponder(nil)`），点击才进入录制（`acceptsFirstResponder` 只在录制中为 true），录到一个组合即结束，Esc / 点别处取消并恢复原值（issue `settings-recorder-steals-keys`：以前一打开就在录制，⌘W 被录成快捷键）。录制中它吞掉 `performKeyEquivalent`，否则 `⌘Q` 之类会被 window/菜单先一步拿走。按键怎么处理由 `SettingsKey.action`（IslandCore，有测试）决定；island 没有主菜单，所以 `SettingsWindow` 自己处理 ⌘W / Esc 关窗。自动化测试点击这个自定义 view 要用 CGEvent，System Events 的 `click at` 送不到。从 `NSEvent` 到 `HotkeySpec` 的映射在 `HotkeySpec.captured`（IslandCore，有测试）
- 快捷键 on/off 关闭时 `HotkeySettingsCoordinator.isEnabled == false`，不再注册全局键，但 `current` 与落盘配置都保留；重新打开会重新注册，被系统拒绝则保持关闭并在 UI 提示（不会假装成功）
- 菜单栏图标有**两处真源**：设计资产在 `hai/reference/icon/menubar-icon.svg`，运行时绘制在 `Sources/Island/IslandGlyph.swift`。改图标必须同时改（AGENTS.md 禁止 reference 被编译或作为运行时依赖，所以不能直接读那个 SVG）
- **agent 任务只算增量**：`AgentMonitor` 用启动时间卡一个 `completedAt >= startedAt` 过滤（在 `Sources/Island`，不在 IslandCore），所以历史 run 与重开 app 前的 run 一律不显示；`--scan-agents` 相反，故意列出全部已完成 run 供调试
- **三类 CLI agent 的完成信号**（详见 `hai/reference/agents/README.md`）：Claude Code = `~/.claude/sessions/<pid>.json` 列出活着的 session，**完成只看 transcript**（`~/.claude/projects/*/<sessionId>.jsonl`）：最后一轮以 `system/turn_duration` 收尾、之后没有新的 user 输入、该轮没有 `[Request interrupted by user…` 标记。**`status` 不作数**：新开 session 和按 esc 中断都会变 `idle`，而一轮结束时还有后台任务在跑（`run_in_background`、monitor）会一直停在 `busy`（issue `claude-busy-with-background-tasks`，以前因此漏检）；pi = 会话 jsonl 最后一条 assistant 的 `stopReason == stop`（esc 是 `aborted`）；Codex = `thread_history_1.sqlite` 的 `thread_turns.status == 'completed'`（两个库要 `attach`；**不能用 `sqlite3 -readonly`**，会 CANTOPEN）
- **悬浮窗一个 session 一行**：`AgentInbox.ingest` 按 `AgentTask.sessionKey`（`agent:sessionID`）去重，同一 session 的更新一轮替换旧行并重新标未读；`AgentTask.id`（含 completedAt）仍是行 id
- **Claude transcript 会长到几百 MB**（本机最大 852 MB），而且 busy 的 session 每几秒追加一次：`ClaudeTranscriptCache` **增量解析**，按文件记下已消费的字节 offset，之后只读追加的部分（`scanTranscript(_:continuing:)` 从上次的状态接着扫）；末尾没有换行的行只在它已经是完整 JSON 时才消费（否则可能写了一半）；文件变小视为被重写，从头再扫。scanner 必须长期持有（`AgentMonitor` 里就是），每次 new 一个就要全量重读
- **Codex 的 sqlite 访问走注入的 `SQLiteQuerying`**：IslandCore 只定义协议 + 解析，`Sources/Island/ProcessSQLite.swift` 才是 `/usr/bin/sqlite3` 包装。测试用 `NoSQLiteQuerying` / stub，所以核心层不会 spawn 进程
- **点击任务后的行为**（`AgentReopen.plan`，纯逻辑有测试）：命中 tmux pane 就 `focusTmux`；host 是 terminal 但不在 tmux 就 `focusHostApp`（沿祖先链找离它最近的常规 GUI app，`HostApp.nearest`，不靠终端白名单——cmux 等任意终端都能命中；tmux 场景同样用它从 tmux client 找到宿主终端，`hostingBundleIDs` 只在 tmux 没有 client 时兜底）；桌面 app 就 `activateApp`；host 仍无法确定时才 `copyToClipboard(resume)`。执行层 `AgentReopenExecutor` 在 Sources/Island。调试：`--reopen-plan <pid>` 或 `--reopen-plan <agent> <cwd>`（后者走无 pid 的宿主反查），**加 `--perform` 真的执行**（会抢焦点）
- **精确到 tab**（issue `reopen-precise-terminal-tab`，机制与实测细节见 `hai/reference/agents/README.md` § 5）：tmux 必须 `switch-client`，只 `select-window` 不会让 client 离开当前 session；叶子进程（agent 或 tmux client）的宿主 app 决定手段——cmux 读 `CMUX_SURFACE_ID` 走 AppleScript（**不走 cmux socket**，默认只许 cmux 内进程连）；Ghostty 往 tty 写 OSC 2 标题探针再按 name 找 terminal，找到后写回原标题；Terminal / iTerm2 按 tty（Terminal 要先 activate 再调窗口顺序）；VS Code 用自带扩展做**文件握手**（`~/Library/Application Support/island/vscode/focus-request.json` → `focus-response-<id>.json`），**不用 `vscode://` URI**，因为 VS Code 每次都弹确认框
- AppleScript 用 `/usr/bin/osascript` 子进程跑，首次控制某个终端 app 时 macOS 弹一次自动化授权（`Info.plist` 的 `NSAppleEventsUsageDescription`）。**osascript 会阻塞到用户回答为止，所以点击任务后的整条链（`AgentReopenExecutor`）跑在 `AppDelegate.reopenQueue` 串行后台队列上，不要再把它放回主线程**。用户拒绝时 osascript 报 `-1743`（`AppleScriptOutcome.notAuthorized`），菜单栏出现 `Allow island to control <app>…`（`AutomationDenials`），点击打开 系统设置 → 自动化；同一 app 之后授权成功会自动消失。重置授权做测试：`tccutil reset AppleEvents com.commallama.island`。**签名**：`build-app.sh` 优先用 `$ISLAND_SIGN_IDENTITY`，否则自动找钥匙串里的 `Developer ID Application`（hardened runtime + 时间戳 + `scripts/Island.entitlements`），都没有才 ad-hoc。**hardened runtime 下必须有 entitlement `com.apple.security.automation.apple-events`，否则 osascript 控制终端会被拒**。ad-hoc 每次重新构建 cdhash 都变，授权会反复弹；Developer ID 签名不会
- **发布**（issue `signed-notarized-release`）：`scripts/release.sh` = build-app（Developer ID）→ 公证 app 的 zip 并 staple → 打 dmg（app + Applications 快捷方式）→ 签名、公证、staple dmg → `spctl` 验证。公证凭据是钥匙串 profile `notary`（`ISLAND_NOTARY_PROFILE` 可改），账号与一次性配置记在 dotfiles 的 `macos-release` skill 与 `macos-signing` 脚本。2026-09-26 实测一次约 45 秒，两次提交都 Accepted
- **brew 分发**（issue `brew-distribution`）：源码仓库 `lbyxiafei/island` 当初是私有的（2026-09-27 已转 public，issue `open-source-release`；Feedback 的 GitHub issue 入口依赖它保持 public），dmg 一直放在**公开**的 `lbyxiafei/homebrew-tap` 的 Release `island-v<version>` 里，cask 是该仓库的 `Casks/island.rb`（由 `scripts/publish.sh` 生成，别手改）。用户装：`brew install --cask lbyxiafei/tap/island`。版本号只从 `publish.sh <version>` 进来，必须比上一版大（`brew upgrade` 靠它）；本地构建是 `0.0.0`。cask 的 `uninstall quit:` 会在卸载时退出正在运行的 island
- **bundle id 是 `com.commallama.island`**（2026-09-26 起；之前开发期是 `com.binyanli.island.poc`）。首次以新 id 启动时 `LegacySettings.migrate` 把旧域里的 4 个设置拷过来（只拷一次、不覆盖新值）。**对外发布后不要再改 bundle id**：授权、登录项、设置都绑在它上面。本机现在装的是 `/Applications/Island.app`（登录项指向它）；repo 里 `build/Island.app` 是同一个 bundle id，开发时先 `pkill -x Island` 再跑构建产物，别两个同时开。用户直接在 dmg 里双击会被 App Translocation 到随机只读路径，或者跑在 `/Volumes/` 下（issue `move-to-applications-prompt`）：启动时 `ApplicationsMover` 先于一切注册弹框，选 `Move to Applications` 就把 bundle 复制到 `/Applications/<同名>.app`（已有旧版先移到废纸篓）、`xattr -dr com.apple.quarantine`（否则非 Finder 拷贝的隔离 app 会再次被迁移）、spawn 一个 `sh` 等当前 pid 退出后 `open` 新副本，然后本实例退出；`Not Now` 照常运行，每次启动都会再问。判定 `AppLocation.classify` 只看路径（含 `/AppTranslocation/` 或以 `/Volumes/` 开头）。**本地测它别点 Move**：目标写死 `/Applications`，会替换掉本机正在用的那份
- VS Code 扩展：`vscode-extension/package.json` 的 `version` 是唯一版本号，`build-app.sh` 写进 `Info.plist` 的 `IslandVSCodeExtensionVersion`；**改了 extension.js 必须 bump version**，否则已安装用户不会升级（安装器只比版本）。扩展声明了 `extensionKind: ["ui"]`（Remote 窗口里也在本地跑，pid 才对得上）和 `untrustedWorkspaces.supported`（受限模式下照常激活）。全新安装会在已打开的 VS Code 窗口里直接激活；同版本覆盖安装不会重新加载。扩展是 JS wiring，不在 Swift 覆盖率统计内
- **任务标题的取值是 `title → 最后一条用户消息 → 目录名`**（`TaskTitle.resolve`，PLAN § Design / 下拉框 UX #1）。Claude：transcript 里的 `custom-title`（/rename）→ session json 里 `nameSource != "derived"` 的 `name` → `ai-title` → 最后一条用户 prompt（跳过 `isMeta`、sidechain、tool_result、`<command-…>` 包装、中断标记）。**`nameSource: "derived"` 的 `name`（如 `dotfiles-9e`）是 Claude 自动生成的占位名，不算标题**。pi：`session_info.name`（/name）→ 最后一条 user 文本。Codex：`threads.name` → 最后一条不以 `<` 开头的 `userMessage` → `threads.title`（首条用户消息）
- **点任务后悬浮窗会立刻收起**（PLAN § Design / 下拉框 UX #2）：`selectTask` 先 `markRead` + `refreshAgentUI`，再 `hideOverlay(reason:)`，最后才 focus/跳转（顺序重要，否则聚焦那一刻悬浮窗还会闪）
- **pi 没有 host pid 落盘**，`AgentReopenExecutor.resolveHost` 在点击时才反查：`ps -axo pid=,comm=` 筛命令名 `pi`，再 `lsof -a -p <pids> -d cwd -Fpn` 取 cwd，按 session 的 cwd 匹配。**`lsof -c pi` 不好使**——pi 是 node 脚本，lsof 看到的命令名是 node，必须先用 ps 拿到 pid 再 `lsof -p`
- **悬浮窗两种模式**（issue `dropdown-alfred-ux`）：键盘模式（召唤）下标题行整行是搜索框，↑↓ / ↩ / ⌘1–9 / esc 由 `OverlayContentView` 转给 `OverlaySelection`（IslandCore，有测试），`⌘,` 收起悬浮窗并打开 settings（`onOpenSettings`）；底部提示可在 settings 关掉（`Show keyboard hints`，`UserDefaults` key `IslandOverlayShowsHints`，缺省开，存取在 `UserDefaultsOverlayStore`）；没有自动隐藏计时，失焦（点别处）即收起（`OverlayPanel.onResignKey`）；被动模式（自动弹出）下标题行是 `● N new` / `All caught up`（`OverlayStatus`）+ 右侧快捷键键帽，**不显示 island 品牌字样**（用户明确认为无信息量），行用 `OverlayTaskRowView.mouseUp` 自己处理点击（不依赖窗口变 key），hover 时 `AppDelegate.setOverlayHovered` 取消自动隐藏，离开后重新计时。自动弹出不会把正在打字的键盘模式降级。`hideOverlay` 先清 `acceptsKeyboard` 再 `orderOut`，否则 `resignKey` 回调会重入。如果鼠标事件在非 key 窗口下有意外行为，菜单栏里同一份任务列表是保底入口（`StatusItemController.setTasks`）
- **Codex 桌面版与 CLI 共用 `state_5.sqlite` / `thread_history_1.sqlite`**，桌面线程只是 `threads.source` 不同（实测桌面端写的也是 `source='vscode'`）。**"Codex 桌面版"就是 `/Applications/ChatGPT.app`**（bundle id `com.openai.codex`）。2026-09-25 实测：一轮完成后约 1s 内写入 `thread_turns`（`status='completed'`）；中途停止写的是 `status='interrupted'`，被 SQL 的 `status = 'completed'` 过滤，不会误报。ChatGPT.app 里的普通聊天也是 Codex thread，同样被覆盖；点击走 `codex://threads/<id>`（app 注册的 `codex` scheme）打开对应对话
- **Claude 桌面版（聊天）读的是 claude.ai 前端的 IndexedDB 缓存**（`ClaudeDesktopActivitySource`，格式与判据见 `hai/reference/agents/README.md` § 4）：取 blob 目录下最新的文件，`Snappy` 解压，`V8Value` 反序列化，最后一条 assistant 消息 `stop_reason == end_turn` 才算完成。两个解码器都是本 repo 自写的（零依赖），格式没有公开文档，**桌面版升级后要先用 `--scan-agents` 看 `claude-desktop` 行是否还在**。只有当前或最近打开的对话才有 transcript。点击任务走 `AgentReopenAction.openURL`（`claude://claude.ai/chat/<uuid>`），打不开再激活 app
- **主题**：`Settings…` 里的 `Overlay theme` 选 System / Lagoon / Coral / Sand / Midnight，立即生效并弹出被动预览，存在 `UserDefaults` key `IslandOverlayTheme`（缺省 `system`：浅色 Sand、深色 Lagoon，由 `OverlayContentView.viewDidChangeEffectiveAppearance` 重新取色）。配色是 IslandCore 里的纯数据（`ThemeColor` 为 sRGB），AppKit 侧只做 `NSColor(ThemeColor)` 转换。**刻意不像 Alfred**（issue `island-capsule-look`，用户同时在用 Alfred）：不要再引入顶部大搜索框、整行实色高亮、右侧 ⌘N 或 Alfred 原版配色。旧的主题存值（`light` / `dark` / `modern-dark` / `frosty`）由 `OverlayTheme.resolve` 迁移到新主题
- 面板形状：`OverlayPanel.positionNearTopOfScreen` 让面板上沿贴着 `visibleFrame.maxY`（菜单栏下沿）；`CapsuleShapeView` 画平顶、底部 26pt 圆角的形状，描边不画上沿；毛玻璃用 `NSVisualEffectView.maskImage` 裁形（layer mask 裁不住 behind-window 的 vibrancy）
- 行图标：`AgentIcon.bundleIDs` 找已安装的 app 图标（Claude → `com.anthropic.claudefordesktop`，Codex → `com.openai.codex`，即 ChatGPT.app），找不到用 SF Symbol（pi 固定是 `terminal`）
- 应用内改快捷键立即生效并写 `UserDefaults`（key `IslandHotkeyText`）；开关状态写 `IslandHotkeyEnabled`（缺省开启）。直接用 `defaults write` 改则要重启 app 才生效
- 检查登录项是否真的注册了：`sfltool dumpbtm | grep -iA6 "Name: island"`（`Disposition: [enabled, ...]` 即已启用）
- `.app` 是 ad-hoc 签名（`codesign --sign -`）的，本地运行足够；重新构建后必须重新签名，`scripts/build-app.sh` 每次都会重签
- 先跑 `swift test`（不带 `--enable-code-coverage`）会让 `.build` 里的二进制失去插桩，之后直接调 `llvm-cov` 会报 `no coverage data found`。覆盖率只走 `scripts/coverage.sh`
- `swift test` 会连带构建可执行 target，所以 `Sources/Island` 里的编译错误会以测试失败的形式出现
- `swift-format` 默认 2 空格缩进，本 repo 在 `.swift-format` 里改成 4 空格；不加 `--configuration` 也能被发现，但换机器/换版本时留意
- **通知分两种**（issue `notification-n-auto-hide`）：菜单栏未读数永远跟着未读走，不可关；完成时的弹出可在 `Settings…` → `Notifications` 开关、改秒数（`UserDefaults` key `IslandPopupEnabled` / `IslandPopupSeconds`，缺省开 / `ISLAND_OVERLAY_SECONDS` / 5），hover 暂停计时。弹出关掉后，启动时那一次弹出也不再出现；改主题的预览照常弹
- **用户正看着的任务不通知**：`AgentMonitor` 每轮先 `AgentInbox.pending` 取出新 run，连同现有未读，一起交给 `TaskVisibilityProbe`（`AppDelegate.visibilityQueue`，与 reopen 队列分开）判断；`AgentInbox.update` 把“在眼前”的新 run 直接记为已读（不弹、不计数），并把用户自己切回去的未读项标已读。切换 app（`didActivateApplicationNotification`）会立刻补一轮。判据**宁可漏判不可误判**（误判=用户丢通知）：桌面 app 只能到 app 级（前台即算）；tmux 要求 pane 是其 session 的当前 pane、且有 client 挂在该 session、client 的宿主 app 在前台，再问宿主 tab；Terminal / iTerm2 比 tty；cmux 比 `CMUX_SURFACE_ID`；Ghostty 没有 id，只在“唯一一个 terminal”或“前台 terminal 是唯一一个 working directory == 任务 cwd 的”时才算；VS Code 靠扩展（0.2.0 起）写的 `~/Library/Application Support/island/vscode/window-<扩展宿主pid>.json`（`focused` + 当前终端 shell pid），pid 已死的文件忽略；装了新扩展的 VS Code 窗口要 reload 一次才会开始写
- 可见性判断**绝不弹授权框**：AppleScript 之前先用 `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)` 确认已授权，没授权就当“不在眼前”；也不做 Ghostty 的标题探针（会改用户看得到的标题）
- **Agent 场景开关**（issue `make-agent-optional`）：`Settings…` → `Agents` 按 `AgentProfile.all` 列出每个 agent 的 `AgentScenario`（id 形如 `claude-code.terminal`，**会落盘，不要改名**）。只存**被关掉的** id（`UserDefaults` key `IslandDisabledScenarios`，字符串数组），所以以后新加的场景默认开。关掉的场景：scanner 直接丢弃，整个 agent 全关时连 source 都不读（Codex 就不 spawn sqlite3）；已经在列表里的行由 `AgentInbox.removeAll(where:)` 立即清掉，但 `known` 保留，重新打开不会把旧 run 翻出来。`--scan-agents` 故意不过滤，每行打印场景 id，被关的标 `(off)`。归类依据：Claude Code 看 session json 的 `entrypoint`（本机只见过 `cli`；`*desktop*` / `*vscode*`·`*jetbrains*` / 其他分别归 Claude app / 编辑器 / SDK，**非 cli 的取值未实测**，没有该字段的旧文件算终端）；Codex 看 `threads.source`（`cli` / `exec` / 其余含 `vscode` 归桌面 app & IDE，index 兜底源也归 app）；pi、Claude 桌面版各只有一个场景
- 设置窗口是 `NSTabView`：`General`（快捷键）/ `Appearance`（主题、键盘提示）/ `Notifications`（弹出）/ `Agents` / `Updates` / `Feedback`。**`window 1` 可能是悬浮窗（无标题 NSPanel），System Events 要写 `window "island settings"`**；有新版本时 tab 名变成 `Updates 🔴`。自动化测试可以用 System Events：`click radio button "Agents" of tab group 1 of window 1`，Agents 页的开关是 `checkbox "<标题>" of scroll area 1 of tab group 1 of window 1`（agent 总开关 value 为 2 表示 mixed）
- **已关闭的 session 会从下拉框消失**（issue `remove-closed-agent-title`）：每轮 poll 先 `AgentMonitor.pruneClosed`，按 `AgentActivitySource.liveSessionIDs` 判断——Claude Code 看 `~/.claude/sessions/<pid>.json` 存在且 pid 活着（任一文件解不开就当“无法判断”，不误删）；Codex 看 `threads.archived = 0`（Codex 里删对话就是 archive）；pi 看是否仍有 `pi` 进程的 cwd 等于该项目最新 session 的 cwd；**Claude 桌面版无法判断**（聊天在服务端，本地缓存只有近期打开的），它的行永远保留。点击一行前也会先 prune 一次，已关闭的行直接消失、不再尝试聚焦。被移除的 run 仍在 `known` 里，只有同一 session 更新的一轮（如 `claude --resume`）才会重新出现
- **轮询路径上的大文件一律要缓存**：Claude Code 转录（`ClaudeTranscriptCache`，只读追加部分）、Claude 桌面版 blob（`ClaudeDesktopCacheReader`）、pi session（`PiScanCache`，按 mtime + size 判断变没变）。改文件属性要用 `FileManager.attributesOfItem`，不要用 `URL.resourceValues`，后者在同一个 URL 实例上会缓存旧值（issue `cache-pi-session-scans`：没缓存时 pi 每 3 秒全量解析约 6.7 MB，约 0.3s CPU）
- **应用内升级**（issue `upgrade-n-feedback`）：版本真源是公开 tap 的 `Casks/island.rb`（raw.githubusercontent，`UpdateSource.caskURL`），不是 GitHub API（无限流问题）。app 版本读 `CFBundleShortVersionString`，本地构建 `0.0.0` 视为开发版、永不提示。本地测提示用 `ISLAND_VERSION=0.0.9 ./scripts/build-app.sh`。有新版本时 Updates tab 名带 `🔴`（NSTabView 标签没法上色，emoji 是唯一不用自绘的办法）、菜单出现 `Update to x available…`。自动检查开关存 `IslandAutoCheckUpdates`（缺省开）。**升级只对 brew 装的有效**（`<prefix>/bin/brew` 与 `<prefix>/Caskroom/island` 都在）：spawn 脱离的 `sh` 后 island 立刻 `terminate`，shell 等 pid 退出再 `brew update && brew upgrade --cask lbyxiafei/tap/island`，输出与 `island-upgrade: exit N` 追加到 `~/Library/Logs/island-upgrade.log`，最后无论成败都 `open -b com.commallama.island`；下次打开 Updates tab 若日志最后一次非 0 会提示。先退出再升级，是为了让 cask 的 `uninstall quit:` 不去 quit 一个正在跑 brew 的父进程。不是 brew 装的就打开 tap 的 Release 页
- **反馈没有服务端**（issue `upgrade-n-feedback` § Decision）：`Send Email` 是 `mailto:`（用户自己的邮件客户端）、`Open GitHub Issue` 是预填的 `lbyxiafei/island/issues/new`、`Copy` 兜底。URL 编码只放行 RFC 3986 unreserved 字符——`URLComponents` 不转义 `+` / `&`，邮件客户端会把 `+` 当空格
- **开发流程**（PLAN § 开发指南，issue `dev-flow-brew-upgrade`，完整步骤见 `hai/reference/workflow/README.md`）：开发机只装 brew 那份。每次开发完成 = ship 到 master + `./scripts/publish.sh <下一个版本>`，开发者在 Settings → Updates 一键升级来验收，顺带验证 upgrade。只动 `hai/` 的提交不发版。agent 中途要跑构建产物，先 `pkill -x Island`，测完 `pkill -x Island; open /Applications/Island.app` 换回来

