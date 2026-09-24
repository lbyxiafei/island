# island

监视本机 AI Agent 的运行活动，在 session / task 完成时于屏幕中央上方弹出一个悬浮窗。

> **当前处于 MVP 阶段**：POC（app 流程、global hotkey、菜单栏、开机自启、快捷键配置）已完成；MVP 正在做 agent 检测与展示 UX，详见 `hai/PLAN.md`。

## 现在能做什么

- **检测本机已完成的 agent run**：支持 Claude Code（terminal）、pi（terminal）、Codex（CLI + 桌面）；完成信号、任务身份、标题、宿主进程的调研见 `hai/reference/agents/README.md`
- 任务完成时自动弹出悬浮窗，里面是任务列表（未读优先，未读左侧有红点）；hover 会暂停自动隐藏
- 任务标题优先用 agent 自己的 title，没有就显示**最后一条消息**，再没有才回退到目录名
- 点击任务后**悬浮窗随即收起**，并跳回它：tmux 就选中对应 window/pane 并激活终端，VS Code 就聚焦对应文件夹的窗口，桌面 app 就激活对应应用，无法精确定位时把 resume 命令（如 `claude --resume <id>`）贴到剪贴板；点过后红点消失但条目保留
- 菜单栏图标右侧显示**未读任务数**，菜单里也有一份同样的任务列表（点击即跳回）
- 只统计 island 启动之后完成的 run，不看历史
- 按 `⌃⌘,` 全局召唤屏幕顶部中央的悬浮窗，**不需要任何系统权限授权**（不弹输入监控 / 辅助功能对话框）；悬浮窗显示期间再按一次即可立即收起（toggle）
- 悬浮窗 5 秒后自动消失，时长可配置；重复召唤会重置计时
- 悬浮窗不抢焦点，也不会出现在窗口切换器里
- 菜单栏常驻一个 island 图标：一眼看出它在跑，可手动召唤、开关召唤快捷键、改快捷键、切换开机自启、退出
- 快捷键可以随时 on / off：关掉后键位还给系统，配置仍然保留，随时可以再打开
- 改快捷键时直接**按组合键录制**（不用记语法），并有一键 `Clear` 清空
- 支持开机 / 登录自启（`SMAppService`，可在系统设置的登录项里关掉）
- 构建与运行只需要本机 Xcode，**不需要 Apple Developer 账号**（ad-hoc 签名）

## 快速开始

要求 macOS 13+ 与 Xcode（本机在 macOS 26.6.2 / Xcode 26.6 / Swift 6.3.3 上验证过）。零第三方依赖。

```bash
git clone https://github.com/lbyxiafei/island.git
cd island

./scripts/build-app.sh      # 编译并打包成 build/Island.app（ad-hoc 签名）
open build/Island.app       # 启动，无日志输出

# 或者前台运行，配置与事件日志直接打在终端：
./build/Island.app/Contents/MacOS/Island
```

启动时会先自动弹一次悬浮窗，之后按快捷键即可再次召唤。退出：点菜单栏 island 图标 → `Quit island`，或 `pkill -x Island`。

> 想长期使用，建议把 `Island.app` 拷到 `/Applications` 再从那里启动——登录项记的是 app 的路径，放在构建目录里容易被后续构建或清理打扰。

## 配置快捷键

菜单栏图标 → `Settings…`：点一下录制框，直接按下想要的组合键即可录入（至少含一个 `⌘⌃⌥⇧` 修饰键）。`Apply` 立即生效并记住；`Clear` 清空并关掉快捷键；`Reset to default` 回到内置默认。失败的换绑会自动保留旧快捷键。

快捷键也可以随时停用：录制框上方的 `Enabled` 勾选框、菜单里的 `Summon hotkey` 勾选项，效果一致（关掉后配置保留，随时可再打开）。

快捷键本身是 toggle：悬浮窗已经显示时再按一次会立刻收起，而不是把 5 秒计时重新开始（菜单里的 `Summon overlay` 则始终是“显示”）。

另外两种方式，**应用内设置优先**：

| 方式 | 说明 |
|---|---|
| 菜单栏图标 → `Settings…` | 立即生效并记住；非法组合会当场提示，改坏了会自动保留旧快捷键 |
| 环境变量 `ISLAND_HOTKEY` | 启动时读取，适合一次性试用；被应用内设置覆盖 |

内置默认是 `cmd+ctrl+,`。清掉应用内设置即回到环境变量或默认：

```bash
# 恢复默认快捷键，并重新打开
defaults delete com.binyanli.island.poc IslandHotkeyText
defaults delete com.binyanli.island.poc IslandHotkeyEnabled
```

## 配置

时长通过环境变量，改完即生效，无需重新构建。

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ISLAND_HOTKEY` | `cmd+ctrl+,` | 召唤快捷键 |
| `ISLAND_OVERLAY_SECONDS` | `5` | 悬浮窗停留秒数 |
| `ISLAND_TASK_LIMIT` | `10` | 悬浮窗展示的任务条数 |

看一下本机现在检测到哪些已完成 run（不会开窗，纯调试）：

```bash
./build/Island.app/Contents/MacOS/Island --scan-agents
./build/Island.app/Contents/MacOS/Island --reopen-plan <pid>   # 某个 agent 进程会被怎么跳回
```

任务条数用 `ISLAND_TASK_LIMIT` 调，默认 10。

## 菜单栏

点开菜单栏的 island 图标：

| 菜单项 | 作用 |
|---|---|
| `Summon overlay (⌃⌘,)` | 手动召唤一次（快捷键之外的备用入口） |
| `Summon hotkey` | 召唤快捷键的 on / off 开关，勾选状态即真实状态 |
| `hotkey ⌃⌘, · default` | 当前快捷键及其来源（应用内设置 / 环境变量 / 默认），关掉时显示 `hotkey off` |
| `Settings…` | 录制快捷键、开关、清空 |
| `Launch at login` | 开机自启开关，勾选状态即系统真实状态 |
| `Quit island` | 退出 |

图标右侧的数字是未读 agent 任务数（同微信那种角标）。

登录项也可以用命令行检查与开关（必须调用 `.app` 包内的可执行文件）：

```bash
./build/Island.app/Contents/MacOS/Island --login-item-status
./build/Island.app/Contents/MacOS/Island --login-item-enable
./build/Island.app/Contents/MacOS/Island --login-item-disable
```

关闭自启后，也可以在「系统设置 → 通用 → 登录项」里确认。

modifier 可写 `cmd`/`command`/`⌘`、`ctrl`/`control`/`⌃`、`opt`/`option`/`alt`/`⌥`、`shift`/`⇧`；key 是 US 布局的单字符，或 `space` / `tab` / `return` / `escape`（这条语法只有写环境变量 / `defaults` 时才需要，应用内录制不涉及）。

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
