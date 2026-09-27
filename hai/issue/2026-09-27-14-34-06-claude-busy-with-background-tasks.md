---
type: bug
name: claude-busy-with-background-tasks
title: "Claude Code 有后台任务时一轮结束不报 idle，island 漏检"
status: new
created_ts: 2026-09-27T14:34:06-07:00
updated_ts: 2026-09-27T14:34:06-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

2026-09-27 排查"没看到 pop-up"时实测：Claude Code session（pid 15421，v2.1.283）一轮回复结束、transcript 已写 `system/turn_duration`，但因为这一轮留了一个 `run_in_background` 的后台任务，`~/.claude/sessions/<pid>.json` 的 `status` 一直是 `busy`，直到后台任务结束。`ClaudeCodeActivitySource` 要求 `status == idle`，所以这一轮完全没被检测到（3 分钟内 island 无日志）。没有后台任务的一轮：`busy -> idle` 约 8 秒内被检测到并弹出，正常。

## 期望结果

一轮结束但仍有后台任务在跑时，island 也能判断"这一轮完成了"（例如 `busy` 时也读 transcript，最后一轮以 `turn_duration` 收尾且之后没有新的 user 输入即算完成；需要确认 busy 状态下 transcript 的形态，避免把仍在跑的 turn 误判为完成）。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
