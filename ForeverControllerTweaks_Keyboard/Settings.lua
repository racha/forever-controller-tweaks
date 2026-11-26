-- Forever Controller Tweaks "Keyboard" side tab (design/keyboard.md section 7, artboards 7a-c), in the Touch tab's
-- language: the hint and Quick messages (top right) in the header, a preview of the disc at the current layout and
-- scale on the left, the settings on the right, one value per row (On, Open, Layout, Scale, Word suggestions): up/down
-- move between rows, A opens a dropdown's list or grabs the slider (then left/right change it). The buttons are always
-- the defaults and the placement always Auto. Quick messages opens a page of the player's own lines per situation, typed
-- in our own box with the keyboard. Saves to ForeverControllerTweaksDB.keyboard through K.Settings.
local ns = ForeverControllerTweaks
local UI, K = ns.UI, ns.Keyboard
local L, P = UI.L, K.Library

local S = {}
K.SettingsTab = S

local T = {
	TAB = "Keyboard", TITLE = "Controller Tweaks · Keyboard", ON = "On", OPEN = "Open",
	HINT = "An on-screen keyboard for chat and text boxes, while the Gamepad UI is on.", SECTION = "Keyboard",
	LAYOUT = "Layout", SCALE = "Scale", SUGGEST = "Word suggestions", RESET = "Reset keyboard to defaults",
	RESET_TEXT = "Reset the keyboard's settings to the defaults?", SCALE_TIP = "Press A, then D-pad left and right change it. On a phone, 1.25 reads best.",
	QUICK = "Quick messages", QUICK_TIP = "Your own lines for each situation. They come first in its suggestions.",
	QUICK_TITLE = "Controller Tweaks · Keyboard · Quick messages", SITUATION = "Situation", YOURS = "Yours", RESTORE = "Restore hidden built-in lines (%d)",
	ADD = "Add a line", EDIT = "Edit", DELETE = "Delete", MOVE = "Move", DONE = "Done", NONE = "None",
	QUICK_HINT = "Your lines come first in this situation's suggestions, on the channel its lines use.",
	NEW_TITLE = "New quick message · %s", EDIT_TITLE = "Edit quick message · %s",
	EDIT_HINT = "Send saves, Close cancels.", DELETE_TEXT = "Delete this quick message?",
	REFUSED = "That line can't be saved: it is empty, a slash command, already in the list, or the list is full.",
	CHOICES = { controller = "With the controller", always = "Always", ring = "Ring", compact = "Compact" },
	SITUATIONS = {
		anywhere = "Always", ready = "Ready check", resurrect = "Resurrection offered", summon = "Summon offered", invite = "Group invite",
		trade = "Trade window", duel = "Duel request", roll = "Loot roll", proposal = "Queue popped", bosskill = "Boss killed", wipe = "Group wiped",
		levelup = "Level up", achievement = "Achievement earned", looted = "Item looted", buffed = "Buffed by a player", dead = "Dead",
		combat = "In combat", newgroup = "Just joined a group", battleground = "Battleground or arena", dungeon = "Dungeon", raid = "Raid",
		progress = "Quest progress", quest = "Tracking a quest", whisper = "Whispering", friend = "Friendly player targeted",
		enemy = "Enemy targeted", npc = "Near an NPC, grouped", group = "In a group", queue = "In a queue", city = "In a city",
		guild = "Guild chat", world = "Out in the world, solo",
	},
}

local RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H, LEFT_X, LEFT_W = 604, 84, 572, 526, 24, 560
local ROW_W, ROW_H, ROW_PITCH, SCALE_MIN, SCALE_MAX, SCALE_STEP = 520, 28, 44, 0.75, 1.5, 0.05
-- A row's control starts CONTROL_X in; dropdown values are CHOICE_W wide, the slider SLIDER_W.
local CONTROL_X, CHOICE_W, SLIDER_W = 230, 160, 220
-- The header button (top right).
local QUICK_W = 160
local OPEN, LAYOUT = { "controller", "always" }, { "ring", "compact" }
-- The quick messages page: the situations in a left inset, their lines in a right one (the Rings tab's), VISIBLE rows
-- of each shown from LIST_Y, MARGIN in from the inset.
local Q_LEFT_X, Q_LEFT_W, Q_RIGHT_X, Q_RIGHT_W, LINE_H, LINE_PITCH = 24, 300, 344, 832, 22, 23
local LIST_Y, VISIBLE, MARGIN = RIGHT_Y + 58, 19, 12
-- A column's scroll bar: its left BAR_X in from the inset's right; rows give up BAR_ROOM while it shows.
local BAR_X, BAR_ROOM = 20, 16

local window, onRow, openRow, layoutRow, suggestRow, preview, scaleRow, resetButton, quickButton
local quick, linesHeader, sitRows, lineRows, editor, moving
local bars = {}
-- Always (anywhere) first, then the situations most specific first.
local SITS, sit = { "anywhere" }, 1
for _, spec in ipairs(P.SITUATIONS) do if spec.id ~= "anywhere" then SITS[#SITS + 1] = spec.id end end

local function settings()
	if not ns.db then return end
	ns.db.keyboard = K.Settings(ns.db.keyboard)
	return ns.db.keyboard
end

local function changed()
	if K.View and K.View.Wake then K.View.Wake() end
	if K.View and K.View.Place then K.View.Place() end
	if window and window:IsShown() then window:Refresh() end
end

local function set(key, value)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	settings()[key] = value
	changed()
end

local function newRow(y, label, x, parent, height)
	parent = parent or window
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_W, height or ROW_H)
	UI.At(row, parent, x or RIGHT_X + (RIGHT_W - ROW_W) / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 10, 0)
	row.label:SetText(label)
	return row
end

-- A row's control, CONTROL_X in and centred on it.
local function control(row, widget)
	widget:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	row.control = widget
	return widget
end

-- The preview: the disc, rim, hub and the lower-case clusters at the current layout and scale (fit to the inset).
local function buildPreview()
	preview = CreateFrame("Frame", nil, window)
	preview:SetSize(2 * K.DISC_R, 2 * K.DISC_R)
	UI.At(preview, window, LEFT_X + LEFT_W / 2 - K.DISC_R, RIGHT_Y + RIGHT_H / 2 - K.DISC_R)
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
	-- The rim (8 past the disc) stays inside the inset.
	local fit = (RIGHT_H - 16) / (2 * K.DISC_R + 8)
	preview:SetScale(math.min(k, fit))
	-- Scaled around its centre: the frame's offset is in its own (scaled) units.
	local scale = preview:GetScale()
	preview:ClearAllPoints()
	UI.At(preview, window, (LEFT_X + LEFT_W / 2) / scale - K.DISC_R, (RIGHT_Y + RIGHT_H / 2) / scale - K.DISC_R)
	local sets = K.CHARSETS.lower
	for i, cluster in ipairs(preview.keys) do
		for j, key in ipairs(cluster.keys) do
			key:SetShown(not compact)
			K.View.KeyLabel(key, sets[i][j], "idle", compact)
		end
		cluster.range:SetText(compact and sets[i][1] .. "–" .. sets[i][4] or "")
	end
end

-- One step through a choice's options; false past an end (nothing changes), round with wrap (a click on the value).
-- A choice's dropdown list: its options' labels with the saved one current; a pick saves it.
local function choiceOf(key, options)
	return {
		options = function()
			local labels, value, current = {}, settings()[key], nil
			for i, option in ipairs(options) do
				labels[i] = T.CHOICES[option]
				if option == value then current = i end
			end
			return labels, current
		end,
		pick = function(index) set(key, options[index]) end,
	}
end

local function toggle(key) set(key, not settings()[key]) end

local function stepScale(step)
	local s = settings()
	local value = math.floor((s.scale + step * SCALE_STEP) * 100 + 0.5) / 100
	if value < SCALE_MIN or value > SCALE_MAX then return false end
	set("scale", value)
end

local function reset()
	UI.Dialog():Open(window, { text = T.RESET_TEXT, buttons = { L.RESET, L.CANCEL }, on1 = function()
		local s = settings()
		for key, value in pairs(K.DEFAULTS) do s[key] = value end
		changed()
	end })
end

local function prompts() return { { "PAD1", L.SELECT }, { "PAD3", T.QUICK }, { "PAD4", L.MORE }, UI.TabPrompt("keyboard", -1), { "PAD2", L.CLOSE } } end

local function refresh()
	local s = settings()
	if not s then return end
	onRow.control:Set(s.enabled)
	openRow.control:Set(T.CHOICES[s.open])
	layoutRow.control:Set(T.CHOICES[s.layout])
	suggestRow.control:Set(s.suggestions)
	scaleRow.control:Set(s.scale, string.format("%.2f", s.scale))
	drawPreview(s)
	local nodes = {
		UI.Node(window, quickButton, function() S.OpenQuick() end, { cursorX = 0, tip = { title = T.QUICK, lines = { T.QUICK_TIP }, side = "left" } }),
		UI.Node(window, onRow, function() toggle("enabled") end, { cursorX = 0, onFocus = function(on) onRow.wash:SetShown(on) end }),
		UI.Node(window, openRow, function() openRow.control:Open() end, {
			cursorX = 0, choice = true, onFocus = function(on) openRow.wash:SetShown(on) openRow.control:SetFocused(on) end,
		}),
		UI.Node(window, layoutRow, function() layoutRow.control:Open() end, {
			cursorX = 0, choice = true, onFocus = function(on) layoutRow.wash:SetShown(on) layoutRow.control:SetFocused(on) end,
		}),
		UI.Node(window, scaleRow, nil, {
			cursorX = 0, onDir = stepScale, onFocus = function(on) scaleRow.wash:SetShown(on) end,
			tip = { title = T.SCALE, lines = { T.SCALE_TIP }, side = "left" },
		}),
		UI.Node(window, suggestRow, function() toggle("suggestions") end, { cursorX = 0, onFocus = function(on) suggestRow.wash:SetShown(on) end }),
		UI.Node(window, resetButton, reset, { cursorX = 0 }),
	}
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(prompts()) end
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.keyboard then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(T.TITLE)
	quickButton = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate")
	quickButton:SetSize(QUICK_W, 22)
	UI.At(quickButton, window, RIGHT_X + RIGHT_W - QUICK_W, 27)
	quickButton:SetText(T.QUICK)
	quickButton:SetScript("OnClick", function() S.OpenQuick() end)
	UI.Text(window, "GameFontDisableSmall", UI.PORTRAIT_CLEAR, 33, T.HINT)
	UI.Inset(window, LEFT_X, RIGHT_Y, LEFT_W, RIGHT_H)
	UI.Inset(window, RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H)
	buildPreview()

	UI.SectionHeader(window, RIGHT_X + (RIGHT_W - 197) / 2, RIGHT_Y + 12, 197, T.SECTION)
	local y = RIGHT_Y + 62
	onRow = newRow(y, T.ON)
	control(onRow, UI.Checkbox(onRow, function() toggle("enabled") end))
	openRow = newRow(y + ROW_PITCH, T.OPEN)
	control(openRow, UI.Dropdown(openRow, CHOICE_W, choiceOf("open", OPEN)))
	y = y + 2 * ROW_PITCH
	layoutRow = newRow(y, T.LAYOUT)
	control(layoutRow, UI.Dropdown(layoutRow, CHOICE_W, choiceOf("layout", LAYOUT)))
	scaleRow = newRow(y + ROW_PITCH, T.SCALE)
	control(scaleRow, UI.Slider(scaleRow, SLIDER_W, SCALE_MIN, SCALE_MAX, SCALE_STEP, stepScale, function(value) set("scale", value) end))
	suggestRow = newRow(y + 2 * ROW_PITCH, T.SUGGEST)
	control(suggestRow, UI.Checkbox(suggestRow, function() toggle("suggestions") end))
	resetButton = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate")
	resetButton:SetSize(200, 22)
	UI.At(resetButton, window, RIGHT_X + (RIGHT_W - 200) / 2, RIGHT_Y + RIGHT_H - 36)
	resetButton:SetText(T.RESET)
	resetButton:SetScript("OnClick", reset)

	window.OnRefresh = refresh
	window.OnFocusChanged = function() if not UI.DialogShown() then window:SetPrompts(prompts()) end end
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		if key == "PAD3" then S.OpenQuick() return true end
		if key == "PAD4" then
			UI.OpenMore(window, { { id = "kbreset", name = T.RESET, detail = T.RESET_TEXT, run = reset } })
			return true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Quick messages, in two columns like the Rings tab. Left: every situation (Always first), with the count of the
-- player's own lines; the selected one is lit and up/down move through them. Right: its lines, the player's own first
-- (A edits, X deletes, Y moves), then the built-in ones (X hides that one), then Add a line, and Restore while any of
-- its built-in lines is hidden. Left/right switch columns; both lists scroll with the focus. Typing happens in our own
-- box over the world, with the window hidden, so the on-screen keyboard takes the pad; its Send and Close call the
-- box's own save and cancel (View.lua).

-- col: the focused column ("sits" or "lines"); line: the focused row of the right one; *Top: the first row shown.
local col, line, sitTop, lineTop, items, drawing = "sits", 1, 0, 0, {}, false

local function key() return SITS[sit] end

-- The right column's rows for the selected situation: { kind = "own" | "builtin" | "add" | "restore", index, text }.
local function lineItems()
	local id, saved = key(), settings().phrases
	local own, builtin, list = P.Own(saved, id), P.Builtin(saved, id), {}
	for i, text in ipairs(own) do list[#list + 1] = { kind = "own", index = i, text = text } end
	for _, entry in ipairs(builtin) do list[#list + 1] = { kind = "builtin", text = P.Text(entry) } end
	if #own < P.LINES_MAX then list[#list + 1] = { kind = "add", text = T.ADD } end
	local hidden = #(P.DEFAULTS[id] or {}) - #builtin
	if hidden > 0 then list[#list + 1] = { kind = "restore", text = T.RESTORE:format(hidden) } end
	return list
end

-- The first row shown, so that row i of n is among the VISIBLE ones.
local function scrolled(top, i, n) return math.max(0, math.min(n - VISIBLE, math.max(top, i - VISIBLE), i - 1)) end
local function clampTop(top, n) return math.max(0, math.min(n - VISIBLE, top)) end

local function quickPrompts()
	if moving then return { { "PAD1", T.DONE } } end
	local item, tab, back = col == "lines" and items[line], UI.TabPrompt("keyboard", -1), { "PAD2", L.BACK }
	if item and item.kind == "own" then return { { "PAD1", T.EDIT }, { "PAD3", T.DELETE }, { "PAD4", T.MOVE }, tab, back } end
	if item and item.kind == "builtin" then return { { "PAD3", T.DELETE }, tab, back } end
	return { { "PAD1", L.SELECT }, tab, back }
end

local function quickChanged()
	if quick and quick:IsShown() then quick:Refresh() end
end

local function closeEditor(text)
	if not editor:IsShown() then return end
	local id, index = editor.key, editor.index
	editor:Hide()
	local typed = text and text:match("%S")
	local ok = typed and P.Set(settings(), id, index, text)
	if typed and not ok then ns.log(T.REFUSED) end
	-- The page comes back on the line just saved (a new one is the last of the player's), else on Add a line.
	col, line = "lines", index or #P.Own(settings().phrases, id) + (ok and 0 or 1)
	if not InCombatLockdown() then S.OpenQuick(id) end
end

local function buildEditor()
	local box = CreateFrame("Frame", nil, UIParent)
	-- Near the top: the keyboard keeps clear of the whole dialog (edit's Area), so it sits below.
	box:SetSize(540, 100)
	box:SetPoint("TOP", UIParent, "TOP", 0, -48)
	box:SetFrameStrata("DIALOG")
	box:EnableMouse(true)
	local bottom = box:CreateTexture(nil, "BACKGROUND", nil, -7)
	bottom:SetAtlas("UI-DialogBox-Background-Dark")
	bottom:SetPoint("TOPLEFT", 7, -7)
	bottom:SetPoint("BOTTOMRIGHT", -7, 7)
	local top = box:CreateTexture(nil, "BACKGROUND", nil, -4)
	top:SetAtlas(GameDialogBackgroundTop or "UI-DiamondDialogBox-Border")
	top:SetAllPoints()
	box.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	box.title:SetPoint("TOP", 0, -18)
	local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
	edit:SetSize(480, 24)
	edit:SetPoint("TOP", 0, -42)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(P.LINE_MAX)
	-- Our own functions only: the keyboard's Send and Close call them (V.OWN), a hardware Enter and Escape too. The
	-- keyboard lists the fill-ins for a "quick" box and stays clear of its Area.
	edit[K.View.OWN .. "Save"] = closeEditor
	edit[K.View.OWN .. "Cancel"] = function() closeEditor() end
	edit[K.View.OWN .. "Field"], edit[K.View.OWN .. "Area"] = "quick", box
	edit:SetScript("OnEnterPressed", function(self) closeEditor(self:GetText()) end)
	edit:SetScript("OnEscapePressed", function() closeEditor() end)
	local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOP", edit, "BOTTOM", 0, -10)
	hint:SetText(T.EDIT_HINT)
	box:SetScript("OnHide", function() edit:ClearFocus() end)
	box.edit = edit
	box:Hide()
	editor = box
end

local function openEditor(index)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	if not editor then buildEditor() end
	local id = key()
	local text = index and P.Own(settings().phrases, id)[index]
	UI.CloseAll()
	editor.key, editor.index = id, index
	editor.title:SetText((index and T.EDIT_TITLE or T.NEW_TITLE):format(T.SITUATIONS[id]))
	editor:Show()
	editor.edit:SetText(text or "")
	editor.edit:SetFocus()
end

ns.On("FCT_COMBAT_START", function() if editor and editor:IsShown() then editor:Hide() end end)

local function pickSituation(index)
	if index == sit then return end
	sit, line, lineTop, moving = index, 1, 0, nil
	quickChanged()
end

-- X on a line: the player's own after a confirm; a built-in one is hidden at once (Restore brings it back).
local function deleteLine(item)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	local id = key()
	if item.kind == "builtin" then
		P.Remove(settings(), id, item.text, true)
		return quickChanged()
	end
	UI.Dialog():Open(quick, { text = T.DELETE_TEXT, sub = item.text, buttons = { T.DELETE, L.CANCEL }, back = 2, on1 = function()
		P.Remove(settings(), id, item.text)
		quickChanged()
	end })
end

local function restore()
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	P.Restore(settings(), key())
	quickChanged()
end

local function selectLine(item)
	if item.kind == "own" then return openEditor(item.index) end
	if item.kind == "add" then return openEditor() end
	if item.kind == "restore" then return restore() end
end

local function moveLine(step)
	if not P.Move(settings(), key(), moving, step) then return end
	moving = moving + step
	line = moving
	quickChanged()
end

-- A bar or the wheel scrolls a column to top. The focused column's focus moves along into view (as in the Rings icon
-- grid); in the situations that is the selected one, so the lines follow. The other column scrolls on its own.
local function scroll(column, top)
	if moving then return quickChanged() end
	if column == "lines" then
		lineTop = clampTop(top, #items)
		if col == "lines" then line = math.max(lineTop + 1, math.min(line, lineTop + VISIBLE)) end
		return quickChanged()
	end
	sitTop = clampTop(top, #SITS)
	local index = math.max(sitTop + 1, math.min(sit, sitTop + VISIBLE))
	if col == "sits" and index ~= sit then return pickSituation(index) end
	quickChanged()
end

-- A column's rows at full width, or BAR_ROOM narrower while its bar shows.
local function fit(rows, column, top, n, width)
	local room = bars[column]:Set(top, VISIBLE, n) and BAR_ROOM or 0
	for _, row in ipairs(rows) do row:SetWidth(width - 2 * MARGIN - room) end
end

local function quickRefresh()
	local s = settings()
	if not s then return end
	local saved = s.phrases
	items = lineItems()
	line = math.max(1, math.min(line, #items))
	-- The focused column keeps its focus in view; the other one stays where a bar or the wheel left it.
	sitTop = col == "sits" and scrolled(sitTop, sit, #SITS) or clampTop(sitTop, #SITS)
	lineTop = col == "lines" and scrolled(lineTop, line, #items) or clampTop(lineTop, #items)
	linesHeader.text:SetText(T.SITUATIONS[key()])
	local nodes, want = {}, nil
	for i, row in ipairs(sitRows) do
		local index = sitTop + i
		local id = SITS[index]
		row:SetShown(id ~= nil)
		if id then
			local own = #P.Own(saved, id)
			row.label:SetText(T.SITUATIONS[id])
			row.count:SetText(own > 0 and own or "")
			row.lit:SetShown(index == sit)
			row.select = function()
				col = "lines"
				if index == sit then return quickChanged() end
				pickSituation(index)
			end
			local node = UI.Node(quick, row, row.select, { cursorX = 0, onFocus = function(on)
				row.wash:SetShown(on)
				-- The mouse on a situation selects it too, as the pad does.
				if on and not drawing then
					col = "sits"
					pickSituation(index)
				end
			end })
			nodes[#nodes + 1] = node
			if col == "sits" and index == sit then want = node end
		end
	end
	for i, row in ipairs(lineRows) do
		local index = lineTop + i
		local item = items[index]
		row:SetShown(item ~= nil)
		if item then
			local kind = item.kind
			local action = kind == "add" or kind == "restore"
			row.label:SetText(item.text)
			row.label:SetFontObject(action and "GameFontNormal" or "GameFontHighlight")
			row.label:SetPoint("LEFT", kind == "add" and 34 or 10, 0)
			row.icon:SetShown(kind == "add")
			row.tag:SetText(kind == "own" and T.YOURS or "")
			row.lit:SetShown(kind == "own" and moving == item.index)
			row.select = function() selectLine(item) end
			local node = UI.Node(quick, row, row.select, { cursorX = 0, onFocus = function(on)
				row.wash:SetShown(on)
				if on and not drawing then col, line = "lines", index end
			end })
			nodes[#nodes + 1] = node
			if col == "lines" and index == line then want = node end
		end
	end
	fit(sitRows, "sits", sitTop, #SITS, Q_LEFT_W)
	fit(lineRows, "lines", lineTop, #items, Q_RIGHT_W)
	drawing = true
	quick:SetNodes(nodes)
	quick:Focus(want or nodes[1])
	drawing = false
	if not UI.DialogShown() then quick:SetPrompts(quickPrompts()) end
end

-- A list row of the quick page: one line of text on a stripe, every other row a shade lighter; lit when selected.
local function listRow(i, x, width, column)
	local row = newRow(LIST_Y + (i - 1) * LINE_PITCH, "", x, quick, LINE_H)
	row:SetWidth(width)
	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta) scroll(column, bars[column].top - delta) end)
	row.label:SetPoint("RIGHT", -60, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.label:SetFontObject("GameFontHighlight")
	local stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	stripe:SetColorTexture(1, 1, 1, i % 2 == 1 and 0.05 or 0.02)
	stripe:SetAllPoints()
	row.lit = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.lit:SetBlendMode("ADD")
	row.lit:SetAllPoints()
	row:SetScript("OnClick", function(self) if self.select then self.select() end end)
	return row
end

-- A column's scroll bar at its inset's right, as tall as its rows.
local function scrollBar(x, width, column)
	local bar = UI.ScrollBar(quick, VISIBLE * LINE_PITCH - 1, function(top) scroll(column, top) end)
	UI.At(bar, quick, x + width - BAR_X, LIST_Y)
	bars[column] = bar
end

local function buildQuick()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.keyboard then index = i end end
	quick = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	quick.tabs = UI.SideTabs(quick, UI.TABS, index)
	quick:SetTitle(T.QUICK_TITLE)
	UI.Text(quick, "GameFontDisableSmall", UI.PORTRAIT_CLEAR, 33, T.QUICK_HINT)
	UI.Inset(quick, Q_LEFT_X, RIGHT_Y, Q_LEFT_W, RIGHT_H)
	UI.Inset(quick, Q_RIGHT_X, RIGHT_Y, Q_RIGHT_W, RIGHT_H)
	UI.SectionHeader(quick, Q_LEFT_X + (Q_LEFT_W - 197) / 2, RIGHT_Y + 12, 197, T.SITUATION)
	linesHeader = UI.SectionHeader(quick, Q_RIGHT_X + (Q_RIGHT_W - 197) / 2, RIGHT_Y + 12, 197, "")
	sitRows, lineRows = {}, {}
	for i = 1, VISIBLE do
		local row = listRow(i, Q_LEFT_X + MARGIN, Q_LEFT_W - 2 * MARGIN, "sits")
		row.label:SetPoint("RIGHT", -36, 0)
		row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.count:SetPoint("RIGHT", -10, 0)
		sitRows[i] = row
		row = listRow(i, Q_RIGHT_X + MARGIN, Q_RIGHT_W - 2 * MARGIN, "lines")
		row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.tag:SetPoint("RIGHT", -10, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 10, 0)
		lineRows[i] = row
	end
	scrollBar(Q_LEFT_X, Q_LEFT_W, "sits")
	scrollBar(Q_RIGHT_X, Q_RIGHT_W, "lines")

	quick.OnRefresh = quickRefresh
	quick.OnFocusChanged = function() if not drawing and not UI.DialogShown() then quick:SetPrompts(quickPrompts()) end end
	quick.OnBack = function() S.Open() end
	-- The D-pad (a held one repeats): up/down through the focused column, scrolling it; left/right between columns.
	quick.Move = function(self, dx, dy)
		if moving then return end
		if dx > 0 and col == "sits" then
			col = "lines"
		elseif dx < 0 and col == "lines" then
			col = "sits"
		elseif dy ~= 0 and col == "sits" then
			if not SITS[sit - dy] then return end
			sit, line, lineTop = sit - dy, 1, 0
		elseif dy ~= 0 then
			if not items[line - dy] then return end
			line = line - dy
		else
			return
		end
		self:Refresh()
	end
	quick.OnKey = function(_, pad)
		-- Moving a line: D-pad up / down carries it, any other press puts it down (an L1/R1 tap must not switch tabs).
		if moving then
			quick.tap = nil
			if pad == "PADDUP" or pad == "PADDDOWN" then
				moveLine(pad == "PADDUP" and -1 or 1)
			elseif pad == "PAD1" or pad == "PAD2" or pad == "PAD4" then
				moving = nil
				quickChanged()
			end
			return true
		end
		local item = col == "lines" and items[line]
		if not item then return end
		if pad == "PAD3" and (item.kind == "own" or item.kind == "builtin") then
			deleteLine(item)
			return true
		end
		if pad == "PAD4" and item.kind == "own" then
			if #P.Own(settings().phrases, key()) > 1 then
				moving = item.index
				quickChanged()
			end
			return true
		end
	end
	quick.OnClosed = function() moving = nil end
end

-- The quick messages page, on situation id (the editor coming back), else on the last situation shown, focused.
function S.OpenQuick(id)
	if not settings() then return end
	if not id then col = "sits" end
	for i, other in ipairs(SITS) do if other == id then sit = i end end
	if not quick then buildQuick() end
	UI.Show(quick)
end

function S.Open()
	if not settings() then return end
	if not window then build() end
	UI.Show(window)
end

S.T = T

-- A side tab after Bindings and Touch (Bindings, Touch, Keyboard, Rings, of those loaded); L1/R1 step through them.
UI.AddTab({ "Interface\\Icons\\INV_Letter_15", T.TAB, function() S.Open() end, keyboard = true, order = 3, prompt = T.TAB })
