# island

监视本机 AI Agent 的运行活动，在 session / task 完成时于屏幕中央上方弹出一个悬浮窗。

> **当前处于 POC 阶段**：只验证「macOS 上做 app 有没有账号/资格门槛」和「global hotkey 召唤悬浮窗是否可行」两件事。Agent 活动的检测与交互尚未实现，详见 `hai/PLAN.md`。

## POC 能做什么

- 按 `⌃⌘,` 全局召唤屏幕顶部中央的悬浮窗，**不需要任何系统权限授权**（不弹输入监控 / 辅助功能对话框）
- 悬浮窗 5 秒后自动消失，时长可配置
- 悬浮窗不抢焦点，也不会出现在窗口切换器里；app 本身没有 Dock 图标、没有菜单栏
- 构建与运行只需要本机 Xcode，**不需要 Apple Developer 账号**（ad-hoc 签名）

## 快速开始

要求 macOS 13+ 与 Xcode（本机在 macOS 26.6.2 / Xcode 26.6 / Swift 6.3.3 上验证过）。零第三方依赖。

```bash
git clone https://github.com/lbyxiafei/island.git
cd island

./scripts/build-app.sh      # 编译并打包成 build/Island.app（ad-hoc 签名）
open build/Island.app       # 启动，无日志输出
pkill -x Island             # 退出

# 或者前台运行，配置与事件日志直接打在终端：
./build/Island.app/Contents/MacOS/Island
```

启动时会先自动弹一次悬浮窗，方便确认界面正常；之后按快捷键即可再次召唤。

## 配置

全部通过环境变量，改完即生效，无需重新构建。

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ISLAND_HOTKEY` | `cmd+ctrl+,` | 召唤快捷键 |
| `ISLAND_OVERLAY_SECONDS` | `5` | 悬浮窗停留秒数 |

modifier 可写 `cmd`/`command`/`⌘`、`ctrl`/`control`/`⌃`、`opt`/`option`/`alt`/`⌥`、`shift`/`⇧`；key 是 US 布局的单字符，或 `space` / `tab` / `return` / `escape`。

```bash
ISLAND_HOTKEY=cmd+shift+k ISLAND_OVERLAY_SECONDS=2 ./build/Island.app/Contents/MacOS/Island
```

配置值写错时不会崩：回落到默认值，并在 stderr 打一行 `warning`。想只检查配置解析结果：

```bash
./build/Island.app/Contents/MacOS/Island --print-config
```

## 开发

```bash
make verify        # 全部 gate：build / fmt / lint / test / coverage / cycles / issue-check
make help          # 所有可用 target
swift test         # 只跑测试
```

| 文件 | 内容 | 维护者 |
|---|---|---|
| `hai/PLAN.md` | goal / non-goal / scope / design / key decisions | 人 |
| `hai/CONTEXT.md` | setup / test / layout / conventions / gotchas，面向 AI Agent | Agent |
| `hai/ISSUES.md` | issue 索引，由 `make sync-issue` 生成 | 工具 |

代码分两层：`Sources/IslandCore`（纯逻辑，不与 UI 框架耦合，测试完整覆盖）与 `Sources/Island`（AppKit / Carbon 装配）。
