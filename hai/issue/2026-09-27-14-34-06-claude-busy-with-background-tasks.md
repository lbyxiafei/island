---
type: bug
name: claude-busy-with-background-tasks
title: "Claude Code 有后台任务时一轮结束不报 idle，island 漏检"
status: solved
created_ts: 2026-09-27T14:34:06-07:00
updated_ts: 2026-09-27T14:39:46-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

2026-09-27 排查"没看到 pop-up"时实测：Claude Code session（pid 15421，v2.1.283）一轮回复结束、transcript 已写 `system/turn_duration`，但因为这一轮留了一个 `run_in_background` 的后台任务，`~/.claude/sessions/<pid>.json` 的 `status` 一直是 `busy`，直到后台任务结束。`ClaudeCodeActivitySource` 要求 `status == idle`，所以这一轮完全没被检测到（3 分钟内 island 无日志）。没有后台任务的一轮：`busy -> idle` 约 8 秒内被检测到并弹出，正常。

## 期望结果

一轮结束但仍有后台任务在跑时，island 也能判断"这一轮完成了"（例如 `busy` 时也读 transcript，最后一轮以 `turn_duration` 收尾且之后没有新的 user 输入即算完成；需要确认 busy 状态下 transcript 的形态，避免把仍在跑的 turn 误判为完成）。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-27T14:37:23-07:00: new -> in-progress

Scope-check: PLAN § Design / Agents 交互 interface #1（扫描到 agent 完成任务）；用户明确要求修复。

## 2026-09-27T14:39:46-07:00: in-progress -> solved

根因：ClaudeCodeActivitySource 要求 session json 的 status == idle，而一轮结束时仍有后台任务在跑的 session 一直是 busy。修复：status 不再参与判断，完成只看 transcript（turn_duration 收尾、之后无新 user 输入、无中断）；为此 ClaudeTranscriptCache 改为增量解析（按字节 offset 只读追加部分，半行等换行，文件变小则重扫），避免 busy session 每 3 秒全量重读大 transcript（本机最大 852 MB）。验证：新增/调整 5 个测试，make verify 全过；--scan-agents 实测正处在一轮中间的 busy session 不会被误报。
