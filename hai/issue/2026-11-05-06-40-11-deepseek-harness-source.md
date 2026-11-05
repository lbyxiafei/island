---
type: feat
name: deepseek-harness-source
title: "支持 DeepSeek Harness 桌面版"
status: solved
created_ts: 2026-11-05T06:40:11-08:00
updated_ts: 2026-11-05T06:42:58-08:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

2026-11-05 用户要求支持本机正在跑的 DeepSeek Harness（`/Applications/DeepSeek Harness.app`，bundle id `com.deepseek.dsh`，0.2.1-rc.2，Electron）。PLAN § 负责 Agents 范围 里没有列出它，属于**用户明确指令覆盖 scope**（AGENTS.md 裁决顺序）；PLAN 本身未改，需要的话由人补上。

调研结论写在 [`hai/reference/agents/README.md` § 4b](../reference/agents/README.md)。要点：完成信号取 `~/.dsh/storages/session_projcache/sessions/session-<uuid>.json` 的 `turnBoundary`（纯 JSON，运行中持续重写），不读 zstd 压缩的事件流（避免新增依赖）；app 只注册 `dsh://open`，没有按 session 的链接。

## 期望结果

- 新 agent `deepseek`，单一场景 `deepseek.app`，Settings → Agents 里可开关
- 一轮跑完 → 计数 + 弹窗；标题 `title` → 首条 prompt → 目录名
- 点击 → `dsh://open` 把 DeepSeek Harness 提到前面（做不到精确到 session）

## 验证

- 新增 `DeepSeekActivityTests`（7 个测试），全量 373 个测试通过，没有改动既有断言
- 新构建 `--scan-agents` 读真实 `~/.dsh`：5 个 session 中 4 个已完成的全部列出，标题 / 目录正确；正在跑的 doc-triage session 跑完后（14:41:19Z）立即出现

## 未覆盖

- 用户中途停止的一轮也会被算作完成（缓存里没有 `turn/end` 的 reason）
- 无法判断 session 是否已删除，行不会自动从下拉框消失

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-11-05T06:42:58-08:00: new -> in-progress

用户明确要求（覆盖 PLAN scope）；调研完成，按 projcache JSON 实现

## 2026-11-05T06:42:58-08:00: in-progress -> solved

新增 deepseek agent（DeepSeekActivitySource + 场景 deepseek.app），点击用 dsh://open 唤起 app。7 个新测试，真实 ~/.dsh 扫描结果正确。随 0.2.7 发布。未覆盖：中途停止也算完成；删除的 session 不会自动消失。
