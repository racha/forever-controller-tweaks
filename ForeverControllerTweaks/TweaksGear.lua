-- Forever Controller Tweaks "Tweaks", loot and gear: Fast loot, Pass on unusable rolls, Upgrade arrows and Wear
-- quest rewards (rows of the Tweaks tab), and the picker's Eat & drink and Quest item actions. Tweaks.lua's rules: off
-- until turned on, only while the Gamepad UI is on, nothing written on a Blizzard frame. The arrows and the reward
-- card are our own frames; the two actions are our own secure buttons whose macro text is written out of combat.
--   Gear.CanEver(class, classID, subClassID)  false when the class can never use that kind of gear, true when it can,
--                                  nil when unsure.
--   Gear.Upgrade(link)             the inventory slot an item would be an upgrade in, else nil (the rule below).
local _, ns = ...
local Tweaks = ns.Tweaks
local Gear = {}
Tweaks.Gear = Gear
local on, call, secret = Tweaks.Is, Tweaks.Call, Tweaks.Secret

local T = {
	BAGS_FULL = "Fast loot: your bags are full, %d item%s left in the loot.", PASSED = "Passed on %s: your class can't use it.",
	WEAR = "Hold %s to wear it", NO_FOOD = "Eat & drink: no food or drink in your bags.", NO_QUEST_ITEM = "Quest item: none of your quests has an item to use.",
}
Gear.T = T

local ITEM = Enum and Enum.ItemClass or {}
local ARMOR, WEAPON, CONSUMABLE = ITEM.Armor or 4, ITEM.Weapon or 2, ITEM.Consumable or 0
local FOOD_DRINK = Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink or 5
local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local PASS = Enum and Enum.LootRollType and Enum.LootRollType.Pass or 0
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

---------------------------------------------------------------------------------------------------------------------
-- What a class can ever use. Only what holds in every era is judged; anything else is "unsure" (nil), and unsure
-- never passes a roll.

-- The heaviest armor a class ever wears (Enum.ItemArmorSubclass: Cloth 1, Leather 2, Mail 3, Plate 4).
local ARMOR_MAX = {
	MAGE = 1, PRIEST = 1, WARLOCK = 1, ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
	HUNTER = 3, SHAMAN = 3, EVOKER = 3, WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
-- Armor kinds only some classes use: shields (6), librams (7), idols (8), totems (9), sigils (10).
local ARMOR_ONLY = {
	[6] = { WARRIOR = true, PALADIN = true, SHAMAN = true }, [7] = { PALADIN = true }, [8] = { DRUID = true },
	[9] = { SHAMAN = true }, [10] = { DEATHKNIGHT = true },
}
-- The cloth casters' whole weapon list (one-hand swords 7, staves 10, daggers 15, wands 19; priests one-hand maces
-- 4 for swords). Wands are theirs alone. Generic weapons (14) and fishing poles (20) are never judged.
local MAGE_WEAPONS = { [7] = true, [10] = true, [15] = true, [19] = true }
local CASTER_WEAPONS = { MAGE = MAGE_WEAPONS, WARLOCK = MAGE_WEAPONS, PRIEST = { [4] = true, [10] = true, [15] = true, [19] = true } }
local WAND, UNJUDGED = 19, { [14] = true, [20] = true }

function Gear.CanEver(class, classID, subClassID)
	if not (class and classID and subClassID and ARMOR_MAX[class]) then return nil end
	if classID == ARMOR then
		if subClassID >= 1 and subClassID <= 4 then return subClassID <= ARMOR_MAX[class] end
		if ARMOR_ONLY[subClassID] then return ARMOR_ONLY[subClassID][class] == true end
		if subClassID == 0 then return true end
		return nil
	end
	if classID ~= WEAPON or UNJUDGED[subClassID] then return nil end
	local list = CASTER_WEAPONS[class]
	if list then return list[subClassID] == true end
	if subClassID == WAND then return false end
	return nil
end

local function playerClass() return select(2, UnitClass("player")) end

---------------------------------------------------------------------------------------------------------------------
-- The upgrade rule, said once for the player: gear you can wear now, of a kind your class can use and not lighter
-- armor than you wear there, with a higher item level than the piece you wear in that place (the lower of your two
-- rings or trinkets). An empty place takes anything that goes there. One-hand and two-hand weapons both compare
-- with the main hand; shields, off-hands and held items with the off hand.

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function itemLevel(item) return call(C_Item.GetDetailedItemLevelInfo, item) end

-- Results by link (an upgrade's slot or NONE), dropped when the worn gear or the level changes. An item the game
-- hadn't loaded yet gets no entry, so GET_ITEM_INFO_RECEIVED needs nothing dropped: the next poll judges it again.
local upgrades = {}
local NONE = false

local function judge(link)
	local _, _, _, equipLoc, _, classID, subClassID = call(C_Item.GetItemInfoInstant, link)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots or classID ~= ARMOR and classID ~= WEAPON then return NONE end
	if Gear.CanEver(playerClass(), classID, subClassID) == false then return NONE end
	-- Not C_Item.IsUsableItem: that is "has a use effect" (the gamepad bags' Use prompt), false for plain gear.
	-- Not loaded yet (the item or a worn piece): no answer, which is never kept, so a later look tries again.
	local minLevel = select(5, call(C_Item.GetItemInfo, link))
	if secret(minLevel) then return NONE end
	if not minLevel then return nil end
	if minLevel > (call(UnitLevel, "player") or 0) then return NONE end
	local mine = itemLevel(link)
	if secret(mine) then return NONE end
	if not mine then return nil end

	local best, bestLevel, bestKind
	for _, slot in ipairs(slots) do
		local worn = GetInventoryItemLink("player", slot)
		local level = 0
		if worn then level = itemLevel(worn) end
		if secret(level) then return NONE end
		if not level then return nil end
		if not bestLevel or level < bestLevel then
			best, bestLevel = slot, level
			bestKind = worn and select(7, call(C_Item.GetItemInfoInstant, worn))
		end
	end
	local lighter = classID == ARMOR and subClassID >= 1 and subClassID <= 4 and bestKind and bestKind >= 1 and bestKind <= 4 and subClassID < bestKind
	if mine > bestLevel and not lighter then return best end
	return NONE
end

function Gear.Upgrade(link)
	if not link or secret(link) then return end
	if upgrades[link] == nil then upgrades[link] = judge(link) end
	return upgrades[link] or nil
end

local function forget() upgrades = {} end
ns.On("PLAYER_EQUIPMENT_CHANGED", forget)
ns.On("PLAYER_LEVEL_UP", forget)

---------------------------------------------------------------------------------------------------------------------
-- Upgrade arrows: our own small frames with the bags' green arrow, anchored at the top left of the item buttons of
-- the bag windows, the loot window and the loot rolls, shown while that button shows. Read only: the buttons' bag and
-- slot (or loot slot, roll id) and the item's link.

local arrows, used, found, told = {}, 0, 0, nil
local BAG_FRAMES = 13

local function arrowOn(button, link)
	if button and link then found = found + 1 end
	if not (button and link and Gear.Upgrade(link)) then return end
	used = used + 1
	local arrow = arrows[used]
	if not arrow then
		arrow = CreateFrame("Frame", nil, UIParent)
		arrow:SetSize(16, 16)
		local texture = arrow:CreateTexture(nil, "OVERLAY")
		texture:SetAtlas("bags-greenarrow")
		texture:SetAllPoints()
		arrow:Hide()
		arrows[used] = arrow
	end
	-- Place anchors again only when this arrow's button changed.
	Tweaks.Place(arrow, button, "TOPLEFT", "TOPLEFT", 2, -2)
end

local function bagButtons(frame)
	if not (frame and frame:IsVisible() and type(frame.Items) == "table") then return end
	for _, button in ipairs(frame.Items) do
		if button:IsVisible() and button.GetBagID then
			local bag, slot = call(button.GetBagID, button), button:GetID()
			arrowOn(button, bag and call(C_Container.GetContainerItemLink, bag, slot))
		end
	end
end

local function lootButtons()
	local box = LootFrame and LootFrame:IsVisible() and LootFrame.ScrollBox
	for _, frame in ipairs(box and box.GetFrames and call(box.GetFrames, box) or {}) do
		local slot = frame.GetSlotIndex and call(frame.GetSlotIndex, frame)
		arrowOn(frame.Item or frame, slot and call(GetLootSlotLink, slot))
	end
end

local function rollButtons()
	for i = 1, 4 do
		local frame = _G["GroupLootFrame" .. i]
		if frame and frame:IsVisible() and frame.rollID then arrowOn(frame.IconFrame or frame, call(GetLootRollItemLink, frame.rollID)) end
	end
	local box = GamepadGroupLootRollFrame and GamepadGroupLootRollFrame:IsVisible() and GamepadGroupLootRollFrame.ScrollBox
	for _, frame in ipairs(box and box.GetFrames and call(box.GetFrames, box) or {}) do
		if frame.rollID then arrowOn(frame.IconFrame or frame.Icon or frame, call(GetLootRollItemLink, frame.rollID)) end
	end
end

-- Each poll looks again, so a bag opened, scrolled or changed, a new piece worn or an item loaded shows at the next
-- look (POLL seconds). /fct debug logs the count of items seen and marked whenever it changes.
Tweaks.Poll({ "upgradeArrows" }, function(wanted)
	used, found = 0, 0
	if wanted then
		bagButtons(ContainerFrameCombinedBags)
		for i = 1, BAG_FRAMES do bagButtons(_G["ContainerFrame" .. i]) end
		lootButtons()
		rollButtons()
	end
	for i = used + 1, #arrows do arrows[i]:Hide() end
	local now = found .. "/" .. used
	if wanted and now ~= told then ns.debug("arrows: %d items in open windows, %d marked", found, used) end
	told = wanted and now or nil
end)

---------------------------------------------------------------------------------------------------------------------
-- Fast loot: once per loot window the game doesn't auto-loot, every slot not locked to the player is taken with the
-- game's own LootSlot, last first. A bind-on-pickup item still asks with the game's own popup, never answered here.
-- With no free bag slot only coins and currencies are taken, and one line says so.

local looted

local function fastLoot(autoLoot)
	if looted or autoLoot or not on("fastLoot") then return end
	looted = true
	local full, left = (call(C_Container.CalculateTotalNumberOfFreeBagSlots) or 0) <= 0, 0
	for slot = call(GetNumLootItems) or 0, 1, -1 do
		local _, _, _, _, _, locked = call(GetLootSlotInfo, slot)
		if not locked then
			if full and call(GetLootSlotType, slot) == LOOT_ITEM then left = left + 1 else LootSlot(slot) end
		end
	end
	if left > 0 then ns.log(T.BAGS_FULL:format(left, left == 1 and "" or "s")) end
end

ns.On("LOOT_READY", fastLoot)
ns.On("LOOT_OPENED", fastLoot)
ns.On("LOOT_CLOSED", function() looted = nil end)

-- Pass on unusable rolls: armor or a weapon the class can never use; unsure means the player rolls.
ns.On("START_LOOT_ROLL", function(rollID)
	if not on("passUnusable") then return end
	local link = call(GetLootRollItemLink, rollID)
	if not link or secret(link) then return end
	local _, _, _, _, _, classID, subClassID = call(C_Item.GetItemInfoInstant, link)
	if Gear.CanEver(playerClass(), classID, subClassID) ~= false then return end

	RollOnLoot(rollID, PASS)
	ns.log(T.PASSED:format(link))
end)

---------------------------------------------------------------------------------------------------------------------
-- Wear quest rewards: the quest's reward items are read on QUEST_COMPLETE; after the turn-in, the first of them that
-- lands in the bags and is an upgrade gets a card for 10 seconds: hold Y a second, out of combat, and it is worn in
-- the place it was compared with. A frame of ours sees the pad presses while the card shows and passes every one on,
-- so a tap of Y still does what Y does.

local WEAR_FOR, WEAR_WAIT, HOLD_MIN, HOLD_MAX = 10, 30, 1, 3
local rewards, waiting, card, listener

local function wearKey() return ns.UI and ns.UI.KEY and ns.UI.KEY.FT or "PAD4" end

local function hideCard()
	if card then card:Hide() end
	if listener then listener:Hide() end
end

local function wear()
	local offer = card and card:IsShown() and card.offer
	hideCard()
	if not offer or InCombatLockdown() then return end
	C_Item.EquipItemByName(offer.link, offer.slot)
end

local function buildCard()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetSize(320, 64)
	card:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
	card:SetFrameStrata("HIGH")
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then NineSliceUtil.ApplyLayoutByName(card, "TooltipDefaultLayout") end
	local color = TOOLTIP_DEFAULT_BACKGROUND_COLOR
	if card.Center and color and color.GetRGB then card.Center:SetVertexColor(color:GetRGB()) end
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(40, 40)
	card.icon:SetPoint("LEFT", 12, 0)
	card.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
	card.name:SetPoint("RIGHT", -12, 0)
	card.name:SetJustifyH("LEFT")
	card.hint = card:CreateFontString(nil, "ARTWORK", "GameFontGreen")
	card.hint:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 2)
	card:Hide()

	listener = CreateFrame("Frame", nil, UIParent)
	listener:EnableGamePadButton(true)
	listener:SetPropagateKeyboardInput(true)
	listener:SetScript("OnGamePadButtonDown", function(self, key) if key == wearKey() then self.down = GetTime() end end)
	listener:SetScript("OnGamePadButtonUp", function(self, key)
		local down = key == wearKey() and self.down
		self.down = nil
		if down and GetTime() - down >= HOLD_MIN and GetTime() - down <= HOLD_MAX then wear() end
	end)
	listener:Hide()
end

local function offer(link, slot)
	if InCombatLockdown() then return end
	if not card then buildCard() end
	card.offer = { link = link, slot = slot }
	card.icon:SetTexture(select(5, call(C_Item.GetItemInfoInstant, link)))
	card.name:SetText(link)
	card.hint:SetText(T.WEAR:format(ns.UI and ns.UI.ButtonText("FT", 16) or "Y"))
	card:Show()
	listener.down = nil
	listener:Show()
	C_Timer.After(WEAR_FOR, function() if card.offer and card.offer.link == link then hideCard() end end)
end

ns.On("QUEST_COMPLETE", function()
	rewards = {}
	for _, kind in ipairs({ "choice", "reward" }) do
		local count = kind == "choice" and call(GetNumQuestChoices) or call(GetNumQuestRewards) or 0
		for i = 1, count or 0 do
			local link = call(GetQuestItemLink, kind, i)
			local id = link and not secret(link) and call(C_Item.GetItemInfoInstant, link)
			if id then rewards[id] = true end
		end
	end
end)

ns.On("QUEST_TURNED_IN", function()
	if rewards and next(rewards) and on("wearRewards") then waiting = { items = rewards, untilAt = GetTime() + WEAR_WAIT } end
	rewards = nil
end)

ns.On("BAG_UPDATE_DELAYED", function()
	if not waiting or InCombatLockdown() then return end
	if GetTime() > waiting.untilAt then waiting = nil return end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, call(C_Container.GetContainerNumSlots, bag) or 0 do
			local info = call(C_Container.GetContainerItemInfo, bag, slot)
			local link = info and waiting.items[info.itemID] and call(C_Container.GetContainerItemLink, bag, slot)
			local place = link and Gear.Upgrade(link)
			if place then
				waiting = nil
				return offer(link, place)
			end
		end
	end
end)

ns.On("PLAYER_REGEN_DISABLED", hideCard)

---------------------------------------------------------------------------------------------------------------------
-- Picker actions: our own secure buttons, clicked by the action's /click. Their macro text is written out of combat
-- only, and only when it changes; the text itself refuses a fight ([nocombat]).

-- The picker's /click sends the release only, so the button acts on the release whatever ActionButtonUseKeyDown says.
local function secureButton(globalName)
	local button = CreateFrame("Button", globalName, UIParent, "SecureActionButtonTemplate")
	button:SetAttribute("type", "macro")
	button:SetAttribute("useOnKeyDown", false)
	button:RegisterForClicks("AnyUp", "AnyDown")
	return button
end

local function setText(button, text)
	if InCombatLockdown() or button.text == text then return end
	button.text = text
	button:SetAttribute("macrotext", text)
end
Gear.SecureButton, Gear.SetText = secureButton, setText

-- Eat & drink: the best food, and the best drink when the character uses mana: the highest required level the
-- character meets, then the higher item level. Food or drink by the item's spell ("Food", "Drink", "Refreshment").
-- ponytail: the spell names are the English client's; on another language nothing is found and the press says so.
local eat = secureButton("ForeverControllerTweaksEatDrink")
Gear.eat = eat

-- The best bag item of each kind: kinds = { kind = fits(item) }, item = { id, classID, subClassID, name, spell }. Best
-- is the highest required level the character meets, then the higher item level. One pass serves every kind
-- (Gear.KINDS: food and drink here, potions and grenades in TweaksActions.lua). An item the game hasn't loaded yet
-- (no name at login) can't be told apart: it is asked for, and its arrival marks the bags dirty again.
local loading = {}

function Gear.Best(kinds)
	local best, level = {}, call(UnitLevel, "player") or 0
	loading = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, call(C_Container.GetContainerNumSlots, bag) or 0 do
			local info = call(C_Container.GetContainerItemInfo, bag, slot)
			local id = info and info.itemID
			local _, _, _, _, _, classID, subClassID = call(C_Item.GetItemInfoInstant, id)
			local name, _, _, ilvl, minLevel = call(C_Item.GetItemInfo, id)
			local spell = classID and call(C_Item.GetItemSpell, id)
			if id and not secret(name) and name == nil then
				loading[id] = true
				call(C_Item.RequestLoadItemDataByID, id)
			end
			local item = { id = id, classID = classID, subClassID = subClassID, name = not secret(name) and type(name) == "string" and name or "", spell = not secret(spell) and type(spell) == "string" and spell or "" }
			minLevel, ilvl = minLevel or 0, ilvl or 0
			for kind, fits in pairs(kinds) do
				local held = best[kind]
				if id and fits(item) and minLevel <= level and (not held or minLevel > held.min or minLevel == held.min and ilvl > held.ilvl) then
					best[kind] = { id = id, min = minLevel, ilvl = ilvl }
				end
			end
		end
	end
	return best
end

local function foodOf(words)
	return function(item)
		return item.classID == CONSUMABLE and item.subClassID == FOOD_DRINK and (item.spell:find(words[1]) or item.spell:find(words[2])) ~= nil
	end
end
Gear.KINDS = { food = foodOf({ "Food", "Refreshment" }), drink = foodOf({ "Drink", "Refreshment" }) }

local function usesMana()
	local kind = call(UnitPowerType, "player")
	return not secret(kind) and kind == MANA or playerClass() == "DRUID"
end

function Gear.RefreshEat(best)
	local lines = {}
	if best.food then lines[#lines + 1] = "/use [nocombat] item:" .. best.food.id end
	if best.drink and usesMana() and not (best.food and best.food.id == best.drink.id) then lines[#lines + 1] = "/use [nocombat] item:" .. best.drink.id end
	setText(eat, table.concat(lines, "\n"))
end

eat:SetScript("PreClick", function(self) if self.text == "" and not InCombatLockdown() then ns.log(T.NO_FOOD) end end)

-- Quest item: the super-tracked quest's item, else the nearest quest's that has one.
local questItem = secureButton("ForeverControllerTweaksQuestItem")
Gear.questItem = questItem

local function itemOf(logIndex)
	local link = logIndex and call(GetQuestLogSpecialItemInfo, logIndex)
	return type(link) == "string" and not secret(link) and link:match("item:(%d+)")
end

local function questItemID()
	local Q = C_QuestLog
	if not Q then return end
	local tracked = C_SuperTrack and call(C_SuperTrack.GetSuperTrackedQuestID)
	local id = tracked and itemOf(call(Q.GetLogIndexForQuestID, tracked))
	if id then return id end

	local best, bestDistance
	for i = 1, call(Q.GetNumQuestLogEntries) or 0 do
		local info = call(Q.GetInfo, i)
		local item = info and not info.isHeader and itemOf(i)
		if item then
			local distance = call(Q.GetDistanceSqToQuest, info.questID) or math.huge
			if not bestDistance or distance < bestDistance then best, bestDistance = item, distance end
		end
	end
	return best
end

function Gear.RefreshQuestItem()
	local id = questItemID()
	setText(questItem, id and "/use item:" .. id or "")
end

questItem:SetScript("PreClick", function(self) if self.text == "" and not InCombatLockdown() then ns.log(T.NO_QUEST_ITEM) end end)

-- The macro texts are written out of combat only, so nothing is scanned in combat either: a change there marks its
-- part dirty, and the leaving of combat runs it. Out of combat a burst of events runs once, on the next frame.
--   Gear.Dirty("bags")   one Gear.Best pass over Gear.KINDS, then every Gear.ON_BEST(best) (Eat & drink, potions).
--   Gear.Dirty("quest")  the quest item.
Gear.ON_BEST = { function(best) Gear.RefreshEat(best) end }

local dirty, queued = {}, false

function Gear.Flush()
	queued = false
	if InCombatLockdown() then return end
	if dirty.bags then
		dirty.bags = nil
		local best = Gear.Best(Gear.KINDS)
		for _, fn in ipairs(Gear.ON_BEST) do fn(best) end
	end
	if dirty.quest then
		dirty.quest = nil
		Gear.RefreshQuestItem()
	end
end

function Gear.Dirty(part)
	dirty[part] = true
	if queued or InCombatLockdown() then return end
	queued = true
	C_Timer.After(0, Gear.Flush)
end

local function bagsDirty() Gear.Dirty("bags") end
-- The first arrival clears the list: the rescan asks again for any still missing, so a burst rescans once.
ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
	if ok == false or not loading[id] then return end
	loading = {}
	bagsDirty()
end)
local function questDirty() Gear.Dirty("quest") end
ns.On("PLAYER_REGEN_ENABLED", Gear.Flush)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do ns.On(event, bagsDirty) end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED", "QUEST_WATCH_LIST_CHANGED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do ns.On(event, questDirty) end

