---
type: chore
name: notification-n-auto-hide
title: "[ux] make notification configurable and auto hide notification when user focus on ai agent panel"
status: new
created_ts: 2026-09-26T14:02:22-07:00
updated_ts: 2026-09-26T14:02:22-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

两个要求：
1. 当 agent 运行完成，如果用户的页面已经是当前的agent的运行界面，就没有必要notify提示了 — 没有提示，但是当用户打开drop down，要在list里能看到这个agent刚刚运行完成 just now，只是没有未读的提示圆点。这里有一个更加 advanced 的要求：如果用户没有通过点击 island pop up msg的方式自己切换窗口回到了刚完成的 agent window，island“最好”能够检测出来并且把menu bar上图标的msg减一，同时消掉未读圆圈。
2. 我们要重新定义下 island 的 notification 的行为，并且收录到 settings，详情看下一章。

## 期望结果

我们定义如下 notification 的种类：
1. menu bar 的图标msg+1，这个是default 的，应该永远都是保持这样，setting也改不了
2. 在island pop up处进行即时展示（x秒，x默认5秒，在settings里有一个专门的设置），当鼠标hover到这个即时pop up的时候，就停止计时，即不消失。这一个 notification setting是可以toggle on/off 在settting 配置里。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
