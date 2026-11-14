-- Forever Controller Tweaks "Keyboard" side tab (design/keyboard.md section 7, artboards 7a-c), in the Touch tab's
-- language: On | Off and Open (With the controller | Always) in the header, a preview of the disc at the current
-- layout and scale on the left, the settings and the button rows on the right. A on a button row takes the next
-- press (swapping with the action that had it), X restores that row's default. Saves to
-- ForeverControllerTweaksDB.keyboard through K.Settings.
local ns = ForeverControllerTweaks
local UI, K = ns.UI, ns.Keyboard
local L = UI.L

local S = {}
K.SettingsTab = S

local T = {
	TAB = "Keyboard", TITLE = "Controller Tweaks · Keyboard", ON = "On", OFF = "Off", OPEN = "Open", CONTROLLER = "With the controller", ALWAYS = "Always",
	HINT = "An on-screen keyboard for chat and text boxes, while the Gamepad UI is on.", SECTION = "Keyboard", BUTTONS = "Buttons",
	LAYOUT = "Layout", RING = "Ring", COMPACT = "Compact", SCALE = "Scale", SUGGEST = "Word suggestions", RESET = "Reset keyboard to defaults",
	CHANGE = "Change", DEFAULT = "Default", PRESS = "Press a button…", RESET_TEXT = "Reset the keyboard's settings and buttons to the defaults?",
	ROW_TIP = "A: press the new button. X: back to the default.", POSITION = "Position", AUTO = "Auto", CENTRE = "Centre", CUSTOM = "Custom",
	OFFSET_X = "Left / right", OFFSET_Y = "Up / down", POSITION_TIP = "Auto keeps it clear of the chat, the crossbar and your unit frame. Centre and Custom pin it at the lower centre, Custom moved by the offsets.",
	OFFSET_TIP = "D-pad left and right move it (Custom).", SCALE_TIP = "D-pad left and right change it. On a phone, 1.25 reads best.",
	ACTIONS = { space = "Space", send = "Send", erase = "Erase", close = "Close", shift = "Shift", symbols = "Symbols", insert = "Insert word", prev = "Previous / next word", left = "Cursor left / right" },
}

-- Button rows; a pair row binds its two actions together (Previous / next word, Cursor left / right).
local ROWS = { { "space" }, { "send" }, { "erase" }, { "close" }, { "shift" }, { "symbols" }, { "insert" }, { "prev", "next" }, { "left", "right" } }
local RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H, LEFT_X, LEFT_W = 604, 84, 572, 526, 24, 560
local ROW_W, ROW_H, ROW_PITCH, SEG_W, SCALE_MIN, SCALE_MAX, SCALE_STEP = 520, 28, 30, 110, 0.75, 1.5, 0.05
-- Position rows sit under the preview in the left inset; the offsets step 10 units within OFFSET_MAX.
local POSITION_Y, OFFSET_STEP, OFFSET_MAX, PREVIEW_ROOM = RIGHT_Y + RIGHT_H - 108, 10, 600, 120

local window, onoff, openSeg, layoutSeg, suggestSeg, positionSeg, preview, rows, scaleRow, offsetRows, resetButton, capture

local function settings()
	if not ns.db then return end
	ns.db.keyboard = K.Settings(ns.db.keyboard)
	return ns.db.keyboard
end

local function changed()
	if K.View and K.View.Place then K.View.Place() end
	if window and window:IsShown() then window:Refresh() end
end

local function set(key, value)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	settings()[key] = value
	changed()
end

local function newRow(y, label, x)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(ROW_W, ROW_H)
	UI.At(row, window, x or RIGHT_X + (RIGHT_W - ROW_W) / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 10, 0)
	row.label:SetText(label)
	return row
end

-- The preview: the disc, rim, hub and the lower-case clusters at the current layout and scale (fit to the inset).
local function buildPreview()
	preview = CreateFrame("Frame", nil, window)
	preview:SetSize(2 * K.DISC_R, 2 * K.DISC_R)
	UI.At(preview, window, LEFT_X + LEFT_W / 2 - K.DISC_R, RIGHT_Y + (RIGHT_H - PREVIEW_ROOM) / 2 - K.DISC_R)
	for _, part in ipairs({ { "disc", 2 * K.DISC_R, 0.62 }, { "kb-glow", 2 * K.DISC_R - 12 }, { "kb-rim", 2 * K.DISC_R + 8 }, { "kb-hub", 160 } }) do
		local tex = preview:CreateTexture(nil, "BACKGROUND")
		if part[1] == "disc" then tex:SetAtlas("gamepad-targetingradial-radial-circle") else tex:SetTexture(UI.ART .. part[1] .. ".tga") end
		tex:SetSize(part[2], part[2])
		tex:SetPoint("CENTER")
		tex:SetAlpha(part[3] or 1)
	end
	preview.keys = {}
	local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
	for i = 1, 8 do
		local a = math.rad((i - 1) * 45)
		local cluster = CreateFrame("Frame", nil, preview)
		cluster:SetSize(1, 1)
		cluster:SetPoint("CENTER", preview, "CENTER", 132 * math.sin(a), 132 * math.cos(a))
		cluster.range = cluster:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		cluster.range:SetPoint("CENTER")
		cluster.keys = {}
		for j = 1, 4 do
			local key = K.View.NewKey(cluster, j)
			K.View.StyleKey(key, "idle", 32)
			key:SetPoint("CENTER", cluster, "CENTER", dirs[j][1] * 22, dirs[j][2] * 22)
			cluster.keys[j] = key
		end
		preview.keys[i] = cluster
	end
end

local function drawPreview(s)
	local compact = s.layout == "compact"
	local k = s.scale * (compact and 0.8 or 1)
	local fit = (RIGHT_H - PREVIEW_ROOM - 8) / (2 * K.DISC_R)
	preview:SetScale(math.min(k, fit))
	-- Scaled around its centre: the frame's offset is in its own (scaled) units.
	local scale = preview:GetScale()
	preview:ClearAllPoints()
	UI.At(preview, window, (LEFT_X + LEFT_W / 2) / scale - K.DISC_R, (RIGHT_Y + (RIGHT_H - PREVIEW_ROOM) / 2) / scale - K.DISC_R)
	local sets = K.CHARSETS.lower
	for i, cluster in ipairs(preview.keys) do
		for j, key in ipairs(cluster.keys) do
			key:SetShown(not compact)
			K.View.KeyLabel(key, sets[i][j], "idle", compact)
		end
		cluster.range:SetText(compact and sets[i][1] .. "–" .. sets[i][4] or "")
	end
end

local function rowGlyphs(row, actions)
	row.glyphs = row.glyphs or {}
	for i = 1, 2 do
		local glyph = row.glyphs[i] or UI.Glyph(row, 24)
		row.glyphs[i] = glyph
		glyph:ClearAllPoints()
		glyph:SetPoint("RIGHT", row, "RIGHT", -10 - (#actions - i) * 30, 0)
		glyph:SetShown(actions[i] ~= nil)
	end
end

local function rebind(row, key)
	local buttons = settings().buttons
	local actions = row.actions
	K.Bind(buttons, actions[1], key)
	-- A pair's second action takes the opposite D-pad direction when the first lands on the D-pad.
	local opposite = { PADDUP = "PADDDOWN", PADDDOWN = "PADDUP", PADDLEFT = "PADDRIGHT", PADDRIGHT = "PADDLEFT" }
	if actions[2] and opposite[key] then K.Bind(buttons, actions[2], opposite[key]) end
	capture = nil
	changed()
end

local function restore(row)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	for _, action in ipairs(row.actions) do K.Bind(settings().buttons, action, K.BUTTONS[action]) end
	changed()
end

local function stepScale(step)
	local s = settings()
	local value = math.floor((s.scale + step * SCALE_STEP) * 100 + 0.5) / 100
	if value < SCALE_MIN or value > SCALE_MAX then return false end
	set("scale", value)
end

local function stepOffset(key, step)
	local s = settings()
	if s.position ~= "custom" then return false end
	local value = s[key] + step * OFFSET_STEP
	if math.abs(value) > OFFSET_MAX then return false end
	set(key, value)
end

local function reset()
	UI.Dialog():Open(window, { text = T.RESET_TEXT, buttons = { L.RESET, L.CANCEL }, on1 = function()
		local s = settings()
		for key, value in pairs(K.DEFAULTS) do s[key] = value end
		for action, key in pairs(K.BUTTONS) do s.buttons[action] = key end
		changed()
	end })
end

local function prompts(region)
	if capture then return {} end
	if region and region.actions then return { { "PAD1", T.CHANGE }, { "PAD3", T.DEFAULT }, { "PAD4", L.MORE }, UI.TabPrompt("keyboard", -1), { "PAD2", L.CLOSE } } end
	return { { "PAD1", L.SELECT }, { "PAD4", L.MORE }, UI.TabPrompt("keyboard", -1), { "PAD2", L.CLOSE } }
end

local function refresh()
	local s = settings()
	if not s then return end
	onoff:Select(s.enabled and "on" or "off")
	openSeg:Select(s.open)
	layoutSeg:Select(s.layout)
	suggestSeg:Select(s.suggestions and "on" or "off")
	scaleRow.value:SetText(string.format("%.2f", s.scale))
	positionSeg:Select(s.position)
	for key, row in pairs(offsetRows) do
		row.value:SetText(s[key])
		row:SetAlpha(s.position == "custom" and 1 or 0.4)
	end
	drawPreview(s)
	local nodes = {}
	for _, segs in ipairs({ onoff, openSeg, layoutSeg, suggestSeg }) do
		for _, segment in ipairs(segs) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0 }) end
	end
	nodes[#nodes + 1] = UI.Node(window, scaleRow, function() end, {
		cursorX = 0, noSide = true, onDir = stepScale, onFocus = function(on) scaleRow.wash:SetShown(on) end,
		tip = { title = T.SCALE, lines = { T.SCALE_TIP }, side = "left" },
	})
	for _, row in ipairs(rows) do
		local actions = row.actions
		rowGlyphs(row, actions)
		for i, action in ipairs(actions) do row.glyphs[i]:SetCode(s.buttons[action]) end
		row.label:SetText(capture == row and T.PRESS or T.ACTIONS[actions[1]])
		nodes[#nodes + 1] = UI.Node(window, row, function() if not InCombatLockdown() then capture = row window:Refresh() end end, {
			cursorX = 0, onFocus = function(on) row.wash:SetShown(on) end, tip = { title = T.ACTIONS[actions[1]], lines = { T.ROW_TIP }, side = "left" },
		})
	end
	nodes[#nodes + 1] = UI.Node(window, resetButton, reset, { cursorX = 0 })
	for _, segment in ipairs(positionSeg) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = T.POSITION, lines = { T.POSITION_TIP }, side = "right" } }) end
	for _, key in ipairs({ "x", "y" }) do
		local row = offsetRows[key]
		nodes[#nodes + 1] = UI.Node(window, row, function() end, {
			cursorX = 0, noSide = true, onDir = function(step) return stepOffset(key, step) end, onFocus = function(on) row.wash:SetShown(on) end,
			tip = { title = row.label:GetText(), lines = { T.OFFSET_TIP }, side = "right" },
		})
	end
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(prompts(window.focus and window.focus.region)) end
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.keyboard then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(T.TITLE)
	onoff = UI.Segments(window, { { "on", T.ON }, { "off", T.OFF } }, 24, 25, 64, function(id) set("enabled", id == "on") end)
	UI.Text(window, "GameFontNormal", 236 - 56, 31, T.OPEN)
	openSeg = UI.Segments(window, { { "controller", T.CONTROLLER }, { "always", T.ALWAYS } }, 236, 25, 130, function(id) set("open", id) end)
	UI.Text(window, "GameFontDisableSmall", 24, 58, T.HINT)
	UI.Inset(window, LEFT_X, RIGHT_Y, LEFT_W, RIGHT_H)
	UI.Inset(window, RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H)
	buildPreview()

	local y = RIGHT_Y + 12
	UI.SectionHeader(window, RIGHT_X + (RIGHT_W - 197) / 2, y, 197, T.SECTION)
	y = y + 46
	local layoutRow = newRow(y, T.LAYOUT)
	layoutSeg = UI.Segments(layoutRow, { { "ring", T.RING }, { "compact", T.COMPACT } }, ROW_W - 2 * SEG_W - 4, 1, SEG_W, function(id) set("layout", id) end)
	y = y + ROW_PITCH
	-- A stepper row: the value between clickable D-pad left / right hints.
	local function stepper(row, onStep)
		row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.value:SetPoint("RIGHT", -40, 0)
		for step, code in pairs({ [-1] = "DL", [1] = "DR" }) do
			local arrow = CreateFrame("Button", nil, row)
			arrow:SetSize(26, ROW_H)
			arrow:SetPoint("RIGHT", row, "RIGHT", step < 0 and -82 or -6, 0)
			arrow:SetScript("OnClick", function() onStep(step) end)
			UI.Glyph(arrow, 16, code):SetPoint("CENTER")
		end
		return row
	end
	scaleRow = stepper(newRow(y, T.SCALE), stepScale)
	local leftRowX = LEFT_X + (LEFT_W - ROW_W) / 2
	local positionRow = newRow(POSITION_Y, T.POSITION, leftRowX)
	positionSeg = UI.Segments(positionRow, { { "auto", T.AUTO }, { "centre", T.CENTRE }, { "custom", T.CUSTOM } }, ROW_W - 3 * SEG_W - 4, 1, SEG_W, function(id) set("position", id) end)
	offsetRows = {
		x = stepper(newRow(POSITION_Y + ROW_PITCH, T.OFFSET_X, leftRowX), function(step) stepOffset("x", step) end),
		y = stepper(newRow(POSITION_Y + 2 * ROW_PITCH, T.OFFSET_Y, leftRowX), function(step) stepOffset("y", step) end),
	}
	y = y + ROW_PITCH
	local suggestRow = newRow(y, T.SUGGEST)
	suggestSeg = UI.Segments(suggestRow, { { "on", T.ON }, { "off", T.OFF } }, ROW_W - 2 * SEG_W - 4, 1, SEG_W, function(id) set("suggestions", id == "on") end)
	y = y + ROW_PITCH + 10
	UI.SectionHeader(window, RIGHT_X + (RIGHT_W - 197) / 2, y, 197, T.BUTTONS)
	y = y + 46
	rows = {}
	for i, actions in ipairs(ROWS) do
		local row = newRow(y + (i - 1) * ROW_PITCH, T.ACTIONS[actions[1]])
		row.actions = actions
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then return restore(self) end
			capture = self
			window:Refresh()
		end)
		rows[i] = row
	end
	resetButton = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate")
	resetButton:SetSize(200, 22)
	UI.At(resetButton, window, RIGHT_X + (RIGHT_W - 200) / 2, RIGHT_Y + RIGHT_H - 36)
	resetButton:SetText(T.RESET)
	resetButton:SetScript("OnClick", reset)

	window.OnRefresh = refresh
	window.OnFocusChanged = function() if not UI.DialogShown() then window:SetPrompts(prompts(window.focus and window.focus.region)) end end
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		-- Taking a button: the next press is the new one, whatever it is (an L1/R1 tap must not switch tabs).
		if capture then
			window.tap = nil
			rebind(capture, key)
			return true
		end
		local region = window.focus and window.focus.region
		if key == "PAD3" and region and region.actions then
			restore(region)
			return true
		end
		if key == "PAD4" then
			UI.OpenMore(window, { { id = "kbreset", name = T.RESET, detail = T.RESET_TEXT, run = reset } })
			return true
		end
	end
end

function S.Open()
	if not settings() then return end
	if not window then build() end
	UI.Show(window)
end

S.T = T

-- A side tab after Bindings and Touch (Bindings, Touch, Keyboard, Rings, of those loaded); L1/R1 step through them.
UI.AddTab({ "Interface\\Icons\\INV_Letter_15", T.TAB, function() S.Open() end, keyboard = true, order = 3, prompt = T.TAB })
