-- Forever Controller Tweaks "Rings" side tab (design/rings.md section 6), built like the Keyboard tab: the ring list on
-- the left (a row per ring, then New ring), the selected ring drawn in the middle as it shows in game, its slot count
-- and Rename / Icon / Delete under it. A on a slot opens the action picker for it, X clears it; X on a ring renames it.
-- Rename hides the window and asks in a small box of ours, so the on-screen keyboard (or a real one) types the name.
local ns = ForeverControllerTweaks
local UI, Rings = ns.UI, ns.Rings
local L = UI.L

local S = {}
Rings.SettingsTab = S

local STRINGS = {
	RINGS_TAB = "Rings", RINGS_TITLE = "Controller Tweaks · Rings",
	RINGS_HINT = "Radial menus of actions. Put \"Open ring\" on any button in Bindings or Touch: hold it, aim with the right stick, release.",
	RINGS_LIST = "Your rings", RINGS_COUNT = "Rings %d / %d", RINGS_NEW = "New ring", RINGS_NEW_TIP = "A new ring with 8 empty slots.",
	RINGS_NONE = "No rings yet. Make one with New ring.", RINGS_EDIT = "Edit slots",
	RINGS_RENAME = "Rename", RINGS_RENAME_TITLE = "Rename ring", RINGS_RENAME_HINT = "Enter saves, Escape cancels.",
	RINGS_ICON = "Icon", RINGS_ICON_TITLE = "Ring icon", RINGS_ICON_AUTO = "First slot's icon", RINGS_ICON_SLOT = "From this ring's slots", RINGS_ICON_TIP = "The icon in the ring's hub and on the buttons that open it.",
	RINGS_DELETE = "Delete", RINGS_DELETE_TEXT = "Delete the ring \"%s\"?", RINGS_DELETE_SUB = "It is on %d button(s) (every character): they will be cleared.",
	RINGS_DELETE_TIP = "Deletes the ring and clears every button that opens it.",
	RINGS_SLOTS = "Slots", RINGS_SLOTS_TIP = "D-pad left and right: %d to %d slots. Slots past the count are kept for later.",
	RINGS_STICK = "Stick", RINGS_STICK_NAMES = { right = "Right", left = "Left", dynamic = "Dynamic" },
	RINGS_STICK_TIP = "The stick that aims while you hold the button. Dynamic: right on a D-pad button, left on a face button.",
	RINGS_SLOT = "Slot %d", RINGS_EMPTY = "Empty slot", RINGS_UNUSABLE = "This character can't use it now.",
	RINGS_ROW_TIP = "%d slots, on %d button(s).", RINGS_COMBAT = "Controller Tweaks changes rings out of combat only.",
}
for key, text in pairs(STRINGS) do L[key] = text end

local GEO = Rings.GEO
-- Two content boxes by the tabs' rule (y 84 to 610, 24 from the sides, 20 apart): the list on the left, the ring on
-- the right, each under its section pill.
local LEFT_X, TOP_Y, LEFT_W, RIGHT_X, RIGHT_W, BOX_H, PILL_W = 24, 84, 300, 344, 832, 526, 197
local ROW_W, ROW_H, ROW_PITCH, LIST_Y = 268, 28, 30, TOP_Y + 58
local DISC_Y = TOP_Y + 58
local STEP_Y = DISC_Y + 2 * GEO.DISC + 22
local STICK_Y, SETTING_W, STICK_SEG_W = STEP_Y + 32, 360, 90
local BUTTONS_Y, BUTTON_W = STICK_Y + 40, 140

local window, countText, rows, newRow, ringPill, preview, hub, slotButtons, emptyText, stepRow, stickRow, buttons, renameBox
local selected

local function report(ok, err)
	if ok then return true end
	if err then UI.Dialog():Open(window, { text = err, buttons = { L.CLOSE } }) end
end

local function editable()
	if not InCombatLockdown() then return true end
	ns.log(L.RINGS_COMBAT)
end

local function newRing()
	if not editable() then return end
	local ring, err = Rings.New()
	if ring then selected = ring.id end
	report(ring, err)
end

local function stepCount(step)
	local ring = Rings.Get(selected)
	if not (ring and editable()) then return false end
	local count = ring.count + step
	if count < Rings.MIN_SLOTS or count > Rings.MAX_SLOTS then return false end
	report(Rings.SetCount(ring.id, count))
end

-- One step through Right, Left, Dynamic; past either end false (left/right moves the focus on), or round with wrap (A).
local function stepStick(step, wrap)
	local ring = Rings.Get(selected)
	if not (ring and editable()) then return false end
	local index, sticks = 1, Rings.STICKS
	for i, stick in ipairs(sticks) do if stick == ring.stick then index = i end end
	local stick = sticks[wrap and (index + step - 1) % #sticks + 1 or index + step]
	if not stick then return false end
	report(Rings.SetStick(ring.id, stick))
end

local function pick(i)
	if not (Rings.Get(selected) and editable()) then return end
	UI.ActionPicker.Open({ window = window, cell = slotButtons[i], ring = { id = selected, index = i } })
end

local function clearSlot(i)
	if not (Rings.Get(selected) and editable()) then return end
	report(Rings.SetSlot(selected, i, nil))
end

---------------------------------------------------------------------------------------------------------------------
-- Ring icon: every macro icon in a grid, in the action picker's look (common-dropdown-bg, a section-pill title,
-- native slot cells with their gold focus). Virtualized: COLS x GRID_ROWS cells show the rows at the offset. A modal of
-- the window: D-pad moves (a held direction repeats), L2/R2 page, A picks, B closes; mouse hover, click, wheel and the
-- scroll bar work too.

local COLS, GRID_ROWS, CELL, GAP, EDGE, HEAD, FOOT = 10, 6, 40, 6, 14, 46, 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The "First slot's icon" cell.
local AUTO = {}
local grid, allIcons
local Grid = {}

-- Every macro icon the game lists (file ids, or names under Interface\Icons), once, deduplicated.
local function macroIcons()
	if allIcons then return allIcons end
	local raw, seen = {}, {}
	for _, name in ipairs({ "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }) do
		if _G[name] then pcall(_G[name], raw) end
	end
	allIcons = {}
	for _, value in ipairs(raw) do
		local icon = tonumber(value) or "Interface\\Icons\\" .. tostring(value)
		if not seen[icon] then
			seen[icon] = true
			allIcons[#allIcons + 1] = icon
		end
	end
	return allIcons
end

local function rowOf(index) return math.floor((index - 1) / COLS) end
local function maxOffset() return math.max(0, rowOf(#grid.list) + 1 - GRID_ROWS) end

local function drawGrid()
	local list = grid.list
	for i, cell in ipairs(grid.cells) do
		local index = grid.offset * COLS + i
		local icon = list[index]
		cell.index = icon and index or nil
		cell:SetShown(icon ~= nil)
		if icon then
			cell.icon:SetTexture(icon == AUTO and grid.first or icon)
			cell.tick:SetShown(index == grid.current)
			UI.Bindings.SetCellFocus(cell, index == grid.index)
		end
	end
	window.cursor:Attach(grid.cells[grid.index - grid.offset * COLS], 0)
	local index = grid.index
	grid.note:SetText(index == 1 and L.RINGS_ICON_AUTO or index <= 1 + grid.fromSlots and L.RINGS_ICON_SLOT or "")
	local bar, top = grid.bar, maxOffset()
	bar:SetShown(top > 0)
	grid.drawing = true
	bar:SetMinMaxValues(0, top)
	bar:SetValue(grid.offset)
	grid.drawing = nil
end

-- index: the focused cell, kept in view.
function Grid.Focus(index)
	grid.index = math.max(1, math.min(#grid.list, index))
	local row = rowOf(grid.index)
	if row < grid.offset then grid.offset = row end
	if row >= grid.offset + GRID_ROWS then grid.offset = row - GRID_ROWS + 1 end
	drawGrid()
end

-- The rows shown from offset; the focus moves along into view (same column).
function Grid.Scroll(offset)
	grid.offset = math.max(0, math.min(maxOffset(), offset))
	local row = rowOf(grid.index)
	local column = (grid.index - 1) % COLS + 1
	if row < grid.offset then grid.index = grid.offset * COLS + column end
	if row >= grid.offset + GRID_ROWS then grid.index = (grid.offset + GRID_ROWS - 1) * COLS + column end
	Grid.Focus(grid.index)
end

-- dy > 0 is up; |dy| > 1 pages (L2/R2) and stops at the ends. A step past the last full row lands on the last icon.
function Grid.Move(_, dx, dy)
	local index, last = grid.index, #grid.list
	if math.abs(dy) > 1 then return Grid.Focus(index - (dy > 0 and 1 or -1) * COLS * GRID_ROWS) end
	local target = index + dx - dy * COLS
	if target > last and dy < 0 and rowOf(last) > rowOf(index) then target = last end
	if target < 1 or target > last then return end
	Grid.Focus(target)
end

function Grid.Close()
	if not (grid and grid:IsShown()) then return end
	grid:Hide()
	grid.catcher:Hide()
	window.modal = nil
	window.focus = { region = buttons.icon }
	if window:IsShown() then window:Refresh() end
end

function Grid.Pick(index)
	local icon, id = grid.list[index], grid.ringId
	Grid.Close()
	if editable() then report(Rings.SetIcon(id, icon ~= AUTO and icon or nil)) end
end

local DIRS = { PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 }, PADLTRIGGER = { 0, GRID_ROWS }, PADRTRIGGER = { 0, -GRID_ROWS } }

function Grid.OnPad(_, key)
	if key == "PAD1" then return Grid.Pick(grid.index) end
	if key == "PAD2" then return Grid.Close() end
	local dir = DIRS[key]
	if not dir then return end
	window.repeatKey = key
	window:StartRepeat(dir)
end

local function buildGrid()
	local width = COLS * (CELL + GAP) - GAP + 2 * EDGE + 12
	grid = CreateFrame("Frame", nil, UIParent)
	grid:SetSize(width, HEAD + GRID_ROWS * (CELL + GAP) - GAP + FOOT)
	grid:SetClampedToScreen(true)
	grid:EnableMouse(true)
	grid:EnableMouseWheel(true)
	grid:SetScript("OnMouseWheel", function(_, delta) Grid.Scroll(grid.offset - delta) end)
	local bg = grid:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("common-dropdown-bg")
	bg:SetAlpha(0.925)
	bg:SetPoint("TOPLEFT", -10, 3)
	bg:SetPoint("BOTTOMRIGHT", 10, -3)
	UI.SectionHeader(grid, 0, 2, width, L.RINGS_ICON_TITLE)
	grid.cells = {}
	for i = 1, COLS * GRID_ROWS do
		local cell = UI.Bindings.SlotCell(grid, CELL, false)
		UI.At(cell, grid, EDGE + (i - 1) % COLS * (CELL + GAP), HEAD + rowOf(i) * (CELL + GAP))
		cell.icon:SetPoint("TOPLEFT", 3, -3)
		cell.icon:SetPoint("BOTTOMRIGHT", -3, 3)
		cell.tick = cell:CreateTexture(nil, "OVERLAY", nil, 2)
		cell.tick:SetAtlas("common-dropdown-icon-radialtick-yellow")
		cell.tick:SetSize(14, 14)
		cell.tick:SetPoint("TOPRIGHT", 3, 3)
		cell:SetScript("OnEnter", function(self) if self.index then Grid.Focus(self.index) end end)
		cell:SetScript("OnClick", function(self) if self.index then Grid.Pick(self.index) end end)
		grid.cells[i] = cell
	end
	grid.note = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	grid.note:SetPoint("BOTTOMLEFT", EDGE, 10)

	-- MinimalScrollBar's art on a plain Slider (the template's scroll controller is Blizzard code).
	local bar = CreateFrame("Slider", nil, grid)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -6, -HEAD)
	bar:SetPoint("BOTTOMRIGHT", -6, FOOT)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	for _, spec in ipairs({ { "minimal-scrollbar-track-top", "TOP" }, { "minimal-scrollbar-track-bottom", "BOTTOM" } }) do
		local cap = bar:CreateTexture(nil, "BACKGROUND")
		cap:SetAtlas(spec[1], true)
		cap:SetPoint(spec[2])
	end
	local track = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
	track:SetAtlas("!minimal-scrollbar-track-middle", true)
	track:SetPoint("TOP", 0, -8)
	track:SetPoint("BOTTOM", 0, 8)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
	thumb:SetSize(8, 40)
	bar:SetThumbTexture(thumb)
	for _, spec in ipairs({ { "minimal-scrollbar-small-thumb-top", "BOTTOM", "TOP" }, { "minimal-scrollbar-small-thumb-bottom", "TOP", "BOTTOM" } }) do
		local cap = bar:CreateTexture(nil, "ARTWORK")
		cap:SetAtlas(spec[1], true)
		cap:SetPoint(spec[2], thumb, spec[3])
	end
	bar:SetScript("OnValueChanged", function(_, value) if not grid.drawing then Grid.Scroll(math.floor(value + 0.5)) end end)
	grid.bar = bar

	-- A click anywhere else closes the grid without a change.
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetScript("OnClick", Grid.Close)
	catcher:Hide()
	grid.catcher = catcher
	grid:Hide()
end

-- "First slot's icon", this ring's slot icons, then every other icon; the focus on the ring's icon.
local function pickIcon()
	local ring = Rings.Get(selected)
	if not (ring and editable()) then return end
	if not grid then buildGrid() end
	local list, seen, fromSlots = { AUTO }, {}, 0
	local function add(icon)
		if not icon or seen[icon] then return end
		seen[icon] = true
		list[#list + 1] = icon
	end
	for i = 1, ring.count do
		local slot = ring.slots[i]
		add(slot and slot.icon)
	end
	fromSlots = #list - 1
	for _, icon in ipairs(macroIcons()) do add(icon) end
	local current = 1
	for index, icon in ipairs(list) do if ring.icon ~= nil and icon == ring.icon then current = index end end
	if ring.icon ~= nil and current == 1 then
		list[#list + 1] = ring.icon
		current = #list
	end
	grid.list, grid.fromSlots, grid.current, grid.ringId, grid.offset = list, fromSlots, current, ring.id, 0
	grid.first = Rings.Icon({ count = ring.count, slots = ring.slots })
	grid:SetScale(window:GetScale())
	grid:ClearAllPoints()
	grid:SetPoint("CENTER", window, "CENTER")
	grid.catcher:Show()
	UI.RaiseAbove(grid.catcher, window, "catcher")
	UI.RaiseAbove(grid, window, "picker")
	grid:Show()
	UI.HideTooltip()
	window.modal = Grid
	window:SetPrompts({ { "PAD1", L.SELECT }, { "PADRTRIGGER", L.PAGE }, { "PAD2", L.BACK } })
	Grid.Focus(current)
end

local function delete()
	local ring = Rings.Get(selected)
	if not (ring and editable()) then return end
	local count = Rings.BindingCount(ring.id)
	UI.Dialog():Open(window, {
		text = string.format(L.RINGS_DELETE_TEXT, ring.name), sub = count > 0 and string.format(L.RINGS_DELETE_SUB, count) or nil,
		buttons = { L.RINGS_DELETE, L.CANCEL }, back = 2, on1 = function() report(Rings.Delete(ring.id)) end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Rename: our own box over the world, with the window hidden, so the on-screen keyboard takes the pad.

local function closeRename(save)
	local box = renameBox
	local id, text = box.id, box.edit:GetText()
	box:Hide()
	if save then
		local ok, err = Rings.Rename(id, text)
		if not ok then ns.log(err) end
	end
	if not InCombatLockdown() then S.Open(id) end
end

local function buildRename()
	local box = CreateFrame("Frame", "ForeverControllerTweaksRingRename", UIParent)
	box:SetSize(360, 112)
	box:SetPoint("TOP", UIParent, "TOP", 0, -96)
	box:SetFrameStrata("DIALOG")
	box:EnableMouse(true)
	local bottom = box:CreateTexture(nil, "BACKGROUND", nil, -7)
	bottom:SetAtlas("UI-DialogBox-Background-Dark")
	bottom:SetPoint("TOPLEFT", 7, -7)
	bottom:SetPoint("BOTTOMRIGHT", -7, 7)
	local top = box:CreateTexture(nil, "BACKGROUND", nil, -4)
	top:SetAtlas(GameDialogBackgroundTop or "UI-DiamondDialogBox-Border")
	top:SetAllPoints()
	local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", 0, -18)
	title:SetText(L.RINGS_RENAME_TITLE)
	local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
	edit:SetSize(280, 24)
	edit:SetPoint("TOP", 0, -42)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(Rings.NAME_MAX)
	edit:SetScript("OnEnterPressed", function() closeRename(true) end)
	edit:SetScript("OnEscapePressed", function() closeRename(false) end)
	local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOP", edit, "BOTTOM", 0, -10)
	hint:SetText(L.RINGS_RENAME_HINT)
	box:SetScript("OnHide", function() edit:ClearFocus() end)
	box.edit = edit
	box:Hide()
	renameBox = box
end

local function rename()
	local ring = Rings.Get(selected)
	if not (ring and editable()) then return end
	if not renameBox then buildRename() end
	UI.CloseAll()
	renameBox.id = ring.id
	renameBox:Show()
	renameBox.edit:SetText(ring.name)
	renameBox.edit:SetFocus()
	renameBox.edit:HighlightText()
end

ns.On("FCT_COMBAT_START", function() if renameBox and renameBox:IsShown() then renameBox:Hide() end end)

---------------------------------------------------------------------------------------------------------------------
-- Drawing

local function newListRow(y)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(ROW_W, ROW_H)
	UI.At(row, window, LEFT_X + (LEFT_W - ROW_W) / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.lit = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.lit:SetBlendMode("ADD")
	row.lit:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("LEFT", 8, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", -8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	return row
end

-- The selected ring in the middle, as it shows in game (icons only: states are live in game).
local function drawRing()
	local ring = Rings.Get(selected)
	preview:SetShown(ring ~= nil)
	emptyText:SetShown(ring == nil)
	stepRow:SetShown(ring ~= nil)
	stickRow:SetShown(ring ~= nil)
	for _, button in pairs(buttons) do button:SetEnabled(ring ~= nil) end
	for _, row in ipairs(rows) do
		local lit = row.id ~= nil and row.id == selected
		row.lit:SetShown(lit)
		row.name:SetFontObject(lit and "GameFontNormal" or "GameFontHighlight")
	end
	ringPill:SetShown(ring ~= nil)
	if not ring then return end

	ringPill.text:SetText(ring.name)
	hub.icon:SetTexture(Rings.Icon(ring))
	hub.name:SetText(ring.name)
	stepRow.value:SetText(ring.count)
	stickRow.segments:Select(ring.stick)
	for i, button in ipairs(slotButtons) do
		local shown = i <= ring.count
		button:SetShown(shown)
		if shown then
			local dx, dy = Rings.Dir(ring.count, i)
			local stored = ring.slots[i]
			button:ClearAllPoints()
			button:SetPoint("CENTER", preview, "CENTER", GEO.SLOT_R * dx, GEO.SLOT_R * dy)
			Rings.View.DrawSlot(button.view, stored, Rings.Resolve(stored))
		end
	end
end

local function slotTip(i)
	local stored = Rings.SlotEntry(selected, i)
	local lines = { string.format(L.RINGS_SLOT, i) }
	local entry = Rings.Resolve(stored)
	if entry then lines[#lines + 1] = ns.Actions.Describe(entry) end
	if stored and not Rings.Attributes(entry) then lines[#lines + 1] = L.RINGS_UNUSABLE end
	return { title = stored and stored.name or L.RINGS_EMPTY, lines = lines, actions = { { "PAD1", L.CHOOSE_ACTION }, { "PAD3", L.CLEAR_SLOT } }, side = "right" }
end

local function prompts(region)
	local more, tab, close = { "PAD4", L.MORE }, UI.TabPrompt("rings", -1), { "PAD2", L.CLOSE }
	if region and region.slot then return { { "PAD1", L.CHOOSE_ACTION }, { "PAD3", L.CLEAR_SLOT }, more, tab, close } end
	if region and region.id then return { { "PAD1", L.RINGS_EDIT }, { "PAD3", L.RINGS_RENAME }, more, tab, close } end
	return { { "PAD1", L.SELECT }, more, tab, close }
end

local function refresh()
	local list = Rings.List()
	if not Rings.Get(selected) then selected = list[1] and list[1].id end
	countText:SetText(string.format(L.RINGS_COUNT, #list, Rings.MAX_RINGS))
	local nodes = {}
	for i, row in ipairs(rows) do
		local ring = list[i]
		row:SetShown(ring ~= nil)
		row.id = ring and ring.id
		if ring then
			local id = ring.id
			row.icon:SetTexture(Rings.Icon(ring))
			row.name:SetText(ring.name)
			nodes[#nodes + 1] = UI.Node(window, row, function() if Rings.Get(id) then window:Focus(window.slotNodes[1]) end end, {
				cursorX = 0,
				onFocus = function(on)
					row.wash:SetShown(on)
					if not (on and selected ~= id) then return end
					selected = id
					drawRing()
				end,
				tip = function()
					local current = Rings.Get(id)
					return { title = current and current.name or "", lines = { string.format(L.RINGS_ROW_TIP, current and current.count or 0, Rings.BindingCount(id)) }, actions = { { "PAD1", L.RINGS_EDIT }, { "PAD3", L.RINGS_RENAME } }, side = "right" }
				end,
			})
		end
	end
	newRow:SetShown(#list < Rings.MAX_RINGS)
	newRow:ClearAllPoints()
	UI.At(newRow, window, LEFT_X + (LEFT_W - ROW_W) / 2, LIST_Y + #list * ROW_PITCH)
	nodes[#nodes + 1] = UI.Node(window, newRow, newRing, { cursorX = 0, onFocus = function(on) newRow.wash:SetShown(on) end, tip = { title = L.RINGS_NEW, lines = { L.RINGS_NEW_TIP }, side = "right" } })
	drawRing()

	window.slotNodes = {}
	for i, button in ipairs(slotButtons) do
		local node = UI.Node(window, button, function() pick(i) end, {
			cursorX = 0, tip = function() return slotTip(i) end,
			onFocus = function(on)
				Rings.View.SetFocus(button.view, on)
				local stored = on and Rings.SlotEntry(selected, i)
				if on then hub.slotName:SetText(stored and stored.name or L.RINGS_EMPTY) end
				if not on then hub.slotName:SetText("") end
			end,
		})
		window.slotNodes[i] = node
		nodes[#nodes + 1] = node
	end
	nodes[#nodes + 1] = UI.Node(window, stepRow, function() end, {
		cursorX = 0, noSide = true, onDir = stepCount, onFocus = function(on) stepRow.wash:SetShown(on) end,
		tip = { title = L.RINGS_SLOTS, lines = { string.format(L.RINGS_SLOTS_TIP, Rings.MIN_SLOTS, Rings.MAX_SLOTS) }, side = "right" },
	})
	nodes[#nodes + 1] = UI.Node(window, stickRow, function() stepStick(1, true) end, {
		cursorX = 0, noSide = true, onDir = stepStick, onFocus = function(on) stickRow.wash:SetShown(on) end,
		tip = { title = L.RINGS_STICK, lines = { L.RINGS_STICK_TIP }, side = "right" },
	})
	nodes[#nodes + 1] = UI.Node(window, buttons.rename, rename, { cursorX = 0 })
	nodes[#nodes + 1] = UI.Node(window, buttons.icon, pickIcon, { cursorX = 0, tip = { title = L.RINGS_ICON_TITLE, lines = { L.RINGS_ICON_TIP }, side = "right" } })
	nodes[#nodes + 1] = UI.Node(window, buttons.delete, delete, { cursorX = 0, tip = { title = L.RINGS_DELETE, lines = { L.RINGS_DELETE_TIP }, side = "right" } })
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(prompts(window.focus and window.focus.region)) end
end

-- A setting row under the ring: its label on the left, its control on the right.
local function settingRow(y, label)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(SETTING_W, ROW_H)
	UI.At(row, window, RIGHT_X + (RIGHT_W - SETTING_W) / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 10, 0)
	row.label:SetText(label)
	return row
end

local function stepper(y)
	local row = settingRow(y, L.RINGS_SLOTS)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.value:SetPoint("RIGHT", -40, 0)
	for step, code in pairs({ [-1] = "DL", [1] = "DR" }) do
		local arrow = CreateFrame("Button", nil, row)
		arrow:SetSize(26, ROW_H)
		arrow:SetPoint("RIGHT", row, "RIGHT", step < 0 and -82 or -6, 0)
		arrow:SetScript("OnClick", function() stepCount(step) end)
		UI.Glyph(arrow, 16, code):SetPoint("CENTER")
	end
	return row
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.rings then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(L.RINGS_TITLE)
	countText = UI.Text(window, "GameFontNormal", 24, 31, "")
	UI.Text(window, "GameFontDisableSmall", 24, 58, L.RINGS_HINT)
	UI.Inset(window, LEFT_X, TOP_Y, LEFT_W, BOX_H)
	UI.Inset(window, RIGHT_X, TOP_Y, RIGHT_W, BOX_H)
	UI.SectionHeader(window, LEFT_X + (LEFT_W - PILL_W) / 2, TOP_Y + 12, PILL_W, L.RINGS_LIST)
	ringPill = UI.SectionHeader(window, RIGHT_X + (RIGHT_W - PILL_W) / 2, TOP_Y + 12, PILL_W, "")
	ringPill.text:SetWidth(PILL_W - 24)
	ringPill.text:SetWordWrap(false)

	rows = {}
	for i = 1, Rings.MAX_RINGS do
		local row = newListRow(LIST_Y + (i - 1) * ROW_PITCH)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouseButton)
			selected = self.id
			if mouseButton == "RightButton" then return rename() end
			window:Refresh()
		end)
		rows[i] = row
	end
	newRow = newListRow(LIST_Y)
	newRow.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	newRow.name:SetText(L.RINGS_NEW)
	newRow.name:SetFontObject("GameFontNormal")
	newRow.lit:Hide()
	newRow:SetScript("OnClick", newRing)

	preview = CreateFrame("Frame", nil, window)
	preview:SetSize(2 * GEO.DISC, 2 * GEO.DISC)
	UI.At(preview, window, RIGHT_X + RIGHT_W / 2 - GEO.DISC, DISC_Y)
	hub = Rings.View.Disc(preview)
	slotButtons = {}
	for i = 1, Rings.MAX_SLOTS do
		local button = CreateFrame("Button", nil, preview)
		button:SetSize(GEO.ICON, GEO.ICON)
		button.slot = i
		button.view = Rings.View.NewSlot(button)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "RightButton" then return clearSlot(i) end
			pick(i)
		end)
		slotButtons[i] = button
	end
	emptyText = UI.CenterText(window, "GameFontDisable", RIGHT_X, DISC_Y + GEO.DISC, RIGHT_W, L.RINGS_NONE)
	stepRow = stepper(STEP_Y)
	stickRow = settingRow(STICK_Y, L.RINGS_STICK)
	local specs = {}
	for i, stick in ipairs(Rings.STICKS) do specs[i] = { stick, L.RINGS_STICK_NAMES[stick] } end
	stickRow.segments = UI.Segments(stickRow, specs, SETTING_W - #specs * STICK_SEG_W - 4, 1, STICK_SEG_W, function(stick)
		if editable() and Rings.Get(selected) then report(Rings.SetStick(selected, stick)) end
	end)
	buttons = {}
	for i, spec in ipairs({ { "rename", L.RINGS_RENAME, rename }, { "icon", L.RINGS_ICON, pickIcon }, { "delete", L.RINGS_DELETE, delete } }) do
		local button = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate")
		button:SetSize(BUTTON_W, 22)
		UI.At(button, window, RIGHT_X + RIGHT_W / 2 + (i - 2.5) * (BUTTON_W + 12) + 6, BUTTONS_Y)
		button:SetText(spec[2])
		button:SetScript("OnClick", spec[3])
		buttons[spec[1]] = button
	end

	window.OnRefresh = refresh
	window.OnFocusChanged = function() if not UI.DialogShown() then window:SetPrompts(prompts(window.focus and window.focus.region)) end end
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		local region = window.focus and window.focus.region
		if key == "PAD3" and region and region.slot then
			clearSlot(region.slot)
			return true
		end
		if key == "PAD3" and region and region.id then
			rename()
			return true
		end
		if key ~= "PAD4" then return end
		local more = { { id = "ringnew", name = L.RINGS_NEW, detail = L.RINGS_NEW_TIP, run = newRing } }
		if Rings.Get(selected) then
			more[2] = { id = "ringrename", name = L.RINGS_RENAME_TITLE, detail = L.RINGS_RENAME_HINT, run = rename }
			more[3] = { id = "ringicon", name = L.RINGS_ICON_TITLE, detail = L.RINGS_ICON_TIP, run = pickIcon }
			more[4] = { id = "ringdelete", name = L.RINGS_DELETE, detail = L.RINGS_DELETE_TIP, run = delete }
		end
		UI.OpenMore(window, more)
		return true
	end
end

-- id: the ring to show selected (the first one otherwise).
function S.Open(id)
	if not ns.db then return end
	if not window then build() end
	selected = id or selected
	UI.Show(window)
end

function ns.commands.rings() S.Open() end

-- The last side tab (Bindings, Touch, Keyboard, Rings, of those loaded); L1/R1 step through them.
UI.AddTab({ "Interface\\Icons\\INV_Jewelry_Ring_03", L.RINGS_TAB, function() S.Open() end, rings = true, order = 4, prompt = L.RINGS_TAB })
