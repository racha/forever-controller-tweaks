-- Forever Controller Tweaks glyph overlay: shows the physical button wherever Blizzard hard-codes a native one.
--
-- Blizzard's crossbar modifier glyphs, class-action prompts and persistent legend name the native keys (L2/R2 under
-- the bars, L1/R1 in the legend). After a remap another physical button outputs that key, so the addon draws that
-- button's glyph on its own frame over Blizzard's: a UIParent child anchored to the Blizzard glyph, with its size,
-- scale, alpha and texture state. The atlas comes from InputIconTextureSetUtility (a pure lookup); the
-- InputIconTexture template is not used because its OnLoad registers with InputDeviceIconSetManager
-- (InputIconTexture.lua:644-647). Moved first-page face actions get their SpecialActionIcon (or the catalog entry's
-- icon) mirrored at the slot they now live on, pressed in when their own button is; an entry routed on any face or
-- D-pad cell of any layer (Face.CellEntry) gets its icon on that cell with a native slot's look, read from the shadow
-- action slot Face.lua places it in (Face.Slot). Every mirror is a SlotView (SlotView.lua: native slot art, states and
-- press). Clicks and hover go to Face.lua's catcher (Face.Catcher); the mirror keeps the mouse off. A mirrored slot's
-- prompt is redrawn on top.
-- Hiding the native glyph: SetAlpha(0) on its five state textures (Normal, Hover, Pressed,
-- Active, Disabled), the only kind of write to Blizzard objects. It is safe here because it touches no Lua field or table,
-- only texture regions of the non-protected icon frames (PageUnit.ModifierIcons, the class-action prompts, the
-- legend entries' InputIcon1/2), never their bars, buttons, PageUnit or the legend. The icon frame itself keeps its
-- alpha, so the crossbar focus FX Blizzard parents to it (ActionBarFocusFX.lua animatedGlowTop/animatedGlowBottom)
-- still play there, under and over our glyph. Each texture's alpha is saved before the first hide and put back when
-- the glyph leaves the overlay; while hidden it is re-asserted every frame. `/fct glyphhide overlay` (debug)
-- keeps the fallback: our glyph on top, the native one untouched.
-- The same write, under the same rules, goes to the shoulder tab textures (below) and to a mirrored slot's own
-- texture regions (every one but the alpha-animated focus FX, SLOT_FX), only while a mirror stands on that slot, so
-- a pressed-in mirror shows no native ring around it. A mirrored slot's prompt (its five state textures) too.
-- And to a crossbar slot's macro-name FontString (Name) while that slot holds a registered game macro of ours, so
-- "FCT:Bags" never shows as text on the button; the player's own macros keep their names.
-- Targeting shoulder markers: Blizzard's friendly / hostile tabs (PageUnit.Left/RightShoulderBackground, Icon,
-- Highlight) sit at L1 / R1. When the layout moves those roles, the native tabs go to alpha 0 (texture regions only,
-- as above) and ours show the side of the button that holds each role. Both roles on one side become one split tab in
-- the same 50x45 footprint and place: trigger role on top, bumper role below (the order the buttons sit in), a paddle
-- under either. Overlay mode draws ours over the native tabs and writes nothing.
-- Any error stops the overlay: everything is put back to native and one chat line says so.
local _, ns = ...
local Glyphs = {}
ns.Glyphs = Glyphs

local Layout = ns.Layout
local POLL = 0.1
-- Alpha mode: our content frame (one level above the overlay) lands on the native icon's level, so Blizzard's glows
-- layer around it as around the native glyph. Overlay mode: above the native glyph and its child frames.
local ALPHA_LEVEL, OVERLAY_LEVEL, MIRROR_LEVEL = -1, 5, 1
local GLYPH_TEXTURES = { "NormalTexture", "HoverTexture", "PressedTexture", "ActiveTexture", "DisabledTexture" }
-- InputIconTextureState's values (local to InputIconTexture.lua); the atlas table is indexed by them.
local NORMAL_STATE, PRESSED_STATE, ACTIVE_STATE, DISABLED_STATE = 1, 3, 4, 5
-- The newer 76x75 prompt atlases carry padding; InputIconTexture widens them by 5 pixels per side the same way.
local LARGE_PROMPT_W, LARGE_PROMPT_H, LARGE_PROMPT_PAD = 76, 75, 5
-- No glyph set has paddles, so a paddle is GameFontNormal "P1" over the footer prompt slot frame.
local PADDLE_FRAME, PADDLE_FRAME_LIT = "gamepad-footer-slot-frameneutral", "gamepad-footer-slot-framefocused"
-- topBar.Right.ActionButtonN that owns each reserved action (GamepadMainActionBarFrame.lua:420-620).
local ACTION_BUTTON = { interact = 1, inspect = 2, back = 3, jump = 4 }
-- ResolveNonBindableInteract's cursor units, in its order; used only when the Interact icon can't be copied.
local CURSOR_UNITS, NO_UNITS = { "softinteract", "target" }, {}
-- The Inspect slot's clear-marker ring (MainActionBarFrame.lua SetupNonBindableInspect clearOverlay).
local CLEAR_OVERLAY_ATLAS = "gamepad-actionbar-circleslot-permabound"
local CLAMP = "CLAMPTOBLACKADDITIVE"
-- Which side of the pad each button sits on, and its row order in a split tab (trigger above bumper above paddles).
-- ponytail: paddle sides assume SDL's Elite order (P1/P3 right, P2/P4 left), unverified without paddle hardware.
local SIDE = { L1 = "Left", L2 = "Left", R1 = "Right", R2 = "Right", P1 = "Right", P2 = "Left", P3 = "Right", P4 = "Left" }
local STACK = { L2 = 1, R2 = 1, L1 = 2, R1 = 2, P1 = 3, P2 = 3, P3 = 4, P4 = 4 }
local SIDES = { "Left", "Right" }
local TAB = {}
for _, side in ipairs(SIDES) do
	local lower = side:lower()
	TAB[side] = {
		bg = side .. "ShoulderBackground", icon = side .. "ShoulderIcon", highlight = side .. "ShoulderHighlight",
		bgAtlas = "gamepad-targeting-" .. lower .. "-shoulder-bg", pressedAtlas = "gamepad-targeting-" .. lower .. "-shoulder-pressed",
	}
end
local ROLE_ICON = { friendly = "gamepad-targeting-friendly", hostile = "gamepad-targeting-hostile" }
local FRIENDLY_HOSTILE, HOSTILE_FRIENDLY, FRIENDLY, HOSTILE = { "friendly", "hostile" }, { "hostile", "friendly" }, { "friendly" }, { "hostile" }
-- Split tab geometry in the native 50x45 tab, y down: each half 22.5 tall, crosshair (50x45 art) at 0.55 centred on
-- y 15 / 30.5, pressed wash 42x15.5 from y 7 / 22.5, a 36x1 divider at (7, 22).
local TAB_W, TAB_H, HALF_H, CROSS_SCALE = 50, 45, 22.5, 0.55
local HALVES = { { cy = 15, washY = 7 }, { cy = 30.5, washY = 22.5 } }
-- Face.lua's cells: each code's key, the bar that draws each layer (T base, L/R one modifier, B both), and how many
-- router keys the header carries (ps-key1..n).
local CELL_KEY = { FB = "PAD1", FR = "PAD2", FL = "PAD3", FT = "PAD4", DU = "PADDUP", DL = "PADDLEFT", DR = "PADDRIGHT", DD = "PADDDOWN" }
local CELL_BARS = { T = "topBar", L = "leftBar", R = "rightBar", B = "bottomBar" }
local ROUTER_KEYS = 8
local routedKeys = {}
local FACE_POS = {}
for pos, key in pairs(Layout.FACE_KEY) do FACE_POS[key] = pos end
-- Slot FX Blizzard animates by alpha (ActionBarButton.xml focus anims, ActionButtonTemplate.xml SpellHighlightAnim):
-- never written, so an animation can't leave them at a value we would later overwrite.
local SLOT_FX = { "CircleShadowFocus", "SquareShadowFocus", "CircleGlowFocus", "SquareGlowFocus", "SpellHighlightTexture" }
local overlays = setmetatable({}, { __mode = "k" }) -- Blizzard glyph -> our overlay
local entryOf = setmetatable({}, { __mode = "k" }) -- Blizzard glyph -> what we draw over it (reused table)
local wanted = setmetatable({}, { __mode = "k" }) -- Blizzard glyph -> true while drawn over (or hidden)
local hidden = setmetatable({}, { __mode = "k" }) -- Blizzard glyphs whose textures we hid
local saved = setmetatable({}, { __mode = "k" }) -- Blizzard texture -> its alpha before we hid it
local clearOverlays = setmetatable({}, { __mode = "k" }) -- Inspect button -> its clear-marker ring texture
local slotRegions = setmetatable({}, { __mode = "k" }) -- mirrored slot button -> its texture regions we may hide
local slotsHidden = setmetatable({}, { __mode = "k" }) -- slot buttons whose textures we hid
local slotsNow = {}
local icons, mirrors, faces, markers, markerPlan = {}, {}, {}, {}, { rows = {} }
local failed, lastSummary, lastIconSet, markersHidden, driver
-- Blizzard face-action buttons our router is pressing this frame: Blizzard moves them (ApplyPressedStyle).
local nativePressed = {}
-- Crossbar slots holding one of our game macros: the action each one was last judged on, whether it is ours, and the
-- slots whose Name we hid. namesDirty re-judges every slot (macro or slot changes).
local MACRO_PREFIX = "FCT:"
local nameAction, nameOurs, namesNow = {}, {}, {}
local namesHidden = setmetatable({}, { __mode = "k" })
local namesDirty = true

local function hideMode() return ns.db.options.glyphHide == "overlay" and "overlay" or "alpha" end

local function hideTexture(texture)
	if not texture then return end
	if saved[texture] == nil then saved[texture] = texture:GetAlpha() end
	texture:SetAlpha(0)
end

local function showTexture(texture)
	local alpha = texture and saved[texture]
	if alpha == nil then return end

	texture:SetAlpha(alpha)
	saved[texture] = nil
end

-- A mirrored slot's own art: every texture region of the button but the animated FX. Child frames (prompt,
-- cooldowns, proc glow) are not regions and stay untouched.
local function regionsOf(button)
	local list = slotRegions[button]
	if list then return list end

	local skip = {}
	for _, key in ipairs(SLOT_FX) do
		if button[key] then skip[button[key]] = true end
	end
	list = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not skip[region] then list[#list + 1] = region end
	end
	slotRegions[button] = list
	return list
end

local function restoreSlot(button)
	for _, region in ipairs(regionsOf(button)) do showTexture(region) end
	slotsHidden[button] = nil
end

local function restore(native)
	if not hidden[native] then return end

	for _, key in ipairs(GLYPH_TEXTURES) do showTexture(native[key]) end
	hidden[native] = nil
end

local function pageUnit() return GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit end

local function hideMarkerTabs(unit)
	for _, side in ipairs(SIDES) do
		local tab = TAB[side]
		hideTexture(unit[tab.bg])
		hideTexture(unit[tab.icon])
		hideTexture(unit[tab.highlight])
	end
	markersHidden = unit
end

local function restoreMarkers()
	local unit = markersHidden
	if not unit then return end

	for _, side in ipairs(SIDES) do
		local tab = TAB[side]
		showTexture(unit[tab.bg])
		showTexture(unit[tab.icon])
		showTexture(unit[tab.highlight])
	end
	markersHidden = nil
end

-- Everything back to native: every texture we hid, every frame we drew.
local function restoreAll()
	for native in pairs(hidden) do restore(native) end
	restoreMarkers()
	for texture in pairs(saved) do showTexture(texture) end
	wipe(slotsHidden)
	wipe(namesHidden)
	namesDirty = true
	for _, overlay in pairs(overlays) do overlay:Hide() end
	for _, mirror in pairs(mirrors) do mirror:Hide() end
	for _, marker in pairs(markers) do marker:Hide() end
	wipe(wanted)
	wipe(faces)
	markerPlan.on = false
end

local function addIcon(icon)
	if icon and icon.mappedButtonKey then icons[#icons + 1] = icon end
end

local function addPrompt(prompt)
	for _, icon in ipairs(prompt and prompt.InputIcons or {}) do addIcon(icon) end
end

-- Every Blizzard glyph that can name a remapped key: the modifier glyphs, the class-action prompts (L1+L2 / R1+R2)
-- and the legend. Per-button prompts only name face and D-pad keys, which the addon never moves.
local function collect()
	wipe(icons)
	local unit = pageUnit()
	if unit then
		addIcon(unit.LeftIcon)
		addIcon(unit.RightIcon)
		addPrompt(unit.CenteredIcons)
		addPrompt(unit.LeftInputPrompt)
		addPrompt(unit.RightInputPrompt)
	end

	local legend = GamepadPersistentInputLegend
	for _, group in pairs(legend and legend.groups or {}) do
		for _, frame in ipairs(group) do addPrompt(frame) end
	end
end

-- Fills entry with what to draw over native: the physical button now outputting its key. Returns false when
-- Blizzard's glyph is right.
local function fillEntry(entry, native)
	local from = native.mappedButtonKey
	local key, name = Layout.PhysicalFor(from)
	entry.from, entry.key, entry.name, entry.keep, entry.face = from, key, name, nil, nil
	if not key or key == from then return false end

	local textures = InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key)
	entry.atlas = not not (textures and textures[NORMAL_STATE])
	return true
end

local function active()
	local db, device = ns.db, ns.Device
	if failed or not (db and db.options.glyphs and ns.Active()) or ns.panelOpen then return false end
	return not (device and device.Detecting and device.Detecting())
end

-- The tabs to draw instead of Blizzard's, in markerPlan (on = false when Blizzard's are right).
local function planMarkers()
	markerPlan.on = false
	local rows = markerPlan.rows
	rows.Left, rows.Right = nil, nil
	if ns.Remap.State() ~= "ours" then return end

	local swap = ns.Device.SwapTargets()
	local _, friendly = Layout.PhysicalFor(Layout.RoleKey("friendly", swap))
	local _, hostile = Layout.PhysicalFor(Layout.RoleKey("hostile", swap))
	local friendlySide, hostileSide = SIDE[friendly], SIDE[hostile]
	if not (friendlySide and hostileSide) then return end
	if friendlySide ~= hostileSide and friendlySide == (swap and "Right" or "Left") then return end

	markerPlan.on, markerPlan.swap = true, swap
	if friendlySide ~= hostileSide then
		rows[friendlySide], rows[hostileSide] = FRIENDLY, HOSTILE
		return
	end
	rows[friendlySide] = STACK[friendly] <= STACK[hostile] and FRIENDLY_HOSTILE or HOSTILE_FRIENDLY
end

local function faceRouted()
	local header = ForeverControllerTweaksFaceHeader
	return header and header:GetAttribute("state-face") == "routed" and header:GetAttribute("ps-enabled") and header
end

local function cellEntry(code, layer) return ns.Face and ns.Face.CellEntry and ns.Face.CellEntry(code, layer) end

-- True while the face layout or a routed entry differs from native, so the router may route.
local function faceCustom()
	local face = Layout.Face()
	for _, pos in ipairs(Layout.FACE_POSITIONS) do
		if face[pos] ~= Layout.NATIVE_FACE[pos] then return true end
	end
	for code in pairs(CELL_KEY) do
		for layer in pairs(CELL_BARS) do
			if cellEntry(code, layer) then return true end
		end
	end
	return false
end

-- The slot in a bar group whose prompt is the key: the slot Blizzard draws for that physical button.
local function slotFor(group, key)
	for index = 1, 4 do
		local button = group and group["ActionButton" .. index]
		if button and button.ButtonIcon and button.ButtonIcon.mappedButtonKey == key then return button end
	end
end

local function cellFor(bar, key) return bar and (slotFor(bar.Left, key) or slotFor(bar.Right, key)) end

local function clearOverlayOf(button)
	local found = clearOverlays[button]
	if found ~= nil then return found or nil end

	found = false
	for i = 1, select("#", button:GetRegions()) do
		local region = select(i, button:GetRegions())
		if region ~= button.PermaboundOverlay and region.GetAtlas and region:GetAtlas() == CLEAR_OVERLAY_ATLAS then found = region end
	end
	clearOverlays[button] = found
	return found or nil
end

local function newOverlay()
	local overlay = CreateFrame("Frame", nil, UIParent)
	overlay:Hide()
	local content = CreateFrame("Frame", nil, overlay)
	content:SetAllPoints()
	local icon = content:CreateTexture(nil, "ARTWORK")
	local paddle = content:CreateTexture(nil, "ARTWORK")
	paddle:SetAllPoints()
	paddle:SetAtlas(PADDLE_FRAME)
	local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	overlay.icon, overlay.paddle, overlay.label = icon, paddle, label
	return overlay
end

-- A SlotView on UIParent, plus the clear-marker ring a moved Inspect brings along.
local function newMirror()
	local mirror = ns.SlotView.New(UIParent)
	mirror:Hide()
	mirror.clear = mirror.body:CreateTexture(nil, "ARTWORK", nil, 1)
	return mirror
end

local function newMarker()
	local marker = CreateFrame("Frame", nil, UIParent)
	marker:Hide()
	local bg = marker:CreateTexture(nil, "BACKGROUND", nil, -2)
	bg:SetAllPoints()
	local divider = marker:CreateTexture(nil, "BACKGROUND", nil, -1)
	divider:SetColorTexture(0, 0, 0, 0.75)
	divider:SetPoint("TOPLEFT", 7, -22)
	divider:SetSize(36, 1)
	-- Split rows draw only inside the tab's own shape: the background atlas masks them.
	local mask = marker:CreateMaskTexture()
	mask:SetAllPoints()
	marker.bg, marker.divider, marker.rows, marker.mask = bg, divider, {}, mask
	for i = 1, 2 do
		local wash = marker:CreateTexture(nil, "BACKGROUND")
		wash:SetColorTexture(1, 1, 1, 0.12)
		marker.rows[i] = { wash = wash, icon = marker:CreateTexture(nil, "ARTWORK"), pressed = marker:CreateTexture(nil, "OVERLAY"), crop = {} }
	end
	return marker
end

-- SetAtlas only when it changes; returns true when it did (so a crop can be re-applied).
local function setAtlas(texture, atlas)
	if texture.psAtlas == atlas then return false end

	texture.psAtlas = atlas
	texture:SetAtlas(atlas)
	return true
end

local function wantMirror(id, target, source, action, catalog, code, layer)
	local mirrorFace = faces[id] or {}
	faces[id] = mirrorFace
	mirrorFace.target, mirrorFace.source, mirrorFace.action, mirrorFace.catalog, mirrorFace.seen = target, source, action, catalog, true
	mirrorFace.code, mirrorFace.layer, mirrorFace.id = code, layer, id
	mirrorFace.slot = catalog and ns.Face and ns.Face.Slot and ns.Face.Slot(code, layer) or nil
	mirrors[id] = mirrors[id] or newMirror()
	-- The mirror covers the slot's prompt, so the prompt is drawn again on top.
	local prompt = target.ButtonIcon
	if not prompt then return end

	local entry = entryOf[prompt] or {}
	entryOf[prompt] = entry
	entry.from, entry.key, entry.name, entry.atlas, entry.keep, entry.face = prompt.mappedButtonKey, prompt.mappedButtonKey, nil, true, true, mirrorFace
	wanted[prompt] = true
	overlays[prompt] = overlays[prompt] or newOverlay()
end

local function poll()
	local manager = InputDeviceIconSetManager
	local iconSet = manager and manager.GetActiveInputDeviceIconSet and manager:GetActiveInputDeviceIconSet()
	if iconSet ~= lastIconSet then
		lastIconSet = iconSet
		for _, overlay in pairs(overlays) do overlay.atlas = nil end
	end

	wipe(wanted)
	local on = active()
	if on and ns.Remap.State() == "ours" then
		for _, native in ipairs(icons) do
			local entry = entryOf[native]
			if not entry then
				entry = {}
				entryOf[native] = entry
			end
			if fillEntry(entry, native) then
				wanted[native] = true
				overlays[native] = overlays[native] or newOverlay()
			end
		end
	end

	-- Mirrors follow the face router itself: it is off in vehicles, override bars and while the panel is open.
	local unit, header = pageUnit(), on and faceRouted()
	local actionBars = header and unit and unit.actionBars
	local right = actionBars and actionBars.topBar and actionBars.topBar.Right
	local face = right and Layout.Face()
	wipe(routedKeys)
	for i = 1, ROUTER_KEYS do
		local key = right and header:GetAttribute("ps-key" .. i)
		if key then routedKeys[key] = true end
	end
	-- Each routed cell: a moved base face action, or an entry on any layer. A face action entry ("face:jump") is run
	-- by clicking that action's top-bar button, so it mirrors that button like a moved face action.
	for code, key in pairs(CELL_KEY) do
		local pos = FACE_POS[key]
		for layer, barKey in pairs(CELL_BARS) do
			local entry = routedKeys[key] and cellEntry(code, layer)
			local action = entry and tostring(entry.id):match("^face:(%a+)$")
			if not entry and routedKeys[key] and layer == "T" and pos and face[pos] ~= Layout.NATIVE_FACE[pos] then action = face[pos] end
			local source = action and ACTION_BUTTON[action] and right["ActionButton" .. ACTION_BUTTON[action]]
			local target = (source or entry) and cellFor(actionBars[barKey], key)
			if target then wantMirror(code .. "/" .. layer, target, source, action, not source and entry, code, layer) end
		end
	end
	for id, mirrorFace in pairs(faces) do
		if mirrorFace.seen then mirrorFace.seen = nil else faces[id] = nil end
	end

	if on then planMarkers() else markerPlan.on = false end
	if markerPlan.on then
		for _, side in ipairs(SIDES) do
			if markerPlan.rows[side] then markers[side] = markers[side] or newMarker() end
		end
	end

	-- Idle when nothing can be wanted until an event says otherwise (refresh wakes it).
	local busy = next(wanted) or next(faces) or markerPlan.on or on and (ns.Remap.State() == "ours" or faceCustom())
	if driver then driver:SetShown(not not busy) end

	if not ns.db.options.debug then return end
	local parts = {}
	for native in pairs(wanted) do
		local entry = entryOf[native]
		if not entry.keep then parts[#parts + 1] = string.format("%s %s->%s", native:GetDebugName(), entry.from, entry.name or entry.key) end
	end
	for id, mirrorFace in pairs(faces) do
		parts[#parts + 1] = id .. "=" .. tostring(mirrorFace.catalog and mirrorFace.catalog.name or mirrorFace.action)
	end
	for _, side in ipairs(SIDES) do
		local rows = markerPlan.on and markerPlan.rows[side]
		if rows then parts[#parts + 1] = "marker " .. side .. "=" .. table.concat(rows, "/") end
	end
	table.sort(parts)
	local summary = #parts > 0 and table.concat(parts, "; ") or "none"
	if summary ~= lastSummary then ns.debug("glyphs: %s", summary) end
	lastSummary = summary
end

local function alphaOver(alpha)
	local base = UIParent:GetEffectiveAlpha()
	return base > 0 and alpha / base or 0
end

-- Our frames sit on UIParent, so placement, scale, alpha and layering are copied from the Blizzard frame.
-- ref is the frame that owns target's scale and layering, for a texture target.
local function follow(frame, target, alpha, level, ref)
	ref = ref or target
	frame:SetScale(ref:GetEffectiveScale() / UIParent:GetEffectiveScale())
	frame:SetSize(target:GetSize())
	frame:SetAlpha(alphaOver(alpha))
	if frame.target ~= target then
		frame.target = target
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", target)
		frame:SetFrameStrata(ref:GetFrameStrata())
	end
	frame:SetFrameLevel(math.max(0, ref:GetFrameLevel() + level))
	frame:Show()
end

-- What was last copied onto one of our textures (one table per texture, reused): the copies below run every frame
-- but write only what changed. gen is the view's generation (SlotView): it rewrote these regions since.
local function lastCopy(to, key, gen)
	local last = to[key]
	if not last then
		last = {}
		to[key] = last
	end
	if last.gen ~= gen then
		wipe(last)
		last.gen = gen
	end
	return last
end

-- Copies anchors given relative to the region's own button onto ours relative to the mirror.
local function copyPoints(from, to, frame, gen)
	local last = lastCopy(to, "psPoints", gen)
	local count = from and from:GetNumPoints() or -1
	local same = last.from == from and last.frame == frame and last.count == count
	for i = 1, count do
		local point, _, relativePoint, x, y = from:GetPoint(i)
		local k = i * 4
		same = same and last[k - 3] == point and last[k - 2] == relativePoint and last[k - 1] == x and last[k] == y
		last[k - 3], last[k - 2], last[k - 1], last[k] = point, relativePoint, x, y
	end
	if same then return end

	last.from, last.frame, last.count = from, frame, count
	to:ClearAllPoints()
	if not from then return to:SetAllPoints() end

	for i = 1, count do
		local k = i * 4
		to:SetPoint(last[k - 3], frame, last[k - 2], last[k - 1], last[k])
	end
end

-- A texture with neither atlas nor file is the interact cursor: it is re-set every frame, as the cursor unit can
-- change without the native icon changing.
local function copyTexture(from, to, cursorUnits, gen)
	if not from then return to:Hide() end

	local last = lastCopy(to, "psTexture", gen)
	local atlas, file = from:GetAtlas(), from:GetTexture()
	if not (atlas or file) or last.atlas ~= atlas or last.file ~= file then
		last.atlas, last.file, last.left = atlas, file, nil
		if atlas then
			to:SetAtlas(atlas)
		elseif file then
			to:SetTexture(file)
		else
			to:SetTexture(nil)
			for _, unit in ipairs(cursorUnits or NO_UNITS) do
				if SetUnitCursorTexture(to, unit, nil, nil, false) then break end
			end
		end
	end
	local ulX, ulY, llX, llY, urX, urY, lrX, lrY = from:GetTexCoord()
	if last.left ~= ulX or last.ulY ~= ulY or last.llX ~= llX or last.llY ~= llY or last.urX ~= urX or last.urY ~= urY or last.lrX ~= lrX or last.lrY ~= lrY then
		last.left, last.ulY, last.llX, last.llY, last.urX, last.urY, last.lrX, last.lrY = ulX, ulY, llX, llY, urX, urY, lrX, lrY
		to:SetTexCoord(ulX, ulY, llX, llY, urX, urY, lrX, lrY)
	end
	local r, g, b, a = from:GetVertexColor()
	if last.r ~= r or last.g ~= g or last.b ~= b or last.a ~= a then
		last.r, last.g, last.b, last.a = r, g, b, a
		to:SetVertexColor(r, g, b, a)
	end
	local desaturated = from:IsDesaturated()
	if last.desaturated ~= desaturated then
		last.desaturated = desaturated
		to:SetDesaturated(desaturated)
	end
	local alpha = saved[from]
	if alpha == nil then alpha = from:GetAlpha() end
	if last.alpha ~= alpha then
		last.alpha = alpha
		to:SetAlpha(alpha)
	end
	local shown = from:IsShown()
	if to:IsShown() ~= shown then to:SetShown(shown) end
end

local function paintPaddle(overlay, native, name)
	local label, state = overlay.label, native.textureState
	local size = math.max(8, math.floor(native:GetHeight() / 2 + 0.5))
	if overlay.fontSize ~= size then
		local path, _, flags = GameFontNormal:GetFont()
		label:SetFont(path, size, flags)
		overlay.fontSize = size
	end
	label:SetText(name)
	local lit = state == PRESSED_STATE or state == ACTIVE_STATE
	local color = state == DISABLED_STATE and DISABLED_FONT_COLOR or lit and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
	label:SetTextColor(color:GetRGB())
	setAtlas(overlay.paddle, lit and PADDLE_FRAME_LIT or PADDLE_FRAME)
	overlay.paddle:SetDesaturated(state == DISABLED_STATE)
end

local function showGlyph(native, overlay, entry)
	follow(overlay, native, native:GetEffectiveAlpha(), hidden[native] and not entry.keep and ALPHA_LEVEL or OVERLAY_LEVEL)
	-- A mirrored slot's prompt (anchored TOPRIGHT of its button) moves with the mirror's dent, not the native's.
	local face = entry.face
	if face then overlay:SetPoint("CENTER", native, "CENTER", face.promptX or 0, face.promptY or 0) end

	local icon, atlas = overlay.icon, nil
	if entry.atlas then
		local variant = InputDeviceIconVariant and (native.useDropShadow == false and InputDeviceIconVariant.NoShadow or InputDeviceIconVariant.Standard)
		local textures = InputIconTextureSetUtility.GetActiveInputIconButtonTextures(entry.key, variant)
		-- A routed entry's prompt shows that entry's range state (RefreshRange), the bar's focus kept.
		local state, mirror = native.textureState, entry.face and entry.face.slot and mirrors[entry.face.id]
		local range = mirror and mirror.looked and mirror.rangeState
		if mirror and mirror.looked then state = state == ACTIVE_STATE and ACTIVE_STATE or range == "disabled" and DISABLED_STATE or NORMAL_STATE end
		atlas = textures and (textures[state] or textures[NORMAL_STATE])
	end
	icon:SetShown(atlas)
	overlay.paddle:SetShown(not atlas)
	overlay.label:SetShown(not atlas)
	if not atlas then return paintPaddle(overlay, native, entry.name) end
	if overlay.atlas == atlas then return end

	overlay.atlas = atlas
	icon:SetAtlas(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo(atlas)
	local pad = info and info.width == LARGE_PROMPT_W and info.height == LARGE_PROMPT_H and LARGE_PROMPT_PAD or 0
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", -pad, pad)
	icon:SetPoint("BOTTOMRIGHT", pad, -pad)
end

-- The rest size of a slot: the widest of its group (a pressed slot on a collapsed bar is 4 smaller).
local function restOf(button)
	local group, rest = button:GetParent(), button:GetWidth()
	for index = 1, 4 do
		local other = group and group["ActionButton" .. index]
		if other then rest = math.max(rest, other:GetWidth()) end
	end
	return rest
end

local function pressedOf(mirrorFace)
	local face = ns.Face
	local pad = face and face.Pressed and face.Pressed(mirrorFace.code, mirrorFace.layer)
	local catcher = face and face.Catcher and face.Catcher(mirrorFace.code, mirrorFace.layer)
	return pad, catcher and catcher:GetButtonState() == "PUSHED"
end

-- Returns true while the slot's own art stays hidden: drawn, or merely invisible (so it can't flash back).
local function showMirror(mirror, mirrorFace)
	local target, source, catalog = mirrorFace.target, mirrorFace.source, mirrorFace.catalog
	local from = source and source.SpecialActionIcon
	mirrorFace.promptX, mirrorFace.promptY = 0, 0
	if not target:IsVisible() then
		mirror:Hide()
		return true
	end
	if not (catalog or from:IsShown()) then
		mirror:Hide()
		return false
	end

	follow(mirror, target, target:GetEffectiveAlpha(), MIRROR_LEVEL)
	local square = target.SquareMask
	square = square and square:IsShown()
	mirror:SetShape(square and "square" or "circle")
	-- A catalog entry draws its shadow slot (not filled yet, or Face.lua without shadow slots: the entry's own icon, no
	-- states); a face action has no slot and is drawn from its Blizzard button below.
	if catalog then mirror:SetSlot(mirrorFace.slot, catalog.icon) else mirror:SetSlot(nil, nil) end
	-- At the slot's rest size; the Blizzard slot under us may itself be moved (its face action pressed through another
	-- key, ApplyPressedStyle), which is undone. This cell presses from its own key (pad) or its catcher (mouse).
	local pad, mouse = pressedOf(mirrorFace)
	local rest = restOf(target)
	local nativeY, nativeS = nativePressed[target] and ns.SlotView.PRESS_DY or 0, target:GetWidth() - rest
	mirror:SetSize(rest, rest)
	mirror:SetPoint("CENTER", target, "CENTER", 0, -nativeY)
	local dy, ds = mirror:SetPressed(pad or mouse, not pad)
	-- The slot's prompt is anchored TOPRIGHT of its button, so it moves by the centre offset plus half the size step.
	mirrorFace.promptX, mirrorFace.promptY = (ds - nativeS) / 2, dy - nativeY + (ds - nativeS) / 2
	-- The drop shadow as the slot shows it now (hidden while the bar is focused: the focus FX stays native).
	local shadow, gen = square and target.SquareShadow or target.CircleShadow, mirror.generation
	copyPoints(shadow, mirror.shadow, mirror.body, gen)
	copyTexture(shadow, mirror.shadow, nil, gen)
	mirror.text:SetFrameLevel(mirror:GetFrameLevel() + 2)
	if catalog then
		mirror.clear:Hide()
		return true
	end

	-- A face action: its Blizzard button's icon, flash, clear ring and checked state.
	local icon, flash, clear, checked, body = mirror.icon, mirror.flash, mirror.clear, mirror.checked, mirror.body
	copyPoints(from, icon, body, gen)
	copyTexture(from, icon, mirrorFace.action == "interact" and CURSOR_UNITS, gen)
	if not icon:IsShown() then icon:Show() end
	copyPoints(source.Flash, flash, body, gen)
	copyTexture(source.Flash, flash, nil, gen)
	local ring = clearOverlayOf(source)
	copyPoints(ring, clear, body, gen)
	copyTexture(ring, clear, nil, gen)
	local checkedArt = source:GetCheckedTexture()
	copyPoints(checkedArt, checked, body, gen)
	copyTexture(checkedArt, checked, nil, gen)
	checked:SetShown(source:GetChecked())
	return true
end

-- Pressed state and icon as Blizzard draws them: the native left tab is the left target modifier (friendly, hostile
-- with GamepadSwapTargetModifiers), so its highlight and icon (friendly, or shortcuts while a targeting bar shows)
-- are read rather than re-derived.
local function nativeTab(role, swap)
	local leftRole = swap and "hostile" or "friendly"
	return TAB[role == leftRole and "Left" or "Right"]
end

local function layoutMarker(marker, split, unit, side)
	local tab, mask = TAB[side], marker.mask
	-- Blizzard's highlight is centred on the tab at its atlas size, which may be larger than the tab.
	local highlightW, highlightH = unit[tab.highlight]:GetSize()
	local highlightX, highlightY = (TAB_W - highlightW) / 2, (TAB_H - highlightH) / 2
	for i, row in ipairs(marker.rows) do
		local icon, wash, pressed, half = row.icon, row.wash, row.pressed, HALVES[i]
		icon:ClearAllPoints()
		pressed:ClearAllPoints()
		wash:ClearAllPoints()
		pressed.psAtlas = nil
		if row.masked ~= split then
			local method = split and "AddMaskTexture" or "RemoveMaskTexture"
			wash[method](wash, mask)
			pressed[method](pressed, mask)
			row.masked = split
		end
		if split then
			icon:SetSize(TAB_W * CROSS_SCALE, TAB_H * CROSS_SCALE)
			icon:SetPoint("TOPLEFT", TAB_W / 2 - TAB_W / 2 * CROSS_SCALE, -(half.cy - 23 * CROSS_SCALE))
			wash:SetPoint("TOPLEFT", 4, -half.washY)
			wash:SetSize(42, 15.5)
			-- The part of the highlight inside this half of the tab, at the native highlight's own place and scale.
			local left, right = math.max(0, highlightX), math.min(TAB_W, highlightX + highlightW)
			local top, bottom = math.max((i - 1) * HALF_H, highlightY), math.min(i * HALF_H, highlightY + highlightH)
			pressed:SetPoint("TOPLEFT", left, -top)
			pressed:SetSize(right - left, bottom - top)
			local crop = row.crop
			crop[1], crop[2] = (left - highlightX) / highlightW, (right - highlightX) / highlightW
			crop[3], crop[4] = (top - highlightY) / highlightH, (bottom - highlightY) / highlightH
		else
			-- The native icon and highlight use their atlas size, centred on the tab.
			icon:SetPoint("CENTER")
			icon:SetSize(unit[tab.icon]:GetSize())
			pressed:SetPoint("CENTER")
			pressed:SetSize(unit[tab.highlight]:GetSize())
		end
	end
	marker.split, marker.side = split, side
	marker.divider:SetShown(split)
end

local function drawMarker(marker, side, rows, unit)
	local native = unit[TAB[side].bg]
	if not native:IsVisible() then return marker:Hide() end

	follow(marker, native, unit:GetEffectiveAlpha(), markersHidden and 0 or OVERLAY_LEVEL, unit)
	local split = #rows == 2
	if marker.split ~= split or marker.side ~= side then layoutMarker(marker, split, unit, side) end
	local bgAtlas = TAB[side].bgAtlas
	setAtlas(marker.bg, bgAtlas)
	if marker.maskAtlas ~= bgAtlas then
		marker.maskAtlas = bgAtlas
		marker.mask:SetAtlas(bgAtlas, false, nil, nil, CLAMP, CLAMP)
	end
	local swap = markerPlan.swap
	for i, row in ipairs(marker.rows) do
		local role = rows[i]
		local tab = role and nativeTab(role, swap)
		local down = tab and unit[tab.highlight]:IsShown()
		row.icon:SetShown(role)
		row.wash:SetShown(split and down)
		row.pressed:SetShown(down)
		if role then
			setAtlas(row.icon, unit[tab.icon]:GetAtlas() or ROLE_ICON[role])
			if setAtlas(row.pressed, TAB[side].pressedAtlas) and split then
				local left, top, _, bottom, right = row.pressed:GetTexCoord()
				local crop, width, height = row.crop, right - left, bottom - top
				row.pressed:SetTexCoord(left + width * crop[1], left + width * crop[2], top + height * crop[3], top + height * crop[4])
			end
		end
	end
end

local function syncMarkers()
	local unit = pageUnit()
	if not (markerPlan.on and unit and unit.LeftShoulderBackground) then
		restoreMarkers()
		for _, marker in pairs(markers) do marker:Hide() end
		return
	end

	if hideMode() == "alpha" then hideMarkerTabs(unit) else restoreMarkers() end
	for side, marker in pairs(markers) do
		local rows = markerPlan.rows[side]
		if rows then drawMarker(marker, side, rows, unit) else marker:Hide() end
	end
end

-- Runs every frame while shown: a 0.1 s lag would flash the native glyph at every modifier press. The heavier key
-- resolution runs at POLL. A hidden native stays at alpha 0 while it is merely invisible, so it can't flash when
-- Blizzard shows it again before our next frame; it is put back only when it leaves the wanted set.
local function sync()
	local alphaMode = hideMode() == "alpha"
	-- Mirrors first: a mirrored slot's prompt takes this frame's dent. The slot's own art is hidden while a mirror
	-- stands on it (else a pressed-in mirror shows the native ring around it) and put back when it leaves.
	wipe(slotsNow)
	-- A face action's own Blizzard button moves while a routed key presses it (pad or catcher click).
	wipe(nativePressed)
	for _, mirrorFace in pairs(faces) do
		if mirrorFace.source then
			local pad, mouse = pressedOf(mirrorFace)
			if pad or mouse then nativePressed[mirrorFace.source] = true end
		end
	end
	for id, mirror in pairs(mirrors) do
		local mirrorFace = faces[id]
		if not mirrorFace then
			mirror:Hide()
		elseif showMirror(mirror, mirrorFace) and alphaMode then
			slotsNow[mirrorFace.target] = true
		end
	end
	for button in pairs(slotsNow) do
		for _, region in ipairs(regionsOf(button)) do hideTexture(region) end
		slotsHidden[button] = true
	end
	for button in pairs(slotsHidden) do
		if not slotsNow[button] then restoreSlot(button) end
	end
	for native, overlay in pairs(overlays) do
		local entry = wanted[native] and entryOf[native]
		if entry and not entry.keep and native.mappedButtonKey ~= entry.from and not fillEntry(entry, native) then
			wanted[native], entry = nil, nil
		end
		if entry then
			if alphaMode then
				hidden[native] = true
				for _, key in ipairs(GLYPH_TEXTURES) do hideTexture(native[key]) end
			else
				restore(native)
			end
			if native:IsVisible() then showGlyph(native, overlay, entry) else overlay:Hide() end
		else
			overlay:Hide()
			restore(native)
		end
	end
	syncMarkers()
end

-- Our game macro: "FCT:" and in Actions' registries (account or this character). Anything else, even a
-- macro named "FCT:...", is the player's (Actions.lua registry comment).
local function ourMacro(action)
	if GetActionInfo(action) ~= "macro" then return false end

	local name = C_ActionBar.GetActionText(action)
	if not name or issecretvalue and issecretvalue(name) or name:sub(1, #MACRO_PREFIX) ~= MACRO_PREFIX then return false end

	local char = ns.Face.CharDB()
	return not not (ns.db.macros and ns.db.macros[name] or char and char.macros and char.macros[name])
end

-- Every frame while active, so a page flip (the same buttons take new actions, no event) never shows a frame of
-- "FCT:..." text. A slot is re-judged only when its action changed or namesDirty; inactive, every name comes back.
local function syncNames()
	wipe(namesNow)
	local unit = active() and pageUnit()
	local actionBars = unit and unit.actionBars
	for _, barKey in pairs(actionBars and CELL_BARS or NO_UNITS) do
		local bar = actionBars[barKey]
		for _, side in ipairs(SIDES) do
			local group = bar and bar[side]
			for index = 1, 4 do
				local button = group and group["ActionButton" .. index]
				local action = button and button.Name and button.action
				if action and (namesDirty or nameAction[button] ~= action) then nameAction[button], nameOurs[button] = action, ourMacro(action) end
				if action and nameOurs[button] then namesNow[button] = true end
			end
		end
	end
	namesDirty = false
	for button in pairs(namesNow) do
		hideTexture(button.Name)
		namesHidden[button] = true
	end
	for button in pairs(namesHidden) do
		if not namesNow[button] then
			showTexture(button.Name)
			namesHidden[button] = nil
		end
	end
end

local namesWatch = CreateFrame("Frame")
namesWatch:Hide()

local function fail(err)
	failed = true
	if driver then driver:Hide() end
	namesWatch:Hide()
	pcall(restoreAll)
	ns.log("glyph overlay stopped after an error; Blizzard's glyphs are back (/reload to retry)")
	ns.debug("glyphs error: %s", tostring(err))
end

local function guarded(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then fail(err) end
end

local since = 0
local function step(elapsed)
	since = since + elapsed
	if since >= POLL then
		since = 0
		poll()
	end
	sync()
end

driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed) guarded(step, elapsed) end)
namesWatch:SetScript("OnUpdate", function() guarded(syncNames) end)

local function doRefresh()
	collect()
	since = 0
	poll()
	sync()
	syncNames()
	namesWatch:SetShown(active())
end

local function refresh()
	if not ns.db or failed then return end
	guarded(doRefresh)
end

-- "alpha" / "overlay": how covered native glyphs are hidden; "off" while the addon draws nothing (inactive, panel or
-- detection open, glyphs option off, or stopped after an error).
function Glyphs.Mode()
	if not (ns.db and active()) then return "off" end
	return hideMode()
end

-- The settings screen (and controller detection) open and close through SetPanelOpen, which sends no message.
local setPanelOpen = ns.SetPanelOpen
function ns.SetPanelOpen(open)
	setPanelOpen(open)
	refresh()
end

ns.On("PLAYER_ENTERING_WORLD", refresh)
ns.On("FCT_ACTIVE_CHANGED", refresh)
ns.On("FCT_LAYOUT_CHANGED", refresh)
ns.On("FCT_COMBAT_START", refresh)
ns.On("CVAR_UPDATE", function(name) if name == "GamepadSwapTargetModifiers" then refresh() end end)
ns.On("PLAYER_LOGOUT", function() pcall(restoreAll) end)

-- Our own event frame: macro or slot changes re-judge the macro names on the next watcher frame.
local nameEvents = CreateFrame("Frame")
nameEvents:SetScript("OnEvent", function() namesDirty = true end)
pcall(nameEvents.RegisterEvent, nameEvents, "ACTIONBAR_SLOT_CHANGED")
pcall(nameEvents.RegisterEvent, nameEvents, "UPDATE_MACROS")

-- Debug only: compare the two ways of hiding the native glyph.
function ns.commands.glyphhide(args)
	local mode = (args[1] or ""):lower()
	if mode ~= "alpha" and mode ~= "overlay" then return ns.log("glyph hide: " .. hideMode() .. " (/fct glyphhide alpha|overlay)") end

	ns.db.options.glyphHide = mode
	pcall(restoreAll)
	refresh()
	ns.log("glyph hide: " .. mode)
end
