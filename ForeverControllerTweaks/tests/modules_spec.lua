-- The core alone and with each module, loaded the way the game loads them: the core's TOC files, its ADDON_LOADED,
-- then each module's TOC files under its own addon name and private table (they read the core's namespace global).
-- On the full panel stub (real TOC files, Glyphs aside), an Xbox Elite pad: lua tests/modules_spec.lua. Every set
-- runs in its own Lua process; each checks no errors, and only the loaded modules' tabs, footer prompts, More entries,
-- Options buttons, picker categories and slash commands, plus a ring entry left on a button while Rings is off.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local SETS = { "none", "Touch", "Keyboard", "Rings", "Touch,Keyboard,Rings" }

if not arg[1] then
	for _, set in ipairs(SETS) do
		local status = os.execute(string.format('"%s" "%s" %s', arg[-1] or "lua", arg[0], set))
		if status ~= true and status ~= 0 then error("FAIL: modules_spec set " .. set) end
	end
	io.stdout:write("modules_spec: all " .. #SETS .. " sets passed\n")
	return
end

local set = arg[1]
local loaded = {}
for module in set:gmatch("%a+") do if module ~= "none" then loaded[#loaded + 1] = module end end
local has = {}
for _, module in ipairs(loaded) do has[module] = true end

local W = dofile(here .. "/panel_stub.lua")
local raw = { name = "Test Pad", vendorID = 0x045e, productID = 0x0b00, rawButtons = {}, rawAxes = {} }
for i = 0, 20 do raw.rawButtons[i] = false end
for i = 0, 9 do raw.rawAxes[i] = 0 end
W.raw = raw
-- The Options page: the buttons registered on it.
local options = {}
Settings = {
	RegisterVerticalLayoutCategory = function() return {}, { AddInitializer = function(_, init) options[#options + 1] = init.name end } end,
	RegisterAddOnCategory = function() end,
}
function CreateSettingsButtonInitializer(name) return { name = name } end
function SecureHandlerSetFrameRef(frame, label, ref) frame:SetAttribute("frameref-" .. label, ref) end

-- A player's saves from the single-folder addon: a ring, keyboard settings with learned words, a touch layout.
ForeverControllerTweaksDB = {
	version = 2,
	rings = { nextId = 3, list = { { id = 2, name = "Heals", icon = 5, count = 8, stick = "right", slots = { { id = "face:jump", name = "Jump", icon = 7, kind = "face" } } } } },
	keyboard = { enabled = true, open = "always", dictionary = { zugzug = 40, raid = 3 } },
	chars = { ["Ann-Realm"] = { touch = { enabled = true, bars = { left = { { T = { id = "ring:2", name = "Open ring: Heals", icon = 5, kind = "ring" } } }, right = {} } } } },
}
local saved = ForeverControllerTweaksDB

local ns = {}
for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
	if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
end
W.fire("ADDON_LOADED", "ForeverControllerTweaks")
assert(ForeverControllerTweaks == ns and ns.db, "the core's namespace is the global, ready before the modules load")
-- A layout change while the core loads applies the routers (their one-time setup) before any module is there.
ns.Fire("FCT_LAYOUT_CHANGED", "device")
local early
for _, f in ipairs(W.frames) do if f.frameName == "ForeverControllerTweaksPaddle1" then early = f:GetAttribute("ps-kind") end end
assert(early == "paddle", "the routers were set up before the modules loaded")
for _, module in ipairs(loaded) do
	local name = "ForeverControllerTweaks_" .. module
	local folder = dir .. "/../" .. name
	local toc = {}
	for line in io.lines(folder .. "/" .. name .. ".toc") do toc[#toc + 1] = line end
	local deps = table.concat(toc, "\n")
	assert(deps:find("\n## Dependencies: ForeverControllerTweaks\n", 1, true) and deps:find("\n## Group: ForeverControllerTweaks\n", 1, true), name .. ": dependency and group")
	for _, line in ipairs(toc) do
		if line:match("%.lua$") then assert(loadfile(folder .. "/" .. line))(name, {}) end
	end
	W.fire("ADDON_LOADED", name)
end
W.fire("PLAYER_LOGIN")
W.fire("PLAYER_ENTERING_WORLD")
W.advance(2.5)
local UI, L = ns.UI, ns.UI.L
UI.CloseAll()

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL [" .. set .. "]: " .. msg, 2) end
end
local function errors()
	local out = {}
	for _, line in ipairs(W.log) do
		if line:find("error") or line:find("failed") or line:find("blocked") then out[#out + 1] = line end
	end
	return table.concat(out, " | ")
end
local function contains(list, value)
	for _, v in ipairs(list) do if v == value then return true end end
	return false
end
local function pickerRows()
	local out = {}
	for _, f in ipairs(W.frames) do
		if f.tick and f.name and f:IsVisible() and f.index then out[f.index] = f.name.text end
	end
	return out
end
local function footer(window)
	local out = {}
	for _, prompt in ipairs(window.footer.prompts) do
		if prompt:IsShown() then out[prompt.key] = prompt.label.text end
	end
	return out
end

check(errors() == "", "no errors while loading: " .. errors())

-- Module APIs: only the loaded ones.
check(not ns.Touch == not has.Touch and not ns.Keyboard == not has.Keyboard and not ns.Rings == not has.Rings, "module APIs follow the loaded set")

-- Side tabs: Bindings, then the loaded modules in the fixed order, whatever order they loaded in.
local wanted = { "Bindings" }
for _, module in ipairs({ "Touch", "Keyboard", "Rings" }) do
	if has[module] then wanted[#wanted + 1] = ({ Touch = L.TOUCH_TAB, Keyboard = "Keyboard", Rings = "Rings" })[module] end
end
local titles = {}
for i, spec in ipairs(UI.TABS) do titles[i] = spec[2] end
check(table.concat(titles, ",") == table.concat(wanted, ","), "tabs " .. table.concat(titles, ",") .. ", wanted " .. table.concat(wanted, ","))

-- Bindings: the side tabs only with a module, R1 names the next tab, none without.
UI.Bindings.Open()
local b = UI.Current()
check(b.tabs:IsShown() == (#loaded > 0), "Bindings side tabs shown only with a module")
local prompts = footer(b)
check(prompts.PADRSHOULDER == (UI.TABS[2] and UI.TABS[2].prompt or nil), "Bindings R1 prompt: " .. tostring(prompts.PADRSHOULDER))
check(not prompts.PADLSHOULDER, "Bindings has no L1 tab prompt")

-- More: Keyboard settings only with the Keyboard module.
UI.OpenMore(b)
local more = pickerRows()
check(contains(more, L.KEYBOARD) == (has.Keyboard == true), "More lists Keyboard settings: " .. tostring(contains(more, L.KEYBOARD)))
check(contains(more, L.SETUP_GUIDE) and contains(more, L.RESET), "More keeps its common entries")
UI.ActionPicker.Close()

-- Options page: the Keyboard button only with the module.
check(contains(options, L.SETTINGS_OPEN_LABEL), "Options page registered")
check(contains(options, L.KEYBOARD) == (has.Keyboard == true), "Options lists the keyboard button only with the module")

-- Every module tab opens; L1 names the tab before it, and R1 from the one before steps into it.
for i = 2, #UI.TABS do
	UI.Current().tabs:Step(1)
	local window = UI.Current()
	check(window and window ~= b and window.tabs.index == i, "R1 steps to tab " .. i)
	check(footer(window).PADLSHOULDER == UI.TABS[i - 1].prompt, UI.TABS[i][2] .. ": L1 names " .. tostring(UI.TABS[i - 1].prompt) .. ", got " .. tostring(footer(window).PADLSHOULDER))
end
UI.CloseAll()

-- The saved touch button holding a ring: greyed in the Touch tab only while Rings is off.
if has.Touch then
	UI.TouchTab.Open()
	local row
	for _, n in ipairs(UI.Current().nodes) do
		local r = n.region.row
		if r and r.side == "left" and r.index == 1 then row = r end
	end
	check(row and row.name.text == "Open ring: Heals", "Touch tab shows the saved ring button")
	check((row.name.font == "GameFontDisable") == not has.Rings and row.cells[1].icon.desat == not has.Rings, "the touch ring entry is greyed only without Rings")
	UI.CloseAll()
end

-- /fct rings: the Rings tab with the module, the help line without.
local logged = #W.log
SlashCmdList.FOREVERCONTROLLERTWEAKS("rings")
if has.Rings then
	check(UI.Current() and UI.Current().tabs.specs[UI.Current().tabs.index].rings, "/fct rings opens the Rings tab")
	UI.CloseAll()
else
	check(not UI.Current() and W.log[logged + 1] and W.log[logged + 1]:find("/fct", 1, true), "/fct rings without the module: help")
end

-- Picker categories: Rings only with the module and a ring.
local function categories()
	local out = {}
	for _, category in ipairs(ns.Actions.Catalog()) do out[#out + 1] = category.name end
	return out
end
if has.Rings then
	local id = assert(ns.Rings.New()).id
	check(contains(categories(), "Rings"), "a ring: the picker has the Rings category")
	assert(ns.Face.SetCellEntry("P1", "R", { id = "ring:" .. id, name = "Open ring: Ring", icon = 5, kind = "ring" }, 1))
else
	check(not contains(categories(), "Rings"), "no Rings category without the module")
	-- A ring left on a paddle from when Rings was on (the saves keep it).
	assert(ns.Face.SetCellEntry("P1", "R", { id = "ring:1", name = "Open ring: Heals", icon = 5, kind = "ring" }, 1))
end

-- The ring entry: routed with the module; without it, not routed, greyed, with a note.
W.advance(1)
local router
for _, f in ipairs(W.frames) do if f.frameName == "ForeverControllerTweaksPaddle1" then router = f end end
check(router, "paddle router exists")
local routed = router:GetAttribute("ps-ring-right")
UI.Bindings.Open()
b = UI.Current()
local cell
for _, n in ipairs(b.nodes) do
	local region = n.region
	if region.row and region.row.code == "P1" and region.layer == "R" then cell = n end
end
check(cell and cell.region.entry and cell.region.entry.id:find("^ring:"), "the P1/R cell shows the ring entry")
check(cell.region.icon.desat == (not has.Rings), "the ring entry is greyed only without the module")
local tip = cell.tip()
check(contains(tip.lines, L.RINGS_OFF) == (not has.Rings), "the cell's tooltip says the Rings module is off only without it")
check(not routed == not has.Rings, "the ring entry is routed only with Rings: " .. tostring(routed))
check(router:GetAttribute("frameref-rings") == (has.Rings and ns.Rings.Frame() or nil), "the router knows the ring frame once Rings loaded after its setup")
UI.CloseAll()

-- The saves stay whatever is loaded: the core keeps the modules' tables, each module repairs only its own.
W.fire("PLAYER_LOGOUT")
local db = ForeverControllerTweaksDB
check(db == saved and db == ns.db, "one SavedVariables table, the core's")
check(db.rings.list[1] and db.rings.list[1].name == "Heals" and db.rings.list[1].slots[1].id == "face:jump", "the ring is kept")
check(db.keyboard.open == "always" and db.keyboard.dictionary.zugzug ~= nil, "keyboard settings and learned words are kept")
local touch = db.chars["Ann-Realm"].touch
check(touch.enabled and touch.bars.left[1].T.id == "ring:2", "the touch layout is kept")

check(errors() == "", "no errors after the checks: " .. errors())
io.stdout:write(("modules_spec [%s]: %d checks passed\n"):format(set, checks))
