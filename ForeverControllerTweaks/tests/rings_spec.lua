-- Stubbed WoW check of the action rings: lua tests/rings_spec.lua
-- Rings.lua with the real Core, Layout, Face, Actions and Touch: the stick -> slot pick for 8 and 12 slots and the dead
-- zone, the per-slot attributes for every entry kind, the ring's restricted snippets run in a strict stub environment
-- (open, release pick, toggle, slot tap, catcher, guard), a ring on a routed face cell and on a touch button, in
-- combat too, deleting a ring clearing every binding, and the db repair.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local W = { combat = false, conds = {}, held = {}, sticks = {}, bindings = {}, cvars = {}, char = "Ann" }

local function compile(body, env, name)
	if setfenv then return setfenv(assert(loadstring(body, name)), env) end
	return assert(load(body, name, "t", env))
end
local function newtable(...) return { ... } end
local function renv(control)
	return setmetatable({ newtable = newtable, format = string.format, control = control }, { __index = _G })
end
-- The ring frame's environment holds only what WoW's restricted one gives these snippets: a missing name fails.
local RESTRICTED = { math = math, select = select, tostring = tostring, tonumber = tonumber, GetGamePadState = function() return GetGamePadState() end }
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
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetName() return self.name end
function Frame:SetScript(s, fn) self.scripts[s] = fn end
function Frame:IsProtected() return self.protected end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:GetFrameRef(k) return self.attrs["frameref-" .. k] end
function Frame:SetAttribute(k, v)
	if W.combat and self.protected and not W.secure then error("ADDON_ACTION_BLOCKED SetAttribute " .. k) end
	self.attrs[k] = v
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
function Frame:WrapScript(target, _, pre, post) target.wrap = { header = self, pre = pre, post = post } end
function Frame:ClearBindings()
	for k, v in pairs(W.bindings) do if v.owner == self then W.bindings[k] = nil end end
end
function Frame:SetBindingClick(priority, key, name, button) W.bindings[key] = { owner = self, priority = priority, click = name .. ":" .. button } end

-- A click as the secure button runs it: the wrapped pre-snippet in its header's environment, then (when a message
-- came back) the post-snippet. Returns what the button then fires: "type value" or nil.
local function click(button, down, which)
	local wrap = button.wrap
	local newButton, message = secure(run, wrap.header.env, "self,button,down", wrap.pre, button, "LeftButton", down)
	if newButton == false then return false end
	local a = button.attrs
	local actionType = a[which or "type"]
	local fired = actionType and (actionType .. " " .. tostring(a.spell or a.item or a.toy or a.macrotext or a.action))
	if wrap.post and message ~= nil then secure(run, wrap.header.env, "self,message,button,down", wrap.post, button, message, "LeftButton", down) end
	return fired
end
-- A bound key on a face router: press (fires type) or release (fires typerelease, as pressAndHoldAction does).
local function press(key, down)
	local b = assert(W.bindings[key], "nothing bound to " .. key)
	return click(frames[b.click:match("^(.-):")], down, down and "type" or "typerelease")
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
function InCombatLockdown() return W.combat end
function GetTime() return 0 end
function date() return "00:00:00 " end
function UnitName() return W.char end
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

local function loadAddonFile(file) assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
loadAddonFile("Core.lua")
loadAddonFile("Layout.lua")
ns.Device = { Current = function() return { key = "054c/0ce6" } end, SwapTargets = function() return false end }
ns.SlotView = { New = function(parent)
	local view = frame(nil, nil, parent)
	function view:SetSlot(slot, icon) self.slot, self.fallback = slot, icon end
	return view
end }
for _, file in ipairs({ "Face.lua", "Actions.lua", "Touch.lua", "Rings.lua" }) do loadAddonFile(file) end
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks")
ns.Fire("PLAYER_ENTERING_WORLD")

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

local Rings, Actions = ns.Rings, ns.Actions
local ring = frames.ForeverControllerTweaksRing

-- Stick angle -> slot, clockwise from the top, and the dead zone.
for _, n in ipairs({ 8, 12 }) do
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
check(Rings.SlotAt(1, 0, 12) == 4 and Rings.SlotAt(0, -1, 12) == 7 and Rings.SlotAt(-1, 0, 12) == 10, "pick: 12 slots E S W")
check(Rings.SlotAt(0.25, 0.25, 8) == nil and Rings.SlotAt(0, 0, 12) == nil and Rings.SlotAt(0, -0.39, 8) == nil, "pick: inside the dead zone, nothing")
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
check(same(attrs("face:jump"), { "macro", "macrotext", "/click TopButton8 LeftButton 1\n/click TopButton8 LeftButton" }), "attributes: a face action clicks down and up")
check(same(attrs("addon:CLICK MyAddonButton:LeftButton"), { "macro", "macrotext", "/click MyAddonButton LeftButton 1\n/click MyAddonButton LeftButton" }), "attributes: an addon's CLICK binding")
check(#attrs("addon:MYADDON_LUA") == 0 and Actions.Find("addon:MYADDON_LUA").disabled, "attributes: an addon's Lua binding can't fire")
check(#attrs("spell:999") == 0, "attributes: unknown to this character, nothing")

-- Rings: made out of combat only, named, sized, filled.
W.combat = true
check(select(2, Rings.New()) == "Controller Tweaks changes rings out of combat only." and #Rings.List() == 0, "rings: none made in combat")
W.combat = false
local heals = assert(Rings.New())
check(heals.name == "Ring 1" and heals.count == 8 and heals.stick == "right" and next(heals.slots) == nil and Rings.Icon(heals):find("QuestionMark"), "rings: defaults")
check(not Rings.SetStick(heals.id, "up") and heals.stick == "right", "rings: only right, left or dynamic")
check(Rings.Rename(heals.id, "  Heals|cff  ") and heals.name == "Healscff" and not Rings.Rename(heals.id, "   "), "rings: names trimmed, escapes dropped, never empty")
check(Rings.Rename(heals.id, "Heals") and not Rings.SetCount(heals.id, 3) and not Rings.SetCount(heals.id, 13) and not Rings.SetCount(heals.id, 8.5), "rings: 4 to 12 slots")
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
check(ring.attrs["ps-lstick"] == 1 and ring.attrs["ps-rstick"] == 2 and ring.attrs[p .. "s"] == "right" and math.abs(ring.attrs["dx8-3"] - 1) < 1e-9 and math.abs(ring.attrs["dy12-7"] + 1) < 1e-9, "secure: right stick index and slot directions")

-- On a routed face cell: hold opens, release fires the slot under the right stick, centred cancels. In combat too.
assert(ns.Face.Routable("FB", "T", ringEntry) and ns.Face.Routable("DU", "L", ringEntry))
assert(ns.Face.SetCellEntry("FB", "T", ringEntry))
local router = frames.ForeverControllerTweaksFaceBottom
check(router.attrs["ps-ring-top"] == heals.id and router.attrs["frameref-rings"] == ring and W.bindings.PAD1, "face: the ring on the router")
W.combat = true
aim(0, 0)
check(press("PAD1", true) == nil, "face: the press fires nothing")
check(ring.shown and ring.attrs["ps-ring"] == heals.id and ring.attrs["ps-mode"] == "hold", "face: the press opens the ring")
local slot3 = frames.ForeverControllerTweaksRingSlot3
check(slot3.shown and slot3.attrs.type == "spell" and slot3.attrs.spell == 639 and slot3.point[4] > 100 and math.abs(slot3.point[5]) < 1e-9, "face: slots laid out and armed")
check(not frames.ForeverControllerTweaksRingSlot9.shown, "face: slots past the count hidden")
aim(90)
check(press("PAD1", false) == "spell 639" and not ring.shown, "face: release fires the aimed slot and closes")
check(router.attrs.checkselfcast == true, "face: self-cast modifiers on spells")
press("PAD1", true)
aim(180, 0.2)
check(press("PAD1", false) == nil and not ring.shown, "face: release in the dead zone cancels")
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
check(dpadRight.attrs["ps-ring-top"] == heals.id and W.bindings.PADDRIGHT, "face: the ring on D-pad right")
W.combat = true
aim(0, 0)
press("PADDRIGHT", true)
check(ring.shown and ring.attrs["ps-mode"] == "hold", "face: D-pad right opens the ring")
aim(0)
check(press("PADDRIGHT", false) == "spell 133" and not ring.shown and dpadRight.attrs.typerelease == "spell", "face: D-pad right's release fires slot 1")
W.combat = false

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
aim(0)
check(press("PADDRIGHT", false) == nil and not ring.shown, "stick: left, the right stick doesn't pick")
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
check(press("PAD1", false) == nil, "stick: dynamic on a face button, the right stick doesn't pick")
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

-- After a held ring closes, its aiming stick is still pushed: the hold-off frame keeps that stick from the game until it
-- is back near the middle (or a second has passed), and passes the other stick on. Our own insecure frame: shown and
-- hidden in combat.
local hold = frames.ForeverControllerTweaksRingStickHold
local holdStick = hold.scripts.OnGamePadStick
W.combat = true
aimLeft(90)
Rings.HoldStick("left", 1)
check(hold.shown and not hold.protected and hold.parent == UIParent, "hold-off: shown after a release with the left stick pushed, our own frame under UIParent")
check(holdStick(hold, "Movement") == false and holdStick(hold, "Left") == false and holdStick(hold, "Camera") == true and holdStick(hold, "Right") == true, "hold-off: the left stick kept, the right passes on")
hold.scripts.OnUpdate(hold, 0.5)
check(hold.shown, "hold-off: still pushed, still held")
W.sticks[1] = { x = 0.1, y = 0.1 }
hold.scripts.OnUpdate(hold, 1 / 60)
check(not hold.shown, "hold-off: back in the middle, let go")
aimLeft(90)
Rings.HoldStick("left", 1)
hold.scripts.OnUpdate(hold, 0.6)
check(hold.shown, "hold-off: within the second")
hold.scripts.OnUpdate(hold, 0.5)
check(not hold.shown, "hold-off: a reading that never settles is let go after a second")
aim(0, 0)
Rings.HoldStick("right", 2)
check(not hold.shown, "hold-off: nothing while the stick is already in the middle")
aim(90)
Rings.HoldStick("right", 2)
check(hold.shown and holdStick(hold, "Camera") == false and holdStick(hold, "Look") == false and holdStick(hold, "Movement") == true, "hold-off: aiming right, the camera stick kept, the left walks")
aim(0, 0)
hold.scripts.OnUpdate(hold, 1 / 60)
check(not hold.shown, "hold-off: right stick centred, let go")
W.combat = false

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
W.combat = true
check(click(touch, true) == nil and ring.shown and ring.attrs["ps-mode"] == "touch", "touch: a tap opens")
local slot1 = frames.ForeverControllerTweaksRingSlot1
check(click(slot1, false) == "spell 133" and not ring.shown, "touch: a slot tap fires and closes")
click(touch, true)
check(click(touch, true) == nil and not ring.shown, "touch: a second tap on the button closes")
click(touch, true)
local catcher = frames.ForeverControllerTweaksRingCatcher
secure(run, catcher.env, "self,button,down", catcher.attrs._onclick, catcher, "LeftButton", false)
check(not ring.shown, "touch: a tap outside closes")
W.combat = false

-- Renames and icons follow on every binding; deleting a ring clears every binding to it, every character.
assert(Rings.Rename(heals.id, "Big heals"))
local cell = ns.Face.CellEntry("FB", "T")
check(cell.name == "Open ring: Big heals" and ns.Touch.Entry("left", 1).name == "Open ring: Big heals", "bindings: renamed with the ring")
assert(Rings.SetIcon(heals.id, 77))
check(ns.Face.CellEntry("FB", "T").icon == 77 and Rings.Icon(heals) == 77, "bindings: the icon follows")
local other = assert(Rings.New())
ns.db.chars["Bob-Realm"] = { cells = { ["054c/0ce6"] = { DD = { R = { id = "ring:" .. heals.id, name = "x" }, B = { id = "spell:133", name = "Fireball" } } } }, touch = { bars = { right = { [2] = { L = { id = "ring:" .. heals.id } } } } } }
ns.db.chars["Cy-Realm"] = { cells = { ["054c/0ce6"] = { DU = { T = { id = "ring:" .. other.id } } } } }
check(Rings.BindingCount(heals.id) == 4, "delete: every binding counted")
assert(Rings.Delete(heals.id))
check(ns.Face.CellEntry("FB", "T") == nil and ns.Touch.Entry("left", 1) == nil, "delete: this character's bindings cleared")
local bob = ns.db.chars["Bob-Realm"]
check(bob.cells["054c/0ce6"].DD.R == nil and bob.cells["054c/0ce6"].DD.B.id == "spell:133" and bob.touch.bars.right[2] == nil, "delete: other characters' bindings cleared, the rest kept")
check(ns.db.chars["Cy-Realm"].cells["054c/0ce6"].DU.T.id == "ring:" .. other.id, "delete: another ring's binding kept")
check(ring.attrs[p .. "n"] == nil and ring.attrs[p .. "t1"] == nil and router.attrs["ps-ring-top"] == nil and touch.attrs["ps-ring-T"] == nil, "delete: secure attributes gone")
check(Actions.Find("ring:" .. heals.id) == nil, "delete: gone from the catalog")
for _ = 2, Rings.MAX_RINGS do assert(Rings.New()) end
check(select(2, Rings.New()):find("most there can be", 1, true), "rings: at most " .. Rings.MAX_RINGS)

-- Repair: bad rings, ids, names, counts, icons and slots, and bindings to rings that are gone.
local db = {
	rings = { nextId = "x", list = {
		[1] = { id = 1, name = "  Heals  ", count = 99, slots = { [1] = { id = "spell:133", name = "Fireball", icon = 1 }, [2] = "bad", [13] = { id = "spell:1" }, [3] = { id = "ring:1" }, [4] = { id = "item:6948", icon = {} } } },
		[2] = { id = 1, name = "dup" }, [3] = "junk", x = { id = 5 }, [4] = { id = 7, icon = {}, slots = "no", stick = "up" },
	} },
	chars = { ["Bob-Realm"] = { cells = { dev = { FB = { T = { id = "ring:9" }, L = { id = "spell:133" } } } }, touch = { bars = { left = { [1] = { T = { id = "ring:7" } } } } } } },
}
local fixes = {}
Rings.Repair(db, function(what) fixes[#fixes + 1] = what end)
local list = db.rings.list
check(#list == 2 and list[1].id == 1 and list[2].id == 7 and db.rings.nextId == 8, "repair: bad and duplicate rings dropped, next id past the last")
check(list[1].name == "Heals" and list[1].count == 8 and list[2].name == "Ring 7" and list[2].icon == nil and list[2].count == 8, "repair: names, counts and icons")
check(list[1].stick == "right" and list[2].stick == "right", "repair: a missing or unknown stick is Right")
local s = list[1].slots
check(s[1].id == "spell:133" and s[1].kind == "spell" and s[2] == nil and s[3] == nil and s[13] == nil and s[4].icon == nil and s[4].name == "item:6948" and next(list[2].slots) == nil, "repair: slots")
local bobCells = db.chars["Bob-Realm"].cells.dev.FB
check(bobCells.T == nil and bobCells.L.id == "spell:133" and db.chars["Bob-Realm"].touch.bars.left[1].T.id == "ring:7", "repair: a binding to a missing ring dropped, the others kept")
check(#fixes >= 10, "repair: each fix reported (" .. #fixes .. ")")
local clean = {}
Rings.Repair(clean, function() error("a fresh db needs no repair") end)
check(clean.rings.nextId == 1 and #clean.rings.list == 0, "repair: a fresh db")

print = function() end
io.write(("rings_spec: %d checks passed (%s)\n"):format(checks, _VERSION))
