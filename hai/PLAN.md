# PLAN

> 这份文件是本项目 scope 的唯一真源，**只由人修改**。
> Agent 发现它与现实脱节时，向人指出并等待确认，不得自行改写。

## Goal

我们要创建一个 app。该 app 会监视当前电脑的所有 AI AGENT 的运行活动，一旦检测到有 session/task 完成，会在屏幕中央上方 pop up 一个`悬浮窗`，里面是 AGENT 任务完成的总结。

当用户 hover 到浮窗上后，进入交互，浮窗会扩展并展示更多的在过去时间已完成的 sessions/tasks。

如果户在浮窗点击一个 session/task，根据 session/task 运行方式的不同，会有不同的交互：
1. 如果 session/task 是在已经打开的 terminal/ghostty/tmux/cmux/codex 的窗口内执行，那么交互结果是把窗口 pop up 到最前方即可。
2. 如果 session/task 是一个 background/daemon service，那么根据 AGENT 类型，把 session/task 的打开方式贴到 clipboard。例如：`pi --session 01a09864-466e-7336-bc20-c93637035001`。

浮窗在 session/task 完成后，pop up 5秒（可配置）后消失，同时，在任何时候，都有一个 global hot key，可以调出弹窗。

## Non-goal

1. 当前版本我们只考虑 `macOS` 情况，暂时不考虑其他操作系统。

## Scope

### VERSION — POC

1. 当前，我们首先要验证方案是否可行，AI AGENT 的交互部分先暂时不做研究。 —— 已验证可行
    > a. 验看 MAC OS 上做 app 的流程； 
    > b. 如果可行，即没有手续、账号、资格的限制，我们就做一个用 global hot key 调用的悬浮窗（暂定： `cmd + ctr + ,`），悬浮窗调出后自动显示 5 秒后消失。
2. 接下来，帮我验证：这个可否做成app，并发布，即其他人可以通过brew install安装？同时，帮我做一个menubar上的图标 —— 已验证
3. 帮我做一个 menubar 的图标，图标你来定，做好了放到 reference 里面，打开图标后可以有设置，设置目前就设置快捷键，以及退出选项。 —— done
4. 关于开机启动，帮我调研下可否在 mac os 的setting里面进行注册：launch item on 开机这个选项。 —— done


## Design
 
目前处于项目创建阶段，我们先进行几轮讨论，brainstorm、grill-me，等大致情况落实后，我再来回写。

## Key Decisions

| 决策 | 选择 | 被否的备选及理由 | 日期 |
|---|---|---|---|
| | | | |
