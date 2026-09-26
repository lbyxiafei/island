---
type: chore
name: notification-n-auto-hide
title: "[ux] make notification configurable and auto hide notification when user focus on ai agent panel"
status: new
created_ts: 2026-09-26T14:02:22-07:00
updated_ts: 2026-09-26T14:02:22-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

两个要求：
1. 当 agent 运行完成，如果用户的页面已经是当前的agent的运行界面，就没有必要notify提示了 — 没有提示，但是当用户打开drop down，要在list里能看到这个agent刚刚运行完成 just now，只是没有未读的提示圆点
2. 我们要重新定义下notification

## 期望结果

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
