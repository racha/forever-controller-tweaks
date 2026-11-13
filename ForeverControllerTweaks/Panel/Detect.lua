-- Forever Controller Tweaks controller setup (detect wizard): teaches the game every control of an unknown pad, then writes a full config.
-- Screens: a keyboard confirm, calibrate, one per step, finish (glyph style), done. Until Save
-- the pad is being read raw, so the window takes no pad navigation, shows no footer and no chevron: mouse buttons
-- and Enter (main) / Space (skip) / Backspace (back) / Escape (cancel), every other key passes on. Driven by
-- ns.Device.DetectStart's events; Back/Skip/Cancel call DetectBack/DetectSkip/DetectCancel; Save calls
-- DetectFinish(style). The generic pad is the addon's own art: a body texture plus one fill and one line mask per
-- control, tinted by state.
local _, ns = ...
local UI = ns.UI
local L = UI.L

local D = {}
UI.Detect = D

local ART = "Interface\\AddOns\\ForeverControllerTweaks\\Art\\"
local W, H = 760, 470
local BUTTON_TOP = 404
local PULSE = 1.2

-- Control shapes on the generic drawing (viewBox 400x300): circle { cx, cy, r } or mask { x, y, w, h, art }.
local SHAPES = {
	FB = { circle = { 276, 164, 10 } }, FR = { circle = { 298, 142, 10 } }, FL = { circle = { 254, 142, 10 } }, FT = { circle = { 276, 120, 10 } },
	LS = { circle = { 162, 198, 15 } }, RS = { circle = { 238, 198, 15 } }, HOME = { circle = { 200, 130, 7 } }, SHARE = { circle = { 200, 104, 4.5 } },
	L1 = { mask = { 98, 62, 62, 12, "shoulder" } }, R1 = { mask = { 240, 62, 62, 12, "shoulder" } },
	SEL = { mask = { 168, 106, 18, 8, "pill" } }, START = { mask = { 214, 106, 18, 8, "pill" } },
	DU = { mask = { 117, 120, 14, 16, "dpadv" } }, DD = { mask = { 117, 148, 14, 16, "dpadv" } },
	DL = { mask = { 102, 135, 16, 14, "dpadh" } }, DR = { mask = { 130, 135, 16, 14, "dpadh" } },
	P1 = { mask = { 292, 262, 22, 10, "tab" } }, P2 = { mask = { 86, 262, 22, 10, "tab" } },
	P3 = { mask = { 318, 240, 20, 9, "tab" } }, P4 = { mask = { 62, 240, 20, 9, "tab" } },
	L2 = { mask = { 96, 28, 68, 32, "trigger" } }, R2 = { mask = { 236, 28, 68, 32, "trigger" } },
}
-- Detect step id -> the control drawn for it.
local CONTROL = {
	faceBottom = "FB", faceRight = "FR", faceLeft = "FL", faceTop = "FT",
	dpadUp = "DU", dpadDown = "DD", dpadLeft = "DL", dpadRight = "DR",
	lb = "L1", rb = "R1", lt = "L2", rt = "R2", l3 = "LS", r3 = "RS", start = "START", select = "SEL",
	home = "HOME", share = "SHARE", p1 = "P1", p2 = "P2", p3 = "P3", p4 = "P4",
	lstickX = "LS", lstickY = "LS", rstickX = "RS", rstickY = "RS",
}
-- Mask canvases (pixels) and their viewBox (shape + 2 units of padding a side), centred with "meet": the texcoords
-- crop to the viewBox so each mask scales uniformly.
local maskCoords = UI.MaskCoords

local function rgb(hex) return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end
local STATE = {
	idle = { fill = "2b241c", line = "8a6a3c" },
	done = { fill = "6e5130", line = "c9a464" },
	current = { fill = "ffd200", line = "fff2a8" },
	skipped = { fill = "1a1612", line = "5a4a35" },
}
local STYLES = { "Letters", "Shapes", "Reverse" }
-- Face glyphs per style (bottom, right, left, top), the atlases of the game's own sets.
local STYLE_FACES = {
	Letters = { "gamepad-xbox1-buttona-normal", "gamepad-xbox1-buttonb-normal", "gamepad-xbox1-buttonx-normal", "gamepad-xbox1-buttony-normal" },
	Shapes = { "gamepad-ps-buttoncrox-normal", "gamepad-ps-buttoncircle-normal", "gamepad-ps-buttonsquare-normal", "gamepad-ps-buttontriangle-normal" },
	Reverse = { "gamepad-switch-128x-face-b-normal", "gamepad-switch-128x-face-a-normal", "gamepad-switch-128x-face-y-normal", "gamepad-switch-128x-face-x-normal" },
}
D.STYLE_FACES = STYLE_FACES

local window, pad, strip, buttons, screens, opts, run
local steps = {}

local function at(region, x, y) UI.At(region, window, x, y) end

-- Pad drawing ----------------------------------------------------------------------------------------------------

local function newControl(parent, shape)
	local control = { shape = shape }
	control.fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	control.line = parent:CreateTexture(nil, "ARTWORK", nil, 2)
	if shape.circle then
		control.fill:SetTexture(ART .. "disc.tga")
		control.line:SetTexture(ART .. "ring.tga")
	else
		control.fill:SetTexture(ART .. "ctl-" .. shape.mask[5] .. "-fill.tga")
		control.line:SetTexture(ART .. "ctl-" .. shape.mask[5] .. "-line.tga")
		control.fill:SetTexCoord(maskCoords(shape.mask[5]))
		control.line:SetTexCoord(maskCoords(shape.mask[5]))
	end
	control.pulse = control.fill:CreateAnimationGroup()
	control.pulse:SetLooping("REPEAT")
	local fade = control.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(PULSE / 2)
	fade:SetOrder(1)
	local back = control.pulse:CreateAnimation("Alpha")
	back:SetFromAlpha(0.45)
	back:SetToAlpha(1)
	back:SetDuration(PULSE / 2)
	back:SetOrder(2)
	return control
end

local function placeControl(control, frame, s)
	local shape = control.shape
	for _, region in ipairs({ control.fill, control.line }) do region:ClearAllPoints() end
	if shape.circle then
		local cx, cy, r = unpack(shape.circle)
		control.fill:SetSize(2 * r * s, 2 * r * s)
		control.fill:SetPoint("CENTER", frame, "TOPLEFT", cx * s, -cy * s)
		-- ring.tga: radius 27 of a 64 box.
		control.line:SetSize(2 * r * s * 32 / 27, 2 * r * s * 32 / 27)
		control.line:SetPoint("CENTER", frame, "TOPLEFT", cx * s, -cy * s)
		return
	end
	local x, y, w, h = unpack(shape.mask)
	-- The masks carry 2 units of padding on each side.
	for _, region in ipairs({ control.fill, control.line }) do
		region:SetSize((w + 4) * s, (h + 4) * s)
		region:SetPoint("TOPLEFT", frame, "TOPLEFT", (x - 2) * s, -(y - 2) * s)
	end
end

local function styleControl(control, state, conflict)
	local colors = STATE[state] or STATE.idle
	control.fill:SetVertexColor(rgb(colors.fill))
	if conflict then control.line:SetVertexColor(RED_FONT_COLOR:GetRGB()) else control.line:SetVertexColor(rgb(colors.line)) end
	if state == "current" then
		if not control.pulse:IsPlaying() then control.pulse:Play() end
	else
		control.pulse:Stop()
		control.fill:SetAlpha(1)
	end
end

local function newPad(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.body = frame:CreateTexture(nil, "ARTWORK")
	frame.body:SetAllPoints()
	frame.body:SetTexture(ART .. "generic-controller.tga")
	frame.body:SetTexCoord(0, 2 / 3, 0, 1)
	frame.controls = {}
	for name, shape in pairs(SHAPES) do frame.controls[name] = newControl(frame, shape) end
	frame.check = frame:CreateTexture(nil, "OVERLAY")
	frame.check:SetAtlas("common-icon-checkmark")
	frame.check:SetSize(18, 18)
	frame.arrow = frame:CreateTexture(nil, "OVERLAY")
	frame.arrow:SetAtlas("common-icon-forwardarrow")
	frame.arrow:SetSize(24, 24)
	frame.faces = {}
	for i = 1, 4 do
		local face = frame:CreateTexture(nil, "OVERLAY")
		face:SetSize(22, 22)
		frame.faces[i] = face
	end
	return frame
end

local function placePad(x, y, s, alpha)
	pad:ClearAllPoints()
	at(pad, x, y)
	pad:SetSize(400 * s, 300 * s)
	pad:SetAlpha(alpha or 1)
	pad.scale = s
	for _, control in pairs(pad.controls) do placeControl(control, pad, s) end
end

local function centre(name)
	local shape, s = SHAPES[name], pad.scale
	if shape.circle then return shape.circle[1] * s, shape.circle[2] * s end
	local x, y, w, h = unpack(shape.mask)
	return (x + w / 2) * s, (y + h / 2) * s
end

-- States of every control from the run: done / skipped / current, the conflict outlined on a rejection.
local function drawControls()
	local states = {}
	for _, step in ipairs(steps) do
		local control = CONTROL[step.id]
		if run.done[step.id] then states[control] = states[control] == "current" and "current" or "done" end
		if run.skipped[step.id] and states[control] ~= "done" then states[control] = "skipped" end
	end
	local current = run.step and CONTROL[run.step.id]
	if current then states[current] = "current" end
	local conflict = run.conflict and CONTROL[run.conflict]
	for name, control in pairs(pad.controls) do styleControl(control, states[name], name == conflict) end

	pad.check:Hide()
	local last = run.lastCaptured and CONTROL[run.lastCaptured]
	if last and last ~= current then
		local x, y = centre(last)
		pad.check:ClearAllPoints()
		pad.check:SetPoint("CENTER", pad, "TOPLEFT", x, -y)
		pad.check:Show()
	end

	pad.arrow:Hide()
	if run.step and run.step.kind == "stick" then
		local x, y = centre(current)
		pad.arrow:ClearAllPoints()
		pad.arrow:SetPoint("CENTER", pad, "TOPLEFT", x + 22, -y)
		pad.arrow:SetRotation(ns.Layout.STICK_DOWN[run.step.target] and -math.pi / 2 or 0)
		pad.arrow:Show()
	end
end

local function showFaces(style)
	for i, face in ipairs(pad.faces) do
		face:SetShown(style ~= nil)
		if style then
			local x, y = centre(({ "FB", "FR", "FL", "FT" })[i])
			face:SetAtlas(STYLE_FACES[style][i])
			face:ClearAllPoints()
			face:SetPoint("CENTER", pad, "TOPLEFT", x, -y)
		end
	end
end

-- Buttons ----------------------------------------------------------------------------------------------------------

local function newButton()
	local button = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate")
	button:SetScript("OnEnter", nil)
	button:SetScript("OnLeave", nil)
	button.key = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	button.key:SetPoint("TOP", button, "BOTTOM", 0, -3)
	return button
end

-- specs: { { x, w, label, key, fn, main }, ... }
local function setButtons(specs)
	for _, button in ipairs(buttons) do button:Hide() end
	for i, spec in ipairs(specs) do
		local button = buttons[i] or newButton()
		buttons[i] = button
		button:ClearAllPoints()
		at(button, spec[1], BUTTON_TOP)
		button:SetSize(spec[2], 28)
		button:SetText(spec[3])
		button:SetNormalFontObject(spec[6] and "GameFontHighlight" or "GameFontNormal")
		button.key:SetText(spec[4])
		button:SetScript("OnClick", spec[5])
		button:Show()
	end
end

-- Steps strip -------------------------------------------------------------------------------------------------------

local function newStrip()
	local inset = UI.Inset(window, 424, 96, 312, 280)
	UI.Text(inset, "GameFontNormal", 12, 9, L.DETECT_STEPS)
	inset.count = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	inset.count:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -9)
	inset.rows = {}
	for i = 1, 26 do
		local row = CreateFrame("Frame", nil, inset)
		row:SetSize(140, 18)
		UI.At(row, inset, i <= 13 and 12 or 164, 30 + ((i - 1) % 13) * 19)
		row.wash = row:CreateTexture(nil, "BACKGROUND")
		row.wash:SetColorTexture(1, 1, 1, 0.1)
		row.wash:SetAllPoints()
		row.check = row:CreateTexture(nil, "ARTWORK")
		row.check:SetAtlas("common-icon-checkmark")
		row.check:SetSize(12, 12)
		row.check:SetPoint("TOPLEFT", 0, -3)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.text:SetPoint("TOPLEFT", 16, -3)
		row.text:SetWidth(124)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		inset.rows[i] = row
	end
	return inset
end

local function label(step) return L.DETECT_LABELS[step.id] or step.id end

local function drawStrip()
	local set, skipped = 0, 0
	for i, step in ipairs(steps) do
		local row = strip.rows[i]
		local done, skip, current = run.done[step.id], run.skipped[step.id], run.step and run.step.id == step.id
		if done then set = set + 1 end
		if skip then skipped = skipped + 1 end
		row.check:SetShown(done and not current)
		row.wash:SetShown(current)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", done and not current and 16 or 0, -3)
		row.text:SetFontObject(current and "GameFontNormal" or done and "GameFontHighlightSmall" or "GameFontDisableSmall")
		row.text:SetText(skip and not current and string.format(L.DETECT_SKIPPED_ROW, label(step)) or label(step))
	end
	strip.count:SetText(string.format(L.DETECT_COUNT, set, skipped, #steps))
end

-- Bars (MirrorTimer art) ------------------------------------------------------------------------------------------

local function newBar(width, height, withText)
	local bar = CreateFrame("StatusBar", nil, window)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture("ui-castingbar-filling-standard")
	bar:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
	bar:SetMinMaxValues(0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("ui-castingbar-background")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	local border = bar:CreateTexture(nil, "OVERLAY")
	border:SetAtlas("ui-castingbar-frame")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	if withText then
		local box = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		box:SetAtlas("ui-castingbar-textbox")
		box:SetPoint("TOP", bar, "BOTTOM", 0, 0)
		box:SetSize(width, 16)
		bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.text:SetPoint("CENTER", box, "CENTER")
	end
	return bar
end

-- Screens -----------------------------------------------------------------------------------------------------------

local function showOnly(...)
	local wanted = {}
	for _, name in ipairs({ ... }) do wanted[name] = true end
	for name, region in pairs(screens) do region:SetShown(wanted[name] or false) end
end

local function setStatus(icon, text, color)
	screens.statusIcon:SetShown(icon ~= nil)
	if icon then screens.statusIcon:SetAtlas(icon) end
	screens.status:SetText(text or "")
	screens.status:SetFontObject(icon and "GameFontNormal" or "GameFontDisableSmall")
	if color then screens.status:SetTextColor(color:GetRGB()) end
end

local function close() UI.CloseAll() end

local function cancel()
	if ns.Device.Detecting() then return ns.Device.DetectCancel() end
	close()
end

local function stepScreen()
	local step = run.step
	window.noPad = true
	window:SetPrompts({})
	showOnly("counter", "prompt", "status", "statusIcon", "pad", "strip")
	placePad(24, 96, 0.93)
	showFaces(nil)
	local index = 1
	for i, s in ipairs(steps) do
		if s.id == step.id then index = i end
	end
	screens.counter:SetText(string.format(L.DETECT_COUNTER, index, #steps, label(step)))
	screens.prompt:SetText(label(step))
	if run.rejected then
		setStatus("common-icon-redx", run.rejected, RED_FONT_COLOR)
	elseif run.captured then
		setStatus("common-icon-checkmark", run.captured, GREEN_FONT_COLOR)
	elseif step.optional then
		setStatus(nil, L.DETECT_OPTIONAL)
	elseif step.kind == "stick" then
		setStatus(nil, L.DETECT_STICK)
	elseif step.kind == "trigger" then
		setStatus(nil, L.DETECT_TRIGGER)
	else
		setStatus(nil, L.DETECT_WAITING)
	end
	screens.meter:SetShown(step.kind == "trigger" and not run.captured)

	local skip = step.optional and { 432, 164, L.DETECT_SKIP_OPTIONAL, L.KEY_SPACE, function() ns.Device.DetectSkip() end, true } or { 476, 120, L.SKIP, L.KEY_SPACE, function() ns.Device.DetectSkip() end }
	setButtons({ { 24, 120, L.BACK, L.KEY_BACKSPACE, function() ns.Device.DetectBack() end }, skip, { 616, 120, L.CANCEL, L.KEY_ESCAPE, cancel } })
	drawControls()
	drawStrip()
end

local function calibrateScreen()
	window.noPad = true
	window:SetPrompts({})
	showOnly("counter", "prompt", "pad", "strip", "calibrate")
	placePad(24, 96, 0.93, 0.5)
	showFaces(nil)
	screens.counter:SetText(L.DETECT_CALIBRATING_COUNTER)
	screens.prompt:SetText(L.DETECT_CALIBRATING)
	run.calibrateStarted = GetTime()
	setButtons({ { 616, 120, L.CANCEL, L.KEY_ESCAPE, cancel } })
	drawControls()
	drawStrip()
end

local function finishScreen()
	window.noPad = true
	window:SetPrompts({})
	showOnly("prompt", "finish", "skippedInset")
	screens.prompt:SetText(L.DETECT_FINISH_HEADING)
	run.style = run.style or (ns.Device.Current() and ns.Device.Current().labelStyle ~= "Generic" and ns.Device.Current().labelStyle) or "Letters"
	if not STYLE_FACES[run.style] then run.style = "Letters" end
	for _, radio in ipairs(screens.finish.radios) do
		local on = radio.style == run.style
		radio.check:SetShown(on)
		radio.wash:SetShown(on)
	end
	local list, set = {}, 0
	for _, step in ipairs(steps) do
		if run.skipped[step.id] then list[#list + 1] = label(step) end
		if run.done[step.id] then set = set + 1 end
	end
	screens.skippedInset.list:SetText(#list > 0 and table.concat(list, "\n") or L.DETECT_NONE_SKIPPED)
	screens.skippedInset.note:SetText(string.format(L.DETECT_SKIPPED_NOTE, set))
	setButtons({ { 24, 120, L.BACK, L.KEY_BACKSPACE, function() ns.Device.DetectBack() end }, { 616, 120, L.DETECT_SAVE, L.KEY_ENTER, D.Save, true } })
end

local function doneScreen()
	window.noPad = false
	showOnly("pad", "heading", "device", "lines")
	placePad(30, 90, 0.8)
	for _, control in pairs(pad.controls) do styleControl(control, "done") end
	pad.check:Hide()
	pad.arrow:Hide()
	showFaces(run.style)
	screens.heading:SetText(L.DETECT_DONE_HEADING)
	local device = ns.Device.Current()
	screens.device:SetText(device and string.format(L.DETECT_DEVICE_LINE, device.name or "", device.key) or "")
	screens.lines:SetText(L.DETECT_DONE_LINES)
	setButtons({})
	window:SetNodes({})
	window:SetPrompts({ { "PAD1", L.CONTINUE }, { "PAD2", L.CLOSE } })
end

-- Engine events -------------------------------------------------------------------------------------------------

-- "rejected": b is the engine's reason, c the id of the step already holding that input when it gives one.
local function onEvent(kind, a, b, c)
	if not window then return end
	if kind == "calibrating" then
		run.phase = "calibrating"
		return calibrateScreen()
	end
	if kind == "step" then
		local wasCaptured = run.pendingCapture
		run.phase, run.step, run.rejected, run.conflict = "step", a, nil, nil
		run.done[a.id], run.skipped[a.id] = nil, nil
		run.captured = wasCaptured and string.format(L.DETECT_CAPTURED, wasCaptured, label(a)) or nil
		run.pendingCapture = nil
		-- Steps before this one that were neither captured nor marked done were skipped.
		for _, step in ipairs(steps) do
			if step.id == a.id then break end
			if not run.done[step.id] then run.skipped[step.id] = true end
		end
		return stepScreen()
	end
	if kind == "captured" then
		run.done[a.id], run.skipped[a.id], run.lastCaptured = true, nil, a.id
		run.pendingCapture = b and (b.button and string.format(L.DETECT_BUTTON, b.button + 1) or b.axis and string.format(L.DETECT_AXIS, b.axis + 1)) or ""
		return
	end
	if kind == "rejected" then
		local used = c
		local stepLabel = used
		for _, step in ipairs(steps) do
			if step.id == used then stepLabel = label(step) end
		end
		run.conflict = used
		run.rejected = used and string.format(L.DETECT_REJECTED, stepLabel) or b
		return stepScreen()
	end
	if kind == "done" then
		run.phase, run.step, run.result = "finish", nil, a
		for _, step in ipairs(steps) do
			if not run.done[step.id] then run.skipped[step.id] = true end
		end
		return finishScreen()
	end
	if kind == "cancelled" then
		run.phase = "cancelled"
		if window:IsShown() and not UI.combatClosing then close() end
	end
end

-- Actions ------------------------------------------------------------------------------------------------------------

function D.Begin()
	steps = ns.Device.DetectSteps()
	run = { done = {}, skipped = {} }
	local ok, err = ns.Device.DetectStart(onEvent)
	if not ok then
		close()
		ns.log("detect: " .. tostring(err))
	end
end

function D.Save()
	local ok, err = ns.Device.DetectFinish(run.style)
	if not ok then return ns.log("detect: " .. tostring(err)) end
	doneScreen()
end

local function continue()
	local done = opts and opts.onDone
	close()
	if done then done() end
end

-- Main window ----------------------------------------------------------------------------------------------------

-- Enter = the screen's main button, Space = skip, Backspace = back, Escape = cancel; nothing else is kept.
local function onKey(_, key)
	-- The keyboard confirm before a run: Enter continues, Esc cancels; nothing else.
	if UI.DialogShown() then
		if key == "ENTER" then UI.Dialog():Press(1) end
		if key == "ESCAPE" then UI.Dialog():Press(2) end
		return true
	end
	if key == "ESCAPE" then
		cancel()
		return true
	end
	if not window.noPad and (key == "ENTER" or key == "SPACE") then
		continue()
		return true
	end
	if key == "ENTER" then
		if run and run.phase == "finish" then D.Save() end
		return true
	end
	if key == "SPACE" then
		if run and run.phase == "step" then ns.Device.DetectSkip() end
		return true
	end
	if key == "BACKSPACE" then
		if run and (run.phase == "step" or run.phase == "finish") then ns.Device.DetectBack() end
		return true
	end
	if run and run.phase == "finish" and (key == "UP" or key == "DOWN") then
		local index = 1
		for i, style in ipairs(STYLES) do
			if style == run.style then index = i end
		end
		run.style = STYLES[(index - 1 + (key == "DOWN" and 1 or -1)) % #STYLES + 1]
		finishScreen()
		return true
	end
end

local function build()
	window = UI.NewWindow(W, H)
	window:SetTitle(L.DETECT_TITLE)
	window.ClosePanelButton:SetScript("OnClick", cancel)
	window.OnKeyDownOverride = onKey
	window.OnKey = function(_, key)
		if window.noPad then return true end
		if key == "PAD1" then continue() return true end
		if key == "PAD2" then
			close()
			return true
		end
	end
	window.OnBack = close
	buttons, screens = {}, {}
	pad = newPad(window)
	screens.pad = pad
	strip = newStrip()
	screens.strip = strip
	screens.counter = UI.Text(window, "GameFontDisableSmall", 24, 34)
	screens.prompt = UI.Text(window, "GameFontNormalHuge", 24, 52)
	screens.statusIcon = window:CreateTexture(nil, "OVERLAY")
	screens.statusIcon:SetSize(16, 16)
	at(screens.statusIcon, 24, 77)
	screens.status = UI.Text(window, "GameFontDisableSmall", 44, 79)
	screens.heading = UI.Text(window, "GameFontNormalHuge", 370, 92)
	screens.device = UI.Text(window, "GameFontDisableSmall", 370, 118)
	screens.lines = UI.Text(window, "GameFontHighlight", 370, 150, nil, 350)
	screens.lines:SetSpacing(3)

	local calibrate = newBar(195, 13, true)
	at(calibrate, 120, 250)
	screens.calibrate = calibrate
	local meter = newBar(195, 19)
	at(meter, 160, 79)
	meter.line = meter:CreateTexture(nil, "OVERLAY", nil, 2)
	meter.line:SetColorTexture(1, 0.82, 0)
	meter.line:SetSize(1, 19)
	meter.line:SetPoint("LEFT", meter, "LEFT", 195 * 0.8, 0)
	screens.meter = meter

	-- Finish: three style rows with live face glyphs, and the skipped list.
	local finish = UI.Inset(window, 24, 100, 440, 236)
	finish.radios = {}
	for i, style in ipairs(STYLES) do
		local radio = CreateFrame("Button", nil, finish)
		radio:SetSize(420, 44)
		UI.At(radio, window, 34, 124 - 100 + 100 + (i - 1) * 66 - 22)
		radio.wash = radio:CreateTexture(nil, "BACKGROUND")
		radio.wash:SetColorTexture(1, 1, 1, 0.1)
		radio.wash:SetAllPoints()
		local tick = radio:CreateTexture(nil, "ARTWORK")
		tick:SetAtlas("common-dropdown-tickradial")
		tick:SetSize(18, 18)
		tick:SetPoint("LEFT", 6, 0)
		radio.check = radio:CreateTexture(nil, "OVERLAY")
		radio.check:SetAtlas("common-dropdown-icon-radialtick-yellow")
		radio.check:SetAllPoints(tick)
		local name = radio:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("TOPLEFT", 30, -6)
		name:SetText(L.DETECT_STYLES[style][1])
		local sub = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
		sub:SetText(L.DETECT_STYLES[style][2])
		for f = 1, 4 do
			local face = radio:CreateTexture(nil, "OVERLAY")
			face:SetAtlas(STYLE_FACES[style][f])
			face:SetSize(30, 30)
			face:SetPoint("RIGHT", radio, "RIGHT", -8 - (4 - f) * 32, 0)
		end
		radio.style = style
		radio:SetScript("OnClick", function()
			run.style = style
			finishScreen()
		end)
		finish.radios[i] = radio
	end
	screens.finish = finish
	local skippedInset = UI.Inset(window, 480, 100, 256, 236)
	UI.Text(skippedInset, "GameFontNormal", 12, 9, L.DETECT_SKIPPED_TITLE)
	skippedInset.list = UI.Text(skippedInset, "GameFontDisableSmall", 12, 30, nil, 232)
	skippedInset.list:SetSpacing(2)
	skippedInset.note = UI.Text(skippedInset, "GameFontHighlightSmall", 12, 180, nil, 232)
	screens.skippedInset = skippedInset

	window.OnHoldTick = function()
		if not run then return end
		if run.phase == "calibrating" and run.calibrateStarted then
			local elapsed = math.min(1, GetTime() - run.calibrateStarted)
			calibrate:SetValue(elapsed)
			calibrate.text:SetText(string.format(L.DETECT_CALIBRATE_BAR, 1 - elapsed))
		end
		if run.phase == "step" and run.step and run.step.kind == "trigger" then
			local _, raw = ns.Device.Raw()
			local peak = 0
			for _, value in pairs(raw and raw.rawAxes or {}) do
				if type(value) == "number" then peak = math.max(peak, math.min(1, math.abs(value))) end
			end
			meter:SetValue(peak)
		end
	end
	window.OnClosed = function()
		if ns.Device.Detecting() then
			if UI.combatClosing then
				local saved = opts
				UI.resume = { text = L.RESUME_DETECT, fn = function() D.Open(saved) end }
			end
			ns.Device.DetectCancel()
		end
		run = nil
	end
	window.OnRefresh = function() end
end

-- opts = { onDone = fn }. A run is driven by keyboard keys (the pad is read raw), so a native confirm says so first;
-- a pad-only player cancels there instead of being stuck in the wizard.
function D.Open(options)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	if not ns.Device.Current() then return UI.ShowMessage(L.NO_PAD_NOTICE, { { L.CLOSE } }) end
	if not window then build() end
	opts = options or {}
	UI.Show(window)
	if UI.Current() ~= window then return end
	-- From the first frame: no pad navigation, no footer, no chevron (the pad is read raw).
	window.noPad = true
	window:SetPrompts({})
	window:SetNodes({})
	window.cursor:Hide()
	steps = ns.Device.DetectSteps()
	showOnly()
	window.noPad = false
	UI.Dialog():Open(window, { text = L.DETECT_KEYBOARD, buttons = { L.CONTINUE, L.CANCEL }, back = 2, on1 = function()
		-- From here the pad is read raw: no pad navigation, no footer, no chevron.
		window.noPad = true
		window:SetPrompts({})
		window.cursor:Hide()
		D.Begin()
	end, on2 = close })
end

-- More's "Reset detection": a native confirm first.
function D.Reset(owner)
	UI.Dialog():Open(owner, { text = L.DETECT_RESET_TEXT, sub = L.DETECT_RESET_SUB, buttons = { L.RESET, L.CANCEL }, on1 = function()
		if not ns.Device.DetectReset() then ns.log(L.DETECT_NOTHING_TO_RESET) end
	end })
end
