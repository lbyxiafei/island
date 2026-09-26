# 开发与发布流程

island 从提需求到发布的全流程，写给人和 Agent 看。规则的真源是根目录的 `AGENTS.md`；本文只把它和本 repo 的脚本串成一条路，两者冲突时以 `AGENTS.md` 为准。

```
提需求 ──▶ agent 实现 ──▶ 本地验收 ──▶（可选）发布
 issue      worktree +       重启 app       publish.sh
 new        make verify      closed         brew upgrade
            ff-merge + push
            solved
```

## 1. 提需求

最省事的是直接在会话里跟 agent 说，它会建 issue。也可以自己建：

```bash
make issue type=feat slug=short-name title="一句话描述"
```

- type：`feat` `bug` `chore` `style` `refactor` `test` `docs`
- 新建的 issue 状态是 `new`，所有 issue 的总表是 `hai/ISSUES.md`（由工具生成，不要手改）
- agent 判断需求在 `hai/PLAN.md` 的范围内、且不属于 Ask first，会直接推到 `in-progress` 开工；判断不了就停下来问你

## 2. agent 实现

agent 按 `AGENTS.md` / Workflow 走完以下步骤：

1. 在独立 worktree（`../.worktree/island-<slug>`）里开分支，主 checkout 始终停在 master
2. 先写测试再改代码（TDD）。决策逻辑放 `Sources/IslandCore`（测试覆盖 100%），`Sources/Island` 只放 AppKit 装配
3. `make verify` 全部检查通过：build、fmt、lint（分层）、test、coverage（不低于基线）、cycles、issue-check
4. 把改动合成一个 commit，rebase 到 master，再跑一次 `make verify`，然后 `git merge --ff-only` 合回 master 并 push（pre-push 钩子会再跑一次 verify）
5. issue 改成 `solved`，History 里写明做了什么、怎么验证的、还有什么没覆盖

## 3. 本地验收

在主 checkout 里重启 app：

```bash
pkill -x Island; ./scripts/build-app.sh && open build/Island.app
```

- 想看日志就前台运行：`./build/Island.app/Contents/MacOS/Island`
- `build/Island.app` 和 `/Applications`（或 brew 装的）Island 是同一个 bundle id，**不要同时运行两个**
- 本地构建的版本号是 `0.0.0`，这是正常的
- 有 Developer ID 证书时，本地构建也会用它签名，macOS 的自动化授权在多次重新构建之间不会丢

验收结果：

```bash
make issue-status name=short-name status=closed note="验收通过"
```

有问题就直接告诉 agent，它会继续在这个 issue 上修。发现的新问题让 agent 另开 issue。

## 4. 发布

在**已 push 的干净 master** 上执行一条命令：

```bash
./scripts/publish.sh 0.2.0
```

| 步骤 | 做了什么 |
|---|---|
| 检查 | 工作区干净、HEAD 等于 `origin/master`、版本号没发布过，任一条不满足就退出 |
| `release.sh` | 用 Developer ID 签名并公证 app，打 dmg，签名并公证 dmg，staple，最后用 `spctl` 按 Gatekeeper 的标准自检（约 1 分钟） |
| 上传 | dmg 挂到公开仓库 `lbyxiafei/homebrew-tap` 的 Release `island-v0.2.0` |
| cask | 生成 `Casks/island.rb`（版本号 + sha256）并推到 tap |
| tag | 给 island 仓库打 tag `v0.2.0` 并 push |

也可以直接跟 agent 说“发 0.2.0”。发布属于 Ask first，一句话授权就够了。

**版本号**：修 bug 升 patch（`0.1.1`），加功能升 minor（`0.2.0`）。版本号必须比上一版大（`brew upgrade` 靠它识别新版），发布过的版本号不能再用。已发布的版本可以这样查：

```bash
gh release list --repo lbyxiafei/homebrew-tap
```

**前提**（只需配置一次，账号细节记在 dotfiles 的 `macos-release` skill 里）：

- 钥匙串里有 `Developer ID Application` 证书（2027-02-01 到期，续期看那个 skill）
- notarytool 的钥匙串 profile `notary`（可以用 `ISLAND_NOTARY_PROFILE` 换名字）
- `gh` 已登录，账号有 `lbyxiafei/homebrew-tap` 的写权限

**用户侧**：

```bash
brew install --cask lbyxiafei/tap/island     # 首次安装
brew upgrade --cask island                   # 升级
brew uninstall --cask island [--zap]         # 卸载（--zap 连设置一起清掉）
```

为什么 dmg 不放 island 自己的仓库：源码仓库是私有的，brew 下载不了私有仓库的 Release 资产。

## 5. 开发机上装哪一份

- **开发期**：用 `build/Island.app`，随改随重启
- **日常使用**：建议用 brew 装的那份，和用户拿到的是同一份发布产物。从手动安装切换过去：删掉 `/Applications/Island.app`，执行 `brew install --cask lbyxiafei/tap/island`，再在菜单里重新勾选 `Launch at login`
- 两份切换时先 `pkill -x Island`

## 常见卡点

| 现象 | 处理 |
|---|---|
| `git merge --ff-only` 失败 | master 在这期间前进了。回 worktree 执行 `git rebase master` 和 `make verify` 后重试，**不要**改用普通 merge |
| rebase 时 `hai/ISSUES.md` 冲突 | 不要手工合并，跑 `make issue-sync` 后 `git add` 继续 |
| `publish: working tree is not clean` | 先把 master 上的改动提交或 stash |
| `publish: HEAD is not origin/master` | 先 `git push`，或者本地落后了先 `git pull --ff-only` |
| `release: notarytool profile "notary" is missing` | 钥匙串 profile 丢了，按 `macos-release` skill 重建 |
| 公证不是 `Accepted` | 脚本会打印 Apple 的 log，常见原因是签名少了 hardened runtime 或时间戳 |
