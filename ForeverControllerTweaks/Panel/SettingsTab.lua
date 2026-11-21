-- Forever Controller Tweaks "Settings" side tab, in the Tweaks tab's look (its four insets, section headers and rows):
-- Profile (the profile this controller uses, its name, New, Copy, Delete), the controllers this computer knows and their
-- profiles, Sync between machines (the switch, the status, Sync now, Undo last sync) and Backup (Export… and Import…,
-- the windows of Panel/Sync.lua). Profiles are Profile.lua's: a switch applies out of combat with the pad free. Y opens
-- More, as on every tab.
local _, ns = ...
local UI = ns.UI
local L = UI.L
local Profile, Sync = ns.Profile, ns.Sync

local S = {}
UI.SettingsTab = S

local T = {
	TAB = "Settings", TITLE = "Controller Tweaks · Settings", HINT = "Profiles for your controllers, sync between your computers and backups.",
	PROFILE = "Profile", CONTROLLERS = "Controllers", SYNC = "Sync between machines", BACKUP = "Backup",
	THIS = "This controller",
	THIS_TIP = "The profile %s uses: modifier roles, face buttons and every character's bindings. Controllers on the same profile share all of it; glyphs and button setup stay each controller's own.",
	THIS_PENDING = "Not picked yet: it plays on this profile until you pick one.",
	NAME = "Name", NAME_TIP = "This profile's name. A starts typing; Enter keeps it, Escape puts it back.",
	NEW = "New profile", NEW_TIP = "An empty profile for this controller: the game's own layout and no bindings.",
	NEW_NAME = "New profile",
	COPY = "Copy profile", COPY_TIP = "A copy of this profile for this controller, with every character's bindings, to change on its own.",
	DELETE = "Delete profile", DELETE_TIP = "Deletes this profile and every character's bindings in it, on every computer that syncs. Its controllers move to %s.",
	DELETE_LAST = "The last profile can't be deleted.",
	DELETE_ASK = "Delete the profile %s?", DELETE_SUB = "Every character's bindings in it go too. Its controllers move to %s.", DELETE_GO = "Delete",
	NO_PAD = "No controller found: connect one to pick its profile.",
	PAD_PROFILE = "Profile: %s", PAD_THIS = "Profile: %s · this controller", PAD_MORE = "and %d more",
	EXPORT_TIP = "Your settings as text, to keep as a backup or to share: this controller's profile with this character's bindings, touch bars, rings, tweaks, keyboard and options.",
	IMPORT_TIP = "Settings from an export, yours or a friend's, into this controller's profile. You see what changes first.",
	BACKUP_HINT = "Export… shows your settings as text to copy; Import… takes one back. Undo last sync puts back what an import replaced.",
	ASK = "New controller: %s",
	ASK_SUB = "Use shares a profile's bindings and layout with your other controllers. Copy starts from a copy you change on its own; New empty starts from the game's layout. Settings → Profile changes it any time.",
	ASK_USE = "Use %s", ASK_COPY = "Copy %s…", ASK_NEW = "New empty",
}
S.T = T

local GEO = UI.TweaksTab.GEO
local X, TOP, INSET_W, INSET_H, HEADER_W = GEO.X, GEO.TOP, GEO.INSET_W, GEO.INSET_H, GEO.HEADER_W
local ROW_W, ROW_H, ROW_PITCH, CONTROL_END, CHOICE_W = GEO.ROW_W, GEO.ROW_H, GEO.ROW_PITCH, GEO.CONTROL_END, GEO.CHOICE_W
local FIRST_ROW, BUTTON_W, BUTTON_H, NAME_W, MAX_PADS, LINE_GAP = TOP + 62, 200, 21, 150, 8, 4

local window
local rows, pads, status = {}, {}, {}
local nameBox, hint

local function rowX(column) return X[column] + (INSET_W - ROW_W) / 2 end

local function hasPad() return ns.Device and ns.Device.Current() ~= nil end

---------------------------------------------------------------------------------------------------------------------
-- Profile

local function profileIndex(items, id)
	for i, item in ipairs(items) do if item.id == id then return i end end
	return 1
end

-- One step through the profiles (A rounds); false past an end.
local function stepProfile(by, wrap)
	local items = Profile.List()
	if not (hasPad() and items[1]) then return false end
	local index = profileIndex(items, Profile.CurrentId())
	local item = items[wrap and (index + by - 1) % #items + 1 or index + by]
	if not item then return false end
	Profile.Use(item.id)
end

-- The first profile but this one: where Delete moves its controllers.
local function heir(id)
	for _, item in ipairs(Profile.List()) do if item.id ~= id then return item end end
end

local function newProfile()
	if not hasPad() then return end
	Profile.Use(Profile.New(T.NEW_NAME))
end

local function copyProfile()
	local _, id = Profile.Current()
	if not id then return end
	Profile.Use((Profile.Copy(id)))
end

local function deleteProfile()
	local profile, id = Profile.Current()
	local after = profile and heir(id)
	if not after then return end
	UI.Dialog():Open(window, {
		text = T.DELETE_ASK:format(profile.name),
		sub = T.DELETE_SUB:format(after.name),
		buttons = { T.DELETE_GO, L.CANCEL },
		on1 = function() Profile.Delete(id) end,
	})
end

-- Enter or a lost focus keeps the typed name (an empty one puts the old one back); Escape puts it back.
local function commitName()
	local _, id = Profile.Current()
	local text = nameBox:GetText()
	if id and text:find("%S") then Profile.Rename(id, text) end
	window:Refresh()
end

local function editName()
	if not Profile.Current() then return end
	nameBox:SetFocus()
	nameBox:HighlightText()
end

---------------------------------------------------------------------------------------------------------------------
-- Rows

local function newRow(column, y, label, indent)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(ROW_W, ROW_H)
	UI.At(row, window, rowX(column), y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", indent or 10, 0)
	row.label:SetText(label)
	return row
end

local function placeControl(row, control, width)
	control:SetPoint("LEFT", row, "LEFT", CONTROL_END - (width or control:GetWidth()), 0)
	row.control = control
end

-- A wide dialog-art button centred in its column (Sync & backup's look), focused with its highlight locked.
local function newButton(column, y, label, onClick)
	local button = UI.DialogButton(window)
	button:SetSize(BUTTON_W, BUTTON_H)
	button:SetText(label)
	UI.At(button, window, X[column] + (INSET_W - BUTTON_W) / 2, y + (ROW_H - BUTTON_H) / 2)
	button:SetScript("OnClick", function() if button:IsEnabled() then onClick() end end)
	button.run = onClick
	return button
end

local function buttonNode(button, tip, side)
	return UI.Node(window, button, function() if button:IsEnabled() then button.run() end end, {
		onFocus = function(on) if on then button:LockHighlight() else button:UnlockHighlight() end end,
		tip = { title = button:GetText(), lines = { tip }, side = side },
	})
end

local function rowFocus(row)
	return function(focused)
		row.wash:SetShown(focused)
		if row.control and row.control.SetFocused then row.control:SetFocused(focused) end
	end
end

local function buildProfile()
	local y = FIRST_ROW
	rows.profile = newRow(1, y, T.THIS)
	placeControl(rows.profile, UI.Dropdown(rows.profile, CHOICE_W, stepProfile))
	y = y + ROW_PITCH
	rows.name = newRow(1, y, T.NAME)
	nameBox = CreateFrame("EditBox", nil, rows.name, "InputBoxTemplate")
	nameBox:SetSize(NAME_W, 20)
	nameBox:SetAutoFocus(false)
	nameBox:SetFontObject("GameFontHighlight")
	nameBox:SetMaxLetters(32)
	nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	nameBox:SetScript("OnEscapePressed", function(self)
		self:SetText((Profile.Current() or {}).name or "")
		self:ClearFocus()
	end)
	nameBox:SetScript("OnEditFocusLost", commitName)
	placeControl(rows.name, nameBox, NAME_W)
	rows.name:SetScript("OnClick", editName)
	y = y + ROW_PITCH
	rows.new = newButton(1, y, T.NEW, newProfile)
	y = y + ROW_PITCH
	rows.copy = newButton(1, y, T.COPY, copyProfile)
	y = y + ROW_PITCH
	rows.delete = newButton(1, y, T.DELETE, deleteProfile)
	rows.noPad = UI.Text(window, "GameFontDisableSmall", rowX(1) + 10, y + ROW_PITCH + 4, T.NO_PAD, ROW_W - 20)
end

-- Read-only: each controller's name and the profile it plays on.
local function buildControllers()
	for i = 1, MAX_PADS + 1 do
		local y = FIRST_ROW + (i - 1) * ROW_PITCH
		pads[i] = { name = UI.Text(window, "GameFontNormal", rowX(2) + 10, y, "", ROW_W - 20), profile = UI.Text(window, "GameFontHighlightSmall", rowX(2) + 10, y + 17, "", ROW_W - 20) }
		pads[i].name:SetWordWrap(false)
		pads[i].profile:SetWordWrap(false)
	end
end

-- The same state and chat line as /fct sync on|off; this computer only, never synced.
local function toggleSync()
	local on = not Sync.Status().on
	Sync.SetOn(on)
	ns.log(on and L.SYNC_LINE_ON or L.SYNC_LINE_OFF)
	window:Refresh()
end

local function buildSync()
	rows.syncOn = newRow(3, FIRST_ROW, L.SYNC_ON)
	placeControl(rows.syncOn, UI.Checkbox(rows.syncOn, toggleSync))
	for i = 1, 3 do status[i] = { label = UI.Text(window, "GameFontNormalSmall", 0, 0, "", ROW_W - 20), value = UI.Text(window, "GameFontHighlightSmall", 0, 0, "", ROW_W - 20) } end
	status.state = UI.Text(window, "GameFontHighlightSmall", 0, 0, "", ROW_W - 20)
	rows.syncNow = newButton(3, 0, L.SYNC_NOW, function()
		Sync.Now()
		window:Refresh()
	end)
	rows.undo = newButton(3, 0, "", function() Sync.Undo() end)
end

local function buildBackup()
	rows.export = newButton(4, FIRST_ROW, L.SYNC_EXPORT, function() UI.Sync.OpenExport() end)
	rows.import = newButton(4, FIRST_ROW + ROW_PITCH, L.SYNC_IMPORT, function() UI.Sync.OpenImport() end)
	hint = UI.Text(window, "GameFontDisableSmall", rowX(4) + 10, FIRST_ROW + 2 * ROW_PITCH + 4, T.BACKUP_HINT, ROW_W - 20)
end

---------------------------------------------------------------------------------------------------------------------
-- Refresh

local function refreshProfile(nodes)
	local device, items = ns.Device and ns.Device.Current(), Profile.List()
	local profile, id = Profile.Current()
	local live = device ~= nil and profile ~= nil
	local index = profileIndex(items, id)
	rows.profile.control:Set(profile and profile.name or "", index == 1, index == #items)
	if not nameBox:HasFocus() then nameBox:SetText(profile and profile.name or "") end
	nameBox:EnableMouse(live)
	for _, key in ipairs({ "profile", "name" }) do rows[key].label:SetFontObject(live and "GameFontNormal" or "GameFontDisable") end
	rows.new:SetEnabled(device ~= nil)
	rows.copy:SetEnabled(live)
	local after = live and heir(id)
	rows.delete:SetEnabled(not not after)
	rows.noPad:SetShown(not device)
	if not device then return end

	local lines = { T.THIS_TIP:format(device.name or device.key) }
	if Profile.Pending() then lines[2] = T.THIS_PENDING end
	lines[#lines + 1] = L.CHOICE_TIP
	nodes[#nodes + 1] = UI.Node(window, rows.profile, function() stepProfile(1, true) end, { cursorX = 0, onDir = stepProfile, noSide = true, onFocus = rowFocus(rows.profile), tip = { title = T.THIS, lines = lines, side = "right" } })
	if profile then nodes[#nodes + 1] = UI.Node(window, rows.name, editName, { cursorX = 0, onFocus = rowFocus(rows.name), tip = { title = T.NAME, lines = { T.NAME_TIP }, side = "right" } }) end
	nodes[#nodes + 1] = buttonNode(rows.new, T.NEW_TIP, "right")
	if live then nodes[#nodes + 1] = buttonNode(rows.copy, T.COPY_TIP, "right") end
	if live then nodes[#nodes + 1] = buttonNode(rows.delete, after and T.DELETE_TIP:format(after.name) or T.DELETE_LAST, "right") end
end

local function refreshControllers()
	local list, current = Profile.Controllers(), ns.Device and ns.Device.Current()
	for i, line in ipairs(pads) do
		local pad = list[i]
		local more = i == MAX_PADS + 1 and #list > MAX_PADS + 1
		line.name:SetText(more and T.PAD_MORE:format(#list - MAX_PADS) or pad and pad.name or "")
		local profile = not more and pad and Profile.Get(pad.id)
		local here = current and pad and pad.key == current.key
		line.profile:SetText(profile and (here and T.PAD_THIS or T.PAD_PROFILE):format(profile.name) or "")
	end
end

-- The status lines of Panel/Sync.lua under the switch; Sync now and Undo follow them.
local function refreshSync(nodes)
	local info = Sync.Status()
	rows.syncOn.control:Set(info.on)
	rows.syncOn.label:SetFontObject(info.state ~= "unavailable" and "GameFontNormal" or "GameFontDisable")
	if info.state ~= "unavailable" then nodes[#nodes + 1] = UI.Node(window, rows.syncOn, toggleSync, { cursorX = 0, onFocus = rowFocus(rows.syncOn), tip = { title = L.SYNC_ON, lines = { L.SYNC_ON_TIP }, side = "left" } }) end
	local x, y = rowX(3) + 10, FIRST_ROW + ROW_PITCH
	for i, pair in ipairs(UI.Sync.StatusLines(info)) do
		local line = status[i]
		line.label:ClearAllPoints()
		UI.At(line.label, window, x, y)
		line.label:SetText(pair[1])
		line.value:ClearAllPoints()
		UI.At(line.value, window, x, y + 13)
		line.value:SetText(pair[2])
		y = y + 13 + line.value:GetStringHeight() + LINE_GAP + 2
	end
	local text, color = UI.Sync.StateText(info)
	status.state:ClearAllPoints()
	UI.At(status.state, window, x, y)
	status.state:SetText(text)
	status.state:SetTextColor(color:GetRGB())
	y = y + status.state:GetStringHeight() + 12
	rows.syncNow:ClearAllPoints()
	UI.At(rows.syncNow, window, X[3] + (INSET_W - BUTTON_W) / 2, y)
	rows.syncNow:SetEnabled(info.on and info.state ~= "newer" and info.state ~= "unavailable" and info.state ~= "choice")
	nodes[#nodes + 1] = buttonNode(rows.syncNow, L.SYNC_NOW_TIP, "left")
	local backup = info.backup
	rows.undo:SetShown(backup ~= nil)
	if not backup then return end
	local keys = {}
	for key in pairs(backup.s) do keys[#keys + 1] = key end
	rows.undo:SetText(L.SYNC_UNDO:format(Sync.When(backup.at)))
	rows.undo:ClearAllPoints()
	UI.At(rows.undo, window, X[3] + (INSET_W - BUTTON_W) / 2, y + ROW_PITCH)
	nodes[#nodes + 1] = buttonNode(rows.undo, L.SYNC_UNDO_TIP:format(Sync.KindList(keys)), "left")
end

local function prompts() return { { "PAD1", L.SELECT }, { "PAD4", L.MORE }, UI.TabPrompt("settings", -1), { "PAD2", L.CLOSE } } end

local function refresh()
	local nodes = {}
	refreshProfile(nodes)
	refreshControllers()
	refreshSync(nodes)
	local available = Sync.Available()
	rows.export:SetEnabled(available)
	rows.import:SetEnabled(available)
	nodes[#nodes + 1] = buttonNode(rows.export, T.EXPORT_TIP, "left")
	nodes[#nodes + 1] = buttonNode(rows.import, T.IMPORT_TIP, "left")
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(prompts()) end
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.settings then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(T.TITLE)
	UI.Text(window, "GameFontDisableSmall", 24, 33, T.HINT)
	for i, title in ipairs({ T.PROFILE, T.CONTROLLERS, T.SYNC, T.BACKUP }) do
		UI.Inset(window, X[i], TOP, INSET_W, INSET_H)
		UI.SectionHeader(window, X[i] + (INSET_W - HEADER_W) / 2, TOP + 12, HEADER_W, title)
	end
	buildProfile()
	buildControllers()
	buildSync()
	buildBackup()

	window.OnRefresh = refresh
	window.OnFocusChanged = function() if not UI.DialogShown() then window:SetPrompts(prompts()) end end
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		if key ~= "PAD4" then return end
		UI.OpenMore(window)
		return true
	end
	window.OnClosed = function() if nameBox:HasFocus() then nameBox:ClearFocus() end end
	-- A question over the tab (first sync, new controller, Delete) closes only with an answer: the X waits.
	window.ClosePanelButton:SetScript("OnClick", function() if not UI.DialogShown() then UI.CloseAll() end end)
end

function S.Window() return window end

function S.Open()
	if not ns.db then return end
	if not window then build() end
	UI.Show(window)
	return window:IsShown() and window or nil
end

---------------------------------------------------------------------------------------------------------------------
-- The new-controller question: a controller with no pick of its own while a profile exists (Profile.Pending). It plays
-- on the last profile used meanwhile; B answers Use. It waits for no fight, no loading screen, the pad free, the
-- Gamepad UI on, the login sync settled (it may bring this controller's pick) and no other window or question of ours,
-- so the controller setup and the first-run guide (2 s), What's new (3 s) and the first-sync question come first. Then
-- the Settings tab opens with the question over it.

local ASK_DELAY, BUTTON_NAME = 4, 12
local loading = false
local askSoon

-- A profile name short enough for a dialog button.
local function short(name)
	if #name <= BUTTON_NAME then return name end
	return (name:sub(1, BUTTON_NAME - 1):gsub("[\192-\255][\128-\191]*$", "")) .. "…"
end

local function ask()
	local device = ns.Device and ns.Device.Current()
	if not (device and Profile.Pending() and window and window:IsShown()) or UI.DialogShown() then return end
	local items, key, name = Profile.List(), device.key, device.name or device.key
	local pick = profileIndex(items, Profile.CurrentId())
	local function chosen() return items[pick] end
	local function answered(id)
		Profile.Use(id, key)
		askSoon()
	end
	local stepper = #items > 1 and {
		label = function() return chosen().name, pick == 1, pick == #items end,
		step = function(by, wrap) pick = wrap and (pick + by - 1) % #items + 1 or math.max(1, math.min(#items, pick + by)) end,
	} or nil
	UI.Dialog():Open(window, {
		text = T.ASK:format(name),
		sub = T.ASK_SUB,
		buttons = function() return { T.ASK_USE:format(short(chosen().name)), T.ASK_COPY:format(short(chosen().name)), T.ASK_NEW } end,
		stepper = stepper,
		back = 1,
		on1 = function() answered(chosen().id) end,
		on2 = function() answered((Profile.Copy(chosen().id, name))) end,
		on3 = function() answered(Profile.New(name)) end,
	})
end
S.Ask = ask

local function askWhenFree()
	if not Profile.Pending() or InCombatLockdown() or loading or not ns.Active() or not ns.padFree() or UI.DialogShown() then return end
	if ns.Sync and not ns.Sync.Settled() then return end
	local current = UI.Current()
	if current and current ~= window then return end
	if S.Open() then ask() end
end
function askSoon() if Profile.Pending() then C_Timer.After(ASK_DELAY, askWhenFree) end end

ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then askSoon() end end)
ns.On("FCT_SYNC_SETTLED", askSoon)
ns.On("PLAYER_REGEN_ENABLED", askSoon)
ns.On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.On("LOADING_SCREEN_DISABLED", function()
	loading = false
	askSoon()
end)
ns.On("FCT_PAD_FREE", function(free) if free then askSoon() end end)
ns.On("FCT_ACTIVE_CHANGED", function(active) if active then askSoon() end end)
ns.On("FCT_PANEL_OPEN", function(open) if not open then askSoon() end end)

local function redraw() if window and window:IsShown() then UI.RefreshSoon(window) end end
ns.On("FCT_SYNC_CHANGED", redraw)
ns.On("FCT_PROFILES_CHANGED", redraw)
ns.On("FCT_LAYOUT_CHANGED", redraw)

-- The last side tab (Bindings, Touch, Keyboard, Rings, Tweaks, of those loaded, then Settings).
UI.AddTab({ "Interface\\Icons\\INV_Misc_Gear_01", T.TAB, function() S.Open() end, settings = true, order = 6, prompt = T.TAB })
