-- Forever Controller Tweaks action catalog: everything a crossbar cell can hold, and how it lands there.
-- Entries: { id, category, name, icon, kind, payload [, ranks, highest, note] }.
--   spell/pet/item/toy/mount/macro/set: picked up with the native Pickup* call and placed with PlaceAction(slot),
--   so they show natively on Blizzard's crossbar.
--   spellgroup: a spell with several ranks. Its ranks[1] (highest = true) always casts the highest known rank: on a
--   slot the addon re-places the new top rank after SPELLS_CHANGED; on a routed cell the text names it. ranks[2..]
--   are plain spell entries per rank, highest first.
--   game: a game command, as an addon macro "FCT:<short>" whose text uses secure commands only (/click of the
--   game's own buttons for windows, never /run). The addon only ever deletes macros it made (the registry below),
--   and only once no character uses them.
--   face: Jump and Interact need press and release, which a macro can't send: routed cells only (Face.Routable).
-- On a routed cell (Face.lua) an entry sits in a shadow slot on the hidden keyboard bars 6-8 (Actions.Shadow) and
-- fires natively; macro text (TextFor) is the fallback while no shadow slot can be placed.
-- All writes (PlaceAction, CreateMacro, DeleteMacro) happen out of combat only.
local _, ns = ...
local Actions = {}
ns.Actions = Actions

local ICONS = "Interface\\Icons\\"
local QUESTION = ICONS .. "INV_Misc_QuestionMark"
local MACRO_PREFIX = "FCT:"
local MACRO_CONSTS = Constants and Constants.MacroConsts or {}
local MAX_ACCOUNT, MAX_CHARACTER = MACRO_CONSTS.MAX_ACCOUNT_MACROS or 120, MACRO_CONSTS.MAX_CHARACTER_MACROS or 30
-- Gamepad storage: the standard pages' bindable slots (4 bars of 8, less the 4 reserved top-bar slots), then the
-- stance bars. Shared with Face.lua.
local GAMEPAD = Constants and Constants.GamepadActionBarConstants or {}
Actions.PER_BAR = GAMEPAD.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
Actions.STANDARD_PAGES = GAMEPAD.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 3
local PER_PAGE = (GAMEPAD.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE or 32) - (GAMEPAD.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 4)
local STORAGE_SLOTS = Actions.STANDARD_PAGES * PER_PAGE + (GAMEPAD.NUM_GAMEPAD_STANCE_ACTION_BARS or 5) * Actions.PER_BAR
-- Shadow slots: keyboard bars 6-8 (MultiBar5-7), which the Gamepad UI never shows. Searched from the top down.
local SHADOW_FIRST, SHADOW_LAST = 145, 180
local RANDOM_MOUNT = "random"
-- GetActionInfo's id for "Summon random favorite mount", and the spell a macro casts for it.
local RANDOM_MOUNT_ACTION, RANDOM_MOUNT_SPELL = 268435455, 150544

Actions.CATEGORIES = { "Spells", "Items", "Mounts", "Macros", "Movement", "Targeting", "Combat", "Windows", "Misc", "AddOns", "Rings" }

-- Open chat: no macro command opens the chat box and restricted code can't run the OPENCHAT binding, so the entry
-- clicks this plain button. Opening chat isn't protected; the box opens on its current chat type, as Enter does.
local openChat = CreateFrame("Button", "ForeverControllerTweaksOpenChat", UIParent)
openChat:SetScript("OnClick", function()
	local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
	if open then open("") end
end)

-- Game commands. short = macro name after "FCT:" (macro names hold 16 characters). button = a Blizzard button
-- whose existence is checked at build time. press = when the button acts: "up" (default, plain buttons) or "both"
-- (action buttons act on down or up per the ActionButtonUseKeyDown CVar, so both clicks are sent; one acts).
local GAME = {
	{ "Movement", "jump", "Jump", "Ability_Rogue_Sprint", face = "jump" },
	{ "Movement", "sit", "Sit", "Spell_Nature_Sleep", text = "/sit", short = "Sit" },
	{ "Movement", "stand", "Stand", "Ability_Warrior_Charge", text = "/stand", short = "Stand" },

	{ "Targeting", "targetenemy", "Target nearest enemy", "Ability_Hunter_SniperShot", text = "/targetenemy", short = "Enemy" },
	{ "Targeting", "targetfriend", "Target nearest friend", "Spell_Holy_FlashHeal", text = "/targetfriend", short = "Friend" },
	{ "Targeting", "targetself", "Target yourself", "Spell_Holy_InnerFire", text = "/target player", short = "Self" },
	{ "Targeting", "party1", "Target party member 1", "Spell_Holy_PrayerOfHealing02", text = "/target party1", short = "Party1" },
	{ "Targeting", "party2", "Target party member 2", "Spell_Holy_PrayerOfHealing02", text = "/target party2", short = "Party2" },
	{ "Targeting", "party3", "Target party member 3", "Spell_Holy_PrayerOfHealing02", text = "/target party3", short = "Party3" },
	{ "Targeting", "party4", "Target party member 4", "Spell_Holy_PrayerOfHealing02", text = "/target party4", short = "Party4" },
	{ "Targeting", "focus", "Set focus", "Ability_Hunter_SniperShot", text = "/focus", short = "Focus" },
	{ "Targeting", "targetfocus", "Target focus", "Ability_Hunter_SniperShot", text = "/target focus", short = "TargetFocus" },
	{ "Targeting", "assist", "Assist target", "Ability_Warrior_BattleShout", text = "/assist", short = "Assist" },
	{ "Targeting", "cleartarget", "Clear target", "Spell_ChargeNegative", text = "/cleartarget", short = "ClearTarget" },
	{ "Targeting", "interact", "Interact", "Ability_Hunter_Pathfinding", face = "interact" },
	{ "Targeting", "inspect", "Inspect", "INV_Misc_Spyglass_02", face = "inspect" },
	{ "Targeting", "ping", "Ping", "Ability_Hunter_Pathfinding", text = "/ping", short = "Ping" },

	{ "Combat", "startattack", "Start attack", "Ability_SteelMelee", text = "/startattack", short = "Attack" },
	{ "Combat", "stopattack", "Stop attack", "Spell_ChargeNegative", text = "/stopattack", short = "StopAttack" },
	{ "Combat", "stopcasting", "Stop casting", "Spell_Frost_Stun", text = "/stopcasting", short = "StopCast" },
	{ "Combat", "back", "Back (stop, clear)", "Spell_ChargeNegative", face = "back" },
	{ "Combat", "petattack", "Pet attack", "Ability_GhoulFrenzy", text = "/petattack", short = "PetAttack" },
	{ "Combat", "petfollow", "Pet follow", "Ability_Tracking", text = "/petfollow", short = "PetFollow" },
	{ "Combat", "petstay", "Pet stay", "Spell_Nature_TimeStop", text = "/petstay", short = "PetStay" },
	{ "Combat", "petpassive", "Pet passive", "Ability_Seal", text = "/petpassive", short = "PetPassive" },
	{ "Combat", "petdefensive", "Pet defensive", "Ability_Defend", text = "/petdefensive", short = "PetDefend" },
	{ "Combat", "petaggressive", "Pet aggressive", "Ability_Racial_BloodRage", text = "/petaggressive", short = "PetAggro" },
	{ "Combat", "petassist", "Pet assist", "Ability_Hunter_Pet_Assist", text = "/petassist", short = "PetAssist" },
	{ "Combat", "extraaction", "Extra action button", "Spell_Nature_WispSplode", button = "ExtraActionButton1", press = "both", short = "ExtraAction" },

	{ "Windows", "bags", "Backpack", "INV_Misc_Bag_08", button = "MainMenuBarBackpackButton", short = "Bags" },
	{ "Windows", "character", "Character", "INV_Chest_Cloth_17", button = "CharacterMicroButton", short = "Character" },
	{ "Windows", "spellbook", "Spellbook", "INV_Misc_Book_09", button = "SpellbookMicroButton", short = "Spellbook" },
	{ "Windows", "talents", "Talents", "Ability_Marksmanship", button = "TalentMicroButton", short = "Talents" },
	{ "Windows", "professions", "Professions", "Trade_Engineering", button = "ProfessionMicroButton", short = "Professions" },
	{ "Windows", "questlog", "Map & Quest Log", "INV_Misc_Map_01", button = "QuestLogMicroButton", short = "QuestLog" },
	{ "Windows", "groupfinder", "Group finder", "INV_Misc_GroupNeedMore", button = "LFDMicroButton", short = "GroupFinder" },
	{ "Windows", "collections", "Collections", "Ability_Mount_RidingHorse", button = "CollectionsMicroButton", short = "Collections" },
	{ "Windows", "guild", "Guild & Communities", "INV_Shirt_GuildTabard_01", button = "GuildMicroButton", short = "Guild" },
	{ "Windows", "journal", "Adventure guide", "INV_Misc_Book_11", button = "EJMicroButton", short = "Journal" },
	{ "Windows", "calendar", "Calendar", "INV_Misc_Note_01", button = "GameTimeFrame", short = "Calendar" },
	{ "Windows", "shop", "Shop", "INV_Misc_Coin_01", button = "StoreMicroButton", short = "Shop" },
	{ "Windows", "gamemenu", "Game menu", "INV_Misc_Gear_01", button = "MainMenuMicroButton", short = "GameMenu" },
	{ "Windows", "chat", "Open chat", "INV_Letter_15", button = "ForeverControllerTweaksOpenChat", short = "Chat" },

	{ "Misc", "dismount", "Dismount", "Ability_Mount_RidingHorse", text = "/dismount", short = "Dismount" },
	{ "Misc", "leavevehicle", "Leave vehicle", "Spell_ChargeNegative", text = "/leavevehicle", short = "LeaveVehicle" },
	{ "Misc", "wave", "Wave", "Spell_Holy_Heal", text = "/wave", short = "Wave" },
	{ "Misc", "thank", "Thank", "Spell_Holy_Heal", text = "/thank", short = "Thank" },
	{ "Misc", "cheer", "Cheer", "Spell_Holy_Heal", text = "/cheer", short = "Cheer" },
	{ "Misc", "dance", "Dance", "Spell_Holy_Heal", text = "/dance", short = "Dance" },
	{ "Misc", "bow", "Bow", "Spell_Holy_Heal", text = "/bow", short = "Bow" },
	{ "Misc", "hello", "Hello", "Spell_Holy_Heal", text = "/hello", short = "Hello" },
}
for i = 0, 8 do
	local name = i == 0 and "Clear raid marker" or ("Raid marker " .. i)
	GAME[#GAME + 1] = { "Targeting", "marker" .. i, name, "INV_Misc_Gem_Variety_01", text = "/tm " .. i, short = i == 0 and "MarkClear" or ("Mark" .. i) }
end
local GAME_BY_KEY = {}
for _, spec in ipairs(GAME) do GAME_BY_KEY[spec[2]] = spec end
local CLICK = { up = "/click %s", down = "/click %s LeftButton 1", both = ns.Face.CLICK_BOTH }

-- Shared with Face.lua and Touch.lua, which read them at run time (Face.lua loads first). Kinds an action slot can
-- hold (Assign, Shadow); anything else needs the router.
Actions.SLOT_KINDS = { spell = true, spellgroup = true, pet = true, item = true, toy = true, mount = true, macro = true, set = true, game = true }
-- Catalog events that change an entry's macro text: spell names and ranks, macro bodies, set, toy and mount names.
Actions.TEXT_EVENTS = { SPELLS_CHANGED = true, UPDATE_MACROS = true, EQUIPMENT_SETS_CHANGED = true, NEW_TOY_ADDED = true, NEW_MOUNT_ADDED = true }
function Actions.KindOf(entry) return entry.kind or tostring(entry.id):match("^(%a+):") end

local function call(fn, ...)
	if not fn then return end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h, i, j, k, l end
end

local function gameText(spec)
	if spec.text then return spec.text end
	local name = spec.button and _G[spec.button] and spec.button
	return name and CLICK[spec.press or "up"]:format(name, name)
end

-- Back and Inspect were PS: game macros before they became face actions. A macro sends press and release in the same
-- instant, so a held Jump or hold-to-loot Interact can't work that way; the router sends them as they happen.
-- Face.lua moves old placements to routed cells.
Actions.LEGACY_FACE = { ["game:back"] = "face:back", ["game:inspect"] = "face:inspect" }

local function gameEntries(add)
	for _, spec in ipairs(GAME) do
		local category, key, name, icon = spec[1], spec[2], spec[3], ICONS .. spec[4]
		if spec.face then
			add({ id = "face:" .. spec.face, category = category, name = name, icon = icon, kind = "face", payload = spec.face })
		else
			local text = gameText(spec)
			-- CreateMacro takes the icon as a bare icon name.
			if text then add({ id = "game:" .. key, category = category, name = name, icon = icon, kind = "game", payload = { text = text, icon = spec[4], macro = (MACRO_PREFIX .. spec.short):sub(1, 16) } }) end
		end
	end
end

-- Highest rank first: by the number in the rank text, else the one the spellbook doesn't call a lower rank, else the
-- higher spell id.
local function byRank(a, b)
	if a.number and b.number and a.number ~= b.number then return a.number > b.number end
	if a.low ~= b.low then return not a.low end
	return a.id > b.id
end

-- The player's castable spellbook spells: byName[name] = ranks (highest first), byID[spellID] = rank, names in book
-- order. A rank is { id, name, sub, number, low, icon, ranked }. The spellbook lists every rank (ShowAllSpellRanks
-- only filters Blizzard's spellbook frame). Cached with the catalog.
local book
local function spellbook()
	if book then return book end

	book = { byName = {}, byID = {}, names = {} }
	local api = C_SpellBook
	if not (api and api.GetNumSpellBookSkillLines) then return book end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	for line = 1, call(api.GetNumSpellBookSkillLines) or 0 do
		local info = call(api.GetSpellBookSkillLineInfo, line)
		if info and not info.shouldHide then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = call(api.GetSpellBookItemInfo, slot, bank)
				local spellID = item and item.spellID
				local future = item and Enum.SpellBookItemType and item.itemType == Enum.SpellBookItemType.FutureSpell
				local name = spellID and (item.name or call(C_Spell.GetSpellName, spellID))
				if name and not future and not item.isPassive and not call(api.IsSpellBookItemPassive, slot, bank) and not book.byID[spellID] then
					local sub = item.subName or call(C_Spell.GetSpellSubtext, spellID) or ""
					local rank = { id = spellID, name = name, sub = sub, number = tonumber(sub:match("(%d+)")), low = not not call(api.IsSpellBookItemLowRank, slot, bank), icon = item.iconID or call(C_Spell.GetSpellTexture, spellID) or QUESTION }
					local list = book.byName[name]
					if not list then
						list = {}
						book.byName[name] = list
						book.names[#book.names + 1] = name
					end
					list[#list + 1] = rank
					book.byID[spellID] = rank
				end
			end
		end
	end
	for _, list in pairs(book.byName) do
		table.sort(list, byRank)
		for _, rank in ipairs(list) do rank.ranked = #list > 1 end
	end
	return book
end

-- "Holy Light(Rank 3)" is the macro form Blizzard's spellbook inserts for a ranked spell (Blizzard_SpellBookItem.lua
-- OnModifiedIconClick); a single-rank spell is cast by name.
local function castText(rank)
	if rank.ranked and rank.sub ~= "" then return "/cast " .. rank.name .. "(" .. rank.sub .. ")" end
	return "/cast " .. rank.name
end

local function rankLabel(rank, i, count)
	return string.format("%s (%s)", rank.name, rank.sub ~= "" and rank.sub or ("Rank " .. (count - i + 1)))
end

local function spellEntries(add)
	local spells = spellbook()
	for _, name in ipairs(spells.names) do
		local list = spells.byName[name]
		local top = list[1]
		if #list == 1 then
			add({ id = "spell:" .. top.id, category = "Spells", name = name, icon = top.icon, kind = "spell", payload = top.id })
		else
			local id = "spellgroup:" .. name
			local ranks = { { id = id, category = "Spells", name = name .. " (Highest Rank)", icon = top.icon, kind = "spellgroup", payload = name, highest = true } }
			for i, rank in ipairs(list) do
				ranks[i + 1] = { id = "spell:" .. rank.id, category = "Spells", name = rankLabel(rank, i, #list), icon = rank.icon, kind = "spell", payload = rank.id }
			end
			add({ id = id, category = "Spells", name = name, icon = top.icon, kind = "spellgroup", payload = name, ranks = ranks })
		end
	end

	local api = C_SpellBook
	if not (api and api.GetNumSpellBookSkillLines) then return end
	local petBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
	for slot = 1, petBank and tonumber(call(api.HasPetSpells)) or 0 do
		local item = call(api.GetSpellBookItemInfo, slot, petBank)
		if item and item.spellID and not call(api.IsSpellBookItemPassive, slot, petBank) then
			local name = item.name or call(C_Spell.GetSpellName, item.spellID)
			if name then add({ id = "pet:" .. item.spellID, category = "Spells", name = name .. " (pet)", icon = item.iconID or QUESTION, kind = "pet", payload = { slot = slot, spellID = item.spellID } }) end
		end
	end
end

local function isToy(itemID)
	return not not (C_ToyBox and call(C_ToyBox.GetToyInfo, itemID) and PlayerHasToy and call(PlayerHasToy, itemID))
end

local function itemEntries(add)
	local seen = {}
	local function addItem(itemID, name, icon)
		if not itemID or seen[itemID] or not call(C_Item.GetItemSpell, itemID) then return end
		seen[itemID] = true
		name = name or call(C_Item.GetItemNameByID, itemID) or call(C_Item.GetItemInfo, itemID)
		if name then add({ id = "item:" .. itemID, category = "Items", name = name, icon = icon or QUESTION, kind = "item", payload = itemID }) end
	end

	-- Equipped trinkets and other items with a use effect.
	for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
		addItem(call(GetInventoryItemID, "player", slot), nil, call(GetInventoryItemTexture, "player", slot))
	end

	local container = C_Container
	if container and container.GetContainerNumSlots then
		local first = Enum.BagIndex and Enum.BagIndex.Backpack or 0
		for bag = first, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
			for slot = 1, call(container.GetContainerNumSlots, bag) or 0 do
				local info = call(container.GetContainerItemInfo, bag, slot)
				if info then addItem(info.itemID, info.itemName, info.iconFileID) end
			end
		end
	end

	-- ponytail: toys come from the Toy Box's filtered list; there is no unfiltered toy API, and changing the
	-- player's Toy Box filters would be a write to Blizzard state. A toy hidden by a filter is missing until unfiltered.
	local toys = C_ToyBox
	if toys and toys.GetNumFilteredToys then
		for i = 1, call(toys.GetNumFilteredToys) or 0 do
			local itemID = call(toys.GetToyFromIndex, i)
			local _, name, icon = call(toys.GetToyInfo, itemID)
			if itemID and name and (not PlayerHasToy or call(PlayerHasToy, itemID)) then
				add({ id = "toy:" .. itemID, category = "Items", name = name .. " (toy)", icon = icon or QUESTION, kind = "toy", payload = itemID })
			end
		end
	end

	local sets = C_EquipmentSet
	for _, setID in ipairs(sets and call(sets.GetEquipmentSetIDs) or {}) do
		local name, icon = call(sets.GetEquipmentSetInfo, setID)
		if name then add({ id = "set:" .. setID, category = "Items", name = name .. " (equipment set)", icon = icon or QUESTION, kind = "set", payload = setID }) end
	end
end

-- Every collected mount by id, so the Mount Journal's filters and search don't hide any.
local function mountEntries(add)
	local journal = C_MountJournal
	if not (journal and journal.GetMountIDs) then return end
	add({ id = "mount:" .. RANDOM_MOUNT, category = "Mounts", name = "Random favorite mount", icon = ICONS .. "Ability_Mount_RidingHorse", kind = "mount", payload = RANDOM_MOUNT })
	for _, mountID in ipairs(call(journal.GetMountIDs) or {}) do
		local name, spellID, icon, _, _, _, _, _, _, hidden, isCollected = call(journal.GetMountInfoByID, mountID)
		if name and isCollected and not hidden then add({ id = "mount:" .. mountID, category = "Mounts", name = name, icon = icon or QUESTION, kind = "mount", payload = { mountID = mountID, spellID = spellID } }) end
	end
end

-- Macro registry. db.macros[name] = { id = <catalog id>, chars = { ["Name-Realm"] = true } }: the account macros
-- The addon made and the characters that have one on their bars. db.chars[...].macros[name] = { id }: character
-- macros it made once the account slots were full. Anything else, even a macro named "FCT:...", is the player's.
local function registries()
	local char, me = ns.Face.CharDB()
	ns.db.macros = ns.db.macros or {}
	char = char or {}
	char.macros = char.macros or {}
	return ns.db.macros, char.macros, me or "?"
end

local function ours(name)
	local account, character = registries()
	return account[name] or character[name]
end

local function findMacro(name, perChar)
	local account, character = call(GetNumMacros)
	local first, last = 1, account or 0
	if perChar then first, last = MAX_ACCOUNT + 1, MAX_ACCOUNT + (character or 0) end
	for i = first, last do
		if call(GetMacroInfo, i) == name then return i end
	end
end

local function macroIndex(name) return findMacro(name) or findMacro(name, true) end

local function macroEntries(add)
	local account, character = call(GetNumMacros)
	local indexes = {}
	for i = 1, account or 0 do indexes[#indexes + 1] = i end
	for i = MAX_ACCOUNT + 1, MAX_ACCOUNT + (character or 0) do indexes[#indexes + 1] = i end
	for _, index in ipairs(indexes) do
		local name, icon = call(GetMacroInfo, index)
		if name and not ours(name) then add({ id = "macro:" .. name, category = "Macros", name = name, icon = icon or QUESTION, kind = "macro", payload = name }) end
	end
end

-- AddOns: every key binding an addon declares. Blizzard has no "is an addon binding" API; its own Bindings.xml files
-- use only these categories, and an addon's BINDING_HEADER_/BINDING_NAME_ globals are tainted by that addon
-- (issecurevariable), which also names it.
local BLIZZARD_BINDING_CATEGORIES = {}
for _, category in ipairs({ "BINDING_HEADER_MOVEMENT", "BINDING_HEADER_INTERFACE", "BINDING_HEADER_ACTIONBAR", "BINDING_HEADER_ACTIONBAR2",
	"BINDING_HEADER_ACTIONBAR3", "BINDING_HEADER_ACTIONBAR4", "BINDING_HEADER_ACTIONBAR5", "BINDING_HEADER_ACTIONBAR6", "BINDING_HEADER_ACTIONBAR7",
	"BINDING_HEADER_ACTIONBAR8", "BINDING_HEADER_MULTIACTIONBAR", "BINDING_HEADER_CHAT", "BINDING_HEADER_TARGETING", "BINDING_HEADER_RAID_TARGET",
	"BINDING_HEADER_VEHICLE", "BINDING_HEADER_CAMERA", "BINDING_HEADER_PING_SYSTEM", "BINDING_HEADER_HOUSING_SYSTEM", "BINDING_HEADER_MISC",
	"BINDING_HEADER_OTHER", "BINDING_HEADER_DEBUG", "BINDING_HEADER_COMMENTATOR", "WOWLABS_BINDING_HEADER", "GAMEPAD_LABEL", "Gamepad Action Buttons", "PTR" }) do
	BLIZZARD_BINDING_CATEGORIES[category] = true
end
-- The addon's own toggle binding is left out by its globals' taint (Core.lua sets them).
local ADDON_ICON, ADDON_MACRO_ICON, OWN_ADDON = ICONS .. "INV_Misc_Gear_08", "INV_Misc_Gear_08", "ForeverControllerTweaks"

-- The addon that set a global, nil for a secure (Blizzard) one or a missing one.
local function setBy(name)
	if not (issecurevariable and name) then return nil end
	local ok, secure, addon = pcall(issecurevariable, name)
	if not ok or secure then return nil end
	return addon or "?"
end

local function addonIcon(addon)
	local icon = addon ~= "?" and C_AddOns and call(C_AddOns.GetAddOnMetadata, addon, "IconTexture")
	return icon and icon ~= "" and icon or ADDON_ICON
end

-- A CLICK binding is a secure /click; a key sends its press and release, so the macro sends both (the target's own
-- click registration decides which one acts). Any other binding runs Lua, which a macro can't without /run: listed,
-- but not assignable.
local function bindingEntries(add)
	for i = 1, GetNumBindings and call(GetNumBindings) or 0 do
		local command, category = call(GetBinding, i)
		if type(command) == "string" and not command:find("^HEADER") and not command:find("^PREFACE") then
			local nameKey = "BINDING_NAME_" .. command
			local header = type(category) == "string" and category or nil
			local addon = setBy(nameKey) or setBy(header)
			local blizzard = not addon and (not header or BLIZZARD_BINDING_CATEGORIES[header] or _G[header] ~= nil)
			if not blizzard and addon ~= OWN_ADDON then
				local button, mouseButton = command:match("^CLICK ([^:]+):(.+)$")
				local title = header and (type(_G[header]) == "string" and _G[header] or header) or "AddOns"
				local name = type(_G[nameKey]) == "string" and _G[nameKey] or button or command
				local entry = { id = "addon:" .. command, category = "AddOns", name = title .. ": " .. name, icon = addon and addonIcon(addon) or ADDON_ICON }
				if button then
					entry.kind = "game"
					local text = ("/click %s %s 1\n/click %s %s"):format(button, mouseButton, button, mouseButton)
					entry.payload = { text = text, icon = ADDON_MACRO_ICON, macro = (MACRO_PREFIX .. button):sub(1, 16) }
				else
					entry.kind, entry.payload, entry.disabled, entry.note = "binding", command, true, "needs a key binding"
				end
				add(entry)
			end
		end
	end
end

local function byName(a, b)
	if a.name ~= b.name then return a.name < b.name end
	return a.id < b.id
end

local function build()
	local byCategory = {}
	local function add(entry)
		local list = byCategory[entry.category] or {}
		byCategory[entry.category] = list
		list[#list + 1] = entry
	end
	spellEntries(add)
	itemEntries(add)
	mountEntries(add)
	macroEntries(add)
	bindingEntries(add)
	gameEntries(add)
	-- Rings.lua: "Open ring: <name>", one per ring the player made.
	for _, entry in ipairs(ns.Rings and ns.Rings.Entries() or {}) do add(entry) end

	local categories = {}
	for _, name in ipairs(Actions.CATEGORIES) do
		local list = byCategory[name]
		if list and #list > 0 then
			table.sort(list, byName)
			categories[#categories + 1] = { name = name, entries = list }
		end
	end
	return categories
end

-- The categories with entries, in CATEGORIES order, entries sorted by name; one catalog for every cell (the argument
-- is ignored: any action goes on any cell). Cached until spells, bags, equipment, mounts, toys or macros change;
-- callers must not modify it.
local cache
function Actions.Catalog()
	cache = cache or build()
	return cache
end

-- The catalog entry with this id (a spell group's ranks included), or nil.
function Actions.Find(id)
	for _, category in ipairs(Actions.Catalog()) do
		for _, entry in ipairs(category.entries) do
			if entry.id == id then return entry end
			for _, rank in ipairs(entry.ranks or {}) do
				if rank.id == id then return rank end
			end
		end
	end
end

-- Macro names on this character's gamepad storage and shadow slots, or nil when the range can't be read (then nothing is deleted).
local function usedMacros()
	local first = C_GamepadUI and call(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
	if not first then return nil end

	local used = {}
	local function scan(from, to)
		for slot = from, to do
			if GetActionInfo(slot) == "macro" then
				local name = C_ActionBar.GetActionText(slot)
				if name then used[name] = true end
			end
		end
	end
	scan(first, first + STORAGE_SLOTS - 1)
	scan(SHADOW_FIRST, SHADOW_LAST)
	return used
end

-- Recomputes this character's use of the addon's macros; deletes those no character uses. Other characters' flags
-- stay until they log in and change their own bars.
local function cleanup()
	local used = usedMacros()
	if not used then return end

	local account, character, me = registries()
	for name, info in pairs(account) do
		info.chars[me] = used[name] or nil
		if not next(info.chars) then
			local index = findMacro(name)
			if index then DeleteMacro(index) end
			account[name] = nil
		end
	end
	for name in pairs(character) do
		if not used[name] then
			local index = findMacro(name, true)
			if index then DeleteMacro(index) end
			character[name] = nil
		end
	end
end

-- Builds before the registry made these face actions as unregistered macros. Their bodies, as the addon wrote them:
-- "/click <top-bar button>" (a release only, which Back and Inspect's press handlers ignore) and the
-- press-and-release form after it.
local LEGACY_MACROS = { ["PS:Back"] = { id = "game:back", slot = 7 }, ["PS:Inspect"] = { id = "game:inspect", slot = 6 } }

local function topButtonName(slot)
	local bars = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit and GamepadMainActionBarFrame.PageUnit.actionBars
	local button = bars and bars.topBar and bars.topBar.actionButtons and bars.topBar.actionButtons[slot]
	return button and button:GetName()
end

-- A PS:Back / PS:Inspect macro on slot that no registry holds (Face calls this only when CurrentId didn't find it
-- registered): adopted into the account registry (for this character)
-- when its body is word for word one the addon wrote, and its old id returned. Otherwise nil and the macro's name: the
-- player's macro, left alone.
function Actions.AdoptLegacy(slot)
	if GetActionInfo(slot) ~= "macro" then return end
	local name = C_ActionBar.GetActionText(slot)
	local legacy = name and LEGACY_MACROS[name]
	if not legacy then return end

	local index, button = findMacro(name), topButtonName(legacy.slot)
	local body = index and call(GetMacroBody, index)
	if not (body and button and (body == "/click " .. button or body == CLICK.both:format(button, button))) then return nil, name end
	local account, _, me = registries()
	account[name] = { id = legacy.id, chars = { [me] = true } }
	return legacy.id
end

local FULL = "Your macro slots are full (%d account, %d character). Delete a macro to put game actions like %s on the crossbar."

-- The index of the addon's macro for a game entry, made if needed. A name the player already uses is skipped
-- ("FCT:Bags" taken -> "FCT:Bags 2").
local function ensureMacro(entry)
	local account, character, me = registries()
	local id, payload = entry.id, entry.payload
	-- Reuse: the cleanup after the assign flags this character.
	-- An older build may have written another body: brought up to date first.
	local function current(index)
		if call(GetMacroBody, index) ~= payload.text then EditMacro(index, nil, nil, payload.text) end
		return index
	end
	for name, info in pairs(account) do
		local index = info.id == id and findMacro(name)
		if index then return current(index) end
	end
	for name, info in pairs(character) do
		local index = info.id == id and findMacro(name, true)
		if index then return current(index) end
	end

	local name
	for n = 1, 9 do
		local candidate = n == 1 and payload.macro or (payload.macro:sub(1, 14) .. " " .. n)
		if not macroIndex(candidate) then
			name = candidate
			break
		end
	end
	if not name then return nil, "Controller Tweaks couldn't find a free macro name for " .. entry.name .. "." end

	local numAccount, numCharacter = call(GetNumMacros)
	local perChar = (numAccount or 0) >= MAX_ACCOUNT
	if perChar and (numCharacter or 0) >= MAX_CHARACTER then return nil, FULL:format(MAX_ACCOUNT, MAX_CHARACTER, entry.name) end

	local ok, index = pcall(CreateMacro, name, payload.icon, payload.text, perChar)
	if not (ok and index) then return nil, "The game couldn't create the macro for " .. entry.name .. "." end
	if perChar then character[name] = { id = id } else account[name] = { id = id, chars = { [me] = true } } end
	return index
end

local function pickupMount(payload)
	local journal = C_MountJournal
	if payload == RANDOM_MOUNT then return journal.Pickup(0) end
	for i = 1, call(journal.GetNumDisplayedMounts) or 0 do
		if select(12, call(journal.GetDisplayedMountInfo, i)) == payload.mountID then return journal.Pickup(i) end
	end
	-- Hidden by the journal's filters: the mount's summon spell does the same.
	return C_Spell.PickupSpell(payload.spellID)
end

-- Slots that follow a spell's highest rank: db.chars[char].highest[slot] = { name, id } (id = the rank placed).
local function highestSlots()
	local char = ns.Face.CharDB()
	if not char then return nil end
	char.highest = char.highest or {}
	return char.highest
end

local function topRank(name)
	local list = spellbook().byName[name]
	return list and list[1]
end

local function pickup(entry)
	local kind, payload = entry.kind, entry.payload
	if kind == "spell" then return C_Spell.PickupSpell(payload) end
	if kind == "spellgroup" then
		local top = topRank(payload)
		return top and C_Spell.PickupSpell(top.id)
	end
	if kind == "pet" then return C_SpellBook.PickupSpellBookItem(payload.slot, Enum.SpellBookSpellBank.Pet) end
	if kind == "item" then return C_Item.PickupItem(payload) end
	if kind == "toy" then return C_ToyBox.PickupToyBoxItem(payload) end
	if kind == "set" then return C_EquipmentSet.PickupEquipmentSet(payload) end
	if kind == "mount" then return pickupMount(payload) end
	if kind == "macro" then
		local index = macroIndex(payload)
		return index and PickupMacro(index)
	end
	if kind == "game" then
		local index, err = ensureMacro(entry)
		if not index then return nil, err end
		return PickupMacro(index)
	end
end

local COMBAT = "Controller Tweaks changes the crossbar out of combat only."
local HOLDING = "Put down what the cursor is holding first."
local ROUTED = "%s needs press and release, which a crossbar slot can't send: Controller Tweaks routes it on this button instead."

local NOT_EMPTY = "That action slot isn't free after all; Controller Tweaks left it as it was."

-- Picks entry up and places it in slot. guard (shadow slots): the slot must be empty or hold what the addon placed
-- (expected); if PlaceAction hands back anything else, it goes back into the slot and nothing is deleted.
local function place(slot, entry, guard, expected)
	if InCombatLockdown() then return nil, COMBAT end
	if entry.kind == "face" then return nil, ROUTED:format(entry.name) end
	if entry.disabled then return nil, entry.note end
	if GetCursorInfo() then return nil, HOLDING end

	local _, err = pickup(entry)
	if err or not GetCursorInfo() then
		cleanup()
		return nil, err or ("The game couldn't pick up " .. entry.name .. ".")
	end
	local before = C_ActionBar.HasAction(slot) and GetActionInfo(slot) and true
	PlaceAction(slot)
	-- PlaceAction swaps: the slot's previous action is on the cursor now.
	if guard and GetCursorInfo() and not (expected and before) then
		PlaceAction(slot)
		ClearCursor()
		cleanup()
		return nil, NOT_EMPTY
	end
	ClearCursor()
	cleanup()
	local tracked = highestSlots()
	if tracked then tracked[slot] = entry.kind == "spellgroup" and { name = entry.payload, id = topRank(entry.payload).id } or nil end
	return true
end

-- Puts entry into a gamepad storage slot. Returns true, or nil and a reason.
function Actions.Assign(slot, entry) return place(slot, entry) end

function Actions.Clear(slot)
	if InCombatLockdown() then return nil, COMBAT end
	if GetCursorInfo() then return nil, HOLDING end

	if C_ActionBar.HasAction(slot) then
		PickupAction(slot)
		ClearCursor()
	end
	cleanup()
	local tracked = highestSlots()
	if tracked then tracked[slot] = nil end
	return true
end

-- Shadow slots: a routed cell's entry that a slot can hold also sits in a spare action slot, so the router and its
-- click catcher fire it natively (UseAction: hold-to-cast, empower, flyouts) and it draws every native state.
-- db.chars[char].shadow[slot] = { code, layer, id, holds }: holds is what the addon placed (kind:id, a macro by name),
-- so a slot the player changed is noticed and given up without clearing it.
local function shadowSlots()
	local char = ns.Face.CharDB()
	if not char then return nil end
	char.shadow = char.shadow or {}
	return char.shadow
end

local function signature(slot)
	if not C_ActionBar.HasAction(slot) then return nil end
	local kind, id = GetActionInfo(slot)
	if kind == "macro" then return "macro:" .. tostring(C_ActionBar.GetActionText(slot)) end
	return tostring(kind) .. ":" .. tostring(id)
end

-- A macro slot's GetActionInfo id is the macro's spell for a spell macro, not its index (ActionButton.lua:924), so a
-- macro is known by the slot's macro name and that macro's body, which a rename keeps.
local function macroBody(slot)
	local index = macroIndex(C_ActionBar.GetActionText(slot) or "")
	return index and call(GetMacroBody, index)
end

-- What the addon placed: its signature, and for a macro its body, to know it again after a rename.
local function stamp(slot, info)
	info.holds = signature(slot)
	info.macro = nil
	info.body = GetActionInfo(slot) == "macro" and macroBody(slot) or nil
end

-- Still the addon's: what it placed, or the same spell at a higher rank (learning a rank moves the bars up to it) or
-- the same macro renamed. Then holds follows the change; anything else, a lower rank included, is the player's.
local function stillOurs(slot, info)
	if not C_ActionBar.HasAction(slot) then return false end
	if signature(slot) == info.holds then return true end

	local kind, id = GetActionInfo(slot)
	local was, wasID = tostring(info.holds):match("^(%a+):(.*)$")
	local same
	if kind == "spell" and was == "spell" then
		local new, old = spellbook().byID[id], spellbook().byID[tonumber(wasID)]
		same = not not (new and old and new.name == old.name and (new.number or 0) > (old.number or 0))
	elseif kind == "macro" and was == "macro" then
		same = info.body ~= nil and macroBody(slot) == info.body
	end
	if same then stamp(slot, info) end
	return same
end

local function isGamepadSlot(slot)
	for _, api in ipairs({ C_ActionBar or {}, C_GamepadUI or {} }) do
		if api.IsValidGamepadActionStorageSlotIndex then return not not call(api.IsValidGamepadActionStorageSlotIndex, slot) end
	end
	local first = C_GamepadUI and call(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
	return first and slot >= first and slot < first + STORAGE_SLOTS or false
end

local function ownedSlot(code, layer)
	for slot, info in pairs(shadowSlots() or {}) do
		if info.code == code and info.layer == layer then return slot, info end
	end
end

local RELEASED = "Controller Tweaks gave its action slots back (/fct release); /reload to use them again."
local released

local FULL_SHADOW = "No free action slot for %s: routed buttons and touch-bar buttons share the 36 hidden slots on keyboard bars 6-8 (slots 145-180), and none is free. Clear one of them, or empty a slot there."

-- The shadow slot holding entry for this cell, placed if needed (out of combat, empty cursor). Returns the slot, or nil
-- and a reason. A slot the player changed is given up (left as is) and a new one picked; the cell's previous entry is
-- replaced in its own slot.
function Actions.Shadow(code, layer, entry)
	if released then return nil, RELEASED end
	local owned = shadowSlots()
	if not owned then return nil, "no character yet" end
	local slot, info = ownedSlot(code, layer)
	if slot and C_ActionBar.HasAction(slot) and not stillOurs(slot, info) then
		owned[slot], slot = nil, nil
	end
	if slot and info.id == entry.id and C_ActionBar.HasAction(slot) then return slot end
	if InCombatLockdown() then return nil, COMBAT end
	if GetCursorInfo() then return nil, HOLDING end
	local full = Actions.Find(entry.id)
	if not full then return nil, tostring(entry.name) .. " is no longer available." end

	if not slot then
		for candidate = SHADOW_LAST, SHADOW_FIRST, -1 do
			if not owned[candidate] and not C_ActionBar.HasAction(candidate) and not isGamepadSlot(candidate) then
				slot = candidate
				break
			end
		end
		if not slot then return nil, FULL_SHADOW:format(entry.name) end
	end
	local ok, err = place(slot, full, true, owned[slot] and C_ActionBar.HasAction(slot))
	if not ok then return nil, err end
	owned[slot] = { code = code, layer = layer, id = entry.id }
	stamp(slot, owned[slot])
	return slot
end

-- The cell's shadow slot while it still holds what the addon placed, else nil. Reads only.
function Actions.ShadowSlot(code, layer, id)
	local slot, info = ownedSlot(code, layer)
	if slot and info.id == id and stillOurs(slot, info) then return slot end
end

-- Gives the cell's shadow slot back: cleared if it still holds the addon's action, else just let go.
function Actions.ReleaseShadow(code, layer)
	local owned = shadowSlots()
	local slot, info = ownedSlot(code, layer)
	if not slot then return true end
	if stillOurs(slot, info) then
		local ok, err = Actions.Clear(slot)
		if not ok then return nil, err end
	end
	owned[slot] = nil
	return true
end

-- Slot writes make and delete FCT: macros, whose UPDATE_MACROS (and the catalog messages after it) run synchronously;
-- an apply then would read a half-swapped slot and take it for the player's change. Every write runs inside this, and
-- Face and Touch skip their applies while it runs (the caller's own apply follows).
local writing = 0
function Actions.Busy() return writing > 0 end

local function finish(ok, ...)
	writing = writing - 1
	if not ok then error((...), 0) end
	return ...
end
local function guard(fn)
	return function(...)
		writing = writing + 1
		return finish(pcall(fn, ...))
	end
end
for _, name in ipairs({ "Assign", "Clear", "Shadow", "ReleaseShadow" }) do Actions[name] = guard(Actions[name]) end

-- Bars 6-8 as the allocator sees them: slots it holds (routed cells and touch buttons alike), empty slots it could
-- still take, and the range's size.
function Actions.ShadowCapacity()
	local owned = shadowSlots() or {}
	local used, free = 0, 0
	for slot = SHADOW_FIRST, SHADOW_LAST do
		if owned[slot] then used = used + 1 elseif not C_ActionBar.HasAction(slot) and not isGamepadSlot(slot) then free = free + 1 end
	end
	return used, free, SHADOW_LAST - SHADOW_FIRST + 1
end

-- The shadow slots in use, for /fct selftest.
function Actions.ShadowState()
	local list = {}
	for slot in pairs(shadowSlots() or {}) do list[#list + 1] = slot end
	table.sort(list, function(a, b) return a > b end)
	return #list > 0 and table.concat(list, ",") or "none"
end

-- After a new rank is learned, tracked slots get it. A slot whose spell the player changed is no longer tracked;
-- one the game already moved to the new rank just follows it.
local function upgradeRanks()
	local tracked = highestSlots()
	if not tracked or InCombatLockdown() then return end

	for slot, info in pairs(tracked) do
		local kind, id = GetActionInfo(slot)
		local top = topRank(info.name)
		if kind ~= "spell" or not top or (id ~= info.id and id ~= top.id) then
			tracked[slot] = nil
		elseif id ~= top.id and not GetCursorInfo() then
			C_Spell.PickupSpell(top.id)
			if GetCursorInfo() then
				PlaceAction(slot)
				ClearCursor()
				info.id = top.id
			end
		else
			info.id = id
		end
		-- A shadow slot that moved to the new rank is still the addon's.
		local shadow = tracked[slot] and shadowSlots()[slot]
		if shadow then stamp(slot, shadow) end
	end
end

-- True when the slot holds one of the addon's registered FCT: macros.
function Actions.Ours(slot)
	return C_ActionBar.HasAction(slot) and GetActionInfo(slot) == "macro" and not not ours(C_ActionBar.GetActionText(slot) or "")
end

-- The catalog id of what a storage slot holds, to pre-focus it in the picker.
function Actions.CurrentId(slot)
	if not (slot and C_ActionBar.HasAction(slot)) then return end
	local kind, id, subType = GetActionInfo(slot)
	if kind == "spell" then
		local tracked = highestSlots()
		local info = tracked and tracked[slot]
		if info and info.id == id then return "spellgroup:" .. info.name end
		return (subType == "pet" and "pet:" or "spell:") .. tostring(id)
	end
	if kind == "item" then return (isToy(id) and "toy:" or "item:") .. tostring(id) end
	if kind == "summonmount" then return "mount:" .. (id == RANDOM_MOUNT_ACTION and RANDOM_MOUNT or tostring(id)) end
	if kind == "equipmentset" then
		local setID = C_EquipmentSet and call(C_EquipmentSet.GetEquipmentSetID, id)
		return setID and "set:" .. setID
	end
	if kind == "macro" then
		local name = C_ActionBar.GetActionText(slot)
		if not name then return end
		local info = ours(name)
		return info and info.id or "macro:" .. name
	end
end

-- Secure macro text for a catalog id on a routed cell. Face.lua builds it when it applies, so spell names, ranks and
-- the player's macro bodies are current; nil when the id no longer resolves.
function Actions.TextFor(id)
	local kind, value = tostring(id):match("^(%a+):(.+)$")
	local number = tonumber(value)
	if kind == "spell" and spellbook().byID[number] then return castText(spellbook().byID[number]) end
	if kind == "spellgroup" then
		local top = topRank(value)
		return top and castText(top)
	end
	if kind == "spell" or kind == "pet" then
		local name = call(C_Spell.GetSpellName, number)
		return name and "/cast " .. name
	end
	if kind == "item" then return "/use item:" .. value end
	if kind == "toy" then
		local _, name = call((C_ToyBox or {}).GetToyInfo, number)
		return name and "/usetoy " .. name
	end
	if kind == "set" then
		local name = C_EquipmentSet and call(C_EquipmentSet.GetEquipmentSetInfo, number)
		return name and "/equipset " .. name
	end
	if kind == "mount" then
		local spellID = value == RANDOM_MOUNT and RANDOM_MOUNT_SPELL or select(2, call((C_MountJournal or {}).GetMountInfoByID, number))
		local name = spellID and call(C_Spell.GetSpellName, spellID)
		return name and "/cast " .. name
	end
	if kind == "macro" then
		local index = macroIndex(value)
		return index and call(GetMacroBody, index)
	end
	if kind == "game" then
		local spec = GAME_BY_KEY[value]
		return spec and gameText(spec)
	end
	if kind == "addon" then
		local entry = Actions.Find(id)
		return entry and entry.kind == "game" and entry.payload.text or nil
	end
end

local DESCRIBE = { spell = "Spell", pet = "Pet spell", item = "Item with a use effect", toy = "Toy", set = "Equipment set", mount = "Mount", macro = "Your macro", face = "Face action (press and hold)", ring = "Ring: hold the button, aim with the right stick, release to use (a touch button: tap)" }

function Actions.Describe(entry)
	if entry.kind == "game" then return "Game command: " .. entry.payload.text end
	if entry.kind == "spellgroup" then return entry.highest and "Spell: always your highest rank, also after you learn a new one" or "Spell with ranks" end
	return DESCRIBE[entry.kind] or entry.kind
end

-- Actions owns the caches: the catalog is rebuilt lazily on the next read, the spellbook only after spells change.
-- FCT_CATALOG_CHANGED(event) follows; Face and Touch rebuild texts only for TEXT_EVENTS.
for _, event in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED", "NEW_MOUNT_ADDED", "NEW_TOY_ADDED", "UPDATE_MACROS", "FCT_ACTIVE_CHANGED", "ADDON_LOADED", "UPDATE_BINDINGS", "FCT_RINGS_CHANGED" }) do
	ns.On(event, function()
		cache = nil
		if event == "SPELLS_CHANGED" then book = nil end
		-- Ranks first, so Face sees its shadow slots on the new rank. Placing waits for combat to end.
		if event == "SPELLS_CHANGED" and next(highestSlots() or {}) then ns.whenPadFree("highest ranks", guard(upgradeRanks)) end
		ns.Fire("FCT_CATALOG_CHANGED", event)
	end)
end

-- Macros made before the rename are named "PS:<short>". Once per character, out of combat, the registered ones take
-- the new prefix (EditMacro keeps them on every bar) and the registry keys follow. A "PS:" macro no registry holds is
-- the player's and stays as it is; a new name already taken leaves that one as it was (it is still found by its id).
local OLD_PREFIX = "PS:"
local function renamePrefix()
	local char = ns.Face.CharDB()
	if not char or char.macroPrefixDone or InCombatLockdown() then return end

	local account, character = registries()
	for list, perChar in pairs({ [account] = false, [character] = true }) do
		local old = {}
		for name in pairs(list) do
			if name:sub(1, #OLD_PREFIX) == OLD_PREFIX then old[#old + 1] = name end
		end
		for _, name in ipairs(old) do
			local new = (MACRO_PREFIX .. name:sub(#OLD_PREFIX + 1)):sub(1, 16)
			if not (list[new] or macroIndex(new)) then
				local index = findMacro(name, perChar)
				if index then EditMacro(index, new) end
				list[new], list[name] = list[name], nil
			end
		end
	end
	char.macroPrefixDone = true
end
ns.On("PLAYER_ENTERING_WORLD", guard(renamePrefix))
ns.On("PLAYER_REGEN_ENABLED", guard(renamePrefix))

-- /fct release: before uninstalling, gives back every slot the addon holds (shadow and touch slots, cleared while
-- they still hold its action) and deletes its registered FCT: macros, which leaves its game commands off the crossbar.
-- Nothing is placed again until /reload; routed cells run as macro text meanwhile.
function ns.commands.release()
	if InCombatLockdown() then return ns.log(COMBAT) end
	if GetCursorInfo() then return ns.log(HOLDING) end

	local slots, macros = 0, 0
	for _, info in pairs(shadowSlots() or {}) do
		if Actions.ReleaseShadow(info.code, info.layer) then slots = slots + 1 end
	end
	released = true
	local account, character = registries()
	for list, perChar in pairs({ [account] = false, [character] = true }) do
		for name in pairs(list) do
			local index = findMacro(name, perChar)
			if index then
				DeleteMacro(index)
				macros = macros + 1
			end
			list[name] = nil
		end
	end
	ns.log(("gave back %d action slots and deleted %d FCT: macros. /reload to place them again."):format(slots, macros))
	ns.Fire("FCT_LAYOUT_CHANGED", "release")
end
