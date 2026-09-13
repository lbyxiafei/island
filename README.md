# <project>

（一句话说清这个项目做什么、给谁用。）

## 快速开始

```bash
make verify      # 全部 gate（build / fmt / lint / test / coverage / cycles / issue-check）
make help        # 所有可用 target
```

## 文档

| 文件 | 内容 | 维护者 |
|---|---|---|
| `hai/PLAN.md` | goal / non-goal / scope / design / key decisions | 人 |
| `hai/CONTEXT.md` | setup / test / layout / conventions / gotchas，面向 AI Agent | Agent |
| `hai/ISSUES.md` | issue 索引，由 `make sync-issue` 生成 | 工具 |

## 开发

（安装步骤、运行方式、测试命令、目录结构。面向使用者，简洁易读。）
