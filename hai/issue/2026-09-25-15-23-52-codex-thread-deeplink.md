---
type: feat
name: codex-thread-deeplink
title: "点击 Codex 任务直接打开对应对话（codex://threads/<id>）"
status: solved
created_ts: 2026-09-25T15:23:52-07:00
updated_ts: 2026-09-25T15:24:17-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

ChatGPT.app（bundle id `com.openai.codex`）里的聊天和 Codex 任务是同一种东西，都写进 `~/.codex` 的 thread 表，现有 Codex 数据源已经覆盖（2026-09-25 实测「整理 Hacker News 热榜前五简介」被检测到）。但点击任务只会激活 app，不会定位到对话。

app 注册了 `codex` URL scheme，`app.asar` 里有 `codex://threads/${id}` 的路由。

Scope-check: PLAN § Design / Agents 交互 interface #3（打开到对应窗口/对话）

## 期望结果

Codex 任务带 `deepLink = codex://threads/<thread id>`，点击走 `AgentReopenAction.openURL`，打不开就退回激活 app。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T15:23:52-07:00: new -> in-progress

## 处理结果

`CodexTurnActivitySource` / `CodexIndexActivitySource` 产出的任务都带上 `deepLink = codex://threads/<id>`，沿用 Claude 桌面版引入的 `.openURL` → 激活 app 兜底。命令行这边无法确认链接是否真的跳到对话，待人验收。

## 2026-09-25T15:24:17-07:00: in-progress -> solved
