-- Stubbed WoW check of controller detection: lua tests/detect_spec.lua
-- A scripted unknown pad goes through every step (scrambled face buttons, a hat D-pad, an analog trigger resting at
-- -1, a digital trigger, sticks with inverted signs, a noisy gyro axis, a duplicate, a back, skips), then the stored
-- detect table and the full config the addon writes are compared, alone and with a role remap on top.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local now, combat, padFree = 100, false, true
local frames, tickers, configs, events = {}, {}, {}, {}

local function copy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = copy(x) end
	return o
end
local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function idKey(id) return string.format("%04x/%04x", id.vendorID, id.productID) end

function CreateFrame()
	local f = { events = {}, scripts = {}, shown = true }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	frames[#frames + 1] = f
	return f
end
function print() end
function date() return "12:00:00 " end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetCVarBool() return false end
SlashCmdList = {}
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
InputUtil = { IsGamepadUIEnabled = function() return true end }
GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return padFree end } }
C_Timer = { NewTicker = function(_, fn)
	local t = { fn = fn }
	function t:Cancel() self.cancelled = true end
	tickers[#tickers + 1] = t
	return t
end }

-- The fake pad: 1-based raw tables, 16 buttons and 9 axes. Axis 3 is a trigger resting at -1; axis 8 a noisy gyro.
local buttons, axes = {}, {}
for i = 1, 16 do buttons[i] = false end
for i = 1, 9 do axes[i] = 0 end
axes[4] = -1
local pad = { name = "Generic Pad", vendorID = 0x1234, productID = 0x5678 }
C_GamePad = {
	GetActiveDeviceID = function() return 1 end,
	GetAllDeviceIDs = function() return { 1 } end,
	GetDeviceRawState = function()
		return { name = pad.name, vendorID = pad.vendorID, productID = pad.productID, rawButtons = copy(buttons), rawAxes = copy(axes) }
	end,
	GetDeviceMappedState = function() return { labelStyle = "Generic" } end,
	GetConfig = function(id) return copy(configs[idKey(id)]) end,
	SetConfig = function(c) configs[idKey(c.configID)] = copy(c) end,
	DeleteConfig = function(id) configs[idKey(id)] = nil end,
	ApplyConfigs = function() assert(not combat) end,
	GetAllConfigIDs = function() return {} end,
}

local ns = {}
for _, file in ipairs({ "Core.lua", "Device.lua", "Layout.lua", "Remap.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
local Device, Layout = ns.Device, ns.Layout
local KEY = "1234/5678"

local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] then f.scripts.OnEvent(f, event, ...) end
	end
end
local gyro, gyroSwing = 0, 0
local function run(seconds)
	for _ = 1, math.floor((seconds or 0.2) * 30) do
		now = now + 1 / 30
		gyro = gyro + 1
		axes[9] = gyroSwing + ((gyro % 2 == 0) and 0.3 or -0.3)
		for _, f in ipairs(frames) do
			if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1 / 30) end
		end
		for _, t in ipairs(tickers) do if not t.cancelled then t.fn() end end
	end
end
local function press(raw)
	buttons[raw + 1] = true
	run(0.1)
	buttons[raw + 1] = false
	run(0.1)
end
local function push(raw, value, rest)
	axes[raw + 1] = value
	run(0.1)
	axes[raw + 1] = rest or 0
	run(0.1)
end
local function last(kind)
	for i = #events, 1, -1 do
		if events[i][1] == kind then return events[i] end
	end
end
local function stepID() return last("step")[2].id end

fire("ADDON_LOADED", "ForeverControllerTweaks")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
run()
assert(Device.Current().family == "xbox", "unknown vendor, Generic label style")

combat = true
assert(not Device.DetectStart(function() end), "refused in combat")
combat = false

assert(Device.DetectStart(function(kind, a, b) events[#events + 1] = { kind, a, b } end))
assert(events[1][1] == "calibrating" and Device.Detecting() and ns.panelOpen)
assert(#Device.DetectSteps() == 26 and Device.DetectSteps()[1].id == "faceBottom")
run(1.2)
assert(stepID() == "faceBottom")

press(2)
press(1)
press(2)
assert(last("rejected")[3] == "already used for faceBottom" and stepID() == "faceLeft")
press(3)
assert(not Device.DetectSkip() and stepID() == "faceTop", "a required step can't be skipped")
press(0)
push(7, -1)
push(7, 1)
push(6, -1)
push(6, 1)
press(4)
assert(Device.DetectBack() and stepID() == "lb", "back re-asks the previous step")
press(4)
press(5)
buttons[14] = true -- some pads click a button at full pull; the axis still wins
push(3, 1, -1)
buttons[14] = false
run()
-- The pad tilts while the digital trigger is pressed: the gyro axis, noisy at calibration, must not count as a pull.
gyroSwing = 0.9
press(7)
gyroSwing = 0
run()
press(10)
press(11)
press(9)
press(8)
press(12)
for _ = 1, 5 do assert(Device.DetectSkip()) end
assert(stepID() == "lstickX")
push(0, 1)
push(1, 1)
push(2, -1)
push(5, -1)
assert(last("done") and not Device.DetectSkip())

-- While detection ran, nothing of ours was applied; the unknown pad still needs setup until the detection is saved.
assert(configs[KEY] == nil and ns.Remap.State() == "needsSetup" and Device.NeedsSetup())

local expected = {
	version = 1,
	buttons = { PAD1 = 2, PAD2 = 1, PAD3 = 3, PAD4 = 0, PADLSHOULDER = 4, PADRSHOULDER = 5, PADRTRIGGER = 7, PADLSTICK = 10, PADRSTICK = 11, PADFORWARD = 9, PADBACK = 8, PADSYSTEM = 12 },
	axes = { LTrigger = { raw = 3, shift = 1, scale = 0.5 }, LStickX = { raw = 0, scale = 1 }, LStickY = { raw = 1, scale = -1 }, RStickX = { raw = 2, scale = -1 }, RStickY = { raw = 5, scale = 1 } },
	hats = { PADDUP = { raw = 7, value = -1 }, PADDDOWN = { raw = 7, value = 1 }, PADDLEFT = { raw = 6, value = -1 }, PADDRIGHT = { raw = 6, value = 1 } },
}
assert(same(last("done")[2], expected), "the done result")
assert(not Device.DetectFinish("Wingdings"))
-- A family picked earlier (wrong buttons) is replaced cleanly by the wizard's result.
assert(Device.SetFamily(KEY, "xbox") and Device.Current().labelStyle == "Letters")
assert(Device.DetectFinish("Shapes"))
expected.labelStyle = "Shapes"
local entry = ForeverControllerTweaksDB.devices[KEY]
assert(entry.family == nil and entry.familyPicked == nil and Device.Current().labelStyle == "Shapes", "the wizard wins over the pick")
assert(same(entry.detect, expected) and not Device.Detecting() and not ns.panelOpen)
assert(same(entry.raw, { L1 = { button = 4 }, R1 = { button = 5 }, L2 = { axis = "LTrigger" }, R2 = { button = 7 } }))
assert(Device.Current().family == "playstation", "the chosen label style decides an unknown vendor's family")
assert(not Device.NeedsSetup(), "a detection confirms the pad")

-- The full config, written as soon as the pad is free.
run()
local TAG = "Forever Controller Tweaks"
local function b(raw, button, comment) return { rawIndex = raw, button = button, comment = comment } end
local function stick(axis, scale) return { axis = axis, shift = 0, scale = scale, deadzone = 0.05 } end
local full = {
	name = "Generic Pad",
	comment = TAG,
	labelStyle = "Shapes",
	configID = { vendorID = 0x1234, productID = 0x5678 },
	rawButtonMappings = {
		b(2, "PAD1"), b(1, "PAD2"), b(3, "PAD3"), b(0, "PAD4"), b(4, "PADLSHOULDER"), b(5, "PADRSHOULDER"),
		b(7, "PADRTRIGGER"), b(10, "PADLSTICK"), b(11, "PADRSTICK"), b(9, "PADFORWARD"), b(8, "PADBACK"), b(12, "PADSYSTEM"),
	},
	rawAxisMappings = {
		{ rawIndex = 7, axis = "PStickX" }, { rawIndex = 6, axis = "PStickY" }, { rawIndex = 3, axis = "LTrigger" },
		{ rawIndex = 0, axis = "LStickX" }, { rawIndex = 1, axis = "LStickY" }, { rawIndex = 2, axis = "RStickX" }, { rawIndex = 5, axis = "RStickY" },
	},
	axisConfigs = {
		{ axis = "PStickX", buttonThreshold = 0.5, buttonNeg = "PADDUP", buttonPos = "PADDDOWN" },
		{ axis = "PStickY", buttonThreshold = 0.5, buttonNeg = "PADDLEFT", buttonPos = "PADDRIGHT" },
		{ axis = "LTrigger", shift = 1, scale = 0.5, deadzone = 0.12, buttonThreshold = 0.5, buttonPos = "PADLTRIGGER" },
		stick("LStickX", 1), stick("LStickY", -1), stick("RStickX", -1), stick("RStickY", 1),
	},
	stickConfigs = {
		{ stick = "Left", axisX = "LStickX", axisY = "LStickY", deadzone = 0.25 },
		{ stick = "Right", axisX = "RStickX", axisY = "RStickY", deadzone = 0.25 },
		{ stick = "Movement", axisX = "LStickX", axisY = "LStickY", deadzoneX = 0.05, deadzoneY = 0.05, deadzone = 0.25 },
		{ stick = "Camera", axisX = "RStickX", axisY = "RStickY", deadzoneX = 0.05, deadzoneY = 0.2, deadzone = 0.25 },
	},
}
assert(same(configs[KEY], full), "the full detected config")

-- The split preset composes on top: shoulders and the digital trigger move, the rest of the mapping stays.
assert(Layout.SetPreset("split"))
run()
local composed = copy(full)
local physical = function(phys) return TAG .. ": physical " .. phys end
composed.rawButtonMappings = {
	b(2, "PAD1"), b(1, "PAD2"), b(3, "PAD3"), b(0, "PAD4"), b(10, "PADLSTICK"), b(11, "PADRSTICK"), b(9, "PADFORWARD"), b(8, "PADBACK"), b(12, "PADSYSTEM"),
	b(4, "PADRTRIGGER", physical("L1")), b(5, "PADLSHOULDER", physical("R1")), b(7, "PADRSHOULDER", physical("R2")),
}
assert(same(configs[KEY], composed) and ns.Remap.State() == "ours", "split over the detected config")

-- A role on the analog trigger changes only its buttonPos; its shift and scale stay.
local swapped = Layout.BuildConfig(Device.Current(), { L1 = "friendly", R1 = "hostile", L2 = "rightmod", R2 = "leftmod" }, false)
assert(same(swapped.axisConfigs[3], { axis = "LTrigger", shift = 1, scale = 0.5, deadzone = 0.12, buttonThreshold = 0.5, buttonPos = "PADRTRIGGER", comment = physical("L2") }))

-- A window holds the pad: the detected mapping stays, only the roles go.
padFree = false
run()
assert(same(configs[KEY], full) and ns.Remap.State() == "native")
padFree = true
run()
assert(ns.Remap.State() == "ours")

-- Detection again: native while it runs, and a cancel gives everything back.
assert(Device.DetectStart(function(kind, a, b) events[#events + 1] = { kind, a, b } end))
run()
assert(configs[KEY] == nil)
assert(Device.DetectCancel() and last("cancelled") and not ns.panelOpen)
run()
assert(same(configs[KEY], composed))

-- Reset: the game default comes back.
assert(Layout.SetPreset("native") and Device.DetectReset(KEY))
run()
assert(entry.detect == nil and configs[KEY] == nil and entry.raw.L1.button == 9)

-- The chat flow drives the same engine.
SlashCmdList.FOREVERCONTROLLERTWEAKS("detect")
assert(Device.Detecting())
SlashCmdList.FOREVERCONTROLLERTWEAKS("detect cancel")
assert(not Device.Detecting())

io.stdout:write("detect_spec: all checks passed\n")
