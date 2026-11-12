-- Stubbed WoW check of the glyph overlay: lua tests/glyphs_spec.lua
-- Which physical glyph lands on which Blizzard glyph for the user's layout (L2 left bar, L1 right bar, R1 friendly,
-- R2 hostile), face mirrors, the targeting tabs, hiding and restoring, standing down and error isolation.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local fails = 0
local function check(cond, msg)
	if not cond then
		fails = fails + 1
		print("FAIL " .. msg)
	end
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local created, registered = {}, 0
local Mock = {}
local NOOP = {}
for name in ("SetAllPoints SetScale ClearAllPoints SetFrameStrata SetFrameLevel SetDesaturated SetColorTexture SetTextColor SetDrawBling SetDrawEdge SetEdgeTexture SetDrawSwipe SetSwipeColor SetUsingParentLevel SetJustifyH RegisterEvent RegisterUnitEvent"):gmatch("%S+") do NOOP[name] = function() end end
Mock.__index = function(_, k) return rawget(Mock, k) or NOOP[k] end
local function mock(fields)
	local o = setmetatable(fields or {}, Mock)
	o.shown = o.shown ~= false
	o.attrs = o.attrs or {}
	return o
end
function Mock:SetShown(v)
	local was = self.shown
	self.shown = not not v
	if was ~= self.shown and self[self.shown and "OnShow" or "OnHide"] then self[self.shown and "OnShow" or "OnHide"](self) end
end
function Mock:Show() self:SetShown(true) end
function Mock:Hide() self:SetShown(false) end
function Mock:IsShown() return self.shown end
function Mock:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Mock:GetParent() return self.parent end
function Mock:GetEffectiveScale() return 1 end
function Mock:GetSize() return self.w or 24, self.h or 24 end
function Mock:SetSize(w, h) self.w, self.h = w, h end
function Mock:GetWidth() return self.w or 24 end
function Mock:AddMaskTexture(m) self.mask = m end
function Mock:RemoveMaskTexture() self.mask = nil end
function Mock:GetHeight() return self.h or 24 end
function Mock:GetAlpha() return self.alpha or 1 end
function Mock:SetAlpha(a) self.alpha = a end
function Mock:GetEffectiveAlpha() return (self.alpha or 1) * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function Mock:GetFrameLevel() return 3 end
function Mock:GetFrameStrata() return "MEDIUM" end
function Mock:GetDebugName() return self.name or "?" end
function Mock:GetAttribute(k) return self.attrs[k] end
function Mock:SetPoint(_, rel, relPoint, x, y)
	if type(rel) == "table" then self.anchor, self.offset = rel, { x or 0, y or 0 } else self.offset = { rel or 0, relPoint or 0 } end
end
function Mock:GetNumPoints() return 2 end
function Mock:GetPoint(i) return i == 1 and "TOPLEFT" or "BOTTOMRIGHT", self.parent, i == 1 and "TOPLEFT" or "BOTTOMRIGHT", 0, 0 end
function Mock:SetText(t) self.text = t end
function Mock:SetFont(_, size) self.fontSize = size end
function Mock:SetAtlas(a) self.atlas, self.file, self.coords = a, nil, nil end
function Mock:GetAtlas() return self.atlas end
function Mock:GetTexture() return self.file end
function Mock:SetTexture(f) self.file, self.atlas = f, nil end
function Mock:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Mock:SetTexCoord(...) self.coords = { ... } end
function Mock:GetVertexColor() return 1, 1, 1, 1 end
function Mock:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Mock:SetHideCountdownNumbers(v) self.hideNumbers = v end
function Mock:SetSwipeTexture(t) self.swipe = t end
function Mock:EnableMouse(v) self.mouse = v end
function Mock:SetCooldownFromDurationObject(d) self.duration, self.cd = d, nil end
function Mock:SetCooldown(start, duration) self.cd, self.duration = { start, duration }, nil end
function Mock:Clear() self.cd, self.duration = nil, nil end
function Mock:IsDesaturated() return false end
function Mock:SetScript(name, fn) self[name] = fn end
function Mock:CreateTexture() return mock({ parent = self }) end
Mock.CreateFontString = Mock.CreateTexture
Mock.CreateMaskTexture = Mock.CreateTexture
function Mock:GetNormalTexture() return self.normal end
function Mock:GetPushedTexture() return self.pushed end
function Mock:GetCheckedTexture() return self.checkedArt end
function Mock:GetChecked() return self.isChecked end
function Mock:GetButtonState() return self.buttonState or "NORMAL" end
function Mock:GetObjectType() return self.objectType or "Texture" end
function Mock:GetRegions() return (table.unpack or unpack)(self.regions or {}) end

UIParent = mock({ name = "UIParent" })
function CreateFrame(_, name, parent, template)
	local f = mock({ name = name, parent = parent, template = template })
	if template == "ActionButtonSpellAlertTemplate" then
		f.shown = false
		f.ProcStartAnim = { Play = function(a) a.playing = true end, Stop = function(a) a.playing = false end }
	end
	created[#created + 1] = f
	return f
end
local color = { GetRGB = function() return 1, 1, 1 end }
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, DISABLED_FONT_COLOR = color, color, { GetRGB = function() return 0.5, 0.5, 0.5 end }
GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
C_Texture = { GetAtlasInfo = function() return { width = 76, height = 75 } end }
RANGE_INDICATOR, ATTACK_BUTTON_FLASH_TIME = "*", 0.4
RED_FONT_COLOR, ACTIONBAR_HOTKEY_FONT_COLOR = { GetRGB = function() return 1, 0.1, 0.1 end }, { GetRGB = function() return 0.6, 0.6, 0.6 end }
local clock = 100
function GetTime() return clock end
function GetCVarBool() return true end
-- Stubbed shadow action slots (Face.Slot) for routed entries' native look: C_ActionBar answers per slot.
local actions = {
	[145] = { texture = 135812, usable = true, cooldown = "cd145", charge = "ch145", loc = "loc145", count = "2", type = "spell", id = 133 },
	[146] = { texture = 135230, usable = true, cooldown = "cd146", count = "3", equipped = true, type = "item", id = 5512 },
}
local overlayed, rangeEnabled = {}, {}
C_ActionBar = {
	HasAction = function(s) return actions[s] ~= nil end,
	GetActionTexture = function(s) return actions[s].texture end,
	GetActionCooldownDuration = function(s) return actions[s].cooldown end,
	GetActionLossOfControlCooldownDuration = function(s) return actions[s].loc end,
	GetActionChargeDuration = function(s) return actions[s].charge end,
	IsCurrentAction = function(s) return actions[s].current end,
	IsAutoRepeatAction = function(s) return actions[s].autoRepeat end,
	IsAutoCastPetAction = function() return false end,
	IsUsableAction = function(s) return actions[s].usable, actions[s].noMana end,
	GetActionDisplayCount = function(s) return actions[s].count end,
	IsAttackAction = function(s) return actions[s].attack end,
	IsEquippedAction = function(s) return actions[s].equipped end,
	EnableActionRangeCheck = function(s, on) rangeEnabled[s] = on or nil end,
	GetActionText = function(s) return actions[s] and actions[s].text end,
}
function GetActionInfo(s) local a = actions[s] if a then return a.type, a.id end end
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return overlayed[id] end }

local function icon(name, key, parent)
	local i = mock({ name = name, mappedButtonKey = key, parent = parent, useDropShadow = true, usableState = 1, textureState = 1 })
	for _, t in ipairs({ "NormalTexture", "HoverTexture", "PressedTexture", "ActiveTexture", "DisabledTexture" }) do i[t] = mock({ parent = i }) end
	i.animatedGlowTop = mock({ parent = i })
	return i
end
local function glyphAlpha(i) return i.NormalTexture:GetAlpha() + i.ActiveTexture:GetAlpha() + i.DisabledTexture:GetAlpha() end
local function prompt(name, keys, parent)
	local p = mock({ name = name, parent = parent, InputIcons = {} })
	for i, key in ipairs(keys) do p.InputIcons[i] = icon(name .. ".InputIcon" .. i, key, p) end
	return p
end

-- Crossbar: modifier glyphs on the bars, top bar reserved slots with prompts (ActionBarTemplates.xml Right group).
local bars = mock({ name = "Bars" })
local right = mock({ name = "topBar.Right", parent = bars })
local RIGHT_KEYS = { "PAD3", "PAD4", "PAD2", "PAD1" }
local ICONS = { "Interface\\Cursor\\Interact", nil, nil, nil }
local ATLASES = { nil, "crosshair_inspect_32", "128-redbutton-exit", "gamepad-ability-icon-jump" }
for i, key in ipairs(RIGHT_KEYS) do
	local b = mock({ name = "topBar.Right.ActionButton" .. i, parent = right })
	b.ButtonIcon = icon(b.name .. ".ButtonIcon", key, b)
	b.ButtonIcon.shown = false
	b.SpecialActionIcon = mock({ parent = b, file = ICONS[i], atlas = ATLASES[i] })
	b.CircleMask, b.Flash = mock({ parent = b }), mock({ parent = b, shown = false, atlas = "flash" })
	b.normal, b.pushed, b.checkedArt = mock({ parent = b, atlas = "circleslot-normal" }), mock({ parent = b, atlas = "circleslot-pushed" }), mock({ parent = b, atlas = "checked" })
	b.CircleShadow, b.CircleShadowFocus = mock({ parent = b, atlas = "circleslot-dropshadow", alpha = 0.8 }), mock({ parent = b, atlas = "focus-bg-circ" })
	b.backdrop = mock({ parent = b })
	b.regions = { b.SpecialActionIcon, b.Flash, b.normal, b.pushed, b.checkedArt, b.CircleShadow, b.CircleShadowFocus, b.backdrop, b.CircleMask }
	b.CircleMask.objectType = "MaskTexture"
	right["ActionButton" .. i] = b
end
local inspect = right.ActionButton2
inspect.PermaboundOverlay = mock({ parent = inspect, atlas = "gamepad-actionbar-circleslot-permabound", shown = false })
local ring = mock({ parent = inspect, atlas = "gamepad-actionbar-circleslot-permabound", shown = false })
table.insert(inspect.regions, inspect.PermaboundOverlay)
table.insert(inspect.regions, ring)
-- A bar slot prompt is not scanned (only face and D-pad keys live there); give one a moved key to prove it.
local leftBar = mock({ name = "leftBar", parent = bars })
leftBar.actionButtons = { mock({ ButtonIcon = icon("leftBar.ActionButton1.ButtonIcon", "PADRTRIGGER", leftBar) }) }
-- A D-pad cell on the left bar (square) and a face cell on the right bar (circle), for Face.CellEntry.
local function cell(name, key, parent, square)
	local b = mock({ name = name, parent = parent, normal = mock({ atlas = square and "squareslot-normal" or "circleslot-normal" }) })
	b.pushed = mock({ atlas = square and "squareslot-pushed" or "circleslot-pushed" })
	b.ButtonIcon = icon(name .. ".ButtonIcon", key, b)
	b.SquareMask, b.CircleMask = mock({ parent = b, atlas = "SquareMask", shown = square }), mock({ parent = b, atlas = "CircleMask", shown = not square })
	b.icon, b.SquareShadow = mock({ parent = b, file = 133000 }), mock({ parent = b, atlas = "squareslot-dropshadow", shown = square })
	b.regions = { b.icon, b.normal, b.SquareShadow }
	return b
end
leftBar.Left = mock({ name = "leftBar.Left", parent = leftBar })
leftBar.Left.ActionButton1 = cell("leftBar.Left.ActionButton1", "PADDUP", leftBar.Left, true)
local rightBar = mock({ name = "rightBar", parent = bars, actionButtons = {} })
rightBar.Right = mock({ name = "rightBar.Right", parent = rightBar })
rightBar.Right.ActionButton2 = cell("rightBar.Right.ActionButton2", "PAD4", rightBar.Right, false)
local bottomBar = mock({ name = "bottomBar", parent = bars, actionButtons = {} })
local unitFrame = mock({ name = "PageUnit" })
local function tab(name, atlas, hidden) return mock({ name = name, parent = unitFrame, shown = not hidden, w = 50, h = 45, atlas = atlas }) end
local U = setmetatable({
	LeftShoulderBackground = tab("LeftShoulderBackground"), RightShoulderBackground = tab("RightShoulderBackground"),
	LeftShoulderIcon = tab("LeftShoulderIcon", "gamepad-targeting-friendly"), RightShoulderIcon = tab("RightShoulderIcon", "gamepad-targeting-hostile"),
	LeftShoulderHighlight = tab("LeftShoulderHighlight", nil, true), RightShoulderHighlight = tab("RightShoulderHighlight", nil, true),
	LeftIcon = icon("PageUnit.LeftIcon", "PADLTRIGGER", leftBar),
	RightIcon = icon("PageUnit.RightIcon", "PADRTRIGGER", rightBar),
	CenteredIcons = prompt("PageUnit.CenteredIcons", { "PADLTRIGGER", "PADRTRIGGER" }, bottomBar),
	LeftInputPrompt = prompt("PageUnit.LeftInputPrompt", { "PADLSHOULDER", "PADLTRIGGER" }, bars),
	RightInputPrompt = prompt("PageUnit.RightInputPrompt", { "PADRSHOULDER", "PADRTRIGGER" }, bars),
	actionBars = { topBar = mock({ Right = right, actionButtons = {} }), leftBar = leftBar, rightBar = rightBar, bottomBar = bottomBar },
}, { __index = unitFrame })
GamepadMainActionBarFrame = { PageUnit = U }
-- The pressed art is larger than the 50x45 tab (glow margin).
U.LeftShoulderHighlight.w, U.LeftShoulderHighlight.h, U.RightShoulderHighlight.w, U.RightShoulderHighlight.h = 60, 55, 60, 55

local legend = mock({ name = "Legend" })
local L = {
	leftTargetingModEntry = prompt("leftTargetingModEntry", { "PADLSHOULDER" }, legend),
	rightTargetingModEntry = prompt("rightTargetingModEntry", { "PADRSHOULDER" }, legend),
	ping = prompt("ping", { "PADRSTICK" }, legend),
	friendlyTargetingHeader = prompt("friendlyTargetingHeader", { "PADLSHOULDER" }, legend),
	friendlyShortcutsEntry = prompt("friendlyShortcutsEntry", { "PADRSHOULDER" }, legend),
	hostileTargetingHeader = prompt("hostileTargetingHeader", { "PADRSHOULDER" }, legend),
	hostileShortcutsEntry = prompt("hostileShortcutsEntry", { "PADLSHOULDER" }, legend),
	modifierHeader = prompt("MODIFIER[2]", { "PADLSHOULDER", "PADRSHOULDER" }, legend),
	dpadUp = prompt("dpadUp", { "PADDUP" }, legend),
}
GamepadPersistentInputLegend = { groups = {
	GAMEPLAY = { mock(), L.leftTargetingModEntry, L.rightTargetingModEntry, L.ping },
	FRIENDLY_TARGETING = { mock(), L.friendlyTargetingHeader, L.dpadUp, L.friendlyShortcutsEntry },
	HOSTILE_TARGETING = { mock(), L.hostileTargetingHeader, L.hostileShortcutsEntry },
	MODIFIER = { mock(), L.modifierHeader },
} }

local header = mock({ attrs = { ["state-face"] = "routed", ["ps-enabled"] = true, ["ps-key1"] = "PAD1", ["ps-key3"] = "PAD3" } })
ForeverControllerTweaksFaceHeader = header
InputIconTextureSetUtility = { GetActiveInputIconButtonTextures = function(key) if not key:find("^PADPADDLE") then return { "atlas-" .. key, "hover", "pressed", "active-" .. key, "disabled-" .. key } end end }
InputDeviceIconVariant = { Standard = 1, NoShadow = 2 }
local iconSet = "Shapes"
InputDeviceIconSetManager = {
	RegisterActiveInputDeviceIconSetUpdatedCallback = function() registered = registered + 1 end,
	GetActiveInputDeviceIconSet = function() return iconSet end,
}
function SetUnitCursorTexture() return false end

-- Namespace as Core builds it, with the device, remap, face and db the other units provide.
local handlers, lines, debugLog = {}, {}, {}
local detecting, isActive = false, true
local ns = { commands = {}, panelOpen = false }
function ns.Active() return isActive end
function ns.On(e, fn) handlers[e] = handlers[e] or {}; table.insert(handlers[e], fn) end
function ns.Fire(e, ...) for _, fn in ipairs(handlers[e] or {}) do fn(...) end end
function ns.log(m) lines[#lines + 1] = m end
function ns.debug(fmt, ...) debugLog[#debugLog + 1] = string.format(fmt, ...) end
function ns.SetPanelOpen(open) ns.panelOpen = not not open end

assert(loadfile(dir .. "/Layout.lua"))("ForeverControllerTweaks", ns)
local Layout = ns.Layout
local swap, state = false, "ours"
local entry = { roles = Layout.Copy(Layout.PRESETS.split), face = { bottom = "interact", left = "jump", right = "back", top = "inspect" } }
local raw = { L1 = { button = 9 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" }, P1 = { button = 16 } }
-- Face.CellEntry's storage: cells["FT/T"] = entry (codes FB/FR/FL/FT/DU/DL/DR/DD, layers T/L/R/B).
local cells = {}
ns.db = { options = { glyphs = true, debug = true }, devices = { ["054c/0ce6"] = entry } }
ns.Device = { Current = function() return { key = "054c/0ce6", raw = raw } end, SwapTargets = function() return swap end, Detecting = function() return detecting end }
ns.Remap = { State = function() return state end, Outputs = function() return state == "ours" and Layout.Outputs(raw, entry.roles, swap) or nil end }
-- Face.lua's shadow-slot contract: Slot, Catcher (click catcher frame), Pressed (key held).
local slotOf, catchers, held = {}, {}, {}
ns.Face = {
	CellEntry = function(code, layer) return cells[code .. "/" .. layer] end,
	Slot = function(code, layer) return slotOf[code .. "/" .. layer] end,
	Catcher = function(code, layer) return catchers[code .. "/" .. layer] end,
	Pressed = function(code, layer) return held[code .. "/" .. layer] end,
	CharDB = function() return { macros = { ["FCT:Target"] = { id = "game:target" } } } end,
}

assert(loadfile(dir .. "/SlotView.lua"))("ForeverControllerTweaks", ns)
local viewDriver
for _, f in ipairs(created) do if f.OnUpdate then viewDriver = f end end
assert(loadfile(dir .. "/Glyphs.lua"))("ForeverControllerTweaks", ns)
local driver
for _, f in ipairs(created) do if f.OnUpdate and f ~= viewDriver then driver = f end end

check(registered == 0, "no InputDeviceIconSetManager callback registered")
for _, f in ipairs(created) do check(f.template ~= "InputIconTextureFrameTemplate", "no InputIconTexture template frames") end

-- Every drawn overlay by the Blizzard frame it covers: glyph key, paddle label, mirror icon, or marker rows.
local function drawn()
	local out = {}
	for _, f in ipairs(created) do
		if f.parent == UIParent and f.shown and f.anchor then
			local what
			if f.rows then
				local rows = {}
				for _, r in ipairs(f.rows) do
					if r.icon.shown then rows[#rows + 1] = r.icon.atlas:gsub("gamepad%-targeting%-", "") .. (r.pressed.shown and "*" or "") .. (r.wash.shown and "+" or "") end
				end
				what = table.concat(rows, "/") .. (f.divider.shown and " split" or "")
			elseif f.mask then
				what = "mirror " .. tostring(f.icon.atlas or f.icon.file)
			elseif f.icon.shown then
				what = f.icon.atlas:gsub("^atlas%-", "")
			else
				what = "paddle " .. tostring(f.label.text)
			end
			out[f.anchor.name] = what
		end
	end
	return out
end
local function run()
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
	driver.OnUpdate(driver, 0.2)
	if viewDriver.shown then viewDriver.OnUpdate(viewDriver, 0.2) end
	return drawn()
end
local function expect(out, want, label)
	for target, what in pairs(want) do check(out[target] == what, string.format("%s: %s shows %s (got %s)", label, target, what, tostring(out[target]))) end
	for target, what in pairs(out) do
		if want[target] == nil then check(false, string.format("%s: unexpected overlay on %s (%s)", label, target, what)) end
	end
end

-- The user's layout; face bottom = Interact, left = Jump.
expect(run(), {
	["PageUnit.RightIcon"] = "PADLSHOULDER",
	["PageUnit.CenteredIcons.InputIcon2"] = "PADLSHOULDER",
	["PageUnit.LeftInputPrompt.InputIcon1"] = "PADRSHOULDER",
	["PageUnit.RightInputPrompt.InputIcon1"] = "PADRTRIGGER",
	["PageUnit.RightInputPrompt.InputIcon2"] = "PADLSHOULDER",
	["leftTargetingModEntry.InputIcon1"] = "PADRSHOULDER",
	["rightTargetingModEntry.InputIcon1"] = "PADRTRIGGER",
	["friendlyTargetingHeader.InputIcon1"] = "PADRSHOULDER",
	["friendlyShortcutsEntry.InputIcon1"] = "PADRTRIGGER",
	["hostileTargetingHeader.InputIcon1"] = "PADRTRIGGER",
	["hostileShortcutsEntry.InputIcon1"] = "PADRSHOULDER",
	["MODIFIER[2].InputIcon1"] = "PADRSHOULDER",
	["MODIFIER[2].InputIcon2"] = "PADRTRIGGER",
	["topBar.Right.ActionButton4"] = "mirror Interface\\Cursor\\Interact",
	["topBar.Right.ActionButton1"] = "mirror gamepad-ability-icon-jump",
	["RightShoulderBackground"] = "hostile/friendly split",
}, "split")
check(glyphAlpha(U.RightIcon) == 0 and U.RightIcon:GetAlpha() == 1, "covered glyph: textures at 0, frame (and its glow) at 1")

-- A mirrored slot's own art (every texture region but the animated focus FX) is at alpha 0 while the mirror stands
-- on it, and back at its own alpha when it leaves; unmirrored slots are never written.
local SLOT_ART = { "SpecialActionIcon", "Flash", "normal", "pushed", "checkedArt", "CircleShadow", "backdrop" }
local function slotHidden(b)
	for _, key in ipairs(SLOT_ART) do if b[key].alpha ~= 0 then return false end end
	return b.CircleShadowFocus.alpha == nil and b.CircleMask.alpha == nil
end
local function slotNative(b)
	for _, key in ipairs(SLOT_ART) do if b[key]:GetAlpha() ~= (key == "CircleShadow" and 0.8 or 1) then return false end end
	return b.CircleShadowFocus.alpha == nil and b.CircleMask.alpha == nil
end
check(slotHidden(right.ActionButton4) and slotHidden(right.ActionButton1), "mirrored slots: own art at 0, focus FX and mask untouched")
check(right.ActionButton2.SpecialActionIcon.alpha == nil and right.ActionButton3.normal.alpha == nil and right.ActionButton2.PermaboundOverlay.alpha == nil, "unmirrored slots never written")
local crossMirror
for _, f in ipairs(created) do if f.mask and not f.rows and f.shown and f.anchor == right.ActionButton4 then crossMirror = f end end
check(crossMirror.shadow.alpha == 0.8 and crossMirror.shadow.atlas == "circleslot-dropshadow" and crossMirror.icon.alpha == 1, "mirror draws the drop shadow and icon at the natives' own alpha")
-- Copies write only what changed: an unchanged frame re-anchors and re-sets nothing; a changed source, or a SlotView
-- redraw of those regions (here: the mirror shown again), is copied again.
local writes = 0
for _, region in ipairs({ crossMirror.shadow, crossMirror.icon, crossMirror.flash, crossMirror.checked }) do
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAtlas", "SetTexture", "SetTexCoord", "SetVertexColor", "SetAlpha", "SetDesaturated" }) do
		local native = rawget(Mock, method) or NOOP[method]
		region[method] = function(self, ...) writes = writes + 1 return native(self, ...) end
	end
end
run()
writes = 0
run()
check(writes == 0, "unchanged frame: no mirror texture written (got " .. writes .. " writes)")
right.ActionButton4.CircleShadow.atlas = "circleslot-dropshadow-2"
run()
check(writes == 2 and crossMirror.shadow.atlas == "circleslot-dropshadow-2", "source atlas changed: that atlas and its tex coords (SetAtlas resets them) set again, nothing else (got " .. writes .. ")")
right.ActionButton4.CircleShadow.atlas = "circleslot-dropshadow"
run()
crossMirror:Hide()
writes = 0
run()
check(writes > 0 and crossMirror.icon.file == "Interface\\Cursor\\Interact" and crossMirror.shadow.atlas == "circleslot-dropshadow", "mirror shown again (SlotView redraw): copied again")
for _, region in ipairs({ crossMirror.shadow, crossMirror.icon, crossMirror.flash, crossMirror.checked }) do
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAtlas", "SetTexture", "SetTexCoord", "SetVertexColor", "SetAlpha", "SetDesaturated" }) do region[method] = nil end
end
right.ActionButton1.SpecialActionIcon.shown = false
run()
check(slotNative(right.ActionButton4) and slotHidden(right.ActionButton1), "source icon gone: that slot's mirror leaves and its art comes back")
right.ActionButton1.SpecialActionIcon.shown = true
run()
check(glyphAlpha(U.LeftIcon) == 3, "right glyph untouched")
check(Layout and ns.Glyphs.Mode() == "alpha", "Mode() alpha")

-- Glyph state follows the native one (focused bar = Active atlas).
U.RightIcon.textureState = 4
local out = run()
check(out["PageUnit.RightIcon"] == "active-PADLSHOULDER", "texture state mirrored (got " .. tostring(out["PageUnit.RightIcon"]) .. ")")
U.RightIcon.textureState = 1

-- Flicker: a hidden native that is merely invisible stays at alpha 0.
L.friendlyTargetingHeader.shown = false
out = run()
check(out["friendlyTargetingHeader.InputIcon1"] == nil and glyphAlpha(L.friendlyTargetingHeader.InputIcons[1]) == 0, "invisible native: overlay hidden, native kept at alpha 0")
L.friendlyTargetingHeader.shown = true

-- Face mirror copies the source button's pushed, checked and flash state; Inspect's clear ring comes along.
header.attrs["ps-key4"] = "PAD4"
entry.face = { bottom = "interact", left = "jump", right = "back", top = "inspect" }
local interact = right.ActionButton1
interact.isChecked, interact.Flash.shown = true, true
held["FB/T"] = true
run()
local mirror
for _, f in ipairs(created) do if f.mask and f.shown and f.anchor == right.ActionButton4 then mirror = f end end
check(mirror and mirror.border.atlas == "gamepad-actionbar-circleslot-border-pressed" and mirror.checked.shown and mirror.flash.shown, "mirror: pushed frame while its key is held, checked and flash copied")
interact.isChecked, interact.Flash.shown, held["FB/T"] = nil, false, nil
header.attrs["ps-key4"] = nil

-- Catalog entry on a face position: its icon, no mirror of a Blizzard button.
cells["FT/T"] = { id = "item:6948", name = "Hearthstone", icon = 134414, kind = "item" }
header.attrs["ps-key4"] = "PAD4"
out = run()
check(out["topBar.Right.ActionButton2"] == "mirror 134414", "catalog entry icon on its slot (got " .. tostring(out["topBar.Right.ActionButton2"]) .. ")")
cells["FT/T"], header.attrs["ps-key4"] = nil, nil

-- Prompts shown: a mirrored slot gets its prompt drawn again on top; the native prompt keeps its alpha.
right.ActionButton4.ButtonIcon.shown = true
out = run()
check(out["topBar.Right.ActionButton4.ButtonIcon"] == "PAD1" and glyphAlpha(right.ActionButton4.ButtonIcon) == 0, "mirrored slot redraws its PAD1 prompt over the hidden native")

-- Press geometry equals native (ActionBarStyles.lua:140-148, ActionBarButton.lua:421-433, MainActionBarFrame.lua:690-727).
-- Jump is on Square: holding Square (FL/T) makes the router press Jump's own button, ActionButton4 under the Cross
-- cell, which Blizzard moves (ApplyPressedStyle). The Square cell looks pressed like a native slot; the Cross cell
-- stays at rest, undoing the move of the button under it. Prompts (TOPRIGHT of their button) follow.
local function mirrorOn(target)
	for _, f in ipairs(created) do if f.mask and not f.rows and f.shown and f.anchor == target then return f end end
end
local function promptOffset(native)
	for _, f in ipairs(created) do if f.icon and not f.mask and f.shown and f.anchor == native then return f.offset end end
end
-- A mirror's drawn slot: its body's size and centre offset from the Blizzard slot, and its frame art.
local function press(m) return m.body.w, m.offset[2] + m.body.offset[2], m.border.atlas:gsub("^gamepad%-actionbar%-", ""):gsub("%-border", "") end
local function geometry(target)
	local m, p = mirrorOn(target), promptOffset(target.ButtonIcon)
	local w, y, atlas = press(m)
	return string.format("%g %g %g %g %s", w, y, p[1], p[2], atlas)
end
right.ActionButton1.ButtonIcon.shown = true
-- Collapsed bar (30): native shrinks a pad-pressed slot by 4 and moves it down 2.
for i = 1, 4 do right["ActionButton" .. i].w = 30 end
right.ActionButton4.w = 26
held["FL/T"] = true
run()
check(geometry(right.ActionButton1) == "26 -2 -2 -4 circleslot-pressed", "collapsed pad press: Square cell 26, down 2, pushed frame (got " .. geometry(right.ActionButton1) .. ")")
check(geometry(right.ActionButton4) == "30 2 2 4 circleslot-normal", "collapsed pad press: Cross cell at rest over its moved button (got " .. geometry(right.ActionButton4) .. ")")
-- Expanded (focused) bar (38): the size step is overwritten, so a pad press only moves the slot down 2.
for i = 1, 4 do right["ActionButton" .. i].w = 38 end
run()
check(geometry(right.ActionButton1) == "38 -2 0 -2 circleslot-pressed", "expanded pad press: Square cell keeps its size, down 2, pushed frame (got " .. geometry(right.ActionButton1) .. ")")
check(geometry(right.ActionButton4) == "38 2 0 2 circleslot-normal", "expanded pad press: Cross cell at rest (got " .. geometry(right.ActionButton4) .. ")")
-- Mouse on the catcher: native skips ApplyPressedStyle for mouse clicks, so only the pushed frame shows.
held["FL/T"], catchers["FL/T"] = nil, mock({ buttonState = "PUSHED" })
run()
check(geometry(right.ActionButton1) == "38 0 0 0 circleslot-pressed", "mouse press: Square cell pushed frame only, no move (got " .. geometry(right.ActionButton1) .. ")")
catchers["FL/T"] = nil
run()
check(geometry(right.ActionButton1) == "38 0 0 0 circleslot-normal" and geometry(right.ActionButton4) == "38 0 0 0 circleslot-normal", "released: both cells at rest")
for i = 1, 4 do right["ActionButton" .. i].w = nil end
right.ActionButton4.ButtonIcon.shown, right.ActionButton1.ButtonIcon.shown = false, false

-- Face.CellEntry: an entry routed on any face or D-pad cell of any layer gets its icon on that cell, in the cell's
-- shape; nothing while the router is native or the key isn't routed.
cells["DU/L"] = { id = "game:mount", name = "Mount", icon = 132261, kind = "game" }
cells["FT/R"] = { id = "item:6948", name = "Hearthstone", icon = 134414, kind = "item" }
out = run()
check(out["leftBar.Left.ActionButton1"] == nil and out["rightBar.Right.ActionButton2"] == nil, "cell entry: nothing while its key isn't routed")
header.attrs["ps-key4"], header.attrs["ps-key5"] = "PAD4", "PADDUP"
out = run()
check(out["leftBar.Left.ActionButton1"] == "mirror 132261" and mirrorOn(leftBar.Left.ActionButton1).maskAtlas == "SquareMask", "cell entry: D-pad up on the left bar, square mask")
check(out["rightBar.Right.ActionButton2"] == "mirror 134414" and mirrorOn(rightBar.Right.ActionButton2).maskAtlas == "CircleMask", "cell entry: Y on the right bar, circle mask")
check(out["leftBar.Left.ActionButton1.ButtonIcon"] == "PADDUP", "cell entry: the cell's prompt drawn again on top")
header.attrs["state-face"] = "native"
out = run()
check(out["leftBar.Left.ActionButton1"] == nil and out["rightBar.Right.ActionButton2"] == nil, "cell entry: nothing while the router is native")
header.attrs["state-face"] = "routed"
-- Native look on a routed entry, read from its shadow slot with the native calls: a spell on DU/L (slot 145), an item
-- on FT/R (slot 146). Duration objects passed through untouched (secret-safe), tint, count, equipped border, glow,
-- checked, flash; range from ACTION_RANGE_CHECK_UPDATE on our enabled slot; every refresh on its native event.
local function fire(event, ...)
	for _, f in ipairs(created) do if f.OnEvent then f.OnEvent(f, event, ...) end end
end
cells["DU/L"] = { id = "spell:133", name = "Fireball", icon = 1, kind = "spell" }
cells["FT/R"] = { id = "item:5512", name = "Healthstone", icon = 2, kind = "item" }
slotOf["DU/L"], slotOf["FT/R"] = 145, 146
overlayed[133] = true
out = run()
local fire1, stone = mirrorOn(leftBar.Left.ActionButton1), mirrorOn(rightBar.Right.ActionButton2)
check(fire1.mouse == false and stone.mouse == false, "mirrors keep the mouse off, so clicks reach the catcher")
check(out["leftBar.Left.ActionButton1"] == "mirror 135812" and fire1.cooldown.duration == "cd145" and fire1.loc.duration == "loc145" and fire1.charge.duration == "ch145", "slot look: GetActionTexture icon, cooldown, loss-of-control and charge duration objects")
check(fire1.count.text == "2" and fire1.cooldown.swipe:find("WHITE8X8") and fire1.icon.color[1] == 1 and fire1.alert.shown and fire1.alert.ProcStartAnim.playing, "slot look: count, square swipe, usable tint, proc glow")
check(not fire1.range.shown and out["leftBar.Left.ActionButton1.ButtonIcon"] == "PADDUP" and rangeEnabled[145], "slot look: range check enabled, nothing shown before its first event")
check(stone.count.text == "3" and stone.equipped.shown and stone.cooldown.duration == "cd146" and stone.cooldown.swipe:find("TempPortraitAlphaMask"), "item slot: count, equipped border, round swipe")
fire("ACTION_RANGE_CHECK_UPDATE", 145, false, true)
out = run()
check(fire1.range.shown and fire1.range.color[1] == 1 and out["leftBar.Left.ActionButton1.ButtonIcon"] == "disabled-PADDUP", "range event: out of range, red dot, prompt disabled")
fire("ACTION_RANGE_CHECK_UPDATE", 145, true, true)
out = run()
check(fire1.range.color[1] == 0.6 and out["leftBar.Left.ActionButton1.ButtonIcon"] == "PADDUP", "range event: in range, grey dot, prompt pressable")
fire("ACTION_RANGE_CHECK_UPDATE", 145, false, false)
out = run()
check(not fire1.range.shown and out["leftBar.Left.ActionButton1.ButtonIcon"] == "disabled-PADDUP", "range event: no range check, dot hidden, prompt disabled")
actions[145].usable, actions[145].noMana, actions[145].cooldown = false, true, "gcd"
run()
check(fire1.icon.color[1] == 1 and fire1.cooldown.duration == "cd145", "no event: nothing re-read (no per-frame polling)")
fire("ACTION_USABLE_CHANGED", {})
run()
check(fire1.icon.color[1] == 0.5 and fire1.icon.color[3] == 1 and fire1.cooldown.duration == "cd145", "ACTION_USABLE_CHANGED: no-mana tint only")
fire("ACTIONBAR_UPDATE_COOLDOWN")
run()
check(fire1.cooldown.duration == "gcd", "ACTIONBAR_UPDATE_COOLDOWN: the new (GCD) duration")
overlayed[133], actions[145].current, actions[145].autoRepeat = nil, true, true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 133)
fire("ACTIONBAR_UPDATE_STATE")
fire("START_AUTOREPEAT_SPELL")
clock = 100
run()
check(not fire1.alert.shown and fire1.checked.shown and fire1.flash.shown, "glow gone, checked, auto-repeat flash on")
clock = 100.4
run()
check(not fire1.flash.shown, "flash off after ATTACK_BUTTON_FLASH_TIME")
catchers["DU/L"] = mock({ buttonState = "PUSHED" })
run()
local function pressed(m) return string.format("%g %g %s", press(m)) end
check(pressed(fire1) == "24 0 squareslot-pressed", "routed spell, mouse press: pushed frame only (got " .. pressed(fire1) .. ")")
catchers["DU/L"], held["DU/L"] = nil, true
run()
check(pressed(fire1) == "20 -2 squareslot-pressed", "routed spell, pad press on a collapsed bar: 4 smaller, down 2, pushed frame (got " .. pressed(fire1) .. ")")
held["DU/L"] = nil
run()
check(pressed(fire1) == "24 0 squareslot-normal", "routed spell released: at rest (got " .. pressed(fire1) .. ")")
slotOf["DU/L"] = 147
run()
check(out["leftBar.Left.ActionButton1"] and fire1.icon.file == 1 and fire1.cooldown.duration == nil and fire1.count.text == "", "shadow slot not filled yet: the entry's own icon, no states")
check(not rangeEnabled[145], "slot left: its range check turned off")
slotOf["DU/L"], slotOf["FT/R"] = nil, nil
actions[145].usable, actions[145].noMana, actions[145].cooldown, actions[145].current, actions[145].autoRepeat = true, nil, "cd145", nil, nil
clock = 100

-- A face action routed on a D-pad cell (Jump on DU/L): the router clicks Jump's top-bar button, so the cell mirrors
-- that button's icon; its dent stays off the left bar (the same button dents for a base-layer Jump press too).
cells["DU/L"] = { id = "face:jump", name = "Jump", icon = 0, kind = "face" }
cells["FT/R"] = nil
for i = 1, 4 do right["ActionButton" .. i].w = 30 end
out = run()
local dpad = mirrorOn(leftBar.Left.ActionButton1)
check(out["leftBar.Left.ActionButton1"] == "mirror gamepad-ability-icon-jump" and dpad.maskAtlas == "SquareMask", "Jump on DU/L: Jump's icon on the left bar's D-pad up cell, square")
held["DU/L"] = true
right.ActionButton4.w = 26
run()
check(pressed(dpad) == "20 -2 squareslot-pressed" and mirrorOn(right.ActionButton4).offset[2] == 2, "Jump on DU/L pressed: the D-pad cell presses, the Cross cell stays over Jump's moved button")
held["DU/L"] = nil
right.ActionButton4.w = 30
run()
check(slotHidden(right.ActionButton4) and leftBar.Left.ActionButton1.ButtonIcon.NormalTexture.alpha == 0, "Jump on DU/L: Cross slot (base-layer mirror) and the cell's prompt hidden under ours")
local cellArt = leftBar.Left.ActionButton1
check(cellArt.icon.alpha == 0 and cellArt.normal.alpha == 0 and cellArt.SquareShadow.alpha == 0 and dpad.shadow.atlas == "squareslot-dropshadow", "Jump on DU/L: the cell's own art hidden, square drop shadow drawn by the mirror")
for i = 1, 4 do right["ActionButton" .. i].w = nil end
cells["DU/L"], cells["FT/R"] = nil, nil
header.attrs["ps-key4"], header.attrs["ps-key5"] = nil, nil
out = run()
check(out["leftBar.Left.ActionButton1"] == nil and glyphAlpha(leftBar.Left.ActionButton1.ButtonIcon) == 3 and leftBar.Left.ActionButton1.icon:GetAlpha() == 1, "cell entry removed: mirror gone, prompt and cell art restored")

-- GamepadSwapTargetModifiers: the legend swaps its own header keys; friendly stays R1 (native R1 there), hostile R2.
swap = true
U.LeftShoulderIcon.atlas, U.RightShoulderIcon.atlas = "gamepad-targeting-hostile", "gamepad-targeting-friendly" -- SetShoulderIcons swaps
L.friendlyTargetingHeader.InputIcons[1].mappedButtonKey = "PADRSHOULDER"
L.hostileTargetingHeader.InputIcons[1].mappedButtonKey = "PADLSHOULDER"
out = run()
check(out["friendlyTargetingHeader.InputIcon1"] == nil and out["hostileTargetingHeader.InputIcon1"] == "PADRTRIGGER", "swap: friendly native R1 kept, hostile shows R2")
check(out["RightShoulderBackground"] == "hostile/friendly split", "swap: split tab still R2 (hostile) over R1 (friendly)")
swap = false
U.LeftShoulderIcon.atlas, U.RightShoulderIcon.atlas = "gamepad-targeting-friendly", "gamepad-targeting-hostile"
L.friendlyTargetingHeader.InputIcons[1].mappedButtonKey = "PADLSHOULDER"
L.hostileTargetingHeader.InputIcons[1].mappedButtonKey = "PADRSHOULDER"

-- Paddle holding friendly: "P1" over the footer slot frame, font scaled to the slot, disabled tint.
entry.roles = Layout.AssignRole(entry.roles, "P1", "friendly", false)
L.leftTargetingModEntry.InputIcons[1].h, L.leftTargetingModEntry.InputIcons[1].textureState = 18, 5
out = run()
local paddle
for _, f in ipairs(created) do if f.anchor == L.leftTargetingModEntry.InputIcons[1] and f.label then paddle = f end end
check(out["leftTargetingModEntry.InputIcon1"] == "paddle P1" and paddle.label.fontSize == 9 and paddle.paddle.atlas == "gamepad-footer-slot-frameneutral", "paddle: P1 tab, font 9 for an 18 slot")
check(out["RightShoulderBackground"] == "hostile/friendly split", "paddle: trigger row on top, paddle row below (got " .. tostring(out["RightShoulderBackground"]) .. ")")
L.leftTargetingModEntry.InputIcons[1].h, L.leftTargetingModEntry.InputIcons[1].textureState = nil, 1
entry.roles = Layout.Copy(Layout.PRESETS.split)

-- Targeting tabs: top half = trigger (R2 hostile), bottom = bumper (R1 friendly). R1 held lights the bottom half; the
-- friendly targeting bar sets the right native icon (hostile's) to shortcuts, so the top half shows it.
U.LeftShoulderHighlight.shown, U.RightShoulderIcon.atlas = true, "gamepad-targeting-shortcuts"
out = run()
check(out["RightShoulderBackground"] == "shortcuts/friendly*+ split", "R1 held: bottom half pressed, top copies the native shortcuts icon (got " .. tostring(out["RightShoulderBackground"]) .. ")")
local marker
for _, f in ipairs(created) do if f.rows and f.shown and f.anchor == U.RightShoulderBackground then marker = f end end
local pressed = marker.rows[2].pressed
local left, right_, top, bottom = (table.unpack or unpack)(pressed.coords or {})
check(not marker.rows[1].pressed.shown and pressed.shown and top == 0.5 and math.abs(bottom - 50 / 55) < 1e-9, "R1 held: pressed art cropped to the bottom half (got " .. tostring(top) .. "-" .. tostring(bottom) .. ")")
check(math.abs(left - 5 / 60) < 1e-9 and math.abs(right_ - 55 / 60) < 1e-9, "R1 held: the 60-wide pressed art's glow margin is cropped off")
check(pressed.offset[1] == 0 and pressed.offset[2] == -22.5 and pressed.w == 50 and pressed.h == 22.5, "R1 held: pressed art stays inside the tab's bottom half")
check(pressed.mask == marker.mask and marker.rows[2].wash.mask == marker.mask and marker.mask.atlas == "gamepad-targeting-right-shoulder-bg", "split rows masked to the tab's shape")
U.LeftShoulderHighlight.shown, U.RightShoulderIcon.atlas = false, "gamepad-targeting-hostile"
entry.roles = { L1 = "hostile", R2 = "friendly", L2 = "leftmod", R1 = "rightmod" }
out = run()
check(out["LeftShoulderBackground"] == "hostile" and out["RightShoulderBackground"] == "friendly", "opposite sides, colours reversed: one tab per side")
entry.roles = { L2 = "friendly", R1 = "hostile", L1 = "leftmod", R2 = "rightmod" }
out = run()
check(out["LeftShoulderBackground"] == nil and out["RightShoulderBackground"] == nil and U.LeftShoulderBackground:GetAlpha() == 1, "same picture as native: Blizzard's tabs untouched")
entry.roles = Layout.Copy(Layout.PRESETS.split)

-- Saved original alpha: put back exactly what was there (the split layout makes RightIcon covered again).
state = "native"
run()
U.RightIcon.NormalTexture:SetAlpha(0.5)
state = "ours"
run()
check(U.RightIcon.NormalTexture:GetAlpha() == 0, "hidden again")
U.RightIcon.NormalTexture:SetAlpha(1) -- a Blizzard style resetting it
driver.OnUpdate(driver, 0.01)
check(U.RightIcon.NormalTexture:GetAlpha() == 0, "alpha 0 re-asserted on the next frame")
state = "native"
run()
check(U.RightIcon.NormalTexture:GetAlpha() == 0.5 and U.RightIcon.ActiveTexture:GetAlpha() == 1, "restored to the saved alpha, not 1")
U.RightIcon.NormalTexture:SetAlpha(1)
state = "ours"

-- Overlay mode: ours drawn, nothing of Blizzard's touched.
ns.commands.glyphhide({ "overlay" })
out = run()
check(out["PageUnit.RightIcon"] == "PADLSHOULDER" and glyphAlpha(U.RightIcon) == 3 and U.RightShoulderBackground:GetAlpha() == 1, "overlay mode: drawn, natives untouched")
check(ns.Glyphs.Mode() == "overlay", "Mode() overlay")
check(slotNative(right.ActionButton1) and slotNative(right.ActionButton4), "overlay mode: slot art untouched")
ns.commands.glyphhide({ "alpha" })

-- The addon game macro names: a registered "FCT:" macro on a crossbar slot has its Name at alpha 0; the player's own
-- macros (even one named "FCT:...") keep theirs. A page flip changes a button's action with no event.
local bagsSlot, mineSlot = leftBar.Left.ActionButton1, rightBar.Right.ActionButton2
bagsSlot.Name, mineSlot.Name = mock({ parent = bagsSlot, alpha = 0.9 }), mock({ parent = mineSlot })
bagsSlot.action, mineSlot.action = 1, 2
actions[1], actions[2], actions[3] = { type = "macro", text = "FCT:Bags" }, { type = "macro", text = "FCT:Mine" }, { type = "spell", text = "FCT:Bags" }
ns.db.macros = { ["FCT:Bags"] = { id = "game:bags" } }
run()
local watch
for _, f in ipairs(created) do if f.OnUpdate and f ~= driver and f ~= viewDriver then watch = f end end
local function names() return bagsSlot.Name:GetAlpha() .. " " .. mineSlot.Name:GetAlpha() end
check(names() == "0 1" and watch.shown, "registered FCT:Bags name hidden, player's FCT:Mine shown (got " .. names() .. ")")
bagsSlot.action = 2
watch.OnUpdate(watch, 0.01)
check(names() == "0.9 1", "page flip to the player's macro: name back at its saved alpha on the next frame (got " .. names() .. ")")
bagsSlot.action = 3
watch.OnUpdate(watch, 0.01)
check(names() == "0.9 1", "not a macro: name untouched")
bagsSlot.action = 1
watch.OnUpdate(watch, 0.01)
check(names() == "0 1", "page flip back: hidden again")
ns.db.macros["FCT:Bags"] = nil
watch.OnUpdate(watch, 0.01)
check(names() == "0 1", "no event, same action: not re-judged")
fire("UPDATE_MACROS")
watch.OnUpdate(watch, 0.01)
check(names() == "0.9 1", "UPDATE_MACROS: unregistered macro keeps its name")
ns.db.macros["FCT:Bags"] = { id = "game:bags" }
actions[2].text = "FCT:Target"
fire("ACTIONBAR_SLOT_CHANGED", 2)
watch.OnUpdate(watch, 0.01)
check(names() == "0 0", "ACTIONBAR_SLOT_CHANGED: this character's registered macro hidden too (got " .. names() .. ")")
ns.SetPanelOpen(true)
check(names() == "0.9 1" and not watch.shown, "panel open: names restored, watcher idle")
ns.SetPanelOpen(false)
check(names() == "0 0" and watch.shown, "panel closed: hidden again")
isActive = false
ns.Fire("FCT_ACTIVE_CHANGED", false)
check(names() == "0.9 1" and not watch.shown, "Gamepad UI off: names restored")
isActive = true
ns.Fire("FCT_ACTIVE_CHANGED", true)
check(names() == "0 0", "Gamepad UI back: hidden again")

-- Standing down: panel open, detection running, Gamepad UI off.
ns.SetPanelOpen(true)
out = run()
check(next(out) == nil and glyphAlpha(U.RightIcon) == 3 and ns.Glyphs.Mode() == "off", "panel open: nothing drawn, Mode() off")
check(slotNative(right.ActionButton1) and slotNative(right.ActionButton4), "panel open: slot art restored")
ns.SetPanelOpen(false)
detecting = true
out = run()
check(next(out) == nil and glyphAlpha(U.RightIcon) == 3, "detection running: nothing drawn")
detecting = false
isActive = false
ns.Fire("FCT_ACTIVE_CHANGED", false)
check(next(drawn()) == nil and not driver.shown, "Gamepad UI off: nothing drawn, driver idle")
check(slotNative(right.ActionButton1) and slotNative(right.ActionButton4), "Gamepad UI off: slot art restored")
isActive = true
run()
check(slotHidden(right.ActionButton1), "Gamepad UI back: slot art hidden again")

-- Logout puts everything back.
ns.Fire("PLAYER_LOGOUT")
check(glyphAlpha(U.RightIcon) == 3 and U.RightShoulderBackground:GetAlpha() == 1 and slotNative(right.ActionButton1), "PLAYER_LOGOUT restores the natives")
run()

-- Idle: remap not applied and the face native, so nothing can be wanted.
state = "native"
header.attrs["ps-key1"], header.attrs["ps-key3"], header.attrs["state-face"] = nil, nil, "native"
entry.face = {}
out = run()
check(next(out) == nil and not driver.shown, "nothing wanted: nothing drawn, driver idle")
state, entry.face = "ours", { bottom = "interact", left = "jump", right = "back", top = "inspect" }
header.attrs["ps-key1"], header.attrs["ps-key3"], header.attrs["state-face"] = "PAD1", "PAD3", "routed"
run()
check(driver.shown, "layout back: driver running")

-- Debug strings only with debug on.
local before = #debugLog
ns.db.options.debug = false
entry.roles = Layout.AssignRole(entry.roles, "L2", "hostile", false)
run()
check(#debugLog == before, "debug off: no glyph debug line")
entry.roles = Layout.Copy(Layout.PRESETS.split)
ns.db.options.debug = true

-- Error isolation: a failing Blizzard frame stops the overlay and puts everything back.
U.RightIcon.GetEffectiveAlpha = function() error("boom") end
run()
check(glyphAlpha(U.RightIcon) == 3 and U.RightShoulderBackground:GetAlpha() == 1 and not driver.shown, "error: natives restored, driver stopped")
check(slotNative(right.ActionButton1) and slotNative(right.ActionButton4), "error: slot art restored")
check(names() == "0.9 1" and not watch.shown, "error: macro names restored, watcher stopped")
check(ns.Glyphs.Mode() == "off" and lines[#lines]:find("stopped after an error"), "error: Mode() off and one chat line")
local count = #lines
run()
check(#lines == count and next(drawn()) == nil, "error: stays off, no repeat line")

print(fails == 0 and "glyphs_spec: all checks passed" or ("glyphs_spec: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
