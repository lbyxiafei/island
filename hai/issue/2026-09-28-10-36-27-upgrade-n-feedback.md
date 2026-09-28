---
type: feat
name: upgrade-n-feedback
title: "[feat] enable in-app upgrade and feedback channels"
status: solved
created_ts: 2026-09-28T10:36:27-07:00
updated_ts: 2026-09-28T12:26:51-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

我希望在 in-app 的setting处增加 feedback 和 upgrade 的选项。

## 期望结果

feedback可以是用户提交一个问题，可以是一段话，然后直接发到我邮箱，如果可能，如果不可能帮我看看市面上的最简实用option

upgrade就是我homebrew版本升级，用户可以点击upgrade跟着**一键**升级，不用操心自己升级。然后同时可以检测有版本更新，然后提示用户，比如settings打开的时候，升级的所在tab上面有个红点， 引导用户去按。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

## 设计

- **Upgrade**：版本真源是公开 tap 的 `Casks/island.rb`（`raw.githubusercontent.com`，无 API 限流）里的 `version "x.y.z"`；启动时、每 6 小时、打开 settings 时各查一次（可在 Settings → Updates 关掉自动检查，`Check Now` 始终可用）。有新版本时 Updates tab 标签带红点，菜单栏菜单出现 `Update to x.y.z…`。本地构建（`0.0.0`）视为开发版，不提示。
- 点 `Upgrade & Relaunch`：island spawn 一个脱离的 `sh`，自己退出；shell 等 island 退出后跑 `brew update` + `brew upgrade --cask lbyxiafei/tap/island`，日志写 `~/Library/Logs/island-upgrade.log`，最后无论成败都 `open -b com.commallama.island`。不是 brew 装的（找不到 `Caskroom/island`）就退回打开 tap 的 Release 页。
- **Feedback**：Settings → Feedback 一个文本框；`Send Email` 用默认邮件客户端打开预填好的邮件（收件人 lbyxiafei@gmail.com，附版本号和 macOS 版本）；`Open GitHub Issue` 打开预填好的 `lbyxiafei/island` new issue；`Copy` 把文本 + 环境信息放进剪贴板，兜底没配邮件客户端的用户。
- 决策逻辑（版本比较、cask 解析、命令拼装、URL 拼装、日志结果解析）放 IslandCore 有测试；网络与 AppKit 放 Sources/Island。

## Decision

- 2026-09-28，binyan.li 在会话中选择 Feedback 渠道为「mailto + GitHub issue」（零服务端、零第三方服务），否决 Web3Forms / Formspree 直达邮箱方案。
- 同一会话由用户明确要求实现本 issue（PLAN 未列此 scope，按「用户明确指令可以覆盖 scope」执行）。

# History

## 2026-09-28T12:20:36-07:00: new -> in-progress

用户在会话中要求实现；设计与 Decision 见正文。

## 2026-09-28T12:26:51-07:00: in-progress -> solved

Settings 新增 Updates / Feedback 两个 tab。Updates：读公开 tap 的 cask 判断新版本（启动、每 6 小时、打开 settings），有新版时 tab 名带 🔴、菜单出现 Update to x available…；brew 安装的一键 = 脱离 sh 等 island 退出后 brew update + upgrade --cask 再重开，日志 ~/Library/Logs/island-upgrade.log；非 brew 安装打开 Release 页。Feedback：mailto（预填收件人/主题/版本）、预填 GitHub issue、Copy 兜底。决策逻辑在 IslandCore（AppUpdate / Feedback，25 个新测试，覆盖率保持 100%）。验证：make verify 全过；ISLAND_VERSION=0.0.9 构建实测检测到 0.1.0、红点与菜单项出现、Copy 内容正确；升级 shell 用假 brew 实测（等 pid、update→upgrade、记录 exit 码、仍会重开）。未覆盖：本机不是 brew 安装，真实 brew upgrade 一键链路要等下一次 publish 后在 brew 安装的机器上验收。
