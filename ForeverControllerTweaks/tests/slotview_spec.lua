-- Stubbed WoW check of the slot view API: lua tests/slotview_spec.lua
-- New / SetShape / SetSlot / SetPressed against the native slot's art, states, events and press geometry.
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

local created = {}
local Mock = {}
local NOOP = {}
for name in ("SetScale SetFrameStrata SetFrameLevel SetDesaturated SetColorTexture SetDrawBling SetDrawEdge SetEdgeTexture SetDrawSwipe SetSwipeColor SetUsingParentLevel SetJustifyH RegisterEvent AddMaskTexture SetTexCoord"):gmatch("%S+") do NOOP[name] = function() end end
Mock.__index = function(_, k) return rawget(Mock, k) or NOOP[k] end
local function mock(fields)
	local o = setmetatable(fields or {}, Mock)
	o.shown, o.points = o.shown ~= false, {}
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
function Mock:GetFrameLevel() return 3 end
function Mock:SetSize(w, h) self.w, self.h = w, h end
function Mock:GetSize() return self.w or 0, self.h or 0 end
function Mock:GetWidth() return self.w or 0 end
function Mock:EnableMouse(v) self.mouse = v end
function Mock:SetScript(name, fn) self[name] = fn end
function Mock:ClearAllPoints() self.points = {} end
function Mock:SetAllPoints(rel) self.points = { all = rel or self.parent } end
function Mock:SetPoint(point, rel, relPoint, x, y) self.points[point] = { rel, relPoint, x or 0, y or 0 } end
function Mock:SetAtlas(a) self.atlas, self.file = a, nil end
function Mock:SetTexture(f) self.file, self.atlas = f, nil end
function Mock:SetAlpha(a) self.alpha = a end
function Mock:SetText(t) self.text = t end
function Mock:SetVertexColor(r, g, b) self.color = string.format("%g %g %g", r, g, b) end
function Mock:SetSwipeTexture(t) self.swipe = t end
function Mock:SetHideCountdownNumbers(v) self.hideNumbers = v end
function Mock:SetCooldownFromDurationObject(d) self.duration = d end
function Mock:Clear() self.duration = nil end
function Mock:CreateTexture() return mock({ parent = self }) end
Mock.CreateMaskTexture, Mock.CreateFontString = Mock.CreateTexture, Mock.CreateTexture

UIParent = mock({ name = "UIParent" })
function CreateFrame(_, _, parent, template)
	local f = mock({ parent = parent, template = template })
	if template == "ActionButtonSpellAlertTemplate" then f.ProcStartAnim = { Play = function(a) a.playing = true end, Stop = function(a) a.playing = false end } end
	created[#created + 1] = f
	return f
end
RANGE_INDICATOR, ATTACK_BUTTON_FLASH_TIME = "*", 0.4
RED_FONT_COLOR, ACTIONBAR_HOTKEY_FONT_COLOR = { GetRGB = function() return 1, 0.1, 0.1 end }, { GetRGB = function() return 0.6, 0.6, 0.6 end }
local clock = 100
function GetTime() return clock end
function GetCVarBool() return true end

local actions = { [5] = { texture = 135812, usable = true, cooldown = "cd5", charge = "ch5", loc = "loc5", count = "2", type = "spell", id = 133, equipped = true } }
local overlayed, rangeEnabled = { [133] = true }, {}
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
	IsAttackAction = function() return false end,
	IsEquippedAction = function(s) return actions[s].equipped end,
	EnableActionRangeCheck = function(s, on) rangeEnabled[s] = on or nil end,
}
function GetActionInfo(s) local a = actions[s] if a then return a.type, a.id end end
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return overlayed[id] end }

local lines = {}
local ns = { log = function(m) lines[#lines + 1] = m end, debug = function() end }
assert(loadfile(dir .. "/SlotView.lua"))("ForeverControllerTweaks", ns)
local driver, events
for _, f in ipairs(created) do
	if f.OnUpdate then driver = f end
	if f.OnEvent then events = f end
end
local function fire(event, ...) events.OnEvent(events, event, ...) end
local SlotView = ns.SlotView

-- New: our frame, mouse off, the native circle slot art on its body.
local parent = mock({ name = "Touch" })
local view = SlotView.New(parent)
local body = view.body
check(view.parent == parent and view.mouse == false and body.parent == view, "New: a child of the caller's frame, mouse off, art on its body")
check(view.maskAtlas == "CircleMask" and view.mask.points.TOPLEFT[3] == 3 and view.border.atlas == "gamepad-actionbar-circleslot-border-normal", "circle: CircleMask inset 3, normal frame")
check(view.shadow.atlas == "gamepad-actionbar-circleslot-dropshadow" and view.shadow.points.TOPLEFT[3] == -4 and view.checked.atlas == "gamepad-actionbar-circleslot-border-selected" and view.checked.points.TOPLEFT[3] == -4, "circle: drop shadow out 4, checked frame out 4")
check(view.cooldown.swipe:find("TempPortraitAlphaMask") and view.flash.atlas == "UI-HUD-ActionBar-IconFrame-Flash" and view.icon.points.all == body, "circle: round swipe, native flash, icon fills the body")
check(view.cooldown.points.TOPLEFT[1] == view.icon and view.cooldown.points.TOPLEFT[3] == 3 and view.charge.points.TOPLEFT[3] == 2, "cooldowns anchored to the icon as ActionButtonTemplate.xml (3, charges 2)")
view:SetShape("square")
check(view.maskAtlas == "SquareMask" and view.border.atlas == "gamepad-actionbar-squareslot-border-normal" and view.shadow.atlas == "gamepad-actionbar-squareslot-dropshadow", "square: SquareMask, square frame and shadow")
check(view.checked.atlas == "gamepad-actionbar-squareslot-border-selected" and view.cooldown.swipe:find("WHITE8X8") and view.equipped.atlas == "UI-HUD-ActionBar-IconFrame-Border", "square: checked frame, square swipe, square equipped border")

-- SetSlot: every state of the action slot, with the native calls.
view:SetSize(40, 40)
view:SetSlot(5, 999)
check(view.icon.file == 135812 and view.cooldown.duration == "cd5" and view.loc.duration == "loc5" and view.charge.duration == "ch5", "SetSlot: icon, cooldown, loss-of-control and charge durations")
check(view.count.text == "2" and view.icon.color == "1 1 1" and view.equipped.shown and view.equipped.color == "0 1 0", "SetSlot: count, usable tint, equipped border")
check(view.alert.shown and view.alert.ProcStartAnim.playing and view.alert.w == 56 and not view.checked.shown and not view.flash.shown, "SetSlot: proc glow at 1.4x, not checked, no flash")
check(rangeEnabled[5] and not view.range.shown and view.rangeState == nil, "SetSlot: range check on, nothing shown before its first event")

-- Events: each refreshes its own kind at once; nothing is polled.
actions[5].usable, actions[5].noMana, actions[5].cooldown = false, true, "gcd"
fire("ACTION_USABLE_CHANGED")
check(view.icon.color == "0.5 0.5 1" and view.cooldown.duration == "cd5", "ACTION_USABLE_CHANGED: no-mana tint only")
fire("ACTIONBAR_UPDATE_COOLDOWN")
check(view.cooldown.duration == "gcd", "ACTIONBAR_UPDATE_COOLDOWN: the new (GCD) duration")
fire("ACTION_RANGE_CHECK_UPDATE", 5, false, true)
check(view.range.shown and view.range.color == "1 0.1 0.1" and view.rangeState == "disabled", "range: out of range, red dot, prompt disabled")
fire("ACTION_RANGE_CHECK_UPDATE", 5, true, true)
check(view.range.color == "0.6 0.6 0.6" and view.rangeState == "normal", "range: in range, grey dot")
fire("ACTION_RANGE_CHECK_UPDATE", 6, false, true)
check(view.rangeState == "normal", "range: another slot's event ignored")
overlayed[133], actions[5].current, actions[5].autoRepeat = nil, true, true
fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 133)
fire("ACTIONBAR_UPDATE_STATE")
fire("START_AUTOREPEAT_SPELL")
check(not view.alert.shown and view.checked.shown and view.flash.shown and driver.shown, "glow gone, checked, auto-repeat flash on, blink driver running")
clock = 100.4
driver.OnUpdate(driver, 0.4)
check(not view.flash.shown, "flash blinks off after ATTACK_BUTTON_FLASH_TIME")
actions[5].current, actions[5].autoRepeat = nil, nil
fire("STOP_AUTOREPEAT_SPELL")
driver.OnUpdate(driver, 0.1)
check(not view.flash.shown and not driver.shown, "flash stopped: driver idle")

-- Hidden: no range check, no refresh; shown again it looks again.
view:Hide()
check(not rangeEnabled[5], "hidden: range check off")
actions[5].count = "7"
fire("SPELL_UPDATE_CHARGES")
check(view.count.text == "2", "hidden: events not applied")
view:Show()
check(view.count.text == "7" and rangeEnabled[5], "shown again: full refresh, range check on")

-- Empty or nil slot: the fallback icon, no states, range check off.
actions[6] = nil
view:SetSlot(6, 999)
check(view.icon.file == 999 and view.cooldown.duration == nil and view.count.text == "" and not view.equipped.shown and not view.checked.shown and not rangeEnabled[5], "empty slot: fallback icon, no states, range off")
actions[6] = { texture = 4, usable = true, count = "" }
fire("ACTIONBAR_SLOT_CHANGED", 6)
check(view.icon.file == 4 and rangeEnabled[6], "ACTIONBAR_SLOT_CHANGED: the slot filled, drawn")
view:SetSlot(nil, 12)
check(view.icon.file == 12 and not rangeEnabled[6], "nil slot: fallback icon, range off")

-- SetPressed: the native press geometry (ActionBarStyles.lua:140-148) on the body; the view itself never moves.
local function pressed() return string.format("%g %g %s", body.w, body.points.CENTER[4], view.border.atlas:gsub("^gamepad%-actionbar%-", "")) end
view:SetShape("circle")
view:SetSize(30, 30)
local dy, ds = view:SetPressed(true)
check(pressed() == "26 -2 circleslot-border-pressed" and dy == -2 and ds == -4, "circle collapsed (30), pad press: 4 smaller, down 2, pushed frame (got " .. pressed() .. ")")
view:SetSize(38, 38)
view:SetPressed(true)
check(pressed() == "38 -2 circleslot-border-pressed", "circle expanded (38), pad press: size kept, down 2 (got " .. pressed() .. ")")
view:SetPressed(true, true)
check(pressed() == "38 0 circleslot-border-pressed", "mouse press (a tap): pushed frame only (got " .. pressed() .. ")")
view:SetPressed(false)
check(pressed() == "38 0 circleslot-border-normal", "released: at rest")
view:SetShape("square")
view:SetSize(32, 32)
view:SetPressed(true)
check(pressed() == "28 -2 squareslot-border-pressed", "square collapsed (32), pad press: 4 smaller, down 2 (got " .. pressed() .. ")")
view:SetSize(40, 40)
view.OnSizeChanged(view)
check(pressed() == "40 -2 squareslot-border-pressed", "resized to expanded (40) while pressed: the press follows the size (got " .. pressed() .. ")")
check(view.points.CENTER == nil, "the caller's anchor is never written")

-- An error stops the refreshes with one chat line; the view keeps its last look.
view:SetPressed(false)
view:SetSlot(5, 999)
C_ActionBar.IsUsableAction = function() error("boom") end
fire("ACTION_USABLE_CHANGED")
check(lines[#lines] and lines[#lines]:find("stopped after an error"), "error: one chat line")
local count = #lines
fire("ACTION_USABLE_CHANGED")
check(#lines == count, "error: stays stopped, no repeat line")

print(fails == 0 and "slotview_spec: all checks passed" or ("slotview_spec: " .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
