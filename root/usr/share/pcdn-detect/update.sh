#!/bin/sh
# pcdn-detect 二进制下载 / 更新脚本
#
# 用法：update.sh <下载地址> [安装路径]
#   下载地址支持 http:// 与 https://，需指向未压缩的 ELF 二进制
#   安装路径默认 /usr/bin/pcdn-detect
#
# 说明：
#   - 下载后校验 ELF 头与文件大小，安装后执行 -v 自检，失败自动回滚；
#   - 进度写入 /tmp/pcdn-detect-update.log，供 LuCI 轮询；
#   - 运行中的服务在更新成功后自动重启（需 enabled=1）。

set -u

URL="${1:-}"
BIN="${2:-/usr/bin/pcdn-detect}"
LOG="/tmp/pcdn-detect-update.log"
RUNNING="/tmp/pcdn-detect-update.running"
TMP="/tmp/pcdn-detect.download.$$"
BAK="${BIN}.bak"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
	log "错误：$*"
	log "=== 更新失败 ==="
	exit 1
}

if [ -e "$RUNNING" ]; then
	echo "已有下载任务正在进行，请稍后再试"
	exit 1
fi

: >"$LOG"
# 之后所有输出（含 curl/wget 的错误）都写入日志，供 LuCI 轮询
exec >>"$LOG" 2>&1

echo $$ >"$RUNNING"
trap 'rm -f "$RUNNING" "$TMP"' EXIT INT TERM

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

mkdir -p "$(dirname "$BIN")" || fail "无法创建目录：$(dirname "$BIN")"

if [ -f "$BIN" ]; then
	cp -f "$BIN" "$BAK" || fail "备份原程序失败"
	log "已备份原程序：$BAK"
fi

chmod 0755 "$TMP" || fail "设置权限失败"
if ! mv -f "$TMP" "$BIN"; then
	if [ -f "$BAK" ]; then
		cp -f "$BAK" "$BIN"
		chmod 0755 "$BIN"
		log "安装失败，已恢复原程序"
	fi
	fail "安装失败（无法覆盖 $BIN）"
fi
chmod 0755 "$BIN"

VERSION="$("$BIN" -v 2>&1 | head -n 1)"
case "$VERSION" in
	"" | *"not found"* | *"Permission denied"* | *"Exec format error"* | *"No such file"*)
		log "自检失败：$VERSION"
		if [ -f "$BAK" ]; then
			mv -f "$BAK" "$BIN"
			chmod 0755 "$BIN"
			log "已回滚到原程序"
		fi
		fail "新程序无法运行（架构不匹配或文件损坏）"
		;;
esac

log "安装成功：$BIN"
log "版本：$VERSION"

if /etc/init.d/pcdn-detect enabled >/dev/null 2>&1; then
	log "正在重启服务"
	/etc/init.d/pcdn-detect restart >/dev/null 2>&1
	log "服务已重启"
elif pidof "$(basename "$BIN")" >/dev/null 2>&1; then
	log "服务正在运行但未设置开机自启，请手动重启后生效"
fi

log "=== 更新完成 ==="
exit 0
