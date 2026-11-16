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
-- Healer rings (Rings.HealerRing, design/healer-mode.md 2-3): the Compact look with a unit in each of the 7 places
-- instead of an action: round portrait, a radial health ring in the class colour, incoming heals, shield, heal
-- absorbs, a critical pulse, the role and the dispellable debuff; the aimed unit gets the game's own tooltip. Health,
-- absorbs and auras are secret: they go straight into widgets (StatusBar values, texture rotations, alphas and vertex
-- colours), through curves where a shape is needed, never into a comparison or a sum. Only plain answers (does it
-- exist, can it be helped, dead, class, role) steer the look; a secret one counts as unknown.
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
		local view, healer = i and wheel.slots[i], wheel.healer
		-- A healer place counts as filled while its unit can be helped; it has its own aimed border.
		local filled = view and (healer and view.pickable or not healer and view.file ~= nil)
		for k, other in ipairs(wheel.slots) do
			other.fly.over:SetShown(k == i and filled and not healer)
			if other.heal then other.heal.over:SetShown(k == i and filled and healer) end
		end
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
-- A healer place (design/healer-mode.md 3), on its secure slot button, bottom to top: dispel glow, critical glow, slot
-- ring, portrait, health track, health + incoming heals, heal absorbs, shield arc, skull, dispel icon, aimed border,
-- role. Sizes in UI units.

local HEAL = { GLOW = 48, CRIT = 52, SLOT = 56, PORTRAIT = 26, METER = 45, SHIELD = 42, SKULL = 16, DISPEL = 12, OVER = 70, ROLE = 13, RIM = 12 }
local METER_ATLAS = "gamepad-targetingradial-target-meterbg-64"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Dispel type ids 1-4 (GetAuraDispelTypeColor's curve x), their DEBUFF_TYPE_*_COLOR (the client's GlobalColor table)
-- and the raid frames' icons.
local DISPEL = { { "Magic", 0, 129, 255 }, { "Curse", 159, 6, 228 }, { "Disease", 241, 106, 9 }, { "Poison", 123, 199, 0 } }
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }
-- CUF_MY_HEAL_PREDICTION_COLOR, the raid frames' incoming-heal teal; the tooltip bar's green for a unit without a class.
local MY_HEAL, NO_CLASS, HOSTILE = { 11 / 255, 136 / 255, 105 / 255 }, { 0, 1, 0 }, { 1, 0, 0 }
local CRITICAL, DIM, DEAD_SHADE, MISSING_ALPHA, PULSE = 0.3, 0.45, 0.55, 0.5, 0.5
local HEAL_EVERY = 0.5
local HEAL_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_PORTRAIT_UPDATE", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
}

-- A plain value, or nil for a secret one (a restricted unit's class, role or state).
local function plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

-- The curves the secret values go through, made once; false where the client lacks them (no rotation, no pulse, no
-- dispel tint then). rotation: health fraction -> the turn (radians, clockwise) where the health ends; critical: 1
-- under CRITICAL, else 0; glow: dispel type -> its colour, others clear; icons[i]: type i opaque, others clear.
local curves
local function makeCurves()
	local util, kind = C_CurveUtil, Enum.LuaCurveType
	local rotation = util.CreateCurve()
	rotation:SetType(kind.Linear)
	rotation:AddPoint(0, 0)
	rotation:AddPoint(1, -2 * math.pi)
	local critical = util.CreateCurve()
	critical:SetType(kind.Step)
	critical:AddPoint(0, 1)
	critical:AddPoint(CRITICAL, 0)
	local clear, glow, icons = CreateColor(1, 1, 1, 0), util.CreateColorCurve(), {}
	glow:SetType(kind.Step)
	glow:AddPoint(0, clear)
	glow:AddPoint(#DISPEL + 1, clear)
	for i, spec in ipairs(DISPEL) do
		glow:AddPoint(i, CreateColor(spec[2] / 255, spec[3] / 255, spec[4] / 255, 1))
		local icon = util.CreateColorCurve()
		icon:SetType(kind.Step)
		icon:AddPoint(i - 1, clear)
		icon:AddPoint(i, CreateColor(1, 1, 1, 1))
		icon:AddPoint(i + 1, clear)
		icons[i] = icon
	end
	return { rotation = rotation, critical = critical, glow = glow, icons = icons }
end

local function getCurves()
	if curves == nil then
		local ok, made = pcall(makeCurves)
		curves = ok and made or false
		if not ok then ns.debug("healer curves: %s", tostring(made)) end
	end
	return curves
end

-- Incoming heals, clamped to the missing health, from the heal-prediction calculator; false without one.
local calculator
local function getCalculator()
	if calculator == nil then
		local ok, made = pcall(function()
			local calc = CreateUnitHealPredictionCalculator()
			calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
			return calc
		end)
		calculator = ok and made or false
	end
	return calculator
end

local function centredTex(parent, layer, size, atlas, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	if atlas then t:SetAtlas(atlas) end
	return t
end

-- A radial StatusBar size wide, its fill masked to a ring (an atlas, or a file); nil where Radial can't be set: the
-- place then shows the track only.
local function radialBar(parent, size, level, mask, file)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(size, size)
	bar:SetPoint("CENTER")
	bar:SetFrameLevel(level)
	bar:SetStatusBarTexture(WHITE)
	local mode = Enum.StatusBarRenderMode
	if not (mode and pcall(bar.SetRenderMode, bar, mode.Radial)) then
		bar:Hide()
		return
	end
	local m = bar:CreateMaskTexture()
	m:SetAllPoints(bar)
	if file then m:SetTexture(mask, CLAMP, CLAMP) else m:SetAtlas(mask) end
	bar:GetStatusBarTexture():AddMaskTexture(m)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

-- Frames over the slot button, one per depth, so textures and the bars stack in the design's order.
local function healLayer(button, depth)
	local f = CreateFrame("Frame", nil, button)
	f:SetSize(HEAL.OVER, HEAL.OVER)
	f:SetPoint("CENTER")
	f:SetFrameLevel(button:GetFrameLevel() + depth)
	f:EnableMouse(false)
	return f
end

local function newHealer(button)
	local h = { back = healLayer(button, 1), pulse = healLayer(button, 2), mid = healLayer(button, 3), bars = healLayer(button, 4), top = healLayer(button, 9), icons = {} }
	h.glow = centredTex(h.back, "BACKGROUND", HEAL.GLOW, "gamepad-targetingradial-target-selected-glow")
	h.glow:SetDesaturated(true)
	-- Critical: the frame's alpha is the secret 0/1 from the step curve; the texture's own looping animation pulses.
	h.crit = centredTex(h.pulse, "ARTWORK", HEAL.CRIT, "gamepad-targetingradial-target-incombat")
	local group = h.crit:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.25)
	fade:SetToAlpha(1)
	fade:SetDuration(PULSE)
	h.critAnim = group
	h.ring = centredTex(h.mid, "BACKGROUND", HEAL.SLOT, FLY .. "slot-normal")
	h.portrait = centredTex(h.mid, "ARTWORK", HEAL.PORTRAIT)
	h.track = centredTex(h.mid, "OVERLAY", HEAL.METER, METER_ATLAS)
	local level = h.bars:GetFrameLevel()
	h.health = radialBar(h.bars, HEAL.METER, level, METER_ATLAS)
	h.incoming = radialBar(h.bars, HEAL.METER, level + 1, METER_ATLAS)
	h.absorb = radialBar(h.bars, HEAL.METER, level + 2, METER_ATLAS)
	h.shield = radialBar(h.bars, HEAL.SHIELD, level + 3, UI.ART .. "healer-shield-mask.tga", true)
	if h.incoming then h.incoming:SetStatusBarColor(MY_HEAL[1], MY_HEAL[2], MY_HEAL[3]) end
	if h.absorb then
		h.absorb:SetReverseFill(true)
		pcall(h.absorb.SetStatusBarTexture, h.absorb, "raidframe-absorb-fill")
		h.absorb:SetStatusBarColor(1, 1, 1, 0.75)
	end
	if h.shield then pcall(h.shield.SetStatusBarTexture, h.shield, "raidframe-shield-fill") end
	h.skull = centredTex(h.top, "ARTWORK", HEAL.SKULL)
	h.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	for i, spec in ipairs(DISPEL) do
		local icon = centredTex(h.top, "ARTWORK", HEAL.DISPEL, "RaidFrame-Icon-Debuff" .. spec[1], 1)
		icon:SetPoint("CENTER", HEAL.RIM, -HEAL.RIM)
		h.icons[i] = icon
	end
	h.over = centredTex(h.top, "OVERLAY", HEAL.OVER, FLY .. "slot-over-border")
	h.over:Hide()
	h.role = centredTex(h.top, "OVERLAY", HEAL.ROLE, nil, 1)
	h.role:SetPoint("CENTER", -HEAL.RIM, HEAL.RIM)
	h.frames = { h.back, h.pulse, h.mid, h.bars, h.top }
	return h
end

local function showHealer(h, shown)
	for _, f in ipairs(h.frames) do f:SetShown(shown) end
	if shown then h.critAnim:Play() else h.critAnim:Stop() end
end

-- The dispellable debuff (the first one the player can dispel) tints the glow and shows its type's icon. Aura reads
-- need unit aura access: a failed one leaves the place without a tint.
local function drawDispel(h, unit, c)
	local auras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|RAID", 1)
	local aura = auras and auras[1]
	h.glow:SetShown(aura ~= nil)
	for _, icon in ipairs(h.icons) do icon:SetShown(aura ~= nil) end
	if not aura then return end
	local id, get = aura.auraInstanceID, C_UnitAuras.GetAuraDispelTypeColor
	h.glow:SetVertexColor(get(unit, id, c.glow):GetRGBA())
	for i, icon in ipairs(h.icons) do icon:SetVertexColor(get(unit, id, c.icons[i]):GetRGBA()) end
end

-- One place for its unit now. Returns whether the unit can be helped (the secure pick's own test).
local function drawHealer(h, unit, backdrop)
	local exists = plain(UnitExists(unit))
	backdrop:SetAlpha(MISSING_ALPHA)
	backdrop:SetShown(not exists)
	showHealer(h, not not exists)
	if not exists then return false end

	local pickable = not not plain(UnitCanAssist("player", unit))
	local dead = not not plain(UnitIsDeadOrGhost(unit))
	local _, class = UnitClass(unit)
	class = plain(class)
	local color = not pickable and HOSTILE or class and RAID_CLASS_COLORS[class] or NO_CLASS
	local dim = pickable and 1 or DIM
	h.ring:SetAtlas(FLY .. (pickable and "slot-normal" or "slot-disabled"))
	SetPortraitTexture(h.portrait, unit)
	h.portrait:SetDesaturated(dead)
	h.portrait:SetVertexColor(dead and DEAD_SHADE or 1, dead and DEAD_SHADE or 1, dead and DEAD_SHADE or 1)
	h.skull:SetShown(dead)
	for _, f in ipairs({ h.portrait, h.track, h.bars }) do f:SetAlpha(dim) end
	local role = ROLE_ATLAS[plain(UnitGroupRolesAssigned(unit)) or ""]
	h.role:SetShown(role ~= nil)
	if role then h.role:SetAtlas(role) end
	h.role:SetAlpha(dim)

	local c, calc, max = getCurves(), getCalculator(), UnitHealthMax(unit)
	if h.health then
		h.health:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3])
		h.health:SetMinMaxValues(0, max)
		h.health:SetValue(UnitHealth(unit))
	end
	-- The rotation is secret: never tested, only passed on. Whether there is one follows from the curves.
	local turn = c and UnitHealthPercent(unit, true, c.rotation)
	for _, bar in ipairs({ h.incoming, h.absorb }) do
		bar:SetShown(not dead and not not c)
		bar:SetMinMaxValues(0, max)
		if c then bar:GetStatusBarTexture():SetRotation(turn) end
	end
	if h.incoming and calc and c then
		UnitGetDetailedHealPrediction(unit, "player", calc)
		h.incoming:SetValue((calc:GetIncomingHeals()))
	end
	if h.absorb and c then h.absorb:SetValue(UnitGetTotalHealAbsorbs(unit)) end
	if h.shield then
		h.shield:SetShown(not dead)
		h.shield:SetMinMaxValues(0, max)
		h.shield:SetValue(UnitGetTotalAbsorbs(unit))
	end
	h.pulse:SetShown(c and pickable and not dead)
	if c then h.pulse:SetAlpha(UnitHealthPercent(unit, true, c.critical)) end

	local ok = c and pickable and pcall(drawDispel, h, unit, c)
	if ok then return pickable end
	h.glow:Hide()
	for _, icon in ipairs(h.icons) do icon:Hide() end
	return pickable
end

---------------------------------------------------------------------------------------------------------------------
-- In game: the display frame is the wheel, on the ring frame's centre. Aim, draw and the frame's scripts.

local frame = Rings.Frame()
local display = View.Wheel(frame)
display:SetPoint("CENTER", frame, "CENTER")
display:SetFrameLevel(frame:GetFrameLevel() + 1)

local views = {}
local drawn, focused, dirty, rangeIn = {}, nil, false, 0
-- A healer ring: its places are redrawn when one of their events came (healDirty) and every HEAL_EVERY anyway.
local healDirty, healIn = false, 0
local healEvents = CreateFrame("Frame")
healEvents:SetScript("OnEvent", function() healDirty = true end)

local function listenHealer(on)
	for _, event in ipairs(HEAL_EVENTS) do
		if on then pcall(healEvents.RegisterEvent, healEvents, event) else healEvents:UnregisterEvent(event) end
	end
end

-- The aimed unit's own game tooltip, at the default place; hidden when nothing (or no one) is aimed. GameTooltip is
-- shared with Blizzard's secure code, so it is touched only while a healer ring shows one.
local tipUnit
local function healerTip(i)
	local unit = i and Rings.HealerUnits[i]
	if unit and plain(UnitExists(unit)) then
		GameTooltip_SetDefaultAnchor(GameTooltip, display)
		GameTooltip:SetUnit(unit)
		tipUnit = unit
	elseif tipUnit then
		tipUnit = nil
		if GameTooltip:IsOwned(display) then GameTooltip:Hide() end
	end
end

local function drawHealers()
	local ring = drawn.ring
	for i = 1, ring.count do
		local view = views[i]
		if view then view.pickable = drawHealer(view.heal, Rings.HealerUnits[i], display.backdrops[i]) end
	end
	if focused and focused > 0 then View.Highlight(display, ring.count, focused, false) end
end
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
	if ring and ring.healer then healerTip(i) end
end

local function draw(id, mode, side, layer, kind)
	local ring = id and (Rings.Get(id) or Rings.Healer(id))
	drawn = { id = id, mode = mode, side = side, layer = layer, kind = kind, ring = ring }
	openMode = mode
	local healer = ring and ring.healer
	display.healer = healer
	listenHealer(healer)
	for _, view in ipairs(views) do
		view.pickable = nil
		showHealer(view.heal, false)
	end
	if not ring then return end
	local n = ring.count
	View.DrawWheel(display, n, ring.style)
	View.DrawCentre(display, ring.style == "compact" and Rings.Icon(ring), kind == "dpad" and "square" or "circle", layer)
	for i = 1, Rings.MAX_SLOTS do
		local view = views[i]
		-- A healer place shows its unit, not the action every place fires.
		local stored = not healer and i <= n and ring.slots[i] or nil
		if view then drawSlot(view, stored, Rings.Resolve(stored), n, i, ring.style) end
	end
	for _, backdrop in ipairs(display.backdrops) do backdrop:SetAlpha(1) end
	focused = -1
	focus(nil)
	dirty, rangeIn, healIn = true, 0, 0
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
	healerTip(nil)
	display.healer = nil
	listenHealer(false)
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
	if ring.healer then
		healIn = healIn - elapsed
		if healDirty or healIn <= 0 then
			healDirty, healIn = false, HEAL_EVERY
			drawHealers()
		end
		return
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
		views[i].heal = newHealer(button)
		showHealer(views[i].heal, false)
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
