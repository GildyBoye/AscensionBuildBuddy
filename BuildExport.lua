AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy
BB.BuildExport = {}

local PREFIX = "ABB1:"

local MAX_INPUT_LEN = 100000
local MAX_DECOMPRESSED_LEN = 200000
local MAX_TALENTS = 200
local MAX_SPELLS = 500
local MAX_NOTES_LEN = 10000

local function TrimString(s)
	return s:match("^%s*(.-)%s*$")
end

local function GetLibDeflate()
	if LibStub then
		return LibStub:GetLibrary("LibDeflate", true)
	end
	return _G.LibDeflate
end

function BB.BuildExport.Export(buildName, buildData)
	local LibDeflate = GetLibDeflate()
	if not LibDeflate then
		return nil, "LibDeflate not loaded"
	end

	local package = {
		v = 1,
		bn = buildName,
		bd = buildData,
	}

	local ok, serialized = pcall(function() return BB.Serializer:Serialize(package) end)
	if not ok then
		return nil, "failed to serialize build: " .. tostring(serialized)
	end

	local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
	local encoded = LibDeflate:EncodeForPrint(compressed)
	return PREFIX .. encoded
end

function BB.BuildExport.Import(str)
	local LibDeflate = GetLibDeflate()
	if not LibDeflate then
		return false, nil, nil, "LibDeflate not loaded"
	end

	if type(str) ~= "string" then
		return false, nil, nil, "no data given"
	end
	if #str > MAX_INPUT_LEN then
		return false, nil, nil, "that's way too long to be a real share string"
	end
	str = TrimString(str)
	if str:sub(1, #PREFIX) ~= PREFIX then
		return false, nil, nil, "doesn't look like an AscensionBuildBuddy share string"
	end
	local encoded = str:sub(#PREFIX + 1)

	local compressed = LibDeflate:DecodeForPrint(encoded)
	if not compressed then
		return false, nil, nil, "couldn't decode string (was it copied fully?)"
	end

	local serialized = LibDeflate:DecompressDeflate(compressed)
	if not serialized then
		return false, nil, nil, "couldn't decompress string (was it copied fully?)"
	end
	if #serialized > MAX_DECOMPRESSED_LEN then
		return false, nil, nil, "decompressed build data is implausibly large"
	end

	local ok, package = BB.Serializer:Deserialize(serialized)
	if not ok then
		return false, nil, nil, "corrupt build data: " .. tostring(package)
	end

	if type(package) ~= "table" or package.v ~= 1 or type(package.bn) ~= "string" or type(package.bd) ~= "table" then
		return false, nil, nil, "unrecognized build data format"
	end

	local bd = package.bd
	if type(bd.talents) == "table" and #bd.talents > MAX_TALENTS then
		return false, nil, nil, "this build has an implausible number of talents"
	end
	if type(bd.knownSpells) == "table" and #bd.knownSpells > MAX_SPELLS then
		return false, nil, nil, "this build has an implausible number of spells"
	end
	if type(bd.notes) == "string" and #bd.notes > MAX_NOTES_LEN then
		bd.notes = bd.notes:sub(1, MAX_NOTES_LEN)
	end

	for _, field in ipairs({ "notes", "author", "playerName", "class", "race", "classToken" }) do
		if type(bd[field]) == "string" then
			bd[field] = BB.StripFormatting(bd[field])
		end
	end

	local name = BB.StripFormatting(package.bn)

	return true, name, bd
end
