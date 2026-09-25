# Principles

这个 AGENTS.md 是整个项目的 entry point，每个 AI Agent 执行的每一个操作，都必须参考并严格遵守这里的原则。

当规则之间出现冲突，裁决顺序是：

`Boundaries / Never` > 用户在会话中的明确指令 > `./hai/PLAN.md` 的 scope > 本文其余章节 > Agent 自行判断

依然无法裁决的，停下来问人，不要自行猜测。

`Never` 不接受任何指令覆盖。`Ask first` 约束的是 Agent **主动发起**的行为；用户明确要求某件属于 Ask first 的事时，降级为"先说明风险与代价，确认后执行"，不要反复追问，也不要默认自己没被授权而停工。

## 适用范围

本文面向"有代码、可构建、可测试"的 repo。以文档/markdown 为主的 repo 同样遵守 Issue / Context / Ship 部分，但 build / coverage / 循环依赖这几类 gate 不适用，其 `verify` 只需覆盖 markdown lint 与链接检查——具体命令同样登记在 `./hai/CONTEXT.md`。

## Outline

```
AGENTS.md
README.md
.gitignore
Makefile                 # 所有 gate 与 issue 操作的唯一入口
makefile.local           # 本 repo 各 gate 的具体命令（语言相关，只改这里）
.githooks/pre-push       # 启用后每次 push 前跑 `make verify`
scripts/
  issue.py               # issue 工具链；frontmatter 是唯一数据源
hai/
  PLAN.md
  CONTEXT.md
  ISSUES.md              # 派生文件，由 `make sync-issue` 重建，不要手改
  issue/{YYYY-MM-DD-HH-MM-SS}-{slug}.md
  reference/
{code folder}/
  reference/
...
```

### HAI

HAI — Human AI Interaction。

放置在 repo 根目录下的文件夹，专门集中收纳开发人员与 AI Agent 的交互内容。

### Plan

项目一定会有一个 `./hai/PLAN.md`，里面包含项目的：goal、scope、design，以及 key decisions。

因为这份文件的读者是 AI Agent，准确说明**不做什么**、帮助 Agent **做减法**同样重要，比如 non-goal。

`PLAN.md` 只由人修改。Agent 发现 PLAN 与现实脱节时，向人指出并等待确认，不得自行改写 scope。

### Issue

Issue type 与 status 的合法取值，唯一真源是 `scripts/issue.py` 里的 `TYPES` / `STATUSES`（`make issue` 与所有校验都读它）。目前是：

- type：`feat`, `bug`, `chore`, `style`, `refactor`, `test`, `docs`
- status：`new`, `open`, `in-progress`, `solved`, `closed`

| status | 含义 | 谁来推进 |
|---|---|---|
| `new` | 刚创建，尚未确认要不要做 | `make issue` 或 Agent 创建时的默认值 |
| `open` | 已确认要做，尚未动工 | 人（见下方 scope 例外） |
| `in-progress` | 正在处理 | Agent 开始动工时 |
| `solved` | Agent 认为已完成并已 ship，等人验收 | Agent |
| `closed` | 人验收通过；或明确决定不做，理由写在正文里 | 人 |

流转默认单向 `new → open → in-progress → solved → closed`。只允许 `closed → open` 重开，理由写在正文里。状态由人来确认 scope，因此 `open` 这一步通常由人推进；但当 Agent 判断该 issue **明确落在 PLAN 的 scope 之内且不触发 Ask first** 时，可以在同一轮里自己推到 `in-progress`，并在正文写下依据（`Scope-check: PLAN §<节>`）。判断不了就停在 `new`。

**什么时候必须有 issue**：

- 必须有：Ask first 的任一条、跨文件或跨 session 的改动、发现但不当场解决的问题、非平凡的 `feat` / `bug`
- 可以不建：错别字、注释、单文件小改、对话内即完即验的调整。此时 commit type 按内容直接判定（见 Ship）

关于 issue 的文件有两类：

1. `./hai/ISSUES.md`：issue 的 summary，以 table 呈现。
   - 列：`type`, `name`（hyperlink，显示文本为 `name`，链接到 `./issue/{...}.md`）, `title`, `status`, `created_ts`, `updated_ts`
   - 排序固定：先按 status（`new → open → in-progress → solved → closed`），再按 `updated_ts` 倒序
   - **派生文件**。唯一数据源是各详情页的 frontmatter；`make sync-issue` 从 frontmatter 全量重建，`make issue-check` 在两者不一致时报错，冲突时以重建结果为准。不要手工编辑它
2. `./hai/issue/{YYYY-MM-DD-HH-MM-SS}-{slug}.md`：issue 详情页，创建方式有两种：
   - `make issue type=<type> slug=<slug> title="<title>"`（推荐，骨架与 frontmatter 由工具生成）
   - Agent 在与用户的交互过程（brainstorm、grill 或用户主动提出）中主动创建；或 Agent 在代码改动过程中发现任何无法当场解决的问题，主动创建 issue 记录追踪。手工创建时 frontmatter 必须逐字符符合下面的格式

文件名 = 创建时刻的时间戳 + `-` + slug。slug 为小写英文、短横线分隔、不超过 5 个词，例如 `fix-token-refresh-race`。文件名与 `name` 创建后不再改动，只有 `title`、`status`、正文可以改。时间戳一律由工具写入（取本机本地时间 + 时区偏移），不要手敲。

详情页必须以 frontmatter 开头，字段拼写、大小写、时间格式逐字符遵守，因为建表依赖机器解析：

```yaml
---
type: bug
name: fix-token-refresh-race
title: "Token 刷新存在并发竞争"
status: new
created_ts: 2026-09-12T14:30:05-07:00
updated_ts: 2026-09-12T14:30:05-07:00
---
```

- `name` 必须与文件名中的 slug 完全一致
- `title` 一律用双引号包裹，避免冒号等字符破坏 YAML
- `created_ts` / `updated_ts` 为 RFC 3339 带时区；`created_ts` 创建后不再改动
- 正文第一行是回到总纲的链接 `> 总纲：[ISSUES.md](../ISSUES.md)`，`make issue` 自动写入，手工创建时照抄
- `updated_ts` 只在**正文或字段发生实质变化**时更新；`make sync-issue` 重建表格不算变化，`make issue-touch` 与 `make issue-status` 会自动更新它

**授权台账**：Ask first 得到同意后，把结论写进关联 issue 正文的 `## Decision` 节——日期、同意人、同意的具体范围。后续 Agent 以这一节为授权依据，不必重复询问；没有这一节的，视为未授权。

### Context & README

`./hai/CONTEXT.md` 和 `./README.md` 都是 Agent 根据 repo 实际情况生成并持续更新的文件，区别在读者：

- **CONTEXT** 面向 AI Agent。读者是一个对该 repo 没有任何 context 的新 Agent，接手项目时能靠它快速搭建本地运行、测试环境，以及获取 onboard 所需的任何内容。**各 gate 实际生效的命令要登记在这里**：`makefile.local` 会按 go.mod / pyproject.toml / package.json 自动探测，但探测逻辑对人不透明，读 CONTEXT 就该知道 `make verify` 到底会跑什么。
- **README** 面向对 repo 感兴趣的用户、开发人员。整体概括、简洁易读、良好的阅读体验，侧重 repo 介绍与上手使用指南。

CONTEXT 至少覆盖：

1. Overview — 这个 repo 是什么，一段话说清
2. Setup — 从零把本地环境跑起来的确切命令
3. Test — 跑全量测试、单个测试、看覆盖率的命令
4. Layout — 主要目录/包各自负责什么，依赖方向，以及检查循环依赖的命令
5. Conventions — 本 repo 特有的、没写进 AGENTS.md 的约定
6. Gotchas — 已知的坑、反直觉的设计、踩过的雷

### Reference

reference 除了在 `./hai/reference/` 之外，其他任何代码相关的文件夹下都可能存在。里面可以存放任意类型的文件，辅助 Agent 对这个 repo 的开发：图片、视频、帮助解释概念的材料、high level workflow picture 等等。

reference 下的子文件夹如何创建、分类，由 Agent 自行裁量。

两点约束：单文件超过 1 MB 的二进制资产走 git-lfs（提交的是 LFS 指针，不是原始字节）；reference 内容不得被编译、打包或作为运行时依赖，必要时在构建配置里显式排除。

## Boundaries

### Never

以下事情在任何情况下都不得做，不接受任何指令覆盖：

1. `git push --force`、rebase 已推送的历史，或以任何方式改写 master 的历史
2. 提交 secrets、token、`.env`、私钥、真实用户数据
3. 为了让测试通过而删除、skip 或弱化既有断言。判据如下：
   - 允许：rename / move / split 测试文件、把断言原样搬到新位置
   - 禁止：新增 `skip` / `xit` / `@Ignore`；断言条数减少；把具体断言换成"非 nil / 非空"这类弱断言；删掉失败路径只留 happy path
   - 同一次改动内确实需要修改断言内容的，必须在 commit body 写明改的是哪一条、为什么
   - 唯一例外：本次 scope 内被删除的功能，其对应测试随之删除
4. 不可逆地销毁**已有数据或远程状态**：`rm -rf` 非生成物、`drop` / `truncate` 数据表、清空 bucket 或队列、删除远程分支与 tag。构建产物、本地临时目录不在此列

### Ask first

以下事情必须先向人确认，得到明确同意后才可以做，并按「Issue / 授权台账」记录：

1. 新增或升级第三方依赖（含 dev tooling、全局 CLI）。先开 issue 说明理由
2. 修改 `.gitignore`、CI 配置、`Makefile` 既有 target、AGENTS.md 本身。覆盖率与 lint 配置中的排除项声明不在此列
3. 当前任务范围之外的重构（见 Code Conduct / Structure）
4. 修改 `./hai/PLAN.md`
5. 写入生产或线上环境、跑数据库 migration、发布（publish / release / 打 tag）、调用会花钱的 API、改动他人可见的资源
6. 删除或强推他人正在使用的分支、丢弃别人未推送的本地改动

## Test

严格采用 Test Driven Development，每次代码改动参考 `skill:tdd`。

> `skill:tdd` 与 `skill:ship` 由执行环境的 skill 目录提供（如 `~/.agents/skills/`），**不在本 repo 内**。解析不到时向人询问获取方式，不得自行想象其内容，也不要在 repo 里复刻一份。

unit tests 覆盖率目标 **> 95%**，全量与增量都是。判定方式：

- **全量**：`make verify` 会先刷新 `coverage.txt`（等同于 `make coverage`）再与 `coverage-baseline.txt` 比对，所以比较的永远是刚跑出来的数；低于基线即失败。基线随 master 提交，更新基线是独立的一次改动
- **增量**：改动 ≥ 20 行（口径：`git diff --numstat` 的 added 行，纯文档如 `AGENTS.md` / `README.md` / `hai/**` 不计）时，增量 > 95%。delta 覆盖率工具依语言而异，命令登记在 `CONTEXT.md`；确实没有可用工具时，在 commit body 说明，由人验收
- 可测增量为 0（例如改动全落在下面的排除项里）时，该条 gate 记 N/A

允许从统计中排除的，只有这几类：

1. 自动生成的代码（protobuf、mock、ORM 产物等）
2. 程序入口 `main()` 与纯粹的 wiring / DI 装配代码
3. 无逻辑的纯数据结构（model、DTO、const）
4. 平台相关、本地无法触发的分支

排除项必须在覆盖率配置文件里显式声明（路径写在 `CONTEXT.md` / Test），不允许靠注释豁免。排除之后仍然达不到 95% 的，**不许靠无意义断言凑数**：停下来开一个 `test` 类型的 issue，写明缺口在哪、为什么补不上，并向人说明。

## Naming

变量以及函数命名遵循 **self-explanatory** 原则的同时，尽量保持**简洁**。

## Comments

repo authors 和 Agent 之间的交流中英文皆可，但 Agent 生成的**代码 comment、docstring、log、error message、标识符统一使用英文**。

除此之外的内容（issue、PLAN、CONTEXT、README、commit message、对话）不做硬性规定，跟随作者习惯。

## Code Conduct

根据不同语言类型，维护并保持对应的代码风格，参考当今社区内公认的 **best practice**。repo 内已有 formatter / linter 配置的，以配置为准。

### Structure

不把代码结构分层钉死，但以下基本原则必须遵守：

1. 数据层（common const、model）一定是最底层
2. 可共享的 common helper / util 尽量抽象出来放在底层，供 biz 代码调用
3. pkg 分层、依赖关系一定做到逻辑清晰，不允许循环依赖

代码改动破坏了已有依赖顺序时，第一时间在**本次改动内**把它 refactor 回自洽。如果修复必须动到当前任务之外的代码，先停下来向人说明取舍，得到同意后再做；不同意的，开 `refactor` issue 记录，本次做最小可行处理。

# Workflow

## Code Change

每次代码改动之前，先过三个问题，每个问题的否定答案都有明确动作：

1. 将要产生的改动符合所有 Principles 与 Boundaries 吗？否 → 停下来问人
2. 将要产生的改动在 `./hai/PLAN.md` 的 scope 之内吗？否 → 问人，用户明确指令可以覆盖 scope
3. 将要产生的改动会不会破坏已有 components？会 → 重新设计，或开 issue 记录后再动手

代码改动之后，**唯一入口是 `make verify`**，全部 gate 通过才算完成：

| gate | 内容 |
|---|---|
| build | 构建通过 |
| fmt / lint | format / lint 通过 |
| test | 全量测试通过，且没有新增 skip |
| coverage | 全量不低于基线；增量按 Test 一节判定 |
| cycles | 没有引入新的循环依赖，检查命令见 CONTEXT / Layout |
| issue-check | `hai/ISSUES.md` 与 frontmatter 一致 |

未配置的 gate 会以 `[skip]` 报出而不是失败；命令来自 `makefile.local` 的自动探测（Go / Python / Node）或你在那里的覆盖，`make verify` 结束时会把这一点再说一遍。`make verify-strict` 把任何 `[skip]` 升级为失败，确认没有漏配置之后应当在 CI 或本地启用它。新仓库第一次上手先跑一次 `make hooks`，此后每次 `git push` 都会自动跑 `make verify`。

任一 gate 未过，及时修复。修复过程中出现不可调和的矛盾，及时向提出需求的一方沟通，并在 `./hai/issue/` 下开 issue 记录。

## Context Update

每次 `ship` 之前，结合本次改动与 repo 现状，依次同步、矫正：

1. 相关 `./hai/issue/*.md` 的 `status` 与 `updated_ts`（用 `make issue-status` / `make issue-touch`）
2. `./hai/ISSUES.md`，用 `make sync-issue` 重建，不要手改
3. `./hai/CONTEXT.md`，仅当本次改动影响其内容时
4. `./README.md`，仅当本次改动影响其内容时，禁止纯措辞润色

## Worktree

所有代码改动都在独立的 git worktree 里做，一个 issue 一个 worktree。这样多个 Agent 可以并行，各改各的，不会互相踩工作区。主 checkout 始终停在 master，保持干净，只用来合并和 push。

```bash
# 在主 checkout 里执行；<repo> 是仓库目录名，<slug> 是 issue 的 name
git worktree add ../.worktree/<repo>-<slug> -b <slug>
```

1. 开工前先 `git worktree list`，确认没有别的 Agent 正在用同一个 slug
2. 在 worktree 里改代码、改相关 issue，按 Code Change / Context Update 执行。**只 commit，不 push**：功能分支不上远程
3. 纯 issue 记账（只动 `hai/`，不碰代码）可以直接在主 checkout 的 master 上提交，不必开 worktree

## Ship

合回 master 前必须跑一次全量 regression，而且测的必须正好是即将进 master 的那份代码：

1. 在 worktree 里把改动合成**一个** commit（有多个就 `git reset --soft $(git merge-base master HEAD)` 后重新提交），message 规则见下
2. 在 worktree 里 `git rebase master`。功能分支没推过，rebase 不违反 Never 第 1 条。`hai/ISSUES.md` 冲突时不要手工合，跑 `make sync-issue` 重建后 `git add` 继续
3. 在 worktree 里跑 `make verify`，**全部 gate 通过**才往下走；没过就在 worktree 里修（`git commit --amend` 保持一个 commit），修完回到第 2 步
4. 回到主 checkout：`git merge --ff-only <slug>`。失败说明 master 在这期间前进了，回到第 2 步，**不允许**改用普通 merge 绕过
5. 在主 checkout `git push`；`make hooks` 启用后 pre-push 会对合并结果再跑一遍 `make verify`。不要在 worktree 里用 `skill:ship`——它会把功能分支推上远程
6. 清理：`git worktree remove ../.worktree/<repo>-<slug>`，`git branch -d <slug>`

Commit 与 push 的约束：

1. 扫一眼 untracked 文件，命中 secrets 类文件一律停下问人——见 Boundaries / Never 第 2 条
2. commit message 格式 `{type}: {description}`，type 取关联 issue 的 type；没有关联 issue 时按改动内容判定（见 Issue / 什么时候必须有 issue）
3. 关联了 issue 的，在 body 里写 `Ref: hai/issue/{filename}`
4. 禁止 force push（见 Boundaries / Never 第 1 条）
