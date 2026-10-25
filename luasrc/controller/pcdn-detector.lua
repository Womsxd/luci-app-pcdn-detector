--[[
luci-app-pcdn-detector 控制器

页面：
	/admin/services/pcdn-detector/overview	运行状态 + 服务设置
	/admin/services/pcdn-detector/config	完整 TOML 文本编辑（txt 方式）
	/admin/services/pcdn-detector/log		运行日志
	/admin/services/pcdn-detector/update	二进制下载 / 更新

接口（全部仅登录用户可访问）：
	status / svc / getconfig / saveconfig / resetsettings /
	getlog / stats / httpinfo / httpcheck /
	updateinfo / checkupdate / doupdate / updatelog

配置编辑采用「完整文件」模式：
	getconfig 直接返回完整 TOML，saveconfig 接收完整 TOML；
	后端不解析、不打补丁，只做 -T 校验、保存与热重载。
]]--

module("luci.controller.pcdn-detector", package.seeall)

local fs = require "nixio.fs"
local http = require "luci.http"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local toml = require "luci.model.pcdn_toml"
local util = require "luci.model.pcdn_util"

local APP = "pcdn-detector"
local SID = "main"

local DEFAULT_BIN = "/usr/bin/pcdn-detect"
local DEFAULT_CFG = "/etc/pcdn-detect/pcdn-detect.toml"
local CHECK_TOML = "/tmp/pcdn-detect.check.toml"
local CHECK_OUT = "/tmp/pcdn-detect.check.out"
local UPDATE_SCRIPT = "/usr/share/pcdn-detector/update.sh"
local UPDATE_LOG = "/tmp/pcdn-detect-update.log"
local UPDATE_FLAG = "/tmp/pcdn-detect-update.running"
local DEFAULT_REPO = "Womsxd/pcdn-detector"
local INITD = "/etc/init.d/pcdn-detector"

function index()
	entry({ "admin", "services", "pcdn-detector" },
		alias("admin", "services", "pcdn-detector", "overview"),
		_("PCDN 检测"), 60).dependent = true

	entry({ "admin", "services", "pcdn-detector", "overview" },
		cbi("pcdn-detector/overview"), _("概览"), 10).leaf = true

	entry({ "admin", "services", "pcdn-detector", "config" },
		cbi("pcdn-detector/config"), _("配置编辑"), 20).leaf = true

	entry({ "admin", "services", "pcdn-detector", "log" },
		cbi("pcdn-detector/log"), _("日志"), 30).leaf = true

	entry({ "admin", "services", "pcdn-detector", "update" },
		cbi("pcdn-detector/update"), _("下载/更新"), 40).leaf = true

	entry({ "admin", "services", "pcdn-detector", "status" },
		call("action_status")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "svc" },
		call("action_service")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "getconfig" },
		call("action_getconfig")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "saveconfig" },
		call("action_saveconfig")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "savechunk" },
		call("action_savechunk")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "savecommit" },
		call("action_savecommit")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "resetsettings" },
		call("action_resetsettings")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "getlog" },
		call("action_getlog")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "stats" },
		call("action_stats")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "device" },
		call("action_device")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "peers" },
		call("action_peers")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "httpinfo" },
		call("action_httpinfo")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "httpcheck" },
		call("action_httpcheck")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "updateinfo" },
		call("action_updateinfo")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "checkupdate" },
		call("action_checkupdate")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "doupdate" },
		call("action_doupdate")).leaf = true

	entry({ "admin", "services", "pcdn-detector", "updatelog" },
		call("action_updatelog")).leaf = true
end

---------------------------------------------------------------------------
-- 基础读取
---------------------------------------------------------------------------

local function uci_get(key, default)
	local v = uci:get(APP, SID, key)
	if v == nil then
		v = uci:get(APP, "@pcdn-detector[0]", key)
	end
	if v == nil or v == "" then
		return default
	end
	return v
end

local function bin_path()
	return uci_get("bin_path", DEFAULT_BIN)
end

local function config_path()
	return uci_get("config_path", DEFAULT_CFG)
end

-- 前向声明：配置文件不存在时由 pcdn-detect 自己生成默认内容（不再随包内嵌 TOML）
local default_config_text

local function read_config()
	local path = config_path()
	local content = fs.readfile(path)
	if not content then
		content = default_config_text() or ""
	end
	return content, path
end

-- 状态页 / 统计只关心这几个键：按需解析，不建整棵 TOML 表
local WANTED_KEYS = {
	http = { enabled = true, listen = true, token = true },
	capture = { interface = true, protocol = true },
	log = { level = true },
}

-- 只读用途：状态页与 HTTP 统计读取少量字段；配置编辑不经过这里
local function read_values()
	local content = read_config()
	return toml.read(content, WANTED_KEYS)
end

-- 从 [http] 段提取监听地址、端口、token（只读）
local function http_settings(vals)
	vals = vals or read_values()

	local listen = toml.get(vals, "http", "listen") or "127.0.0.1:8080"
	local token = toml.get(vals, "http", "token") or ""
	local host, port = util.parse_listen(listen)
	local url

	if host and port then
		url = "http://" .. (host:find(":", 1, true) and ("[" .. host .. "]") or host) .. ":" .. tostring(port)
	end

	return {
		enabled = toml.get(vals, "http", "enabled") == true,
		listen = listen,
		host = host,
		port = port,
		url = url,
		token = token,
		token_set = token ~= "",
	}
end

local function reply_json(data)
	http.prepare_content("application/json")
	http.header("Cache-Control", "no-store")
	http.write(util.json_encode(data))
end

-- 直连地址（浏览器绕过 LuCI 代理直接访问 pcdn-detect HTTP API）：
--   listen 绑到具体非回环地址 → 返回 http://ip:port；
--   绑到 0.0.0.0 / :: / 空主机 → 返回 ""，由前端用当前访问的主机名 + 端口拼接；
--   只绑回环地址 → 返回 nil + 原因（浏览器在别的机器上，连不到 127.0.0.1）。
local function direct_endpoint(listen, port)
	port = tonumber(port)
	if not port then
		return nil, "HTTP 端口无效"
	end

	local host = tostring(listen or ""):match("^%[?(.-)%]?:%d+$") or ""

	if host == "" or host == "0.0.0.0" or host == "::" then
		return ""
	end
	if host == "127.0.0.1" or host == "::1" or host == "localhost" then
		return nil, "listen 是回环地址，浏览器无法直连（请改为 0.0.0.0:端口 或局域网 IP）"
	end
	if host:find(":", 1, true) then
		return "http://[" .. host .. "]:" .. tostring(port)
	end
	return "http://" .. host .. ":" .. tostring(port)
end

local function reply_text(text)
	http.prepare_content("text/plain; charset=utf-8")
	http.header("Cache-Control", "no-store")
	http.write(text or "")
end

-- 查询参数编码：保留 RFC 3986 unreserved 字符，其余（如 MAC 里的 ':'）转义
local function url_encode(s)
	return (tostring(s or ""):gsub("[^%w%-%._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local HTTP_REASON = {
	[200] = "OK",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[413] = "Payload Too Large",
	[414] = "URI Too Long",
	[431] = "Request Header Fields Too Large",
	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[503] = "Service Unavailable",
}

-- 流式透传：先写状态码与响应头，再把 body 逐块转发给浏览器。
-- Lua 侧不解析上游 JSON（解析交给浏览器 JSON.parse），只保留当前块（≤16 KiB），
-- 峰值不随 body 线性增长；读取总量有上限，异常上游不会把 CGI 进程撑爆。
local function reply_upstream_stream(code, pump, close)
	if not code or code == 0 then
		if close then
			close()
		end
		reply_upstream_unreachable("HTTP API 无响应")
		return
	end

	http.status(code, HTTP_REASON[code] or "OK")
	http.prepare_content("application/json")
	http.header("Cache-Control", "no-store")
	pump(http.write)
end

-- 上游不可达时返回本地的 503 JSON（绕开 LuCI 默认错误页，前端好统一展示）
local function reply_upstream_unreachable(err)
	http.status(503, HTTP_REASON[503])
	reply_json({ ok = false, available = false, message = err or "无法访问 HTTP API" })
end

local function running_pid()
	return util.pid_of(bin_path())
end

-- 校验 TOML 文本：调用二进制自身的 -T/--test-config（与启动、热重载使用同一套规则）
local function validate_text(text)
	local bin = bin_path()
	if not fs.access(bin) then
		return false, "找不到可执行文件：" .. bin .. "\n请先在「下载/更新」中安装 pcdn-detect。"
	end

	fs.writefile(CHECK_TOML, text)
	os.remove(CHECK_OUT)

	local code = sys.call(string.format("%s -T -c %s >%s 2>&1",
		util.q(bin), util.q(CHECK_TOML), util.q(CHECK_OUT)))
	local out = fs.readfile(CHECK_OUT) or ""

	os.remove(CHECK_TOML)
	os.remove(CHECK_OUT)

	if code == 0 then
		return true, out
	end
	return false, out ~= "" and out or ("校验失败（退出码 " .. tostring(code) .. "）")
end

local function save_config_file(text)
	local path = config_path()
	local dir = util.dirname(path)

	if dir ~= "" and not fs.access(dir) then
		fs.mkdirr(dir)
	end

	local old = fs.readfile(path)
	if old then
		fs.writefile(path .. ".bak", old)
	end

	local tmp = path .. ".new"
	if not fs.writefile(tmp, text) then
		return nil, "写入临时文件失败：" .. tmp
	end
	fs.chmod(tmp, 420) -- 0644

	if os.rename(tmp, path) then
		return path
	end

	if not fs.writefile(path, text) then
		os.remove(tmp)
		return nil, "写入配置文件失败：" .. path
	end
	fs.chmod(path, 420)
	os.remove(tmp)

	return path
end

local GEN_DIR = "/tmp/pcdn-detect-gen"
local GEN_CACHE = "/tmp/pcdn-detect.default.toml"

-- 让 pcdn-detect 自己生成默认配置：
--   使用 --init-config <目录>，由程序把内置模板写成 pcdn-detect.toml
--   （内容随二进制版本更新）。
local function generate_default_text()
	local bin = bin_path()
	if not fs.access(bin) then
		return nil, "找不到可执行文件：" .. bin .. "，请先在「下载/更新」中安装 pcdn-detect。"
	end

	local st = fs.stat(bin)
	local cache_key = bin .. "|" .. tostring(st and st.mtime or 0)
	local cached = fs.readfile(GEN_CACHE)

	if cached then
		local key, body = cached:match("^(.-)\n(.*)$")
		if key == cache_key and body and body ~= "" then
			return body
		end
	end

	fs.mkdirr(GEN_DIR)
	os.remove(GEN_DIR .. "/config.toml")
	os.remove(GEN_DIR .. "/pcdn-detect.toml")

	local outfile = "/tmp/pcdn-detect-gen.out"
	os.remove(outfile)

	-- --init-config <目录>：目录需存在、不覆盖已有文件、成功返回 0
	local code = sys.call(string.format("%s --init-config %s >%s 2>&1",
		util.q(bin), util.q(GEN_DIR), util.q(outfile)))
	local out = util.trim(fs.readfile(outfile) or "")
	os.remove(outfile)

	if code ~= 0 then
		return nil, "pcdn-detect --init-config 执行失败"
			.. (out ~= "" and ("：" .. out) or ("（退出码 " .. tostring(code) .. "）"))
	end

	local text = fs.readfile(GEN_DIR .. "/pcdn-detect.toml")
	os.remove(GEN_DIR .. "/pcdn-detect.toml")

	if not text or text == "" then
		return nil, "pcdn-detect 未能生成默认配置（未写出 pcdn-detect.toml）"
	end

	fs.writefile(GEN_CACHE, cache_key .. "\n" .. text)
	return text
end

-- 生成的模板中 interface = ""（无法通过校验）；这里保留当前配置的网卡，
-- 没有当前值时使用默认 br-lan，避免“恢复默认 / 首次生成”必然校验失败。
-- 不自动探测 UCI network.lan.device，避免在 x86 等设备上误填成 eth2 之类的物理口。
default_config_text = function()
	local text, err = generate_default_text()
	if not text then
		return nil, err
	end

	local iface = toml.get(toml.read(fs.readfile(config_path()) or "", WANTED_KEYS), "capture", "interface")
	if not iface or iface == "" then
		iface = "br-lan"
	end

	if iface and iface ~= "" then
		-- 只替换生成文本中的 interface 行，不做 TOML 解析/打补丁
		iface = iface:gsub('"', "")
		text = text:gsub('interface%s*=%s*""', 'interface = "' .. iface .. '"', 1)
	end

	return text
end

-- 配置保存后：运行中则 SIGHUP 热重载；已启用但未运行则启动
local function apply_runtime()
	if running_pid() then
		sys.call(INITD .. " reload >/dev/null 2>&1")
		return "reloaded"
	elseif uci_get("enabled", "0") == "1" then
		sys.call(INITD .. " start >/dev/null 2>&1")
		return "started"
	end
	return "stopped"
end

---------------------------------------------------------------------------
-- 状态
---------------------------------------------------------------------------

function action_status()
	local pid = running_pid()
	local bin = bin_path()
	local cfg = config_path()
	local vals = read_values()
	local http_cfg = http_settings(vals)
	local uptime = pid and util.uptime_of(pid) or nil
	local version = util.version_of(bin)
	-- 上游 -v 输出版本 + SemVer build metadata（0.0.1-alpha+<hash>）
	local version_base, version_build = util.version_parts(version)

	-- 直连模式：开启后浏览器直接请求 HTTP API，不再经过本控制器。
	-- token 只在开启时下发（页面本来就能通过 httpinfo 取到），供 fetch 带 Authorization。
	local direct = uci_get("direct_api", "0") == "1"
	local direct_url, direct_hint
	if direct then
		direct_url, direct_hint = direct_endpoint(http_cfg.listen, http_cfg.port)
	end

	reply_json({
		ok = true,
		running = pid ~= nil,
		pid = pid and tonumber(pid) or nil,
		uptime = uptime,
		uptime_text = uptime and util.format_duration(uptime) or nil,
		version = version,
		version_base = version_base,
		version_build = version_build,
		enabled = uci_get("enabled", "0") == "1",
		bin_path = bin,
		bin_exists = fs.access(bin) and true or false,
		config_path = cfg,
		config_exists = fs.access(cfg) and true or false,
		extra_args = uci_get("extra_args", ""),
		interface = toml.get(vals, "capture", "interface"),
		protocol = toml.get(vals, "capture", "protocol"),
		log_level = toml.get(vals, "log", "level"),
		http_enabled = http_cfg.enabled,
		http_listen = http_cfg.listen,
		http_host = http_cfg.host,
		http_port = http_cfg.port,
		http_url = http_cfg.url,
		http_token_set = http_cfg.token_set,
		log_file = uci_get("log_file", ""),
		-- 直连模式：direct_url 为空串表示由前端用当前主机名 + http_port 拼接
		direct_api = direct,
		direct_url = direct_url,
		direct_hint = direct_hint,
		http_token = direct and http_cfg.token or nil,
	})
end

function action_stats()
	local h = http_settings()

	if not h.enabled then
		reply_json({
			ok = false,
			available = false,
			message = "HTTP API 未启用。可在「配置编辑」的 [http] 段启用后查看实时统计。",
		})
		return
	end

	local code, body, err = util.http_raw_get(h.listen, "/api/v1/status", h.token)
	if not code then
		reply_upstream_unreachable(err)
		return
	end

	if code ~= 200 then
		reply_json({
			ok = false,
			available = false,
			http_status = code,
			message = "HTTP API 返回状态码 " .. tostring(code),
		})
		return
	end

	if type(body) ~= "string" or body == "" then
		reply_json({ ok = false, available = false, message = "HTTP API 返回了空响应" })
		return
	end

	-- 上游 /api/v1/devices 只返回设备级汇总（IPv4 / IPv6 的端口条目数与封禁数），
	-- 端口明细由 /api/v1/device 按需读取。这里只取响应头，body 边读边转发，
	-- 与 status 段原样拼接，不在 Lua 侧解析、也不整段驻留。
	local d_code, d_pump, d_err, d_close = util.http_stream_get(h.listen, "/api/v1/devices", h.token)

	local devices_error
	if not d_code then
		devices_error = d_err or "无法访问 HTTP API"
	elseif d_code ~= 200 then
		devices_error = "HTTP API 返回状态码 " .. tostring(d_code)
		if d_close then
			d_close()
		end
		d_pump = nil
	end

	http.prepare_content("application/json")
	http.header("Cache-Control", "no-store")
	http.write('{"ok":true,"available":true,"status":')
	http.write(body)

	-- 收到第一块 body 后才写 devices 字段：上游返回空 body 时仍能得到合法 JSON
	local devices_started = false
	if d_pump then
		d_pump(function(chunk)
			if not devices_started then
				devices_started = true
				http.write(',"devices":')
			end
			http.write(chunk)
		end)
	end

	if not devices_started then
		http.write(',"devices":null')
		devices_error = devices_error or "HTTP API 返回了空响应"
	end

	if devices_error then
		http.write(',"devices_error":')
		http.write(util.json_encode(devices_error))
	end
	http.write("}")
end

-- 单设备端口明细：透传 /api/v1/device 的 family / state / limit / page
function action_device()
	local h = http_settings()

	if not h.enabled then
		reply_json({
			ok = false,
			available = false,
			message = "HTTP API 未启用。可在「配置编辑」的 [http] 段启用后查看端口明细。",
		})
		return
	end

	local mac = util.trim(http.formvalue("mac") or "")
	if mac == "" then
		reply_json({ ok = false, available = true, message = "缺少 mac 参数" })
		return
	end

	-- 只接受上游支持的取值，避免把任意字符串拼进请求路径
	local family = http.formvalue("family") or "all"
	if family ~= "v4" and family ~= "v6" then
		family = "all"
	end

	local state = http.formvalue("state") or "all"
	if state ~= "banned" and state ~= "unbanned" then
		state = "all"
	end

	local limit = tonumber(http.formvalue("limit") or "") or 100
	if limit < 1 then
		limit = 100
	elseif limit > 1000 then
		limit = 1000
	end

	local page = tonumber(http.formvalue("page") or "") or 1
	if page < 1 then
		page = 1
	end

	local code, pump, err, close = util.http_stream_get(h.listen, string.format(
		"/api/v1/device?mac=%s&family=%s&state=%s&limit=%d&page=%d",
		url_encode(mac), family, state, limit, page), h.token)

	if not code then
		reply_upstream_unreachable(err)
		return
	end

	reply_upstream_stream(code, pump, close)
end

-- 单端口对端 IP：透传 /api/v1/peers 的 proto / v6 / limit / page
function action_peers()
	local h = http_settings()

	if not h.enabled then
		reply_json({
			ok = false,
			available = false,
			message = "HTTP API 未启用。可在「配置编辑」的 [http] 段启用后查看对端 IP。",
		})
		return
	end

	local mac = util.trim(http.formvalue("mac") or "")
	local port = tonumber(http.formvalue("port") or "")

	if mac == "" or not port or port < 0 or port > 65535 then
		reply_json({ ok = false, available = true, message = "参数无效：需要 mac 与 0-65535 的 port" })
		return
	end

	local proto = string.lower(http.formvalue("proto") or "udp")
	if proto ~= "tcp" then
		proto = "udp"
	end

	local v6 = http.formvalue("v6") == "1" or http.formvalue("v6") == "true"

	local page = tonumber(http.formvalue("page") or "") or 1
	if page < 1 then
		page = 1
	end

	-- limit 留空时由上游按 [http] device_ip_limit 决定，请求值不能超过该上限
	local limit = tonumber(http.formvalue("limit") or "") or 0

	local path = string.format("/api/v1/peers?mac=%s&port=%d&proto=%s&v6=%s&page=%d",
		url_encode(mac), port, proto, v6 and "true" or "false", page)
	if limit > 0 then
		path = path .. "&limit=" .. tostring(limit)
	end

	local code, pump, err, close = util.http_stream_get(h.listen, path, h.token)
	if not code then
		reply_upstream_unreachable(err)
		return
	end

	reply_upstream_stream(code, pump, close)
end

-- 获取 [http] 端口 / 密钥（按需调用，不参与状态轮询）
function action_httpinfo()
	local h = http_settings()
	reply_json({
		ok = true,
		enabled = h.enabled,
		listen = h.listen,
		host = h.host,
		port = h.port,
		url = h.url,
		token = h.token,
		token_set = h.token_set,
	})
end

-- 检测 HTTP API：未启用 / 不可达 / 401 密钥错误 / 200 正常
function action_httpcheck()
	local h = http_settings()

	if not h.enabled then
		reply_json({
			ok = false,
			enabled = false,
			reachable = false,
			listen = h.listen,
			token_set = h.token_set,
			message = "HTTP API 未启用",
		})
		return
	end

	if not h.host then
		reply_json({
			ok = false,
			enabled = true,
			reachable = false,
			listen = h.listen,
			token_set = h.token_set,
			message = "HTTP 监听地址无效：" .. tostring(h.listen),
		})
		return
	end

	local status, body, err = util.http_raw_get(h.listen, "/api/v1/status", h.token)

	-- 仅此处解析：/api/v1/status 很小，用于在提示里显示设备数与告警数；
	-- 端口明细 / 对端列表等大响应一律透传，不经过 Lua 解码。
	local data
	if status == 200 and type(body) == "string" and body ~= "" then
		data = util.json_decode(body)
	end

	if not status then
		reply_json({
			ok = false,
			enabled = true,
			reachable = false,
			host = h.host,
			port = h.port,
			url = h.url,
			token_set = h.token_set,
			message = err or "无法访问 HTTP API",
		})
		return
	end

	local message
	if status == 200 then
		message = "HTTP API 正常"
	elseif status == 401 or status == 403 then
		message = "HTTP API 返回 " .. tostring(status) .. "，请检查 [http] token"
	else
		message = "HTTP API 返回状态码 " .. tostring(status)
	end

	reply_json({
		ok = status == 200,
		enabled = true,
		reachable = true,
		http_status = status,
		host = h.host,
		port = h.port,
		url = h.url,
		token_set = h.token_set,
		data = data,
		message = message,
	})
end

---------------------------------------------------------------------------
-- 服务控制
---------------------------------------------------------------------------

function action_service()
	local act = http.formvalue("action")
	local allowed = { start = true, stop = true, restart = true, reload = true }

	if not allowed[act] then
		reply_json({ ok = false, message = "不支持的操作：" .. tostring(act) })
		return
	end

	-- 启动 / 重启 / 停止同步“开机自启”，避免出现“已停止但重启后又起来”的迷惑状态
	if act == "start" or act == "restart" then
		uci:set(APP, SID, "enabled", "1")
		uci:commit(APP)
	elseif act == "stop" then
		uci:set(APP, SID, "enabled", "0")
		uci:commit(APP)
	end

	local outfile = "/tmp/pcdn-detect.service.out"
	os.remove(outfile)
	local code = sys.call(string.format("%s %s >%s 2>&1", INITD, act, util.q(outfile)))
	local out = fs.readfile(outfile) or ""
	os.remove(outfile)

	local pid = running_pid()
	local ok = true
	local message = "操作完成"

	if act == "start" or act == "restart" then
		ok = pid ~= nil
		message = ok and "服务已启动" or "服务未能启动，请查看日志"
	elseif act == "stop" then
		ok = pid == nil
		message = ok and "服务已停止" or "服务仍在运行"
	elseif act == "reload" then
		if pid then
			message = "已发送重载信号"
		else
			ok = false
			message = "服务未运行，无法重载"
		end
	end

	reply_json({
		ok = ok,
		exit_code = code,
		message = message,
		output = out,
		running = pid ~= nil,
		enabled = uci_get("enabled", "0") == "1",
	})
end

---------------------------------------------------------------------------
-- 配置：原始 TOML
---------------------------------------------------------------------------

function action_getconfig()
	local path = config_path()
	local content = fs.readfile(path)
	local exists = content ~= nil
	local created = false
	local gen_err

	if not exists then
		content, gen_err = default_config_text()
		content = content or ""

		-- 首次打开配置页时直接把默认配置落到 config_path，
		-- 避免“前端有内容、磁盘上却没有文件”的误导。
		if content ~= "" and not gen_err then
			local ok, out = validate_text(content)

			if not ok then
				gen_err = "生成的默认配置校验失败：" .. tostring(out)
			else
				local dir = path:match("^(.*)/[^/]+$")
				if dir and dir ~= "" then
					fs.mkdirr(dir)
				end

				if fs.writefile(path, content) then
					fs.chmod(path, 0644)
					exists = true
					created = true
				else
					gen_err = "无法写入配置文件：" .. path
				end
			end
		end
	end

	reply_json({
		ok = true,
		path = path,
		exists = exists,
		created = created,
		content = content,
		has_binary = fs.access(bin_path()) and true or false,
		error = gen_err,
	})
end

function action_saveconfig()
	local content = http.formvalue("content")

	-- 前端优先用 text/plain 原始 body 发送完整 TOML；
	-- 这里回退到 http.content()，避免大文本被 formvalue 解析/长度限制影响。
	if type(content) ~= "string" or content == "" then
		local raw = http.content and http.content() or nil
		if type(raw) == "string" and raw ~= "" then
			content = raw
		end
	end

	local validate_only = http.formvalue("validate") == "1"

	if type(content) ~= "string" or util.trim(content) == "" then
		reply_json({ ok = false, message = "配置内容为空" })
		return
	end

	local text = content:gsub("\r\n", "\n")
	local ok, out = validate_text(text)

	if not ok then
		reply_json({ ok = false, message = "配置校验失败，未保存", detail = out })
		return
	end

	if validate_only then
		reply_json({ ok = true, message = "配置校验通过", detail = out })
		return
	end

	local path, save_err = save_config_file(text)
	if not path then
		reply_json({ ok = false, message = save_err or "保存配置失败", detail = out })
		return
	end

	local state = apply_runtime()

	local msg = "配置已保存到 " .. path
	if state == "reloaded" then
		msg = msg .. "，已热重载生效"
	elseif state == "started" then
		msg = msg .. "，服务已启动"
	else
		msg = msg .. "（服务未运行，下次启动时生效）"
	end

	reply_json({ ok = true, message = msg, detail = out, state = state })
end

-- 大配置分片上传：
--   savechunk 每次只收一小段 text/plain body，index=0 时清空临时文件；
--   savecommit 校验临时文件后落盘。避免 LuCI http.content() 的小 body 限制。
local SAVE_TMP = "/tmp/pcdn-detect.save.part"

function action_savechunk()
	local content = http.content and http.content() or nil

	if type(content) ~= "string" or content == "" then
		reply_json({ ok = false, message = "分片内容为空" })
		return
	end

	if #content > 16384 then
		reply_json({ ok = false, message = "分片过大" })
		return
	end

	local index = tonumber(http.formvalue("index") or "0") or 0
	local mode = index == 0 and "wb" or "ab"
	local f, err = io.open(SAVE_TMP, mode)

	if not f then
		reply_json({ ok = false, message = "无法写入临时文件：" .. tostring(err) })
		return
	end

	f:write(content)
	f:close()

	fs.chmod(SAVE_TMP, 0600)

	reply_json({ ok = true, index = index, bytes = #content })
end

function action_savecommit()
	local content = fs.readfile(SAVE_TMP)

	if type(content) ~= "string" or content == "" then
		reply_json({ ok = false, message = "没有待保存的配置分片" })
		return
	end

	local validate_only = http.formvalue("validate") == "1"
	local text = content:gsub("\r\n", "\n")
	local ok, out = validate_text(text)

	if not ok then
		os.remove(SAVE_TMP)
		reply_json({ ok = false, message = "配置校验失败，未保存", detail = out })
		return
	end

	if validate_only then
		os.remove(SAVE_TMP)
		reply_json({ ok = true, message = "配置校验通过", detail = out })
		return
	end

	local path, save_err = save_config_file(text)
	os.remove(SAVE_TMP)

	if not path then
		reply_json({ ok = false, message = save_err or "保存配置失败", detail = out })
		return
	end

	local state = apply_runtime()
	local msg = "配置已保存到 " .. path

	if state == "reloaded" then
		msg = msg .. "，已热重载生效"
	elseif state == "started" then
		msg = msg .. "，服务已启动"
	else
		msg = msg .. "（服务未运行，下次启动时生效）"
	end

	reply_json({ ok = true, message = msg, detail = out, state = state })
end

function action_resetsettings()
	local template, gen_err = default_config_text()

	if not template then
		reply_json({ ok = false, message = gen_err or "无法生成默认配置" })
		return
	end

	local ok, out = validate_text(template)
	if not ok then
		reply_json({ ok = false, message = "默认配置校验失败", detail = out })
		return
	end

	local path, save_err = save_config_file(template)
	if not path then
		reply_json({ ok = false, message = save_err or "保存配置失败", detail = out })
		return
	end

	local state = apply_runtime()

	reply_json({
		ok = true,
		message = "已恢复默认配置到 " .. path,
		detail = out,
		state = state,
	})
end

---------------------------------------------------------------------------
-- 日志
---------------------------------------------------------------------------

local function log_level_of(line, from_file)
	if from_file then
		if line:find("警告", 1, true) or line:find("WARN", 1, true) then
			return "warn"
		end
		if line:find("错误", 1, true) or line:find("ERROR", 1, true) or line:find("失败", 1, true) then
			return "error"
		end
		if line:find("DEBUG", 1, true) then
			return "debug"
		end
		return "info"
	end

	local lv = line:match("daemon%.(%a+)")
		or line:match("user%.(%a+)")
		or line:match("local%d%.(%a+)")
		or line:match("kern%.(%a+)")

	if not lv then
		return "info"
	end

	lv = lv:lower()

	if lv == "debug" then
		return "debug"
	elseif lv == "info" or lv == "notice" then
		return "info"
	elseif lv == "warn" or lv == "warning" then
		return "warn"
	end

	return "error"
end

function action_getlog()
	local max_lines = tonumber(http.formvalue("lines")) or 300
	if max_lines < 10 then
		max_lines = 10
	elseif max_lines > 5000 then
		max_lines = 5000
	end

	local level = http.formvalue("level") or ""
	local keyword = util.trim(http.formvalue("keyword") or "")
	local keyword_l = keyword:lower()

	local logfile = uci_get("log_file", "")
	local from_file = logfile ~= "" and fs.access(logfile) and true or false
	local raw

	if from_file then
		raw = util.exec("tail -n " .. tostring(max_lines * 4) .. " " .. util.q(logfile) .. " 2>/dev/null")
	else
		raw = util.exec("logread 2>/dev/null")
		if raw == "" then
			raw = util.exec("cat /var/log/messages 2>/dev/null")
		end
	end

	local filtered = {}
	-- procd 用 basename(command[0]) 作为 stdout 日志的 tag
	local expected_tag = util.basename(bin_path())

	for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
		local keep = true

		if not from_file then
			-- 只保留本服务的 syslog tag 记录：
			--   格式：Sat Oct 24 ... daemon.info pcdn-detect[123]: 消息
			-- 不能简单匹配消息正文，否则正文里出现 pcdn-detect 的其它进程日志也会被带出来。
			local tag = line:match("[%a]+%.%a+%s+([%w%._%-]+)%[?%d*%]?:")
			keep = (tag == expected_tag or tag == "pcdn-detect")
		end

		if keep and level ~= "" and level ~= "all" then
			keep = log_level_of(line, from_file) == level
		end

		if keep and keyword_l ~= "" then
			keep = line:lower():find(keyword_l, 1, true) ~= nil
		end

		if keep then
			filtered[#filtered + 1] = line
		end
	end

	local start = #filtered - max_lines + 1
	if start < 1 then
		start = 1
	end

	local out = {}
	for i = start, #filtered do
		out[#out + 1] = filtered[i]
	end

	reply_text(table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

---------------------------------------------------------------------------
-- 下载 / 更新
---------------------------------------------------------------------------

local function detect_arch()
	local arch = ""
	local out = util.exec("opkg print-architecture 2>/dev/null")

	for a in out:gmatch("arch%s+([%w_%-]+)%s+%d+") do
		if a ~= "all" and a ~= "noarch" then
			arch = a
			break
		end
	end

	if arch == "" then
		-- apk 系统（OpenWrt 24.10+）：输出包架构，如 mipsel_24kc、aarch64_cortex-a53
		arch = util.exec("apk --print-arch 2>/dev/null")
	end

	if arch == "" then
		-- 兜底：uname -m（注意 mipsel 与 mips 可能无法区分，仅作最后手段）
		arch = util.exec("uname -m 2>/dev/null")
	end

	local l = arch:lower()
	local target = "unknown"

	if l:find("aarch64", 1, true) or l == "arm64" then
		target = "arm64"
	elseif l:find("mipsel", 1, true) or l:find("mipsle", 1, true) then
		target = "mipsle"
	elseif l:find("mips", 1, true) then
		target = "mips"
	elseif l:find("x86_64", 1, true) or l:find("amd64", 1, true) then
		target = "amd64"
	elseif l:find("arm", 1, true) then
		target = "armv7"
	end

	return target, arch
end

-- 目标分区 / /tmp 的剩余空间与下载方式由 update.sh --space 统一判定：
-- 阈值只在脚本里维护，避免前端与脚本各写一套；这里只做桥接，
-- 供页面显示剩余空间，并在下载前拦掉必然失败的请求。
local function probe_space(bin)
	if not fs.access(UPDATE_SCRIPT) then
		return nil
	end

	local out = util.exec(string.format("%s --space %s 2>/dev/null",
		util.q(UPDATE_SCRIPT), util.q(bin or bin_path())))
	local res = {}

	for k, v in out:gmatch("([%w_]+)=(%S+)") do
		res[k] = tonumber(v) or v
	end

	if not res.mode then
		return nil
	end

	return res
end

local function kb_text(kb)
	kb = tonumber(kb)
	if not kb then
		return "未知"
	end
	return util.format_bytes(kb * 1024)
end

local function allow_overwrite()
	return uci_get("allow_overwrite", "0") == "1"
end

function action_updateinfo()
	local arch, pkg_arch = detect_arch()
	local repo = uci_get("repo", DEFAULT_REPO)
	local base = uci_get("download_base", "")

	if base == "" then
		base = "https://github.com/" .. repo .. "/releases/latest/download"
	end
	base = base:gsub("/+$", "")

	local asset = "pcdn-detect-" .. arch
	local current = util.version_of(bin_path())
	local current_base, current_build = util.version_parts(current)
	local space = probe_space(bin_path())

	reply_json({
		ok = true,
		arch = arch,
		pkg_arch = pkg_arch,
		repo = repo,
		base = base,
		asset = asset,
		url = base .. "/" .. asset,
		current = current,
		current_base = current_base,
		current_build = current_build,
		bin_path = bin_path(),
		has_curl = fs.access("/usr/bin/curl") or fs.access("/bin/curl") or false,
		has_wget = fs.access("/usr/bin/wget") or fs.access("/bin/wget") or false,
		script_exists = fs.access(UPDATE_SCRIPT) and true or false,
		-- space_mode：tmp（/tmp 充足，优先）/ direct（写目标分区）/ overwrite（两者都不足）
		space_mode = space and space.mode or nil,
		dir_free_kb = space and space.dir_kb or nil,
		tmp_free_kb = space and space.tmp_kb or nil,
		dir_min_kb = space and space.dir_min_kb or nil,
		tmp_min_kb = space and space.tmp_min_kb or nil,
		allow_overwrite = allow_overwrite(),
	})
end

function action_checkupdate()
	local repo = uci_get("repo", DEFAULT_REPO)
	local api = "https://api.github.com/repos/" .. repo .. "/releases/latest"
	local cmd

	if fs.access("/usr/bin/curl") or fs.access("/bin/curl") then
		cmd = "curl -fsSL --connect-timeout 10 " .. util.q(api) .. " 2>/dev/null"
	else
		cmd = "wget -qO- " .. util.q(api) .. " 2>/dev/null"
	end

	local body = util.exec(cmd)
	local tag = body and body:match('"tag_name"%s*:%s*"([^"]+)"')

	if tag then
		reply_json({ ok = true, latest = tag, repo = repo })
	else
		reply_json({
			ok = false,
			repo = repo,
			message = "无法获取最新版本：仓库可能没有 Release，或当前网络无法访问 GitHub。可直接使用下方地址下载。",
		})
	end
end

local function valid_download_url(url)
	return url:match("^https?://[%w%._%-/~%?%%=&:;%+%[%]#@!%,]+$") ~= nil
end

function action_doupdate()
	local url = util.trim(http.formvalue("url") or "")
	local bin = bin_path()

	if url == "" then
		reply_json({ ok = false, message = "下载地址为空" })
		return
	end
	if not valid_download_url(url) then
		reply_json({ ok = false, message = "下载地址包含非法字符，仅支持 http(s) 地址" })
		return
	end
	if not fs.access(UPDATE_SCRIPT) then
		reply_json({ ok = false, message = "缺少更新脚本：" .. UPDATE_SCRIPT })
		return
	end
	if fs.access(UPDATE_FLAG) then
		reply_json({ ok = false, message = "已有下载任务正在进行" })
		return
	end

	local allow = allow_overwrite()

	-- 目标分区与 /tmp 都不足、且未允许覆盖安装时直接拒绝：
	-- 避免起一个注定失败的后台任务，也避免用户只看到“更新失败”。
	local space = probe_space(bin)
	if space and space.mode == "overwrite" and not allow then
		reply_json({
			ok = false,
			message = string.format(
				"空间不足：%s 剩余 %s（需要 %s），/tmp 剩余 %s（需要 %s）。请清理空间，或在下方开启「空间不足时覆盖安装」。",
				util.dirname(bin) ~= "" and util.dirname(bin) or "/",
				kb_text(space.dir_kb), kb_text(space.dir_min_kb),
				kb_text(space.tmp_kb), kb_text(space.tmp_min_kb)),
		})
		return
	end

	-- 第 3 个参数：空间不足时是否允许先删除旧程序再下载（0/1）
	sys.call(string.format("%s %s %s %s >/dev/null 2>&1 &",
		util.q(UPDATE_SCRIPT), util.q(url), util.q(bin), allow and "1" or "0"))

	reply_json({ ok = true, message = "已开始下载，请稍候…" })
end

function action_updatelog()
	local log = fs.readfile(UPDATE_LOG) or ""
	local lines = {}

	for line in (log .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end

	local start = #lines - 199
	if start < 1 then
		start = 1
	end

	reply_json({
		ok = true,
		running = fs.access(UPDATE_FLAG) and true or false,
		log = table.concat(lines, "\n", start, #lines),
	})
end
