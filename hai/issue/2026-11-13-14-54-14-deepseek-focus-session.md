---
type: feat
name: deepseek-focus-session
title: "Clicking a DeepSeek task opens that session, not just the app"
status: solved
created_ts: 2026-11-13T14:54:14-08:00
updated_ts: 2026-11-13T14:57:59-08:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

用户（2026-11-13）复现：点 dsh 任务仍定位不到准确 session。0.2.9 去掉了子 agent 行，但 dsh 只注册 `dsh://open`（只把窗口提前），所以点主 session 也只是停在 app 当前打开的 session 上。

## 期望结果

点击 DeepSeek 任务 = 打开窗口 + 在侧栏按下该 session（必要时先切工作区）。没有辅助功能权限时首次点击弹一次系统授权框，之后退化为只打开窗口。

调研：dsh 侧栏 AX 结构见 `hai/reference/agents/README.md` §4b。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-11-13T14:56:49-08:00: new -> in-progress

Scope-check: PLAN § Scope（回到任务）；用户反馈复现。

## 2026-11-13T14:57:59-08:00: in-progress -> solved

点击 DeepSeek 任务改为 dsh://open + AX 按侧栏 session 行（必要时先按工作区行）；首次缺辅助功能权限弹一次系统授权框。新增 --open-task 诊断参数。真机（终端继承辅助功能权限）：同工作区 本地 stories选卡 ↔ 审查其他 agent 的建议、跨工作区 doc-triage「执行 durable kernel 计划任务」、Default workspace「K8s Service 502 排查」都切到了正确 session，窗口标题随之变化。未覆盖：「Show more」折叠的旧 session、无标题 session、先按工作区行的分支（实测时各工作区都展开，没走到）。make verify 全过、覆盖率 100%。
