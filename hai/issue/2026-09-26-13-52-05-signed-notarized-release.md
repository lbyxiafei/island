---
type: feat
name: signed-notarized-release
title: "Developer ID 签名 + 公证 + dmg；bundle id 换成 com.commallama.island"
status: solved
created_ts: 2026-09-26T13:52:05-07:00
updated_ts: 2026-09-26T14:01:52-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

陌生用户下载 ad-hoc 签名的 island 会被 Gatekeeper 拦（"无法验证开发者"）。用户有付费开发者账号（team `C7QG7K23D7`），2026-09-25/26 在会话里配好了 Developer ID Application 证书（到期 2027-02-01）和 notarytool 钥匙串 profile `notary`（dotfiles `macos-release` skill / `macos-signing` 脚本记录与恢复）。

## 期望结果

1. `scripts/build-app.sh`：有 Developer ID 证书就用它签（hardened runtime + 时间戳 + `scripts/Island.entitlements` 的 apple-events），否则 ad-hoc
2. `scripts/release.sh`：公证 app 并 staple → 打 dmg → 签名、公证、staple dmg → `spctl` 验证
3. bundle id 换成 `com.commallama.island`，首次启动从 `com.binyanli.island.poc` 迁移设置（`LegacySettings`）

## Decision

- 2026-09-26，用户（binyan.li）在会话中同意（"ok"）：换 bundle id 为 `com.commallama.island`、做签名 + 公证 + dmg 流水线，并在本机验证 Gatekeeper。**不包括**把 dmg 发布到任何外部渠道（GitHub Release / brew），那需要另行确认

Scope-check: 用户明确指令（分发给陌生用户开箱即用）

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-26T14:01:52-07:00: new -> in-progress

开始实现

## 2026-09-26T14:01:52-07:00: in-progress -> solved

签名、公证、dmg、bundle id 迁移全部完成。`scripts/release.sh` 实测约 45 秒，app 与 dmg 两次公证均 Accepted；`spctl` 对带隔离标记的 dmg 和安装后的 app 都判 `accepted, source=Notarized Developer ID`。用户本人从 `~/Downloads` 打开 dmg、在 Finder 拖进「应用程序」、双击启动，确认运行路径是 `/Applications/Island.app`（没有被 App Translocation），快捷键、提示开关已从旧 bundle id 迁移过来，点 cmux 任务能跳到对应 pane（hardened runtime 下 apple-events entitlement 生效）。旧 id 的登录项已关、新 app 的登录项已开。`make verify` 全过（252 个测试，覆盖率 100）。未做：发布 dmg 到外部渠道；从 dmg 里直接运行的情况另开 issue `move-to-applications-prompt`。
