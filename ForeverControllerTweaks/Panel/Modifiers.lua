-- Forever Controller Tweaks "Modifiers & targeting" window, in Bindings' design: the same window size, header, drawing and
-- row look, and each row sits where that control's row sits in Bindings, so an L1/R1 tab switch moves nothing.
-- One row per shoulder, trigger and paddle shows its role; only the focused row draws its gold line into the
-- control. A opens the role picker (the action picker's list mode); Y opens More (controller setup, guide, Learn,
-- resets). Presets are a segmented control in the header.
-- Onboarding step 3 runs the same window in guided mode: one role at a time, chosen by pressing the button.
local _, ns = ...
local UI = ns.UI
local L, Layout = UI.L, ns.Layout

local M = {}
UI.Modifiers = M

local GUIDE_ROLES = { "leftmod", "rightmod", "friendly", "hostile" }
local GUIDE_TARGET = L.GUIDE_TARGET
local GUIDE_WILL = L.GUIDE_WILL
local LEARN_TIMEOUT = 10.5
local BUTTON_TIPS = L.BUTTON_TIPS
local PRESETS = { { "native", L.PRESET_NATIVE }, { "split", L.PRESET_SPLIT_SHORT }, { "custom", L.PRESET_CUSTOM } }
local SEGMENT_W = 112

local window, drawing, curve, guided, learn
local rows = {}

local function isPaddle(phys) return phys:sub(1, 1) == "P" end

local function holderOf(roles, role)
	for _, phys in ipairs(Layout.PHYSICAL) do
		if roles[phys] == role then return phys end
	end
end

local function storedRoles()
	local device = ns.Device.Current()
	local entry = device and ns.db.devices[device.key]
	return entry and entry.roles or {}
end

local function report(ok, err)
	if not ok and err then ns.log(err) end
end

local function freePaddle(roles)
	local device = ns.Device.Current()
	for _, paddle in ipairs({ "P1", "P2", "P3", "P4" }) do
		if device and device.raw[paddle] and not roles[paddle] then return paddle end
	end
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
		if role ~= mine and role == "none" and not isPaddle(phys) then
			local paddle = freePaddle(roles)
			entry.note, entry.disabled = paddle and L.ROLE_TO_PADDLE or L.ROLE_NEEDS_BUTTON, not paddle
		elseif role ~= mine and holder then
			entry.note = string.format(mine == "none" and L.ROLE_TAKES or L.ROLE_SWAPS, UI.Name(holder))
		end
		entries[#entries + 1] = entry
	end
	return entries, mine
end

-- Picking a role another button holds swaps the two; the note under the drawing says so in one line.
local function pickRole(phys, role)
	local before = Layout.Roles()
	assign(phys, role)
	local after = Layout.Roles()
	window.note:SetText("")
	for _, other in ipairs(Layout.PHYSICAL) do
		if other ~= phys and before[other] ~= after[other] then
			window.note:SetText(string.format(L.ROLE_SWAPPED, UI.Name(phys), UI.ROLE[after[phys] or "none"].name, UI.Name(other), UI.ROLE[after[other] or "none"].name))
		end
	end
end

local function openRoles(row)
	if guided or InCombatLockdown() then return end
	local entries, mine = roleEntries(row.code)
	UI.ActionPicker.Open({ window = window, cell = row.plate, list = { title = string.format(L.ROLES_TITLE, UI.Name(row.code)), entries = entries, current = mine, onPick = function(entry) pickRole(row.code, entry.id) end } })
end

-- More: the window's less frequent actions, in the picker's look, from Y (no row of red buttons).
local function openMore()
	if guided or InCombatLockdown() then return end
	local entries = {
		{ id = "detect", name = L.DETECT_BUTTON_LABEL, detail = L.DETECT_BUTTON_TIP, run = function() UI.Detect.Open() end },
		{ id = "guide", name = L.SETUP_GUIDE, detail = BUTTON_TIPS[1], run = function() UI.Onboarding.Start() end },
		{ id = "learn", name = L.LEARN, detail = BUTTON_TIPS[2], run = function() M.Learn() end },
		{ id = "detectreset", name = L.DETECT_RESET, detail = L.DETECT_RESET_TEXT, run = function() UI.Detect.Reset(window) end },
		{ id = "reset", name = L.RESET, detail = BUTTON_TIPS[3], run = function() M.Reset() end },
		{ id = "family", name = L.CONTROLLER_TYPE, detail = L.CONTROLLER_TYPE_TIP, run = function() UI.Onboarding.ShowFamily() end },
		{ id = "minimap", name = ns.db.options.minimapIcon == false and L.MINIMAP_SHOW or L.MINIMAP_HIDE, detail = L.MINIMAP_TIP, run = function() UI.ToggleMinimapButton() end },
	}
	local focus = window.focus and window.focus.region or window
	UI.ActionPicker.Open({ window = window, cell = focus, point = { "BOTTOM", window, "BOTTOM", 0, 24 }, list = { title = L.MORE, entries = entries, onPick = function(entry) entry.run() end } })
end

-- A row from Bindings' parts, with a plate over glyph and names that takes the focus and the click.
local function newRow(phys)
	local row = UI.Bindings.NewRow(window, phys)
	UI.Bindings.AddPlate(row, function() openRoles(row) end)
	return row
end

local function sideKeys()
	local leftPads, rightPads = UI.Paddles()
	local left, right = { "L2", "L1" }, { "R2", "R1" }
	for _, phys in ipairs(leftPads) do left[#left + 1] = phys end
	for _, phys in ipairs(rightPads) do right[#right + 1] = phys end
	return left, right
end

-- The row's two lines: the role (or, in guided mode, where the button stands) and what it does.
local function fillRow(row)
	local phys, roles = row.code, Layout.Roles()
	local role, name, sub, grey = roles[phys] or "none", nil, nil, false
	if guided then
		local stepRole = GUIDE_ROLES[guided.step]
		if guided.detected == phys then
			role, sub = stepRole, L.GUIDE_CONFIRM
		elseif not guided.confirmed[phys] then
			role, name, sub, grey = nil, L.GUIDE_NOT_SET, L.GUIDE_WAITING, true
		end
	end
	local info = role and UI.ROLE[role]
	row.name:SetText(name or info.name)
	row.name:SetFontObject(grey and "GameFontDisable" or "GameFontNormal")
	row.sub:SetText(sub or info.hint)
	row.marker:SetRole(role)
	row:SetAlpha(grey and 0.45 or 1)
end

-- The drawing: modifier buttons at full strength, held ones and the focused one lit; the focused row (in guided
-- mode the detected button's) draws its gold line.
local function refreshHold()
	local held = guided and {} or UI.HeldButtons()
	local lit = {}
	for _, phys in ipairs(held) do lit[phys] = true end
	local focusRow = guided and rows[guided.detected] or not guided and window.focus and window.focus.region and window.focus.region.row
	if focusRow then lit[focusRow.code] = true end
	drawing:Style(function(code) return UI.MOD_CODES[code] end, lit, nil, true)
	UI.Bindings.FocusLine(curve, drawing, rows, focusRow and focusRow:IsShown() and focusRow or nil)
	window.heldKey = table.concat(held, "+")
end

local function header()
	local device = ns.Device.Current()
	window.device:SetText(device and device.name or "")
	local on = ns.Remap.State() ~= "off"
	window.sub:SetText(device and (device.key .. " · " .. (on and L.LAYOUT_ON or L.LAYOUT_NATIVE)) or L.NO_PAD)
end

local function fillPresets() window.segments:Select(Layout.PresetName(storedRoles())) end

local function refresh()
	header()
	drawing:Place(unpack(UI.Bindings.GEO.DRAWING_PLACE))
	for _, row in pairs(rows) do row:Hide() end

	local nodes = {}
	local left, right = sideKeys()
	for _, list in ipairs({ left, right }) do
		for _, phys in ipairs(list) do
			local isLeft, top = UI.Bindings.RowSpot(phys)
			if top then
				local row = rows[phys] or newRow(phys)
				rows[phys] = row
				UI.Bindings.PlaceRow(row, isLeft, top)
				local plate = row.plate
				plate:EnableMouse(not guided)
				fillRow(row)
				nodes[#nodes + 1] = UI.Node(window, plate, function() openRoles(row) end, {
					phys = phys, onFocus = function(on) plate.wash:SetShown(on) end,
					tip = function()
						local held = Layout.Roles()[phys] or "none"
						return { title = UI.Name(phys) .. " · " .. UI.ROLE[held].name, lines = { UI.ROLE[held].hint, L.ROLE_TIP }, actions = { { "PAD1", L.CHANGE_ROLE }, { "PAD4", L.MORE } }, side = isLeft and "left" or "right" }
					end,
				})
			end
		end
	end

	for _, segment in ipairs(window.segments) do segment:SetShown(not guided) end
	window.tabs:SetShown(not guided)
	window.tabsLocked = not not guided
	window.title:SetShown(guided ~= nil)
	window.hint:SetShown(guided ~= nil)
	window.note:SetShown(not guided)
	if guided then
		local stepRole = GUIDE_ROLES[guided.step]
		window:SetTitle(L.CUSTOM_TITLE)
		window.title:SetText(string.format(L.GUIDE_HEADING, guided.step, GUIDE_TARGET[stepRole]))
		window.hint:SetText(L.GUIDE_HINT)
		window:SetPrompts({ { "PAD3", L.SKIP }, { "PAD2", L.BACK } })
		window:SetNodes({})
		window.cursor:Hide()
	else
		window:SetTitle(L.MODIFIERS_TITLE)
		fillPresets()
		for _, segment in ipairs(window.segments) do
			local custom = segment.preset == "custom"
			nodes[#nodes + 1] = UI.Node(window, segment, segment.click, { cursorX = 0, tip = custom and { title = segment.text, lines = { L.PRESETS_NOTE }, side = "below" } or { title = segment.text, lines = { L.PRESET_TIP }, actions = { { "PAD1", L.USE_LAYOUT } }, side = "below" } })
		end
		local prompts = { { "PAD1", L.SELECT }, { "PAD4", L.MORE }, { "PADLSHOULDER", L.BINDINGS }, { "PAD2", L.CLOSE } }
		if UI.TouchTab then table.insert(prompts, 4, { "PADRSHOULDER", L.TOUCH }) end
		if not UI.DialogShown() then window:SetPrompts(prompts) end
		window:SetNodes(nodes)
	end
	refreshHold()
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

function M.Learn()
	local device = ns.Device.Current()
	if not device then return ns.log(L.NO_PAD) end

	local steps = { "L1", "R1", "L2", "R2" }
	local leftPads, rightPads = UI.Paddles()
	for _, list in ipairs({ rightPads, leftPads }) do
		for _, phys in ipairs(list) do steps[#steps + 1] = phys end
	end
	learn = { steps = steps, index = 1 }
	learnStep()
end

function M.Reset()
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
		M.EndGuided()
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
		M.EndGuided()
		if done then done() end
		return true
	end
	refresh()
	return true
end

local function build()
	local geo = UI.Bindings.GEO
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, 2)
	window.device = UI.Text(window, "GameFontHighlight", 24, 30)
	window.sub = UI.Text(window, "GameFontDisableSmall", 24, 47)
	drawing = UI.Drawing(window, false, UI.Bindings.DRAWN)
	curve = UI.Connector(window, drawing)
	-- Guided mode's step line, over the drawing; normal mode's one-line swap note under it.
	local mid = (geo.WIDTH - 480) / 2
	window.title = UI.CenterText(window, "GameFontNormalLarge", mid, 74, 480)
	window.hint = UI.CenterText(window, "GameFontDisableSmall", mid, 98, 480)
	window.note = UI.CenterText(window, "GameFontHighlightSmall", mid, 560, 480)

	-- Presets: a segmented control where Bindings has its page selector; Custom only shows that roles are your own.
	window.segments = UI.Segments(window, PRESETS, geo.WIDTH - 16 - #PRESETS * SEGMENT_W, 25, SEGMENT_W, function(id)
		if id ~= "custom" then report(Layout.SetPreset(id)) end
	end)
	for _, segment in ipairs(window.segments) do segment.preset = segment.id end

	window.OnRefresh = refresh
	window.OnKey = function(_, key)
		if guided then return guidedKey(key) end
		if key == "PAD4" then
			openMore()
			return true
		end
	end
	window.OnBack = function()
		if guided then return guidedKey("PAD2") end
		UI.CloseAll()
	end
	window.OnFocusChanged = function() refreshHold() end
	window.OnHoldTick = function()
		if learn then learnTick() end
		if guided then return end
		local held = table.concat(UI.HeldButtons(), "+")
		if held ~= window.heldKey then refreshHold() end
	end
	window.OnClosed = function()
		window.note:SetText("")
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
		if guided then M.EndGuided() end
	end
end

-- phys: focus that button's row (Bindings' modifier rows).
function M.Open(phys)
	if not window then build() end
	UI.Show(window)
	if not phys or UI.Current() ~= window then return end

	for _, node in ipairs(window.nodes or {}) do if node.phys == phys then return window:Focus(node) end end
end

-- Onboarding step 3. onDone runs after the fourth role, onBack on Back.
function M.OpenGuided(onDone, onBack)
	if not window then build() end
	guided = { step = 1, confirmed = {}, onDone = onDone, onBack = onBack }
	UI.Show(window)
end

function M.EndGuided()
	guided = nil
	if window and window:IsShown() then refresh() end
end
