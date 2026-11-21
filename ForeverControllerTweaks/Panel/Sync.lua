-- Forever Controller Tweaks panel: Export, Import, the first-sync question and the sync status lines of the Settings
-- tab (design/sync.md 6), the windows in the What's new look (the portrait frame on FCT's window base). Our own frames and EditBoxes only: no Menu,
-- StaticPopup, Settings page or SmartNavigation; the clipboard is the player's Ctrl/Cmd+C and +V (CopyToClipboard is
-- protected). Both text boxes carry ForeverControllerTweaksNoKeyboard, which the on-screen keyboard skips.
local _, ns = ...
local UI = ns.UI
local L = UI.L
local Sync = ns.Sync

local STRINGS = {
	SYNC_ON = "Sync between machines",
	SYNC_ON_TIP = "Your profiles and bindings, rings, touch bars, controller setup, tweaks and keyboard settings are saved on the game's server in a few account macros (FCT:Sync 1, 2, …). Every computer you log in on uses the newest copy.\nOff: this computer stops reading and writing them. The macros stay for your other computers.",
	SYNC_LAST_LABEL = "Last synced", SYNC_SERVER_LABEL = "On the server", SYNC_WHAT_LABEL = "What syncs",
	SYNC_LAST = "%s · from %s",
	SYNC_NEVER = "Not synced yet",
	SYNC_MACROS = "%d account macros (FCT:Sync 1–%d) · %d of %d free",
	SYNC_NO_MACROS = "no sync macros · %d of %d free",
	SYNC_KEPT = "%d account macros, kept for your other computers",
	SYNC_CHARS = "bindings for %d characters", SYNC_CHAR = "bindings for 1 character",
	SYNC_RINGS = "%d rings", SYNC_RING = "1 ring",
	SYNC_REST = "profiles, touch bars, controller setup, tweaks, keyboard",
	SYNC_WHAT_OFF = "nothing on this computer",
	SYNC_WHAT_PAUSED = "paused on this computer",
	SYNC_OK = "Up to date",
	SYNC_PENDING = "Changes waiting: they go out after the fight",
	SYNC_CHOICE = "Waiting for your choice",
	SYNC_OFF = "Off on this computer",
	SYNC_NOW = "Sync now",
	SYNC_NOW_TIP = "Writes this computer's settings into the sync macros now (out of combat). It also retries after the macro list was full.",
	SYNC_EXPORT = "Export…", SYNC_EXPORT_TIP = "Your settings as text, to keep as a backup or to share.",
	SYNC_IMPORT = "Import…", SYNC_IMPORT_TIP = "Settings from an export, yours or a friend's. You see what changes first.",
	SYNC_UNDO = "Undo last sync (%s)",
	SYNC_UNDO_TIP = "Puts back the settings the last sync or import replaced: %s.",
	SYNC_FULL = "Needs %d more free account macros (Esc → Macros). Your settings stay on this computer.",
	SYNC_CORRUPT = "The sync macros were changed or are incomplete. This computer's copy will be written again.",
	SYNC_CORRUPT_FRESH = "The sync macros were changed or are incomplete. Press Sync now to replace them with this computer's settings.",
	SYNC_NEWER = "Synced by a newer Controller Tweaks. Update the addon on this computer to sync.",
	SYNC_BIG = "Too much to sync (over %d macros).",
	SYNC_UNAVAILABLE_LINE = "This game client can't sync: C_EncodingUtil is missing.",
	SYNC_FIRST = "Controller Tweaks found settings from another computer (%s, %s). Use them on this computer?",
	SYNC_FIRST_SUB = "Keep mine sends this computer's settings to the other instead. Either way, Settings → Undo last sync brings the other copy back.",
	SYNC_USE = "Use synced",
	SYNC_KEEP = "Keep mine",
	EXPORT_TITLE = "Controller Tweaks · Export",
	EXPORT_SUB = "Your settings as text, to keep or to share.",
	EXPORT_HINT = "It's selected: press Ctrl+C (Cmd+C on a Mac) to copy it.",
	EXPORT_HAS = "%s · %d characters",
	EXPORT_BINDINGS = "Bindings for this character (profile %s)",
	EXPORT_ALL = "Select all",
	EXPORT_ALL_TIP = "Selects the whole text again, ready for Ctrl+C (Cmd+C on a Mac).",
	IMPORT_TITLE = "Controller Tweaks · Import",
	IMPORT_SUB = "Settings from an export, yours or a friend's.",
	IMPORT_HINT = "Paste a Controller Tweaks export here: Ctrl+V (Cmd+V on a Mac).",
	IMPORT_WILL = "This will change:",
	IMPORT_SAME_ROW = "no change",
	IMPORT_MISSING = "not on this computer yet",
	IMPORT_BUTTONS = "%d buttons change", IMPORT_BUTTON = "1 button changes",
	IMPORT_SETTINGS = "%d settings change", IMPORT_SETTING = "1 setting changes",
	IMPORT_RINGS = "%d rings replace your %d",
	IMPORT_ROW_TIP = "Ticked parts replace yours as a whole; unticked ones stay as they are.",
	IMPORT_GO = "Import",
	IMPORT_CONFIRM = "Replace these settings with the imported ones? Settings → Undo last sync puts yours back.",
	IMPORT_BAD = "This isn't a Controller Tweaks export, or part of it is missing.",
	IMPORT_NEWER = "This export is from a newer Controller Tweaks. Update the addon to import it.",
	IMPORT_SAME = "Nothing to change: these settings match yours.",
	IMPORT_BOX_TIP = "Click the box, then paste with Ctrl+V (Cmd+V on a Mac). A controller alone can't paste.",
}
for key, text in pairs(Sync.L) do L[key] = text end
for key, text in pairs(STRINGS) do L[key] = text end

local Panel = {}
UI.Sync = Panel

local ICON = "Interface\\AddOns\\ForeverControllerTweaks\\Art\\icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CLAMP = "CLAMPTOBLACKADDITIVE"
local BODY_ALPHA, PAD, BUTTON_W, BUTTON_H, BUTTON_GAP, ROW_H = 0.75, 24, 128, 21, 12, 29
local MAX_LETTERS, DECODE_DELAY, ASK_DELAY, LINE = 32000, 0.2, 1, 14
local NONE = {}

local function plural(n, one, many) return n == 1 and one or many:format(n) end

---------------------------------------------------------------------------------------------------------------------
-- Pieces

-- FCT's window base in the What's new look: the PortraitFrameTemplate NineSlice with the addon icon as portrait, the
-- body at 0.75 without the black underlay, its focus glow; a white sub line and the divider under it.
local function newWindow(w, h, title, sub)
	local window = UI.NewWindow(w, h)
	window:SetTitle(title)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then pcall(NineSliceUtil.ApplyLayoutByName, window.NineSlice, "PortraitFrameTemplate") end
	window.glow = UI.Glow(window, window.NineSlice, "gamepad-uiframemetal-largeportrait-focus", -20, 24, 14, -14)
	window.underlay:Hide()
	if window.Bg then window.Bg:SetAlpha(BODY_ALPHA) end
	local portrait = window:CreateTexture(nil, "ARTWORK")
	portrait:SetSize(62, 62)
	portrait:SetPoint("TOPLEFT", -5, 7)
	portrait:SetTexture(ICON)
	local mask = window:CreateMaskTexture()
	mask:SetTexture(PORTRAIT_MASK, CLAMP, CLAMP)
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, 0)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 4)
	portrait:AddMaskTexture(mask)
	UI.Text(window, "GameFontHighlight", 62, 31, sub)
	local divider = window:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("Options_HorizontalDivider")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", PAD, -60)
	divider:SetPoint("TOPRIGHT", -PAD, -60)
	return window
end

-- A dialog-art button (UI.Dialog's), focused by the pad with its highlight locked.
local function button(window, label, onClick, tip)
	local b = UI.DialogButton(window)
	b:SetText(label)
	b:SetScript("OnClick", function() if b:IsEnabled() then onClick() end end)
	b.node = UI.Node(window, b, function() if b:IsEnabled() then onClick() end end, {
		onFocus = function(on) if on then b:LockHighlight() else b:UnlockHighlight() end end,
		tip = tip and { title = label, lines = { tip } } or nil,
	})
	return b
end

local function placeButtons(window, list, y)
	local x = (window:GetWidth() - #list * BUTTON_W - (#list - 1) * BUTTON_GAP) / 2
	for i, b in ipairs(list) do
		b:ClearAllPoints()
		UI.At(b, window, x + (i - 1) * (BUTTON_W + BUTTON_GAP), y)
	end
end

-- A checkbox row (What's new's): GameFontNormal label at the left, an optional white detail before the box at the
-- right, the row wash on focus. row:Set(on, enabled).
local function checkRow(window, x, y, w, onToggle)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(w, ROW_H)
	UI.At(row, window, x, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetPoint("TOPLEFT", -10, 0)
	row.wash:SetPoint("BOTTOMRIGHT", 5, 0)
	row.wash:Hide()
	row.box = UI.Checkbox(row, function() if row.enabled ~= false then onToggle() end end)
	row.box:SetPoint("RIGHT")
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", 10, 0)
	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.detail:SetPoint("RIGHT", row.box, "LEFT", -10, 0)
	row:SetScript("OnClick", function() if row.enabled ~= false then onToggle() end end)
	function row.Set(_, on, enabled)
		row.enabled = enabled ~= false
		row.box:Set(on)
		row.box:SetAlpha(row.enabled and 1 or 0.5)
		row.label:SetFontObject(row.enabled and "GameFontNormal" or "GameFontDisable")
		row.detail:SetFontObject(row.enabled and "GameFontHighlight" or "GameFontDisable")
	end
	return row
end

-- A multi-line text box in a dark inset, clipped by a scroll frame. Its height follows the text (measured on a
-- hidden font string in the same font), so the scroll bar knows the range.
local function textBox(window, x, y, w, h, withBar)
	local inset = UI.Inset(window, x, y, w, h)
	local scroll = CreateFrame("ScrollFrame", nil, window)
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", withBar and -18 or -6, 6)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(w - (withBar and 24 or 12))
	edit:SetHeight(h - 12)
	edit:SetAttribute("ForeverControllerTweaksNoKeyboard", true)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(edit)
	local measure = window:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	measure:SetWidth(w - (withBar and 24 or 12))
	measure:Hide()
	local box = { inset = inset, scroll = scroll, edit = edit, offset = 0, visible = h - 12 }
	function box.Fit()
		measure:SetText(edit:GetText())
		box.total = math.max(box.visible, measure:GetStringHeight() + 4)
		edit:SetHeight(box.total)
		box.ScrollTo(box.offset)
	end
	function box.ScrollTo(top)
		box.offset = math.max(0, math.min(top, (box.total or box.visible) - box.visible))
		scroll:SetVerticalScroll(box.offset)
		if box.bar then box.bar:Set(math.floor(box.offset + 0.5), box.visible, math.ceil(box.total or box.visible)) end
	end
	if withBar then
		box.bar = UI.ScrollBar(window, h - 12, function(top)
			local step = top - math.floor(box.offset + 0.5)
			box.ScrollTo(math.abs(step) == 1 and box.offset + step * 3 * LINE or top)
		end)
		box.bar:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -4, -6)
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta) box.ScrollTo(box.offset - delta * 3 * LINE) end)
	return box
end

local function colour(fs, color) fs:SetTextColor(color:GetRGB()) end

---------------------------------------------------------------------------------------------------------------------
-- The sync status, for the Settings tab (Panel/SettingsTab.lua), and the first-sync question over it

local function lastText(status)
	local last = status.last
	if not last then return L.SYNC_NEVER end
	local from = last.by == status.me and L.SYNC_THIS:format(Sync.Host()) or tostring(last.host)
	return L.SYNC_LAST:format(Sync.When(last.at), from)
end

local function serverText(status)
	if status.state == "off" and status.macros > 0 then return L.SYNC_KEPT:format(status.macros) end
	if status.macros == 0 then return L.SYNC_NO_MACROS:format(status.free, status.max) end
	return L.SYNC_MACROS:format(status.macros, status.top, status.free, status.max)
end

local function whatText(status)
	if status.state == "off" then return L.SYNC_WHAT_OFF end
	if status.state == "newer" then return L.SYNC_WHAT_PAUSED end
	local parts = {}
	if status.chars > 0 then parts[#parts + 1] = status.chars == 1 and L.SYNC_CHAR or L.SYNC_CHARS:format(status.chars) end
	if status.rings > 0 then parts[#parts + 1] = plural(status.rings, L.SYNC_RING, L.SYNC_RINGS) end
	parts[#parts + 1] = L.SYNC_REST
	return table.concat(parts, ", ")
end

-- { { label, value }, ... }: last synced, on the server, what syncs.
function Panel.StatusLines(status)
	return { { L.SYNC_LAST_LABEL, lastText(status) }, { L.SYNC_SERVER_LABEL, serverText(status) }, { L.SYNC_WHAT_LABEL, whatText(status) } }
end

local STATES = {
	ok = { "SYNC_OK", GREEN_FONT_COLOR }, pending = { "SYNC_PENDING", NORMAL_FONT_COLOR }, choice = { "SYNC_CHOICE", NORMAL_FONT_COLOR },
	off = { "SYNC_OFF", GRAY_FONT_COLOR }, full = { "SYNC_FULL", RED_FONT_COLOR }, corrupt = { "SYNC_CORRUPT", RED_FONT_COLOR },
	newer = { "SYNC_NEWER", RED_FONT_COLOR }, big = { "SYNC_BIG", RED_FONT_COLOR }, unavailable = { "SYNC_UNAVAILABLE_LINE", RED_FONT_COLOR },
}

-- The state line and its colour.
function Panel.StateText(status)
	local spec = STATES[status.state] or STATES.ok
	local text = L[spec[1]]
	if status.state == "full" then text = text:format(status.need or 1) end
	if status.state == "corrupt" and not status.rewriting then text = L.SYNC_CORRUPT_FRESH end
	if status.state == "big" then text = text:format(20) end
	return text, spec[2]
end

local function settings() return UI.SettingsTab and UI.SettingsTab.Window() end

-- The first-sync dialog over the Settings tab. B and Escape ask again; combat closes both and the question comes back
-- after the fight.
local function ask()
	local choice, owner = Sync.Choice(), settings()
	if not (choice and owner and owner:IsShown()) or UI.DialogShown() then return end
	UI.Dialog():Open(owner, {
		text = L.SYNC_FIRST:format(tostring(choice.host), choice.when),
		sub = L.SYNC_FIRST_SUB,
		buttons = { L.SYNC_USE, L.SYNC_KEEP },
		on1 = function() Sync.Choose(true) end,
		on2 = function() Sync.Choose(false) end,
		back = 3,
		on3 = function() C_Timer.After(0, ask) end,
	})
end

-- The Settings tab, with the first-sync question over it while one waits.
function Panel.Open()
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	if UI.SettingsTab and UI.SettingsTab.Open() then ask() end
end

-- Opens the question on its own once nothing else is in the way (no fight, no loading screen, the pad free, the
-- Gamepad UI on, no other window of ours). 1 s after the login read: before the setup guide (2 s) and What's new
-- (3 s), which both wait while a window of ours is up.
local loading = false
local function askWhenFree()
	if not Sync.Choice() or InCombatLockdown() or loading or not ns.Active() or not ns.padFree() then return end
	local current = UI.Current()
	if current and current ~= settings() then return end
	Panel.Open()
end
local function askSoon() if Sync.Choice() then C_Timer.After(ASK_DELAY, askWhenFree) end end

ns.On("FCT_SYNC_CHOICE", askSoon)
ns.On("PLAYER_REGEN_ENABLED", askSoon)
ns.On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.On("LOADING_SCREEN_DISABLED", function()
	loading = false
	askSoon()
end)
ns.On("FCT_PAD_FREE", function(free) if free then askSoon() end end)
ns.On("FCT_ACTIVE_CHANGED", function(active) if active then askSoon() end end)
ns.On("FCT_PANEL_OPEN", function(open) if not open then askSoon() end end)

---------------------------------------------------------------------------------------------------------------------
-- Export

local exportWindow, exportBox, exportHas, exportText

local function selectAll()
	exportBox.edit:SetFocus()
	exportBox.edit:HighlightText()
end

-- "Bindings for this character (profile DualSense Wireless Controller), 3 rings, touch bars, profile layout, tweaks, keyboard".
local function exportWhat(held)
	local parts = {}
	if held.bindings and next(held.bindings) then parts[#parts + 1] = L.EXPORT_BINDINGS:format(held.layout and held.layout.name or L.GENERIC_SHORT) end
	local rings = held.rings and held.rings.list and #held.rings.list or 0
	if rings > 0 then parts[#parts + 1] = plural(rings, L.SYNC_RING, L.SYNC_RINGS) end
	for _, id in ipairs({ "touch", "layout", "tweaks", "keyboard", "options" }) do
		if held[id] ~= nil then parts[#parts + 1] = L.SEC_LOWER[id] end
	end
	local text = table.concat(parts, ", ")
	return text:sub(1, 1):upper() .. text:sub(2)
end

local function buildExport()
	exportWindow = newWindow(560, 410, L.EXPORT_TITLE, L.EXPORT_SUB)
	UI.Text(exportWindow, "GameFontHighlight", PAD, 70, L.EXPORT_HINT)
	exportHas = UI.Text(exportWindow, "GameFontNormalSmall", PAD, 90, "", 560 - 2 * PAD)
	exportBox = textBox(exportWindow, PAD, 122, 560 - 2 * PAD, 214, true)
	exportBox.edit:SetMaxLetters(0)
	-- Read-only: a typed letter puts the text back.
	exportBox.edit:SetScript("OnTextChanged", function(self, user) if user and exportText then self:SetText(exportText) self:HighlightText() end end)
	-- No Print to chat: chat lines can't be selected in Forever, so the selected box is the one copy path.
	local all = button(exportWindow, L.EXPORT_ALL, selectAll, L.EXPORT_ALL_TIP)
	local close = button(exportWindow, L.CLOSE, function() UI.CloseAll() end)
	placeButtons(exportWindow, { all, close }, 352)
	exportWindow.OnRefresh = function()
		exportWindow:SetNodes({ all.node, close.node })
		local prompts = { { "PAD1", L.SELECT } }
		if exportBox.total and exportBox.total > exportBox.visible then prompts[#prompts + 1] = { GAMEPAD_STICK_RIGHT_VERTICAL or "PADRSTICKUP", L.NEWS_SCROLL } end
		prompts[#prompts + 1] = { "PAD2", L.CLOSE }
		exportWindow:SetPrompts(prompts)
	end
	exportWindow.OnClosed = function() exportBox.edit:ClearFocus() end
end

function Panel.OpenExport()
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	local text, held = Sync.Export()
	if not text then return ns.log(L.SYNC_UNAVAILABLE) end
	if not exportWindow then buildExport() end
	exportText = text
	exportHas:SetText(L.EXPORT_HAS:format(exportWhat(held), #text))
	exportBox.edit:SetText(text)
	exportBox.offset = 0
	exportBox.Fit()
	UI.Show(exportWindow)
	if exportWindow:IsShown() then selectAll() end
end

---------------------------------------------------------------------------------------------------------------------
-- Import

local IW_ = 560
local importWindow, importBox, importNote, importRows, importGo, importCancel, importBoxNode
local payload, preview, ticked, pasted, decodeToken = nil, nil, {}, nil, 0

local function rowDetail(row)
	if row.missing then return L.IMPORT_MISSING end
	if row.same then return L.IMPORT_SAME_ROW end
	if row.id == "rings" then return L.IMPORT_RINGS:format(row.rings, row.yours) end
	if row.id == "bindings" or row.id == "touch" or row.id == "layout" then return plural(row.count, L.IMPORT_BUTTON, L.IMPORT_BUTTONS) end
	return plural(row.count, L.IMPORT_SETTING, L.IMPORT_SETTINGS)
end

local function anyTicked()
	for _, row in ipairs(preview or NONE) do
		if ticked[row.id] and not row.same and not row.missing then return true end
	end
	return false
end

local function refreshImport()
	local rows, y = preview or NONE, 170
	importNote:ClearAllPoints()
	UI.At(importNote, importWindow, PAD, y)
	local nodes = { importBoxNode }
	if not payload then
		importNote:SetText(importNote.error or "")
		colour(importNote, importNote.errorColor or RED_FONT_COLOR)
	else
		local allSame = true
		for _, row in ipairs(rows) do allSame = allSame and (row.same or row.missing) end
		importNote:SetText(allSame and L.IMPORT_SAME or L.IMPORT_WILL)
		colour(importNote, allSame and GRAY_FONT_COLOR or NORMAL_FONT_COLOR)
	end
	y = y + 18
	for i, widget in ipairs(importRows) do
		local row = payload and rows[i]
		widget:SetShown(row ~= nil)
		if row then
			widget.id = row.id
			widget.label:SetText(L.SEC[row.id])
			widget.detail:SetText(rowDetail(row))
			local live = not (row.same or row.missing)
			widget:Set(live and ticked[row.id], live)
			nodes[#nodes + 1] = widget.node
			y = y + ROW_H
		end
	end
	y = math.max(y + 12, 170 + 18 + 12)
	placeButtons(importWindow, { importGo, importCancel }, y)
	importGo:SetEnabled(payload ~= nil and anyTicked())
	nodes[#nodes + 1] = importGo.node
	nodes[#nodes + 1] = importCancel.node
	importWindow:SetHeight(y + BUTTON_H + 35)
	UI.Fit(importWindow)
	importWindow:SetNodes(nodes)
	importWindow:SetPrompts({ { "PAD1", L.SELECT }, { "PAD2", L.BACK } })
end

local function decode()
	local text = importBox.edit:GetText()
	pasted = text
	payload, preview, importNote.error, importNote.errorColor = nil, nil, nil, nil
	if text:find("%S") then
		local read, why = Sync.ReadExport(text)
		if read then
			payload, preview, ticked = read, Sync.Preview(read), {}
			for _, row in ipairs(preview) do ticked[row.id] = not (row.same or row.missing) end
		else
			importNote.error = why == "newer" and L.IMPORT_NEWER or L.IMPORT_BAD
		end
	end
	refreshImport()
end

local function decodeSoon()
	decodeToken = decodeToken + 1
	local token = decodeToken
	C_Timer.After(DECODE_DELAY, function() if token == decodeToken and importWindow:IsShown() then decode() end end)
end

local function doImport()
	if not (payload and anyTicked()) then return end
	UI.Dialog():Open(importWindow, {
		text = L.IMPORT_CONFIRM,
		buttons = { L.IMPORT_GO, L.CANCEL },
		on1 = function()
			local ids = {}
			for _, row in ipairs(preview) do
				if ticked[row.id] and not row.same and not row.missing then ids[#ids + 1] = row.id end
			end
			Sync.Import(payload, ids)
			pasted, payload, preview = nil, nil, nil
			Panel.Open()
		end,
	})
end

-- Cancel forgets the pasted text; a fight only closes the window and keeps it for this session.
local function cancel()
	pasted, payload, preview = nil, nil, nil
	importBox.edit:SetText("")
	UI.CloseAll()
end

local function toggleRow(widget)
	if widget.enabled == false then return end
	ticked[widget.id] = not ticked[widget.id]
	refreshImport()
end

local function buildImport()
	importWindow = newWindow(IW_, 430, L.IMPORT_TITLE, L.IMPORT_SUB)
	UI.Text(importWindow, "GameFontHighlight", PAD, 70, L.IMPORT_HINT)
	importBox = textBox(importWindow, PAD, 90, IW_ - 2 * PAD, 66, false)
	importBox.edit:SetMaxLetters(MAX_LETTERS)
	importBox.edit:SetScript("OnTextChanged", function(_, user) if user then decodeSoon() end end)
	importBox.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	importBoxNode = UI.Node(importWindow, importBox.inset, function() importBox.edit:SetFocus() end, { tip = { title = L.IMPORT_TITLE, lines = { L.IMPORT_BOX_TIP } } })
	importNote = UI.Text(importWindow, "GameFontNormal", PAD, 170, "", IW_ - 2 * PAD)
	importRows = {}
	for i = 1, 7 do
		local widget
		widget = checkRow(importWindow, PAD, 188 + (i - 1) * ROW_H, IW_ - 2 * PAD, function() toggleRow(widget) end)
		widget.node = UI.Node(importWindow, widget, function() toggleRow(widget) end, { onFocus = function(on) widget.wash:SetShown(on) end, tip = { title = L.IMPORT_WILL, lines = { L.IMPORT_ROW_TIP } } })
		importRows[i] = widget
	end
	importGo = button(importWindow, L.IMPORT_GO, doImport)
	importCancel = button(importWindow, L.CANCEL, cancel)
	importWindow.OnRefresh = refreshImport
	importWindow.OnBack = cancel
	importWindow.OnClosed = function() importBox.edit:ClearFocus() end
end

function Panel.OpenImport()
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	if not importWindow then buildImport() end
	importBox.edit:SetText(pasted or "")
	UI.Show(importWindow)
	if not importWindow:IsShown() then return end
	decode()
	importBox.edit:SetFocus()
end
