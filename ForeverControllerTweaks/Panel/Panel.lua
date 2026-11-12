-- Forever Controller Tweaks panel entry points: /fct, the pad shortcut (hold L2 + R2, press Create), the Key Bindings
-- entry, Options > AddOns and the compartment open the Bindings window (Modifiers is its second tab); /fct setup
-- the guide. Blocked-action reports are Core's (ns.OnBlocked).
local _, ns = ...
local UI = ns.UI

function ns.TogglePanel()
	if UI.Current() then return UI.CloseAll() end
	UI.Bindings.Open()
end

function ns.commands.bindings() UI.Bindings.Open() end
function ns.commands.setup() UI.Onboarding.Start() end

-- /fct detect opens controller setup; the engine's chat flow stays as /fct detect chat [skip|back|...].
local chatDetect = ns.commands.detect
function ns.commands.detect(args)
	if (args[1] or ""):lower() == "chat" and chatDetect then
		table.remove(args, 1)
		return chatDetect(args)
	end
	if args[1] and chatDetect then return chatDetect(args) end
	UI.Detect.Open()
end

-- The pad shortcut: hold the physical L2 + R2 (wherever the layout sends them), then press Create. Nothing is bound:
-- in gamepad mode the triggers are not key modifiers (IsShiftKeyDown stays false), so no binding can ask for them,
-- and a binding on Create would take Create alone from the game and other addons. A listener frame sees every pad
-- press and passes it on, except the shortcut press itself, out of combat. It is hidden in combat: the addon can't
-- open then, and the pass-on flag can't be changed under lockdown. Shown only while the Gamepad UI is on.
local listener = CreateFrame("Frame", "ForeverControllerTweaksShortcut", UIParent)
listener:Hide()

-- The mapped buttons the physical ones send now: ours while the remap is applied, else native.
local function held(physList)
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
	local buttons = ok and type(state) == "table" and state.buttons
	if not buttons then return false end

	local outputs = ns.Remap.Outputs() or ns.Layout.NATIVE_KEY
	for _, phys in ipairs(physList) do
		local index = outputs[phys] and C_GamePad.ButtonBindingToIndex(outputs[phys])
		if not (index and buttons[index + 1]) then return false end
	end
	return true
end

listener:EnableGamePadButton(true)
listener:SetPropagateKeyboardInput(true)
listener:SetScript("OnGamePadButtonDown", function(self, key)
	if InCombatLockdown() then return end
	local toggle = UI.Toggle()
	local mine = toggle.keys[key] and (toggle.hold[1] and held(toggle.hold) or not toggle.hold[1] and ns.padFree())
	self:SetPropagateKeyboardInput(not mine)
	if mine then ns.TogglePanel() end
end)
listener:SetScript("OnGamePadButtonUp", function(self) if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)

local function updateListener()
	if InCombatLockdown() then return listener:Hide() end
	listener:SetPropagateKeyboardInput(true)
	listener:SetShown(ns.Active())
end

ns.On("FCT_ACTIVE_CHANGED", updateListener)
ns.On("PLAYER_ENTERING_WORLD", updateListener)
ns.On("PLAYER_REGEN_ENABLED", updateListener)
ns.On("PLAYER_REGEN_DISABLED", function() listener:Hide() end)

local coreHelp = ns.commands.help
function ns.commands.help(args)
	coreHelp(args)
	ns.log(UI.OpenWays() .. UI.L.HELP_MORE)
end

-- Addon compartment (minimap AddOns button), declared in the TOC. Blizzard calls these globals after
-- forceinsecure(); the window opens on the next frame, outside the compartment menu's own click handling.
function ForeverControllerTweaks_OnCompartmentClick()
	C_Timer.After(0, function() UI.Bindings.Open() end)
end

function ForeverControllerTweaks_OnCompartmentEnter(_, button)
	UI.Tooltip(button, { title = UI.L.NOTICE_TITLE, lines = { UI.L.COMPARTMENT_TIP } })
end

function ForeverControllerTweaks_OnCompartmentLeave(_, button) UI.HideTooltip(button) end

-- Options > AddOns > Forever Controller Tweaks: one native vertical-layout category with native button rows only, so the
-- Settings panel's own gamepad navigation runs it and the addon adds nothing to it. A row opens the addon above the
-- panel (FULLSCREEN_DIALOG over HIGH) on the next frame, outside the row button's click. Registered once at login,
-- out of combat; a missing API logs and skips it.
-- Options can't be closed from addon code: every close path (Close, CloseButton, Escape, ExitWithCommit) ends in
-- HideUIPanel (Blizzard_SettingsPanel.lua 40-45, 64-69, 256-302), which taints the gamepad binding stack. It goes
-- transparent under the addon instead (SetAlpha only, no Lua fields written), a shield takes its mouse, the addon's
-- window keeps every pad press, and it comes back when the addon closes, like a native sub-window's parent.
local settingsDone = false
local shield = CreateFrame("Frame", nil, UIParent)
shield:SetAllPoints()
shield:SetFrameStrata("DIALOG")
shield:EnableMouse(true)
shield:EnableMouseWheel(true)
shield:Hide()

local function nextFrame(fn)
	return function()
		C_Timer.After(0, function()
			fn()
			if not (ns.panelOpen and SettingsPanel and SettingsPanel:IsShown()) then return end
			SettingsPanel:SetAlpha(0)
			shield:Show()
		end)
	end
end

-- Interact off its native face button: the world's interact prompts still show the native glyph (the game draws
-- them from its own binding), so say so once per new button, over our open window, unless turned off.
local function interactAt(code)
	local entry = ns.Face.CellEntry(code, "T")
	if entry then return entry.id == "face:interact" end
	return ns.Layout.Face()[UI.CODE_POS[code]] == "interact"
end

local function checkInteract()
	local options, owner = ns.db and ns.db.options, UI.Current()
	if not options or options.interactNoticeOff or InCombatLockdown() or not owner or owner.notice or UI.DialogShown() then return end

	local native
	for code, pos in pairs(UI.CODE_POS) do if ns.Layout.NATIVE_FACE[pos] == "interact" then native = code end end
	if interactAt(native) then
		options.interactNoticed = nil
		return
	end
	local now = "none"
	for _, code in ipairs({ "FB", "FR", "FT" }) do if code ~= native and interactAt(code) then now = code break end end
	if options.interactNoticed == now then return end

	options.interactNoticed = now
	local L = UI.L
	local first = now == "none" and L.INTERACT_GONE or string.format(L.INTERACT_MOVED, UI.ButtonText(now))
	UI.Dialog():Open(owner, { text = string.format(L.INTERACT_PROMPTS, first, UI.ButtonText(native)), sub = L.INTERACT_HIDE, buttons = { L.OK, L.DONT_SHOW_AGAIN }, back = 1, on2 = function() options.interactNoticeOff = true end })
end

-- Next frame: after the picker or slash command that made the change has finished.
local function laterCheckInteract() C_Timer.After(0, checkInteract) end
ns.On("FCT_LAYOUT_CHANGED", laterCheckInteract)

-- Blizzard leftovers behind our window, whatever opened it (Options, the game menu, the compartment, the
-- shortcut, the minimap button): the last tooltip (GameTooltip, or Options' SettingsTooltip) unless one of ours owns
-- it, and SmartNavigation's gamepad focus arrow. All go transparent while the addon is open (SetAlpha only, saved and
-- given back): a Hide from here would run GameTooltip's OnHide, which writes its fields, under the addon's taint. The
-- arrow's alpha is set on its Pointer child: SmartNavigation keeps its own alpha as state (IsCursorHidden reads it).
local hidden = {}

local function fade(region)
	if not region or hidden[region] then return end
	hidden[region] = region:GetAlpha()
	region:SetAlpha(0)
end

local function hideLeftovers()
	for _, tooltip in ipairs({ GameTooltip, SettingsTooltip }) do
		local owner = tooltip:IsShown() and tooltip:GetOwner()
		local name = owner and owner.GetName and owner:GetName()
		if tooltip:IsShown() and not (name and name:find("^ForeverControllerTweaks")) then fade(tooltip) end
	end
	fade(SmartNavigation and SmartNavigation.Pointer)
end

local function restoreLeftovers()
	for region, alpha in pairs(hidden) do region:SetAlpha(alpha) end
	hidden = {}
end

-- Closing gives everything back before the panel state changes, so nothing stays hidden if a listener errors.
local setPanelOpen = ns.SetPanelOpen
function ns.SetPanelOpen(open)
	local was = ns.panelOpen
	if not open and was then restoreLeftovers() end
	if not open and shield:IsShown() then
		shield:Hide()
		SettingsPanel:SetAlpha(1)
	end
	setPanelOpen(open)
	if open and not was then
		hideLeftovers()
		laterCheckInteract()
	end
end

-- Our own minimap button, no library: the native tracking-button look with the addon's icon, on the minimap ring at
-- options.minimapAngle (drag it round); a click opens the addon. options.minimapIcon = false hides it (Modifiers > More).
local MINIMAP_ANGLE, MINIMAP_OUTSIDE = 225, 10
local atan2 = math.atan2 or math.atan
local minimapButton

local function placeMinimapButton()
	local angle = math.rad(ns.db.options.minimapAngle or MINIMAP_ANGLE)
	local radius = Minimap:GetWidth() / 2 + MINIMAP_OUTSIDE
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragMinimapButton()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	ns.db.options.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
	placeMinimapButton()
end

local function buildMinimapButton()
	local button = CreateFrame("Button", "ForeverControllerTweaksMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(UI.ART .. "icon.tga")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function() ns.TogglePanel() end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragMinimapButton) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		UI.Tooltip(self, { title = UI.L.NOTICE_TITLE, lines = { UI.L.COMPARTMENT_TIP, string.format(UI.L.MINIMAP_SHORTCUT, UI.ToggleKeyText()) } })
	end)
	button:SetScript("OnLeave", function(self) UI.HideTooltip(self) end)
	minimapButton = button
end

function UI.UpdateMinimapButton()
	if not (Minimap and ns.db) then return end
	if not minimapButton then buildMinimapButton() end
	placeMinimapButton()
	minimapButton:SetShown(ns.db.options.minimapIcon ~= false)
end

function UI.ToggleMinimapButton()
	ns.db.options.minimapIcon = ns.db.options.minimapIcon == false
	UI.UpdateMinimapButton()
end

ns.On("PLAYER_LOGIN", UI.UpdateMinimapButton)

local function registerSettings()
	local L = UI.L
	local category, layout = Settings.RegisterVerticalLayoutCategory(L.SETTINGS_TITLE)
	layout:AddInitializer(CreateSettingsButtonInitializer(L.SETTINGS_OPEN_LABEL, L.SETTINGS_OPEN, nextFrame(UI.Bindings.Open), string.format(L.SETTINGS_OPEN_TIP, UI.ToggleKeyText(nil, true)), true))
	layout:AddInitializer(CreateSettingsButtonInitializer(L.SETTINGS_SETUP_LABEL, L.SETTINGS_SETUP, nextFrame(UI.Onboarding.Start), L.SETTINGS_SETUP_TIP, true))
	Settings.RegisterAddOnCategory(category)
end

local function addSettingsPage()
	if settingsDone or InCombatLockdown() then return end

	settingsDone = true
	local ok, err = pcall(function()
		if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory and CreateSettingsButtonInitializer) then error("Settings API missing") end
		registerSettings()
	end)
	if not ok then ns.log(string.format(UI.L.SETTINGS_FAILED, tostring(err))) end
end

ns.On("PLAYER_LOGIN", addSettingsPage)
ns.On("PLAYER_REGEN_ENABLED", addSettingsPage)

-- A small native message window: text and one or two buttons (A presses the focused one, B the last).
-- buttons = { { label, fn }, ... }; it is "notice"-class, so it opens while the Gamepad UI is off too.
local message, messageButtons

function UI.ShowMessage(text, buttons)
	if not message then
		message = UI.NewWindow(440, 150)
		message.notice = true
		message:SetTitle(UI.L.NOTICE_TITLE)
		message.text = UI.Text(message, "GameFontHighlight", 24, 44, "", 392)
		message.text:SetSpacing(3)
		messageButtons = {}
		for i = 1, 2 do
			local button = CreateFrame("Button", nil, message, "SharedButtonSmallTemplate")
			button:SetSize(138, 28)
			button:SetScript("OnEnter", nil)
			button:SetScript("OnLeave", nil)
			messageButtons[i] = button
		end
		message.OnBack = function() UI.CloseAll() end
	end
	message.text:SetText(text)
	local nodes = {}
	for i, button in ipairs(messageButtons) do
		local spec = buttons[i]
		button:SetShown(spec ~= nil)
		if spec then
			local function press()
				UI.CloseAll()
				if spec[2] then spec[2]() end
			end
			button:SetText(spec[1])
			button:SetScript("OnClick", press)
			button:ClearAllPoints()
			if #buttons == 1 then button:SetPoint("BOTTOM", message, "BOTTOM", 0, 20) else button:SetPoint("BOTTOM", message, "BOTTOM", (i - 1.5) * 148, 20) end
			nodes[i] = UI.Node(message, button, press)
		end
	end
	message.OnRefresh = function()
		message:SetNodes(nodes)
		message:SetPrompts({ { "PAD1", UI.L.SELECT }, { "PAD2", UI.L.CLOSE } })
	end
	UI.Show(message)
end

-- Shown instead of the addon's windows while the Gamepad UI is off.
function UI.ShowNotice() UI.ShowMessage(UI.L.NOTICE_TEXT, { { UI.L.CLOSE } }) end

-- After combat: offer to resume what combat closed (a setup step, the guided custom layout).
function UI.OfferResume(resume) UI.ShowMessage(resume.text, { { UI.L.RESUME, resume.fn }, { UI.L.NOT_NOW } }) end

-- /fct debug glyphs: every visible glyph of ours with its key, atlas, size and frame level.
local coreDebug = ns.commands.debug
function ns.commands.debug(args)
	if (args[1] or ""):lower() ~= "glyphs" then return coreDebug(args) end

	local n = 0
	for glyph in pairs(UI.glyphs) do
		if glyph:IsVisible() then
			n = n + 1
			local w, h = glyph:GetSize()
			ns.log(string.format("glyph %s: atlas %s, icon shown %s, %dx%d, level %d", tostring(glyph.key), tostring(glyph.atlas), tostring(glyph.icon:IsShown()), w, h, glyph:GetFrameLevel()))
		end
	end
	ns.log(n .. " visible glyphs")
end
