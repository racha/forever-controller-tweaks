-- Stubbed WoW check of device selection with several pads (Steam virtual + physical): lua tests/device_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local now, active = 100, 1
local frames, tickers, lines = {}, {}, {}

local function newPad(name, vendorID, productID, labelStyle)
	local buttons = {}
	for i = 1, 22 do buttons[i] = false end
	return { name = name, vendorID = vendorID, productID = productID, labelStyle = labelStyle, rawButtons = buttons, rawAxes = {} }
end
-- 1 is the combined device: no raw state, as the DualSense run showed.
local pads = { [2] = newPad("Steam Virtual Gamepad", 0x28de, 0x11ff, "Letters"), [3] = newPad("DualSense", 0x054c, 0x0ce6, "Shapes") }
local ids = { 1, 2, 3 }

function CreateFrame()
	local f = { events = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(name, fn) if name == "OnEvent" then self.onEvent = fn end end
	function f:Show() end
	function f:Hide() end
	frames[#frames + 1] = f
	return f
end
function print(msg) lines[#lines + 1] = msg end
function date() return "12:00:00 " end
function GetTime() return now end
function InCombatLockdown() return false end
function GetCVarBool() return false end
SlashCmdList = {}
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
InputUtil = { IsGamepadUIEnabled = function() return true end }
C_Timer = { NewTicker = function(_, fn)
	local t = { fn = fn }
	function t:Cancel() self.cancelled = true end
	tickers[#tickers + 1] = t
	return t
end }
C_GamePad = {
	GetActiveDeviceID = function() return active end,
	GetCombinedDeviceID = function() return 1 end,
	GetAllDeviceIDs = function() return ids end,
	GetDeviceRawState = function(id)
		local pad = pads[id]
		if not pad then return nil end
		local copy = {}
		for k, v in pairs(pad) do copy[k] = v end
		return copy
	end,
	GetDeviceMappedState = function(id)
		local pad = pads[id]
		return { name = pad and pad.name or "combined", labelStyle = pad and pad.labelStyle or "Generic" }
	end,
}

local ns = {}
for _, file in ipairs({ "Core.lua", "Device.lua", "Layout.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end

local deviceChanges = 0
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then deviceChanges = deviceChanges + 1 end end)
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] then f.onEvent(f, event, ...) end
	end
end
local function run()
	for _ = 1, 4 do
		now = now + 0.25
		for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end
	end
end
local function key() return ns.Device.Current() and ns.Device.Current().key end

ForeverControllerTweaksDB = { options = { debug = true } }
fire("ADDON_LOADED", "ForeverControllerTweaks")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

-- First listed pad with a raw state; Steam's virtual pad is xbox through its Letters label style, SDL defaults.
local device = ns.Device.Current()
assert(device.key == "28de/11ff" and device.family == "xbox" and device.labelStyle == "Letters")
assert(device.raw.L1.button == 9 and device.raw.R1.button == 10 and device.raw.R2.axis == "RTrigger" and not device.hasPaddles)
local logged
for _, line in ipairs(ForeverControllerTweaksDB.debugLog) do logged = logged or line:find("name=Steam Virtual Gamepad vendor=28de product=11ff labelStyle=Letters", 1, true) end
assert(logged, "detection is in the debug log")

-- Input on the physical pad moves the addon to it; Steam mirroring the press keeps it there.
pads[3].rawButtons[1] = true
run()
assert(key() == "054c/0ce6" and ns.Device.Current().family == "playstation" and deviceChanges >= 2)
local changes = deviceChanges
pads[2].rawButtons[1] = true
run()
assert(key() == "054c/0ce6" and deviceChanges == changes, "both pressed: stays")
pads[3].rawButtons[1] = false
run()
assert(key() == "28de/11ff", "only the virtual pad pressed: moves back")
pads[2].rawButtons[1] = false

-- An active device with a raw state always wins.
active = 3
fire("GAME_PAD_ACTIVE_CHANGED", true)
pads[2].rawButtons[1] = true
run()
assert(key() == "054c/0ce6")
pads[2].rawButtons[1] = false
active = 1

-- Per-device layouts stay separate.
assert(ns.Layout.SetPreset("split"))
assert(ForeverControllerTweaksDB.devices["054c/0ce6"].roles.L1 == "rightmod" and next(ForeverControllerTweaksDB.devices["28de/11ff"].roles) == nil)

-- Unknown vendor: its label style decides. Both earlier pads are unplugged.
pads[2], pads[3], pads[4] = nil, nil, newPad("8BitDo", 0x2dc8, 0x6001, "Shapes")
ids = { 1, 4 }
fire("GAME_PAD_CONNECTED")
assert(key() == "2dc8/6001" and ns.Device.Current().family == "playstation")
pads[4].labelStyle = "Reverse"
fire("GAME_PAD_ACTIVE_CHANGED", true)
assert(ns.Device.Current().family == "switch")

-- With the shared stubs: 0/1-based raw tables, learn rejection and cancel, and an unknown pad that needs setup.
local harness = dofile(here .. "/wow.lua")

-- held = 0-based raw button index, whatever base the pad's tables use.
local function learnPress(H, pad, phys, held, base)
	H.slash("learn " .. phys)
	H.run(0.2)
	pad.rawButtons[held + base] = true
	H.run(0.8)
	pad.rawButtons[held + base] = false
	H.run(0.2)
end

for _, base in ipairs({ 0, 1 }) do
	local H = harness(dir, { pads = {} })
	local pad = H.newPad("Base " .. base, 0x054c, 0x0ce6, base)
	H.pads[1] = pad
	H.login()
	local Dev = H.ns.Device
	assert(Dev.RawBase() == base)
	learnPress(H, pad, "R1", 11, base)
	assert(H.said("R1 learned: raw button 11") and Dev.Current().raw.R1.button == 11, "base " .. base)

	-- Raw 9 is L1's: holding it for R1 is rejected, and both keep their inputs.
	learnPress(H, pad, "R1", 9, base)
	assert(H.said("that input already drives L1") and Dev.Current().raw.R1.button == 11 and Dev.Current().raw.L1.button == 9)
	assert(Dev.Learning() == "R1", "learning goes on after a rejection")
	assert(Dev.LearnCancel() and not Dev.Learning() and H.said("learn R1: cancelled"))
	assert(not Dev.LearnCancel(), "nothing left to cancel")
end

-- An unknown pad needs setup: nothing is written until it is learned (or detected).
local H = harness(dir, { pads = {} })
local unknown = H.newPad("Cheap Pad", 0x2dc8, 0x6001, 1)
unknown.labelStyle = "Generic"
H.pads[1] = unknown
local changes = 0
H.login()
H.ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason ~= "remap" then changes = changes + 1 end end)
assert(H.ns.Device.NeedsSetup() and H.ns.Remap.State() == "needsSetup")
assert(H.ns.Layout.SetPreset("split"))
H.run()
assert(next(H.configs) == nil and H.ns.Remap.State() == "needsSetup", "no guessed config written")
learnPress(H, unknown, "L1", 9, 1)
assert(not H.ns.Device.NeedsSetup() and H.ns.db.devices["2dc8/6001"].confirmed and changes >= 2)
H.run()
assert(H.configs["2dc8/6001"] and H.ns.Remap.State() == "ours", "confirmed by learning: the layout applies")

io.stdout:write("device_spec: all checks passed\n")
