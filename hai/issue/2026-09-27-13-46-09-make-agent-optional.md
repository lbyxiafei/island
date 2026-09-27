---
type: feat
name: make-agent-optional
title: "[ux] support agents in optional way"
status: new
created_ts: 2026-09-27T13:46:09-07:00
updated_ts: 2026-09-27T13:46:09-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

现在有一个情况，就是我们无法保证支持全部的 agents 检测情况，因此，我们需要在settings里面单独辟一个tab：agents（顺道把setting分一下类）。
这样我们就会对当前的功能支持scope有一个具像化的了解，并且，在使用的时候，如果发现异常，也可以通过对比setting观察是否符合预期。
同时，这些agent支持的scenario，都可以做成一个toggle on/off的情景。

这样的话，务必从 interface 的角度去重新审视，请把每一个支持的 agents 的各种情况都隔离在interface之后，仔细设计interface，以应对当前的variance，以及未来的可能。

## 期望结果

我希望看到 settings 有多个 tabs，把现在已有的放到合适位置。同时，tab：agents 按照需求来。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
