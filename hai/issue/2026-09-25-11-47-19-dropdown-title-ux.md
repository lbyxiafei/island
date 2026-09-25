---
type: bug
name: dropdown-title-ux
title: "[ux] title at island dropdown not meeting expectation"
status: new
created_ts: 2026-09-25T11:47:19-07:00
updated_ts: 2026-09-25T11:47:19-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

我们就当前版本统一更新下已知、已经发现的一些 ux 方面的bug：

![alt text](image.png)

1. title 一塌糊涂，我的意思是，如果有title（claude 桌面版有 ai 自己定的title，terminal 有 /name、/rename 出来的title）就用title，没有的话，就用上一个 用户 msg 作为 title 显示，你现在这个dotfiles-9e啥玩意儿？
2. 你的dotfiles-9e出现了太多次，需要去重，同一个session/task/任务 id 就不要堆叠了
3. 观测到新打开 session 的时候也会有 island 的 pop up，这个就不必了，因为我新打开啥内容都没有，何必pop up？我的目的是提醒我有新结束的 ai 内容，新打开是没有的；同时，我自测在claude code按下 esc也会出发island pop up，这个似乎也没有必要，因为这是我主动中断，你看看这两种情况能否检测出来并且filterout

## 期望结果

我期待所有上面的 bugs 都修复。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship
