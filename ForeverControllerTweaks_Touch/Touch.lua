local ns = ForeverControllerTweaks

-- Touch bars: two columns of tap buttons on the left and right screen edges (Steam Link on a phone sends a tap as a
-- mouse click). Each button holds up to four entries, one per crossbar layer (T no modifier, L, R, B both), as the
-- Bindings window does: a tap fires the layer whose modifiers are held at that moment, and on a layer without an entry
-- the button is empty there (hidden in play, a tap does nothing). Every (button, layer) entry a slot can hold sits on its own
-- action slot from Actions' shadow allocator (keyboard bars 6-8, empty slots only, shared with routed cells), keyed
-- ("TL" | "TR") .. layer and the button's index. Nothing is written to a Blizzard frame; the bars hang off our own
-- header under UIParent.
local Touch = {}
ns.Touch = Touch

local MAX = 12
local SIDES = { left = "TL", right = "TR" }
local LAYERS = { "T", "L", "R", "B" }
local IS_LAYER = { T = true, L = true, R = true, B = true }
local SHOWS = { always = true, gamepad = true, combat = true, never = true }
-- Per-side settings the Touch tab reads as ns.Touch.LIMITS: numbers as { min, max, integer }, shape as its allowed
-- values, showEmpty as a boolean.
local LIMITS = {
	count = { 1, MAX, true }, size = { 24, 128 }, gap = { 0, 48 }, inset = { 0, 400 }, offsetY = { -600, 600 }, alpha = { 0.1, 1 },
	shape = { values = { "circle", "square" } }, showEmpty = { boolean = true },
}
Touch.LIMITS = LIMITS
-- Global settings. Each side has its own layout, its button shape (SlotView's native slot art) and showEmpty: empty
-- buttons and empty layers stay on screen in play too, dimmed (they always show while one of our windows is open).
local GLOBALS = { enabled = false, show = "gamepad" }
local SIDE_DEFAULTS = { count = 6, size = 52, gap = 6, inset = 24, offsetY = 0, alpha = 1, shape = "circle", showEmpty = false }
-- An empty button: the native empty crossbar slot (Bindings' empty cells use the same art) in the side's shape, dimmed.
local EMPTY_BG, EMPTY_ALPHA = "gamepad-actionbar-slot-bg-empty", 0.5
local EMPTY_BORDER = { circle = "gamepad-actionbar-circleslot-border-normal", square = "gamepad-actionbar-squareslot-border-normal" }
local COMBAT = "Controller Tweaks changes the touch bars out of combat only."
local NONE = {}

-- The header decides in secure code, so a fight starting or ending shows or hides the bars without a protected call
-- from us. ps-active (the Gamepad UI) is written out of combat only.
local VISIBILITY = [[
	local mode = self:GetAttribute("ps-mode")
	local on = mode == "always" or (mode == "gamepad" and self:GetAttribute("ps-active")) or (mode == "combat" and self:GetAttribute("state-touch") == "combat")
	if on then self:Show() else self:Hide() end
]]

-- A tap picks its layer at press time, in combat too, the way the face router picks a crossbar layer: both crossbar
-- modifiers held -> B, one -> L or R (Blizzard never latches them), else T; a layer without an entry clears the type,
-- so the click does nothing. The release keeps what the press set (actionrelease for hold-to-cast and empower).
local TAP_SNIPPET = [[
	if not down then return end
	local layer = "T"
	local state = GetGamePadState()
	local held = state and state.buttons
	if held then
		local lm, rm = held[self:GetAttribute("ps-ileftmod") or 0], held[self:GetAttribute("ps-irightmod") or 0]
		if lm and rm then layer = "B" elseif lm then layer = "L" elseif rm then layer = "R" end
	end
	-- A ring (Rings.lua): the tap opens it (or closes it when open); a tap on one of its slots fires that slot.
	local ring = self:GetAttribute("ps-ring-" .. layer)
	if ring then
		local rings = self:GetFrameRef("rings")
		self:SetAttribute("type", nil)
		self:SetAttribute("typerelease", nil)
		if rings then rings:RunAttribute("_toggle", ring) end
		return
	end
	local action, text = self:GetAttribute("ps-action-" .. layer), self:GetAttribute("ps-macro-" .. layer)
	self:SetAttribute("type", action and "action" or text and "macro" or nil)
	self:SetAttribute("typerelease", action and "actionrelease" or nil)
	self:SetAttribute("action", action)
	self:SetAttribute("macrotext", text)
	self:SetAttribute("checkselfcast", action and true or nil)
	self:SetAttribute("checkfocuscast", action and true or nil)
	self:SetAttribute("checkmouseovercast", action and true or nil)
]]

local header = CreateFrame("Frame", "ForeverControllerTweaksTouch", UIParent, "SecureHandlerStateTemplate")
header:SetAllPoints(UIParent)
header:Hide()
local bars, buttons = {}, { left = {}, right = {} }
for side in pairs(SIDES) do bars[side] = CreateFrame("Frame", nil, header) end

local function slotCode(side, layer) return SIDES[side] .. layer end

-- Before layers and per-side settings: one count, size, gap, inset, offsetY and alpha for both bars, and one entry
-- per button. The values go to both sides, each entry becomes its button's T entry, and its shadow slot follows.
local function migrate(config, char)
	config.sides = {}
	for side, sideCode in pairs(SIDES) do
		local settings = {}
		for key in pairs(SIDE_DEFAULTS) do settings[key] = config[key] end
		config.sides[side] = settings
		local list = config.bars and config.bars[side] or NONE
		for i, entry in pairs(list) do
			if entry.id then list[i] = { T = entry } end
		end
		for _, info in pairs(char.shadow or NONE) do
			if info.code == sideCode then info.code = sideCode .. "T" end
		end
	end
	for key in pairs(SIDE_DEFAULTS) do config[key] = nil end
end

-- This character's settings, defaults filled in: { enabled, show, sides = { left = { count, size, gap, inset, offsetY,
-- alpha, shape, showEmpty }, right = { ... } }, bars = { left = { [i] = { T, L, R, B } }, right = ... } }; nil before the
-- character is known. Callers must not modify it.
function Touch.Config()
	local char = ns.Face and ns.Face.CharDB()
	if not char then return nil end

	local config = char.touch or {}
	char.touch = config
	if not config.sides then migrate(config, char) end
	-- showEmpty was global before it went per side.
	if config.showEmpty ~= nil then
		for side in pairs(SIDES) do
			if config.sides[side] and config.sides[side].showEmpty == nil then config.sides[side].showEmpty = config.showEmpty end
		end
		config.showEmpty = nil
	end
	for key, value in pairs(GLOBALS) do
		if config[key] == nil then config[key] = value end
	end
	config.bars = config.bars or {}
	for side in pairs(SIDES) do
		local settings = config.sides[side] or {}
		config.sides[side] = settings
		for key, value in pairs(SIDE_DEFAULTS) do
			if settings[key] == nil then settings[key] = value end
		end
		config.bars[side] = config.bars[side] or {}
	end
	return config
end

local function valid(key, value)
	if key == "enabled" then return type(value) == "boolean" end
	if key == "show" then return SHOWS[value] ~= nil end
	local limit = LIMITS[key]
	if limit and limit.boolean then return type(value) == "boolean" end
	if limit and limit.values then
		for _, allowed in ipairs(limit.values) do
			if value == allowed then return true end
		end
		return false
	end
	if not (limit and type(value) == "number") then return false end
	return value >= limit[1] and value <= limit[2] and (not limit[3] or value % 1 == 0)
end

local apply

local function store(target, key, value)
	if InCombatLockdown() then return nil, COMBAT end
	if not valid(key, value) then return nil, ("%s can't be %s"):format(key, tostring(value)) end

	target[key] = value
	apply()
	ns.Fire("FCT_LAYOUT_CHANGED", "touch")
	return true
end

-- A global setting: enabled, show.
function Touch.Set(key, value)
	if GLOBALS[key] == nil then return nil, "unknown touch setting " .. tostring(key) end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end
	return store(config, key, value)
end

-- A side's setting: count, size, gap, inset (from the screen edge), offsetY, alpha, shape, showEmpty.
function Touch.SetSide(side, key, value)
	if not SIDES[side] then return nil, "unknown touch side " .. tostring(side) end
	if SIDE_DEFAULTS[key] == nil then return nil, "unknown touch setting " .. tostring(key) end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end
	return store(config.sides[side], key, value)
end

-- Puts one side's layout (count, size, gap, inset, offsetY, alpha, shape, showEmpty) back to its defaults, or both
-- sides' with nil. Button assignments and their slots stay.
function Touch.Reset(side)
	if side ~= nil and not SIDES[side] then return nil, "unknown touch side " .. tostring(side) end
	if InCombatLockdown() then return nil, COMBAT end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end

	for name in pairs(SIDES) do
		if side == nil or side == name then
			for key, value in pairs(SIDE_DEFAULTS) do config.sides[name][key] = value end
		end
	end
	apply()
	ns.Fire("FCT_LAYOUT_CHANGED", "touch")
	return true
end

local function validButton(side, i) return SIDES[side] and type(i) == "number" and i >= 1 and i <= MAX and i % 1 == 0 end

-- The entry { id, name, icon, kind } on a button's layer (default T), or nil. Callers must not modify it.
function Touch.Entry(side, i, layer)
	layer = layer or "T"
	local config = validButton(side, i) and IS_LAYER[layer] and Touch.Config()
	local layers = config and config.bars[side][i]
	return layers and layers[layer]
end

-- Our secure button, or nil before it is made (out of combat, once the bar shows that many).
function Touch.Button(side, i) return buttons[side] and buttons[side][i] end

-- Slots on keyboard bars 6-8: used (routed cells and touch buttons), still free, and the total.
function Touch.SlotsUsed() return ns.Actions.ShadowCapacity() end

-- entry: a catalog entry, or nil to empty that layer (its slot is given back); layer defaults to T. Refused with the
-- allocator's reason when no slot is free. Fires FCT_LAYOUT_CHANGED("touch").
function Touch.SetEntry(side, i, entry, layer)
	layer = layer or "T"
	if InCombatLockdown() then return nil, COMBAT end
	if not (validButton(side, i) and IS_LAYER[layer]) then return nil, "unknown touch button " .. tostring(side) .. " " .. tostring(i) .. " " .. tostring(layer) end
	-- An addon's Lua key binding: nothing secure can run a binding command.
	if entry and entry.disabled then return nil, entry.note end
	local Actions = ns.Actions
	local kind = entry and Actions.KindOf(entry)
	if entry and not (Actions.SLOT_KINDS[kind] or kind == "face" or kind == "ring") then return nil, tostring(entry.name) .. " can't go on a touch button." end
	local config = Touch.Config()
	if not config then return nil, "no character yet" end

	local new = entry and { id = entry.id, name = entry.name, icon = entry.icon, kind = kind }
	-- Slots are written only with the Gamepad UI on (bars 6-8 are the player's otherwise); the next apply while it is
	-- on places them.
	if ns.Active() then
		local ok, err
		if new and Actions.SLOT_KINDS[kind] then ok, err = Actions.Shadow(slotCode(side, layer), i, new) else ok, err = Actions.ReleaseShadow(slotCode(side, layer), i) end
		if not ok then return nil, err end
	end
	local list = config.bars[side]
	local layers = list[i] or {}
	layers[layer] = new
	list[i] = next(layers) and layers or nil
	apply()
	ns.Fire("FCT_LAYOUT_CHANGED", "touch")
	return true
end

-- The crossbar layer shown now, as a tap would pick it: the held crossbar modifiers (IsKeyDown on their keys, which
-- allocates nothing, so the display can follow it every frame).
local leftKey, rightKey = nil, nil
local function heldLayer()
	local lm, rm = leftKey and IsKeyDown(leftKey), rightKey and IsKeyDown(rightKey)
	return lm and rm and "B" or lm and "L" or rm and "R" or "T"
end

-- The layer the bars show now (T, L, R, B), for the Touch tab's preview.
function Touch.Layer() return heldLayer() end

-- Blizzard's tooltip for an action button (ActionBarActionButtonMixin:SetTooltip), on the shown layer's slot.
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
	header:WrapScript(button, "OnClick", TAP_SNIPPET)
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
	local background = empty:CreateTexture(nil, "ARTWORK")
	background:SetAllPoints(empty)
	background:SetAtlas(EMPTY_BG)
	empty.border = empty:CreateTexture(nil, "ARTWORK")
	empty.border:SetAllPoints(empty)
	button.empty, button.slots, button.layers = empty, {}, NONE
	buttons[side][i] = button
	return button
end

-- How one layer fires: its slot (native use, hold-to-cast), a face action's reserved button clicked down and up (the
-- routed form), or the entry's macro text until its slot is placed.
local function resolve(side, i, layer, entry, writable)
	local Actions = ns.Actions
	local kind = entry and Actions.KindOf(entry)
	local key = slotCode(side, layer)
	if entry and Actions.SLOT_KINDS[kind] then
		local slot = Actions.ShadowSlot(key, i, entry.id)
		if not slot and writable then slot = Actions.Shadow(key, i, entry) end
		return slot, not slot and Actions.TextFor(entry.id) or nil
	end
	if writable then Actions.ReleaseShadow(key, i) end
	if kind == "face" then
		local target = ns.Face.ActionButton(tostring(entry.id):match("^face:(%a+)$"))
		return nil, target and ns.Face.ClickBoth(target:GetName())
	end
end

-- Out of combat: every layer's action or text on the button for the tap snippet, and T as the click before any.
local function aim(button, side, i, layers, mods, writable)
	for _, layer in ipairs(LAYERS) do
		local entry = layers[layer]
		local slot, text = resolve(side, i, layer, entry, writable)
		button:SetAttribute("ps-action-" .. layer, slot)
		button:SetAttribute("ps-macro-" .. layer, text)
		button:SetAttribute("ps-ring-" .. layer, entry and tonumber(tostring(entry.id):match("^ring:(%d+)$")) or nil)
		button.slots[layer] = slot
	end
	for role, index in pairs(mods) do button:SetAttribute("ps-i" .. role, index) end
	local slot, text = button.slots.T, button:GetAttribute("ps-macro-T")
	button:SetAttribute("type", slot and "action" or text and "macro" or nil)
	button:SetAttribute("typerelease", slot and "actionrelease" or nil)
	button:SetAttribute("action", slot)
	button:SetAttribute("macrotext", text)
	for _, check in ipairs(ns.Face.CHECK_CASTS) do button:SetAttribute(check, slot and true or nil) end
	button.layers = layers
end

-- Insecure display, so it follows the layer in combat: the shown layer's entry with every state of its slot. A layer
-- without an entry is empty: nothing drawn in play (the secure button stays where it is, and its tap does nothing),
-- the dimmed empty-slot art while previewing (our window open, or the side's showEmpty). SlotView draws an empty slot as
-- its black backdrop disc, so it hides.
local shownLayer = "T"
local function draw(button)
	local entry, slot = button.layers[shownLayer], button.slots[shownLayer]
	button.slot = slot
	button.view:SetSlot(slot, entry and entry.icon)
	button.view:SetShown(entry ~= nil)
	button.empty:SetShown(not entry and button.preview)
end

local function drawAll()
	for _, list in pairs(buttons) do
		for _, button in pairs(list) do draw(button) end
	end
end

-- Runs only while the bars are shown; redraws only when the held layer changes.
local watcher = CreateFrame("Frame", nil, header)
watcher:SetScript("OnUpdate", function()
	local layer = heldLayer()
	if layer == shownLayer then return end
	shownLayer = layer
	drawAll()
end)

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
	local mods = ns.Face.ModifierIndexes()
	leftKey, rightKey = ns.Layout.RoleKey("leftmod"), ns.Layout.RoleKey("rightmod")
	shownLayer = heldLayer()
	-- Disabled: nothing is made or placed; slots already placed are kept for when it is on again.
	for side, bar in pairs(config.enabled and bars or NONE) do
		local settings = config.sides[side]
		local count, size, gap, shape = settings.count, settings.size, settings.gap, settings.shape
		local preview = not not (settings.showEmpty or ns.panelOpen)
		bar:ClearAllPoints()
		bar:SetPoint(side:upper(), UIParent, side:upper(), side == "left" and settings.inset or -settings.inset, settings.offsetY)
		bar:SetSize(size, count * size + (count - 1) * gap)
		bar:SetAlpha(settings.alpha)
		for i = 1, MAX do
			local button = buttons[side][i] or i <= count and newButton(side, i)
			if button then
				local layers = config.bars[side][i]
				-- Once the Rings module is loaded; it may load after this one.
				if ns.Rings and not button.ringsLinked then
					SecureHandlerSetFrameRef(button, "rings", ns.Rings.Frame())
					button.ringsLinked = true
				end
				button:ClearAllPoints()
				button:SetPoint("TOP", bar, "TOP", 0, -(i - 1) * (size + gap))
				button:SetSize(size, size)
				-- The hit area is the button's square frame for either shape, as on the native bars.
				button.view:SetShape(shape)
				button.empty.border:SetAtlas(EMPTY_BORDER[shape])
				button.preview = preview
				aim(button, side, i, layers or NONE, mods, writable)
				draw(button)
				-- A button with an entry on any layer stays shown (drawn only on its filled layers); a wholly empty one hides
				-- in play. Every other button keeps its place.
				if i <= count and (layers or preview) then button:Show() else button:Hide() end
			end
		end
	end
	header:SetAttribute("ps-active", writable or nil)
	header:SetAttribute("ps-mode", config.enabled and config.show or "never")
	header:Execute(VISIBILITY)
	ns.debug("touch %s", config.enabled and config.show or "off")
	-- One line per assigned layer, after layout and visibility: what the screen should show.
	for side, list in pairs(buttons) do
		for i, button in pairs(list) do
			local view = button.view
			for _, layer in ipairs(LAYERS) do
				local entry = button.layers[layer]
				if entry then ns.debug("touch %s %d %s %s slot=%s type=%s shown=%s alpha=%.2f", side, i, layer, tostring(entry.id), tostring(button.slots[layer]), button.slots[layer] and "action" or tostring(button:GetAttribute("ps-macro-" .. layer) and "macro"), tostring(view:IsVisible()), view:GetEffectiveAlpha()) end
			end
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
-- A release gives the slots back; a remap or another controller may move the crossbar modifiers.
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "release" or reason == "layout" or reason == "device" then apply() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then apply() end end)
