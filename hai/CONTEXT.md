# CONTEXT

面向**接手本 repo、没有任何 context 的新 Agent**。每一项都应当是可直接复制执行的命令。

## Overview

island —— 一个 macOS 常驻小工具：监视本机 AI AGENT 的运行活动，session/task 完成时在屏幕中央上方弹出悬浮窗。

当前处于 **MVP 阶段**（见 `hai/PLAN.md` § Scope / VERSION — MVP）：已经能检测本机 Claude Code / pi / Codex 的**已完成 agent run**，并在菜单栏显示未读数；悬浮窗列表、回到宿主窗口等 UX 仍在做。POC 阶段已完成的悬浮窗、global hotkey、菜单栏、开机自启继续沿用。

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
./scripts/build-app.sh             # 打成 build/Island.app 并 ad-hoc 签名（release）
./scripts/build-app.sh --debug     # 同上，debug 构建

# 运行
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
defaults read com.binyanli.island.poc IslandHotkeyText
defaults read com.binyanli.island.poc IslandHotkeyEnabled
defaults delete com.binyanli.island.poc IslandHotkeyText   # 回到环境变量或默认
defaults delete com.binyanli.island.poc IslandHotkeyEnabled   # 回到默认开启
```

配置全部走环境变量，无需重新构建：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ISLAND_HOTKEY` | `cmd+ctrl+,` | 召唤快捷键。见下方语法；被应用内设置覆盖 |
| `ISLAND_OVERLAY_SECONDS` | `5` | 悬浮窗停留秒数，正数 |
| `ISLAND_TASK_LIMIT` | `10` | 悬浮窗展示的任务条数（PLAN § Design 里的 N），正数 |

```bash
./build/Island.app/Contents/MacOS/Island --print-config   # 只解析并打印配置后退出，不开窗
./build/Island.app/Contents/MacOS/Island --scan-agents    # 列出本机检测到的所有已完成 agent run（调试用）
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
  2. `Sources/Island/*.swift`（逐文件列出，含 `StatusItemController.swift` / `LoginItemController.swift` / `IslandGlyph.swift` / `HotkeySettingsWindow.swift` / `HotkeyRecorderView.swift` / `AgentMonitor.swift`）—— 可执行 target 的全部内容，即 `main()` 与 AppKit / Carbon / ServiceManagement 的 wiring（AGENTS 排除类 2）。**该目录下新增文件必须显式加进 `coverage.config`**；任何决策逻辑都不该写在里面，应放 `IslandCore`
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
  LoginItem.swift              #   登录项状态 + 菜单勾选/提示的映射
  HotkeySettings.swift         #   换绑协调器（失败回滚）+ on/off 开关 + UserDefaults 存储
  AgentTask.swift              #   统一任务模型（agent / sessionID / title / cwd / completedAt / host / resume）
  AgentActivity.swift          #   三种 agent 的落盘解析 + AgentActivityScanner
  AgentInbox.swift             #   增量入库 + 已读/未读 + 排序 + 条数上限（N）
Sources/Island/                # 可执行 target：NSApplication / NSPanel / Carbon 装配
  main.swift                   #   入口 + --help / --print-config / --scan-agents
  AppDelegate.swift            #   启动、注册 hotkey、显示与自动隐藏
  OverlayPanel.swift           #   不抢焦点的悬浮 NSPanel
  OverlayContent.swift         #   面板内容（占位文案）
  HotkeyRegistrar.swift        #   Carbon RegisterEventHotKey 包装
  StatusItemController.swift   #   菜单栏图标与菜单
  IslandGlyph.swift            #   菜单栏图标绘制（对应 reference/icon/menubar-icon.svg）
  HotkeySettingsWindow.swift   #   设置窗口：录制快捷键 / 开关 / 清空
  HotkeyRecorderView.swift     #   点击录制：NSEvent -> HotkeySpec
  LoginItemController.swift    #   SMAppService.mainApp 包装
  AgentMonitor.swift           #   轮询 agent 落盘，把未读数推到菜单栏
  ResolvedConfiguration.swift  #   环境变量 -> 配置对象
Tests/IslandCoreTests/         # IslandCore 的行为测试（XCTest）
scripts/build-app.sh           # 打包 .app + ad-hoc 签名
scripts/coverage.sh            # 刷新 coverage.txt
scripts/check-layering.sh      # 依赖方向检查
hai/reference/icon/            # 菜单栏图标的设计资产（SVG + 预览 + 说明），非运行时依赖
hai/reference/agents/          # MVP 调研：各 agent 的完成信号 / 任务身份 / 宿主 / 回到任务的手段
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
- **agent 检测分两层**：`IslandCore` 只做纯解析（`AgentActivitySource.completedTasks()` 吃 URL、只读文件，不碰 AppKit）；`Sources/Island/AgentMonitor.swift` 负责定时轮询。新增一个 agent 只需加一个 `AgentActivitySource` 并在 `AgentActivityScanner.standard(home:)` 里注册，UI 不用动
- Swift 源码 4 空格缩进，格式由 `.swift-format` 定义；`swift-format` 随 Xcode 提供，不额外安装
- comment / docstring / log 一律英文（见 AGENTS.md § Comments）；菜单项等 UI 字符串同样用英文，保持代码内单一语言
- 新增 `Sources/Island/` 下的文件后，记得把路径加进 `coverage.config`，否则覆盖率基线（100）会掉

## Gotchas

- **hotkey 用 Carbon 而不是 `NSEvent.addGlobalMonitorForEvents`**。后者需要用户在「隐私与安全性 → 输入监控/辅助功能」里授权，Carbon 的 `RegisterEventHotKey` 不需要任何授权。这是 POC 要验证的结论之一，改动前先想清楚
- Carbon 的 keycode 是 **US 布局**的物理键位；真正的产品阶段要考虑非 US 布局下的键位映射（POC 不管）
- 悬浮窗靠 `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = false` + `level = .statusBar` + `canJoinAllSpaces` 实现"浮在最上层且绝不抢焦点"。这几个属性少一个行为就会退化（比如抢走终端焦点）
- 按键 toggle 的依据是 `panel.isVisible`（由 `OverlayToggle.hotkeyPress` 决策）：显示中则 `orderOut` 并取消 `hideTask`，否则走 `showOverlay` 重新计时。自动隐藏后 `isVisible` 变回 false，所以下一次按键又是"显示"
- 进程是 accessory（`LSUIElement=true` 且 `setActivationPolicy(.accessory)`）：**没有 Dock 图标**，唯一的界面是菜单栏 status item。退出走菜单的 `Quit island`，前台运行也可以 Ctrl-C，或者 `pkill -x Island`
- 菜单栏 status item 是 2026-09-13 才加的。在那之前 app 完全不可见，导致"按快捷键没反应"时无法判断是没进程还是功能坏了（见 issue `menubar-status-item`）
- 开机自启用 `SMAppService.mainApp`（不是 LaunchAgent plist）。已实测 **ad-hoc 签名 + 非 `/Applications` 路径下可用**，但：
  - `unregister()` 只把 BTM 记录标成 `disabled`，不删除（`sfltool dumpbtm` 仍能看到）；`status` 会正确返回 `notRegistered`
  - 注册的 URL 是本 repo 的构建目录 `build/Island.app`；要长期稳定使用，把 app 拷到 `/Applications` 后重新注册，否则 bundle 被移动后状态可能变 `notFound`
  - 从未注册过的机器上首次查询返回 `notFound` 而非 `notRegistered`（macOS 行为），菜单里都按未勾选处理
- **快捷键换绑**：`HotkeySettingsCoordinator` 保证"app 不会变成没有可用快捷键"——解析失败什么都不动；macOS 拒绝新键（被别的 app 占用）时会把旧键重新注册回来并提示。改这一块务必保住这条不变量
- `HotkeySpec.displayString`（`⌃⌘,`，给人看）与 `HotkeySpec.specText`（`ctrl+cmd+,`，可持久化）是两个不同的东西。两者都能被 `parse` 接受，但落盘只写 `specText`
- 设置窗口是全 app 唯一会主动抢焦点的东西（`NSApp.activate(ignoringOtherApps:)`）。它由用户点菜单触发，属于预期行为；悬浮窗绝不能这样
- 设置窗口里录快捷键的是 `HotkeyRecorderView`：它成为 first responder 后捕获 `keyDown`，并吞掉 `performKeyEquivalent`，否则 `⌘Q` 之类会被 window/菜单先一步拿走。从 `NSEvent` 到 `HotkeySpec` 的映射在 `HotkeySpec.captured`（IslandCore，有测试）
- 快捷键 on/off 关闭时 `HotkeySettingsCoordinator.isEnabled == false`，不再注册全局键，但 `current` 与落盘配置都保留；重新打开会重新注册，被系统拒绝则保持关闭并在 UI 提示（不会假装成功）
- 菜单栏图标有**两处真源**：设计资产在 `hai/reference/icon/menubar-icon.svg`，运行时绘制在 `Sources/Island/IslandGlyph.swift`。改图标必须同时改（AGENTS.md 禁止 reference 被编译或作为运行时依赖，所以不能直接读那个 SVG）
- **agent 任务只算增量**：`AgentMonitor` 用启动时间卡一个 `completedAt >= startedAt` 过滤（在 `Sources/Island`，不在 IslandCore），所以历史 run 与重开 app 前的 run 一律不显示；`--scan-agents` 相反，故意列出全部已完成 run 供调试
- **三类 CLI agent 的完成信号**（详见 `hai/reference/agents/README.md`）：Claude Code = `~/.claude/sessions/<pid>.json` 的 `status == idle`；pi = 会话 jsonl 最后一条 assistant 的 `stopReason == stop`；Codex = `~/.codex/session_index.jsonl` 的 `updated_at`。三者都按 `sessionId + completedAt` 去重，所以同一 session 的下一轮会产生新条目
- **Codex 桌面版的活动未必写进 `session_index.jsonl`**（实测 index 停在旧日期，而 `ChatGPT.app` 常驻）；Claude 桌面版没有可读的任务列表。这两块是 issue `mvp-desktop-agent-sources`
- 应用内改快捷键立即生效并写 `UserDefaults`（key `IslandHotkeyText`）；开关状态写 `IslandHotkeyEnabled`（缺省开启）。直接用 `defaults write` 改则要重启 app 才生效
- 检查登录项是否真的注册了：`sfltool dumpbtm | grep -iA6 "Name: island"`（`Disposition: [enabled, ...]` 即已启用）
- `.app` 是 ad-hoc 签名（`codesign --sign -`）的，本地运行足够；重新构建后必须重新签名，`scripts/build-app.sh` 每次都会重签
- 先跑 `swift test`（不带 `--enable-code-coverage`）会让 `.build` 里的二进制失去插桩，之后直接调 `llvm-cov` 会报 `no coverage data found`。覆盖率只走 `scripts/coverage.sh`
- `swift test` 会连带构建可执行 target，所以 `Sources/Island` 里的编译错误会以测试失败的形式出现
- `swift-format` 默认 2 空格缩进，本 repo 在 `.swift-format` 里改成 4 空格；不加 `--configuration` 也能被发现，但换机器/换版本时留意
