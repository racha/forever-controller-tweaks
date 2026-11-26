-- Stubbed WoW check of the action rings: lua tests/rings_spec.lua
-- Rings.lua with the real Core, Layout, Face, Actions and Touch: the stick -> slot pick for 4 and 8 slots and the dead
-- zone, the per-slot attributes for every entry kind, the ring's restricted snippets run in a strict stub environment
-- (open, release pick, toggle, slot tap, catcher, guard), a ring on a routed face cell and on a touch button, in
-- combat too, Healer mode (kinds, attributes, units, pick skips, native copy and its undo, touch), the native sticks
-- (pass and block keep only the aiming stick's twin from the game, open and after the close), deleting a ring
-- clearing every binding, the db repair, and the mouse on an open ring (hover, tooltip, click, a held ring's release)
-- with View.lua loaded.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local W = { combat = false, conds = {}, held = {}, sticks = {}, bindings = {}, prio = {}, cvars = {}, char = "Ann" }

local function compile(body, env, name)
	if setfenv then return setfenv(assert(loadstring(body, name)), env) end
	return assert(load(body, name, "t", env))
end
local function newtable(...) return { ... } end
local function renv(control)
	return setmetatable({ newtable = newtable, format = string.format, control = control }, { __index = _G })
end
-- The ring frame's environment holds only what WoW's restricted one gives these snippets: a missing name fails.
local RESTRICTED = { math = math, select = select, tostring = tostring, tonumber = tonumber, format = string.format, GetGamePadState = function() return GetGamePadState() end }
-- Units for Healer mode: W.units[token] = "friend" | "dead" | "hostile", missing when absent.
W.units = {}
function RESTRICTED.UnitExists(unit) return W.units[unit] ~= nil end
function RESTRICTED.PlayerCanAssist(unit) return W.units[unit] == "friend" or W.units[unit] == "dead" end
local function strictEnv()
	return setmetatable({}, { __index = function(_, k)
		local v = RESTRICTED[k]
		if v == nil then error("restricted environment has no " .. tostring(k), 2) end
		return v
	end })
end
local function run(env, sig, body, ...) return compile("local " .. sig .. " = ...\n" .. body, env, "snippet")(...) end
-- What WoW's restricted closures pass on (RestrictedExecution.lua: def(SelfScrub(self), scrub(...))): nil, booleans,
-- numbers and strings; anything else, a frame handle included, arrives as nil.
local function scrub(...)
	local n, out = select("#", ...), { ... }
	for i = 1, n do
		local kind = type(out[i])
		if kind ~= "nil" and kind ~= "boolean" and kind ~= "number" and kind ~= "string" then out[i] = nil end
	end
	return (table.unpack or unpack)(out, 1, n)
end
-- RunAttribute's closure: self, then the caller's scrubbed arguments as ...
local function runArgs(env, body, self, ...)
	return compile("local self = ...\nreturn (function(...)\n" .. body .. "\nend)(select(2, ...))", env, "snippet")(self, ...)
end
local function secure(fn, ...)
	local was = W.secure
	W.secure = true
	local results = { fn(...) }
	W.secure = was
	return (table.unpack or unpack)(results)
end

local frames = {}
local Frame = {}
Frame.__index = function(_, k) return Frame[k] or (type(k) == "string" and k:match("^%u") and function() end) or nil end
local function frame(name, template, parent)
	local f = setmetatable({ name = name, attrs = {}, scripts = {}, shown = true, parent = parent, template = template, protected = template and template:find("Secure") ~= nil }, Frame)
	if name then
		_G[name] = f
		frames[name] = f
	end
	f.env = name == "ForeverControllerTweaksRing" and strictEnv() or renv(f)
	return f
end
function Frame:CreateTexture() return frame(nil, nil, self) end
function Frame:RegisterForClicks(...) self.clicks = table.concat({ ... }, ",") end
function Frame:SetAllPoints(target) self.anchor = target end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:GetParent() return self.parent end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:HookScript(s, fn)
	self.hooks = self.hooks or {}
	self.hooks[s] = self.hooks[s] or {}
	table.insert(self.hooks[s], fn)
end
local function hooked(f, s, ...) for _, fn in ipairs(f.hooks and f.hooks[s] or {}) do fn(f, ...) end end
function Frame:Show() if not self.shown then self.shown = true; hooked(self, "OnShow") end end
function Frame:Hide() if self.shown then self.shown = false; hooked(self, "OnHide") end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetName() return self.name end
function Frame:GetID() return self.id or 0 end
function Frame:SetScript(s, fn) self.scripts[s] = fn end
function Frame:IsProtected() return self.protected end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:GetFrameRef(k) return self.attrs["frameref-" .. k] end
function Frame:SetAttribute(k, v)
	if W.combat and self.protected and not W.secure then error("ADDON_ACTION_BLOCKED SetAttribute " .. k) end
	self.attrs[k] = v
	hooked(self, "OnAttributeChanged", k, v)
	local stateid = k:match("^state%-(.+)")
	local body = stateid and self.attrs["_onstate-" .. stateid]
	if body then secure(run, self.env, "self,stateid,newstate", body, self, stateid, v) end
end
function Frame:Execute(body)
	if W.combat then error("ADDON_ACTION_BLOCKED Execute") end
	secure(run, self.env, "self", body, self)
end
function Frame:RunAttribute(name, ...)
	assert(W.secure, "RunAttribute outside a snippet")
	return scrub(runArgs(self.env, assert(self.attrs[name], "no snippet " .. name), self, scrub(...)))
end
function Frame:WrapScript(target, script, pre, post)
	target.wraps = target.wraps or {}
	target.wraps[script] = { header = self, pre = pre, post = post }
	if script == "OnClick" then target.wrap = target.wraps[script] end
end
-- Priority bindings (an open ring's) beat the routers' plain ones and give them back when cleared.
function Frame:ClearBindings()
	for _, list in ipairs({ W.bindings, W.prio }) do
		for k, v in pairs(list) do if v.owner == self then list[k] = nil end end
	end
end
function Frame:SetBindingClick(priority, key, name, button) (priority and W.prio or W.bindings)[key] = { owner = self, click = name .. ":" .. button } end
function Frame:SetBinding(priority, key, command)
	if W.combat and not W.secure then error("ADDON_ACTION_BLOCKED SetBinding") end
	(priority and W.prio or W.bindings)[key] = { owner = self, command = command }
end
-- What the stick frames are set up with, kept for the checks.
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:EnableGamePadButton(on) self.padButtons = on end
function Frame:EnableGamePadStick(on) self.stickOn = on end
function Frame:SetPropagateKeyboardInput(on) self.propagate = on end
function ClearOverrideBindings(f)
	if W.combat then error("ADDON_ACTION_BLOCKED ClearOverrideBindings") end
	f:ClearBindings()
end

-- A click as the secure button runs it: the wrapped pre-snippet in its header's environment, then (when a message
-- came back) the post-snippet. Returns what the button then fires: "type value" or nil.
local function click(button, down, which, mouse)
	local wrap = button.wrap
	local newButton, message = secure(run, wrap.header.env, "self,button,down", wrap.pre, button, mouse or "LeftButton", down)
	if newButton == false then return false end
	local a = button.attrs
	local actionType = a[which or "type"]
	local fired = actionType and (actionType .. " " .. tostring(a.spell or a.item or a.toy or a.macrotext or a.action))
	if wrap.post and message ~= nil then secure(run, wrap.header.env, "self,message,button,down", wrap.post, button, message, mouse or "LeftButton", down) end
	return fired
end
-- A bound key: press (fires type) or release (fires typerelease, as pressAndHoldAction does).
local function press(key, down)
	local b = assert(W.prio[key] or W.bindings[key], "nothing bound to " .. key)
	local name, mouse = b.click:match("^(.-):(.*)$")
	return click(frames[name], down, down and "type" or "typerelease", mouse)
end

function CreateFrame(_, name, parent, template) return frame(name, template, parent) end
UIParent = frame("UIParent")
function SecureHandlerSetFrameRef(f, label, ref) f.attrs["frameref-" .. label] = ref end

local function evalConditions(values)
	for clause in values:gmatch("[^;]+") do
		local conds, value = clause:match("^%s*(.-)%s*([%w]+)%s*$")
		if conds == "" then return value end
		for c in conds:gmatch("%[([^%]]*)%]") do if W.conds[c] then return value end end
	end
end
local drivers = {}
function RegisterStateDriver(f, state, values)
	if W.combat then error("ADDON_ACTION_BLOCKED RegisterStateDriver") end
	drivers[#drivers + 1] = { f = f, state = state, values = values }
	secure(f.SetAttribute, f, "state-" .. state, evalConditions(values))
end
local function cond(name, on)
	W.conds[name] = on or nil
	for _, d in ipairs(drivers) do
		local v = evalConditions(d.values)
		if d.f.attrs["state-" .. d.state] ~= v then secure(d.f.SetAttribute, d.f, "state-" .. d.state, v) end
	end
end

-- The pad: held buttons and the sticks (1 = left, 2 = right), as GetGamePadState and the mapped state report them.
local INDEX = { PAD1 = 0, PAD2 = 1, PAD3 = 2, PAD4 = 3, PADLSHOULDER = 9, PADRSHOULDER = 10, PADLTRIGGER = 13, PADRTRIGGER = 14 }
function GetGamePadState() return { buttons = W.held, sticks = W.sticks } end
local STICK_NAMES = { [0] = "Movement", [1] = "Camera" }
C_GamePad = {
	ButtonBindingToIndex = function(k) return INDEX[k] end,
	GetDeviceMappedState = function() return { stickCount = 2, buttons = W.held, sticks = W.sticks } end,
	StickIndexToConfigName = function(i) return STICK_NAMES[i] end,
}
local function aim(degrees, length)
	local a = math.rad(degrees)
	W.sticks = { { x = 0, y = 0 }, { x = (length or 1) * math.sin(a), y = (length or 1) * math.cos(a) } }
end
function IsKeyDown() return false end

function GetBindingAction() return "" end
Enum = { BindingContext = { GamepadModeInGameCore = 9 }, SpellBookSpellBank = { Player = 0, Pet = 1 } }
function GetCVar(k) return W.cvars[k] end
function GetCVarBool(k) return W.cvars[k] == "1" end
W.writes = {}
function SetCVar(k, v)
	W.writes[#W.writes + 1] = k .. "=" .. v
	W.cvars[k] = v
	return true
end
function InCombatLockdown() return W.combat end
function GetTime() return 0 end
function date() return "00:00:00 " end
function UnitName() return W.char end
function UnitGUID(unit) if unit == "player" then return "Player-0-" .. W.char end end
function GetNormalizedRealmName() return "Realm" end
local printed = {}
function print(msg) printed[#printed + 1] = msg end
SlashCmdList = {}
local afters = {}
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) afters[#afters + 1] = fn end }
InputUtil = { IsGamepadUIEnabled = function() return true end }
GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return true end } }

-- The catalog: Fireball (one rank), Holy Light (two ranks), a usable bag item, a toy, a mount, an equipment set, a
-- macro, an addon's CLICK binding and an addon's Lua binding.
local ns = {}
local BOOK = { { spellID = 133, name = "Fireball", subName = "" }, { spellID = 635, name = "Holy Light", subName = "Rank 1" }, { spellID = 639, name = "Holy Light", subName = "Rank 2" } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
	GetSpellBookItemInfo = function(slot, bank) if bank == 0 then return BOOK[slot] end end,
	IsSpellBookItemPassive = function() return false end,
	HasPetSpells = function() return 0 end,
}
C_Spell = { GetSpellName = function(id) return ({ [133] = "Fireball", [4321] = "Swift Horse", [150544] = "Summon Random Favorite Mount" })[id] end }
C_Item = { GetItemSpell = function(id) return id == 6948 and "Hearth" end }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
	GetContainerItemInfo = function() return { itemID = 6948, itemName = "Hearthstone", iconFileID = 11 } end,
}
C_ToyBox = { GetNumFilteredToys = function() return 1 end, GetToyFromIndex = function() return 54452 end, GetToyInfo = function(id) if id == 54452 then return id, "Ethereal Portal", 22 end end }
function PlayerHasToy() return true end
C_MountJournal = {
	GetMountIDs = function() return { 7 } end,
	GetMountInfoByID = function(id) if id == 7 then return "Horse", 4321, 33, false, true, 0, false, false, nil, false, true end end,
}
C_EquipmentSet = { GetEquipmentSetIDs = function() return { 1 } end, GetEquipmentSetInfo = function(id) if id == 1 then return "PvP", 44 end end }
local macros = { { "My Macro", 55, "/cast Fireball\n/say hi" } }
function GetNumMacros() return #macros, 0 end
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
function GetMacroBody(i) local m = macros[i]; return m and m[3] end
local BINDINGS = { { "CLICK MyAddonButton:LeftButton", "MyAddon" }, { "MYADDON_LUA", "MyAddon" } }
function GetNumBindings() return #BINDINGS end
function GetBinding(i) return BINDINGS[i][1], BINDINGS[i][2] end
function issecurevariable(name) return not tostring(name):find("MyAddon", 1, true) and not tostring(name):find("MYADDON", 1, true) and not tostring(name):find("CLICK", 1, true), "MyAddon" end
C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 181 end }
C_ActionBar = { HasAction = function() return false end, GetActionText = function() end }
function GetActionInfo() end
function GetCursorInfo() end

-- Blizzard's top bar: the reserved face buttons the routers and face entries click.
local top = { actionButtons = {} }
for i = 1, 8 do top.actionButtons[i] = frame("TopButton" .. i, "SecureActionButtonTemplate") end
GamepadMainActionBarFrame = { PageUnit = { actionBars = { topBar = top } } }
-- Routed cells with a crossbar slot are per page: the router reads the page from the top bar button's ID (page 1).
local PAGE_UTIL = { GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID = function(page, id) return 181 + (page - 1) * 32 + id end }
GamepadActionBarBindingUtil = PAGE_UTIL
for i, b in ipairs(top.actionButtons) do
	b.id = PAGE_UTIL.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(1, i)
	function b.GetGamepadPageUnitSlotID() return i end
end

local function loadAddonFile(file) assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
loadAddonFile("Core.lua")
loadAddonFile("Layout.lua")
ns.Device = { Current = function() return { key = "054c/0ce6" } end, SwapTargets = function() return false end }
ns.SlotView = { New = function(parent)
	local view = frame(nil, nil, parent)
	function view:SetSlot(slot, icon) self.slot, self.fallback = slot, icon end
	view.text = frame(nil, nil, view)
	return view
end, HealerBadge = function(f, shown) f.badge = shown end, RingMarker = function(f, shown) f.marker = shown end }
-- As SlotView's: a ring entry wears the marker unless the setting is off or that ring is open; it shows the ring's live
-- icon.
function ns.SlotView.MarksRing(entry)
	local id = entry and entry.kind == "ring" and tonumber(tostring(entry.id):match("^ring:(%d+)$"))
	if not id or ns.db and ns.db.ringMarker == false then return false end
	return not (ns.Rings and ns.Rings.IsOpen(id))
end
function ns.SlotView.EntryIcon(entry)
	local id = entry and entry.kind == "ring" and tonumber(tostring(entry.id):match("^ring:(%d+)$"))
	if id and ns.Rings then return ns.Rings.LiveIcon(id) end
	return entry and entry.icon
end
for _, file in ipairs({ "Face.lua", "Actions.lua" }) do loadAddonFile(file) end
-- Remap's hold, recorded: a held ring holds it from its open until its CVar is back.
local holds = {}
ns.Remap = { Hold = function(on, stillOpen) holds[#holds + 1] = { on, #W.writes, stillOpen } end }
local function lastHold() local h = holds[#holds] return h and h[1], h and h[2], h and h[3] end
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks")
-- Modules as the game loads them: their own addon name and private table; they read the core's namespace global.
local function loadModule(module, file) assert(loadfile(here .. "/../../ForeverControllerTweaks_" .. module .. "/" .. file .. ".lua"))("ForeverControllerTweaks_" .. module, {}) end
loadModule("Touch", "Touch")
loadModule("Rings", "Rings")
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks_Touch")
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks_Rings")
ns.Fire("PLAYER_ENTERING_WORLD")

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

local Rings, Actions = ns.Rings, ns.Actions
local ring = frames.ForeverControllerTweaksRing

-- Stick angle -> slot, clockwise from the top, and the dead zone.
for _, n in ipairs({ 4, 8 }) do
	local step = 360 / n
	for i = 1, n do
		local centre = (i - 1) * step
		for _, offset in ipairs({ 0, step / 2 - 0.5, -(step / 2 - 0.5) }) do
			local a = math.rad(centre + offset)
			check(Rings.SlotAt(math.sin(a), math.cos(a), n) == i, ("pick: %d slots, %.1f degrees -> slot %d"):format(n, centre + offset, i))
		end
	end
end
check(Rings.SlotAt(0, 1, 8) == 1 and Rings.SlotAt(1, 0, 8) == 3 and Rings.SlotAt(0, -1, 8) == 5 and Rings.SlotAt(-1, 0, 8) == 7, "pick: 8 slots N E S W")
check(Rings.SlotAt(1, 1, 8) == 2 and Rings.SlotAt(1, -1, 8) == 4 and Rings.SlotAt(-1, -1, 8) == 6 and Rings.SlotAt(-1, 1, 8) == 8, "pick: 8 slots NE SE SW NW")
check(Rings.SlotAt(0.25, 0.25, 8) == nil and Rings.SlotAt(0, 0, 8) == nil and Rings.SlotAt(0, -0.39, 8) == nil, "pick: inside the dead zone, nothing")
check(Rings.SlotAt(0, -0.41, 8) == 5, "pick: just past the dead zone")

-- The per-slot attributes for every entry kind, from the real catalog.
local function attrs(id) return { Rings.Attributes(Actions.Find(id)) } end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
check(same(attrs("spell:133"), { "spell", "spell", 133 }), "attributes: a spell by id")
check(same(attrs("spellgroup:Holy Light"), { "spell", "spell", 639 }), "attributes: Highest Rank casts the top rank")
check(same(attrs("spell:635"), { "spell", "spell", 635 }), "attributes: a fixed lower rank")
check(same(attrs("item:6948"), { "item", "item", "item:6948" }), "attributes: an item")
check(same(attrs("toy:54452"), { "toy", "toy", 54452 }), "attributes: a toy")
check(same(attrs("mount:7"), { "spell", "spell", 4321 }), "attributes: a mount by its summon spell")
check(same(attrs("mount:random"), { "macro", "macrotext", "/cast Summon Random Favorite Mount" }), "attributes: the random favourite mount")
check(same(attrs("set:1"), { "macro", "macrotext", "/equipset PvP" }), "attributes: an equipment set")
check(same(attrs("macro:My Macro"), { "macro", "macrotext", "/cast Fireball\n/say hi" }), "attributes: the player's macro body")
check(same(attrs("game:sit"), { "macro", "macrotext", "/sit" }), "attributes: a game action")
check(not Actions.Find("game:chat") and #attrs("game:chat") == 0 and Rings.Resolve({ id = "game:chat" }) == nil, "attributes: removed Open chat, a saved slot fires nothing")
check(same(attrs("game:fps"), { "macro", "macrotext", "/click ForeverControllerTweaksToggleFPS" }), "attributes: Toggle FPS clicks our button")
check(same(attrs("face:jump"), { "macro", "macrotext", "/click TopButton8 LeftButton 1\n/click TopButton8 LeftButton" }), "attributes: a face action clicks down and up")
check(same(attrs("addon:CLICK MyAddonButton:LeftButton"), { "macro", "macrotext", "/click MyAddonButton LeftButton 1\n/click MyAddonButton LeftButton" }), "attributes: an addon's CLICK binding")
check(#attrs("addon:MYADDON_LUA") == 0 and Actions.Find("addon:MYADDON_LUA").disabled, "attributes: an addon's Lua binding can't fire")
check(#attrs("spell:999") == 0, "attributes: unknown to this character, nothing")

-- Rings: made out of combat only, named, sized, filled.
W.combat = true
check(select(2, Rings.New()) == "Controller Tweaks changes rings out of combat only." and #Rings.List() == 0, "rings: none made in combat")
W.combat = false
local heals = assert(Rings.New())
check(heals.name == "Ring 1" and heals.count == 8 and heals.stick == "right" and heals.show == "toggle" and next(heals.slots) == nil and Rings.Icon(heals):find("QuestionMark"), "rings: defaults")
check(not Rings.SetStick(heals.id, "up") and heals.stick == "right", "rings: only right, left or dynamic")
check(not Rings.SetShow(heals.id, "press") and heals.show == "toggle", "rings: shown by toggle or hold only")
check(Rings.Rename(heals.id, "  Heals|cff  ") and heals.name == "Healscff" and not Rings.Rename(heals.id, "   "), "rings: names trimmed, escapes dropped, never empty")
check(Rings.Rename(heals.id, "Heals") and not Rings.SetCount(heals.id, 3) and not Rings.SetCount(heals.id, 9) and not Rings.SetCount(heals.id, 8.5), "rings: 4 to 8 slots")
local function put(id, i, entryId) assert(Rings.SetSlot(id, i, Actions.Find(entryId))) end
put(heals.id, 1, "spell:133")
put(heals.id, 3, "spellgroup:Holy Light")
put(heals.id, 5, "item:6948")
put(heals.id, 7, "game:sit")
check(Rings.Icon(heals) == Actions.Find("spell:133").icon, "rings: icon defaults to the first slot's")
check(select(2, Rings.SetSlot(heals.id, 2, Actions.Find("addon:MYADDON_LUA"))) == "needs a key binding", "rings: a Lua binding refused")
check(not Rings.SetSlot(heals.id, 9, Actions.Find("spell:133")), "rings: no slot past the count")
W.combat = true
check(select(2, Rings.SetSlot(heals.id, 2, Actions.Find("spell:133"))) == "Controller Tweaks changes rings out of combat only.", "rings: edits refused in combat")
W.combat = false
local ringEntry = Actions.Find("ring:" .. heals.id)
check(ringEntry and ringEntry.kind == "ring" and ringEntry.name == "Open ring: Heals" and ringEntry.category == "Rings", "catalog: the Rings category")
check(select(2, Rings.SetSlot(heals.id, 2, ringEntry)) == "A ring can't open another ring.", "rings: no ring in a ring")

-- Written for the snippets, out of combat.
local p = "r" .. heals.id
check(ring.attrs[p .. "n"] == 8 and ring.attrs[p .. "t1"] == "spell" and ring.attrs[p .. "v1"] == 133 and ring.attrs[p .. "v3"] == 639 and ring.attrs[p .. "t2"] == nil, "secure: slot attributes written")
check(ring.attrs[p .. "k5"] == "item" and ring.attrs[p .. "k7"] == "macrotext" and ring.attrs[p .. "v7"] == "/sit", "secure: item and macro text")
check(ring.attrs["ps-lstick"] == 1 and ring.attrs["ps-rstick"] == 2 and ring.attrs[p .. "s"] == "right" and math.abs(ring.attrs["dx8-3"] - 1) < 1e-9 and math.abs(ring.attrs["dy8-5"] + 1) < 1e-9 and ring.attrs["dx9-1"] == nil, "secure: right stick index and slot directions, none past 8")

-- Style: Full or Compact. The secure open sizes and places each ring's slot buttons on its drawn circles, at the same
-- angles in both, from attributes written out of combat: a Compact and a Full ring opened one after the other in combat.
check(heals.style == "full" and ring.attrs[p .. "y"] == "full", "style: new rings are Full")
check(not Rings.SetStyle(heals.id, "round") and heals.style == "full", "style: full or compact only")
local GEO = Rings.GEO
local function layout(id, n)
	secure(ring.RunAttribute, ring, "_open", id, "touch")
	local out = {}
	for i = 1, n do
		local slot = frames["ForeverControllerTweaksRingSlot" .. i]
		out[i] = { slot.point[4], slot.point[5], slot.w, slot.h, slot.shown }
	end
	secure(ring.RunAttribute, ring, "_close")
	return out
end
local function placed(out, r, hit)
	local ok = true
	for i, at in ipairs(out) do
		local dx, dy = Rings.Dir(#out, i)
		ok = ok and math.abs(at[1] - r * dx) < 1e-9 and math.abs(at[2] - r * dy) < 1e-9 and at[3] == hit and at[4] == hit and at[5]
	end
	return ok
end
local same = true
for n = Rings.MIN_SLOTS, Rings.MAX_SLOTS do
	assert(Rings.SetCount(heals.id, n) and Rings.SetStyle(heals.id, "full"))
	local full = layout(heals.id, n)
	assert(Rings.SetStyle(heals.id, "compact"))
	local compact = layout(heals.id, n)
	same = same and placed(full, GEO.SLOT_R, GEO.HIT) and placed(compact, GEO.COMPACT_R, GEO.COMPACT_HIT)
end
check(same and ring.attrs[p .. "y"] == "compact", "style: every count 4 to 8, the slot buttons on the circles, at the same angles in both styles")
local small = assert(Rings.New())
assert(Rings.SetCount(small.id, 4) and Rings.SetStyle(heals.id, "full") and Rings.SetStyle(small.id, "compact"))
W.combat = true
check(placed(layout(small.id, 4), GEO.COMPACT_R, GEO.COMPACT_HIT) and placed(layout(heals.id, 8), GEO.SLOT_R, GEO.HIT) and placed(layout(small.id, 4), GEO.COMPACT_R, GEO.COMPACT_HIT), "style: in combat, Compact then Full then Compact, each laid out as drawn")
W.combat = false
assert(Rings.Delete(small.id))

check(ring.attrs[p .. "h"] == "toggle", "secure: the Show setting written")

assert(ns.Face.Routable("FB", "T", ringEntry) and ns.Face.Routable("DU", "L", ringEntry))
assert(ns.Face.SetCellEntry("FB", "T", ringEntry))
local router = frames.ForeverControllerTweaksFaceBottom

-- Compact opens centred on the crossbar button of the cell and layer that opened it, its rect read live by the open
-- snippet (in combat too), the frame the flyout's size; Full, a touch ring or no known button: the screen centre.
assert(ns.Face.SetCellEntry("DU", "T", ringEntry) and Rings.SetStyle(heals.id, "compact"))
local dpad = frames.ForeverControllerTweaksDpadUp
local native = assert(dpad.attrs["frameref-slot-top"], "the D-pad router's top-bar button")
function native:GetRect() return 100, 50, 40, 40 end
native.scale = 1.5
local function opened(pt) return ring.shown and ("%s %s %s %g %g"):format(tostring(pt[1]), tostring(pt[2]), tostring(pt[3]), tonumber(pt[4]) or -1, tonumber(pt[5]) or -1) end
local function letGo()
	click(dpad, false)
	if ring.shown then secure(ring.RunAttribute, ring, "_close") end
end
aim(0, 0)
click(dpad, true)
check(opened(ring.point) == "CENTER $screen BOTTOMLEFT 180 105" and ring.w == Rings.GEO.FLY and ring.attrs["ps-layer"] == "top" and ring.attrs["ps-kind"] == "dpad" and ring.attrs["ps-trace"]:find(" at=top", 1, true), "compact: opens on the cell's crossbar button, the flyout's size")
letGo()
W.combat = true
native.scale = 2
click(dpad, true)
check(opened(ring.point) == "CENTER $screen BOTTOMLEFT 240 140", "compact: in combat, at the button's live place and scale")
letGo()
W.combat = false
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
check(ring.point[1] == "CENTER" and ring.point[2] == nil and ring.attrs["ps-layer"] == nil, "compact: a touch ring opens in the middle")
secure(ring.RunAttribute, ring, "_close")
native.GetRect = nil
click(dpad, true)
check(ring.shown and ring.point[1] == "CENTER" and ring.point[2] == nil and not ring.attrs["ps-at"], "compact: no rect to read, the middle")
letGo()
function native:GetRect() return 100, 50, 40, 40 end
-- The router is found through the ref Face sets on the ring frame under its name (SecureHandlerSetFrameRef, the only
-- way a ref resolves here, as in the game): without it, the middle.
local dpadRef = ring.attrs["frameref-ForeverControllerTweaksDpadUp"]
check(dpadRef == dpad and ring.attrs["ps-router" .. 1] and ring.attrs["ps-routern"] >= 4, "compact: the routers known by name, each with Face's ref on the ring frame")
ring.attrs["frameref-ForeverControllerTweaksDpadUp"] = nil
click(dpad, true)
check(ring.shown and ring.point[1] == "CENTER" and ring.point[2] == nil and not ring.attrs["ps-at"] and ring.attrs["ps-layer"] == nil, "compact: no ref to the router, the middle")
letGo()
SecureHandlerSetFrameRef(ring, "ForeverControllerTweaksDpadUp", dpad)
click(dpad, true)
check(opened(ring.point) == "CENTER $screen BOTTOMLEFT 240 140", "compact: the ref back, on the button again")
letGo()
assert(Rings.SetStyle(heals.id, "full"))
click(dpad, true)
check(ring.point[1] == "CENTER" and ring.point[2] == nil and ring.w == 2 * Rings.GEO.WHEEL, "full: the middle of the screen, the wheel's size")
letGo()
assert(ns.Face.SetCellEntry("DU", "T", nil))

local keyButton = frames.ForeverControllerTweaksRingKey
local function keyUp(key) return click(keyButton, false, "typerelease", key) end

-- Show Toggle (the default) on a routed face cell, in combat: a click opens the ring and it stays open until a slot
-- is used, the button is pressed again or B; the button's release with a slot aimed still uses it.
W.combat = true
aim(0, 0)
press("PAD1", true)
check(press("PAD1", false) == nil and ring.shown, "toggle: a click opens the ring, it stays open")
aim(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown and not next(W.prio), "toggle: the stick let go uses the slot and closes")
press("PAD1", true)
press("PAD1", false)
check(press("PAD1", true) == nil and not ring.shown and press("PAD1", false) == nil and not ring.shown, "toggle: the button again closes it, nothing used, its release does nothing")
press("PAD1", true)
press("PAD1", false)
check(press("PAD2", true) == nil and not ring.shown and not next(W.prio), "toggle: B closes it")
press("PAD1", true)
aim(90)
check(press("PAD1", false) == "spell 639" and not ring.shown, "toggle: the button let go with a slot aimed uses it")
aim(0, 0)
press("PAD1", true)
aim(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PAD1", false) == "spell 639" and not ring.shown and keyUp("PADRSTICKRIGHT") == nil, "toggle: the button let go centred with a kept pick uses it; the key's release then does nothing")
W.combat = false

-- Show Hold for the release orders below: up only while the button is held.
assert(Rings.SetShow(heals.id, "hold"))
check(ring.attrs[p .. "h"] == "hold", "secure: Hold written for the snippets")

-- On a routed face cell: hold opens, release fires the slot under the right stick, centred cancels. In combat too.
check(router.attrs["ps-ring-top"] == heals.id and router.attrs["frameref-rings"] == ring and W.bindings.PAD1, "face: the ring on the router")
W.combat = true
aim(0, 0)
check(press("PAD1", true) == nil, "face: the press fires nothing")
check(ring.shown and ring.attrs["ps-ring"] == heals.id and ring.attrs["ps-mode"] == "hold", "face: the press opens the ring")
local slot3 = frames.ForeverControllerTweaksRingSlot3
check(slot3.shown and slot3.attrs.type == "spell" and slot3.attrs.spell == 639 and slot3.point[4] > 100 and math.abs(slot3.point[5]) < 1e-9, "face: slots laid out and armed")
check(frames.ForeverControllerTweaksRingSlot8.shown and frames.ForeverControllerTweaksRingSlot9 == nil, "face: 8 slot buttons, all shown at 8")
aim(90)
check(press("PAD1", false) == "spell 639" and not ring.shown, "face: release fires the aimed slot and closes")
check(router.attrs.checkselfcast == true, "face: self-cast modifiers on spells")
press("PAD1", true)
aim(180, 0.2)
check(press("PAD1", false) == nil and not ring.shown and not next(W.prio), "face: released in the dead zone with nothing aimed, the ring closes, nothing fired")
press("PAD1", true)
check(not W.prio.PAD1 and not W.prio["SHIFT-PAD1"] and W.prio.PAD2 and W.prio["ALT-CTRL-SHIFT-PADRSTICKUP"], "keys: the opening key isn't bound, B and the stick keys are")
check(press("PAD1", true) == nil and not ring.shown and not next(W.prio) and press("PAD1", false) == nil, "face: the ring's button again closes it, nothing fired, keys given back")
press("PAD1", true)
aim(181)
check(press("PAD1", false) == "item item:6948" and router.attrs.spell == nil, "face: an item, the spell attribute cleared")
press("PAD1", true)
aim(45)
check(press("PAD1", false) == nil, "face: an empty slot fires nothing")
W.combat = false
-- The case seen in game: a ring on D-pad right, held and released in combat.
assert(ns.Face.SetCellEntry("DR", "T", ringEntry))
local dpadRight = frames.ForeverControllerTweaksDpadRight
check(dpadRight.attrs["ps-ring-top-1"] == heals.id and W.bindings.PADDRIGHT, "face: the ring on D-pad right")
W.combat = true
aim(0, 0)
press("PADDRIGHT", true)
check(ring.shown and ring.attrs["ps-mode"] == "hold", "face: D-pad right opens the ring")
aim(0)
check(press("PADDRIGHT", false) == "spell 133" and not ring.shown and dpadRight.attrs.typerelease == "spell", "face: D-pad right's release fires slot 1")

-- Stick keys (GamePadStickAxisButtons on): flick to a slot, let the stick go, the last direction key up fires it and
-- the ring closes, as the native radial menu does; the button's release no longer has to.
-- The ring's button pressed and held: its release would close the ring.
local function open()
	aim(0, 0)
	press("PADDRIGHT", true)
end
open()
check(ring.shown and W.prio.PAD1.click == "ForeverControllerTweaksRingKey:PAD1" and W.prio["SHIFT-PADRSTICKRIGHT"].click == "ForeverControllerTweaksRingKey:PADRSTICKRIGHT" and W.prio.PADRSTICK, "keys: the held ring binds A, B, the right stick's press and directions")
aim(90)
check(press("PADRSTICKRIGHT", true) == nil and ring.shown and ring.attrs["ps-pick"] == 3, "keys: a flick picks, nothing fires yet")
aim(90, 0.3)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown and not next(W.prio) and keyButton.attrs.checkselfcast == true, "keys: the stick let go fires the pick and closes, keys given back")
open()
aim(0)
press("PADRSTICKUP", true)
aim(90)
press("PADRSTICKRIGHT", true)
check(press("PADRSTICKUP", false) == nil and ring.shown and ring.attrs["ps-pick"] == 3, "keys: rolled from up to right, the pick follows, one key still down")
aim(90, 0.2)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "keys: the last key up fires")
open()
aim(180, 0.3)
check(press("PADRSTICKDOWN", true) == nil and ring.attrs["ps-pick"] == 5, "keys: a short reading as the key goes down picks by the key's own direction")
aim(0, 0)
check(press("PADRSTICKDOWN", false) == "item item:6948" and not ring.shown, "keys: an item fires on the let go")
open()
aim(90, 0.7)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "keys: a key the ring never saw go down, let go with the stick out short of the rim, fires where it points")
open()
aim(90)
check(press("PADRSTICKRIGHT", false) == nil and ring.shown, "keys: every key released with the stick at the rim (rolling round the edge): nothing fires, still open")
check(press("PAD2", true) == nil and not ring.shown, "keys: then B closes it")
-- A release decides by where the stick is (under 0.6 it is let go), not by the keys still marked down.
open()
aim(100)
press("PADRSTICKRIGHT", true)
press("PADRSTICKDOWN", true)
aim(100, 0.55)
check(press("PADRSTICKDOWN", false) == "spell 639" and not ring.shown, "keys: diagonal, the other key's release lost, a release on the way back (0.55) fires")
open()
aim(100)
press("PADRSTICKRIGHT", true)
press("PADRSTICKDOWN", true)
aim(100, 0.7)
check(press("PADRSTICKDOWN", false) == nil and ring.shown, "keys: diagonal, one key up at 0.7 with the other down: open")
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "keys: then the last key up fires")
open()
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == nil and ring.shown, "keys: a key the ring never saw go down, let go centred: nothing to fire, still open")
check(press("PAD2", true) == nil and not ring.shown and not next(W.prio), "keys: then B closes it")
open()
aim(0, 0)
check(press("PAD1", true) == nil and press("PAD1", false) == nil and ring.shown, "keys: A with nothing aimed keeps the ring open")
aim(270)
check(press("PAD1", true) == nil and press("PAD1", false) == "macro /sit" and not ring.shown, "keys: A fires the slot aimed at (no stick keys)")
open()
aim(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PAD1", false) == "spell 639", "keys: A, stick centred, fires the kept pick")
open()
check(press("PAD2", true) == nil and not ring.shown and not next(W.prio), "keys: B closes, nothing fired")
open()
check(press("PADRSTICK", true) == nil and not ring.shown, "keys: the stick's press closes")
open()
check(press("PADDRIGHT", true) == nil and not ring.shown and press("PADDRIGHT", false) == nil, "keys: the ring's button again closes")
open()
cond("vehicleui", true)
check(not ring.shown and not next(W.prio), "keys: the guard closes and gives the keys back")
cond("vehicleui", false)
W.combat = false

-- The button and the stick let go together, in either order: the first release fires the pick, the second does
-- nothing. A stick key's release reaches the key button that took its press, bound or not by then.
W.combat = true
local function hold(degrees)
	aim(0, 0)
	press("PADDRIGHT", true)
	aim(degrees)
end
hold(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PADDRIGHT", false) == "spell 639" and not ring.shown, "together: the button first, the stick already centred, its key still down: the kept pick fires")
check(keyUp("PADRSTICKRIGHT") == nil, "together: then the stick key's release does nothing")
hold(90)
press("PADRSTICKRIGHT", true)
check(press("PADDRIGHT", false) == "spell 639" and not ring.shown, "together: the button first, the stick still out: the slot it points at fires")
aim(0, 0)
check(keyUp("PADRSTICKRIGHT") == nil, "together: then the stick key's release does nothing")
hold(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "together: the stick key first fires")
check(press("PADDRIGHT", false) == nil, "together: then the button's release does nothing")
hold(100)
press("PADRSTICKRIGHT", true)
press("PADRSTICKDOWN", true)
aim(0, 0)
check(press("PADDRIGHT", false) == "spell 639" and not ring.shown, "together, diagonal: the button first fires the kept pick")
check(keyUp("PADRSTICKRIGHT") == nil and keyUp("PADRSTICKDOWN") == nil, "together, diagonal: both keys' releases do nothing")
hold(100)
press("PADRSTICKRIGHT", true)
press("PADRSTICKDOWN", true)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "together, diagonal: one key up with the stick centred fires the kept pick, the other still marked down")
check(press("PADDRIGHT", false) == nil and keyUp("PADRSTICKDOWN") == nil, "together, diagonal: then the button and the last key do nothing")
hold(100)
press("PADRSTICKRIGHT", true)
press("PADRSTICKDOWN", true)
check(press("PADRSTICKDOWN", false) == nil and ring.shown, "together, diagonal: one key up with the stick still out: open")
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "together, diagonal: both keys first: the last fires")
check(press("PADDRIGHT", false) == nil, "together, diagonal: then the button's release does nothing")
hold(0)
aim(0, 0)
check(press("PADDRIGHT", false) == nil and not ring.shown and not next(W.prio), "without stick keys: the button let go centred closes the ring, nothing fired")
W.combat = false
local logged = #printed
ns.commands.ringlog()
local lines = table.concat(printed, "\n", logged + 1)
check(lines:find("release ForeverControllerTweaks", 1, true) and lines:find("key PADRSTICKRIGHT up", 1, true) and lines:find("fire key slot 3", 1, true) and lines:find("close", 1, true), "ringlog: prints the opens, releases, stick keys and closes")
check(#Rings.Trace <= 40, "ringlog: keeps the last 40")

-- Every slot kind on every one of the 8 directions (the diagonals need two stick keys) fires from the key button and
-- from the ring's button, in each order the releases can come; one release always closes the ring.
local KEYS_AT = { [0] = { "UP" }, [45] = { "UP", "RIGHT" }, [90] = { "RIGHT" }, [135] = { "RIGHT", "DOWN" }, [180] = { "DOWN" }, [225] = { "DOWN", "LEFT" }, [270] = { "LEFT" }, [315] = { "LEFT", "UP" } }
local function want(i)
	local actionType, _, value = Rings.Attributes(Rings.Resolve(heals.slots[i]))
	return actionType .. " " .. tostring(value)
end
-- Two layouts: other kinds on the diagonals, then spells there (the reported case: Seal and Judgement stuck on the
-- diagonals while Jump, below, fired).
local LAYOUTS = { { "toy:54452", "mount:random", "face:jump", "macro:My Macro" }, { "spell:635", "mount:7", "spell:133", "spellgroup:Holy Light" } }
for _, show in ipairs(Rings.SHOWS) do
assert(Rings.SetShow(heals.id, show))
for _, layout in ipairs(LAYOUTS) do
for d, id in ipairs(layout) do assert(Rings.SetSlot(heals.id, 2 * d, Actions.Find(id))) end
W.combat = true
for i = 1, 8 do
	local degrees = (i - 1) * 45
	local keys, name = KEYS_AT[degrees], show .. ", slot " .. i .. " (" .. heals.slots[i].id .. ")"
	local function downs() for _, way in ipairs(keys) do press("PADRSTICK" .. way, true) end end
	-- The stick let go: the first key up finds it centred and fires; the other key and the button then do nothing.
	hold(degrees)
	downs()
	aim(0, 0)
	local first, late = press("PADRSTICK" .. keys[1], false), true
	for k = 2, #keys do late = late and keyUp("PADRSTICK" .. keys[k]) == nil end
	check(first == want(i) and not ring.shown and late and press("PADDRIGHT", false) == nil, "kinds: " .. name .. ", the stick let go fires it")
	if keys[2] then
		-- The other key first, the first key's release lost (an ApplyConfigs mid-aim): the centred release fires.
		hold(degrees)
		downs()
		aim(0, 0)
		check(press("PADRSTICK" .. keys[2], false) == want(i) and not ring.shown and press("PADDRIGHT", false) == nil, "kinds: " .. name .. ", the other key first, the other's release lost, fires it")
		-- One key let go with the stick still out (rolled to the other direction): open until the last.
		hold(degrees)
		downs()
		check(press("PADRSTICK" .. keys[1], false) == nil and ring.shown, "kinds: " .. name .. ", one key up with the stick out: open")
		aim(0, 0)
		check(press("PADRSTICK" .. keys[2], false) == want(i) and not ring.shown and press("PADDRIGHT", false) == nil, "kinds: " .. name .. ", then the last key up centred fires it")
	end
	-- The button let go with the stick out, then the keys.
	hold(degrees)
	downs()
	check(press("PADDRIGHT", false) == want(i) and not ring.shown, "kinds: " .. name .. ", the button let go fires it")
	for _, way in ipairs(keys) do check(keyUp("PADRSTICK" .. way) == nil, "kinds: " .. name .. ", then " .. way .. " up does nothing") end
	-- The button let go with the stick already centred and its keys still down: the kept pick.
	hold(degrees)
	downs()
	aim(0, 0)
	check(press("PADDRIGHT", false) == want(i) and not ring.shown, "kinds: " .. name .. ", the button let go centred fires the kept pick")
	-- No key's release comes at all: the button's release fires the kept pick (above), and a Toggle ring's A does.
	hold(degrees)
	downs()
	aim(0, 0)
	check(press("PAD1", false) == want(i) and not ring.shown, "kinds: " .. name .. ", every key's release lost, A fires the kept pick")
	press("PADDRIGHT", false)
end
W.combat = false
end
end
assert(Rings.SetShow(heals.id, "hold"))
W.combat = true
-- Orders a counter of the keys down got wrong, so the ring never closed.
hold(45)
press("PADRSTICKUP", true)
press("PADRSTICKUP", true)
press("PADRSTICKRIGHT", true)
press("PADRSTICKUP", false)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == want(2) and not ring.shown, "drift: a key pressed twice (no release between) still lets the last release fire")
press("PADDRIGHT", false)
hold(45)
press("PADRSTICKRIGHT", true)
check(press("PADRSTICKUP", false) == nil and ring.shown, "drift: a key the ring never saw go down, let go while another is down: still open")
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == want(2) and not ring.shown, "drift: then the last key down fires")
press("PADDRIGHT", false)
-- No stick keys at all (a push short of the game's key threshold): the button's release fires where the stick
-- points, or closes the ring centred; it never stays open.
hold(135)
check(press("PADDRIGHT", false) == want(4) and not ring.shown, "no keys: the button let go with the stick out fires that slot")
hold(135)
aim(0, 0)
check(press("PADDRIGHT", false) == nil and not ring.shown and not next(W.prio), "no keys: the button let go centred closes the ring, nothing fired")
W.combat = false
assert(Rings.SetShow(heals.id, "toggle"))
W.combat = true
hold(135)
aim(0, 0)
check(press("PADDRIGHT", false) == nil and ring.shown, "no keys, Toggle: the button let go centred keeps the ring open")
check(press("PAD2", true) == nil and not ring.shown, "no keys, Toggle: then B closes it")
W.combat = false
assert(Rings.SetShow(heals.id, "hold"))
for _, i in ipairs({ 2, 4, 6, 8 }) do assert(Rings.SetSlot(heals.id, i, nil)) end

-- GamePadStickAxisButtons: on while a held ring is open, the player's value saved and put back (in combat, after the
-- fight; after a /reload mid-ring, at login), never written when it already holds the wanted value.
local AXIS = "GamePadStickAxisButtons"
-- The restore waits a frame, out of the click that closes the ring.
local function nextFrame() while afters[1] do table.remove(afters, 1)() end end
nextFrame()
W.cvars[AXIS], W.writes = "0", {}
open()
check(W.cvars[AXIS] == "1" and ns.db.ringAxisSaved == "0" and #W.writes == 1, "axis: a held ring switches it on and saves the old value")
-- The CVar write and its restore change the controller config: Remap is held from before the one until after the other.
local on, at = lastHold()
check(on == true and at == 0, "axis: Remap is held before the CVar write")
press("PAD2", true)
check(W.cvars[AXIS] == "1" and #W.writes == 1, "axis: still on in the click that closed the ring")
check(lastHold() == true, "axis: Remap still held in the click that closed the ring")
nextFrame()
check(W.cvars[AXIS] == "0" and ns.db.ringAxisSaved == nil and #W.writes == 2, "axis: closing puts it back")
on, at = lastHold()
check(on == false and at == 2, "axis: Remap let go only after the restore write")
W.cvars[AXIS] = "1"
open()
check(lastHold() == true, "axis: already on: Remap is still held while the ring aims")
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "1" and ns.db.ringAxisSaved == nil and #W.writes == 2 and lastHold() == false, "axis: already on: neither saved nor written, Remap let go")
W.cvars[AXIS] = "0"
W.combat = true
open()
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "1" and ns.db.ringAxisSaved == "0" and #W.writes == 3, "axis: closed in combat, it stays on until the fight ends")
open()
press("PAD2", true)
check(ns.db.ringAxisSaved == "0" and #W.writes == 3, "axis: opened again in combat: no write, the first saved value kept")
W.combat = false
local held = #holds
ns.Fire("PLAYER_REGEN_ENABLED")
check(W.cvars[AXIS] == "0" and ns.db.ringAxisSaved == nil and #W.writes == 4, "axis: put back after the fight")
check(holds[held + 1] and holds[held + 1][1] == true and holds[held + 1][2] == 3 and holds[#holds][1] == false and holds[#holds][2] == 4, "axis: the restore after the fight holds Remap around its write")
ns.db.ringAxisSaved, W.cvars[AXIS] = "0", "1"
ns.Fire("FCT_READY")
check(W.cvars[AXIS] == "0" and ns.db.ringAxisSaved == nil and #W.writes == 5, "axis: a value left saved (a /reload mid-ring) is put back at login")
ns.db.ringAxisSaved = "0"
ns.Fire("FCT_READY")
check(ns.db.ringAxisSaved == nil and #W.writes == 5, "axis: at login, already the saved value: cleared, not written")
local setCVar = SetCVar
SetCVar = function() error("blocked") end
open()
aim(90)
check(ring.shown and W.cvars[AXIS] == "0" and press("PAD1", true) == nil and press("PAD1", false) == "spell 639", "axis: a failed write: the ring opens and A still fires")
nextFrame()
check(ns.db.ringAxisSaved == nil and #W.writes == 5, "axis: after a failed write nothing is left to put back")
SetCVar = setCVar

-- The keys and Remap's hold follow ps-mode, not the frame's show: a held ring opened over a touch ring already up, a
-- touch ring opened over a held one.
nextFrame()
W.cvars[AXIS], W.writes = "0", {}
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
check(ring.shown and W.cvars[AXIS] == "0" and lastHold() == false, "mode: a touch ring: keys off, Remap free")
open()
local _, _, stillOpen = lastHold()
check(ring.attrs["ps-mode"] == "hold" and W.cvars[AXIS] == "1" and lastHold() == true, "mode: a held ring over the open touch ring: keys on, Remap held")
check(type(stillOpen) == "function" and stillOpen(), "mode: Remap's failsafe is passed a check that sees the ring open")
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
check(ring.shown and W.cvars[AXIS] == "1" and lastHold() == true and stillOpen(), "mode: a touch ring over the held one: put back next frame")
nextFrame()
check(ring.shown and W.cvars[AXIS] == "0" and ns.db.ringAxisSaved == nil and lastHold() == false and not stillOpen(), "mode: then keys off and Remap let go, the touch ring still up")
secure(ring.RunAttribute, ring, "_close")
-- Closed in combat: Remap stays held while the keys are still on.
W.combat = true
open()
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "1" and lastHold() == true and stillOpen(), "combat: closed in combat, the keys on: Remap still held")
W.combat = false
ns.Fire("PLAYER_REGEN_ENABLED")
on, at = lastHold()
check(W.cvars[AXIS] == "0" and on == false and at == #W.writes, "combat: after the fight put back, then Remap let go")

-- A temp value first (never saved: nothing to put back after a crash), read back.
local temps = {}
C_CVar = { SetTempCVar = function(k, v) temps[k] = v end, RemoveTempCVar = function(k) temps[k] = nil end }
local getCVar = GetCVar
GetCVar = function(k) return temps[k] or W.cvars[k] end
W.writes = {}
open()
check(GetCVar(AXIS) == "1" and temps[AXIS] == "1" and #W.writes == 0 and ns.db.ringAxisSaved == nil and lastHold() == true, "temp: on as a temp value, nothing written or saved, Remap held")
press("PAD2", true)
nextFrame()
check(temps[AXIS] == nil and GetCVar(AXIS) == "0" and W.cvars[AXIS] == "0" and #W.writes == 2 and lastHold() == false, "temp: the close removes it, flips the saved value and back (the controller refreshes), then Remap let go")
-- A client that takes the call but doesn't apply it: removed again, the saved write instead.
local removed
C_CVar = { SetTempCVar = function() end, RemoveTempCVar = function(k) removed = k end }
W.writes = {}
open()
check(removed == AXIS and W.cvars[AXIS] == "1" and ns.db.ringAxisSaved == "0" and #W.writes == 1, "temp: not read back: removed, the saved write instead")
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "0" and ns.db.ringAxisSaved == nil and #W.writes == 2, "temp: then put back as before")
C_CVar, GetCVar = nil, getCVar

-- A button the layout moves (L1 as the right modifier, PADRTRIGGER) held as the ring opens: no CVar change, which would
-- drop our config under it, so its release comes as the key it went down as. A still fires.
ns.Remap.Outputs = function() return { L1 = "PADRTRIGGER", L2 = "PADLTRIGGER", R1 = "PADLSHOULDER" } end
IsKeyDown = function(k) return k == "PADRTRIGGER" end
W.cvars[AXIS], W.writes = "0", {}
open()
check(ring.shown and W.cvars[AXIS] == "0" and #W.writes == 0 and ns.db.ringAxisSaved == nil and lastHold() == true, "moved: L1 held as the right modifier: the keys stay off, Remap held")
aim(90)
check(press("PAD1", true) == nil and press("PAD1", false) == "spell 639", "moved: A fires the slot aimed at")
nextFrame()
check(#W.writes == 0 and W.cvars[AXIS] == "0" and lastHold() == false, "moved: nothing to put back, Remap let go")
IsKeyDown = function(k) return k == "PADLTRIGGER" end
open()
check(W.cvars[AXIS] == "1" and #W.writes == 1, "moved: a held button on its native key (L2 as the left modifier) leaves the keys on")
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "0" and lastHold() == false, "moved: then put back as before")
ns.Remap.Outputs, IsKeyDown = nil, function() return false end

-- Stale pick: a held ring opened with its stick already pushed ignores that slot until the stick re-centres or moves
-- to another one.
aim(90)
press("PADDRIGHT", true)
check(ring.shown and ring.attrs["ps-stale"] == 3 and Rings.Trace[#Rings.Trace]:find("stale=3", 1, true), "stale: opened with the stick on slot 3, the ringlog says so")
check(press("PADDRIGHT", false) == nil and not ring.shown, "stale: released still there: a Hold ring closes, nothing fired")
aim(90)
press("PADDRIGHT", true)
aim(180)
check(press("PADDRIGHT", false) == "item item:6948", "stale: moved to another slot, that one fires")
aim(90)
press("PADDRIGHT", true)
aim(180)
press("PADRSTICKDOWN", true)
aim(90)
check(press("PADDRIGHT", false) == "spell 639", "stale: moved off and back, slot 3 fires")
aim(90)
press("PADDRIGHT", true)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == nil and ring.shown and ring.attrs["ps-stale"] == nil, "stale: its key released in the middle: still open, slot 3 aimable again")
aim(90)
press("PADRSTICKRIGHT", true)
aim(0, 0)
check(press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "stale: then a flick to slot 3 fires it")
press("PADDRIGHT", false)
aim(0, 0)
open()
check(ring.attrs["ps-stale"] == nil, "stale: opened centred, nothing ignored")
press("PAD2", true)
assert(Rings.SetShow(heals.id, "toggle"))
aim(90)
press("PADDRIGHT", true)
check(press("PADDRIGHT", false) == nil and ring.shown, "stale: a Toggle ring released still there stays open, nothing fired")
check(press("PAD2", true) == nil and not ring.shown, "stale: then B closes it")
assert(Rings.SetShow(heals.id, "hold"))
nextFrame()

-- An apply that fails is reported once; after one that works, the next failure is reported again.
ns.db.options.debug = true
local function failures()
	local n = 0
	for _, line in ipairs(ns.db.debugLog) do if line:find("rings apply failed", 1, true) then n = n + 1 end end
	return n
end
local function failApply()
	ring.SetAttribute = function() error("boom") end
	ns.Fire("FCT_ACTIVE_CHANGED")
	ring.SetAttribute = nil
end
failApply()
failApply()
check(failures() == 1, "failed: reported once while it keeps failing")
ns.Fire("FCT_ACTIVE_CHANGED")
failApply()
check(failures() == 2, "failed: after an apply that works, the next failure is reported")
ns.db.options.debug = false

-- Native sticks: while a held ring aims with one stick, the other stays the game's own analog stick. pass (BACKGROUND,
-- propagates) sees every stick event; block (TOOLTIP, doesn't) goes up only just before the aiming stick's virtual
-- twin. One frame of events as the game sends them: raw sticks in order, then their twins; each goes to block when it
-- is shown (kept from the game), else on through pass to the game. Then pass's OnUpdate ends the frame.
local pass, block = frames.ForeverControllerTweaksRingStickPass, frames.ForeverControllerTweaksRingStickBlock
local ORDER = { "Left", "Right", "Gyro" }
local function sticksFrame(raws, twins)
	local reached, events = {}, {}
	for _, raw in ipairs(ORDER) do if raws[raw] then events[#events + 1] = raw end end
	for _, raw in ipairs(ORDER) do if raws[raw] and twins ~= false then events[#events + 1] = Rings.TWIN[raw] end end
	for _, stick in ipairs(events) do
		if block.shown then
			block.scripts.OnGamePadStick(block, stick, 0, 1, 1)
		else
			if pass.shown then pass.scripts.OnGamePadStick(pass, stick, 0, 1, 1) end
			reached[stick] = true
		end
	end
	local blockUp = block.shown
	if pass.shown then pass.scripts.OnUpdate(pass, 1 / 30) end
	return reached, blockUp
end
check(pass.parent == UIParent and block.parent == UIParent and not pass.protected and not block.protected, "sticks: pass and block are our own insecure frames under UIParent")
check(pass.strata == "BACKGROUND" and pass.propagate == true and pass.stickOn == true and block.strata == "TOOLTIP" and block.propagate == false and block.stickOn == true, "sticks: pass propagates at BACKGROUND, block doesn't at TOOLTIP, both set up at load")
check(pass.mouse == false and block.mouse == false and pass.alpha == 0 and block.alpha == 0 and pass.w == 1 and block.h == 1 and not pass.padButtons and not block.padButtons, "sticks: no mouse, no buttons, invisible, 1 x 1")
check(not pass.shown and not block.shown, "sticks: both hidden with no ring")
nextFrame()
W.cvars[AXIS], W.writes = "0", {}
-- A right-stick ring.
open()
check(pass.shown and not block.shown, "right aim: pass up, block down")
local reached, blockUp = sticksFrame({ Left = true, Right = true })
check(reached.Movement and not reached.Camera and not blockUp and not block.shown, "right aim, both raw sticks: Movement reaches the game, Camera is swallowed, block down after")
reached = sticksFrame({ Right = true })
check(reached.Right and not reached.Camera, "right aim, only Right fired: block up at Right, Camera swallowed")
reached = sticksFrame({ Left = true, Right = true, Gyro = true })
check(reached.Movement and reached.Look and not reached.Camera, "right aim with the gyro: Look is left alone")
reached = sticksFrame({ Left = true })
check(reached.Movement and not block.shown, "right aim, only the left stick: it walks")
-- A twin that never came: the end of the frame takes block down and wipes the frame.
pass.scripts.OnGamePadStick(pass, "Right")
check(block.shown, "end of frame: block up at Right")
pass.scripts.OnUpdate(pass, 1 / 30)
check(not block.shown, "end of frame: block down though Camera never came")
pass.scripts.OnGamePadStick(pass, "Left")
pass.scripts.OnGamePadStick(pass, "Right")
check(not block.shown, "end of frame: Left fired, block waits for Movement")
pass.scripts.OnUpdate(pass, 1 / 30)
reached = sticksFrame({ Left = true })
check(reached.Movement and not block.shown, "end of frame: the wait is wiped, the next frame's Movement still walks")
-- The aiming stick still fires through its keys.
aim(90)
local flicked = press("PADRSTICKRIGHT", true) == nil
aim(90, 0.3)
check(flicked and press("PADRSTICKRIGHT", false) == "spell 639" and not ring.shown, "right aim: the ring aims with the right stick and fires")
check(not pass.shown and not block.shown, "closed with the stick near the middle: pass down")
nextFrame()
-- A stick already pushed as the ring opens keeps running natively: the keys come on at once.
W.sticks = { { x = 0, y = 0.9 }, { x = 0, y = 0 } }
press("PADDRIGHT", true)
check(ring.shown and W.cvars[AXIS] == "1" and pass.shown, "running as the ring opens: the keys on at once, the left stick still the game's")
reached = sticksFrame({ Left = true, Right = true })
check(reached.Movement and not reached.Camera, "running as the ring opens: Movement goes on")
press("PAD2", true)
nextFrame()
check(W.cvars[AXIS] == "0", "closed: the CVar put back")
-- A left-stick ring: Movement is swallowed, Camera goes on; a raw Right reaching block is harmless.
assert(Rings.SetStick(heals.id, "left"))
open()
reached, blockUp = sticksFrame({ Left = true, Right = true })
check(not reached.Movement and reached.Camera and not blockUp, "left aim: Movement swallowed, Camera reaches the game, block down after")
reached = sticksFrame({ Right = true })
check(reached.Camera, "left aim, only the right stick: the camera moves")
press("PAD2", true)
nextFrame()
assert(Rings.SetStick(heals.id, "right"))
-- Removed: nothing binds the free stick's keys to movement or the camera, and the free frames are gone.
local MOVES = { MOVEFORWARD = true, MOVEBACKWARD = true, STRAFELEFT = true, STRAFERIGHT = true, TURNLEFT = true, TURNRIGHT = true, PITCHUP = true, PITCHDOWN = true }
local function movesBound()
	for _, list in ipairs({ W.bindings, W.prio }) do
		for _, b in pairs(list) do if b.command and MOVES[b.command] then return true end end
	end
end
open()
local rightOpen = movesBound()
press("PAD2", true)
assert(Rings.SetStick(heals.id, "left"))
open()
local leftOpen = movesBound()
press("PAD2", true)
nextFrame()
check(not (rightOpen or leftOpen or movesBound()), "removed: no movement or camera binding, open or closed")
check(not (frames.ForeverControllerTweaksRingFree or frames.ForeverControllerTweaksRingFreeWatch or frames.ForeverControllerTweaksRingKeyWait or frames.ForeverControllerTweaksRingStickHold), "removed: the free frames and the old hold frame don't exist")
assert(Rings.SetStick(heals.id, "right"))
-- A touch ring aims with no stick: nothing shown.
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
check(ring.shown and not pass.shown and not block.shown, "touch: pass and block stay down")
secure(ring.RunAttribute, ring, "_close")
nextFrame()
aim(0, 0)

-- The Stick setting: stored per ring for the snippets; Left aims with the left stick wherever the ring opens, Dynamic
-- with the left on a face button and the right on a D-pad button. The release reads that stick only.
local function aimLeft(degrees)
	local a = math.rad(degrees)
	W.sticks = { { x = math.sin(a), y = math.cos(a) }, { x = 0, y = 0 } }
end
for _, stick in ipairs({ "left", "dynamic", "right" }) do
	assert(Rings.SetStick(heals.id, stick))
	check(ring.attrs[p .. "s"] == stick, "stick: " .. stick .. " stored for the snippets")
end
assert(Rings.SetStick(heals.id, "left"))
W.combat = true
press("PADDRIGHT", true)
check(ring.attrs["ps-aim"] == 1 and ring.attrs["ps-aimside"] == "left", "stick: left from a D-pad button aims with the left stick")
check(W.prio.PADLSTICKUP and W.prio.PADLSTICK and not W.prio.PADRSTICKUP, "keys: aiming left binds the left stick's keys")
aim(0)
check(press("PADDRIGHT", false) == nil and not ring.shown, "stick: left, the right stick doesn't pick: the release closes, nothing fired")
press("PADDRIGHT", true)
aimLeft(90)
check(press("PADDRIGHT", false) == "spell 639", "stick: left, the left stick picks")
W.combat = false
assert(Rings.SetStick(heals.id, "dynamic"))
W.combat = true
press("PADDRIGHT", true)
check(ring.attrs["ps-aim"] == 2 and ring.attrs["ps-aimside"] == "right", "stick: dynamic on a D-pad button aims with the right stick")
aim(90)
check(press("PADDRIGHT", false) == "spell 639", "stick: dynamic on D-pad right, the right stick picks")
press("PAD1", true)
check(ring.attrs["ps-aim"] == 1 and ring.attrs["ps-aimside"] == "left", "stick: dynamic on a face button aims with the left stick")
aim(90)
check(press("PAD1", false) == nil and not ring.shown, "stick: dynamic on a face button, the right stick doesn't pick")
press("PAD1", true)
aimLeft(0)
check(press("PAD1", false) == "spell 133", "stick: dynamic on a face button, the left stick picks")
W.combat = false
assert(Rings.SetStick(heals.id, "right"))
assert(ns.Face.SetCellEntry("DR", "T", nil))

-- On a back paddle without a role: the same route on RT's layer, armed through the paddle router's name (a handle
-- can't pass RunAttribute); a dynamic ring aims with the right stick there.
local realDevice = ns.Device.Current
ns.Device.Current = function() return { key = "054c/0ce6", raw = { P1 = { button = 16 } } } end
ns.Fire("FCT_LAYOUT_CHANGED", "device")
assert(ns.Face.Routable("P1", "R", ringEntry) and ns.Face.SetCellEntry("P1", "R", ringEntry))
local paddle1 = frames.ForeverControllerTweaksPaddle1
check(paddle1.attrs["ps-ring-right"] == heals.id and paddle1.attrs["frameref-rings"] == ring and ring.attrs["frameref-ForeverControllerTweaksPaddle1"] == paddle1 and W.bindings.PADPADDLE1, "paddle: the ring on its router, known to the ring by name")
W.combat = true
W.held = { [15] = true }
aim(0, 0)
check(press("PADPADDLE1", true) == nil and ring.shown and ring.attrs["ps-mode"] == "hold", "paddle: RT + paddle 1 opens the ring")
W.held = {}
aim(90)
check(press("PADPADDLE1", false) == "spell 639" and not ring.shown and paddle1.attrs.typerelease == "spell", "paddle: the release fires the aimed slot and closes")
check(press("PADPADDLE1", true) == false and not ring.shown, "paddle: no top cell, nothing opens")
W.combat = false
assert(Rings.SetStick(heals.id, "dynamic"))
W.combat = true
W.held = { [15] = true }
aim(0, 0)
press("PADPADDLE1", true)
check(ring.attrs["ps-aim"] == 2 and ring.attrs["ps-aimside"] == "right", "paddle: a dynamic ring aims with the right stick")
aim(90)
check(press("PADPADDLE1", false) == "spell 639", "paddle: dynamic, the right stick picks")
W.held = {}
W.combat = false
assert(Rings.SetStick(heals.id, "right"))
assert(ns.Face.SetCellEntry("P1", "R", nil))
check(W.bindings.PADPADDLE1 == nil, "paddle: given back, native")
ns.Device.Current = realDevice
ns.Fire("FCT_LAYOUT_CHANGED", "device")

-- After a held ring closes, its aiming stick is still pushed: the same pass and block keep that stick's twin from the
-- game until it is back near the middle (or a second has passed outside a cast), the other stick going on. Shown and
-- hidden in combat; the setup calls are never made there.
local stickCalls = 0
local realEnable, realPropagate = Frame.EnableGamePadStick, Frame.SetPropagateKeyboardInput
Frame.EnableGamePadStick = function(...) stickCalls = stickCalls + 1 return realEnable(...) end
Frame.SetPropagateKeyboardInput = function(...) stickCalls = stickCalls + 1 return realPropagate(...) end
W.combat = true
local function openHeld() secure(ring.RunAttribute, ring, "_open", heals.id, "hold") end
openHeld()
check(pass.shown, "combat: a held ring raises pass")
aim(90)
secure(ring.RunAttribute, ring, "_close")
check(not pass.shown, "combat: closed, pass down until the hold-off")
Rings.HoldStick("right", 2)
check(pass.shown and not block.shown, "hold-off: shown after a close with the right stick pushed")
reached = sticksFrame({ Left = true, Right = true })
check(reached.Movement and not reached.Camera, "hold-off: Camera kept, the left stick walks")
pass.scripts.OnUpdate(pass, 0.5)
check(pass.shown, "hold-off: still pushed, still held")
aim(0, 0)
pass.scripts.OnUpdate(pass, 1 / 60)
check(not pass.shown and not block.shown, "hold-off: back in the middle, both down")
Rings.HoldStick("right", 2)
check(not pass.shown, "hold-off: nothing while the stick is already in the middle")
aimLeft(90)
Rings.HoldStick("left", 1)
reached = sticksFrame({ Left = true, Right = true })
check(not reached.Movement and reached.Camera, "hold-off: aiming left, Movement kept, the camera moves")
pass.scripts.OnUpdate(pass, 0.6)
check(pass.shown, "hold-off: within the second")
pass.scripts.OnUpdate(pass, 0.5)
check(not pass.shown and not block.shown, "hold-off: a reading that never settles is let go after a second")
-- A ring opened again during a hold-off takes pass over: no timer while it is open.
aimLeft(90)
Rings.HoldStick("left", 1)
openHeld()
pass.scripts.OnUpdate(pass, 2)
check(pass.shown and pass.side == "right" and not pass.left, "hold-off: a ring opened again takes it over, no timer")
secure(ring.RunAttribute, ring, "_close")
nextFrame()
-- Through a cast (a heal aimed with the left stick): the second doesn't run while the player casts or channels; the
-- stick back in the middle still lets go; after the cast the cap runs on.
local castEvent = function(event) pass.scripts.OnEvent(pass, event, "player") end
aimLeft(90)
Rings.HoldStick("left", 1)
castEvent("UNIT_SPELLCAST_START")
pass.scripts.OnUpdate(pass, 2.5)
check(pass.shown, "hold-off cast: a 2.5 s cast keeps the left stick held")
castEvent("UNIT_SPELLCAST_SUCCEEDED")
castEvent("UNIT_SPELLCAST_STOP")
pass.scripts.OnUpdate(pass, 0.5)
check(pass.shown, "hold-off cast: after the cast the second starts running")
pass.scripts.OnUpdate(pass, 0.6)
check(not pass.shown, "hold-off cast: and the cap lets go a second after the cast ended")
Rings.HoldStick("left", 1)
castEvent("UNIT_SPELLCAST_CHANNEL_START")
castEvent("UNIT_SPELLCAST_SUCCEEDED")
pass.scripts.OnUpdate(pass, 5)
check(pass.shown, "hold-off cast: a channel keeps it too, its SUCCEEDED at the start ends nothing")
W.sticks[1] = { x = 0.1, y = 0 }
pass.scripts.OnUpdate(pass, 1 / 60)
check(not pass.shown, "hold-off cast: mid-channel, the stick back in the middle lets go")
castEvent("UNIT_SPELLCAST_CHANNEL_STOP")
aimLeft(90)
Rings.HoldStick("left", 1)
castEvent("UNIT_SPELLCAST_START")
ns.Fire("PLAYER_ENTERING_WORLD")
pass.scripts.OnUpdate(pass, 1.1)
check(not pass.shown, "hold-off cast: entering the world drops a cast whose stop never came")
aim(0, 0)
check(stickCalls == 0, "combat: opening, closing and the hold-off never call EnableGamePadStick or SetPropagateKeyboardInput")
Frame.EnableGamePadStick, Frame.SetPropagateKeyboardInput = realEnable, realPropagate
W.combat = false
nextFrame()

-- The snippet picks as Rings.SlotAt does, all round.
local target = frame("Target", "SecureActionButtonTemplate")
-- A handle can't be passed: the ring knows a button by a frame ref name, as Face sets one per router.
SecureHandlerSetFrameRef(ring, "Target", target)
secure(ring.RunAttribute, ring, "_open", heals.id, "hold")
aim(90)
secure(ring.RunAttribute, ring, "_release", target)
check(target.attrs.typerelease == nil and ring.shown, "snippet: a handle passed to RunAttribute arrives as nil: nothing armed, nothing closed")
secure(ring.RunAttribute, ring, "_close")
check(ring.attrs["frameref-ForeverControllerTweaksFaceBottom"] == frames.ForeverControllerTweaksFaceBottom and ring.attrs["frameref-ForeverControllerTweaksDpadRight"] == frames.ForeverControllerTweaksDpadRight, "face: the ring holds a frame ref to every router, by its name")
for degrees = 0, 359, 7 do
	aim(0, 0)
	secure(ring.RunAttribute, ring, "_open", heals.id, "hold")
	aim(degrees)
	secure(ring.RunAttribute, ring, "_release", "Target")
	local i = Rings.SlotAt(W.sticks[2].x, W.sticks[2].y, 8)
	check(target.attrs.typerelease == ring.attrs[p .. "t" .. i], "snippet: same pick as SlotAt at " .. degrees)
end
-- A release that didn't open a held ring does nothing.
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
secure(ring.RunAttribute, ring, "_release", "Target")
check(target.attrs.typerelease == nil and ring.shown, "snippet: a touch ring ignores a release")
secure(ring.RunAttribute, ring, "_close")

-- A vehicle takes the routed keys away: the ring closes.
secure(ring.RunAttribute, ring, "_open", heals.id, "hold")
cond("vehicleui", true)
check(not ring.shown and ring.attrs["ps-ring"] == nil, "guard: a vehicle closes the ring")
cond("vehicleui", false)

-- On a touch button: a tap opens, a tap on a slot fires it and closes, a tap outside closes.
assert(ns.Touch.Set("enabled", true))
assert(ns.Touch.SetEntry("left", 1, ringEntry))
local touch = ns.Touch.Button("left", 1)
check(touch.attrs["ps-ring-T"] == heals.id and touch.attrs["frameref-rings"] == ring, "touch: the ring on the button")
nextFrame()
W.combat = true
local writes = #W.writes
check(click(touch, true) == nil and ring.shown and ring.attrs["ps-mode"] == "touch", "touch: a tap opens")
check(W.cvars.GamePadStickAxisButtons == "0" and #W.writes == writes and lastHold() == false, "touch: a touch ring leaves GamePadStickAxisButtons and Remap alone")
local slot1 = frames.ForeverControllerTweaksRingSlot1
check(click(slot1, false) == "spell 133" and not ring.shown, "touch: a slot tap fires and closes")
click(touch, true)
check(click(touch, true) == nil and not ring.shown, "touch: a second tap on the button closes")
click(touch, true)
local catcher = frames.ForeverControllerTweaksRingCatcher
secure(run, catcher.env, "self,button,down", catcher.attrs._onclick, catcher, "LeftButton", false)
check(not ring.shown, "touch: a tap outside closes")
W.combat = false

-- Healer mode (design/healer-mode.md): spells, spell groups and items only; a 7-place ring per binding, always Hold,
-- Dynamic, Compact, each place on its unit; a native crossbar cell copies its slot's spell and gives it back when off.
check(Rings.HealerAllowed(Actions.Find("spell:133")) and Rings.HealerAllowed(Actions.Find("spellgroup:Holy Light")) and Rings.HealerAllowed(Actions.Find("item:6948")), "healer: spells, spell groups and items can")
check(select(2, Rings.HealerAllowed(Actions.Find("mount:7"))) == "This button holds a mount." and select(2, Rings.HealerAllowed(Actions.Find("game:sit"))) == "This button holds a game action." and select(2, Rings.HealerAllowed(nil)) == "This button is empty.", "healer: other kinds and an empty button can't, with why")
check(select(2, ns.Face.SetHealer("FB", "T", true)) == "This button holds a ring." and not ns.Face.CellEntry("FB", "T").healer, "healer: refused on a ring cell, nothing changed")
W.combat = true
check(select(2, ns.Face.SetHealer("FB", "T", false)) == "out of combat only", "healer: switched out of combat only")
W.combat = false

-- Shadow slots (Actions.lua, its own spec) stand in: a spell placed on one is slot 150.
local shadow, releaseShadow = Actions.Shadow, Actions.ReleaseShadow
Actions.Shadow, Actions.ReleaseShadow = function() return 150 end, function() return true end
local storage = {}
C_ActionBar.HasAction = function(slot) return storage[slot] ~= nil end
function GetActionInfo(slot) local a = storage[slot]; if a then return a[1], a[2] end end
storage[183] = { "spell", 133 }
check(select(2, ns.Face.SetHealer("DU", "T", true, 2)) == "This button is empty." and ns.Face.CellEntry("DU", "T") == nil, "healer: an empty native slot can't")
assert(ns.Face.SetHealer("DU", "T", true, 1))
local copy = ns.Face.CellEntry("DU", "T")
check(copy and copy.id == "spell:133" and copy.healer and copy.native and storage[183], "healer: a native cell copies its slot's spell, the slot kept")
local hid = "hspell133"
check(dpad.attrs["ps-ring-top-1"] == hid and W.bindings.PADDUP, "healer: the D-pad cell opens its healer ring")
local hp, units = "r" .. hid, true
for i, unit in ipairs(Rings.HealerUnits) do units = units and ring.attrs[hp .. "u" .. i] == unit and ring.attrs[hp .. "t" .. i] == "spell" and ring.attrs[hp .. "v" .. i] == 133 end
check(ring.attrs[hp .. "n"] == 7 and ring.attrs[hp .. "s"] == "dynamic" and ring.attrs[hp .. "h"] == "hold" and ring.attrs[hp .. "y"] == "compact" and units and ring.attrs[hp .. "u8"] == nil, "healer: 7 places on You, Party 1-4, Target, Focus, all the spell, Hold, Dynamic, Compact")
check(Rings.Healer(hid).healer and Rings.Healer(hid).icon == copy.icon, "healer: the ring the display draws")

-- In combat: a release on a unit casts there; missing, hostile, centred: nothing. Dead allies stay pickable.
W.units = { player = "friend", party1 = "friend", party3 = "dead", target = "hostile" }
W.combat = true
local STEP = 360 / 7
local function heal(at)
	aim(0, 0)
	press("PADDUP", true)
	if at then aim(at) end
	return press("PADDUP", false)
end
check(heal(0) == "spell 133" and dpad.attrs.unit == "player" and dpad.attrs.checkselfcast == nil and dpad.attrs.checkmouseovercast == nil, "healer: You, cast on the player, no self/mouseover cast checks")
check(heal(STEP) == "spell 133" and dpad.attrs.unit == "party1" and not ring.shown, "healer: Party 1")
check(heal(3 * STEP) == "spell 133" and dpad.attrs.unit == "party3", "healer: a dead ally is pickable")
check(heal(2 * STEP) == nil and not ring.shown and not next(W.prio), "healer: a missing Party 2, nothing cast, the ring closes")
check(heal(5 * STEP) == nil and heal(6 * STEP) == nil and heal() == nil and not ring.shown, "healer: hostile Target, no Focus, the centre: nothing")
aim(0, 0)
press("PADDUP", true)
check(dpad.attrs.unit == nil, "healer: the next press takes the unit off the button")
aim(STEP)
press("PADRSTICKRIGHT", true)
check(ring.attrs["ps-pick"] == 2, "healer: a stick key keeps Party 1")
aim(5 * STEP)
press("PADRSTICKLEFT", true)
check(ring.attrs["ps-pick"] == nil, "healer: rolled on to the hostile Target, the kept pick is dropped")
aim(0, 0)
check(press("PADDUP", false) == nil and not ring.shown, "healer: then let go, nothing cast")
check(Rings.HealerRing(Actions.Find("item:6948")) == nil and Rings.HealerRing(copy) == hid, "healer: in combat no new ring is written; a written one still opens")
W.combat = false
secure(ring.RunAttribute, ring, "_open", heals.id, "touch")
check(frames.ForeverControllerTweaksRingSlot1.attrs.unit == nil and frames.ForeverControllerTweaksRingSlot1.attrs.checkselfcast == true, "healer: an ordinary ring's slot has no unit, cast checks on")
secure(ring.RunAttribute, ring, "_close")

-- Last target (design/1.5.0.md 6): off by default; on, a binding's middle release casts on the place it last healed,
-- only while that unit can be helped. It remembers the place, per binding and character.
check(not ns.Face.CellEntry("DU", "T").healerLast and Rings.Healer(hid).middle == "cancel" and ring.attrs[hp .. "m"] == nil, "healer last: off by default")
check(select(2, ns.Face.SetHealerLast("DD", "T", true)) == "Healer mode is off on this button.", "healer last: only on a button in Healer mode")
W.combat = true
check(select(2, ns.Face.SetHealerLast("DU", "T", true)) == "out of combat only", "healer last: switched out of combat only")
W.combat = false
assert(ns.Face.SetHealerLast("DU", "T", true))
local lid = hid .. "_last"
check(ns.Face.CellEntry("DU", "T").healerLast and dpad.attrs["ps-ring-top-1"] == lid and ring.attrs["r" .. lid .. "m"] == "last" and Rings.Healer(lid).middle == "last", "healer last: the binding's own ring, its middle written")
W.combat = true
check(heal(STEP) == "spell 133" and dpad.attrs.unit == "party1" and ns.Face.CharDB().ringLast[lid][1] == 2, "healer last: a cast remembers the place")
check(heal() == "spell 133" and dpad.attrs.unit == "party1" and not ring.shown, "healer last: let go in the middle, cast on Party 1 again")
W.units.party1 = "hostile"
check(heal() == nil and not ring.shown, "healer last: the place can't be helped now, nothing cast")
W.units.party1 = nil
check(heal() == nil and not ring.shown, "healer last: the place is empty, nothing cast")
W.units.party1 = "friend"
check(heal(0) == "spell 133" and dpad.attrs.unit == "player" and heal() == "spell 133" and dpad.attrs.unit == "player", "healer last: aiming elsewhere moves it")
check(Rings.LiveIcon(lid) ~= nil and ns.Face.CellEntry("DU", "T").icon == copy.icon, "healer last: the button keeps the spell's icon")
W.combat = false
ns.Fire("PLAYER_ENTERING_WORLD")
check(ring.attrs["r" .. lid .. "l"] == 1, "healer last: the place restored after a reload")
assert(ns.Face.SetHealerLast("DU", "T", false))
check(not ns.Face.CellEntry("DU", "T").healerLast and dpad.attrs["ps-ring-top-1"] == hid, "healer last: off again, the plain healer ring")
W.combat = true
check(heal() == nil, "healer last: off, the middle casts nothing")
W.combat = false

-- Off: the copy goes, the cell is native again; a routed entry keeps its action.
assert(ns.Face.SetHealer("DU", "T", false))
check(ns.Face.CellEntry("DU", "T") == nil and dpad.attrs["ps-ring-top-1"] == nil and storage[183], "healer off: the copy is dropped, the slot fires natively again")
assert(ns.Face.SetCellEntry("FB", "T", Actions.Find("spell:133")))
assert(ns.Face.SetHealer("FB", "T", true))
check(ns.Face.CellEntry("FB", "T").healer and router.attrs["ps-ring-top"] == hid, "healer: a routed spell cell opens the ring")
assert(ns.Face.SetHealerLast("FB", "T", true))
assert(ns.Face.SetHealer("FB", "T", false))
check(ns.Face.CellEntry("FB", "T").healerLast == nil, "healer off: Last target goes with it")
check(ns.Face.CellEntry("FB", "T").id == "spell:133" and not ns.Face.CellEntry("FB", "T").healer and router.attrs["ps-ring-top"] == nil, "healer off: a routed cell keeps its spell")
assert(ns.Face.SetCellEntry("FB", "T", ringEntry))
GamepadActionBarBindingUtil = nil
C_ActionBar.HasAction = function() return false end
function GetActionInfo() end

-- A touch button: a tap opens the healer ring; a tapped place casts on its unit, a missing one does nothing.
assert(ns.Touch.SetEntry("left", 2, Actions.Find("spell:133")))
check(select(2, ns.Touch.SetHealer("left", 1, "T", true)) == "This button holds a ring.", "touch healer: refused on a ring")
assert(ns.Touch.SetHealer("left", 2, "T", true))
local touch2 = ns.Touch.Button("left", 2)
check(touch2.attrs["ps-ring-T"] == hid and touch2.attrs["ps-action-T"] == nil and touch2.view.text.badge, "touch healer: the button opens the healer ring and wears the badge")
W.combat = true
click(touch2, true)
check(ring.shown and click(frames.ForeverControllerTweaksRingSlot3, false) == false and ring.shown, "touch healer: a missing Party 2 tapped: nothing, still open")
check(click(slot1, false) == "spell 133" and slot1.attrs.unit == "player" and not ring.shown, "touch healer: You tapped: cast on the player, closed")
W.combat = false
assert(ns.Touch.SetHealer("left", 2, "T", false))
check(touch2.attrs["ps-ring-T"] == nil and touch2.attrs["ps-action-T"] and not ns.Touch.Entry("left", 2).healer and not touch2.view.text.badge, "touch healer off: the spell on its slot again, no badge")
assert(ns.Touch.SetEntry("left", 2, nil))
Actions.Shadow, Actions.ReleaseShadow = shadow, releaseShadow
W.units = {}

-- Middle (design/1.5.0.md 1): Cancel by default; with Use last a Hold ring let go in the middle, or A with nothing
-- aimed, fires the slot this character fired last, and the ring's buttons show its icon. Every fire records the slot
-- (in combat, by the snippets); it is saved per character with the slot's action and dropped when that changes.
assert(Rings.SetStick(heals.id, "right"))
assert(Rings.SetShow(heals.id, "hold"))
check(heals.middle == "cancel" and ring.attrs[p .. "m"] == nil, "middle: Cancel by default, nothing written")
check(not Rings.SetMiddle(heals.id, "first") and heals.middle == "cancel", "middle: cancel or last only")
W.combat = true
check(select(2, Rings.SetMiddle(heals.id, "last")) == "Controller Tweaks changes rings out of combat only.", "middle: set out of combat only")
aim(0, 0)
press("PAD1", true)
aim(90)
check(press("PAD1", false) == "spell 639" and ring.attrs[p .. "l"] == 3, "last: a fire records its slot, in combat")
local function annLast() return ns.Face.CharDB().ringLast[heals.id] end
check(annLast()[1] == 3 and annLast()[2] == "spellgroup:Holy Light", "last: saved for this character with the slot's action")
press("PAD1", true)
aim(0, 0)
check(press("PAD1", false) == nil and not ring.shown, "last: with Cancel, let go in the middle: nothing")
check(Rings.LiveIcon(heals.id) == Rings.Icon(heals), "live icon: with Cancel, the ring's own")
W.combat = false
assert(Rings.SetMiddle(heals.id, "last"))
check(heals.middle == "last" and ring.attrs[p .. "m"] == "last" and ring.attrs[p .. "l"] == 3, "last: Use last written, the pick written back")
local hl = heals.slots[3].icon
check(Rings.LiveIcon(heals.id) == hl and ns.SlotView.EntryIcon(ns.Face.CellEntry("FB", "T")) == hl and touch.view.fallback == hl, "live icon: the last slot's on cells and touch buttons")
W.combat = true
press("PAD1", true)
check(press("PAD1", false) == "spell 639" and not ring.shown, "last: Hold let go in the middle fires the last slot")
press("PAD1", true)
aim(180)
check(press("PAD1", false) == "item item:6948" and annLast()[1] == 5 and touch.view.fallback == heals.slots[5].icon, "last: an aimed fire as before, now the last; the buttons follow in combat")
press("PAD1", true)
aim(45)
check(press("PAD1", false) == nil and ring.attrs[p .. "l"] == 5 and annLast()[1] == 5, "last: an empty slot fires nothing and isn't remembered")
aim(0, 0)
press("PAD1", true)
check(keyUp("PAD1") == "item item:6948" and not ring.shown and press("PAD1", false) == nil, "last: A with nothing aimed fires the last slot")
press("PAD1", true)
press("PAD2", true)
check(not ring.shown and press("PAD1", false) == nil, "last: B still cancels")
click(touch, true)
check(ring.shown and click(slot1, false) == "spell 133" and annLast()[1] == 1, "last: a tapped slot is remembered")
W.combat = false
assert(Rings.SetShow(heals.id, "toggle"))
W.combat = true
press("PAD1", true)
check(press("PAD1", false) == nil and ring.shown, "last: a Toggle ring's release only opens it")
check(press("PAD1", true) == nil and not ring.shown and press("PAD1", false) == nil, "last: the button again only closes it")
W.combat = false
assert(Rings.SetShow(heals.id, "hold"))
assert(Rings.SetSlot(heals.id, 1, Actions.Find("game:sit")))
check(annLast() == nil and ring.attrs[p .. "l"] == nil and Rings.LiveIcon(heals.id) == Rings.Icon(heals), "last: its slot changed, the pick is dropped")
W.combat = true
press("PAD1", true)
check(press("PAD1", false) == nil and not ring.shown, "last: no pick, the middle fires nothing")
W.combat = false
ns.Face.CharDB().ringLast[heals.id] = { 7, "game:sit" }
assert(Rings.SetCount(heals.id, 6))
check(annLast() == nil and ring.attrs[p .. "l"] == nil, "last: a slot past a smaller count is dropped")
assert(Rings.SetCount(heals.id, 8))
ns.Face.CharDB().ringLast[heals.id] = { 7, "game:sit" }
ns.Fire("PLAYER_ENTERING_WORLD")
check(ring.attrs[p .. "l"] == 7 and Rings.LiveIcon(heals.id) == heals.slots[7].icon, "last: restored after a reload while the slot holds it")
check(Rings.LiveIcon(999) == "Interface\\Icons\\INV_Misc_QuestionMark", "live icon: an unknown ring")
-- The marker hides on every button of a ring while it is open (ps-ring), and the touch buttons redraw.
check(touch.view.text.marker == true and not Rings.IsOpen(heals.id), "marker: on the touch button that opens the ring")
W.combat = true
press("PAD1", true)
check(Rings.IsOpen(heals.id) and touch.view.text.marker == false, "marker: hidden while the ring is open, in combat")
press("PAD1", false)
check(not Rings.IsOpen(heals.id) and touch.view.text.marker == true, "marker: back when it closes")
W.combat = false
-- A Dynamic ring opened from a stick press aims with the other stick.
assert(Rings.SetStick(heals.id, "dynamic"))
secure(ring.RunAttribute, ring, "_open", heals.id, "hold", "rstick")
local fromR3 = ring.attrs["ps-aimside"]
secure(ring.RunAttribute, ring, "_close")
secure(ring.RunAttribute, ring, "_open", heals.id, "hold", "lstick")
check(fromR3 == "left" and ring.attrs["ps-aimside"] == "right", "dynamic: R3 aims with the left stick, L3 with the right")
secure(ring.RunAttribute, ring, "_close")
assert(Rings.SetStick(heals.id, "right"))

-- The mouse on an open ring (the game's radial flyout): in every mode the slot under the pointer lights as the aim and
-- shows its tooltip, a left click fires it, a right click closes. A held ring's release (and A) fires the hovered slot
-- when the stick aims at nothing; the stick wins. The secure wraps keep ps-hover only for a pointer that moved.
-- The pointer moving onto or off a slot, as the game runs it: the secure wrap's snippet (only with motion), then the
-- slot's own scripts (View.lua hooks them).
local function enter(slot, motion)
	if motion then secure(run, slot.wraps.OnEnter.header.env, "self", slot.wraps.OnEnter.pre, slot) end
	hooked(slot, "OnEnter", motion)
end
local function leave(slot)
	secure(run, slot.wraps.OnLeave.header.env, "self", slot.wraps.OnLeave.pre, slot)
	hooked(slot, "OnLeave", true)
end
-- What View.lua draws with, as no-ops or recorders.
function Frame:CreateMaskTexture() return frame(nil, nil, self) end
function Frame:CreateFontString() return frame(nil, nil, self) end
function Frame:CreateAnimationGroup() return frame(nil, nil, self) end
function Frame:CreateAnimation() return frame(nil, nil, self) end
ns.UI = ns.UI or { ART = "", Glyph = function(parent) return frame(nil, nil, parent) end }
SOUNDKIT, RAID_CLASS_COLORS = {}, {}
local function color() return { GetRGB = function() return 1, 1, 1 end } end
NORMAL_FONT_COLOR, DISABLED_FONT_COLOR = color(), color()
function UnitExists(unit) return W.units[unit] ~= nil end
function UnitCanAssist(_, unit) return W.units[unit] == "friend" or W.units[unit] == "dead" end
function UnitIsDeadOrGhost(unit) return W.units[unit] == "dead" end
function UnitClass() return "Priest", "PRIEST" end
function UnitHealth() return 1 end
function UnitHealthMax() return 1 end
function SetPortraitTexture() end
function UnitGroupRolesAssigned() return "NONE" end
-- The tooltip: what it shows now, or nil.
local shownTip
GameTooltip = {
	IsOwned = function() return shownTip ~= nil end, Hide = function() shownTip = nil end, Show = function() end,
	SetUnit = function(_, unit) shownTip = "unit " .. unit end, SetSpellByID = function(_, id) shownTip = "spell " .. id end,
	SetItemByID = function(_, id) shownTip = "item " .. id end, SetText = function(_, text) shownTip = "text " .. text end,
}
function GameTooltip_SetDefaultAnchor() end
W.combat = false
assert(Rings.SetMiddle(heals.id, "cancel"))
assert(Rings.SetShow(heals.id, "hold"))
assert(Rings.SetStyle(heals.id, "full"))
local made, create = {}, CreateFrame
function CreateFrame(...) local f = create(...) made[#made + 1] = f return f end
loadModule("Rings", "View")
CreateFrame = create
local display
for _, f in ipairs(made) do if f.parent == ring and not display then display = f end end
local View = Rings.View
local function tick() display.scripts.OnUpdate(display, 0.01) end
local slot = {}
for i = 1, 8 do slot[i] = frames["ForeverControllerTweaksRingSlot" .. i] end
check(slot[3].wraps.OnEnter and slot[3].wraps.OnLeave and slot[3].wrap == slot[3].wraps.OnClick and slot[3].hooks.OnEnter, "mouse: the slots' OnEnter and OnLeave wrapped by the ring, View hooks them (a SetScript would drop the wrap)")

-- Hold, in combat: hover lights and shows the tooltip, leaving clears it; a pointer at rest aims nothing.
W.combat = true
aim(0, 0)
press("PAD1", true)
tick()
enter(slot[3], true)
tick()
check(ring.attrs["ps-hover"] == 3 and View.Focused() == 3 and shownTip == "spell 639", "mouse hold: slot 3 hovered: the aim's highlight and its spell's tooltip")
enter(slot[5], true)
tick()
check(View.Focused() == 5 and shownTip == "item 6948", "mouse hold: an item shows its item tooltip")
leave(slot[5])
tick()
check(ring.attrs["ps-hover"] == nil and View.Focused() == nil and shownTip == nil, "mouse hold: left, cleared")
enter(slot[7], true)
tick()
check(shownTip == "text Sit", "mouse hold: a game action shows its name")
leave(slot[7])
enter(slot[3], false)
tick()
check(ring.attrs["ps-hover"] == nil and View.Focused() == nil and shownTip == nil, "mouse hold: a pointer at rest under the opening ring aims nothing")
check(press("PAD1", false) == nil and not ring.shown, "mouse hold: let go with nothing aimed, nothing fires")

-- Hold release: the hovered slot fires with the stick centred; a pushed stick wins. A fires it too.
aim(0, 0)
press("PAD1", true)
enter(slot[3], true)
check(press("PAD1", false) == "spell 639" and not ring.shown and ring.attrs["ps-hover"] == nil, "mouse hold: let go with slot 3 hovered, stick centred: slot 3 fires, closed")
leave(slot[3])
press("PAD1", true)
enter(slot[3], true)
aim(180)
tick()
check(View.Focused() == 5 and shownTip == nil, "mouse hold: the stick's aim lights over the hovered slot, no tooltip")
check(press("PAD1", false) == "item item:6948" and not ring.shown, "mouse hold: stick pushed at slot 5, slot 3 hovered: slot 5 fires")
leave(slot[3])
aim(0, 0)
press("PAD1", true)
enter(slot[3], true)
check(keyUp("PAD1") == "spell 639" and not ring.shown and press("PAD1", false) == nil, "mouse hold: A with slot 3 hovered fires it")
leave(slot[3])

-- Click: a left click fires the slot, records it and closes; a right click only closes. In combat.
press("PAD1", true)
check(click(slot[3], false) == "spell 639" and ring.attrs[p .. "l"] == 3 and not ring.shown and press("PAD1", false) == nil, "mouse hold: a click on slot 3 fires it (_used), closes; the release then does nothing")
press("PAD1", true)
check(click(slot[3], false, nil, "RightButton") == false and not ring.shown and press("PAD1", false) == nil, "mouse hold: a right click closes, nothing fires")
W.combat = false

-- Toggle: the same hover; the release that opened it ignores the pointer; a click uses the slot.
assert(Rings.SetShow(heals.id, "toggle"))
W.combat = true
press("PAD1", true)
enter(slot[3], true)
check(press("PAD1", false) == nil and ring.shown, "mouse toggle: the opening release ignores a hovered slot")
tick()
check(View.Focused() == 3 and shownTip == "spell 639", "mouse toggle: slot 3 hovered: highlight and tooltip")
leave(slot[3])
tick()
check(View.Focused() == nil and shownTip == nil, "mouse toggle: left, cleared")
check(click(slot[3], false) == "spell 639" and not ring.shown, "mouse toggle: a click on slot 3 fires it, closes")
press("PAD1", true)
press("PAD1", false)
check(click(slot[3], false, nil, "RightButton") == false and not ring.shown, "mouse toggle: a right click closes")
W.combat = false

-- Healer: hover shows the unit; a click on a place without a unit does nothing; on one with a unit, it heals there.
W.units = { player = "friend", party1 = "friend" }
W.combat = true
secure(ring.RunAttribute, ring, "_open", hid, "hold")
tick()
enter(slot[2], true)
tick()
check(View.Focused() == 2 and shownTip == "unit party1", "mouse healer: Party 1 hovered: the unit's tooltip")
leave(slot[2])
check(click(slot[3], false) == false and ring.shown, "mouse healer: a click on a missing Party 2: nothing, still open")
enter(slot[3], true)
check(secure(ring.RunAttribute, ring, "_hover") == false, "mouse healer: a hovered missing unit can't be the aim")
leave(slot[3])
check(click(slot[2], false) == "spell 133" and slot[2].attrs.unit == "party1" and not ring.shown, "mouse healer: a click on Party 1 heals Party 1")
display.scripts.OnHide(display)
check(shownTip == nil, "mouse healer: closed (the display hides with the ring), the tooltip goes")
W.units = {}

-- Touch: unchanged, a tap on a slot fires it; the hover lights and shows the tooltip.
click(touch, true)
tick()
enter(slot[3], true)
check(View.Focused() == 3, "mouse touch: the slot entered is focused")
tick()
check(shownTip == "spell 639", "mouse touch: with its tooltip")
leave(slot[3])
tick()
check(View.Focused() == nil and shownTip == nil, "mouse touch: left, cleared")
check(click(slot[1], false) == "game macrotext" or not ring.shown, "mouse touch: a tap fires and closes")
W.combat = false

-- Renames and icons follow on every binding; deleting a ring clears this character's bindings to it (rings are per
-- character since 1.5.2: another character's ring:<id> is its own ring).
assert(Rings.Rename(heals.id, "Big heals"))
local cell = ns.Face.CellEntry("FB", "T")
check(cell.name == "Open ring: Big heals" and ns.Touch.Entry("left", 1).name == "Open ring: Big heals", "bindings: renamed with the ring")
assert(Rings.SetIcon(heals.id, 77))
check(ns.Face.CellEntry("FB", "T").icon == 77 and Rings.Icon(heals) == 77, "bindings: the icon follows")
local other = assert(Rings.New())
ns.db.chars["Player-0-Bob"] = { cells = { ["054c/0ce6"] = { DD = { R = { id = "ring:" .. heals.id, name = "x" }, B = { id = "spell:133", name = "Fireball" } } } }, touch = { bars = { right = { [2] = { L = { id = "ring:" .. heals.id } } } } } }
ns.db.chars["Player-0-Cy"] = { cells = { ["054c/0ce6"] = { DU = { T = { id = "ring:" .. other.id } } } } }
check(Rings.BindingCount(heals.id) == 2, "delete: this character's bindings counted")
-- A paged cell's pages (ns.Cells): each page a binding of its own.
local annRows = ns.Face.CharDB().cells["054c/0ce6"]
annRows.DR = { L = { { id = "ring:" .. heals.id, name = "x" }, { id = "ring:" .. other.id, name = "y" } } }
annRows.DL = { B = { [3] = { id = "ring:" .. heals.id, name = "x" } } }
check(Rings.BindingCount(heals.id) == 4, "delete: a paged cell counted per page")
assert(Rings.Delete(heals.id))
check(annRows.DR.L[1] == nil and annRows.DR.L[2].id == "ring:" .. other.id and annRows.DL == nil, "delete: a page cleared, the other ring's page kept, an emptied page list and row dropped")
annRows.DR = nil
check(ns.Face.CellEntry("FB", "T") == nil and ns.Touch.Entry("left", 1) == nil, "delete: this character's bindings cleared")
local bob = ns.db.chars["Player-0-Bob"]
check(bob.cells["054c/0ce6"].DD.R.id == "ring:" .. heals.id and bob.touch.bars.right[2].L.id == "ring:" .. heals.id, "delete: another character's bindings (its own ring) untouched")
check(ns.db.chars["Player-0-Cy"].cells["054c/0ce6"].DU.T.id == "ring:" .. other.id, "delete: another ring's binding kept")
check(ring.attrs[p .. "n"] == nil and ring.attrs[p .. "t1"] == nil and ring.attrs[p .. "m"] == nil and ring.attrs[p .. "l"] == nil and router.attrs["ps-ring-top"] == nil and touch.attrs["ps-ring-T"] == nil, "delete: secure attributes gone")
check(ns.Face.CharDB().ringLast[heals.id] == nil, "delete: the last pick goes too")
check(Actions.Find("ring:" .. heals.id) == nil, "delete: gone from the catalog")
for _ = 2, Rings.MAX_RINGS do assert(Rings.New()) end
check(select(2, Rings.New()):find("most there can be", 1, true), "rings: at most " .. Rings.MAX_RINGS)

-- Repair: bad rings, ids, names, counts, icons and slots, and bindings to rings that are gone.
local db = {
	rings = { nextId = "x", list = {
		[1] = { id = 1, name = "  Heals  ", count = 99, slots = { [1] = { id = "spell:133", name = "Fireball", icon = 1 }, [2] = "bad", [13] = { id = "spell:1" }, [3] = { id = "ring:1" }, [4] = { id = "item:6948", icon = {} } } },
		[2] = { id = 1, name = "dup" }, [3] = "junk", x = { id = 5 }, [4] = { id = 7, icon = {}, slots = "no", stick = "up", show = "press", style = "round", middle = "first" },
	} },
	ringMarker = "yes",
	chars = {
		["Player-0-Bob"] = { cells = { dev = { FB = { T = { id = "ring:9" }, L = { id = "spell:133" } } } }, touch = { bars = { left = { [1] = { T = { id = "ring:7" } } } } }, ringLast = { [1] = { 1, "spell:133" }, [9] = { 1, "spell:1" }, hspell133 = { 2, "spell:133" }, [7] = "bad", x = { 1, "a" }, [2] = { 0.5, "spell:1" } } },
		["Player-0-Cy"] = { ringLast = 5, cells = { dev = { DU = { T = { id = "spell:133", healer = true, healerLast = true }, L = { id = "spell:133", healerLast = true }, R = { id = "spell:133", healer = true, healerLast = 1 } } } } },
	},
}
local fixes = {}
Rings.Repair(db, function(what) fixes[#fixes + 1] = what end)
local list = db.rings.list
check(#list == 2 and list[1].id == 1 and list[2].id == 7 and db.rings.nextId == 8, "repair: bad and duplicate rings dropped, next id past the last")
check(list[1].name == "Heals" and list[1].count == 8 and list[2].name == "Ring 7" and list[2].icon == nil and list[2].count == 8, "repair: names, counts and icons")
check(list[1].stick == "right" and list[2].stick == "right", "repair: a missing or unknown stick is Right")
check(list[1].show == "toggle" and list[2].show == "toggle", "repair: a missing or unknown Show is Toggle")
check(list[1].style == "full" and list[2].style == "full", "repair: a missing or unknown Style is Full")
check(list[1].middle == "cancel" and list[2].middle == "cancel", "repair: a missing or unknown Middle is Cancel")
local bobLast = db.chars["Player-0-Bob"].ringLast
local cy = db.chars["Player-0-Cy"].cells.dev.DU
check(db.ringMarker == nil and fixes[1] ~= nil, "repair: a bad ring marker setting is on again")
check(cy.T.healerLast == true and cy.L.healerLast == nil and cy.R.healerLast == nil, "repair: Last target only true and only in Healer mode")
check(bobLast[1][1] == 1 and bobLast.hspell133 and bobLast[9] == nil and bobLast[7] == nil and bobLast.x == nil and bobLast[2] == nil and db.chars["Player-0-Cy"].ringLast == nil, "repair: last picks of existing and healer rings kept, the rest dropped")
local s = list[1].slots
check(s[1].id == "spell:133" and s[1].kind == "spell" and s[2] == nil and s[3] == nil and s[13] == nil and s[4].icon == nil and s[4].name == "item:6948" and next(list[2].slots) == nil, "repair: slots")
local bobCells = db.chars["Player-0-Bob"].cells.dev.FB
check(bobCells.T == nil and bobCells.L.id == "spell:133" and db.chars["Player-0-Bob"].touch.bars.left[1].T.id == "ring:7", "repair: a binding to a missing ring dropped, the others kept")
check(#fixes >= 10, "repair: each fix reported (" .. #fixes .. ")")
local clean = {}
Rings.Repair(clean, function() error("a fresh db needs no repair") end)
check(clean.rings == nil, "repair: a fresh db gets no account list")
-- Per character: each record's own list, its bindings checked against it.
local per = { chars = {
	["Player-0-Bob"] = { rings = { nextId = "x", list = { { id = 3, name = "Mine", count = 6, slots = {} } } }, cells = { dev = { FB = { T = { id = "ring:3" }, L = { id = "ring:7" } } } }, touchBars = { p1 = { left = { [1] = { T = { id = "ring:7" } } } } } },
	["Player-0-Cy"] = { cells = { dev = { DU = { T = { id = "ring:3" } } } } },
} }
Rings.Repair(per, function() end)
local bobPer = per.chars["Player-0-Bob"]
check(bobPer.rings.nextId == 4 and bobPer.cells.dev.FB.T.id == "ring:3" and bobPer.cells.dev.FB.L == nil and bobPer.touchBars.p1.left[1] == nil, "repair: per character, bindings to rings it lacks dropped (touch per profile too)")
check(per.chars["Player-0-Cy"].cells.dev.DU == nil and per.rings == nil, "repair: a character without rings keeps no ring binding")
local wide = { rings = { nextId = 2, list = { { id = 1, name = "Wide", count = 12, slots = {} } } } }
for i = 1, 12 do wide.rings.list[1].slots[i] = { id = "spell:" .. i } end
Rings.Repair(wide, function() end)
local kept = wide.rings.list[1]
check(kept.count == 8 and kept.slots[1].id == "spell:1" and kept.slots[8].id == "spell:8" and kept.slots[9] == nil and kept.slots[12] == nil, "repair: a saved 12-slot ring keeps its first 8")

-- The native radial's look (design/rings.md 10): its geometry, the wheel composed for every count from pieces of the
-- 8-slot art that tile the circle once, the highlight pieces covering exactly their wedge, every mask width shipped,
-- and the secure pick's directions on the drawn wedge centres.
local GEO, ART = Rings.GEO, Rings.ART
check(GEO.SLOT_R == 130 and GEO.ICON == 38 and GEO.HL_R == 150 and GEO.WHEEL == 270, "look: the native radial's geometry")
local EPS = 1e-6
local function hasMask(width)
	local f = io.open(dir .. "/Art/" .. Rings.SectorFile(width), "rb")
	if f then f:close() end
	return f ~= nil
end
local function norm(a) return (a + 180) % 360 - 180 end
check(#Rings.WheelPieces(8) == 1 and Rings.WheelPieces(8)[1][3] == nil, "look: 8 slots draw the native wheel as is")
for n = Rings.MIN_SLOTS, Rings.MAX_SLOTS do
	local step, half = 360 / n, 180 / n
	if n ~= 8 then
		local spans, ok = {}, true
		for _, p in ipairs(Rings.WheelPieces(n)) do
			local turn, centre, width = p[1], p[2], p[3]
			ok = ok and hasMask(width)
			if p.divider then ok = ok and math.abs(norm(turn + ART.SEG / 2 - centre)) < EPS and width == 2 * ART.GAP
			else ok = ok and turn == centre and width <= ART.PIECE + EPS end
			spans[#spans + 1] = { (centre - width / 2) % 360, width }
		end
		table.sort(spans, function(a, b) return a[1] < b[1] end)
		local total = 0
		for k, sp in ipairs(spans) do
			total = total + sp[2]
			local nxt = spans[k + 1] and spans[k + 1][1] or spans[1][1] + 360
			ok = ok and math.abs(sp[1] + sp[2] - nxt) < 1e-3
		end
		check(ok and math.abs(total - 360) < 1e-3, "look: " .. n .. " slots, the wheel pieces tile the circle once, clear of the art's dividers, masks shipped")
	end
	local covered = true
	for i = 1, n do
		local theta = (i - 1) * step
		local dx, dy = Rings.Dir(n, i)
		covered = covered and math.abs(norm(math.deg((math.atan2 or math.atan)(dx, dy)) - theta)) < EPS
		covered = covered and Rings.SlotAt(math.sin(math.rad(theta + half - 0.01)), math.cos(math.rad(theta + half - 0.01)), n) == i
		local lo, hi = math.huge, -math.huge
		for _, p in ipairs(Rings.SegmentPieces(n, i)) do
			local at, centre, width = p[1], p[2] or p[1], p[3] or 2 * half
			if p[3] then covered = covered and hasMask(width) end
			-- Each piece keeps only its own art's wedge (gold edges SEG / 2 out from where it is placed).
			covered = covered and math.abs(norm(centre - at)) + width / 2 <= ART.SEG / 2 + EPS
			lo, hi = math.min(lo, norm(centre - width / 2 - theta)), math.max(hi, norm(centre + width / 2 - theta))
		end
		covered = covered and math.abs(lo + half) < EPS and math.abs(hi - half) < EPS
	end
	check(covered, "look: " .. n .. " slots, each highlight spans its wedge edge to edge; the pick's directions are the wedge centres")
end

print = function() end
io.write(("rings_spec: %d checks passed (%s)\n"):format(checks, _VERSION))
