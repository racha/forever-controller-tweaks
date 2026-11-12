-- Forever Controller Tweaks device: finds the controller's raw state, keeps one db entry per vendor/product, runs the learn
-- flow that records which raw button or axis a physical button drives, and the full controller detection.
local _, ns = ...
local Device = {}
ns.Device = Device

local LEARN_POLL, LEARN_HOLD, LEARN_TIMEOUT = 0.05, 0.5, 10
local WATCH_POLL = 0.25
local rawID, current, learning, detection

-- Raw tables may start at 0 or 1 (the DualSense's are 1-based). Returns them keyed 0-based, and the entry count.
local function zeroBased(list)
	local out = {}
	if type(list) ~= "table" then return out, 0 end

	local base = list[0] ~= nil and 0 or 1
	local i = base
	while list[i] ~= nil do
		out[i - base] = list[i]
		i = i + 1
	end
	return out, i - base
end

local function rawState(id)
	local ok, raw = pcall(C_GamePad.GetDeviceRawState, id)
	if ok and type(raw) == "table" and type(raw.rawButtons) == "table" then return raw end
end

local function listed() return C_GamePad.GetAllDeviceIDs and C_GamePad.GetAllDeviceIDs() or {} end

-- The active device wins when it has a raw state. It is often the combined device, which has none; then the device
-- chosen before stays (the watch below moves it to the one that sends input), else combined, else the first listed.
function Device.Raw()
	local active = C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
	local raw = active ~= nil and rawState(active)
	if raw then
		rawID = active
		return active, raw
	end
	raw = rawID and rawState(rawID)
	if raw then return rawID, raw end

	rawID = nil
	local candidates = {}
	local function add(id) if id ~= nil then candidates[#candidates + 1] = id end end
	add(C_GamePad.GetCombinedDeviceID and C_GamePad.GetCombinedDeviceID())
	for _, id in ipairs(listed()) do add(id) end

	for _, id in ipairs(candidates) do
		raw = rawState(id)
		if raw then
			rawID = id
			ns.debug("raw device %s: %s", tostring(id), tostring(raw.name))
			return id, raw
		end
	end
end

-- 0 or 1: where the current pad's raw tables start, for /fct selftest.
function Device.RawBase()
	local _, raw = Device.Raw()
	if raw then return raw.rawButtons[0] ~= nil and 0 or 1 end
end

local function hasPaddles(raw) return not not (raw.P1 or raw.P2 or raw.P3 or raw.P4) end

-- The game's label set for the device (Letters, Shapes, Reverse, Generic), from its own or the active mapped state.
local function labelStyle(id)
	for _, which in ipairs({ id, C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID() }) do
		local ok, state = pcall(C_GamePad.GetDeviceMappedState, which)
		local style = ok and type(state) == "table" and state.labelStyle
		if type(style) == "string" and not (issecretvalue and issecretvalue(style)) then return style end
	end
end

local function entryFor(key, raw, defaults)
	local entry = ns.db.devices[key]
	if entry then return entry end

	entry = { raw = defaults.raw, roles = {}, face = {} }
	ns.db.devices[key] = entry
	local setup = defaults.known and "/fct learn L1 confirms its buttons" or "unknown vendor: /fct family playstation|xbox|switch or /fct detect sets it up"
	ns.log(string.format("new controller %s (%s, %s); %s", tostring(raw.name), key, defaults.family, setup))
	return entry
end

function Device.Current() return current end

-- A pad the addon can't trust yet: unknown vendor, nothing learned, no detection. Remap writes nothing for it.
function Device.NeedsSetup() return not not (current and not current.confirmed) end

-- A trigger counts as held from a quarter pull, well under the game's 0.5 button threshold, so a press near the
-- threshold can't straddle a config switch either.
local TRIGGER_HELD = 0.25

-- The first input down on the pad (raw button, trigger, detected axis D-pad), else nil. Remap doesn't switch configs
-- while one is held: its release would come under the other mapping and the game would never see it.
function Device.Held()
	local _, raw = Device.Raw()
	if not raw then return nil end

	local buttons, buttonCount = zeroBased(raw.rawButtons)
	local axes = zeroBased(raw.rawAxes)
	for i = 0, buttonCount - 1 do
		if buttons[i] then return "raw button " .. i end
	end
	-- Without a detection the triggers are SDL raw axes 4/5 in 0..1; a detected one is scaled as its config does.
	local detect = current and current.detect
	for index, name in pairs(ns.Layout.TRIGGER_AXES) do
		local axis = detect and (detect.axes or {})[name] or (not detect and { raw = index })
		local value = axis and axes[axis.raw]
		if type(value) == "number" and (value + (axis.shift or 0)) * (axis.scale or 1) > TRIGGER_HELD then return name end
	end
	for target, hat in pairs(detect and detect.hats or {}) do
		local value = axes[hat.raw]
		if type(value) == "number" and value * hat.value > 0.5 then return target end
	end
end

function Device.SwapTargets() return not not (GetCVarBool and GetCVarBool("GamepadSwapTargetModifiers")) end

-- Re-resolves the controller; fires FCT_LAYOUT_CHANGED("device") when it changed, or always with force. Each
-- vendor/product keeps its own db entry, so a Steam virtual pad and a physical one have separate layouts. A detected
-- pad uses the label style the player chose.
function Device.Refresh(force)
	if not ns.db then return nil end

	local id, raw = Device.Raw()
	local key = raw and raw.vendorID and ns.Layout.Key(raw.vendorID, raw.productID)
	local known = key and ns.db.devices[key]
	local style = key and (known and (known.detect and known.detect.labelStyle or ns.Layout.FAMILY_STYLE[known.family]) or labelStyle(id))
	local defaults = key and ns.Layout.DeviceDefaults(raw.vendorID, raw.productID, style)
	local family = defaults and defaults.family
	if not force and current and current.key == key and current.deviceID == id and current.family == family then return current end
	if not (current or key) then return nil end

	current = nil
	if key then
		local entry = entryFor(key, raw, defaults)
		ns.debug("device %s: name=%s vendor=%04x product=%04x labelStyle=%s family=%s", tostring(id), tostring(raw.name), raw.vendorID, raw.productID or 0, tostring(style), family)
		current = {
			key = key,
			deviceID = id,
			name = raw.name,
			raw = entry.raw,
			detect = entry.detect,
			family = family,
			labelStyle = style,
			vendorID = raw.vendorID,
			productID = raw.productID,
			motionAxes = defaults.motionAxes,
			hasPaddles = hasPaddles(entry.raw),
			familyPicked = entry.familyPicked == true,
			confirmed = defaults.confirmed or entry.confirmed or entry.detect ~= nil or entry.familyPicked == true,
		}
	end
	if not key then ns.debug("device: none") end
	ns.Fire("FCT_LAYOUT_CHANGED", "device")
	return current
end

local function stopLearn(msg)
	if learning and learning.ticker then learning.ticker:Cancel() end
	learning = nil
	ns.log(msg)
end

-- The logical trigger axis a raw axis feeds: from the detection when there is one, else the SDL order (raw 4/5).
local function triggerAxis(index)
	local detect = current.detect
	if not detect then return ns.Layout.TRIGGER_AXES[index] end

	for name in pairs(ns.Layout.TRIGGER_BUTTON) do
		local axis = detect.axes and detect.axes[name]
		if axis and axis.raw == index then return name end
	end
end

local function sourceOf(found)
	if found.button then return { button = found.button } end
	local axis = triggerAxis(found.axisIndex)
	return axis and { axis = axis }
end

-- The other physical button that already uses source, if any (the detection's duplicate rule).
local function usedBy(phys, source)
	for other, used in pairs(current.raw) do
		if other ~= phys and used.button == source.button and used.axis == source.axis then return other end
	end
end

local function finishLearn(phys, source)
	local raw, entry = current.raw, ns.db.devices[current.key]
	raw[phys] = source
	entry.confirmed, current.confirmed = true, true
	current.hasPaddles = hasPaddles(raw)
	stopLearn(string.format("%s learned: raw %s", phys, source.button and ("button " .. source.button) or ("axis " .. source.axis)))
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
end

-- Learn rule: a newly pressed raw button wins, else the single button already held at the start;
-- an axis counts only when no button changed and it moved more than 0.8 from where it rested (a detected trigger can
-- rest at -1); motion axes are ignored.
local function learnTick()
	local job, now = learning, GetTime()
	local _, raw = Device.Raw()
	if not (raw and current) then return stopLearn("no controller with a raw state; nothing learned") end
	if now - job.started > LEARN_TIMEOUT then return stopLearn("nothing detected; " .. job.phys .. " keeps its raw input") end

	local buttons, buttonCount = zeroBased(raw.rawButtons)
	local axes, axisCount = zeroBased(raw.rawAxes)
	if not job.base then
		local down = {}
		for i = 0, buttonCount - 1 do
			if buttons[i] then down[#down + 1] = i end
		end
		if #down > 1 then
			if not job.told then ns.log("let go of every button except " .. job.phys) end
			job.told = true
			return
		end
		job.base, job.startHeld = { buttons = buttons, axes = axes }, down[1]
		return
	end

	local found
	for i = 0, buttonCount - 1 do
		if buttons[i] and not job.base.buttons[i] then found = found or { button = i } end
	end
	if not found and job.startHeld and buttons[job.startHeld] then found = { button = job.startHeld } end
	if not found then
		local motion = current.motionAxes
		for i = 0, axisCount - 1 do
			local from, value = job.base.axes[i] or 0, axes[i] or 0
			if not motion[i] and math.abs(value - from) > 0.8 then found = found or { axisIndex = i } end
		end
	end

	local text = found and (found.button and ("b" .. found.button) or ("a" .. found.axisIndex))
	if text ~= job.found then job.found, job.holdStart = text, now end
	if not found or now - job.holdStart < LEARN_HOLD or text == job.rejected then return end

	-- Rejected inputs are told once and ignored; learning goes on until another input is held or it times out.
	local source = sourceOf(found)
	local other = source and usedBy(job.phys, source)
	if source and not other then return finishLearn(job.phys, source) end
	job.rejected = text
	if other then return ns.log(string.format("that input already drives %s; hold another one for %s (/fct learn cancel)", other, job.phys)) end
	ns.log(string.format("raw axis %d is not a trigger axis the game can remap; hold another input for %s", found.axisIndex, job.phys))
end

function Device.Learn(phys)
	if not ns.Layout.NATIVE_KEY[phys] then return ns.log("learn: unknown button " .. tostring(phys) .. " (L1 R1 L2 R2 P1-P4)") end
	if not ns.Active() then return ns.log("learn: Gamepad UI off — Controller Tweaks is inactive") end

	-- Starts once the chat box closes, so the Enter that sent the command isn't read as a press.
	ns.whenPadFree("learn", function()
		if not ns.Active() then return ns.log("learn: Gamepad UI off — Controller Tweaks is inactive") end
		if not Device.Refresh() then return ns.log("learn: no controller found") end
		if learning then stopLearn("learn " .. learning.phys .. ": cancelled") end

		learning = { phys = phys, started = GetTime() }
		learning.ticker = C_Timer.NewTicker(LEARN_POLL, learnTick)
		ns.log("hold " .. phys .. " alone until Controller Tweaks confirms (" .. LEARN_TIMEOUT .. " s)")
	end, { combatOk = true, timeout = 15 })
end

function Device.LearnCancel()
	if not learning then return false end

	stopLearn("learn " .. learning.phys .. ": cancelled")
	return true
end

function Device.Learning() return learning and learning.phys end

function ns.commands.learn(args)
	local phys = (args[1] or ""):upper()
	if phys == "CANCEL" then return Device.LearnCancel() or ns.log("learn: not running") end
	Device.Learn(phys)
end

-- Controller detection ("press each button"): calibrate, then one step per control, each captured
-- when everything touched is released. Polls the raw state on its own OnUpdate, only while it runs.
local CALIBRATE_TIME = 1
-- An axis whose rest range is wider than this (gyro, touchpad, a stick being held) is ignored for the run.
local NOISE_LIMIT = 0.15
local REST_MARGIN = 0.2
local BUTTON_AXIS_MOVE, TRIGGER_PULL, STICK_MOVE = 0.5, 0.8, 0.5
local STYLES = { letters = "Letters", shapes = "Shapes", reverse = "Reverse", generic = "Generic" }
local detectFrame = CreateFrame("Frame")
detectFrame:Hide()

local function emit(kind, a, b)
	local onEvent = detection and detection.onEvent
	if onEvent then onEvent(kind, a, b) end
end

local function newAccumulator() return { order = {}, down = {}, peak = {} } end

local function enterStep(index)
	detection.phase, detection.index, detection.acc = "step", index, newAccumulator()
	emit("step", ns.Layout.DETECT_STEPS[index])
end

-- Ends the run; the panel stand-down we took (face router off, as with the settings screen open) is given back.
local function stopDetection()
	local run = detection
	detectFrame:Hide()
	detection = nil
	if run and run.ownsPanel then ns.SetPanelOpen(false) end
	return run
end

local function cancelDetection(reason)
	local run = stopDetection()
	if not run then return false end

	if run.onEvent then run.onEvent("cancelled", reason) end
	return true
end

local function calibrate(buttons, buttonCount, axes, axisCount)
	local run = detection
	for i = 0, axisCount - 1 do
		local value = axes[i] or 0
		local c = run.cal[i] or { min = value, max = value, sum = 0, n = 0 }
		c.min, c.max, c.sum, c.n = math.min(c.min, value), math.max(c.max, value), c.sum + value, c.n + 1
		run.cal[i] = c
	end
	if GetTime() - run.started < CALIBRATE_TIME then return end

	for i, c in pairs(run.cal) do
		c.rest = c.sum / c.n
		c.ignore = c.max - c.min > NOISE_LIMIT or run.device.motionAxes[i]
		c.margin = math.max(REST_MARGIN, (c.max - c.min) * 2)
	end
	-- A button still down after calibration is ignored until it is released.
	for i = 0, buttonCount - 1 do run.stuck[i] = buttons[i] or nil end
	enterStep(1)
end

local function bestAxis(acc, minimum)
	local best, peak
	for i, delta in pairs(acc.peak) do
		if math.abs(delta) > minimum and (not peak or math.abs(delta) > math.abs(peak)) then best, peak = i, delta end
	end
	return best, peak
end

-- The game wants sticks in -1..1 and triggers in 0..1, so an off-centre rest gets a shift and a scale.
local function stickInput(axis, rest, delta, down)
	local sign = (delta > 0 and 1 or -1) * (down and -1 or 1)
	if math.abs(rest) < 0.25 then return { axis = axis, scale = sign } end
	return { axis = axis, shift = -rest, scale = sign / (1 - math.abs(rest)) }
end

local function triggerInput(axis, rest, delta)
	if rest < -0.5 then return { axis = axis, shift = 1, scale = 0.5 } end
	if rest > 0.5 then return { axis = axis, shift = -1, scale = -0.5 } end
	return { axis = axis, scale = delta < 0 and -1 or nil }
end

local function choose(step, acc)
	local run, button = detection, acc.order[1]
	if step.kind == "stick" then
		local axis, delta = bestAxis(acc, STICK_MOVE)
		return axis and stickInput(axis, run.cal[axis].rest, delta, ns.Layout.STICK_DOWN[step.target])
	end
	if step.kind == "trigger" then
		local axis, delta = bestAxis(acc, TRIGGER_PULL)
		if axis then return triggerInput(axis, run.cal[axis].rest, delta) end
		return button and { button = button }
	end
	if button then return { button = button } end

	local axis, delta = bestAxis(acc, BUTTON_AXIS_MOVE)
	return axis and { axis = axis, value = delta > 0 and 1 or -1 }
end

-- A raw button, a whole axis, or one direction of a hat axis can serve one step per run.
local function usedBy(input)
	for _, capture in pairs(detection.captures) do
		local other = capture.input
		if input.button and other.button == input.button then return capture.step.id end
		if input.axis and other.axis == input.axis and not (input.value and other.value and input.value ~= other.value) then return capture.step.id end
	end
end

local function detected()
	local detect = { version = 1, buttons = {}, axes = {}, hats = {} }
	for _, capture in pairs(detection.captures) do
		local target, input = capture.step.target, capture.input
		if input.button then
			detect.buttons[ns.Layout.TRIGGER_BUTTON[target] or target] = input.button
		elseif input.value then
			detect.hats[target] = { raw = input.axis, value = input.value }
		else
			detect.axes[target] = { raw = input.axis, shift = input.shift, scale = input.scale }
		end
	end
	return detect
end

local function advance()
	local steps = ns.Layout.DETECT_STEPS
	if detection.index < #steps then return enterStep(detection.index + 1) end

	detection.phase = "done"
	detectFrame:Hide()
	emit("done", detected())
end

local function capture(step, input)
	local used = usedBy(input)
	if used then return emit("rejected", step, "already used for " .. used, used) end

	detection.captures[detection.index] = { step = step, input = input }
	emit("captured", step, input)
	if detection then advance() end
end

local function stepFrame(buttons, buttonCount, axes)
	local run = detection
	local acc, moving = run.acc, false
	for i = 0, buttonCount - 1 do
		if run.stuck[i] and not buttons[i] then run.stuck[i] = nil end
		if buttons[i] and not run.stuck[i] then
			moving = true
			if not acc.down[i] then acc.down[i], acc.order[#acc.order + 1] = true, i end
		end
	end
	for i, c in pairs(run.cal) do
		local delta = not c.ignore and (axes[i] or c.rest) - c.rest
		if delta and math.abs(delta) > c.margin then moving = true end
		if delta and math.abs(delta) > math.abs(acc.peak[i] or 0) then acc.peak[i] = delta end
	end
	if moving then acc.touched = true end
	if moving or not acc.touched then return end

	local step = ns.Layout.DETECT_STEPS[run.index]
	local input = choose(step, acc)
	run.acc = newAccumulator()
	if input then capture(step, input) end
end

detectFrame:SetScript("OnUpdate", function()
	local raw = detection and rawState(detection.deviceID)
	if not raw then return cancelDetection("the controller went away") end

	local buttons, buttonCount = zeroBased(raw.rawButtons)
	local axes, axisCount = zeroBased(raw.rawAxes)
	if detection.phase == "calibrating" then return calibrate(buttons, buttonCount, axes, axisCount) end
	stepFrame(buttons, buttonCount, axes)
end)

function Device.DetectSteps() return ns.Layout.Copy(ns.Layout.DETECT_STEPS) end

function Device.Detecting() return detection ~= nil end

-- onEvent(kind, ...): "calibrating"; "step", step; "captured", step, input; "rejected", step, reason; "done", result
-- (the detect table without labelStyle); "cancelled", reason. Returns true, or false and a reason.
function Device.DetectStart(onEvent)
	if InCombatLockdown() then return false, "not in combat" end
	if not ns.Active() then return false, "Gamepad UI off — Controller Tweaks is inactive" end

	local device = Device.Refresh()
	if not device then return false, "no controller found" end
	if detection then cancelDetection("restarted") end
	if learning then stopLearn("learn " .. learning.phys .. ": cancelled") end

	detection = { device = device, deviceID = device.deviceID, onEvent = onEvent, phase = "calibrating", started = GetTime(), cal = {}, stuck = {}, captures = {}, index = 0 }
	if not ns.panelOpen then
		detection.ownsPanel = true
		ns.SetPanelOpen(true)
	end
	detectFrame:Show()
	emit("calibrating")
	return true
end

function Device.DetectSkip()
	local run = detection
	if not (run and run.phase == "step") then return false end

	local step = ns.Layout.DETECT_STEPS[run.index]
	if not step.optional then
		emit("rejected", step, "this control is needed; press it, or go back or cancel")
		return false
	end
	run.captures[run.index] = nil
	advance()
	return true
end

function Device.DetectBack()
	local run = detection
	if not run or run.phase == "calibrating" or (run.phase == "step" and run.index == 1) then return false end

	local index = run.phase == "done" and run.index or run.index - 1
	run.captures[index] = nil
	detectFrame:Show()
	enterStep(index)
	return true
end

function Device.DetectCancel() return cancelDetection() end

-- Stores the finished detection with the player's glyph style and re-resolves the device.
function Device.DetectFinish(style)
	local run = detection
	if not (run and run.phase == "done") then return false, "detection isn't done" end
	if not ns.Layout.LABEL_FAMILY[style] then return false, "unknown label style " .. tostring(style) end

	local detect = detected()
	detect.labelStyle = style
	local entry = ns.db.devices[run.device.key]
	entry.detect, entry.raw = detect, ns.Layout.RawFromDetect(detect)
	entry.family, entry.familyPicked = nil, nil
	stopDetection()
	Device.Refresh(true)
	return true
end

-- Forgets a detection; the game's default mapping comes back, and the raw sources go back to the family defaults.
function Device.DetectReset(deviceKey)
	local key = deviceKey or (current and current.key)
	local entry = key and ns.db.devices[key]
	if not (entry and entry.detect) then return false end

	local defaults = ns.Layout.DeviceDefaults(tonumber(key:sub(1, 4), 16), tonumber(key:sub(6, 9), 16))
	entry.detect, entry.raw = nil, defaults.raw
	if current and current.key == key then Device.Refresh(true) end
	return true
end

local function deviceEntry(deviceKey)
	local key = deviceKey or (current and current.key)
	return key, key and ns.db.devices[key]
end

local function refreshIf(key)
	if current and current.key == key then Device.Refresh(true) end
	return true
end

-- Most third-party pads follow one of the big three layouts, and SDL reports those in the same raw order as the known
-- pads, so a pick trusts that order (the SDL defaults) and takes the family's labels. It replaces a detection and
-- learned buttons; a later detection replaces the pick. "custom" isn't a template: it returns false for the wizard.
function Device.SetFamily(deviceKey, family)
	local key, entry = deviceEntry(deviceKey)
	if not entry then return false, "no such controller" end
	if family == "custom" then return false, "custom: the detect wizard sets it up" end
	if not ns.Layout.FAMILY_STYLE[family] then return false, "unknown family " .. tostring(family) end
	local vendor = ns.Layout.FAMILIES[key:sub(1, 4)]
	if vendor and vendor.certain then return false, "this controller's family is known (" .. vendor.family .. ")" end

	entry.family, entry.familyPicked = family, true
	entry.detect, entry.raw, entry.confirmed = nil, ns.Layout.DefaultsForKey(key).raw, nil
	return refreshIf(key)
end

-- What the pad itself says about its family, for the panel to preselect; nil when it says nothing reliable. Steam's
-- virtual gamepad (28de/11ff) emulates an Xbox 360 pad, which SDL reports in the standard order the Xbox template uses.
local SUGGESTED = { ["28de/11ff"] = "xbox" }

function Device.SuggestedFamily(deviceKey)
	local key = deviceKey or (current and current.key)
	return key and SUGGESTED[key:lower()] or nil
end

-- Back to unrecognised: the pick, a detection and learned buttons are forgotten (a known vendor stays recognised).
function Device.ResetFamily(deviceKey)
	local key, entry = deviceEntry(deviceKey)
	if not entry then return false end

	entry.family, entry.familyPicked, entry.confirmed = nil, nil, nil
	entry.detect, entry.raw = nil, ns.Layout.DefaultsForKey(key).raw
	return refreshIf(key)
end

function ns.commands.family(args)
	local name = (args[1] or ""):lower()
	if name == "reset" then return ns.log(Device.ResetFamily() and "family: reset, the controller is unrecognised again" or "family: no controller") end
	local ok, err = Device.SetFamily(nil, name)
	if not ok then return ns.log("family: " .. err .. (name == "custom" and " (/fct detect)" or "")) end
	ns.log("family: " .. name .. " layout and labels set; /fct detect redoes it if buttons are wrong")
end

local CHAT_EVENTS = {
	calibrating = function() ns.log("detect: keep the controller still for a second (/fct detect back | cancel)") end,
	step = function(step)
		local index = detection.index
		ns.log(string.format("detect %d/%d: %s%s", index, #ns.Layout.DETECT_STEPS, step.prompt, step.optional and " (/fct detect skip)" or ""))
	end,
	captured = function(step, input)
		local what = input.button and ("raw button " .. input.button) or string.format("raw axis %d%s", input.axis, input.value and (input.value < 0 and " -" or " +") or "")
		ns.log("  " .. step.id .. " = " .. what)
	end,
	rejected = function(step, reason) ns.log("  " .. step.id .. ": " .. reason) end,
	done = function() ns.log("detect: done. Pick the glyph style: /fct detect finish letters | shapes | reverse | generic") end,
	cancelled = function(reason) ns.log("detect: cancelled" .. (reason and (", " .. reason) or "")) end,
}

local function chatEvent(kind, a, b) CHAT_EVENTS[kind](a, b) end

function ns.commands.detect(args)
	local sub = (args[1] or ""):lower()
	if sub == "skip" then return Device.DetectSkip() end
	if sub == "back" then return Device.DetectBack() end
	if sub == "cancel" then return Device.DetectCancel() or ns.log("detect: not running") end
	if sub == "reset" then return ns.log(Device.DetectReset() and "detect: reset, the game default mapping is back" or "detect: nothing to reset") end
	if sub == "finish" then
		local ok, err = Device.DetectFinish(STYLES[(args[2] or ""):lower()] or args[2])
		return ns.log(ok and "detect: saved; Controller Tweaks now writes the detected mapping" or ("detect: " .. err))
	end

	local ok, err = Device.DetectStart(chatEvent)
	if not ok then ns.log("detect: " .. err) end
end

ns.On("FCT_ACTIVE_CHANGED", function(active)
	if active then return end
	if learning then stopLearn("learn " .. learning.phys .. ": cancelled, Gamepad UI off") end
	cancelDetection("Gamepad UI off")
end)

-- Our mapping must be applied for the fight (Remap.ApplyNow("combat") runs right after), so detection stops here.
ns.On("FCT_COMBAT_START", function() cancelDetection("combat") end)

local function pressed(raw)
	for _, down in pairs(raw.rawButtons) do
		if down then return true end
	end
end

-- With Steam running the game can see a virtual pad next to a physical one. The one whose buttons are pressed becomes
-- the device; while the current one has a button down too (Steam mirrors the physical pad), it stays.
-- The device list only changes with these events, so the watch doesn't ask for it every poll with one pad.
local multi

local function watch()
	if not multi or learning or detection or not ns.Active() then return end

	local ids, now = listed(), rawID and rawState(rawID)
	if now and pressed(now) then return end
	for _, id in ipairs(ids) do
		local raw = id ~= rawID and rawState(id)
		if raw and pressed(raw) then
			rawID = id
			return Device.Refresh()
		end
	end
end

local function refresh()
	multi = #listed() > 1
	Device.Refresh()
end
for _, event in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "GAME_PAD_ACTIVE_CHANGED" }) do ns.On(event, refresh) end
ns.On("PLAYER_LOGIN", function()
	refresh()
	C_Timer.NewTicker(WATCH_POLL, watch)
end)
