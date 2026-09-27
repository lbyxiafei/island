---
type: bug
name: remove-closed-agent-title
title: "[chore] title should be removed from dropdown when agent task is closed"
status: solved
created_ts: 2026-09-27T14:33:09-07:00
updated_ts: 2026-09-27T14:45:53-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

如果 agents 已经关了，比如claude code的terminal 已经closed了，或者codex的对话已经删了，而drop down的agent title又包含这个，那么我们最好能够检测出来，然后从dropdown里面去掉record。
如果做不到自动检测，那么当用户点击已经closed/del的task（从dropdown），能够给出提示，再去掉也可以作为second best option。

## 期望结果

下拉框（悬浮窗 / 菜单）里，session 已经不存在的行自动消失，不需要用户点。

## 设计

- 每个 `AgentActivitySource` 可选实现 `liveSessionIDs(processes:)`：返回仍开着的 session id，nil 表示无法判断（默认）
  - Claude Code：`~/.claude/sessions/<pid>.json` 存在且 pid 存活（`kill(pid, 0)`）；任一文件解码失败 → nil，避免半写文件导致误删
  - Codex：`select id from threads where archived = 0`（Codex 删除对话 = archive）；sqlite 读不了 → nil
  - pi：没有 pid，用 `ps` + `lsof` 找 `pi` 进程的 cwd，匹配各项目最新 session 的 cwd
  - Claude 桌面版：无法判断，行保留（聊天存在服务端，本地 IndexedDB 只缓存近期打开的，缺席不代表被删）
- `AgentMonitor.pruneClosed` 在每轮 poll 开头运行，只问 inbox 里有行的 agent；点击行时也先跑一次，已关闭的行直接移除、不再去聚焦（覆盖两次 poll 之间的窗口，即 second best 方案）
- 移除的 run 仍留在 `known`，不会被同一轮重新加回；session 被 resume 后跑完新一轮会重新出现
- 调试：`Island --live-sessions`

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-27T14:42:05-07:00: new -> in-progress

Scope-check: PLAN § Island 下拉框 UX（用户明确要求实现）。开工：按 agent 探测 session 是否仍存在，消失的从下拉框移除。

## 2026-09-27T14:45:53-07:00: in-progress -> solved

各 source 新增 liveSessionIDs：Claude Code 看 sessions/<pid>.json + pid 存活，Codex 看 threads.archived = 0，pi 看 pi 进程 cwd；Claude 桌面版无法判断、保留。AgentMonitor 每轮 poll 与点击前 pruneClosed，移除已关闭 session 的行。验证：新增单测覆盖三类 source 与 scanner 聚合，make verify 全过（覆盖率 100%）；真机 --live-sessions 输出与 ps / sqlite 一致。未覆盖：Claude 桌面版删除聊天无法检测；未做 UI 实测（关掉一个 claude 终端看行消失）。
