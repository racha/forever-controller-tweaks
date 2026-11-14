-- WoW UI stub for the panel specs (tests/bindings_spec.lua): frames, timers, events, the gamepad and the action bars, with taint traps on Blizzard UI the panel must never touch. Lua 5.1 and 5.4. Not a spec itself.
unpack = unpack or table.unpack
local W = { clock = 100, timers = {}, events = {}, frames = {}, log = {}, calls = {}, held = {}, raw = nil, combat = false }
_G.W = W

function GetTime() return W.clock end
function date() return "00:00:00" end
function InCombatLockdown() return W.combat end
function UnitAffectingCombat() return W.combat end
-- The keyboard's reads: the focused EditBox (W.focus), secure commands, the box's own scripts, sounds, place.
function GetCurrentKeyBoardFocus() return W.focus end
function IsSecureCmd(cmd) return ({ ["/CAST"] = true, ["/USE"] = true, ["/TARGET"] = true, ["/FOCUS"] = true })[cmd:upper()] or false end
function ExecuteFrameScript(frame, script) W.scriptsRun = W.scriptsRun or {} table.insert(W.scriptsRun, script) local fn = frame.scripts and frame.scripts[script] if fn then fn(frame) end end
SOUNDKIT = SOUNDKIT or { GAMEPAD_RADIAL_MENU_OPEN = 1, GAMEPAD_RADIAL_MENU_CLOSE = 2, GAMEPAD_RADIAL_MENU_HIGHLIGHT = 3 }
function PlaySound(id) W.sounds = (W.sounds or 0) + 1 end
function debugprofilestop() return (W.now or 0) * 1000 end
function IsInInstance() return W.instance ~= nil, W.instance or "none" end
function GetInstanceInfo() return W.instanceName or "The Deadmines" end
function GetZoneText() return "Westfall" end
function IsResting() return false end
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	W.log[#W.log + 1] = table.concat(parts, " ")
end
function Mixin(obj, ...)
	for _, m in ipairs({ ... }) do for k, v in pairs(m) do obj[k] = v end end
	return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateAtlasMarkup(a) return "|A:" .. a .. "|a" end
W.cvars = { GamepadFocusStateColor = "3", GamepadFocusStateOpacity = "0.6" }
function GetCVar(name) return W.cvars[name] end
function GetCVarBool() return false end
C_CVar = { GetCVar = function(n) if n == "GamepadFocusStateColor" then return "1" end return "1" end }
Enum = { BindingContext = { GamepadModeInGameCore = 9 } }
Constants = { GamepadActionBarConstants = { NUM_SLOTS_PER_GAMEPAD_ACTION_BAR = 8 } }
RED_FONT_COLOR = { GetRGB = function() return 1, 0.13, 0.13 end }
GREEN_FONT_COLOR = { GetRGB = function() return 0.1, 1, 0.1 end }
function HideUIPanel(f) W.calls[#W.calls + 1] = "HideUIPanel"; f:Hide() end
function hooksecurefunc(t, name, fn) local orig = t[name]; t[name] = function(...) local r = orig(...); fn(...); return r end end
HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }
NORMAL_FONT_COLOR = { GetRGB = function() return 1, 0.82, 0 end }
BLUE_FONT_COLOR = { GetRGB = function() return 0, 0.75, 0.95 end }
InputUtil = { IsGamepadUIEnabled = function() return W.gamepadUI ~= false end }
InputIconTextureSetUtility = {
	GetNormalActiveInputIconButtonTexture = function(k) return "gamepad-ps-" .. k end,
	GetActiveInputIconButtonTextures = function(k) assert(type(k) == "string"); return { [1] = "gamepad-ps-" .. k .. "-normal", [4] = "gamepad-ps-" .. k .. "-focus", [5] = "gamepad-ps-" .. k .. "-disabled" } end,
}
C_Texture = { GetAtlasInfo = function() return { width = 76, height = 75 } end }
-- Taint traps: the panel must never reach these.
W.trapped = {}
local function fromPanel()
	local info = debug.getinfo(3, "Sl")
	-- The core's panel files, and every module file (their tabs are panel code too).
	if info and (info.source:find("/Panel/", 1, true) or info.source:find("/ForeverControllerTweaks_", 1, true)) then return info.source:match("[^/]+$") .. ":" .. tostring(info.currentline) end
end
-- The few reads the panel may make: hiding a leftover tooltip, and SmartNavigation's Pointer for its alpha.
local ALLOWED = {
	GameTooltip = {
		IsShown = function() return W.tooltipShown end,
		GetOwner = function() return W.tooltipOwner end,
		GetAlpha = function() return W.tooltipAlpha or 1 end,
		SetAlpha = function(_, a) W.tooltipAlpha = a end,
	},
	SmartNavigation = { Pointer = function() W.pointer = W.pointer or CreateFrame("Frame") return W.pointer end },
}
local function trap(name)
	return setmetatable({}, {
		__index = function(_, k)
			local allowed = ALLOWED[name] and ALLOWED[name][k]
			if allowed then
				if name == "SmartNavigation" then return allowed() end
				return allowed
			end
			local where = fromPanel()
			if where then error("Panel touched " .. name .. "." .. tostring(k) .. " at " .. where, 2) end
		end,
		__call = function() local where = fromPanel(); if where then error("Panel called " .. name .. " at " .. where, 2) end end,
	})
end
for _, name in ipairs({ "Menu", "MenuUtil", "FrameControlsManager", "SmartNavigation", "GamepadMode", "GamepadSharedUtility", "GameTooltip", "StaticPopup_Show", "StaticPopup_Hide", "ShowUIPanel", "SmartNavigation_MarkFrameFocusable", "InputPromptLegends", "EventRegistry", "CVarCallbackRegistry", "InputDeviceIconSetManager", "TextSizeManager" }) do _G[name] = trap(name) end
SlashCmdList = {}

-- timers
C_Timer = {}
function C_Timer.After(d, fn) W.timers[#W.timers + 1] = { at = W.clock + d, fn = fn } end
function C_Timer.NewTicker(d, fn)
	local t = { every = d, at = W.clock + d, fn = fn, ticker = true }
	function t:Cancel() self.cancelled = true end
	W.timers[#W.timers + 1] = t
	return t
end

-- frames
local Obj = {}
Obj.__index = function(self, k)
	local v = rawget(Obj, k)
	if v ~= nil then return v end
	-- Unknown WoW methods are no-ops; lowercase fields and the panel's own On* hooks stay nil until set.
	if type(k) == "string" and k:match("^%u") and not k:match("^On") then return function() end end
end
local function new(kind, parent)
	local o = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, hooks = {}, w = 0, h = 0, x = 0, y = 0, text = "" }, Obj)
	return o
end
W.new = new
function Obj:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Obj:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Obj:SetShown(s) if s then self:Show() else self:Hide() end end
function Obj:IsShown() return self.shown end
function Obj:IsVisible()
	local o = self
	while o do if not o.shown then return false end o = o.parent end
	return true
end
function Obj:GetParent() return self.parent end
function Obj:SetParent(p) self.parent = p end
function Obj:SetSize(w, h) self.w, self.h = w, h end
function Obj:SetWidth(w) self.w = w end
function Obj:SetHeight(h) self.h = h end
function Obj:GetWidth() return self.w end
function Obj:GetHeight() return self.h end
function Obj:SetPoint(point, rel, relPoint, x, y)
	if type(rel) == "number" then x, y, rel = rel, relPoint, nil
	elseif type(relPoint) == "number" then x, y = relPoint, x end
	-- A second anchor (e.g. RIGHT after TOPLEFT) only stretches the region; keep the position anchor.
	if self.point == "TOPLEFT" and point ~= "TOPLEFT" and not self.cleared then return end
	self.cleared = false
	self.point, self.rel, self.x, self.y = point, rel, x or 0, y or 0
end
function Obj:ClearAllPoints() self.cleared = true end
function Obj:SetAllPoints() end
function Obj:Abs()
	local base = self.rel or self.parent
	local bx, by = 0, 0
	if base and base ~= self and base.Abs then bx, by = base:Abs() end
	return bx + (self.x or 0), by + (self.y or 0)
end
function Obj:GetCenter()
	local x, y = self:Abs()
	if self.point == "TOPLEFT" then return x + self.w / 2, y - self.h / 2 end
	if self.point == "LEFT" then return x + self.w / 2, y end
	return x, y
end
function Obj:SetScript(name, fn) self.scripts[name] = fn end
function Obj:GetScript(name) return self.scripts[name] end
function Obj:HookScript(name, fn) self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], fn) end
function Obj:Fire(name, ...)
	if self.scripts[name] then self.scripts[name](self, ...) end
	for _, fn in ipairs(self.hooks[name] or {}) do fn(self, ...) end
end
function Obj:Click(button) self:Fire("OnClick", button or "LeftButton") end
function Obj:SetText(t) self.text = t or "" end
function Obj:GetText() return self.text end
function Obj:GetStringHeight() return 14 end
function Obj:GetStringWidth() return #(self.text or "") * 6 end
function Obj:SetAlpha(a) self.alpha = a end
function Obj:GetAlpha() return self.alpha or 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetName() return self.frameName end
function Obj:SetDesaturated(d) self.desat = d end
function Obj:EnableMouse(on) self.mouse = on end
function Obj:SetJustifyH(j) self.justify = j end
-- Levels and strata follow the parent unless set, as in the client; GetChildren lists frames only.
function Obj:GetFrameLevel() return self.level or ((self.parent and self.parent.GetFrameLevel and self.parent:GetFrameLevel() or 0) + 1) end
function Obj:GetChildren() return unpack(self.children or {}) end
function Obj:SetFrameLevel(l) self.level = l end
function Obj:SetFrameStrata(s) self.strata = s end
function Obj:GetFrameStrata() return self.strata or (self.parent and self.parent.GetFrameStrata and self.parent:GetFrameStrata()) or "MEDIUM" end
function Obj:GetEffectiveAlpha() return self.alpha or 1 end
function Obj:GetBottom() return self.bottom end
function Obj:GetRect() if self.bottom then return 0, self.bottom, self.w or 0, self.h or 0 end end
function Obj:CreateTexture() local t = new("Texture", self); self.textures = self.textures or {}; table.insert(self.textures, t); return t end
function Obj:CreateMaskTexture() return new("Mask", self) end
function Obj:CreateLine() local l = new("Line", self); self.lines = self.lines or {}; table.insert(self.lines, l); return l end
function Obj:CreateFontString(_, _, font) local fs = new("FontString", self); fs.font = font; self.strings = self.strings or {}; table.insert(self.strings, fs); return fs end
function Obj:SetFontObject(f) self.font = f end
function Obj:SetAtlas(a, _, _, _, wrapH, wrapV) self.atlas, self.wrapH, self.wrapV = a, wrapH, wrapV end
function Obj:AddMaskTexture(m) self.masks = self.masks or {}; table.insert(self.masks, m) end
function Obj:GetAtlas() return self.atlas end
function Obj:SetTexture(t) self.texture = t end
function Obj:GetTexture() return self.texture end
function Obj:GetTexCoord() return 0, 1, 0, 1 end
function Obj:SetPropagateKeyboardInput(p) self.propagate = p end
function Obj:EnableGamePadStick(on) self.stickEnabled = on end
function Obj:SetNormalTexture() self.normal = self.normal or new("Texture", self) end
function Obj:SetPushedTexture() self.pushed = self.pushed or new("Texture", self) end
function Obj:SetDisabledTexture() self.disabled = self.disabled or new("Texture", self) end
function Obj:SetHighlightTexture() self.highlightTex = self.highlightTex or new("Texture", self) end
function Obj:GetNormalTexture() return self.normal end
function Obj:GetPushedTexture() return self.pushed end
function Obj:GetDisabledTexture() return self.disabled end
function Obj:GetHighlightTexture() return self.highlightTex end
function Obj:IsEnabled() return true end
function Obj:SetMinMaxValues() end
function Obj:SetValue(v) self.value = v end
function Obj:GetStatusBarTexture() return self.barTex or new("Texture", self) end
function Obj:SetScale(v) self.scale = v end
function Obj:GetScale() return self.scale or 1 end
function Obj:GetEffectiveScale() return self.scale or 1 end
function Obj:LockHighlight() self.locked = true end
function Obj:UnlockHighlight() self.locked = false end
function Obj:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Obj:IsMouseOver() return false end
function Obj:CreateAnimationGroup()
	local g = new("Anim", self)
	function g:CreateAnimation() return new("A", g) end
	function g:IsPlaying() return self.playing end
	function g:Play() self.playing = true end
	return g
end

local TEMPLATES = {}
TEMPLATES.ForeverControllerTweaksWindowTemplate = function(f)
	f.NineSlice = new("Frame", f)
	f.NineSlice.Text = f:CreateFontString()
	f.ClosePanelButton = new("Button", f)
	f.Bg = new("Frame", f)
	f.shown = false
end
TEMPLATES.InsetFrameTemplate = function(f) f.Bg = f:CreateTexture() end
function CreateFrame(kind, name, parent, template)
	local f = new(kind, parent)
	if parent then parent.children = parent.children or {}; table.insert(parent.children, f) end
	if template then
		for t in template:gmatch("[^,%s]+") do if TEMPLATES[t] then TEMPLATES[t](f) end end
	end
	if name then _G[name], f.frameName = f, name end
	W.frames[#W.frames + 1] = f
	return f
end
UIParent = new("Frame")
UIParent:SetSize(1365, 768)
Minimap = new("Frame", UIParent)
Minimap:SetSize(140, 140)
function GetCursorPosition() return W.cursorX or 0, W.cursorY or 0 end

-- gamepad
C_GamePad = {}
local INDEX = { PADSOCIAL = 7, PADLSHOULDER = 9, PADRSHOULDER = 10, PADLTRIGGER = 30, PADRTRIGGER = 31, PADPADDLE1 = 16, PADPADDLE2 = 17, PADPADDLE3 = 18, PADPADDLE4 = 19 }
function C_GamePad.ButtonBindingToIndex(k) return INDEX[k] end
function C_GamePad.GetActiveDeviceID() return 1 end
function C_GamePad.GetAllDeviceIDs() return { 1 } end
function C_GamePad.GetDeviceRawState() return W.raw end
function C_GamePad.GetDeviceMappedState()
	local buttons = {}
	for key in pairs(W.held) do buttons[INDEX[key] + 1] = true end
	return { buttons = buttons }
end
for _, n in ipairs({ "GetConfig", "SetConfig", "DeleteConfig", "ApplyConfigs" }) do C_GamePad[n] = function() end end
function C_GamePad.GetAllConfigIDs() return {} end

-- action slots
W.actions = {}
GamepadActionBarBindingUtil = {}
function GamepadActionBarBindingUtil.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, id)
	if id >= 5 and id <= 8 then return nil end
	return 200 + (page - 1) * 100 + id
end
function GamepadActionBarBindingUtil.IsStandardGamepadPageNum(n) return n >= 1 and n <= 3 end
Enum.GamepadStanceBarOverride = { None = 0, Page2LeftBar = 5 }
W.cvars.GamepadStanceBarOverride = "5"
function GetBindingAction() return "" end
function HasAction(s) return W.actions[s] ~= nil end
function GetActionTexture(s) return W.actions[s] and ("icon" .. s) end
function GetActionInfo(s)
	local a = W.actions[s]
	if type(a) == "table" then return a[1], a[2] end
	return "spell", s
end
function Obj:SetAttribute(k, v) self.attrs = self.attrs or {}; self.attrs[k] = v end
function Obj:GetAttribute(k) return self.attrs and self.attrs[k] end
function RegisterStateDriver() end
function SecureHandlerSetFrameRef() end
-- catalog stubs
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
Enum.BagIndex = { Backpack = 0 }
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0
Constants.MacroConsts = { MAX_ACCOUNT_MACROS = 120 }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 30 } end,
	GetSpellBookItemInfo = function(slot) return { spellID = 100 + slot, name = "Spell" .. slot, iconID = 1000 + slot } end,
	IsSpellBookItemPassive = function(slot) return slot == 3 end,
	HasPetSpells = function() return 0 end,
}
C_Spell = { GetSpellName = function(id) return "Spell" .. (id - 100) end, PickupSpell = function(id) W.cursor = { "spell", id } end }
C_Container = {
	GetContainerNumSlots = function() return 2 end,
	GetContainerItemInfo = function(_, slot) return ({ { itemID = 6948, iconFileID = 1, itemName = "Hearthstone" }, { itemID = 2, iconFileID = 2, itemName = "Rock" } })[slot] end,
}
C_Item = { GetItemSpell = function(id) return id == 6948 and "Hearthstone" or nil end, PickupItem = function(id) W.cursor = { "item", id } end }
C_MountJournal = {
	GetNumDisplayedMounts = function() return 1 end,
	GetDisplayedMountInfo = function() return "Horse", 458, 3, nil, nil, nil, nil, nil, nil, nil, true, 9 end,
	Pickup = function(i) W.cursor = { "summonmount", i == 0 and 268435455 or 9 } end,
}
W.macros = {}
function GetNumMacros() return #W.macros, 0 end
function GetMacroInfo(i) local m = W.macros[i]; if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body) table.insert(W.macros, { name = name, icon = icon, body = body }); return #W.macros end
function DeleteMacro(i) if type(i) == "number" then table.remove(W.macros, i) end end
function PickupMacro(i) W.cursor = { "macro", i } end
CharacterMicroButton = W.new("Button")
-- The crossbar's top bar buttons 5-8 (Interact, Inspect, Back, Jump), named, for Actions' click texts.
do
	local buttons = {}
	for i = 5, 8 do buttons[i] = { GetName = function() return "GamepadTopBarButton" .. i end } end
	GamepadMainActionBarFrame = { PageUnit = { actionBars = { topBar = { actionButtons = buttons } } } }
end
function GetActionText(s)
	local a = W.actions[s]
	if type(a) == "table" and a[1] == "macro" and W.macros[a[2]] then return W.macros[a[2]].name end
end
C_ActionBar = { HasAction = HasAction, GetActionTexture = GetActionTexture, GetActionText = GetActionText }
-- A1's per-character data and macro registry read the character and the storage slot range.
function UnitName() return "Ann" end
function GetNormalizedRealmName() return "Realm" end
C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 200 end }
function GetCursorInfo() return W.cursor end
function PickupAction(s) W.calls[#W.calls + 1] = "Pickup" .. s; W.cursor, W.actions[s] = W.actions[s], W.cursor end
function PlaceAction(s) W.calls[#W.calls + 1] = "Place" .. s; W.cursor, W.actions[s] = W.actions[s], W.cursor end
function ClearCursor() W.cursor = nil end
function SetOverrideBinding(_, _, key, action) W.override = key .. "->" .. action end
function ClearOverrideBindings() W.override = nil end

-- events
W.eventFrames = {}
local createFrame = CreateFrame
function W.fire(event, ...)
	for _, f in ipairs(W.frames) do
		if f.events and f.events[event] then f:Fire("OnEvent", event, ...) end
	end
end
function Obj:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end

function W.advance(seconds, step)
	step = step or 0.05
	local target = W.clock + seconds
	while W.clock < target do
		W.clock = W.clock + step
		for i = #W.timers, 1, -1 do
			local t = W.timers[i]
			if not t.cancelled and W.clock >= t.at then
				if t.ticker then t.at = W.clock + t.every else table.remove(W.timers, i) end
				t.fn()
			end
		end
		for _, f in ipairs(W.frames) do
			if f.scripts.OnUpdate and f:IsVisible() then f:Fire("OnUpdate", step) end
		end
	end
end

function W.press(window, key)
	window:Fire("OnGamePadButtonDown", key)
	window:Fire("OnGamePadButtonUp", key)
end

return W
