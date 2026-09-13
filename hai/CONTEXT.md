# CONTEXT

面向**接手本 repo、没有任何 context 的新 Agent**。每一项都应当是可直接复制执行的命令。

## Overview

island —— 一个 macOS 常驻小工具：监视本机 AI AGENT 的运行活动，session/task 完成时在屏幕中央上方弹出悬浮窗。

当前处于 **POC 阶段**（见 `hai/PLAN.md` § Scope），只验证两件事：macOS 上做 app 的流程有没有门槛，以及 global hotkey 召唤悬浮窗是否可行。agent 检测与交互部分尚未开始。

实现形态：SwiftPM 工程 + AppKit。accessory app（无 Dock 图标），菜单栏有一个 status item 常驻；global hotkey 用 Carbon `RegisterEventHotKey`，悬浮窗是 `NSPanel`，开机自启用 `SMAppService.mainApp`。**零第三方依赖**。

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

菜单栏 island 图标（点开）提供：`Summon overlay (⌃⌘,)`、当前配置展示、`Launch at login` 勾选项、`Quit island`。

启动日志里 `menu bar item installed; launch at login: <status>` 这一行可以确认菜单栏挂载成功。

配置全部走环境变量，无需重新构建：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ISLAND_HOTKEY` | `cmd+ctrl+,` | 召唤快捷键。modifier 可写 `cmd`/`command`/`⌘`、`ctrl`/`control`/`⌃`、`opt`/`option`/`alt`/`⌥`、`shift`/`⇧`；key 为 US 布局单字符或 `space`/`tab`/`return`/`escape` |
| `ISLAND_OVERLAY_SECONDS` | `5` | 悬浮窗停留秒数，正数 |

```bash
./build/Island.app/Contents/MacOS/Island --print-config   # 只解析并打印配置后退出，不开窗
./build/Island.app/Contents/MacOS/Island --help

# 登录项（开机自启）：必须用 .app 包内的可执行文件调用
./build/Island.app/Contents/MacOS/Island --login-item-status
./build/Island.app/Contents/MacOS/Island --login-item-enable
./build/Island.app/Contents/MacOS/Island --login-item-disable
```

值非法时不会崩也不会静默：回落到默认值并在 stderr 打印 `warning`。

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
  2. `Sources/Island/*.swift`（逐文件列出，含 `StatusItemController.swift` / `LoginItemController.swift`）—— 可执行 target 的全部内容，即 `main()` 与 AppKit / Carbon / ServiceManagement 的 wiring（AGENTS 排除类 2）。**该目录下新增文件必须显式加进 `coverage.config`**；任何决策逻辑都不该写在里面，应放 `IslandCore`
  - 没有类 3（纯数据结构）、类 4（平台分支）的排除项
- 增量覆盖率：本 repo 没有可用的 Swift delta-coverage 工具（`xcrun llvm-cov` 没有 diff 模式）。改动达到增量门槛时，用 `xcrun llvm-cov show` 人工核对改动行，并在 commit body 说明；`IslandCore` 的基线是 100%，任何新增未覆盖行都会在下次 `make verify` 里暴露

## Layout

```
Package.swift                  # 两个 target：IslandCore（库）、Island（可执行）
Sources/IslandCore/            # 纯逻辑，不 import 任何 UI 框架；被测试完整覆盖
  HotkeySpec.swift             #   hotkey 文案解析 + US 布局 keycode + 展示串
  HotkeyConfiguration.swift    #   环境变量取值，非法时回落并上报
  OverlayDuration.swift        #   悬浮窗停留时长，同上
  LoginItem.swift              #   登录项状态 + 菜单勾选/提示的映射
Sources/Island/                # 可执行 target：NSApplication / NSPanel / Carbon 装配
  main.swift                   #   入口 + --help / --print-config
  AppDelegate.swift            #   启动、注册 hotkey、显示与自动隐藏
  OverlayPanel.swift           #   不抢焦点的悬浮 NSPanel
  OverlayContent.swift         #   面板内容（占位文案）
  HotkeyRegistrar.swift        #   Carbon RegisterEventHotKey 包装
  StatusItemController.swift   #   菜单栏图标与菜单
  LoginItemController.swift    #   SMAppService.mainApp 包装
  ResolvedConfiguration.swift  #   环境变量 -> 配置对象
Tests/IslandCoreTests/         # IslandCore 的行为测试（XCTest）
scripts/build-app.sh           # 打包 .app + ad-hoc 签名
scripts/coverage.sh            # 刷新 coverage.txt
scripts/check-layering.sh      # 依赖方向检查
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
- Swift 源码 4 空格缩进，格式由 `.swift-format` 定义；`swift-format` 随 Xcode 提供，不额外安装
- comment / docstring / log 一律英文（见 AGENTS.md § Comments）；菜单项等 UI 字符串同样用英文，保持代码内单一语言
- 新增 `Sources/Island/` 下的文件后，记得把路径加进 `coverage.config`，否则覆盖率基线（100）会掉

## Gotchas

- **hotkey 用 Carbon 而不是 `NSEvent.addGlobalMonitorForEvents`**。后者需要用户在「隐私与安全性 → 输入监控/辅助功能」里授权，Carbon 的 `RegisterEventHotKey` 不需要任何授权。这是 POC 要验证的结论之一，改动前先想清楚
- Carbon 的 keycode 是 **US 布局**的物理键位；真正的产品阶段要考虑非 US 布局下的键位映射（POC 不管）
- 悬浮窗靠 `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = false` + `level = .statusBar` + `canJoinAllSpaces` 实现"浮在最上层且绝不抢焦点"。这几个属性少一个行为就会退化（比如抢走终端焦点）
- 进程是 accessory（`LSUIElement=true` 且 `setActivationPolicy(.accessory)`）：**没有 Dock 图标**，唯一的界面是菜单栏 status item。退出走菜单的 `Quit island`，前台运行也可以 Ctrl-C，或者 `pkill -x Island`
- 菜单栏 status item 是 2026-09-13 才加的。在那之前 app 完全不可见，导致"按快捷键没反应"时无法判断是没进程还是功能坏了（见 issue `menubar-status-item`）
- 开机自启用 `SMAppService.mainApp`（不是 LaunchAgent plist）。已实测 **ad-hoc 签名 + 非 `/Applications` 路径下可用**，但：
  - `unregister()` 只把 BTM 记录标成 `disabled`，不删除（`sfltool dumpbtm` 仍能看到）；`status` 会正确返回 `notRegistered`
  - 注册的 URL 是本 repo 的构建目录 `build/Island.app`；要长期稳定使用，把 app 拷到 `/Applications` 后重新注册，否则 bundle 被移动后状态可能变 `notFound`
  - 从未注册过的机器上首次查询返回 `notFound` 而非 `notRegistered`（macOS 行为），菜单里都按未勾选处理
- 检查登录项是否真的注册了：`sfltool dumpbtm | grep -iA6 "Name: island"`（`Disposition: [enabled, ...]` 即已启用）
- `.app` 是 ad-hoc 签名（`codesign --sign -`）的，本地运行足够；重新构建后必须重新签名，`scripts/build-app.sh` 每次都会重签
- 先跑 `swift test`（不带 `--enable-code-coverage`）会让 `.build` 里的二进制失去插桩，之后直接调 `llvm-cov` 会报 `no coverage data found`。覆盖率只走 `scripts/coverage.sh`
- `swift test` 会连带构建可执行 target，所以 `Sources/Island` 里的编译错误会以测试失败的形式出现
- `swift-format` 默认 2 空格缩进，本 repo 在 `.swift-format` 里改成 4 空格；不加 `--configuration` 也能被发现，但换机器/换版本时留意
