# luci-app-pcdn-detector

[pcdn-detector](https://github.com/womsxd/pcdn-detector) 的 LuCI 前端：在 OpenWrt 上管理 PCDN 行为检测服务。

最低支持 OpenWrt 20.02 / 21.02 系列（20.02 未发布正式版，实际以 21.02 为最低正式版），兼容官方 OpenWrt、Lean LEDE、ImmortalWrt。同一份 Makefile 会根据构建树自动产出 `.ipk`（opkg）或 `.apk`（OpenWrt 24.10+ 的 apk）。

## 功能

- **概览**：运行状态、版本（主版本 + 构建号）、PID / 运行时长、监听网卡、启动 / 停止 / 重启 / 热重载；读取 HTTP API 端口与密钥、检测 HTTP 状态（200 / 401 / 不可达）；启用后展示设备级统计（IPv4 / IPv6 端口条目数与封禁数、`port_evictions` / `port_drops`），并可下钻查看单设备端口明细与对端 IP（支持分页，按需读取）。可选**直连模式**：浏览器直接请求 HTTP API，绕过 LuCI 代理（见下文）。
- **配置编辑**：完整 TOML 文本编辑，像编辑 txt 文件一样直接改全文，保留注释、黑白名单与未知配置项；保存时把完整文件发回后端，后端不解析，只做校验与保存。支持 Ctrl/Cmd+S。
- **在线校验与热重载**：保存前调用 `pcdn-detect -T` 校验，失败不落盘；成功后发送 SIGHUP 原地生效，不重启进程、不丢失封禁状态。
- **日志**：从 `logread` 中按 syslog tag 精确筛选 (不是简单的正文匹配)，支持等级、关键词、行数、自动刷新、暂停与下载；页面切到后台时自动暂停刷新。
- **下载 / 更新**：按设备架构推导 GitHub Release 资源地址，也可填写任意 http(s) 直链（需为未压缩的 ELF 二进制）；按剩余空间选择下载位置（`/tmp` 优先，其次目标分区）；安装后执行 `-v` 自检，失败自动回滚旧版本，成功后清理临时文件与备份。

## 目录结构

```
luci-app-pcdn-detector/
├── Makefile                                      # OpenWrt 打包
├── scripts/build-openwrt.sh                      # 官方源码编译 ipk / apk
├── luasrc/
│   ├── controller/pcdn-detector.lua              # 菜单、页面与后端接口
│   ├── model/pcdn_toml.lua                       # TOML 只读解析（状态 / 统计）
│   ├── model/pcdn_util.lua                       # JSON、进程、HTTP、格式化
│   ├── model/cbi/pcdn-detector/
│   │   ├── overview.lua                          # 概览 + 服务设置（UCI）
│   │   ├── config.lua                            # 完整 TOML 文本编辑
│   │   ├── log.lua                               # 日志
│   │   └── update.lua                            # 下载源设置
│   └── view/pcdn-detector/
│       ├── status.htm                            # 状态卡片 + 服务控制
│       ├── config.htm                            # TOML 文本编辑器
│       ├── log.htm                               # 日志查看器
│       └── update.htm                            # 下载面板
├── root/
│   ├── etc/config/pcdn-detector                  # UCI 配置
│   ├── etc/init.d/pcdn-detector                  # procd 服务脚本（缺配置时让程序自动生成）
│   ├── etc/uci-defaults/40_luci-pcdn-detector    # 首次安装初始化
│   └── usr/share/pcdn-detector/update.sh         # 下载 / 安装 / 回滚脚本
└── po/zh-cn/pcdn-detector.po
```

> 仓库不内嵌 TOML 配置：首次启动服务或首次打开「配置编辑」时，由
> `pcdn-detect` 生成默认配置并写入 UCI 指定的 `config_path`（默认
> `/etc/pcdn-detect/pcdn-detect.toml`），内容来自二进制内置模板，因此会随上游版本更新。

## 兼容性与包格式

| 源码树 | 最低版本 | 包格式 |
| --- | --- | --- |
| 官方 OpenWrt | 20.02 / 21.02 | 23.05 及更早为 `..ipk`；24.10+ 为 `.apk` |
| Lean LEDE | 使用含 `luci-compat` 的 LuCI | 由构建树的包管理器决定 |
| ImmortalWrt | 21.02+ | 由构建树的包管理器决定 |

`Makefile` 使用标准 `BuildPackage`：构建树为 opkg 时输出 `.ipk`，`CONFIG_USE_APK=y` 时输出 `.apk`，无需为两种格式分别维护。`luci-compat` 已写入 `DEPENDS`，由包管理器自动安装。

本 LuCI 应用为 **noarch**（`PKGARCH:=all`）：包内只有 Lua / HTML / shell 脚本，同一份 `.ipk` / `.apk` 可安装在所有架构上。架构相关的只有 `pcdn-detect` 二进制，它不包含在本包内，由「下载/更新」按设备架构单独获取。

## 安装

### 1. 随固件编译

以下步骤适用于官方 OpenWrt、Lean LEDE、ImmortalWrt（把 `openwrt` 换成对应源码树目录）：

```bash
cd openwrt
git clone <本仓库地址> package/luci-app-pcdn-detector
./scripts/feeds update -a && ./scripts/feeds install -a   # 首次编译时执行
make menuconfig     # LuCI -> Applications -> luci-app-pcdn-detector
make package/luci-app-pcdn-detector/compile V=s
```

产物：

```bash
# opkg 构建树（未启用 CONFIG_USE_APK，如 23.05 及更早）
bin/packages/<arch>/luci/luci-app-pcdn-detector_*.ipk

# apk 构建树（OpenWrt 24.10+）
bin/packages/<arch>/luci/luci-app-pcdn-detector-*.apk
```

> `Makefile` 没有把 `pcdn-detect` 写成依赖，因为上游二进制通常不在官方 feed 中。
> 首次安装后请在「下载/更新」中安装二进制，或手动放入 `/usr/bin/pcdn-detect`。

### 2. 手动安装到路由器

```bash
scp -r luasrc root /tmp/
ssh root@192.168.1.1 '
  cp -r /tmp/luasrc/* /usr/lib/lua/luci/ &&
  cp -r /tmp/root/* / &&
  chmod +x /etc/init.d/pcdn-detector /etc/uci-defaults/40_luci-pcdn-detector /usr/share/pcdn-detector/update.sh &&
  /etc/init.d/pcdn-detector enable &&
  rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache
'
```

手动安装前请确认 `luci-compat` 已安装：

```bash
opkg install luci-compat     # ipk / opkg 系统
apk add luci-compat          # apk 系统（24.10+）
```

安装二进制：

```bash
scp bin/pcdn-detect-mipsle root@192.168.1.1:/usr/bin/pcdn-detect
ssh root@192.168.1.1 'chmod +x /usr/bin/pcdn-detect && /usr/bin/pcdn-detect -v'
```

### 依赖

- `luci-base`
- `luci-compat`（Lua CBI / `luci.model.uci` 兼容层；已写入 `DEPENDS`，由 opkg / apk 自动安装）
- 下载功能需要 `curl` 或 `wget`（BusyBox 自带 `wget` 即可）
- 路由表 / 封禁功能依赖 `iptables` 或 `nftables`（由 pcdn-detect 自行调用）

## 本地编译 ipk / apk

仓库自带 `scripts/build-openwrt.sh`，使用官方 OpenWrt 源码编译 LuCI 包：

```bash
# 推荐：官方 SDK 模式，只编译包本身，速度最快
./scripts/build-openwrt.sh 24.10 --sdk
./scripts/build-openwrt.sh 23.05 --sdk
./scripts/build-openwrt.sh all --sdk

# 完整官方源码模式（首次需要编译 tools/toolchain，较慢）
./scripts/build-openwrt.sh 23.05
./scripts/build-openwrt.sh 24.10
```

常用参数：

- `--sdk`：使用官方 SDK，跳过 `tools` / `toolchain` 编译，只构建包；
- `--mirror URL`：指定 SDK 镜像站（`official` / `ustc` / `tencent` / `tencent-intra` 或自定义 URL），会自动启用 `--sdk`；
- `--fallback URL`：显式指定备用镜像；不加时镜像缺少 SDK 直接报错，不回退；
- `--no-fallback`：禁止回退（默认行为）；
- `--update`：更新源码树 / feeds；默认复用已有内容；
- `--jobs N`：并行任务数；
- `--clean`：删除对应源码树 / SDK 后重新下载；
- `--sdk-url URL`：指定 SDK 压缩包（镜像或固定版本）；
- `OPENWRT_GIT_URL=...`：替换官方源码地址（默认 `https://github.com/openwrt/openwrt.git`）。

说明：

- SDK 模式源码树位于 `build/sdk-<version>`；完整源码模式位于 `build/openwrt-<version>`；
- 产物复制到 `dist/openwrt-<version>/`，并生成 `SHA256SUMS`；
- 构建目标固定为 `x86/64`；LuCI 包是 noarch（`PKGARCH:=all`），产物可安装到任意架构；
- `--sdk` 首次会下载约 100 MB 官方 SDK，仍建议 10 GiB 以上空闲磁盘；完整源码模式建议 20 GiB 以上；
- 编译依赖见下方「编译依赖」小节；SDK 模式也需要 OpenWrt 的 host 前置包，不只是 `git` / `make`；
- 更新 feeds 需要 Perl 的 `FindBin` 模块：Fedora 若提示 `Can't locate FindBin.pm`，执行 `dnf install perl-FindBin`；Debian/Ubuntu 安装 `perl`；
- `24.10` 通过 `CONFIG_USE_APK=y` 生成 `.apk`，其余版本生成 `.ipk`；
- 脚本只编译 LuCI 前端包；`pcdn-detect` 二进制由「下载/更新」安装，或按上游项目单独编译。

### 编译依赖

SDK 模式虽然跳过 `tools` / `toolchain`，但仍会执行 OpenWrt 的 `prereq-build` 检查，并编译 `po2lmo` 等 host 工具，所以下面这些包仍要装。

**Fedora**

```bash
sudo dnf install -y \
  git make gcc gcc-c++ tar gzip wget curl xz zstd 7zip \
  rsync patch unzip bzip2 diffutils findutils gawk grep sed coreutils \
  file which bash util-linux \
  ncurses-devel glibc-devel gettext-devel python3 \
  perl perl-FindBin perl-Time-Piece perl-JSON-PP perl-Thread-Queue perl-Data-Dumper \
  cmake ninja-build
```

**Debian / Ubuntu**

```bash
sudo apt update
sudo apt install -y \
  build-essential git make gcc g++ tar gzip wget curl xz-utils zstd \
  rsync patch unzip bzip2 diffutils findutils gawk grep sed coreutils \
  file debianutils util-linux bash \
  libncurses-dev libc6-dev gettext python3 perl \
  cmake ninja-build

# 新版发行版有 7zip；旧版用 p7zip-full
sudo apt install -y 7zip || sudo apt install -y p7zip-full
```

**Arch Linux**

```bash
sudo pacman -S --needed base-devel git rsync patch unzip bzip2 xz zstd 7zip \
  ncurses gettext python perl wget curl cmake ninja \
  file which bash util-linux
```

完整源码模式还要额外安装：

```bash
# Fedora
sudo dnf install -y autoconf automake libtool bison flex \
  zlib-devel openssl-devel elfutils-libelf-devel swig ccache bc cpio texinfo

# Debian / Ubuntu
sudo apt install -y autoconf automake libtool bison flex \
  zlib1g-dev libssl-dev libelf-dev swig ccache bc cpio texinfo
```

说明：

- `ncurses-devel` / `libncurses-dev`、GNU `patch`、Perl 的 `FindBin` / `Time::Piece` / `JSON::PP` / `Thread::Queue` 在 SDK 模式下也会用到；
- `tar` 在受限容器里报 `Function not implemented` 时，需要安装 `7z` / `7zz` / `7za`；
- 部分发行版把 Python 工具拆在 `python3-distutils` / `python3-setuptools`，缺少时补装；
- 让 OpenWrt 自己检查缺什么：
  ```bash
  make -C build/sdk-<版本>/<sdk目录> prereq
  ```
- 脚本顶部的命令检查只是快速失败；完整前置检查以 OpenWrt 的 `prereq-build` 为准。

### SDK 镜像站

`--sdk` 默认从 `downloads.openwrt.org` 下载 SDK，也可以切换镜像：

```bash
./scripts/build-openwrt.sh all --sdk --mirror ustc
./scripts/build-openwrt.sh 24.10 --sdk --mirror tencent
./scripts/build-openwrt.sh 24.10 --sdk --mirror tencent-intra
./scripts/build-openwrt.sh 24.10 --sdk --mirror https://mirrors.example.com/openwrt
```

预设：

- `official`：`https://downloads.openwrt.org`
- `ustc`：`https://mirrors.ustc.edu.cn/openwrt`（中科大）
- `tencent`：`https://mirrors.cloud.tencent.com/openwrt`（公网）
- `tencent-intra`：`http://mirrors.tencentyun.com/openwrt`（腾讯云内网）

也可以使用环境变量：

```bash
OPENWRT_MIRROR=ustc ./scripts/build-openwrt.sh all --sdk

# 需要回退时显式设置
OPENWRT_MIRROR=tencent-intra OPENWRT_MIRROR_FALLBACK=official \
  ./scripts/build-openwrt.sh all --sdk
```

说明：

- `--mirror` 只影响 SDK 下载；完整源码模式请用 `OPENWRT_GIT_URL` 指定 git 镜像；
- 镜像站需保持 `releases/<版本>/targets/x86/64/openwrt-sdk-*.tar.xz|zst` 结构；
- 脚本会从最新补丁版开始向下查找 SDK，镜像同步不完整时会继续尝试旧补丁版；
- 当前镜像找不到 SDK 时默认直接报错，**不会自动回退**；需要回退时显式加 `--fallback official`（或其它镜像），或设置 `OPENWRT_MIRROR_FALLBACK=official`；
- 在受限容器 / 特殊文件系统中，`tar` 可能报 `Function not implemented`（ENOSYS）；脚本会自动改用 `7z` 重新解压（需要 `7z` / `7zz` / `7za`，xz/zst 先解成 tar），**已下载的 SDK 压缩包会保留**，直接重跑原命令即可，不需要 `--clean`；
- USTC 镜像同时提供 `23.05.6`（ipk）与 `24.10.8`（apk）的 x86/64 SDK，适合一次构建两种格式：

  ```bash
  ./scripts/build-openwrt.sh all --sdk --mirror ustc
  ```

- 腾讯云镜像当前对 24.10 / 25.12 提供完整 SDK，但 `23.05` 的 `targets/x86/64` 未同步：
  - 默认 `all --sdk --mirror tencent-intra` 的 23.05 会直接报错；需要回退时加 `--fallback official`；
  - 纯内网无法访问官方源时，23.05 需要提供可用的 SDK 地址（`--sdk-url`）或改用完整源码模式；24.10 仍会继续构建，不会因 23.05 失败而中断。

### 更快的开发方式

只改 Lua / HTML 时，不必每次打包：直接把 `luasrc` 和 `root` 覆盖到路由器，清一次 LuCI 缓存即可，见上面的手动安装步骤。需要交付安装包时再用 `--sdk` 打包。

## 首次使用

1. 进入 **服务 → PCDN 检测 → 概览**，确认「程序路径」下有可执行文件；没有则到「下载/更新」安装。
2. 打开 **配置编辑**，像编辑 txt 一样直接修改完整 TOML。首次打开时配置不存在，页面会调用 `pcdn-detect --init-config` 生成默认文本、填入默认 `br-lan`（不自动探测 `network.lan.device`，避免误填成 `eth2` 等物理口），并在校验通过后写入 `config_path`（默认 `/etc/pcdn-detect/pcdn-detect.toml`；需要二进制已安装）。常用项：
   - `[capture] interface = "br-lan"`：必须是能看到设备真实 MAC 的 LAN 侧网桥；
   - `[detect] threshold = 20`、`window = "60s"`：触发阈值与检测时长；
   - `[capture] protocol = "udp"`：PCDN 以 UDP 为主；
   - `[log] level = "warn"`：上游默认值；如需在日志页查看告警与解封记录，可临时改为 `info`。
3. 保存并应用，回到概览点击「启动」。
4. 「日志」页可查看告警；启用 HTTP API 后概览页会显示实时统计。

## 配置说明

配置分两层：

| 层 | 文件 | 内容 |
| --- | --- | --- |
| UCI | `/etc/config/pcdn-detector` | 开机自启、配置文件路径、二进制路径、附加命令行参数、下载源、空间不足时覆盖安装 |
| TOML | `/etc/pcdn-detect/pcdn-detect.toml` | pcdn-detect 自身的全部配置（检测、抓包、内存、日志、HTTP、黑白名单、防火墙、UPnP）；首次使用时由程序生成 |

- 仓库与安装包 **不包含 TOML 文件**。缺少配置时，服务启动脚本或 LuCI 会在临时目录执行
  `pcdn-detect --init-config <临时目录>`，由程序把内置模板写入 `pcdn-detect.toml`，再补上检测到的
  LAN 网卡。该功能要求二进制支持 `--init-config`（当前上游已提供）。
- 后端 `getconfig` / `saveconfig` 只收发完整文件，不做 TOML 解析、字段提取或补丁。
- 大配置采用分片上传：前端每片最多 1000 个字符（UTF-8 约 4 KiB），`POST savechunk` 追加到 `/tmp/pcdn-detect.save.part`；全部发完后 `POST savecommit` 统一校验、落盘、热重载。
- 这样不再受 LuCI 单次请求 body 限制影响（部分固件约 8 KiB，会把 `[[filter.blacklist]]` 等尾部内容截断）；分片仍保留完整注释和名单。
- 「配置编辑」直接编辑完整 TOML 原文（等同 txt），前端不做解析；保存时把全文回传。
- 编辑链路不解析 TOML；`pcdn_toml.lua` 仅用于状态页 / HTTP 统计读取少量字段。
- 「恢复默认」也用程序生成一份新配置（保留当前监听网卡），不再依赖随包模板。
- 保存成功后：服务运行中 → `kill -HUP` 热重载；已启用但未运行 → 自动启动；未启用 → 仅保存。
- `附加启动参数` 会追加到 `pcdn-detect -c <配置>` 之后，**优先级高于 TOML**，例如 `-i br-lan -n 30`。

> 尚未安装 `pcdn-detect` 时无法生成默认配置：配置页会提示先到「下载/更新」安装二进制。

## HTTP API 检测

概览页从**已保存的 TOML** 的 `[http]` 段读取 `enabled`、`listen`、`token`：

- **端口**：自动解析 `listen` 中的端口并显示（`0.0.0.0` / `[::]` 会通过 `127.0.0.1` / `::1` 访问）；
- **密钥**：点击「获取密钥」按需读取 `[http] token` 并显示，可点击「复制密钥」复制；未设置时提示为空；
- **状态检测**：点击「检测 HTTP API」请求本机 `/api/v1/status`，区分：
  - `200`：正常；
  - `401/403`：密钥不匹配；
  - 连接失败：服务未启动、端口/监听地址错误或被防火墙拦截；
  - `[http] enabled` 未开启：提示未启用。
- 实时统计区默认每 5 秒自动读取一次，可用操作区的「自动刷新（5 秒）」开关关闭（选择会记住）；页面切到后台时停止轮询，切回前台立即刷新一次；同一时刻只允许一个轮询在途，慢请求不会叠加。服务未运行、二进制未安装或 `[http] enabled` 未开启时不会发起请求（因此 `nohttp` 构建或服务启动失败时不会再看到“无法连接 … (111)”）。HTTP API 正常时显示“正常”（直连模式为“正常（直连）”，回退后为“正常（代理）”），否则显示“异常”。
- **设备级汇总**：概览页读取 `/api/v1/devices`，展示每设备 IPv4 / IPv6 的端口条目数与封禁数（含 UDP / TCP 拆分）；上游该接口不再下发端口明细，`port_evictions` / `port_drops` 大于 0 时会提示 `[memory] max_ports` 已生效。
- **端口明细 / 对端 IP**：点击「端口明细」按需请求 `/api/v1/device`（地址族、封禁状态筛选 + 分页），点击「对端 N」请求 `/api/v1/peers`（分页上限受 `[http] device_ip_limit` 约束）。自动刷新只更新汇总，展开的明细保持不动。
- **JSON 流式透传**：`device` / `peers` 只解析上游响应头，body 按 16 KiB 分块直接转发给浏览器，Lua 侧峰值约等于一块（实测 4.5 MB 响应只额外占用约 100 KiB，整段缓冲则要 2 倍以上）；`stats` 的 `/api/v1/devices` 同样流式转发，只有体积很小的 `/api/v1/status` 整段缓冲用于判断空响应与错误码，两段再原样拼成一段 JSON。Lua 侧不做 JSON 解码，浏览器统一用 `JSON.parse`。仅「检测 HTTP API」为显示设备数 / 告警数解析体积很小的 `/api/v1/status`。上游 4xx/5xx 的 `{"error":"..."}` 与状态码也会原样到达前端；读取总量有 32 MiB 上限，异常上游不会把 CGI 进程撑爆。

### 直连模式（可选，默认关闭）

在「概览 → 服务设置」勾选「直连后端 API（绕过 LuCI 代理）」后，实时统计、端口明细与对端列表改由浏览器直接请求 `pcdn-detect` 的 HTTP API，不再为每次轮询启动 Lua 代理进程。

需要同时满足以下条件，否则页面自动回退到 LuCI 代理并显示原因：

1. `[http] listen` 监听局域网可达地址（默认 `127.0.0.1:8080` 只有路由器本机能访问）；
2. 设置 `[http] token`；
3. 把 LuCI 页面的来源加入 `[http] cors_allowed_origins`（**不带路径**；端口非 80 时要写上端口，默认端口 80/443 不要写，因为浏览器发送的 `Origin` 不带默认端口）。来源写错时页面会提示当前应加入的来源。

```toml
[http]
enabled = true
listen = "0.0.0.0:8080"
token = "换成随机字符串"
cors_allowed_origins = ["http://192.168.1.1"]
```

行为说明：

- 直连与代理都保持 `stats` 两段数据（`/api/v1/status` + `/api/v1/devices`）；
- 只有浏览器层面失败（CORS 未放行、网络不通、5 秒超时）才回退，且 60 秒内不再重试；`401` 等业务错误照常展示；
- 直连时 token 会随 `/status` 下发（页面本来也能通过「获取密钥」看到）；API 仅支持明文 HTTP，请只在可信内网使用；
- LuCI 若通过 HTTPS 访问，浏览器会以 mixed content 拦截直连请求，此时只能走代理。

密钥只返回给已登录的 LuCI 管理员，接口响应带 `Cache-Control: no-store`；请不要在不可信网络中使用弱 token。

## 下载源说明

默认按 `https://github.com/<repo>/releases/latest/download/pcdn-detect-<arch>` 推导地址，资源命名与上游 Makefile 产物一致：

| 设备架构（opkg） | 资源名 |
| --- | --- |
| `mipsel_24kc` / `mipsel_*` | `pcdn-detect-mipsle` |
| `mips_24kc` / `mips_*` | `pcdn-detect-mips` |
| `aarch64_*` | `pcdn-detect-arm64` |
| `arm_*`（armv7） | `pcdn-detect-armv7` |
| `x86_64` | `pcdn-detect-amd64` |

若仓库没有公开 Release、使用私有仓库或需要走镜像：

- 在「下载/更新 → 下载源」中修改仓库名，或设置「下载地址前缀」；
- 也可以直接在页面顶部填写完整的 http(s) 地址（需为未压缩的 ELF 二进制）；

架构识别顺序：`opkg print-architecture`（opkg 系统）→ `apk --print-arch`（apk 系统，24.10+）→ `uname -m` 兜底。

安装流程按剩余空间选择下载位置（阈值由 `update.sh` 统一判定，页面会显示目标分区与 `/tmp` 的剩余空间）：

| 方式 | 条件 | 行为 |
| --- | --- | --- |
| `tmp` | `/tmp` ≥ 24 MiB | 下载到 `/tmp`（tmpfs，下载期间占用内存），复制到目标目录后立刻删除 |
| `direct` | `/tmp` < 24 MiB 且目标分区 ≥ 16 MiB | 下载到目标目录下的临时文件，同分区 `rename` 覆盖：不占内存，替换是原子的 |
| `overwrite` | 两者都不足 | 先删除旧程序再下载；需在「下载/更新 → 下载源」开启「空间不足时覆盖安装」，更新失败无法回滚 |

无论哪种方式，下载后都会校验文件大小与 ELF 头 → 备份原文件（`rename` 到 `pcdn-detect.bak`，不额外占用闪存）→ 覆盖安装 → 执行 `-v` 自检 → 失败自动回滚 → 成功则删除临时文件与 `.bak` → 重启服务。若上次更新被中断（只剩 `.bak`），下次运行会先自动恢复。进度输出位于 `/tmp/pcdn-detect-update.log`。

> `-v` 输出为 SemVer，git 短哈希作为 build metadata：`0.0.1-alpha+c6d101c`（早期格式为 `0.0.1-alpha-c6d101c`）。
> 概览页与下载页把主版本与构建号分开显示，完整字符串保留在鼠标悬停提示中。

## 日志说明

pcdn-detect 输出到 stdout，由 procd（`stdout 1`）写入系统日志，tag 为二进制文件名：

```
Sat Oct 24 12:00:42 2026 daemon.info pcdn-detect[1234]: ... 疑似产生PCDN行为 ...
```

日志页按 syslog tag 精确筛选，不会把正文里提到 pcdn-detect 的其它进程日志混进来。可查看的历史长度取决于系统日志缓冲区；需要长期保存请配置 `logread` 落盘或远程 syslog。

## 常见问题

**服务启动失败 / 一直重启**

在「配置编辑」点「仅校验」查看具体错误。常见原因：

- 监听网卡为空或填错（必须填 LAN 侧网桥）；
- 选择了 `hook` 防火墙后端但没写 `[firewall.hook] cmd`；
- 选了 `blacklist` 名单模式但名单为空（pcdn-detect 会拒绝启动）；
- HTTP API 绑定了非回环地址但没设置 token。

**日志页为空**

- 服务可能没启动；
- `[log] level` 默认为 `warn`，不会输出普通告警与业务事件；需要查看时改为 `info`；
- 系统日志缓冲区已滚动，或设备没有 `logread`。

**概览页没有实时统计**

「配置编辑」中的 `[http] enabled` 没有启用，或 `listen` / `token` 不匹配。默认 `127.0.0.1:8080` 仅本机可访问，LuCI 通过本机回环读取。

**下载 404**

默认仓库没有公开 Release 时会出现。请改用自定义完整地址，或把编译好的二进制上传到路由器：

```bash
scp bin/pcdn-detect-mipsle root@192.168.1.1:/usr/bin/pcdn-detect
```

**SSH 里 `pcdn-detect -v` 正常，但 LuCI 概览页版本显示 `sh: ... Permission denied`**

这是旧版本缓存：`version_of` 曾把失败输出也写入 `/tmp/pcdn-detect.version`，而 `chmod` 只改变 `ctime` / `mode`，不改变 `mtime`，导致缓存没有失效。清除缓存并刷新页面：

```bash
rm -f /tmp/pcdn-detect.version
```

新版已修复：缓存 key 包含 `mtime | ctime | mode`，且只缓存匹配版本号的输出，错误信息不再写入缓存。

**LuCI 菜单不显示 / 页面空白**

- 21.02+ 未安装 `luci-compat` 时会出现该问题；通过 opkg/apk 正常安装本包会自动拉取，手动安装请先执行 `opkg install luci-compat` 或 `apk add luci-compat`；
- 安装后清理缓存：`rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache`。

## 开发与校验

```bash
# Lua 语法
find luasrc -name '*.lua' -exec luac -p {} \;

# shell 语法
sh -n root/etc/init.d/pcdn-detector
sh -n root/usr/share/pcdn-detector/update.sh

# 默认配置由程序自己生成，可在临时目录验证
tmp="$(mktemp -d)"
pcdn-detect --init-config "$tmp"
pcdn-detect -T -i br-lan -c "$tmp/pcdn-detect.toml"
rm -rf "$tmp"
```

`getconfig` / `saveconfig` 的完整文件收发已用上游真实二进制做端到端校验：保存的全文可直接通过 `pcdn-detect -T`。
