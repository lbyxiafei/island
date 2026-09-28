# v3：4K 全模拟介绍视频（当前采用的版本）

`~/Movies/island/island-intro.mp4` 用的就是这一版（2026-09-28）：3840×2160，30fps，60 秒。整片由 `index.html` 画出来，里面的 `render(t)` 按时间线决定每一帧；`render.mjs` 通过 CDP 让 headless Chrome 以 2× 设备像素比逐帧截图，再用管道交给 ffmpeg 编码。零依赖，只要 Node 和 Chrome。

```bash
node render.mjs stills ./st "6,17.5,24.3"          # 检查几个关键帧
node render.mjs video ./island-intro-4k.mp4 60       # 渲染全片
```

## 为什么全模拟，不用实录

上一版（`../live.sh` 那套）是真实交互的录屏，但画面不像真实使用场景：两个普通 Terminal 窗口、字小、任务是 CI / token 这类看不懂的内容，而且全是终端。用户反馈要「大胆模拟」，还原他真实的环境：

- Ghostty + tmux 左右分屏：左边 Claude Code（v2 的像素 logo、输入框、状态行），右边 pi（启动头、`[Context]`、底部状态）
- VS Code：编辑器 + 集成终端里跑 Claude Code
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

片头 0–4 → tmux 里问天气、问 HN（4–8.5）→ Codex 问东京（8.5–11.5）→ 回到 VS Code 干活（11.5–17）→ 天气 / 东京 / HN 陆续完成，浮窗弹出（17–24）→ 点 HN 那一行，跳进 tmux 右侧窗格（24.3）→ `⌃⌘,` 输入 `tok` 回车，打开 Codex 对话（28.6–31）→ `⌘⇥` 切回 VS Code，测试完成但不弹出（34–38）→ `⌃⌘,` 再按 `⌘1` 回到天气（38.3–42）→ 功能页（42.4–51.2）→ 片尾安装命令（51.2–60，给 YouTube 结束画面留位置）。
