# luci-app-pcdn-detector

[pcdn-detector](https://github.com/womsxd/pcdn-detector) 的 LuCI 前端：在 OpenWrt 上管理 PCDN 行为检测服务。

支持官方 OpenWrt（21.02+）、Lean LEDE、ImmortalWrt。同一份 `Makefile` 会根据构建树自动产出 `.ipk`（opkg）或 `.apk`（`CONFIG_USE_APK=y`，24.10+）。

## 功能

- **概览**：运行状态、版本（主版本 + 构建号）、PID / 运行时长、监听网卡、启动 / 停止 / 重启 / 热重载；读取 HTTP API 端口与密钥、检测 HTTP 状态（200 / 401 / 不可达）；启用后展示设备级统计（IPv4 / IPv6 端口条目数与封禁数、`port_evictions` / `port_drops`），并可下钻查看单设备端口明细与对端 IP（支持分页，按需读取）。可选**直连模式**：浏览器直接请求 HTTP API，绕过 LuCI 代理（见 [HTTP API](docs/http-api.md#直连模式可选默认关闭)）。
- **配置编辑**：完整 TOML 文本编辑，像编辑 txt 文件一样直接改全文，保留注释、黑白名单与未知配置项；保存时把完整文件发回后端，后端不解析，只做校验与保存。支持 Ctrl/Cmd+S。
- **在线校验与热重载**：保存前调用 `pcdn-detect -T` 校验，失败不落盘；成功后发送 SIGHUP 原地生效，不重启进程、不丢失封禁状态。
- **日志**：从 `logread` 中按 syslog tag 精确筛选（不是简单的正文匹配），支持等级、关键词、行数、自动刷新、暂停与下载；页面切到后台时自动暂停刷新。
- **下载 / 更新**：按设备架构推导 GitHub Release 资源地址，也可填写任意 http(s) 直链（需为未压缩的 ELF 二进制）；按剩余空间选择下载位置（`/tmp` 优先，其次目标分区）；安装后执行 `-v` 自检，失败自动回滚旧版本，成功后清理临时文件与备份。

## 快速开始

### 1. 安装 LuCI 应用

随固件编译（官方 OpenWrt、Lean LEDE、ImmortalWrt 通用，把 `openwrt` 换成对应源码树目录）：

```bash
cd openwrt
git clone <本仓库地址> package/luci-app-pcdn-detector
./scripts/feeds update -a && ./scripts/feeds install -a   # 首次编译时执行
make menuconfig     # LuCI -> Applications -> luci-app-pcdn-detector
make package/luci-app-pcdn-detector/compile V=s
```

产物位于 `bin/packages/<arch>/luci/`：opkg 构建树为 `luci-app-pcdn-detector_*.ipk`，apk 构建树为 `luci-app-pcdn-detector-*.apk`。

手动安装（`scp` 覆盖到路由器）与依赖说明见 [docs/install.md](docs/install.md)。

### 2. 安装 pcdn-detect 二进制

本仓库只提供 LuCI 前端，二进制需单独获取：进入「服务 → PCDN 检测 → 下载/更新」按设备架构安装，或手动上传：

```bash
scp bin/pcdn-detect-mipsle root@192.168.1.1:/usr/bin/pcdn-detect
ssh root@192.168.1.1 'chmod +x /usr/bin/pcdn-detect && /usr/bin/pcdn-detect -v'
```

### 3. 初始化并启动

1. 打开 **服务 → PCDN 检测 → 概览**，确认「程序路径」下有可执行文件。
2. 进入 **配置编辑**，确认 `[capture] interface` 为 LAN 侧网桥（默认 `br-lan`）后保存。
3. 回到概览点击「启动」，「日志」页可查看告警。

完整步骤与配置项说明见 [使用与配置](docs/usage.md)。

## 目录结构

```
.
├── Makefile                  # OpenWrt 打包
├── luasrc/                   # LuCI 控制器、CBI 页面、视图
├── root/                     # UCI 配置、procd 服务脚本、更新脚本
├── po/zh-cn/                 # 中文翻译
├── docs/                     # 文档
└── scripts/build-openwrt.sh  # 本地编译 ipk / apk
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [安装](docs/install.md) | 兼容性、包格式、手动安装、依赖 |
| [本地编译](docs/build.md) | ipk / apk 构建、编译依赖、SDK 镜像站 |
| [使用与配置](docs/usage.md) | 首次使用、UCI / TOML 配置、日志 |
| [HTTP API 检测](docs/http-api.md) | 状态检测、实时统计、直连模式 |
| [下载 / 更新](docs/update.md) | 下载源、架构映射、安装与回滚 |
| [常见问题](docs/faq.md) | 启动失败、日志为空、下载 404 等 |
| [开发与校验](docs/development.md) | 完整目录结构、语法检查 |

## 开发

```bash
# Lua 语法
find luasrc -name '*.lua' -exec luac -p {} \;

# shell 语法
sh -n root/etc/init.d/pcdn-detector
sh -n root/usr/share/pcdn-detector/update.sh
```

更多见 [docs/development.md](docs/development.md)。
