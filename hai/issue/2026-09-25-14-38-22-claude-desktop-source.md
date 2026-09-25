---
type: feat
name: claude-desktop-source
title: "Claude 桌面版（聊天）完成后不弹 island：尚无数据源"
status: solved
created_ts: 2026-09-25T14:38:22-07:00
updated_ts: 2026-09-25T15:02:31-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

用户反馈：Claude 桌面版里的聊天（如「N8n与其他AI工作流工具的对比」）回复完成后，island 没有弹出，下拉框里也没有这一项。

这不是回归：island 从来没有接入 Claude 桌面版，`AgentActivityScanner.standard` 里只有 Claude Code CLI / pi / Codex 三个数据源（CONTEXT Gotchas 已注明"Claude 桌面版没有可读的任务列表，目前不支持"）。

### 调研（2026-09-25）

- 桌面版聊天记录存在服务端，`~/Library/Application Support/Claude/` 下没有 JSON / sqlite 形式的会话列表
- `claude-code-sessions/`、`local-agent-mode-sessions/` 只有 scheduled-tasks / artifacts 元数据，没有对话
- **唯一的本地痕迹是 claude.ai 前端的 IndexedDB 缓存**（`IndexedDB/https_claude.ai_0.indexeddb.leveldb`）：里面有对话树记录，字段有 `conversationUuid`、`name`（标题，UTF-16）、`conversationUpdatedAt`、`messageCount`、`model`、`created_at` / `updated_at`，还有一个 `claude-notifications` store
- 难点：
  - 格式是 Chromium IndexedDB，也就是 leveldb 外面再套一层 V8 序列化。新写入先落在 `.log`（未压缩），compaction 之后进 `.ldb`（snappy 压缩）；本 repo 零依赖，要自己写 snappy 解压和 V8 值解码
  - 这是前端缓存，只有前端拉取过的对话才会写进去；"回复完成"写入的时机和字段还没验证
  - 格式没有公开文档，桌面版升级就可能失效

## 期望结果

Claude 桌面版聊天回复完成后，island 与 CLI agent 一样弹出，标题取对话 `name`，点击后激活 Claude 桌面版（`com.anthropic.claudefordesktop`，定位到具体对话需再调研）。

## Decision

- 2026-09-25，用户：所有支持的 AI 产品都在 scope 内，桌面版普通聊天也算（PLAN Scope 目前写的是"claude code 桌面版"，措辞需由人更新）
- 2026-09-25，用户：方案 1（IndexedDB）与方案 2（系统通知中心）都做 spike，目标是长期稳定

## Spike 记录

### 方案 1：IndexedDB（2026-09-25，可行性高）

spike 脚本（一次性，不进 repo）：解析 leveldb log/ldb + snappy + V8 反序列化。结论：

- 关键数据不在对象存储的普通记录里，而在 **react-query 持久化缓存**：`IndexedDB/https_claude.ai_0.indexeddb.blob/<db>/<xx>/<blob id>`，是**单个 blob 文件**，每次持久化整体重写
  - 文件头 `ff 11 02` = Blink 包装、snappy 压缩；解压后是 `ff 15 …`（Blink envelope）+ `ff 10 o…`（V8 序列化）
  - 顶层 `{buster: "conversations_v2:…", timestamp, clientState: {queries: [...]}}`
- 可用的 query：
  - `hub_transcript`：当前打开对话的完整消息，最后一条 `sender: assistant` 带 `stop_reason: end_turn`（中断时应不同，待验证）与 `updated_at`
  - `chat_conversation_list`：对话列表（`name`、`updated_at`）
  - `sessions_api_list_sessions`：桌面版 Claude Code 会话，带 `title`、`worker_status`、`status_bucket`（`completed`）、`unread`、`updated_at`
- 零依赖实现需要：snappy 解压（约 40 行）+ V8 反序列化子集（object / array / map / set / string / number / bool / null / date），不需要解析 leveldb 本身（直接挑 blob 目录里最新的文件）
- 风险：格式无公开文档；`hub_transcript` 只覆盖**当前打开**的对话；写盘时机待实测

#### 实测（2026-09-25 14:45–14:49，用户在桌面版发消息 + 中途停止）

| 事件 | 最后一条 assistant | 写盘时刻 | 延迟 |
|---|---|---|---|
| 正常回复完成 | `stop_reason: end_turn`，`updated_at` 21:47:52.937Z | 14:47:58 | 约 5s |
| 回复中途点停止 | `stop_reason: user_canceled`，`updated_at` 21:49:11.167Z | 14:49:16 | 约 5s |

- 每次持久化都会写一个**新的 blob 文件**（id 递增：1944f → 19450 → … → 19458），旧文件会被回收（目录里始终只有少量文件）；取 mtime 最新的那个即可
- 生成过程中持久化的仍是上一轮的最后一条消息，没有半截状态；**完成判据 = 最后一条 assistant 的 `stop_reason == end_turn`，`user_canceled` 过滤掉**（与 CLI 的 esc 规则一致）
- 5 秒延迟加上 3 秒轮询，在可接受范围内

未验证 / 已知缺口：

- `hub_transcript` 只有**当前打开**的对话。回复期间切到别的对话，这条完成信号就看不到了；需要再验证 `chat_conversation_list` 的 `updated_at` 能否兜底
- 桌面版 Claude Code 会话（`sessions_api_list_sessions`）的完成判据（`worker_status` / `status_bucket` / `unread` 的变化）还没实测

### 方案 2：系统通知中心（2026-09-25，受限）

- `~/Library/Group Containers/group.com.apple.usernoted/db2/db` 受 TCC 保护，没有"完全磁盘访问权限"连目录都列不出（`Operation not permitted`）
- 在系统设置里关掉某 app 的通知后，macOS 直接丢弃该 app 的通知，不会写入这个库；在 app 内关掉则根本不会发出。**关掉通知 = 这条路失效**

## 期望结果

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-25T14:56:02-07:00: new -> in-progress

## 处理结果

Scope-check: PLAN § Scope 负责 Agents 范围 #1，以及 ## Decision 中用户对聊天的确认。

- 新增 `ClaudeDesktopActivitySource`：读 IndexedDB blob 目录里最新的文件，用自写的 `Snappy` 解压、`V8Value` 反序列化，取每个 `hub_transcript` 的最后一条消息；`assistant` + `end_turn` 才算完成（`user_canceled` 过滤掉）。标题取 `chat_conversation_list` 的 `name`，没有就用最后一条用户消息
- `AgentKind.claudeDesktop`（显示为 "Claude"，图标用桌面版 app 的图标）
- 点击：`AgentTask.deepLink` = `claude://claude.ai/chat/<uuid>`，reopen 新增 `.openURL` 动作，打不开再激活 app
- 真实数据验证：`--scan-agents` 列出 `claude-desktop  N8n与其他AI工作流工具的对比`；release 构建下缓存变化时解码约 37ms，没变化时约 5ms
- 测试用自带的 V8 / snappy 编码器生成合成 fixture，repo 里没有真实聊天内容

待人验收 / 未覆盖：

- `claude://claude.ai/chat/<uuid>` 是否真的跳到对应对话（从命令行看不到窗口内容）
- 桌面版 Code 标签页：本机没有使用记录，推测走 `~/.claude` 被 Claude Code 数据源覆盖，需要跑一个任务验证
- 回复期间切到别的对话：那个对话的 transcript 可能不再更新，会漏报

## 2026-09-25T15:02:31-07:00: in-progress -> solved
