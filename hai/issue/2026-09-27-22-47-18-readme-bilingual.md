---
type: docs
name: readme-bilingual
title: "README 中英双语、发布文案与演示 GIF"
status: new
created_ts: 2026-09-27T22:47:18-07:00
updated_ts: 2026-09-27T22:47:18-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

仓库开源后面向海外用户：README 需要英文默认、可切中文；另需演示 GIF 与各平台发布文案（用户在会话中要求）。

## 期望结果

- `README.md` 英文（默认），`README.zh-CN.md` 中文，顶部互相切换；删掉「源码仓库是私有的」这句过时描述
- 演示 GIF 不能暴露本机真实 session：新增 `ISLAND_AGENT_HOME`（`AgentHome`，macOS 上改 `HOME` 无效）+ `scripts/demo.sh` 用假数据跑真 app，再录屏
- `hai/reference/launch/posts.md`：Show HN / Reddit / X 中英 / V2EX 草稿
- GitHub Sponsors 需要用户本人开通（银行 / 税务信息），开通后再加 `.github/FUNDING.yml`

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
