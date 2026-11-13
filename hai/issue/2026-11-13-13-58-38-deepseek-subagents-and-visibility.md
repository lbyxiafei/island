---
type: bug
name: deepseek-subagents-and-visibility
title: "DeepSeek: subagent sessions listed as tasks; finishes silently marked read while the app is frontmost"
status: solved
created_ts: 2026-11-13T13:58:38-08:00
updated_ts: 2026-11-13T14:01:35-08:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

用户反馈（2026-11-13）：dsh 最近几次「要么无法定位到准确 session，要么干脆检测不到完成」。

调查（真实 `~/.dsh` 数据，未读 `.credentials.yaml`）：

1. **定位不准**：dsh 给 session 派出的每个 teammate / subagent 都写一个独立的 projcache 文件（无 `session-` 前缀，`subagent.identity` 非空），island 把它们当成独立任务列出——本机 82 个文件里 61 个是子 agent（"You are converting one batch"、"你负责只读审计…" 等）。用户点到的正是子 agent 行，app 里根本没有这个“会话”可去。dsh 只认 `dsh://open`，本来就无法按 session 跳转（`open-url` 源码只比较 `dsh://open`）。
2. **检测不到完成**：`TaskVisibility` 对桌面 app 是“前台即算在看”。dsh 一个窗口里并行跑多个 session，用户停在 dsh 里时：(a) 任何 session 跑完都被直接记为已读、不弹；(b) 之后每轮 poll，所有 dsh 未读行只要 dsh 在前台就被清掉。另外大量子 agent 行也会挤占列表前 10 行。

## 期望结果

- 子 agent 文件不再产生任务
- dsh 在前台时，只有主窗口标题等于该 session 标题才算“在看”；读不到标题（没有辅助功能权限）一律通知

## 备注

- 窗口标题经 AX 读取，`AXIsProcessTrusted()` 为 false 时直接返回 nil，不弹权限框
- Codex / Claude 桌面版仍是“前台即算”，本次不动

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-11-13T14:00:56-08:00: new -> in-progress

Scope-check: PLAN § Scope（已支持的 agent 的完成检测与回到任务）。

## 2026-11-13T14:01:35-08:00: in-progress -> solved

跳过 `subagent.identity` 非空的 projcache 文件（本机 61/82 个是子 agent，`--scan-agents` 复核后只剩主 session）；dsh 在前台时改为比 AX 读到的主窗口标题，读不到（无辅助功能权限）一律通知。新增 3 个测试，`make verify` 全过、覆盖率 100%。窗口标题比对的真机路径（AX）需用户在 dsh 里实际跑一轮验收：若 island 没有辅助功能权限，停在 dsh 里看着一轮跑完也会弹通知。
