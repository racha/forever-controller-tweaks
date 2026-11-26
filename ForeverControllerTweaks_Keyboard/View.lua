-- Forever Controller Tweaks on-screen keyboard (design/keyboard.md): a dark disc with eight 4-key
-- clusters, a command hub, the word / phrase tab and a leader line to the focused EditBox. It types into that box with
-- the box's own methods only, and finds it by polling GetCurrentKeyBoardFocus() in our own OnUpdate (no hooks). A chat
-- box is never written to: its line is composed in the tab's field and sent by our own secure button (V.Send).
-- Input: the frame has EnableGamePadButton / EnableGamePadStick and SetPropagateKeyboardInput(false) set once at
-- creation, out of combat (they are restricted in combat), so showing and hiding it never changes input settings:
-- a shown keyboard takes the pad, a hidden one takes nothing and the sticks move the character again.
local ns = ForeverControllerTweaks
local UI, K = ns.UI, ns.Keyboard
local L = UI.L

local V = {}
K.View = V

local T = {
	SHIFT = "Shift", SYMBOLS = "Symbols", CHOOSE = "Choose", INSERT = "Insert", CORRECTION = "Correction",
	SECURE = "This command needs Enter on a real keyboard.", SLASH = "Only channel switches (/s, /p, /g, /w ...): other commands need a real keyboard.",
	WHISPER_FIRST = "Start a whisper on an empty line: /w, then the name.", CHANNEL = "Channel: %s",
	NO_CHANNEL = "This chat channel can't be sent from the keyboard: switch with /s, /p, /g or /w.", LONG = "Too long for one chat line.",
	COMBAT = "In combat only party, raid, instance, guild and whispers send: the line waits.", MODIFIER = "Let go of Shift and Symbols to send.",
	BOUND = "Another binding holds the Send button: the line was not sent.", NOT_SENT = "The game did not run Send: the keyboard's chat line was not sent.", DENIED = "Typing here needs a real keyboard: the game blocks addons from this box.", SPACE = "Space", SEND = "Send", ERASE = "Erase", CLOSE = "Close", CURSOR = "Cursor",
	-- The tab's heading and its line when there are no rows, by the kind of list Suggest returned.
	HEAD = { phrases = "Quick phrases · %s", fills = "Fill-ins", words = "Words", items = "Items", names = "Names", searches = "Recent searches", none = "" },
	EMPTY = { phrases = "", fills = "No fill-in starts like that", words = "Type a word to see suggestions", items = "No matching item", names = "No matching name", searches = "No recent searches", none = "" },
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
-- typedAt: when the keyboard last changed the box's text or pressed its Enter; told: boxes whose refusal was said;
-- sent: the box a message was just sent from (or a chat box closed), kept closed until it loses the focus; tipRow:
-- the row with the tooltip; scroll: the rows above the first one shown; passing: a press went on to the game (passBack).
local typedAt, told, sent, tipRow, scroll, passing = 0, setmetatable({}, { __mode = "k" }), nil, nil, 0, false
local repeatAction, repeatAt, statusUntil, statusText, lastInput = nil, 0, 0, T.SECURE, nil
local mirror, mode = false, "right"
-- draft, draftAt: a chat box's line and its byte cursor, kept here; lineChannel: the channel a switch typed in it
-- picked (nil: the box's own); drafts: what a closed chat box had. sender: the secure button Send runs a chat line
-- through; loaded: the line on it for this press, clicked once it ran.
local draft, draftAt, lineChannel, drafts = "", 0, nil, setmetatable({}, { __mode = "k" })
local sender, loaded, clicked = nil, nil, false

-- The saved settings, repaired (K.Settings) once per table: on FCT_READY, and again only if the table is replaced.
local repaired
local function db()
	local saved = ns.db and ns.db.keyboard
	if saved and saved == repaired then return saved end
	if not ns.db then return end
	repaired = K.Settings(saved)
	ns.db.keyboard = repaired
	return repaired
end

local function sound(id) if id then PlaySound(id) end end

-- A value the game hides (a secret) is never compared or parsed: it reads as nil.
local function plain(value) if issecretvalue and issecretvalue(value) then return nil end return value end

local function chat() return box.GetAttribute ~= nil and box:GetAttribute("chatType") ~= nil end

-- Where a chat line goes: the channel its typed switch picked, else the box's own.
local function channelNow() return lineChannel or { kind = plain(box:GetAttribute("chatType")), target = plain(box:GetAttribute("tellTarget")), id = tonumber(plain(box:GetAttribute("channelTarget"))) } end

local function snapshot() return K.Context.Snapshot(box, chat() and lineChannel or nil) end

-- The chat line changes the way the chat box's text would: a complete channel switch at its start becomes the line's
-- channel and leaves the rest (K.TakeSwitch).
local function setDraft(text, cur)
	local channel, rest = K.TakeSwitch(text)
	if channel then lineChannel, cur, text = channel, math.max(0, (cur or #text) - (#text - #rest)), rest end
	draft, draftAt = text, cur or #text
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
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self) V.Tip(self) end)
		row:SetScript("OnLeave", function() V.Tip() end)
		inner.rows[i] = row
	end
	inner.up = inner:CreateTexture(nil, "OVERLAY")
	inner.up:SetAtlas("minimal-scrollbar-arrow-top", true)
	inner.up:SetPoint("BOTTOMRIGHT", inner, "TOPRIGHT", -2, -56)
	inner.down = inner:CreateTexture(nil, "OVERLAY")
	inner.down:SetAtlas("minimal-scrollbar-arrow-bottom", true)
	inner.down:SetPoint("TOPRIGHT", -2, -(60 + ROWS * 20))
	tab:EnableMouseWheel(true)
	tab:SetScript("OnMouseWheel", function(_, delta) V.Scroll(-delta) end)
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

	sender = CreateFrame("Button", "ForeverControllerTweaksChatSend", UIParent, "SecureActionButtonTemplate")
	sender:SetAttribute("type", "macro")
	sender:SetAttribute("useOnKeyDown", true)
	sender:RegisterForClicks("AnyDown", "AnyUp")
	-- It runs on the press (useOnKeyDown); the binding comes off with the release, so no half of the press goes elsewhere.
	sender:SetScript("PostClick", function(_, _, down)
		if not loaded then return end
		if down then clicked = true else V.Disarm(true) end
	end)

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

-- A command key that is not a channel switch in this client is dimmed in a chat box: it would be refused.
local function dimmed(value) return box ~= nil and box.GetAttribute ~= nil and box:GetAttribute("chatType") ~= nil and #value > 1 and value:sub(1, 1) == "/" and not K.SwitchKind(value) end

local function keyLabel(key, value, state, compactHidden)
	local marker = K.Marker(value)
	key.label:SetAlpha(dimmed(value) and 0.35 or 1)
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
		-- Compact: an unfocused set is only its range; its keys would cover that text, so they go too.
		local hidden = compact and not focused
		for j, key in ipairs(cluster.keys) do
			key:SetShown(not hidden)
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
		mod.glyph:SetCode(K.BUTTONS[action])
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
	if chat() then return draft, draftAt end
	local text = plain(box:GetText()) or ""
	local cur = box.GetUTF8CursorPosition and K.CharToByte(text, box:GetUTF8CursorPosition()) or #text
	return text, cur
end

-- A chat line is only in the tab's field, so a chat box shows the tab (its field alone with suggestions off).
local function tabShown() return settings.suggestions or box ~= nil and chat() end

local function drawTab()
	local tab, inner = frame.tab, frame.tab.inner
	local shown, full = tabShown(), settings.suggestions
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
	local switch = chat() and lineChannel and K.SwitchCommand(lineChannel) or ""
	inner.text:SetText(lastChars(switch .. text:sub(1, cur), 26))
	inner.ghost:SetText(ghost and K.InsertText(ghost) or "")
	local status = GetTime() < statusUntil
	inner.head:SetFontObject(status and "GameFontRedSmall" or "GameFontNormal")
	inner.head:SetText(status and statusText or full and string.format(T.HEAD[head.kind], head.place) or "")

	local count = #suggestions
	inner.empty:SetText(full and count == 0 and T.EMPTY[head.kind] or "")
	if rowFocus then scroll = math.max(math.min(scroll, rowFocus - 1), rowFocus - ROWS) end
	scroll = math.max(0, math.min(scroll, count - ROWS))
	for i, row in ipairs(inner.rows) do
		local item = suggestions[i + scroll]
		row.item = item
		row:SetShown(item ~= nil)
		if item then
			local focused = rowFocus == i + scroll
			row.hl:SetShown(focused)
			row.text:SetText(item.text)
			row.text:SetTextColor(unpack(focused and GOLD or item.mode == "hint" and GREY or WHITE))
			local isFix = correction == i + scroll
			row.tag:SetFontObject(isFix and "GameFontGreenSmall" or "GameFontDisableSmall")
			row.tag:SetText(isFix and T.CORRECTION or item.tag)
		end
	end
	inner.up:SetShown(scroll > 0)
	inner.down:SetShown(scroll + ROWS < count)
	for _, hint in ipairs(inner.hints) do
		hint:SetShown(full)
		if hint.action then hint:SetCode(K.BUTTONS[hint.action]) end
	end
	V.Tip()
end

-- The mouse wheel: the rows move; a focused row stays among the shown ones.
function V.Scroll(step)
	if not box then return end
	scroll = math.max(0, math.min(scroll + step, #suggestions - ROWS))
	if rowFocus then rowFocus = math.max(scroll + 1, math.min(rowFocus, scroll + ROWS)) end
	drawTab()
end

-- The full line of a row cut short by the tab's width, in the addon's tooltip, beside the tab away from the disc:
-- for the row under the mouse, else the focused row. Rows that fit get none.
function V.Tip(hovered)
	local rows = frame.tab.inner.rows
	local row = hovered
	if not row then for _, each in ipairs(rows) do if each.item and each.item == suggestions[rowFocus or 0] then row = each end end end
	local item, label = row and row:IsShown() and row.item, row and row.text
	if not (item and label.IsTruncated and label:IsTruncated()) then
		if tipRow then UI.HideTooltip(tipRow) end
		tipRow = nil
		return
	end
	tipRow = row
	local channel = item.channel and string.format(T.CHANNEL, K.Suggest.ChannelName(item.channel))
	UI.Tooltip(row, { title = item.tag ~= "" and item.tag or item.category, lines = { item.text, channel }, side = mirror and "left" or "right" })
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
		item.glyph:SetCode(K.BUTTONS[spec[1]])
		item.glyph2:SetShown(spec[3] ~= nil)
		if spec[3] then item.glyph2:SetCode(K.BUTTONS[spec[3]]) end
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
-- One of our own boxes may name the area around it (V.OWN .. "Area": the quick message dialog), kept clear like a chat.
function V.ChatBounds(edit)
	local bounds = union(rectOf(edit), shownRect(rawget(edit, V.OWN .. "Area")))
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
	left, bottom, scale, mode, mirror = K.Place(boxRect, chatRect, V.Avoid(), UIParent:GetWidth(), UIParent:GetHeight(), k, not tabShown())
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

-- A chat line holds only channel switches (K.Slash): Send runs it as a macro line, so another command would run.
-- Other boxes parse nothing.
local function command(text) return chat() and K.Slash(text) == "refused" end

-- cur nil: the end of the text.
local function setText(text, cur)
	if command(text) then return note(T.SLASH) end
	if chat() then return setDraft(text, cur) end
	typedAt = GetTime()
	box:SetText(text)
	box:SetCursorPosition(cur or #(plain(box:GetText()) or ""))
end

local function insert(text)
	local before, cur = boxText()
	local after, at2 = K.Insert(before, cur, text)
	if command(after) then return note(T.SLASH) end
	if chat() then return setDraft(after, at2) end
	typedAt = GetTime()
	box:Insert(text)
end

local function flash(key) key.flash:SetAlpha(1) key.flashAt = GetTime() end

local function typeKey(j)
	local value = set and K.CHARSETS[charset][set][j]
	if not value then return end
	flash(frame.sets[set].keys[j])
	if not (chat() and #value > 1 and value:sub(1, 1) == "/") then return insert(K.InsertText(value)) end
	if not K.SwitchKind(value) then return note(T.SLASH) end
	local line = K.PutSwitch(boxText(), value)
	if not line then return note(T.WHISPER_FIRST) end
	setText(line)
end

local function erase()
	local text, cur = boxText()
	if shiftHeld then return setText("", 0) end
	local after, at2 = K.Erase(text, cur)
	if after ~= text then setText(after, at2) end
end

local function moveCursor(step)
	local text, cur = boxText()
	local to = step < 0 and K.Left(text, cur) or K.Right(text, cur)
	if chat() then draftAt = to else box:SetCursorPosition(to) end
end

-- Our code never ends a box's focus, nor runs its Enter or Escape (which end it): focus-lost handlers drive the
-- Gamepad UI's binding stack and frame manager in our call, and the game then blocks its own calls. Bag search:
-- OnEnterPressed = EditBox_ClearFocus (InputBoxTemplates.xml:252) -> the OnEditFocusLost hook (ContainerFrame.lua:3420)
-- -> footer HideAndDeactivateBindings (PromptedBindingFooter.lua:380) -> InputBindingManager:RemoveSet (:174-191) ->
-- CheckCoreBindingActive -> UpdateActionBarFocusedState (MainActionBarFrame.lua:672, :57) -> SetPreferredGamepadInteractTarget
-- (:373). Chat: OnEditFocusLost -> ClearGamepadFocus -> FrameHidden (ChatFrameEditBox.lua:417-423).
-- The game's own B ends it as Blizzard code: out of combat, a press of B goes on to it while the Gamepad UI works on
-- this box: SmartNavigation on its chat frame (B = AttemptClose, SmartNavigation.lua:241), or the frame manager on the
-- box itself (its footer's Back, ContainerFrame.lua:3398).
local function passBack(key)
	local nav, fcm = SmartNavigation, GamepadMode and GamepadMode.FrameControlsManager
	local info, focused, chatFrame = nav and nav.bindingActive and nav.activeInfo, fcm and fcm.isUIFocused and fcm.focusedFrame, box.chatFrame
	local owned = chat() and info and chatFrame and info.frame == chatFrame or not chat() and focused == box
	if key ~= (GAMEPAD_FACE_RIGHT or "PAD2") or shiftHeld or symbolsHeld or InCombatLockdown() or not owned then return false end
	passing = true
	frame:SetPropagateKeyboardInput(true)
	return true
end

-- Once the passed press is through our frame takes the pad again (PLAYER_REGEN_DISABLED still comes before combat).
local function takeBack()
	if not passing or InCombatLockdown() then return end
	passing = false
	frame:SetPropagateKeyboardInput(false)
end

-- Our own boxes (the quick message editor) carry ForeverControllerTweaksSave / ForeverControllerTweaksCancel: Send
-- and Close call them, our code on our frame, after the keyboard closes. Nothing is learned from them.
V.OWN = "ForeverControllerTweaks"

local function own(edit, action)
	local run = rawget(edit, V.OWN .. action)
	if type(run) ~= "function" then return false end
	V.Hide()
	run(plain(edit:GetText()) or "")
	return true
end

-- A chat line is sent by the game's own code: the line goes on our secure button as its macro text, the Send key
-- clicks that button for this one press (a priority override binding on our button), and the press goes on to the
-- bindings (SecureTemplates.lua SECURE_ACTIONS.macro -> C_Macro.RunMacroText -> MacroExecutionManager.lua: a private
-- chat box of the game's sends it). The chat box, its history and its last tell are never touched by our code.
-- Attributes and bindings change only out of combat. False when the key doesn't reach the button.
local function arm(key, line)
	local click = "CLICK " .. sender:GetName() .. ":LeftButton"
	sender:SetAttribute("macrotext", line)
	SetOverrideBindingClick(sender, true, key, sender:GetName(), "LeftButton")
	loaded, clicked = line, false
	return GetBindingAction(key, true) == click
end

-- The line and the binding come off once the button ran it (ran), or the keyboard closed without it (said in chat).
function V.Disarm(ran)
	if ran then clicked = true end
	if not loaded or InCombatLockdown() then return end
	if not clicked then ns.log(T.NOT_SENT) end
	loaded = nil
	ClearOverrideBindings(sender)
	sender:SetAttribute("macrotext", nil)
end

-- In combat no secure button changes: the chat API sends the message itself, to the channels an addon may send to
-- (say, yell, emotes and numbered channels from addons are blocked outside instances).
local COMBAT_SEND = { PARTY = true, RAID = true, RAID_WARNING = true, INSTANCE_CHAT = true, GUILD = true, OFFICER = true, WHISPER = true }

local WHY = { command = T.SLASH, channel = T.NO_CHANNEL, long = T.LONG }

-- Send in a chat box: the field's line (K.ChatLine) out through our button, or in combat the chat API. Then the field
-- empties and the keyboard closes; the chat box keeps the focus, open and empty, until B. An empty line is Close. A
-- line that can't go stays, and the keyboard stays open with the note.
local function sendChat(key)
	local line, message, dest = K.ChatLine(draft, channelNow())
	if not line then
		if message == "empty" then return V.Close(key) end
		return note(WHY[message])
	end
	local combat = InCombatLockdown()
	if combat then
		local api = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
		if locked or not (api and dest and COMBAT_SEND[dest.kind]) or not pcall(api, message, dest.kind, nil, dest.target) then return note(T.COMBAT) end
	elseif shiftHeld or symbolsHeld or IsModifierKeyDown and IsModifierKeyDown() then
		return note(T.MODIFIER)
	elseif not arm(key, line) then
		V.Disarm(true)
		return note(T.BOUND)
	else
		passing = true
		frame:SetPropagateKeyboardInput(true)
	end
	K.Learn(settings.dictionary, message)
	K.Suggest.Sent(settings, message, snapshot())
	draft, draftAt, lineChannel, sent = "", 0, nil, box
	-- Out of combat the frame stays up for this press (it goes on to the button); the next Observe closes it.
	if combat then V.Hide() end
end

-- Send: a chat box's line goes out (sendChat); other boxes keep their text and nothing of theirs runs. Then the
-- keyboard closes, and on B the box's focus goes too (passBack); it opens on that box again only after the box lost
-- the focus and got it back. A secure command stays, and the keyboard stays open with the note.
function V.Send(key)
	if own(box, "Save") then return end
	if chat() then return sendChat(key) end
	local text = boxText()
	local secure = text:match("^(/%S+)")
	if secure and IsSecureCmd and IsSecureCmd(secure) then return note(T.SECURE) end
	typedAt = GetTime()
	if text ~= "" then K.Suggest.Sent(settings, text, K.Context.Snapshot(box)) end
	sent = box
	if not passBack(key) then V.Hide() end
end

-- Close: the keyboard closes and the box keeps its text (a chat box's line waits for it: V.Hide); on B its focus
-- goes too (passBack), else it keeps the focus until B or a tap elsewhere.
function V.Close(key)
	if own(box, "Cancel") then return end
	sent = box
	if not passBack(key) then V.Hide() end
end

-- R1: the focused row (row 1 when none), put in the box the way Suggest.Apply says: a word replaces the word under
-- the cursor, a line the whole text, a phrase goes in at the cursor, a switch row types its channel command (the box
-- switches); a hint row is not taken. The rows are
-- asked for again at once, so R1 pressed again takes the next word: a sentence builds press by press.
local function insertRow()
	local item = suggestions[rowFocus or scroll + 1]
	if not item or item.mode == "hint" then return end
	if item.mode == "switch" and not chat() then return end
	setText(K.Suggest.Apply(item, boxText()))
	K.Suggest.Accept(settings, item, suggestions, context)
	rowFocus = nil
	refreshSuggestions()
end

local function stepRow(step)
	if #suggestions == 0 then return end
	rowFocus = ((rowFocus or scroll + (step > 0 and 0 or 1)) - 1 + step) % #suggestions + 1
	drawTab()
end

local function charsetNow() return K.Charset(shiftHeld, symbolsHeld, box and box.IsNumeric and box:IsNumeric() and not shiftHeld and not symbolsHeld) end

local REPEATS = { erase = erase, left = function() moveCursor(-1) end, right = function() moveCursor(1) end }

local function up(key)
	local ok, down = pcall(IsKeyDown, key)
	return ok and not down
end

-- While our controller config is applied a shoulder or trigger sends its role's key; the keyboard goes by the
-- physical button, so L2 and R2 are Shift and Symbols with any layout. A held modifier keeps the key it went down
-- with (shiftHeld = key): that key's up lets it go even if the remap changed in between.
function V.Press(key)
	if not box then return end
	local pad = ns.Layout.PhysicalFor(key)
	local code = UI.CODE[pad]
	if set and FACE_OF[code] then
		typeKey(FACE_OF[code])
		return V.Draw()
	end
	local action = K.ActionOf(K.BUTTONS, pad)
	if action == "space" then
		insert(" ")
		flash(frame.hubKeys[3])
	elseif action == "send" then
		return V.Send(key)
	elseif action == "close" then
		flash(frame.hubKeys[1])
		return V.Close(key)
	elseif action == "shift" or action == "symbols" then
		if action == "shift" then shiftHeld = key else symbolsHeld = key end
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
	local action = K.ActionOf(K.BUTTONS, ns.Layout.PhysicalFor(key))
	if action == repeatAction then repeatAction = nil end
	if shiftHeld ~= key and symbolsHeld ~= key then return end
	if shiftHeld == key then shiftHeld = false end
	if symbolsHeld == key then symbolsHeld = false end
	charset = charsetNow()
	V.Draw()
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
-- (Keyboard/Context.lua) and the box's channel. They are asked for again only when one of those changes; when only
-- the situation or the channel did, the row the player is on stays focused. The word search behind them still runs in a coroutine, 2 ms a frame.

-- The box's channel, read: the chat box switches it itself (its own button, or a typed /p), and the list follows.
local function channelOf()
	if not chat() then return "" end
	local channel = channelNow()
	return tostring(channel.kind) .. "\0" .. tostring(channel.target) .. "\0" .. tostring(channel.id)
end

function refreshSuggestions()
	local text, cur = boxText()
	local keyNow, rev = text .. "\0" .. cur, K.Context.rev .. "\0" .. channelOf()
	if keyNow == searchKey and rev == searchRev then return end
	local held = keyNow == searchKey and suggestions[rowFocus or 0]
	searchKey, searchRev, rowFocus, correction, searchJob, scroll = keyNow, rev, nil, nil, nil, 0
	context = snapshot()
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
	takeBack()
	V.Disarm()
	if box and chat() then drafts[box] = (draft ~= "" or lineChannel) and { draft, lineChannel } or nil end
	box, boxRect, chatRect = nil, nil, nil
	if tipRow then UI.HideTooltip(tipRow) end
	tipRow = nil
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
	-- A lost up never leaves a modifier held.
	if shiftHeld and up(shiftHeld) then V.Release(shiftHeld) end
	if symbolsHeld and up(symbolsHeld) then V.Release(symbolsHeld) end
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
	if issecretvalue and issecretvalue(edit:GetText()) then return false end
	return not (edit.GetAttribute and edit:GetAttribute("ForeverControllerTweaksNoKeyboard"))
end

local function open(edit)
	local was = box
	box, boxRect = edit, rectOf(edit)
	set, keyFocus, searchKey, rowFocus, head, suggestions, scroll = nil, nil, nil, nil, WORDS, {}, 0
	local kept = chat() and drafts[edit] or {}
	draft, lineChannel = kept[1] or "", kept[2]
	draftAt = #draft
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

-- A blocked action within BLOCK_WINDOW of our changing the box (or sending from it, which closes the keyboard): its
-- handlers reach code the game keeps from addons. The box is denied for this session; the next Observe closes the
-- keyboard. Only a blocked function that is plainly the box's own ("<its name>:SetText()") saves the denial: any of
-- our modules may be blamed, so a block from elsewhere must not shut the box for good.
local function onBlocked(addon, fn)
	local edited = box or sent
	if not (type(addon) == "string" and addon:find("^ForeverControllerTweaks") and edited and GetTime() - typedAt <= BLOCK_WINDOW) then return end
	local name, called = plain(edited.GetName and edited:GetName()), plain(fn)
	local ownCall = type(name) == "string" and name ~= "" and type(called) == "string" and (called:sub(1, #name + 1) == name .. ":" or called:sub(1, #name + 1) == name .. ".")
	K.Context.Deny(edited, settings, ownCall)
end

-- A tap on the screen (Steam Link sends touches as mouse clicks) counts as the controller while our touch bars are on.
local function touchBars()
	local Touch = ns.Touch
	local config = Touch and Touch.Config and Touch.Config()
	return config and config.enabled and config.show ~= "never"
end

-- The observer runs only while the keyboard is enabled and the Gamepad UI is on (V.Wake).
function V.Wake()
	settings = db()
	local on = settings and settings.enabled and ns.Active() and true or false
	if observer then observer:SetShown(on) end
	if not on then V.Hide() end
end

function V.Observe()
	settings = db()
	if not (settings and frame) then return end
	if not (settings.enabled and ns.Active()) then return V.Hide() end
	local focus = GetCurrentKeyBoardFocus()
	if sent and focus ~= sent then sent = nil end
	if not V.Valid(focus) or focus == sent then return V.Hide() end
	if focus ~= box and settings.open == "controller" and not box and not (lastInput == "pad" or lastInput == "mouse" and touchBars()) then return end
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
	V.Wake()
end

-- Creation sets input propagation, which is restricted in combat: after a /reload in combat it waits for its end.
function V.Init()
	if frame or InCombatLockdown() then return end
	build()
	buildInput()
end

-- The settings tab's preview draws with the same key parts.
V.NewKey, V.StyleKey, V.KeyLabel = newKey, styleKey, keyLabel

-- Text in at the cursor, as the keyboard types it (the specs type with it).
function V.Type(text)
	if not box then return end
	insert(text)
	V.Draw()
end

function V.Frame() return frame end
function V.Box() return box end
function V.State() return { charset = charset, set = set, key = keyFocus, row = rowFocus, scroll = scroll, head = head, suggestions = suggestions, correction = correction, mode = mode, mirror = mirror, draft = draft, at = draftAt, channel = lineChannel } end

ns.On("PLAYER_LOGIN", V.Init)
ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)
ns.On("PLAYER_REGEN_ENABLED", function()
	V.Init()
	V.Disarm()
end)
-- Still out of combat here: the pad and the Send button are given back before the lockdown.
ns.On("PLAYER_REGEN_DISABLED", function()
	takeBack()
	V.Disarm()
end)
ns.On("FCT_READY", function()
	repaired = nil
	local s = db()
	if s then K.Context.Forget(s) end
	V.Wake()
end)
ns.On("FCT_ACTIVE_CHANGED", function() V.Wake() end)
ns.On("PLAYER_LOGOUT", function()
	local s = db()
	if not s then return end
	K.Normalize(s.dictionary)
	K.Suggest.Prune(s)
end)
ns.On("UI_SCALE_CHANGED", function() V.Place() end)
ns.On("DISPLAY_SIZE_CHANGED", function() V.Place() end)
