---
type: chore
name: dev-flow-brew-upgrade
title: "开发完成即发布到 brew，本地从 settings 升级验收"
status: in-progress
created_ts: 2026-09-28T14:11:52-07:00
updated_ts: 2026-09-28T14:14:33-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

`hai/PLAN.md` § 开发指南（commit `24777eb`）改了开发行为：每次开发完成都发布新版本到 `lbyxiafei/tap/island`，本地开发者从 Settings → Updates 手动升级，顺道验证 upgrade 功能（issue `upgrade-n-feedback`）。

## 期望结果

1. 发布 0.2.0（含 in-app upgrade / feedback）
2. 本机从手动安装的 0.1.0 切到 brew 安装的 0.2.0（旧 app 进废纸篓）
3. `hai/reference/workflow/README.md` 与 `hai/CONTEXT.md` 改成新流程：本地验收 = 发布 + 从 settings 升级
4. 提交后发布 0.2.1，开发者在本机从 Settings → Updates 一键升级 0.2.0 → 0.2.1，验证升级链路

## Decision

- 2026-09-28，binyan.li 在会话中同意：发布 0.2.0 与 0.2.1 到公开 tap（Ask first #5），并把本机 `/Applications/Island.app` 换成 brew 安装。之后按 PLAN § 开发指南，每次开发完成的发布视为已授权，版本号按 reference/workflow 的规则（功能升 minor、修复升 patch）。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-28T14:12:01-07:00: new -> in-progress

用户在会话中要求按 PLAN § 开发指南实践；授权见 Decision。
