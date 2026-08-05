AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy

local ICON_SIZE = 31
local button

local function GetAngleRadians()
	return math.rad(BB.db.minimapIcon.angle or 220)
end

local function UpdateButtonPosition()
	local radius = (Minimap:GetWidth() / 2) + 5
	local angle = GetAngleRadians()
	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SetAngleFromCursor()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	local mx, my = Minimap:GetCenter()
	local angle = math.atan2(cy - my, cx - mx)
	BB.db.minimapIcon.angle = math.deg(angle)
	UpdateButtonPosition()
end

local function BuildButton()
	local b = CreateFrame("Button", "AscensionBuildBuddyMinimapButton", Minimap)
	b:SetWidth(ICON_SIZE)
	b:SetHeight(ICON_SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")

	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", b, "CENTER", 0, 1)
	icon:SetTexture("Interface\\Icons\\INV_Helmet_05")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon = icon

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetWidth(20)
	highlight:SetHeight(20)
	highlight:SetPoint("CENTER", b, "CENTER", 0, 1)
	highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	highlight:SetBlendMode("ADD")

	b:SetScript("OnClick", function()
		if BB.ToggleMainFrame then
			BB.ToggleMainFrame()
		end
	end)

	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", SetAngleFromCursor)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	b:SetScript("OnEnter", function(self)
		self.bbTooltipElapsed = 0
		self:SetScript("OnUpdate", function(self, elapsed)
			self.bbTooltipElapsed = self.bbTooltipElapsed + elapsed
			if self.bbTooltipElapsed >= 0.5 then
				self:SetScript("OnUpdate", nil)
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:SetText("Ascension Build Buddy", 1, 1, 1)
				GameTooltip:AddLine("Click to open", 0.9, 0.9, 0.9)
				GameTooltip:AddLine("Drag to move", 0.9, 0.9, 0.9)
				GameTooltip:Show()
			end
		end)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetScript("OnUpdate", nil)
		GameTooltip:Hide()
	end)

	return b
end

function BB.InitMinimapIcon()
	BB.db.minimapIcon = BB.db.minimapIcon or { angle = 220 }
	if not button then
		button = BuildButton()
	end
	UpdateButtonPosition()
end
