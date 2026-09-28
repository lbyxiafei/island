# 介绍视频与 GIF 的制作工具

> **当前采用的是 `simulated/`（v3，4K 全模拟）**。本页记录的是 v2 实录方案，保留下来供参考。

2026-09-27 做 60 秒 YouTube 介绍视频（`~/Movies/island/island-intro.mp4`）和 `docs/demo.gif` 用的全套工具。**仅作参考，不参与构建**；脚本里的路径指向当时会话的 scratchpad，重录前先改路径。

## 思路

1. **实录，只录自己的窗口**：`rec.swift` 用 ScreenCaptureKit，内容过滤器只包含 Terminal、demo 版 island、以及录制器自己画的渐变背景窗口。用户屏幕上的其他 app 即使盖在上面也录不进去，所以不需要清桌面。
2. **假数据，真交互**：`live.sh` 让 island 通过 `ISLAND_AGENT_HOME` 读临时目录里的假 session（Claude Code transcript、pi jsonl、Codex 的两个 sqlite）。终端里跑的是 `fakeagent.c` 编出来的、名字叫 `claude` / `pi` 的真进程，它们按 `scripts.py` 生成的脚本逐行打印。island 解析到的宿主是真实的 Terminal tab 和 tmux pane，点击、`⌃⌘,`、输入和回车都是真实操作（`mouse.swift` 用 CGEvent 模拟鼠标，按键走 System Events）。
3. **后期**：原始帧由 `final.html` 合成：镜头推拉、菜单栏未读数、点击涟漪、按键帽、字幕、片头、功能页和片尾。`render.mjs` 通过 CDP 驱动 headless Chrome 逐帧截图（零依赖，Node 自带 WebSocket），最后用 ffmpeg 编码。GIF 从成片里截取。

## 踩过的坑

- 拼音输入法会吞掉合成按键，召唤出的浮窗随即失焦关闭。录制期间要用 `ime.swift` 临时切到 ABC，结束后切回。
- `do script` 之后的 `front window` 可能是 Terminal 启动时自带的默认窗口，要用 `first window whose selected tab is t` 才能拿到正确的窗口。
- 窗口标题由 Terminal 描述文件的 `Show*InTitle` 开关决定：先 `defaults export com.apple.Terminal` 备份，修改后 import，录完再整份导回。标题本身由 agent 进程用 OSC 0 设置。
- tmux 走用户的默认 server（island 只查默认 socket），所以只新建 `island-demo` 这一个 session，并用 session 级 / window 级选项覆盖状态栏样式，不碰全局配置。
- 录制期间 island 的设置（快捷键、弹出时长、主题）要改成演示用的值：录前 `defaults export com.commallama.island` 备份，录完导回。
- 复制出来的 `/bin/sleep` 会因签名失效被 SIGKILL；自己用 `cc` 编的二进制是 ad-hoc 签名，可以直接运行。
- 显示器分辨率不固定（这次录制中途从 3008pt 2x 变成了 1080p 1x），布局和录制区域要按当时的屏幕来定。
