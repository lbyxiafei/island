---
type: chore
name: brew-distribution
title: "brew install 分发：公开 homebrew-tap + 公证 dmg"
status: solved
created_ts: 2026-09-13T14:20:51-07:00
updated_ts: 2026-09-26T15:46:57-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

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

## Decision

- 2026-09-26，用户（binyan.li）在会话中选定方案 1 并授权「包圆儿」：源码仓库 `lbyxiafei/island` 保持私有；新建**公开**仓库 `lbyxiafei/homebrew-tap`，dmg 作为该仓库的 GitHub Release 资产上传，cask 放在其 `Casks/island.rb`；在 island 仓库打 tag `v<version>`。范围仅限以上，不包括把 island 源码公开、不包括提交官方 homebrew-cask

Scope-check: 用户明确指令（PLAN POC #2「其他人可以通过 brew install 安装」）

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship
- 依赖前置：先有本地 MVP（agent 活动检测 + 悬浮窗真实内容），发布才有意义 —— **前置已具备（2026-09-24 MVP 走通）**
- 相关但独立：`launch-at-login`、`menubar-status-item`

## 调研结果（2026-09-24，只做了本机可验证的部分）

**已验证（本机事实）**

| 项 | 结果 |
|---|---|
| 当前签名 | `codesign -dv` → `flags=0x2(adhoc)`、`TeamIdentifier=not set` |
| Gatekeeper 评估 | `spctl -a -vvv build/Island.app` → **rejected** |
| 版本号 | `scripts/build-app.sh` 写死 `version="0.1.0"` → `CFBundleShortVersionString` |
| 本机工具链 | `brew 7.0.4`、`xcrun notarytool` 均可用 |
| bundle id | `com.binyanli.island.poc`（名字带 `poc`，正式分发前应改成稳定 id） |

**结论（基于以上 + Homebrew 机制）**

1. **硬成本在这里**：ad-hoc 签名的 app `spctl` 直接 rejected。别人拿到它，即使没有 quarantine 属性，macOS 也会拦。要「下载即开」，需要 **Apple Developer Program（99 USD/年）→ Developer ID Application 证书 → `notarytool` 公证 → `stapler staple`**。这是 POC #1「无门槛」的适用边界：**本地自用无门槛 ≠ 对外分发无门槛**。
2. **一个待验证的中间地带**：`brew install --cask` 下载走 `curl`，而 `curl` **不会**加 `com.apple.quarantine`（只有浏览器会）。理论上可能绕过 Gatekeeper 首次拦截，但 macOS 新版本对未公证 app 的策略在收紧，**必须在干净机器上实测**，不能拿本机（已 trust、已运行过）当依据。
3. **formula 还是 cask**：GUI app → **cask**（`brew install --cask island`），`app` stanza 投放到 `/Applications`。
4. **托管**：两种都行 —— GitHub Releases（打 tag + 上传 `.zip`/`.dmg` + `sha256`）或自建 `homebrew-island` tap。推荐 Releases + 官方 cask 或自建 tap。
5. **自动更新**：`brew upgrade` 需要版本号单调递增，`0.1.0` 写死要改成从 tag/环境变量注入。
6. **默认开机自启**：`SMAppService.mainApp` 是用户主动勾的，不是安装即注册，这点 OK；但 cask 安装到一个被别人用的机器上时，仍需在 README 里说清。

**建议的分发路径（待授权后执行）**

```
1. 买 Apple Developer Program → 生成 Developer ID Application 证书
2. build-app.sh 支持注入版本号 + Developer ID 签名 + 公证 + staple
3. 打 tag（v0.1.0）→ GitHub Release 上传 zip + sha256
4. 写 cask formula（version / sha256 / url / app stanza）到自建 tap 或提交 homebrew-cask
5. 干净机器验证：brew install --cask island → 双击能开、登录项可用、快捷键可用
```

**卡点（必须人来定）**

- 是否花 99 USD/年买 Apple Developer Program。不买就只能停在「本机 / 可信机器手动 `xattr -d com.apple.quarantine`」
- `publish / release / 打 tag` 属 AGENTS.md § Boundaries 的 Ask first；未获明确授权前本 issue 停在 `new`

> 2026-09-24 会话：用户授权「把未完成的 issues 都自主处理」，但该授权带有「如果顺利」前提，而本 issue 的下一步是付费 + 公开发布，不属可自主执行范围，故只做到本机可验证的调研。

# History

## 2026-09-26T15:41:48-07:00: new -> open

用户选定方案 1（私有源码 + 公开 homebrew-tap），授权建 tap、打 tag、上传 Release

## 2026-09-26T15:41:48-07:00: open -> in-progress

开始实现：版本号注入、cask 生成、publish 脚本

## 2026-09-26T15:46:57-07:00: in-progress -> solved

已发布 island 0.1.0：`brew install --cask lbyxiafei/tap/island`。2026-09-24 调研里「要不要买开发者账号」「curl 不带 quarantine」两个卡点已被 `signed-notarized-release` 消解。源码仓库保持私有，新建公开的 `lbyxiafei/homebrew-tap`：Release `island-v0.1.0` 挂公证过的 dmg，`Casks/island.rb` 由新脚本 `scripts/publish.sh <version>` 生成（release.sh → 上传 → 改 cask → island 打 tag `v0.1.0`）；版本号改为 `ISLAND_VERSION` 注入（本地构建 0.0.0）。验证：`brew style` / `brew audit --cask --online` 通过；本机真实 `brew install --cask --appdir=<临时目录>`，装出来的 app 带 quarantine，`spctl` 判 `accepted, source=Notarized Developer ID`，版本 0.1.0，可执行；`brew uninstall --cask` 正确退出 app 并删除。`make verify` 全过（273 个测试，覆盖率 100）。未覆盖：没在另一台干净 Mac 上从零装过（本机已信任该证书，首次启动的"来自互联网"确认框没点过）；本机 `/Applications/Island.app` 是手动装的，没交给 brew 管理。
