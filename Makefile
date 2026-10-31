#
# LuCI 应用：pcdn-detector 前端
#
# 支持源码树：
#   - 官方 OpenWrt（最低 20.02 / 21.02 系列）
#   - Lean LEDE
#   - ImmortalWrt
#
# 包格式由构建树自动决定：
#   - opkg 构建树（未启用 CONFIG_USE_APK，如 23.05 / 24.10）生成 .ipk
#   - apk 构建树（CONFIG_USE_APK=y，如 25.12 及更新）生成 .apk
#   本 Makefile 使用标准 BuildPackage，不需要为两种格式分别维护。
#
# 用法（OpenWrt / Lean / ImmortalWrt 源码树）：
#   git clone <本仓库> package/luci-app-pcdn-detector
#   make menuconfig     # LuCI -> Applications -> luci-app-pcdn-detector
#   make package/luci-app-pcdn-detector/compile V=s
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pcdn-detector
PKG_VERSION:=1.0.2
PKG_RELEASE:=3
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

# /etc/config/pcdn-detector 不再随包安装，也不注册为 conffile。
# 页面会把「更新源 / 版本 / 仓库 / 开机自启」等写回该文件，升级时它必然与包内
# 默认值不同，进而触发
#   resolve_conffiles: Existing conffile /etc/config/pcdn-detector is different ...
# 以及 /etc/config/pcdn-detector-opkg 副本（apk 则是 .apk-new）。
# 现在默认值作为普通文件放在 /usr/share/pcdn-detector/pcdn-detector.config，
# 由 postinst / uci-defaults 在文件缺失时创建：升级保留用户设置，
# 也不会再出现 conffile 冲突提示。

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
	# 默认 UCI 配置以模板形式随包安装（/usr/share 下，非 conffile）：
	# 仅在文件缺失时创建（首次安装 / 用户手动删除），升级保留现有设置。
	cfg="/etc/config/pcdn-detector"
	if [ ! -s "$$cfg" ]; then
		# 旧版本把该文件当作 conffile 发布：opkg 在升级前会把用户改过的内容
		# 备份为 <文件>-opkg，随后删除旧包独有的文件。这里优先恢复备份，
		# 避免从 conffile 版本升级时丢失用户设置。
		if [ -s "$$cfg-opkg" ]; then
			mv -f "$$cfg-opkg" "$$cfg"
		else
			cp -f /usr/share/pcdn-detector/pcdn-detector.config "$$cfg"
		fi
	fi
	# 旧版本升级时可能残留的 conffile 副本
	rm -f "$$cfg-opkg"

	/etc/init.d/pcdn-detector enable >/dev/null 2>&1
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

# 不再清理 /etc/config/ucitrack：该文件在 19.07+ 已废弃，包内也不再写入。
# UCI 配置不是 conffile，删除动作交给 postrm：升级时旧包的 prerm 也会执行，
# 集中在一处处理更不容易误删用户设置。
exit 0
endef

define Package/luci-app-pcdn-detector/postrm
#!/bin/sh
# UCI 配置由 postinst 创建、不随包安装（非 conffile）：卸载时手动删除；
# 升级（PKG_UPGRADE=1）保留用户设置。
[ -n "$${IPKG_INSTROOT}" ] && exit 0

if [ "$${PKG_UPGRADE}" != "1" ]; then
	rm -f /etc/config/pcdn-detector
	rm -f /etc/config/pcdn-detector-opkg
fi

exit 0
endef

$(eval $(call BuildPackage,luci-app-pcdn-detector))
