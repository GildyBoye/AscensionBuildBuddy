AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy

BB.ADDON_NAME = "AscensionBuildBuddy"

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7ebAscensionBuildBuddy|r: " .. tostring(msg))
end
BB.Print = Print

function BB.StripFormatting(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("|", ""))
end

local MAX_BUILDS = 25
BB.MAX_BUILDS = MAX_BUILDS

local function InitializeSavedVariables()
	if type(AscensionBuildBuddyDB) ~= "table" then
		AscensionBuildBuddyDB = {}
	end
	local db = AscensionBuildBuddyDB
	db.version = db.version or 1
	db.buildsByRealm = db.buildsByRealm or {}
	db.denyShares = db.denyShares or false
	db.stats = db.stats or { sharesSent = 0, sharesReceived = 0 }
	BB.db = db

	if type(db.builds) == "table" then
		local currentRealm = GetRealmName() or "Unknown"
		for name, buildData in pairs(db.builds) do
			local realm = (type(buildData) == "table" and buildData.realmName) or currentRealm
			db.buildsByRealm[realm] = db.buildsByRealm[realm] or {}
			if not db.buildsByRealm[realm][name] then
				db.buildsByRealm[realm][name] = buildData
			end
		end
		db.builds = nil
	end
end

local function GetRealmBuilds()
	local realm = GetRealmName() or "Unknown"
	BB.db.buildsByRealm[realm] = BB.db.buildsByRealm[realm] or {}
	return BB.db.buildsByRealm[realm]
end

function BB.CountBuilds()
	local count = 0
	for _ in pairs(GetRealmBuilds()) do count = count + 1 end
	return count
end

function BB.GetBuilds()
	return GetRealmBuilds()
end

function BB.SaveBuild(name, buildData)
	if type(name) ~= "string" or name == "" then
		return false, "Build name can't be empty."
	end
	local builds = GetRealmBuilds()
	if not builds[name] and BB.CountBuilds() >= MAX_BUILDS then
		return false, ("You already have %d saved builds (the max). Delete one first."):format(MAX_BUILDS)
	end
	builds[name] = buildData
	return true
end

function BB.DeleteBuild(name)
	local builds = GetRealmBuilds()
	if not builds[name] then return false end
	builds[name] = nil
	return true
end

function BB.RenameBuild(oldName, newName)
	local builds = GetRealmBuilds()
	if not builds[oldName] or builds[newName] then
		return false
	end
	builds[newName] = builds[oldName]
	builds[oldName] = nil
	return true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
	if event == "ADDON_LOADED" and addonName == BB.ADDON_NAME then
		InitializeSavedVariables()
		self:UnregisterEvent("ADDON_LOADED")
		if BB.InitMinimapIcon then
			BB.InitMinimapIcon()
		end
	end
end)

SLASH_ASCENSIONBUILDBUDDY1 = "/abb"
SLASH_ASCENSIONBUILDBUDDY2 = "/buildbuddy"

SlashCmdList["ASCENSIONBUILDBUDDY"] = function(msg)
	if BB.ToggleMainFrame then
		BB.ToggleMainFrame()
	end
end
