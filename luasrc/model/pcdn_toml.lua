-- 轻量 TOML 只读解析（仅用于状态页 / HTTP 统计读取少量字段）
--
-- 配置编辑不经过后端：
--   - 前端通过 getconfig 获取完整 TOML 文本；
--   - 浏览器内就地修改后，通过 saveconfig 整体回传；
--   - 后端只做 -T 校验、保存与热重载，不解析、不打补丁。
--
-- 这里保留最小解析器，供 status / stats 读取 capture.interface、log.level、
-- http.* 等少量字段。调用方传入 wanted（section -> { key = true }），只解析
-- 关心的键，不为每个键建表，也不保留原始字符串；数组表（[[filter.*]]）跳过。

local M = {}

-- 去掉行内注释（# 之后），忽略字符串内部的 # 与双引号里的反斜杠转义。
-- 用 find 跳过字符串区段，避免逐字符 sub。
local function strip_comment(line)
	local pos = 1

	while true do
		local hash = line:find("#", pos, true)
		if not hash then
			return line
		end

		-- # 出现在第一个引号之前：直接截断
		local quote = line:find("[\"']", pos)
		if not quote or quote > hash then
			return line:sub(1, hash - 1)
		end

		local q = line:sub(quote, quote)
		local i = quote + 1

		-- 跳过这段字符串，从它的结尾继续找 #
		while true do
			local close = line:find(q, i, true)
			if not close then
				return line
			end

			-- 单引号字符串是字面量，没有转义
			if q ~= '"' then
				pos = close + 1
				break
			end

			local bs = 0
			local k = close - 1
			while k > quote and line:sub(k, k) == "\\" do
				bs = bs + 1
				k = k - 1
			end

			if bs % 2 == 1 then
				i = close + 1
			else
				pos = close + 1
				break
			end
		end
	end
end

-- 解析 [section] / [[section]]；非节标题返回 nil
local function parse_section(line)
	if not line:match("^%s*%[") then
		return nil
	end

	local s = strip_comment(line):match("^%s*(.-)%s*$")
	if s == "" then
		return nil
	end

	local name, is_array = s:match("^%[%[(.-)%]%]$")
	if name then
		return name:match("^%s*(.-)%s*$"), true
	end

	name = s:match("^%[(.-)%]$")
	if name then
		return name:match("^%s*(.-)%s*$"), false
	end

	return nil
end

local function unescape(s)
	return (s:gsub("\\(.)", function(c)
		if c == "n" then
			return "\n"
		elseif c == "t" then
			return "\t"
		elseif c == "r" then
			return "\r"
		elseif c == "\\" then
			return "\\"
		elseif c == '"' then
			return '"'
		end
		return c
	end))
end

local function parse_value(raw)
	raw = raw:match("^%s*(.-)%s*$")

	local dq = raw:match('^"(.*)"$')
	if dq ~= nil then
		return unescape(dq)
	end

	local sq = raw:match("^'(.*)'$")
	if sq ~= nil then
		return sq
	end

	if raw == "true" then
		return true
	end
	if raw == "false" then
		return false
	end
	if raw:match("^-?%d+$") then
		return tonumber(raw)
	end

	return raw
end

-- 解析文本，返回 values[section][key] = value。
-- wanted 指定关心的键：{ http = { listen = true, token = true }, ... }；
-- 未列出的 section / key 直接跳过，不建表、不做字符串副本。
function M.read(text, wanted)
	local values = {}
	if type(wanted) ~= "table" then
		return values
	end

	local cur = nil
	local keys = nil

	text = tostring(text or ""):gsub("\r\n", "\n")

	for line in text:gmatch("[^\n]+") do
		local name, is_array = parse_section(line)

		if name then
			if is_array then
				cur, keys = nil, nil
			else
				cur = name
				keys = wanted[name]
				if keys then
					values[cur] = values[cur] or {}
				end
			end
		elseif keys then
			local code = strip_comment(line)
			local key, raw = code:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")

			if key and keys[key] and raw ~= "" then
				values[cur][key] = parse_value(raw)
			end
		end
	end

	return values
end

local function get_value(values, section, key)
	local s = values and values[section]
	if not s then
		return nil
	end
	return s[key]
end

M.get = get_value

return M
