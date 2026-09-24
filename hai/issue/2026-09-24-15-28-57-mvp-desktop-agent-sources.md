---
type: chore
name: mvp-desktop-agent-sources
title: "MVP: 调研 Codex 桌面版与 Claude 桌面版的活动数据源"
status: new
created_ts: 2026-09-24T15:28:57-07:00
updated_ts: 2026-09-24T15:34:10-07:00
---

Scope-check: PLAN § Scope / 负责 Agents 范围（明确列出「claude code 桌面版」「codex 桌面版」）。

## 已知

- **Codex 桌面版**：和 CLI 共用 `~/.codex`。CLI 的线程会写进 `~/.codex/session_index.jsonl`，但实测该 index 停在 2026-09-11，而 `ChatGPT.app`（`codex app-server`）当天仍在跑 —— 桌面版的活动很可能落在 `state_5.sqlite` / `thread_history_1.sqlite` / `queue_1.sqlite`，`~/.codex/.codex-global-state.json` 里还有 `electron-thread-read-state-v1`、`thread-project-assignments` 等 UI 状态
- **Claude 桌面版**：`~/Library/Application Support/Claude/` 是 Electron，只看到 `IndexedDB/`、`Local Storage/`、`Session Storage/`，没有可读的任务列表。最坏情况只能靠 UI 抓取 / computer use

## 期望结果

- 确定 Codex 桌面版「一轮 turn 完成」在 sqlite 里怎么体现（表名、字段、时间戳），能否像 CLI 那样拿到 id + title + 时间
- 确定 Claude 桌面版有没有任何本地可读的任务状态；没有的话给出建议方案（computer use / 放弃 vs 只检测进程存在）
- 结论回写 `hai/reference/agents/README.md`，并决定是否为两者各开一个实现 issue

## 备注

- 只读调研，不改代码；sqlite 用 `sqlite3` 只读打开
- 注意 `~/.codex` 下的库有 WAL，别在 agent 运行时做写操作（AGENTS.md Boundaries / Never 第 4 条）
