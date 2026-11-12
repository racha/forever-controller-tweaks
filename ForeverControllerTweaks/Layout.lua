-- Forever Controller Tweaks layout model: roles, face actions, controller-family defaults and the controller config builder.
-- No WoW API and Lua 5.1 syntax only, so tests/layout_spec.lua runs this file in plain Lua. The runtime helpers at
-- the bottom reach the game only through ns.Device and ns.Remap.
local _, ns = ...
local Layout = {}
ns.Layout = Layout

local TAG = "Forever Controller Tweaks"
-- Controller configs live in the game's own settings, not in SavedVariables: one written under the addon's first name
-- is still ours, or a remap would build on it as foreign and put it back for native.
local OLD_TAG = "Forever PadShift"
local function tagged(comment) return type(comment) == "string" and (comment:sub(1, #TAG) == TAG or comment:sub(1, #OLD_TAG) == OLD_TAG) end

Layout.PHYSICAL = { "L1", "R1", "L2", "R2", "P1", "P2", "P3", "P4" }
Layout.ROLES = { "leftmod", "rightmod", "friendly", "hostile" }
Layout.NATIVE_KEY = {
	L1 = "PADLSHOULDER", R1 = "PADRSHOULDER", L2 = "PADLTRIGGER", R2 = "PADRTRIGGER",
	P1 = "PADPADDLE1", P2 = "PADPADDLE2", P3 = "PADPADDLE3", P4 = "PADPADDLE4",
}

-- Face actions are stored by position, as Blizzard does (PAD1-PAD4), so Switch's swapped A/B needs no special case.
Layout.FACE_POSITIONS = { "bottom", "right", "left", "top" }
Layout.FACE_KEY = { bottom = "PAD1", right = "PAD2", left = "PAD3", top = "PAD4" }
Layout.FACE_ACTIONS = { "interact", "inspect", "back", "jump" }
Layout.NATIVE_FACE = { bottom = "jump", right = "back", left = "interact", top = "inspect" }

Layout.PRESETS = {
	native = {},
	split = { L2 = "leftmod", L1 = "rightmod", R1 = "friendly", R2 = "hostile" },
}

-- SDL GameController raw order, which WTF/GamePadConfig_Default.json follows: 9/10 shoulders, 16-19 paddles,
-- raw axes 4/5 the triggers.
Layout.TRIGGER_AXES = { [4] = "LTrigger", [5] = "RTrigger" }
local SDL_RAW = { L1 = { button = 9 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }
local SDL_PADDLES = { P1 = { button = 16 }, P2 = { button = 17 }, P3 = { button = 18 }, P4 = { button = 19 } }

-- Per-vendor overrides, keyed by vendor ID hex. Only the DualSense (054c/0ce6) is confirmed in game; the paddle
-- product IDs (DualSense Edge, Xbox Elite 1/2) and the other vendors' raw order come from SDL.
-- certain: the vendor makes one family, so it wins over the game's labelStyle. Valve's Steam Input virtual gamepad
-- (and Steam Deck) can stand for any pad, so its labelStyle decides, with Xbox labels when it gives none.
-- Motion axes (gyro, touchpad) are ignored by the learn flow.
Layout.FAMILIES = {
	["054c"] = { family = "playstation", certain = true, motionAxes = { [6] = true, [7] = true, [8] = true, [9] = true }, paddles = { ["0df2"] = true } },
	["045e"] = { family = "xbox", certain = true, paddles = { ["02e3"] = true, ["0b00"] = true, ["0b05"] = true, ["0b22"] = true } },
	["057e"] = { family = "switch", certain = true },
	["28de"] = { family = "xbox" },
}
-- C_GamePad.GetDeviceMappedState().labelStyle, the set the game draws its glyphs with.
Layout.LABEL_FAMILY = { Letters = "xbox", Generic = "xbox", Shapes = "playstation", Reverse = "switch" }
-- The label set a family picked for an unrecognised pad uses (Device.SetFamily).
Layout.FAMILY_STYLE = { playstation = "Shapes", xbox = "Letters", switch = "Reverse" }

-- What nobody listens to; the game's default config maps the DualSense touchpad click this way.
local NONE = "None"
-- The "All Devices" LTrigger/RTrigger axisConfigs in WTF/GamePadConfig_Default.json.
local TRIGGER_DEADZONE, TRIGGER_THRESHOLD = 0.12, 0.5
local ROLE_KEY = { leftmod = "PADLTRIGGER", rightmod = "PADRTRIGGER", friendly = "PADLSHOULDER", hostile = "PADRSHOULDER" }
local SWAPPED = { friendly = "hostile", hostile = "friendly" }
local LISTS = { "rawButtonMappings", "rawAxisMappings", "axisConfigs", "stickConfigs" }

local IS_NATIVE_KEY = {}
for _, key in pairs(Layout.NATIVE_KEY) do IS_NATIVE_KEY[key] = true end

local function isPaddle(phys) return phys:sub(1, 1) == "P" end

function Layout.Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, inner in pairs(value) do out[key] = Layout.Copy(inner) end
	return out
end

function Layout.Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for key, value in pairs(a) do if not Layout.Same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function sameMap(a, b)
	for key, value in pairs(a) do if b[key] ~= value then return false end end
	for key, value in pairs(b) do if a[key] ~= value then return false end end
	return true
end

function Layout.Key(vendorID, productID) return string.format("%04x/%04x", vendorID or 0, productID or 0) end

function Layout.IsOurs(config)
	return tagged(config and config.comment)
end

-- Defaults for a device nobody has learned yet: family, raw sources (paddles only on paddle hardware), motion axes.
-- labelStyle (optional) is the game's own label set for the device.
function Layout.DeviceDefaults(vendorID, productID, labelStyle)
	local key = Layout.Key(vendorID, productID)
	local vendor, product = key:sub(1, 4), key:sub(6, 9)
	local entry = Layout.FAMILIES[vendor]
	local family = entry and entry.certain and entry.family or Layout.LABEL_FAMILY[labelStyle] or entry and entry.family or "generic"
	local hasPaddles = not not (entry and entry.paddles and entry.paddles[product])
	local raw = Layout.Copy(SDL_RAW)
	if hasPaddles then
		for phys, source in pairs(SDL_PADDLES) do raw[phys] = Layout.Copy(source) end
	end

	-- confirmed: the raw order is trusted. An unknown vendor's is a guess until the player learns or detects it.
	return { family = family, raw = raw, hasPaddles = hasPaddles, motionAxes = entry and entry.motionAxes or {}, known = not not entry, confirmed = not not entry }
end

function Layout.DefaultsForKey(key, labelStyle)
	return Layout.DeviceDefaults(tonumber(key:sub(1, 4), 16) or 0, tonumber(key:sub(6, 9), 16) or 0, labelStyle)
end

-- SavedVariables repair for one devices[key] entry, in place. Returns the entry (nil to drop it) and what was fixed.
local DEVICE_FIELDS = { raw = "table", roles = "table", face = "table", detect = "table", foreign = "table", confirmed = "boolean", family = "string", familyPicked = "boolean" }
local IS_ROLE, IS_POSITION, IS_ACTION = {}, {}, {}
for _, role in ipairs(Layout.ROLES) do IS_ROLE[role] = true end
for _, pos in ipairs(Layout.FACE_POSITIONS) do IS_POSITION[pos] = true end
for _, action in ipairs(Layout.FACE_ACTIONS) do IS_ACTION[action] = true end

local function isIndex(value) return type(value) == "number" and value >= 0 and value % 1 == 0 end

local function validSource(source)
	if type(source) ~= "table" then return false end
	local count = 0
	for _ in pairs(source) do count = count + 1 end
	return count == 1 and (isIndex(source.button) or type(source.axis) == "string")
end

-- Empty, or every one of values used exactly once on a valid key.
local function validAssignment(map, isKey, isValue, needed)
	local seen, count = {}, 0
	for key, value in pairs(map) do
		if not isKey(key) or not isValue[value] or seen[value] then return false end
		seen[value], count = true, count + 1
	end
	return count == 0 or count == needed
end

local function validDetect(detect)
	if type(detect.buttons or {}) ~= "table" or type(detect.axes or {}) ~= "table" or type(detect.hats or {}) ~= "table" then return false end
	for _, raw in pairs(detect.buttons or {}) do if not isIndex(raw) then return false end end
	for _, axis in pairs(detect.axes or {}) do
		if type(axis) ~= "table" or not isIndex(axis.raw) then return false end
		if axis.shift ~= nil and type(axis.shift) ~= "number" or axis.scale ~= nil and type(axis.scale) ~= "number" then return false end
	end
	for _, hat in pairs(detect.hats or {}) do
		if type(hat) ~= "table" or not isIndex(hat.raw) or (hat.value ~= 1 and hat.value ~= -1) then return false end
	end
	return true
end

function Layout.RepairDevice(entry, key)
	if type(key) ~= "string" or not key:match("^%x%x%x%x/%x%x%x%x$") then return nil, { "bad device key" } end
	if type(entry) ~= "table" then return nil, { "not a table" } end

	local fixes = {}
	local function fix(what) fixes[#fixes + 1] = what end
	for field, value in pairs(entry) do
		if DEVICE_FIELDS[field] ~= type(value) then
			entry[field] = nil
			fix("dropped " .. tostring(field))
		end
	end

	if entry.raw then
		for phys, source in pairs(entry.raw) do
			if not Layout.NATIVE_KEY[phys] or not validSource(source) then
				entry.raw[phys] = nil
				fix("raw " .. tostring(phys))
			end
		end
	else
		entry.raw = Layout.DefaultsForKey(key).raw
		fix("raw missing")
	end
	if not entry.roles or not validAssignment(entry.roles, function(phys) return Layout.NATIVE_KEY[phys] ~= nil end, IS_ROLE, #Layout.ROLES) then
		if entry.roles then fix("roles") end
		entry.roles = {}
	end
	if not entry.face or not validAssignment(entry.face, function(pos) return IS_POSITION[pos] end, IS_ACTION, #Layout.FACE_ACTIONS) then
		if entry.face then fix("face") end
		entry.face = {}
	end
	if entry.detect and not validDetect(entry.detect) then
		entry.detect = nil
		fix("detect")
	end
	if entry.detect and entry.detect.labelStyle ~= nil and not Layout.LABEL_FAMILY[entry.detect.labelStyle] then
		entry.detect.labelStyle = nil
		fix("detect labelStyle")
	end
	if (entry.family ~= nil) ~= (entry.familyPicked == true) or entry.family and not Layout.FAMILY_STYLE[entry.family] then
		entry.family, entry.familyPicked = nil, nil
		fix("family")
	end
	return entry, fixes
end

-- With GamepadSwapTargetModifiers on, the game treats the left target modifier as hostile, so the names swap.
function Layout.RoleKey(role, swap)
	if swap then role = SWAPPED[role] or role end
	return ROLE_KEY[role]
end

function Layout.NativeRoles(swap)
	return { L1 = swap and "hostile" or "friendly", R1 = swap and "friendly" or "hostile", L2 = "leftmod", R2 = "rightmod" }
end

-- Stored roles are either empty (native) or a full assignment.
function Layout.Effective(roles, swap)
	if roles and next(roles) then return Layout.Copy(roles) end
	return Layout.NativeRoles(swap)
end

local function normalize(roles, swap)
	if sameMap(roles, Layout.NativeRoles(swap)) then return {} end
	return roles
end

-- Gives role to phys and swaps: the button that held the role takes phys's old one, so every role keeps exactly one
-- source. "none" is allowed on a paddle only; its role goes back to the native holder, else the first free button.
-- Returns the new stored roles, or nil and a reason.
function Layout.AssignRole(roles, phys, role, swap)
	if not Layout.NATIVE_KEY[phys] then return nil, "unknown button " .. tostring(phys) end

	local out = Layout.Effective(roles, swap)
	if role == "none" then
		local old = out[phys]
		if not old then return normalize(out, swap) end
		if not isPaddle(phys) then return nil, "every role needs a button; give " .. old .. " to another button instead" end

		local free
		for _, other in ipairs({ "L1", "R1", "L2", "R2" }) do
			if not out[other] then free = free or other end
		end
		for other, native in pairs(Layout.NativeRoles(swap)) do
			if native == old and not out[other] then free = other end
		end
		out[phys], out[free] = nil, old
		return normalize(out, swap)
	end
	if not ROLE_KEY[role] then return nil, "unknown role " .. tostring(role) end

	local holder
	for other, held in pairs(out) do
		if held == role then holder = other end
	end
	if holder ~= phys then out[holder], out[phys] = out[phys], role end
	return normalize(out, swap)
end

-- The native key each physical button outputs under these roles. A button without a raw source isn't remapped, so it
-- keeps its native key; a paddle without a role keeps PADPADDLEn; a shoulder without a role outputs nothing.
function Layout.Outputs(raw, roles, swap)
	local eff, out = Layout.Effective(roles, swap), {}
	for _, phys in ipairs(Layout.PHYSICAL) do
		local role = eff[phys]
		local key = role and Layout.RoleKey(role, swap) or isPaddle(phys) and Layout.NATIVE_KEY[phys] or NONE
		out[phys] = raw[phys] and key or Layout.NATIVE_KEY[phys]
	end
	return out
end

-- Controller detection ("press each button"): every control, in the order the player is asked; optional ones can be skipped.
-- kind: "button" (an axis hat or D-pad is the fallback), "trigger" (axis preferred, button fallback) or "stick".
local function step(id, target, prompt, kind, optional) return { id = id, target = target, prompt = prompt, kind = kind or "button", optional = optional } end
Layout.DETECT_STEPS = {
	step("faceBottom", "PAD1", "Bottom face button (A / Cross)"),
	step("faceRight", "PAD2", "Right face button (B / Circle)"),
	step("faceLeft", "PAD3", "Left face button (X / Square)"),
	step("faceTop", "PAD4", "Top face button (Y / Triangle)"),
	step("dpadUp", "PADDUP", "D-pad up"),
	step("dpadDown", "PADDDOWN", "D-pad down"),
	step("dpadLeft", "PADDLEFT", "D-pad left"),
	step("dpadRight", "PADDRIGHT", "D-pad right"),
	step("lb", "PADLSHOULDER", "Left bumper"),
	step("rb", "PADRSHOULDER", "Right bumper"),
	step("lt", "LTrigger", "Left trigger", "trigger"),
	step("rt", "RTrigger", "Right trigger", "trigger"),
	step("l3", "PADLSTICK", "Press the left stick"),
	step("r3", "PADRSTICK", "Press the right stick"),
	step("start", "PADFORWARD", "Menu / Start / Options"),
	step("select", "PADBACK", "View / Select / Share-or-touchpad"),
	step("home", "PADSYSTEM", "Home / Guide (optional)", nil, true),
	step("share", "PADSOCIAL", "Share / Create / Capture (optional)", nil, true),
	step("p1", "PADPADDLE1", "Back button 1 (optional)", nil, true),
	step("p2", "PADPADDLE2", "Back button 2 (optional)", nil, true),
	step("p3", "PADPADDLE3", "Back button 3 (optional)", nil, true),
	step("p4", "PADPADDLE4", "Back button 4 (optional)", nil, true),
	step("lstickX", "LStickX", "Push the left stick right", "stick"),
	step("lstickY", "LStickY", "Push the left stick down", "stick"),
	step("rstickX", "RStickX", "Push the right stick right", "stick"),
	step("rstickY", "RStickY", "Push the right stick down", "stick"),
}
-- The game maps sticks up and right to +1: a right push keeps its raw sign, a down push is flipped.
Layout.STICK_DOWN = { LStickY = true, RStickY = true }
Layout.TRIGGER_BUTTON = { LTrigger = "PADLTRIGGER", RTrigger = "PADRTRIGGER" }

-- Stick deadzones and stick configs from the "All Devices" entry of WTF/GamePadConfig_Default.json.
local STICK_DEADZONE = 0.05
local STICKS = {
	{ stick = "Left", axisX = "LStickX", axisY = "LStickY", deadzone = 0.25 },
	{ stick = "Right", axisX = "RStickX", axisY = "RStickY", deadzone = 0.25 },
	{ stick = "Movement", axisX = "LStickX", axisY = "LStickY", deadzoneX = 0.05, deadzoneY = 0.05, deadzone = 0.25 },
	{ stick = "Camera", axisX = "RStickX", axisY = "RStickY", deadzoneX = 0.05, deadzoneY = 0.2, deadzone = 0.25 },
}
-- The game turns a raw axis into buttons only through a logical axis, so an axis D-pad borrows the touchpad and gyro
-- axes, which a generic pad doesn't have.
local HAT_AXES = { "PStickX", "PStickY", "GStickX", "GStickY" }

-- The full controller config a detection describes (no ID, name or tag yet).
function Layout.DetectedConfig(detect)
	local buttons, rawAxes, axisConfigs, sticks = {}, {}, {}, {}
	local hatAxis, hatCount = {}, 0
	local detectButtons, detectAxes, detectHats = detect.buttons or {}, detect.axes or {}, detect.hats or {}
	for _, s in ipairs(Layout.DETECT_STEPS) do
		local target = s.target
		local buttonKey = Layout.TRIGGER_BUTTON[target] or target
		local axis, hat = detectAxes[target], detectHats[target]
		if detectButtons[buttonKey] then buttons[#buttons + 1] = { rawIndex = detectButtons[buttonKey], button = buttonKey } end
		if axis then
			rawAxes[#rawAxes + 1] = { rawIndex = axis.raw, axis = target }
			local trigger = Layout.TRIGGER_BUTTON[target]
			-- Written in full, as the game's own device configs do, so nothing falls back to an unknown default.
			local entry = { axis = target, shift = axis.shift or 0, scale = axis.scale or 1, deadzone = trigger and TRIGGER_DEADZONE or STICK_DEADZONE }
			if trigger then entry.buttonThreshold, entry.buttonPos = TRIGGER_THRESHOLD, trigger end
			axisConfigs[#axisConfigs + 1] = entry
		end
		if hat then
			local entry = hatAxis[hat.raw]
			if not entry then
				hatCount = hatCount + 1
				entry = { axis = HAT_AXES[hatCount], buttonThreshold = TRIGGER_THRESHOLD }
				hatAxis[hat.raw] = entry
				rawAxes[#rawAxes + 1] = { rawIndex = hat.raw, axis = entry.axis }
				axisConfigs[#axisConfigs + 1] = entry
			end
			entry[hat.value < 0 and "buttonNeg" or "buttonPos"] = target
		end
	end
	for _, stick in ipairs(STICKS) do
		if detectAxes[stick.axisX] and detectAxes[stick.axisY] then sticks[#sticks + 1] = Layout.Copy(stick) end
	end
	return { rawButtonMappings = buttons, rawAxisMappings = rawAxes, axisConfigs = axisConfigs, stickConfigs = sticks }
end

-- The role remap's raw sources after a detection: shoulders, paddles and digital triggers by raw button, analog
-- triggers by their logical axis.
function Layout.RawFromDetect(detect)
	local raw, buttons, axes = {}, detect.buttons or {}, detect.axes or {}
	for phys, key in pairs(Layout.NATIVE_KEY) do
		if buttons[key] then raw[phys] = { button = buttons[key] } end
	end
	if axes.LTrigger then raw.L2 = { axis = "LTrigger" } end
	if axes.RTrigger then raw.R2 = { axis = "RTrigger" } end
	return raw
end

-- The GamePadConfig for device ({ vendorID, productID, name, raw, detect }), or nil when nothing differs from native.
-- Without a detection only outputs change: rawAxisMappings and stickConfigs stay empty, so the analog trigger axes
-- keep their sources. With one, the full detected mapping comes first and the role remap is laid over it.
function Layout.BuildConfig(device, roles, swap)
	local outputs, buttons, axes = Layout.Outputs(device.raw, roles, swap), {}, {}
	for _, phys in ipairs(Layout.PHYSICAL) do
		local source, key = device.raw[phys], outputs[phys]
		local comment = TAG .. ": physical " .. phys
		if key ~= Layout.NATIVE_KEY[phys] and source.button then buttons[#buttons + 1] = { rawIndex = source.button, button = key, comment = comment } end
		if key ~= Layout.NATIVE_KEY[phys] and source.axis then
			axes[#axes + 1] = { axis = source.axis, deadzone = TRIGGER_DEADZONE, buttonThreshold = TRIGGER_THRESHOLD, buttonPos = key, comment = comment }
		end
	end
	-- Nothing is written from a guessed raw order: an unconfirmed pad must be learned or detected first.
	local detect = device.detect
	if not (device.confirmed or detect) then return nil end
	if #buttons + #axes == 0 and not detect then return nil end

	local config = {
		name = device.name or TAG,
		comment = TAG,
		configID = { vendorID = device.vendorID, productID = device.productID },
		rawButtonMappings = buttons,
		rawAxisMappings = {},
		axisConfigs = axes,
		stickConfigs = {},
	}
	-- A picked family's labels go with our config; while native is applied the game shows its own.
	if not detect then
		config.labelStyle = device.familyPicked and device.labelStyle or nil
		return config
	end

	local merged = Layout.Merge(Layout.DetectedConfig(detect), config)
	merged.labelStyle = detect.labelStyle
	return merged
end

-- " (was: X)" after a tagged comment records what a foreign base had there, so Unmerge can give it back.
local function was(comment, value) return comment .. " (was: " .. tostring(value or "") .. ")" end

-- Lays our config over a base: a foreign one (another addon's, foreign = true) or a detected one. Our raw buttons
-- replace the base's entries for the same raw index; our axis entries change only buttonPos on the base's entry for
-- the same axis, so its scale, shift and deadzone stay. Everything else in the base stays.
function Layout.Merge(base, ours, foreign)
	if not base then return ours end

	local merged, takenButton, ourAxis, replaced = Layout.Copy(base), {}, {}, {}
	for _, list in ipairs(LISTS) do merged[list] = merged[list] or {} end
	for _, mapping in ipairs(ours.rawButtonMappings) do takenButton[mapping.rawIndex] = true end
	for _, axisConfig in ipairs(ours.axisConfigs) do ourAxis[axisConfig.axis] = axisConfig end

	local buttons, axes = {}, {}
	for _, mapping in ipairs(merged.rawButtonMappings) do
		if takenButton[mapping.rawIndex] then replaced[mapping.rawIndex] = mapping.button else buttons[#buttons + 1] = mapping end
	end
	for _, axisConfig in ipairs(merged.axisConfigs) do
		local own = ourAxis[axisConfig.axis]
		if own then
			local comment = foreign and was(own.comment, axisConfig.buttonPos) or own.comment
			axisConfig.buttonPos, axisConfig.comment = own.buttonPos, comment
			axisConfig.buttonThreshold = axisConfig.buttonThreshold or own.buttonThreshold
			axisConfig.deadzone = axisConfig.deadzone or own.deadzone
			ourAxis[axisConfig.axis] = nil
		end
		axes[#axes + 1] = axisConfig
	end
	for _, mapping in ipairs(ours.rawButtonMappings) do
		local copy = Layout.Copy(mapping)
		if foreign and replaced[copy.rawIndex] then copy.comment = was(copy.comment, replaced[copy.rawIndex]) end
		buttons[#buttons + 1] = copy
	end
	for _, axisConfig in ipairs(ours.axisConfigs) do
		if ourAxis[axisConfig.axis] then axes[#axes + 1] = Layout.Copy(axisConfig) end
	end

	merged.rawButtonMappings, merged.axisConfigs = buttons, axes
	merged.configID = Layout.Copy(ours.configID)
	merged.name = merged.name or ours.name
	merged.comment = foreign and was(TAG, base.comment) or TAG
	return merged
end

-- nil: not the addon's; false: the addon's with nothing before it; a string: what a foreign base had ("" = nothing).
local function ownedBy(comment)
	if not tagged(comment) then return nil end
	return comment:match(" %(was: (.-)%)$") or false
end

-- A config merged over a foreign one, with the addon's part taken out again: the other addon's config, minus the
-- comments the addon replaced. nil when it isn't the addon's or has no foreign base.
function Layout.Unmerge(config)
	local base = ownedBy(config and config.comment)
	if not base then return nil end

	local out, buttons, axes = Layout.Copy(config), {}, {}
	out.comment = base ~= "" and base or nil
	for _, mapping in ipairs(out.rawButtonMappings or {}) do
		local prev = ownedBy(mapping.comment)
		if prev == nil then buttons[#buttons + 1] = mapping end
		if prev and prev ~= "" then buttons[#buttons + 1] = { rawIndex = mapping.rawIndex, button = prev } end
	end
	for _, axisConfig in ipairs(out.axisConfigs or {}) do
		local prev = ownedBy(axisConfig.comment)
		if prev then axisConfig.buttonPos, axisConfig.comment = prev ~= "" and prev or nil, nil end
		if prev ~= false then axes[#axes + 1] = axisConfig end
	end
	out.rawButtonMappings, out.axisConfigs = buttons, axes
	return out
end

-- Which physical button now outputs key: its native key and name. Keys the addon never moves come back as they are;
-- a moved-away key with no source (a paddle that took a role) gives nil.
function Layout.SourceOf(key, outputs)
	for _, phys in ipairs(Layout.PHYSICAL) do
		if outputs[phys] == key then return Layout.NATIVE_KEY[phys], phys end
	end
	if not IS_NATIVE_KEY[key] then return key end
end

function Layout.EffectiveFace(face)
	if face and next(face) then return Layout.Copy(face) end
	return Layout.Copy(Layout.NATIVE_FACE)
end

-- Same swap rule as roles: the position that held action takes pos's old action.
function Layout.AssignFace(face, pos, action)
	if not Layout.FACE_KEY[pos] then return nil, "unknown position " .. tostring(pos) end

	local out, holder = Layout.EffectiveFace(face), nil
	for other, held in pairs(out) do
		if held == action then holder = other end
	end
	if not holder then return nil, "unknown action " .. tostring(action) end

	out[holder], out[pos] = out[pos], action
	if sameMap(out, Layout.NATIVE_FACE) then return {} end
	return out
end

function Layout.PresetName(roles)
	if not (roles and next(roles)) then return "native" end
	if sameMap(roles, Layout.PRESETS.split) then return "split" end
	return "custom"
end

-- Runtime helpers for the current device (ns.Device), used by the commands and the settings screen.

local function current()
	local device = ns.Device and ns.Device.Current()
	return device and ns.db.devices[device.key], device
end

local function swapTargets() return ns.Device and ns.Device.SwapTargets() end

local function changed()
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
	return true
end

function Layout.Roles()
	local entry = current()
	return Layout.Effective(entry and entry.roles, swapTargets())
end

function Layout.Face()
	local entry = current()
	return Layout.EffectiveFace(entry and entry.face)
end

function Layout.PhysicalFor(key) return Layout.SourceOf(key, ns.Remap and ns.Remap.Outputs() or Layout.NATIVE_KEY) end

function Layout.SetRole(phys, role)
	local entry, device = current()
	if not entry then return nil, "no controller found" end
	if not Layout.NATIVE_KEY[phys] then return nil, "unknown button " .. tostring(phys) .. " (L1 R1 L2 R2 P1-P4)" end
	if role ~= "none" and not device.raw[phys] then return nil, phys .. " has no raw input on this controller; /fct learn " .. phys .. " first" end

	local roles, err = Layout.AssignRole(entry.roles, phys, role, swapTargets())
	if not roles then return nil, err end
	entry.roles = roles
	return changed()
end

function Layout.SetPreset(name)
	local entry = current()
	if not entry then return nil, "no controller found" end
	if not Layout.PRESETS[name] then return nil, "unknown preset " .. tostring(name) .. " (native, split)" end

	entry.roles = Layout.Copy(Layout.PRESETS[name])
	return changed()
end

function Layout.SetFace(pos, action)
	local entry = current()
	if not entry then return nil, "no controller found" end

	local face, err = Layout.AssignFace(entry.face, pos, action)
	if not face then return nil, err end
	entry.face = face
	return changed()
end

function Layout.Reset()
	local entry = current()
	if not entry then return nil, "no controller found" end

	entry.roles, entry.face = {}, {}
	return changed()
end
