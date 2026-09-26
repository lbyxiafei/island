---
type: feat
name: move-to-applications-prompt
title: "从 dmg 里或被系统迁移（App Translocation）运行时提示移到「应用程序」"
status: new
created_ts: 2026-09-26T14:01:51-07:00
updated_ts: 2026-09-26T14:01:51-07:00
---

> 总纲：[ISSUES.md](../ISSUES.md)

## 背景

2026-09-26 做 `signed-notarized-release` 的安装实测时发现：带隔离标记的 app 只要不是用户在 Finder 里亲手拖进「应用程序」，macOS 就会把它 App Translocation 到 `/private/var/folders/.../AppTranslocation/<随机>/d/Island.app` 只读运行（用 `ditto` 拷、用脚本让 Finder duplicate 都会触发）。陌生用户最常见的情况是**直接在 dmg 窗口里双击 Island**，同样会这样。

后果：登录项（`SMAppService.mainApp`）会记下随机路径或 dmg 卷上的路径，下次登录就启动失败；dmg 推出后 app 直接没了。

## 期望结果

启动时发现自己跑在 AppTranslocation 路径或 `/Volumes/` 下，弹一个说明：「请把 island 拖到应用程序文件夹再打开」，并提供一键「移到应用程序并重新打开」（常见做法：复制到 `/Applications`、去掉 quarantine 的迁移标记由系统处理、重新 `open` 后退出当前实例）。判定逻辑（路径分类）放 IslandCore 并测试。

## 备注

- 全程在独立 worktree（`../.worktree/<repo>-<slug>`）中完成，合回 master 前 `make verify` 全过，流程见 AGENTS.md / Workflow / Worktree 与 Ship

# History
