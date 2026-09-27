---
type: refactor
name: cache-pi-session-scans
title: "pi 每轮 poll 全量重读并解析最新 session 文件，CPU 偏高"
status: solved
created_ts: 2026-09-27T14:48:18-07:00
updated_ts: 2026-09-27T14:50:38-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

`PiActivitySource` 每轮 poll（3s）都把每个项目最新的 session 文件整读一遍再逐行 JSON 解析。本机 17 个项目合计约 6.7 MB，release 构建下单次约 0.3s CPU，并且跑在主线程上。

`remove-closed-agent-title` 之后，只要下拉框里有 pi 的行，`liveSessionIDs` 还会再扫一遍（`newestScans()`），这部分开销翻倍。另外还要加一次 `ps` + `lsof`（约 20ms）。

对比：Claude Code 判活只读几个很小的 json 再调用 `kill(pid, 0)`；Codex 多跑一次 `sqlite3`（约 4ms）。两者都可以忽略。

## 期望结果

- 按 (path, mtime, size) 缓存 `SessionScan`，文件没变就不重读。做法参照 `ClaudeTranscriptCache` 或 `ClaudeDesktopCacheReader`
- `completedTasks` 和 `liveSessionIDs` 共用这份缓存，一轮 poll 最多只解析一次


## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-27T14:49:32-07:00: new -> in-progress

用户在会话中确认要做（「ok」）。Scope-check: 性能修复，属于 remove-closed-agent-title 的后续，落在 PLAN § Agents 交互 interface #1。

## 2026-09-27T14:50:38-07:00: in-progress -> solved

新增 PiScanCache：按 (path, mtime, size) 缓存 SessionScan，completedTasks 与 liveSessionIDs 共用。验证：新增单测覆盖命中 / mtime 变化 / size 变化 / 文件消失；临时基准在真实 ~/.pi（17 个项目，6.7 MB）上，首轮 376ms（debug），之后每轮约 4ms。make verify 全过。遗留：缓存每结束一个 session 留一条很小的条目，不做淘汰。
