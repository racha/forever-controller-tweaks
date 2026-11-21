-- Bindings window with the back paddles, on the full panel stub (real TOC files, Glyphs aside), an Xbox Elite pad:
-- lua tests/bindings_spec.lua. A paddle without a role is an action row (four cells, routed entries), one with a role a
-- role row; the role list switches between them, asks before parking a paddle's actions, and the focus follows.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local W = dofile(here .. "/panel_stub.lua")
local raw = { name = "Test Pad", vendorID = 0x045e, productID = 0x0b00, rawButtons = {}, rawAxes = {} }
for i = 0, 20 do raw.rawButtons[i] = false end
for i = 0, 9 do raw.rawAxes[i] = 0 end
W.raw = raw
local ns = {}
for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
	if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
end
local UI = ns.UI
W.fire("ADDON_LOADED", "ForeverControllerTweaks")
W.fire("PLAYER_LOGIN")
W.fire("PLAYER_ENTERING_WORLD")
W.advance(2.5)
UI.CloseAll()

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end
UI.Bindings.Open()
local b = UI.Current()
local function rowOf(code)
	for _, n in ipairs(b.nodes) do
		local row = n.region.row
		if row and row.code == code and row:IsShown() then return row end
	end
end
local function nodeOf(region)
	for _, n in ipairs(b.nodes) do if n.region == region then return n end end
end
-- A layout change redraws the window on the next frame (UI.RefreshSoon).
local function nextFrame() W.advance(0.05) end
local function pickerRows()
	local out = {}
	for _, f in ipairs(W.frames) do
		if f.tick and f.name and f:IsVisible() and f.index then out[f.index] = { name = f.name.text, note = f.note.text } end
	end
	return out
end

-- A free paddle (no role): an action row, four square cells, its own glyph; the name line is the action, the sub
-- line names the paddle and the bar.
for _, code in ipairs({ "P1", "P2", "P3", "P4" }) do
	local row = rowOf(code)
	check(row and row.kind == "slot" and #row.cells == 4 and not row.plate and row.glyph.code == code, code .. ": free paddle, action row")
	check(row.cells[1].shape == "squareslot" and row.cells[1].slot == nil, code .. ": square cells without a storage slot")
end
local p1 = rowOf("P1")
check(p1.name.text == "Not bound" and p1.sub.text == "Back paddle 1 · TOP bar", "P1 names: " .. tostring(p1.name.text) .. " / " .. tostring(p1.sub.text))

-- An entry on a paddle cell goes through the router (no slot), and shows on the cell.
assert(ns.Face.SetCellEntry("P1", "R", { id = "face:jump", name = "Jump", icon = 7 }, 1))
b:Refresh()
p1 = rowOf("P1")
check(p1.cells[3].entry and p1.cells[3].entry.id == "face:jump" and p1.cells[3].icon.texture == 7, "P1/R shows its routed entry")

-- More on a paddle cell: Healer mode first (greyed: without the Rings module, and the top cell is empty), then its role
-- list. Picking a role there asks first (the paddle holds actions).
b:Focus(nodeOf(p1.cells[1]))
W.press(b, "PAD4")
local more = pickerRows()
check(more[1] and more[1].name == "Healer mode: Off" and more[1].note == "Spells and items", "More: Healer mode first, greyed, got " .. tostring(more[1] and more[1].name))
check(more[2] and more[2].name == "Back paddle 1: role", "More: the paddle's role list next, got " .. tostring(more[2] and more[2].name))
UI.ActionPicker.Choose(2)
local roles = pickerRows()
check(roles[5] and roles[5].name == "None" and roles[5].note == "use it for actions", "role list: None says it frees the paddle for actions")
UI.ActionPicker.Choose(1)
check(UI.DialogShown() and ns.Layout.Roles().P1 == nil, "a role on a paddle with actions: confirm first, nothing changed yet")
UI.Dialog():Press(2)
check(ns.Layout.Roles().P1 == nil and rowOf("P1").kind == "slot", "Cancel: still free")

b:Focus(nodeOf(rowOf("P1").cells[1]))
W.press(b, "PAD4")
UI.ActionPicker.Choose(2)
UI.ActionPicker.Choose(1)
UI.Dialog():Press(1)
nextFrame()
local mod = rowOf("P1")
check(ns.Layout.Roles().P1 == "leftmod" and mod.kind == "mod" and mod.plate and mod.name.text == "Left bar", "Change role: P1 is a role row")
check(b.focus.region == mod.plate, "the focus follows to the role row")
check(ns.Face.CellEntry("P1", "R").id == "face:jump", "its cells are kept")

-- None from the role row: back to the action row with the kept cells, focus on its first cell.
nodeOf(mod.plate).select()
UI.ActionPicker.Choose(5)
nextFrame()
p1 = rowOf("P1")
check(ns.Layout.Roles().P1 == nil and p1.kind == "slot" and b.focus.region == p1.cells[1], "None: action row again, focus on its first cell")
check(p1.cells[3].entry and p1.cells[3].entry.id == "face:jump", "the kept cell is back")

-- A role on a free paddle without actions: no question.
b:Focus(nodeOf(rowOf("P2").cells[1]))
W.press(b, "PAD4")
UI.ActionPicker.Choose(2)
UI.ActionPicker.Choose(2)
nextFrame()
check(
not UI.DialogShown() and ns.Layout.Roles().P2 == "rightmod" and rowOf("P2").kind == "mod", "no actions: the role is set at once")

-- None on a trigger hands its role to a free paddle without actions first (P3, not P1).
local r2 = rowOf("R2")
nodeOf(r2.plate).select()
UI.ActionPicker.Choose(5)
check(ns.Layout.Roles().P2 == "rightmod" and ns.Layout.Roles().R2 == nil, "P2 keeps rightmod")
nodeOf(rowOf("L2").plate).select()
UI.ActionPicker.Choose(5)
check(ns.Layout.Roles().P3 == "leftmod" and ns.Layout.Roles().P1 == nil, "L2 None: leftmod moved to P3, P1 keeps its actions")

-- Guided mode sets roles: every paddle is a role row there.
assert(ns.Layout.Reset())
UI.Bindings.OpenGuided(function() end, function() end)
for _, code in ipairs({ "P1", "P2", "P3", "P4" }) do
	local row
	for _, r in ipairs({ b:GetChildren() }) do if r.code == code and r.kind and r:IsShown() then row = r end end
	check(row and row.kind == "mod", code .. ": guided mode shows the role row")
end
UI.Bindings.EndGuided()
check(rowOf("P1").kind == "slot", "guided mode over: action row again")
-- L3 / R3 while nothing of ours holds them: every bar shows the game's own binding (core context), its prompt name
-- and gold art like a reserved face cell; an atlas the client lacks falls back to the stick's glyph. Once a bar holds
-- an action the stick is ours: that cell shows it and the others are empty again.
local NATIVE = { PADLSTICK = "TOGGLEAUTORUN", PADRSTICK = "TOGGLEPINGLISTENER" }
GetBindingAction = function(key) return NATIVE[key] or "" end
local getAtlas = C_Texture.GetAtlasInfo
C_Texture.GetAtlasInfo = function(atlas) if atlas ~= "gamepad-actionbar-ping-up" then return getAtlas(atlas) end end
b:Refresh()
local l3, r3 = rowOf("L3"), rowOf("R3")
local allNative = true
for _, cell in ipairs(l3.cells) do allNative = allNative and cell.native and cell.icon.atlas == "gamepad-actionbar-autorun-up" and cell.icon.shown end
check(l3.kind == "slot" and allNative and l3.name.text == "Auto-run", "L3 unbound: Auto-run on every bar, the gold art, its name")
check(r3.cells[2].native and r3.cells[2].native.name == "Ping" and r3.cells[2].icon.atlas == "gamepad-ps-PADRSTICK-normal", "R3 unbound: Ping, the stick glyph where the art is missing")
local tip = nodeOf(l3.cells[1]).tip()
check(tip.title == "Auto-run" and tip.lines[#tip.lines]:find("the same on every bar", 1, true), "the native cell's tooltip says it's the game's own, on every bar")
assert(ns.Face.SetCellEntry("L3", "R", { id = "face:jump", name = "Jump", icon = 7 }, 1))
b:Refresh()
l3 = rowOf("L3")
check(l3.cells[3].entry and not l3.cells[3].native and not l3.cells[1].native and not l3.cells[1].icon.shown and rowOf("R3").cells[1].native, "L3 taken over: its own cell, the empty bars empty again; R3 still native")
assert(ns.Face.SetCellEntry("L3", "R", nil))
b:Refresh()
check(rowOf("L3").cells[1].native, "every bar cleared: native again")
GetBindingAction = function() return "" end
b:Refresh()
check(not rowOf("L3").cells[1].native and not rowOf("L3").cells[1].icon.shown, "nothing bound natively: empty")
C_Texture.GetAtlasInfo = getAtlas

-- A ring button's More: under the Healer mode row (greyed: a ring), the ring's own Middle, the Rings tab's setting
-- shared by every button that opens it, stepped through Rings.SetMiddle. Not on a non-ring cell; none without Rings.
local totems = { id = 4, name = "Totems", middle = "cancel", count = 4, slots = {} }
local setMiddle = {}
ns.Rings = {
	Get = function(id) if id == 4 then return totems end end, Frame = function() return CreateFrame("Frame") end,
	SetMiddle = function(id, middle) setMiddle[#setMiddle + 1] = id .. "=" .. middle totems.middle = middle return true end,
	HealerAllowed = function() return nil, "This button holds a ring." end, LiveIcon = function() return 9 end, IsOpen = function() return false end,
}
assert(ns.Face.SetCellEntry("L3", "T", { id = "ring:4", name = "Open ring: Totems", icon = 9, kind = "ring" }, 1))
b:Refresh()
local function moreOf(cell)
	b:Focus(nodeOf(cell))
	W.press(b, "PAD4")
	return pickerRows()
end
more = moreOf(rowOf("L3").cells[1])
check(more[1] and more[1].name == "Healer mode: Off" and more[2] and more[2].name == "Middle: Cancel", "ring cell More: Healer mode (greyed), then Middle: Cancel")
UI.ActionPicker.Choose(2)
check(setMiddle[1] == "4=last" and totems.middle == "last", "picking it steps the ring's own Middle to Use last")
b:Refresh()
more = moreOf(rowOf("L3").cells[1])
check(more[2] and more[2].name == "Middle: Use last", "the row follows the ring: Middle: Use last")
UI.ActionPicker.Choose(2)
check(setMiddle[2] == "4=cancel" and totems.middle == "cancel", "and back to Cancel")
b:Refresh()
more = moreOf(rowOf("L3").cells[2])
check(more[2] == nil or more[2].name ~= "Middle: Cancel" and more[2].name ~= "Middle: Use last", "an empty cell's More has no Middle row")
UI.ActionPicker.Close()
check(UI.Bindings.RingMiddleMore({ id = "spell:133", kind = "spell" }) == nil and UI.Bindings.RingMiddleMore({ id = "ring:9", kind = "ring" }) == nil, "only for a ring that exists")
assert(ns.Face.SetCellEntry("L3", "T", nil))
ns.Rings = nil
check(UI.Bindings.RingMiddleMore({ id = "ring:4", kind = "ring" }) == nil, "no row without the Rings module")

io.stdout:write(("bindings_spec: %d checks passed\n"):format(checks))
