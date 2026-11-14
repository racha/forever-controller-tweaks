-- Forever Controller Tweaks "Touch bars" window: the two on-screen bars Touch.lua draws for touch screens (Steam
-- Link), in Bindings' design and window. Each bar's buttons are rows at the window's edges with four layer cells like
-- Bindings (top, left, right, bottom bar, under the same layer headers): A opens the action picker on a cell, X clears,
-- Y undoes. The centre shows the screen with both bars at their real relative size, count and place (each side by
-- its own settings), the held modifier's layer icons on them, and the focused row's gold line landing on its button.
-- Header: On/Off and when the bars show (global), and the slot counter. Under the preview: a Left / Right switch and
-- that side's settings as a vertical list (up/down move, left/right change one; Shape and Empty buttons are two-option
-- segments, shown once Touch keeps them per side).
-- Everything goes through ns.Touch: Config (per side under sides.left / sides.right when Touch keeps them so),
-- Set / SetSide, LIMITS, Entry / SetEntry (with a layer when Touch takes layers), Layer, SlotsUsed;
-- FCT_LAYOUT_CHANGED "touch". A Touch build without sides or layers gets one shared settings list and the top-bar
-- cell only.
local ns = ForeverControllerTweaks
local UI = ns.UI
local L = UI.L

local T = {}
UI.TouchTab = T

local SIDES = { "left", "right" }
local SHOW = { "always", "gamepad", "combat", "never" }
-- { Touch setting, step } (the limits are Touch.LIMITS), or { Touch setting, options = left and right segment }.
local SETTINGS = {
	{ "count", 1 }, { "size", 4 }, { "gap", 2 }, { "inset", 4 }, { "offsetY", 10 }, { "alpha", 0.1 },
	{ "shape", options = { "circle", "square" } }, { "showEmpty", options = { false, true } },
}
-- The box the screen preview fits in (window units, 12 inside the middle content box, 400-800), its corner radius and
-- outline tone; the side switch and the settings list under it, all in that box down to 610.
local BOX_X, BOX_Y, BOX_W, BOX_H, CORNER = 412, 96, 376, 216, 14
local OUTLINE = { 138 / 255, 106 / 255, 60 / 255 }
local SIDE_TOP, SIDE_W = 324, 120
local STEPPER_W, STEPPER_H, STEPPER_TOP, STEPPER_PITCH, ARROW, CHOICE_W = 280, 28, 362, 30, 26, 70
local CELL, ONOFF_W, SHOW_W, SHOW_GAP, SHOW_LABEL_W = 34, 64, 110, 28, 56

local window, preview, curve, outline, onoff, show, sideSwitch, counter, headers
local rows, steppers = {}, {}
-- The preview's buttons per side and shape (a cell's mask is fixed when it is made).
local buttons = { left = { circle = {}, square = {} }, right = { circle = {}, square = {} } }
local settingSide, heldLayer = "left", nil

-- Touch's settings for this character, defaults filled in; nil before the character is known.
local function config() return ns.Touch and ns.Touch.Config() end

-- One side's settings: per side when Touch keeps them so, else the shared ones.
local function sideConfig(c, side) return c.sides and c.sides[side] or c end

-- Touch takes a layer per button (L, R, B besides the top bar).
local function layered() return ns.Touch and ns.Touch.Layer ~= nil end

local function entryOf(side, i, layer)
	if not ns.Touch or layer ~= "T" and not layered() then return end
	return ns.Touch.Entry(side, i, layer)
end

local function set(key, value)
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
	local _, err = ns.Touch.Set(key, value)
	if err then ns.log(err) end
end

local function setSide(side, key, value)
	if ns.Touch.SetSide then return ns.Touch.SetSide(side, key, value) end
	return ns.Touch.Set(key, value)
end

-- used, total and whether none is free; nil when Touch doesn't count them.
local function slots()
	if not (ns.Touch and ns.Touch.SlotsUsed) then return end
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

-- A cell is usable on the top bar always, on the other layers when Touch takes layers.
local function usable(cell) return cell.layer == "T" or layered() end

local function pick(cell)
	if InCombatLockdown() or not usable(cell) then return end
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
	local row = cell.row
	UI.ActionPicker.Open({ window = window, cell = cell, touch = { side = row.side, index = row.index, layer = cell.layer } })
end

local function clear(cell)
	if not (ns.Touch and usable(cell)) then return end
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
		cell.bg:SetAlpha(usable(cell) and 1 or 0.35)
	end
end

local function cellTip(cell)
	local row = cell.row
	local entry = entryOf(row.side, row.index, cell.layer)
	local lines = { subText(row, cell.layer) }
	if not usable(cell) then
		lines[#lines + 1] = L.TOUCH_LAYERS_LATER
		return { title = L.TOUCH_EMPTY, lines = lines, side = row.side }
	end
	local _, total, full = slots()
	if full and not entry then lines[#lines + 1] = string.format(L.TOUCH_FULL, total) end
	lines[#lines + 1] = UI.EntryOff(entry)
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
	return (setSide(settingSide, key, value)) and true or false
end

-- One step of a setting on the chosen side (a choice: the option that way). False at its end (past Touch's limits,
-- the last option, or refused by Set, quietly), so left/right moves the focus on instead of sticking there.
local function stepBy(spec, step)
	local c = config()
	if not c then return false end
	local key, inc, options = spec[1], spec[2], spec.options
	local current = sideConfig(c, settingSide)[key]
	if options then
		local index = (current == options[2] and 2 or 1) + step
		if index < 1 or index > #options then return false end
		return setSetting(key, options[index])
	end
	local value = current + step * inc
	-- Opacity in tenths, so repeated steps never drift.
	if inc < 1 then value = math.floor(value * 10 + 0.5) / 10 end
	local limit = ns.Touch.LIMITS and ns.Touch.LIMITS[key]
	if limit and (value < limit[1] or value > limit[2]) then return false end
	return setSetting(key, value)
end

local function valueText(key, value)
	if key == "alpha" then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
	return tostring(value)
end

-- One setting line: the label on the left, then the value between small D-pad left/right hints (clickable), or a
-- choice's two segments.
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
	stepper.spec = spec
	if spec.options then
		local labels, specs = L.TOUCH_CHOICES[spec[1]], {}
		for j, option in ipairs(spec.options) do specs[j] = { option, labels[option] } end
		stepper.choice = UI.Segments(stepper, specs, STEPPER_W - 2 * CHOICE_W - 2, 1, CHOICE_W, function(id) setSetting(spec[1], id) end)
		return stepper
	end
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
	return stepper
end

local function refresh()
	local c = config()
	if not c then return end
	local B, geo = UI.Bindings, UI.Bindings.GEO
	onoff:Select(c.enabled and "on" or "off")
	show:Select(c.show)
	sideSwitch:Select(settingSide)
	for _, segment in ipairs(sideSwitch) do segment:SetShown(c.sides ~= nil) end
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
	for _, segment in ipairs(onoff) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = segment.text, lines = { L.TOUCH_ONOFF_TIP }, side = "below" } }) end
	for _, segment in ipairs(show) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = segment.text, lines = { L.TOUCH_SHOW_TIP }, side = "below" } }) end
	if c.sides then
		for _, segment in ipairs(sideSwitch) do nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = { title = segment.text, lines = { L.TOUCH_SIDE_TIP }, side = "right" } }) end
	end
	local s = sideConfig(c, settingSide)
	for _, stepper in ipairs(steppers) do
		local spec, choice = stepper.spec, stepper.choice
		local key = spec[1]
		-- A choice shows once Touch keeps it per side.
		local shown = not choice or c.sides ~= nil and s[key] ~= nil
		stepper:SetShown(shown)
		if shown then
			local tip = { title = L.TOUCH_SETTINGS[key], lines = { L.STEPPER_TIP }, actions = { { "PADDLEFT", "-" }, { "PADDRIGHT", "+" } }, side = "right" }
			if choice then
				choice:Select(s[key])
				tip.lines, tip.actions = { L.CHOICE_TIP }, nil
			else
				stepper.value:SetText(valueText(key, s[key]))
			end
			nodes[#nodes + 1] = UI.Node(window, stepper, function() end, {
				cursorX = 0, noSide = true, onDir = function(step) return stepBy(spec, step) end, onFocus = function(on) stepper.wash:SetShown(on) end, tip = tip,
			})
		end
	end
	window:SetNodes(nodes)
	drawFocus()
end

-- Touch's own More entry (when Touch has Reset): both bars' settings back to the defaults, after a confirm.
local function resetTouch()
	UI.Dialog():Open(window, { text = L.TOUCH_RESET_TEXT, buttons = { L.RESET, L.CANCEL }, on1 = function()
		local _, err = ns.Touch.Reset()
		if err then ns.log(err) end
	end })
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
	-- One header line from the left: On/Off, then "Show" and its segments, then the slot counter; the hint under it.
	-- Nothing near the right edge, where the side tabs and the close button are.
	onoff = UI.Segments(window, { { "on", L.TOUCH_ON }, { "off", L.TOUCH_OFF } }, 24, 25, ONOFF_W, function(id) set("enabled", id == "on") end)
	local showX = 24 + 2 * ONOFF_W + SHOW_GAP
	local showLabel = UI.Text(window, "GameFontNormal", showX, 31, L.TOUCH_SHOW_LABEL)
	UI.Text(window, "GameFontDisableSmall", 24, 58, L.TOUCH_HINT)
	local specs = {}
	for i, id in ipairs(SHOW) do specs[i] = { id, L.TOUCH_SHOW[id] } end
	show = UI.Segments(window, specs, showX + SHOW_LABEL_W, 25, SHOW_W, function(id) set("show", id) end)
	showLabel:SetWidth(SHOW_LABEL_W - 8)
	counter = UI.Text(window, "GameFontHighlightSmall", showX + SHOW_LABEL_W + #SHOW * SHOW_W + 18, 32)
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
	sideSwitch = UI.Segments(window, { { "left", L.TOUCH_SIDE.left }, { "right", L.TOUCH_SIDE.right } }, geo.WIDTH / 2 - SIDE_W, SIDE_TOP, SIDE_W, function(id)
		settingSide = id
		window:Refresh()
	end)
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
			UI.OpenMore(window, ns.Touch.Reset and { { id = "touchreset", name = L.TOUCH_RESET, detail = L.TOUCH_RESET_TIP, run = resetTouch } })
			return true
		end
	end
	window.OnClosed = function()
		heldLayer = nil
		UI.HideTooltip()
	end
end

-- The footer for what is focused: a cell, a setting (left/right change it) or a header segment.
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
	if not ns.Touch then return ns.log(L.TOUCH_MISSING) end
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
