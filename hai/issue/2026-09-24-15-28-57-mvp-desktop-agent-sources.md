---
type: chore
name: mvp-desktop-agent-sources
title: "MVP: 调研 Codex 桌面版与 Claude 桌面版的活动数据源"
status: solved
created_ts: 2026-09-24T15:28:57-07:00
updated_ts: 2026-09-24T15:48:00-07:00
---

Scope-check: PLAN § Scope / 负责 Agents 范围（明确列出「claude code 桌面版」「codex 桌面版」）。授权来源：用户会话指令「把未完成的 issues 都自主处理了」。

## 结论：Codex 桌面版有解，Claude 桌面版没有

### Codex（CLI + 桌面共用）

- **权威完成信号**：`~/.codex/thread_history_1.sqlite` → `thread_turns.status == 'completed'`，带 `completed_at`（秒）。实测取值只有 `completed`(857) 与 `interrupted`(2)
- **任务元数据**：`~/.codex/state_5.sqlite` → `threads`：`id` / `name`（短标题）/ `title`（首条 user message）/ `cwd` / `updated_at_ms` / `source` / `archived`
- 两个库靠 `attach database … as history` 连起来，`sqlite3 -json` 直出 JSON（避免手动处理分隔符）
- 桌面与 CLI 写同一张表，只是 `threads.source` 不同（本机样本全是 `vscode`）
- **坑**：这两个库用 `sqlite3 -readonly` 打不开（`unable to open database file (14)`，WAL 无法在只读连接下恢复）；去掉 `-readonly`、只跑 SELECT 即可

### Claude 桌面版

`~/Library/Application Support/Claude/` 是 Electron，只有 `IndexedDB/` / `Local Storage/` / `Session Storage/`，**没有可读的任务列表**。要支持只能走 computer use / UI 抓取。当前不做。

## 实现（Codex 部分已落地）

- 新增 `IslandCore/CodexTurns.swift`：
  - `SQLiteQuerying` 协议 + `NoSQLiteQuerying`（核心层不 spawn 进程）
  - `CodexTurnActivitySource`：按上面的 SQL 查 turn 历史，`name → title → cwd basename` 选标题
  - `CodexIndexActivitySource`：原来的 `session_index.jsonl` 解析改名为它，作为 sqlite 读不到时的兑底
  - `CodexActivitySource`：组合，turn 历史优先
- `Sources/Island/ProcessSQLite.swift`：`/usr/bin/sqlite3 -json` 包装（macOS 自带，无新依赖）
- `AgentActivityScanner.standard(home:sqlite:)`：app 传真实 runner，测试传 stub

## 验证

- 单元测试：turn JSON 解析（含 `name: null`、空字符串、缺字段、非对象元素）、runner 注入与 SQL 内容、turns 优先 / index 兑底，共 9 个 codex 测试
- 真机 `--scan-agents`：codex 行现在来自 sqlite（带 `cwd` 与 `name` 标题），与 `sqlite3` 直查一致
- 未验证：**桌面版新线程**——截至调研，`threads` 表最新也是 2026-09-11 且 `source='vscode'`（本机最近没用桌面版），所以桌面路径只能用同表推断。等你实际用一次 Codex 桌面版，`--scan-agents` 应能看到 `source='app'` 的线程

## 后续

- Claude 桌面版：不建议做，除非接受 computer use
- Codex 的 sqlite 文件名带版本号（`state_5` / `thread_history_1`），codex 升级可能改号；真改了会先看到 codex 检测变空（那时回退到 session_index 兑底仍工作）
