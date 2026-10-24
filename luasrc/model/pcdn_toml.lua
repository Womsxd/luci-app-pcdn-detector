-- 轻量 TOML 只读解析（仅用于状态页 / HTTP 统计读取少量字段）
--
-- 配置编辑不再经过后端：
--   - 前端通过 getconfig 获取完整 TOML 文本；
--   - 浏览器内就地修改后，通过 saveconfig 整体回传；
--   - 后端只做 -T 校验、保存与热重载，不解析、不打补丁。
--
-- 这里保留最小解析器，供 status / stats 读取 capture.interface、log.level、
-- http.* 等只读信息。数组表（[[filter.*]]）会跳过，不影响统计。

local M = {}

-- 去掉行内注释（# 之后），但忽略字符串内部的 # 与转义
local function strip_comment(line)
	local in_str = false
	local quote = nil
	local esc = false
	for i = 1, #line do
		local c = line:sub(i, i)
		if in_str then
			if quote == '"' and esc then
				esc = false
			elseif quote == '"' and c == "\\" then
				esc = true
			elseif c == quote then
				in_str = false
			end
		else
			if c == '"' or c == "'" then
				in_str = true
				quote = c
			elseif c == "#" then
				return line:sub(1, i - 1)
			end
		end
	end
	return line
end

-- 解析 [section] / [[section]]；非节标题返回 nil, is_array
local function parse_section(line)
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

-- 返回 value, type
local function parse_value(raw)
	raw = raw:match("^%s*(.-)%s*$")
	local dq = raw:match('^"(.*)"$')
	if dq ~= nil then
		return unescape(dq), "string"
	end
	local sq = raw:match("^'(.*)'$")
	if sq ~= nil then
		return sq, "string"
	end
	if raw == "true" then
		return true, "bool"
	end
	if raw == "false" then
		return false, "bool"
	end
	if raw:match("^-?%d+$") then
		return tonumber(raw), "number"
	end
	return raw, "raw"
end

-- 解析文本，返回 values[section][key] = { value=..., type=... }
function M.read(text)
	local values = {}
	local section = nil
	local is_array = false

	text = tostring(text or ""):gsub("\r\n", "\n")
	if text ~= "" and text:sub(-1) ~= "\n" then
		text = text .. "\n"
	end

	for line in text:gmatch("([^\n]*)\n") do
		local name, arr = parse_section(line)
		if name then
			section = name
			is_array = arr
			values[section] = values[section] or {}
		elseif section and not is_array then
			local code = strip_comment(line)
			local key, raw = code:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
			if key and raw ~= "" then
				local value, typ = parse_value(raw)
				values[section][key] = { value = value, type = typ, raw = raw }
			end
		end
	end

	return values
end

local function get_value(values, section, key)
	local s = values and values[section]
	if not s or not s[key] then
		return nil
	end
	return s[key].value
end

M.get = get_value

return M
