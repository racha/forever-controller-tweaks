-- Forever Controller Tweaks action picker: a modal list anchored at a crossbar cell, in native dropdown art
-- (common-dropdown-bg, UI-Character-Info-Title header, UI-QuestTitleHighlight focus, radial tick on the current
-- entry). Controller first: D-pad moves (hold repeats) with wrap, L1/R1 (or D-pad left/right) switch category, A chooses,
-- X clears the cell, Y shows details, B closes. Mouse: hover, click, wheel, click outside closes.
-- Any cell takes any catalog entry (the face actions are in it): an entry the router must carry (Face.Routable: a
-- face button's base layer, or a face action anywhere) goes to Face.SetCellEntry, every other one into the storage
-- slot (Actions.Assign). A spell group opens its ranks on a second page of the same list.
-- List mode (opts.list) shows any one list in the same look, e.g. Bindings' role list: no clear row, no categories,
-- the focused entry's details beside it, and A hands the entry to list.onPick.
local _, ns = ...
local UI = ns.UI
local L, Layout = UI.L, ns.Layout

local Picker = {}
UI.ActionPicker = Picker

local ROWS, ROW_HEIGHT, WIDTH, HEADER = 12, 24, 320, 44
-- Header: L1 glyph (x 14-32), previous name, current name (at most CENTER_MAX wide), next name, R1 glyph.
local CENTER_MAX, NAME_GAP, GLYPH_EDGE = 140, 8, 36

local frame, state

-- A target cell: { code = "FT"..., layer = "T" | "L" | "R" | "B", slot = storage slot, pos = base face position,
-- page = the Bindings page shown (a routed entry belongs to that page) }, or a touch bar button { touch = { side,
-- index, layer } } (Touch tab; layer T unless Touch takes layers), or a ring slot { ring = { id, index } } (Rings tab).
local POS_CODE = {}
for code, pos in pairs(UI.CODE_POS) do POS_CODE[pos] = code end

-- The routed entry of a cell: { id, name, icon, kind } or nil.
function Picker.CellEntry(t)
	if t.ring then return ns.Rings.SlotEntry(t.ring.id, t.ring.index) end
	if t.touch then return ns.Touch and ns.Touch.Entry(t.touch.side, t.touch.index, t.touch.layer) end
	return ns.Face.CellEntry(t.code, t.layer, t.page)
end

-- Sets (or with nil clears) a routed cell on its page, or a touch button.
local function setEntry(t, entry)
	if t.ring then return ns.Rings.SetSlot(t.ring.id, t.ring.index, entry) end
	if not t.touch then return ns.Face.SetCellEntry(t.code, t.layer, entry, t.page) end
	if not ns.Touch then return nil, L.TOUCH_MISSING end
	return ns.Touch.SetEntry(t.touch.side, t.touch.index, entry, t.touch.layer)
end

local function assign(t, entry)
	if t.touch or t.ring or ns.Face.Routable(t.code, t.layer, entry) then return setEntry(t, entry) end
	if not t.slot then return nil, L.NO_SLOT end

	local ok, err = ns.Actions.Assign(t.slot, entry)
	if ok and Picker.CellEntry(t) then setEntry(t, nil) end
	return ok, err
end

local function report(ok, err)
	if ok then return true end
	if err then UI.Dialog():Open(state and state.window or UI.Current(), { text = err, buttons = { L.CLOSE } }) end
end

-- The catalog ids of the four face actions (Actions.GAME: Jump and Interact are face kind, Inspect and Back click
-- their top-bar button).
-- A base face cell without an entry holds its face action; a highest-rank slot reads as its spell group's id.
local function currentId(t)
	local entry = Picker.CellEntry(t)
	if entry then return entry.id end
	if t.pos then
		local action = Layout.Face()[t.pos]
		return action and "face:" .. action
	end
	return t.slot and ns.Actions.CurrentId(t.slot)
end

local function holds(entry, id)
	if entry.id == id then return true end
	for _, rank in ipairs(entry.ranks or {}) do if rank.id == id then return true end end
end

-- Focus the current entry: its row, or for a ranked spell its group's row with the ranks page opened on it.
local function build()
	state.categories = ns.Actions.Catalog()
	-- A ring slot can't open another ring.
	if state.ring then
		local list = {}
		for _, category in ipairs(state.categories) do
			if category.name ~= "Rings" then list[#list + 1] = category end
		end
		state.categories = list
	end
	local wanted = currentId(state)
	state.category, state.index, state.current = 1, 1, wanted
	if not wanted then return end
	for c = #state.categories, 1, -1 do
		for i, entry in ipairs(state.categories[c].entries) do
			if holds(entry, wanted) then state.category, state.index, state.preGroup = c, i + 1, entry.ranks and entry end
		end
	end
end

-- The list shows a category (row 1 clears the cell) or, on the ranks page, one spell group's ranks.
local function items() return state.group and state.group.ranks or state.categories[state.category].entries end

local function clearRow() return (state.group or state.list) and 0 or 1 end

local function categoryName(category) return category.name end

-- The neighbours L1/R1 switch to (they wrap), faded beside the glyphs; none on the ranks page or with one category.
local function neighbour(step)
	local n = #state.categories
	if state.group or n < 2 then return end
	return state.categories[(state.category - 1 + step) % n + 1]
end

local function drawHeader(title)
	local header = frame.header
	header.text:SetWidth(0)
	header.text:SetText(title)
	local centerWidth = math.min(header.text:GetStringWidth(), CENTER_MAX)
	header.text:SetWidth(centerWidth)
	local side = WIDTH / 2 - centerWidth / 2 - NAME_GAP - GLYPH_EDGE
	for step, link in pairs({ [-1] = frame.previousName, [1] = frame.nextName }) do
		local category = neighbour(step)
		link:SetWidth(math.max(side, 0))
		link.text:SetText(category and categoryName(category) or "")
		link:SetShown(category ~= nil and side > 0)
	end
	frame.previous:SetShown(not (state.group or state.list))
	frame.next:SetShown(not (state.group or state.list))
	frame.previous:SetDisabled(not neighbour(-1))
	frame.next:SetDisabled(not neighbour(1))
end

local function row(i)
	local r = frame.rows[i]
	if r then return r end

	r = CreateFrame("Button", nil, frame)
	r:SetSize(WIDTH - 20, ROW_HEIGHT)
	r:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(HEADER + (i - 1) * ROW_HEIGHT))
	r.highlight = r:CreateTexture(nil, "BACKGROUND")
	r.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	r.highlight:SetBlendMode("ADD")
	r.highlight:SetAllPoints()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 4, 0)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.note = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.note:SetPoint("RIGHT", -24, 0)
	r.tick = r:CreateTexture(nil, "OVERLAY")
	r.tick:SetAtlas("common-dropdown-icon-radialtick-yellow")
	r.tick:SetSize(16, 16)
	r.tick:SetPoint("RIGHT", -4, 0)
	-- Blizzard Menu's submenu arrow (MenuVariants.CreateSubmenuArrow).
	r.arrow = r:CreateTexture(nil, "ARTWORK")
	r.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	r.arrow:SetSize(16, 16)
	r.arrow:SetPoint("RIGHT", -4, 0)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnEnter", function(self) if self.index then Picker.Focus(self.index) end end)
	r:SetScript("OnClick", function(self, button)
		if button == "RightButton" then return Picker.Back() end
		if self.index then Picker.Choose(self.index) end
	end)
	frame.rows[i] = r
	return r
end

-- In a category index 1 is "Clear slot" and the entries follow; on the ranks page the ranks start at 1.
local function entryAt(index) return items()[index - clearRow()] end

local function count() return #items() + clearRow() end

local function draw()
	local category, group = state.categories[state.category], state.group
	drawHeader(group and group.name or categoryName(category))
	frame.back:SetShown(group ~= nil)

	local total = count()
	state.offset = math.max(0, math.min(state.offset or 0, total - ROWS))
	if state.index <= state.offset then state.offset = state.index - 1 end
	if state.index > state.offset + ROWS then state.offset = state.index - ROWS end

	for i = 1, ROWS do
		local r, index = row(i), state.offset + i
		r.index = index <= total and index or nil
		r:SetShown(r.index ~= nil)
		if r.index then
			local entry = entryAt(index)
			r.icon:SetTexture(entry and entry.icon or nil)
			if not entry then r.icon:SetAtlas("common-icon-redx") end
			r.icon:SetDesaturated(entry and entry.disabled or false)
			r.icon:SetVertexColor(unpack(entry and entry.color or { 1, 1, 1 }))
			local note, isGroup = entry and entry.note, entry and entry.ranks ~= nil
			-- A note greys the entry (it can't go here), unless it only says what choosing it does (entry.live).
			local grey = entry and (entry.disabled or note and not entry.live)
			r.name:SetText(entry and entry.name or (state.pos and L.RESTORE_DEFAULT or L.CLEAR_SLOT))
			r.name:SetFontObject(grey and "GameFontDisable" or "GameFontHighlight")
			r.name:SetWidth(WIDTH - 20 - 30 - 30 - (note and 110 or 0))
			r.note:SetText(note or "")
			r.arrow:SetShown(isGroup)
			r.tick:ClearAllPoints()
			r.tick:SetPoint("RIGHT", isGroup and -22 or -4, 0)
			r.tick:SetShown(entry and state.current and holds(entry, state.current))
			r.highlight:SetShown(index == state.index)
		end
	end
	frame.up:SetShown(state.offset > 0)
	frame.down:SetShown(state.offset + ROWS < total)

	local focused = frame.rows[state.index - state.offset]
	if focused then state.window.cursor:Attach(focused, 0) end
	if state.info then Picker.Info() else UI.HideTooltip() end
end

function Picker.Focus(index)
	state.index = index
	draw()
end

-- dy > 0 is up; wraps at the ends.
-- dy > 0 is up. Single steps wrap at the ends; pages (|dy| > 1, L2/R2) stop at them and double after a few
-- repeats. A held left/right never repeats a category switch.
local PAGE, PAGE_FAST, FAST_AFTER = 10, 20, 3

function Picker.Move(_, dx, dy, repeats)
	if dx ~= 0 then
		if repeats then return end
		return Picker.Category(dx > 0 and 1 or -1)
	end
	local total = count()
	if math.abs(dy) > 1 then
		local step = (repeats or 0) >= FAST_AFTER and PAGE_FAST or PAGE
		state.index = math.max(1, math.min(total, state.index - (dy > 0 and step or -step)))
	else
		state.index = (state.index - (dy > 0 and 1 or -1) - 1) % total + 1
	end
	draw()
end

local function setPrompts()
	if state.list then return state.window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD2", L.BACK } }) end
	local clear = state.pos and L.RESTORE_DEFAULT or L.CLEAR_SLOT
	if state.group then return state.window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD3", clear }, { "PAD4", L.INFO }, { "PADRTRIGGER", L.PAGE }, { "PAD2", L.BACK } }) end
	state.window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD3", clear }, { "PAD4", L.INFO }, { "PADRSHOULDER", L.CATEGORY }, { "PADRTRIGGER", L.PAGE }, { "PAD2", L.BACK } })
end

-- The ranks page: opened from a spell group's row, Back returns to that row.
local function openGroup(entry)
	state.group, state.groupFrom = entry, { index = state.index, offset = state.offset }
	state.index, state.offset = 1, 0
	for i, rank in ipairs(entry.ranks) do if rank.id == state.current then state.index = i end end
	setPrompts()
	draw()
end

function Picker.Back()
	if not state then return end
	if not state.group then return Picker.Close() end

	state.index, state.offset = state.groupFrom.index, state.groupFrom.offset
	state.group, state.groupFrom = nil, nil
	setPrompts()
	draw()
end

-- No category switch on the ranks page or in list mode (one list), so left/right never resets the focus there.
function Picker.Category(step)
	if state.group or state.list then return end
	local n = #state.categories
	state.category = (state.category - 1 + step) % n + 1
	state.index, state.offset = 1, 0
	draw()
end

function Picker.Info()
	local entry = entryAt(state.index)
	state.info = true
	local spec = { title = L.CLEAR_SLOT, lines = { L.CLEAR_TIP } }
	if state.list then spec = { title = entry.name, lines = { entry.detail } }
	elseif entry and entry.ranks then spec = { title = entry.name, lines = { entry.category, string.format(L.RANKS_TIP, #entry.ranks) } }
	elseif entry then spec = { title = entry.name, lines = { entry.category, ns.Actions.Describe(entry) } } end
	if entry and entry.note then spec.lines[#spec.lines + 1] = entry.note end
	spec.side = state.side
	UI.Tooltip(frame, spec)
end

-- Clearing remembers what was there (one level): Picker.Undo puts it back.
local lastClear

-- A routed cell (or a base face position, which gets its default action back) clears its entry; any other cell
-- empties its storage slot.
function Picker.ClearCell(t)
	if InCombatLockdown() then return end
	local entry = Picker.CellEntry(t)
	if entry or t.pos or t.touch or t.ring then
		lastClear = { target = t, entry = entry }
		return report(setEntry(t, nil))
	end
	if not t.slot then return end
	lastClear = { target = t, id = ns.Actions.CurrentId(t.slot) }
	report(ns.Actions.Clear(t.slot))
end

function Picker.CanUndo() return lastClear ~= nil and (lastClear.entry ~= nil or lastClear.id ~= nil) end

local function find(id)
	for _, category in ipairs(ns.Actions.Catalog()) do
		for _, entry in ipairs(category.entries) do
			if entry.id == id then return entry end
			for _, rank in ipairs(entry.ranks or {}) do if rank.id == id then return rank end end
		end
	end
end

-- What Undo would put back, by name.
function Picker.UndoName()
	if not Picker.CanUndo() then return end
	local entry = lastClear.entry or find(lastClear.id)
	return entry and entry.name
end

function Picker.Undo()
	local undo = lastClear
	if InCombatLockdown() or not Picker.CanUndo() then return end
	lastClear = nil
	if undo.entry then return report(setEntry(undo.target, undo.entry)) end
	local entry = find(undo.id)
	if entry then report(ns.Actions.Assign(undo.target.slot, entry)) end
end

function Picker.Clear()
	local done = state.onDone
	Picker.ClearCell({ code = state.code, layer = state.layer, slot = state.slot, pos = state.pos, page = state.page, touch = state.touch, ring = state.ring })
	Picker.Close()
	if done then done() end
end

function Picker.Choose(index)
	if InCombatLockdown() then return end

	local entry, done = entryAt(index), state.onDone
	if not entry then return Picker.Clear() end
	if entry.ranks then return openGroup(entry) end
	-- A disabled entry (e.g. a command that needs a key binding) only shows its note; the focus stays on it.
	if entry.disabled then return Picker.Info() end
	if state.list then
		local pick = state.list.onPick
		Picker.Close()
		return pick(entry)
	end
	local ok, err = assign(state, entry)
	Picker.Close()
	report(ok, err)
	if done then done() end
end

function Picker.OnPad(_, key)
	if key == "PAD1" then return Picker.Choose(state.index) end
	if key == "PAD2" then return Picker.Back() end
	if key == "PAD3" then return not state.list and Picker.Clear() end
	if key == "PAD4" then
		if state.info then
			state.info = false
			return UI.HideTooltip()
		end
		return Picker.Info()
	end
	if key == "PADLSHOULDER" then return Picker.Category(-1) end
	if key == "PADRSHOULDER" then return Picker.Category(1) end
	local window = state.window
	local dir = key == "PADDUP" and 1 or key == "PADDDOWN" and -1 or key == "PADLTRIGGER" and PAGE or key == "PADRTRIGGER" and -PAGE
	if dir then
		window.repeatKey = key
		return window:StartRepeat({ 0, dir })
	end
	if key == "PADDLEFT" or key == "PADDRIGHT" then return Picker.Category(key == "PADDLEFT" and -1 or 1) end
end

local function create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, HEADER + ROWS * ROW_HEIGHT + 12)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		state.offset = math.max(0, (state.offset or 0) - delta * 3)
		local total = count()
		state.offset = math.min(state.offset, math.max(0, total - ROWS))
		if state.index <= state.offset or state.index > state.offset + ROWS then state.index = state.offset + 1 end
		draw()
	end)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("common-dropdown-bg")
	bg:SetAlpha(0.925)
	bg:SetPoint("TOPLEFT", -10, 3)
	bg:SetPoint("BOTTOMRIGHT", 10, -3)
	frame.header = UI.SectionHeader(frame, 0, 2, WIDTH, "")
	frame.previous = UI.Glyph(frame.header, 18, "L1")
	frame.previous:SetPoint("LEFT", frame.header, "LEFT", 14, 1)
	frame.next = UI.Glyph(frame.header, 18, "R1")
	frame.next:SetPoint("RIGHT", frame.header, "RIGHT", -14, 1)
	frame.header.text:SetWordWrap(false)
	for step, spec in pairs({ [-1] = { "LEFT", GLYPH_EDGE }, [1] = { "RIGHT", -GLYPH_EDGE } }) do
		local link = CreateFrame("Button", nil, frame.header)
		link:SetHeight(20)
		link:SetPoint(spec[1], frame.header, spec[1], spec[2], 1)
		link.text = link:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		link.text:SetAllPoints()
		link.text:SetJustifyH(spec[1])
		link.text:SetWordWrap(false)
		link:SetScript("OnClick", function() Picker.Category(step) end)
		if step < 0 then frame.previousName = link else frame.nextName = link end
	end
	frame.back = CreateFrame("Button", nil, frame.header)
	frame.back:SetSize(20, 20)
	frame.back:SetPoint("LEFT", frame.header, "LEFT", 12, 1)
	frame.back:SetNormalAtlas("common-icon-backarrow")
	frame.back:SetHighlightAtlas("common-icon-backarrow", "ADD")
	frame.back:SetScript("OnClick", function() Picker.Back() end)
	frame.back:Hide()
	frame.up = frame:CreateTexture(nil, "OVERLAY")
	frame.up:SetAtlas("minimal-scrollbar-arrow-top", true)
	frame.up:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -HEADER + 2)
	frame.down = frame:CreateTexture(nil, "OVERLAY")
	frame.down:SetAtlas("minimal-scrollbar-arrow-bottom", true)
	frame.down:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 4)
	frame.rows = {}

	-- A click anywhere else closes the picker without a change.
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetScript("OnClick", function() Picker.Close() end)
	catcher:Hide()
	frame.catcher = catcher
	frame:Hide()
end

-- opts = { window, cell, code, layer, slot = storage slot, pos = base face position, touch, ring }; onDone after a change.
-- Onboarding passes only pos: that is the base (top bar) layer of the face button.
-- List mode: opts = { window, cell (focus returns there), list = { title, entries, current = id, onPick(entry) },
-- point = an anchor instead of beside the cell }. Entries: { id, name, icon, color, note, live, detail, disabled }.
function Picker.Open(opts)
	if InCombatLockdown() then return end
	if not frame then create() end
	if state then Picker.Close() end

	local code = opts.code or POS_CODE[opts.pos]
	state = { window = opts.window, cell = opts.cell, code = code, layer = opts.layer or "T", slot = opts.slot, pos = opts.pos, onDone = opts.onDone, offset = 0, list = opts.list, page = opts.page, touch = opts.touch, ring = opts.ring }
	local list = state.list
	if list then
		state.categories, state.category, state.index, state.current, state.info = { { name = list.title, entries = list.entries } }, 1, 1, list.current, true
		for i, entry in ipairs(list.entries) do if entry.id == list.current then state.index = i end end
	else
		build()
	end
	frame:SetHeight(HEADER + (list and math.min(ROWS, #list.entries) or ROWS) * ROW_HEIGHT + 12)
	local window = state.window
	local cellX = select(1, opts.cell:GetCenter()) or 0
	local windowX = select(1, window:GetCenter()) or 0
	frame:SetScale(window:GetScale())
	frame:ClearAllPoints()
	if opts.point then
		frame:SetPoint(unpack(opts.point))
		state.side = "right"
	elseif cellX <= windowX then
		frame:SetPoint("TOPLEFT", opts.cell, "TOPRIGHT", 8, 0)
		state.side = "right"
	else
		frame:SetPoint("TOPRIGHT", opts.cell, "TOPLEFT", -8, 0)
		state.side = "left"
	end
	frame.catcher:Show()
	UI.RaiseAbove(frame.catcher, window, "catcher")
	UI.RaiseAbove(frame, window, "picker")
	frame:Show()
	window.modal = Picker
	UI.HideTooltip()
	if state.preGroup then return openGroup(state.preGroup) end
	setPrompts()
	draw()
end

-- Closing returns the focus to the cell and redraws the window.
function Picker.Close()
	if not state then return end
	local window, cell = state.window, state.cell
	state = nil
	frame:Hide()
	frame.catcher:Hide()
	UI.HideTooltip()
	window.modal = nil
	window.focus = { region = cell }
	if window:IsShown() then window:Refresh() end
end

