# 开发与发布流程

island 从提需求到发布的全流程，写给人和 Agent 看。规则的真源是根目录的 `AGENTS.md`；本文只把它和本 repo 的脚本串成一条路，两者冲突时以 `AGENTS.md` 为准。

```
提需求 ──▶ agent 实现 ──▶ agent 发布 ──▶ 本地升级验收
 issue      worktree +       publish.sh     Settings → Updates
 new        make verify      solved         → Upgrade
            ff-merge + push                 closed
```

`hai/PLAN.md` § 开发指南（2026-09-28 起）：**每次开发完成都发布新版本到 brew，开发者从 settings 升级来验收**，顺带每次都把 in-app upgrade 走一遍。

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

## 3. agent 发布

合回 master 并 push 之后，agent 在**已 push 的干净 master** 上发布：

```bash
./scripts/publish.sh 0.2.1
```

| 步骤 | 做了什么 |
|---|---|
| 检查 | 工作区干净、HEAD 等于 `origin/master`、版本号没发布过，任一条不满足就退出 |
| `release.sh` | 用 Developer ID 签名并公证 app，打 dmg，签名并公证 dmg，staple，最后用 `spctl` 按 Gatekeeper 的标准自检（约 1 分钟） |
| 上传 | dmg 挂到公开仓库 `lbyxiafei/homebrew-tap` 的 Release `island-v0.2.1` |
| cask | 生成 `Casks/island.rb`（版本号 + sha256）并推到 tap |
| tag | 给 island 仓库打 tag `v0.2.1` 并 push（pre-push 钩子会再跑一次 `make verify`） |

发布本属于 Ask first；按 PLAN § 开发指南，开发完成后的这一次发布已获授权（台账见 issue `dev-flow-brew-upgrade` § Decision）。**只动 `hai/` 的记账提交不发版**——app 没变，发了也没有可验收的东西。

**版本号**：修 bug 升 patch（`0.2.1`），加功能升 minor（`0.3.0`）。版本号必须比上一版大（cask 和 in-app upgrade 都靠它识别新版），发布过的版本号不能再用。已发布的版本：

```bash
gh release list --repo lbyxiafei/homebrew-tap
```

发布后 issue 改成 `solved`，History 里写上版本号，提醒开发者去升级。

**前提**（只需配置一次，账号细节记在 dotfiles 的 `macos-release` skill 里）：

- 钥匙串里有 `Developer ID Application` 证书（2027-02-01 到期，续期看那个 skill）
- notarytool 的钥匙串 profile `notary`（可以用 `ISLAND_NOTARY_PROFILE` 换名字）
- `gh` 已登录，账号有 `lbyxiafei/homebrew-tap` 的写权限

## 4. 本地升级验收

开发机上跑的是 **brew 装的** island（见第 5 节）。新版发布后：

1. 菜单栏菜单出现 `Update to x.y.z available…`，Settings 的 `Updates` tab 带 🔴。island 启动时和每 6 小时自动检查一次；等不及就点 `Check Now`（raw.githubusercontent 有约 5 分钟缓存）
2. 点 `Upgrade to x.y.z & Relaunch`：island 退出，后台跑 `brew update` + `brew upgrade --cask lbyxiafei/tap/island`，完成后自动重开
3. 重开后 Updates 显示 `island x.y.z is up to date.` 即升级链路正常；失败时 Updates 会提示，日志在 `~/Library/Logs/island-upgrade.log`
4. 验收本次改动，通过就：

```bash
make issue-status name=short-name status=closed note="0.2.1 升级后验收通过"
```

有问题就直接告诉 agent，它会继续在这个 issue 上修（修好再发一个 patch 版）。发现的新问题让 agent 另开 issue。

**agent 自己的中间验证**不用发版：`./scripts/build-app.sh` 打出 `build/Island.app`（版本 `0.0.0`），先 `pkill -x Island` 再前台跑 `./build/Island.app/Contents/MacOS/Island` 看日志，测完 `pkill -x Island; open /Applications/Island.app` 换回 brew 那份。要测更新提示就用 `ISLAND_VERSION=0.0.9 ./scripts/build-app.sh` 打一个“旧版本”。

## 5. 开发机上装哪一份

- **只装 brew 那份**：`brew install --cask lbyxiafei/tap/island`，和用户拿到的是同一份发布产物，也是 in-app upgrade 能工作的前提（它认 `Caskroom/island`）
- 从手动安装切换过去：`pkill -x Island`，把 `/Applications/Island.app` 移到废纸篓，`brew install --cask lbyxiafei/tap/island`，再 `/Applications/Island.app/Contents/MacOS/Island --login-item-enable`（换了 app 登录项会变 `notFound`）
- `build/Island.app` 和 brew 装的是同一个 bundle id，**不要同时运行两个**

**用户侧**：

```bash
brew install --cask lbyxiafei/tap/island     # 首次安装
brew upgrade --cask island                   # 升级（或 Settings → Updates 一键）
brew uninstall --cask island [--zap]         # 卸载（--zap 连设置一起清掉）
```

dmg 放在 tap 仓库而不是 island 仓库，是因为源码仓库当初是私有的（brew 下载不了私有仓库的 Release 资产）；现在已经 public，但 cask 与 in-app upgrade 都认 tap 的地址，不要搬。

## 常见卡点

| 现象 | 处理 |
|---|---|
| `git merge --ff-only` 失败 | master 在这期间前进了。回 worktree 执行 `git rebase master` 和 `make verify` 后重试，**不要**改用普通 merge |
| 升级后还是旧版 / Updates 提示失败 | 看 `~/Library/Logs/island-upgrade.log`；手动 `brew upgrade --cask lbyxiafei/tap/island` 对照 |
| rebase 时 `hai/ISSUES.md` 冲突 | 不要手工合并，跑 `make issue-sync` 后 `git add` 继续 |
| `publish: working tree is not clean` | 先把 master 上的改动提交或 stash |
| `publish: HEAD is not origin/master` | 先 `git push`，或者本地落后了先 `git pull --ff-only` |
| `release: notarytool profile "notary" is missing` | 钥匙串 profile 丢了，按 `macos-release` skill 重建 |
| 公证不是 `Accepted` | 脚本会打印 Apple 的 log，常见原因是签名少了 hardened runtime 或时间戳 |
