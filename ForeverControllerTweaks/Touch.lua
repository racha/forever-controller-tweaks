local _, ns = ...

-- Touch bars: two columns of tap buttons on the left and right screen edges (Steam Link on a phone sends a tap as a
-- mouse click). Each button is our own secure action button on a real action slot from Actions' shadow allocator
-- (keyboard bars 6-8, empty slots only), keyed ("TL" | "TR", index) so it never meets a routed cell's slot. Nothing is
-- written to a Blizzard frame; the bars hang off our own header under UIParent.
local Touch = {}
ns.Touch = Touch

local MAX = 12
local SIDES = { left = "TL", right = "TR" }
local SHOWS = { always = true, gamepad = true, combat = true, never = true }
-- { min, max, integer }; the Touch tab reads them as ns.Touch.LIMITS.
local LIMITS = { count = { 1, MAX, true }, size = { 24, 128 }, gap = { 0, 48 }, inset = { 0, 400 }, offsetY = { -600, 600 }, alpha = { 0.1, 1 } }
Touch.LIMITS = LIMITS
-- showEmpty: empty buttons stay on screen in play too (they always show while one of our windows is open).
local DEFAULTS = { enabled = false, showEmpty = false, show = "gamepad", count = 6, size = 52, gap = 6, inset = 24, offsetY = 0, alpha = 1 }
-- An empty button: the native empty crossbar slot (Bindings' empty cells use the same art), dimmed.
local EMPTY_BG, EMPTY_BORDER, EMPTY_ALPHA = "gamepad-actionbar-slot-bg-empty", "gamepad-actionbar-circleslot-border-normal", 0.5
local COMBAT = "Controller Tweaks changes the touch bars out of combat only."

-- The header decides in secure code, so a fight starting or ending shows or hides the bars without a protected call
-- from us. ps-active (the Gamepad UI) is written out of combat only.
local VISIBILITY = [[
	local mode = self:GetAttribute("ps-mode")
	local on = mode == "always" or (mode == "gamepad" and self:GetAttribute("ps-active")) or (mode == "combat" and self:GetAttribute("state-touch") == "combat")
	if on then self:Show() else self:Hide() end
]]

local header = CreateFrame("Frame", "ForeverControllerTweaksTouch", UIParent, "SecureHandlerStateTemplate")
header:SetAllPoints(UIParent)
header:Hide()
local bars, buttons = {}, { left = {}, right = {} }
for side in pairs(SIDES) do bars[side] = CreateFrame("Frame", nil, header) end

-- This character's settings, defaults filled in; nil before the character is known.
function Touch.Config()
	local char = ns.Face and ns.Face.CharDB()
	if not char then return nil end

	local config = char.touch or {}
	char.touch = config
	for key, value in pairs(DEFAULTS) do
		if config[key] == nil then config[key] = value end
	end
	config.bars = config.bars or {}
	for side in pairs(SIDES) do config.bars[side] = config.bars[side] or {} end
	return config
end

local function valid(key, value)
	if key == "enabled" or key == "showEmpty" then return type(value) == "boolean" end
	if key == "show" then return SHOWS[value] ~= nil end
	local limit = LIMITS[key]
	if not (limit and type(value) == "number") then return false end
	return value >= limit[1] and value <= limit[2] and (not limit[3] or value % 1 == 0)
end

local apply

function Touch.Set(key, value)
	if InCombatLockdown() then return nil, COMBAT end
	if DEFAULTS[key] == nil then return nil, "unknown touch setting " .. tostring(key) end
	if not valid(key, value) then return nil, ("%s can't be %s"):format(key, tostring(value)) end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end

	config[key] = value
	apply()
	ns.Fire("FCT_LAYOUT_CHANGED", "touch")
	return true
end

local function validButton(side, i) return SIDES[side] and type(i) == "number" and i >= 1 and i <= MAX and i % 1 == 0 end

-- The entry { id, name, icon, kind } on a button, or nil. Callers must not modify it.
function Touch.Entry(side, i)
	local config = validButton(side, i) and Touch.Config()
	return config and config.bars[side][i]
end

-- Our secure button, or nil before it is made (out of combat, once the bar shows that many).
function Touch.Button(side, i) return buttons[side] and buttons[side][i] end

-- entry: a catalog entry, or nil to empty the button (its slot is given back). Fires FCT_LAYOUT_CHANGED("touch").
function Touch.SetEntry(side, i, entry)
	if InCombatLockdown() then return nil, COMBAT end
	if not validButton(side, i) then return nil, "unknown touch button " .. tostring(side) .. " " .. tostring(i) end
	-- An addon's Lua key binding: nothing secure can run a binding command.
	if entry and entry.disabled then return nil, entry.note end
	local Actions = ns.Actions
	local kind = entry and Actions.KindOf(entry)
	if entry and not (Actions.SLOT_KINDS[kind] or kind == "face") then return nil, tostring(entry.name) .. " can't go on a touch button." end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end

	local new = entry and { id = entry.id, name = entry.name, icon = entry.icon, kind = kind }
	-- Slots are written only with the Gamepad UI on (bars 6-8 are the player's otherwise); the next apply while it is
	-- on places them.
	if ns.Active() then
		local ok, err
		if new and Actions.SLOT_KINDS[kind] then ok, err = Actions.Shadow(SIDES[side], i, new) else ok, err = Actions.ReleaseShadow(SIDES[side], i) end
		if not ok then return nil, err end
	end
	config.bars[side][i] = new
	apply()
	ns.Fire("FCT_LAYOUT_CHANGED", "touch")
	return true
end

-- Blizzard's tooltip for an action button (ActionBarActionButtonMixin:SetTooltip), on the button's slot.
local function tooltip(self)
	if not self.slot then return end
	if GetCVar("UberTooltips") == "1" then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
	self.UpdateTooltip = GameTooltip:SetAction(self.slot) and tooltip or nil
end

local function leave(self)
	self.UpdateTooltip = nil
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function newButton(side, i)
	local button = CreateFrame("Button", "ForeverControllerTweaksTouch" .. (side == "left" and "Left" or "Right") .. i, bars[side], "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")
	button:SetScript("OnEnter", tooltip)
	button:SetScript("OnLeave", leave)
	-- The native slot look and states (SlotView.lua); the view has no size or place of its own, and its press follows
	-- the tap (a mouse click: the pushed frame only, as ApplyPressedStyle does for mouse clicks).
	local view = ns.SlotView.New(button)
	view:SetAllPoints(button)
	button.view = view
	button:SetScript("OnMouseDown", function() view:SetPressed(true, true) end)
	button:SetScript("OnMouseUp", function() view:SetPressed(false) end)
	button:SetScript("OnHide", function() view:SetPressed(false) end)
	local empty = CreateFrame("Frame", nil, button)
	empty:SetAllPoints(button)
	empty:SetAlpha(EMPTY_ALPHA)
	for _, atlas in ipairs({ EMPTY_BG, EMPTY_BORDER }) do
		local texture = empty:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints(empty)
		texture:SetAtlas(atlas)
	end
	button.empty = empty
	buttons[side][i] = button
	return button
end

-- How a button fires: its slot (native use, hold-to-cast), a face action's reserved button clicked down and up (the
-- routed form), or the entry's macro text until its slot is placed.
local function aim(button, side, i, entry, writable)
	local Actions = ns.Actions
	local kind = entry and Actions.KindOf(entry)
	local slot, text
	if entry and Actions.SLOT_KINDS[kind] then
		slot = Actions.ShadowSlot(SIDES[side], i, entry.id)
		if not slot and writable then slot = Actions.Shadow(SIDES[side], i, entry) end
		text = not slot and Actions.TextFor(entry.id) or nil
	elseif writable then
		Actions.ReleaseShadow(SIDES[side], i)
	end
	if kind == "face" then
		local target = ns.Face.ActionButton(tostring(entry.id):match("^face:(%a+)$"))
		local name = target and target:GetName()
		text = name and ns.Face.ClickBoth(name)
	end
	button:SetAttribute("type", slot and "action" or text and "macro" or nil)
	button:SetAttribute("typerelease", slot and "actionrelease" or nil)
	button:SetAttribute("action", slot)
	button:SetAttribute("macrotext", text)
	for _, check in ipairs(ns.Face.CHECK_CASTS) do button:SetAttribute(check, slot and true or nil) end
	button.slot = slot
	-- Without a slot (a face action, or macro text until the slot is placed): the entry's icon, no states.
	button.view:SetSlot(slot, entry and entry.icon)
	-- SlotView draws an empty slot as its black backdrop disc; an empty button shows the empty-slot art instead.
	button.view:SetShown(entry ~= nil)
	button.empty:SetShown(not entry)
end

local setUp, pending
local function applyNow()
	if InCombatLockdown() then
		pending = true
		return
	end
	local config = Touch.Config()
	if not config then return end
	pending = nil
	if not setUp then
		setUp = true
		header:SetAttribute("_onstate-touch", VISIBILITY)
		RegisterStateDriver(header, "touch", "[combat] combat; nocombat")
	end

	local writable = ns.Active()
	local preview = config.showEmpty or ns.panelOpen
	local count, size, gap = config.count, config.size, config.gap
	-- Disabled: nothing is made or placed; slots already placed are kept for when it is on again.
	for side, bar in pairs(config.enabled and bars or {}) do
		bar:ClearAllPoints()
		bar:SetPoint(side:upper(), UIParent, side:upper(), side == "left" and config.inset or -config.inset, config.offsetY)
		bar:SetSize(size, count * size + (count - 1) * gap)
		bar:SetAlpha(config.alpha)
		for i = 1, MAX do
			local button = buttons[side][i] or i <= count and newButton(side, i)
			if button then
				button:ClearAllPoints()
				button:SetPoint("TOP", bar, "TOP", 0, -(i - 1) * (size + gap))
				button:SetSize(size, size)
				aim(button, side, i, config.bars[side][i], writable)
				-- Empty buttons hide in play, keeping every other button where it is.
				if i <= count and (config.bars[side][i] or preview) then button:Show() else button:Hide() end
			end
		end
	end
	header:SetAttribute("ps-active", writable or nil)
	header:SetAttribute("ps-mode", config.enabled and config.show or "never")
	header:Execute(VISIBILITY)
	ns.debug("touch %s", config.enabled and config.show or "off")
	-- One line per assigned button, after layout and visibility: what the screen should show.
	for side, list in pairs(buttons) do
		for i, button in pairs(list) do
			local entry = config.bars[side][i]
			local view = button.view
			if entry then ns.debug("touch %s %d %s slot=%s type=%s shown=%s alpha=%.2f", side, i, tostring(entry.id), tostring(button.slot), tostring(button:GetAttribute("type")), tostring(view:IsVisible()), view:GetEffectiveAlpha()) end
		end
	end
end

-- Placing a slot makes and deletes FCT: macros, whose UPDATE_MACROS would apply again mid-swap; a Lua error must not
-- leave busy set.
local busy, failed
function apply()
	if busy or ns.Actions.Busy() then return end
	busy = true
	local ok, err = pcall(applyNow)
	busy = false
	if ok or failed then return end
	failed = true
	ns.debug("touch apply failed: %s", tostring(err))
end

-- Our windows (the Touch tab among them) show the empty buttons while open; Core's SetPanelOpen sends no message.
local setPanelOpen = ns.SetPanelOpen
function ns.SetPanelOpen(open)
	local was = ns.panelOpen
	setPanelOpen(open)
	if ns.panelOpen ~= was then apply() end
end

ns.On("PLAYER_ENTERING_WORLD", apply)
ns.On("FCT_ACTIVE_CHANGED", apply)
-- Only a text change matters (an assigned entry's macro text, or a slot to place again); one apply per frame.
local queued
ns.On("FCT_CATALOG_CHANGED", function(event)
	local config = ns.Actions.TEXT_EVENTS[event] and Touch.Config()
	if queued or not (config and config.enabled and (next(config.bars.left) or next(config.bars.right))) then return end
	queued = true
	C_Timer.After(0, function()
		queued = nil
		apply()
	end)
end)
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "release" then apply() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then apply() end end)
