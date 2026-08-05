AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy
BB.UI = {}

local mainFrame
local tabButtons = {}
local tabFrames = {}
local activeTab = "character"

local TOOLTIP_DELAY = 0.5

local SLOT_LABELS = {
	HeadSlot = "Head", NeckSlot = "Neck", ShoulderSlot = "Shoulder", BackSlot = "Back",
	ChestSlot = "Chest", WristSlot = "Wrist", HandsSlot = "Hands", WaistSlot = "Waist",
	LegsSlot = "Legs", FeetSlot = "Feet", Finger0Slot = "Ring 1", Finger1Slot = "Ring 2",
	Trinket0Slot = "Trinket 1", Trinket1Slot = "Trinket 2", MainHandSlot = "Main Hand",
	SecondaryHandSlot = "Off Hand", RangedSlot = "Ranged",
}

local function SetDelayedTooltip(widget, showFn)
	widget:SetScript("OnEnter", function(self)
		self.bbTooltipElapsed = 0
		self:SetScript("OnUpdate", function(self, elapsed)
			self.bbTooltipElapsed = self.bbTooltipElapsed + elapsed
			if self.bbTooltipElapsed >= TOOLTIP_DELAY then
				self:SetScript("OnUpdate", nil)
				showFn(self)
			end
		end)
	end)
	widget:SetScript("OnLeave", function(self)
		self:SetScript("OnUpdate", nil)
		GameTooltip:Hide()
	end)
end

local function AddTooltip(widget, title, subtext)
	SetDelayedTooltip(widget, function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title, 1, 1, 1)
		if subtext then GameTooltip:AddLine(subtext, 0.9, 0.9, 0.9, true) end
		GameTooltip:Show()
	end)
end

local function CreateBorderedFrame(name, parent, width, height, title)
	local f = CreateFrame("Frame", name, parent)
	f:SetWidth(width)
	f:SetHeight(height)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("DIALOG")

	local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleFS:SetPoint("TOP", f, "TOP", 0, -14)
	titleFS:SetText(title or "")
	f.titleText = titleFS

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	AddTooltip(closeBtn, "Close", nil)

	return f
end

local function CreateActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetWidth(width or 90)
	btn:SetHeight(22)
	btn:SetText(text)
	return btn
end

local function CreateSelectionBorder(parent, padding)
	local glow = parent:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints(parent)
	glow:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
	glow:SetBlendMode("ADD")
	glow:Hide()
	return glow
end

local function MakeModalOverMain(dialog)
	dialog:SetFrameStrata("FULLSCREEN_DIALOG")
	dialog:SetScript("OnShow", function()
		if mainFrame then mainFrame:EnableMouse(false) end
	end)
	dialog:SetScript("OnHide", function()
		if mainFrame then mainFrame:EnableMouse(true) end
	end)
end

local TEXT_DIALOG_W, TEXT_DIALOG_H = 520, 420

local function BuildTextDialog(name, title)
	local f = CreateBorderedFrame(name, UIParent, TEXT_DIALOG_W, TEXT_DIALOG_H, title)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:Hide()

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("TOP", f, "TOP", 0, -32)
	f.hint = hint

	local scrollFrame = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -54)
	scrollFrame:SetWidth(TEXT_DIALOG_W - 50)
	scrollFrame:SetHeight(TEXT_DIALOG_H - 100)

	local editBox = CreateFrame("EditBox", nil, scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(TEXT_DIALOG_W - 50)
	editBox:SetHeight(TEXT_DIALOG_H - 100)
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function(self) self:GetParent():GetParent():Hide() end)
	scrollFrame:SetScrollChild(editBox)
	f.editBox = editBox

	local closeBtn = CreateActionButton(f, "Close", 80)
	closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	AddTooltip(closeBtn, "Close", nil)

	return f
end

local SCROLL_TOP_INSET = 6
local SCROLL_BOTTOM_INSET = 6
local SCROLL_RIGHT_INSET = 28

local function UpdateScrollBarVisibility(scrollFrame)
	if not scrollFrame then return end
	local bar = scrollFrame.ScrollBar or _G[(scrollFrame:GetName() or "") .. "ScrollBar"]
	if not bar then return end
	local child = scrollFrame:GetScrollChild()
	local contentHeight = child and child:GetHeight() or 0
	if contentHeight <= scrollFrame:GetHeight() + 1 then
		scrollFrame:SetVerticalScroll(0)
		bar:Hide()
	else
		bar:Show()
	end
end

local viewingLive = true
local currentBuildName
local viewedBuild

local function GetActiveBuild()
	if viewingLive then
		return BB.Capture.CaptureCurrent()
	end
	return viewedBuild or BB.Capture.CaptureCurrent()
end

local characterTab
local playerModel
local gearButtons = {}
local statScrollFrame
local statScrollChild
local statLines = {}
local sectionHeaders = {}
local STAT_LINE_POOL = 60
local LINE_HEIGHT = 15
local HEADER_HEIGHT = 20

local SECTION_ORDER = { "basic", "melee", "ranged", "spell", "defense" }
local SECTION_LABELS = {
	basic = "Basic Stats", melee = "Melee", ranged = "Ranged", spell = "Spell", defense = "Defenses",
}
local sectionExpanded = { basic = true, melee = true, ranged = false, spell = false, defense = false }

local WEAPON_SLOT_KIND = { MainHandSlot = "melee", SecondaryHandSlot = "melee", RangedSlot = "ranged" }
local weaponMode = "melee"
local modelFacing = 0

function BB.UI.ToggleWeaponMode()
	weaponMode = (weaponMode == "melee") and "ranged" or "melee"
	if BB.UI.weaponToggleBtn then
		BB.UI.weaponToggleBtn:SetText(weaponMode == "melee" and "Melee" or "Ranged")
	end
	BB.UI.RefreshCharacterTab()
end

function BB.UI.RotateModel(delta)
	modelFacing = modelFacing + delta
	if playerModel then
		playerModel:SetFacing(modelFacing)
	end
end

local function CreateGearSlotButton(parent, slotName)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetWidth(36)
	btn:SetHeight(36)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetAllPoints(btn)
	border:SetTexture("Interface\\Common\\WhiteIconFrame")
	btn.border = border

	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn.slotName = slotName

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.itemLink then
			GameTooltip:SetHyperlink(self.itemLink)
		else
			GameTooltip:SetText(SLOT_LABELS[self.slotName] or self.slotName)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return btn
end

local GEAR_COL_LEFT_X = 6
local MODEL_TOP_OFFSET = 10
local MODEL_W, MODEL_H = 180, 340
local MODEL_LEFT_X = 54
local MODEL_CENTER_X = MODEL_LEFT_X + MODEL_W / 2
local GEAR_COL_RIGHT_X = MODEL_LEFT_X + MODEL_W + 10
local STATS_LEFT_X = GEAR_COL_RIGHT_X + 36 + 14

local function BuildCharacterTab(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)

	local prevLeft
	for _, slotName in ipairs(BB.Capture.LEFT_SLOTS) do
		local btn = CreateGearSlotButton(f, slotName)
		if prevLeft then
			btn:SetPoint("TOP", prevLeft, "BOTTOM", 0, -6)
		else
			btn:SetPoint("TOPLEFT", f, "TOPLEFT", GEAR_COL_LEFT_X, -10)
		end
		gearButtons[slotName] = btn
		prevLeft = btn
	end

	local prevRight
	for _, slotName in ipairs(BB.Capture.RIGHT_SLOTS) do
		local btn = CreateGearSlotButton(f, slotName)
		if prevRight then
			btn:SetPoint("TOP", prevRight, "BOTTOM", 0, -6)
		else
			btn:SetPoint("TOPLEFT", f, "TOPLEFT", GEAR_COL_RIGHT_X, -10)
		end
		gearButtons[slotName] = btn
		prevRight = btn
	end

	local model = CreateFrame("DressUpModel", nil, f)
	model:SetWidth(MODEL_W)
	model:SetHeight(MODEL_H)
	model:SetPoint("TOPLEFT", f, "TOPLEFT", MODEL_LEFT_X, -MODEL_TOP_OFFSET)
	playerModel = model

	local weaponRowW = 3 * 36 + 2 * 6
	local prevBottom
	for _, slotName in ipairs(BB.Capture.BOTTOM_SLOTS) do
		local btn = CreateGearSlotButton(f, slotName)
		if prevBottom then
			btn:SetPoint("LEFT", prevBottom, "RIGHT", 6, 0)
		else
			btn:SetPoint("TOPLEFT", f, "TOPLEFT", MODEL_CENTER_X - weaponRowW / 2, -(MODEL_TOP_OFFSET + MODEL_H + 8))
		end
		gearButtons[slotName] = btn
		prevBottom = btn
	end

	local controlsY = -(MODEL_TOP_OFFSET + MODEL_H + 8 + 36 + 8)

	local rotateLeftBtn = CreateActionButton(f, "<", 24)
	rotateLeftBtn:SetPoint("TOPLEFT", f, "TOPLEFT", MODEL_CENTER_X - 73, controlsY)
	rotateLeftBtn:SetScript("OnClick", function() BB.UI.RotateModel(-0.5) end)
	AddTooltip(rotateLeftBtn, "Rotate Left", nil)

	local weaponToggleBtn = CreateActionButton(f, "Melee", 90)
	weaponToggleBtn:SetPoint("LEFT", rotateLeftBtn, "RIGHT", 4, 0)
	weaponToggleBtn:SetScript("OnClick", function() BB.UI.ToggleWeaponMode() end)
	AddTooltip(weaponToggleBtn, "Weapon Display", "Toggle between showing melee or ranged weapons on the model.")
	BB.UI.weaponToggleBtn = weaponToggleBtn

	local rotateRightBtn = CreateActionButton(f, ">", 24)
	rotateRightBtn:SetPoint("LEFT", weaponToggleBtn, "RIGHT", 4, 0)
	rotateRightBtn:SetScript("OnClick", function() BB.UI.RotateModel(0.5) end)
	AddTooltip(rotateRightBtn, "Rotate Right", nil)

	statScrollFrame = CreateFrame("ScrollFrame", "AscensionBuildBuddyStatScroll", f, "UIPanelScrollFrameTemplate")
	statScrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", STATS_LEFT_X, -SCROLL_TOP_INSET)
	statScrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_RIGHT_INSET, SCROLL_BOTTOM_INSET)

	local scrollChild = CreateFrame("Frame", nil, statScrollFrame)
	scrollChild:SetWidth(200)
	scrollChild:SetHeight(1)
	statScrollFrame:SetScrollChild(scrollChild)
	statScrollChild = scrollChild

	for _, key in ipairs(SECTION_ORDER) do
		local header = CreateFrame("Button", nil, scrollChild)
		header:SetWidth(200)
		header:SetHeight(HEADER_HEIGHT)

		local arrow = header:CreateTexture(nil, "OVERLAY")
		arrow:SetWidth(14)
		arrow:SetHeight(14)
		arrow:SetPoint("LEFT", header, "LEFT", 0, 0)
		header.arrow = arrow

		local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
		label:SetText(SECTION_LABELS[key])
		label:SetTextColor(1, 0.82, 0)

		header:SetScript("OnClick", function()
			sectionExpanded[key] = not sectionExpanded[key]
			BB.UI.RefreshCharacterTab()
		end)

		sectionHeaders[key] = header
	end

	for i = 1, STAT_LINE_POOL do
		local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetWidth(190)
		fs:Hide()
		statLines[i] = fs
	end

	characterTab = f
	return f
end

local function BuildSectionData(build)
	local attrs = build.attributes or {}
	local melee = build.melee or {}
	local ranged = build.ranged or {}
	local spell = build.spell or { schools = {}, critBySchool = {} }
	local defense = build.defense or {}
	local pathName = build.primaryStatPathName
	local ilvl = build.itemLevel
	local prestige = build.prestigeLevel

	local data = { basic = {}, melee = {}, ranged = {}, spell = {}, defense = {} }

	table.insert(data.basic, { text = "Path of " .. (pathName or "Unknown"), r = 1, g = 0.82, b = 0 })
	table.insert(data.basic, { text = ("Item Level: %s"):format(ilvl and ("%.2f"):format(ilvl) or "?") })
	table.insert(data.basic, { text = ("Prestige Level: %s"):format(prestige and tostring(prestige) or "?") })
	table.insert(data.basic, { text = ("Health: %d"):format(defense.health or 0) })
	for _, stat in ipairs(attrs) do
		table.insert(data.basic, { text = ("%s: %d"):format(stat.label, stat.value or 0), r = 0.2, g = 1, b = 0.2 })
	end

	table.insert(data.melee, { text = ("Damage: %d - %d"):format(melee.minDamage or 0, melee.maxDamage or 0) })
	table.insert(data.melee, { text = ("Speed: %.2f"):format(melee.speed or 0) })
	table.insert(data.melee, { text = ("Attack Power: %d"):format(melee.attackPower or 0) })
	table.insert(data.melee, { text = ("Hit Rating: %.2f%%"):format(melee.hitRating or 0) })
	if melee.hasOffhand then
		table.insert(data.melee, { text = ("Off-Hand Speed: %.2f"):format(melee.offhandSpeed or 0) })
	end
	table.insert(data.melee, { text = ("Armor Penetration: %.2f%%"):format(melee.armorPenetration or 0) })
	table.insert(data.melee, { text = ("Crit Chance: %.2f%%"):format(melee.critChance or 0) })
	table.insert(data.melee, { text = ("Expertise: %.2f"):format(melee.expertise or 0) })

	table.insert(data.ranged, { text = ("Damage: %d - %d"):format(ranged.minDamage or 0, ranged.maxDamage or 0) })
	table.insert(data.ranged, { text = ("Speed: %.2f"):format(ranged.speed or 0) })
	table.insert(data.ranged, { text = ("Attack Power: %d"):format(ranged.attackPower or 0) })
	table.insert(data.ranged, { text = ("Hit Rating: %.2f%%"):format(ranged.hitRating or 0) })
	table.insert(data.ranged, { text = ("Crit Chance: %.2f%%"):format(ranged.critChance or 0) })
	table.insert(data.ranged, { text = ("Haste: %.2f%%"):format(ranged.haste or 0) })

	for _, school in ipairs(spell.schools) do
		table.insert(data.spell, { text = (school.name .. " Damage: %d"):format(school.value) })
	end
	if spell.bonusHealing and spell.bonusHealing ~= 0 then
		table.insert(data.spell, { text = ("Bonus Healing: %d"):format(spell.bonusHealing) })
	end
	for _, school in ipairs(spell.critBySchool) do
		table.insert(data.spell, { text = (school.name .. " Crit: %.2f%%"):format(school.value) })
	end
	table.insert(data.spell, { text = ("Hit Rating: %.2f%%"):format(spell.hitRating or 0) })
	table.insert(data.spell, { text = ("Haste: %.2f%%"):format(spell.haste or 0) })
	if spell.manaRegenBase then
		table.insert(data.spell, { text = ("Mana Regen: %.1f / 5s"):format(spell.manaRegenBase) })
		table.insert(data.spell, { text = ("Mana Regen (casting): %.1f / 5s"):format(spell.manaRegenCasting or 0) })
	end
	if #data.spell == 0 then
		table.insert(data.spell, { text = "No spell stats found." })
	end

	table.insert(data.defense, { text = ("Armor: %d"):format(defense.armor or 0) })
	table.insert(data.defense, { text = ("Dodge: %.2f%%"):format(defense.dodge or 0) })
	table.insert(data.defense, { text = ("Parry: %.2f%%"):format(defense.parry or 0) })
	table.insert(data.defense, { text = ("Block: %.2f%%"):format(defense.block or 0) })
	table.insert(data.defense, { text = ("Defense Rating: %.2f%%"):format(defense.defenseRating or 0) })

	return data
end

function BB.UI.RefreshCharacterTab()
	if not characterTab then return end
	local build = GetActiveBuild()

	local gear = build.gear or {}
	for slotName, btn in pairs(gearButtons) do
		local entry = gear[slotName]
		if entry and entry.texture then
			btn.icon:SetTexture(entry.texture)
			btn.itemLink = entry.link
		else
			btn.icon:SetTexture(BB.Capture.EMPTY_SLOT_TEXTURE[slotName])
			btn.itemLink = nil
		end
	end

	if playerModel then
		playerModel:Show()
		playerModel:SetUnit("player")
		playerModel:Undress()
		for slotName, entry in pairs(gear) do
			local weaponKind = WEAPON_SLOT_KIND[slotName]
			if (not weaponKind or weaponKind == weaponMode) and entry.link then
				playerModel:TryOn(entry.link)
			end
		end
		playerModel:SetFacing(modelFacing)
	end

	local ok, sectionData = pcall(BuildSectionData, build)
	if not ok then
		sectionData = { basic = { { text = "Error: " .. tostring(sectionData), r = 1, g = 0.2, b = 0.2 } }, melee = {}, ranged = {}, spell = {}, defense = {} }
	end

	local y = 0
	local lineIdx = 0
	for _, key in ipairs(SECTION_ORDER) do
		local header = sectionHeaders[key]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", statScrollChild, "TOPLEFT", 0, y)
		header.arrow:SetTexture(sectionExpanded[key]
			and "Interface\\Buttons\\UI-MinusButton-Up"
			or "Interface\\Buttons\\UI-PlusButton-Up")
		y = y - HEADER_HEIGHT

		if sectionExpanded[key] then
			for _, entry in ipairs(sectionData[key]) do
				lineIdx = lineIdx + 1
				local fs = statLines[lineIdx]
				if fs then
					fs:ClearAllPoints()
					fs:SetPoint("TOPLEFT", statScrollChild, "TOPLEFT", 12, y)
					fs:SetText(entry.text or "")
					fs:SetTextColor(entry.r or 1, entry.g or 1, entry.b or 1)
					fs:Show()
				end
				y = y - LINE_HEIGHT
			end
		end
	end

	for i = lineIdx + 1, STAT_LINE_POOL do
		if statLines[i] then statLines[i]:Hide() end
	end

	statScrollChild:SetHeight(math.max(1, -y))
	UpdateScrollBarVisibility(statScrollFrame)
end

local spellsTab
local spellScrollFrame
local spellScrollChild
local talentButtons = {}
local spellButtons = {}
local talentsLabel, spellsLabel, passivesLabel, divider, divider2

local SPELL_ICON_SIZE = 36
local SPELL_ICON_PAD = 4
local SPELL_ICONS_PER_ROW = 10
local TALENT_RANK_LABEL_H = 12
local TALENT_CELL_H = SPELL_ICON_SIZE + TALENT_RANK_LABEL_H
local GROUP_LABEL_HEIGHT = 18
local GROUP_GAP = 20

local function BuildSpellsTab(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f:Hide()

	spellScrollFrame = CreateFrame("ScrollFrame", "AscensionBuildBuddySpellScroll", f, "UIPanelScrollFrameTemplate")
	spellScrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -SCROLL_TOP_INSET)
	spellScrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_RIGHT_INSET, SCROLL_BOTTOM_INSET)

	local scrollChild = CreateFrame("Frame", nil, spellScrollFrame)
	scrollChild:SetWidth(1)
	scrollChild:SetHeight(1)
	spellScrollFrame:SetScrollChild(scrollChild)
	spellScrollChild = scrollChild

	talentsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	talentsLabel:SetJustifyH("LEFT")
	talentsLabel:SetText("Talents")
	talentsLabel:SetTextColor(1, 0.82, 0)
	talentsLabel:Hide()

	divider = scrollChild:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(2)
	divider:SetTexture(1, 0.82, 0, 0.7)
	divider:Hide()

	spellsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	spellsLabel:SetJustifyH("LEFT")
	spellsLabel:SetText("Spells")
	spellsLabel:SetTextColor(1, 0.82, 0)
	spellsLabel:Hide()

	divider2 = scrollChild:CreateTexture(nil, "ARTWORK")
	divider2:SetHeight(1)
	divider2:SetTexture(1, 1, 1, 0.35)
	divider2:Hide()

	passivesLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	passivesLabel:SetJustifyH("LEFT")
	passivesLabel:SetText("Passive Abilities")
	passivesLabel:SetTextColor(0.8, 0.8, 0.8)
	passivesLabel:Hide()

	spellsTab = f
	return f
end

local function SortTalentsByCost(talents)
	table.sort(talents, function(a, b)
		local aCost = a.ae and (a.ae + (a.te or 0)) or nil
		local bCost = b.ae and (b.ae + (b.te or 0)) or nil
		if aCost == nil and bCost == nil then return a.entryId < b.entryId end
		if aCost == nil then return false end
		if bCost == nil then return true end
		if aCost == bCost then return a.entryId < b.entryId end
		return aCost < bCost
	end)
end

local function GetOrCreateTalentButton(idx)
	local btn = talentButtons[idx]
	if btn then return btn end
	btn = CreateFrame("Button", nil, spellScrollChild)
	btn:SetWidth(SPELL_ICON_SIZE)
	btn:SetHeight(SPELL_ICON_SIZE)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	btn.icon = icon
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	rankText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	rankText:SetWidth(SPELL_ICON_SIZE + 14)
	rankText:SetJustifyH("CENTER")
	btn.rankText = rankText

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.tooltipSpellId then
			GameTooltip:SetHyperlink("spell:" .. self.tooltipSpellId)
		else
			GameTooltip:SetText(self.tooltipName or "?", 1, 1, 1)
		end
		if self.tooltipCost then
			GameTooltip:AddLine(self.tooltipCost, 0.8, 0.8, 0.8)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	talentButtons[idx] = btn
	return btn
end

local function LayoutTalentGroup(entries, top)
	for i, entry in ipairs(entries) do
		local btn = GetOrCreateTalentButton(i)
		local col = (i - 1) % SPELL_ICONS_PER_ROW
		local row = math.floor((i - 1) / SPELL_ICONS_PER_ROW)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", col * (SPELL_ICON_SIZE + SPELL_ICON_PAD), top - row * (TALENT_CELL_H + SPELL_ICON_PAD))

		btn.icon:SetTexture(entry.icon)
		btn.rankText:SetText(entry.maxRank and ("%d/%d"):format(entry.rank, entry.maxRank) or ("%d/?"):format(entry.rank))
		btn.tooltipSpellId = entry.spellId
		btn.tooltipName = entry.name
		btn.tooltipCost = entry.ae and ("AE %d / TE %d"):format(entry.ae, entry.te or 0) or nil
		btn:Show()
	end
	for i = #entries + 1, #talentButtons do
		talentButtons[i]:Hide()
	end
	local rows = math.ceil(#entries / SPELL_ICONS_PER_ROW)
	return top - rows * (TALENT_CELL_H + SPELL_ICON_PAD)
end

function BB.UI.RefreshSpellsTab()
	if not spellScrollChild then return end
	local build = GetActiveBuild()

	local talentsAll = {}
	for i, entry in ipairs(build.talents or {}) do talentsAll[i] = entry end
	SortTalentsByCost(talentsAll)

	local realTalents, abilityEntries = {}, {}
	for _, entry in ipairs(talentsAll) do
		if entry.kind == "ability" then
			table.insert(abilityEntries, entry)
		else
			table.insert(realTalents, entry)
		end
	end

	local rawSpells = build.knownSpells or {}
	local rowWidth = SPELL_ICONS_PER_ROW * (SPELL_ICON_SIZE + SPELL_ICON_PAD)

	local talentSpellIds = {}
	for _, entry in ipairs(talentsAll) do
		if entry.spellId then talentSpellIds[entry.spellId] = entry end
	end

	local spells, spellIdSet = {}, {}
	for _, id in ipairs(rawSpells) do
		if not talentSpellIds[id] then
			spellIdSet[id] = true
			table.insert(spells, id)
		end
	end
	for _, entry in ipairs(abilityEntries) do
		local spellId = entry.spellId
		if spellId and not spellIdSet[spellId] then
			spellIdSet[spellId] = true
			table.insert(spells, spellId)
		end
	end

	local y = 0

	talentsLabel:ClearAllPoints()
	talentsLabel:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", 0, y)
	talentsLabel:SetText(#realTalents > 0 and "Talents" or "Talents (none found)")
	talentsLabel:Show()
	y = y - GROUP_LABEL_HEIGHT

	y = LayoutTalentGroup(realTalents, y)

	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", 0, y - (GROUP_GAP / 2))
	divider:SetWidth(rowWidth)
	divider:Show()
	y = y - GROUP_GAP

	local spellbookIndex = BB.Capture.BuildSpellbookIndex()
	local activeSpells, passiveSpells = {}, {}
	for _, id in ipairs(spells) do
		if BB.Capture.IsPassiveSpellId(id, spellbookIndex) then
			table.insert(passiveSpells, id)
		else
			table.insert(activeSpells, id)
		end
	end
	local hasPassiveSplit = #passiveSpells > 0

	if #spells > 0 then
		spellsLabel:ClearAllPoints()
		spellsLabel:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", 0, y)
		spellsLabel:SetText(hasPassiveSplit and "Active Spells" or "Spells")
		spellsLabel:Show()
		y = y - GROUP_LABEL_HEIGHT
	else
		spellsLabel:Hide()
	end

	local btnIdx = 0
	local function GetOrCreateSpellButton(idx)
		local btn = spellButtons[idx]
		if btn then return btn end
		btn = CreateFrame("Button", nil, spellScrollChild)
		btn:SetWidth(SPELL_ICON_SIZE)
		btn:SetHeight(SPELL_ICON_SIZE)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(btn)
		btn.icon = icon
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		btn:SetScript("OnEnter", function(self)
			if self.spellId then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("spell:" .. self.spellId)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		spellButtons[idx] = btn
		return btn
	end

	local function LayoutSpellGroup(ids)
		local top = y
		for i, spellId in ipairs(ids) do
			btnIdx = btnIdx + 1
			local btn = GetOrCreateSpellButton(btnIdx)
			local col = (i - 1) % SPELL_ICONS_PER_ROW
			local row = math.floor((i - 1) / SPELL_ICONS_PER_ROW)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", col * (SPELL_ICON_SIZE + SPELL_ICON_PAD), top - row * (SPELL_ICON_SIZE + SPELL_ICON_PAD))

			local _, _, icon = GetSpellInfo(spellId)
			btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			btn.spellId = spellId
			btn:Show()
		end
		local rows = math.ceil(#ids / SPELL_ICONS_PER_ROW)
		y = top - rows * (SPELL_ICON_SIZE + SPELL_ICON_PAD)
	end

	LayoutSpellGroup(activeSpells)

	if hasPassiveSplit then
		divider2:ClearAllPoints()
		divider2:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", 0, y - (GROUP_GAP / 2))
		divider2:SetWidth(rowWidth)
		divider2:Show()
		y = y - GROUP_GAP

		passivesLabel:ClearAllPoints()
		passivesLabel:SetPoint("TOPLEFT", spellScrollChild, "TOPLEFT", 0, y)
		passivesLabel:Show()
		y = y - GROUP_LABEL_HEIGHT

		LayoutSpellGroup(passiveSpells)
	else
		divider2:Hide()
		passivesLabel:Hide()
	end

	for i = btnIdx + 1, #spellButtons do
		spellButtons[i]:Hide()
	end

	spellScrollChild:SetWidth(rowWidth)
	spellScrollChild:SetHeight(math.max(1, -y))
	UpdateScrollBarVisibility(spellScrollFrame)
end

local cardsTab
local cardsScrollFrame, cardsScrollChild
local cardsEmptyText
local cardIconButtons = {}
local cardSectionLabels = {}
local cardRowLabels = {}
local cardDivider

local CARD_ICON_SIZE = 36
local CARD_ICON_PAD = 44
local CARD_ROW_LABEL_W = 56
local CARD_ROW_GAP = 40
local CARD_SECTION_GAP = CARD_ROW_GAP + 20
local CARD_NAME_WIDTH = CARD_ICON_SIZE + CARD_ICON_PAD - 8

local function GetOrCreateCardIcon(idx)
	local btn = cardIconButtons[idx]
	if btn then return btn end
	btn = CreateFrame("Button", nil, cardsScrollChild)
	btn:SetWidth(CARD_ICON_SIZE)
	btn:SetHeight(CARD_ICON_SIZE)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	btn.icon = icon
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
	nameText:SetWidth(CARD_NAME_WIDTH)
	nameText:SetJustifyH("CENTER")
	btn.nameText = nameText

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.tooltipSpellId then
			GameTooltip:SetHyperlink("spell:" .. self.tooltipSpellId)
		else
			GameTooltip:SetText(self.tooltipName or "?", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	cardIconButtons[idx] = btn
	return btn
end

local function GetOrCreateSectionLabel(idx)
	local fs = cardSectionLabels[idx]
	if fs then return fs end
	fs = cardsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetJustifyH("LEFT")
	cardSectionLabels[idx] = fs
	return fs
end

local function GetOrCreateRowLabel(idx)
	local fs = cardRowLabels[idx]
	if fs then return fs end
	fs = cardsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(0.8, 0.8, 0.8)
	cardRowLabels[idx] = fs
	return fs
end

local function BuildCardsTab(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f:Hide()

	cardsScrollFrame = CreateFrame("ScrollFrame", "AscensionBuildBuddyCardsScroll", f, "UIPanelScrollFrameTemplate")
	cardsScrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -SCROLL_TOP_INSET)
	cardsScrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SCROLL_RIGHT_INSET, SCROLL_BOTTOM_INSET)

	local scrollChild = CreateFrame("Frame", nil, cardsScrollFrame)
	scrollChild:SetWidth(1)
	scrollChild:SetHeight(1)
	cardsScrollFrame:SetScrollChild(scrollChild)
	cardsScrollChild = scrollChild

	cardsEmptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cardsEmptyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
	cardsEmptyText:SetWidth(400)
	cardsEmptyText:SetJustifyH("LEFT")
	cardsEmptyText:SetText(
		"Skill Cards data isn't available yet - open the real Skill Cards panel once " ..
		"this session (it only gets created the first time you open it), then reopen " ..
		"this tab."
	)
	cardsEmptyText:Hide()

	cardDivider = scrollChild:CreateTexture(nil, "ARTWORK")
	cardDivider:SetHeight(1)
	cardDivider:SetTexture(1, 1, 1, 0.35)
	cardDivider:Hide()

	cardsTab = f
	return f
end

local function LayoutCardRow(rowLabelIdx, label, entries, top, iconIdx, rowWidth)
	local rowLabel = GetOrCreateRowLabel(rowLabelIdx)
	rowLabel:ClearAllPoints()
	rowLabel:SetPoint("TOPLEFT", cardsScrollChild, "TOPLEFT", 0, top - (CARD_ICON_SIZE / 2) + 6)
	rowLabel:SetText(label)
	rowLabel:Show()

	local x = 0
	for _, card in ipairs(entries) do
		iconIdx = iconIdx + 1
		local btn = GetOrCreateCardIcon(iconIdx)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", cardsScrollChild, "TOPLEFT", CARD_ROW_LABEL_W + x, top)
		btn.icon:SetTexture(card.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		btn.tooltipSpellId = card.spellId
		btn.tooltipName = card.name or ("Card #" .. tostring(card.cardId))
		btn.nameText:SetText(card.name or ("Card #" .. tostring(card.cardId)))

		btn:Show()
		x = x + CARD_ICON_SIZE + CARD_ICON_PAD
	end

	if rowWidth then rowWidth[1] = math.max(rowWidth[1], CARD_ROW_LABEL_W + x) end
	return iconIdx, top - (CARD_ICON_SIZE + CARD_ROW_GAP)
end

local function LayoutCardSection(sectionIdx, title, golden, normal, top, iconIdx, rowLabelIdx, rowWidth)
	local hasAny = (#golden > 0) or (#normal > 0)
	if not hasAny then return top, iconIdx, rowLabelIdx end

	local header = GetOrCreateSectionLabel(sectionIdx)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", cardsScrollChild, "TOPLEFT", 0, top)
	header:SetText(title)
	header:Show()
	top = top - 18

	rowLabelIdx = rowLabelIdx + 1
	iconIdx, top = LayoutCardRow(rowLabelIdx, "Normal", normal, top, iconIdx, rowWidth)
	rowLabelIdx = rowLabelIdx + 1
	iconIdx, top = LayoutCardRow(rowLabelIdx, "Golden", golden, top, iconIdx, rowWidth)

	return top - (CARD_SECTION_GAP - CARD_ROW_GAP), iconIdx, rowLabelIdx
end

function BB.UI.RefreshCardsTab()
	if not cardsScrollChild then return end
	local build = GetActiveBuild()
	local cards = build and build.cards or { ability = { golden = {}, normal = {} }, talent = { golden = {}, normal = {} } }

	local hasAny = (#cards.ability.golden > 0) or (#cards.ability.normal > 0)
		or (#cards.talent.golden > 0) or (#cards.talent.normal > 0)

	if not hasAny then
		cardsEmptyText:Show()
		cardDivider:Hide()
		for _, fs in pairs(cardSectionLabels) do fs:Hide() end
		for _, fs in pairs(cardRowLabels) do fs:Hide() end
		for _, btn in pairs(cardIconButtons) do btn:Hide() end
		cardsScrollChild:SetHeight(60)
		UpdateScrollBarVisibility(cardsScrollFrame)
		return
	end

	cardsEmptyText:Hide()
	local rowWidth = { 0 }
	local y, iconIdx, rowLabelIdx = 0, 0, 0

	y, iconIdx, rowLabelIdx = LayoutCardSection(1, "Ability Cards", cards.ability.golden, cards.ability.normal, y, iconIdx, rowLabelIdx, rowWidth)

	if (#cards.ability.golden > 0 or #cards.ability.normal > 0) and (#cards.talent.golden > 0 or #cards.talent.normal > 0) then
		cardDivider:ClearAllPoints()
		cardDivider:SetPoint("TOPLEFT", cardsScrollChild, "TOPLEFT", 0, y + (CARD_SECTION_GAP / 2))
		cardDivider:SetWidth(math.max(rowWidth[1], 200))
		cardDivider:Show()
	else
		cardDivider:Hide()
	end

	y, iconIdx, rowLabelIdx = LayoutCardSection(2, "Talent Cards", cards.talent.golden, cards.talent.normal, y, iconIdx, rowLabelIdx, rowWidth)

	for i = iconIdx + 1, #cardIconButtons do cardIconButtons[i]:Hide() end
	for i = rowLabelIdx + 1, #cardRowLabels do cardRowLabels[i]:Hide() end
	for i = 3, #cardSectionLabels do cardSectionLabels[i]:Hide() end

	cardsScrollChild:SetHeight(math.max(1, -y))
	UpdateScrollBarVisibility(cardsScrollFrame)
end

local SIDEBAR_W = 170
local BUILD_ROW_HEIGHT = 20

local buildListScrollFrame, buildListScrollChild
local buildRowPool = {}
local liveBtn
local countText

local function BuildBuildsSidebar(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(SIDEBAR_W)
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)

	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
	header:SetText("Builds")
	header:SetTextColor(1, 0.82, 0)

	countText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	countText:SetPoint("LEFT", header, "RIGHT", 6, 0)

	local function Pair(label1, handler1, label2, handler2, anchor)
		local btn1 = CreateActionButton(f, label1, (SIDEBAR_W - 6) / 2)
		btn1:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
		btn1:SetScript("OnClick", handler1)
		local btn2 = CreateActionButton(f, label2, (SIDEBAR_W - 6) / 2)
		btn2:SetPoint("LEFT", btn1, "RIGHT", 6, 0)
		btn2:SetScript("OnClick", handler2)
		return btn1, btn2
	end

	local newBtn, saveBtn = Pair("New", function() BB.UI.PromptNewBuild() end, "Save", function() BB.UI.SaveOverCurrent() end, header)
	AddTooltip(newBtn, "New Build", "Save your current live character as a new build.")
	AddTooltip(saveBtn, "Save", "Overwrite the selected build with your current live character.")

	local renameBtn, deleteBtn = Pair("Rename", function() BB.UI.PromptRenameBuild() end, "Delete", function() BB.UI.PromptDeleteBuild() end, newBtn)
	AddTooltip(renameBtn, "Rename", "Rename the selected build.")
	AddTooltip(deleteBtn, "Delete", "Delete the selected build.")

	local shareBtn = CreateActionButton(f, "Share / Export", SIDEBAR_W - 4)
	shareBtn:SetPoint("TOPLEFT", renameBtn, "BOTTOMLEFT", 0, -6)
	shareBtn:SetScript("OnClick", function() BB.UI.OpenShareChannelDialog() end)
	AddTooltip(shareBtn, "Share / Export", "Share the selected build to party/raid/guild chat, or get a copy-paste string.")

	local importBtn = CreateActionButton(f, "Import", SIDEBAR_W - 4)
	importBtn:SetPoint("TOPLEFT", shareBtn, "BOTTOMLEFT", 0, -6)
	importBtn:SetScript("OnClick", function() BB.UI.OpenImportDialog() end)
	AddTooltip(importBtn, "Import", "Paste a share string to import a build.")

	liveBtn = CreateFrame("Button", nil, f)
	liveBtn:SetWidth(SIDEBAR_W - 4)
	liveBtn:SetHeight(BUILD_ROW_HEIGHT)
	liveBtn:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -10)
	liveBtn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
	local liveText = liveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	liveText:SetPoint("LEFT", liveBtn, "LEFT", 2, 0)
	liveText:SetText("Live Character")
	liveText:SetTextColor(0.4, 0.8, 1)
	liveBtn.selectedBorder = CreateSelectionBorder(liveBtn, 1)
	liveBtn:SetScript("OnClick", function() BB.UI.ShowLiveBuild() end)
	AddTooltip(liveBtn, "Live Character", "View your current character, always up to date.")

	buildListScrollFrame = CreateFrame("ScrollFrame", "AscensionBuildBuddyBuildListScroll", f, "UIPanelScrollFrameTemplate")
	buildListScrollFrame:SetPoint("TOPLEFT", liveBtn, "BOTTOMLEFT", 0, -8)
	buildListScrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 0)

	local scrollChild = CreateFrame("Frame", nil, buildListScrollFrame)
	scrollChild:SetWidth(SIDEBAR_W - 26)
	scrollChild:SetHeight(1)
	buildListScrollFrame:SetScrollChild(scrollChild)
	buildListScrollChild = scrollChild

	return f
end

function BB.UI.RefreshBuildList()
	if not buildListScrollChild then return end

	if liveBtn then
		if viewingLive then liveBtn.selectedBorder:Show() else liveBtn.selectedBorder:Hide() end
	end

	local names = {}
	for name in pairs(BB.GetBuilds()) do table.insert(names, name) end
	table.sort(names)

	for i, name in ipairs(names) do
		local row = buildRowPool[i]
		if not row then
			row = CreateFrame("Button", nil, buildListScrollChild)
			row:SetWidth(SIDEBAR_W - 26)
			row:SetHeight(BUILD_ROW_HEIGHT)
			row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetPoint("LEFT", row, "LEFT", 2, 0)
			fs:SetJustifyH("LEFT")
			fs:SetWidth(SIDEBAR_W - 30)
			row.text = fs
			row.selectedBorder = CreateSelectionBorder(row, 1)
			buildRowPool[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", buildListScrollChild, "TOPLEFT", 0, -(i - 1) * BUILD_ROW_HEIGHT)
		row.text:SetText(name)
		row.buildName = name
		row:SetScript("OnClick", function() BB.UI.ShowSavedBuild(name) end)
		if not viewingLive and name == currentBuildName then
			row.selectedBorder:Show()
		else
			row.selectedBorder:Hide()
		end
		local build = BB.GetBuilds()[name]
		AddTooltip(row, name, "by " .. ((build and build.author) or "?") .. " - click to view this build.")
		row:Show()
	end

	for i = #names + 1, #buildRowPool do
		buildRowPool[i]:Hide()
	end

	buildListScrollChild:SetHeight(math.max(1, #names * BUILD_ROW_HEIGHT))
	UpdateScrollBarVisibility(buildListScrollFrame)

	if countText then
		countText:SetText(("%d/%d"):format(#names, BB.MAX_BUILDS))
	end
end

local function SetActiveTab(tabName)
	activeTab = tabName
	for name, btn in pairs(tabButtons) do
		if btn.selectedBorder then
			if name == tabName then btn.selectedBorder:Show() else btn.selectedBorder:Hide() end
		end
	end
	for name, frame in pairs(tabFrames) do
		if name == tabName then frame:Show() else frame:Hide() end
	end
	if tabName == "character" then BB.UI.RefreshCharacterTab() end
	if tabName == "spells" then BB.UI.RefreshSpellsTab() end
	if tabName == "cards" then BB.UI.RefreshCardsTab() end
end

function BB.UI.ShowLiveBuild()
	viewingLive = true
	currentBuildName = nil
	viewedBuild = nil
	if mainFrame then mainFrame.nameText:SetText("Live Character") end
	SetActiveTab(activeTab)
	BB.UI.RefreshBuildList()
end

function BB.UI.ShowSavedBuild(name)
	local build = BB.GetBuilds()[name]
	if not build then return end
	viewingLive = false
	currentBuildName = name
	viewedBuild = build
	if mainFrame then
		mainFrame.nameText:SetText(("%s (by %s)"):format(name, build.author or build.playerName or "?"))
	end
	SetActiveTab(activeTab)
	BB.UI.RefreshBuildList()
end

function BB.UI.PromptNewBuild()
	StaticPopup_Show("ASCENSIONBUILDBUDDY_NEW_BUILD")
end

function BB.UI.CreateNewBuild(name)
	name = BB.StripFormatting((name or ""):match("^%s*(.-)%s*$"))
	if name == "" then
		BB.Print("Build name can't be empty.")
		return
	end
	local snapshot = BB.Capture.CaptureCurrent()
	local ok, err = BB.SaveBuild(name, snapshot)
	if not ok then
		BB.Print(err)
		return
	end
	BB.Print("Saved build '" .. name .. "'.")
	BB.UI.ShowSavedBuild(name)
end

function BB.UI.SaveOverCurrent()
	if viewingLive or not currentBuildName then
		BB.UI.PromptNewBuild()
		return
	end
	StaticPopup_Show("ASCENSIONBUILDBUDDY_CONFIRM_SAVE", currentBuildName)
end

function BB.UI.PromptRenameBuild()
	if viewingLive or not currentBuildName then
		BB.Print("Select a saved build to rename.")
		return
	end
	StaticPopup_Show("ASCENSIONBUILDBUDDY_RENAME_BUILD")
end

function BB.UI.RenameCurrentBuild(newName)
	newName = BB.StripFormatting((newName or ""):match("^%s*(.-)%s*$"))
	if viewingLive or not currentBuildName then return end
	if newName == "" then
		BB.Print("Build name can't be empty.")
		return
	end
	if newName == currentBuildName then return end
	if BB.GetBuilds()[newName] then
		BB.Print("A build named '" .. newName .. "' already exists.")
		return
	end
	if not BB.RenameBuild(currentBuildName, newName) then
		BB.Print("Rename failed.")
		return
	end
	BB.Print("Renamed build to '" .. newName .. "'.")
	BB.UI.ShowSavedBuild(newName)
end

function BB.UI.PromptDeleteBuild()
	if viewingLive or not currentBuildName then
		BB.Print("Select a saved build to delete.")
		return
	end
	StaticPopup_Show("ASCENSIONBUILDBUDDY_CONFIRM_DELETE", currentBuildName)
end

function BB.UI.DeleteCurrentBuild()
	if viewingLive or not currentBuildName then return end
	local name = currentBuildName
	BB.DeleteBuild(name)
	BB.Print("Deleted build '" .. name .. "'.")
	BB.UI.ShowLiveBuild()
end

StaticPopupDialogs["ASCENSIONBUILDBUDDY_NEW_BUILD"] = {
	text = "Save your current character as a new build:",
	button1 = "Save",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 64,
	OnAccept = function(self) BB.UI.CreateNewBuild(self.editBox:GetText()) end,
	EditBoxOnEnterPressed = function(self)
		BB.UI.CreateNewBuild(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ASCENSIONBUILDBUDDY_CONFIRM_SAVE"] = {
	text = "Overwrite build \"%s\" with your current character?",
	button1 = "Save",
	button2 = CANCEL,
	OnAccept = function()
		if viewingLive or not currentBuildName then return end
		local name = currentBuildName
		local snapshot = BB.Capture.CaptureCurrent()
		local ok, err = BB.SaveBuild(name, snapshot)
		if not ok then
			BB.Print(err)
			return
		end
		BB.Print("Saved build '" .. name .. "'.")
		BB.UI.ShowSavedBuild(name)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ASCENSIONBUILDBUDDY_RENAME_BUILD"] = {
	text = "Rename build to:",
	button1 = "Rename",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 64,
	OnShow = function(self)
		self.editBox:SetText(currentBuildName or "")
		self.editBox:HighlightText()
	end,
	OnAccept = function(self) BB.UI.RenameCurrentBuild(self.editBox:GetText()) end,
	EditBoxOnEnterPressed = function(self)
		BB.UI.RenameCurrentBuild(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ASCENSIONBUILDBUDDY_CONFIRM_DELETE"] = {
	text = "Delete build \"%s\"? This can't be undone.",
	button1 = "Delete",
	button2 = CANCEL,
	OnAccept = function() BB.UI.DeleteCurrentBuild() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local exportDialog
local function OpenExportDialog(title, str)
	if not exportDialog then
		exportDialog = BuildTextDialog("AscensionBuildBuddyExportDialog", "Export Build")
		exportDialog.hint:SetText("Ctrl+A then Ctrl+C to copy the whole string:")
		MakeModalOverMain(exportDialog)
	end
	exportDialog.titleText:SetText(title)
	exportDialog.editBox:SetText(str)
	exportDialog:Show()
	exportDialog.editBox:HighlightText()
	exportDialog.editBox:SetFocus()
end

function BB.UI.ExportCurrent()
	local name = viewingLive and "Live Character" or currentBuildName
	local buildData = GetActiveBuild()
	local str, err = BB.BuildExport.Export(name, buildData)
	if not str then
		BB.Print("Export failed: " .. tostring(err))
		return
	end
	OpenExportDialog("Share string for \"" .. name .. "\"", str)
end

function BB.UI.ImportBuild(name, buildData, sourceLabel)
	if BB.GetBuilds()[name] then
		StaticPopup_Show("ASCENSIONBUILDBUDDY_CONFIRM_IMPORT_OVERWRITE", name, nil, { name = name, buildData = buildData, sourceLabel = sourceLabel })
		return
	end
	local ok, err = BB.SaveBuild(name, buildData)
	if not ok then
		BB.Print("Import failed: " .. err)
		return
	end
	BB.Print(("Imported build \"%s\"%s."):format(name, sourceLabel and (" " .. sourceLabel) or ""))
	BB.UI.ShowSavedBuild(name)
end

StaticPopupDialogs["ASCENSIONBUILDBUDDY_CONFIRM_IMPORT_OVERWRITE"] = {
	text = "You already have a build named \"%s\". Overwrite it?",
	button1 = "Overwrite",
	button2 = CANCEL,
	OnAccept = function(self, data)
		local ok, err = BB.SaveBuild(data.name, data.buildData)
		if not ok then
			BB.Print("Import failed: " .. err)
			return
		end
		BB.Print(("Imported build \"%s\"%s (overwritten)."):format(data.name, data.sourceLabel and (" " .. data.sourceLabel) or ""))
		BB.UI.ShowSavedBuild(data.name)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local importDialog
function BB.UI.OpenImportDialog()
	if not importDialog then
		importDialog = BuildTextDialog("AscensionBuildBuddyImportDialog", "Import Build")
		importDialog.hint:SetText("Paste a share string, then click Import:")
		MakeModalOverMain(importDialog)

		local importBtn = CreateActionButton(importDialog, "Import", 80)
		importBtn:SetPoint("BOTTOMLEFT", importDialog, "BOTTOMLEFT", 14, 14)
		importBtn:SetScript("OnClick", function()
			local ok, name, buildData, err = BB.BuildExport.Import(importDialog.editBox:GetText())
			if not ok then
				BB.Print("Import failed: " .. tostring(err))
				return
			end
			importDialog:Hide()
			BB.UI.ImportBuild(name, buildData, "(pasted)")
		end)
		AddTooltip(importBtn, "Import", "Import the pasted build.")

		local cancelBtn = CreateActionButton(importDialog, "Cancel", 80)
		cancelBtn:SetPoint("BOTTOMRIGHT", importDialog, "BOTTOMRIGHT", -14, 14)
		cancelBtn:SetScript("OnClick", function() importDialog:Hide() end)
		AddTooltip(cancelBtn, "Cancel", nil)
	end
	importDialog.editBox:SetText("")
	importDialog:Show()
	importDialog.editBox:SetFocus()
end

local shareChannelDialog

local function BuildShareChannelDialog()
	local f = CreateBorderedFrame("AscensionBuildBuddyShareChannel", UIParent, 260, 190, "Share Build")
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:Hide()

	local info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	info:SetPoint("TOP", f, "TOP", 0, -34)
	info:SetText("Share to which chat?")

	local raidBtn = CreateActionButton(f, "Raid", 70)
	raidBtn:SetPoint("TOP", info, "BOTTOM", 0, -16)
	raidBtn:SetScript("OnClick", function() BB.UI.ShareCurrentBuild("RAID") f:Hide() end)
	AddTooltip(raidBtn, "Raid", "Share this build to raid chat.")

	local partyBtn = CreateActionButton(f, "Party", 70)
	partyBtn:SetPoint("RIGHT", raidBtn, "LEFT", -6, 0)
	partyBtn:SetScript("OnClick", function() BB.UI.ShareCurrentBuild("PARTY") f:Hide() end)
	AddTooltip(partyBtn, "Party", "Share this build to party chat.")

	local guildBtn = CreateActionButton(f, "Guild", 70)
	guildBtn:SetPoint("LEFT", raidBtn, "RIGHT", 6, 0)
	guildBtn:SetScript("OnClick", function() BB.UI.ShareCurrentBuild("GUILD") f:Hide() end)
	AddTooltip(guildBtn, "Guild", "Share this build to guild chat.")

	local orText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	orText:SetPoint("TOP", raidBtn, "BOTTOM", 0, -14)
	orText:SetText("- or -")

	local stringBtn = CreateActionButton(f, "Copy as String", 160)
	stringBtn:SetPoint("TOP", orText, "BOTTOM", 0, -8)
	stringBtn:SetScript("OnClick", function() f:Hide() BB.UI.ExportCurrent() end)
	AddTooltip(stringBtn, "Copy as String", "Get a copy-paste export string for the selected build instead.")

	local cancelBtn = CreateActionButton(f, "Cancel", 80)
	cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
	cancelBtn:SetScript("OnClick", function() f:Hide() end)
	AddTooltip(cancelBtn, "Cancel", nil)

	return f
end

function BB.UI.ShareCurrentBuild(channel)
	if channel == "GUILD" and not IsInGuild() then
		BB.Print("You're not in a guild.")
		return
	end
	if channel == "PARTY" and not IsInGroup() then
		BB.Print("You're not in a party.")
		return
	end
	if channel == "RAID" and not IsInRaid() then
		BB.Print("You're not in a raid.")
		return
	end
	local name = viewingLive and "Live Character" or currentBuildName
	local buildData = GetActiveBuild()
	BB.BuildChat.PostBuild(channel, name, buildData)
end

function BB.UI.OpenShareChannelDialog()
	if not shareChannelDialog then
		shareChannelDialog = BuildShareChannelDialog()
		MakeModalOverMain(shareChannelDialog)
	end
	shareChannelDialog:Show()
end

local function FormatBuildSummary(buildData)
	local lvl = buildData.level or 0
	local cls = buildData.classToken or buildData.class or "?"
	local ilvl = buildData.itemLevel
	return ("Level %d %s%s"):format(lvl, tostring(cls), ilvl and (" - Item Level " .. ("%.1f"):format(ilvl)) or "")
end

local sharePreviewDialog
local pendingSharedBuild

local function BuildSharePreviewDialog()
	local f = CreateBorderedFrame("AscensionBuildBuddySharePreview", UIParent, 300, 160, "Shared Build")
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:Hide()

	local info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	info:SetPoint("TOP", f, "TOP", 0, -34)
	info:SetWidth(270)
	info:SetJustifyH("CENTER")
	f.info = info

	local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOP", info, "BOTTOM", 0, -10)
	summary:SetWidth(270)
	summary:SetJustifyH("CENTER")
	f.summary = summary

	local acceptBtn = CreateActionButton(f, "Import", 90)
	acceptBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
	acceptBtn:SetScript("OnClick", function()
		if not pendingSharedBuild then
			f:Hide()
			return
		end
		local p = pendingSharedBuild
		pendingSharedBuild = nil
		f:Hide()
		BB.UI.ImportBuild(p.buildName, p.buildData, "(shared by " .. p.sender .. ")")
	end)
	AddTooltip(acceptBtn, "Import", "Save this shared build to your own build list.")

	local declineBtn = CreateActionButton(f, "Decline", 90)
	declineBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	declineBtn:SetScript("OnClick", function()
		pendingSharedBuild = nil
		f:Hide()
	end)
	AddTooltip(declineBtn, "Decline", "Don't save this shared build.")

	return f
end

BB.BuildChat.onBuildReceived = function(sender, buildName, buildData)
	if not sharePreviewDialog then
		sharePreviewDialog = BuildSharePreviewDialog()
		sharePreviewDialog:SetFrameStrata("FULLSCREEN_DIALOG")
	end
	pendingSharedBuild = { sender = sender, buildName = buildName, buildData = buildData }
	sharePreviewDialog.info:SetText(("%s shared \"%s\""):format(sender, buildName))
	sharePreviewDialog.summary:SetText(FormatBuildSummary(buildData))
	sharePreviewDialog:Show()
end

local shareToastDialog

local function BuildShareToastDialog()
	local f = CreateBorderedFrame("AscensionBuildBuddyShareToast", UIParent, 280, 110, "Build Shared")
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("DIALOG")
	f:Hide()

	local info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	info:SetPoint("TOP", f, "TOP", 0, -34)
	info:SetWidth(250)
	info:SetJustifyH("CENTER")
	f.info = info

	local getBtn = CreateActionButton(f, "Get", 90)
	getBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
	getBtn:SetScript("OnClick", function()
		if f.pending then
			BB.BuildChat.RequestBuild(f.pending.sender, f.pending.shareID)
		end
		f:Hide()
	end)
	AddTooltip(getBtn, "Get", "Request this shared build from its sender.")

	local ignoreBtn = CreateActionButton(f, "Ignore", 90)
	ignoreBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	ignoreBtn:SetScript("OnClick", function()
		f.pending = nil
		f:Hide()
	end)
	AddTooltip(ignoreBtn, "Ignore", "Don't request this shared build.")

	return f
end

BB.BuildChat.onShareAnnounced = function(sender, shareID, buildName)
	if not shareToastDialog then
		shareToastDialog = BuildShareToastDialog()
		shareToastDialog:SetFrameStrata("FULLSCREEN_DIALOG")
	end
	shareToastDialog.pending = { sender = sender, shareID = shareID }
	shareToastDialog.info:SetText(("%s shared \"%s\""):format(sender, BB.StripFormatting(buildName)))
	shareToastDialog:Show()
end

local function BuildMainFrame()
	local f = CreateBorderedFrame("AscensionBuildBuddyMainFrame", UIParent, 740, 560, "Ascension Build Buddy")
	f:SetPoint("CENTER")
	f:Hide()

	local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	nameText:SetPoint("TOP", f, "TOP", 0, -34)
	f.nameText = nameText

	local sidebarArea = CreateFrame("Frame", nil, f)
	sidebarArea:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -54)
	sidebarArea:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
	sidebarArea:SetWidth(SIDEBAR_W)
	BuildBuildsSidebar(sidebarArea)

	local CONTENT_X = 14 + SIDEBAR_W + 14

	local contentArea = CreateFrame("Frame", nil, f)
	contentArea:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_X, -80)
	contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)

	local tabNames = { "character", "spells", "cards" }
	local tabLabels = { character = "Character", spells = "Spells & Talents", cards = "Cards" }
	local tabWidths = { character = 130, spells = 130, cards = 80 }
	local contentWidth = 740 - CONTENT_X - 12
	local tabRowWidth = 0
	for _, tabName in ipairs(tabNames) do
		tabRowWidth = tabRowWidth + tabWidths[tabName]
	end
	tabRowWidth = tabRowWidth + 6 * (#tabNames - 1)
	local tabRowStartX = CONTENT_X + (contentWidth - tabRowWidth) / 2

	local prevTab
	for _, tabName in ipairs(tabNames) do
		local btn = CreateActionButton(f, tabLabels[tabName], tabWidths[tabName])
		if prevTab then
			btn:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
		else
			btn:SetPoint("TOPLEFT", f, "TOPLEFT", tabRowStartX, -52)
		end
		btn.selectedBorder = CreateSelectionBorder(btn, 3)
		btn:SetScript("OnClick", function() SetActiveTab(tabName) end)
		tabButtons[tabName] = btn
		prevTab = btn
	end

	tabFrames.character = BuildCharacterTab(contentArea)
	tabFrames.spells = BuildSpellsTab(contentArea)
	tabFrames.cards = BuildCardsTab(contentArea)

	mainFrame = f
	return f
end

function BB.ToggleMainFrame()
	if not mainFrame then
		BuildMainFrame()
	end
	if mainFrame:IsShown() then
		mainFrame:Hide()
		return
	end

	mainFrame:Show()
	if viewingLive then
		BB.UI.ShowLiveBuild()
	else
		BB.UI.ShowSavedBuild(currentBuildName)
	end
end
