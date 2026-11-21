-- Stubbed WoW check of the action catalog and the addon macro registry: lua tests/actions_spec.lua
-- Macros are made, shared across characters and deleted only when the addon made them and no character uses them;
-- a player's macro named FCT: is never touched; full macro slots fall back, then report. Also the catalog (order,
-- sort, cache), the click text per press kind, CurrentId and TextFor.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local W = { char = "Ann", combat = false }
local ns = {}
local FIRST, MAX_ACCOUNT = 500, 120

-- Frames: anything Face.lua calls at load is a no-op.
local Obj = {}
local function new(name)
	local o = setmetatable({ attrs = {}, scripts = {}, name = name }, { __index = function(_, k) return Obj[k] or function() end end })
	if name then _G[name] = o end
	return o
end
function Obj:SetAttribute(k, v) self.attrs[k] = v end
function Obj:GetAttribute(k) return self.attrs[k] end
function Obj:GetName() return self.name end
function Obj:SetScript(k, fn) self.scripts[k] = fn end
UIParent = new()
function CreateFrame(_, name) return new(name) end
local printed = {}
function print(msg) printed[#printed + 1] = msg end
function date() return "00:00:00 " end
function GetTime() return 0 end
function InCombatLockdown() return W.combat end
function GetCVar() return nil end
function GetCVarBool() return false end
function UnitName() return W.char end
function UnitGUID(unit) if unit == "player" then return "Player-0-" .. W.char end end
function GetNormalizedRealmName() return "Realm" end
SlashCmdList = {}
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
local tickers = {}
C_Timer = { NewTicker = function(_, fn)
	local t = { fn = fn, Cancel = function(self) self.dead = true end }
	tickers[#tickers + 1] = t
	return t
end }
local function tickAll() for _, t in ipairs(tickers) do if not t.dead then t.fn() end end end

-- Macros: account indexes 1..120, character indexes 121..150 (per character).
local account, perChar = {}, {}
local function charList()
	perChar[W.char] = perChar[W.char] or {}
	return perChar[W.char]
end
local function macroAt(i)
	if i <= MAX_ACCOUNT then return account[i] end
	return charList()[i - MAX_ACCOUNT]
end
function GetNumMacros() return #account, #charList() end
function GetMacroInfo(i)
	local m = macroAt(i)
	if m then return m.name, m.icon, m.body end
end
function GetMacroBody(i)
	local m = macroAt(i)
	return m and m.body
end
function CreateMacro(name, icon, body, isChar)
	local list = isChar and charList() or account
	list[#list + 1] = { name = name, icon = icon, body = body }
	if ns.Fire then ns.Fire("UPDATE_MACROS") end
	return #list + (isChar and MAX_ACCOUNT or 0)
end
function EditMacro(i, name, icon, body)
	local m = macroAt(i)
	m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
end
function DeleteMacro(i)
	if i <= MAX_ACCOUNT then table.remove(account, i) else table.remove(charList(), i - MAX_ACCOUNT) end
	ns.Fire("UPDATE_MACROS")
end
local function macroNamed(name, list)
	for i, m in ipairs(list or account) do if m.name == name then return i, m end end
end

-- Action slots per character, and the cursor. A macro slot holds the macro itself (renames and deletes show).
local slots, cursor = {}, nil
local function bars()
	slots[W.char] = slots[W.char] or {}
	return slots[W.char]
end
C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return FIRST end }
C_ActionBar = {}
-- No deprecated globals (loadDeprecationFallbacks off): only C_ActionBar answers.
assert(HasAction == nil and GetActionText == nil and GetActionTexture == nil, "deprecated action globals must stay unstubbed")
function C_ActionBar.HasAction(slot) return bars()[slot] ~= nil end
function GetActionInfo(slot)
	local a = bars()[slot]
	if not a then return end
	if a.kind == "macro" then
		-- A spell macro reports its spell, not its index (ActionButton.lua:924).
		for i, m in ipairs(account) do if m == a.macro then return "macro", m.spell or i end end
		return "macro", 0
	end
	return a.kind, a.id, a.sub
end
function C_ActionBar.GetActionText(slot)
	local a = bars()[slot]
	return a and a.kind == "macro" and a.macro.name or nil
end
function GetCursorInfo() return cursor and cursor.kind end
function ClearCursor() cursor = nil end
function PickupMacro(i) cursor = { kind = "macro", macro = macroAt(i) } end
function PlaceAction(slot) cursor, bars()[slot] = bars()[slot], cursor end
function PickupAction(slot) cursor, bars()[slot] = bars()[slot], nil end
local picked = {}
C_Spell = {
	PickupSpell = function(id)
		picked[#picked + 1] = "spell:" .. id
		cursor = { kind = "spell", id = id }
	end,
	GetSpellName = function(id) return ({ [133] = "Fireball", [400] = "Bite", [4321] = "Swift Horse", [150544] = "Summon Random Favorite Mount" })[id] end,
}

-- Catalog sources. Holy Light has three ranks, listed out of order; a rank's subName may be missing (not loaded).
local book = {
	{ spellID = 133, name = "Fireball" }, { spellID = 639, name = "Holy Light", subName = "Rank 2", low = true },
	{ spellID = 116, name = "Arcane Missiles", subName = "Racial" }, { spellID = 647, name = "Holy Light", subName = "Rank 3" },
	{ spellID = 635, name = "Holy Light", subName = "Rank 1", low = true },
	{ spellID = 20, name = "Seal", subName = "", low = true }, { spellID = 21, name = "Seal", subName = "" },
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
	GetSpellBookItemInfo = function(slot, bank)
		if bank == 1 then return { spellID = 400, name = "Bite" } end
		return book[slot]
	end,
	IsSpellBookItemPassive = function() return false end,
	IsSpellBookItemLowRank = function(slot) return book[slot].low end,
	HasPetSpells = function() return 1 end,
}
C_MountJournal = {
	GetMountIDs = function() return { 7, 8, 9 } end,
	GetMountInfoByID = function(id)
		if id == 7 then return "Swift Horse", 4321, 1, false, true, 0, false, false, nil, false, true, 7 end
		if id == 8 then return "Unowned Drake", 4322, 1, false, true, 0, false, false, nil, false, false, 8 end
		if id == 9 then return "Alliance Only", 4323, 1, false, true, 0, false, false, nil, true, true, 9 end
	end,
	-- The journal's search filters everything out.
	GetNumDisplayedMounts = function() return 0 end,
}
function GetInventoryItemID(_, slot) if slot == 13 then return 111 end end
function GetInventoryItemTexture() return 5 end
C_Item = {
	GetItemSpell = function(id) if id == 111 then return "Use" end end,
	GetItemNameByID = function(id) if id == 111 then return "Badge" end end,
}
C_ToyBox = {
	GetNumFilteredToys = function() return 0 end,
	GetToyInfo = function(id) if id == 222 then return 222, "Toy Train", 3 end end,
}
function PlayerHasToy(id) return id == 222 end
C_EquipmentSet = {
	GetEquipmentSetIDs = function() return { 3 } end,
	GetEquipmentSetInfo = function(id) if id == 3 then return "PvP", 4 end end,
	GetEquipmentSetID = function(name) if name == "PvP" then return 3 end end,
}
MainMenuBarBackpackButton, ExtraActionButton1 = {}, {}
local top = {}
for i = 1, 8 do top[i] = new("TopButton" .. i) end
GamepadMainActionBarFrame = { PageUnit = { actionBars = { topBar = { actionButtons = top } } } }

for _, file in ipairs({ "Core.lua", "Layout.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
ns.Device = { Current = function() return { key = "054c/0ce6" } end, SwapTargets = function() return false end }
-- Sync.lua without C_EncodingUtil: always settled, its timers never needed.
C_Timer.After = function() end
for _, file in ipairs({ "Face.lua", "Actions.lua", "Sync.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks")
local Actions = ns.Actions

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end
local function find(categories, id)
	for _, category in ipairs(categories) do
		for _, entry in ipairs(category.entries) do if entry.id == id then return entry, category end end
	end
end
local function entry(id) return assert(find(Actions.Catalog(), id), id) end
local function registered(name) return ns.db.macros[name] end

-- The take-back waits for the login sync (design/sync.md 2.5), then runs on FCT_SYNC_SETTLED.
local Sync, synced = ns.Sync, false
local realSettled = Sync.Settled
Sync.Settled = function() return synced end
ns.db.options.debug = true
InputUtil = { IsGamepadUIEnabled = function() return true end }
ns.Fire("FCT_ACTIVE_CHANGED", true)
check(ns.db.debugLog[#ns.db.debugLog]:find("leftovers: waiting (sync)", 1, true), "take-back: waits for the login sync")
synced = true
ns.Fire("FCT_SYNC_SETTLED")
check(not ns.db.debugLog[#ns.db.debugLog]:find("waiting (sync)", 1, true), "take-back: runs once the sync settled")
Sync.Settled, ns.db.options.debug, InputUtil = realSettled, false, nil

-- Catalog: order, sort, sources, cache.
local catalog = Actions.Catalog()
local names = {}
for _, category in ipairs(catalog) do names[#names + 1] = category.name end
check(table.concat(names, ",") == "Spells,Items,Mounts,Movement,Targeting,Combat,Windows,Misc", "categories in order, empty ones left out")
local spells = catalog[1].entries
check(spells[1].name == "Arcane Missiles" and spells[2].name == "Bite (pet)" and spells[3].name == "Fireball" and spells[4].name == "Holy Light", "entries sorted by name")
check(find(catalog, "mount:7") and not find(catalog, "mount:8") and not find(catalog, "mount:9"), "mounts: collected ones by id, despite the journal filter")
check(find(catalog, "item:111"), "equipped trinket with a use effect")
check(find(catalog, "set:3"), "equipment set")
check(Actions.Catalog() == catalog, "cached")
check(Actions.Catalog(true) == catalog, "one catalog for every cell")
check(entry("mount:random") and not entry("mount:random").disabled and entry("face:jump") and not entry("face:jump").disabled, "random mount and face actions on every cell")
ns.Fire("UPDATE_MACROS")
check(Actions.Catalog() ~= catalog, "invalidated on UPDATE_MACROS")
ns.Fire("NEW_MOUNT_ADDED")
check(Actions.Catalog() ~= catalog, "invalidated on NEW_MOUNT_ADDED")

-- Click text per press kind.
check(entry("game:bags").payload.text == "/click MainMenuBarBackpackButton", "plain button: up click")
check(entry("game:extraaction").payload.text == "/click ExtraActionButton1 LeftButton 1\n/click ExtraActionButton1 LeftButton", "action button: down and up")
check(entry("face:back").kind == "face" and entry("face:inspect").kind == "face" and not find(catalog, "game:back") and not find(catalog, "game:inspect"), "Back and Inspect are face actions, not FCT: macros")
check(Actions.LEGACY_FACE["game:back"] == "face:back" and Actions.TextFor("game:back") == nil, "old ids map to the face actions")
check(entry("game:targetenemy").payload.text == "/targetenemy", "slash command as is")
check(not find(Actions.Catalog(), "game:character"), "missing Blizzard button: no entry")
check(entry("game:bags").payload.icon == "INV_Misc_Bag_08", "macro icon is the bare icon name")

-- Toggle FPS: our own plain button, clicked like the Blizzard ones; FramerateFrame:Toggle, else ToggleFramerate.
-- Open chat is gone: no entry, no button, and no text for an old saved cell.
local fps = entry("game:fps")
check(fps and fps.category == "Misc" and fps.name == "Toggle FPS" and fps.payload.text == "/click ForeverControllerTweaksToggleFPS" and fps.payload.icon == "INV_Misc_PocketWatch_01", "Toggle FPS: a Misc game action clicking our button")
check(Actions.TextFor("game:fps") == "/click ForeverControllerTweaksToggleFPS", "Toggle FPS: the same text for rings and touch buttons")
check(not find(Actions.Catalog(), "game:chat") and Actions.TextFor("game:chat") == nil and ForeverControllerTweaksOpenChat == nil, "Open chat removed")
local toggled = 0
FramerateFrame = { Toggle = function(self) toggled = toggled + (self == FramerateFrame and 1 or 100) end }
ForeverControllerTweaksToggleFPS.scripts.OnClick(ForeverControllerTweaksToggleFPS, "LeftButton")
check(toggled == 1, "the click toggles the framerate frame")
FramerateFrame = {}
ToggleFramerate = function() toggled = toggled + 10 end
ForeverControllerTweaksToggleFPS.scripts.OnClick(ForeverControllerTweaksToggleFPS, "LeftButton")
check(toggled == 11, "no Toggle method: ToggleFramerate")
FramerateFrame, ToggleFramerate = nil, nil
ForeverControllerTweaksToggleFPS.scripts.OnClick(ForeverControllerTweaksToggleFPS, "LeftButton")
check(toggled == 11, "neither API: the click does nothing")

-- Registry: Ann makes FCT:Bags, Bob reuses it, it lives while either character uses it.
check(Actions.Assign(FIRST, entry("game:bags")), "Ann assigns Bags")
check(#account == 1 and account[1].name == "FCT:Bags" and account[1].icon == "INV_Misc_Bag_08", "macro made")
check(registered("FCT:Bags").id == "game:bags" and registered("FCT:Bags").chars["Player-0-Ann"], "registered for Ann")
check(Actions.CurrentId(FIRST) == "game:bags", "CurrentId of a Controller Tweaks macro")
W.char = "Bob"
check(Actions.Assign(FIRST + 3, entry("game:bags")) and #account == 1, "Bob reuses it")
check(registered("FCT:Bags").chars["Player-0-Bob"], "registered for Bob")
account[1].body = "/click MainMenuBarBackpackButton OldBody"
check(Actions.Assign(FIRST + 4, entry("game:bags")) and account[1].body == "/click MainMenuBarBackpackButton" and #account == 1, "reuse brings an old body up to date")
Actions.Clear(FIRST + 4)
check(Actions.Clear(FIRST + 3) and #account == 1 and not registered("FCT:Bags").chars["Player-0-Bob"], "Bob clears: kept for Ann")
W.char = "Ann"
check(Actions.Clear(FIRST) and #account == 0 and registered("FCT:Bags") == nil, "Ann clears: deleted")

-- The other character's flag stays until they change their own bars.
check(Actions.Assign(FIRST, entry("game:bags")), "Ann again")
W.char = "Bob"
check(Actions.Assign(FIRST, entry("game:sit")), "Bob uses another macro")
check(macroNamed("FCT:Bags") and registered("FCT:Bags").chars["Player-0-Ann"], "Bob's cleanup keeps Ann's macro")
W.char = "Ann"
check(Actions.Clear(FIRST) and not macroNamed("FCT:Bags") and macroNamed("FCT:Sit"), "Ann's last use gone: FCT:Bags deleted, Bob's FCT:Sit kept")
W.char = "Bob"
check(Actions.Clear(FIRST) and #account == 0, "Bob clears FCT:Sit")
W.char = "Ann"

-- A player's own macro named FCT: is never touched; the addon takes the next name.
CreateMacro("FCT:Bags", 1, "/say mine", false)
check(Actions.Assign(FIRST, entry("game:bags")), "assign with a foreign FCT:Bags present")
check(#account == 2 and account[2].name == "FCT:Bags 2" and registered("FCT:Bags") == nil, "the addon's is FCT:Bags 2")
check(find(Actions.Catalog(), "macro:FCT:Bags") and not find(Actions.Catalog(), "macro:FCT:Bags 2"), "foreign FCT: macro listed as the player's, ours not")
check(Actions.Clear(FIRST) and #account == 1 and account[1].body == "/say mine", "clear: ours deleted, foreign kept")
bars()[FIRST + 1] = { kind = "macro", macro = account[1] }
check(Actions.CurrentId(FIRST + 1) == "macro:FCT:Bags", "CurrentId of a foreign FCT: macro")
bars()[FIRST + 1] = nil
check(Actions.Clear(FIRST) and #account == 1, "foreign macro survives an unused cleanup")
table.remove(account, 1)

-- Usage counts the whole gamepad storage range (3 pages x 28 + 5 stances x 8).
check(Actions.Assign(FIRST + 123, entry("game:sit")), "last stance slot")
check(Actions.Assign(FIRST, entry("game:stand")) and macroNamed("FCT:Sit"), "macro on the last storage slot counts as used")
Actions.Clear(FIRST + 123)
Actions.Clear(FIRST)
check(#account == 0, "both cleared")

-- Account slots full: character macro; both full: a reason for the dialog.
for i = 1, MAX_ACCOUNT do account[i] = { name = "user" .. i, body = "" } end
check(Actions.Assign(FIRST, entry("game:sit")), "account full: assigned")
local index = macroNamed("FCT:Sit", charList())
check(index and ns.db.chars["Player-0-Ann"].macros["FCT:Sit"].id == "game:sit", "character macro made and registered for Ann")
check(Actions.CurrentId(FIRST) == "game:sit", "CurrentId of a Controller Tweaks character macro")
check(Actions.Clear(FIRST) and #charList() == 0 and ns.db.chars["Player-0-Ann"].macros["FCT:Sit"] == nil, "character macro deleted when unused")
for i = 1, 30 do charList()[i] = { name = "char" .. i, body = "" } end
local ok, err = Actions.Assign(FIRST, entry("game:sit"))
check(not ok and err:find("macro slots are full"), "both full: reason")
check(#account == MAX_ACCOUNT and #charList() == 30 and not bars()[FIRST], "nothing made, nothing placed")
for i = MAX_ACCOUNT, 1, -1 do account[i] = nil end
perChar[W.char] = {}

-- Cursor: a held item is not dropped; PlaceAction's swap leaves nothing behind.
cursor = { kind = "item" }
ok, err = Actions.Assign(FIRST, entry("spell:133"))
check(not ok and err:find("Put down") and cursor.kind == "item", "held cursor kept")
ok, err = Actions.Clear(FIRST)
check(not ok and cursor.kind == "item", "clear keeps a held cursor too")
cursor = nil
bars()[FIRST] = { kind = "spell", id = 116 }
check(Actions.Assign(FIRST, entry("spell:133")) and cursor == nil and bars()[FIRST].id == 133, "swap: old spell not left on the cursor")

-- Mounts hidden by the journal's filters are picked up by their summon spell.
picked = {}
check(Actions.Assign(FIRST + 1, entry("mount:7")) and picked[1] == "spell:4321", "filtered mount: summon spell")

-- CurrentId per action kind.
local function currentFor(action)
	bars()[FIRST + 2] = action
	return Actions.CurrentId(FIRST + 2)
end
check(currentFor({ kind = "spell", id = 133 }) == "spell:133", "spell")
check(currentFor({ kind = "spell", id = 400, sub = "pet" }) == "pet:400", "pet spell")
check(currentFor({ kind = "item", id = 111 }) == "item:111", "item")
check(currentFor({ kind = "item", id = 222 }) == "toy:222", "toy")
check(currentFor({ kind = "summonmount", id = 7 }) == "mount:7", "mount")
check(currentFor({ kind = "summonmount", id = 268435455 }) == "mount:random", "random favorite mount")
check(currentFor({ kind = "equipmentset", id = "PvP" }) == "set:3", "equipment set by name")
CreateMacro("Mine", 1, "/dance", false)
check(currentFor({ kind = "macro", macro = account[#account] }) == "macro:Mine", "player macro")

-- Face text from ids.
check(Actions.TextFor("pet:400") == "/cast Bite", "pet text")
check(Actions.TextFor("toy:222") == "/usetoy Toy Train", "toy text")
check(Actions.TextFor("set:3") == "/equipset PvP", "set text")
check(Actions.TextFor("macro:Mine") == "/dance", "player macro body")
check(Actions.TextFor("macro:Gone") == nil and Actions.TextFor("spell:999") == nil, "missing ids: nil")

-- Spell ranks: one group per ranked spell, highest rank first; single-rank spells stay flat.
local holy = entry("spellgroup:Holy Light")
local labels = {}
for i, rank in ipairs(holy.ranks) do labels[i] = rank.name end
check(holy.kind == "spellgroup" and holy.category == "Spells" and holy.name == "Holy Light" and holy.payload == "Holy Light", "group entry")
check(table.concat(labels, ",") == "Holy Light (Highest Rank),Holy Light (Rank 3),Holy Light (Rank 2),Holy Light (Rank 1)", "ranks highest to lowest")
check(holy.ranks[1].highest and holy.ranks[1].id == "spellgroup:Holy Light" and holy.ranks[1].kind == "spellgroup", "first row tracks the highest rank")
check(holy.ranks[2].id == "spell:647" and holy.ranks[2].kind == "spell" and holy.ranks[4].id == "spell:635", "rank rows are plain spells")
check(not find(catalog, "spell:647") and not find(Actions.Catalog(), "spell:635"), "ranks only inside the group")
check(entry("spell:133").kind == "spell" and not entry("spell:133").ranks, "single rank: flat")
local seal = entry("spellgroup:Seal")
check(seal.ranks[2].id == "spell:21" and seal.ranks[2].name == "Seal (Rank 2)" and seal.ranks[3].name == "Seal (Rank 1)", "no rank text: the non-low rank first, numbered by position")
check(Actions.TextFor("spellgroup:Holy Light") == "/cast Holy Light(Rank 3)", "highest: the top rank by name and rank")
check(Actions.TextFor("spell:635") == "/cast Holy Light(Rank 1)" and Actions.TextFor("spell:116") == "/cast Arcane Missiles", "rank text only for ranked spells")
check(Actions.Describe(holy.ranks[1]):find("highest rank"), "Describe the highest row")

-- A highest-rank slot is re-placed with a new rank once it's learned; a fixed rank stays.
check(Actions.Assign(FIRST + 6, holy.ranks[1]) and bars()[FIRST + 6].id == 647, "highest placed")
check(Actions.Assign(FIRST + 7, holy.ranks[4]) and bars()[FIRST + 7].id == 635, "rank 1 placed")
check(Actions.CurrentId(FIRST + 6) == "spellgroup:Holy Light" and Actions.CurrentId(FIRST + 7) == "spell:635", "CurrentId tells them apart")
book[4].low = true
book[#book + 1] = { spellID = 3472, name = "Holy Light", subName = "Rank 4" }
ns.Fire("SPELLS_CHANGED")
check(bars()[FIRST + 6].id == 3472 and cursor == nil, "new rank on the highest slot")
check(bars()[FIRST + 7].id == 635, "fixed rank untouched")
check(Actions.CurrentId(FIRST + 6) == "spellgroup:Holy Light" and Actions.TextFor("spellgroup:Holy Light") == "/cast Holy Light(Rank 4)", "still tracked; routed text follows")
-- In combat the swap waits; a slot the player changed is let go.
book[#book + 1] = { spellID = 10328, name = "Holy Light", subName = "Rank 5" }
W.combat = true
ns.Fire("SPELLS_CHANGED")
check(bars()[FIRST + 6].id == 3472, "combat: waits")
W.combat = false
tickAll()
check(bars()[FIRST + 6].id == 10328, "after combat: new rank")
bars()[FIRST + 6] = { kind = "spell", id = 133 }
check(Actions.CurrentId(FIRST + 6) == "spell:133", "tracked slot holding another spell: not the group")
ns.Fire("SPELLS_CHANGED")
check(Actions.CurrentId(FIRST + 6) == "spell:133" and ns.db.chars["Player-0-Ann"].highest[FIRST + 6] == nil, "player's own change: untracked")
check(Actions.Assign(FIRST + 6, holy.ranks[1]) and Actions.Assign(FIRST + 6, entry("spell:133")) and ns.db.chars["Player-0-Ann"].highest[FIRST + 6] == nil, "assigning over it untracks")
check(Actions.Assign(FIRST + 6, holy.ranks[1]) and Actions.Clear(FIRST + 6) and ns.db.chars["Player-0-Ann"].highest[FIRST + 6] == nil, "clearing untracks")

-- Face actions can't go into a slot; the random favorite mount has routed text too.
ok, err = Actions.Assign(FIRST + 8, entry("face:jump"))
check(not ok and err:find("press and release") and not bars()[FIRST + 8], "face action refused on a slot")
check(Actions.TextFor("mount:random") == "/cast Summon Random Favorite Mount", "random favorite mount text")

-- Shadow slots: hidden keyboard bars 6-8 (145-180), empty slots only, from the top down.
local A = Actions
function GetServerTime() return 1795200000 end
bars()[180] = { kind = "spell", id = 116 }
local shadow = A.Shadow("FT", "T", { id = "spell:133", name = "Fireball" })
check(shadow == 179 and bars()[179].id == 133 and bars()[180].id == 116, "top-down, a used slot skipped")
local placed = ns.db.chars["Player-0-Ann"].placed
check(placed[179] and placed[179].holds == "spell:133" and placed[179].at == 1795200000 and not placed[180], "the synced list: the placed slot, with what it holds and when")
check(A.ShadowSlot("FT", "T", "spell:133") == 179 and A.ShadowSlot("FT", "T", "spell:116") == nil, "ShadowSlot by id")
check(A.Shadow("FT", "T", { id = "spell:133", name = "Fireball" }) == 179 and cursor == nil, "same entry: same slot, nothing placed")
check(A.Shadow("FB", "T", { id = "game:sit", name = "Sit" }) == 178 and macroNamed("FCT:Sit"), "next cell: next slot, a game macro")
check(placed[178].holds == "macro:FCT:Sit" and placed[178].body == nil and ns.db.chars["Player-0-Ann"].shadow[178].body, "the synced list: a macro slot without its body (the local record keeps it)")
check(Actions.Clear(FIRST) and macroNamed("FCT:Sit"), "a macro only in a shadow slot counts as used")
check(A.Shadow("FT", "T", { id = "spellgroup:Holy Light", name = "Holy Light" }) == 179 and bars()[179].id == 10328, "changed entry: replaced in its own slot")
check(A.CurrentId(179) == "spellgroup:Holy Light", "highest rank tracked in the shadow slot")
book[#book + 1] = { spellID = 25292, name = "Holy Light", subName = "Rank 6" }
ns.Fire("SPELLS_CHANGED")
check(bars()[179].id == 25292 and A.ShadowSlot("FT", "T", "spellgroup:Holy Light") == 179, "new rank: still the addon's slot")
-- The player puts something else there: given up as is, a new slot taken.
bars()[179] = { kind = "spell", id = 116 }
check(A.ShadowSlot("FT", "T", "spellgroup:Holy Light") == nil, "foreign change noticed")
check(A.Shadow("FT", "T", { id = "spellgroup:Holy Light", name = "Holy Light" }) == 177 and bars()[179].id == 116, "foreign slot kept, next free one used")
check(A.ShadowState() == "178,177", "state lists the slots in use")
-- An emptied slot is filled again in place.
bars()[177] = nil
check(A.Shadow("FT", "T", { id = "spellgroup:Holy Light", name = "Holy Light" }) == 177, "emptied slot: re-placed")
-- Release clears the addon's own slot, and only lets go of a changed one.
check(A.ReleaseShadow("FB", "T") and bars()[178] == nil and not macroNamed("FCT:Sit"), "release: cleared, its macro deleted")
check(placed[178] == nil and placed[177] and placed[177].holds:find("^spell:"), "the synced list: a released slot leaves it")
bars()[177] = { kind = "spell", id = 116 }
check(A.ReleaseShadow("FT", "T") and bars()[177].id == 116 and A.ShadowState() == "none", "release of a changed slot: left as is")
check(placed[177] == nil and placed[179] == nil, "the synced list: a slot the player changed leaves it")
check(A.ReleaseShadow("DU", "L"), "release without a slot: fine")
-- Gamepad storage is never used, even inside the range.
C_GamepadUI.IsValidGamepadActionStorageSlotIndex = function(slot) return slot == 178 end
check(A.Shadow("FR", "T", { id = "spell:133", name = "Fireball" }) == 176, "gamepad storage slot skipped")
C_GamepadUI.IsValidGamepadActionStorageSlotIndex = nil
A.ReleaseShadow("FR", "T")
-- Full range: a reason, nothing placed.
local filled = {}
for slot = 145, 180 do
	if not bars()[slot] then
		bars()[slot] = { kind = "spell", id = 116 }
		filled[#filled + 1] = slot
	end
end
ok, err = A.Shadow("FR", "T", { id = "spell:133", name = "Fireball" })
check(not ok and err:find("No free action slot for Fireball"), "full: reason")
for _, slot in ipairs(filled) do bars()[slot] = nil end
bars()[180], bars()[179], bars()[177] = nil, nil, nil
cursor = { kind = "item" }
ok, err = A.Shadow("FR", "T", { id = "spell:133", name = "Fireball" })
check(not ok and err:find("Put down"), "held cursor: refused")
cursor = nil
check(not A.Shadow("FR", "T", { id = "spell:999", name = "Gone" }), "unknown id: refused")

-- Two cells with the same action share one slot; the slot is cleared only when the last one leaves. A cell whose entry
-- changes in a shared slot moves to its own slot (the other keeps its action), and one whose new entry another cell's
-- slot already holds joins that slot.
for slot = 145, 180 do bars()[slot] = nil end
local own = ns.db.chars["Player-0-Ann"].shadow
local fire = { id = "spell:133", name = "Fireball" }
local usedBefore = A.ShadowCapacity()
check(A.Shadow("FB", "T", fire) == 180 and A.Shadow("FR", "L", fire) == 180 and #own[180].users == 2 and not bars()[179], "shared: the second cell with Fireball uses the first one's slot")
check(A.ShadowSlot("FR", "L", "spell:133") == 180 and A.ShadowCapacity() == usedBefore + 1 and A.ShadowState() == "180", "shared: read back per cell, counted once")
check(A.ReleaseShadow("FB", "T") and bars()[180].id == 133 and A.ShadowSlot("FR", "L", "spell:133") == 180 and A.ShadowSlot("FB", "T", "spell:133") == nil, "shared: releasing one cell keeps the slot for the other")
check(A.ReleaseShadow("FR", "L") and bars()[180] == nil and own[180] == nil, "shared: releasing the last one clears it")
assert(A.Shadow("FB", "T", fire) == 180 and A.Shadow("FR", "L", fire) == 180)
check(A.Shadow("FB", "T", { id = "spell:116", name = "Arcane Missiles" }) == 179 and bars()[180].id == 133 and bars()[179].id == 116 and #own[180].users == 1 and own[180].users[1].code == "FR", "shared: a new entry moves its cell to a slot of its own")
check(A.Shadow("FB", "T", fire) == 180 and bars()[179] == nil and #own[180].users == 2, "shared: an entry another cell's slot holds joins it, the old slot cleared")
bars()[180] = nil
check(A.Shadow("FR", "L", fire) == 180 and bars()[180].id == 133 and #own[180].users == 2, "shared: an emptied slot is placed again for both")
A.ReleaseShadow("FB", "T")
A.ReleaseShadow("FR", "L")
check(bars()[180] == nil and next(own) == nil, "shared: all given back")

-- The list repaired once per table: bad entries go; slots held before the list existed join it.
W.char = "Cid"
ns.db.chars["Player-0-Cid"] = { shadow = { [170] = { code = "FB", layer = "T", id = "spell:133", holds = "spell:133" } }, placed = { [160] = { holds = 5 }, [161] = "x", [162] = { holds = "spell:1", body = "/say a long macro body" }, [163] = { holds = "spell:116", at = 7 } } }
bars()[170] = { kind = "spell", id = 133 }
check(A.ShadowSlot("FB", "T", "spell:133") == 170, "repair: an old record still reads")
local migrated = ns.db.chars["Player-0-Cid"].shadow[170]
check(migrated.code == nil and migrated.id == nil and #migrated.users == 1 and migrated.users[1].code == "FB" and migrated.users[1].layer == "T" and migrated.users[1].id == "spell:133" and migrated.holds == "spell:133", "repair: the one-cell record became one user")
ns.db.chars["Player-0-Cid"].shadow[171] = { users = { { code = 3 } } }
A.ShadowState()
check(ns.db.chars["Player-0-Cid"].shadow[171] == nil, "repair: a record without a good user goes")
local cid = ns.db.chars["Player-0-Cid"].placed
check(cid[160] == nil and cid[161] == nil and cid[162].holds == "spell:1" and cid[162].body == nil and cid[163].at == 7 and cid[170] and cid[170].holds == "spell:133" and cid[170].at == 0, "repair: bad entries dropped, a held slot joins the list (oldest)")
bars()[170] = nil
W.char = "Ann"

-- Changes the game or the player makes in place keep the slot the addon's: the same spell at another rank, the same
-- macro renamed. Only something different is a foreign change.
local rankSlot = A.Shadow("FR", "T", { id = "spell:635", name = "Holy Light (Rank 1)" })
check(rankSlot == 180 and bars()[180].id == 635, "a fixed rank placed")
bars()[180] = { kind = "spell", id = 639 }
check(A.ShadowSlot("FR", "T", "spell:635") == 180 and ns.db.chars["Player-0-Ann"].shadow[180].holds == "spell:639", "the game moved its rank: still ours, holds follows")
check(A.Shadow("FR", "T", { id = "spell:635", name = "Holy Light (Rank 1)" }) == 180 and not bars()[179], "no new slot taken")
bars()[180] = { kind = "spell", id = 635 }
check(A.ShadowSlot("FR", "T", "spell:635") == nil, "a lower rank put back by the player: not ours")
check(A.Shadow("FR", "T", { id = "spell:635", name = "Holy Light (Rank 1)" }) == 180 and bars()[180].id == 635 and not bars()[179], "the slot holds exactly what the cell wants: taken back, no new slot")
check(A.ReleaseShadow("FR", "T") and bars()[180] == nil, "released: cleared as ours")
local mine = account[#account]
check(mine.name == "Mine" and A.Shadow("FB", "T", { id = "macro:Mine", name = "Mine" }) == 180, "the player's macro placed")
mine.name = "Mine renamed"
check(A.ShadowSlot("FB", "T", "macro:Mine") == 180 and ns.db.chars["Player-0-Ann"].shadow[180].holds == "macro:Mine renamed", "renamed: still ours")
bars()[180] = { kind = "spell", id = 116 }
check(A.ShadowSlot("FB", "T", "macro:Mine") == nil and A.Shadow("FB", "T", { id = "spell:133", name = "Fireball" }) == 179 and bars()[180].id == 116, "something different: foreign, left as is")
A.ReleaseShadow("FB", "T")
bars()[180] = nil
-- Spell macros report their spell as the id: another macro casting the same spell isn't ours.
mine.name, mine.spell, mine.body = "Mine", 133, "/cast Fireball"
check(A.Shadow("FB", "T", { id = "macro:Mine", name = "Mine" }) == 180, "a spell macro placed")
local other = { name = "Other", icon = 1, body = "/cast Fireball\n/say hi", spell = 133 }
account[#account + 1] = other
bars()[180] = { kind = "macro", macro = other }
check(A.ShadowSlot("FB", "T", "macro:Mine") == nil and bars()[180].macro == other, "another spell macro with the same spell id: foreign")
A.ReleaseShadow("FB", "T")
bars()[180], mine.spell = nil, nil
table.remove(account)
mine.name = "Mine"

-- Hardening: a slot that only looked empty keeps the player's action; nothing is deleted.
local realHas = C_ActionBar.HasAction
C_ActionBar.HasAction = function(slot) return slot ~= 180 and realHas(slot) end
bars()[180] = { kind = "spell", id = 116 }
ok, err = A.Shadow("DL", "L", { id = "spell:133", name = "Fireball" })
C_ActionBar.HasAction = realHas
check(not ok and err:find("isn't free") and bars()[180].id == 116 and cursor == nil and A.ShadowState() == "none", "put back, aborted, not owned")
bars()[180] = nil

-- AddOns: addon key bindings. WellMet's CLICK binding (as in its Bindings.xml), a Lua binding, a raw category; Blizzard's
-- own, the addon's own and header rows are left out.
local BINDINGS = {
	{ "MOVEFORWARD", "BINDING_HEADER_MOVEMENT" }, { "TOGGLEGAMEMENU" }, { "FOREVERCONTROLLERTWEAKS_TOGGLE", "BINDING_HEADER_FOREVERCONTROLLERTWEAKS" },
	{ "HEADER_BLANK1", "BINDING_HEADER_WELLMET" }, { "CLICK WellMetCast:LeftButton", "BINDING_HEADER_WELLMET" },
	{ "MYADDON_DOTHING", "BINDING_HEADER_MYADDON" }, { "CLICK RawBtn:RightButton", "RawCat" }, { "NEWBLIZZ", "BINDING_HEADER_NEWBLIZZ" },
}
function GetNumBindings() return #BINDINGS end
function GetBinding(i) return BINDINGS[i][1], BINDINGS[i][2] end
local TAINT = {
	BINDING_HEADER_WELLMET = "WellMet", ["BINDING_NAME_CLICK WellMetCast:LeftButton"] = "WellMet",
	BINDING_HEADER_MYADDON = "MyAddon", BINDING_NAME_MYADDON_DOTHING = "MyAddon", BINDING_HEADER_FOREVERCONTROLLERTWEAKS = "ForeverControllerTweaks",
}
function issecurevariable(name) if TAINT[name] then return false, TAINT[name] end return true end
BINDING_HEADER_MOVEMENT, BINDING_HEADER_NEWBLIZZ, BINDING_HEADER_WELLMET, BINDING_HEADER_MYADDON = "Movement", "New Blizzard", "WellMet", "My Addon"
_G["BINDING_NAME_CLICK WellMetCast:LeftButton"] = "Buff the next nearby player (WellMet)"
BINDING_NAME_MYADDON_DOTHING = "Do the thing"
C_AddOns = { GetAddOnMetadata = function(addon, field) if addon == "WellMet" and field == "IconTexture" then return "Interface\\AddOns\\WellMet\\Icons\\Icon" end end }
local before = Actions.Catalog()
ns.Fire("UPDATE_BINDINGS")
local addons = select(2, find(Actions.Catalog(), "addon:CLICK WellMetCast:LeftButton"))
check(Actions.Catalog() ~= before and addons and addons.name == "AddOns" and Actions.Catalog()[#Actions.Catalog()] == addons, "AddOns: the last category, rebuilt on UPDATE_BINDINGS")
local listed = {}
for i, e in ipairs(addons.entries) do listed[i] = e.name end
check(table.concat(listed, "|") == "My Addon: Do the thing|RawCat: RawBtn|WellMet: Buff the next nearby player (WellMet)", "addon bindings only, grouped by header, by name")
local wellmet = entry("addon:CLICK WellMetCast:LeftButton")
check(wellmet.kind == "game" and wellmet.payload.text == "/click WellMetCast LeftButton 1\n/click WellMetCast LeftButton" and wellmet.payload.macro == "FCT:WellMetCast", "CLICK binding: a FCT: macro sending press and release, like the key")
check(wellmet.icon == "Interface\\AddOns\\WellMet\\Icons\\Icon" and entry("addon:CLICK RawBtn:RightButton").icon:find("INV_Misc_Gear_08"), "the addon's TOC icon, else a generic one")
check(entry("addon:CLICK RawBtn:RightButton").payload.text == "/click RawBtn RightButton 1\n/click RawBtn RightButton", "its mouse button kept")
local lua = entry("addon:MYADDON_DOTHING")
check(lua.disabled and lua.note == "needs a key binding" and lua.kind == "binding", "a Lua binding: listed, disabled")
check(not find(Actions.Catalog(), "addon:NEWBLIZZ") and not find(Actions.Catalog(), "addon:FOREVERCONTROLLERTWEAKS_TOGGLE") and not find(Actions.Catalog(), "addon:MOVEFORWARD"), "Blizzard's and the addon's own left out")
check(Actions.Assign(FIRST + 9, wellmet) and macroNamed("FCT:WellMetCast") and Actions.CurrentId(FIRST + 9) == wellmet.id, "assigned: registered FCT: macro, CurrentId knows it")
check(Actions.TextFor(wellmet.id) == wellmet.payload.text, "routed text")
ok, err = Actions.Assign(FIRST + 10, lua)
check(not ok and err == "needs a key binding" and not bars()[FIRST + 10], "the Lua binding is refused on a slot")
Actions.Clear(FIRST + 9)
check(not macroNamed("FCT:WellMetCast"), "cleared: its macro deleted")
local cached = Actions.Catalog()
ns.Fire("ADDON_LOADED", "SomeAddon")
check(Actions.Catalog() ~= cached, "rebuilt on ADDON_LOADED")

-- Combat: nothing changes.
W.combat = true
ok, err = Actions.Assign(FIRST + 5, entry("game:sit"))
check(not ok and err:find("out of combat") and not macroNamed("FCT:Sit"), "combat: refused, no macro")
ok, err = Actions.Shadow("FR", "T", { id = "spell:133", name = "Fireball" })
check(not ok and err:find("out of combat") and not bars()[180], "combat: no shadow slot")
W.combat = false

-- Macros from before the rename: the registered PS: ones take FCT: once per character, out of combat, and stay on
-- their bars; the player's own PS: macro is never touched.
CreateMacro("PS:Bags", 1, "/click MainMenuBarBackpackButton", false)
CreateMacro("PS:Mine", 1, "/say mine", false)
CreateMacro("PS:Sit", 1, "/sit", true)
ns.db.macros["PS:Bags"] = { id = "game:bags", chars = { ["Player-0-Ann"] = true } }
ns.db.chars["Player-0-Ann"].macros["PS:Sit"] = { id = "game:sit" }
bars()[FIRST + 6] = { kind = "macro", macro = account[macroNamed("PS:Bags")] }
ns.db.chars["Player-0-Ann"].macroPrefixDone = nil
W.combat = true
ns.Fire("PLAYER_ENTERING_WORLD")
check(macroNamed("PS:Bags") and ns.db.macros["PS:Bags"], "rename: not in combat")
W.combat = false
ns.Fire("PLAYER_REGEN_ENABLED")
check(macroNamed("FCT:Bags") and not macroNamed("PS:Bags") and ns.db.macros["FCT:Bags"].id == "game:bags" and ns.db.macros["PS:Bags"] == nil, "rename: account macro and its registry key")
check(macroNamed("FCT:Sit", charList()) and ns.db.chars["Player-0-Ann"].macros["FCT:Sit"].id == "game:sit" and ns.db.chars["Player-0-Ann"].macros["PS:Sit"] == nil, "rename: character macro too")
check(macroNamed("PS:Mine") and not macroNamed("FCT:Mine"), "rename: an unregistered PS: macro is the player's, untouched")
check(Actions.CurrentId(FIRST + 6) == "game:bags" and ns.db.chars["Player-0-Ann"].macroPrefixDone, "rename: still on its bar, once per character")
ns.db.macros["PS:Again"] = { id = "game:sit", chars = {} }
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.db.macros["PS:Again"], "rename: runs once")
ns.db.macros["PS:Again"] = nil
local macroNames, unique = {}, true
for _, category in ipairs(Actions.Catalog()) do
	for _, e in ipairs(category.entries) do
		local name = e.kind == "game" and not e.id:find("^addon:") and e.payload.macro
		if name then
			unique = unique and not macroNames[name] and #name <= 16 and name:sub(1, 4) == "FCT:"
			macroNames[name] = true
		end
	end
end
check(unique and macroNames["FCT:LeaveVehicle"], "every game macro name fits 16 characters, uncut and unique")
bars()[FIRST + 6] = nil
for _, name in ipairs({ "FCT:Bags", "PS:Mine" }) do table.remove(account, macroNamed(name)) end
table.remove(charList(), macroNamed("FCT:Sit", charList()))
ns.db.macros["FCT:Bags"], ns.db.chars["Player-0-Ann"].macros["FCT:Sit"] = nil, nil

-- Every slot write holds off applies: UPDATE_MACROS (and the catalog message) fire inside it, synchronously.
local busyInside
ns.On("FCT_CATALOG_CHANGED", function() if busyInside == nil then busyInside = Actions.Busy() end end)
check(Actions.Assign(FIRST + 5, entry("game:sit")) and busyInside == true and not Actions.Busy(), "busy while the macro is made, free after")
busyInside = nil
check(Actions.Clear(FIRST + 5) and busyInside == true and not Actions.Busy(), "busy while it is deleted")
local realPickup = PickupAction
PickupAction = function() error("boom") end
bars()[FIRST + 5] = { kind = "spell", id = 133 }
check(not pcall(Actions.Clear, FIRST + 5) and not Actions.Busy(), "an error inside a write doesn't leave it busy")
PickupAction = realPickup
bars()[FIRST + 5] = nil

-- Lost settings: the registries and shadow records are gone, and earlier writes left "FCT:Bags" .. "FCT:Bags 8", all with
-- the addon's body, on the crossbar, on bars 6-8 and on another bar. The take-back keeps the one on the crossbar,
-- points the other slots at it, deletes the copies nothing else holds, keeps (unregistered) the one on another bar,
-- gives one bars 6-8 slot back to the routed cell that wants Backpack and clears the rest. A player's macro of the
-- same name pattern with another body, and two macros sharing one name, stay untouched.
local BAGS = "/click MainMenuBarBackpackButton"
local char = ns.db.chars["Player-0-Ann"]
ns.db.macros, char.macros, char.shadow = {}, {}, {}
for slot = 145, 180 do bars()[slot] = nil end
local copies = {}
for n = 1, 8 do
	local name = n == 1 and "FCT:Bags" or "FCT:Bags " .. n
	account[#account + 1] = { name = name, body = BAGS }
	copies[n] = account[#account]
end
account[#account + 1] = { name = "FCT:Bags 9", body = "/say my own" }
account[#account + 1] = { name = "FCT:Wave", body = "/wave" }
account[#account + 1] = { name = "FCT:Wave", body = "/wave" }
local function slotMacro(n) return { kind = "macro", macro = copies[n] } end
bars()[FIRST + 20] = slotMacro(3)
bars()[180], bars()[179], bars()[178] = slotMacro(5), slotMacro(6), slotMacro(7)
bars()[12] = slotMacro(8)
assert(ns.Face.SetCellEntry("FT", "T", (entry("game:bags"))))
local done = A.AdoptLeftovers()
check(done and done.kept == 1 and registered("FCT:Bags 3") and registered("FCT:Bags 3").id == "game:bags", "leftovers: the copy on the crossbar kept and registered")
check(done.deleted == 6 and not macroNamed("FCT:Bags") and not macroNamed("FCT:Bags 2") and not macroNamed("FCT:Bags 7") and macroNamed("FCT:Bags 3"), "leftovers: the copies nothing else holds deleted")
check(macroNamed("FCT:Bags 8") and not registered("FCT:Bags 8") and bars()[12].macro.name == "FCT:Bags 8", "leftovers: a copy on another bar kept as it is, unregistered")
check(bars()[180].macro.name == "FCT:Bags 3" and char.shadow[180] and char.shadow[180].users[1].code == "FT" and A.ShadowSlot("FT", "T", "game:bags") == 180, "leftovers: one bars 6-8 slot given back to the cell that wants it, holding the kept copy")
check(bars()[179] == nil and bars()[178] == nil and done.cleared == 2 and done.adopted == 1, "leftovers: the other bars 6-8 slots freed")
local mine9, wave = select(2, macroNamed("FCT:Bags 9")), 0
for _, m in ipairs(account) do if m.name == "FCT:Wave" then wave = wave + 1 end end
check(mine9 and mine9.body == "/say my own" and not registered("FCT:Bags 9") and wave == 2, "leftovers: another body, or a name two macros share: untouched")
local again = A.AdoptLeftovers()
check(again.kept + again.deleted + again.moved + again.adopted + again.cleared == 0, "leftovers: a second run finds nothing")
assert(ns.Face.SetCellEntry("FT", "T", nil))
A.ReleaseShadow("FT", "T")
bars()[FIRST + 20], bars()[12] = nil, nil

-- The game keeps bodies with a trailing newline, and addons' CLICK bindings leak the same way: both are taken back.
local CAST = entry("addon:CLICK WellMetCast:LeftButton").payload.text
ns.db.macros = {}
account[#account + 1] = { name = "FCT:Bags", body = BAGS .. "\n" }
bars()[FIRST + 24] = { kind = "macro", macro = account[#account] }
account[#account + 1] = { name = "FCT:WellMetCast", body = CAST .. "\n" }
account[#account + 1] = { name = "FCT:WellMetCas 2", body = CAST .. "\n" }
account[#account + 1] = { name = "FCT:WellMetCas 3", body = CAST }
bars()[FIRST + 21] = { kind = "macro", macro = account[#account - 1] }
done = A.AdoptLeftovers()
check(registered("FCT:WellMetCas 2") and registered("FCT:WellMetCas 2").id == "addon:CLICK WellMetCast:LeftButton" and not macroNamed("FCT:WellMetCast") and not macroNamed("FCT:WellMetCas 3"), "leftovers: an addon's CLICK macros too, one kept, the rest deleted")
check(registered("FCT:Bags") and select(2, macroNamed("FCT:Bags")).body == BAGS .. "\n" and not macroNamed("FCT:Bags 3") and not macroNamed("FCT:Bags 8"), "leftovers: a body with a trailing newline still matches (kept on its slot, the older copies deleted)")
bars()[FIRST + 21], bars()[FIRST + 24] = nil, nil

-- The leak itself: a write that finds no registry entry for its action but an unregistered macro of ours (our name, our
-- text, the only one of that name) uses and registers it, never "FCT:Sit 2" beside it. A player's macro of our name
-- with other text is left alone and the next name taken.
ns.db.macros = {}
account[#account + 1] = { name = "FCT:Sit", body = "/sit\n" }
account[#account + 1] = { name = "FCT:Stand", body = "/say mine" }
check(A.Assign(FIRST + 22, entry("game:sit")) and bars()[FIRST + 22].macro.name == "FCT:Sit" and registered("FCT:Sit") and not macroNamed("FCT:Sit 2"), "leak: the lost FCT:Sit used and registered again, no FCT:Sit 2")
check(A.Assign(FIRST + 23, entry("game:stand")) and bars()[FIRST + 23].macro.name == "FCT:Stand 2" and select(2, macroNamed("FCT:Stand")).body == "/say mine", "leak: a player's FCT:Stand with other text stays; ours is FCT:Stand 2")
-- A cleanup while the macro list reads empty (early at login) drops nothing.
local numMacros = GetNumMacros
GetNumMacros = function() return 0, 0 end
A.Clear(FIRST + 22)
GetNumMacros = numMacros
check(registered("FCT:Sit") and macroNamed("FCT:Sit"), "leak: a cleanup with the macro list not loaded keeps the registry")
A.Clear(FIRST + 22)
A.Clear(FIRST + 23)
check(not registered("FCT:Sit") and macroNamed("FCT:Sit") and not macroNamed("FCT:Stand 2") and macroNamed("FCT:Stand"), "leak: unused again, one made here is deleted; one taken over (maybe another machine's) is only let go")

-- /fct cleanup: runs it now and prints the counts, or why it can't.
ns.UI = { L = { CLEANUP_DONE = "cleanup: %d %d %d %d %d", CLEANUP_CANT = "cleanup can't run now: %s.", CLEANUP_WHY = { combat = "you're in combat" } } }
account[#account + 1] = { name = "FCT:Bags 4", body = BAGS }
SlashCmdList.FOREVERCONTROLLERTWEAKS("cleanup")
local bagsLeft = 0
for _, m in ipairs(account) do if m.body:gsub("%s+$", "") == BAGS then bagsLeft = bagsLeft + 1 end end
check(printed[#printed]:find("cleanup: %d+ %d+ %d+ %d+ %d+$") and bagsLeft <= 1 and not macroNamed("FCT:Bags 4"), "/fct cleanup: runs, prints the counts, one Backpack macro at most")
W.combat = true
SlashCmdList.FOREVERCONTROLLERTWEAKS("cleanup")
W.combat = false
check(printed[#printed]:find("you're in combat", 1, true), "/fct cleanup: in combat, says why")
ns.UI = nil

-- Two machines: macros and bars follow the account, the SavedVariables (registry, shadow records) don't. On machine B a
-- cell takes back the bars 6-8 slot machine A placed its action in (the same spell, or our macro for that game action,
-- registered on the way) instead of a new slot; a player's macro of our name with other text is no match. A macro
-- taken over that way is never deleted when unused here: an alt on machine A may have it on its bars.
ns.db.macros, char.shadow = {}, {}
for slot = 145, 180 do bars()[slot] = nil end
local _, sit = macroNamed("FCT:Sit")
bars()[175], bars()[174] = { kind = "spell", id = 133 }, { kind = "macro", macro = sit }
bars()[173] = { kind = "macro", macro = select(2, macroNamed("FCT:Stand")) }
check(A.Shadow("FB", "T", { id = "spell:133", name = "Fireball" }) == 175 and char.shadow[175].users[1].code == "FB", "two machines: the slot already holding Fireball taken back")
check(A.Shadow("FR", "T", (entry("game:sit"))) == 174 and registered("FCT:Sit") and registered("FCT:Sit").adopted and not macroNamed("FCT:Sit 2"), "two machines: the slot holding our FCT:Sit taken back, the macro registered")
local standSlot = A.Shadow("DU", "T", (entry("game:stand")))
check(standSlot ~= 173 and standSlot == 180 and bars()[173].macro.body == "/say mine", "two machines: a player's FCT:Stand is no match; an empty slot taken")
A.ReleaseShadow("FB", "T")
A.ReleaseShadow("FR", "T")
A.ReleaseShadow("DU", "T")
check(bars()[175] == nil and bars()[174] == nil and macroNamed("FCT:Sit") and not registered("FCT:Sit"), "two machines: released, the taken-over macro kept, only let go")
bars()[173] = nil

-- The synced list (slots the addon placed on any machine) on a machine whose records don't hold them: a slot whose
-- action a cell wants and has no slot for goes to that cell; one no binding of this character needs on any pad or touch
-- bar is freed, only while sync is in step. A slot the list doesn't name, or no longer matches, is never touched.
ns.db.macros, char.shadow, char.placed = {}, {}, {}
for slot = 145, 180 do bars()[slot] = nil end
local inStep, realInStep = false, Sync.InStep
Sync.InStep = function() return inStep end
ns.Touch = { ShadowNeeds = function() return { { code = "TLT", layer = 1, id = "spell:116" } } end }
assert(ns.Face.SetCellEntry("FT", "T", (entry("spell:133"))))
char.cells["045e/0b13"] = { FB = { R = { id = "item:111", name = "Badge", kind = "item" } } }
char.shadow[160] = { code = "TLT", layer = 1, id = "spell:116", holds = "spell:116" }
bars()[160] = { kind = "spell", id = 116 }
bars()[172], bars()[171], bars()[170], bars()[169] = { kind = "spell", id = 133 }, { kind = "spell", id = 20 }, { kind = "item", id = 111 }, { kind = "spell", id = 116 }
bars()[168], bars()[167] = { kind = "spell", id = 20 }, { kind = "spell", id = 21 }
for slot, holds in pairs({ [172] = "spell:133", [171] = "spell:20", [170] = "item:111", [169] = "spell:116", [167] = "spell:133" }) do char.placed[slot] = { holds = holds, at = 1 } end
done = A.AdoptLeftovers()
check(char.shadow[172] and char.shadow[172].users[1].code == "FT" and A.ShadowSlot("FT", "T", "spell:133") == 172 and done.adopted == 1, "synced list: the cell that wants Fireball gets the slot another machine placed")
check(bars()[171] and char.placed[171] and done.cleared == 0, "synced list: sync not in step: nothing is freed")
check(char.placed[167] == nil and bars()[167].id == 21, "synced list: an entry the slot no longer matches is dropped, the slot left as it is")
local listed = {}
for _, item in ipairs(A.ForeignShadowSlots()) do listed[item.slot] = true end
check(listed[168] and listed[167] and listed[171] and listed[170] and listed[169] and not listed[172], "free up: sync not in step: the synced slots are listed, nothing else frees them")
inStep = true
listed = {}
for _, item in ipairs(A.ForeignShadowSlots()) do listed[item.slot] = true end
check(listed[168] and listed[167] and not listed[171] and not listed[170] and not listed[169], "free up: in step: the synced slots are the addon's, not the player's")
done = A.AdoptLeftovers()
check(bars()[171] == nil and char.placed[171] == nil and done.cleared == 1, "synced list: in step, a slot no binding needs is freed")
check(bars()[170] and char.placed[170], "synced list: a binding on another pad keeps its slot")
check(bars()[169] and char.placed[169], "synced list: a touch button's action keeps its slot")
check(bars()[168].id == 20 and bars()[167].id == 21, "synced list: slots the list doesn't name are never cleared")
Sync.InStep, ns.Touch = realInStep, nil
assert(ns.Face.SetCellEntry("FT", "T", nil))
A.ReleaseShadow("FT", "T")
char.cells["045e/0b13"], char.shadow, char.placed = nil, {}, {}
for slot = 145, 180 do bars()[slot] = nil end

-- "Free up slots": the player's own actions on bars 6-8 are listed (top down, with name and icon), never the addon's own
-- slots; clearing takes exactly the listed slots that still hold what was listed.
C_ActionBar.GetActionTexture = function(slot) return bars()[slot] and 77 or nil end
local ownSlot = A.Shadow("FB", "T", { id = "spell:133", name = "Fireball" })
bars()[170], bars()[160] = { kind = "spell", id = 133 }, { kind = "item", id = 111 }
local foreign = A.ForeignShadowSlots()
check(#foreign == 2 and foreign[1].slot == 170 and foreign[1].name == "Fireball" and foreign[1].icon == 77 and foreign[2].slot == 160 and foreign[2].name == "Badge", "free up: the player's actions on bars 6-8, top down, named")
for _, item in ipairs(foreign) do check(item.slot ~= ownSlot, "free up: the addon's own slot is never listed") end
bars()[170] = { kind = "spell", id = 116 }
check(A.ClearForeign(foreign) == 1 and bars()[170].id == 116 and bars()[160] == nil, "free up: a slot changed since the list is left as it is")
check(A.ClearForeign(A.ForeignShadowSlots()) == 1 and bars()[170] == nil and bars()[ownSlot] and #A.ForeignShadowSlots() == 0, "free up: cleared; the addon's slot kept")
W.combat = true
check(select(2, A.ClearForeign({ { slot = ownSlot, holds = "x" } })) and bars()[ownSlot], "free up: refused in combat")
W.combat = false
A.ReleaseShadow("FB", "T")
C_ActionBar.GetActionTexture = nil

-- /fct release: every owned slot given back, every registered FCT: macro deleted, nothing placed until /reload.
assert(A.Shadow("FB", "T", { id = "spell:133", name = "Fireball" }) == 180)
assert(Actions.Assign(FIRST + 5, entry("game:sit")) and macroNamed("FCT:Sit"))
local realDelete, busyAtDelete = DeleteMacro, nil
DeleteMacro = function(i)
	busyAtDelete = Actions.Busy()
	realDelete(i)
end
SlashCmdList.FOREVERCONTROLLERTWEAKS("release")
DeleteMacro = realDelete
check(busyAtDelete and not Actions.Busy(), "release deletes its macros as a slot write (Busy while it runs)")
check(not bars()[180] and next(ns.db.chars["Player-0-Ann"].shadow) == nil and not macroNamed("FCT:Sit") and next(ns.db.macros) == nil, "release: slots cleared, FCT: macros deleted")
check(printed[#printed]:find("gave back 1 action slots and deleted 1 FCT: macros", 1, true), "release: one chat line")
ok, err = A.Shadow("FB", "T", { id = "spell:133", name = "Fireball" })
check(not ok and err:find("/reload") and not bars()[180], "released: no slot placed until /reload")

-- Sync macros hold settings: never in the picker. A player's macro of that name with another body is theirs.
account[#account + 1] = { name = "FCT:Sync 1", icon = "INV_Misc_Note_01", body = "#FCT1 1/1 abcdef 0A0B\n" }
account[#account + 1] = { name = "FCT:Sync 2", icon = "x", body = "/say mine" }
ns.Fire("UPDATE_MACROS")
check(not find(Actions.Catalog(), "macro:FCT:Sync 1") and find(Actions.Catalog(), "macro:FCT:Sync 2"), "sync macros: not in the picker, a player's FCT:Sync 2 is")
-- /fct release deletes the sync macros too and turns sync off here.
SlashCmdList.FOREVERCONTROLLERTWEAKS("release")
check(not macroNamed("FCT:Sync 1") and macroNamed("FCT:Sync 2") and ns.db.sync.on == false, "release: sync macros deleted, the player's kept, sync off")
check(printed[#printed]:find("deleted 1 FCT: macros", 1, true), "release: the sync macro counted")

io.stdout:write(("actions_spec: %d checks passed\n"):format(checks))
