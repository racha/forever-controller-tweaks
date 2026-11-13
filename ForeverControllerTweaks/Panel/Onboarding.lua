-- Forever Controller Tweaks onboarding: Welcome -> Choose a layout -> (Set it up yourself, the Bindings window in guided
-- mode) -> Try it -> Face actions -> Done, in one 760x470 native window. It shows once per account per controller
-- family on the first login with the gamepad UI on and a pad connected; /fct setup and "Setup guide" re-run it.
local _, ns = ...
local UI = ns.UI
local L, Layout = UI.L, ns.Layout

local O = {}
UI.Onboarding = O

local AUTO_DELAY = 2
local CARD_W, CARD_H = 226, 372

local window, pages, step, active
local TITLES = { family = L.FAMILY_TITLE, welcome = L.WELCOME_TITLE, choose = L.CHOOSE_TITLE, try = L.TRY_TITLE, face = L.FACE_TITLE, done = L.DONE_TITLE }
local FAMILIES = { "playstation", "xbox", "switch", "custom" }
local FAMILY_ART = { playstation = "playstation", xbox = "xbox", switch = "switch", custom = "generic" }
local FAMILY_W, FAMILY_PITCH, FAMILY_H = 169, 181, 316
-- A family card's art: the pad cropped to the drawing's units (VB_X, VB_Y, VB_W, VB_H), stretched over its canvas, so
-- UI.DIA positions map onto it by ART_K. The face glyphs are the game's sets (Detect.STYLE_FACES: bottom, right, left,
-- top), the legend repeats them larger.
local VB_X, VB_Y, VB_W, VB_H = 28, 14, 344, 268
local ART_W, ART_TOP = FAMILY_W - 4, 44
local ART_K = ART_W / VB_W
local FAMILY_STYLE = { playstation = "Shapes", xbox = "Letters", switch = "Reverse" }
local FACE_CODES = { "FB", "FR", "FL", "FT" }
local LEGEND_Y, LEGEND_SIZE, LEGEND_GAP = 204, 28, 6

local function onboarded()
	ns.db.onboarded = ns.db.onboarded or {}
	return ns.db.onboarded
end

local function newPage()
	local page = CreateFrame("Frame", nil, window)
	page:SetAllPoints()
	page:Hide()
	return page
end

local function modCodes()
	local codes = { "L2", "L1", "R2", "R1" }
	local left, right = UI.Paddles()
	for _, list in ipairs({ left, right }) do
		for _, phys in ipairs(list) do codes[#codes + 1] = phys end
	end
	return codes
end

-- 0 An unrecognised pad: which layout is it? Four cards with the family art; PlayStation, Xbox or Switch is saved
-- through Device.SetFamily (when the build has it) and the guide goes on to the layout choice; Custom runs
-- controller setup. Bindings > More > Controller type opens the same page and returns to Bindings.
local familyFromMore

-- True: as a page's Back it has opened the next window, which must stay (Window closes all on a false Back).
local function afterFamily()
	if not familyFromMore then
		O.Show("choose")
		return true
	end
	O.Finish()
	UI.Bindings.Open()
	return true
end

local function pickFamily(id)
	if id == "custom" then
		window.handoff = true
		return UI.Detect.Open({ onDone = afterFamily })
	end
	local device = ns.Device.Current()
	if not ns.Device.SetFamily then
		ns.log(L.FAMILY_MISSING)
	elseif device then
		local _, err = ns.Device.SetFamily(device.key, id)
		if err then ns.log(err) end
	end
	afterFamily()
end

-- A mark on the card art at drawing units (x, y): a face glyph, a "?" or a trigger name (point: which side of it).
local function onArt(card, region, x, y, point) region:SetPoint(point or "CENTER", card.art, "TOPLEFT", (x - VB_X) * ART_K, -(y - VB_Y) * ART_K) end

local function familyMarks(card, id)
	local style, pos = FAMILY_STYLE[id], UI.DIA[FAMILY_ART[id]].pos
	local faces = style and UI.Detect.STYLE_FACES[style]
	local legendX = (FAMILY_W - 4 * LEGEND_SIZE - 3 * LEGEND_GAP) / 2
	for i, code in ipairs(FACE_CODES) do
		local x, y = unpack(pos[code])
		local mark = faces and card:CreateTexture(nil, "OVERLAY") or card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		local legend = faces and card:CreateTexture(nil, "OVERLAY") or CreateFrame("Frame", nil, card)
		legend:SetSize(LEGEND_SIZE, LEGEND_SIZE)
		UI.At(legend, card, legendX + (i - 1) * (LEGEND_SIZE + LEGEND_GAP), LEGEND_Y - LEGEND_SIZE / 2)
		if faces then
			mark:SetAtlas(faces[i])
			mark:SetSize(28 * ART_K, 28 * ART_K)
			legend:SetAtlas(faces[i])
		else
			mark:SetText("?")
			-- The custom card's legend: neutral slots with "?", as the learn screen starts.
			legend.border = legend:CreateTexture(nil, "ARTWORK")
			legend.border:SetAllPoints()
			legend.border:SetAtlas("gamepad-footer-slot-frameneutral")
			legend.text = legend:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			legend.text:SetPoint("CENTER")
			legend.text:SetText("?")
		end
		onArt(card, mark, x, y)
	end
	-- Names sit outside the pad beside their trigger or shoulder; the custom card marks its triggers with "?".
	local names = UI.FAMILY[id] and UI.FAMILY[id].names
	for _, code in ipairs(names and { "L2", "L1", "R2", "R1" } or { "L2", "R2" }) do
		local x, y = unpack(pos[code])
		local left = code:sub(1, 1) == "L"
		local label = card:CreateFontString(nil, "OVERLAY", names and "GameFontNormalSmall" or "GameFontNormal")
		label:SetText(names and names[code] or "?")
		if names then onArt(card, label, x + (left and -36 or 36), y, left and "RIGHT" or "LEFT") else onArt(card, label, x, y) end
	end
	local line = names and string.format(L.FAMILY_NAMES, names.L1, names.L2, names.R1, names.R2) or ""
	card.names = UI.CenterText(card, "GameFontNormal", 8, LEGEND_Y + LEGEND_SIZE / 2 + 10, FAMILY_W - 16, line)
end

local function buildFamily(page)
	UI.Text(page, "GameFontHighlight", 24, 34, L.FAMILY_HEADING)
	page.hint = UI.Text(page, "GameFontDisableSmall", 24, 52)
	page.cards = {}
	for i, id in ipairs(FAMILIES) do
		local card = CreateFrame("Button", nil, page)
		card:SetSize(FAMILY_W, FAMILY_H)
		UI.At(card, page, 24 + (i - 1) * FAMILY_PITCH, 70)
		local inset = UI.InsetFill(CreateFrame("Frame", nil, card, "InsetFrameTemplate"))
		inset:SetAllPoints()
		card.border = card:CreateTexture(nil, "OVERLAY")
		card.border:SetAtlas("gamepad-footer-slot-framefocused")
		card.border:SetPoint("TOPLEFT", -6, 6)
		card.border:SetPoint("BOTTOMRIGHT", 6, -6)
		card.title = UI.Text(card, "GameFontNormalLarge", 14, 16, L.FAMILY_CARDS[id], FAMILY_W - 28)
		card.art = card:CreateTexture(nil, "ARTWORK")
		card.art:SetTexture(UI.ART .. FAMILY_ART[id] .. "-card.tga")
		card.art:SetSize(ART_W, ART_W * VB_H / VB_W)
		card.art:SetPoint("TOP", 0, -ART_TOP)
		familyMarks(card, id)
		local textY = id == "custom" and LEGEND_Y + LEGEND_SIZE / 2 + 10 or LEGEND_Y + 56
		card.text = UI.CenterText(card, "GameFontHighlightSmall", 12, textY, FAMILY_W - 24, L.FAMILY_LINES[id])
		card.text:SetSpacing(1)
		-- What the pad itself suggests (Device.SuggestedFamily): marked, preselected, still the player's pick.
		card.suggested = UI.Text(card, "GameFontNormalSmall", 14, FAMILY_H - 24, L.SUGGESTED, FAMILY_W - 28)
		card.anchor = CreateFrame("Frame", nil, card)
		card.anchor:SetSize(1, 1)
		card.anchor:SetPoint("LEFT", card, "TOPLEFT", 0, -26)
		card.id = id
		card:SetScript("OnClick", function() pickFamily(id) end)
		page.cards[i] = card
	end
	function page:Refresh()
		local device = ns.Device.Current()
		local suggested = device and ns.Device.SuggestedFamily and ns.Device.SuggestedFamily(device.key)
		self.hint:SetText(suggested and L.FAMILY_SUGGESTED[suggested] or "")
		local nodes, preselect = {}, nil
		for i, card in ipairs(self.cards) do
			nodes[i] = UI.Node(window, card, function() pickFamily(card.id) end, { cursorRegion = card.anchor, onFocus = function(on) card.border:SetShown(on) end })
			card.border:Hide()
			card.suggested:SetShown(card.id == suggested)
			if card.id == suggested then preselect = nodes[i] end
		end
		window:SetNodes(nodes)
		if preselect then window:Focus(preselect) end
		window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD2", familyFromMore and L.BACK or L.NOT_NOW } })
	end
	function page:OnBack()
		if familyFromMore then return afterFamily() end
		O.NotNow()
	end
end

-- 1 Welcome
local function buildWelcome(page)
	page.drawing = UI.Drawing(page)
	page.heading = UI.Text(page, "GameFontNormalHuge", 370, 92)
	page.set = UI.Text(page, "GameFontDisableSmall", 370, 118)
	local one = UI.Text(page, "GameFontHighlight", 370, 150, L.WELCOME_LINE1, 350)
	local two = UI.Text(page, "GameFontHighlight", 370, 200, L.WELCOME_LINE2, 350)
	one:SetSpacing(2)
	two:SetSpacing(2)
	page.note = UI.Text(page, "GameFontDisableSmall", 370, 262, nil, 350)
	page.note:SetSpacing(1)
	function page:Refresh()
		local _, _, info = UI.Device()
		self.drawing:Place(30, 80, 0.8)
		self.drawing:Style(nil, nil, nil, false)
		-- An unknown pad (generic family, or one Device says still needs setup) gets the generic wording.
		local device = ns.Device.Current()
		local unknown = not device or device.family == "generic" or (ns.Device.NeedsSetup and ns.Device.NeedsSetup())
		self.heading:SetText(string.format(L.DETECTED, unknown and L.GENERIC_SHORT or info.short))
		self.set:SetText(unknown and "" or info.set)
		self.note:SetText(string.format(L.WELCOME_NOTE, UI.ToggleKeyText()))
		window:SetNodes({})
		window:SetPrompts({ { "PAD1", L.CONTINUE }, { "PAD2", L.NOT_NOW } })
	end
	function page:OnKey(key)
		if key == "PAD1" then O.Show("choose") return true end
		if key == "PAD2" then O.NotNow() return true end
	end
end

-- 2 Choose a layout: three cards of equal height. Each shows the shared controller drawing at card size with the
-- shoulders and triggers filled in the layout's role colours (neutral on the custom card), and a legend in Bindings'
-- modifier row style: glyph, role colour bar, role word, left side and right side in two columns. The focused card wears the
-- native gold focus frame.
local CARD_PAD, CARD_DRAW_TOP, LEGEND_PITCH, LEGEND_GAP = 16, 92, 20, 8
local NEUTRAL = { 0.45, 0.45, 0.45, 0.45 }

local function newCard(page, i, title, text, note)
	local card = CreateFrame("Button", nil, page)
	card:SetSize(CARD_W, CARD_H)
	UI.At(card, page, 24 + (i - 1) * 242, 62)
	local inset = UI.InsetFill(CreateFrame("Frame", nil, card, "InsetFrameTemplate"))
	inset:SetAllPoints()
	card.border = card:CreateTexture(nil, "OVERLAY")
	card.border:SetAtlas("gamepad-footer-slot-framefocused")
	card.border:SetPoint("TOPLEFT", -6, 6)
	card.border:SetPoint("BOTTOMRIGHT", 6, -6)
	card.border:Hide()
	card.title = UI.Text(card, "GameFontNormalLarge", CARD_PAD, 14, title, CARD_W - 2 * CARD_PAD)
	card.text = UI.Text(card, "GameFontHighlightSmall", CARD_PAD, 14, text, CARD_W - 2 * CARD_PAD)
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.text:SetSpacing(1)
	card.drawing = UI.Drawing(card, false, { "L2", "L1", "R2", "R1" })
	card.rows = {}
	card.note = UI.Text(card, "GameFontDisableSmall", nil, nil, note, CARD_W - 2 * CARD_PAD)
	card.anchor = CreateFrame("Frame", nil, card)
	card.anchor:SetSize(1, 1)
	card.anchor:SetPoint("LEFT", card, "TOPLEFT", 0, -26)
	return card
end

local function legendRow(card)
	local row = CreateFrame("Frame", nil, card)
	row:SetSize((CARD_W - 2 * CARD_PAD) / 2, LEGEND_PITCH)
	row.glyph = UI.Glyph(row, 18)
	row.glyph:SetPoint("LEFT")
	row.marker = UI.Marker(row, 10)
	row.marker:SetPoint("LEFT", row.glyph, "RIGHT", 6, 0)
	row.word = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.word:SetPoint("LEFT", row.glyph, "RIGHT", 22, 0)
	return row
end

-- roles: the layout's roles, or nil for the custom card (neutral controls, "?").
local function fillCard(card, roles)
	local scale = (CARD_W - 2 * CARD_PAD) / 400
	local drawing = card.drawing
	drawing:Place(CARD_PAD, CARD_DRAW_TOP, scale)
	drawing:Style(function(code) return UI.MOD_CODES[code] end, nil, nil, true)
	drawing:Fills(function(code)
		if not roles then return NEUTRAL end
		local role = roles[code]
		if not role then return end
		local r, g, b = UI.RoleRGB(role)
		return { r, g, b, 0.85 }
	end)

	for _, row in ipairs(card.rows) do row:Hide() end
	local leftPads, rightPads = UI.Paddles()
	local columns = { { "L2", "L1" }, { "R2", "R1" } }
	for _, phys in ipairs(leftPads) do table.insert(columns[1], phys) end
	for _, phys in ipairs(rightPads) do table.insert(columns[2], phys) end
	local top, used = CARD_DRAW_TOP + 300 * scale + LEGEND_GAP, 0
	for c, codes in ipairs(columns) do
		for i, code in ipairs(codes) do
			used = used + 1
			local row = card.rows[used] or legendRow(card)
			card.rows[used] = row
			row:ClearAllPoints()
			UI.At(row, card, CARD_PAD + (c - 1) * (CARD_W - 2 * CARD_PAD) / 2, top + (i - 1) * LEGEND_PITCH)
			row.glyph:SetCode(code)
			local role = roles and roles[code]
			row.marker:SetRole(role)
			row.word:SetText(not roles and "?" or role and UI.ROLE[role].card or "–")
			if role then row.word:SetTextColor(UI.RoleRGB(role)) else row.word:SetTextColor(0.5, 0.5, 0.5) end
			row:Show()
		end
	end
	card.note:ClearAllPoints()
	UI.At(card.note, card, CARD_PAD, top + math.max(#columns[1], #columns[2]) * LEGEND_PITCH + 4)
end

local function buildChoose(page)
	UI.Text(page, "GameFontHighlight", 24, 34, L.CHOOSE_LINE)
	page.cards = {
		newCard(page, 1, L.PRESET_NATIVE, ""),
		newCard(page, 2, L.PRESET_SPLIT, L.CARD_SPLIT_LINE),
		newCard(page, 3, L.CARD_CUSTOM, L.CARD_CUSTOM_LINE, L.CARD_CUSTOM_NOTE),
	}
	local function pick(i)
		if i == 3 then
			window.handoff = true
			return UI.Bindings.OpenGuided(function() O.Show("try") end, function() O.Show("choose") end)
		end
		local ok, err = Layout.SetPreset(i == 1 and "native" or "split")
		if not ok then ns.log(err) end
		O.Show("try")
	end
	for i, card in ipairs(page.cards) do card:SetScript("OnClick", function() pick(i) end) end

	function page:Refresh()
		local cards = self.cards
		cards[1].text:SetText(string.format(L.CARD_NATIVE_LINE, UI.Name("L2"), UI.Name("R2"), UI.Name("L1"), UI.Name("R1")))
		fillCard(cards[1], Layout.NativeRoles(ns.Device.SwapTargets()))
		fillCard(cards[2], Layout.PRESETS.split)
		fillCard(cards[3], nil)
		local nodes = {}
		for i, card in ipairs(cards) do
			nodes[i] = UI.Node(window, card, function() pick(i) end, { cursorRegion = card.anchor, onFocus = function(on) card.border:SetShown(on) end })
			card.border:Hide()
		end
		window:SetNodes(nodes)
		if not self.focused then
			self.focused = true
			window:Focus(nodes[2])
		end
		window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD2", L.BACK } })
	end
	function page:OnBack() O.Show("welcome") end
end

-- The seven key rows (Try it, Done).
local function keyRows(page, x, y)
	local rows = {}
	for i, role in ipairs(UI.KEY_ROLES) do
		local row = UI.KeyRow(page)
		UI.At(row, page, x, y + (i - 1) * 25)
		rows[role] = row
	end
	return rows
end

-- 4 Try it: hold each button, its row lights up.
local function buildTry(page)
	page.drawing = UI.Drawing(page)
	UI.Text(page, "GameFontNormalLarge", 360, 40, L.TRY_HEADING)
	page.sub = UI.Text(page, "GameFontDisableSmall", 360, 62)
	UI.Inset(page, 350, 84, 386, 196)
	page.rows = keyRows(page, 366, 96)
	page.status = UI.CenterText(page, "GameFontNormal", 350, 300, 386)
	function page:Hold(force)
		local held = UI.HeldButtons()
		local key = table.concat(held, "+")
		if key == self.heldKey and not force then return end
		self.heldKey = key

		local roles = Layout.Roles()
		local lit, text = UI.HoldResult(held, roles)
		for role, row in pairs(self.rows) do row:Set(role, roles, role == lit) end
		local names = {}
		for _, phys in ipairs(held) do names[#names + 1] = UI.Name(phys) end
		self.sub:SetText(#held > 0 and string.format(L.TRY_HOLDING, table.concat(names, " + ")) or L.TRY_IDLE)
		self.status:SetFontObject(text and "GameFontNormal" or "GameFontDisableSmall")
		self.status:SetText(text or L.HOLD_IDLE)
		-- The rows and the status line answer the hold; the drawing stays still.
		self.drawing:Style(function(code) return UI.MOD_CODES[code] end, nil, nil, true)
	end
	function page:Refresh()
		self.drawing:Place(20, 90, 0.8)
		self:Hold(true)
		window:SetNodes({})
		window:SetPrompts({ { "PAD1", L.CONTINUE }, { "PAD2", L.BACK } })
	end
	function page:OnKey(key)
		if key == "PAD1" then O.Show("face") return true end
	end
	function page:OnBack() O.Show("choose") end
end

-- 5 Face actions: the four first-page face slots as they are now.
local function buildFace(page)
	UI.Text(page, "GameFontNormalLarge", 24, 40, L.FACE_HEADING)
	local text = UI.Text(page, "GameFontHighlight", 24, 66, L.FACE_LINE, 700)
	text:SetSpacing(2)
	UI.Inset(page, 24, 110, 712, 200)
	page.items = {}
	for i, spec in ipairs({ { "FT", 0, 0 }, { "FL", 0, 1 }, { "FR", 1, 0 }, { "FB", 1, 1 } }) do
		local x, y = 60 + spec[2] * 340, 140 + spec[3] * 80
		local item = { code = spec[1] }
		item.glyph = UI.Glyph(page, 24, spec[1])
		item.glyph:SetPoint("CENTER", page, "TOPLEFT", x + 12, -(y + 15))
		local slot = CreateFrame("Button", nil, page)
		slot:SetSize(30, 30)
		UI.At(slot, page, x + 34, y)
		local bg = slot:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetAtlas("gamepad-actionbar-slot-bg-empty")
		item.icon = slot:CreateTexture(nil, "ARTWORK")
		UI.SlotMask(slot, item.icon, true, 2)
		local border = slot:CreateTexture(nil, "OVERLAY")
		border:SetAllPoints()
		border:SetAtlas("gamepad-actionbar-circleslot-border-normal")
		item.slot = slot
		slot:SetScript("OnClick", function() O.PickFace(item) end)
		slot:SetScript("OnLeave", function() UI.HideTooltip(slot) end)
		item.name = UI.Text(page, "GameFontNormal", x + 72, y + 2)
		item.sub = UI.Text(page, "GameFontDisableSmall", x + 72, y + 18)
		page.items[i] = item
	end
	function page:Refresh()
		local face = Layout.Face()
		local nodes = {}
		for _, item in ipairs(self.items) do
			local pos = UI.CODE_POS[item.code]
			local action, entry = face[pos], UI.ActionPicker.CellEntry({ code = item.code, layer = "T", pos = pos })
			local inset = entry and 3 or UI.Bindings.SPECIAL_INSET[action] or 0
			item.glyph:SetCode(item.code)
			item.icon:ClearAllPoints()
			item.icon:SetPoint("TOPLEFT", item.slot, "TOPLEFT", inset, -inset)
			item.icon:SetPoint("BOTTOMRIGHT", item.slot, "BOTTOMRIGHT", -inset, inset)
			item.icon:SetTexCoord(0, 1, 0, 1)
			if entry then item.icon:SetTexture(entry.icon) else UI.Bindings.SpecialIcon(item.icon, action) end
			item.name:SetText(entry and entry.name or UI.Bindings.ACTION_NAME[action])
			local where = entry and L.SET_BY_ADDON or Layout.NATIVE_FACE[pos] == action and L.GAME_DEFAULT_SUFFIX or L.MOVED_BY_ADDON
			item.sub:SetText(UI.Name(item.code) .. where)
			local tip = { title = item.name:GetText(), lines = { string.format(L.FACE_ITEM_TIP, UI.Name(item.code)) }, actions = { { "PAD1", L.CHOOSE_ACTION } }, side = "right" }
			nodes[#nodes + 1] = UI.Node(window, item.slot, function() O.PickFace(item) end, { tip = tip })
		end
		window:SetNodes(nodes)
		window:SetPrompts({ { "PAD1", L.SELECT }, { "PAD3", L.SKIP }, { "PAD2", L.BACK } })
	end
	function page:OnKey(key)
		if key == "PAD3" then O.Show("done") return true end
	end
	function page:OnBack() O.Show("try") end
end

-- 6 Done: the layout key and where to change it later.
local function buildDone(page)
	page.title = UI.Text(page, "GameFontNormalLarge", 24, 40)
	UI.Inset(page, 24, 70, 356, 200)
	page.rows = keyRows(page, 40, 82)
	UI.Text(page, "GameFontNormal", 404, 76, L.DONE_CHANGE)
	local lines = L.DONE_LINES
	for i, line in ipairs(lines) do UI.Text(page, "GameFontHighlight", 404, 100 + (i - 1) * 40, line, 330):SetSpacing(2) end
	page.open = UI.Text(page, "GameFontHighlight", 404, 180, nil, 330)
	page.open:SetSpacing(2)
	function page:Refresh()
		local device = ns.Device.Current()
		local entry = device and ns.db.devices[device.key]
		self.title:SetText(string.format(L.DONE_HEADING, UI.PresetLabel(Layout.PresetName(entry and entry.roles))))
		local roles = Layout.Roles()
		for role, row in pairs(self.rows) do row:Set(role, roles, false) end
		self.open:SetText(UI.OpenWays())
		window:SetNodes({})
		window:SetPrompts({ { "PAD4", L.OPEN_BINDINGS }, { "PAD1", L.CLOSE } })
	end
	function page:OnKey(key)
		if key == "PAD1" then
			O.Finish()
			UI.CloseAll()
			return true
		end
		if key == "PAD4" then
			O.Finish()
			UI.Bindings.Open()
			return true
		end
	end
	function page:OnBack() O.Show("face") end
end

local function build()
	window = UI.NewWindow(760, 470)
	pages = {}
	local builders = { family = buildFamily, welcome = buildWelcome, choose = buildChoose, try = buildTry, face = buildFace, done = buildDone }
	for name, builder in pairs(builders) do
		pages[name] = newPage()
		builder(pages[name])
	end
	window.OnRefresh = function()
		for name, page in pairs(pages) do page:SetShown(name == step) end
		window:SetTitle(TITLES[step])
		pages[step]:Refresh()
	end
	window.OnKey = function(_, key)
		local page = pages[step]
		return page.OnKey and page:OnKey(key)
	end
	window.OnBack = function()
		local page = pages[step]
		if page.OnBack then return page:OnBack() end
		O.NotNow()
	end
	window.OnHoldTick = function()
		if step == "try" then pages.try:Hold() end
	end
	-- Combat closes every window; the guide comes back at the same step when combat ends.
	window.OnClosed = function()
		if active and not window.handoff and UI.combatClosing then
			local name = step
			UI.resume = { text = L.RESUME_GUIDE, fn = function() O.Show(name) end }
		elseif not window.handoff then
			active = false
		end
		window.handoff = nil
	end
end

function O.PickFace(item)
	UI.ActionPicker.Open({ window = window, cell = item.slot, pos = UI.CODE_POS[item.code] })
end

function O.Show(name)
	if not window then build() end
	step, active = name, true
	if name == "choose" then pages.choose.focused = nil end
	UI.Show(window)
end

-- From the first login trigger, "Setup guide" or /fct setup. The family is marked at once, so the guide never
-- auto-shows twice whatever way it ends.
-- A pad needs controller setup when Device says so, or when its vendor is outside the known families and it has
-- not been detected yet.
local function unknown(device)
	if ns.Device.NeedsSetup then return ns.Device.NeedsSetup() end
	local vendor = device.key and device.key:sub(1, 4)
	return not (vendor and ns.Layout.FAMILIES[vendor]) and not device.detect
end

-- Onboarded once per account per family; an unknown pad counts per device.
local function onboardKey(device) return unknown(device) and device.key or device.family end

function O.Start()
	if not ns.Active() then return UI.ShowNotice() end
	local device = ns.Device.Current()
	if not device then return UI.ShowMessage(L.NO_PAD_NOTICE, { { L.CLOSE } }) end
	if InCombatLockdown() then
		UI.resume = { text = L.RESUME_GUIDE, fn = O.Start }
		return ns.log(L.COMBAT)
	end

	onboarded()[onboardKey(device)] = true
	familyFromMore = false
	O.Show(unknown(device) and "family" or "welcome")
end

-- Bindings > More > Controller type: the family cards, back to Bindings after.
function O.ShowFamily()
	familyFromMore = true
	O.Show("family")
end

-- Not now: keep the game's layout as it is and don't ask again for this controller (the welcome note's promise);
-- Setup guide, /fct setup and Bindings > More > Controller type still open it.
function O.NotNow()
	local device = ns.Device.Current()
	if device then
		ns.db.declined = ns.db.declined or {}
		ns.db.declined[device.key] = true
	end
	O.Finish()
	UI.CloseAll()
end

function O.Finish()
	active = false
	if window then window.handoff = true end
end

-- First start: on the first login with the Gamepad UI on, or when it is turned on later in the session.
local function autoStart()
	C_Timer.After(AUTO_DELAY, function()
		local device = ns.Device.Current()
		if not device then return end
		-- A pad that still needs setup is asked every time (its family cards first); a known one once.
		local seen = onboarded()[onboardKey(device)] and not unknown(device)
		local declined = ns.db.declined and ns.db.declined[device.key]
		if not ns.Active() or seen or declined or UI.Current() or InCombatLockdown() then return end
		O.Start()
	end)
end

local checked
ns.On("PLAYER_ENTERING_WORLD", function()
	if checked then return end
	checked = true
	autoStart()
end)

ns.On("FCT_ACTIVE_CHANGED", function(active)
	if active and checked then autoStart() end
end)

-- A pad connected or switched to later in the session gets its first-time guide too.
for _, event in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_ACTIVE_CHANGED" }) do
	ns.On(event, function()
		if checked then autoStart() end
	end)
end
