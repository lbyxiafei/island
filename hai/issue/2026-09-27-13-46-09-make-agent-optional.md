---
type: feat
name: make-agent-optional
title: "[ux] support agents in optional way"
status: solved
created_ts: 2026-09-27T13:46:09-07:00
updated_ts: 2026-09-27T14:16:55-07:00
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

## 设计

**Interface**：每个 agent 的差异只放两处——

1. `AgentProfile`（`Sources/IslandCore/AgentProfile.swift`，声明式）：`displayName`、`ps` 进程名、图标（app bundle id / SF Symbol）、`scenarios: [AgentScenario]`。原来散在 `AgentKind.displayName` / `processNames` / `AgentIcon` 里的 `switch` 都收进来
2. `AgentActivitySource`（检测）：读落盘、产出 `AgentTask`，并给每个 task 打上 `scenario`（`AgentScenario.id`）

`AgentScenario` = 一个 agent 的一种运行形态，带 `title` / `detection`（怎么检测）/ `jumpBack`（点击后怎样），Settings → Agents 直接拿它渲染成"支持矩阵"。新增 agent = case + profile + source；新增形态 = 一个 `AgentScenario` + source 里的归类规则，UI 不动。

**场景**（归类依据都是落盘字段，不猜进程树）：

| agent | scenario | 依据 |
|---|---|---|
| Claude Code | `terminal` / `editor` / `desktop` / `headless` | session json 的 `entrypoint`：`cli`（或缺省）/ 含 `vscode`·`jetbrains` / 含 `desktop` / 其他。本机只见过 `cli`，其余取值未实测 |
| Claude（桌面聊天） | `chat` | 只有一种 |
| pi | `terminal` | 只有一种 |
| Codex | `app` / `cli` / `exec` | `threads.source`：`vscode`（桌面 app 与 IDE 扩展共用）/ `cli` / `exec`；index 兜底源归 `app` |

**开关**：`AgentScenarioSettings` 只记被关掉的 id（`UserDefaults` `IslandDisabledScenarios`），新场景默认开。scanner 过滤、整 agent 全关则不读 source；关掉时 inbox 立即移除对应行，重新打开不翻旧账。`--scan-agents` 不过滤，打印场景 id 并标 `(off)`。

**Settings tabs**：`General`（快捷键）/ `Appearance`（主题、键盘提示）/ `Notifications`（弹出）/ `Agents`（agent 总开关可 mixed + 每个场景一个开关）。

# History

## 2026-09-27T14:11:29-07:00: new -> in-progress

Scope-check: PLAN § Design / Settings、Agents 交互 interface；用户通过 /goal 明确要求实现。开工：worktree ../.worktree/island-make-agent-optional

## 2026-09-27T14:16:55-07:00: in-progress -> solved

实现 AgentProfile / AgentScenario interface（Claude Code 按 entrypoint、Codex 按 threads.source 归类场景）、AgentScenarioSettings 开关（UserDefaults IslandDisabledScenarios）、scanner 过滤 + inbox 即时移除；设置窗口改为 General / Appearance / Notifications / Agents 四个 tab。验证：新增 AgentScenarioTests，make verify 全过（302 tests，IslandCore 覆盖率 100）；本机 --scan-agents 实测任务正确带上 claude-code.terminal / codex.app / claude-desktop.chat；GUI 里勾选场景后 defaults 落盘、agent 总开关呈 mixed、点总开关可全开。未覆盖：Claude Code 非 cli 的 entrypoint 取值未实测。
