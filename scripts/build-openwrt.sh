#!/usr/bin/env bash
#
# 使用官方 OpenWrt 源码编译 luci-app-pcdn-detector 的 ipk / apk
#
# 用法：
#   ./scripts/build-openwrt.sh <21.02|22.03|23.05|24.10|all> [--sdk] [--jobs N] [--update] [--clean]
#
#   21.02 / 22.03 / 23.05 -> ipk
#   24.10                 -> apk
#   all                   -> 依次编译 23.05(ipk) 与 24.10(apk)
#
# 两种模式：
#   默认        完整官方源码，首次需编译 tools/toolchain，最慢但最接近官方发布
#   --sdk       官方 SDK，只编译包本身，速度快很多（推荐日常打包）
#
# 说明：
#   - LuCI 包声明为 noarch（PKGARCH:=all），这里仅用 x86/64 作为构建目标，
#     产物可安装到任意设备架构；
#   - SDK 模式下源码树放在 build/sdk-<version>，源码模式放在 build/openwrt-<version>；
#     产物都复制到 dist/openwrt-<version>/；
#   - SDK 模式约需 10 GiB 磁盘；完整源码模式建议 20 GiB 以上；
#   - 仅供 Linux 构建主机使用。

set -euo pipefail

trap 'echo "构建失败：脚本第 $LINENO 行" >&2' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_URL="${OPENWRT_GIT_URL:-https://github.com/openwrt/openwrt.git}"
MIRROR="${OPENWRT_MIRROR:-https://downloads.openwrt.org}"
FALLBACK="${OPENWRT_MIRROR_FALLBACK:-}"
NO_FALLBACK=1
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
CLEAN=0
UPDATE=0
MODE="source"
SDK_URL="${SDK_URL:-}"
VERSION=""

usage() {
	cat <<EOF
用法: $(basename "$0") <21.02|22.03|23.05|24.10|all> [选项]

  --sdk            使用官方 SDK（只编译包，速度最快）
  --update         更新源码树 / feeds（默认复用已有内容）
  --jobs N, -j N   并行编译任务数（默认: $JOBS）
  --sdk-url URL    指定 SDK 压缩包地址（网络受限或固定版本时使用）
  --mirror URL     指定 SDK 镜像站，或使用预设：
                     official（默认）、ustc、tencent（公网）、tencent-intra（腾讯云内网）
  --fallback URL   显式指定备用镜像（默认不回退）
  --no-fallback    镜像缺少 SDK 时直接报错（默认行为）
  --clean          删除对应版本的源码树 / SDK 后重新下载
  -h, --help       显示帮助

示例:
  ./scripts/build-openwrt.sh 24.10 --sdk   # 用官方 SDK 快速生成 apk
  ./scripts/build-openwrt.sh 23.05 --sdk   # 用官方 SDK 快速生成 ipk
  ./scripts/build-openwrt.sh all --sdk     # 依次生成 ipk + apk
  ./scripts/build-openwrt.sh 23.05         # 完整官方源码（首次较慢）

  # 国内镜像
  ./scripts/build-openwrt.sh all --sdk --mirror ustc
  ./scripts/build-openwrt.sh 24.10 --sdk --mirror tencent
  ./scripts/build-openwrt.sh 24.10 --sdk --mirror tencent-intra

可用环境变量:
  OPENWRT_GIT_URL          官方源码地址（默认 $SOURCE_URL）
  OPENWRT_MIRROR           SDK 镜像站（默认 official，也可用 ustc / tencent / tencent-intra）
  OPENWRT_MIRROR_FALLBACK  备用镜像（设置后才会启用回退）
  SDK_URL                  指定 SDK 压缩包地址
  JOBS                     并行任务数
EOF
}

die() {
	echo "错误：$*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--clean)
			CLEAN=1
			shift
			;;
		--sdk)
			MODE="sdk"
			shift
			;;
		--source)
			MODE="source"
			shift
			;;
		--update)
			UPDATE=1
			shift
			;;
		--sdk-url)
			[ $# -ge 2 ] || die "$1 需要参数"
			SDK_URL="$2"
			shift 2
			;;
		--sdk-url=*)
			SDK_URL="${1#*=}"
			shift
			;;
		--mirror)
			[ $# -ge 2 ] || die "$1 需要参数"
			MIRROR="$2"
			MODE="sdk"
			shift 2
			;;
		--mirror=*)
			MIRROR="${1#*=}"
			MODE="sdk"
			shift
			;;
		--fallback)
			[ $# -ge 2 ] || die "$1 需要参数"
			FALLBACK="$2"
			NO_FALLBACK=0
			MODE="sdk"
			shift 2
			;;
		--fallback=*)
			FALLBACK="${1#*=}"
			NO_FALLBACK=0
			MODE="sdk"
			shift
			;;
		--no-fallback)
			NO_FALLBACK=1
			FALLBACK=""
			shift
			;;
		-j|--jobs)
			[ $# -ge 2 ] || die "$1 需要参数"
			JOBS="$2"
			shift 2
			;;
		--jobs=*)
			JOBS="${1#*=}"
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		-*)
			die "未知选项：$1"
			;;
		*)
			[ -z "$VERSION" ] || die "只能指定一个版本"
			VERSION="$1"
			shift
			;;
	esac
done

[ -n "$VERSION" ] || {
	usage
	exit 1
}

case "$VERSION" in
	21.02|22.03|23.05|24.10|all) ;;
	*) die "不支持的版本：$VERSION" ;;
esac

case "$JOBS" in
	''|*[!0-9]*) die "--jobs 必须是正整数：$JOBS" ;;
esac
[ "$JOBS" -gt 0 ] || die "--jobs 必须大于 0"

if [ -n "$SDK_URL" ]; then
	MODE="sdk"
fi

normalize_mirror() {
	local m="${1%/}"
	case "$m" in
		official|openwrt)
			echo "https://downloads.openwrt.org"
			;;
		ustc|ustc-edu)
			echo "https://mirrors.ustc.edu.cn/openwrt"
			;;
		tencent)
			echo "https://mirrors.cloud.tencent.com/openwrt"
			;;
		tencent-intra|tencent-internal|tencent-intranet)
			echo "http://mirrors.tencentyun.com/openwrt"
			;;
		*)
			echo "${m%/}"
			;;
	esac
}

validate_mirror() {
	case "$1" in
		http://*|https://*) ;;
		*) die "$2 必须是 http(s) 地址或预设名（official / ustc / tencent / tencent-intra）" ;;
	esac
}

MIRROR="$(normalize_mirror "$MIRROR")"
validate_mirror "$MIRROR" "--mirror"

# OPENWRT_MIRROR_FALLBACK 非空时才启用回退
if [ -n "$FALLBACK" ]; then
	NO_FALLBACK=0
fi

if [ "$NO_FALLBACK" = "0" ]; then
	FALLBACK="$(normalize_mirror "$FALLBACK")"
	validate_mirror "$FALLBACK" "--fallback"
fi

if [ "$VERSION" = "all" ] && [ -n "$SDK_URL" ]; then
	die "--sdk-url 不能与 all 一起使用；请分别编译 23.05 与 24.10"
fi

for cmd in git make gcc g++ tar gzip wget find awk sed sha256sum; do
	command -v "$cmd" >/dev/null 2>&1 || die "缺少命令：$cmd"
done

if [ "$(id -u)" = "0" ]; then
	echo "警告：root 编译会让 build/、dist/ 等产物归 root 所有；之后普通用户在同一棵树编译会遇到权限 / git safe.directory 问题。建议使用普通用户，或在隔离容器中始终用 root。" >&2
fi

avail_kb="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}' || echo 0)"
if [ "${avail_kb:-0}" -lt 20971520 ]; then
	echo "警告：磁盘剩余约 $(( ${avail_kb:-0} / 1024 )) MiB，建议至少 20 GiB" >&2
fi

copy_package() {
	local tree="$1"
	local pkgdir="$tree/package/luci-app-pcdn-detector"

	rm -rf "$pkgdir"
	mkdir -p "$pkgdir"

	cp -a "$ROOT_DIR/Makefile" "$pkgdir/"
	cp -a "$ROOT_DIR/luasrc" "$ROOT_DIR/root" "$ROOT_DIR/po" "$pkgdir/"

	chmod 755 \
		"$pkgdir/root/etc/init.d/pcdn-detector" \
		"$pkgdir/root/etc/uci-defaults/40_luci-pcdn-detector" \
		"$pkgdir/root/usr/share/pcdn-detector/update.sh" 2>/dev/null || true
}

# 7z 会以“Dangerous link path”为由跳过带 .. 的符号链接，
# 但 SDK 里这些链接（如 toolchain sys-include -> ../include）是必需的。
# 7z 解包后，从 tar 清单里重新创建这些链接。
restore_symlinks() {
	local tarfile="$1"
	local dest="$2"
	local log="$3"
	local list="$dest/.tar-symlinks.list"
	local count=0
	local path target

	if ! tar --quoting-style=literal -tvf "$tarfile" 2>>"$log" \
		| awk '
			/^l/ {
				line = $0
				target = line
				sub(/^.* -> /, "", target)
				path = line
				sub(/^.*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] /, "", path)
				sub(/ -> .*/, "", path)
				print path "\t" target
			}
		' > "$list"; then
		rm -f "$list"
		return 1
	fi

	while IFS=$'\t' read -r path target; do
		[ -n "$path" ] || continue
		mkdir -p "$dest/$(dirname "$path")" 2>>"$log" || {
			rm -f "$list"
			return 1
		}
		# 7z 可能留下同名空文件，-f 会替换它
		ln -sfn "$target" "$dest/$path" 2>>"$log" || {
			rm -f "$list"
			return 1
		}
		count=$((count + 1))
	done < "$list"

	rm -f "$list"
	echo "7z 解压后已恢复符号链接：$count 个" >&2
	return 0
}

# 某些受限文件系统 / 沙箱里 GNU tar 会报 "Function not implemented"（ENOSYS），
# 用 7z 作为兜底：先把 xz/zst 解成 tar，再交给 7z 解包。
sevenzip_extract() {
	local archive="$1"
	local dest="$2"
	local tmp="$3"
	local log="$4"
	local sz=""
	local rc

	for c in 7z 7zz 7za; do
		if command -v "$c" >/dev/null 2>&1; then
			sz="$c"
			break
		fi
	done

	if [ -z "$sz" ]; then
		echo "未找到 7z / 7zz / 7za" >>"$log"
		return 1
	fi

	case "$archive" in
		*.tar.xz)
			command -v xz >/dev/null 2>&1 || {
				echo "7z 兜底需要 xz" >>"$log"
				return 1
			}
			xz -dc "$archive" >"$tmp" 2>>"$log" || return 1
			;;
		*.tar.zst)
			command -v zstd >/dev/null 2>&1 || {
				echo "7z 兜底需要 zstd" >>"$log"
				return 1
			}
			zstd -dc "$archive" >"$tmp" 2>>"$log" || return 1
			;;
		*.tar)
			cp -f "$archive" "$tmp" 2>>"$log" || return 1
			;;
		*)
			return 1
			;;
	esac

	"$sz" x -y -o"$dest" "$tmp" >>"$log" 2>&1
	rc=$?

	if [ "$rc" -eq 2 ]; then
		# 仅允许 “Dangerous link” 这类符号链接警告；其它错误仍视为失败
		if grep '^ERROR:' "$log" 2>/dev/null | grep -vq 'Dangerous link'; then
			rm -f "$tmp"
			return 1
		fi
		echo "7z 跳过了部分符号链接，正在从 tar 恢复..." >&2
	elif [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
		rm -f "$tmp"
		return 1
	fi

	restore_symlinks "$tmp" "$dest" "$log" || {
		rm -f "$tmp"
		return 1
	}

	rm -f "$tmp"
	return 0
}

prepare_sdk() {
	local ver="$1"
	local root="$ROOT_DIR/build/sdk-$ver"
	local marker="$root/.extract-ok"
	local feeds

	if [ "$CLEAN" = "1" ]; then
		rm -rf "$root"
	fi

	if [ -d "$root" ]; then
		feeds="$(find "$root" -maxdepth 3 -type f -path '*/scripts/feeds' -print -quit 2>/dev/null || true)"
		if [ -n "$feeds" ] && [ -f "$marker" ]; then
			dirname "$(dirname "$feeds")"
			return 0
		fi
	fi

	command -v curl >/dev/null 2>&1 || die "SDK 模式需要 curl"

	mkdir -p "$root"

	local url="$SDK_URL"
	local fname=""

	if [ -z "$url" ]; then
		local versions rel base listing mirror tried count
		local -a mirrors=("$MIRROR")

		if [ "$NO_FALLBACK" = "0" ] && [ "$FALLBACK" != "$MIRROR" ]; then
			mirrors+=("$FALLBACK")
		fi

		tried=""
		for mirror in "${mirrors[@]}"; do
			if [ -n "$tried" ]; then
				tried="$tried、"
			fi
			tried="${tried}${mirror}"

			versions="$(curl -fsSL --connect-timeout 5 --max-time 10 "$mirror/releases/" 2>/dev/null \
				| grep -oE "${ver//./\\.}\.[0-9]+" | sort -Vu | sort -Vr || true)"
			if [ -z "$versions" ]; then
				echo "镜像 $mirror 未列出 OpenWrt $ver 版本，尝试下一个..." >&2
				continue
			fi

			# 从最新补丁版开始找，避免镜像站列表里有目录但 SDK 尚未同步。
			# 最多尝试 3 个补丁版，避免镜像不可达时等待过久。
			count=0
			for rel in $versions; do
				count=$((count + 1))
				[ "$count" -le 3 ] || break

				base="$mirror/releases/$rel/targets/x86/64/"
				listing="$(curl -fsSL --connect-timeout 5 --max-time 10 "$base" 2>/dev/null || true)"

				# 优先 .tar.xz（大多数构建机自带 xz），没有再选 .tar.zst
				fname="$(printf '%s' "$listing" \
					| grep -oE 'openwrt-sdk-[^"<> ]+\.tar\.xz' | head -1 || true)"
				if [ -z "$fname" ]; then
					fname="$(printf '%s' "$listing" \
						| grep -oE 'openwrt-sdk-[^"<> ]+\.tar\.zst' | head -1 || true)"
				fi

				if [ -n "$fname" ]; then
					url="${base%/}/$fname"
					echo "使用镜像：$mirror（$rel）" >&2
					break 2
				fi
			done

			echo "镜像 $mirror 未同步 OpenWrt $ver 的 SDK，尝试下一个..." >&2
		done

		[ -n "$url" ] || die "在 $tried 未找到 OpenWrt $ver 的 SDK（镜像可能未同步），可用 --sdk-url 指定完整地址"
	else
		fname="${url##*/}"
		fname="${fname%%\?*}"
	fi

	local file="$root/$fname"
	if [ ! -f "$file" ]; then
		echo "下载 SDK：$url" >&2
		curl -fL --retry 2 -o "$file.part" "$url"
		mv -f "$file.part" "$file"
	fi

	local tar_log="$root/.tar-extract.log"

	case "$fname" in
		*.tar.zst)
			command -v zstd >/dev/null 2>&1 || die "解压 .tar.zst 需要 zstd"
			if ! { zstd -dc "$file" | tar -xf - -C "$root"; } >"$tar_log" 2>&1; then
				echo "tar 解压失败，尝试 7z 解压（保留已下载的 SDK）..." >&2
				sevenzip_extract "$file" "$root" "$root/.sdk-extract.tar" "$tar_log" \
					|| die "SDK 解压失败（tar 与 7z 均失败），详见 $tar_log"
			fi
			;;
		*.tar.xz)
			command -v xz >/dev/null 2>&1 || die "解压 .tar.xz 需要 xz"
			if ! tar -xJf "$file" -C "$root" >"$tar_log" 2>&1; then
				echo "tar 解压失败，尝试 7z 解压（保留已下载的 SDK）..." >&2
				sevenzip_extract "$file" "$root" "$root/.sdk-extract.tar" "$tar_log" \
					|| die "SDK 解压失败（tar 与 7z 均失败），详见 $tar_log"
			fi
			;;
		*)
			die "不支持的 SDK 压缩格式：$fname"
			;;
	esac

	rm -f "$tar_log"

	feeds="$(find "$root" -maxdepth 3 -type f -path '*/scripts/feeds' -print -quit 2>/dev/null || true)"
	[ -n "$feeds" ] || die "SDK 解压后未找到 scripts/feeds"

	# 只有完整解压出 scripts/feeds 后才写完成标记，避免复用半成品目录
	printf '%s\n' "$fname" > "$marker"
	dirname "$(dirname "$feeds")"
}

build_one() {
	local ver="$1"
	local branch="openwrt-$ver"
	local tree=""
	local outdir="$ROOT_DIR/dist/openwrt-$ver"
	local ext="ipk"

	if [ "$ver" = "24.10" ]; then
		ext="apk"
	fi

	echo
	echo "============================================================"
	echo " 编译 luci-app-pcdn-detector for OpenWrt $ver（$ext）"
	echo " 模式：$MODE"
	echo "============================================================"

	if [ "$MODE" = "sdk" ]; then
		if ! tree="$(prepare_sdk "$ver")"; then
			return 1
		fi
		echo "使用 SDK：$tree"
	else
		tree="$ROOT_DIR/build/$branch"
		echo "源码树：$tree"

		if [ "$CLEAN" = "1" ]; then
			echo "清理源码树：$tree"
			rm -rf "$tree"
		fi

		if [ -d "$tree" ] && [ ! -d "$tree/.git" ]; then
			echo "目录存在但不是完整源码树，清理后重新克隆：$tree"
			rm -rf "$tree"
		fi

		if [ ! -d "$tree/.git" ]; then
			mkdir -p "$ROOT_DIR/build"
			echo "克隆 $SOURCE_URL（$branch）..."
			git clone --depth 1 --branch "$branch" "$SOURCE_URL" "$tree"
		elif [ "$UPDATE" = "1" ]; then
			echo "更新源码树：$tree"
			git -C "$tree" fetch --depth 1 origin "$branch"
			git -C "$tree" reset --hard FETCH_HEAD
		else
			echo "复用源码树（--update 可更新到分支最新）"
		fi

		local cur
		cur="$(git -C "$tree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
		if [ "$cur" != "$branch" ]; then
			die "源码树当前分支为 $cur，不是 $branch；请加 --clean 重新克隆"
		fi
	fi

	echo "产物目录：$outdir"
	copy_package "$tree"

	if [ "$UPDATE" = "1" ] || [ ! -d "$tree/package/feeds/luci" ] || [ ! -f "$tree/feeds/luci.index" ]; then
		if ! command -v perl >/dev/null 2>&1 || ! perl -MFindBin -e1 >/dev/null 2>&1; then
			die "更新 feeds 需要 Perl 的 FindBin 模块：Fedora 请安装 perl-FindBin，Debian/Ubuntu 请安装 perl"
		fi

		echo "更新 feeds ..."
		(
			cd "$tree"
			./scripts/feeds update -a
			./scripts/feeds install -a -p luci
		)
	else
		echo "复用已有 feeds（--update 可更新）"
	fi

	echo "写入 .config ..."
	if [ "$MODE" = "sdk" ]; then
		# SDK 若自带 .config，保留其目标配置，只增删包选项；
		# 部分 SDK（例如 23.05）不带 .config，则按固定目标 x86/64 生成。
		local cfg="$tree/.config"

		if [ ! -s "$cfg" ]; then
			echo "SDK 未带 .config，生成 x86/64 基础配置"
			{
				echo "CONFIG_TARGET_x86=y"
				echo "CONFIG_TARGET_x86_64=y"
				echo "CONFIG_TARGET_x86_64_Generic=y"
			} > "$cfg"
		fi

		for sym in \
			CONFIG_PACKAGE_luci-app-pcdn-detector \
			CONFIG_PACKAGE_luci-compat \
			CONFIG_PACKAGE_luci-base \
			CONFIG_USE_APK; do
			sed -i "/^${sym}[= ]/d" "$cfg"
			sed -i "/^# ${sym} is not set/d" "$cfg"
		done

		{
			echo "CONFIG_PACKAGE_luci-app-pcdn-detector=y"
			echo "CONFIG_PACKAGE_luci-compat=y"
			echo "CONFIG_PACKAGE_luci-base=y"
			if [ "$ver" = "24.10" ]; then
				echo "CONFIG_USE_APK=y"
			fi
		} >> "$cfg"
	else
		{
			echo "CONFIG_TARGET_x86=y"
			echo "CONFIG_TARGET_x86_64=y"
			echo "CONFIG_TARGET_x86_64_Generic=y"
			echo "CONFIG_PACKAGE_luci-app-pcdn-detector=y"
			echo "CONFIG_PACKAGE_luci-compat=y"
			echo "CONFIG_PACKAGE_luci-base=y"
			if [ "$ver" = "24.10" ]; then
				echo "CONFIG_USE_APK=y"
			fi
		} > "$tree/.config"
	fi

	make -C "$tree" defconfig

	grep -q '^CONFIG_PACKAGE_luci-app-pcdn-detector=y' "$tree/.config" \
		|| die "defconfig 后未选中 luci-app-pcdn-detector"

	if [ "$ver" = "24.10" ] && ! grep -q '^CONFIG_USE_APK=y' "$tree/.config"; then
		echo "警告：24.10 未启用 CONFIG_USE_APK，产物可能是 ipk" >&2
	fi

	if [ "$MODE" = "source" ]; then
		echo "编译 tools ..."
		make -C "$tree" tools/install -j"$JOBS"

		echo "编译 toolchain ..."
		make -C "$tree" toolchain/install -j"$JOBS"
	else
		echo "SDK 模式：跳过 tools / toolchain 编译"
	fi

	echo "编译 LuCI 包 ..."
	make -C "$tree" package/luci-app-pcdn-detector/compile -j"$JOBS" V=s

	mkdir -p "$outdir"
	find "$outdir" -maxdepth 1 -type f \( -name '*.ipk' -o -name '*.apk' \) -delete
	find "$tree/bin/packages" -type f -name "luci-app-pcdn-detector*.$ext" \
		-exec cp -f {} "$outdir/" \;

	local count
	count="$(find "$outdir" -maxdepth 1 -type f -name "*.$ext" | wc -l)"
	if [ "$count" -eq 0 ]; then
		die "未找到 .$ext 产物，请检查上面的编译日志"
	fi

	echo
	echo "构建完成，产物："
	find "$outdir" -maxdepth 1 -type f -name "*.$ext" -print -exec ls -lh {} \;
	(
		cd "$outdir"
		sha256sum ./*."$ext" > SHA256SUMS
	)
	echo "校验文件：$outdir/SHA256SUMS"
}

if [ "$VERSION" = "all" ]; then
	rc=0
	rc23=0
	rc24=0

	# 子 shell 必须是独立命令（不能放在 || / if 条件里），否则会禁用 set -e；
	# 外层先关闭 errexit，保证 23.05 失败后仍继续 24.10。
	set +e
	( set -e; build_one 23.05 ); rc23=$?
	( set -e; build_one 24.10 ); rc24=$?
	set -e

	[ "$rc23" -eq 0 ] || rc=1
	[ "$rc24" -eq 0 ] || rc=1

	if [ "$rc" -ne 0 ]; then
		echo "提醒：部分版本构建失败，已完成的产物仍在 dist/ 下。" >&2
	fi
	exit "$rc"
else
	build_one "$VERSION"
fi
