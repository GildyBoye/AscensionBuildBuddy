AscensionBuildBuddy = AscensionBuildBuddy or {}
local BB = AscensionBuildBuddy
BB.Capture = {}

BB.Capture.LEFT_SLOTS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
BB.Capture.RIGHT_SLOTS = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
BB.Capture.BOTTOM_SLOTS = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

local EMPTY_SLOT_TEXTURE = {
	HeadSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
	NeckSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck",
	ShoulderSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
	BackSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
	ChestSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
	ShirtSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shirt",
	TabardSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Tabard",
	WristSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
	HandsSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
	WaistSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
	LegsSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
	FeetSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
	Finger0Slot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
	Finger1Slot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
	Trinket0Slot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
	Trinket1Slot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
	MainHandSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
	SecondaryHandSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
	RangedSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged",
}
BB.Capture.EMPTY_SLOT_TEXTURE = EMPTY_SLOT_TEXTURE

function BB.Capture.GetGear(unit)
	unit = unit or "player"
	local gear = {}
	local allSlots = {}
	for _, s in ipairs(BB.Capture.LEFT_SLOTS) do table.insert(allSlots, s) end
	for _, s in ipairs(BB.Capture.RIGHT_SLOTS) do table.insert(allSlots, s) end
	for _, s in ipairs(BB.Capture.BOTTOM_SLOTS) do table.insert(allSlots, s) end

	for _, slotName in ipairs(allSlots) do
		local slotId = GetInventorySlotInfo(slotName)
		if slotId then
			local link = GetInventoryItemLink(unit, slotId)
			local texture = GetInventoryItemTexture(unit, slotId)
			gear[slotName] = { slotId = slotId, link = link, texture = texture }
		end
	end
	return gear
end

local STAT_LABELS = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
BB.Capture.STAT_LABELS = STAT_LABELS

function BB.Capture.GetAttributes(unit)
	unit = unit or "player"
	local stats = {}
	for i = 1, 5 do
		local base, effective = UnitStat(unit, i)
		stats[i] = { label = STAT_LABELS[i], value = effective, base = base }
	end
	return stats
end

function BB.Capture.GetMeleeStats(unit)
	unit = unit or "player"
	local minDmg, maxDmg = UnitDamage(unit)
	local speed, offhandSpeed = UnitAttackSpeed(unit)
	local base, posBuff, negBuff = UnitAttackPower(unit)

	local hitRating, critChance, armorPen, expertise = 0, 0, 0, 0
	if CR_HIT_MELEE then hitRating = GetCombatRatingBonus(CR_HIT_MELEE) end
	if GetCritChance then critChance = GetCritChance() end
	if GetArmorPenetration then armorPen = GetArmorPenetration() end
	if CR_EXPERTISE then expertise = GetCombatRatingBonus(CR_EXPERTISE) end

	return {
		minDamage = minDmg,
		maxDamage = maxDmg,
		speed = speed,
		offhandSpeed = offhandSpeed,
		attackPower = (base or 0) + (posBuff or 0) + (negBuff or 0),
		hitRating = hitRating,
		critChance = critChance,
		armorPenetration = armorPen,
		expertise = expertise,
		hasOffhand = offhandSpeed ~= nil,
	}
end

function BB.Capture.GetRangedStats(unit)
	unit = unit or "player"
	local result = { minDamage = 0, maxDamage = 0, speed = 0, attackPower = 0, hitRating = 0, critChance = 0, haste = 0 }

	local ok, minDmg, maxDmg = pcall(UnitRangedDamage, unit)
	if ok then
		result.minDamage = minDmg or 0
		result.maxDamage = maxDmg or 0
	end

	local okSpeed, speed = pcall(UnitRangedAttackSpeed, unit)
	if okSpeed then result.speed = speed or 0 end

	local okAP, base, posBuff, negBuff = pcall(UnitRangedAttackPower, unit)
	if okAP then result.attackPower = (base or 0) + (posBuff or 0) + (negBuff or 0) end

	if CR_HIT_RANGED then
		local ok2, v = pcall(GetCombatRatingBonus, CR_HIT_RANGED)
		if ok2 then result.hitRating = v or 0 end
	end
	local okCrit, crit = pcall(GetRangedCritChance)
	if okCrit then result.critChance = crit or 0 end
	if CR_HASTE_RANGED then
		local ok3, v = pcall(GetCombatRatingBonus, CR_HASTE_RANGED)
		if ok3 then result.haste = v or 0 end
	end

	return result
end

local SPELL_SCHOOLS = {
	{ id = 2, name = "Holy" },
	{ id = 3, name = "Fire" },
	{ id = 4, name = "Nature" },
	{ id = 5, name = "Frost" },
	{ id = 6, name = "Shadow" },
	{ id = 7, name = "Arcane" },
}

function BB.Capture.GetSpellStats(unit)
	local result = { schools = {}, critBySchool = {}, hitRating = 0, haste = 0 }
	if unit and unit ~= "player" then return result end

	for _, school in ipairs(SPELL_SCHOOLS) do
		local ok, dmg = pcall(GetSpellBonusDamage, school.id)
		if ok and dmg and dmg ~= 0 then
			table.insert(result.schools, { name = school.name, value = dmg })
		end
	end
	local okHeal, healing = pcall(GetSpellBonusHealing)
	if okHeal and healing and healing ~= 0 then result.bonusHealing = healing end

	for _, school in ipairs(SPELL_SCHOOLS) do
		local ok, crit = pcall(GetSpellCritChance, school.id)
		if ok and crit and crit ~= 0 then
			table.insert(result.critBySchool, { name = school.name, value = crit })
		end
	end

	if CR_HIT_SPELL then
		local ok, v = pcall(GetCombatRatingBonus, CR_HIT_SPELL)
		if ok then result.hitRating = v or 0 end
	end
	if CR_HASTE_SPELL then
		local ok, v = pcall(GetCombatRatingBonus, CR_HASTE_SPELL)
		if ok then result.haste = v or 0 end
	end

	local okPT, powerType = pcall(UnitPowerType, "player")
	if okPT and powerType == 0 then
		local okMR, base, casting = pcall(GetManaRegen)
		if okMR then
			result.manaRegenBase = (base or 0) * 5
			result.manaRegenCasting = (casting or 0) * 5
		end
	end
	return result
end

function BB.Capture.GetDefenseStats(unit)
	unit = unit or "player"
	local result = { armor = 0, health = 0, dodge = 0, parry = 0, block = 0, defenseRating = 0 }

	local okArmor, base, effective = pcall(UnitArmor, unit)
	if okArmor then result.armor = effective or 0 end

	local okHealth, health = pcall(UnitHealthMax, unit)
	if okHealth then result.health = health or 0 end

	local okDodge, dodge = pcall(GetDodgeChance)
	if okDodge then result.dodge = dodge or 0 end
	local okParry, parry = pcall(GetParryChance)
	if okParry then result.parry = parry or 0 end
	local okBlock, block = pcall(GetBlockChance)
	if okBlock then result.block = block or 0 end

	if CR_DEFENSE_SKILL then
		local ok, v = pcall(GetCombatRatingBonus, CR_DEFENSE_SKILL)
		if ok then result.defenseRating = v or 0 end
	end

	return result
end

local PRIMARY_STAT_PATH_NAMES = {
	[1] = "Strength",
	[2] = "Agility",
	[3] = "Intelligence",
	[4] = "Healing",
	[6] = "Duality",
}
BB.Capture.PRIMARY_STAT_PATH_NAMES = PRIMARY_STAT_PATH_NAMES

function BB.Capture.GetPrimaryStatPath(unit)
	unit = unit or "player"
	if type(GetUnitPrimaryStat) == "function" then
		local ok, pathId = pcall(GetUnitPrimaryStat, unit)
		if ok then return pathId end
	end
	return nil
end

function BB.Capture.GetPrimaryStatPathName(unit)
	local pathId = BB.Capture.GetPrimaryStatPath(unit)
	if not pathId then return nil end
	return PRIMARY_STAT_PATH_NAMES[pathId] or ("Path #" .. tostring(pathId))
end

function BB.Capture.GetItemLevel(unit)
	unit = unit or "player"
	if type(GetAverageItemLevel) ~= "function" then return nil end
	local ok, a, b = pcall(GetAverageItemLevel, unit)
	if ok and a then return a, b end
	ok, a, b = pcall(GetAverageItemLevel)
	if ok and a then return a, b end
	return nil
end

function BB.Capture.GetPrestigeLevel(unit)
	unit = unit or "player"
	if type(GetPrestigeLevel) ~= "function" then return nil end
	local ok, p = pcall(GetPrestigeLevel, unit)
	if ok and p then return p end
	ok, p = pcall(GetPrestigeLevel)
	if ok and p then return p end
	return nil
end

local function NormalizeIdList(list)
	local out = {}
	if type(list) ~= "table" then return out end

	for _, v in ipairs(list) do
		if type(v) == "number" then
			table.insert(out, v)
		elseif type(v) == "table" then
			table.insert(out, v.entryId or v.ID or v.id or v.spellId or v[1])
		end
	end
	if #out > 0 then return out end

	for k in pairs(list) do
		if type(k) == "number" then
			table.insert(out, k)
		end
	end
	return out
end

function BB.Capture.GetTalents()
	if not (C_CharacterAdvancement and C_CharacterAdvancement.GetKnownTalentEntries) then
		return {}
	end

	local specId
	if C_CharacterAdvancement.GetActiveSpecID then
		local specOk, id = pcall(C_CharacterAdvancement.GetActiveSpecID)
		if specOk then specId = id end
	end

	local ok, entries = false, nil
	if specId then
		ok, entries = pcall(C_CharacterAdvancement.GetKnownTalentEntries, specId)
	end
	if not ok or not entries then
		ok, entries = pcall(C_CharacterAdvancement.GetKnownTalentEntries)
	end
	if not ok or not entries then return {} end

	local function RankFor(entryId)
		if not C_CharacterAdvancement.GetTalentRankByID then return 0 end
		local rankOk, r = pcall(C_CharacterAdvancement.GetTalentRankByID, entryId)
		return (rankOk and r) or 0
	end

	local result = {}
	for _, v in ipairs(entries) do
		if type(v) == "table" then
			local entryId = v.entryId or v.ID or v.id
			if entryId then
				table.insert(result, { entryId = entryId, rank = RankFor(entryId), node = v })
			end
		elseif type(v) == "number" then
			table.insert(result, { entryId = v, rank = RankFor(v) })
		end
	end

	if #result == 0 then
		for k in pairs(entries) do
			if type(k) == "number" then
				table.insert(result, { entryId = k, rank = RankFor(k) })
			end
		end
	end

	return result
end

function BB.Capture.GetKnownSpells()
	if not (C_CharacterAdvancement and C_CharacterAdvancement.GetKnownSpells) then
		return {}
	end
	local ok, spells = pcall(C_CharacterAdvancement.GetKnownSpells)
	if not ok or not spells then return {} end
	return NormalizeIdList(spells)
end

function BB.Capture.BuildSpellbookIndex()
	local index = {}
	if type(GetNumSpellTabs) ~= "function" or type(GetSpellBookItemInfo) ~= "function" then
		return index
	end
	local okTabs, numTabs = pcall(GetNumSpellTabs)
	if not okTabs or not numTabs then return index end

	for tab = 1, numTabs do
		local okTab, _, _, offset, numSpells = pcall(GetSpellTabInfo, tab)
		if okTab and offset and numSpells then
			for i = offset + 1, offset + numSpells do
				local okItem, spellType, spellId = pcall(GetSpellBookItemInfo, i, BOOKTYPE_SPELL)
				if okItem and spellType == "SPELL" and spellId then
					index[spellId] = i
				end
			end
		end
	end
	return index
end

function BB.Capture.IsPassiveSpellId(spellId, spellbookIndex)
	local slot = spellbookIndex and spellbookIndex[spellId]
	if not slot or type(IsPassiveSpell) ~= "function" then return nil end
	local ok, isPassive = pcall(IsPassiveSpell, slot, BOOKTYPE_SPELL)
	if ok then return isPassive end
	return nil
end

function BB.Capture.GetTalentDisplayInfo(entryId, node)
	node = node or (CHARACTER_ADVANCEMENT_NODES and CHARACTER_ADVANCEMENT_NODES[entryId])
	if node and node.Name then
		local icon = node.Icon
		if icon and not tostring(icon):find("\\") then
			icon = "Interface\\Icons\\" .. icon
		end
		return node.Name, icon
	end
	return ("Talent #" .. tostring(entryId)), "Interface\\Icons\\INV_Misc_QuestionMark"
end

function BB.Capture.GetTalentCost(entryId, node)
	node = node or (CHARACTER_ADVANCEMENT_NODES and CHARACTER_ADVANCEMENT_NODES[entryId])
	if not node then return nil, nil end
	return node.AECost, node.TECost
end

function BB.Capture.ClassifyTalentEntry(entry)
	local node = entry.node
	local te = node and node.TECost
	local ae = node and node.AECost
	if te and te > 0 then return "talent" end
	if ae and ae > 0 then return "ability" end
	return "talent"
end

function BB.Capture.GetTalentMaxRank(entry)
	local node = entry.node
	if not node or type(node.Spells) ~= "table" then return nil end
	return #node.Spells
end

function BB.Capture.GetTalentSpellId(entry)
	local node = entry.node
	if not node or not node.Spells then return nil end
	if type(node.Spells) == "number" then return node.Spells end
	if type(node.Spells) == "table" then
		return node.Spells[entry.rank] or node.Spells[1]
	end
	return nil
end

local function ReadCardSlots(tif, maxGolden, maxNormal)
	local golden, normal = {}, {}
	for i = 1, (maxGolden or 0) do
		local ok, info = pcall(tif.GetCardInfoGoldenAtIndex, tif, i)
		if ok and type(info) == "table" and info.SpellID then
			local name, _, icon = GetSpellInfo(info.SpellID)
			table.insert(golden, {
				cardId = info.CardID, spellId = info.SpellID, itemId = info.ItemID,
				quality = info.Quality, rank = info.Rank, maxRank = info.MaxRank,
				name = name, icon = icon,
			})
		end
	end
	for i = 1, (maxNormal or 0) do
		local ok, info = pcall(tif.GetCardInfoNormalAtIndex, tif, i)
		if ok and type(info) == "table" and info.SpellID then
			local name, _, icon = GetSpellInfo(info.SpellID)
			table.insert(normal, {
				cardId = info.CardID, spellId = info.SpellID, itemId = info.ItemID,
				quality = info.Quality, rank = info.Rank, maxRank = info.MaxRank,
				name = name, icon = icon,
			})
		end
	end
	return golden, normal
end

local cachedCards, cachedCardsTime
local CARDS_CACHE_TTL = 60

function BB.Capture.GetSocketedCards(forceRefresh)
	if not forceRefresh and cachedCards and cachedCardsTime and (GetTime() - cachedCardsTime) < CARDS_CACHE_TTL then
		return cachedCards
	end

	local result = { ability = { golden = {}, normal = {} }, talent = { golden = {}, normal = {} } }
	local frame = SkillCardsFrame
	local tif = frame and frame.TabInsetFrame
	if not frame or not tif or not frame.SetTab then
		return result
	end

	local originalTab = frame.selectedTab
	local seenAbility, seenTalent = false, false

	local function TryTab(i)
		if not pcall(frame.SetTab, frame, i) then return end
		local cardType = tif.cardTypeGolden
		local okMaxG, maxG = pcall(tif.GetMaxGoldenCards, tif)
		local okMaxN, maxN = pcall(tif.GetMaxNormalCards, tif)
		maxG = (okMaxG and type(maxG) == "number") and maxG or 0
		maxN = (okMaxN and type(maxN) == "number") and maxN or 0

		if cardType == "SKILL_CARD_DEFAULT_GOLDEN" and not seenAbility then
			result.ability.golden, result.ability.normal = ReadCardSlots(tif, maxG, maxN)
			seenAbility = true
		elseif cardType == "SKILL_CARD_TALENT_GOLDEN" and not seenTalent then
			result.talent.golden, result.talent.normal = ReadCardSlots(tif, maxG, maxN)
			seenTalent = true
		end
	end

	TryTab(1)
	TryTab(4)

	if not (seenAbility and seenTalent) then
		local numTabs = frame.numTabs or 5
		for i = 1, numTabs do
			if seenAbility and seenTalent then break end
			TryTab(i)
		end
	end

	if originalTab then
		pcall(frame.SetTab, frame, originalTab)
	end

	cachedCards = result
	cachedCardsTime = GetTime()
	return result
end

function BB.Capture.CaptureCharacterSnapshot()
	return {
		gear = BB.Capture.GetGear("player"),
		attributes = BB.Capture.GetAttributes("player"),
		melee = BB.Capture.GetMeleeStats("player"),
		ranged = BB.Capture.GetRangedStats("player"),
		spell = BB.Capture.GetSpellStats("player"),
		defense = BB.Capture.GetDefenseStats("player"),
		primaryStatPath = BB.Capture.GetPrimaryStatPath("player"),
		primaryStatPathName = BB.Capture.GetPrimaryStatPathName("player"),
		itemLevel = BB.Capture.GetItemLevel("player"),
		prestigeLevel = BB.Capture.GetPrestigeLevel("player"),
	}
end

function BB.Capture.CaptureTalents()
	local liveTalents = BB.Capture.GetTalents()
	local talents = {}
	for _, entry in ipairs(liveTalents) do
		local name, icon = BB.Capture.GetTalentDisplayInfo(entry.entryId, entry.node)
		local ae, te = BB.Capture.GetTalentCost(entry.entryId, entry.node)
		table.insert(talents, {
			entryId = entry.entryId,
			rank = entry.rank,
			maxRank = BB.Capture.GetTalentMaxRank(entry),
			name = name,
			icon = icon,
			ae = ae,
			te = te,
			spellId = BB.Capture.GetTalentSpellId(entry),
			kind = BB.Capture.ClassifyTalentEntry(entry),
		})
	end
	return talents
end

function BB.Capture.GetTotalEssenceSpent()
	local ae, te = 0, 0
	if type(C_CharacterAdvancement) == "table" then
		if C_CharacterAdvancement.GetGlobalAEInvestment then
			local ok, v = pcall(C_CharacterAdvancement.GetGlobalAEInvestment)
			if ok and type(v) == "number" then ae = v end
		end
		if C_CharacterAdvancement.GetGlobalTEInvestment then
			local ok, v = pcall(C_CharacterAdvancement.GetGlobalTEInvestment)
			if ok and type(v) == "number" then te = v end
		end
	end
	return ae, te
end

function BB.Capture.CaptureCurrent()
	local build = {
		version = 1,
		playerName = UnitName("player"),
		level = UnitLevel("player"),
		created = time(),
		updated = time(),
		knownSpells = BB.Capture.GetKnownSpells(),
	}
	for k, v in pairs(BB.Capture.CaptureCharacterSnapshot()) do
		build[k] = v
	end
	build.class, build.classToken = UnitClass("player")
	build.race = UnitRace("player")
	build.realmName = GetRealmName()
	build.author = (build.playerName or "Unknown") .. "-" .. (build.realmName or "")
	if C_CharacterAdvancement and C_CharacterAdvancement.GetActiveSpecID then
		local ok, specId = pcall(C_CharacterAdvancement.GetActiveSpecID)
		if ok then build.specId = specId end
	end

	build.talents = BB.Capture.CaptureTalents()
	build.cards = BB.Capture.GetSocketedCards(true)
	build.totalAE, build.totalTE = BB.Capture.GetTotalEssenceSpent()

	return build
end
