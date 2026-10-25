#
# LuCI 应用：pcdn-detector 前端
#
# 支持源码树：
#   - 官方 OpenWrt（最低 20.02 / 21.02 系列）
#   - Lean LEDE
#   - ImmortalWrt
#
# 包格式由构建树自动决定：
#   - opkg 构建树（未启用 CONFIG_USE_APK，如 23.05 及更早）生成 .ipk
#   - apk 构建树（CONFIG_USE_APK=y，如 24.10+）生成 .apk
#   本 Makefile 使用标准 BuildPackage，不需要为两种格式分别维护。
#
# 用法（OpenWrt / Lean / ImmortalWrt 源码树）：
#   git clone <本仓库> package/luci-app-pcdn-detector
#   make menuconfig     # LuCI -> Applications -> luci-app-pcdn-detector
#   make package/luci-app-pcdn-detector/compile V=s
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pcdn-detector
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Womsxd <https://github.com/Womsxd>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
# 需要 luci-base 的 host 工具 po2lmo 来编译语言包
PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

# luci-compat 提供 Lua CBI / luci.model.uci 等兼容层：
# 官方 OpenWrt 21.02+、ImmortalWrt、当前 Lean LEDE 均提供该包。
define Package/luci-app-pcdn-detector
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI app for pcdn-detector (P2P CDN detector)
	PKGARCH:=all
	DEPENDS:=+luci-base +luci-compat
endef

define Package/luci-app-pcdn-detector/description
 LuCI support for pcdn-detector: service control, online TOML configuration,
 runtime log viewer and core binary downloader.
endef

# 纯脚本包，无需编译
define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-pcdn-detector/conffiles
/etc/config/pcdn-detector
endef

define Package/luci-app-pcdn-detector/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -pR ./luasrc/* $(1)/usr/lib/lua/luci

	$(INSTALL_DIR) $(1)/
	cp -pR ./root/* $(1)/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/pcdn-detector.po $(1)/usr/lib/lua/luci/i18n/pcdn-detector.zh-cn.lmo
endef

define Package/luci-app-pcdn-detector/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/pcdn-detector enable >/dev/null 2>&1
	# conffile 冲突时 opkg 会把新默认配置写成 <文件>-opkg；以用户现有配置为准，
	# 删除副本，避免 /etc/config 下堆积无用文件。
	rm -f /etc/config/pcdn-detector-opkg
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache
fi
exit 0
endef

define Package/luci-app-pcdn-detector/prerm
#!/bin/sh
# opkg 会把本脚本的 stdout/stderr 当作错误信息展示，统一丢弃。
# 本文件由 default_prerm 在子 shell 中 source；它随后还会自行执行
# init 脚本的 stop，那段输出由 init 脚本在 stop 时丢弃 stderr。
exec >/dev/null 2>&1

[ -n "$${IPKG_INSTROOT}" ] && exit 0

if [ -x /etc/init.d/pcdn-detector ]; then
	/etc/init.d/pcdn-detector stop || true
	/etc/init.d/pcdn-detector disable || true
fi

if command -v uci >/dev/null 2>&1; then
	uci -q batch <<-EOF || true
		delete ucitrack.@pcdn-detector[-1]
		commit ucitrack
	EOF
fi

# 不能在这里删 conffile：opkg 随后还要计算它的 sha256，
# 文件提前消失会报 "file_sha256sum_alloc: Failed to open file ..."。
# 删除动作交给 postrm。
exit 0
endef

define Package/luci-app-pcdn-detector/postrm
#!/bin/sh
# 卸载完成后再删 UCI 配置：prerm 阶段删除会让 opkg 处理 conffile 时报
# "file_sha256sum_alloc: Failed to open file ..."。
# 升级（PKG_UPGRADE=1）保留用户设置。
[ -n "$${IPKG_INSTROOT}" ] && exit 0

if [ "$${PKG_UPGRADE}" != "1" ]; then
	rm -f /etc/config/pcdn-detector
	rm -f /etc/config/pcdn-detector-opkg
fi

exit 0
endef

$(eval $(call BuildPackage,luci-app-pcdn-detector))
