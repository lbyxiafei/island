# CONTEXT

面向**接手本 repo、没有任何 context 的新 Agent**。每一项都应当是可直接复制执行的命令。

## Overview

（这个 repo 是什么，一段话。）

## Setup

```bash
# 从零把本地环境跑起来的确切命令
```

## Test

```bash
make verify        # 全部 gate 的唯一入口
```

| gate | 命令（同时写在 `makefile.local`） | 状态 |
|---|---|---|
| build | | |
| fmt | | |
| lint | | |
| test | | |
| coverage | | |
| cycles | | |

- 全量测试：
- 单个测试：
- 覆盖率：`make verify` 里的 coverage gate 会先刷新 `coverage.txt` 再与 `coverage-baseline.txt` 比对；单独刷新基线用 `make coverage`
- 覆盖率排除项声明在：（覆盖率配置文件路径）

## Layout

（主要目录/包各自负责什么，依赖方向。）

```bash
# 循环依赖检查命令
```

## Conventions

（本 repo 特有的、没写进 AGENTS.md 的约定。）

## Gotchas

（已知的坑、反直觉的设计、踩过的雷。）
