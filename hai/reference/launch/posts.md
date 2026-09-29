# 发布文案

对外发布 island 用的草稿。发之前把 `<GIF>` 换成 README 里演示 GIF 的链接（或直接上传 GIF）。

赞助页：https://github.com/sponsors/lbyxiafei （仓库已有 Sponsor 按钮，文案里不必强调）。

关于 `brew install island`（不带 tap 前缀）：官方 homebrew/cask 里 `island` 这个名字目前没人占用（2026-09-28 查过），但作者自己提交的 cask 要满足知名度门槛：GitHub **≥ 75 star**，或 ≥ 30 fork / ≥ 30 watcher，否则 PR 会被拒。star 到了之后按官方 cask 模板把 `Casks/island.rb` 提交到 homebrew/cask，合并后就能 `brew install island`。在那之前，`brew install lbyxiafei/tap/island` 是最短的写法（不需要 `--cask`）。

发布节奏建议：先 V2EX / X 中文圈小范围试水、收一轮反馈修掉明显问题，再发 Show HN 和 Reddit。Show HN 在美西工作日早上 8–10 点发效果最好，发完前两小时守着回复评论。

---

## YouTube

已发布（2026-09-28）：英文 https://youtu.be/0XrcqU0VyXI ，中文 https://youtu.be/1aLZ_5ponIc 。缩略图是 `~/Movies/island/thumbnail.jpg` / `thumbnail-zh.jpg`，源文件在 `video/simulated/thumb.html`（`?en` / `?zh`）。发 Show HN、V2EX 等帖子时，把文案里的 `<VIDEO>` 换成对应链接。

视频文件：`~/Movies/island/island-intro.mp4`（4K 3840×2160，60 秒，带原创配乐，由 `video/simulated/music.py` 合成，无版权问题）。封面候选：`~/Movies/island/thumbnail-title.jpg` / `thumbnail-panel.jpg`。最后 5 秒是静态片尾，正好放 End screen（订阅 + 链接到 repo）。

**标题**：

> island — a Dynamic Island for every AI agent on your Mac (open source)

**描述**：

> Stop tabbing through terminals to see which agent is done.
>
> island is a free, open-source macOS menu-bar app for people who run AI agents in parallel. The moment any agent finishes a task, a panel drops down from the top of your screen. Click it and you land back in the exact place that task ran: the right terminal tab, tmux pane, VS Code terminal, or desktop conversation.
>
> Works today with Claude Code, Codex, pi and the Claude desktop app. The goal is every agent on your Mac, and more are on the way (PRs welcome).
>
> ▸ One list for every agent, unread first
> ▸ Jumps to the exact tab: tmux, Ghostty, iTerm2, Terminal, cmux, VS Code, desktop apps
> ▸ Summon it from anywhere with ⌃⌘, (or any hotkey you like), type to filter, ↩ to jump
> ▸ Stays quiet when you're already looking at that task
> ▸ 5 themes, adjustable pop-up time, per-agent switches
> ▸ No permission prompts, no network. It only reads local session files
>
> Install:
> brew install lbyxiafei/tap/island
>
> Source (MIT): https://github.com/lbyxiafei/island
>
> Chapters
> 0:00 Run a few agents at once
> 0:17 island pops up, click or ⌃⌘, to jump back
> 0:42 Make it yours: hotkey, themes, per-agent switches
>
> #ClaudeCode #Codex #AIagents #macOS #DeveloperTools

**标签**：AI agents, Claude Code, Codex, pi, macOS, menu bar app, developer tools, tmux, productivity, open source

### 中文版（`~/Movies/island/island-intro-zh.mp4`，封面 `thumbnail-title-zh.jpg` / `thumbnail-panel-zh.jpg`）

**标题**：

> island：Mac 上所有 AI agent 的「灵动岛」，任务一跑完就提醒你（开源）

**描述**：

> 同时开好几个 AI agent 干活，却总要来回切终端看谁跑完了？
>
> island 是一个免费开源的 macOS 菜单栏小工具。任何一个 agent 的任务一完成，屏幕顶部就弹出提醒；点一下，直接回到它所在的地方：对应的终端 tab、tmux 窗格、VS Code 终端，或者桌面 app 里的那段对话。
>
> 目前支持 Claude Code、Codex、pi 和 Claude 桌面版。目标是覆盖你 Mac 上的所有 agent，更多正在陆续加入（欢迎 PR）。
>
> ▸ 所有 agent 一个列表，未读优先
> ▸ 精准跳回：tmux、Ghostty、iTerm2、Terminal、cmux、VS Code、桌面 app
> ▸ 随时按 ⌃⌘,（快捷键可自定义）呼出，打字过滤，回车直达
> ▸ 你正看着的任务完成时，不打扰
> ▸ 5 种主题，弹出时长可调，每个 agent 可单独开关
> ▸ 不需要任何系统权限，不联网，只读本地 session 文件
>
> 安装：
> brew install lbyxiafei/tap/island
>
> 源码（MIT）：https://github.com/lbyxiafei/island
>
> 章节
> 0:00 同时让几个 agent 干活
> 0:17 任务完成就弹出，点一下或按 ⌃⌘, 跳回
> 0:42 按你的习惯来：快捷键、主题、按 agent 开关
>
> #ClaudeCode #Codex #AIagent #macOS #效率工具

**标签**：AI agent, Claude Code, Codex, pi, macOS, 菜单栏, 效率工具, 开发者工具, tmux, 开源

---

## Show HN

发帖时间：美西周二到周四早上 8–10 点（北京时间当晚 23 点到次日 1 点）。URL 填 GitHub 仓库，正文会显示在帖子里。发出后头两小时守着回评论。

**标题**（≤ 80 字符）：

> Show HN: Island – a macOS notch popup when any of your AI agents finishes

**URL**：https://github.com/lbyxiafei/island

**正文**：

> I usually have several agents going at once: Claude Code in tmux, Codex in its desktop app, pi in a VS Code terminal. I kept losing time tabbing around to see which one was done and waiting on me.
>
> Island is a small menu-bar app that watches your agents' local session files and drops a Dynamic-Island-style panel from the top of the screen when any of them finishes a task. Click a task and it takes you back to the exact place it ran: the tmux pane, the Ghostty/iTerm2/Terminal/cmux tab, the VS Code terminal tab, or the conversation in the desktop app. If it can't find the window, it copies the resume command (e.g. `claude --resume <id>`) to your clipboard.
>
> It supports Claude Code, Codex, pi and the Claude desktop app today. The aim is every agent on your Mac, and each agent is a small adapter, so PRs for others are very welcome.
>
> A few things I cared about:
>
> - No permission prompts for the global hotkey (Carbon hotkeys, not an event tap), and no network code at all. It only reads files on your machine
> - It stays quiet if the finished task is already the tab in front of you
> - Hotkey, theme, pop-up time and each agent/scenario are configurable
> - Zero dependencies, native Swift/AppKit, signed and notarized
>
> Detecting "done" turned out to be the fun part: every agent stores state differently (JSONL transcripts, SQLite, and for the Claude desktop app a Snappy-compressed, V8-serialized IndexedDB blob, decoded by hand). Notes on each format are in the repo.
>
> 60-second demo: https://youtu.be/0XrcqU0VyXI
>
> `brew install lbyxiafei/tap/island`, MIT licensed, macOS 13+.

---

## Reddit（r/ClaudeAI、r/macapps、r/commandline）

**标题**：

> I built a free, open-source "Dynamic Island" for macOS that pops up when any AI agent finishes a task

**正文**：

> <GIF>
>
> 60-second demo: <VIDEO>
>
> If you run multiple agents in parallel you know the loop: tab through terminals, check who's done, repeat. Island watches Claude Code, Codex, pi and the Claude desktop app locally and pops a panel from the menu bar when one finishes. Click it to jump straight back to the right tmux pane / terminal tab / VS Code terminal / desktop chat.
>
> - Global hotkey (⌃⌘,) with no Accessibility permissions needed
> - Won't interrupt you if you're already looking at that task
> - No network access, reads local files only, MIT licensed
>
> Install: `brew install lbyxiafei/tap/island`
> Repo: https://github.com/lbyxiafei/island
>
> What agents / terminals should it support next?

r/macapps 规定自己的 app 要带 `[Self-promotion]` 或在周贴里发，发之前看一眼版规。

---

## X / Twitter（英文）

> Running 4 coding agents at once and constantly tabbing around to see who's done?
>
> I built Island: a macOS menu-bar app that pops up the moment Claude Code, Codex or pi finishes a task, and one click jumps you back to the exact tmux pane / terminal tab.
>
> Free, open source, no permissions needed.
>
> <GIF>
> github.com/lbyxiafei/island

可 @ 的相关账号：Claude Code、Codex 官方账号，以及常分享 macOS 小工具的博主。

---

## X / 即刻（中文）

> 同时开好几个 AI agent 干活，最烦的就是来回切终端看谁跑完了。
>
> 做了个 macOS 小工具 island：Claude Code / Codex / pi 任务一跑完，屏幕顶部就弹出一个「灵动岛」；点一下直接跳回那个 tmux pane / 终端 tab / VS Code 终端 / 桌面对话。
>
> 开源免费，不要任何系统权限，也不联网。
>
> <GIF>
> github.com/lbyxiafei/island

---

## V2EX（节点：分享创造）

发帖地址：https://www.v2ex.com/new/create ，节点选「分享创造」（create），正文格式选 Markdown。北京时间工作日白天发。

**标题**：

> [开源] island：Mac 上所有 AI agent 的「灵动岛」，任务一跑完就弹出提醒，一键跳回对应终端

**正文**：

> 平时 Claude Code、Codex、pi 经常同时开好几个，tmux 里、VS Code 终端里、桌面 app 里都有。最大的痛点是不知道谁跑完了在等我，只能挨个切过去看。
>
> 所以写了 island，一个 macOS 菜单栏小工具，目标是覆盖 Mac 上所有的 AI agent：
>
> - 任何一个 agent 的任务跑完，屏幕顶部中央垂下一个「灵动岛」面板，列出刚完成的任务（未读有红点）
> - 点任务直接跳回它所在的位置：tmux 精确到 session/window/pane，Ghostty / iTerm2 / Terminal / cmux 精确到 tab，VS Code 精确到终端 tab，桌面版打开对应对话；实在找不到就把 `claude --resume <id>` 这类命令放进剪贴板
> - 你正看着的那个任务跑完不会打扰你
> - `⌃⌘,` 全局召唤（快捷键可自定义），打字过滤、回车或 `⌘1–9` 直达；不需要辅助功能 / 输入监控权限
> - 5 种主题、弹出时长、每个 agent / 场景单独开关
> - 纯本地：只读各 agent 的本地 session 文件，代码里没有任何网络请求；原生 Swift，零依赖，已签名公证
>
> 目前支持 Claude Code、Codex、pi 和 Claude 桌面版，每接一个 agent 就是一个小 adapter，欢迎提 PR 支持更多 agent 和终端。
>
> 60 秒演示视频：https://youtu.be/1aLZ_5ponIc
>
> ![island 演示](https://raw.githubusercontent.com/lbyxiafei/island/master/docs/demo.gif)
>
> 安装：`brew install lbyxiafei/tap/island`
>
> 仓库（MIT）：https://github.com/lbyxiafei/island
>
> 各家 agent 的「完成」信号都不一样（JSONL、SQLite，Claude 桌面版甚至是 Snappy 压缩 + V8 序列化的 IndexedDB），调研笔记在仓库的 `hai/reference/agents/` 里。

---

## B 站

投稿地址：https://member.bilibili.com/platform/upload/video/frame 。视频文件 `~/Movies/island/island-intro-zh.mp4`，封面 `~/Movies/island/thumbnail-zh.jpg`。分区选「科技 → 软件应用」，类型选「自制」。

**标题**（≤ 80 字）：

> Mac 上所有 AI agent 的「灵动岛」：Claude Code / Codex 跑完就提醒你，一键跳回终端【开源】

**简介**：

> 同时开好几个 AI agent 干活，却总要来回切终端看谁跑完了？island 是一个免费开源的 macOS 菜单栏小工具：任何一个 agent 的任务一完成，屏幕顶部就弹出提醒；点一下，直接回到对应的终端 tab、tmux 窗格、VS Code 终端或桌面 app 里的那段对话。
>
> 目前支持 Claude Code、Codex、pi 和 Claude 桌面版，更多 agent 陆续加入。
> 安装：brew install lbyxiafei/tap/island
> 源码（MIT）：https://github.com/lbyxiafei/island
>
> 00:00 同时让几个 agent 干活
> 00:17 任务完成就弹出，点一下或按 ⌃⌘, 跳回
> 00:42 按你的习惯来：快捷键、主题、按 agent 开关

**标签**：AI, Claude Code, Codex, macOS, 效率工具, 开源, 程序员, 开发工具, tmux, AI编程
