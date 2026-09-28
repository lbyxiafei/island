---
type: feat
name: upgrade-n-feedback
title: "[feat] enable in-app upgrade and feedback channels"
status: new
created_ts: 2026-09-28T10:36:27-07:00
updated_ts: 2026-09-28T10:36:27-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

我希望在 in-app 的setting处增加 feedback 和 upgrade 的选项。

## 期望结果

feedback可以是用户提交一个问题，可以是一段话，然后直接发到我邮箱，如果可能，如果不可能帮我看看市面上的最简实用option

upgrade就是我homebrew版本升级，用户可以点击upgrade跟着**一键**升级，不用操心自己升级。然后同时可以检测有版本更新，然后提示用户，比如settings打开的时候，升级的所在tab上面有个红点， 引导用户去按。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
