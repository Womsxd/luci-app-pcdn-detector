# Contributing to luci-app-pcdn-detector

Thanks for taking the time to contribute! This document explains how to report
issues, propose changes, and get your work merged. It applies to everyone —
please read it before opening a pull request (PR).

[简体中文](#为本项目做出贡献)

---

## Contributor License Agreement (required)

Before your contribution can be accepted, you must agree to the project's
[Contributor License Agreement](CLA.md).

**By opening a pull request, you confirm that you have read the CLA and agree
to its terms for your present and future contributions.** You do not need to
sign any separate document. A PR that does not satisfy the CLA requirement will
not be merged.

In short, the CLA lets the maintainers and administrators of the project — now
and in the future — relicense your contributions under any
[OSI-approved license](https://opensource.org/licenses). Relicensing your
contribution under a non-OSI (for example proprietary) license requires your
separate explicit authorization.

## Developer Certificate of Origin (required)

Every commit in your pull request must be signed off to certify the
[Developer Certificate of Origin](https://developercertificate.org/) (DCO).
Add a `Signed-off-by` line with your name (the name or handle you go by) and an
email address as the last line of the commit message:

```
fix(view): 修复日志页暂停后仍刷新

Signed-off-by: Jane Doe <jane@example.com>
```

`git commit -s` adds the line automatically, using the name and email from your
Git configuration (set them with `git config user.name` and
`git config user.email`). To add the line to commits that are missing it, run:
`git rebase --signoff main`.

The sign-off only needs to identify you — a name or handle together with an
email address is enough; it does not have to be your legal name. By signing
off, you certify that you wrote the contribution or otherwise have the right to
submit it under the project's license. The DCO is a per-commit confirmation and
is required **in addition to** the CLA above; a PR whose commits are not signed
off will not be merged.

## Reporting issues

- Search the existing issues first to avoid duplicates.
- For a bug, include: the LuCI package version, the OpenWrt / distribution
  version and CPU architecture (`cat /proc/cpuinfo`, `opkg print-architecture`
  or `apk --print-arch`), the `pcdn-detect` version (`pcdn-detect -v`), the
  browser you used, and clear steps to reproduce.
- Include the relevant uhttpd / LuCI error output and `logread` lines when they
  matter. **Redact MAC addresses and public IP addresses** before pasting logs:
  the overview page shows per-device statistics.
- For a feature request, describe the use case and the behaviour you expect.
- Do not report security issues in a public issue — contact the maintainer
  privately instead.

## Development setup

This package contains only Lua, HTML and shell code, so there is no compile
step while iterating. Copy `luasrc` and `root` to the router and clear the LuCI
cache; the full procedure lives in
[docs/install.md](docs/install.md#手动安装到路由器). The short version:

```bash
git clone https://cnb.cool/womsxd/luci-app-pcdn-detector.git
cd luci-app-pcdn-detector

# after editing: push the frontend to the router and reload LuCI
scp -r luasrc root /tmp/
ssh root@192.168.1.1 '
  cp -r /tmp/luasrc/* /usr/lib/lua/luci/ && cp -r /tmp/root/* / &&
  rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache
'
```

Building `.ipk` / `.apk` is only needed for delivery: run
`./scripts/build-openwrt.sh 24.10 --sdk`, or compile inside an OpenWrt source
tree (see [docs/build.md](docs/build.md)).

End-to-end checks of configuration editing, hot reload and statistics require a
working `pcdn-detect` binary on the router. Without it the pages fall back to
their "not installed" state.

## Making changes

1. Fork the repository and create a branch off `main`, for example
   `fix/log-pause` or `feat/device-filter`.
2. Keep the change focused. One logical change per PR is much easier to review.
3. Match the existing style: Lua pages under `luasrc/controller` and
   `luasrc/model/cbi/pcdn-detector`, templates under `luasrc/view`, and shared
   helpers in `luasrc/model/pcdn_util.lua` / `pcdn_toml.lua`. Do not add a TOML
   parser to the save path — the editor deliberately treats the file as plain
   text and lets `pcdn-detect -T` validate it.
4. When adding or changing UI strings, update `po/zh-cn/pcdn-detector.po` in the
   same PR.
5. Update the documentation when your change affects user-visible behaviour:
   the overview and quick start stay in `README.md`, details go to the matching
   page under `docs/` (`install.md`, `build.md`, `usage.md`, `http-api.md`,
   `update.md`, `faq.md`, `development.md`). Documentation must describe what
   the code actually does — do not claim capabilities that are not
   implemented.

## Before you open a pull request

Run the same checks locally, and make sure they pass:

```bash
# Lua syntax
find luasrc -name '*.lua' -exec luac -p {} \;

# shell syntax
sh -n root/etc/init.d/pcdn-detector
sh -n root/usr/share/pcdn-detector/update.sh
```

If a binary is available, also verify that a generated or edited configuration
passes validation:

```bash
tmp="$(mktemp -d)"
pcdn-detect --init-config "$tmp"
pcdn-detect -T -i br-lan -c "$tmp/pcdn-detect.toml"
rm -rf "$tmp"
```

## Pull request process

- Open the PR against the `main` branch.
- Use a clear title and describe **what** changed and **why**. Link the issue
  it fixes (`Fixes #123`) where applicable.
- Use Conventional Commit style for the PR title/commits (`feat:`, `fix:`,
  `docs:`, `refactor:`, `test:`, `ci:`, `chore:`), optionally with a scope,
  e.g. `fix(log): …`, `feat(overview): …`.
- Confirm in the PR description that you agree to the CLA.
- Sign off every commit with a `Signed-off-by` line (see above).
- Keep the branch up to date with `main`; resolve conflicts yourself.
- Respond to review feedback. Reviewers may request changes, and a maintainer
  makes the final decision on whether a PR is merged.

---

# 为本项目做出贡献

感谢您愿意花时间做出贡献！本文档说明如何报告问题、提交改动，以及如何让您的改动被合并。
它适用于所有人——在发起 Pull Request（PR）之前，请先阅读本文档。

[English](#contributing-to-luci-app-pcdn-detector)

---

## 贡献者许可协议（必需）

在接受您的贡献之前，您必须同意本项目的[贡献者许可协议](CLA.md)。

**发起 Pull Request 即表示您确认已阅读 CLA，并同意其条款适用于您当前及未来的贡献。**
无需另行签署任何单独文件。不满足 CLA 要求的 PR 将不会被合并。

简言之，CLA 允许本项目的维护者与管理者（当前及未来）将您的贡献内容按任意
[OSI 批准许可证](https://opensource.org/licenses)进行再许可；若要以非 OSI（例如专有）
许可证再许可您的贡献，须另行取得您的明确授权。

## 开发者原创声明（DCO，必需）

Pull Request 中的每一个提交都必须签署，以证明遵守
[开发者原创声明](https://developercertificate.org/)（Developer Certificate of
Origin，DCO）。请在提交信息（commit message）的最后一行加上 `Signed-off-by`，内容为
您的称呼（您使用的名字或网名）与邮箱：

```
fix(view): 修复日志页暂停后仍刷新

Signed-off-by: 张三 <zhangsan@example.com>
```

`git commit -s` 会自动添加该行，姓名与邮箱取自 Git 配置（请先用 `git config user.name`
与 `git config user.email` 设置）。若已有提交缺少该行，可运行
`git rebase --signoff main` 补上。

签署行只需能标识您本人——一个称呼或网名加上邮箱即可，无需使用法定姓名。签署即表示
您证明该贡献由您本人创作，或您有权按本项目许可证提交它。DCO 是对每个提交的确认，与
上述 CLA **同时**适用；未签署的 PR 将不会被合并。

## 报告问题

- 请先搜索已有 issue，避免重复。
- 报告 bug 时请提供：LuCI 包版本、OpenWrt / 发行版版本与 CPU 架构
  （`cat /proc/cpuinfo`、`opkg print-architecture` 或 `apk --print-arch`）、
  `pcdn-detect` 版本（`pcdn-detect -v`）、使用的浏览器，以及清晰的可复现步骤。
- 必要时请附上 uhttpd / LuCI 报错与 `logread` 相关日志。粘贴前请**隐去 MAC 与公网
  IP**：概览页会展示设备级统计。
- 功能建议请描述使用场景与期望行为。
- 安全相关问题请勿在公开 issue 中报告，请私下联系维护者。

## 开发环境

本包只包含 Lua、HTML 与 shell 代码，日常调试不需要编译。把 `luasrc` 与 `root` 覆盖到
路由器并清理一次 LuCI 缓存即可，完整步骤见
[docs/install.md](docs/install.md#手动安装到路由器)。简要流程：

```bash
git clone https://cnb.cool/womsxd/luci-app-pcdn-detector.git
cd luci-app-pcdn-detector

# 修改后把前端推到路由器并重新加载 LuCI
scp -r luasrc root /tmp/
ssh root@192.168.1.1 '
  cp -r /tmp/luasrc/* /usr/lib/lua/luci/ && cp -r /tmp/root/* / &&
  rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache
'
```

只有交付安装包时才需要构建 `.ipk` / `.apk`：运行
`./scripts/build-openwrt.sh 24.10 --sdk`，或在 OpenWrt 源码树中编译
（见 [docs/build.md](docs/build.md)）。

配置编辑、热重载与实时统计的端到端验证，需要路由器上有可用的 `pcdn-detect` 二进制；
未安装时页面会进入“未安装”状态。

## 提交改动

1. Fork 仓库并从 `main` 创建分支，例如 `fix/log-pause` 或 `feat/device-filter`。
2. 保持改动聚焦。一个 PR 只做一件事，更易于评审。
3. 遵循既有风格：页面放在 `luasrc/controller` 与 `luasrc/model/cbi/pcdn-detector`，
   模板放在 `luasrc/view`，公共函数放在 `luasrc/model/pcdn_util.lua` 与
   `pcdn_toml.lua`。不要在保存链路里加 TOML 解析——配置编辑器有意把文件当纯文本处理，
   交给 `pcdn-detect -T` 校验。
4. 新增或修改界面文案时，请在同一 PR 中更新 `po/zh-cn/pcdn-detector.po`。
5. 当改动影响用户可见行为时，请同步更新文档：概览与快速开始留在 `README.md`，细节改
   `docs/` 下的相应页面（`install.md`、`build.md`、`usage.md`、`http-api.md`、
   `update.md`、`faq.md`、`development.md`）。文档必须如实描述代码的实际行为，不得
   宣称尚未实现的能力。

## 发起 Pull Request 之前

请在本地运行以下检查并确保全部通过：

```bash
# Lua 语法
find luasrc -name '*.lua' -exec luac -p {} \;

# shell 语法
sh -n root/etc/init.d/pcdn-detector
sh -n root/usr/share/pcdn-detector/update.sh
```

如果手边有二进制，再确认生成或修改后的配置能通过校验：

```bash
tmp="$(mktemp -d)"
pcdn-detect --init-config "$tmp"
pcdn-detect -T -i br-lan -c "$tmp/pcdn-detect.toml"
rm -rf "$tmp"
```

## Pull Request 流程

- 向 `main` 分支发起 PR。
- 使用清晰的标题，并说明**改了什么**以及**为什么**。若相关，请关联对应 issue
  （`Fixes #123`）。
- PR 标题/提交信息请使用 Conventional Commits 风格（`feat:`、`fix:`、`docs:`、
  `refactor:`、`test:`、`ci:`、`chore:`），可附带作用域，例如 `fix(log): …`、
  `feat(overview): …`。
- 在 PR 描述中确认您同意 CLA。
- 为每个提交添加 `Signed-off-by` 签署行（见上）。
- 保持分支与 `main` 同步，并自行解决冲突。
- 回应评审意见。评审者可能要求修改，最终是否合并由维护者决定。
