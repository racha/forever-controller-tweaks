-- Forever Controller Tweaks "Touch bars" window: the two on-screen bars Touch.lua draws for touch screens (Steam
-- Link), in Bindings' design and window. Each bar's buttons are rows at the window's edges with four layer cells like
-- Bindings (top, left, right, bottom bar, under the same layer headers): A opens the action picker on a cell, X clears,
-- Y undoes. The centre shows the screen with both bars at their real relative size, count and place (each side by
-- its own settings), the held modifier's layer icons on them, and the focused row's gold line landing on its button.
-- Header: the slot counter and the hint. Under the preview, one value per row (up/down move, left/right only change
-- the focused one): On and Show (global), a "Settings for" dropdown (Left / Right bar) and that side's settings: the
-- numbers are sliders, Shape a dropdown and Empty buttons a checkbox.
-- The On row is the list's way in from the bars' rows: left/right on it move the focus (a checkbox has no left/right).
-- Everything goes through ns.Touch: Config (per side under sides.left / sides.right), Set / SetSide, LIMITS,
-- Entry / SetEntry (per layer), SetHealer, Layer, SlotsUsed, Reset; FCT_LAYOUT_CHANGED "touch". Y on a cell: More with
-- its Healer mode row first.
local ns = ForeverControllerTweaks
local UI = ns.UI
local L = UI.L

local T = {}
UI.TouchTab = T

local SIDES = { "left", "right" }
local SHOW = { "always", "gamepad", "combat", "never" }
-- { Touch setting, step } (the limits are Touch.LIMITS), or { Touch setting, options = its two values in order }.
local SETTINGS = {
	{ "count", 1 }, { "size", 4 }, { "gap", 2 }, { "inset", 4 }, { "offsetY", 10 }, { "alpha", 0.1 },
	{ "shape", options = { "circle", "square" } }, { "showEmpty", options = { false, true } },
}
-- The box the screen preview fits in (window units, 12 inside the middle content box, 400-800), its corner radius and
-- outline tone; the settings list under it (On, Show, the side switch, that side's settings), all in that box down to
-- 610.
local BOX_X, BOX_Y, BOX_W, BOX_H, CORNER = 412, 96, 376, 182, 14
local OUTLINE = { 138 / 255, 106 / 255, 60 / 255 }
local ON_TOP, SIDE_TOP = 290, 352
-- A setting row's control starts CONTROL_X in: sliders SLIDER_W wide, dropdown values CHOICE_W (the side's and Show's
-- SIDE_W).
local STEPPER_W, STEPPER_H, STEPPER_TOP, STEPPER_PITCH, CONTROL_X, SLIDER_W, CHOICE_W, SIDE_W = 280, 26, 380, 28, 140, 120, 70, 90
local CELL = 34

local window, preview, curve, outline, onRow, showRow, sideRow, counter, headers
local rows, steppers = {}, {}
-- The preview's buttons per side and shape (a cell's mask is fixed when it is made).
local buttons = { left = { circle = {}, square = {} }, right = { circle = {}, square = {} } }
local settingSide, heldLayer = "left", nil

-- Touch's settings for this character, defaults filled in; nil before the character is known.
local function config() return ns.Touch.Config() end

local function sideConfig(c, side) return c.sides[side] end

local function entryOf(side, i, layer) return ns.Touch.Entry(side, i, layer) end

local function set(key, value)
	local _, err = ns.Touch.Set(key, value)
	if err then ns.log(err) end
end

-- used, total and whether none is free.
local function slots()
	local used, free, total = ns.Touch.SlotsUsed()
	return used, total, free == 0
end

local function codeOf(side, i) return (side == "left" and "TL" or "TR") .. i end

-- A button's place on the screen (UIParent units, from the top-left), by Touch's own anchoring: each bar sits on its
-- edge at inset, centred vertically and moved up by offsetY, its buttons gap apart.
local function buttonRect(side, i, s, width, height)
	local total = s.count * s.size + (s.count - 1) * s.gap
	local x = side == "left" and s.inset or width - s.inset - s.size
	return x, (height - total) / 2 - s.offsetY + (i - 1) * (s.size + s.gap), s.size
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

local function pick(cell)
	if InCombatLockdown() then return end
	local row = cell.row
	UI.ActionPicker.Open({ window = window, cell = cell, touch = { side = row.side, index = row.index, layer = cell.layer } })
end

local function clear(cell)
	local row = cell.row
	UI.ActionPicker.ClearCell({ touch = { side = row.side, index = row.index, layer = cell.layer } })
end

-- A row from Bindings' parts: four layer cells at the window edge, the button number where the glyph goes, then the
-- shown layer's action and a subtitle.
local function newRow(side, i)
	local B = UI.Bindings
	local row = B.NewRow(window, nil)
	row.side, row.index, row.code, row.cells = side, i, codeOf(side, i), {}
	row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.number:SetPoint("CENTER", row.glyph)
	row.number:SetText(i)
	for j, layer in ipairs(B.LAYERS) do
		local cell = B.SlotCell(row, CELL, false)
		cell.row, cell.layer = row, layer
		cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		cell:SetScript("OnClick", function(self, button)
			if button == "RightButton" then return clear(self) end
			pick(self)
		end)
		cell:SetScript("OnLeave", function(self) UI.HideTooltip(self) end)
		row.cells[j] = cell
	end
	return row
end

-- The bar a row names: the held modifier's, else the focused cell's column, else the top bar.
local function shownLayer()
	if heldLayer then return heldLayer end
	local region = window.focus and window.focus.region
	return region and region.layer or "T"
end

local function subText(row, layer)
	if layer == "T" then return string.format(L.TOUCH_SUB, L.TOUCH_SIDE[row.side], row.index) end
	return string.format(L.TOUCH_SUB_LAYER, L.TOUCH_SIDE[row.side], row.index, UI.ROLE[UI.Bindings.LAYER_ROLE[layer]].word)
end

local function fillRow(row)
	local layer = shownLayer()
	local entry = entryOf(row.side, row.index, layer)
	row.name:SetText(entry and entry.name or L.TOUCH_EMPTY)
	row.name:SetFontObject(entry and not UI.EntryOff(entry) and "GameFontNormal" or "GameFontDisable")
	row.sub:SetText(subText(row, layer))
	row.marker:SetRole(nil)
	for _, cell in ipairs(row.cells) do
		local cellEntry = entryOf(row.side, row.index, cell.layer)
		cell.icon:ClearAllPoints()
		cell.icon:SetPoint("TOPLEFT", 3, -3)
		cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
		cell.icon:SetTexture(cellEntry and cellEntry.icon or nil)
		cell.icon:SetDesaturated(UI.EntryOff(cellEntry) ~= nil)
		cell.icon:SetShown(cellEntry ~= nil)
		ns.SlotView.HealerBadge(cell, not not (cellEntry and cellEntry.healer))
	end
end

local function cellTip(cell)
	local row = cell.row
	local entry = entryOf(row.side, row.index, cell.layer)
	local lines = { subText(row, cell.layer) }
	local _, total, full = slots()
	if full and not entry then lines[#lines + 1] = string.format(L.TOUCH_FULL, total) end
	lines[#lines + 1] = UI.EntryOff(entry)
	if entry and entry.healer then lines[#lines + 1] = L.HEALER_ON end
	return { title = entry and entry.name or L.TOUCH_EMPTY, lines = lines, actions = { { "PAD1", L.CHOOSE_ACTION }, { "PAD3", L.CLEAR_SLOT } }, side = row.side }
end

-- The screen with both bars, each by its own settings: aspect from UIParent, buttons at their real relative size and
-- place, the shown layer's icons on them, the focused one lit; greyed while the bars are off or never shown.
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
	local layer = heldLayer or "T"
	for _, side in ipairs(SIDES) do
		local s = sideConfig(c, side)
		for _, list in pairs(buttons[side]) do for _, button in ipairs(list) do button:Hide() end end
		local circle = s.shape == "circle"
		local list = buttons[side][circle and "circle" or "square"]
		for i = 1, s.count do
			local bx, by, size = buttonRect(side, i, s, width, height)
			local button = list[i] or UI.Bindings.SlotCell(preview, 10, circle)
			list[i] = button
			local px = math.max(size * scale, 6)
			button:SetSize(px, px)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", preview, "TOPLEFT", bx * scale, -by * scale)
			button:SetAlpha(live and s.alpha or 0.3)
			local entry = entryOf(side, i, layer)
			button.icon:SetAllPoints()
			button.icon:SetTexture(entry and entry.icon or nil)
			button.icon:SetDesaturated(UI.EntryOff(entry) ~= nil)
			button.icon:SetShown(entry ~= nil)
			UI.Bindings.SetCellFocus(button, false)
			button:Show()
			preview.boxes[codeOf(side, i)] = { x + bx * scale, y + by * scale, x + bx * scale + px, y + by * scale + px }
		end
	end
end

local function drawFocus()
	local region = window.focus and window.focus.region
	local focusRow = region and region.row
	for _, side in ipairs(SIDES) do
		for _, list in pairs(buttons[side]) do
			for i, button in ipairs(list) do UI.Bindings.SetCellFocus(button, focusRow and focusRow.side == side and focusRow.index == i) end
		end
	end
	for _, row in pairs(rows) do if row:IsShown() then fillRow(row) end end
	UI.Bindings.LightLayerHeaders(headers, shownLayer(), region and region.layer and focusRow.side)
	UI.Bindings.FocusLine(curve, preview, rows, focusRow and focusRow:IsShown() and focusRow or nil)
	if not UI.DialogShown() then window:SetPrompts(T.Prompts(region)) end
end

local function setSetting(key, value)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	return (ns.Touch.SetSide(settingSide, key, value)) and true or false
end

-- One step of a setting on the chosen side (a choice: the option that way). False at its end (past Touch's limits,
-- the last option, or refused by Set, quietly): nothing changes.
local function stepBy(spec, step, wrap)
	local c = config()
	if not c then return false end
	local key, inc, options = spec[1], spec[2], spec.options
	local current = sideConfig(c, settingSide)[key]
	if options then
		local index = (current == options[2] and 2 or 1) + step
		if wrap then index = (index - 1) % #options + 1 end
		if index < 1 or index > #options then return false end
		return setSetting(key, options[index])
	end
	local value = current + step * inc
	-- Opacity in tenths, so repeated steps never drift.
	if inc < 1 then value = math.floor(value * 10 + 0.5) / 10 end
	local limit = ns.Touch.LIMITS[key]
	if limit and (value < limit[1] or value > limit[2]) then return false end
	return setSetting(key, value)
end

local function valueText(key, value)
	if key == "alpha" then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
	return tostring(value)
end

-- One setting line: the label on the left, its control CONTROL_X in (a slider within Touch's limits, a choice's
-- dropdown, or Empty buttons' checkbox).
local function settingRow(y, label)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(STEPPER_W, STEPPER_H)
	UI.At(row, window, UI.Bindings.GEO.WIDTH / 2 - STEPPER_W / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 10, 0)
	row.label:SetText(label)
	return row
end

local function newStepper(spec, i)
	local stepper = settingRow(STEPPER_TOP + (i - 1) * STEPPER_PITCH, L.TOUCH_SETTINGS[spec[1]])
	stepper.spec = spec
	local key = spec[1]
	if key == "showEmpty" then
		stepper.control = UI.Checkbox(stepper, function() stepBy(spec, 1, true) end)
	elseif spec.options then
		stepper.control = UI.Dropdown(stepper, CHOICE_W, function(step, wrap) stepBy(spec, step, wrap) end)
	else
		local limit = ns.Touch.LIMITS[key]
		stepper.control = UI.Slider(stepper, SLIDER_W, limit[1], limit[2], spec[2], function(step) stepBy(spec, step) end, function(value) setSetting(key, value) end)
	end
	stepper.control:SetPoint("LEFT", stepper, "LEFT", CONTROL_X, 0)
	return stepper
end

-- One step through Show's options or the sides; false past an end, round with wrap (A).
local function stepList(list, current, step, wrap)
	local index = 1
	for i, id in ipairs(list) do if id == current then index = i end end
	return list[wrap and (index + step - 1) % #list + 1 or index + step]
end

local function stepShow(step, wrap)
	local c = config()
	local id = c and stepList(SHOW, c.show, step, wrap)
	if not id then return false end
	set("show", id)
end

local function stepSide(step, wrap)
	local id = stepList(SIDES, settingSide, step, wrap)
	if not id then return false end
	settingSide = id
	window:Refresh()
end

-- A dropdown's text from a list, its steppers grey at the ends.
local function showList(drop, list, current, labels)
	for i, id in ipairs(list) do if id == current then drop:Set(labels[id], i == 1, i == #list) end end
end

local function refresh()
	local c = config()
	if not c then return end
	local B, geo = UI.Bindings, UI.Bindings.GEO
	onRow.control:Set(c.enabled)
	showList(showRow.control, SHOW, c.show, L.TOUCH_SHOW)
	showList(sideRow.control, SIDES, settingSide, L.TOUCH_SIDE)
	local used, total, full = slots()
	counter:SetText(used and string.format(L.TOUCH_SLOTS, used, total) or "")
	counter:SetFontObject(full and "GameFontRedSmall" or "GameFontHighlightSmall")
	B.FillLayerHeaders(headers, ns.Layout.Roles())
	drawPreview(c)

	-- Both columns start level under their layer headers, the longer one centred in the area. Twelve buttons a side
	-- don't fit the content box at the row pitch: the rows close up to fit, never under their own height.
	for _, row in pairs(rows) do row:Hide() end
	local nodes = {}
	local counts = { left = sideConfig(c, "left").count, right = sideConfig(c, "right").count }
	local most = math.max(counts.left, counts.right)
	local pitch = math.max(geo.ROW_H, math.min(geo.ROW_PITCH, math.floor((geo.AREA_BOTTOM - geo.AREA_TOP - geo.BAND - geo.ROW_H) / math.max(1, most - 1))))
	local block = geo.BAND + most * pitch - (pitch - geo.ROW_H)
	local headerTop = geo.AREA_TOP + math.floor((geo.AREA_BOTTOM - geo.AREA_TOP - block) / 2)
	for _, side in ipairs(SIDES) do
		local isLeft = side == "left"
		B.PlaceLayerHeaders(headers, isLeft, headerTop)
		for i = 1, counts[side] do
			local code = codeOf(side, i)
			local row = rows[code] or newRow(side, i)
			rows[code] = row
			B.PlaceRow(row, isLeft, headerTop + geo.BAND + (i - 1) * pitch)
			for j, cell in ipairs(row.cells) do
				cell:ClearAllPoints()
				cell:SetPoint("TOPLEFT", row, "TOPLEFT", (isLeft and 0 or row:GetWidth() - geo.CELLS_W) + (j - 1) * geo.CELL_PITCH, -(geo.ROW_H - CELL) / 2)
				nodes[#nodes + 1] = UI.Node(window, cell, function() pick(cell) end, { onFocus = function(on) B.SetCellFocus(cell, on) end, tip = function() return cellTip(cell) end })
				B.SetCellFocus(cell, window.focus and window.focus.region == cell)
			end
		end
	end
	nodes[#nodes + 1] = UI.Node(window, onRow, function() set("enabled", not c.enabled) end, {
		cursorX = 0, onFocus = function(on) onRow.wash:SetShown(on) end, tip = { title = L.TOUCH_ON, lines = { L.TOUCH_ONOFF_TIP }, side = "right" },
	})
	nodes[#nodes + 1] = UI.Node(window, showRow, function() stepShow(1, true) end, {
		cursorX = 0, noSide = true, onDir = stepShow, onFocus = function(on) showRow.wash:SetShown(on) showRow.control:SetFocused(on) end,
		tip = { title = L.TOUCH_SHOW_LABEL, lines = { L.TOUCH_SHOW_TIP }, side = "right" },
	})
	nodes[#nodes + 1] = UI.Node(window, sideRow, function() stepSide(1, true) end, {
		cursorX = 0, noSide = true, onDir = stepSide, onFocus = function(on) sideRow.wash:SetShown(on) sideRow.control:SetFocused(on) end,
		tip = { title = L.TOUCH_SIDE_LABEL, lines = { L.TOUCH_SIDE_TIP }, side = "right" },
	})
	local s = sideConfig(c, settingSide)
	for _, stepper in ipairs(steppers) do
		local spec, control = stepper.spec, stepper.control
		local key, choice = spec[1], spec.options
		local tip = { title = L.TOUCH_SETTINGS[key], lines = { L.STEPPER_TIP }, actions = { { "PADDLEFT", "-" }, { "PADDRIGHT", "+" } }, side = "right" }
		if key == "showEmpty" then
			control:Set(s[key])
		elseif choice then
			showList(control, choice, s[key], L.TOUCH_CHOICES[key])
		else
			control:Set(s[key], valueText(key, s[key]))
		end
		if choice then tip.lines, tip.actions = { L.CHOICE_TIP }, nil end
		nodes[#nodes + 1] = UI.Node(window, stepper, function() if choice then stepBy(spec, 1, true) end end, {
			cursorX = 0, noSide = true, onDir = function(step) return stepBy(spec, step) end, tip = tip,
			onFocus = function(on)
				stepper.wash:SetShown(on)
				if control.SetFocused then control:SetFocused(on) end
			end,
		})
	end
	window:SetNodes(nodes)
	drawFocus()
end

-- Touch's own More entry: both bars' settings back to the defaults, after a confirm.
local function resetTouch()
	UI.Dialog():Open(window, { text = L.TOUCH_RESET_TEXT, buttons = { L.RESET, L.CANCEL }, on1 = function()
		local _, err = ns.Touch.Reset()
		if err then ns.log(err) end
	end })
end

-- More's Healer mode row for a focused cell, first (UI.Bindings.HealerMore).
local function healerMore(cell)
	local row = cell.row
	local entry = entryOf(row.side, row.index, cell.layer)
	return UI.Bindings.HealerMore(entry, function()
		local _, err = ns.Touch.SetHealer(row.side, row.index, cell.layer, not (entry and entry.healer))
		if err then ns.log(err) end
	end)
end

-- Holding modifiers shows their layer in the rows and on the preview.
local function holdTick()
	local role = UI.HoldResult(UI.HeldButtons(), ns.Layout.Roles())
	local layer = role and UI.Bindings.ROLE_LAYER[role]
	if layer == heldLayer then return end
	heldLayer = layer
	local c = config()
	if c then drawPreview(c) end
	drawFocus()
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.touch then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	UI.Bindings.Boxes(window, true)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(L.TOUCH_TITLE)
	-- The header: the slot counter, the hint under it. Nothing near the right edge, where the side tabs and the close
	-- button are.
	counter = UI.Text(window, "GameFontHighlightSmall", 24, 32)
	UI.Text(window, "GameFontDisableSmall", 24, 58, L.TOUCH_HINT)
	window.counter = counter
	headers = UI.Bindings.NewLayerHeaders(window)

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
	onRow = settingRow(ON_TOP, L.TOUCH_ON)
	onRow.control = UI.Checkbox(onRow, function() local c = config() if c then set("enabled", not c.enabled) end end)
	onRow.control:SetPoint("LEFT", onRow, "LEFT", CONTROL_X, 0)
	showRow = settingRow(ON_TOP + STEPPER_PITCH, L.TOUCH_SHOW_LABEL)
	showRow.control = UI.Dropdown(showRow, SIDE_W, stepShow)
	showRow.control:SetPoint("LEFT", showRow, "LEFT", CONTROL_X, 0)
	sideRow = settingRow(SIDE_TOP, L.TOUCH_SIDE_LABEL)
	sideRow.control = UI.Dropdown(sideRow, SIDE_W, stepSide)
	sideRow.control:SetPoint("LEFT", sideRow, "LEFT", CONTROL_X, 0)
	for i, spec in ipairs(SETTINGS) do steppers[i] = newStepper(spec, i) end

	window.OnRefresh = refresh
	window.OnFocusChanged = drawFocus
	window.OnHoldTick = holdTick
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		local region = window.focus and window.focus.region
		if key == "PAD3" and region and region.layer then
			clear(region)
			return true
		end
		if key == "PAD4" then
			local entries = { { id = "touchreset", name = L.TOUCH_RESET, detail = L.TOUCH_RESET_TIP, run = resetTouch } }
			if region and region.layer then table.insert(entries, 1, healerMore(region)) end
			UI.OpenMore(window, entries)
			return true
		end
	end
	window.OnClosed = function()
		heldLayer = nil
		UI.HideTooltip()
	end
end

-- The footer for what is focused: a cell, a setting (left/right change it) or a header control.
function T.Prompts(region)
	local spec = region and region.spec
	if spec then
		local options, labels = spec.options, L.TOUCH_CHOICES[spec[1]]
		local less, more = options and labels[options[1]] or L.STEP_LESS, options and labels[options[2]] or L.STEP_MORE
		return { { "PADDLEFT", less }, { "PADDRIGHT", more }, { "PAD4", L.MORE }, UI.TabPrompt("touch", -1), { "PAD2", L.CLOSE } }
	end
	if not (region and region.layer) then return { { "PAD1", L.SELECT }, { "PAD4", L.MORE }, UI.TabPrompt("touch", -1), { "PAD2", L.CLOSE } } end
	return { { "PAD1", L.SELECT }, { "PAD3", L.CLEAR_SLOT }, { "PAD4", L.MORE }, UI.TabPrompt("touch", -1), { "PAD2", L.CLOSE } }
end

function T.Open()
	if not config() then return ns.log(L.TOUCH_NO_CHARACTER) end
	if not window then build() end
	UI.Show(window)
end

-- A side tab after Bindings (Bindings, Touch, Keyboard, Rings, of those loaded); L1/R1 step through them.
UI.AddTab({ "Interface\\Icons\\Spell_Holy_LayOnHands", L.TOUCH_TAB, function() T.Open() end, touch = true, order = 2, prompt = L.TOUCH })

local function redraw() if window and window:IsShown() then window:Refresh() end end
ns.On("FCT_LAYOUT_CHANGED", redraw)
ns.On("UI_SCALE_CHANGED", redraw)
ns.On("DISPLAY_SIZE_CHANGED", redraw)
