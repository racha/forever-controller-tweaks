-- Forever Controller Tweaks "Bindings" window: the controller drawing centred, one row per control in two columns at the
-- window's edges, ordered by where the control sits on the pad. A row holds the four crossbar layers (top, left, right, bottom bar) of the
-- shown page, the control's glyph, and what it does on the shown layer. Only the focused row draws a curve into the
-- drawing, to its control, which lights up. A D-pad or face row's cell opens the action picker (an entry the router
-- carries shows instead of the storage slot's action); a game default explains itself.
-- The modifier rows (shoulders, triggers, the paddles this pad has) show each button's role: A opens the role list
-- (picking a role another button holds swaps the two). A paddle whose role is None gets layer cells like a D-pad row
-- instead (its role list is in More); giving it a role back keeps those cells, unused. Presets, controller setup, Learn
-- and Reset are in More. The setup guide's custom step runs here in guided mode: one role at a time, chosen by
-- pressing the button.
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

-- Geometry (window units). Cells 34 (circles 32) on a 38 pitch; rows 38 tall on a 42 pitch in a box at each side, a
-- layer header over each column's cells; both columns start level, the longer one centred in the area; the drawing
-- at 1.1 between them, on the window body. Every tab's content boxes share one rule: y 84 to 610, 24 from the window's
-- sides, 20 apart (the Keyboard and Rings tabs too). Rows sit 12 inside their box. The side boxes clear the drawing's
-- opaque art by at least 12 for every family: the widest, generic, spans viewBox x 12.3-384.2 of 400 (measured from
-- Art/*-controller.tga), so at 1.1 its left edge is at 393.5 and the box ends at 380.
local WIDTH, HEIGHT = 1200, 640
local CELL, CIRCLE, CELL_PITCH, ROW_H, ROW_PITCH = 34, 32, 38, 38, 42
local BOX_MARGIN, BOX_GAP, BOX_PAD = 24, 20, 12
local EDGE, GLYPH_X, MARKER_X, NAME_X, NAME_W = BOX_MARGIN + BOX_PAD, 205, 232, 242, 126
local ROW_W, CELLS_W = NAME_X + NAME_W - EDGE, 3 * CELL_PITCH + CELL
local AREA_TOP, AREA_BOTTOM, RULE_END = 84, 610, NAME_X + NAME_W + 38
local SIDE_BOX_W = NAME_X + NAME_W + BOX_PAD - BOX_MARGIN
local MIDDLE_X = BOX_MARGIN + SIDE_BOX_W + BOX_GAP
local HEADER_H, HEADER_GAP = 50, 4
local DRAWING_SCALE = 1.1
local DRAWING_PLACE = { (WIDTH - 400 * DRAWING_SCALE) / 2, (AREA_TOP + AREA_BOTTOM) / 2 - 150 * DRAWING_SCALE, DRAWING_SCALE }
-- Which column each control's row is in, and the tie order; rows run top to bottom by where the control sits on
-- the drawing. Only controls the addon can set are listed: the D-pad and face buttons (cells) and the modifiers (their
-- roles, which the layer headers follow); the game keeps L3, R3 and the centre buttons to itself.
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

local GUIDE_ROLES = { "leftmod", "rightmod", "friendly", "hostile" }
local LEARN_TIMEOUT = 10.5
local BUTTON_TIPS = L.BUTTON_TIPS

local window, drawing, curve, guided, learn
local rows, heldLayer = {}, nil
local tabs = { left = {}, right = {} }

local function slotInBar(key)
	local ok, action = pcall(GetBindingAction, key, nil, CORE_CTX)
	return tonumber((ok and action or ""):match("^GAMEPADACTIONBUTTON(%d)$")) or ASSUMED_SLOT[key]
end

-- Storage slot of a layer cell, nil for the reserved top-bar face slots, a paddle or without the gamepad action bars.
local function storageSlot(code, layer)
	local util = GamepadActionBarBindingUtil
	if not util or UI.MOD_CODES[code] then return end

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
	local paddle = UI.MOD_CODES[cell.code]
	local kind = cell.reserved and L.FACE_SLOT or paddle and L.PADDLE_SLOT or L.CROSSBAR_SLOT
	local choose = cell.slot and GetCursorInfo() and L.PLACE_HELD or L.CHOOSE_ACTION
	local actions = { { "PAD1", choose }, { "PAD3", L.CLEAR_SLOT } }
	if paddle then actions[3] = { "PAD4", L.PADDLE_ROLE } end
	local lines = { layerLine(cell.code, cell.layer), kind }
	lines[3] = UI.EntryOff(cell.entry)
	return { title = boundName(cell) or L.EMPTY, lines = lines, actions = actions, side = cell.row.left and "left" or "right" }
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
	cell.icon:SetDesaturated(UI.EntryOff(cell.entry) ~= nil)
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


-- A row (Bindings and Touch): the glyph, the role bar, then name and subtitle, mirrored in the right column;
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

-- A plate over glyph and names: the focus region and click target of a row without cells (the modifier rows).
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

local function isPaddle(phys) return phys:sub(1, 1) == "P" end

local function holderOf(roles, role)
	for _, phys in ipairs(Layout.PHYSICAL) do
		if roles[phys] == role then return phys end
	end
end

-- The roles the player set for this pad (the preset name is read from them).
local function storedRoles()
	local device = ns.Device.Current()
	local entry = device and ns.db.devices[device.key]
	return entry and entry.roles or {}
end

local function report(ok, err)
	if not ok and err then ns.log(err) end
end

local function hasActions(phys)
	for _, layer in ipairs(LAYERS) do if ns.Face.CellEntry(phys, layer) then return true end end
end

-- A free paddle without actions first, so a role handed on doesn't park a paddle's actions.
local function freePaddle(roles)
	local device, spare = ns.Device.Current(), nil
	for _, paddle in ipairs({ "P1", "P2", "P3", "P4" }) do
		if device and device.raw[paddle] and not roles[paddle] then
			if not hasActions(paddle) then return paddle end
			spare = spare or paddle
		end
	end
	return spare
end

-- "None" on a shoulder or trigger hands its role to a free paddle (Layout allows none on paddles only).
local function assign(phys, role)
	if role ~= "none" or isPaddle(phys) then return report(Layout.SetRole(phys, role)) end

	local roles = Layout.Roles()
	local paddle = freePaddle(roles)
	if paddle then report(Layout.SetRole(paddle, roles[phys])) end
end

-- The roles, each with its colour and what it does; a note says what picking it moves.
local function roleEntries(phys)
	local roles = Layout.Roles()
	local mine = roles[phys] or "none"
	local entries = {}
	for _, role in ipairs(UI.PICK_ROLES) do
		local info = UI.ROLE[role]
		local entry = { id = role, name = info.name, detail = info.hint, live = true }
		if info.color then entry.icon, entry.color = UI.ART .. "disc.tga", { UI.RoleRGB(role) } end
		local holder = role ~= "none" and holderOf(roles, role)
		if role == "none" and isPaddle(phys) then
			entry.detail, entry.note = L.PADDLE_FOR_ACTIONS_TIP, L.PADDLE_FOR_ACTIONS
		elseif role ~= mine and role == "none" and not isPaddle(phys) then
			local paddle = freePaddle(roles)
			entry.note, entry.disabled = paddle and L.ROLE_TO_PADDLE or L.ROLE_NEEDS_BUTTON, not paddle
		elseif role ~= mine and holder then
			entry.note = string.format(mine == "none" and L.ROLE_TAKES or L.ROLE_SWAPS, UI.Name(holder))
		end
		entries[#entries + 1] = entry
	end
	return entries, mine
end

-- A paddle switching between a role and actions changes rows: the focus follows to its other row.
local focusCode

-- Picking a role another button holds swaps the two; the note under the drawing says so in one line.
local function setRole(phys, role)
	local before = Layout.Roles()
	focusCode = phys
	assign(phys, role)
	focusCode = nil
	local after = Layout.Roles()
	window.note:SetText("")
	for _, other in ipairs(Layout.PHYSICAL) do
		if other ~= phys and before[other] ~= after[other] then
			window.note:SetText(string.format(L.ROLE_SWAPPED, UI.Name(phys), UI.ROLE[after[phys] or "none"].name, UI.Name(other), UI.ROLE[after[other] or "none"].name))
		end
	end
end

-- A role on a paddle that holds actions asks first; its cells stay stored and come back with None.
local function pickRole(phys, role)
	if role == "none" or not (isPaddle(phys) and ns.Face.PaddleFree(phys) and hasActions(phys)) then return setRole(phys, role) end
	UI.Dialog():Open(window, { text = string.format(L.PADDLE_ROLE_TEXT, UI.Name(phys), UI.ROLE[role].name), sub = L.PADDLE_ROLE_SUB, buttons = { L.CHANGE_ROLE, L.CANCEL }, on1 = function() setRole(phys, role) end })
end

-- anchor: where the list opens and the focus returns (the row's plate, or a paddle's focused cell).
local function openRoles(row, anchor)
	if guided or InCombatLockdown() then return end
	local entries, mine = roleEntries(row.code)
	UI.ActionPicker.Open({ window = window, cell = anchor or row.plate, list = { title = string.format(L.ROLES_TITLE, UI.Name(row.code)), entries = entries, current = mine, onPick = function(entry) pickRole(row.code, entry.id) end } })
end

-- A paddle without a role carries actions, so its row has cells (not in guided mode, which sets roles).
local function hasCells(code) return not UI.MOD_CODES[code] or not guided and ns.Face.PaddleFree(code) end

-- D-pad and face rows, and free paddles, get the four layer cells; modifier rows a plate that opens the role list.
local function newRow(code, withCells)
	local face = UI.CODE_POS[code] ~= nil
	local row = B.NewRow(window, code)
	row.face, row.kind, row.cells = face, withCells and "slot" or "mod", {}
	if row.kind == "mod" then
		B.AddPlate(row, function() openRoles(row) end)
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

-- A modifier row: its role and what that does; in guided mode, where the button stands (grey while not set).
local function modText(row)
	local phys = row.code
	if guided and guided.detected == phys then return UI.ROLE[GUIDE_ROLES[guided.step]].name, L.GUIDE_CONFIRM, GUIDE_ROLES[guided.step] end
	if guided and not guided.confirmed[phys] then return L.GUIDE_NOT_SET, L.GUIDE_WAITING, nil, true end
	local role = Layout.Roles()[phys] or "none"
	local info = UI.ROLE[role]
	return info.name, info.hint, role
end

local function rowText(row, layer)
	if row.kind == "mod" then return modText(row) end
	local cell = row.cells[LAYER_INDEX[layer]]
	local word = UI.ROLE[LAYER_ROLE[layer]].word
	if UI.MOD_CODES[row.code] then return boundName(cell), string.format(L.PADDLE_SUB, UI.Name(row.code), word) end
	return boundName(cell), string.format(cell.reserved and L.FACE_SUB or L.BAR_SUB, word)
end

local function rowTip(row)
	local held = Layout.Roles()[row.code] or "none"
	local info = UI.ROLE[held]
	return { title = UI.Name(row.code) .. " · " .. info.name, lines = { info.hint, L.ROLE_TIP }, actions = { { "PAD1", L.CHANGE_ROLE }, { "PAD4", L.MORE } }, side = row.left and "left" or "right" }
end

-- Names follow the shown layer; the tab of that layer is selected. In guided mode the cell rows step back.
local function drawNames()
	local layer = shownLayer()
	for _, row in pairs(rows) do
		if row:IsShown() then
			local name, sub, role, grey = rowText(row, layer)
			row.name:SetText(name or L.NOT_BOUND)
			row.name:SetFontObject(name and not grey and "GameFontNormal" or "GameFontDisable")
			row.sub:SetText(sub)
			row.marker:SetRole(role)
			row:SetAlpha(grey and 0.45 or guided and row.kind ~= "mod" and 0.35 or 1)
		end
	end
	local region = window.focus and window.focus.region
	B.LightLayerHeaders(tabs, layer, region and region.layer and (region.row.left and "left" or "right"))
end

-- The focused row's line runs into its control, which lights up (in guided mode the detected button's, with only
-- the modifiers at full strength).
local function drawFocus()
	local focusRow = guided and rows[guided.detected] or not guided and window.focus and window.focus.region and window.focus.region.row
	local active = guided and function(code) return UI.MOD_CODES[code] end or nil
	drawing:Style(active, focusRow and { [focusRow.code] = true } or {}, focusRow and focusRow.code, false)
	B.FocusLine(curve, drawing, rows, focusRow and focusRow:IsShown() and focusRow or nil)
	drawNames()
end

-- Layer headers over each column's cells (Bindings, Touch), one per cell column (top, left, right, bottom bar; the
-- same order on both sides): the button(s) to hold for that bar as native glyphs, stacked when two ("None" for the
-- top bar), over a role-colour band. The shown layer's header is lit on both sides. A click moves the focus to that
-- column of the focused row.
local function newTab(owner, i)
	local tab = CreateFrame("Button", nil, owner)
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
		local region = owner.focus and owner.focus.region
		local row = region and region.row
		if not (row and row.cells and row.cells[i]) then return end
		for _, node in ipairs(owner.nodes) do if node.region == row.cells[i] then owner:Focus(node) end end
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

function B.NewLayerHeaders(owner)
	local headers = { left = {}, right = {} }
	for i in ipairs(LAYERS) do
		headers.left[i] = newTab(owner, i)
		headers.right[i] = newTab(owner, i)
	end
	return headers
end

-- The headers follow the player's roles (who holds which bar).
function B.FillLayerHeaders(headers, roles)
	for _, side in pairs(headers) do
		for i, tab in ipairs(side) do fillTab(tab, LAYERS[i], roles) end
	end
end

-- One side's headers over its four cell columns, at top (window units).
function B.PlaceLayerHeaders(headers, isLeft, top)
	for i, tab in ipairs(headers[isLeft and "left" or "right"]) do
		tab:ClearAllPoints()
		UI.At(tab, tab:GetParent(), (isLeft and EDGE or WIDTH - EDGE - CELLS_W) + (i - 1) * CELL_PITCH - 1, top)
	end
end

-- Only the focused side's header of the shown layer is lit ("left" or "right"); with the focus off the cells
-- (a modifier row, the header) neither side is.
function B.LightLayerHeaders(headers, layer, side)
	for name, list in pairs(headers) do
		for i, tab in ipairs(list) do
			local on = name == side and LAYERS[i] == layer
			tab.highlight:SetShown(on)
			tab:SetAlpha(on and 1 or 0.55)
		end
	end
end

local function build()
	window = UI.NewWindow(WIDTH, HEIGHT)
	B.Boxes(window)
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
	tabs = B.NewLayerHeaders(window)
	-- Guided mode's step line over the drawing; normal mode's one-line role swap note under it. All in the middle area.
	local x, _, w = unpack(B.GEO.MIDDLE)
	window.title = UI.CenterText(window, "GameFontNormalLarge", x + 10, 96, w - 20)
	window.hint = UI.CenterText(window, "GameFontDisableSmall", x + 10, 140, w - 20)
	window.note = UI.CenterText(window, "GameFontHighlightSmall", x + 10, 560, w - 20)
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
	for i, code in ipairs(codes) do if hasCells(code) then return i end end
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

-- Where a control's row sits on this pad: left column or not, and its top.
function B.RowSpot(code)
	local left, right = B.Columns()
	local top = columnTops(left, right)
	for _, column in ipairs({ { left, true }, { right, false } }) do
		for i, c in ipairs(column[1]) do if c == code then return column[2], rowTop(column[1], i, top) end end
	end
end

-- The window and row geometry Touch shares.
B.DRAWN = DRAWN
B.LAYERS, B.ROLE_LAYER, B.LAYER_ROLE = LAYERS, ROLE_LAYER, LAYER_ROLE
B.GEO = { CELL_PITCH = CELL_PITCH, CELLS_W = CELLS_W, BAND = HEADER_H + HEADER_GAP, WIDTH = WIDTH, HEIGHT = HEIGHT, EDGE = EDGE, GLYPH_X = GLYPH_X, NAME_X = NAME_X, NAME_W = NAME_W, ROW_H = ROW_H, ROW_PITCH = ROW_PITCH, CELL = CELL, AREA_TOP = AREA_TOP, AREA_BOTTOM = AREA_BOTTOM, DRAWING_PLACE = DRAWING_PLACE }
-- The middle area between the row columns' boxes: x, y, width, height.
B.GEO.MIDDLE = { MIDDLE_X, AREA_TOP, WIDTH - 2 * MIDDLE_X, AREA_BOTTOM - AREA_TOP }

-- The content boxes of a tab with row columns: one per side, and with middle one over the middle area (Touch; the
-- controller drawing floats on the window body instead). Made right after the window, so everything made later (rows,
-- the drawing and its focus line) is above them.
function B.Boxes(owner, middle)
	UI.Inset(owner, BOX_MARGIN, AREA_TOP, SIDE_BOX_W, AREA_BOTTOM - AREA_TOP)
	if middle then UI.Inset(owner, unpack(B.GEO.MIDDLE)) end
	UI.Inset(owner, WIDTH - BOX_MARGIN - SIDE_BOX_W, AREA_TOP, SIDE_BOX_W, AREA_BOTTOM - AREA_TOP)
end

-- The device is resolved at login, on world entry and on connect events; a pad unreadable then (still waking, or
-- Steam's virtual pad not there yet) is looked for again here, so the header doesn't keep saying none was found.
-- The sub line names the active preset, or Custom for the player's own roles.
local function refresh()
	local device = ns.Device.Current() or ns.Device.Refresh()
	window.device:SetText(device and device.name or "")
	local state = ns.Remap.State() ~= "off" and L.LAYOUT_ON or L.LAYOUT_NATIVE
	window.sub:SetText(device and (device.key .. " · " .. state .. " · " .. UI.PresetLabel(Layout.PresetName(storedRoles()))) or L.NO_PAD)
	drawing:Place(unpack(DRAWING_PLACE))

	local roles, face = Layout.Roles(), Layout.Face()
	B.FillLayerHeaders(tabs, roles)

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
		B.PlaceLayerHeaders(tabs, isLeft, headerTop(codes, top))
		for i, code in ipairs(codes) do
			-- A paddle has two rows, its role row and its action row; the one for its role now is shown.
			local withCells = hasCells(code)
			local key = withCells and UI.MOD_CODES[code] and code .. "/cells" or code
			local row = rows[key] or newRow(code, withCells)
			rows[key] = row
			placeRow(row, isLeft, rowTop(codes, i, top))
			row.glyph:SetCode(code)
			local plate = row.plate
			if plate then
				plate:EnableMouse(not guided)
				nodes[#nodes + 1] = UI.Node(window, plate, function() openRoles(row) end, { phys = code, onFocus = function(on) plate.wash:SetShown(on) end, tip = function() return rowTip(row) end })
				if code == focusCode then window.focus = { region = plate } end
			end
			for j, cell in ipairs(row.cells) do
				fillCell(cell, row.face and j == 1 and face[UI.CODE_POS[code]] or nil)
				local node = UI.Node(window, cell, function() selectCell(cell) end, { onFocus = function(on) setCellFocus(cell, on) end, tip = function() return cellTip(cell) end })
				nodes[#nodes + 1] = node
				if code == "DU" and j == 1 then first = node end
				if code == focusCode and j == 1 then window.focus = { region = cell } end
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

	selector:SetShown(not guided)
	window.tabs:SetShown(not guided and #UI.TABS > 1)
	window.tabsLocked = not not guided
	window.title:SetShown(guided ~= nil)
	window.hint:SetShown(guided ~= nil)
	window.note:SetShown(not guided)
	if guided then
		local stepRole = GUIDE_ROLES[guided.step]
		window:SetTitle(L.CUSTOM_TITLE)
		window.title:SetText(string.format(L.GUIDE_HEADING, guided.step, L.GUIDE_TARGET[stepRole]))
		window.hint:SetText(L.GUIDE_HINT)
		window:SetPrompts({ { "PAD3", L.SKIP }, { "PAD2", L.BACK } })
		window:SetNodes({})
		window.cursor:Hide()
	else
		window:SetTitle(L.BINDINGS_TITLE)
		window:SetNodes(nodes)
		if not UI.DialogShown() then window:SetPrompts(B.Prompts()) end
	end
	drawFocus()
end

-- Learn controller: L1, R1, L2, R2 and the paddles in turn, each through Device.Learn; the dialog shows what the
-- raw state shows meanwhile.
local function zeroBased(list)
	local out, base = {}, type(list) == "table" and list[0] ~= nil and 0 or 1
	if type(list) ~= "table" then return out end
	local i = base
	while list[i] ~= nil do
		out[i - base] = list[i]
		i = i + 1
	end
	return out
end

local function rawSnapshot()
	local _, raw = ns.Device.Raw()
	return raw and { buttons = zeroBased(raw.rawButtons), axes = zeroBased(raw.rawAxes) } or { buttons = {}, axes = {} }
end

local function detectedText()
	local now, base, device = rawSnapshot(), learn.base, ns.Device.Current()
	for i, down in pairs(now.buttons) do
		if down and not base.buttons[i] then return string.format(L.LEARN_DETECTED, string.format(L.LEARN_BUTTON, i)) end
	end
	local motion = device and device.motionAxes or {}
	for i, value in pairs(now.axes) do
		if not motion[i] and math.abs(base.axes[i] or 0) < 0.2 and value > 0.8 then return string.format(L.LEARN_DETECTED, string.format(L.LEARN_AXIS, i)) end
	end
end

-- Paddles have no glyph in the input icon sets (asking the set for one errors), so they read as their name.
local function glyphMarkup(phys)
	local atlas = not isPaddle(phys) and UI.GlyphAtlas(UI.KEY[phys], "Normal")
	if atlas then return CreateAtlasMarkup(atlas, 22, 22) end
	return "(" .. UI.Name(phys) .. ")"
end

local learnStep

local function learnSub(text) UI.Dialog():SetSub(string.format(L.LEARN_STEP, text, learn.index, #learn.steps)) end

function learnStep()
	local phys = learn.steps[learn.index]
	if not phys then
		learn = nil
		return
	end

	local device = ns.Device.Current()
	learn.phys, learn.before, learn.started, learn.base = phys, device and device.raw[phys], GetTime(), rawSnapshot()
	ns.Device.Learn(phys)
	UI.Dialog():Open(window, {
		text = string.format(L.LEARN_TEXT, UI.Name(phys)) .. " " .. glyphMarkup(phys),
		buttons = { L.SKIP, L.CANCEL },
		on1 = function()
			learn.index = learn.index + 1
			learnStep()
		end,
		on2 = function()
			if ns.Device.LearnCancel then ns.Device.LearnCancel() end
			learn = nil
		end,
	})
	learnSub(L.LEARN_WAIT)
end

local function learnTick()
	local device = ns.Device.Current()
	if not (device and UI.DialogShown()) then return end

	if device.raw[learn.phys] ~= learn.before then
		learn.index = learn.index + 1
		UI.Dialog():Close()
		return learnStep()
	end
	if GetTime() - learn.started > LEARN_TIMEOUT then
		ns.log(string.format(L.LEARN_NONE, UI.Name(learn.phys)))
		learn.index = learn.index + 1
		UI.Dialog():Close()
		return learnStep()
	end
	local text = detectedText()
	if text then learnSub(text) end
end

function B.Learn()
	local device = ns.Device.Current() or ns.Device.Refresh()
	if not device then return ns.log(L.NO_PAD) end

	local steps = { "L1", "R1", "L2", "R2" }
	local leftPads, rightPads = UI.Paddles()
	for _, list in ipairs({ rightPads, leftPads }) do
		for _, phys in ipairs(list) do steps[#steps + 1] = phys end
	end
	learn = { steps = steps, index = 1 }
	learnStep()
end

function B.Reset()
	UI.Dialog():Open(window, { text = L.RESET_TEXT, sub = L.RESET_SUB, buttons = { L.RESET, L.CANCEL }, on1 = function() report(Layout.Reset()) end })
end

-- Guided mode keys: a modifier press detects, the same press again confirms; Skip and Back from the footer.
local function guidedKey(key)
	local phys = UI.CODE[key]
	local device = ns.Device.Current()
	if key == "PAD3" then
		guided.step, guided.detected = guided.step + 1, nil
	elseif key == "PAD2" then
		local back = guided.onBack
		B.EndGuided()
		if back then back() end
		return true
	elseif phys and UI.MOD_CODES[phys] and device and device.raw[phys] then
		if guided.detected ~= phys then
			guided.detected = phys
			refresh()
			return true
		end
		report(Layout.SetRole(phys, GUIDE_ROLES[guided.step]))
		guided.confirmed[phys] = true
		guided.step, guided.detected = guided.step + 1, nil
	else
		return true
	end

	if guided.step > #GUIDE_ROLES then
		local done = guided.onDone
		B.EndGuided()
		if done then done() end
		return true
	end
	refresh()
	return true
end

-- Learn and Reset run in this window: from another tab they open it first.
local function here(run) return function() if UI.Current() ~= window then B.Open() end run() end end

-- More, from Y on every tab, in the picker's look over the window's foot: Undo while a clear can be undone, the tab's
-- own entries (current: the id to tick), then the same common ones everywhere.
function UI.OpenMore(owner, entries, current)
	if InCombatLockdown() then return end
	local list, Picker = {}, UI.ActionPicker
	if Picker.CanUndo() then list[1] = { id = "undo", name = string.format(L.UNDO_RESTORE, Picker.UndoName() or L.UNNAMED_ACTION), detail = L.UNDO_TIP, run = Picker.Undo } end
	for _, entry in ipairs(entries or {}) do list[#list + 1] = entry end
	local common = {
		{ id = "family", name = L.CONTROLLER_TYPE, detail = L.CONTROLLER_TYPE_TIP, run = function() UI.Onboarding.ShowFamily() end },
		{ id = "detect", name = L.DETECT_BUTTON_LABEL, detail = L.DETECT_BUTTON_TIP, run = function() UI.Detect.Open() end },
		{ id = "detectreset", name = L.DETECT_RESET, detail = L.DETECT_RESET_TEXT, run = function() UI.Detect.Reset(owner) end },
		{ id = "guide", name = L.SETUP_GUIDE, detail = BUTTON_TIPS[1], run = function() UI.Onboarding.Start() end },
		{ id = "learn", name = L.LEARN, detail = BUTTON_TIPS[2], run = here(function() B.Learn() end) },
		{ id = "minimap", name = ns.db.options.minimapIcon == false and L.MINIMAP_SHOW or L.MINIMAP_HIDE, detail = L.MINIMAP_TIP, run = function() UI.ToggleMinimapButton() end },
		{ id = "reset", name = L.RESET, detail = BUTTON_TIPS[3], run = here(function() B.Reset() end) },
	}
	if ns.Keyboard then table.insert(common, 6, { id = "keyboard", name = L.KEYBOARD, detail = L.KEYBOARD_TIP, run = function() ns.Keyboard.SettingsTab.Open() end }) end
	for _, entry in ipairs(common) do list[#list + 1] = entry end
	local focus = owner.focus and owner.focus.region or owner
	Picker.Open({ window = owner, cell = focus, point = { "BOTTOM", owner, "BOTTOM", 0, 24 }, list = { title = L.MORE, entries = list, current = current, onPick = function(entry) entry.run() end } })
end

-- Holding modifiers shows their bar in every row; Learn watches the raw state meanwhile.
local function holdTick()
	if learn then learnTick() end
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
	window.OnBack = function()
		if guided then return guidedKey("PAD2") end
		UI.CloseAll()
	end
	window.OnPageTap = function(_, step) B.SetPage(page + step) end
	window.OnKey = function(_, key)
		if guided then return guidedKey(key) end
		if key == "PAD3" then
			local region = window.focus and window.focus.region
			clearCell(region and region.layer and region)
			return true
		end
		if key ~= "PAD4" then return end
		-- More: on a free paddle's cell its role list first, then the presets (the active one ticked), the pages and the
		-- common entries.
		local count, entries = pageCount(), {}
		local region = window.focus and window.focus.region
		local row = region and region.layer and region.row
		local paddleRow = row and UI.MOD_CODES[row.code] and row
		if paddleRow then entries[1] = { id = "paddlerole", name = string.format(L.ROLES_TITLE, UI.Name(paddleRow.code)), detail = L.PADDLE_ROLE_TIP, run = function() openRoles(paddleRow, region) end } end
		for _, name in ipairs({ "native", "split" }) do
			entries[#entries + 1] = { id = name, name = UI.PresetLabel(name), detail = L.PRESET_TIP, live = true, run = function() report(Layout.SetPreset(name)) end }
		end
		for n = 1, count do entries[#entries + 1] = { id = "page" .. n, name = string.format(L.PAGE_OF, n, count), detail = L.PAGE_TIP, run = function() B.SetPage(n) end } end
		UI.OpenMore(window, entries, Layout.PresetName(storedRoles()))
		return true
	end
	window.OnClosed = function()
		heldLayer = nil
		window.note:SetText("")
		UI.HideTooltip()
		if learn and ns.Device.LearnCancel then ns.Device.LearnCancel() end
		learn = nil
		if guided and UI.combatClosing then
			local saved = guided
			UI.resume = { text = L.RESUME_CUSTOM, fn = function()
				guided = saved
				guided.detected = nil
				UI.Show(window)
			end }
		end
		if guided then B.EndGuided() end
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
	local list = { { "PAD1", L.SELECT }, { "PAD3", L.CLEAR_SLOT }, { "PAD4", L.MORE }, { "PADRTRIGGER", L.PAGE }, { "PAD2", L.CLOSE } }
	list[#list + 1] = UI.TabPrompt("bindings", 1)
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

-- The setup guide's custom step. onDone runs after the fourth role, onBack on Back.
function B.OpenGuided(onDone, onBack)
	setup()
	guided = { step = 1, confirmed = {}, onDone = onDone, onBack = onBack }
	UI.Show(window)
end

function B.EndGuided()
	guided = nil
	if window and window:IsShown() then refresh() end
end

ns.On("ACTIONBAR_SLOT_CHANGED", function()
	if window and window:IsShown() then window:Refresh() end
end)
