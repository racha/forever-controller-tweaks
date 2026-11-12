-- Forever Controller Tweaks "Touch bars" window: the two on-screen bars Touch.lua draws for touch screens (Steam Link), in
-- Bindings' design and window. The centre shows the screen with both bars at their real relative size, count and
-- position; the edge columns list each bar's buttons (A opens the action picker, X clears) and the focused row's
-- gold line lands on its button in the preview. Header: On/Off and when the bars show; steppers under the preview set
-- count, size, spacing, distance from the edge, vertical offset and opacity (D-pad left/right).
-- Everything goes through ns.Touch (Config, Set, Entry, SetEntry; FCT_LAYOUT_CHANGED "touch"): its settings
-- and their defaults come from Config(), and Set refuses a value out of range.
local _, ns = ...
local UI = ns.UI
local L = UI.L

local T = {}
UI.TouchTab = T

local SIDES = { "left", "right" }
local SHOW = { "always", "gamepad", "combat", "never" }
-- { Touch setting, step }. The limits are Touch's (Touch.LIMITS when it exports them, else Set refuses past them).
local SETTINGS = { { "count", 1 }, { "size", 4 }, { "gap", 2 }, { "inset", 4 }, { "offsetY", 10 }, { "alpha", 0.1 } }
-- The box the screen preview fits in (window units), its corner radius and outline tone, the steppers under it.
local BOX_X, BOX_Y, BOX_W, BOX_H, CORNER = 380, 100, 440, 250, 14
local OUTLINE = { 138 / 255, 106 / 255, 60 / 255 }
-- The settings: a vertical list under the preview, one per line (up/down move between them, left/right change one).
local STEPPER_W, STEPPER_H, STEPPER_TOP, STEPPER_PITCH, ARROW = 280, 28, 372, 30, 26
local CELL, CELL_GAP, ONOFF_W, SHOW_W, SHOW_GAP, SHOW_LABEL_W = 34, 8, 64, 110, 28, 56

local window, preview, curve, outline, onoff, show
local rows, buttons, steppers = {}, { left = {}, right = {} }, {}

-- Touch's settings for this character, defaults filled in; nil before the character is known.
local function config() return ns.Touch and ns.Touch.Config() end

local function set(key, value)
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
	local _, err = ns.Touch.Set(key, value)
	if err then ns.log(err) end
end

local function codeOf(side, i) return (side == "left" and "TL" or "TR") .. i end

-- A button's place on the screen (UIParent units, from the top-left), by Touch's own anchoring (Touch.lua applyNow):
-- each bar sits on its edge at inset, centred vertically and moved up by offsetY, its buttons gap apart. Computed, not
-- read from Touch.Button: those frames are not re-placed while the bars are off.
local function buttonRect(side, i, c, width, height)
	local total = c.count * c.size + (c.count - 1) * c.gap
	local x = side == "left" and c.inset or width - c.inset - c.size
	return x, (height - total) / 2 - c.offsetY + (i - 1) * (c.size + c.gap), c.size
end

-- The screen outline: a rounded rectangle through the shared line helper (soft, antialiased), points in window units.
local function roundedRect(x, y, w, h, r)
	local points = {}
	local corners = { { x + w - r, y + r, -90 }, { x + w - r, y + h - r, 0 }, { x + r, y + h - r, 90 }, { x + r, y + r, 180 } }
	for _, corner in ipairs(corners) do
		for step = 0, 6 do
			local angle = math.rad(corner[3] + step * 15)
			points[#points + 1] = { corner[1] + r * math.cos(angle), corner[2] + r * math.sin(angle) }
		end
	end
	points[#points + 1] = points[1]
	return points
end

local function pick(row)
	if InCombatLockdown() then return end
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
	UI.ActionPicker.Open({ window = window, cell = row.cell, touch = { side = row.side, index = row.index } })
end

local function clear(row)
	if ns.Touch then UI.ActionPicker.ClearCell({ touch = { side = row.side, index = row.index } }) end
end

-- A row from Bindings' parts: the button number where the glyph goes, one cell beside it, then name and subtitle.
local function newRow(side, i)
	local B = UI.Bindings
	local row = B.NewRow(window, nil)
	row.side, row.index, row.code = side, i, codeOf(side, i)
	row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.number:SetPoint("CENTER", row.glyph)
	row.number:SetText(i)
	row.inset = B.GEO.GLYPH_X - B.GEO.EDGE - 13 - CELL_GAP - CELL
	local cell = B.SlotCell(row, CELL, false)
	cell.row = row
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:SetScript("OnClick", function(_, button)
		if button == "RightButton" then return clear(row) end
		pick(row)
	end)
	cell:SetScript("OnLeave", function(self) UI.HideTooltip(self) end)
	row.cell = cell
	return row
end

local function fillRow(row)
	local entry = ns.Touch and ns.Touch.Entry(row.side, row.index)
	row.name:SetText(entry and entry.name or L.TOUCH_EMPTY)
	row.name:SetFontObject(entry and "GameFontNormal" or "GameFontDisable")
	row.sub:SetText(string.format(L.TOUCH_SUB, L.TOUCH_SIDE[row.side], row.index))
	row.marker:SetRole(nil)
	row.cell.icon:ClearAllPoints()
	row.cell.icon:SetPoint("TOPLEFT", 3, -3)
	row.cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	row.cell.icon:SetTexture(entry and entry.icon or nil)
	row.cell.icon:SetShown(entry ~= nil)
	return entry
end

local function cellTip(row)
	local entry = ns.Touch and ns.Touch.Entry(row.side, row.index)
	return { title = entry and entry.name or L.TOUCH_EMPTY, lines = { string.format(L.TOUCH_SUB, L.TOUCH_SIDE[row.side], row.index) }, actions = { { "PAD1", L.CHOOSE_ACTION }, { "PAD3", L.CLEAR_SLOT } }, side = row.side }
end

-- The screen with both bars: aspect from UIParent, buttons at their real relative size and place, the focused one
-- lit; greyed while the bars are off or never shown.
local function drawPreview(c)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local scale = math.min(BOX_W / width, BOX_H / height)
	local w, h = width * scale, height * scale
	local x, y = BOX_X + (BOX_W - w) / 2, BOX_Y + (BOX_H - h) / 2
	preview:ClearAllPoints()
	UI.At(preview, window, x, y)
	preview:SetSize(w, h)
	preview.fillA:SetSize(w - 2 * CORNER, h)
	preview.fillB:SetSize(w, h - 2 * CORNER)
	outline:Set(roundedRect(x, y, w, h, CORNER), OUTLINE[1], OUTLINE[2], OUTLINE[3], 1, 2.5)
	preview.boxes = {}
	local live = c.enabled and c.show ~= "never"
	for _, side in ipairs(SIDES) do
		for _, button in ipairs(buttons[side]) do button:Hide() end
		for i = 1, c.count do
			local bx, by, size = buttonRect(side, i, c, width, height)
			local button = buttons[side][i] or UI.Bindings.SlotCell(preview, 10, false)
			buttons[side][i] = button
			local s = math.max(size * scale, 6)
			button:SetSize(s, s)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", preview, "TOPLEFT", bx * scale, -by * scale)
			button:SetAlpha(live and c.alpha or 0.3)
			local entry = ns.Touch and ns.Touch.Entry(side, i)
			button.icon:SetAllPoints()
			button.icon:SetTexture(entry and entry.icon or nil)
			button.icon:SetShown(entry ~= nil)
			UI.Bindings.SetCellFocus(button, false)
			button:Show()
			preview.boxes[codeOf(side, i)] = { x + bx * scale, y + by * scale, x + bx * scale + s, y + by * scale + s }
		end
	end
end

local function drawFocus()
	local focusRow = window.focus and window.focus.region and window.focus.region.row
	for _, side in ipairs(SIDES) do
		for i, button in ipairs(buttons[side]) do UI.Bindings.SetCellFocus(button, focusRow and focusRow.side == side and focusRow.index == i) end
	end
	UI.Bindings.FocusLine(curve, preview, rows, focusRow and focusRow:IsShown() and focusRow or nil)
	if not UI.DialogShown() then window:SetPrompts(T.Prompts(window.focus and window.focus.region)) end
end

-- One step of a setting. False at its end (past Touch's limits, or refused by Set, quietly), so left/right moves the
-- focus on instead of sticking there.
local function stepBy(spec, step)
	local c = config()
	if not c then return false end
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	local key, inc = spec[1], spec[2]
	local value = c[key] + step * inc
	-- Opacity in tenths, so repeated steps never drift.
	if inc < 1 then value = math.floor(value * 10 + 0.5) / 10 end
	local limit = ns.Touch.LIMITS and ns.Touch.LIMITS[key]
	if limit and (value < limit[1] or value > limit[2]) then return false end
	return (ns.Touch.Set(key, value)) and true or false
end

local function valueText(key, value)
	if key == "alpha" then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
	return tostring(value)
end

-- One setting line: the label on the left, then the value between small D-pad left/right hints (clickable).
local function newStepper(spec, i)
	local stepper = CreateFrame("Button", nil, window)
	stepper:SetSize(STEPPER_W, STEPPER_H)
	UI.At(stepper, window, UI.Bindings.GEO.WIDTH / 2 - STEPPER_W / 2, STEPPER_TOP + (i - 1) * STEPPER_PITCH)
	stepper.wash = stepper:CreateTexture(nil, "BACKGROUND")
	stepper.wash:SetColorTexture(1, 1, 1, 0.1)
	stepper.wash:SetAllPoints()
	stepper.wash:Hide()
	stepper.label = stepper:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	stepper.label:SetPoint("LEFT", 10, 0)
	stepper.label:SetText(L.TOUCH_SETTINGS[spec[1]])
	stepper.value = stepper:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	stepper.value:SetPoint("CENTER", stepper, "RIGHT", -ARROW * 2, 0)
	for step, glyphCode in pairs({ [-1] = "DL", [1] = "DR" }) do
		local arrow = CreateFrame("Button", nil, stepper)
		arrow:SetSize(ARROW, STEPPER_H)
		arrow:SetPoint("CENTER", stepper, "RIGHT", step < 0 and -ARROW * 3.5 or -ARROW / 2 - 4, 0)
		arrow:SetScript("OnClick", function() stepBy(spec, step) end)
		local glyph = UI.Glyph(arrow, 16, glyphCode)
		glyph:SetPoint("CENTER")
	end
	stepper.spec = spec
	return stepper
end

local function refresh()
	local c = config()
	if not c then return end
	local B, geo = UI.Bindings, UI.Bindings.GEO
	onoff:Select(c.enabled and "on" or "off")
	show:Select(c.show)
	drawPreview(c)

	for _, row in pairs(rows) do row:Hide() end
	local nodes = {}
	local height = c.count * geo.ROW_PITCH - (geo.ROW_PITCH - geo.ROW_H)
	local top = geo.AREA_TOP + math.floor((geo.AREA_BOTTOM - geo.AREA_TOP - height) / 2)
	for _, side in ipairs(SIDES) do
		for i = 1, c.count do
			local code = codeOf(side, i)
			local row = rows[code] or newRow(side, i)
			rows[code] = row
			B.PlaceRow(row, side == "left", top + (i - 1) * geo.ROW_PITCH)
			local cell = row.cell
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", row, "TOPLEFT", side == "left" and row.inset or row:GetWidth() - row.inset - CELL, -(geo.ROW_H - CELL) / 2)
			fillRow(row)
			nodes[#nodes + 1] = UI.Node(window, cell, function() pick(row) end, { onFocus = function(on) B.SetCellFocus(cell, on) end, tip = function() return cellTip(row) end })
			B.SetCellFocus(cell, window.focus and window.focus.region == cell)
		end
	end
	for _, segment in ipairs(onoff) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = segment.text, lines = { L.TOUCH_ONOFF_TIP }, side = "below" } }) end
	for _, segment in ipairs(show) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = segment.text, lines = { L.TOUCH_SHOW_TIP }, side = "below" } }) end
	for _, stepper in ipairs(steppers) do
		local key = stepper.spec[1]
		stepper.value:SetText(valueText(key, c[key]))
		nodes[#nodes + 1] = UI.Node(window, stepper, function() end, {
			cursorX = 0, noSide = true, onDir = function(step) return stepBy(stepper.spec, step) end, onFocus = function(on) stepper.wash:SetShown(on) end,
			tip = { title = L.TOUCH_SETTINGS[key], lines = { L.STEPPER_TIP }, actions = { { "PADDLEFT", "-" }, { "PADDRIGHT", "+" } }, side = "right" },
		})
	end
	window:SetNodes(nodes)
	drawFocus()
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.touch then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(L.TOUCH_TITLE)
	-- One header line from the left: On/Off, then "Show" and its segments; the hint under it. Nothing near the right
	-- edge, where the side tabs and the close button are.
	onoff = UI.Segments(window, { { "on", L.TOUCH_ON }, { "off", L.TOUCH_OFF } }, 24, 25, ONOFF_W, function(id) set("enabled", id == "on") end)
	local showX = 24 + 2 * ONOFF_W + SHOW_GAP
	local showLabel = UI.Text(window, "GameFontNormal", showX, 31, L.TOUCH_SHOW_LABEL)
	UI.Text(window, "GameFontDisableSmall", 24, 58, L.TOUCH_HINT)
	local specs = {}
	for i, id in ipairs(SHOW) do specs[i] = { id, L.TOUCH_SHOW[id] } end
	show = UI.Segments(window, specs, showX + SHOW_LABEL_W, 25, SHOW_W, function(id) set("show", id) end)
	showLabel:SetWidth(SHOW_LABEL_W - 8)

	preview = Mixin(CreateFrame("Frame", nil, window), UI.DrawingMixin)
	preview.glyphs = {}
	-- The screen's dark face: two overlapping rects, so no corner pokes past the rounded outline.
	preview.fillA = preview:CreateTexture(nil, "BACKGROUND")
	preview.fillA:SetColorTexture(0.05, 0.04, 0.035, 0.95)
	preview.fillA:SetPoint("CENTER")
	preview.fillB = preview:CreateTexture(nil, "BACKGROUND")
	preview.fillB:SetColorTexture(0.05, 0.04, 0.035, 0.95)
	preview.fillB:SetPoint("CENTER")
	outline = UI.Connector(window, preview)
	curve = UI.Connector(window, preview)
	for i, spec in ipairs(SETTINGS) do steppers[i] = newStepper(spec, i) end

	window.OnRefresh = refresh
	window.OnFocusChanged = drawFocus
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		local region = window.focus and window.focus.region
		if key == "PAD3" and region and region.row then
			clear(region.row)
			return true
		end
		if key == "PAD4" and UI.ActionPicker.CanUndo() then
			UI.ActionPicker.Undo()
			return true
		end
	end
	window.OnClosed = function() UI.HideTooltip() end
end

-- The footer for what is focused: a button's cell, a setting (left/right change it) or a header segment.
function T.Prompts(region)
	if region and region.spec then return { { "PADDLEFT", L.STEP_LESS }, { "PADDRIGHT", L.STEP_MORE }, { "PADLSHOULDER", L.MODIFIERS }, { "PAD2", L.CLOSE } } end
	if not (region and region.row) then return { { "PAD1", L.SELECT }, { "PADLSHOULDER", L.MODIFIERS }, { "PAD2", L.CLOSE } } end
	local list = { { "PAD1", L.SELECT }, { "PAD3", L.CLEAR_SLOT }, { "PADLSHOULDER", L.MODIFIERS }, { "PAD2", L.CLOSE } }
	if UI.ActionPicker.CanUndo() then table.insert(list, 3, { "PAD4", L.UNDO_CLEAR }) end
	return list
end

function T.Open()
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
	if not config() then return ns.log(L.TOUCH_NO_CHARACTER) end
	if not window then build() end
	UI.Show(window)
end

-- The third side tab (Bindings, Modifiers, Touch); L1/R1 step through them.
UI.TABS[#UI.TABS + 1] = { "Interface\\Icons\\Spell_Holy_LayOnHands", L.TOUCH_TAB, function() T.Open() end, touch = true }

local function redraw() if window and window:IsShown() then window:Refresh() end end
ns.On("FCT_LAYOUT_CHANGED", redraw)
ns.On("UI_SCALE_CHANGED", redraw)
ns.On("DISPLAY_SIZE_CHANGED", redraw)
