---
type: bug
name: dropdown-title-ux
title: "[ux] title at island dropdown not meeting expectation"
status: solved
created_ts: 2026-09-25T11:47:19-07:00
updated_ts: 2026-09-25T12:44:54-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

我们就当前版本统一更新下已知、已经发现的一些 ux 方面的bug：

![alt text](image.png)

1. title 一塌糊涂，我的意思是，如果有title（claude 桌面版有 ai 自己定的title，terminal 有 /name、/rename 出来的title）就用title，没有的话，就用上一个 用户 msg 作为 title 显示，你现在这个dotfiles-9e啥玩意儿？
2. 你的dotfiles-9e出现了太多次，需要去重，同一个session/task/任务 id 就不要堆叠了
3. 观测到新打开 session 的时候也会有 island 的 pop up，这个就不必了，因为我新打开啥内容都没有，何必pop up？我的目的是提醒我有新结束的 ai 内容，新打开是没有的；同时，我自测在claude code按下 esc也会出发island pop up，这个似乎也没有必要，因为这是我主动中断，你看看这两种情况能否检测出来并且filterout

## 期望结果

我期待所有上面的 bugs 都修复。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

## 处理结果

Scope-check: PLAN § Design / Island 下拉框 UX #1、Island 展示 UX（只提醒新完成的任务）

1. **标题**：`dotfiles-9e` 是 Claude Code 自动派生的占位名（session json 里 `nameSource: "derived"`），不再当标题。取值链改为：
   - Claude：transcript 的 `custom-title`（/rename）→ 非 derived 的 `name` → `ai-title`（AI 自定标题）→ 最后一条用户 prompt → 目录名
   - pi：`session_info.name`（/name）→ 最后一条用户消息
   - Codex：`threads.name` → 最后一条 `userMessage` → 首条用户消息
2. **去重**：`AgentInbox` 按 `agent:sessionID` 一个 session 一行；同一 session 的新一轮替换旧行并重新标为未读。
3. **不必要的弹窗**：Claude 不再只看 `status == idle`，还要求 transcript 最后一轮以 `system/turn_duration` 收尾、且该轮没有 `[Request interrupted by user…`。新开 session（还没有任何一轮）和 esc 中断都不再算完成；pi 的 esc 是 `stopReason: aborted`，本来就被过滤。完成时间取 `turn_duration` 的时间戳，所以 /rename 之类只改 session json 的操作也不会被当成新完成。

transcript 会长到 MB 级，`ClaudeTranscriptCache` 按 (size, mtime) 缓存解析结果，并且直接跳过 busy 的 session。
