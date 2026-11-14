-- Stubbed WoW check of the face router: lua tests/face_spec.lua
-- Runs Face.lua's real restricted snippets (router OnClick wrap, _onstate-face, apply) in a fake secure
-- environment: bindings set and cleared per state, layer pick per modifier, override-bar fallback, catalog entries
-- per kind and per character, combat start, pad free, debug gating.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local unpack = unpack or table.unpack

local W = { combat = false, conds = {}, held = {}, bindings = {}, cvars = { GamepadStanceBarOverride = "1", GamepadPossessBarOverride = "1", GamepadSwapTargetModifiers = "0" } }

local function compile(body, env)
	if setfenv then
		local fn = assert(loadstring(body))
		return setfenv(fn, env)
	end
	return assert(load(body, "snippet", "t", env))
end
local function newtable(...) return { ... } end
local function renv(control)
	local globals = { newtable = newtable, format = string.format, control = control }
	return setmetatable(globals, { __index = _G })
end
local function run(env, sig, body, ...) return compile("local " .. sig .. " = ...\n" .. body, env)(...) end

local frames = {}
local Frame = {}
Frame.__index = Frame
local function frame(name, template, parent)
	local f = setmetatable({ name = name, attrs = {}, scripts = {}, hooks = {}, shown = true, parent = parent, protected = template and template:find("Secure") ~= nil }, Frame)
	if parent and parent.level then f.level = parent.level + 1 end
	if name then
		_G[name] = f
		frames[name] = f
	end
	f.env = renv(f)
	return f
end
local function noop() end
for _, m in ipairs({ "SetSize", "EnableMouse", "RegisterEvent" }) do Frame[m] = noop end
function Frame:RegisterForClicks(...) self.clicks = table.concat({ ... }, ",") end
function Frame:SetAllPoints(target) self.anchor = target end
function Frame:ClearAllPoints() self.anchor = nil end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent)
	if W.combat then error("ADDON_ACTION_BLOCKED SetParent") end
	self.parent = parent
end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:GetName() return self.name end
function Frame:SetScript(s, fn) self.scripts[s] = fn end
function Frame:HookScript(s, fn) self.hooks[s] = fn end
function Frame:IsProtected() return self.protected end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:GetFrameRef(k) return self.attrs["frameref-" .. k] end
function Frame:SetAttribute(k, v)
	if W.combat and self.protected and not W.secure then error("ADDON_ACTION_BLOCKED SetAttribute " .. k) end
	if W.combat and self.blizzard then error("write to a Blizzard frame") end
	self.attrs[k] = v
	if self.hooks.OnAttributeChanged then self.hooks.OnAttributeChanged(self, k, v) end
	local stateid = k:match("^state%-(.+)")
	local body = stateid and self.attrs["_onstate-" .. stateid]
	if body then
		local was = W.secure
		W.secure = true
		run(self.env, "self,stateid,newstate", body, self, stateid, v)
		W.secure = was
	end
end
function Frame:Execute(body)
	if W.combat then error("ADDON_ACTION_BLOCKED Execute") end
	local was = W.secure
	W.secure = true
	run(self.env, "self", body, self)
	W.secure = was
end
function Frame:WrapScript(target, _, pre) target.wrap = { header = self, pre = pre } end
function Frame:ClearBindings()
	for k, v in pairs(W.bindings) do if v.owner == self then W.bindings[k] = nil end end
end
function Frame:SetBindingClick(priority, key, name, button) W.bindings[key] = { owner = self, priority = priority, click = name .. ":" .. button } end

-- Presses a bound key: runs the router's wrapped OnClick; returns the macrotext it would run, or false.
local function press(key, down)
	local b = W.bindings[key]
	if not b then return nil end
	local router = frames[b.click:match("^(.-):")]
	local was = W.secure
	W.secure = true
	local result = run(router.wrap.header.env, "self,button,down", router.wrap.pre, router, "LeftButton", down)
	W.secure = was
	if result == false then return false end
	if router.attrs.type == "action" then return (down and "use " or (router.attrs.typerelease == "actionrelease" and "release " or "?")) .. tostring(router.attrs.action) end
	return router.attrs.macrotext
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
	local was = W.secure
	W.secure = true
	f:SetAttribute("state-" .. state, evalConditions(values))
	W.secure = was
end
local function cond(name, on)
	W.conds[name] = on or nil
	local was = W.secure
	W.secure = true
	for _, d in ipairs(drivers) do
		local v = evalConditions(d.values)
		if d.f.attrs["state-" .. d.state] ~= v then d.f:SetAttribute("state-" .. d.state, v) end
	end
	W.secure = was
end

local INDEX = { PAD1 = 0, PAD2 = 1, PAD3 = 2, PAD4 = 3, PADLSHOULDER = 9, PADRSHOULDER = 10, PADLTRIGGER = 13, PADRTRIGGER = 14 }
function GetGamePadState() return { buttons = W.held } end
C_GamePad = { ButtonBindingToIndex = function(k) return INDEX[k] end }
local function hold(...)
	W.held = {}
	for _, k in ipairs({ ... }) do W.held[INDEX[k] + 1] = true end
end

local CORE = { PAD1 = "GAMEPADACTIONBUTTON8", PAD2 = "GAMEPADACTIONBUTTON7", PAD3 = "GAMEPADACTIONBUTTON5", PAD4 = "GAMEPADACTIONBUTTON6", PADDUP = "GAMEPADACTIONBUTTON2", PADDDOWN = "GAMEPADACTIONBUTTON4" }
function GetBindingAction(key, _, ctx)
	assert(ctx == 9, "core binding context")
	return CORE[key] or ""
end
-- Values as in the API docs: the stance enum starts at None = 1; the possess enum has no None.
Enum = Enum or {}
for k, v in pairs({
	BindingContext = { GamepadModeInGameCore = 9 },
	GamepadStanceBarOverride = { None = 1, Page1LeftBar = 2, Page1RightBar = 3, Page1BottomBar = 4, Page2TopBar = 5 },
	GamepadPossessBarOverride = { SpecialPageTopBar = 1, Page1LeftBar = 2, Page1RightBar = 3, Page1BottomBar = 4 },
}) do Enum[k] = v end
function GetCVar(k) return W.cvars[k] end
function GetCVarBool(k) return W.cvars[k] == "1" end
function InCombatLockdown() return W.combat end
function GetTime() return os.clock() end
function date() return "00:00:00 " end
function UnitName() return W.char end
function GetNormalizedRealmName() return "Realm" end
local printed = {}
function print(msg) printed[#printed + 1] = msg end
SlashCmdList = {}
local tickers, afters = {}, {}
C_Timer = {
	NewTicker = function(_, fn)
		local t = { fn = fn }
		function t:Cancel() self.dead = true end
		tickers[#tickers + 1] = t
		return t
	end,
	After = function(_, fn) afters[#afters + 1] = fn end,
}
local function tickAll() for _, t in ipairs(tickers) do if not t.dead then t.fn() end end end
InputUtil = { IsGamepadUIEnabled = function() return W.ui ~= false end }
GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return not W.window end } }

-- What Actions' catalog and TextFor read, and the action slots and cursor for shadow slots.
local ns = {}
C_Spell = { GetSpellName = function(id) return ({ [133] = "Fireball", [4321] = "Swift Horse" })[id] end }
C_MountJournal = {
	GetMountIDs = function() return { 7 } end,
	GetMountInfoByID = function(id) if id == 7 then return "Horse", 4321, 1, false, true, 0, false, false, nil, false, true end end,
	GetNumDisplayedMounts = function() return 0 end,
}
local macros = { { "My Macro", 1, "/cast Fireball\n/say hi" } }
function GetNumMacros() return #macros, 0 end
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
function GetMacroBody(i) local m = macros[i]; return m and m[3] end
function CreateMacro(name, icon, body)
	macros[#macros + 1] = { name, icon, body }
	ns.Fire("UPDATE_MACROS")
	return #macros
end
function DeleteMacro(i)
	table.remove(macros, i)
	ns.Fire("UPDATE_MACROS")
end
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
	GetSpellBookItemInfo = function(_, bank) if bank == 0 then return { spellID = 133, name = "Fireball" } end end,
	IsSpellBookItemPassive = function() return false end,
	HasPetSpells = function() return 0 end,
}
C_Item = { GetItemSpell = function(id) return id == 6948 and "Hearth" end, PickupItem = function(id) W.cursor = { kind = "item", id = id } end }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
	GetContainerItemInfo = function() return { itemID = 6948, itemName = "Hearthstone", iconFileID = 1 } end,
}
C_Spell.PickupSpell = function(id) W.cursor = { kind = "spell", id = id } end
local slots = {}
W.slots = slots
C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 181 end }
C_ActionBar = {}
-- No deprecated globals (loadDeprecationFallbacks off): only C_ActionBar answers.
assert(HasAction == nil and GetActionText == nil and GetActionTexture == nil, "deprecated action globals must stay unstubbed")
function C_ActionBar.HasAction(slot) return slots[slot] ~= nil end
function GetActionInfo(slot) local a = slots[slot]; if a then return a.kind, a.id end end
function C_ActionBar.GetActionText(slot) local a = slots[slot]; return a and a.name end
function GetCursorInfo() return W.cursor and W.cursor.kind end
function ClearCursor() W.cursor = nil end
function PlaceAction(slot) W.cursor, slots[slot] = slots[slot], W.cursor end
function PickupAction(slot) W.cursor, slots[slot] = slots[slot], nil end
function PickupMacro(i) W.cursor = { kind = "macro", id = i, name = macros[i][1] } end
GameTooltip = {
	SetOwner = function(_, owner) W.tooltipOwner = owner end,
	SetAction = function(_, slot) W.tooltip = slot; return true end,
	IsOwned = function(_, owner) return W.tooltipOwner == owner end,
	Hide = function() W.tooltip = nil end,
}
function GameTooltip_SetDefaultAnchor(_, owner) W.tooltipOwner = owner end

-- Blizzard's gamepad bars, named as in game.
local PREFIX = "GamepadMainActionBarFramePageUnit"
local function bar(path, visible)
	local b = frame(nil, nil, nil)
	b.shown = visible
	b.actionButtons = {}
	for i = 1, 8 do
		local button = frame(PREFIX .. path .. "ActionButton" .. i, "SecureActionButtonTemplate", b)
		button.blizzard, button.level = true, 5
		b.actionButtons[i] = button
	end
	return b
end
local actionBars = {
	topBar = bar("TopCenteredAnchorTopBar", true), leftBar = bar("LeftCenteredAnchorLeftBar", true),
	rightBar = bar("RightCenteredAnchorRightBar", true), bottomBar = bar("BottomCenteredAnchorBottomBar", true),
	friendlyTargetingBar = bar("FriendlyTargetingActionBar", false), hostileTargetingBar = bar("HostileTargetingActionBar", false),
	shortcutsBar = bar("ShortcutsActionBar", false), stanceBar = bar("TopCenteredAnchorStanceBar", false), possessBar = bar("TopCenteredAnchorPossessBar", false),
}
GamepadMainActionBarFrame = { PageUnit = { actionBars = actionBars } }

local function loadAddonFile(file) assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
loadAddonFile("Core.lua")
loadAddonFile("Layout.lua")
ns.Device = { Current = function() return { key = "054c/0ce6" } end, SwapTargets = function() return W.cvars.GamepadSwapTargetModifiers == "1" end }
loadAddonFile("Face.lua")
loadAddonFile("Actions.lua")
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks")
ns.db.devices["054c/0ce6"] = { roles = {}, face = {} }
ns.db.options.debug = true
W.char = "Ann"

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end
local function count()
	local n = 0
	for _ in pairs(W.bindings) do n = n + 1 end
	return n
end
local function name(path, i) return PREFIX .. path .. "ActionButton" .. i end
local function lastDebug() return ns.db.debugLog[#ns.db.debugLog] or "" end
local TOP = "TopCenteredAnchorTopBar"

-- Native face: nothing bound.
ns.Fire("PLAYER_ENTERING_WORLD")
check(count() == 0, "native face binds nothing")
check(lastDebug():find("off: nothing moved"), "debug line for native")
check(ns.Face.State():find("^off nothing moved, state routed"), "State: off")

-- Swap bottom and left.
assert(ns.Layout.SetFace("bottom", "interact"))
check(count() == 2, "two moved positions bound")
check(W.bindings.PAD1.click == "ForeverControllerTweaksFaceBottom:LeftButton" and W.bindings.PAD1.priority == false, "PAD1 -> bottom router, non-priority")
check(W.bindings.PAD3.click == "ForeverControllerTweaksFaceLeft:LeftButton", "PAD3 -> left router")
check(not W.bindings.PAD2 and not W.bindings.PAD4, "unmoved positions stay native")
check(ns.Face.State() == "routed PAD1=interact PAD3=jump, state routed, shadow none, catchers 2", "State: routed")

-- Click catchers over the moved face slots: our secure button, a child of the native slot, one level above it.
local catcher = ns.Face.Catcher("FB", "T")
local slot8 = actionBars.topBar.actionButtons[8]
check(catcher and catcher.parent == slot8 and catcher.anchor == slot8 and catcher:GetFrameLevel() == 6 and catcher.protected, "catcher on the Cross slot")
check(catcher.clicks == "AnyUp,LeftButtonDown,RightButtonDown", "registered for clicks like the native slot")
-- Reserved buttons act on press (Jump, Back, Interact) or release (Inspect): a "click" type would only send the
-- release, so the catcher clicks down and up.
local function both(button) return "/click " .. button .. " LeftButton 1\n/click " .. button .. " LeftButton" end
check(catcher.attrs.type == "macro" and catcher.attrs.macrotext == both(name(TOP, 5)) and catcher.attrs.clickbutton == nil and catcher.shown, "mouse click: the Interact button, down and up")
check(ns.Face.Catcher("FL", "T").attrs.macrotext == both(name(TOP, 8)) and ns.Face.Catcher("FR", "T") == nil, "Square clicks Jump; unmoved: none")
check(catcher.attrs.checkselfcast == nil and catcher.attrs.checkmouseovercast == nil, "click catcher: no cast checks")
catcher.scripts.OnEnter(catcher)
check(W.tooltip == nil, "face action: no tooltip, as native")

-- Unmodified press and release.
hold()
check(press("PAD1", true) == "/click " .. name(TOP, 5) .. " LeftButton 1", "A down -> interact (top 5)")
check(press("PAD1", false) == "/click " .. name(TOP, 5) .. " LeftButton", "A up -> interact release")
check(press("PAD3", true) == "/click " .. name(TOP, 8) .. " LeftButton 1", "X down -> jump (top 8)")
check(lastDebug():find("left down top " .. name(TOP, 8), 1, true), "debug line per routed press")

-- Layer pick order: crossbar modifiers (held) first, both -> bottom; else the targeting bar Blizzard shows in place of
-- the top bar. A held targeting modifier alone changes nothing: the toggle option latches the bar with nothing held,
-- and letting go of one of two held modifiers leaves Blizzard's choice, not the held set's.
local cases = {
	{ { "PADLTRIGGER" }, nil, "LeftCenteredAnchorLeftBar" }, { { "PADRTRIGGER" }, nil, "RightCenteredAnchorRightBar" },
	{ { "PADLTRIGGER", "PADRTRIGGER" }, nil, "BottomCenteredAnchorBottomBar" },
	{ {}, "friendlyTargetingBar", "FriendlyTargetingActionBar" }, { {}, "hostileTargetingBar", "HostileTargetingActionBar" },
	{ {}, "shortcutsBar", "ShortcutsActionBar" }, { { "PADLSHOULDER" }, "shortcutsBar", "ShortcutsActionBar" },
	{ { "PADLSHOULDER" }, nil, TOP }, { { "PADLTRIGGER" }, "friendlyTargetingBar", "LeftCenteredAnchorLeftBar" },
}
for _, case in ipairs(cases) do
	local held, shown, expect = unpack(case)
	local label = table.concat(held, "+") .. " shown " .. tostring(shown)
	if shown then actionBars[shown].shown = true end
	hold(unpack(held))
	local slotA = expect == TOP and 5 or 8
	check(press("PAD1", true) == "/click " .. name(expect, slotA) .. " LeftButton 1", label .. " + A -> " .. expect)
	hold()
	if shown then actionBars[shown].shown = false end
	check(press("PAD1", false) == "/click " .. name(expect, slotA) .. " LeftButton", label .. ": release goes to the pressed bar")
end

-- Guard in combat: each condition drops the bindings, leaving it restores them.
W.combat = true
for _, c in ipairs({ "vehicleui", "overridebar", "possessbar", "bonusbar:5", "petbattle" }) do
	cond(c, true)
	check(count() == 0, c .. ": cleared in combat")
	cond(c, false)
	check(count() == 2, c .. " over: restored in combat")
end

-- A state change drops the press in flight: its release does nothing.
hold()
check(press("PAD1", true):find(name(TOP, 5), 1, true), "press before the vehicle")
cond("vehicleui", true)
cond("vehicleui", false)
check(press("PAD1", false) == false, "release after a state change is dropped")
W.combat = false

-- Stance bar on page 1 left: L2 + A goes to the stance bar only while Blizzard shows it.
W.cvars.GamepadStanceBarOverride = "2"
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
W.combat = true
hold("PADLTRIGGER")
check(press("PAD1", true):find("LeftCenteredAnchorLeftBar", 1, true), "no bonus bar: left bar")
cond("bonusbar", true)
check(press("PAD1", true):find("LeftCenteredAnchorLeftBar", 1, true), "stance hidden (other page): left bar")
actionBars.stanceBar.shown = true
check(press("PAD1", true) == "/click " .. name("TopCenteredAnchorStanceBar", 8) .. " LeftButton 1", "stance shown: stance 8")
hold()
check(press("PAD1", false) == "/click " .. name("TopCenteredAnchorStanceBar", 8) .. " LeftButton", "stance release")
check(press("PAD1", true):find(name(TOP, 5), 1, true), "unmodified still interact")
hold("PADRTRIGGER")
check(press("PAD1", true):find("RightCenteredAnchorRightBar", 1, true), "stance on left leaves the right layer")
actionBars.stanceBar.shown = false
cond("bonusbar", false)
W.combat = false

-- Unresolvable stance bar (unprotected button): face keys native while [bonusbar].
for _, b in ipairs(actionBars.stanceBar.actionButtons) do b.protected = false end
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
W.combat = true
check(count() == 2, "unresolved stance, no bonus bar: routed")
cond("bonusbar", true)
check(count() == 0, "unresolved stance + bonus bar: native")
cond("bonusbar", false)
check(count() == 2, "bonus bar gone: routed")
W.combat = false
for _, b in ipairs(actionBars.stanceBar.actionButtons) do b.protected = true end
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")

-- Pet bar (the possess override, which has no None): routed like the stance bar, so only its own layer on its own
-- page gives way, while Blizzard shows it there.
W.cvars.GamepadPossessBarOverride = "2"
ns.Fire("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")
W.combat = true
cond("pet", true)
check(count() == 2, "pet out: still routed")
hold("PADLTRIGGER")
check(press("PAD1", true):find("LeftCenteredAnchorLeftBar", 1, true), "pet bar on another page: left bar")
actionBars.possessBar.shown = true
check(press("PAD1", true) == "/click " .. name("TopCenteredAnchorPossessBar", 8) .. " LeftButton 1", "pet bar shown on the left layer: pet 8")
hold("PADRTRIGGER")
check(press("PAD1", true):find("RightCenteredAnchorRightBar", 1, true), "pet on left leaves the right layer")
hold()
actionBars.possessBar.shown = false
cond("pet", false)
W.combat = false
-- An unresolvable pet bar (unprotected button) pauses the routed keys while [pet], and status says so.
for _, b in ipairs(actionBars.possessBar.actionButtons) do b.protected = false end
ns.Fire("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")
W.combat = true
cond("pet", true)
check(count() == 0 and ns.Face.paused == "pet" and ns.Face.State():find("pet bar unresolved: moved actions pause while [pet]", 1, true), "unresolved pet bar: native while [pet], status says so")
cond("pet", false)
check(count() == 2, "pet gone: routed")
W.combat = false
for _, b in ipairs(actionBars.possessBar.actionButtons) do b.protected = true end
W.cvars.GamepadPossessBarOverride = "1"
ns.Fire("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")
check(ns.Face.paused == nil, "resolved: nothing paused")

-- Panel open drops the bindings; combat start re-applies them as if it had closed.
ns.SetPanelOpen(true)
check(count() == 0, "panel open: off")
ns.Fire("FCT_COMBAT_START")
check(count() == 2, "combat start: routed although the panel is still open")
ns.SetPanelOpen(false)
check(count() == 2, "panel closed: on")

-- A Blizzard window masks our bindings; the pad turning free binds them again.
W.bindings = {}
ns.Fire("FCT_PAD_FREE", false)
check(count() == 0, "pad busy: nothing")
ns.Fire("FCT_PAD_FREE", true)
check(count() == 2, "pad free: bindings restored")

-- Catalog entries on face positions: every kind a slot holds sits in a shadow slot (hidden keyboard bar, 180 down),
-- and the router fires it the way Blizzard's action buttons do.
local kinds = {
	{ { id = "spell:133", name = "Fireball" }, "spell:133" },
	{ { id = "item:6948", name = "Hearthstone" }, "item:6948" },
	{ { id = "mount:7", name = "Horse" }, "spell:4321" },
	{ { id = "macro:My Macro", name = "My Macro" }, "macro:My Macro" },
	{ { id = "game:targetenemy", name = "Target nearest enemy" }, "macro:FCT:Enemy" },
	{ { id = "game:sit", name = "Sit" }, "macro:FCT:Sit" },
}
local topRouter = frames.ForeverControllerTweaksFaceTop
for _, case in ipairs(kinds) do
	local id = case[1].id
	assert(ns.Face.SetCellEntry("FT", "T", { id = id, name = case[1].name, text = "stale" }))
	local held = W.slots[180]
	check(held and held.kind .. ":" .. tostring(held.name or held.id) == case[2] and not W.cursor, id .. ": placed in shadow slot 180")
	check(topRouter.attrs["ps-action-top"] == 180 and topRouter.attrs["ps-entry-top"] == nil and ns.Face.Slot("FT", "T") == 180, id .. ": router aims at the shadow slot")
	hold()
	check(press("PAD4", true) == "use 180", id .. ": Y down -> UseAction")
	check(press("PAD4", false) == "release 180", id .. ": Y up -> ReleaseAction")
	hold("PADLTRIGGER")
	check(press("PAD4", true) == "/click " .. name("LeftCenteredAnchorLeftBar", 6) .. " LeftButton 1" and topRouter.attrs.type == "macro", id .. ": L2 + Y keeps the native slot")
	local c = ns.Face.Catcher("FT", "T")
	check(c and c.parent == actionBars.topBar.actionButtons[6] and c.attrs.type == "action" and c.attrs.action == 180 and c.attrs.typerelease == "actionrelease", id .. ": catcher fires the shadow slot")
end
hold()
press("PAD4", true)
check(topRouter.attrs.pressAndHoldAction and topRouter.attrs.checkselfcast and topRouter.attrs.checkfocuscast and topRouter.attrs.checkmouseovercast, "action press: cast checks like native")
hold("PADLTRIGGER")
press("PAD4", true)
check(topRouter.attrs.checkselfcast == nil and topRouter.attrs.checkfocuscast == nil and topRouter.attrs.checkmouseovercast == nil, "macro press: cast checks cleared")
local topCatcher = ns.Face.Catcher("FT", "T")
check(topCatcher.attrs.checkfocuscast and topCatcher.shown, "catcher: cast checks, shown while routed")
check(#macros == 2 and macros[2][1] == "FCT:Sit", "replaced in place: the old FCT: macro deleted")
topCatcher.scripts.OnEnter(topCatcher)
check(W.tooltip == 180 and W.tooltipOwner == topCatcher and topCatcher.UpdateTooltip, "hover / gamepad focus: GameTooltip:SetAction(shadow), refreshed")
topCatcher.scripts.OnLeave(topCatcher)
check(W.tooltip == nil and not topCatcher.UpdateTooltip, "leave hides it")
check(ns.Face.State():find("shadow 180, catchers 3", 1, true), "State: shadow slots and catchers")
check(ns.Face.CellEntry("FT", "T").text == nil, "stored entry keeps the id, not the text")
local refused, why = ns.Face.SetCellEntry("FT", "T", { id = "spell:999", name = "Forgotten" })
check(not refused and why:find("no longer available") and ns.Face.CellEntry("FT", "T").id == "game:sit", "unknown spell: refused, entry kept")

-- Giving a cell back clears its shadow slot; the catcher stands down.
assert(ns.Face.SetCellEntry("FT", "T", nil))
check(W.slots[180] == nil and #macros == 1 and ns.Face.Slot("FT", "T") == nil, "released: slot cleared, macro deleted")
check(ns.Face.Catcher("FT", "T") == nil and not topCatcher.shown and topCatcher.attrs["ps-on"] == nil, "catcher hidden and off")

-- No shadow slot while the cursor holds something: macro text as the fallback, placed on the next apply.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FT = { T = { id = "spell:133", name = "Fireball", kind = "spell" } }
W.cursor = { kind = "item" }
ns.Fire("PLAYER_ENTERING_WORLD")
hold()
check(topRouter.attrs["ps-entry-top"] == "/cast Fireball" and press("PAD4", true) == "/cast Fireball" and press("PAD4", false) == "", "fallback: macro text")
check(topCatcher.attrs.type == "macro" and topCatcher.attrs.macrotext == "/cast Fireball" and topCatcher.shadow == nil, "catcher: same text, no tooltip")
W.cursor = nil
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[180] and press("PAD4", true) == "use 180", "cursor free: shadow slot")
-- A player's own change to the shadow slot: given up, a new one taken.
W.slots[180] = { kind = "spell", id = 999 }
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[180].id == 999 and W.slots[179].id == 133 and press("PAD4", true) == "use 179", "foreign change: slot kept, 179 used")
W.slots[180] = nil

-- Combat start applies without placing: an entry without its slot runs as text for that fight.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FR = { T = { id = "item:6948", name = "Hearthstone", kind = "item" } }
local placed = 0
for _ in pairs(W.slots) do placed = placed + 1 end
ns.Fire("FCT_COMBAT_START")
local after = 0
for _ in pairs(W.slots) do after = after + 1 end
check(after == placed and frames.ForeverControllerTweaksFaceRight.attrs["ps-entry-top"] == "/use item:6948", "combat start: nothing placed, text instead")
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.Slot("FR", "T") and frames.ForeverControllerTweaksFaceRight.attrs["ps-entry-top"] == nil, "next apply: placed")
assert(ns.Face.SetCellEntry("FR", "T", nil))

-- An entry that no longer resolves is logged and leaves the key native.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FT = { T = { id = "spell:999", name = "Forgotten", kind = "spell" } }
ns.Fire("PLAYER_ENTERING_WORLD")
check(not W.bindings.PAD4 and lastDebug():find("top entry spell:999 unavailable", 1, true), "unavailable entry logged, key native")
-- Open chat was removed (1.2.1): a cell saved with it stays saved, routes nothing and errors nothing.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FT = { T = { id = "game:chat", name = "Open chat", kind = "game" } }
ns.Fire("PLAYER_ENTERING_WORLD")
check(not W.bindings.PAD4 and lastDebug():find("top entry game:chat unavailable", 1, true) and ns.Face.CellEntry("FT", "T").id == "game:chat", "removed Open chat: kept, key native")
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FT = nil
assert(ns.Face.SetCellEntry("FT", "T", { id = "spell:133", name = "Fireball" }))

-- Entries belong to the character.
W.char = "Bob"
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FT", "T") == nil and not W.bindings.PAD4, "other character: no entry")
W.char = "Ann"
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FT", "T").id == "spell:133" and W.bindings.PAD4, "first character: entry back")

-- Old account-wide entries move to the current character once.
ns.db.faceEntries = { ["054c/0ce6"] = { right = { id = "spell:133", name = "Fireball" } } }
ns.db.chars["Cid-Realm"] = nil
W.char = "Cid"
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FR", "T").id == "spell:133" and ns.db.faceEntries == nil, "migrated to the current character")
W.char = "Ann"
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FR", "T") == nil, "not copied to other characters")

-- A character's own faceEntries (before cells) move to the base layer once.
ns.db.chars["Dee-Realm"] = { faceEntries = { ["054c/0ce6"] = { bottom = { id = "spell:133", name = "Fireball" } } } }
W.char = "Dee"
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FB", "T").kind == "spell" and ns.Face.CellEntry("FB", "T").id == "spell:133", "faceEntries -> cells, kind from the id")
check(ns.db.chars["Dee-Realm"].faceEntries == nil, "old store dropped")
W.char = "Ann"
ns.Fire("PLAYER_ENTERING_WORLD")

-- Any action on any cell: the router picks per (key, layer).
local R = ns.Face.Routable
check(R("FT", "T", { id = "spell:133" }) and R("FB", "T", nil), "face base layer: always routed")
check(R("FB", "L", { id = "face:jump", kind = "face" }) and R("DU", "B", { id = "face:interact" }), "face action: routed on any layer, kind from the id")
check(not R("FB", "L", { id = "spell:133", kind = "spell" }) and not R("DU", "T", { id = "mount:random", kind = "mount" }), "slot kinds: crossbar slot, D-pad base too")
check(not R("FB", "R", { id = "spellgroup:Holy Light", kind = "spellgroup" }) and not R("DL", "L", nil), "spell groups and empty cells: slot")
check(not R("L3", "T", { id = "face:jump" }) and not R("FB", "X", { id = "face:jump" }), "unknown cell")
local noBind, bindWhy = ns.Face.SetCellEntry("FB", "T", { id = "addon:MYADDON_DOTHING", name = "Do", kind = "binding", disabled = true, note = "needs a key binding" })
check(not noBind and bindWhy == "needs a key binding" and ns.Face.CellEntry("FB", "T") == nil, "an addon's Lua binding is refused on a routed cell")
local refused, why = ns.Face.SetCellEntry("FB", "L", { id = "spell:133", name = "Fireball", kind = "spell" })
check(not refused and why:find("crossbar slot") and ns.Face.CellEntry("FB", "L") == nil, "slot entry refused by the router")

assert(ns.Face.SetCellEntry("DU", "L", { id = "face:jump", name = "Jump", icon = 1, kind = "face" }))
check(lastDebug():find("DU(PADDUP, slot 2) PADDUP/L=Jump", 1, true), "debug line per routed key")
check(W.bindings.PADDUP and W.bindings.PADDUP.click == "ForeverControllerTweaksDpadUp:LeftButton", "D-pad up bound to its router")
check(ns.Face.CellEntry("DU", "L").kind == "face" and ns.Face.CellEntry("DU", "R") == nil, "CellEntry")
check(not W.bindings.PADDDOWN and not W.bindings.PADDLEFT, "other D-pad keys stay native")
hold("PADLTRIGGER")
check(press("PADDUP", true) == "/click " .. name(TOP, 8) .. " LeftButton 1", "L2 + up -> jump")
hold()
check(press("PADDUP", false) == "/click " .. name(TOP, 8) .. " LeftButton", "jump release on the pressed target")
check(press("PADDUP", true) == "/click " .. name(TOP, 2) .. " LeftButton 1", "up alone -> its native top-bar slot 2")
hold("PADRTRIGGER")
check(press("PADDUP", true) == "/click " .. name("RightCenteredAnchorRightBar", 2) .. " LeftButton 1", "R2 + up -> native right slot 2")
hold("PADLTRIGGER", "PADRTRIGGER")
check(press("PADDUP", true) == "/click " .. name("BottomCenteredAnchorBottomBar", 2) .. " LeftButton 1", "L2+R2 + up -> native bottom slot 2")
check(ns.Face.State():find("PADDUP/L=Jump", 1, true), "State lists the cell")

-- Pressed: true while the key is held and only on the layer its press went to.
hold("PADLTRIGGER")
press("PADDUP", true)
check(ns.Face.Pressed("DU", "L") and not ns.Face.Pressed("DU", "T") and not ns.Face.Pressed("DD", "L") and not ns.Face.Pressed("DU", "X"), "held: pressed on L only")
hold()
press("PADDUP", false)
check(not ns.Face.Pressed("DU", "L"), "released: not pressed")
press("PADDUP", true)
check(ns.Face.Pressed("DU", "T") and not ns.Face.Pressed("DU", "L"), "plain press: the base layer")
W.combat = true
cond("vehicleui", true)
check(not ns.Face.Pressed("DU", "T"), "state change: cleared")
cond("vehicleui", false)
W.combat = false
press("PADDUP", true)
ns.SetPanelOpen(true)
check(not ns.Face.Pressed("DU", "T"), "stand-down: cleared")
ns.SetPanelOpen(false)

-- Its catcher covers the left bar's Up slot and clicks Jump; the unmoved Up base slot has none.
local upCatcher = ns.Face.Catcher("DU", "L")
check(upCatcher and upCatcher.parent == actionBars.leftBar.actionButtons[2] and upCatcher.attrs.type == "macro" and upCatcher.attrs.macrotext == both(name(TOP, 8)), "catcher: left bar Up slot clicks Jump")
check(upCatcher.attrs.action == nil and upCatcher.attrs.typerelease == nil and ns.Face.Catcher("DU", "T") == nil and ns.Face.Slot("DU", "L") == nil, "a face action: no shadow slot, no catcher on Up base")
-- Catchers follow the header: hidden in a vehicle (in combat too) and while the panel is open.
W.combat = true
cond("vehicleui", true)
check(not upCatcher.shown and not ns.Face.Catcher("FB", "T").shown, "vehicle: catchers hidden")
cond("vehicleui", false)
check(upCatcher.shown, "vehicle gone: shown again")
W.combat = false
ns.SetPanelOpen(true)
check(not upCatcher.shown, "panel open: hidden")
ns.SetPanelOpen(false)
check(upCatcher.shown, "panel closed: shown")

-- Jump on a face button's left layer too; a face action on a D-pad base cell.
assert(ns.Face.SetCellEntry("FT", "L", { id = "face:jump", name = "Jump" }))
hold("PADLTRIGGER")
check(press("PAD4", true) == "/click " .. name(TOP, 8) .. " LeftButton 1", "L2 + Y -> jump as well")
hold()
local ySlot = ns.Face.Slot("FT", "T")
check(press("PAD4", true) == "use " .. ySlot and press("PAD4", false) == "release " .. ySlot, "Y base keeps its entry")
hold("PADRTRIGGER")
check(press("PAD4", true) == "/click " .. name("RightCenteredAnchorRightBar", 6) .. " LeftButton 1", "R2 + Y stays native")
assert(ns.Face.SetCellEntry("DD", "T", { id = "face:interact", name = "Interact" }))
hold()
check(press("PADDDOWN", true) == "/click " .. name(TOP, 5) .. " LeftButton 1", "down -> interact")
check(frames.ForeverControllerTweaksDpadDown.attrs["ps-entry-top"] == nil, "a face action is a click, not macro text")

-- A cell's entry gives way to a stance bar Blizzard shows on that layer.
W.cvars.GamepadStanceBarOverride = "2"
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
W.combat = true
cond("bonusbar", true)
actionBars.stanceBar.shown = true
hold("PADLTRIGGER")
check(press("PADDUP", true) == "/click " .. name("TopCenteredAnchorStanceBar", 2) .. " LeftButton 1", "stance shown: the stance slot wins")
actionBars.stanceBar.shown = false
check(press("PADDUP", true) == "/click " .. name(TOP, 8) .. " LeftButton 1", "stance hidden: the cell again")
cond("bonusbar", false)

-- In combat nothing changes; nil gives the cells back.
check(not ns.Face.SetCellEntry("DU", "L", nil), "combat: refused")
W.combat = false
W.cvars.GamepadStanceBarOverride = "1"
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
for _, cell in ipairs({ { "DU", "L" }, { "FT", "L" }, { "DD", "T" } }) do assert(ns.Face.SetCellEntry(cell[1], cell[2], nil)) end
check(not W.bindings.PADDUP and not W.bindings.PADDDOWN and W.bindings.PAD4, "cells given back: D-pad native, Y keeps its base entry")
check(ns.Face.Catcher("DU", "L") == nil and not upCatcher.shown, "given back: its catcher is off")
check(ns.db.chars["Ann-Realm"].cells["054c/0ce6"].DU == nil and ns.Face.CellEntry("FT", "T").id == "spell:133", "empty rows dropped, base entry kept")

-- Back and Inspect were FCT: macros, whose press and release run in the same instant; old placements move to routed
-- cells once (with the Gamepad UI on), and the old macro goes through the registry.
GamepadActionBarBindingUtil = { GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID = function(page, id) return 181 + (page - 1) * 32 + id end }
macros[#macros + 1] = { "PS:Back", 1, "/click X" }
ns.db.macros = ns.db.macros or {}
ns.db.macros["PS:Back"] = { id = "game:back", chars = { ["Ann-Realm"] = true } }
local backSlot = 181 + 32 + 8 + 7
W.slots[backSlot] = { kind = "macro", id = #macros, name = "PS:Back" }
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].DD = { L = { id = "game:inspect", name = "Inspect", kind = "game" } }
ns.db.chars["Ann-Realm"].legacyFaceDone = nil
ns.Fire("PLAYER_ENTERING_WORLD")
local function hasMacro(macroName)
	for _, m in ipairs(macros) do if m[1] == macroName then return true end end
end
check(ns.Face.CellEntry("FR", "L").id == "face:back" and ns.Face.CellEntry("FR", "L").kind == "face", "page 2 L2 + Circle macro slot -> routed Back cell")
check(W.slots[backSlot] == nil and not hasMacro("PS:Back") and ns.db.macros["PS:Back"] == nil, "slot cleared, PS:Back deleted")
check(ns.Face.CellEntry("DD", "L").id == "face:inspect" and ns.Face.CellEntry("DD", "L").kind == "face", "old cell id -> the face action")
check(ns.db.chars["Ann-Realm"].legacyFaceDone, "done once per character")
hold("PADLTRIGGER")
check(press("PAD2", true) == "/click " .. name(TOP, 7) .. " LeftButton 1", "L2 + Circle presses Back")
check(lastDebug():find("right down left " .. name(TOP, 7), 1, true), "debug line for the routed click")
hold()
check(press("PAD2", false) == "/click " .. name(TOP, 7) .. " LeftButton", "and releases it on release")
local backCatcher = ns.Face.Catcher("FR", "L")
backCatcher.hooks.OnClick(backCatcher, "LeftButton", false)
check(lastDebug():find("face catcher FR/L LeftButton up: /click " .. name(TOP, 7), 1, true), "debug line for a catcher click")
W.slots[backSlot] = { kind = "spell", id = 133 }
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[backSlot].id == 133, "migration doesn't run again")
W.slots[backSlot] = nil
assert(ns.Face.SetCellEntry("FR", "L", nil))
assert(ns.Face.SetCellEntry("DD", "L", nil))

-- An unregistered PS:Back from a build before the registry (body "/click <Back>", a release Back ignores): adopted
-- because the addon wrote it word for word, then moved and deleted like a registered one.
macros[#macros + 1] = { "PS:Back", 1, "/click " .. name(TOP, 7) }
W.slots[backSlot] = { kind = "macro", id = #macros, name = "PS:Back" }
ns.db.chars["Ann-Realm"].legacyFaceDone = nil
ns.Fire("PLAYER_ENTERING_WORLD")
check(ns.Face.CellEntry("FR", "L").id == "face:back" and W.slots[backSlot] == nil and not hasMacro("PS:Back") and ns.db.macros["PS:Back"] == nil, "old-build PS:Back: adopted, routed, deleted")
assert(ns.Face.SetCellEntry("FR", "L", nil))
-- A PS:Back with the player's own text is theirs: left on its slot, and they're told in chat.
macros[#macros + 1] = { "PS:Back", 1, "/stopcasting\n/cleartarget" }
W.slots[backSlot] = { kind = "macro", id = #macros, name = "PS:Back" }
ns.db.chars["Ann-Realm"].legacyFaceDone = nil
local said = #printed
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[backSlot].name == "PS:Back" and hasMacro("PS:Back") and ns.db.macros["PS:Back"] == nil and ns.Face.CellEntry("FR", "L") == nil, "foreign PS:Back: untouched, not registered")
check(#printed == said + 1 and printed[#printed]:find("PS:Back on page 2", 1, true) and printed[#printed]:find("left as is", 1, true), "the player is told once in chat")
ns.Fire("PLAYER_ENTERING_WORLD")
check(#printed == said + 1, "not told again")
W.slots[backSlot] = nil
table.remove(macros)

-- A routed entry empties the cell's storage slot on the page being edited, whatever it holds; on the other pages only
-- The addon's own FCT: macros go (through the registry), never the player's actions.
local function storage(page, layer, key) return 181 + (page - 1) * 32 + ({ T = 0, L = 8, R = 16, B = 24 })[layer] + key end
local under1, under2, under3 = storage(1, "L", 7), storage(2, "L", 7), storage(3, "L", 7)
local back = ns.Actions.Find("face:back")
W.slots[under1], W.slots[under3] = { kind = "spell", id = 133 }, { kind = "spell", id = 133 }
assert(ns.Actions.Assign(under2, ns.Actions.Find("game:cleartarget")))
check(hasMacro("FCT:ClearTarget") and ns.Actions.Ours(under2) and not ns.Actions.Ours(under1), "Clear target placed as the addon's FCT: macro")
check(select(2, ns.Face.SetCellEntry("FR", "L", back, 4)) == "unknown page 4" and W.slots[under2], "page out of range: refused")
W.cursor = { kind = "spell", id = 133 }
check(not ns.Face.SetCellEntry("FR", "L", back, 1) and ns.Face.CellEntry("FR", "L") == nil and W.slots[under1] and W.slots[under2], "cursor busy: refused, nothing changed")
W.cursor = nil
assert(ns.Face.SetCellEntry("FR", "L", back, 1))
check(W.slots[under1] == nil and W.slots[under2] == nil and not hasMacro("FCT:ClearTarget"), "routed Back on page 1: page 1 emptied, FCT:ClearTarget on page 2 deleted")
check(W.slots[under3] and W.slots[under3].id == 133, "the player's spell on page 3 kept")
assert(ns.Face.SetCellEntry("FR", "L", nil))
check(W.slots[under1] == nil and W.slots[under3].id == 133, "given back: page 1 stays empty, page 3 has its spell again")
-- Without a page (older callers) only the addon's own macros go.
W.slots[under1] = { kind = "spell", id = 133 }
assert(ns.Actions.Assign(under2, ns.Actions.Find("game:cleartarget")))
assert(ns.Face.SetCellEntry("FR", "L", back))
check(W.slots[under1].id == 133 and W.slots[under2] == nil and not hasMacro("FCT:ClearTarget"), "no page: the player's spell kept, the FCT: macro deleted")
assert(ns.Face.SetCellEntry("FR", "L", nil))
W.slots[under1], W.slots[under3] = nil, nil
-- The other way, as the picker does it: the slot is assigned, then the routed cell given back; the slot keeps it.
assert(ns.Face.SetCellEntry("FR", "L", back, 1))
assert(ns.Actions.Assign(under1, ns.Actions.Find("spell:133")))
assert(ns.Face.SetCellEntry("FR", "L", nil))
check(W.slots[under1].id == 133 and ns.Face.CellEntry("FR", "L") == nil, "a slot entry replaces the routed one")

-- Cells routed before this may still have a FCT: macro under them: deleted once per character, D-pad base cells too;
-- the player's own actions there stay.
local dpadTop, yTop = storage(2, "T", 2), storage(1, "T", 6)
assert(ns.Actions.Assign(dpadTop, ns.Actions.Find("game:cleartarget")))
W.slots[yTop] = { kind = "spell", id = 133 }
local list = ns.db.chars["Ann-Realm"].cells["054c/0ce6"]
list.FR = list.FR or {}
list.FR.L = { id = "face:back", name = "Back", kind = "face" }
list.DU = { T = { id = "face:jump", name = "Jump", kind = "face" } }
ns.db.chars["Ann-Realm"].routedUnderDone = nil
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[dpadTop] == nil and not hasMacro("FCT:ClearTarget") and ns.db.chars["Ann-Realm"].routedUnderDone, "login: FCT: macros under routed cells deleted")
check(W.slots[under1].id == 133 and W.slots[yTop], "login: the player's spells kept, face base cells have no storage slot")
W.slots[yTop] = nil
assert(ns.Actions.Assign(dpadTop, ns.Actions.Find("game:cleartarget")))
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.slots[dpadTop], "login cleanup runs once")
assert(ns.Actions.Clear(dpadTop))
W.slots[under1] = nil
list.FR.L, list.DU = nil, nil
if not next(list.FR) then list.FR = nil end
ns.Fire("PLAYER_ENTERING_WORLD")
GamepadActionBarBindingUtil = nil

local function failures()
	local n = 0
	for _, line in ipairs(ns.db.debugLog) do if line:find("face apply failed", 1, true) then n = n + 1 end end
	return n
end
check(failures() == 0, "no apply failed so far")

-- Gamepad UI off: no shadow slot is written (bars 6-8 are the player's then); the owned ones stay as they are.
local yShadow = ns.Face.Slot("FT", "T")
local function snapshot()
	local copy = {}
	for slot, action in pairs(W.slots) do copy[slot] = action end
	return copy
end
local function unchanged(before)
	for slot, action in pairs(W.slots) do if before[slot] ~= action then return false end end
	for slot, action in pairs(before) do if W.slots[slot] ~= action then return false end end
	return true
end
W.ui = false
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
local before = snapshot()
assert(ns.Face.SetCellEntry("FR", "T", { id = "item:6948", name = "Hearthstone" }))
assert(ns.Face.SetCellEntry("FT", "T", nil))
check(unchanged(before) and not W.bindings.PAD4, "off: SetCellEntry and apply write no slot")
check(ns.db.chars["Ann-Realm"].shadow[yShadow].id == "spell:133", "off: the owned slot is kept")
W.ui = nil
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
check(ns.Face.Slot("FR", "T") and W.slots[ns.Face.Slot("FR", "T")].id == 6948, "on again: the new entry placed by the apply")
check(W.slots[yShadow] == nil and ns.db.chars["Ann-Realm"].shadow[yShadow] == nil, "on again: the given-back cell's slot released")
assert(ns.Face.SetCellEntry("FR", "T", nil))
assert(ns.Face.SetCellEntry("FT", "T", { id = "spell:133", name = "Fireball" }))

-- A Lua error in an apply is logged once and doesn't freeze the router.
local realFace = ns.Layout.Face
ns.Layout.Face = function() error("boom") end
ns.Fire("PLAYER_ENTERING_WORLD")
ns.Fire("PLAYER_ENTERING_WORLD")
check(failures() == 1, "error logged once")
ns.Layout.Face = realFace
W.bindings = {}
ns.Fire("PLAYER_ENTERING_WORLD")
check(W.bindings.PAD4 and ns.Face.State():find("^routed"), "the next apply runs normally")

local realShadow = ns.Actions.Shadow
ns.Actions.Shadow = function() error("boom") end
local okSet, whySet = ns.Face.SetCellEntry("FR", "T", { id = "item:6948", name = "Hearthstone" })
ns.Actions.Shadow = realShadow
W.bindings = {}
ns.Fire("PLAYER_ENTERING_WORLD")
check(not okSet and whySet:find("couldn't place") and ns.Face.CellEntry("FR", "T") == nil and W.bindings.PAD4, "SetCellEntry error: refused, router still applies")

-- The key's native slot moved: the catcher follows it to the new slot (out of combat).
local yCatcher = ns.Face.Catcher("FT", "T")
CORE.PAD4 = "GAMEPADACTIONBUTTON3"
ns.Fire("PLAYER_ENTERING_WORLD")
check(yCatcher.parent == actionBars.topBar.actionButtons[3] and yCatcher.anchor == actionBars.topBar.actionButtons[3] and ns.Face.Catcher("FT", "T") == yCatcher, "re-parented to the new slot")
CORE.PAD4 = "GAMEPADACTIONBUTTON6"
ns.Fire("PLAYER_ENTERING_WORLD")
check(yCatcher.parent == actionBars.topBar.actionButtons[6], "and back")

-- Cell reads are cached until the layout, the device or the character changes.
local realCurrent, lookups = ns.Device.Current, 0
ns.Device.Current = function() lookups = lookups + 1; return realCurrent() end
for _ = 1, 64 do ns.Face.CellEntry("FT", "T") end
check(lookups == 0, "64 reads: no lookup")
ns.Device.Current = function() return { key = "045e/0b13" } end
check(ns.Face.CellEntry("FT", "T"), "another pad: still the cached cells until told")
ns.Fire("FCT_LAYOUT_CHANGED", "device")
check(ns.Face.CellEntry("FT", "T") == nil, "device change: that pad's cells (none)")
local ySlot = ns.Actions.ShadowSlot("FT", "T", "spell:133")
check(ySlot and W.slots[ySlot].id == 133 and ns.db.chars["Ann-Realm"].shadow[ySlot], "another pad without cells: the shadow slot is kept")
ns.Device.Current = function() return nil end
ns.Fire("FCT_LAYOUT_CHANGED", "device")
check(W.slots[ySlot].id == 133 and ns.db.chars["Ann-Realm"].shadow[ySlot], "pad unplugged: the shadow slot is kept")
ns.Device.Current = realCurrent
ns.Fire("FCT_LAYOUT_CHANGED", "device")
check(ns.Face.CellEntry("FT", "T").id == "spell:133" and ns.Face.Slot("FT", "T") == ySlot, "back: its cells again, on the same slot")

-- Back paddles: a paddle without a role routes its cells per layer through the same snippet; a layer without a cell
-- does nothing (a paddle has no crossbar slot), and a paddle with a role stays native with its cells kept.
local pad = { key = "054c/0ce6", raw = { P1 = { button = 16 }, P2 = { button = 17 } } }
ns.Device.Current = function() return pad end
ns.Fire("FCT_LAYOUT_CHANGED", "device")
local paddle1, faceHeader = frames.ForeverControllerTweaksPaddle1, frames.ForeverControllerTweaksFaceHeader
check(paddle1 and paddle1.attrs["ps-kind"] == "paddle" and paddle1.attrs.pressAndHoldAction, "paddle routers: made like the others, a dynamic ring aims with the right stick")
check(R("P1", "T", { id = "spell:133", kind = "spell" }) and R("P4", "B", nil) and not R("P5", "T", { id = "face:jump" }), "paddle: every cell routed, no storage slot")
check(not W.bindings.PADPADDLE1 and not W.bindings.PADPADDLE2, "no paddle cells: paddles native")
assert(ns.Face.SetCellEntry("P1", "R", { id = "spell:133", name = "Fireball" }, 1))
assert(ns.Face.SetCellEntry("P1", "L", { id = "face:interact", name = "Interact" }, 1))
assert(ns.Face.SetCellEntry("P1", "T", { id = "face:jump", name = "Jump" }, 1))
check(W.bindings.PADPADDLE1 and W.bindings.PADPADDLE1.click == "ForeverControllerTweaksPaddle1:LeftButton" and W.bindings.PADPADDLE1.priority == false, "PADPADDLE1 bound to its router, non-priority")
check(not W.bindings.PADPADDLE2 and faceHeader.attrs["ps-key9"] == "PADPADDLE1" and faceHeader.attrs["ps-key4"] == "PAD4", "a paddle without cells stays native; paddle keys after the crossbar keys (Glyphs reads 1-8)")
check(ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P1.R.id == "spell:133", "stored next to the face cells, per character and pad")
check(lastDebug():find("P1(PADPADDLE1) PADPADDLE1=Jump PADPADDLE1/L=Interact PADPADDLE1/R=Fireball", 1, true), "debug line for the paddle")
local pShadow = ns.Face.Slot("P1", "R")
check(pShadow and W.slots[pShadow].id == 133 and ns.Face.Catcher("P1", "R") == nil, "slot kind: its own shadow slot, no catcher (no crossbar slot)")
hold("PADRTRIGGER")
check(press("PADPADDLE1", true) == "use " .. pShadow and ns.Face.Pressed("P1", "R"), "RT + paddle 1: UseAction on the shadow slot")
hold()
check(press("PADPADDLE1", false) == "release " .. pShadow, "release: ReleaseAction on the same slot")
check(press("PADPADDLE1", true) == "/click " .. name(TOP, 8) .. " LeftButton 1" and press("PADPADDLE1", false) == "/click " .. name(TOP, 8) .. " LeftButton", "paddle 1 alone: Jump down and up")
hold("PADLTRIGGER")
check(press("PADPADDLE1", true) == "/click " .. name(TOP, 5) .. " LeftButton 1", "LT + paddle 1: Interact")
hold("PADLTRIGGER", "PADRTRIGGER")
check(press("PADPADDLE1", true) == false and press("PADPADDLE1", false) == false, "LT+RT + paddle 1: no bottom cell, nothing fires")
hold()
actionBars.friendlyTargetingBar.shown = true
check(press("PADPADDLE1", true) == "/click " .. name(TOP, 8) .. " LeftButton 1", "a shown targeting bar doesn't take a paddle's press")
actionBars.friendlyTargetingBar.shown = false
-- An override bar has no slot on a paddle, so it never takes a paddle's press; an unresolved one pauses every routed key.
W.cvars.GamepadStanceBarOverride = "2"
for _, b in ipairs(actionBars.stanceBar.actionButtons) do b.protected = false end
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
W.combat = true
cond("bonusbar", true)
actionBars.stanceBar.shown = true
hold("PADLTRIGGER")
check(W.bindings.PADPADDLE1 == nil, "unresolved stance bar while [bonusbar]: every routed key native, paddles too")
cond("bonusbar", false)
W.combat = false
for _, b in ipairs(actionBars.stanceBar.actionButtons) do b.protected = true end
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
W.combat = true
cond("bonusbar", true)
check(press("PADPADDLE1", true) == "/click " .. name(TOP, 5) .. " LeftButton 1", "stance shown on LT's layer: the paddle keeps its cell")
actionBars.stanceBar.shown = false
cond("bonusbar", false)
-- Vehicles, override and possess bars and pet battles: native, in combat too.
for _, c in ipairs({ "vehicleui", "overridebar", "possessbar", "bonusbar:5", "petbattle" }) do
	cond(c, true)
	check(W.bindings.PADPADDLE1 == nil, c .. ": paddle unbound in combat")
	cond(c, false)
	check(W.bindings.PADPADDLE1, c .. " over: paddle bound again")
end
check(not ns.Face.SetCellEntry("P1", "B", nil), "combat: no change")
W.combat = false
W.cvars.GamepadStanceBarOverride = "1"
ns.Fire("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
hold()
-- Macro text when no shadow slot can be placed, as on any routed cell.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P2 = { B = { id = "spell:133", name = "Fireball", kind = "spell" } }
W.cursor = { kind = "item" }
ns.Fire("PLAYER_ENTERING_WORLD")
hold("PADLTRIGGER", "PADRTRIGGER")
check(press("PADPADDLE2", true) == "/cast Fireball" and press("PADPADDLE2", false) == "", "paddle 2, both triggers: macro text fallback")
W.cursor = nil
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P2 = nil
ns.Fire("PLAYER_ENTERING_WORLD")
hold()
-- A role: the paddle outputs that modifier's key, so PADPADDLE1 goes native; its cells stay stored, their shadow slot
-- is given back, and new entries wait for None.
assert(ns.Layout.SetRole("P1", "leftmod"))
check(not ns.Face.PaddleFree("P1") and W.bindings.PADPADDLE1 == nil, "role: paddle 1 unbound")
check(ns.Face.CellEntry("P1", "R").id == "spell:133" and ns.Face.CellEntry("P1", "T").id == "face:jump", "role: the cells are kept")
check(W.slots[pShadow] == nil and ns.Face.Slot("P1", "R") == nil, "role: the shadow slot is given back")
local noRole, roleWhy = ns.Face.SetCellEntry("P1", "B", { id = "face:jump", name = "Jump" })
check(not noRole and roleWhy:find("role") and ns.Face.CellEntry("P1", "B") == nil, "role: a new entry is refused")
assert(ns.Face.SetCellEntry("P1", "T", nil))
assert(ns.Layout.SetRole("P1", "none"))
check(ns.Face.PaddleFree("P1") and W.bindings.PADPADDLE1 and ns.Face.CellEntry("P1", "R").id == "spell:133" and ns.Face.CellEntry("P1", "T") == nil, "None again: bound, cells back (the cleared one stays cleared)")
pShadow = ns.Face.Slot("P1", "R")
hold("PADRTRIGGER")
check(pShadow and W.slots[pShadow].id == 133 and press("PADPADDLE1", true) == "use " .. pShadow, "None again: the shadow slot placed again")
hold()
-- A paddle this pad doesn't have (no raw source) never routes; a pad without paddles keeps PADPADDLEn native.
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P3 = { T = { id = "face:jump", name = "Jump", kind = "face" } }
ns.Fire("PLAYER_ENTERING_WORLD")
check(not ns.Face.PaddleFree("P3") and W.bindings.PADPADDLE3 == nil and not ns.Face.SetCellEntry("P3", "L", { id = "face:jump", name = "Jump" }), "P3 not on this pad: native, refused")
ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P3 = nil
for _, layer in ipairs({ "L", "R" }) do assert(ns.Face.SetCellEntry("P1", layer, nil)) end
check(W.bindings.PADPADDLE1 == nil and faceHeader.attrs["ps-key9"] == nil and ns.db.chars["Ann-Realm"].cells["054c/0ce6"].P1 == nil, "cells given back: paddle native, row dropped")
ns.Device.Current = realCurrent
ns.Fire("FCT_LAYOUT_CHANGED", "device")

-- Debug off: no route attribute, no new lines.
SlashCmdList.FOREVERCONTROLLERTWEAKS("debug off")
local lines = #ns.db.debugLog
hold()
press("PAD1", true)
check(#ns.db.debugLog == lines and frames.ForeverControllerTweaksFaceBottom.attrs["ps-debug"] == nil, "debug off: no route line")
SlashCmdList.FOREVERCONTROLLERTWEAKS("debug on")

-- Layout change in combat waits for the end; a window holding the pad waits too.
W.combat = true
assert(ns.Layout.SetFace("top", "back"))
check(W.bindings.PAD2 == nil, "combat: no change yet")
tickAll()
W.combat = false
tickAll()
check(W.bindings.PAD2 and W.bindings.PAD4 and count() == 4, "after combat: all four bound")

-- Gamepad bars missing right after the UI turns on: retried next frame, at most 10 times.
assert(ns.Face.SetCellEntry("FT", "T", nil))
GamepadMainActionBarFrame = nil
ns.Fire("FCT_ACTIVE_CHANGED", true)
check(count() == 0 and #afters == 1, "bars missing: off, one retry queued")
for _ = 1, 20 do
	local fn = table.remove(afters, 1)
	if fn then fn() end
end
check(#afters == 0, "retries stop")
GamepadMainActionBarFrame = { PageUnit = { actionBars = actionBars } }
W.window = true
assert(ns.Layout.Reset())
W.window = nil
tickAll()
check(count() == 0, "reset applied once the pad is free")

io.stdout:write(("face_spec: %d checks passed\n"):format(checks))
