#
# LuCI 应用：pcdn-detect 前端
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
#   git clone <本仓库> package/luci-app-pcdn-detect
#   make menuconfig     # LuCI -> Applications -> luci-app-pcdn-detect
#   make package/luci-app-pcdn-detect/compile V=s
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pcdn-detect
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Womsxd <https://github.com/Womsxd>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
# 需要 luci-base 的 host 工具 po2lmo 来编译语言包
PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

# luci-compat 提供 Lua CBI / luci.model.uci 等兼容层：
# 官方 OpenWrt 21.02+、ImmortalWrt、当前 Lean LEDE 均提供该包。
define Package/luci-app-pcdn-detect
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI app for pcdn-detect (P2P CDN detector)
	PKGARCH:=all
	DEPENDS:=+luci-base +luci-compat
endef

define Package/luci-app-pcdn-detect/description
 LuCI support for pcdn-detect: service control, online TOML configuration,
 runtime log viewer and core binary downloader.
endef

# 纯脚本包，无需编译
define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-pcdn-detect/conffiles
/etc/config/pcdn-detect
endef

define Package/luci-app-pcdn-detect/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	cp -pR ./luasrc/* $(1)/usr/lib/lua/luci

	$(INSTALL_DIR) $(1)/
	cp -pR ./root/* $(1)/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/pcdn-detect.po $(1)/usr/lib/lua/luci/i18n/pcdn-detect.zh-cn.lmo
endef

define Package/luci-app-pcdn-detect/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/pcdn-detect enable >/dev/null 2>&1
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache
fi
exit 0
endef

define Package/luci-app-pcdn-detect/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	# 服务未运行时 procd/ubus 会返回 NOT_FOUND；这里必须兜住，
	# 否则 opkg 会打印 "Command failed: Not found" 并中断卸载。
	if [ -x /etc/init.d/pcdn-detect ]; then
		/etc/init.d/pcdn-detect stop >/dev/null 2>&1 || true
		/etc/init.d/pcdn-detect disable >/dev/null 2>&1 || true
	fi
	if command -v uci >/dev/null 2>&1; then
		uci -q batch <<-EOF >/dev/null 2>&1 || true
			delete ucitrack.@pcdn-detect[-1]
			commit ucitrack
		EOF
	fi
fi
exit 0
endef

$(eval $(call BuildPackage,luci-app-pcdn-detect))
