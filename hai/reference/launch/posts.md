# 发布文案

对外发布 island 用的草稿。发之前把 `<GIF>` 换成 README 里演示 GIF 的链接（或直接上传 GIF）。

赞助页：https://github.com/sponsors/lbyxiafei （仓库已有 Sponsor 按钮，文案里不必强调）。

发布节奏建议：先 V2EX / X 中文圈小范围试水、收一轮反馈修掉明显问题，再发 Show HN 和 Reddit。Show HN 在美西工作日早上 8–10 点发效果最好，发完前两小时守着回复评论。

---

## YouTube

视频文件：`~/Movies/island/island-intro.mp4`（1920×1080，60 秒，无音轨，可以在 YouTube Studio 编辑器里从 Audio Library 加一段免费配乐）。封面候选：`~/Movies/island/thumbnail-title.jpg` / `thumbnail-panel.jpg`。最后 11 秒是静态片尾，正好放 End screen（订阅 + 链接到 repo）。

**标题**：

> island — a macOS "Dynamic Island" for Claude Code, Codex & pi (open source)

**描述**：

> Running several AI coding agents at once? island is a tiny macOS menu-bar app that drops down the moment Claude Code, Codex or pi finishes a task, and one click takes you back to the exact terminal tab, tmux window, VS Code terminal or desktop conversation.
>
> • Every agent, one list: Claude Code · Codex · pi · Claude desktop
> • Jumps to the exact place: tmux · Terminal · iTerm2 · Ghostty · cmux · VS Code
> • ⌃⌘, from anywhere: type to filter, ↩ to jump
> • Quiet when you're already looking at that tab
> • No permission prompts, no network: reads local session files only
>
> Install: brew install --cask lbyxiafei/tap/island
> Source (MIT): https://github.com/lbyxiafei/island
>
> 0:00 Agents finishing in parallel
> 0:19 Jump back: click, or ⌃⌘, and type
> 0:37 Features & install

**标签**：claude code, codex, ai agents, macos, menu bar app, tmux, developer tools, open source

---

## Show HN

**标题**（≤ 80 字符）：

> Show HN: Island – a macOS notch popup when your Claude Code/Codex agents finish

**正文**：

> I run several coding agents at once — Claude Code in tmux, Codex in its desktop app, pi in a VS Code terminal — and kept losing time checking which one was done and waiting on me.
>
> Island is a small menu-bar app that watches the agents' local session files and drops a Dynamic-Island-style panel from the top of the screen when a task finishes. Click a task and it takes you back to the exact place it ran: the tmux pane, the Ghostty/iTerm2/Terminal/cmux tab, the VS Code terminal tab, or the conversation in the desktop app. If it can't find the window, it copies the resume command (`claude --resume <id>`) to your clipboard.
>
> A few things I cared about:
>
> - No permissions prompts for the global hotkey (Carbon hotkeys, not an event tap), and no network code at all — it only reads files on your machine
> - It stays quiet if the finished task is already the tab in front of you
> - Zero dependencies, native Swift/AppKit, signed and notarized
>
> Detecting "done" turned out to be the fun part: every agent stores state differently (JSONL transcripts, SQLite, and for the Claude desktop app, a Snappy-compressed V8-serialized IndexedDB blob, decoded by hand). Notes on each format are in the repo.
>
> `brew install --cask lbyxiafei/tap/island` — MIT licensed, macOS 13+. Feedback and PRs for other agents welcome.
>
> https://github.com/lbyxiafei/island

---

## Reddit（r/ClaudeAI、r/macapps、r/commandline）

**标题**：

> I built a free, open-source "Dynamic Island" for macOS that pops up when Claude Code / Codex finishes a task

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
> Install: `brew install --cask lbyxiafei/tap/island`
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

**标题**：

> [开源] island：AI agent 跑完任务时，macOS 顶部弹出「灵动岛」提醒，一键跳回对应终端

**正文**：

> 平时 Claude Code、Codex、pi 经常同时开好几个，tmux 里、VS Code 终端里、桌面 app 里都有。最大的痛点是不知道谁跑完了在等我，只能挨个切过去看。
>
> 所以写了 island，一个菜单栏小工具：
>
> - 任务跑完，屏幕顶部中央垂下一个「灵动岛」面板，列出刚完成的任务（未读有红点）
> - 点任务直接跳回它所在的位置：tmux 精确到 session/window/pane，Ghostty / iTerm2 / Terminal / cmux 精确到 tab，VS Code 精确到终端 tab，桌面版打开对应对话；实在找不到就把 `claude --resume <id>` 这类命令放进剪贴板
> - 你正看着的那个任务跑完不会打扰你
> - `⌃⌘,` 全局召唤，可以打字过滤、`⌘1–9` 直达；不需要辅助功能 / 输入监控权限
> - 纯本地：只读各 agent 的本地 session 文件，代码里没有任何网络请求
> - 原生 Swift，零依赖，已签名公证
>
> 安装：`brew install --cask lbyxiafei/tap/island`
>
> 仓库（MIT）：https://github.com/lbyxiafei/island
>
> <GIF>
>
> 各家 agent 的「完成」信号都不一样（JSONL、SQLite，Claude 桌面版甚至是 Snappy 压缩 + V8 序列化的 IndexedDB），调研笔记都在仓库的 `hai/reference/agents/` 里。欢迎提需求、提 PR 支持更多 agent 和终端。
