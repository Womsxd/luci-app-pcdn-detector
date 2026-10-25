#!/bin/sh
# pcdn-detect 二进制下载 / 更新脚本
#
# 用法：
#   update.sh <下载地址> [安装路径] [允许覆盖安装: 0/1]
#   update.sh --space [安装路径]        只探测剩余空间，输出 key=value（供 LuCI 预览）
#
# 下载位置按剩余空间自动选择，优先 /tmp（不把下载过程写到闪存）：
#   tmp        /tmp >= 24 MiB    ：下载到 /tmp，再复制到目标目录（下载期间占用内存）
#   direct     目标分区 >= 16 MiB：/tmp 不足时下载到目标目录下的临时文件，同分区 rename 覆盖
#   overwrite  两者都不足        ：先删除旧程序再原地下载；需显式允许，失败无法回滚
#
# 其他说明：
#   - 下载后校验 ELF 头与文件大小，安装后执行 -v 自检，失败自动回滚；
#   - 备份用 rename 完成，不额外占用闪存空间；更新成功后删除临时文件与备份；
#   - 进度写入 /tmp/pcdn-detect-update.log，供 LuCI 轮询；
#   - 运行中的服务在更新成功后自动重启（需 enabled=1）。

set -u

URL="${1:-}"
BIN="${2:-/usr/bin/pcdn-detect}"
ALLOW_OVERWRITE="${3:-}"

LOG="/tmp/pcdn-detect-update.log"
RUNNING="/tmp/pcdn-detect-update.running"
BAK="${BIN}.bak"

# 空间阈值（KiB）：目标目录 16 MiB，/tmp 24 MiB
DIR_MIN_KB=16384
TMP_MIN_KB=24576
# 删除旧程序后至少要剩这么多，否则必然装不下
MIN_AFTER_PURGE_KB=8192

TMP=""
STAGE=""
HAS_BAK=0
DIR_KB=0
TMP_KB=0
MODE=""

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
	log "错误：$*"
	log "=== 更新失败 ==="
	exit 1
}

# 目标路径所在分区的可用空间（KiB），失败时返回 0
free_kb() {
	local kb
	kb="$(df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9')"
	[ -n "$kb" ] || kb=0
	echo "$kb"
}

# 根据剩余空间决定下载位置：direct / tmp / overwrite
probe_space() {
	local dir
	dir="$(dirname "$BIN")"

	# 目标目录可能尚未创建（-p 会创建它）：向上找最近的已存在父目录再取空间，
	# 这样 --space 的预判与 mkdir -p 之后落在同一分区
	while [ -n "$dir" ] && [ "$dir" != "." ] && [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
		dir="$(dirname "$dir")"
	done
	[ -d "$dir" ] || dir="/"

	DIR_KB="$(free_kb "$dir")"
	TMP_KB=0
	[ -d /tmp ] && TMP_KB="$(free_kb /tmp)"

	# 优先 /tmp：下载过程落在内存，不写闪存；/tmp 不够再直接写目标分区
	if [ "$TMP_KB" -ge "$TMP_MIN_KB" ]; then
		MODE="tmp"
	elif [ "$DIR_KB" -ge "$DIR_MIN_KB" ]; then
		MODE="direct"
	else
		MODE="overwrite"
	fi
}

# 第三个参数优先；未传入时读取 UCI 开关（手工执行也遵循界面设置）
resolve_allow() {
	case "${1:-}" in
		0 | 1)
			echo "$1"
			return 0
			;;
	esac

	if command -v uci >/dev/null 2>&1; then
		case "$(uci -q get pcdn-detector.main.allow_overwrite 2>/dev/null)" in
			1 | true | on | yes)
				echo 1
				return 0
				;;
		esac
	fi

	echo 0
}

restore_bak() {
	if [ "$HAS_BAK" = "1" ] && [ -f "$BAK" ]; then
		mv -f "$BAK" "$BIN" && chmod 0755 "$BIN"
		HAS_BAK=0
		log "已回滚到原程序：$BIN"
	fi
}

cleanup() {
	[ -n "$TMP" ] && rm -f "$TMP"
	[ -n "$STAGE" ] && rm -f "$STAGE"
	rm -f "$RUNNING"
	:
}

# ---------------------------------------------------------------------------
# --space：只探测空间，不写日志、不占用 RUNNING
# ---------------------------------------------------------------------------
if [ "$URL" = "--space" ]; then
	probe_space
	echo "mode=$MODE dir_kb=$DIR_KB tmp_kb=$TMP_KB dir_min_kb=$DIR_MIN_KB tmp_min_kb=$TMP_MIN_KB"
	exit 0
fi

if [ -e "$RUNNING" ]; then
	echo "已有下载任务正在进行，请稍后再试"
	exit 1
fi

: >"$LOG"
# 之后所有输出（含 curl/wget 的错误）都写入日志，供 LuCI 轮询
exec >>"$LOG" 2>&1

echo $$ >"$RUNNING"
trap 'cleanup' EXIT INT TERM

# 上次更新被中断（如断电）导致只剩备份时，先恢复旧程序
if [ ! -e "$BIN" ] && [ -f "$BAK" ]; then
	if mv -f "$BAK" "$BIN"; then
		chmod 0755 "$BIN"
		log "检测到上次更新中断，已从备份恢复：$BIN"
	fi
fi

log "=== 开始下载 ==="
log "地址：$URL"
log "目标：$BIN"

[ -n "$URL" ] || fail "下载地址为空"
case "$URL" in
	http://* | https://*) ;;
	*) fail "仅支持 http:// 或 https:// 地址" ;;
esac
case "$URL" in
	*[[:space:]]*) fail "下载地址包含空白字符" ;;
esac

ALLOW_OVERWRITE="$(resolve_allow "$ALLOW_OVERWRITE")"

DIR="$(dirname "$BIN")"
mkdir -p "$DIR" || fail "无法创建目录：$DIR"

probe_space
log "剩余空间：$DIR ${DIR_KB} KiB（需 ${DIR_MIN_KB} KiB），/tmp ${TMP_KB} KiB（需 ${TMP_MIN_KB} KiB）"

case "$MODE" in
	tmp)
		TMP="/tmp/pcdn-detect.download.$$"
		log "下载方式：/tmp 空间充足，先下载到内存再复制到目标目录（下载期间占用内存）"
		;;
	direct)
		TMP="$DIR/.pcdn-detect.download.$$"
		log "下载方式：/tmp 空间不足，改为直接写入目标目录（同分区 rename）"
		;;
	*)
		if [ "$ALLOW_OVERWRITE" != "1" ]; then
			fail "空间不足：$DIR 剩 ${DIR_KB} KiB（需 ${DIR_MIN_KB} KiB），/tmp 剩 ${TMP_KB} KiB（需 ${TMP_MIN_KB} KiB）；请清理空间，或在 LuCI「下载/更新」中开启「空间不足时覆盖安装」"
		fi

		log "警告：空间不足，将删除旧程序后重新下载（更新失败无法回滚）"
		if [ -e "$BIN" ]; then
			rm -f "$BIN" || fail "无法删除旧程序：$BIN"
		fi

		AFTER_KB="$(free_kb "$DIR")"
		log "删除旧程序后剩余：$AFTER_KB KiB"
		[ "$AFTER_KB" -ge "$MIN_AFTER_PURGE_KB" ] ||
			fail "删除旧程序后仍只剩 $AFTER_KB KiB，无法安装新版本"

		TMP="$DIR/.pcdn-detect.download.$$"
		;;
esac

command -v curl >/dev/null 2>&1 && DOWNLOADER="curl" || {
	command -v wget >/dev/null 2>&1 && DOWNLOADER="wget" || fail "系统缺少 curl / wget"
}
log "下载工具：$DOWNLOADER"

if [ "$DOWNLOADER" = "curl" ]; then
	curl -fL -sS --connect-timeout 20 --retry 2 -o "$TMP" "$URL" || fail "下载失败（curl）"
else
	wget -O "$TMP" "$URL" || fail "下载失败（wget）"
fi

[ -s "$TMP" ] || fail "下载的文件为空"

SIZE="$(wc -c <"$TMP" | tr -d ' ')"
log "下载完成：$SIZE 字节"

[ "$SIZE" -ge 200000 ] || fail "文件过小（$SIZE 字节），可能不是 pcdn-detect 二进制"

MAGIC="$(head -c 4 "$TMP" | od -An -tx1 | tr -d ' \n')"
[ "$MAGIC" = "7f454c46" ] || fail "文件不是 ELF 可执行文件（可能是错误页面或文件损坏）"

STAGE="$TMP"
if [ "$MODE" = "tmp" ]; then
	# 跨分区：先复制到目标目录再 rename；复制失败不影响旧程序
	STAGE="$DIR/.pcdn-detect.new.$$"
	if ! cp -f "$TMP" "$STAGE"; then
		rm -f "$STAGE"
		STAGE=""
		fail "无法复制到 $DIR（需要 $SIZE 字节，剩余 $(free_kb "$DIR") KiB；旧程序未被改动）"
	fi
	# 复制完成后立刻释放 /tmp（内存）
	rm -f "$TMP"
	TMP=""
	log "已复制到目标目录，/tmp 临时文件已清理"
fi

# 备份用 rename：同目录移动，不额外占用闪存空间
if [ -f "$BIN" ]; then
	rm -f "$BAK"
	if mv -f "$BIN" "$BAK"; then
		HAS_BAK=1
		log "已备份原程序（rename，未额外占用空间）：$BAK"
	else
		log "警告：无法备份原程序，继续安装"
	fi
fi

chmod 0755 "$STAGE" || {
	restore_bak
	fail "设置执行权限失败：$STAGE"
}

if ! mv -f "$STAGE" "$BIN"; then
	restore_bak
	fail "安装失败（无法覆盖 $BIN）"
fi
STAGE=""
chmod 0755 "$BIN"

VERSION="$("$BIN" -v 2>&1 | head -n 1)"
case "$VERSION" in
	"" | *"not found"* | *"Permission denied"* | *"Exec format error"* | *"No such file"*)
		log "自检失败：$VERSION"
		restore_bak
		fail "新程序无法运行（架构不匹配或文件损坏）"
		;;
esac

log "安装成功：$BIN"
log "版本：$VERSION"

# 更新完成：临时文件与备份都不再需要（备份仅用于本次回滚）
if [ "$HAS_BAK" = "1" ]; then
	rm -f "$BAK" && log "已删除备份：$BAK"
	HAS_BAK=0
fi
if [ -n "$TMP" ]; then
	rm -f "$TMP"
	TMP=""
fi

if /etc/init.d/pcdn-detector enabled >/dev/null 2>&1; then
	log "正在重启服务"
	/etc/init.d/pcdn-detector restart >/dev/null 2>&1
	log "服务已重启"
elif pidof "$(basename "$BIN")" >/dev/null 2>&1; then
	log "服务正在运行但未设置开机自启，请手动重启后生效"
fi

log "=== 更新完成 ==="
exit 0
