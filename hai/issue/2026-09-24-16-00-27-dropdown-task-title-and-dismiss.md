---
type: feat
name: dropdown-task-title-and-dismiss
title: "下拉框 task 标题兜底 last msg，点击后随即消失"
status: solved
created_ts: 2026-09-24T16:00:27-07:00
updated_ts: 2026-09-24T16:04:00-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

Scope-check: PLAN § Design / Island 下拉框 UX 第 1、2 条。授权来源：用户会话指令「更新了下拉框ux新需求，帮忙实现下」。PLAN 里该节由人填写，属 MVP 范围内的 UI 细化。

## 需求（PLAN 原文）

1. 下拉框的 task，有 title 显示 title，没有 title 显示 last msg
2. 点击下拉框的 title 后，下拉框随即消失 / toggle off

## 实现

### 1. 标题：title → last msg → 目录名

新增 `IslandCore/TaskTitle.resolve(title:lastMessage:cwd:)`，三个来源统一走它（顺带统一截断到 72 字、压缩空白）：

- **Claude Code**：`sessions/<pid>.json` 的 `name` 为空时，去 `~/.claude/projects/*/<sessionId>.jsonl` 找 transcript，取**最后一条 assistant 的文本**。按 sessionId 反查文件（Claude 的 cwd-slug 编码没文档，不猜）。只有 name 为空才读文件，正常情况零额外 I/O。
- **pi**：`scan` 现在同时记录第一条 user 文本（title）和**最后一条 assistant 文本**（lastMessage）。
- **Codex**：turn 查询里加了子查询，取该 thread 最后一条 `item_type = 'agentMessage'` 的 `json_extract(item_json, '$.text')`。

三者顺序都是 `title → lastMessage → cwd basename`。

### 2. 点击后收起

`AppDelegate.selectTask` 在标记已读、刷新 UI 之后调用 `hideOverlay(reason:)`，先收起悬浮窗再去 focus/跳转（否则抢焦点那一刻它还会闪一下）。菜单栏那份列表本来就点完即合，无需改。

## 验证

- 单元测试：新增 `TaskTitleTests`、`ClaudeTranscriptTests`（按 id 找 transcript / 取最后一条 assistant / 无 assistant / 文件不存在），并补齐 pi 的 lastMessage 与 codex 的 `last_message` 兑底；135 个测试全绿，覆盖率维持 100
- 真机 `--scan-agents`：Claude（`island-6d`）、Codex（`评估 AI 玩游戏与速通可行性`）标题不变，`json_extract` 子查询在 attach 的库上可用
- 未验证：点击后收起只能人工体验（无头环境点不了）。**请验收时点一下悬浮窗里的任务**，确认它随即消失

## 备注

- 这里把 PLAN 的「下拉框」理解为**悬浮窗那个列表**（菜单栏下拉框点完本来就会消失）。如果其实指的是菜单栏，那条已经天然满足，无需改动。
