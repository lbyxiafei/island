---
type: bug
name: update-check-stale-cdn
title: "发版后检查更新仍报 up to date：raw.githubusercontent CDN 缓存滞后"
status: solved
created_ts: 2026-09-28T14:17:37-07:00
updated_ts: 2026-09-28T14:18:54-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

发布 0.2.1 后，brew 装的 0.2.0 在 Settings → Updates 点 `Check Now` 一直显示 `island 0.2.0 is up to date.`。

根因：`UpdateSource.caskURL` 用的是 `raw.githubusercontent.com`（Fastly，`cache-control: max-age=300`）。实测发布 5 分钟以上仍有节点返回旧 cask（`x-cache: HIT`、`source-age: 225`，内容仍是 0.2.0），同一时刻 contents API 已是 0.2.1。与 `URLRequest.cachePolicy` 无关（本地缓存已忽略），是 CDN 侧滞后。

## 期望结果

检查更新改走 `https://api.github.com/repos/lbyxiafei/homebrew-tap/contents/Casks/island.rb`，带 `Accept: application/vnd.github.raw`（直接返回文件内容；`max-age=60`；未认证 60 次/小时/IP，island 每 6 小时 + 打开 settings 时才查，够用）。contents API 读的是 tap 的 git 内容，和 `brew update` 看到的一致。

已发布的 0.2.0 / 0.2.1 仍走 raw，只是晚几分钟看到新版，不影响升级本身。

Scope-check: 修 issue `upgrade-n-feedback` 引入的缺陷，用户在会话中要求实践 PLAN § 开发指南（发版 + 升级验收），修复属于同一范围。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-28T14:17:46-07:00: new -> in-progress

根因已定位，见正文。

## 2026-09-28T14:18:54-07:00: in-progress -> solved

UpdateSource.caskURL 改为 GitHub contents API，新增 UpdateSource.caskRequest（Accept: application/vnd.github.raw、忽略本地缓存、15s 超时），UpdateController 直接用它。验证：新测试先红后绿；ISLAND_VERSION=0.2.0 构建实测，在 raw CDN 仍返回 0.2.0 时立即检测到 available(0.2.1)；make verify 全过。随 0.2.2 发布。已发布的 0.2.0/0.2.1 仍走 raw，只是晚几分钟看到新版。
