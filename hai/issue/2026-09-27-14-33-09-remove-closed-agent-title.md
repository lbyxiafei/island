---
type: bug
name: remove-closed-agent-title
title: "[chore] title should be removed from dropdown when agent task is closed"
status: new
created_ts: 2026-09-27T14:33:09-07:00
updated_ts: 2026-09-27T14:33:09-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

如果 agents 已经关了，比如claude code的terminal 已经closed了，或者codex的对话已经删了，而drop down的agent title又包含这个，那么我们最好能够检测出来，然后从dropdown里面去掉record。
如果做不到自动检测，那么当用户点击已经closed/del的task（从dropdown），能够给出提示，再去掉也可以作为second best option。

## 期望结果

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
