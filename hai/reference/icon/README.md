# island menubar icon

**设计意图**：一块圆角面板（悬浮窗本体）悬在一条细横线（屏幕顶边）之上 —— 直白表达"悬浮在屏幕上方的浮窗"。
不用 Dynamic Island 那种带缺口的胶囊，是因为菜单栏实际渲染尺寸只有约 16pt，
缺口在这么小的尺寸下会糊成一团；两块粗圆角的对比度在小尺寸反而更清楚。

**规格**

| 项 | 值 |
|---|---|
| 画布 | 18×18（菜单栏会把图片缩放到约 16pt 高） |
| 颜色 | 单色，`isTemplate = true`，由 macOS 负责着色（浅色/深色/高亮/点击态） |
| 面板 | `x=3.5 y=6.2 w=11 h=8 rx=2.6` |
| 屏幕顶边 | `x=2 y=2.2 w=14 h=2 rx=1` |

**文件**

- `menubar-icon.svg` —— 矢量设计源，可直接改数值再对照下面的代码
- `menubar-icon.png` —— 128px 预览图（由 SVG 渲染），只为方便肉眼查看

**约束（AGENTS.md）**：`reference/` 下的内容不得被编译、打包或作为运行时依赖。
因此运行时图标由 `Sources/Island/IslandGlyph.swift` 用 `NSBezierPath` 按上表坐标绘制，
**不读取本目录的任何文件**。改图标要同时改 SVG 与那处绘制代码。

# island app 图标

Finder / 登录项 / Launchpad 里的图标（issue `app-icon`，方案 A「Lagoon 胶囊」）。以前 bundle 里没有图标，系统显示空白占位。

**设计意图**：和菜单栏图标同一个隐喻——一块平顶圆底的岛式胶囊（悬浮窗本体）从屏幕顶边垂下来，上面是一条完成的任务（标题 + 两行 + 珊瑚色未读点），底下是泻湖的海浪。配色取悬浮窗的 Lagoon 主题（`OverlayTheme`）：底色 `#0A2F3D → #11858A`，强调 `#0F8F86` / `#3DD6C8`，未读点 `#FF7F66`。

**规格**：1024 画布，按 macOS 图标网格画 824×824、圆角 185 的主体（左上角在 100,100）。macOS 26 会把不合网格的旧图标关进灰色底框，按网格画就不会；已用 `NSWorkspace.icon(forFile:)` 确认显示正常。16px 下仍能认出白色面板 + 海浪。

**文件**

- 设计源与打包产物**不在本目录**：`assets/AppIcon.svg`（源）→ `scripts/render-app-icon.sh` → `assets/AppIcon.icns`（提交进 git，`build-app.sh` 只负责拷贝）。改完 SVG 必须重新跑脚本并一起提交
- `app-icon-preview.png` —— 256px 预览，只为方便肉眼查看
- 渲染用 AppKit 自带的 SVG 支持（`NSImage`）+ `iconutil`，零依赖。**它不支持 SVG filter**，所以阴影是两层半透明的平移形状，别用 `feDropShadow`

