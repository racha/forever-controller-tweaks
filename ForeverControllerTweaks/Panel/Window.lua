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

function Window:SetPrompts(list) self.footer:Set(list) end

-- nodes: { region, select = fn, cursorX = n, onFocus = fn(focused) }; refreshes rebuild the list, so the focus
-- stays on the same region when it is still listed.
function Window:SetNodes(nodes)
	self.nodes = nodes
	local region, keep = self.focus and self.focus.region, nil
	for _, node in ipairs(nodes) do
		if node.region == region then keep = node end
	end
	if keep then self.focus = nil end
	self:Focus(keep or nodes[1])
end

-- Native focus: the gold chevron at the row's left edge, a subtle row wash (unless the row draws its own focus
-- state), and the row's tooltip with its button actions beside it.
function Window:Focus(node)
	local old = self.focus
	self.focus = node
	if old and old ~= node and old.onFocus then old.onFocus(false) end
	if node and node.onFocus then node.onFocus(true) end

	local region = node and node.region
	self.wash:ClearAllPoints()
	self.wash:SetShown(region and not node.onFocus)
	if region and not node.onFocus then
		self.wash:SetPoint("TOPLEFT", region, "TOPLEFT", -10, 0)
		self.wash:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 5, 0)
	end
	UI.HideTooltip()
	if UI.DialogShown() then return end
	if node and node.tip then UI.Tooltip(node.tipRegion or region, type(node.tip) == "function" and node.tip() or node.tip) end
	self.cursor:Attach(node and (node.cursorRegion or region), node and node.cursorX)
	if self.OnFocusChanged then self:OnFocusChanged(node) end
end

-- Picks the nearest visible node in the direction; off-axis distance counts double.
-- repeats: how many times a held direction has repeated (nil for a fresh press).
local OFF_BAND = 10000

function Window:Move(dx, dy, repeats)
	if self.modal then return self.modal:Move(dx, dy, repeats) end
	local from = self.focus and self.focus.region
	if not from then return self:Focus(self.nodes and self.nodes[1]) end

	local fx, fy = from:GetCenter()
	if not fx then return end
	local best, bestScore
	for _, node in ipairs(self.nodes or {}) do
		local region = node.region
		local x, y = region:GetCenter()
		-- noSide nodes (Touch's settings, where left/right change a value) are reached with up/down only.
		if node ~= self.focus and x and region:IsVisible() and not (dx ~= 0 and node.noSide) then
			local along = (x - fx) * dx + (y - fy) * dy
			local across = math.abs((x - fx) * dy) + math.abs((y - fy) * dx)
			if along > 1 then
				local score = along + across * 2
				-- Left/right stays in the focused element's row band when anything there is level with it.
				if dx ~= 0 and math.abs(y - fy) >= (from:GetHeight() + region:GetHeight()) / 2 then score = score + OFF_BAND end
				if not bestScore or score < bestScore then best, bestScore = node, score end
			end
		end
	end
	if best then return self:Focus(best) end
end

function Window:Select()
	local node = self.focus
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
	-- A focused element may own extra keys.
	if self.focus and self.focus.onKey and self.focus.onKey(key) then return end
	if self.OnKey and self:OnKey(key) then return end

	-- A focused control may use left/right itself (the page selector, a setting); false hands the press back to
	-- focus movement (a setting at its end).
	if (key == "PADDLEFT" or key == "PADDRIGHT") and self.focus and self.focus.onDir and self.focus.onDir(key == "PADDLEFT" and -1 or 1) ~= false then return end
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
	self.repeatKey, self.repeatDir, self.tap = nil, nil, nil
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

ns.On("FCT_ACTIVE_CHANGED", function(active)
	if not active and current and not current.notice then UI.CloseAll() end
end)

-- Layout edits (here, from /fct or from Learn) redraw the open window.
ns.On("FCT_LAYOUT_CHANGED", function()
	if current and current:IsShown() then current:Refresh() end
end)
