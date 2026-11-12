-- Stubbed WoW check of the Gamepad UI gate: lua tests/active_spec.lua
-- Turns the option on -> off -> on (the last one during combat) and checks the controller config, the face-router
-- bindings and the glyph overlay apply, clear and re-apply. Restricted snippets can't run here, so the header's
-- Execute is emulated from the attributes the face router writes.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local now, combat, gamepadUI = 100, false, true
local frames, tickers, configs, lines = {}, {}, {}, {}

local function copy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = copy(x) end
	return o
end
local function idKey(id) return string.format("%04x/%04x", id.vendorID, id.productID) end
local function noop() return 1 end

local Obj = {}
local function new(name)
	local o = setmetatable({ attrs = {}, scripts = {}, shown = true, alpha = 1, name = name }, { __index = function(_, k) return Obj[k] or noop end })
	frames[#frames + 1] = o
	if name then _G[name] = o end
	return o
end
function Obj:SetAttribute(k, v) self.attrs[k] = v end
function Obj:GetAttribute(k) return self.attrs[k] end
function Obj:Show() self.shown = true end
function Obj:Hide() self.shown = false end
function Obj:SetShown(s) self.shown = not not s end
function Obj:IsShown() return self.shown end
function Obj:IsVisible() return self.shown end
function Obj:SetAlpha(a) self.alpha = a end
function Obj:GetAlpha() return self.alpha end
function Obj:GetParent() return UIParent end
function Obj:GetName() return self.name end
function Obj:SetScript(k, fn) self.scripts[k] = fn end
function Obj:GetScript(k) return self.scripts[k] end
function Obj:CreateTexture() return new() end
function Obj:CreateFontString() return new() end
function Obj:CreateMaskTexture() return new() end
-- APPLY_SNIPPET, emulated: clear, then bind each ps-keyN while routed and enabled.
function Obj:Execute(code)
	if not code:find("ClearBindings") then return end
	self.bindings = {}
	if self.attrs["state-face"] ~= "routed" or not self.attrs["ps-enabled"] then return end
	for i = 1, 4 do
		local key = self.attrs["ps-key" .. i]
		if key then self.bindings[key] = self.attrs["ps-router" .. i] end
	end
end

UIParent = new()
function CreateFrame(_, name) return new(name) end
function print(msg) lines[#lines + 1] = msg end
function date() return "12:00:00 " end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetCVar() return nil end
function GetCVarBool() return false end
function GetBindingAction() return "" end
function RegisterStateDriver(frame, state) if state == "face" then frame.attrs["state-face"] = "routed" end end
SecureHandlerSetFrameRef = noop
SlashCmdList = {}
Enum = { BindingContext = { GamepadModeInGameCore = 9 }, InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
InputUtil = { IsGamepadUIEnabled = function() return gamepadUI end }
GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return true end } }
InputIconTextureSetUtility = { GetActiveInputIconButtonTextures = function() return { "atlas" } end }
InputDeviceIconSetManager = { RegisterActiveInputDeviceIconSetUpdatedCallback = noop }
C_Timer = { NewTicker = function(_, fn)
	local t = { fn = fn }
	function t:Cancel() self.cancelled = true end
	tickers[#tickers + 1] = t
	return t
end }

local raw = { name = "DualSense", vendorID = 0x054c, productID = 0x0ce6, rawButtons = {}, rawAxes = {} }
for i = 1, 22 do raw.rawButtons[i] = false end
C_GamePad = {
	GetActiveDeviceID = function() return 1 end,
	GetAllDeviceIDs = function() return { 1 } end,
	GetDeviceRawState = function() return copy(raw) end,
	ButtonBindingToIndex = function() return 3 end,
	GetConfig = function(id) return copy(configs[idKey(id)]) end,
	SetConfig = function(c) configs[idKey(c.configID)] = copy(c) end,
	DeleteConfig = function(id) configs[idKey(id)] = nil end,
	ApplyConfigs = function() assert(not combat, "ApplyConfigs in combat") end,
	GetAllConfigIDs = function()
		local ids = {}
		for _, c in pairs(configs) do ids[#ids + 1] = copy(c.configID) end
		return ids
	end,
}

-- A crossbar glyph for PADRTRIGGER, which physical L1 outputs under the split preset.
local leftIcon = new()
leftIcon.mappedButtonKey = "PADRTRIGGER"
for _, t in ipairs({ "NormalTexture", "HoverTexture", "PressedTexture", "ActiveTexture", "DisabledTexture" }) do leftIcon[t] = new() end
local topButtons = {}
for i = 1, 8 do
	topButtons[i] = new("TopButton" .. i)
	topButtons[i].ButtonIcon = false
end
GamepadMainActionBarFrame = { PageUnit = { LeftIcon = leftIcon, actionBars = { topBar = { actionButtons = topButtons } } } }

local ns = {}
for _, file in ipairs({ "Core.lua", "Device.lua", "Layout.lua", "Remap.lua", "Face.lua", "Glyphs.lua" }) do
	assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns)
end

local function fire(event, ...)
	for _, f in ipairs(frames) do
		local onEvent = f.scripts.OnEvent
		if onEvent then onEvent(f, event, ...) end
	end
end
local function run()
	for _ = 1, 5 do
		now = now + 0.1
		for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end
		for _, f in ipairs(frames) do
			local onUpdate = f.shown and f.scripts.OnUpdate
			if onUpdate then onUpdate(f, 0.1) end
		end
	end
end
local function toggle(on)
	gamepadUI = on
	fire("INPUT_DEVICE_INTERFACE_TRANSITION", on and 1 or 0, on and 0 or 1)
	run()
end
local function said(pattern)
	for _, line in ipairs(lines) do if line:find(pattern) then return true end end
end

local header = ForeverControllerTweaksFaceHeader
local DS = "054c/0ce6"
local function overlayShown()
	for _, f in ipairs(frames) do
		if f ~= leftIcon and f.target == leftIcon then return f.shown end
	end
	return false
end
local function applied()
	return configs[DS] ~= nil and ns.Remap.State() == "ours" and header.bindings.PAD1 ~= nil and overlayShown() and leftIcon.NormalTexture.alpha == 0 and leftIcon.alpha == 1
end
local function cleared()
	return configs[DS] == nil and ns.Remap.State() ~= "ours" and next(header.bindings) == nil and not overlayShown() and leftIcon.NormalTexture.alpha == 1
end

fire("ADDON_LOADED", "ForeverControllerTweaks")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
assert(ns.Active())
SlashCmdList.FOREVERCONTROLLERTWEAKS("preset split")
SlashCmdList.FOREVERCONTROLLERTWEAKS("face bottom interact")
run()
assert(applied(), "on: applied")

toggle(false)
assert(not ns.Active() and cleared(), "off: cleared")
SlashCmdList.FOREVERCONTROLLERTWEAKS("status")
assert(said("Gamepad UI off"))
SlashCmdList.FOREVERCONTROLLERTWEAKS("learn L1")
assert(said("learn: Gamepad UI off"))
SlashCmdList.FOREVERCONTROLLERTWEAKS("role L1 friendly")
run()
assert(cleared() and ForeverControllerTweaksDB.devices[DS].roles.L1 == "friendly", "edits are stored while inactive")
SlashCmdList.FOREVERCONTROLLERTWEAKS("preset split")

-- On again during combat: nothing changes until combat ends.
combat = true
toggle(true)
assert(cleared(), "on in combat: still native")
combat = false
run()
assert(applied(), "on after combat: re-applied")

io.stdout:write("active_spec: all checks passed\n")
