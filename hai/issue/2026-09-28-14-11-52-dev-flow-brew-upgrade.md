---
type: chore
name: dev-flow-brew-upgrade
title: "开发完成即发布到 brew，本地从 settings 升级验收"
status: solved
created_ts: 2026-09-28T14:11:52-07:00
updated_ts: 2026-09-28T14:20:40-07:00
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

## 2026-09-28T14:16:30-07:00: in-progress -> solved

按 PLAN § 开发指南走通：发布 0.2.0（含 in-app upgrade/feedback）；本机 /Applications/Island.app（手动装的 0.1.0）进废纸篓，改为 brew install 的 0.2.0（spctl: Notarized Developer ID），登录项重新启用；reference/workflow 与 CONTEXT 改成「ship → publish → 从 Settings → Updates 升级验收」；发布 0.2.1（与 0.2.0 代码相同，仅用于这次验证升级链路，是「只动 hai/ 不发版」规则的一次性例外）。待开发者在本机从 Settings → Updates 升级 0.2.0 → 0.2.1，确认重开后显示 up to date，即可 close（同时验收 upgrade-n-feedback 的一键升级）。

## 2026-09-28 补记：0.2.2

按新流程验证时发现 0.2.0 点 `Check Now` 看不到 0.2.1：raw.githubusercontent CDN 滞后 5 分钟以上。修复为 issue `update-check-stale-cdn`，已随 0.2.2 发布。本机的 0.2.0 仍走 raw，CDN 追上后会提示 0.2.2，直接从 0.2.0 升到 0.2.2 即可（跳过 0.2.1 没问题）。
