-- Forever Controller Tweaks ring display (design/rings.md section 10): Forever's game-menu radial (GamepadRadial.xml /
-- .lua) on our own frames with the native atlases, the wheel only: a segment per slot with the action's icon and gold
-- label, and the native highlight on the slot aimed at. The native title and context bands are left out (the user's
-- call: no bloat above or below the wheel). Nothing of the native radial is called or inherited.
-- Display only: the secure frame (Rings.lua) opens, picks and fires. This reads its attributes, polls the stick in
-- OnUpdate while shown, and draws states with the C_Spell / C_Item calls (duration objects for cooldowns, so secret
-- values pass as they do on SlotView's native slots).
-- Wheel: the native one is cut for 8. Other counts reuse it, turned and masked by our own invisible sector masks
-- (Art/ring-sector-<centidegrees>.tga): each wedge is filled with pieces of the texture with a segment's clear middle
-- turned onto it, and each divider is the texture's own divider turned into place. Pieces touch and never overlap, so
-- the half-transparent fill stays one layer. The highlight and the disabled segment are pieced below 8 the same way.
-- Stick capture: the display frame has EnableGamePadStick set once out of combat. Shown with the ring, it takes the
-- sticks; it keeps the aiming stick (the ring's Stick setting, resolved by the secure frame as ps-aimside) and hands
-- the other on (OnGamePadStick returning true), as Blizzard's own radial wheel does for the left stick: aiming with the
-- right one, the left still walks; aiming with the left one, the right still turns the camera. Hidden, it takes
-- nothing. The game reports one physical stick under several names (Right / Camera / Look, Left / Movement). When a
-- held ring closes, Rings.HoldStick keeps the aiming stick from the game until it is back in the middle, so the
-- character doesn't walk off (or the camera swing) on the release.
-- Compact style: the game's radial flyout, circular style (Blizzard_GamepadActionBars FlyoutRadial.lua / .xml, the
-- paladin aura and stance picker): the circular base, a slot backdrop where a slot is empty, a filled slot the 36 icon
-- in the slot mask on the slot-normal ring, all at atlas size, GEO.COMPACT_R out at the Full angles (native: 8 at 45
-- degrees). The aimed slot: the over-border (the native HighlightTexture, shown while selected), the selection
-- indicator turned to it and the large cursor arrow 38 out pointing at it; aimed at an empty slot, the indicator
-- desaturated and no arrow, as with no selection natively. No labels. In the middle, as the flyout sits on the
-- crossbar button that opened it: the ring's icon in that button's native slot art (SlotView: an expanded circle, a
-- square on a D-pad cell) and, under it, the glyphs of the layer's modifiers joined by a plus, as the bars'
-- InputPromptTwoIcon prompt (24 icons, an 8 plus 4 from each, 35 under the centre). The base layer shows none.
-- View.Wheel / DrawWheel / Highlight / NewSlot / DrawSlot are shared with the Rings tab's preview, which scales the wheel
-- to fit its box.
local ns = ForeverControllerTweaks
local Rings, UI = ns.Rings, ns.UI

local View = {}
Rings.View = View


local GEO = Rings.GEO
local CLAMP = "CLAMPTOBLACKADDITIVE"
-- The native wheel (GamepadRadial.lua): the atlas size, the segment angle, the highlight's distance and size, the
-- disabled segment's height. The piece layout for other counts is Rings.WheelPieces / SegmentPieces.
local WHEEL_W, WHEEL_H, SEG = 540, 541, Rings.ART.SEG
local HL_R, HL_W, HL_H, DISABLED_H = GEO.HL_R, 169, 165, 164
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Compact (CIRCLE_STYLE_PROPERTIES): the icon size, the arrow's distance, the indicator's width (no wider than the
-- icon), the arrow's size; the round cooldown swipe.
local FLY_ICON, ARROW_R, INDICATOR_W, ARROW_W, ARROW_H = 36, 38, 36, 21, 35
local FLY = "gamepad-flyout-circular-"
-- The crossbar button's expanded sizes (ActionBarStyles.lua); the modifier prompt's icon size, plus, gap and drop.
local CENTRE = { circle = 38, square = 40 }
local MOD_SIZE, PLUS_SIZE, MOD_GAP, MOD_Y = 24, 8, 4, -35
-- The modifier roles each layer is held with (Layout roles; the left one first, as the bottom bar's prompt).
local LAYER_ROLES = { left = { "leftmod" }, right = { "rightmod" }, bottom = { "leftmod", "rightmod" }, friendly = { "friendly" }, hostile = { "hostile" } }
local ROUND_SWIPE, SQUARE_SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask", "Interface\\Buttons\\WHITE8X8"
-- textAnchorData: the label's offset from its icon every 45 degrees clockwise from the top (WoW y up).
local LABEL = { { 0, 60 }, { 30, 45 }, { 60, 0 }, { 30, -45 }, { 0, -60 }, { -30, -45 }, { -60, 0 }, { -30, 45 } }
local RANGE_EVERY = 0.2
local STATE_EVENTS = {
	"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
	"PLAYER_TARGET_CHANGED",
}

local function sound(id) if id then PlaySound(id) end end

local function rad(degrees) return degrees * math.pi / 180 end

-- A texture at atlas size on the centre of parent (UpdateButtonArt anchors every part CENTER).
local function centred(parent, atlas, layer, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetAtlas(atlas, true)
	t:SetPoint("CENTER")
	t:Hide()
	return t
end

---------------------------------------------------------------------------------------------------------------------
-- The wheel: a frame the wheel's size that its pieces, the highlight and the disabled segments are drawn on, about its
-- centre. Slot buttons sit GEO.SLOT_R out from it.

function View.Wheel(parent)
	local wheel = CreateFrame("Frame", nil, parent)
	wheel:SetSize(WHEEL_W, WHEEL_H)
	wheel.pieces, wheel.lit, wheel.slots = {}, {}, {}
	wheel.base = centred(wheel, FLY .. "base", "BACKGROUND", 0)
	wheel.backdrops = {}
	for i = 1, Rings.MAX_SLOTS do wheel.backdrops[i] = centred(wheel, FLY .. "slot-backdrop", "BACKGROUND", 1) end
	wheel.indicator = centred(wheel, "gamepad-flyout-selection-indicator", "BACKGROUND", 2)
	wheel.indicator:SetWidth(INDICATOR_W)
	wheel.arrow = CreateFrame("Frame", nil, wheel)
	wheel.arrow:SetSize(ARROW_W, ARROW_H)
	wheel.arrow.tex = wheel.arrow:CreateTexture(nil, "OVERLAY")
	wheel.arrow.tex:SetAtlas("gamepad-largecursor")
	wheel.arrow.tex:SetAllPoints()
	wheel.arrow:Hide()
	wheel.mods = { glyphs = {}, plus = wheel:CreateTexture(nil, "ARTWORK") }
	wheel.mods.plus:SetAtlas("gamepad-symbols-plus")
	wheel.mods.plus:SetSize(PLUS_SIZE, PLUS_SIZE)
	wheel.mods.plus:Hide()
	return wheel
end

-- A texture on the wheel with its own sector mask about the wheel centre, made on first use.
local function piece(wheel, pool, i, sub)
	local p = pool[i]
	if p then return p end
	p = { tex = wheel:CreateTexture(nil, "OVERLAY", nil, sub), mask = wheel:CreateMaskTexture() }
	p.mask:SetSize(WHEEL_W, WHEEL_W)
	p.mask:SetPoint("CENTER", wheel)
	pool[i] = p
	return p
end

-- The texture keeps only the sector width degrees wide about centre (clockwise from the top), or all of it.
local function sector(p, centre, width)
	if not width then
		if p.masked then p.tex:RemoveMaskTexture(p.mask) end
		p.masked = false
		return
	end
	p.mask:SetTexture(UI.ART .. Rings.SectorFile(width), CLAMP, CLAMP)
	p.mask:SetRotation(rad(-centre))
	if not p.masked then p.tex:AddMaskTexture(p.mask) end
	p.masked = true
end

local function hideFrom(pool, used) for i = used + 1, #pool do pool[i].tex:Hide() end end

-- The wheel for n slots, from Rings.WheelPieces; compact, the flyout's base and n backdrop places instead (drawSlot
-- shows the empty ones).
function View.DrawWheel(wheel, n, style)
	if n == wheel.n and style == wheel.style then return end
	wheel.n, wheel.style = n, style
	hideFrom(wheel.lit, 0)
	wheel.indicator:Hide()
	wheel.arrow:Hide()
	for _, view in ipairs(wheel.slots) do view.fly.over:Hide() end
	wheel.base:SetShown(style == "compact")
	for i, backdrop in ipairs(wheel.backdrops) do
		backdrop:Hide()
		if i <= n then
			local dx, dy = Rings.Dir(n, i)
			backdrop:SetPoint("CENTER", wheel, "CENTER", GEO.COMPACT_R * dx, GEO.COMPACT_R * dy)
		end
	end
	if style == "compact" then return hideFrom(wheel.pieces, 0) end
	local list = Rings.WheelPieces(n)
	for k, spec in ipairs(list) do
		local p = piece(wheel, wheel.pieces, k, -3)
		p.tex:SetAtlas("gamepad-radial-menu-wheelbg", true)
		p.tex:SetPoint("CENTER", wheel)
		p.tex:SetRotation(rad(-spec[1]))
		sector(p, spec[2], spec[3])
		p.tex:Show()
	end
	hideFrom(wheel.pieces, #list)
end

-- The physical buttons that hold a layer's modifiers.
local function modCodes(layer)
	local roles, out = ns.Layout and ns.Layout.Roles() or {}, {}
	for _, role in ipairs(LAYER_ROLES[layer] or {}) do
		for phys, held in pairs(roles) do if held == role then out[#out + 1] = phys end end
	end
	return out
end

-- Compact's middle: icon in the native slot of shape ("circle" | "square"), the layer's modifier glyphs under it; no
-- icon hides both (Full).
function View.DrawCentre(wheel, icon, shape, layer)
	local mods = wheel.mods
	for _, glyph in ipairs(mods.glyphs) do glyph:Hide() end
	mods.plus:Hide()
	if not icon then return wheel.centre and wheel.centre:Hide() end
	wheel.centre = wheel.centre or ns.SlotView.New(wheel)
	local centre = wheel.centre
	centre:SetSize(CENTRE[shape], CENTRE[shape])
	centre:SetPoint("CENTER")
	centre:SetShape(shape)
	centre:SetSlot(nil, icon)
	centre:Show()
	local codes = modCodes(layer)
	local x = -(#codes * MOD_SIZE + (#codes - 1) * (PLUS_SIZE + 2 * MOD_GAP)) / 2
	for i, code in ipairs(codes) do
		if i > 1 then
			mods.plus:SetPoint("LEFT", wheel, "CENTER", x + MOD_GAP, MOD_Y)
			mods.plus:Show()
			x = x + PLUS_SIZE + 2 * MOD_GAP
		end
		local glyph = mods.glyphs[i] or UI.Glyph(wheel, MOD_SIZE)
		mods.glyphs[i] = glyph
		glyph:SetCode(code)
		glyph:ClearAllPoints()
		glyph:SetPoint("LEFT", wheel, "CENTER", x, MOD_Y)
		glyph:Show()
		x = x + MOD_SIZE
	end
end

-- A native segment shape (the highlight or the disabled art, w x h) on slot i of n, from Rings.SegmentPieces: placed
-- HL_R out and turned as GetSegmentRotationAndOffset does.
local function drawSegment(wheel, pool, sub, atlas, w, h, n, i, desaturated)
	local list = Rings.SegmentPieces(n, i)
	for k, spec in ipairs(list) do
		local p, at = piece(wheel, pool, k, sub), spec[1]
		p.tex:SetAtlas(atlas)
		p.tex:SetSize(w, h)
		p.tex:ClearAllPoints()
		p.tex:SetPoint("CENTER", wheel, "CENTER", HL_R * math.sin(rad(at)), HL_R * math.cos(rad(at)))
		p.tex:SetRotation(rad(-180 - at))
		p.tex:SetDesaturated(desaturated)
		sector(p, spec[2], spec[3])
		p.tex:Show()
	end
	hideFrom(pool, #list)
end

local function hideSegment(pool) hideFrom(pool, 0) end

-- The native highlight on slot i of n (desaturated when it can't fire), or none without i. Compact: the flyout's
-- UpdateSelectionIndicators and SetSelection for slot i at theta.
function View.Highlight(wheel, n, i, desaturated)
	if wheel.style == "compact" then
		local view = i and wheel.slots[i]
		local filled = view and view.file ~= nil
		for k, other in ipairs(wheel.slots) do other.fly.over:SetShown(k == i and filled) end
		wheel.indicator:SetShown(i ~= nil)
		wheel.arrow:SetShown(filled)
		if not i then return end
		local theta = rad((i - 1) * 360 / n)
		wheel.indicator:SetRotation(math.pi - theta)
		wheel.indicator:SetDesaturated(not filled or desaturated)
		wheel.arrow:ClearAllPoints()
		wheel.arrow:SetPoint("CENTER", wheel, "CENTER", ARROW_R * math.sin(theta), ARROW_R * math.cos(theta))
		wheel.arrow:SetFrameLevel(wheel:GetFrameLevel() + 6)
		return wheel.arrow.tex:SetRotation(math.pi / 2 - theta)
	end
	if not i then return hideSegment(wheel.lit) end
	drawSegment(wheel, wheel.lit, -2, "gamepad-radial-menu-selected", HL_W, HL_H, n, i, desaturated)
end

-- The label's offset from its icon at theta degrees: textAnchorData, between its 45-degree points linearly.
local function labelOffset(theta)
	local f = (theta % 360) / SEG
	local k = math.floor(f)
	local a, b, t = LABEL[k % 8 + 1], LABEL[(k + 1) % 8 + 1], f - k
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
end

-- The action name only: rank text is the label's to drop.
local function labelText(name) return (tostring(name or ""):gsub("%s*%(Highest Rank%)$", ""):gsub("%s*%(?Rank %d+%)?$", "")) end

---------------------------------------------------------------------------------------------------------------------
-- A slot (GamepadRadialSegmentTemplate's parts) on its secure slot button: the icon square and unmasked, its
-- cooldowns, count and proc glow, the gold label, and the disabled segment on the wheel.

local function newSlot(button, wheel)
	local view = CreateFrame("Frame", nil, button)
	view:SetSize(GEO.ICON, GEO.ICON)
	view:SetPoint("CENTER", button)
	view:EnableMouse(false)
	view.icon = view:CreateTexture(nil, "OVERLAY")
	view.icon:SetAllPoints()
	-- The flyout button's parts: the normal ring (the disabled one when it can't fire), the round icon mask, the
	-- over-border. The view is 38; the icon 36 in compact.
	view.fly = { normal = centred(view, FLY .. "slot-normal", "BACKGROUND", 0), disabled = centred(view, FLY .. "slot-disabled", "BACKGROUND", 0), over = centred(view, FLY .. "slot-over-border", "OVERLAY", 1) }
	view.fly.mask = view:CreateMaskTexture()
	view.fly.mask:SetAtlas(FLY .. "slot-mask", true)
	view.fly.mask:SetPoint("CENTER")
	wheel.slots[#wheel.slots + 1] = view
	view.index = #wheel.slots
	local cooldown = CreateFrame("Cooldown", nil, view, "CooldownFrameTemplate")
	cooldown:SetDrawBling(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetSwipeColor(0, 0, 0, 0.8)
	local loc = CreateFrame("Cooldown", nil, view, "CooldownFrameTemplate")
	loc:SetDrawBling(false)
	loc:SetHideCountdownNumbers(true)
	loc:SetSwipeColor(0.17, 0, 0, 0.8)
	local charge = CreateFrame("Cooldown", nil, view, "CooldownFrameTemplate")
	charge:SetDrawSwipe(false)
	charge:SetHideCountdownNumbers(true)
	for _, cd in ipairs({ cooldown, loc, charge }) do cd:SetAllPoints(view.icon) end
	local text = CreateFrame("Frame", nil, view)
	text:SetAllPoints()
	text:SetFrameLevel(view:GetFrameLevel() + 4)
	view.count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	view.count:SetJustifyH("RIGHT")
	view.count:SetPoint("BOTTOMRIGHT", view.icon, "BOTTOMRIGHT", -2, 2)
	view.label = text:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	view.label:SetSize(80, 40)
	view.label:SetJustifyH("CENTER")
	view.label:SetJustifyV("MIDDLE")
	view.label:SetWordWrap(true)
	view.label:SetMaxLines(2)
	view.alert = CreateFrame("Frame", nil, view, "ActionButtonSpellAlertTemplate")
	view.alert:Hide()
	view.cooldown, view.loc, view.charge, view.disabled, view.wheel = cooldown, loc, charge, {}, wheel
	return view
end

-- Range red, then the usable tints, as an action button paints its icon; a slot this character can't fire is grey.
local function paint(view)
	local icon = view.icon
	if view.cant then return icon:SetVertexColor(1, 1, 1) end
	if view.outOfRange then return icon:SetVertexColor(0.8, 0.1, 0.1) end
	if view.usable ~= false then return icon:SetVertexColor(1, 1, 1) end
	if view.noMana then return icon:SetVertexColor(0.5, 0.5, 1) end
	icon:SetVertexColor(0.4, 0.4, 0.4)
end

local function clearStates(view)
	for _, cd in ipairs({ view.cooldown, view.loc, view.charge }) do cd:Clear() end
	view.count:SetText("")
	view.usable, view.noMana, view.outOfRange = nil, nil, nil
	if view.alert:IsShown() then
		view.alert:Hide()
		view.alert.ProcStartAnim:Stop()
	end
end

-- The flyout look on (compact) or off: a filled slot the masked 36 icon on its ring, an empty one its backdrop.
local function setFly(view, compact, filled, inRing)
	local fly, icon = view.fly, view.icon
	local backdrop = view.wheel.backdrops[view.index]
	if backdrop then backdrop:SetShown(compact and inRing and not filled) end
	fly.normal:SetShown(compact and filled and not view.cant)
	fly.disabled:SetShown(compact and filled and view.cant)
	if not compact then fly.over:Hide() end
	icon:ClearAllPoints()
	if compact then icon:SetSize(FLY_ICON, FLY_ICON) end
	if compact then icon:SetPoint("CENTER") else icon:SetAllPoints() end
	if compact == (view.masked or false) then return end
	view.masked = compact
	if compact then icon:AddMaskTexture(fly.mask) else icon:RemoveMaskTexture(fly.mask) end
end

-- Slot i of n in a style: the action's icon and name, or nothing (an empty segment is the bare wedge, an empty compact
-- slot the empty slot art).
local function drawSlot(view, stored, entry, n, i, style)
	view.entry = stored and entry or nil
	clearStates(view)
	local shown, compact = stored ~= nil, style == "compact"
	view.icon:SetShown(shown)
	view.label:SetShown(shown and not compact)
	view.cant = shown and not Rings.Attributes(entry)
	view.file = shown and (entry and entry.icon or stored.icon or QUESTION_ICON) or nil
	setFly(view, compact, shown, i <= n)
	view.cooldown:SetSwipeTexture(compact and ROUND_SWIPE or SQUARE_SWIPE)
	if not shown or compact then hideSegment(view.disabled) end
	if not shown then return end
	local theta = (i - 1) * 360 / n
	view.icon:SetTexture(view.file)
	view.icon:SetDesaturated(view.cant)
	view.label:SetText(labelText(stored.name))
	view.label:SetTextColor((view.cant and DISABLED_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB())
	view.label:ClearAllPoints()
	view.label:SetPoint("CENTER", view.icon, "CENTER", labelOffset(theta))
	view.cooldown:SetHideCountdownNumbers(not (C_CVar and C_CVar.GetCVarBool or GetCVarBool)("countdownForCooldowns"))
	if view.cant and not compact then drawSegment(view.wheel, view.disabled, -1, "gamepad-radial-menu-disabled", HL_W, DISABLED_H, n, i) else hideSegment(view.disabled) end
	paint(view)
end

---------------------------------------------------------------------------------------------------------------------
-- States, as SlotView's LOOK draws them for a slot, from the spell or item itself.

local function setDuration(cooldown, duration)
	if duration then cooldown:SetCooldownFromDurationObject(duration, true) else cooldown:Clear() end
end

local function glow(view, show)
	local alert = view.alert
	if show and not alert:IsShown() then
		local width, height = view.icon:GetSize()
		alert:SetSize(width * 1.4, height * 1.4)
		alert:SetPoint("CENTER", view.icon, "CENTER")
		alert:Show()
		alert.ProcStartAnim:Play()
	elseif not show and alert:IsShown() then
		alert:Hide()
		alert.ProcStartAnim:Stop()
	end
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
	view.usable, view.noMana = C_Spell.IsSpellUsable(id)
	view.count:SetText(C_Spell.GetSpellDisplayCount(id))
	glow(view, C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed(id))
	paint(view)
end
function LOOK.item(view, id)
	local start, duration, enabled = C_Item.GetItemCooldown(id)
	local timer = view.itemTimer or C_DurationUtil.CreateDuration()
	view.itemTimer = timer
	timer:SetTimeFromStart(start or 0, duration or 0)
	setDuration(view.cooldown, enabled and duration and duration > 0 and timer or nil)
	view.loc:Clear()
	view.charge:Clear()
	view.usable, view.noMana = C_Item.IsUsableItem(id)
	view.count:SetText(C_Item.IsConsumableItem(id) and C_Item.GetItemCount(id, false, true) or "")
	glow(view, false)
	paint(view)
end

local RANGE = {}
function RANGE.spell(id)
	if not C_Spell.SpellHasRange(id) then return false end
	return C_Spell.IsSpellInRange(id, "target") == false
end
function RANGE.item(id)
	if not C_Item.ItemHasRange(id) then return false end
	return C_Item.IsItemInRange(id, "target") == false
end

-- One view's states, guarded: in combat a value may be secret, and a failed read leaves that view as drawn.
local function drawStates(view, withRange)
	local kind, id = source(view.entry)
	if not (kind and id) or view.cant then return end
	if not withRange then
		local ok, err = pcall(LOOK[kind], view, id)
		if not ok then ns.debug("ring slot state: %s", tostring(err)) end
		return
	end
	local ok, out = pcall(RANGE[kind], id)
	if not ok or out == view.outOfRange then return end
	view.outOfRange = out
	paint(view)
end

---------------------------------------------------------------------------------------------------------------------
-- In game: the display frame is the wheel, on the ring frame's centre. Aim, draw and the frame's scripts.

local frame = Rings.Frame()
local display = View.Wheel(frame)
display:SetPoint("CENTER", frame, "CENTER")
display:SetFrameLevel(frame:GetFrameLevel() + 1)

local views = {}
local drawn, focused, dirty, rangeIn = {}, nil, false, 0
-- How the ring shown now was opened ("hold" | "touch"): the close clears the frame's ps-mode before the hide.
local openMode

-- The aimed slot (or the finger's): the highlight on its segment (desaturated when it can't fire), the native
-- highlight sound on a held ring.
local function focus(i)
	if i == focused then return end
	focused = i
	local ring = drawn.ring
	local view = i and views[i]
	View.Highlight(display, ring and ring.count, ring and i, view and view.cant or false)
	if i and drawn.mode == "hold" then sound(SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT) end
end

local function draw(id, mode, side, layer, kind)
	local ring = Rings.Get(id)
	drawn = { id = id, mode = mode, side = side, layer = layer, kind = kind, ring = ring }
	openMode = mode
	if not ring then return end
	local n = ring.count
	View.DrawWheel(display, n, ring.style)
	View.DrawCentre(display, ring.style == "compact" and Rings.Icon(ring), kind == "dpad" and "square" or "circle", layer)
	for i = 1, Rings.MAX_SLOTS do
		local view = views[i]
		local stored = i <= n and ring.slots[i] or nil
		if view then drawSlot(view, stored, Rings.Resolve(stored), n, i, ring.style) end
	end
	focused = -1
	focus(nil)
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
	local layer, kind = frame:GetAttribute("ps-layer"), frame:GetAttribute("ps-kind")
	if id ~= drawn.id or mode ~= drawn.mode or side ~= drawn.side or layer ~= drawn.layer or kind ~= drawn.kind then draw(id, mode, side, layer, kind) end
	local ring = drawn.ring
	if not ring then return end
	-- Back in the middle, the pick the stick keys kept (Rings.lua _key) stays lit until it fires; the slot the stick
	-- pointed at as the ring opened (ps-stale) isn't lit while _pick ignores it.
	if mode == "hold" then
		local live = stickSlot(ring.count)
		focus(live ~= frame:GetAttribute("ps-stale") and live or frame:GetAttribute("ps-pick"))
	end
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
		views[i] = newSlot(button, display)
		-- A finger on a touch ring: the slot under it is focused.
		button:SetScript("OnEnter", function() if drawn.mode == "touch" then focus(i) end end)
		button:SetScript("OnLeave", function() if focused == i then focus(nil) end end)
	end
end

init()
ns.On("PLAYER_REGEN_ENABLED", init)
-- An edit while a ring is open (out of combat only) redraws it.
ns.On("FCT_RINGS_CHANGED", function() drawn = {} end)

-- For the specs.
View.LabelOffset, View.LabelText = labelOffset, labelText
View.NewSlot, View.DrawSlot = newSlot, drawSlot
