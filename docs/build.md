# 本地编译 ipk / apk

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

## 编译依赖

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

## SDK 镜像站

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

## 更快的开发方式

只改 Lua / HTML 时，不必每次打包：直接把 `luasrc` 和 `root` 覆盖到路由器，清一次 LuCI 缓存即可，见[手动安装](install.md#手动安装到路由器)。需要交付安装包时再用 `--sdk` 打包。
