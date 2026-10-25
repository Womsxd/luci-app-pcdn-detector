# 安装

本地打包见[本地编译](build.md)。

## 兼容性与包格式

本 LuCI 应用兼容官方 OpenWrt、Lean LEDE、ImmortalWrt。最低支持 OpenWrt 20.02 / 21.02 系列（20.02 未发布正式版，实际以 21.02 为最低正式版）。

| 源码树 | 最低版本 | 包格式 |
| --- | --- | --- |
| 官方 OpenWrt | 20.02 / 21.02 | 23.05 及更早为 `.ipk`；24.10+ 为 `.apk` |
| Lean LEDE | 使用含 `luci-compat` 的 LuCI | 由构建树的包管理器决定 |
| ImmortalWrt | 21.02+ | 由构建树的包管理器决定 |

`Makefile` 使用标准 `BuildPackage`：构建树为 opkg 时输出 `.ipk`，`CONFIG_USE_APK=y` 时输出 `.apk`，无需为两种格式分别维护。`luci-compat` 已写入 `DEPENDS`，由包管理器自动安装。

本 LuCI 应用为 **noarch**（`PKGARCH:=all`）：包内只有 Lua / HTML / shell 脚本，同一份 `.ipk` / `.apk` 可安装在所有架构上。架构相关的只有 `pcdn-detect` 二进制，它不包含在本包内，由「下载/更新」按设备架构单独获取。

## 随固件编译

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

## 手动安装到路由器

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

## 依赖

- `luci-base`
- `luci-compat`（Lua CBI / `luci.model.uci` 兼容层；已写入 `DEPENDS`，由 opkg / apk 自动安装）
- 下载功能需要 `curl` 或 `wget`（BusyBox 自带 `wget` 即可）
- 路由表 / 封禁功能依赖 `iptables` 或 `nftables`（由 pcdn-detect 自行调用）
