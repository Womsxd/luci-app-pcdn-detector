local util = require "luci.model.pcdn_util"

local m, s, o

m = Map("pcdn-detector", translate("PCDN 检测"))
m.description = translate("在 LAN 侧网卡抓包，按「设备 MAC + 本地端口」统计对端公网 IP 数量；超过阈值即判定疑似 PCDN，并可选自动对接防火墙封禁。")

m:section(SimpleSection).template = "pcdn-detector/status"

s = m:section(TypedSection, "pcdn-detector", translate("服务设置"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("开机自启"))
o.default = 0
o.rmempty = false
o.description = translate("随系统启动。概览页的「启动 / 停止」按钮会同步修改此开关；取消勾选不会立即停止正在运行的服务。")

o = s:option(Value, "config_path", translate("配置文件路径"))
o.default = "/etc/pcdn-detect/pcdn-detect.toml"
o.rmempty = false
o.datatype = "string"
o.description = translate("TOML 配置文件的绝对路径。可在「配置编辑」中在线修改。")

o = s:option(Value, "bin_path", translate("程序路径"))
o.default = "/usr/bin/pcdn-detect"
o.rmempty = false
o.datatype = "string"
o.description = translate("pcdn-detect 可执行文件路径，可在「下载/更新」中自动安装。")

o = s:option(Value, "extra_args", translate("附加启动参数"))
o.rmempty = true
o.placeholder = "-i br-lan -n 30 -t 60s"
o.description = translate("可选，按空格拆分后追加到启动命令。命令行参数优先于 TOML 配置文件。")

o = s:option(Flag, "direct_api", translate("直连后端 API（绕过 LuCI 代理）"))
o.default = 0
o.rmempty = false
o.description = translate("开启后，实时统计与端口明细由浏览器直接请求 pcdn-detect 的 HTTP API，不再每次轮询都启动 Lua 进程。需要 [http] listen 监听局域网地址（如 0.0.0.0:8080）、设置 token，并把本页来源加入 [http] cors_allowed_origins；条件不满足时自动回退到 LuCI 代理。")

-- 保存 UCI 后让开关立即生效（reload_config 已由 procd trigger 兜底）
m.on_after_commit = function()
	local cursor = require("luci.model.uci").cursor()
	if cursor:get("pcdn-detector", "main", "enabled") ~= "1" then
		return
	end

	local bin = cursor:get("pcdn-detector", "main", "bin_path") or "/usr/bin/pcdn-detect"

	if util.pid_of(bin) then
		luci.sys.call("/etc/init.d/pcdn-detector reload >/dev/null 2>&1")
	else
		luci.sys.call("/etc/init.d/pcdn-detector start >/dev/null 2>&1")
	end
end

return m
