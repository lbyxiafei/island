---
type: chore
name: open-source-release
title: "以 MIT 协议开源并把仓库转为 public"
status: in-progress
created_ts: 2026-09-27T22:40:10-07:00
updated_ts: 2026-09-27T22:40:38-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

讨论「先卖还是先开源」后，用户决定先开源：核心以 MIT 开源，后续靠 Sponsors / 付费签名版等方式变现。

## 期望结果

- 根目录有 `LICENSE`（MIT），`vscode-extension/package.json` 的 license 同步为 MIT
- README 补上隐私说明与 License 节
- 当前树中不含他人隐私内容
- GitHub 仓库 `lbyxiafei/island` 由 private 转为 public

## 开源前排查

- 全量 git 历史扫描：无 API key / token / 私钥 / 密码；Team ID `C7QG7K23D7` 本就嵌在每个签名二进制里，不算敏感；邮箱已在 commit author 中
- `/Users/binyanli` 路径只暴露用户名，保留
- `hai/issue/image.png` 与 `image-1.png`（同一张图）截到了微信群聊（群名、好友头像、消息预览）：当前树中裁成只剩 island 面板。**旧版本仍在 git 历史里**（Never 第 1 条不允许改写 master 历史），已由用户确认接受
- 代码中无任何网络请求（`URLSession` / `NWConnection` / URL 均无命中）

## Decision

- 2026-09-27，用户（binyan.li）在会话中明确同意：以 MIT 开源；截图只在当前树打码，不处理历史；把 GitHub 仓库 `lbyxiafei/island` 转为 public

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History

## 2026-09-27T22:40:38-07:00: new -> in-progress

用户明确要求执行（见 Decision）；在 worktree 中加 LICENSE、裁剪截图、更新 README。
