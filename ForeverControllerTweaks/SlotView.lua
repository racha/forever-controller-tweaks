-- Forever Controller Tweaks slot view: a gamepad crossbar slot drawn on our own frame from an action slot, with the native
-- slot's art, states and press. The glyph overlay's routed mirrors (Glyphs.lua) and the touch bars draw with it.
--
-- Art and geometry are the native gamepad slot's: atlases from Blizzard_GamepadActionBars/ActionBarButton.lua:92-113
-- (SetShapeToCircle / SetShapeToSquare, 235-310), anchors from ActionButtonTemplate.xml and UpdateButtonArtAnchoring
-- (504-531), shadow and checked distances, sizes and press from ActionBarStyles.lua. States are read with the native
-- slot's own calls on the native slot's events (ActionBarActionButtonMixin:OnEvent and its watcher frames). Nothing
-- here writes a Blizzard object or registers with a Blizzard manager; the proc glow is our own
-- ActionButtonSpellAlertTemplate frame, never the alert manager.
--
--   local view = ns.SlotView.New(parent)   -- a Frame, mouse off; the caller sizes and anchors it
--   view:SetShape("circle" | "square")     -- native slot art and mask for that shape
--   view:SetSlot(slot | nil, fallbackIcon) -- draws every state of that action slot; nil or empty: the fallback icon
--   view:SetPressed(pressed, byMouse)      -- the native press look; returns the body's y offset and size step
--
-- Everything is drawn on view.body, which the press moves inside the view. The regions are public (view.icon, flash,
-- border, checked, shadow, mask, backdrop, equipped, cooldown, loc, charge, text, count, range, alert) for a caller
-- that draws a non-slot action (Glyphs' face-action mirrors). view.rangeState is "normal" / "disabled" / nil (no range
-- event yet) for a prompt drawn over the view, as RefreshRange sets the native prompt.

local _, ns = ...
local SlotView = {}
ns.SlotView = SlotView

local style = GamepadActionBarStyleUtil or {}
local PRESS_DY = style.PUSHED_BUTTON_ANCHOR_OFFSET and style.PUSHED_BUTTON_ANCHOR_OFFSET.y or -2
local PRESS_DS = style.PUSHED_BUTTON_SIZE_OFFSET or -4
SlotView.PRESS_DY, SlotView.PRESS_DS = PRESS_DY, PRESS_DS

local CLAMP = "CLAMPTOBLACKADDITIVE"
-- Mask inset (template CircleMask/SquareMask), drop shadow distance (collapsed style), checked distance (set on the
-- first expand and never reset, so every bar that has been focused shows it).
local MASK_INSET, SHADOW_DISTANCE, CHECKED_DISTANCE = 3, 4, 4
local FLASH_ATLAS, LOC_EDGE = "UI-HUD-ActionBar-IconFrame-Flash", "Interface\\Cooldown\\UI-HUD-ActionBar-LoC"
local SHAPES = {
	circle = {
		normal = "gamepad-actionbar-circleslot-border-normal", pushed = "gamepad-actionbar-circleslot-border-pressed",
		checked = "gamepad-actionbar-circleslot-border-selected", border = "gamepad-actionbar-circleslot-iconframe-border",
		shadow = "gamepad-actionbar-circleslot-dropshadow", mask = "CircleMask", swipe = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
		collapsed = style.CIRCULAR_BUTTON_COLLAPSED_SIZE or 30,
	},
	square = {
		normal = "gamepad-actionbar-squareslot-border-normal", pushed = "gamepad-actionbar-squareslot-border-pressed",
		checked = "gamepad-actionbar-squareslot-border-selected", border = "UI-HUD-ActionBar-IconFrame-Border",
		shadow = "gamepad-actionbar-squareslot-dropshadow", mask = "SquareMask", swipe = "Interface\\Buttons\\WHITE8X8",
		collapsed = style.SQUARE_BUTTON_COLLAPSED_SIZE or 32,
	},
}

-- What each event refreshes, as ActionBarActionButtonMixin:OnEvent (975-1107) and its watcher frames do. Item counts
-- also follow BAG_UPDATE_DELAYED, a cheap backstop for ACTIONBAR_SLOT_CHANGED.
local LOOK_EVENTS = {
	ACTIONBAR_SLOT_CHANGED = "all", PLAYER_ENTERING_WORLD = "all", UPDATE_SHAPESHIFT_FORM = "all", SPELL_UPDATE_ICON = "all",
	ACTIONBAR_UPDATE_STATE = "state", TRADE_SKILL_SHOW = "state", TRADE_SKILL_CLOSE = "state", COMPANION_UPDATE = "state",
	UNIT_ENTERED_VEHICLE = "state", UNIT_EXITED_VEHICLE = "state",
	ACTIONBAR_UPDATE_COOLDOWN = "cooldown", LOSS_OF_CONTROL_ADDED = "cooldown", LOSS_OF_CONTROL_UPDATE = "cooldown",
	ACTION_USABLE_CHANGED = "usable", PLAYER_MOUNT_DISPLAY_CHANGED = "usable",
	SPELL_UPDATE_CHARGES = "count", BAG_UPDATE_DELAYED = "count",
	PLAYER_ENTER_COMBAT = "flash", PLAYER_LEAVE_COMBAT = "flash", START_AUTOREPEAT_SPELL = "flash", STOP_AUTOREPEAT_SPELL = "flash",
	SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = "glow", SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = "glow",
}
local KINDS = { "cooldown", "state", "usable", "count", "flash", "glow", "range" }

-- Every view; each enabled slot's last range event.
local views, rangeOf, rangeOn = {}, {}, {}
local driver, failed

local function setAtlas(texture, atlas)
	if texture.psAtlas == atlas then return end

	texture.psAtlas = atlas
	texture:SetAtlas(atlas)
end

-- d > 0 insets the region from the body's edges, d < 0 outsets it.
local function inset(region, body, d)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", body, "TOPLEFT", d, -d)
	region:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -d, d)
end

local function setDuration(cooldown, duration)
	if duration then cooldown:SetCooldownFromDurationObject(duration, true) else cooldown:Clear() end
end

local function blink(view)
	view.flash:SetShown(view.flashing and math.floor(GetTime() / (ATTACK_BUTTON_FLASH_TIME or 0.4)) % 2 == 0)
end

-- The calls of a native slot. Cooldowns are duration objects: in combat their values are secret, and SetCooldown
-- refuses secrets from addon code (the native slot is Blizzard code and passes them through).
local LOOK = {}
function LOOK.cooldown(view, slot)
	setDuration(view.cooldown, C_ActionBar.GetActionCooldownDuration(slot))
	setDuration(view.loc, C_ActionBar.GetActionLossOfControlCooldownDuration(slot))
	setDuration(view.charge, C_ActionBar.GetActionChargeDuration(slot))
end
function LOOK.state(view, slot)
	view.checked:SetShown((C_ActionBar.IsCurrentAction(slot) or C_ActionBar.IsAutoRepeatAction(slot)) and not C_ActionBar.IsAutoCastPetAction(slot))
end
function LOOK.usable(view, slot)
	local usable, noMana = C_ActionBar.IsUsableAction(slot)
	if usable then view.icon:SetVertexColor(1, 1, 1) elseif noMana then view.icon:SetVertexColor(0.5, 0.5, 1) else view.icon:SetVertexColor(0.4, 0.4, 0.4) end
end
-- The display count may be secret in combat; FontString:SetText takes it as is.
function LOOK.count(view, slot) view.count:SetText(C_ActionBar.GetActionDisplayCount(slot)) end
-- Attack and auto-repeat flash on and off every ATTACK_BUTTON_FLASH_TIME, like ActionButton's OnUpdate.
function LOOK.flash(view, slot)
	view.flashing = C_ActionBar.IsAttackAction(slot) and C_ActionBar.IsCurrentAction(slot) or C_ActionBar.IsAutoRepeatAction(slot)
	blink(view)
	if view.flashing and driver then driver:Show() end
end
function LOOK.glow(view, slot)
	local actionType, id = GetActionInfo(slot)
	local show = (actionType == "spell" or actionType == "macro") and id and C_SpellActivationOverlay.IsSpellOverlayed(id)
	local alert = view.alert
	if show and not alert:IsShown() then
		local width, height = view.body:GetSize()
		alert:SetSize(width * 1.4, height * 1.4)
		alert:SetPoint("CENTER", view.body, "CENTER")
		alert:Show()
		alert.ProcStartAnim:Play()
	elseif not show and alert:IsShown() then
		alert:Hide()
		alert.ProcStartAnim:Stop()
	end
end
-- RefreshRange: the dot shows while the action checks range (red out of range), and the prompt goes disabled unless
-- in range. Before the first ACTION_RANGE_CHECK_UPDATE the native slot shows neither.
function LOOK.range(view, slot)
	local state = rangeOf[slot]
	local checks = state and state.checks
	view.range:SetShown(checks)
	if checks then view.range:SetVertexColor((state.inRange and ACTIONBAR_HOTKEY_FONT_COLOR or RED_FONT_COLOR):GetRGB()) end
	view.rangeState = state and (checks and state.inRange and "normal" or "disabled") or nil
end

-- No action: the fallback icon, no states.
local function clear(view)
	view.looked, view.flashing, view.rangeState = nil, nil, nil
	view.icon:SetTexture(view.fallback)
	view.icon:SetVertexColor(1, 1, 1)
	view.cooldown:Clear()
	view.loc:Clear()
	view.charge:Clear()
	view.count:SetText("")
	view.range:Hide()
	view.equipped:Hide()
	view.checked:Hide()
	view.flash:Hide()
	if view.alert:IsShown() then
		view.alert:Hide()
		view.alert.ProcStartAnim:Stop()
	end
end

-- Range checks run only while a view shows a filled slot (native: RegisterFrame on show, UnregisterFrame on hide).
local function syncRange(view)
	local want = view:IsVisible() and view.looked and view.slot or nil
	local old = view.rangeSlot
	if old == want then return end

	view.rangeSlot = want
	if old then
		C_ActionBar.EnableActionRangeCheck(old, false)
		local still
		for _, other in ipairs(views) do still = still or other.rangeSlot == old end
		if not still then rangeOn[old], rangeOf[old] = nil, nil end
	end
	if want then
		rangeOn[want] = true
		C_ActionBar.EnableActionRangeCheck(want, true)
	end
end

-- The whole look, as the native slot's Update. view.generation counts these redraws and restyles, so a caller that
-- caches what it copied onto these regions knows they were rewritten.
local function draw(view)
	view.generation = (view.generation or 0) + 1
	local slot = view.slot
	if not (slot and C_ActionBar.HasAction(slot)) then
		clear(view)
		return syncRange(view)
	end

	view.looked = true
	view.icon:SetTexture(C_ActionBar.GetActionTexture(slot) or view.fallback)
	view.cooldown:SetHideCountdownNumbers(not (C_CVar and C_CVar.GetCVarBool or GetCVarBool)("countdownForCooldowns"))
	view.equipped:SetShown(C_ActionBar.IsEquippedAction(slot))
	for _, kind in ipairs(KINDS) do LOOK[kind](view, slot) end
	syncRange(view)
end

-- The shape's art, from scratch (a caller may have drawn something else on these regions).
local function restyle(view)
	local shape, body = SHAPES[view.shape], view.body
	view.generation = (view.generation or 0) + 1
	view.mask:SetAtlas(shape.mask, false, nil, nil, CLAMP, CLAMP)
	view.maskAtlas = shape.mask
	inset(view.mask, body, MASK_INSET)
	view.shadow:SetAtlas(shape.shadow)
	inset(view.shadow, body, -SHADOW_DISTANCE)
	view.shadow:SetAlpha(1)
	view.shadow:Show()
	local icon = view.icon
	icon:ClearAllPoints()
	icon:SetAllPoints(body)
	icon:SetTexCoord(0, 1, 0, 1)
	icon:SetDesaturated(false)
	icon:SetAlpha(1)
	icon:Show()
	view.flash:SetAtlas(FLASH_ATLAS)
	inset(view.flash, body, 0)
	view.flash:SetAlpha(1)
	view.checked:SetAtlas(shape.checked)
	inset(view.checked, body, -CHECKED_DISTANCE)
	view.checked:SetAlpha(1)
	view.equipped:SetAtlas(shape.border)
	inset(view.equipped, body, 0)
	view.equipped:SetVertexColor(0, 1, 0, 0.5)
	view.border.psAtlas = nil
	view.cooldown:SetSwipeTexture(shape.swipe)
end

local View = {}

function View:SetShape(shape)
	shape = SHAPES[shape] and shape or "circle"
	if self.shape == shape then return end

	self.shape = shape
	restyle(self)
	self:SetPressed(self.pressed, self.byMouse)
	draw(self)
end

function View:SetSlot(slot, fallbackIcon)
	if self.drawn and self.slot == slot and self.fallback == fallbackIcon then return end

	self.drawn, self.slot, self.fallback = true, slot, fallbackIcon
	restyle(self)
	self:SetPressed(self.pressed, self.byMouse)
	draw(self)
end

-- The native press (MainActionBarFrame.lua:690-727 PressActionButton, ActionBarButton.lua:421-433 ApplyPressedStyle,
-- ActionBarStyles.lua:140-148): pushed frame art; a pad press also moves the slot down 2 and, only at the collapsed
-- size or smaller (an expanded slot keeps its size), makes it 4 smaller. A mouse click (a tap) shows the pushed frame
-- only: ApplyPressedStyle returns for mouse clicks (:422).
function View:SetPressed(pressed, byMouse)
	local shape, size = SHAPES[self.shape], self:GetWidth()
	local pad = pressed and not byMouse
	local dy, ds = pad and PRESS_DY or 0, pad and size <= shape.collapsed and PRESS_DS or 0
	self.pressed, self.byMouse = pressed, byMouse
	self.body:SetSize(size + ds, size + ds)
	self.body:SetPoint("CENTER", self, "CENTER", 0, dy)
	setAtlas(self.border, pressed and shape.pushed or shape.normal)
	return dy, ds
end

local function layer(view, drawLayer, subLevel, masked)
	local texture = view.body:CreateTexture(nil, drawLayer, nil, subLevel)
	if masked then texture:AddMaskTexture(view.mask) end
	return texture
end

function SlotView.New(parent)
	local view = CreateFrame("Frame", nil, parent)
	-- Clicks and hover belong to the caller's button (a secure catcher or touch button) under or over the view.
	view:EnableMouse(false)
	for name, fn in pairs(View) do view[name] = fn end
	local body = CreateFrame("Frame", nil, view)
	view.body = body
	view.mask = body:CreateMaskTexture()
	-- The reserved slot look (MainActionBarFrame.lua SetupNonBindableSlotBackdrop): a black disc under the icon.
	view.backdrop = layer(view, "BACKGROUND", 0, true)
	view.backdrop:SetAllPoints(body)
	view.backdrop:SetColorTexture(0, 0, 0, 1)
	view.shadow, view.icon, view.flash = layer(view, "BACKGROUND", -1), layer(view, "BACKGROUND", 1, true), layer(view, "ARTWORK", 0, true)
	view.border, view.checked, view.equipped = layer(view, "ARTWORK", 2), layer(view, "OVERLAY", 0), layer(view, "OVERLAY", 1)
	-- ActionButtonTemplate.xml's cooldowns, in its order and settings, anchored to the icon.
	local cooldown = CreateFrame("Cooldown", nil, body, "CooldownFrameTemplate")
	cooldown:SetDrawBling(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetSwipeColor(0, 0, 0, 0.64)
	local loc = CreateFrame("Cooldown", nil, body, "CooldownFrameTemplate")
	loc:SetDrawBling(false)
	loc:SetHideCountdownNumbers(true)
	loc:SetSwipeColor(0.17, 0, 0, 0.64)
	loc:SetEdgeTexture(LOC_EDGE)
	local charge = CreateFrame("Cooldown", nil, body, "CooldownFrameTemplate")
	charge:SetDrawSwipe(false)
	charge:SetHideCountdownNumbers(true)
	for frame, d in pairs({ [cooldown] = 3, [loc] = 3, [charge] = 2 }) do
		frame:SetPoint("TOPLEFT", view.icon, "TOPLEFT", d, -d)
		frame:SetPoint("BOTTOMRIGHT", view.icon, "BOTTOMRIGHT", -d, d)
		if frame.SetUsingParentLevel then frame:SetUsingParentLevel(true) end
	end
	local text = CreateFrame("Frame", nil, body)
	text:SetAllPoints(body)
	local count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetJustifyH("RIGHT")
	count:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -5, 5)
	local range = text:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	range:SetText(RANGE_INDICATOR)
	range:SetSize(32, 10)
	range:SetPoint("CENTER", body, "CENTER", 10, 10)
	range:Hide()
	view.cooldown, view.loc, view.charge, view.text, view.count, view.range = cooldown, loc, charge, text, count, range
	view.alert = CreateFrame("Frame", nil, body, "ActionButtonSpellAlertTemplate")
	view.alert:Hide()
	-- A view that shows again looks again, like the native slot's OnShow Update; hidden, it stops its range check.
	view:SetScript("OnShow", function()
		text:SetFrameLevel(view:GetFrameLevel() + 2)
		if view.drawn then draw(view) end
	end)
	view:SetScript("OnHide", syncRange)
	view:SetScript("OnSizeChanged", function() view:SetPressed(view.pressed, view.byMouse) end)
	views[#views + 1] = view
	view:SetShape("circle")
	return view
end

-- An event refreshes that kind on every shown view at once, as the native slot's OnEvent does (hidden views look
-- again when shown). Range events only reach views showing that slot.
local function refresh(kind, slot)
	for _, view in ipairs(views) do
		if view.slot and view:IsVisible() and (not slot or view.rangeSlot == slot) then
			if kind == "all" then draw(view) elseif view.looked then LOOK[kind](view, view.slot) end
		end
	end
end

-- The flash blinks while a shown view flashes; the driver stops when none does.
local function tick()
	local blinking
	for _, view in ipairs(views) do
		if view.flashing and view:IsVisible() then
			blink(view)
			blinking = true
		end
	end
	if not blinking then driver:Hide() end
end

-- Our own frames only, so an error puts nothing back: the views keep their last look and stop refreshing.
local function guarded(fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then return end

	failed = true
	driver:Hide()
	ns.log("slot look stopped after an error (/reload to retry)")
	ns.debug("slot view error: %s", tostring(err))
end

driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function() guarded(tick) end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, inRange, checksRange)
	if failed then return end
	if event == "ACTION_RANGE_CHECK_UPDATE" then
		if not rangeOn[arg1] then return end
		rangeOf[arg1] = { inRange = inRange, checks = checksRange }
		return guarded(refresh, "range", arg1)
	end
	if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then return end
	if event == "COMPANION_UPDATE" and arg1 ~= "MOUNT" then return end

	local kind = LOOK_EVENTS[event]
	if kind then guarded(refresh, kind) end
end)
pcall(events.RegisterEvent, events, "ACTION_RANGE_CHECK_UPDATE")
for event in pairs(LOOK_EVENTS) do pcall(events.RegisterEvent, events, event) end
