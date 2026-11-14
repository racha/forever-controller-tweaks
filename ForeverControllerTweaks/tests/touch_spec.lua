-- Stubbed WoW check of the touch bars: lua tests/touch_spec.lua
-- Touch.lua with the real Core, Face and Actions: settings and their limits, the API, slots from the shadow allocator
-- shared with routed cells (no collision), the slot view and press, the tooltip, the secure visibility snippet,
-- combat, the debounced catalog apply, the shared write guard and /fct release.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local unpack = unpack or table.unpack

local W = { char = "Ann", combat = false, conds = {}, cvars = {} }
W.slots = {}
local ns = {}

-- Frames: what Touch uses behaves, the rest of the API is a no-op. Secure frames refuse attribute writes in combat
-- outside a snippet.
local frames, Obj, all = {}, {}, {}
local function new(name, parent, template)
	local o = setmetatable({ attrs = {}, scripts = {}, hooks = {}, shown = true, parent = parent, name = name, protected = template and template:find("Secure") ~= nil }, { __index = function(_, k) return Obj[k] or (k:match("^%u") and function() end) or nil end })
	if name then _G[name], frames[name] = o, o end
	all[#all + 1] = o
	return o
end
local function snippet(self, body)
	local env = setmetatable({ self = self, newtable = function(...) return { ... } end }, { __index = _G })
	local fn = setfenv and setfenv(assert(loadstring("local self = ...\n" .. body)), env) or assert(load("local self = ...\n" .. body, "snippet", "t", env))
	local was = W.secure
	W.secure = true
	pcall(fn, self)
	W.secure = was
end
function Obj:SetAttribute(k, v)
	if W.combat and self.protected and not W.secure then error("ADDON_ACTION_BLOCKED SetAttribute " .. k) end
	self.attrs[k] = v
	local id = k:match("^state%-(.+)")
	if id and self.attrs["_onstate-" .. id] then snippet(self, self.attrs["_onstate-" .. id]) end
end
function Obj:GetAttribute(k) return self.attrs[k] end
function Obj:Execute(body)
	if W.combat then error("ADDON_ACTION_BLOCKED Execute") end
	snippet(self, body)
end
function Obj:GetName() return self.name end
function Obj:SetScript(k, fn) self.scripts[k] = fn end
function Obj:HookScript(k, fn) self.hooks[k] = fn end
function Obj:Show() self.shown = true end
function Obj:Hide() self.shown = false end
function Obj:IsShown() return self.shown end
function Obj:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Obj:SetPoint(...) self.point = { ... } end
function Obj:SetAllPoints(target) self.anchor = target end
function Obj:SetAlpha(alpha) self.alpha = alpha end
function Obj:GetEffectiveAlpha() return (self.alpha or 1) * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function Obj:GetParent() return self.parent end
function Obj:RegisterForClicks(...) self.clicks = table.concat({ ... }, ",") end
function Obj:CreateTexture()
	local texture = new(nil, self)
	function texture:SetAtlas(atlas) self.atlas = atlas end
	self.textures = self.textures or {}
	self.textures[#self.textures + 1] = texture
	return texture
end
function Obj:SetShown(on) self.shown = not not on end
function Obj:SetSize(w, h) self.width, self.height = w, h end
function Obj:WrapScript(target, _, pre) target.wrap = { header = self, pre = pre } end

-- The pad: crossbar modifiers held, as GetGamePadState (1-based button indexes) and IsKeyDown see them.
local INDEX = { PADLTRIGGER = 13, PADRTRIGGER = 14 }
C_GamePad = { ButtonBindingToIndex = function(key) return INDEX[key] end }
W.held = {}
function GetGamePadState() return { buttons = W.held } end
function IsKeyDown(key) return INDEX[key] ~= nil and W.held[INDEX[key] + 1] or false end
local function hold(...)
	W.held = {}
	for _, key in ipairs({ ... }) do W.held[INDEX[key] + 1] = true end
end
-- A tap: the header's wrapped pre-click snippet on the press, as the secure button runs it (combat or not); returns
-- what the click then fires.
local function tap(button)
	local env = setmetatable({}, { __index = _G })
	local body = "local self, button, down = ...\n" .. button.wrap.pre
	local fn = setfenv and setfenv(assert(loadstring(body)), env) or assert(load(body, "tap", "t", env))
	local was = W.secure
	W.secure = true
	fn(button, "LeftButton", true)
	W.secure = was
	local a = button.attrs
	return a.type == "action" and "action " .. a.action or a.type == "macro" and a.macrotext or nil
end
UIParent = new("UIParent")
function CreateFrame(_, name, parent, template) return new(name, parent, template) end
function SecureHandlerSetFrameRef(f, label, ref) f.attrs["frameref-" .. label] = ref end
local drivers = {}
local function evaluate(values)
	for clause in values:gmatch("[^;]+") do
		local conds, value = clause:match("^%s*(.-)%s*([%w]+)%s*$")
		if conds == "" then return value end
		for c in conds:gmatch("%[([^%]]*)%]") do if W.conds[c] then return value end end
	end
end
function RegisterStateDriver(f, state, values)
	if W.combat then error("ADDON_ACTION_BLOCKED RegisterStateDriver") end
	drivers[#drivers + 1] = { f = f, state = state, values = values }
	W.secure = true
	f:SetAttribute("state-" .. state, evaluate(values))
	W.secure = false
end
local function cond(name, on)
	W.conds[name] = on or nil
	W.secure = true
	for _, d in ipairs(drivers) do d.f:SetAttribute("state-" .. d.state, evaluate(d.values)) end
	W.secure = false
end

function print() end
function date() return "00:00:00 " end
function GetTime() return 0 end
function InCombatLockdown() return W.combat end
function GetCVar(k) return W.cvars[k] end
function GetCVarBool(k) return W.cvars[k] == "1" end
function UnitName() return W.char end
function GetNormalizedRealmName() return "Realm" end
InputUtil = { IsGamepadUIEnabled = function() return W.ui ~= false end }
SlashCmdList = {}
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
local afters = {}
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) afters[#afters + 1] = fn end }
local function nextFrame()
	local list = afters
	afters = {}
	for _, fn in ipairs(list) do fn() end
	return #list
end
GameTooltip = {
	SetOwner = function(_, owner) W.tooltipOwner = owner end,
	SetAction = function(_, slot) W.tooltip = slot; return true end,
	IsOwned = function(_, owner) return W.tooltipOwner == owner end,
	Hide = function() W.tooltip = nil end,
}
function GameTooltip_SetDefaultAnchor(_, owner) W.tooltipOwner = owner end

-- Action slots, cursor, spellbook, one item; macros for game entries.
local slots, macros = W.slots, {}
C_ActionBar = {}
-- No deprecated globals (loadDeprecationFallbacks off): only C_ActionBar answers.
assert(HasAction == nil and GetActionText == nil, "deprecated action globals must stay unstubbed")
function C_ActionBar.HasAction(slot) return slots[slot] ~= nil end
function C_ActionBar.GetActionText(slot) local a = slots[slot]; return a and a.name end
function GetActionInfo(slot) local a = slots[slot]; if a then return a.kind, a.id end end
function GetCursorInfo() return W.cursor and W.cursor.kind end
function ClearCursor() W.cursor = nil end
function PlaceAction(slot) W.cursor, slots[slot] = slots[slot], W.cursor end
function PickupAction(slot) W.cursor, slots[slot] = slots[slot], nil end
function GetNumMacros() return #macros, 0 end
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
function GetMacroBody(i) return macros[i] and macros[i][3] end
function CreateMacro(name, icon, body) macros[#macros + 1] = { name, icon, body }; ns.Fire("UPDATE_MACROS"); return #macros end
function DeleteMacro(i) table.remove(macros, i); ns.Fire("UPDATE_MACROS") end
function PickupMacro(i) W.cursor = { kind = "macro", id = i, name = macros[i][1] } end
C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 181 end }
C_Spell = { GetSpellName = function(id) return ({ [133] = "Fireball", [4321] = "Swift Horse" })[id] end, PickupSpell = function(id) W.cursor = { kind = "spell", id = id } end }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
	GetSpellBookItemInfo = function(_, bank) if bank == 0 then return { spellID = 133, name = "Fireball" } end end,
	IsSpellBookItemPassive = function() return false end,
	HasPetSpells = function() return 0 end,
}
function GetInventoryItemID(_, slot) if slot == 13 then return 111 end end
function GetInventoryItemTexture() return 5 end
C_Item = { GetItemSpell = function(id) if id == 111 then return "Use" end end, GetItemNameByID = function(id) if id == 111 then return "Badge" end end, PickupItem = function(id) W.cursor = { kind = "item", id = id } end }
local top = {}
for i = 1, 8 do top[i] = new("TopButton" .. i) end
GamepadMainActionBarFrame = { PageUnit = { actionBars = { topBar = { actionButtons = top } } } }

for _, file in ipairs({ "Core.lua", "Layout.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
ns.Device = { Current = function() return { key = "054c/0ce6" } end, SwapTargets = function() return false end }
-- SlotView (its own spec) only records what Touch asks of it.
ns.SlotView = { New = function(parent)
	local view = new(nil, parent)
	function view:SetSlot(slot, icon) self.slot, self.fallback = slot, icon end
	function view:SetPressed(pressed, byMouse) self.pressed, self.byMouse = pressed, byMouse end
	function view:SetShape(shape) self.shape = shape end
	return view
end }
for _, file in ipairs({ "Face.lua", "Actions.lua" }) do assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", ns) end
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks")
-- A module file as the game loads it: its own addon name and private table; it reads the core's namespace global.
local function loadModule(file) assert(loadfile(here .. "/../../ForeverControllerTweaks_Touch/" .. file .. ".lua"))("ForeverControllerTweaks_Touch", {}) end
loadModule("Touch")
ns.Fire("ADDON_LOADED", "ForeverControllerTweaks_Touch")
ns.db.options.debug = true
ns.Fire("PLAYER_ENTERING_WORLD")

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

local Touch = ns.Touch
local touchConfig = Touch.Config()
local leftSide = touchConfig.sides.left
check(touchConfig.enabled == false and touchConfig.show == "gamepad" and leftSide.count == 6 and leftSide.size == 52 and leftSide.alpha == 1 and touchConfig.sides.right.inset == 24 and next(touchConfig.bars.left) == nil, "touch: defaults per character, layout per side")
check(not frames.ForeverControllerTweaksTouch.shown and Touch.Button("left", 1) == nil, "touch: off by default, nothing made")
for _, bad in ipairs({ { "show", "sometimes" }, { "enabled", "yes" }, { "showEmpty", true }, { "count", 6 }, { "bars", {} }, { "nope", 1 } }) do
	check(not Touch.Set(bad[1], bad[2]), "touch: Set refuses " .. bad[1] .. " = " .. tostring(bad[2]))
end
for _, bad in ipairs({ { "left", "count", 13 }, { "left", "count", 0 }, { "right", "count", 2.5 }, { "left", "size", 300 }, { "right", "alpha", 0 }, { "left", "show", "always" }, { "up", "size", 40 } }) do
	check(not Touch.SetSide(bad[1], bad[2], bad[3]), "touch: SetSide refuses " .. table.concat({ bad[1], bad[2], tostring(bad[3]) }, " "))
end
W.combat = true
check(select(2, Touch.Set("enabled", true)) == "Controller Tweaks changes the touch bars out of combat only." and not touchConfig.enabled, "touch: Set out of combat only")
W.combat = false
local touchReasons = {}
ns.On("FCT_LAYOUT_CHANGED", function(reason) touchReasons[#touchReasons + 1] = reason end)
assert(Touch.Set("enabled", true))
local header = frames.ForeverControllerTweaksTouch
check(touchReasons[#touchReasons] == "touch" and header.shown and Touch.Button("right", 6) and Touch.Button("left", 7) == nil, "touch: on, six buttons a side, shown with the Gamepad UI")
local first = Touch.Button("left", 1)
check(first.parent.point[1] == "LEFT" and first.parent.point[4] == 24 and Touch.Button("right", 1).parent.point[4] == -24 and Touch.Button("left", 2).point[5] == -58, "touch: bars on the screen edges, buttons stacked size + gap")

-- Slots come from the allocator the routed cells use: no collision with a face shadow slot, each button its own.
-- A routed cell's shadow slot, as Face places it.
local faceSlot = ns.Actions.Shadow("FB", "T", ns.Actions.Find("spell:133"))
assert(Touch.SetEntry("left", 1, ns.Actions.Find("spell:133")))
assert(Touch.SetEntry("right", 1, ns.Actions.Find("item:111")))
local leftSlot, rightSlot = first.attrs.action, Touch.Button("right", 1).attrs.action
local shadows = ns.db.chars["Ann-Realm"].shadow
check(first.attrs.type == "action" and first.attrs.typerelease == "actionrelease" and W.slots[leftSlot].id == 133 and W.slots[rightSlot].id == 111, "touch: entries on their own action slots")
check(leftSlot >= 145 and leftSlot <= 180 and rightSlot >= 145 and rightSlot <= 180 and faceSlot and leftSlot ~= faceSlot and rightSlot ~= faceSlot and leftSlot ~= rightSlot, "touch: no collision with the routed cells' slots")
check(shadows[leftSlot].code == "TLT" and shadows[leftSlot].layer == 1 and shadows[faceSlot].code == "FB", "touch: owned per character, keyed apart")
check(Touch.Entry("left", 1).id == "spell:133" and Touch.Entry("left", 2) == nil, "touch: Entry reads back")
assert(ns.Actions.ReleaseShadow("FB", "T"))
-- The native look: a SlotView over the whole button on the button's slot; a tap presses it (pushed frame only).
local view = first.view
check(view and view.parent == first and view.anchor == first and view.slot == leftSlot and view.fallback == ns.Actions.Find("spell:133").icon, "touch: the view covers the button and draws its slot")
-- The bug seen in game: slot-backed buttons drew nothing (an unanchored view, and the icon cleared because a slot
-- existed), only the slotless Jump showed. Each assigned button logs its slot, visibility and alpha.
local function touchLine(side, i)
	local found
	for _, line in ipairs(ns.db.debugLog) do if line:find(("touch %s %d "):format(side, i), 1, true) then found = line end end
	return found or ""
end
check(touchLine("left", 1):find("spell:133 slot=" .. leftSlot .. " type=action shown=true alpha=1.00", 1, true) and touchLine("right", 1):find("item:111 slot=" .. rightSlot, 1, true), "touch: debug line per button: entry, slot, type, shown, alpha")
first.scripts.OnMouseDown(first, "LeftButton")
check(view.pressed == true and view.byMouse == true, "touch: mouse down presses the view")
first.scripts.OnMouseUp(first, "LeftButton")
check(not view.pressed, "touch: mouse up releases it")
first.scripts.OnEnter(first)
check(W.tooltip == leftSlot and W.tooltipOwner == first, "touch: the slot's tooltip on hover")
first.scripts.OnLeave(first)
-- A face action clicks its reserved button down and up; Lua bindings and bad buttons are refused.
assert(Touch.SetEntry("left", 2, ns.Actions.Find("face:jump")))
check(Touch.Button("left", 2).attrs.type == "macro" and Touch.Button("left", 2).attrs.macrotext == ns.Face.ClickBoth("TopButton8"), "touch: Jump as the routed both-click")
check(Touch.Button("left", 2).view.slot == nil and Touch.Button("left", 2).view.fallback == ns.Actions.Find("face:jump").icon, "touch: a face action draws its icon")
check(select(2, Touch.SetEntry("left", 3, { id = "addon:X", name = "X", disabled = true, note = "needs a key binding" })) == "needs a key binding", "touch: Lua binding refused")
check(not Touch.SetEntry("up", 1, ns.Actions.Find("face:jump")) and not Touch.SetEntry("left", 13, ns.Actions.Find("face:jump")), "touch: unknown button refused")
-- The player's own change to a touch slot: given up as is, a new slot taken.
W.slots[leftSlot] = { kind = "spell", id = 4321 }
ns.Fire("PLAYER_ENTERING_WORLD")
local moved = first.attrs.action
check(moved ~= leftSlot and W.slots[moved].id == 133 and W.slots[leftSlot].id == 4321 and shadows[leftSlot] == nil, "touch: foreign change given up, a new slot taken")
check(view.slot == moved, "touch: the view follows the new slot")
W.slots[leftSlot] = nil
assert(Touch.SetEntry("left", 1, nil))
check(W.slots[moved] == nil and shadows[moved] == nil and first.attrs.type == nil, "touch: cleared button gives its slot back")
check(view.slot == nil and view.fallback == nil, "touch: a cleared button draws empty")
-- No free slot left on bars 6-8: refused with the allocator's reason, nothing stored.
local filled = {}
for slot = 145, 180 do
	if not W.slots[slot] then W.slots[slot], filled[#filled + 1] = { kind = "spell", id = 4321 }, slot end
end
local _, fullErr = Touch.SetEntry("left", 4, ns.Actions.Find("spell:133"))
check(tostring(fullErr):find("No free action slot", 1, true) and Touch.Entry("left", 4) == nil, "touch: bars 6-8 full, refused")
for _, slot in ipairs(filled) do W.slots[slot] = nil end
-- Cleared with the Gamepad UI off: the slot is kept until it is on again.
W.ui = false
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
assert(Touch.SetEntry("right", 1, nil))
check(W.slots[rightSlot].id == 111, "touch: off, the slot waits")
W.ui = nil
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
check(W.slots[rightSlot] == nil and shadows[rightSlot] == nil, "touch: on again, the slot given back")

-- Visibility runs in the header's secure snippet: combat-only, never, always without the Gamepad UI.
assert(Touch.Set("show", "combat"))
check(not header.shown, "touch: combat only, hidden out of combat")
cond("combat", true)
check(header.shown, "touch: combat only, shown in combat")
cond("combat", false)
assert(Touch.Set("show", "never"))
check(not header.shown, "touch: never")
W.ui = false
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
assert(Touch.Set("show", "gamepad"))
check(not header.shown, "touch: gamepad mode hides without the Gamepad UI")
assert(Touch.Set("show", "always"))
check(header.shown, "touch: always shows without it")
W.ui = nil
ns.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
assert(Touch.Set("show", "gamepad"))
assert(Touch.SetSide("left", "count", 3))
local jump, third = Touch.Button("left", 2), Touch.Button("left", 3)
check(jump.shown and not third.shown and not Touch.Button("left", 4).shown and first.parent.point[4] == 24, "touch: count hides the rest")
-- Empty buttons hide in play (no black disc); the filled ones keep their places.
check(not first.shown and jump.point[5] == -58, "touch: an empty button is hidden, the next one stays where it was")
ns.SetPanelOpen(true)
check(third.shown and not third.view.shown and third.empty.shown and third.empty.alpha == 0.5 and not Touch.Button("left", 4).shown, "touch: our window open: empty buttons show, dimmed, without the view")
check(third.empty.textures[1].atlas == "gamepad-actionbar-slot-bg-empty" and third.empty.textures[2].atlas == "gamepad-actionbar-circleslot-border-normal", "touch: the native empty-slot art")
check(jump.view.shown and not jump.empty.shown, "touch: a filled button keeps its view")
ns.SetPanelOpen(false)
check(not third.shown, "touch: window closed: hidden again")
check(not Touch.SetSide("left", "showEmpty", "yes") and Touch.SetSide("left", "showEmpty", true) and third.shown and third.empty.shown, "touch: show empty buttons in play")
assert(Touch.SetSide("left", "showEmpty", false))
check(not third.shown, "touch: off again")
-- An apply in combat waits for the end and touches no protected frame.
W.combat = true
ns.Fire("FCT_CATALOG_CHANGED", "SPELLS_CHANGED")
W.combat = false
ns.Fire("PLAYER_REGEN_ENABLED")
local touchFailed = false
for _, line in ipairs(ns.db.debugLog) do if line:find("touch apply failed", 1, true) then touchFailed = true end end
check(not touchFailed, "touch: no apply failed")
assert(Touch.Set("enabled", false))
check(not header.shown, "touch: off again")


-- The Touch tab reads the limits Set enforces.
check(Touch.LIMITS.count[2] == 12 and Touch.LIMITS.size[1] == 24 and Touch.LIMITS.alpha[1] == 0.1, "touch: LIMITS exported")

-- A catalog change re-applies once per frame, and only for text events with entries assigned.
assert(Touch.Set("enabled", true))
assert(Touch.SetEntry("left", 1, ns.Actions.Find("spell:133")))
nextFrame()
local before = #ns.db.debugLog
ns.Fire("FCT_CATALOG_CHANGED", "BAG_UPDATE_DELAYED")
check(#afters == 0, "touch: a bag change applies nothing")
ns.Fire("FCT_CATALOG_CHANGED", "SPELLS_CHANGED")
ns.Fire("FCT_CATALOG_CHANGED", "UPDATE_MACROS")
check(#afters == 1 and #ns.db.debugLog == before, "touch: text events queue one apply, none yet")
nextFrame()
check(touchLine("left", 1):find("spell:133", 1, true) and #ns.db.debugLog > before, "touch: applied on the next frame")

-- A slot write in progress holds the apply off; the write's own caller applies after.
local skipped
ns.On("UPDATE_MACROS", function()
	local was = #ns.db.debugLog
	nextFrame()
	ns.Touch.SetSide("left", "alpha", 0.9)
	skipped = #ns.db.debugLog == was
end)
assert(Touch.SetEntry("left", 2, ns.Actions.Find("game:sit")))
check(skipped, "touch: no apply while Actions writes a slot")

-- Per side: each bar its own count, size, gap, inset (X from its edge), offsetY and alpha.
for key, value in pairs({ count = 4, size = 64, gap = 10, inset = 40, offsetY = 30, alpha = 0.7 }) do assert(Touch.SetSide("right", key, value)) end
local rightBar, leftBar = Touch.Button("right", 1).parent, Touch.Button("left", 1).parent
check(rightBar.point[1] == "RIGHT" and rightBar.point[4] == -40 and rightBar.point[5] == 30 and rightBar.alpha == 0.7 and rightBar.height == 4 * 64 + 3 * 10, "touch: right bar placed and sized from its own settings")
check(Touch.Button("right", 2).point[5] == -74 and Touch.Button("right", 2).width == 64 and Touch.Button("left", 2).width == 52, "touch: right buttons stacked by their own size and gap")
check(leftBar.point[4] == 24 and leftBar.point[5] == 0 and leftBar.alpha == 0.9 and Touch.Button("left", 2).point[5] == -58, "touch: the left bar keeps its own")

-- Layers: one entry per crossbar layer. A tap fires the layer held at that moment, in combat too; on a layer without
-- an entry the button is empty: the tap does nothing (no fallback to T). Each filled layer has its own shadow slot,
-- from the allocator routed cells share.
local btn = Touch.Button("left", 1)
assert(Touch.SetEntry("left", 1, ns.Actions.Find("item:111"), "L"))
assert(Touch.SetEntry("left", 1, ns.Actions.Find("face:jump"), "B"))
check(not Touch.SetEntry("left", 1, ns.Actions.Find("item:111"), "X") and Touch.Entry("left", 1, "L").id == "item:111" and Touch.Entry("left", 1).id == "spell:133", "touch: Entry and SetEntry per layer, T by default")
local slotT, slotL = btn.attrs["ps-action-T"], btn.attrs["ps-action-L"]
check(slotT and slotL and slotT ~= slotL and W.slots[slotL].id == 111 and shadows[slotL].code == "TLL" and shadows[slotL].layer == 1, "touch: a slot per filled layer, keyed side + layer")
check(btn.attrs["ps-ileftmod"] == 14 and btn.attrs["ps-irightmod"] == 15, "touch: the crossbar modifiers' pad indexes for the snippet")
W.combat = true
hold()
check(tap(btn) == "action " .. slotT, "touch: no modifier: T")
hold("PADLTRIGGER")
check(tap(btn) == "action " .. slotL and btn.attrs.typerelease == "actionrelease" and btn.attrs.checkselfcast, "touch: L2 held: L, released as an action")
hold("PADRTRIGGER")
check(tap(btn) == nil and btn.attrs.action == nil and btn.attrs.macrotext == nil, "touch: R2 held, R empty: the tap does nothing, no fallback")
hold("PADLTRIGGER", "PADRTRIGGER")
check(tap(btn) == ns.Face.ClickBoth("TopButton8") and btn.attrs.typerelease == nil and not btn.attrs.checkselfcast, "touch: both held: B, Jump's both-click")
W.combat = false

-- The display follows the held layer without a tap, in combat too: the shown layer's slot and icon; an empty layer
-- draws nothing in play.
local watcher
for _, f in ipairs(all) do if f.parent == frames.ForeverControllerTweaksTouch and f.scripts.OnUpdate then watcher = f end end
local function frame() watcher.scripts.OnUpdate(watcher, 0.016) end
hold("PADLTRIGGER")
frame()
check(Touch.Layer() == "L" and btn.view.slot == slotL and btn.slot == slotL and btn.view.fallback == ns.Actions.Find("item:111").icon, "touch: L2 held: the L entry drawn, its tooltip slot")
W.combat = true
hold("PADRTRIGGER")
frame()
check(Touch.Layer() == "R" and not btn.view.shown and not btn.empty.shown and btn.slot == nil and btn.shown, "touch: R empty: nothing drawn, no tooltip slot, the secure button left as it is")
hold("PADLTRIGGER", "PADRTRIGGER")
frame()
check(btn.view.slot == nil and btn.view.fallback == ns.Actions.Find("face:jump").icon, "touch: both held: Jump's icon")
hold()
frame()
check(Touch.Layer() == "T" and btn.view.shown and btn.view.slot == slotT, "touch: released: T again at once")
-- A button with nothing on T but an L entry: invisible until L2 is held, and its plain tap does nothing.
local onlyL = Touch.Button("left", 3)
W.combat = false
assert(Touch.SetEntry("left", 3, ns.Actions.Find("item:111"), "L"))
W.combat = true
frame()
check(onlyL.shown and not onlyL.view.shown and not onlyL.empty.shown and tap(onlyL) == nil, "touch: L-only button, no modifier: hidden, the tap does nothing")
hold("PADLTRIGGER")
frame()
check(onlyL.view.shown and onlyL.view.slot == onlyL.attrs["ps-action-L"] and tap(onlyL) == "action " .. onlyL.attrs["ps-action-L"], "touch: L2 held: it appears and fires")
hold()
frame()
check(not onlyL.view.shown, "touch: L2 let go: hidden again")
W.combat = false
-- Previewing (our window open), an empty layer shows the dimmed empty-slot art instead.
ns.SetPanelOpen(true)
hold("PADRTRIGGER")
frame()
check(btn.empty.shown and not btn.view.shown, "touch: previewing: an empty layer shows the empty-slot art")
hold()
frame()
ns.SetPanelOpen(false)
assert(Touch.SetEntry("left", 3, nil, "L"))

-- Slot accounting: touch layers and routed cells share bars 6-8's 36 slots; the cap is reported, then enforced.
local used, free, total = Touch.SlotsUsed()
local faceSlot2 = ns.Actions.Shadow("FB", "T", ns.Actions.Find("spell:133"))
local used2, free2 = Touch.SlotsUsed()
check(total == 36 and used2 == used + 1 and free2 == free - 1 and faceSlot2 ~= slotT and faceSlot2 ~= slotL, "touch: SlotsUsed counts routed cells and touch layers in one range")
local blocked = {}
for slot = 145, 180 do
	if not W.slots[slot] then W.slots[slot], blocked[#blocked + 1] = { kind = "spell", id = 4321 }, slot end
end
local _, capErr = Touch.SetEntry("left", 1, ns.Actions.Find("spell:133"), "R")
check(select(2, Touch.SlotsUsed()) == 0 and tostring(capErr):find("none is free", 1, true) and Touch.Entry("left", 1, "R") == nil, "touch: no free slot: a clear reason, nothing stored")
for _, slot in ipairs(blocked) do W.slots[slot] = nil end
assert(ns.Actions.ReleaseShadow("FB", "T"))
assert(Touch.SetEntry("left", 1, nil, "L"))
check(W.slots[slotL] == nil and shadows[slotL] == nil and btn.attrs["ps-action-L"] == nil, "touch: an emptied layer gives its slot back")

-- Settings and attributes change out of combat only; an apply asked for in combat waits for the end.
W.combat = true
check(not Touch.SetSide("left", "size", 40) and not Touch.SetEntry("left", 1, nil, "B"), "touch: SetSide and SetEntry refused in combat")
ns.Fire("FCT_LAYOUT_CHANGED", "layout")
W.combat = false
ns.Fire("PLAYER_REGEN_ENABLED")

-- Shape per side: SlotView's native circle or square art, and the empty-slot border to match.
check(btn.view.shape == "circle" and Touch.Button("right", 1).view.shape == "circle", "touch: circle by default")
check(not Touch.SetSide("right", "shape", "hexagon") and not Touch.SetSide("right", "shape", true), "touch: shape refuses other values")
assert(Touch.SetSide("right", "shape", "square"))
local rightFirst = Touch.Button("right", 1)
check(rightFirst.view.shape == "square" and rightFirst.empty.border.atlas == "gamepad-actionbar-squareslot-border-normal" and btn.view.shape == "circle" and btn.empty.border.atlas == "gamepad-actionbar-circleslot-border-normal", "touch: square on the right only, border included")
check(Touch.Config().sides.right.shape == "square" and touchReasons[#touchReasons] == "touch", "touch: shape stored per side, layout message sent")
check(Touch.LIMITS.shape.values[1] == "circle" and Touch.LIMITS.shape.values[2] == "square" and Touch.LIMITS.showEmpty.boolean, "touch: LIMITS name the shapes and showEmpty as a boolean")

-- showEmpty per side with an empty layer held: off hides it in play, on shows the faint empty slot; both tap nothing.
W.combat = true
hold("PADRTRIGGER")
frame()
check(not btn.view.shown and not btn.empty.shown and tap(btn) == nil, "touch: showEmpty off: the empty R layer is hidden, its tap does nothing")
W.combat = false
assert(Touch.SetSide("left", "showEmpty", true))
W.combat = true
frame()
check(not btn.view.shown and btn.empty.shown and btn.empty.alpha == 0.5 and tap(btn) == nil, "touch: showEmpty on: the faint empty slot, the tap still does nothing")
check(not Touch.SetSide("left", "showEmpty", false), "touch: showEmpty out of combat only")
W.combat = false
hold()
frame()
check(btn.view.shown and not btn.empty.shown, "touch: back on T, the filled entry")
assert(Touch.SetSide("left", "showEmpty", false))
assert(Touch.SetSide("right", "shape", "circle"))
check(not Touch.SetSide("left", "showEmpty", "yes") and Touch.Config().sides.right.showEmpty == false, "touch: showEmpty refuses a non-boolean; the right side keeps its own")

-- Reset: one side's layout, or both, back to the defaults; assignments and their slots stay.
for key, value in pairs({ count = 5, size = 70, inset = 60, shape = "square", showEmpty = true }) do assert(Touch.SetSide("left", key, value)) end
assert(Touch.SetSide("right", "size", 80))
local keptSlot = btn.attrs["ps-action-T"]
W.combat = true
check(not Touch.Reset("left") and Touch.Config().sides.left.size == 70, "touch: Reset out of combat only")
W.combat = false
check(not Touch.Reset("up"), "touch: Reset refuses an unknown side")
check(Touch.Reset("left") and touchReasons[#touchReasons] == "touch", "touch: Reset left")
local resetLeft = Touch.Config().sides.left
check(resetLeft.count == 6 and resetLeft.size == 52 and resetLeft.inset == 24 and resetLeft.shape == "circle" and resetLeft.showEmpty == false and resetLeft.alpha == 1 and Touch.Config().sides.right.size == 80, "touch: the left side's defaults back, the right untouched")
check(Touch.Entry("left", 1).id == "spell:133" and btn.attrs["ps-action-T"] == keptSlot and W.slots[keptSlot].id == 133 and shadows[keptSlot] and btn.view.shape == "circle", "touch: assignments and their slots kept, buttons redrawn")
check(Touch.Reset() and Touch.Config().sides.right.size == 52 and Touch.Config().sides.right.count == 6, "touch: Reset() resets both sides")

-- Migration: the single settings go to both sides, each old entry becomes its button's T entry, its slot follows.
ns.db.chars["Bob-Realm"] = {
	touch = { enabled = true, show = "always", showEmpty = true, count = 4, size = 40, gap = 2, inset = 10, offsetY = 5, alpha = 0.8, bars = { left = { [2] = { id = "spell:133", name = "Fireball", kind = "spell" } } } },
	shadow = { [170] = { code = "TL", layer = 2, id = "spell:133", holds = "spell:133" } },
}
local heldBefore = W.slots[170]
W.slots[170] = { kind = "spell", id = 133 }
W.char = "Bob"
ns.Fire("PLAYER_ENTERING_WORLD")
local bob = Touch.Config()
check(bob.sides.left.count == 4 and bob.sides.right.size == 40 and bob.sides.right.alpha == 0.8 and bob.sides.left.inset == 10 and bob.count == nil and bob.enabled and bob.show == "always", "touch: migration: old settings on both sides")
check(Touch.Entry("left", 2).id == "spell:133" and Touch.Entry("left", 2, "L") == nil and ns.db.chars["Bob-Realm"].shadow[170].code == "TLT", "touch: migration: the entry is T, its slot keyed for T")
check(bob.sides.left.showEmpty == true and bob.sides.right.showEmpty == true and bob.showEmpty == nil and bob.sides.left.shape == "circle", "touch: migration: the old global showEmpty on both sides, circles")
-- A config already per side but with the global showEmpty of the build before: copied to both sides once.
ns.db.chars["Cat-Realm"] = { touch = { enabled = false, show = "gamepad", showEmpty = true, sides = { left = { count = 3, showEmpty = false }, right = { count = 2 } }, bars = {} } }
W.char = "Cat"
local cat = Touch.Config()
check(cat.showEmpty == nil and cat.sides.right.showEmpty == true and cat.sides.left.showEmpty == false and cat.sides.left.count == 3, "touch: migration: global showEmpty fills a side that has none")
W.char = "Bob"
check(Touch.Button("left", 2).attrs["ps-action-T"] == 170, "touch: migration: the same slot, nothing re-placed")
W.char = "Ann"
W.slots[170] = heldBefore
ns.Fire("PLAYER_ENTERING_WORLD")

local failedApply = false
for _, line in ipairs(ns.db.debugLog) do if line:find("touch apply failed", 1, true) then failedApply = true end end
check(not failedApply, "touch: no apply failed, combat included")

-- /fct release gives the touch slots back; the buttons fall back to text until /reload.
local touchSlot = Touch.Button("left", 1).attrs.action
SlashCmdList.FOREVERCONTROLLERTWEAKS("release")
check(slots[touchSlot] == nil and Touch.Button("left", 1).attrs.type == "macro" and Touch.Button("left", 1).attrs.macrotext == "/cast Fireball", "touch: released, the button runs its text")

io.stdout:write(("touch_spec: %d checks passed\n"):format(checks))
