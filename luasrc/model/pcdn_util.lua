--[[
luci-app-pcdn-detector 公共工具：JSON、Shell、进程、HTTP 客户端、格式化
]]--

local M = {}

local fs = require "nixio.fs"
local sys = require "luci.sys"

---------------------------------------------------------------------------
-- 字符串 / Shell
---------------------------------------------------------------------------

function M.trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 单引号包装，供 sh 使用
function M.q(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

function M.basename(path)
	return tostring(path or ""):match("([^/]+)$") or ""
end

function M.dirname(path)
	return tostring(path or ""):match("^(.*)/[^/]*$") or ""
end

function M.exec(cmd)
	return (sys.exec(cmd or "") or ""):gsub("%s+$", "")
end

function M.call(cmd)
	return sys.call(cmd or "")
end

---------------------------------------------------------------------------
-- JSON 编解码（自行实现编码，避免依赖 luci-lib-jsonc）
--
-- 上游 HTTP API 的大响应（端口明细、对端列表、设备汇总）一律由控制器原样
-- 透传给浏览器，不在 Lua 侧解析，避免在 Lua 表与字符串之间产生多份内存副本。
-- 这里的解码只给体积很小的响应使用（如 httpcheck 读取 /api/v1/status 的计数）。
---------------------------------------------------------------------------

local function json_escape(s)
	s = tostring(s)
	local out = { '"' }

	for i = 1, #s do
		local c = s:sub(i, i)
		local b = s:byte(i)

		if c == '"' then
			out[#out + 1] = '\\"'
		elseif c == "\\" then
			out[#out + 1] = "\\\\"
		elseif c == "\n" then
			out[#out + 1] = "\\n"
		elseif c == "\r" then
			out[#out + 1] = "\\r"
		elseif c == "\t" then
			out[#out + 1] = "\\t"
		elseif b < 32 then
			out[#out + 1] = string.format("\\u%04x", b)
		else
			out[#out + 1] = c
		end
	end

	out[#out + 1] = '"'
	return table.concat(out)
end

local ARRAY_MT = { __json_array = true }

-- 显式标记空数组：普通空表默认编码为 {}
function M.array(t)
	return setmetatable(t or {}, ARRAY_MT)
end

local function encode(value, out)
	local t = type(value)

	if value == nil then
		out[#out + 1] = "null"
	elseif t == "boolean" then
		out[#out + 1] = value and "true" or "false"
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = "null"
		else
			out[#out + 1] = tostring(value)
		end
	elseif t == "string" then
		out[#out + 1] = json_escape(value)
	elseif t == "table" then
		local mt = getmetatable(value)
		local is_array = (mt and mt.__json_array) or (#value > 0 and (function()
			local n = 0
			for _ in pairs(value) do
				n = n + 1
			end
			return n == #value
		end)())

		if is_array then
			out[#out + 1] = "["
			for i = 1, #value do
				if i > 1 then
					out[#out + 1] = ","
				end
				encode(value[i], out)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, v in pairs(value) do
				if not first then
					out[#out + 1] = ","
				end
				first = false
				out[#out + 1] = json_escape(tostring(k))
				out[#out + 1] = ":"
				encode(v, out)
			end
			out[#out + 1] = "}"
		end
	else
		out[#out + 1] = "null"
	end
end

function M.json_encode(value)
	local out = {}
	encode(value, out)
	return table.concat(out)
end

-- 仅用于解析体积很小的响应（如 /api/v1/status）；大响应请走控制器透传。
-- 优先 luci.jsonc，其次 luci.json；都不可用时返回 nil。
function M.json_decode(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local ok, jsonc = pcall(require, "luci.jsonc")
	if ok and jsonc and jsonc.parse then
		local pok, obj = pcall(jsonc.parse, text)
		if pok then
			return obj
		end
	end

	local ok2, json = pcall(require, "luci.json")
	if ok2 and json and json.decode then
		local pok, obj = pcall(json.decode, text)
		if pok then
			return obj
		end
	end

	return nil
end

---------------------------------------------------------------------------
-- 进程 / 版本
---------------------------------------------------------------------------

function M.pid_of(bin)
	local name = M.basename(bin)
	if name == "" then
		return nil
	end
	local out = M.exec("pidof " .. M.q(name) .. " 2>/dev/null")
	return out:match("%d+")
end

function M.pids_of(bin)
	local name = M.basename(bin)
	if name == "" then
		return ""
	end
	return M.exec("pidof " .. M.q(name) .. " 2>/dev/null")
end

-- 从 /proc/<pid>/stat 与 /proc/uptime 估算进程运行秒数
function M.uptime_of(pid)
	pid = tonumber(pid)
	if not pid then
		return nil
	end

	local stat = fs.readfile("/proc/" .. pid .. "/stat")
	local uptime = tonumber((fs.readfile("/proc/uptime") or ""):match("^(%d+%.?%d*)"))
	if not stat or not uptime then
		return nil
	end

	local rest = stat:match("%)%s+(.*)$")
	if not rest then
		return nil
	end

	local fields = {}
	for f in rest:gmatch("%S+") do
		fields[#fields + 1] = f
	end

	-- comm 之后第 20 个字段是 starttime（整体第 22 个），单位为 USER_HZ
	local start_ticks = tonumber(fields[20])
	if not start_ticks then
		return nil
	end

	local sec = uptime - start_ticks / 100
	if sec < 0 then
		sec = 0
	end
	return math.floor(sec)
end

-- 版本查询带 /tmp 缓存，避免状态页每次轮询都执行一次二进制
function M.version_of(bin)
	if not bin or not fs.access(bin) then
		return nil
	end

	local st = fs.stat(bin)
	local mtime = st and tostring(st.mtime or 0) or "0"
	local ctime = st and tostring(st.ctime or 0) or "0"
	local mode = st and tostring(st.mode or 0) or "0"
	local cache_file = "/tmp/pcdn-detect.version"
	local cache = fs.readfile(cache_file)
	-- chmod 只改变 ctime / mode，不改变 mtime；把它们纳入 key，
	-- 避免把“Permission denied”当成版本号缓存下来。
	local head = tostring(bin) .. "|" .. mtime .. "|" .. ctime .. "|" .. mode .. "\n"

	if cache and cache:sub(1, #head) == head then
		local ver = cache:sub(#head + 1):gsub("\n$", "")
		if ver ~= "" then
			return ver
		end
	end

	local out = M.exec(M.q(bin) .. " -v 2>&1")
	local ver = out:match("^%s*([^\r\n]+)") or ""

	-- 只缓存真正的版本号；错误输出（sh: ... Permission denied）每次重试
	if ver:match("^v?%d+%.%d+") then
		fs.writefile(cache_file, head .. ver .. "\n")
	end

	if ver ~= "" then
		return ver
	end

	return nil
end

-- 拆分 -v 输出：上游为 SemVer，git 短哈希作为 build metadata 跟在 '+' 之后
-- （如 0.0.1-alpha+c6d101c；早期格式为 0.0.1-alpha-c6d101c，此处按原样返回）。
-- 构建信息不参与版本比较，页面把主版本与构建号分开显示。
function M.version_parts(ver)
	ver = M.trim(ver)
	local base, build = ver:match("^([^+]+)%+(.+)$")
	if base and base ~= "" then
		return base, build
	end
	return ver, nil
end

---------------------------------------------------------------------------
-- 格式化
---------------------------------------------------------------------------

function M.format_duration(sec)
	sec = tonumber(sec)
	if not sec then
		return "-"
	end
	sec = math.floor(sec)

	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60

	if d > 0 then
		return string.format("%d天%d小时%d分", d, h, m)
	elseif h > 0 then
		return string.format("%d小时%d分%d秒", h, m, s)
	elseif m > 0 then
		return string.format("%d分%d秒", m, s)
	end
	return string.format("%d秒", s)
end

function M.format_bytes(n)
	n = tonumber(n)
	if not n then
		return "-"
	end

	local units = { "B", "KiB", "MiB", "GiB", "TiB" }
	local i = 1
	while n >= 1024 and i < #units do
		n = n / 1024
		i = i + 1
	end

	if i == 1 then
		return string.format("%d %s", math.floor(n), units[i])
	end
	return string.format("%.1f %s", n, units[i])
end

---------------------------------------------------------------------------
-- 极简 HTTP/1.0 客户端（用于读取本机 pcdn-detect HTTP API）
---------------------------------------------------------------------------

local function parse_listen(listen)
	listen = M.trim(listen)
	if listen == "" then
		return nil
	end

	local host, port = listen:match("^%[(.-)%]:(%d+)$")
	if not host then
		host, port = listen:match("^([^:]+):(%d+)$")
	end

	if not host then
		return nil
	end

	if host == "0.0.0.0" then
		host = "127.0.0.1"
	elseif host == "::" or host == "" then
		host = "::1"
	elseif host == "localhost" then
		host = "127.0.0.1"
	end

	return host, tonumber(port)
end

M.parse_listen = parse_listen

-- 返回 status, body, err；401/403 等也返回状态码，便于前端显示“密钥错误”
function M.http_raw_get(listen, path, token)
	local ok, nixio = pcall(require, "nixio")
	if not ok or not nixio then
		return nil, nil, "系统缺少 nixio，无法访问 HTTP API"
	end

	local host, port = parse_listen(listen)
	if not host then
		return nil, nil, "HTTP 监听地址无效：" .. tostring(listen)
	end

	local domain = host:find(":", 1, true) and "inet6" or "inet"
	local sock = nixio.socket(domain, "stream")
	if not sock then
		return nil, nil, "无法创建 socket"
	end

	sock:setopt("socket", "rcvtimeo", 2000)
	sock:setopt("socket", "sndtimeo", 2000)

	local cok, cerr = sock:connect(host, port)
	if not cok then
		sock:close()
		return nil, nil, "无法连接 " .. host .. ":" .. tostring(port) .. (cerr and ("（" .. tostring(cerr) .. "）") or "")
	end

	local hosthdr = host:find(":") and ("[" .. host .. "]") or host
	local req = {
		"GET " .. path .. " HTTP/1.0",
		"Host: " .. hosthdr .. ":" .. tostring(port),
		"Connection: close",
	}
	if token and token ~= "" then
		req[#req + 1] = "Authorization: Bearer " .. token
	end
	req[#req + 1] = ""
	req[#req + 1] = ""

	sock:send(table.concat(req, "\r\n"))

	local buf = {}
	while true do
		local data = sock:recv(8192)
		if not data or #data == 0 then
			break
		end
		buf[#buf + 1] = data
	end
	sock:close()

	local resp = table.concat(buf)
	if resp == "" then
		return nil, nil, "HTTP API 无响应"
	end

	local status = tonumber(resp:match("^HTTP/%d%.%d%s+(%d+)")) or 0
	local body = resp:match("\r\n\r\n(.*)$") or ""
	return status, body, nil
end

return M
