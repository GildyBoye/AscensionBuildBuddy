AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy

local Serializer = {}
BB.Serializer = Serializer

local function encodeValue(value, parts)
	local t = type(value)
	if value == nil then
		parts[#parts + 1] = "n"
	elseif t == "boolean" then
		parts[#parts + 1] = value and "T" or "F"
	elseif t == "number" then
		parts[#parts + 1] = "N" .. string.format("%.17g", value) .. ";"
	elseif t == "string" then
		parts[#parts + 1] = "S" .. #value .. ":" .. value
	elseif t == "table" then
		local entryParts = {}
		local count = 0
		for k, v in pairs(value) do
			count = count + 1
			encodeValue(k, entryParts)
			encodeValue(v, entryParts)
		end
		parts[#parts + 1] = "{" .. count .. ":"
		for i = 1, #entryParts do
			parts[#parts + 1] = entryParts[i]
		end
		parts[#parts + 1] = "}"
	else
		error("AscensionBuildBuddy.Serializer: cannot serialize value of type " .. t)
	end
end

function Serializer:Serialize(value)
	local parts = {}
	encodeValue(value, parts)
	return table.concat(parts)
end

local MAX_DECODE_DEPTH = 64

local function decodeValue(str, pos, depth)
	if depth > MAX_DECODE_DEPTH then
		error("table nesting too deep")
	end
	local tag = str:sub(pos, pos)
	if tag == "n" then
		return nil, pos + 1
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "N" then
		local semi = str:find(";", pos + 1, true)
		if not semi then error("truncated number") end
		local numStr = str:sub(pos + 1, semi - 1)
		local num = tonumber(numStr)
		if not num then error("invalid number literal: " .. tostring(numStr)) end
		return num, semi + 1
	elseif tag == "S" then
		local colon = str:find(":", pos + 1, true)
		if not colon then error("truncated string header") end
		local lenStr = str:sub(pos + 1, colon - 1)
		local len = tonumber(lenStr)
		if not len or len < 0 then error("invalid string length: " .. tostring(lenStr)) end
		local strStart = colon + 1
		local strEnd = strStart + len - 1
		if strEnd > #str then error("truncated string body") end
		return str:sub(strStart, strEnd), strEnd + 1
	elseif tag == "{" then
		local colon = str:find(":", pos + 1, true)
		if not colon then error("truncated table header") end
		local countStr = str:sub(pos + 1, colon - 1)
		local count = tonumber(countStr)
		if not count or count < 0 then error("invalid table entry count: " .. tostring(countStr)) end
		local result = {}
		local cursor = colon + 1
		for _ = 1, count do
			local key
			key, cursor = decodeValue(str, cursor, depth + 1)
			local val
			val, cursor = decodeValue(str, cursor, depth + 1)
			result[key] = val
		end
		if str:sub(cursor, cursor) ~= "}" then error("missing closing brace") end
		return result, cursor + 1
	else
		error("unknown type tag: " .. tostring(tag) .. " at position " .. pos)
	end
end

function Serializer:Deserialize(str)
	if type(str) ~= "string" or str == "" then
		return false, "empty input"
	end
	local ok, result = pcall(function()
		local value, nextPos = decodeValue(str, 1, 1)
		if nextPos ~= #str + 1 then
			error("trailing data after top-level value")
		end
		return value
	end)
	if not ok then
		return false, result
	end
	return true, result
end
