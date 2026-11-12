-- Forever Controller Tweaks "Bindings" window: the controller drawing centred, one row per control in two columns at the
-- window's edges, ordered by where the control sits on the pad. A row holds the four crossbar layers (top, left, right, bottom bar) of the
-- shown page, the control's glyph, and what it does on the shown layer. Only the focused row draws a curve into the
-- drawing, to its control, which lights up. A D-pad or face row's cell opens the action picker (an entry the router
-- carries shows instead of the storage slot's action); a modifier row's opens Modifiers; a game default explains itself.
local _, ns = ...
local UI = ns.UI
local L, Layout = UI.L, ns.Layout

local B = {}
UI.Bindings = B

local CORE_CTX = Enum.BindingContext and Enum.BindingContext.GamepadModeInGameCore or 9
local MAX_PAGES = 10
local page = 1

-- Standard crossbar pages (the ones with pageable bars).
local function pageCount()
	local util = GamepadActionBarBindingUtil
	local n = 1
	while util and util.IsStandardGamepadPageNum and n < MAX_PAGES and util.IsStandardGamepadPageNum(n + 1) do n = n + 1 end
	return n
end

-- The stance / pet override bars replace one layer on a page (CVars GamepadStanceBarOverride and
-- GamepadPossessBarOverride, read only; Enum names like "Page1LeftBar"). Returns a note for the current page.
local OVERRIDE_CVARS = { { "GamepadStanceBarOverride", L.OVERRIDE_BARS.GamepadStanceBarOverride }, { "GamepadPossessBarOverride", L.OVERRIDE_BARS.GamepadPossessBarOverride } }

local function overrideNote()
	for _, spec in ipairs(OVERRIDE_CVARS) do
		local enum, value = Enum[spec[1]], tonumber(GetCVar(spec[1]) or "")
		for name, v in pairs(enum or {}) do
			if v == value and name ~= "None" then
				local onPage, layer = name:match("^Page(%d+)(%u%l+)Bar$")
				if not onPage then layer = name:match("(%u%l+)Bar$") end
				if layer and (not onPage or tonumber(onPage) == page) then return string.format(L.OVERRIDE_NOTE, spec[2], layer:upper()) end
			end
		end
	end
end
local LAYERS = { "T", "L", "R", "B" }
local LAYER_ROLE = { T = "top", L = "leftmod", R = "rightmod", B = "bottom" }
local ROLE_LAYER = { leftmod = "L", rightmod = "R", bottom = "B" }
local LAYER_INDEX = { T = 1, L = 2, R = 3, B = 4 }

-- Geometry (window units). Cells 34 (circles 32) on a 38 pitch; rows 38 tall on a 42 pitch at the window edges, a
-- layer header over each column's cells; both columns start level, the longer one centred in the area; the drawing
-- at 1.2 between them.
local WIDTH, HEIGHT = 1200, 640
local CELL, CIRCLE, CELL_PITCH, ROW_H, ROW_PITCH = 34, 32, 38, 38, 42
local EDGE, GLYPH_X, MARKER_X, NAME_X, NAME_W = 16, 185, 212, 222, 132
local ROW_W, CELLS_W = NAME_X + NAME_W - EDGE, 3 * CELL_PITCH + CELL
local AREA_TOP, AREA_BOTTOM, RULE_END = 66, 630, 392
local HEADER_H, HEADER_GAP = 50, 4
local DRAWING_SCALE = 1.2
local DRAWING_PLACE = { (WIDTH - 400 * DRAWING_SCALE) / 2, (AREA_TOP + AREA_BOTTOM) / 2 - 150 * DRAWING_SCALE, DRAWING_SCALE }
-- Which column each control's row is in, and the tie order; rows run top to bottom by where the control sits on
-- the drawing. Only controls the addon can set are listed: the D-pad and face buttons (cells) and the modifiers (they
-- explain the layer headers and open Modifiers); the game keeps L3, R3 and the centre buttons to itself.
local LEFT_ORDER = { "L1", "L2", "DU", "DR", "DD", "DL", "P2", "P4" }
local RIGHT_ORDER = { "R1", "R2", "FT", "FR", "FB", "FL", "P1", "P3" }
local DRAWN = { "L2", "R2", "L1", "R1", "FT", "FL", "FR", "FB", "L3", "R3", "SEL", "START", "SOCIAL", "SYSTEM" }
-- The focused row: its rule and curve in native gold; every other rule in the drawing's line tone, faint.
local GOLD, RULE_TONE = { 1, 210 / 255, 0 }, { 160 / 255, 124 / 255, 69 / 255 }
-- Slot in a bar when the core binding context can't be read (D-pad 1-4, face 5-8, as Face.lua assumes).
local ASSUMED_SLOT = { PADDLEFT = 1, PADDUP = 2, PADDRIGHT = 3, PADDDOWN = 4, PAD3 = 5, PAD4 = 6, PAD2 = 7, PAD1 = 8 }
local FACE_ACTION_NAME = L.FACE_ACTION_NAMES
-- The top bar's reserved face buttons (Face.lua's ACTION_SLOT) and how their icons sit in the circle slot.
local ACTION_SLOT = { interact = 5, inspect = 6, back = 7, jump = 8 }
local SPECIAL_INSET = { back = -9, inspect = 3.5 }
local SPECIAL_FALLBACK = { jump = "gamepad-ability-icon-jump", back = "128-redbutton-exit", inspect = "gamepad-actionbar-circleslot-permabound" }

local window, drawing, curve
local rows, heldLayer = {}, nil
local tabs = { left = {}, right = {} }

local function slotInBar(key)
	local ok, action = pcall(GetBindingAction, key, nil, CORE_CTX)
	return tonumber((ok and action or ""):match("^GAMEPADACTIONBUTTON(%d)$")) or ASSUMED_SLOT[key]
end

-- Storage slot of a layer cell, nil for the reserved top-bar face slots or without the gamepad action bars.
local function storageSlot(code, layer)
	local util = GamepadActionBarBindingUtil
	if not util then return end

	local constants = Constants.GamepadActionBarConstants
	local perBar = constants and constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
	local barIndex = ({ T = 1, L = 2, R = 3, B = 4 })[layer]
	local ok, slot = pcall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, page, (barIndex - 1) * perBar + slotInBar(UI.KEY[code]))
	return ok and slot or nil
end

-- C_ActionBar's calls: HasAction, GetActionText and GetActionTexture are only globals with deprecation fallbacks on.
local ActionBar = C_ActionBar or {}

local function hasAction(slot) return slot and ActionBar.HasAction and ActionBar.HasAction(slot) end

local function actionName(slot)
	if not hasAction(slot) then return end

	local kind, id = GetActionInfo(slot)
	local name
	if kind == "spell" then name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or GetSpellInfo and GetSpellInfo(id) end
	if kind == "item" then name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or GetItemInfo and GetItemInfo(id) end
	if kind == "macro" and GetMacroInfo then name = GetMacroInfo(id) end
	if kind == "flyout" and GetFlyoutInfo then name = GetFlyoutInfo(id) end
	if kind == "summonmount" and C_MountJournal and C_MountJournal.GetMountInfoByID then name = C_MountJournal.GetMountInfoByID(id) end
	if kind == "equipmentset" then name = id end
	-- Never the raw kind ("flyout", "companion"): a generic word when the game gives no name.
	return name or ActionBar.GetActionText and ActionBar.GetActionText(slot) or L.UNNAMED_ACTION
end

-- The icon Blizzard's top-bar button shows for a face action (read only), else a fallback atlas.
local function specialIcon(texture, action)
	local bars = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit and GamepadMainActionBarFrame.PageUnit.actionBars
	local bar = bars and bars.topBar
	local button = bar and bar.actionButtons and bar.actionButtons[ACTION_SLOT[action]]
	local source = button and button.SpecialActionIcon
	local atlas = source and source:GetAtlas()
	if atlas then return texture:SetAtlas(atlas) end

	local file = source and source:GetTexture()
	if file then
		texture:SetTexture(file)
		return texture:SetTexCoord(source:GetTexCoord())
	end
	texture:SetTexCoord(0, 1, 0, 1)
	if SPECIAL_FALLBACK[action] then texture:SetAtlas(SPECIAL_FALLBACK[action]) else texture:SetTexture("Interface\\Cursor\\Interact") end
end

B.SpecialIcon, B.SPECIAL_INSET, B.ACTION_NAME = specialIcon, SPECIAL_INSET, FACE_ACTION_NAME

local function layerLine(code, layer)
	local names = {}
	for _, phys in ipairs(UI.Combo(LAYER_ROLE[layer], Layout.Roles())) do names[#names + 1] = UI.Name(phys) end
	names[#names + 1] = UI.Name(code)
	return string.format(L.SHOWN_ACTION, UI.ROLE[LAYER_ROLE[layer]].word, table.concat(names, " + "))
end

-- A slot cell's action name, nil when nothing is bound.
local function boundName(cell)
	if cell.entry then return cell.entry.name end
	if cell.reserved then return FACE_ACTION_NAME[cell.action] end
	return actionName(cell.slot)
end

local function cellTip(cell)
	local kind = cell.reserved and L.FACE_SLOT or L.CROSSBAR_SLOT
	local choose = cell.slot and GetCursorInfo() and L.PLACE_HELD or L.CHOOSE_ACTION
	return { title = boundName(cell) or L.EMPTY, lines = { layerLine(cell.code, cell.layer), kind }, actions = { { "PAD1", choose }, { "PAD3", L.CLEAR_SLOT } }, side = cell.row.left and "left" or "right" }
end

local function hideTooltip(cell)
	UI.HideTooltip(cell)
end

-- Assigning: the cursor's pickup goes into the slot (and the slot's old action onto the cursor, as on the native
-- bars); with an empty cursor the slot's action is picked up. Out of combat only, like AssignActionToGamepadStandardSlot.
-- A (or a click) on a cell opens the action picker there; with something on the cursor (a mouse drag from the
-- spellbook or bags) the click places it instead, as on the native bars.
local function selectCell(cell)
	if InCombatLockdown() then return end
	if cell.slot and GetCursorInfo() then return PlaceAction(cell.slot) end
	if not (cell.slot or cell.pos or ns.Face.SetCellEntry) then return end
	UI.ActionPicker.Open({ window = window, cell = cell, code = cell.code, layer = cell.layer, slot = cell.slot, pos = cell.pos, page = page })
end

local function clearCell(cell)
	if cell and cell.layer then UI.ActionPicker.ClearCell(cell) end
end

-- A slot cell's art (Bindings, Touch): the native empty slot, the icon under the slot mask, the focus border.
function B.SlotCell(parent, size, circle)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(size, size)
	cell.size, cell.shape = size, circle and "circleslot" or "squareslot"
	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()
	cell.bg:SetAtlas("gamepad-actionbar-slot-bg-empty")
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.mask = UI.SlotMask(cell, cell.icon, circle, 3)
	cell.border = cell:CreateTexture(nil, "OVERLAY")
	cell.border:SetAllPoints()
	return cell
end

local function newCell(row, code, layer, face)
	local cell = B.SlotCell(row, face and CIRCLE or CELL, face)
	cell.row, cell.code, cell.layer = row, code, layer
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:RegisterForDrag("LeftButton")
	cell:SetScript("OnClick", function(self, button)
		if button == "RightButton" then return clearCell(self) end
		selectCell(self)
	end)
	cell:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() and self.slot then PickupAction(self.slot) end
	end)
	cell:SetScript("OnReceiveDrag", selectCell)
	cell:SetScript("OnLeave", hideTooltip)
	return cell
end

local function setCellFocus(cell, on)
	cell.border:SetAtlas("gamepad-actionbar-" .. cell.shape .. "-border-" .. (on and "selected" or "normal"))
end

B.SetCellFocus = setCellFocus

-- faceAction: the base face slot's action. A routed entry (Face.CellEntry) shows instead of the slot or face action.
-- Every icon stays under the cell's slot mask (circle or square, as on the native bar), whatever path draws it.
local function fillCell(cell, faceAction)
	cell.reserved, cell.action, cell.page = faceAction ~= nil, faceAction, page
	cell.pos = cell.reserved and UI.CODE_POS[cell.code] or nil
	cell.slot = not cell.reserved and storageSlot(cell.code, cell.layer) or nil
	cell.entry = UI.ActionPicker.CellEntry(cell)
	cell.icon:ClearAllPoints()
	cell.icon:SetTexCoord(0, 1, 0, 1)
	if cell.entry then
		cell.icon:SetPoint("TOPLEFT", 3, -3)
		cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
		cell.icon:SetTexture(cell.entry.icon)
		cell.icon:Show()
	elseif cell.reserved then
		local inset = SPECIAL_INSET[faceAction] or 0
		cell.icon:SetPoint("TOPLEFT", inset, -inset)
		cell.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
		specialIcon(cell.icon, faceAction)
		cell.icon:Show()
	else
		cell.icon:SetPoint("TOPLEFT", 3, -3)
		cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
		local texture = hasAction(cell.slot) and ActionBar.GetActionTexture and ActionBar.GetActionTexture(cell.slot)
		cell.icon:SetTexture(texture)
		cell.icon:SetShown(texture)
	end
end


-- A row (Bindings and Modifiers): the glyph, the role bar, then name and subtitle, mirrored in the right column;
-- under it a rule that fades out toward the drawing. Bindings adds four layer cells at the window edge.
function B.NewRow(parent, code)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(ROW_W, ROW_H)
	row.code = code
	row.glyph = UI.Glyph(row, 26, code)
	row.marker = UI.Marker(row, 12)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetWidth(NAME_W)
	row.name:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetWidth(NAME_W)
	row.sub:SetWordWrap(false)
	row.rule = row:CreateTexture(nil, "BACKGROUND")
	row.rule:SetTexture(UI.ART .. "rule.tga")
	row.rule:SetHeight(1.5)
	return row
end

-- A plate over glyph and names: the focus region and click target of a row without cells (modifier rows here, every
-- row in Modifiers).
function B.AddPlate(row, onClick)
	local plate = CreateFrame("Button", nil, row)
	plate:SetSize(NAME_X + NAME_W - GLYPH_X + 17, ROW_H)
	plate.row = row
	plate.wash = plate:CreateTexture(nil, "BACKGROUND")
	plate.wash:SetColorTexture(1, 1, 1, 0.1)
	plate.wash:SetAllPoints()
	plate.wash:Hide()
	plate:SetScript("OnClick", onClick)
	row.plate = plate
	return plate
end

-- Where a row's own content starts, from the window edge: row.inset, or the plate of a row without cells.
function B.Inset(row) return row.inset or row.plate and ROW_W - row.plate:GetWidth() or 0 end

function B.PlaceRow(row, left, top)
	row.left, row.top = left, top
	row:ClearAllPoints()
	UI.At(row, row:GetParent(), left and EDGE or WIDTH - EDGE - ROW_W, top)
	local function x(offset) return left and offset or ROW_W - offset end
	row.glyph:ClearAllPoints()
	row.glyph:SetPoint("CENTER", row, "TOPLEFT", x(GLYPH_X - EDGE), -ROW_H / 2)
	row.marker:ClearAllPoints()
	row.marker:SetPoint("CENTER", row, "TOPLEFT", x(MARKER_X - EDGE), -ROW_H / 2)
	local anchor = left and "LEFT" or "RIGHT"
	row.name:ClearAllPoints()
	row.name:SetPoint(anchor, row, "TOPLEFT", x(NAME_X - EDGE), -ROW_H / 2 + 7)
	row.name:SetJustifyH(anchor)
	row.sub:ClearAllPoints()
	row.sub:SetPoint(anchor, row, "TOPLEFT", x(NAME_X - EDGE), -ROW_H / 2 - 9)
	row.sub:SetJustifyH(anchor)
	-- The rule runs from where the row starts (the window edge, or the plate of a row without cells) to RULE_END,
	-- full under the row and fading toward the drawing.
	row.rule:ClearAllPoints()
	local inset = B.Inset(row)
	row.rule:SetWidth(RULE_END - EDGE - inset)
	if left then row.rule:SetPoint("TOPLEFT", row, "BOTTOMLEFT", inset, 1) else row.rule:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -inset, 1) end
	row.rule:SetTexCoord(left and 0 or 1, left and 1 or 0, 0, 1)
	local plate = row.plate
	if plate then
		plate:ClearAllPoints()
		plate:SetPoint(left and "TOPRIGHT" or "TOPLEFT", row, left and "TOPRIGHT" or "TOPLEFT", 0, 0)
	end
	row:Show()
end

-- The focused row's line: one gold line from the window edge along its rule, on into the curve to its control (one
-- texture, colour and width end to end); every other rule keeps its faint fade.
function B.FocusLine(line, board, rowList, focusRow)
	for _, row in pairs(rowList) do
		row.rule:SetShown(row ~= focusRow)
		row.rule:SetVertexColor(RULE_TONE[1], RULE_TONE[2], RULE_TONE[3], 0.35)
	end
	local y = focusRow and focusRow.top + ROW_H
	local points = focusRow and board:Curve(focusRow.code, focusRow.left and NAME_X + NAME_W or WIDTH - NAME_X - NAME_W, y)
	if not points then return line:Hide() end

	local inset = B.Inset(focusRow)
	table.insert(points, 1, { focusRow.left and EDGE + inset or WIDTH - EDGE - inset, y })
	line:Set(points, GOLD[1], GOLD[2], GOLD[3], 1, 3.5)
end

-- D-pad and face rows get the four layer cells; modifier rows (no assignable cells) a plate that opens Modifiers on
-- that button.
local function newRow(code)
	local face = UI.CODE_POS[code] ~= nil
	local row = B.NewRow(window, code)
	row.face, row.kind, row.cells = face, UI.MOD_CODES[code] and "mod" or "slot", {}
	if row.kind == "mod" then
		B.AddPlate(row, function() UI.Modifiers.Open(code) end)
		return row
	end
	for i, layer in ipairs(LAYERS) do row.cells[i] = newCell(row, code, layer, face) end
	return row
end

local function placeRow(row, left, top)
	B.PlaceRow(row, left, top)
	for i, cell in ipairs(row.cells) do
		local offset = (CELL - cell.size) / 2
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", row, "TOPLEFT", (left and 0 or ROW_W - CELLS_W) + (i - 1) * CELL_PITCH + offset, -(ROW_H - CELL) / 2 - offset)
	end
end

-- The bar a row shows: the held modifier's, else the focused cell's column, else the top bar.
local function shownLayer()
	if heldLayer then return heldLayer end
	local region = window.focus and window.focus.region
	return region and region.layer or "T"
end

local function rowText(row, layer)
	if row.kind == "mod" then
		local role = Layout.Roles()[row.code] or "none"
		return UI.ROLE[role].name or L.NONE, L.MODIFIER, role
	end
	local cell = row.cells[LAYER_INDEX[layer]]
	local word = UI.ROLE[LAYER_ROLE[layer]].word
	return boundName(cell), string.format(cell.reserved and L.FACE_SUB or L.BAR_SUB, word)
end

local function rowTip(row)
	local name = rowText(row, "T")
	return { title = UI.Name(row.code) .. ": " .. (name or L.NONE), lines = { L.MODIFIER_TIP }, actions = { { "PAD1", L.OPEN_MODIFIERS } }, side = row.left and "left" or "right" }
end

-- Names follow the shown layer; the tab of that layer is selected.
local function drawNames()
	local layer = shownLayer()
	for _, row in pairs(rows) do
		if row:IsShown() then
			local name, sub, role = rowText(row, layer)
			row.name:SetText(name or L.NOT_BOUND)
			row.name:SetFontObject(name and "GameFontNormal" or "GameFontDisable")
			row.sub:SetText(sub)
			row.marker:SetRole(role)
		end
	end
	for _, side in pairs(tabs) do
		for i, tab in ipairs(side) do
			local on = LAYERS[i] == layer
			tab.highlight:SetShown(on)
			tab:SetAlpha(on and 1 or 0.55)
		end
	end
end

-- The focused row's line runs into its control, which lights up.
local function drawFocus()
	local focusRow = window.focus and window.focus.region and window.focus.region.row
	drawing:Style(nil, focusRow and { [focusRow.code] = true } or {}, focusRow and focusRow.code, false)
	B.FocusLine(curve, drawing, rows, focusRow)
	drawNames()
end

-- Layer headers over each column's cells, one per cell column (top, left, right, bottom bar; the same order on
-- both sides): the button(s) to hold for that bar as native glyphs, stacked when two ("None" for the top bar), over
-- a role-colour band. The shown layer's header is lit on both sides. A click moves the focus to that column of the
-- focused row.
local function newTab(i)
	local tab = CreateFrame("Button", nil, window)
	tab:SetSize(CELL_PITCH - 2, HEADER_H)
	tab.highlight = tab:CreateTexture(nil, "BACKGROUND")
	tab.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	tab.highlight:SetBlendMode("ADD")
	tab.highlight:SetAllPoints()
	tab.none = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tab.none:SetPoint("CENTER", 0, 3)
	tab.none:SetText(L.NONE)
	tab.glyphs = { UI.Glyph(tab, 16), UI.Glyph(tab, 16) }
	tab.plus = tab:CreateTexture(nil, "ARTWORK")
	tab.plus:SetAtlas("gamepad-symbols-plus")
	tab.plus:SetSize(8, 8)
	tab.plus:SetPoint("CENTER", tab, "TOP", 0, -22)
	tab.band = tab:CreateTexture(nil, "ARTWORK")
	tab.band:SetSize(CELL - 6, 3)
	tab.band:SetPoint("BOTTOM", 0, 2)
	tab:SetScript("OnClick", function()
		local region = window.focus and window.focus.region
		local row = region and region.row
		if not (row and row.cells[i]) then return end
		for _, node in ipairs(window.nodes) do if node.region == row.cells[i] then window:Focus(node) end end
	end)
	return tab
end

local function fillTab(tab, layer, roles)
	local role = LAYER_ROLE[layer]
	tab.band:SetColorTexture(UI.RoleRGB(role))
	local codes = UI.Combo(role, roles)
	local a, b = tab.glyphs[1], tab.glyphs[2]
	a:ClearAllPoints()
	if #codes == 1 then
		a:SetSize(22, 22)
		a:SetPoint("CENTER", tab, "TOP", 0, -22)
	else
		a:SetSize(16, 16)
		a:SetPoint("CENTER", tab, "TOP", 0, -10)
	end
	b:SetPoint("CENTER", tab, "TOP", 0, -34)
	a:SetCode(codes[1])
	b:SetCode(codes[2])
	a:SetShown(#codes > 0)
	b:SetShown(#codes > 1)
	tab.plus:SetShown(#codes > 1)
	tab.none:SetShown(#codes == 0)
end

local function build()
	window = UI.NewWindow(WIDTH, HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, 1)
	window.device = UI.Text(window, "GameFontHighlight", 24, 30)
	window.sub = UI.Text(window, "GameFontDisableSmall", 24, 47)

	-- Page selector: L2 glyph, "Page n of N", R2 glyph; D-pad left/right on it or an L2/R2 tap switch pages.
	local selector = CreateFrame("Button", nil, window)
	selector:SetSize(200, 28)
	UI.At(selector, window, WIDTH - 230, 24)
	selector.previous = UI.Glyph(selector, 24, "L2")
	selector.previous:SetPoint("LEFT")
	selector.next = UI.Glyph(selector, 24, "R2")
	selector.next:SetPoint("RIGHT")
	selector.text = selector:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	selector.text:SetPoint("CENTER")
	selector:SetScript("OnClick", function() B.SetPage(page % pageCount() + 1) end)
	window.pageSelector = selector
	-- Left of the selector, right-aligned and wrapped, so a long override note stays clear of the right header.
	window.pageNote = UI.Text(window, "GameFontDisableSmall", nil, nil, nil, 420)
	window.pageNote:SetPoint("RIGHT", selector, "LEFT", -12, 0)
	window.pageNote:SetJustifyH("RIGHT")
	window:SetTitle(L.BINDINGS_TITLE)
	drawing = UI.Drawing(window, false, DRAWN)
	curve = UI.Connector(window, drawing)
	for i in ipairs(LAYERS) do
		tabs.left[i] = newTab(i)
		tabs.right[i] = newTab(i)
	end
end

-- The rows of one side, in order, for this pad (only the paddles it has).
local function columnCodes(order, left)
	local leftPads, rightPads = UI.Paddles()
	local has = {}
	for _, phys in ipairs(left and leftPads or rightPads) do has[phys] = true end
	local _, dia = UI.Art()
	local pos = dia.pos
	local list, rank = {}, {}
	for i, code in ipairs(order) do
		local at = pos[code]
		if at and (not code:match("^P%d$") or has[code]) then list[#list + 1], rank[code] = code, i end
	end
	-- Top to bottom on this pad's drawing; the order list breaks ties (D-pad and face clockwise from the top).
	table.sort(list, function(a, b)
		if pos[a][2] ~= pos[b][2] then return pos[a][2] < pos[b][2] end
		return rank[a] < rank[b]
	end)
	return list
end

function B.Columns()
	return columnCodes(LEFT_ORDER, true), columnCodes(RIGHT_ORDER, false)
end

-- A column's layer headers get a band of their own right over its first row with cells, between it and the
-- modifier rows above, so they never crowd the modifiers' glyphs and names.
local BAND = HEADER_H + HEADER_GAP

local function firstWithCells(codes)
	for i, code in ipairs(codes) do if not UI.MOD_CODES[code] then return i end end
end

-- Row i's top: the column's rows on the pitch, everything from the first row with cells down one band lower.
local function rowTop(codes, i, top)
	local first = firstWithCells(codes)
	return top + (i - 1) * ROW_PITCH + (first and i >= first and BAND or 0)
end

local function headerTop(codes, top) return rowTop(codes, firstWithCells(codes) or 1, top) - BAND end

-- Both columns start level, the longer one (with its header band) centred in the area.
local function columnTops(left, right)
	local block = math.max(#left, #right) * ROW_PITCH - (ROW_PITCH - ROW_H) + BAND
	return AREA_TOP + math.floor((AREA_BOTTOM - AREA_TOP - block) / 2)
end

-- Where a control's row sits on this pad: left column or not, and its top. Modifiers puts its rows there too, so
-- switching tabs moves nothing.
function B.RowSpot(code)
	local left, right = B.Columns()
	local top = columnTops(left, right)
	for _, column in ipairs({ { left, true }, { right, false } }) do
		for i, c in ipairs(column[1]) do if c == code then return column[2], rowTop(column[1], i, top) end end
	end
end

-- The window and row geometry Modifiers shares.
B.DRAWN = DRAWN
B.GEO = { WIDTH = WIDTH, HEIGHT = HEIGHT, EDGE = EDGE, GLYPH_X = GLYPH_X, NAME_X = NAME_X, NAME_W = NAME_W, ROW_H = ROW_H, ROW_PITCH = ROW_PITCH, CELL = CELL, AREA_TOP = AREA_TOP, AREA_BOTTOM = AREA_BOTTOM, DRAWING_PLACE = DRAWING_PLACE }

local function refresh()
	local device = ns.Device.Current()
	window.device:SetText(device and device.name or "")
	window.sub:SetText(device and (device.key .. " · " .. (ns.Remap.State() ~= "off" and L.LAYOUT_ON or L.LAYOUT_NATIVE)) or L.NO_PAD)
	drawing:Place(unpack(DRAWING_PLACE))

	local roles, face = Layout.Roles(), Layout.Face()
	for _, side in pairs(tabs) do
		for i, tab in ipairs(side) do fillTab(tab, LAYERS[i], roles) end
	end

	local count = pageCount()
	page = math.min(page, count)
	local selector = window.pageSelector
	selector.text:SetText(string.format(L.PAGE_OF, page, count))
	selector.previous:SetDisabled(page <= 1)
	selector.next:SetDisabled(page >= count)
	window.pageNote:SetText(overrideNote() or "")

	for _, row in pairs(rows) do row:Hide() end
	local nodes, first = {}, nil
	local left, right = B.Columns()
	local top = columnTops(left, right)
	for _, column in ipairs({ { left, true }, { right, false } }) do
		local codes, isLeft = column[1], column[2]
		for i, tab in ipairs(tabs[isLeft and "left" or "right"]) do
			tab:ClearAllPoints()
			UI.At(tab, window, (isLeft and EDGE or WIDTH - EDGE - CELLS_W) + (i - 1) * CELL_PITCH - 1, headerTop(codes, top))
		end
		for i, code in ipairs(codes) do
			local row = rows[code] or newRow(code)
			rows[code] = row
			placeRow(row, isLeft, rowTop(codes, i, top))
			row.glyph:SetCode(code)
			local plate = row.plate
			if plate then nodes[#nodes + 1] = UI.Node(window, plate, function() UI.Modifiers.Open(code) end, { onFocus = function(on) plate.wash:SetShown(on) end, tip = function() return rowTip(row) end }) end
			for j, cell in ipairs(row.cells) do
				fillCell(cell, row.face and j == 1 and face[UI.CODE_POS[code]] or nil)
				local node = UI.Node(window, cell, function() selectCell(cell) end, { onFocus = function(on) setCellFocus(cell, on) end, tip = function() return cellTip(cell) end })
				nodes[#nodes + 1] = node
				if code == "DU" and j == 1 then first = node end
				setCellFocus(cell, window.focus and window.focus.region == cell)
			end
		end
	end
	-- A window opens on D-pad Up's top-bar cell.
	if first then table.insert(nodes, 1, first) end

	nodes[#nodes + 1] = UI.Node(window, selector, function() B.SetPage(page % count + 1) end, {
		onDir = function(step) B.SetPage(page + step) end,
		tip = { title = string.format(L.PAGE_OF, page, count), lines = { L.PAGE_TIP }, actions = { { "PADLTRIGGER", L.PAGE_PREVIOUS }, { "PADRTRIGGER", L.PAGE_NEXT } }, side = "below" },
	})
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(B.Prompts()) end
	drawFocus()
end

-- Holding modifiers shows their bar in every row.
local function holdTick()
	local role = UI.HoldResult(UI.HeldButtons(), Layout.Roles())
	local layer = role and ROLE_LAYER[role]
	if layer == heldLayer then return end
	heldLayer = layer
	drawNames()
end

local function setup()
	if window then return end
	build()
	window.OnRefresh = refresh
	window.OnFocusChanged = drawFocus
	window.OnHoldTick = holdTick
	window.OnBack = function() UI.CloseAll() end
	window.OnPageTap = function(_, step) B.SetPage(page + step) end
	window.OnKey = function(_, key)
		if key == "PAD3" then
			local region = window.focus and window.focus.region
			clearCell(region and region.layer and region)
			return true
		end
		if key == "PAD4" and UI.ActionPicker.CanUndo() then
			UI.ActionPicker.Undo()
			return true
		end
	end
	window.OnClosed = function()
		heldLayer = nil
		UI.HideTooltip()
	end
end

function B.SetPage(n)
	local count = pageCount()
	n = math.max(1, math.min(count, n))
	if n == page then return end
	page = n
	if window and window:IsShown() then window:Refresh() end
end

function B.Prompts()
	local list = { { "PAD1", L.SELECT }, { "PAD3", L.CLEAR_SLOT }, { "PADRSHOULDER", L.MODIFIERS }, { "PADRTRIGGER", L.PAGE }, { "PAD2", L.CLOSE } }
	if UI.ActionPicker.CanUndo() then table.insert(list, 3, { "PAD4", L.UNDO_CLEAR }) end
	return list
end

-- facePos: open the action picker on that first-page face slot (onboarding's "Face actions" step).
function B.Open(facePos)
	setup()
	UI.Show(window)
	if not facePos or UI.Current() ~= window then return end

	for code, row in pairs(rows) do
		if row:IsShown() and UI.CODE_POS[code] == facePos then selectCell(row.cells[1]) end
	end
end

ns.On("ACTIONBAR_SLOT_CHANGED", function()
	if window and window:IsShown() then window:Refresh() end
end)
