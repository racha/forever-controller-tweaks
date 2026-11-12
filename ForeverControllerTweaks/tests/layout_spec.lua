-- Plain-Lua checks for Layout.lua: lua tests/layout_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ns = {}
assert(loadfile(here .. "/../Layout.lua"))("ForeverControllerTweaks", ns)
local Layout = ns.Layout

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function device(vendor, product)
	local d = Layout.DeviceDefaults(vendor, product)
	d.vendorID, d.productID, d.name = vendor, product, "Pad"
	return d
end

local TAG = "Forever Controller Tweaks"
local function tagged(phys) return TAG .. ": physical " .. phys end

-- Auto-swap: L1 takes rightmod, R2 (its holder) gets friendly; then R1 friendly gives split.
local roles = assert(Layout.AssignRole({}, "L1", "rightmod", false))
assert(same(roles, { L1 = "rightmod", R1 = "hostile", L2 = "leftmod", R2 = "friendly" }))
roles = assert(Layout.AssignRole(roles, "R1", "friendly", false))
assert(same(roles, Layout.PRESETS.split))
assert(Layout.PresetName(roles) == "split")
roles = assert(Layout.AssignRole(Layout.AssignRole(roles, "R1", "hostile", false), "L1", "friendly", false))
assert(same(roles, {}), "swapping back to native stores nothing")
assert(not Layout.AssignRole({}, "L1", "none", false), "a shoulder can't drop its role")
assert(not Layout.AssignRole({}, "X9", "friendly", false))

-- BuildConfig for the split layout equals the config verified in game.
local dualsense = device(0x054c, 0x0ce6)
assert(dualsense.family == "playstation" and not dualsense.hasPaddles and not dualsense.raw.P1)
local config = Layout.BuildConfig(dualsense, Layout.PRESETS.split, false)
assert(same(config, {
	name = "Pad",
	comment = TAG,
	configID = { vendorID = 0x054c, productID = 0x0ce6 },
	rawButtonMappings = { { rawIndex = 9, button = "PADRTRIGGER", comment = tagged("L1") }, { rawIndex = 10, button = "PADLSHOULDER", comment = tagged("R1") } },
	rawAxisMappings = {},
	axisConfigs = { { axis = "RTrigger", deadzone = 0.12, buttonThreshold = 0.5, buttonPos = "PADRSHOULDER", comment = tagged("R2") } },
	stickConfigs = {},
}))
assert(Layout.IsOurs(config) and not Layout.IsOurs({ comment = "other" }) and not Layout.IsOurs(nil))
-- A config written under the addon's first name is still ours, merged over a foreign base or not.
assert(Layout.IsOurs({ comment = "Forever PadShift" }) and Layout.Unmerge({ comment = "Forever PadShift (was: Theirs)", rawButtonMappings = {}, axisConfigs = {} }).comment == "Theirs")

-- Native builds no config, with or without the target swap.
assert(Layout.BuildConfig(dualsense, Layout.PRESETS.native, false) == nil)
assert(Layout.BuildConfig(dualsense, {}, true) == nil)

-- Paddles take a role; the shoulder that gave it up outputs nothing; "none" hands it back.
local edge = device(0x054c, 0x0df2)
assert(edge.hasPaddles and edge.raw.P1.button == 16 and edge.raw.P4.button == 19)
local paddle = assert(Layout.AssignRole(Layout.PRESETS.split, "P1", "friendly", false))
assert(paddle.P1 == "friendly" and paddle.R1 == nil)
config = Layout.BuildConfig(edge, paddle, false)
assert(same(config.rawButtonMappings, {
	{ rawIndex = 9, button = "PADRTRIGGER", comment = tagged("L1") },
	{ rawIndex = 10, button = "None", comment = tagged("R1") },
	{ rawIndex = 16, button = "PADLSHOULDER", comment = tagged("P1") },
}))
assert(same(assert(Layout.AssignRole(paddle, "P1", "none", false)), Layout.PRESETS.split))

-- GamepadSwapTargetModifiers swaps the friendly/hostile output names.
assert(same(Layout.NativeRoles(true), { L1 = "hostile", R1 = "friendly", L2 = "leftmod", R2 = "rightmod" }))
config = Layout.BuildConfig(dualsense, Layout.PRESETS.split, true)
assert(same(config.rawButtonMappings, { { rawIndex = 9, button = "PADRTRIGGER", comment = tagged("L1") } }))
assert(config.axisConfigs[1].buttonPos == "PADLSHOULDER" and #config.axisConfigs == 1)

-- Family default tables: SDL-generic, Sony, Microsoft, Nintendo all build the split config on 9/10/RTrigger. The
-- generic one is a guess, so it builds nothing until the pad is confirmed (learned or detected).
local families = { { 0x2dc8, 0x6001, "generic" }, { 0x054c, 0x09cc, "playstation" }, { 0x045e, 0x0b12, "xbox" }, { 0x057e, 0x2009, "switch" } }
for _, case in ipairs(families) do
	local pad = device(case[1], case[2])
	assert(pad.family == case[3], case[3])
	assert(pad.confirmed == (case[3] ~= "generic"), case[3])
	assert(pad.confirmed or not Layout.BuildConfig(pad, Layout.PRESETS.split, false), "unconfirmed builds nothing")
	pad.confirmed = true
	local built = Layout.BuildConfig(pad, Layout.PRESETS.split, false)
	assert(built.rawButtonMappings[1].rawIndex == 9 and built.rawButtonMappings[2].rawIndex == 10 and built.axisConfigs[1].axis == "RTrigger", case[3])
end
assert(device(0x045e, 0x0b00).hasPaddles and not device(0x057e, 0x2009).hasPaddles)

-- The game's labelStyle decides the family for Valve (Steam Input) and unknown vendors; certain vendors keep theirs.
local steam = Layout.DeviceDefaults(0x28de, 0x11ff, "Letters")
assert(steam.family == "xbox" and steam.known and not steam.hasPaddles)
assert(same(steam.raw, { L1 = { button = 9 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }))
assert(Layout.DeviceDefaults(0x28de, 0x11ff, "Shapes").family == "playstation")
assert(Layout.DeviceDefaults(0x28de, 0x11ff).family == "xbox")
assert(Layout.DeviceDefaults(0x2dc8, 0x6001, "Shapes").family == "playstation")
assert(Layout.DeviceDefaults(0x2dc8, 0x6001, "Reverse").family == "switch")
assert(Layout.DeviceDefaults(0x2dc8, 0x6001, "Generic").family == "xbox")
assert(Layout.DeviceDefaults(0x2dc8, 0x6001).family == "generic")
assert(Layout.DeviceDefaults(0x054c, 0x0ce6, "Letters").family == "playstation")
assert(Layout.DeviceDefaults(0x045e, 0x0b12, "Shapes").family == "xbox")
assert(Layout.Key(0x054c, 0x0ce6) == "054c/0ce6")

-- Glyph source lookup.
local outputs = Layout.Outputs(dualsense.raw, Layout.PRESETS.split, false)
local key, phys = Layout.SourceOf("PADRTRIGGER", outputs)
assert(key == "PADLSHOULDER" and phys == "L1")
assert(Layout.SourceOf("PAD1", outputs) == "PAD1")
assert(Layout.SourceOf("PADPADDLE1", Layout.Outputs(edge.raw, paddle, false)) == nil)

-- Merge keeps a foreign config's other entries and replaces the ones we own.
local foreign = { comment = "Other", rawButtonMappings = { { rawIndex = 9, button = "PAD1" }, { rawIndex = 3, button = "PAD4" } }, axisConfigs = {} }
local merged = Layout.Merge(foreign, Layout.BuildConfig(dualsense, Layout.PRESETS.split, false))
assert(#merged.rawButtonMappings == 3 and merged.rawButtonMappings[1].rawIndex == 3 and Layout.IsOurs(merged))

-- Face moves swap too.
local face = assert(Layout.AssignFace({}, "bottom", "interact"))
assert(face.bottom == "interact" and face.left == "jump")
assert(same(assert(Layout.AssignFace(face, "left", "interact")), {}))
assert(not Layout.AssignFace({}, "middle", "jump") and not Layout.AssignFace({}, "top", "dance"))

print("layout_spec: all checks passed")
