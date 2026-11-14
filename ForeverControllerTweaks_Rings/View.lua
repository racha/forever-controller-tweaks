-- Forever Controller Tweaks ring display (design/rings.md): the keyboard's disc family (the native targeting-radial
-- circle, our glow, rim and hub art), the ring's icon and name in the hub, the slots in native round slot art around
-- it, a gold focus on the slot the aiming stick (or the finger) is on and that slot's name under the hub.
-- Display only, on our own insecure frames: the secure frame (Rings.lua) opens, picks and fires. This reads its
-- attributes, polls the stick in OnUpdate while shown, and draws states with the C_Spell / C_Item calls (duration
-- objects for cooldowns, so secret values pass as they do on SlotView's native slots).
-- Stick capture: the display frame has EnableGamePadStick set once out of combat. Shown with the ring, it takes the
-- sticks; it keeps the aiming stick (the ring's Stick setting, resolved by the secure frame as ps-aimside) and hands
-- the other on (OnGamePadStick returning true), as Blizzard's own radial wheel does for the left stick: aiming with the
-- right one, the left still walks; aiming with the left one, the right still turns the camera. Hidden, it takes
-- nothing. The game reports one physical stick under several names (Right / Camera / Look, Left / Movement). When a
-- held ring closes, Rings.HoldStick keeps the aiming stick from the game until it is back in the middle, so the
-- character doesn't walk off (or the camera swing) on the release.
local ns = ForeverControllerTweaks
local Rings, UI = ns.Rings, ns.UI
local L = UI.L

local View = {}
Rings.View = View

L.RINGS_AIM = "Aim, release to use. Centre cancels."
L.RINGS_TAP = "Tap a slot to use it, anywhere else to close."

local GEO = Rings.GEO
local DISC, HUB, ICON = GEO.DISC, GEO.HUB, GEO.ICON
local CLAMP = "CLAMPTOBLACKADDITIVE"
local GOLD = { 1, 230 / 255, 102 / 255 }
-- ring.tga's circle has radius 27 in a 64 box; the focus ring sits 3 outside the icon.
local FOCUS_RING = (ICON / 2 + 3) * 64 / 27
local RANGE_EVERY = 0.2
local STATE_EVENTS = {
	"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
	"PLAYER_TARGET_CHANGED",
}

local function sound(id) if id then PlaySound(id) end end

-- The disc, glow, rim and hub (design/keyboard.md section 9 at the ring's radius), and the hub's icon, name and the
-- focused slot's name under it. Shared with the Rings tab's preview.
function View.Disc(parent)
	for _, spec in ipairs({ { "disc", 2 * DISC, 0.62, 1 }, { "kb-glow", 2 * DISC - 12, 1, 2 }, { "kb-rim", 2 * DISC + 8, 1, 3 }, { "kb-hub", 2 * HUB + 4, 1, 4 } }) do
		local tex = parent:CreateTexture(nil, "BACKGROUND", nil, spec[4])
		if spec[1] == "disc" then tex:SetAtlas("gamepad-targetingradial-radial-circle") else tex:SetTexture(UI.ART .. spec[1] .. ".tga") end
		tex:SetSize(spec[2], spec[2])
		tex:SetPoint("CENTER")
		tex:SetAlpha(spec[3])
	end
	local hub = {}
	hub.icon = parent:CreateTexture(nil, "ARTWORK")
	hub.icon:SetSize(32, 32)
	hub.icon:SetPoint("CENTER", 0, 10)
	local mask = parent:CreateMaskTexture()
	mask:SetAtlas("CircleMask", false, nil, nil, CLAMP, CLAMP)
	mask:SetAllPoints(hub.icon)
	hub.icon:AddMaskTexture(mask)
	hub.name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hub.name:SetPoint("TOP", hub.icon, "BOTTOM", 0, -4)
	hub.name:SetWidth(2 * HUB - 14)
	hub.name:SetWordWrap(false)
	hub.slotName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hub.slotName:SetPoint("CENTER", 0, -(HUB + 16))
	hub.slotName:SetWidth(2 * (GEO.SLOT_R - ICON / 2) - 8)
	hub.slotName:SetWordWrap(false)
	return hub
end

-- A slot's look on button: SlotView's native round slot (its regions drawn by us, as its header allows for a non-slot
-- action), a gold glow under it and a gold ring over its body while focused.
function View.NewSlot(button)
	local view = ns.SlotView.New(button)
	view:SetAllPoints(button)
	view:SetShape("circle")
	local under = CreateFrame("Frame", nil, button)
	under:SetAllPoints(button)
	under:SetFrameLevel(button:GetFrameLevel())
	view.glow = under:CreateTexture(nil, "BACKGROUND")
	view.glow:SetTexture(UI.ART .. "kb-glow.tga")
	view.glow:SetSize(ICON * 2, ICON * 2)
	view.glow:SetPoint("CENTER")
	view.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
	view.ring = view.body:CreateTexture(nil, "OVERLAY", nil, 7)
	view.ring:SetTexture(UI.ART .. "ring.tga")
	view.ring:SetSize(FOCUS_RING, FOCUS_RING)
	view.ring:SetPoint("CENTER")
	view.ring:SetVertexColor(1, 210 / 255, 0)
	View.SetFocus(view, false)
	return view
end

function View.SetFocus(view, on)
	view.glow:SetShown(on)
	view.ring:SetShown(on)
end

-- What the slot shows: its icon (desaturated while this character can't use it, dimmed while empty), no states yet.
function View.DrawSlot(view, stored, entry)
	view.entry = entry
	view:SetSlot(nil, stored and (entry and entry.icon or stored.icon) or nil)
	view.icon:SetDesaturated(stored ~= nil and not Rings.Attributes(entry))
	view:SetAlpha(stored and 1 or 0.5)
end

---------------------------------------------------------------------------------------------------------------------
-- States, as SlotView's LOOK draws them for a slot, from the spell or item itself.

local function setDuration(cooldown, duration)
	if duration then cooldown:SetCooldownFromDurationObject(duration, true) else cooldown:Clear() end
end

local function tint(view, usable, noMana)
	if usable then view.icon:SetVertexColor(1, 1, 1) elseif noMana then view.icon:SetVertexColor(0.5, 0.5, 1) else view.icon:SetVertexColor(0.4, 0.4, 0.4) end
end

local function glow(view, show)
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

local function range(view, checks, inRange)
	view.range:SetShown(checks)
	if checks then view.range:SetVertexColor((inRange and ACTIONBAR_HOTKEY_FONT_COLOR or RED_FONT_COLOR):GetRGB()) end
end

-- The spell or item a slot draws from: ("spell", id) or ("item", id); nil for macro text (icon only).
local function source(entry)
	local actionType, _, value = Rings.Attributes(entry)
	if actionType == "spell" then return "spell", value end
	if actionType == "item" then return "item", tonumber(tostring(value):match("%d+")) end
	if actionType == "toy" then return "item", value end
end

local LOOK = {}
function LOOK.spell(view, id)
	setDuration(view.cooldown, C_Spell.GetSpellCooldownDuration(id))
	setDuration(view.loc, C_Spell.GetSpellLossOfControlCooldownDuration(id))
	setDuration(view.charge, C_Spell.GetSpellChargeDuration(id))
	tint(view, C_Spell.IsSpellUsable(id))
	view.count:SetText(C_Spell.GetSpellDisplayCount(id))
	glow(view, C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(id))
end
function LOOK.item(view, id)
	local start, duration, enabled = C_Item.GetItemCooldown(id)
	local timer = view.itemTimer or C_DurationUtil.CreateDuration()
	view.itemTimer = timer
	timer:SetTimeFromStart(start or 0, duration or 0)
	setDuration(view.cooldown, enabled and duration and duration > 0 and timer or nil)
	view.loc:Clear()
	view.charge:Clear()
	tint(view, C_Item.IsUsableItem(id))
	view.count:SetText(C_Item.IsConsumableItem(id) and C_Item.GetItemCount(id, false, true) or "")
	glow(view, false)
end

local RANGE = {}
function RANGE.spell(id)
	if not C_Spell.SpellHasRange(id) then return false end
	local inRange = C_Spell.IsSpellInRange(id, "target")
	return inRange ~= nil, inRange
end
function RANGE.item(id)
	if not C_Item.ItemHasRange(id) then return false end
	local inRange = C_Item.IsItemInRange(id, "target")
	return inRange ~= nil, inRange
end

-- One view's states, guarded: in combat a value may be secret, and a failed read leaves that view as drawn.
local function drawStates(view, withRange)
	local kind, id = source(view.entry)
	if not (kind and id) then return end
	if not withRange then
		local ok, err = pcall(LOOK[kind], view, id)
		if not ok then ns.debug("ring slot state: %s", tostring(err)) end
		return
	end
	local ok, checks, inRange = pcall(RANGE[kind], id)
	if ok then range(view, checks, inRange) end
end

---------------------------------------------------------------------------------------------------------------------
-- In game

local frame = Rings.Frame()
local display = CreateFrame("Frame", nil, frame)
display:SetAllPoints()
display:SetFrameLevel(frame:GetFrameLevel() + 1)
local hub = View.Disc(display)
local hint = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOP", display, "BOTTOM", 12, -10)
local stickGlyph = UI.Glyph(display, 22, "R3")
stickGlyph:SetPoint("RIGHT", hint, "LEFT", -6, 0)

local views = {}
local drawn, focused, dirty, rangeIn = {}, nil, false, 0

local function focus(i)
	if i == focused then return end
	focused = i
	for index, view in pairs(views) do View.SetFocus(view, index == i) end
	local slot = i and drawn.ring and drawn.ring.slots[i]
	hub.slotName:SetText(slot and slot.name or "")
	if i and drawn.mode == "hold" then sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT) end
end

local AIM_GLYPH = { right = "R3", left = "L3" }
-- How the ring shown now was opened ("hold" | "touch"): the close clears the frame's ps-mode before the hide.
local openMode

local function draw(id, mode, side)
	local ring = Rings.Get(id)
	drawn = { id = id, mode = mode, side = side, ring = ring }
	openMode = mode
	focused = -1
	focus(nil)
	if not ring then return end
	hub.icon:SetTexture(Rings.Icon(ring))
	hub.name:SetText(ring.name)
	for i = 1, ring.count do
		local view = views[i]
		local stored = ring.slots[i]
		if view then View.DrawSlot(view, stored, Rings.Resolve(stored)) end
	end
	hint:SetText(mode == "hold" and L.RINGS_AIM or L.RINGS_TAP)
	stickGlyph:SetShown(mode == "hold")
	stickGlyph:SetCode(AIM_GLYPH[side] or "R3")
	dirty, rangeIn = true, 0
end

-- The aiming stick as the secure pick reads it (GetGamePadState in the snippet is this call).
local function stickSlot(count)
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	local sticks = ok and type(state) == "table" and state.sticks
	local stick = sticks and sticks[frame:GetAttribute("ps-aim") or 2]
	return stick and Rings.SlotAt(stick.x, stick.y, count)
end

display:SetScript("OnShow", function()
	drawn, openMode = {}, frame:GetAttribute("ps-mode")
	sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_OPEN)
end)
-- The close keeps ps-aim and ps-aimside: the stick that aimed is held off until it is back in the middle.
display:SetScript("OnHide", function()
	if openMode == "hold" then Rings.HoldStick(frame:GetAttribute("ps-aimside") or "right", frame:GetAttribute("ps-aim")) end
	drawn, focused, openMode = {}, nil, nil
	sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_CLOSE)
end)
display:SetScript("OnUpdate", function(_, elapsed)
	local id, mode, side = frame:GetAttribute("ps-ring"), frame:GetAttribute("ps-mode"), frame:GetAttribute("ps-aimside")
	if id ~= drawn.id or mode ~= drawn.mode or side ~= drawn.side then draw(id, mode, side) end
	local ring = drawn.ring
	if not ring then return end
	if mode == "hold" then focus(stickSlot(ring.count)) end
	if dirty then
		dirty = false
		for i = 1, ring.count do if views[i] then drawStates(views[i]) end end
	end
	rangeIn = rangeIn - elapsed
	if rangeIn > 0 then return end
	rangeIn = RANGE_EVERY
	for i = 1, ring.count do if views[i] then drawStates(views[i], true) end end
end)
-- Every stick but the aiming one goes on to the game (a touch ring aims with none).
display:SetScript("OnGamePadStick", function(_, stick)
	local names = frame:GetAttribute("ps-mode") == "hold" and Rings.AIM_NAMES[frame:GetAttribute("ps-aimside") or "right"]
	return not (names and names[stick])
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() if display:IsVisible() then dirty = true end end)
for _, event in ipairs(STATE_EVENTS) do pcall(events.RegisterEvent, events, event) end

-- Stick capture and the slot buttons' scripts touch protected frames' settings: once, out of combat.
local ready
local function init()
	if ready or InCombatLockdown() then return end
	ready = true
	display:EnableGamePadStick(true)
	for i = 1, Rings.MAX_SLOTS do
		local button = Rings.Slot(i)
		views[i] = View.NewSlot(button)
		-- A finger on a touch ring: the slot under it is focused.
		button:SetScript("OnEnter", function() if drawn.mode == "touch" then focus(i) end end)
		button:SetScript("OnLeave", function() if focused == i then focus(nil) end end)
	end
end

init()
ns.On("PLAYER_REGEN_ENABLED", init)
-- An edit while a ring is open (out of combat only) redraws it.
ns.On("FCT_RINGS_CHANGED", function() drawn = {} end)
