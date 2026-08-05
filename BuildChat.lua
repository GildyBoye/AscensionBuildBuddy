AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy
BB.BuildChat = {}
local Share = BB.BuildChat

local ADDON_PREFIX = "ABBShare"
local CHUNK_SIZE = 200
local RATE_LIMIT_SECONDS = 3
local ANNOUNCE_RATE_LIMIT_SECONDS = 5
local REQUEST_TIMEOUT_SECONDS = 10
local MAX_CONCURRENT_REQUESTS = 3
local MAX_CLAIMED_CHUNKS = 50
local SHARE_CACHE_LIMIT = 20
local SHARE_CACHE_MAX_AGE = 1800

Share.onBuildReceived = nil
Share.onRequestFailed = nil
Share.onShareAnnounced = nil

local pendingShares = {}
local shareOrder = {}
local lastFulfilledFrom = {}
local lastAnnouncedFrom = {}

local ID_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local function RandomShareID()
	local parts = {}
	for i = 1, 10 do
		local idx = math.random(1, #ID_CHARS)
		parts[i] = ID_CHARS:sub(idx, idx)
	end
	return table.concat(parts)
end

local function EvictOldShares()
	local cutoff = time() - SHARE_CACHE_MAX_AGE
	while shareOrder[1] and (not pendingShares[shareOrder[1]] or pendingShares[shareOrder[1]].timestamp < cutoff) do
		local id = table.remove(shareOrder, 1)
		pendingShares[id] = nil
	end
	while #shareOrder > SHARE_CACHE_LIMIT do
		local id = table.remove(shareOrder, 1)
		pendingShares[id] = nil
	end
end

local function SenderStillEligible(sender, channel)
	if channel == "GUILD" then
		if not IsInGuild() then return false end
		for i = 1, GetNumGuildMembers() do
			local name = GetGuildRosterInfo(i)
			if name and name:match("^([^-]+)") == sender then
				return true
			end
		end
		return false
	end
	return (UnitInParty(sender) and true) or (UnitInRaid(sender) and true) or false
end

function Share.PostBuild(channel, buildName, buildData)
	if not ChatThrottleLib then
		BB.Print("ChatThrottleLib isn't loaded -- can't share to chat.")
		return
	end
	local str, err = BB.BuildExport.Export(buildName, buildData)
	if not str then
		BB.Print("Share failed: " .. tostring(err))
		return
	end

	local shareID = RandomShareID()
	while pendingShares[shareID] do
		shareID = RandomShareID()
	end
	pendingShares[shareID] = { exportString = str, timestamp = time(), channel = channel }
	shareOrder[#shareOrder + 1] = shareID
	EvictOldShares()

	ChatThrottleLib:SendAddonMessage("NORMAL", ADDON_PREFIX, "ANN:" .. shareID .. ":" .. buildName, channel)
	BB.Print(("Shared \"%s\" with your %s -- anyone else with the addon can grab it."):format(buildName, channel:lower()))
end

local pendingRequests = {}
local activeRequestCount = 0
local reassembly = {}

local function RequestKey(sender, shareID)
	return sender .. ":" .. shareID
end

function Share.RequestBuild(sender, shareID)
	if not ChatThrottleLib then
		BB.Print("ChatThrottleLib isn't loaded -- can't request shared builds.")
		return
	end
	local key = RequestKey(sender, shareID)
	if pendingRequests[key] then
		return
	end
	if activeRequestCount >= MAX_CONCURRENT_REQUESTS then
		BB.Print("Already waiting on a few build requests -- try again in a moment.")
		return
	end
	activeRequestCount = activeRequestCount + 1
	pendingRequests[key] = { sender = sender, shareID = shareID, startedAt = time() }
	BB.Print(("Requesting a shared build from %s..."):format(sender))
	ChatThrottleLib:SendAddonMessage("NORMAL", ADDON_PREFIX, "REQ:" .. shareID, "WHISPER", sender)
end

local function FinishRequest(reqKey)
	pendingRequests[reqKey] = nil
	reassembly[reqKey] = nil
	activeRequestCount = math.max(0, activeRequestCount - 1)
end

function Share.FulfillRequest(sender, shareID)
	local now = time()
	if lastFulfilledFrom[sender] and now - lastFulfilledFrom[sender] < RATE_LIMIT_SECONDS then
		return
	end
	lastFulfilledFrom[sender] = now

	local share = pendingShares[shareID]
	if not share or not SenderStillEligible(sender, share.channel) then
		ChatThrottleLib:SendAddonMessage("NORMAL", ADDON_PREFIX, "ERR:" .. shareID .. ":notfound", "WHISPER", sender)
		return
	end

	local str = share.exportString
	local total = math.ceil(#str / CHUNK_SIZE)
	for i = 1, total do
		local chunk = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
		ChatThrottleLib:SendAddonMessage("NORMAL", ADDON_PREFIX, ("DAT:%s:%d/%d:%s"):format(shareID, i, total, chunk), "WHISPER", sender)
	end
end

function Share.ReceiveChunk(sender, shareID, idx, total, chunk)
	local reqKey = RequestKey(sender, shareID)
	if not pendingRequests[reqKey] then
		return
	end
	if not idx or not total or total < 1 or total > MAX_CLAIMED_CHUNKS or idx < 1 or idx > total then
		return
	end

	local buf = reassembly[reqKey]
	if not buf then
		buf = { total = total, chunks = {}, received = 0 }
		reassembly[reqKey] = buf
	end
	if buf.total ~= total then
		return
	end
	if not buf.chunks[idx] then
		buf.chunks[idx] = chunk
		buf.received = buf.received + 1
	end

	if buf.received >= buf.total then
		local parts = {}
		for i = 1, buf.total do
			parts[i] = buf.chunks[i] or ""
		end
		local fullStr = table.concat(parts)
		FinishRequest(reqKey)

		local ok, buildName, buildData, err = BB.BuildExport.Import(fullStr)
		if not ok then
			BB.Print("Received a build from " .. sender .. " but couldn't read it: " .. tostring(err))
			if Share.onRequestFailed then
				Share.onRequestFailed("corrupt")
			end
			return
		end

		if Share.onBuildReceived then
			Share.onBuildReceived(sender, buildName, buildData)
		end
	end
end

function Share.ReceiveError(sender, shareID, reason)
	local reqKey = RequestKey(sender, shareID)
	if not pendingRequests[reqKey] then return end
	FinishRequest(reqKey)
	BB.Print(("%s's shared build is no longer available (%s)."):format(sender, tostring(reason)))
	if Share.onRequestFailed then
		Share.onRequestFailed(reason)
	end
end

function Share.HandleAddonMessage(sender, message)
	local kind = message:match("^(%a+):")
	if kind == "REQ" then
		local shareID = message:match("^REQ:(.+)$")
		if shareID then Share.FulfillRequest(sender, shareID) end
	elseif kind == "DAT" then
		local shareID, idx, total, chunk = message:match("^DAT:([^:]+):(%d+)/(%d+):(.*)$")
		if shareID then Share.ReceiveChunk(sender, shareID, tonumber(idx), tonumber(total), chunk) end
	elseif kind == "ERR" then
		local shareID, reason = message:match("^ERR:([^:]+):(.*)$")
		if shareID then Share.ReceiveError(sender, shareID, reason) end
	elseif kind == "ANN" then
		local now = time()
		if lastAnnouncedFrom[sender] and now - lastAnnouncedFrom[sender] < ANNOUNCE_RATE_LIMIT_SECONDS then
			return
		end
		lastAnnouncedFrom[sender] = now
		local shareID, buildName = message:match("^ANN:([^:]+):(.*)$")
		if shareID and buildName and Share.onShareAnnounced then
			Share.onShareAnnounced(sender, shareID, buildName)
		end
	end
end

local RATE_LIMIT_ENTRY_MAX_AGE = 600

local tickerFrame = CreateFrame("Frame")
local tickerElapsed = 0
tickerFrame:SetScript("OnUpdate", function(self, elapsed)
	tickerElapsed = tickerElapsed + elapsed
	if tickerElapsed < 1 then return end
	tickerElapsed = 0
	local now = time()
	for key, req in pairs(pendingRequests) do
		if now - req.startedAt > REQUEST_TIMEOUT_SECONDS then
			FinishRequest(key)
			BB.Print(("Couldn't reach %s to get that build -- they may be offline or out of range."):format(req.sender))
			if Share.onRequestFailed then
				Share.onRequestFailed("timeout")
			end
		end
	end
	for sender, ts in pairs(lastFulfilledFrom) do
		if now - ts > RATE_LIMIT_ENTRY_MAX_AGE then lastFulfilledFrom[sender] = nil end
	end
	for sender, ts in pairs(lastAnnouncedFrom) do
		if now - ts > RATE_LIMIT_ENTRY_MAX_AGE then lastAnnouncedFrom[sender] = nil end
	end
end)

local msgFrame = CreateFrame("Frame")
msgFrame:RegisterEvent("CHAT_MSG_ADDON")
msgFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if prefix ~= ADDON_PREFIX then return end
	local ok, err = pcall(Share.HandleAddonMessage, sender, message)
	if not ok then
		BB.Print("BuildChat error handling '" .. tostring(message) .. "' from " .. tostring(sender) .. ": " .. tostring(err))
	end
end)
