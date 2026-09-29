# v3：4K 全模拟介绍视频（当前采用的版本）

`~/Movies/island/island-intro.mp4` 用的就是这一版（2026-09-28）：3840×2160，30fps，60 秒。整片由 `index.html` 画出来，里面的 `render(t)` 按时间线决定每一帧；`render.mjs` 通过 CDP 让 headless Chrome 以 2× 设备像素比逐帧截图，再用管道交给 ffmpeg 编码。零依赖，只要 Node 和 Chrome。

```bash
node render.mjs stills ./st "6,17.5,24.3"                        # 检查几个关键帧
node render.mjs video ./silent-4k.mp4 60                           # 渲染画面（英文版）
SCENE_QUERY='?lang=zh' node render.mjs video ./silent-4k-zh.mp4 60  # 中文版：字幕、卡片、任务内容都换成中文，app 界面保持英文
uv run --with numpy --with scipy python music.py                   # 合成配乐 → music.wav
ffmpeg -i silent-4k.mp4 -i music.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -shortest island-intro.mp4
```

## 配乐

`music.py` 从零合成，原创、无版权问题。2026-09-28 按用户要求改成轻快版：128 BPM，D 大调，和声走 I–V–vi–IV（D → A → Bm → G），结尾落在 Dmaj9。配器有反拍短和弦（弹跳感）、马林巴风格的 16 分音符琶音、8 分音符八度跳动的贝斯，前奏就有响指和沙锤，鼓进来后是轻的四拍底鼓、拍手和反拍开镲。网格对齐方式：`T0 = 17.0 - 9 * BAR`，让 17.0 秒（第一个任务完成、浮窗弹出）正好落在小节强拍上，鼓在这里进来，约 54.5 秒片尾时鼓退出。UI 音效（浮窗弹出、鼠标点击、按键帽、打字声）按 index.html 里 `B` / `S` 的时间点放置，改时间线时两边要一起改。输出 `music-raw.wav` 后，先用 ebur128 测响度，再调增益到 -14 LUFS：

```bash
I=$(ffmpeg -hide_banner -i music-raw.wav -af ebur128 -f null - 2>&1 | grep -E '^\s+I:' | tail -1 | awk '{print $2}')
ffmpeg -i music-raw.wav -af "volume=$(python3 -c "print(-14 - ($I))")dB,alimiter=limit=0.89:level=false" music.wav
```

## 为什么全模拟，不用实录

上一版（`../live.sh` 那套）是真实交互的录屏，但画面不像真实使用场景：两个普通 Terminal 窗口、字小、任务是 CI / token 这类看不懂的内容，而且全是终端。用户反馈要「大胆模拟」，还原他真实的环境：

- Ghostty + tmux 左右分屏：左边 Claude Code（v2 的像素 logo、输入框、状态行），右边 pi（启动头、`[Context]`、底部状态）
- VS Code：编辑器 + 集成终端里跑 Claude Code
- Settings：点菜单栏图标 → Settings…，依次演示录制新快捷键（⌥Space）、切主题并实时预览浮窗、改弹出时长、按场景关掉 Codex headless exec。窗口结构和文案照 `Sources/Island/HotkeySettingsWindow.swift` 和 `AgentProfile.swift` 还原
- Codex 桌面版：浅色侧栏 + 对话 + 底部 composer，照着真实截图还原
- 任务选人人看得懂的：西雅图周末天气、HN 今日 Top 5、东京 3 日游、给 `parseDate()` 写单测

island 面板按真实 Midnight 主题截图 1:1 还原（尺寸、配色、行高、红点、选中胶囊、搜索态、键位提示），行的排序和未读逻辑与 app 一致：未读优先、按完成时间倒序；你正看着的任务完成时不计未读。

## 素材

`assets/` 不进仓库。里面是从本机 app 包提取的图标，重新生成：

```bash
for app in Claude ChatGPT "Visual Studio Code" Ghostty; do
  icon=$(defaults read "/Applications/$app.app/Contents/Info" CFBundleIconFile); icon=${icon%.icns}
  sips -s format png -Z 512 "/Applications/$app.app/Contents/Resources/$icon.icns" --out "assets/$(echo $app | tr ' A-Z' '-a-z').png"
done
```

终端字体用的是本机的 JetBrainsMono NL Nerd Font（`@font-face` 指向 `~/Library/Fonts`），没有的话回退到 Menlo。

## 时间线

片头 0–4 → tmux 里问天气、问 HN（4–8.5）→ Codex 问东京（8.5–11.5）→ 回到 VS Code 干活（11.5–17）→ 天气 / 东京 / HN 陆续完成，浮窗弹出（17–24）→ 点 HN 那一行，跳进 tmux 右侧窗格（24.3）→ `⌃⌘,` 输入 `tok` 回车，打开 Codex 对话（28.6–31）→ `⌘⇥` 切回 VS Code，测试完成但不弹出（34–38）→ `⌃⌘,` 再按 `⌘1` 回到天气（38.3–42）→ 菜单栏打开 Settings，演示可配置性（42.2–49.8）→ 功能页（50–55）→ 片尾安装命令（55–60，给 YouTube 结束画面留位置）。
