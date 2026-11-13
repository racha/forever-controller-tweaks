-- Forever Controller Tweaks on-screen keyboard (design/keyboard.md): a dark disc with eight 4-key
-- clusters, a command hub, the word / phrase tab and a leader line to the focused EditBox. It types into that box with
-- the box's own methods only, and finds it by polling GetCurrentKeyBoardFocus() in our own OnUpdate (no hooks).
-- Input: the frame has EnableGamePadButton / EnableGamePadStick and SetPropagateKeyboardInput(false) set once at
-- creation, out of combat (they are restricted in combat), so showing and hiding it never changes input settings:
-- a shown keyboard takes the pad, a hidden one takes nothing and the sticks move the character again.
local addonName, ns = ...
local UI, K = ns.UI, ns.Keyboard
local L = UI.L

local V = {}
K.View = V

local T = {
	SHIFT = "Shift", SYMBOLS = "Symbols", CHOOSE = "Choose", INSERT = "Insert", CORRECTION = "Correction",
	SECURE = "This command needs Enter on a real keyboard.", SLASH = "Slash commands need a real keyboard.", DENIED = "Typing here needs a real keyboard: the game blocks addons from this box.", SPACE = "Space", SEND = "Send", ERASE = "Erase", CLOSE = "Close", CURSOR = "Cursor",
	-- The tab's heading and its line when there are no rows, by the kind of list Suggest returned.
	HEAD = { phrases = "Quick phrases · %s", words = "Words", items = "Items", names = "Names", searches = "Recent searches", none = "" },
	EMPTY = { phrases = "", words = "Type a word to see suggestions", items = "No matching item", names = "No matching name", searches = "No recent searches", none = "" },
}
K.T = T

local ART = UI.ART
local BW, BH, CX, CY, DISC_R = K.BLOCK_W, K.BLOCK_H, K.DISC_X, K.DISC_Y, K.DISC_R
local RING_R, KEY, KEY_D, KEY_F, KEY_FD, HUB_KEY, HUB_D, HUB_R, PAD = 132, 32, 22, 36, 24.4, 26, 18.2, 78, 12
-- [top, right, bottom, left] offsets; FT FR FB FL.
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local FACE_OF = { FT = 1, FR = 2, FB = 3, FL = 4 }
local TAB_L, TAB_W, TAB_H, FIELD_L = CX + DISC_R - 58, BW - (CX + DISC_R - 58), 240, 68
local FLASH, REPEAT_DELAY, REPEAT_EVERY, STATUS_TIME, SEARCH_BUDGET, BLOCK_WINDOW = 0.30, 0.40, 0.05, 3, 2, 1
local ROWS = 6
local GOLD, WHITE, GREY = { 1, 210 / 255, 0 }, { 1, 1, 1 }, { 0.5, 0.5, 0.5 }
local LEAD_COLOR = { 201 / 255, 164 / 255, 100 / 255, 0.75 }

local frame, observer, input, leader, footer
local box, boxRect, chatRect, settings
local charset, set, keyFocus, armed, shiftHeld, symbolsHeld = "lower", nil, nil, true, false, false
-- suggestions: the rows from Keyboard/Suggest.lua; head: the kind of list they are ({ kind, place });
-- context: the Keyboard/Context.lua snapshot they were ranked in.
local WORDS = { kind = "words" }
local suggestions, head, context, rowFocus, correction, searchJob, searchKey, searchRev = {}, WORDS, nil, nil, nil, nil, nil, nil
local refreshSuggestions
-- typedAt: when the keyboard last changed the box's text or pressed its Enter; told: boxes whose refusal was said.
local typedAt, told = 0, setmetatable({}, { __mode = "k" })
local repeatAction, repeatAt, statusUntil, statusText, lastInput, cachedText = nil, 0, 0, T.SECURE, nil, nil
local mirror, mode = false, "right"

local function db()
	if not ns.db then return end
	ns.db.keyboard = K.Settings(ns.db.keyboard)
	return ns.db.keyboard
end

local function sound(id) if id then PlaySound(id) end end

-- The box's own script, run synchronously (ExecuteFrameScript where the client has it).
local function run(edit, script)
	if ExecuteFrameScript then return ExecuteFrameScript(edit, script) end
	local handler = edit:GetScript(script)
	if handler then handler(edit) end
end

local function at(region, parent, x, y, point) region:SetPoint(point or "CENTER", parent, "TOPLEFT", x, -y) end

-- The disc's centre in block units: the tab sits right of it, or left when mirrored.
local function discX() return mirror and BW - CX or CX end

---------------------------------------------------------------------------------------------------------------------
-- Frames

local function keyTexture(parent, layer, state, j)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(ART .. "kb-key-" .. state .. "-" .. j .. ".tga")
	return tex
end

-- One key: its face (idle / focus / pick art, by direction j), the flash, a label and a raid-marker icon.
local function newKey(parent, j)
	local key = CreateFrame("Frame", nil, parent)
	key.j = j
	key.face = keyTexture(key, "ARTWORK", "idle", j)
	key.face:SetPoint("CENTER")
	key.flash = keyTexture(key, "OVERLAY", "pick", j)
	key.flash:SetPoint("CENTER")
	key.flash:SetAlpha(0)
	key.label = key:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	key.label:SetPoint("CENTER", 0, 1)
	key.icon = key:CreateTexture(nil, "OVERLAY", nil, 2)
	key.icon:SetPoint("CENTER")
	key.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	return key
end

-- state: idle (32), focus (36), pick (36); the art is the key plus 12 units of glow room a side.
local function styleKey(key, state, size)
	key:SetSize(size, size)
	local art = (size == KEY_F and KEY_F or KEY) + 2 * PAD
	local scale = size / (art - 2 * PAD)
	key.face:SetTexture(ART .. "kb-key-" .. state .. "-" .. key.j .. ".tga")
	key.face:SetSize(art * scale, art * scale)
	key.flash:SetSize(art * scale, art * scale)
end

local function setMarker(icon, n, size)
	local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
	icon:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
	icon:SetSize(size, size)
end

local function newText(parent, font, x, y, point)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	if x then at(fs, parent, x, y, point or "TOPLEFT") end
	return fs
end

local function buildTab()
	local tab = CreateFrame("Frame", nil, frame)
	tab:SetSize(TAB_W, TAB_H)
	tab:SetFrameLevel(frame:GetFrameLevel())
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetTexture(ART .. "kb-tab.tga")
	tab.bg:SetAllPoints()
	local inner = CreateFrame("Frame", nil, tab)
	tab.inner = inner
	inner.field = inner:CreateTexture(nil, "ARTWORK")
	inner.field:SetTexture(ART .. "kb-field.tga")
	inner.field:SetTexCoord(5 / 288, 283 / 288, 4 / 36, 32 / 36)
	inner.field:SetHeight(28)
	inner.field:SetPoint("TOPLEFT", 0, -2)
	inner.field:SetPoint("TOPRIGHT", 0, -2)
	inner.text = newText(inner, "ChatFontNormal", 10, 9)
	inner.ghost = inner:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	inner.ghost:SetPoint("LEFT", inner.text, "RIGHT", 0, 0)
	inner.ghost:SetAlpha(0.45)
	inner.caret = inner:CreateTexture(nil, "OVERLAY")
	inner.caret:SetColorTexture(1, 1, 1, 1)
	inner.caret:SetSize(1, 14)
	inner.caret:SetPoint("LEFT", inner.ghost, "RIGHT", 1, 0)
	inner.head = newText(inner, "GameFontNormal", 2, 40)
	inner.empty = newText(inner, "GameFontDisableSmall", 2, 60)
	inner.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, inner)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 2, -(58 + (i - 1) * 20))
		row:SetPoint("TOPRIGHT", -2, -(58 + (i - 1) * 20))
		row.hl = row:CreateTexture(nil, "BACKGROUND")
		row.hl:SetAtlas("options_list_active")
		row.hl:SetPoint("TOPLEFT", -6, 0)
		row.hl:SetPoint("BOTTOMRIGHT", 6, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
		row.text:SetPoint("TOPLEFT", 0, -2)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.tag:SetPoint("TOPRIGHT", 0, -5)
		row.text:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
		inner.rows[i] = row
	end
	inner.hints = {}
	local x = 0
	for i, part in ipairs({ "prev", "next", T.CHOOSE, "insert", T.INSERT }) do
		if K.BUTTONS[part] then
			local glyph = UI.Glyph(inner, 6)
			glyph:SetPoint("BOTTOMLEFT", x + 5, 5)
			glyph.action = part
			inner.hints[i] = glyph
			x = x + 18
		else
			local fs = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("BOTTOMLEFT", x + 2, 2)
			fs:SetText(part)
			inner.hints[i] = fs
			x = x + 2 + fs:GetStringWidth() + 8
		end
	end
	return tab
end

local function buildFooter()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetHeight(44)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAtlas("gamepad-footer-slot-bg")
	f.bg:SetAllPoints()
	f.edge = f:CreateTexture(nil, "BORDER")
	f.edge:SetAtlas("gamepad-footer-slot-frameneutral")
	f.edge:SetAllPoints()
	f.items = {}
	f:Hide()
	return f
end

local function build()
	frame = CreateFrame("Frame", "ForeverControllerTweaksKeyboard", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetSize(BW, BH)
	frame:Hide()
	frame:EnableGamePadButton(true)
	if frame.EnableGamePadStick then frame:EnableGamePadStick(true) end
	frame:SetPropagateKeyboardInput(false)

	frame.tab = buildTab()
	frame.disc = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	frame.disc:SetAtlas("gamepad-targetingradial-radial-circle")
	frame.disc:SetSize(2 * DISC_R, 2 * DISC_R)
	frame.disc:SetAlpha(0.62)
	frame.glow = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	frame.glow:SetTexture(ART .. "kb-glow.tga")
	frame.glow:SetSize(2 * DISC_R - 12, 2 * DISC_R - 12)
	frame.rim = frame:CreateTexture(nil, "BORDER")
	frame.rim:SetTexture(ART .. "kb-rim.tga")
	frame.rim:SetSize(2 * DISC_R + 8, 2 * DISC_R + 8)
	frame.hub = frame:CreateTexture(nil, "BORDER", nil, 1)
	frame.hub:SetTexture(ART .. "kb-hub.tga")
	frame.hub:SetSize(2 * HUB_R + 4, 2 * HUB_R + 4)

	frame.sets = {}
	for i = 1, 8 do
		local cluster = CreateFrame("Frame", nil, frame)
		cluster:SetSize(1, 1)
		cluster.keys = {}
		for j = 1, 4 do cluster.keys[j] = newKey(cluster, j) end
		cluster.range = cluster:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		cluster.range:SetPoint("CENTER")
		frame.sets[i] = cluster
	end
	frame.hubKeys = {}
	local icons = { "common-icon-redx", "common-icon-checkmark", false, "gamepad-actionbar-edit-icon-clear" }
	for j = 1, 4 do
		local key = newKey(frame, j)
		styleKey(key, "idle", HUB_KEY)
		if icons[j] then
			key.icon:SetAtlas(icons[j])
			key.icon:SetSize(12, 12)
		else
			-- Space: our own underscore bar, 12 x 4, open at the top.
			key.icon:Hide()
			for _, part in ipairs({ { 1.5, 4, "BOTTOMLEFT" }, { 1.5, 4, "BOTTOMRIGHT" }, { 12, 1.5, "BOTTOM" } }) do
				local bar = key:CreateTexture(nil, "OVERLAY")
				bar:SetColorTexture(1, 1, 1, 1)
				bar:SetSize(part[1], part[2])
				bar:SetPoint(part[3], key, "CENTER", part[3] == "BOTTOMLEFT" and -6 or part[3] == "BOTTOMRIGHT" and 6 or 0, -3)
			end
		end
		frame.hubKeys[j] = key
	end

	frame.mods = {}
	for _, spec in ipairs({ { "shift", T.SHIFT }, { "symbols", T.SYMBOLS } }) do
		local mod = CreateFrame("Frame", nil, frame)
		mod:SetSize(1, 22)
		mod.glyph = UI.Glyph(mod, 12)
		mod.label = mod:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		mod.action = spec[1]
		mod.label:SetText(spec[2])
		frame.mods[spec[1]] = mod
	end
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetWidth(60)

	leader = CreateFrame("Frame", nil, UIParent)
	leader:SetFrameStrata("DIALOG")
	leader:SetAllPoints()
	leader.lines = {}
	for i = 1, 23 do
		local line = leader:CreateLine(nil, "ARTWORK")
		line:SetTexture(ART .. "line.tga")
		line:SetThickness(1)
		line:SetVertexColor(unpack(LEAD_COLOR))
		leader.lines[i] = line
	end
	leader.dot = leader:CreateTexture(nil, "OVERLAY")
	leader.dot:SetTexture(ART .. "disc.tga")
	leader.dot:SetVertexColor(unpack(LEAD_COLOR))
	leader.dot:SetSize(2, 2)
	leader:Hide()
	footer = buildFooter()

	frame:SetScript("OnShow", function()
		leader:Show()
		footer:Show()
	end)
	frame:SetScript("OnHide", function()
		leader:Hide()
		footer:Hide()
		set, keyFocus, repeatAction, shiftHeld, symbolsHeld = nil, nil, nil, false, false
	end)
	frame:SetScript("OnGamePadButtonDown", function(_, key) V.Press(key) end)
	frame:SetScript("OnGamePadButtonUp", function(_, key) V.Release(key) end)
	frame:SetScript("OnGamePadStick", function(_, stick, x, y) V.Stick(stick, x, y) end)
	frame:SetScript("OnUpdate", function(_, elapsed) V.Tick(elapsed) end)
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing

local function keyLabel(key, value, state, compactHidden)
	local marker = K.Marker(value)
	key.label:SetShown(not marker and not compactHidden)
	key.icon:SetShown(marker ~= nil and not compactHidden)
	if marker then return setMarker(key.icon, marker, state == "idle" and 14 or 16) end
	local long = #value > 2 and value:find("^[%w/%%]") ~= nil
	key.label:SetFontObject(long and (state == "idle" and "GameFontHighlightSmall" or "GameFontHighlight") or state == "pick" and "GameFontNormalLarge" or state == "focus" and "GameFontHighlightLarge" or "GameFontHighlightMedium")
	key.label:SetText(value)
end

local function drawDisc()
	local dx = discX()
	local compact = settings.layout == "compact"
	local sets = K.CHARSETS[charset]
	frame.disc:ClearAllPoints()
	at(frame.disc, frame, dx, CY)
	frame.glow:ClearAllPoints()
	at(frame.glow, frame, dx, CY)
	frame.rim:ClearAllPoints()
	at(frame.rim, frame, dx, CY)
	frame.hub:ClearAllPoints()
	at(frame.hub, frame, dx, CY)
	frame.hub:SetAlpha(set and 0.35 or 1)
	for i, cluster in ipairs(frame.sets) do
		local a = math.rad((i - 1) * 45)
		local sx, sy = dx + RING_R * math.sin(a), CY - RING_R * math.cos(a)
		local focused = set == i
		cluster:SetAlpha(set and not focused and 0.55 or 1)
		cluster:ClearAllPoints()
		at(cluster, frame, sx, sy)
		local hidden = compact and not focused
		for j, key in ipairs(cluster.keys) do
			local state = focused and (keyFocus == j and "pick" or "focus") or "idle"
			local size, d = focused and KEY_F or KEY, focused and KEY_FD or KEY_D
			styleKey(key, state, size)
			key:ClearAllPoints()
			key:SetPoint("CENTER", cluster, "CENTER", DIRS[j][1] * d, -DIRS[j][2] * d)
			keyLabel(key, sets[i][j], state, hidden)
		end
		local first, last = sets[i][1], sets[i][4]
		cluster.range:SetText(hidden and (K.Marker(first) and "{rt}" or first .. "–" .. last) or "")
	end
	for j, key in ipairs(frame.hubKeys) do
		key:ClearAllPoints()
		at(key, frame, dx + DIRS[j][1] * HUB_D, CY + DIRS[j][2] * HUB_D)
		key:SetAlpha(set and 0.35 or 1)
	end
	-- Modifiers above the disc: Shift's glyph and label end 30 left of the centre, Symbols' start 30 right of it.
	local on = { shift = charset == "upper" or charset == "symbols", symbols = charset == "numbers" or charset == "symbols" }
	for action, mod in pairs(frame.mods) do
		local left = action == "shift"
		mod.glyph:SetCode(settings.buttons[action])
		mod.label:SetFontObject(on[action] and "GameFontNormalSmall" or "GameFontHighlightSmall")
		mod:SetAlpha(on[action] and 1 or 0.35)
		mod.glyph:ClearAllPoints()
		mod.label:ClearAllPoints()
		if left then
			mod.label:SetPoint("RIGHT", frame, "TOPLEFT", dx - 30, -11)
			mod.glyph:SetPoint("RIGHT", mod.label, "LEFT", -8, 0)
		else
			mod.label:SetPoint("LEFT", frame, "TOPLEFT", dx + 30, -11)
			mod.glyph:SetPoint("LEFT", mod.label, "RIGHT", 8, 0)
		end
	end
	frame.title:ClearAllPoints()
	at(frame.title, frame, dx, 12)
	frame.title:SetText(sets.title)
end

-- The tab: the field (last 26 characters before the cursor, the picked key's ghost, a caret), then words or phrases.
local function lastChars(text, n)
	local count, pos = 0, #text + 1
	while pos > 1 and count < n do
		pos = pos - 1
		while pos > 1 and text:byte(pos) >= 0x80 and text:byte(pos) < 0xC0 do pos = pos - 1 end
		count = count + 1
	end
	return text:sub(pos)
end

local function boxText()
	local text = box:GetText() or ""
	local cur = box.GetUTF8CursorPosition and K.CharToByte(text, box:GetUTF8CursorPosition()) or #text
	return text, cur
end

local function drawTab()
	local tab, inner = frame.tab, frame.tab.inner
	local shown = settings.suggestions
	tab:SetShown(shown)
	if not shown then return end

	tab:ClearAllPoints()
	if mirror then
		at(tab, frame, 0, CY - TAB_H / 2, "TOPLEFT")
		tab.bg:SetTexCoord(358 / 480, 0, 0, 1)
	else
		at(tab, frame, TAB_L, CY - TAB_H / 2, "TOPLEFT")
		tab.bg:SetTexCoord(0, 358 / 480, 0, 1)
	end
	inner:ClearAllPoints()
	inner:SetPoint("TOPLEFT", mirror and 12 or FIELD_L, -10)
	inner:SetPoint("BOTTOMRIGHT", mirror and -FIELD_L or -12, 10)

	local text, cur = boxText()
	local ghost = set and keyFocus and K.CHARSETS[charset][set][keyFocus]
	inner.text:SetText(lastChars(text:sub(1, cur), 26))
	inner.ghost:SetText(ghost and K.InsertText(ghost) or "")
	local status = GetTime() < statusUntil
	inner.head:SetFontObject(status and "GameFontRedSmall" or "GameFontNormal")
	inner.head:SetText(status and statusText or string.format(T.HEAD[head.kind], head.place))

	inner.empty:SetText(#suggestions == 0 and T.EMPTY[head.kind] or "")
	local offset = rowFocus and rowFocus > ROWS and rowFocus - ROWS or 0
	for i, row in ipairs(inner.rows) do
		local item = suggestions[i + offset]
		row:SetShown(item ~= nil)
		if item then
			local focused = rowFocus == i + offset
			row.hl:SetShown(focused)
			row.text:SetText(item.text)
			row.text:SetTextColor(unpack(focused and GOLD or item.mode == "hint" and GREY or WHITE))
			local isFix = correction == i + offset
			row.tag:SetFontObject(isFix and "GameFontGreenSmall" or "GameFontDisableSmall")
			row.tag:SetText(isFix and T.CORRECTION or item.tag)
		end
	end
	for _, hint in ipairs(inner.hints) do if hint.action then hint:SetCode(settings.buttons[hint.action]) end end
end

local FOOT = { { "space", T.SPACE }, { "send", T.SEND }, { "erase", T.ERASE }, { "close", T.CLOSE }, { "shift", T.SHIFT }, { "symbols", T.SYMBOLS }, { "left", T.CURSOR, "right" } }

local function drawFooter(left)
	local x = 10
	for i, spec in ipairs(FOOT) do
		local item = footer.items[i]
		if not item then
			item = CreateFrame("Frame", nil, footer)
			item:SetHeight(24)
			item.glyph = UI.Glyph(item, 24)
			item.glyph:SetPoint("LEFT")
			item.glyph2 = UI.Glyph(item, 24)
			item.glyph2:SetPoint("LEFT", item.glyph, "RIGHT", -2, 0)
			item.label = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
			footer.items[i] = item
		end
		item.glyph:SetCode(settings.buttons[spec[1]])
		item.glyph2:SetShown(spec[3] ~= nil)
		if spec[3] then item.glyph2:SetCode(settings.buttons[spec[3]]) end
		item.label:SetText(spec[2])
		item.label:ClearAllPoints()
		item.label:SetPoint("LEFT", spec[3] and item.glyph2 or item.glyph, "RIGHT", 6, 0)
		local width = (spec[3] and 46 or 24) + 6 + item.label:GetStringWidth()
		item:SetWidth(width)
		item:ClearAllPoints()
		item:SetPoint("LEFT", footer, "LEFT", x, 0)
		x = x + width + 14
	end
	footer:SetWidth(x - 14 + 10)
	footer:ClearAllPoints()
	footer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, 8)
end

-- The leader runs to the edit box itself (not the chat frame): the point of its edge nearest the disc.
local function drawLeader(left, bottom, scale)
	local dx = discX()
	local disc = { left + dx * scale, bottom + (BH - CY) * scale, DISC_R * scale }
	local b = boxRect
	local ex = math.max(b[1] + 6, math.min(b[3] - 6, disc[1]))
	local ey = disc[2] > b[4] and b[4] - 2 or disc[2] < b[2] and b[2] + 2 or (b[2] + b[4]) / 2
	local points = K.Leader(disc, ex, ey)
	for i, line in ipairs(leader.lines) do
		line:SetStartPoint("BOTTOMLEFT", UIParent, points[i][1], points[i][2])
		line:SetEndPoint("BOTTOMLEFT", UIParent, points[i + 1][1], points[i + 1][2])
	end
	leader.dot:ClearAllPoints()
	leader.dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ex, ey)
end

-- The focused box's rect in UIParent units: { left, bottom, right, top }.
local function rectOf(edit)
	local l, b, w, h = edit:GetRect()
	if not l then return end
	local f = edit:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return { l * f, b * f, (l + w) * f, (b + h) * f }
end

local function shownRect(region) return type(region) == "table" and region:IsShown() and rectOf(region) or nil end

local function union(a, b)
	if not a then return b end
	if not b then return a end
	return { math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[3], b[3]), math.max(a[4], b[4]) }
end

-- What the keyboard must not cover: the whole chat frame of a chat box (log, its tab, the edit box), read only.
function V.ChatBounds(edit)
	local bounds = rectOf(edit)
	local chat = edit.chatFrame
	if type(chat) == "table" and chat.GetRect then
		bounds = union(bounds, shownRect(chat))
		local name = chat.GetName and chat:GetName()
		bounds = union(bounds, name and shownRect(_G[name .. "Tab"]))
	end
	return bounds
end

-- Also clear of the player's unit frame, the crossbar and our touch bars.
function V.Avoid()
	local list = {}
	for _, region in ipairs({ _G.PlayerFrame, _G.GamepadMainActionBarFrame }) do list[#list + 1] = shownRect(region) end
	local Touch = ns.Touch
	if Touch and Touch.Button then
		for _, side in ipairs({ "left", "right" }) do
			for i = 1, 12 do list[#list + 1] = shownRect(Touch.Button(side, i)) end
		end
	end
	return list
end

function V.Place()
	if not (frame and box and boxRect) then return end
	local k = settings.scale * (settings.layout == "compact" and 0.8 or 1)
	local left, bottom, scale
	chatRect = V.ChatBounds(box) or boxRect
	left, bottom, scale, mode, mirror = K.Place(boxRect, chatRect, V.Avoid(), UIParent:GetWidth(), UIParent:GetHeight(), k, settings, not settings.suggestions)
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / scale, bottom / scale)
	drawLeader(left, bottom, scale)
	drawFooter(left)
	V.Draw()
end

function V.Draw()
	if not frame then return end
	drawDisc()
	drawTab()
end

---------------------------------------------------------------------------------------------------------------------
-- Typing

-- The red note in the tab's heading, for STATUS_TIME.
local function note(text)
	statusText, statusUntil = text, GetTime() + STATUS_TIME
	drawTab()
end

-- A chat box parses a text that opens with "/" as a slash command, inside whatever call changed the text or pressed
-- Enter (ChatFrameEditBox.lua OnTextChanged -> ParseText -> ProcessChatType, and the slash handlers on Enter). Run
-- from our call that is addon code, and the game blocks what it reaches (C_Discord.IsUserOAuthed, the chat-type
-- switch, protected commands). So the keyboard never leaves such a text in a chat box, and never sends one.
local function command(text) return text:sub(1, 1) == "/" and box.GetAttribute ~= nil and box:GetAttribute("chatType") ~= nil end

local function setText(text, cur)
	if command(text) then return note(T.SLASH) end
	typedAt = GetTime()
	box:SetText(text)
	box:SetCursorPosition(cur)
end

local function insert(text)
	local before, cur = boxText()
	if command(K.Insert(before, cur, text)) then return note(T.SLASH) end
	typedAt = GetTime()
	box:Insert(text)
end

local function flash(key) key.flash:SetAlpha(1) key.flashAt = GetTime() end

local function typeKey(j)
	local value = set and K.CHARSETS[charset][set][j]
	if not value then return end
	insert(K.InsertText(value))
	flash(frame.sets[set].keys[j])
end

local function erase()
	local text, cur = boxText()
	if shiftHeld then return setText("", 0) end
	local after, at2 = K.Erase(text, cur)
	if after ~= text then setText(after, at2) end
end

local function moveCursor(step)
	local text, cur = boxText()
	box:SetCursorPosition(step < 0 and K.Left(text, cur) or K.Right(text, cur))
end

-- Send: the box's own Enter, synchronously inside this button press. A secure command (/cast, /use, /target, ...)
-- is refused: run from addon code it would be blocked, so it stays in the box for a real Enter.
function V.Send()
	local text = box:GetText() or ""
	local secure = text:match("^(/%S+)")
	if command(text) then return note(T.SLASH) end
	if secure and IsSecureCmd and IsSecureCmd(secure) then return note(T.SECURE) end
	cachedText, typedAt = text, GetTime()
	local sentIn = K.Context.Snapshot(box)
	run(box, "OnEnterPressed")
	if cachedText ~= "" then
		K.Learn(settings.dictionary, cachedText)
		K.Suggest.Sent(settings, cachedText, sentIn)
	end
	cachedText = nil
	flash(frame.hubKeys[2])
end

function V.Close()
	local edit = box
	if edit then run(edit, "OnEscapePressed") end
	V.Hide()
end

-- R1: the focused row (row 1 when none), put in the box the way Suggest.Apply says: a word replaces the word under
-- the cursor, a line the whole text, a phrase goes in at the cursor; a hint row is not taken. The rows are
-- asked for again at once, so R1 pressed again takes the next word: a sentence builds press by press.
local function insertRow()
	local item = suggestions[rowFocus or 1]
	if not item or item.mode == "hint" then return end
	setText(K.Suggest.Apply(item, boxText()))
	K.Suggest.Accept(settings, item, suggestions, context)
	rowFocus = nil
	refreshSuggestions()
end

local function stepRow(step)
	if #suggestions == 0 then return end
	rowFocus = ((rowFocus or (step > 0 and 0 or 1)) - 1 + step) % #suggestions + 1
	drawTab()
end

local function charsetNow() return K.Charset(shiftHeld, symbolsHeld, box and box.IsNumeric and box:IsNumeric() and not shiftHeld and not symbolsHeld) end

local REPEATS = { erase = erase, left = function() moveCursor(-1) end, right = function() moveCursor(1) end }

function V.Press(key)
	if not box then return end
	local code = UI.CODE[key]
	if set and FACE_OF[code] then
		typeKey(FACE_OF[code])
		return V.Draw()
	end
	local action = K.ActionOf(settings.buttons, key)
	if action == "space" then
		insert(" ")
		flash(frame.hubKeys[3])
	elseif action == "send" then
		return V.Send()
	elseif action == "close" then
		flash(frame.hubKeys[1])
		return V.Close()
	elseif action == "shift" or action == "symbols" then
		if action == "shift" then shiftHeld = true else symbolsHeld = true end
		charset = charsetNow()
	elseif action == "insert" then
		insertRow()
	elseif action == "prev" or action == "next" then
		return stepRow(action == "next" and 1 or -1)
	elseif REPEATS[action] then
		if action == "erase" then flash(frame.hubKeys[4]) end
		REPEATS[action]()
		repeatAction, repeatAt = action, GetTime() + REPEAT_DELAY
	end
	V.Draw()
end

function V.Release(key)
	local action = K.ActionOf(settings and settings.buttons or K.BUTTONS, key)
	if action == repeatAction then repeatAction = nil end
	if action == "shift" then shiftHeld = false elseif action == "symbols" then symbolsHeld = false end
	if action == "shift" or action == "symbols" then
		charset = charsetNow()
		V.Draw()
	end
end

-- Left stick: the set; right stick: highlight past 0.15, type once past 0.5, re-arm at or below it.
function V.Stick(stick, x, y)
	if not box then return end
	if stick == "Left" or stick == "Movement" then
		local now = K.SetAt(x, y)
		if now == set then return end
		set, keyFocus = now, nil
		if now then sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT) end
		return V.Draw()
	end
	if not (stick == "Right" or stick == "Camera") or not set then return end
	local hover = K.KeyAt(x, y)
	local len = math.sqrt(x * x + y * y)
	if len > K.KEY_TYPE and armed and hover then
		armed = false
		typeKey(hover)
	elseif len <= K.KEY_TYPE then
		armed = true
	end
	if hover ~= keyFocus then
		keyFocus = hover
		V.Draw()
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Suggestions: Keyboard/Suggest.lua ranks the rows for the text, the cursor and the situation
-- (Keyboard/Context.lua). They are asked for again only when one of those changes; when only the situation did, the
-- row the player is on stays focused. The word search behind them still runs in a coroutine, 2 ms a frame.

function refreshSuggestions()
	local text, cur = boxText()
	local keyNow, rev = text .. "\0" .. cur, K.Context.rev
	if keyNow == searchKey and rev == searchRev then return end
	local held = keyNow == searchKey and suggestions[rowFocus or 0]
	searchKey, searchRev, rowFocus, correction, searchJob = keyNow, rev, nil, nil, nil
	context = K.Context.Snapshot(box)
	local word = K.WordAt(text, cur)
	if not word or #word < 2 or K.Suggest.LOOKUP[context.field] then
		suggestions, head = K.Suggest.List(settings, context, text, cur)
		for i, item in ipairs(held and suggestions or {}) do if item.text == held.text then rowFocus = i end end
		return drawTab()
	end
	local dict = settings.dictionary
	searchJob = coroutine.create(function()
		local start = debugprofilestop()
		local results = K.Rank(dict, word, function()
			if debugprofilestop() - start > SEARCH_BUDGET then
				coroutine.yield()
				start = debugprofilestop()
			end
		end)
		suggestions, head, correction = K.Suggest.List(settings, context, text, cur, results)
		rowFocus = correction
		drawTab()
	end)
end

local function stepSearch()
	if not searchJob then return end
	local ok = coroutine.resume(searchJob)
	if not ok or coroutine.status(searchJob) == "dead" then searchJob = nil end
end

---------------------------------------------------------------------------------------------------------------------
-- Open, close, per frame

function V.Hide()
	box, boxRect, chatRect = nil, nil, nil
	if frame and frame:IsShown() then
		frame:Hide()
		sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_CLOSE)
	end
end

function V.Tick()
	local now = GetTime()
	for _, cluster in ipairs(frame.sets) do
		for _, key in ipairs(cluster.keys) do
			if key.flashAt then
				local t = (now - key.flashAt) / FLASH
				key.flash:SetAlpha(t >= 1 and 0 or 1 - t * t * t)
				if t >= 1 then key.flashAt = nil end
			end
		end
	end
	for _, key in ipairs(frame.hubKeys) do
		if key.flashAt then
			local t = (now - key.flashAt) / FLASH
			key.flash:SetAlpha(t >= 1 and 0 or 1 - t * t * t)
			if t >= 1 then key.flashAt = nil end
		end
	end
	if repeatAction and box and now >= repeatAt then
		REPEATS[repeatAction]()
		repeatAt = now + REPEAT_EVERY
		V.Draw()
	end
	if box and settings.suggestions then
		refreshSuggestions()
		stepSearch()
	end
	if statusUntil > 0 and now >= statusUntil then
		statusUntil = 0
		drawTab()
	end
end

-- A box we may type into: a visible, unrestricted, non-password EditBox without our opt-out attribute.
function V.Valid(edit)
	if not edit or not edit.IsObjectType or not edit:IsObjectType("EditBox") then return false end
	if edit.IsForbidden and edit:IsForbidden() then return false end
	if edit.IsAnchoringRestricted and edit:IsAnchoringRestricted() then return false end
	if not edit:IsVisible() or (edit.IsPassword and edit:IsPassword()) then return false end
	return not (edit.GetAttribute and edit:GetAttribute("ForeverControllerTweaksNoKeyboard"))
end

local function open(edit)
	local was = box
	box, boxRect = edit, rectOf(edit)
	set, keyFocus, searchKey, rowFocus, head, suggestions = nil, nil, nil, nil, WORDS, {}
	K.Context.Focus(edit)
	shiftHeld, symbolsHeld = false, false
	charset = charsetNow()
	V.Place()
	if not frame:IsShown() then
		frame:Show()
		sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_OPEN)
	elseif was ~= edit then
		V.Draw()
	end
end

-- A box the game blocks addons from typing into (Keyboard/Context.lua lists them): the keyboard stays closed, and
-- says why once per box a session.
local function refuse(edit)
	if not told[edit] then
		told[edit] = true
		ns.log(T.DENIED)
	end
	V.Hide()
end

-- A blocked action within BLOCK_WINDOW of our changing the box: its handlers reach code the game keeps from
-- addons. The box joins the denied ones; the next Observe closes the keyboard.
local function onBlocked(addon)
	if addon == addonName and box and GetTime() - typedAt <= BLOCK_WINDOW then K.Context.Deny(box, settings) end
end

-- Runs while the Gamepad UI is on and the keyboard is enabled.
function V.Observe()
	settings = db()
	if not (settings and frame) then return end
	if not (settings.enabled and ns.Active()) then return V.Hide() end
	local focus = GetCurrentKeyBoardFocus()
	if not V.Valid(focus) then return V.Hide() end
	if focus ~= box and settings.open == "controller" and lastInput ~= "pad" and not box then return end
	if K.Context.Denied(focus, settings) then return refuse(focus) end
	if focus ~= box then return open(focus) end
	-- Placed again when the box or its chat frame moves or resizes.
	local rect, chat = rectOf(focus), V.ChatBounds(focus)
	local function moved(a, b) return a and b and (a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] or a[4] ~= b[4]) end
	if moved(rect, boxRect) or moved(chat, chatRect) then
		boxRect = rect
		V.Place()
	end
end

-- The last input device, for "With the controller": a shown, empty frame of ours that lets every key through.
local function buildInput()
	input = CreateFrame("Frame", nil, UIParent)
	input:SetSize(1, 1)
	input:EnableGamePadButton(true)
	input:EnableKeyboard(true)
	input:SetPropagateKeyboardInput(true)
	input:SetScript("OnGamePadButtonDown", function() lastInput = "pad" end)
	input:SetScript("OnKeyDown", function() lastInput = "key" end)
	input:RegisterEvent("GLOBAL_MOUSE_DOWN")
	input:SetScript("OnEvent", function() lastInput = "mouse" end)
	observer = CreateFrame("Frame")
	observer:SetScript("OnUpdate", V.Observe)
end

-- Creation sets input propagation, which is restricted in combat: after a /reload in combat it waits for its end.
function V.Init()
	if frame or InCombatLockdown() then return end
	build()
	buildInput()
end

-- The settings tab's preview draws with the same key parts.
V.NewKey, V.StyleKey, V.KeyLabel = newKey, styleKey, keyLabel

function V.Frame() return frame end
function V.Box() return box end
function V.State() return { charset = charset, set = set, key = keyFocus, row = rowFocus, head = head, suggestions = suggestions, correction = correction, mode = mode, mirror = mirror } end

ns.On("PLAYER_LOGIN", V.Init)
ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)
ns.On("PLAYER_REGEN_ENABLED", V.Init)
ns.On("PLAYER_LOGOUT", function()
	local s = db()
	if not s then return end
	K.Normalize(s.dictionary)
	K.Suggest.Prune(s)
end)
ns.On("UI_SCALE_CHANGED", function() V.Place() end)
ns.On("DISPLAY_SIZE_CHANGED", function() V.Place() end)
