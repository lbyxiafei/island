---
type: feat
name: move-to-applications-prompt
title: "从 dmg 里或被系统迁移（App Translocation）运行时提示移到「应用程序」"
status: solved
created_ts: 2026-09-26T14:01:51-07:00
updated_ts: 2026-09-26T15:58:09-07:00
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

## 2026-09-26T15:55:37-07:00: new -> in-progress

用户在会话中明确要求实现（2026-09-26）。开工：路径分类放 IslandCore，AppKit 侧弹窗 + 复制到 /Applications + 重启。

## 2026-09-26T15:58:09-07:00: in-progress -> solved

实现：`IslandCore/AppLocation.swift` 按路径把 bundle 分成 translocated（含 `/AppTranslocation/`）/ diskImage（`/Volumes/` 开头）/ installed，并给出提示文案、目标路径 `/Applications/<同名>.app`、`xattr -dr com.apple.quarantine` 与"等本 pid 退出再 `open`"的 sh 命令（值走位置参数，不拼进脚本）；8 个测试，IslandCore 覆盖率保持 100%。`Sources/Island/ApplicationsMover.swift` 在 `applicationDidFinishLaunching` 最前面弹 NSAlert（Move to Applications / Not Now），Move 时旧版移废纸篓 → 复制 → 去 quarantine → spawn 重启 → 本实例退出；复制失败弹错误并提示手动拖。

验证：`make verify` 全过；做了一个本地 dmg 挂载后从 `/Volumes/island smoke/Island.app` 前台启动，日志出现 `running from a diskImage location`，截图确认弹框与文案正确。

未覆盖：没有真点 Move（目标写死 `/Applications`，会替换本机正在用的那份），复制 / 去 quarantine / 重启这条链与 translocated 路径需要用下一版正式 dmg 在 Finder 里双击验收；弹框每次启动都会问，没有"不再提示"。
