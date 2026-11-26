-- Forever Controller Tweaks panel: the window base. One native window shown at a time; it owns the pad while shown
-- (EnableGamePadButton, set once at creation) and runs its own 2D focus with SmartNavigation's cursor art, pickers
-- included. Navigation is D-pad only (a held direction repeats), as on Forever's own screens; the sticks are not
-- read. Nothing here calls into Blizzard's Menu, SmartNavigation or binding stack. Opening and closing only happen
-- out of combat.
local _, ns = ...
local UI = ns.UI

local DIRS = { PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 } }
local REPEAT_DELAY, REPEAT_EVERY = 0.38, 0.11
local HOLD_POLL = 0.05
-- L1/R1 switch the side tabs on a tap, so holding one (lighting it on the drawing, the guide's Try it) does not.
local TAB_TAP = 0.35
local TAB_KEYS = { PADLSHOULDER = -1, PADRSHOULDER = 1, PADLTRIGGER = -1, PADRTRIGGER = 1 }
local PAGE_KEYS = { PADLTRIGGER = true, PADRTRIGGER = true }

local current
local Window = {}

local function closeKeys()
	local keys = { PADFORWARD = true, PADSOCIAL = true }
	for key in pairs(UI.Toggle().keys) do keys[key] = true end
	return keys
end

function Window:SetTitle(text) self.NineSlice.Text:SetText(text) end

-- A value row (a node with onDir: a slider or a number) changes only while A grabs it. Its hints say so: A Change;
-- while grabbed, the D-pad changes it and A or B is Done. A row's own D-pad labels replace the generic one then. A
-- choice row (choice = true: its select opens a dropdown's list) is never grabbed; its hint is A Change too.
local function valueHints(list, editing)
	local L, sides, rest = UI.L, {}, {}
	for _, entry in ipairs(list or {}) do
		local key = entry[1]
		if key == "PADDLEFT" or key == "PADDRIGHT" then sides[#sides + 1] = entry
		elseif key ~= "PAD1" and not (editing and key == "PAD2") then rest[#rest + 1] = entry end
	end
	local out = editing and (sides[1] and sides or { { "PADDLEFT", L.CHANGE, "PADDRIGHT" } }) or {}
	out[#out + 1] = { "PAD1", editing and L.DONE or L.CHANGE }
	if editing then out[#out + 1] = { "PAD2", L.DONE } end
	for _, entry in ipairs(rest) do out[#out + 1] = entry end
	return out
end

local function valueTip(tip, editing)
	local copy = {}
	for k, v in pairs(tip) do copy[k] = v end
	copy.actions = valueHints(tip.actions, editing)
	return copy
end

-- A dialog or modal sets its own prompts on the window while the row stays focused under it.
function Window:SetPrompts(list)
	local focus = self.focus
	local value = focus and (focus.onDir or focus.choice) and not self.modal and not UI.DialogShown()
	self.footer:Set(value and valueHints(list, self.editing) or list)
end

-- nodes: { region, select = fn, cursorX = n, onFocus = fn(focused), onDir = fn(dx), choice = true }; refreshes rebuild
-- the list, so the focus stays on the same region when it is still listed.
function Window:SetNodes(nodes)
	self.nodes = nodes
	local region, keep = self.focus and self.focus.region, nil
	for _, node in ipairs(nodes) do
		if node.region == region then keep = node end
	end
	if keep then self.focus = nil end
	if self.editing then self.editing = keep and keep.onDir and keep or nil end
	self:Focus(keep or nodes[1])
end

-- Native focus: the gold chevron at the row's left edge, a subtle row wash (unless the row draws its own focus
-- state), and the row's tooltip with its button actions beside it.
-- A grabbed row also takes the window's wash over its own, a stronger wash.
function Window:Focus(node)
	local old = self.focus
	self.focus = node
	if self.editing ~= node then self.editing = nil end
	if old and old ~= node and old.onFocus then old.onFocus(false) end
	if node and node.onFocus then node.onFocus(true) end

	local region, editing = node and node.region, self.editing
	self:Grab(editing and (region.control or region))
	local washed = region and (editing or not node.onFocus)
	self.wash:ClearAllPoints()
	self.wash:SetShown(washed)
	if washed then
		self.wash:SetPoint("TOPLEFT", region, "TOPLEFT", -10, 0)
		self.wash:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 5, 0)
	end
	UI.HideTooltip()
	if UI.DialogShown() then return end
	if node and node.tip then
		local tip = type(node.tip) == "function" and node.tip() or node.tip
		UI.Tooltip(node.tipRegion or region, (node.onDir or node.choice) and valueTip(tip, editing) or tip)
	end
	self.cursor:Attach(node and (node.cursorRegion or region), node and node.cursorX)
	if self.OnFocusChanged then self:OnFocusChanged(node) end
end

-- The grabbed control lights itself (SetEditing: its native hover art) until it is let go.
function Window:Grab(control)
	if control and not control.SetEditing then control = nil end
	if self.grabbed == control then return end
	if self.grabbed then self.grabbed:SetEditing(false) end
	self.grabbed = control
	if control then control:SetEditing(true) end
end

-- A grabs the focused value row (a node with onDir), so left/right change it; Edit(false) lets go.
function Window:Edit(on)
	local focus = self.focus
	self.editing = on and focus and focus.onDir and focus or nil
	self:Focus(focus)
end

-- Picks the nearest visible node in the direction; off-axis distance counts double. While a row is grabbed,
-- left/right change it and up/down let go and move.
-- repeats: how many times a held direction has repeated (nil for a fresh press).
local OFF_BAND = 10000

-- Centre and height in screen units: a scaled frame (the Rings preview's wheel) reports its own units.
local function place(region)
	local x, y = region:GetCenter()
	if not x then return end
	local scale = region:GetEffectiveScale()
	return x * scale, y * scale, region:GetHeight() * scale
end

function Window:Move(dx, dy, repeats)
	if self.modal then return self.modal:Move(dx, dy, repeats) end
	local editing = self.editing
	if editing and dx ~= 0 then return editing.onDir(dx) end
	if editing then self:Edit(false) end
	local from = self.focus and self.focus.region
	if not from then return self:Focus(self.nodes and self.nodes[1]) end

	local fx, fy, fh = place(from)
	if not fx then return end
	local best, bestScore
	for _, node in ipairs(self.nodes or {}) do
		local region = node.region
		local x, y, h = place(region)
		if node ~= self.focus and x and region:IsVisible() then
			local along = (x - fx) * dx + (y - fy) * dy
			local across = math.abs((x - fx) * dy) + math.abs((y - fy) * dx)
			if along > 1 then
				local score = along + across * 2
				-- Left/right stays in the focused element's row band when anything there is level with it, and then prefers
				-- what lies more sideways than up or down (the Rings list, not the buttons under the settings).
				if dx ~= 0 and math.abs(y - fy) >= (fh + h) / 2 then score = score + OFF_BAND end
				if dx ~= 0 and across > along then score = score + OFF_BAND end
				if not bestScore or score < bestScore then best, bestScore = node, score end
			end
		end
	end
	if best then return self:Focus(best) end
end

function Window:Select()
	local node = self.focus
	if node and node.onDir then return self:Edit(self.editing ~= node) end
	if node and node.select then node.select() end
end

-- An open modal (the action picker) owns the input; the window redraws when it closes.
function Window:Refresh()
	if self.modal then return end
	if self.OnRefresh then self:OnRefresh() end
end

function Window:StartRepeat(dir)
	self.repeatDir, self.repeatAt, self.repeatCount = dir, GetTime() + REPEAT_DELAY, 0
	self:Move(dir[1], dir[2])
end

function Window:Pad(key)
	if UI.DialogShown() then
		self.repeatKey, self.repeatDir = nil, nil
		return UI.Dialog():OnPad(key)
	end
	if self.modal then return self.modal:OnPad(key) end
	-- A grabbed row lets go on A or B (keeping its value); any other button but the D-pad lets go, then does its job.
	if self.editing and (key == "PAD1" or key == "PAD2") then return self:Edit(false) end
	if self.editing and not DIRS[key] then self:Edit(false) end
	-- A focused element may own extra keys.
	if self.focus and self.focus.onKey and self.focus.onKey(key) then return end
	if self.OnKey and self:OnKey(key) then return end

	local dir = DIRS[key]
	if dir then
		self.repeatKey = key
		return self:StartRepeat(dir)
	end
	if key == "PAD1" then return self:Select() end
	if key == "PAD2" then
		if self.OnBack then return self:OnBack() end
		return UI.CloseAll()
	end
	if closeKeys()[key] then return UI.CloseAll() end
end

local function tabsFree(self) return self.tabs and not self.tabsLocked and not self.modal and not UI.DialogShown() end

local function onPadDown(self, key)
	if InCombatLockdown() then return end

	self:SetPropagateKeyboardInput(false)
	-- Controller setup reads the pad raw: presses go nowhere (not to the game, not to navigation).
	if self.noPad then return end
	if self.tap then self.tap.spoiled = true end
	-- No tab tap while another shoulder, trigger or paddle is held: that is a hold test (e.g. L2 + R1).
	if TAB_KEYS[key] and tabsFree(self) and #UI.HeldButtons() <= 1 then self.tap = { key = key, at = GetTime() } end
	self:Pad(key)
end

local function onPadUp(self, key)
	if key == self.repeatKey then self.repeatKey, self.repeatDir = nil, nil end
	local tap = self.tap
	if not (tap and tap.key == key) then return end
	self.tap = nil
	if tap.spoiled or GetTime() - tap.at > TAB_TAP or not tabsFree(self) then return end
	-- L1/R1 step the side tabs; L2/R2 step a window's pages (Bindings).
	if PAGE_KEYS[key] then
		if self.OnPageTap then self:OnPageTap(TAB_KEYS[key]) end
		return
	end
	self.tabs:Step(TAB_KEYS[key])
end

-- The keyboard keeps only navigation keys (arrows, Enter/Space as A, Escape as B); everything else passes on.
local KEY_AS_PAD = { UP = "PADDUP", DOWN = "PADDDOWN", LEFT = "PADDLEFT", RIGHT = "PADDRIGHT", ENTER = "PAD1", SPACE = "PAD1" }

local function onKeyDown(self, key)
	if InCombatLockdown() then return end
	if self.OnKeyDownOverride then
		self:SetPropagateKeyboardInput(not self:OnKeyDownOverride(key))
		return
	end

	local pad = KEY_AS_PAD[key]
	local nav = pad or key == "ESCAPE"
	self:SetPropagateKeyboardInput(not nav)
	if pad then
		self:Pad(pad)
		self.repeatKey, self.repeatDir = nil, nil
		return
	end
	if not nav then return end

	if self.modal then return self.modal:Close() end
	if UI.DialogShown() then return UI.Dialog():OnPad("PAD2") end
	if self.editing then return self:Edit(false) end
	if self.OnBack then return self:OnBack() end
	UI.CloseAll()
end

local function onUpdate(self, elapsed)
	local now = GetTime()
	if self.repeatDir and now >= self.repeatAt then
		self.repeatAt = now + REPEAT_EVERY
		self.repeatCount = (self.repeatCount or 0) + 1
		self:Move(self.repeatDir[1], self.repeatDir[2], self.repeatCount)
	end

	if not self.OnHoldTick then return end
	self.holdElapsed = (self.holdElapsed or 0) + elapsed
	if self.holdElapsed < HOLD_POLL then return end
	self.holdElapsed = 0
	self:OnHoldTick()
end

local function onShow(self) self.glow:Show() end

local function onHide(self)
	if self.closing then return end
	self.glow:Hide()
	UI.HideTooltip()
	self.repeatKey, self.repeatDir, self.tap, self.editing = nil, nil, nil, nil
	self:Grab(nil)
	if self.modal then self.modal:Close() end
	if UI.DialogShown() and UI.Dialog().owner == self then UI.Dialog():Close() end
	if self.OnClosed then self:OnClosed() end
	if current == self then current = nil end
	if not current then ns.SetPanelOpen(false) end
	-- Hidden with UIParent (Alt+Z, a cinematic): the window is still shown and would take pad input when UIParent
	-- comes back, with nothing current. Hide it for real.
	if self:IsShown() then
		self.closing = true
		self:Hide()
		self.closing = nil
	end
end

local BODY_ATLAS, BODY_ALPHA, BODY_GREY = "bank-frame-background", 0.5, 0.6

-- A w x h window, centred on screen.
function UI.NewWindow(w, h)
	local window = Mixin(CreateFrame("Frame", nil, UIParent, "ForeverControllerTweaksWindowTemplate"), Window)
	window:SetSize(w, h)
	window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	-- Above the Settings panel (HIGH) and the game menu (DIALOG), which may stay open under our window.
	window:SetFrameStrata("FULLSCREEN_DIALOG")
	window.ClosePanelButton:SetScript("OnClick", function() UI.CloseAll() end)
	-- The flat background's colour is translucent (PANEL_BACKGROUND_COLOR); a black underlay in our own Bg makes the
	-- window opaque over the world and the quest tracker, the native tint unchanged.
	local underlay = (window.Bg or window):CreateTexture(nil, "BACKGROUND", nil, -8)
	underlay:SetColorTexture(0, 0, 0, 1)
	underlay:SetAllPoints()
	window.underlay = underlay
	-- The body texture: the native Bank frame's background (BankFrameTemplates.xml, bank-frame-background), tiled at
	-- 256 x 256 as the Bank frame does, so it stays crisp at any window size (the Character window's body atlas is
	-- drawn for its small inset and blurs when stretched this large). It sits in our Bg frame at sublevel 1: above the
	-- template's flat fill (sublevel 0) and the underlay, below every content frame.
	local body = (window.Bg or window):CreateTexture(nil, "BACKGROUND", nil, 1)
	body:SetAtlas(BODY_ATLAS)
	body:SetHorizTile(true)
	body:SetVertTile(true)
	body:SetAllPoints()
	body:SetAlpha(BODY_ALPHA)
	body:SetDesaturation(BODY_GREY)
	window.body = body
	window:EnableGamePadButton(true)
	window:EnableKeyboard(true)
	window:SetScript("OnGamePadButtonDown", onPadDown)
	window:SetScript("OnGamePadButtonUp", onPadUp)
	window:SetScript("OnKeyDown", onKeyDown)
	window:SetScript("OnUpdate", onUpdate)
	window:SetScript("OnShow", onShow)
	window:SetScript("OnHide", onHide)
	window.footer = UI.Footer(window)
	window.cursor = UI.Cursor(window)
	window.glow = UI.Glow(window, window.NineSlice, "gamepad-uiframemetal-focus", -10, 14, 14, -14)
	window.wash = window:CreateTexture(nil, "BACKGROUND", nil, 7)
	window.wash:SetColorTexture(1, 1, 1, 0.1)
	window.wash:Hide()
	return window
end

-- PortraitFrameTemplate's round portrait on one of our windows (SharedUIPanelTemplates.xml, NineSliceLayouts.lua
-- PortraitFrameTemplate): the window's own border takes the portrait layout (its corner is
-- UI-Frame-PortraitMetal-CornerTopLeft, the gold ring), and under it a 62 x 62 texture at -5, 7 masked round by
-- Interface\CharacterFrame\TempPortraitAlphaMask, inset 2, 0, -2, 4. The title moves right of it as the template's
-- TitleContainer does (58 from the left, 24 from the right). This client has no SetPortraitToTexture, so the mask does
-- the rounding. The ring reaches about 57 in and 55 down: UI.PORTRAIT_CLEAR is where header text starts beside it.
local PORTRAIT_SIZE, PORTRAIT_X, PORTRAIT_Y, TITLE_LEFT, TITLE_RIGHT, TITLE_Y = 62, -5, 7, 58, -24, -5
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
UI.PORTRAIT_CLEAR = 64

function UI.AddPortrait(window, file)
	local nine, close = window.NineSlice, window.ClosePanelButton
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then NineSliceUtil.ApplyLayoutByName(nine, "PortraitFrameTemplate") end
	local holder = CreateFrame("Frame", nil, window)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT")
	holder:SetFrameLevel(window:GetFrameLevel() + 1)
	-- The ring draws over the portrait's edge; the close button stays above the border it sits on.
	nine:SetFrameLevel(window:GetFrameLevel() + 2)
	if close:GetFrameLevel() <= nine:GetFrameLevel() then close:SetFrameLevel(nine:GetFrameLevel() + 1) end
	local portrait = holder:CreateTexture(nil, "OVERLAY")
	portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait:SetPoint("TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
	portrait:SetTexture(file)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, 0)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 4)
	portrait:AddMaskTexture(mask)
	local title = nine.Text
	title:ClearAllPoints()
	title:SetPoint("TOP", 0, TITLE_Y)
	title:SetPoint("RIGHT", TITLE_RIGHT, 0)
	title:SetPoint("LEFT", TITLE_LEFT, 0)
	window.portrait, window.portraitMask = portrait, mask
	return portrait
end

-- A focus node for a frame: hover focuses it, click selects it.
function UI.Node(window, region, select, extra)
	local node = extra or {}
	node.region, node.select = region, select
	if region.HookScript and not region.tweaksHooked then
		region.tweaksHooked = true
		region:HookScript("OnEnter", function() if window:IsShown() and window.nodes then for _, n in ipairs(window.nodes) do if n.region == region then return window:Focus(n) end end end end)
	end
	return node
end

-- Shows window (hiding our other window in place, the way Forever swaps its own panels).
-- Fit to screen: never larger than the screen minus the side tabs, the footer and a margin (Steam Deck 1280x800,
-- 4:3, large UI scales).
-- The window is centred, so each half must fit: half the window plus the side tabs (right) or the footer (below)
-- and a margin.
local FIT_MARGIN, TABS_WIDTH, FOOTER_HEIGHT = 8, 50, 48

function UI.Fit(window)
	local halfWidth = window:GetWidth() / 2 + (window.tabs and TABS_WIDTH or 0) + FIT_MARGIN
	local halfHeight = window:GetHeight() / 2 + FOOTER_HEIGHT + FIT_MARGIN
	window:SetScale(math.min(1, UIParent:GetWidth() / 2 / halfWidth, UIParent:GetHeight() / 2 / halfHeight))
end

-- The addon works only with the Gamepad UI: any other window asked for while it is off shows the notice instead.
function UI.Show(window)
	if InCombatLockdown() then return ns.log(UI.L.COMBAT) end
	if not window.notice and not ns.Active() then return UI.ShowNotice() end

	local old = current
	current = window
	ns.SetPanelOpen(true)
	if old and old ~= window then old:Hide() end
	-- A window opens on its first element, as native windows do.
	if not window:IsShown() then window.focus = nil end
	UI.Fit(window)
	window:Show()
	window:Refresh()
end

function UI.Current() return current end

function UI.CloseAll()
	local open = current
	current = nil
	if open then open:Hide() end
	ns.SetPanelOpen(false)
end

-- Combat closes every window of ours, picker and dialog in the same handler (Core fires FCT_COMBAT_START
-- synchronously at the start of PLAYER_REGEN_DISABLED, before its own apply). Windows that hold progress store it
-- in UI.resume while UI.combatClosing is set; after combat the addon offers to resume it.
local function combatClose()
	if not current then return end
	UI.combatClosing = true
	UI.CloseAll()
	UI.combatClosing = false
end

ns.On("FCT_COMBAT_START", combatClose)

local function refit()
	if current and current:IsShown() then UI.Fit(current) end
end
ns.On("UI_SCALE_CHANGED", refit)
ns.On("DISPLAY_SIZE_CHANGED", refit)
ns.On("PLAYER_REGEN_DISABLED", combatClose)
ns.On("PLAYER_REGEN_ENABLED", function()
	local resume = UI.resume
	if not resume then return end
	UI.resume = nil
	C_Timer.After(0.5, function()
		if not InCombatLockdown() and not current then UI.OfferResume(resume) end
	end)
end)

-- A click anywhere lets go of a grabbed row, except on the footer, whose prompts are the buttons (A Done).
ns.On("GLOBAL_MOUSE_DOWN", function()
	if current and current.editing and not current.footer:IsMouseOver() then current:Edit(false) end
end)

ns.On("FCT_ACTIVE_CHANGED", function(active)
	if not active and current and not current.notice then UI.CloseAll() end
end)

-- One redraw of a window on the next frame, however many changes asked for it in this one (a preset or a Learn run
-- changes many slots at once).
local soon = {}
function UI.RefreshSoon(window)
	if soon[window] then return end
	soon[window] = true
	C_Timer.After(0, function()
		soon[window] = nil
		if window:IsShown() then window:Refresh() end
	end)
end

-- Layout edits (here, from /fct or from Learn) and a ring's new last pick (its live icon) redraw the open window.
local function refreshCurrent() if current and current:IsShown() then UI.RefreshSoon(current) end end
ns.On("FCT_LAYOUT_CHANGED", refreshCurrent)
ns.On("FCT_RING_LAST", refreshCurrent)

