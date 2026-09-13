---
type: chore
name: brew-distribution
title: "调研 brew install 分发路径（等本地 MVP 走通后再做）"
status: new
created_ts: 2026-09-13T14:20:51-07:00
updated_ts: 2026-09-13T14:20:51-07:00
---

## 背景

`PLAN.md` § Scope / VERSION — POC #2 原文：「这个可否做成 app，并发布，即其他人可以通过 `brew install` 安装？」该条目前被人标注为「已验证」，但**实际只完成了「做成 app」**（ad-hoc 签名、本机可运行），brew 分发从未调研，也从未做过。

2026-09-13 用户明确指示：**发布先不做，等本地 MVP 走通之后再说**。因此本 issue 停在 `new`，仅作为待办的显式记录，不代表已批准开工。

## 期望结果（等开工时）

- 结论：在**不买 Apple Developer 账号**的前提下，brew 分发的可行边界在哪；如果必须买，明确写出成本与卡点
- 可复现的分发路径：version → 构建 → 打包 → 托管 → formula/cask → 用户 `brew install`
- 至少一个真实的端到端验证（换一台机器，或至少清掉 quarantine 属性从零安装）

## 调研要点（尚未验证，勿当结论）

1. **签名与公证是第一道坎**：现在只有 ad-hoc 签名。别人从网上下载的 app 会带 `com.apple.quarantine`，Gatekeeper 会拦。是否必须 Developer ID 签名 + 公证？如果必须，付费账号就是硬成本——这会直接推翻 POC #1「无门槛」的结论适用边界（本地自用无门槛 ≠ 分发无门槛）
2. **formula 还是 cask**：GUI app 走 cask（`brew install --cask`）更常规；cask 支持 `app` stanza 直接投放 `/Applications`
3. **托管方式**：GitHub Releases（要打 tag、要上传资产）vs 自建 tap repo（`homebrew-<name>`）
4. **自动更新**：`brew upgrade` 的语义、版本号策略（`CFBundleShortVersionString` 现在是写死的 `0.1.0`）
5. **与"默认开机自启"的交互**：用户装了就被塞一个登录项是否合适，安装时要不要问
6. **Ask first 提醒**：`publish / release / 打 tag` 属于 AGENTS.md § Boundaries 的 Ask first 条目，开工前需要明确授权

## 备注

- 依赖前置：先有本地 MVP（agent 活动检测 + 悬浮窗真实内容），发布才有意义
- 相关但独立：`launch-at-login`、`menubar-status-item`
