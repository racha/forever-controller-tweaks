-- The core alone and with each module, loaded the way the game loads them: the core's TOC files, its ADDON_LOADED,
-- then each module's TOC files under its own addon name and private table (they read the core's namespace global).
-- On the full panel stub (real TOC files, Glyphs aside), an Xbox Elite pad: lua tests/modules_spec.lua. Every set
-- runs in its own Lua process; each checks no errors, and only the loaded modules' tabs, footer prompts, More entries,
-- no Options page, picker categories and slash commands, plus a ring entry left on a button while Rings is off.
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
-- Options: any Settings call or button the addon makes (there must be none: a category of ours taints Options' search).
local registered = {}
local function register(kind) return function() registered[#registered + 1] = kind return {}, { AddInitializer = function() registered[#registered + 1] = "button" end } end end
Settings = setmetatable({}, { __index = function(_, name) return register(name) end })
function CreateSettingsButtonInitializer() registered[#registered + 1] = "initializer" return {} end
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
-- Focuses the setting row labelled text (a checkbox, dropdown or slider row).
local function focusRow(w, text)
	for _, node in ipairs(w.nodes) do if node.region.label and node.region.label.text == text then return w:Focus(node) end end
end

-- Focuses the node whose tooltip is titled title (a header control).
local function focusTip(w, title)
	for _, node in ipairs(w.nodes) do if type(node.tip) == "table" and node.tip.title == title then return w:Focus(node) end end
end

-- A flat dump of a table (sorted keys), to tell whether anything in it changed.
local function dump(t, out)
	out = out or {}
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		local v = t[k]
		out[#out + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{" or tostring(v))
		if type(v) == "table" then dump(v, out) out[#out + 1] = "}" end
	end
	return table.concat(out, ",")
end

-- Walks w from its first node: up/down everywhere, left/right only off nodes without a value (no onDir, not noSide).
-- Returns the labels of the visible nodes it never reached.
local function unreached(w)
	local start = w.nodes[1].region
	local seen, queue, i = { [start] = true }, { start }, 1
	while queue[i] do
		local region = queue[i]
		i = i + 1
		local node
		for _, n in ipairs(w.nodes) do if n.region == region then node = n end end
		local keys = (node.onDir or node.noSide) and { "PADDUP", "PADDDOWN" } or { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
		for _, key in ipairs(keys) do
			w:Focus(node)
			w:Pad(key)
			w.repeatKey, w.repeatDir = nil, nil
			local at = w.focus and w.focus.region
			if at and not seen[at] then seen[at], queue[#queue + 1] = true, at end
		end
	end
	local out = {}
	for _, n in ipairs(w.nodes) do
		local r = n.region
		if not seen[r] and r:IsVisible() then out[#out + 1] = tostring(r.label and r.label.text or type(n.tip) == "table" and n.tip.title or r:GetText()) end
	end
	return table.concat(out, ", ")
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

-- Side tabs: Bindings, then the loaded modules in the fixed order, whatever order they loaded in, then the core's
-- Tweaks.
local wanted = { "Bindings" }
for _, module in ipairs({ "Touch", "Keyboard", "Rings" }) do
	if has[module] then wanted[#wanted + 1] = ({ Touch = L.TOUCH_TAB, Keyboard = "Keyboard", Rings = "Rings" })[module] end
end
wanted[#wanted + 1] = "Tweaks"
local titles = {}
for i, spec in ipairs(UI.TABS) do titles[i] = spec[2] end
check(table.concat(titles, ",") == table.concat(wanted, ","), "tabs " .. table.concat(titles, ",") .. ", wanted " .. table.concat(wanted, ","))

-- Bindings: the side tabs always (Tweaks is the core's), R1 names the next tab.
UI.Bindings.Open()
local b = UI.Current()
check(b.tabs:IsShown(), "Bindings side tabs shown")
local prompts = footer(b)
check(prompts.PADRSHOULDER == (UI.TABS[2] and UI.TABS[2].prompt or nil), "Bindings R1 prompt: " .. tostring(prompts.PADRSHOULDER))
check(not prompts.PADLSHOULDER, "Bindings has no L1 tab prompt")

-- More: Keyboard settings only with the Keyboard module.
UI.OpenMore(b)
local more = pickerRows()
check(contains(more, L.KEYBOARD) == (has.Keyboard == true), "More lists Keyboard settings: " .. tostring(contains(more, L.KEYBOARD)))
check(contains(more, L.SETUP_GUIDE) and contains(more, L.RESET), "More keeps its common entries")
UI.ActionPicker.Close()

-- Keyboard quick messages: Add opens our own box, its save hook stores the line and brings the page back; B returns.
if has.Keyboard then
	local KS, KP, own = ns.Keyboard.SettingsTab, ns.Keyboard.Library, ns.Keyboard.View.OWN .. "Save"
	KS.Open()
	local kb = UI.Current()
	check(footer(kb).PAD3 == KS.T.QUICK, "keyboard tab: Square is Quick messages")
	-- The settings controls on the pad: A toggles a checkbox and rounds a dropdown, D-pad left/right steps.
	local db = ns.db.keyboard
	check(kb.nodes[1].region:GetText() == KS.T.QUICK, "keyboard tab: Quick messages is the first stop")
	focusRow(kb, KS.T.ON)
	kb:Select()
	check(db.enabled == false, "A on the On checkbox turns the keyboard off")
	kb:Select()
	check(db.enabled == true, "and A turns it on again")
	focusRow(kb, KS.T.OPEN)
	kb:Pad("PADDLEFT")
	check(db.open == "controller", "D-pad left steps the Open dropdown")
	kb:Pad("PADDRIGHT")
	local open = kb.focus
	kb:Pad("PADDRIGHT")
	check(db.open == "always" and kb.focus == open, "past its end, D-pad right keeps the focus and the value")
	focusRow(kb, "Scale")
	kb:Pad("PADDRIGHT")
	check(db.scale == 1.05, "D-pad right steps the Scale slider: " .. tostring(db.scale))
	kb:Pad("PADDLEFT")
	focusRow(kb, "Layout")
	kb:Pad("PADDRIGHT")
	check(db.layout == "compact", "D-pad right steps the Layout dropdown")
	kb:Select()
	check(db.layout == "ring", "A rounds the Layout dropdown back to the first")
	focusRow(kb, "Word suggestions")
	kb:Select()
	check(db.suggestions == false, "A on the Word suggestions checkbox turns them off")
	kb:Select()
	kb:Pad("PAD3")
	check(UI.Current() ~= kb and UI.Current().tabs.index == kb.tabs.index, "Square opens the quick messages page")
	KS.OpenQuick("dungeon")
	local q = UI.Current()
	local qp = footer(q)
	check(qp.PAD1 == L.SELECT and qp.PAD2 == L.BACK, "quick messages page prompts")
	local function labels()
		local out = {}
		for _, node in ipairs(q.nodes) do out[#out + 1] = node.region.label.text end
		return out
	end
	local function focused() return q.focus.region.label.text end
	local lit
	for _, node in ipairs(q.nodes) do if node.region.lit.shown then lit = node.region.label.text end end
	check(lit == KS.T.SITUATIONS.dungeon and focused() == lit, "left: the situations, the selected one lit and focused (scrolled into view)")
	local dungeonLines = #KP.DEFAULTS.dungeon
	check(#q.nodes == 19 + dungeonLines + 1, "19 situations in view, then the dungeon's lines and Add a line: " .. #q.nodes)
	focusRow(q, KS.T.ADD)
	q:Select()
	local edit
	for _, f in ipairs(W.frames) do if rawget(f, own) then edit = f end end
	check(UI.Current() == nil and edit and edit:IsVisible(), "Add closes the window and shows our own box")
	check(rawget(edit, "ForeverControllerTweaksField") == "quick" and rawget(edit, "ForeverControllerTweaksArea") == edit:GetParent(), "our box asks for the fill-ins and to keep its dialog clear")
	edit[own]("  Pull on my mark ")
	check(KP.Own(ns.db.keyboard.phrases, "dungeon")[1] == "Pull on my mark" and UI.Current() == q and not edit:IsVisible(), "save stores the line; the page comes back")
	qp = footer(q)
	check(qp.PAD1 == KS.T.EDIT and qp.PAD3 == KS.T.DELETE and qp.PAD4 == KS.T.MOVE, "a line's prompts: " .. tostring(qp.PAD1))
	check(focused() == "Pull on my mark" and q.focus.region.tag.text == KS.T.YOURS, "the page comes back on the new line, marked Yours")
	-- Right: the player's lines, then the built-in ones; X on a built-in one hides it, Restore brings them back.
	q:Pad("PADDDOWN")
	local first = KP.Text(KP.DEFAULTS.dungeon[1])
	check(focused() == first and footer(q).PAD3 == KS.T.DELETE and not footer(q).PAD1, "then the built-in lines: X deletes, nothing to edit")
	q:Pad("PAD3")
	check(not UI.DialogShown() and ns.db.keyboard.phrases.removed.dungeon[first] and #KP.Builtin(ns.db.keyboard.phrases, "dungeon") == dungeonLines - 1, "X hides that built-in line at once")
	local restoreText = KS.T.RESTORE:format(1)
	check(contains(labels(), restoreText) and not contains(labels(), first), "and the Restore row shows")
	focusRow(q, restoreText)
	q:Select()
	check(#KP.Builtin(ns.db.keyboard.phrases, "dungeon") == dungeonLines and not contains(labels(), restoreText), "Restore brings it back")
	-- Columns: left goes to the situations, up/down change the selection (the lines follow), right goes back.
	q:Pad("PADDLEFT")
	check(focused() == KS.T.SITUATIONS.dungeon, "left: back on the selected situation")
	q:Pad("PADDDOWN")
	check(focused() == KS.T.SITUATIONS.raid and q.focus.region.lit.shown and contains(labels(), KP.Text(KP.DEFAULTS.raid[1])), "down selects the next situation and shows its lines")
	q:Pad("PADDRIGHT")
	check(focused() == KP.Text(KP.DEFAULTS.raid[1]), "right: its first line")
	q:Pad("PADDLEFT")
	for _ = 1, 40 do q:Move(0, -1) end
	check(focused() == KS.T.SITUATIONS.world and q.focus.region:IsVisible(), "the list scrolls to the last situation")
	q:Pad("PAD2")
	check(UI.Current() == kb, "B goes back to the keyboard tab")
	UI.Bindings.Open()
end

check(#registered == 0, "no page in Options: " .. table.concat(registered, ", "))

-- Every module tab opens; L1 names the tab before it, and R1 from the one before steps into it.
for i = 2, #UI.TABS do
	UI.Current().tabs:Step(1)
	local window = UI.Current()
	check(window and window ~= b and window.tabs.index == i, "R1 steps to tab " .. i)
	check(footer(window).PADLSHOULDER == UI.TABS[i - 1].prompt, UI.TABS[i][2] .. ": L1 names " .. tostring(UI.TABS[i - 1].prompt) .. ", got " .. tostring(footer(window).PADLSHOULDER))
end
UI.CloseAll()

-- One value per row: every tab's controls are reached with up/down (left/right only off cells and buttons) and the
-- walk changes nothing saved. Every setting with a left/right value is a noSide row (Bindings' page selector aside;
-- Tweaks' value rows hand left/right back at their ends, so its four columns are crossed sideways: tweaks_spec).
local walks = {}
for _, spec in ipairs(UI.TABS) do walks[#walks + 1] = { spec[2], spec[3] } end
for _, walk in ipairs(walks) do
	walk[2]()
	local w = UI.Current()
	local before = dump(ns.db)
	local missed = unreached(w)
	check(missed == "", walk[1] .. ": up/down reach every control, missed: " .. missed)
	check(dump(ns.db) == before, walk[1] .. ": walking the controls changes no setting")
	for _, node in ipairs(w.nodes) do
		if node.onDir and node.region ~= w.pageSelector and walk[1] ~= "Tweaks" then check(node.noSide, walk[1] .. ": a value row keeps left/right") end

	end
	-- Every tooltip wraps at the native width, so it stays beside its row.
	local tooltip
	for _, f in ipairs(W.frames) do if f.title and type(f.lines) == "table" and type(f.actions) == "table" then tooltip = f end end
	for _, node in ipairs(w.nodes) do
		if node.tip then
			w:Focus(node)
			for _, line in ipairs(tooltip and tooltip.lines or {}) do
				check(not line.shown or line:GetWidth() <= UI.TIP_TEXT_W + 1, walk[1] .. ": tooltip line wraps: " .. tostring(line.text))
			end
		end
	end
	UI.CloseAll()
end

-- The quick messages page scrolls its two lists, so it is walked by what it shows: down the situations from the top,
-- then right and down one situation's lines. Every situation and line comes into focus; nothing saved changes.
if has.Keyboard then
	local KS, KP = ns.Keyboard.SettingsTab, ns.Keyboard.Library
	-- Group's own lines and built-in ones together run past the 19 rows in view.
	for i = 1, 12 do assert(KP.Set(ns.db.keyboard, "group", nil, "Mine " .. i)) end
	KS.OpenQuick()
	local q = UI.Current()
	local before = dump(ns.db)
	local function focused() return q.focus.region.label.text end
	for _ = 1, 40 do q:Pad("PADDUP") q.repeatKey, q.repeatDir = nil, nil end
	check(focused() == KS.T.SITUATIONS.anywhere, "Quick messages: Always is the first situation")
	local seen = { [focused()] = true }
	for _ = 1, 40 do
		q:Pad("PADDDOWN")
		q.repeatKey, q.repeatDir = nil, nil
		seen[focused()] = true
	end
	local missed = {}
	for _, name in pairs(KS.T.SITUATIONS) do if not seen[name] then missed[#missed + 1] = name end end
	check(#missed == 0, "Quick messages: down reaches every situation, missed: " .. table.concat(missed, ", "))
	for _ = 1, 40 do q:Pad("PADDUP") q.repeatKey, q.repeatDir = nil, nil end
	-- Group: the most built-in lines, so its list is the longest.
	local id = "group"
	for _ = 1, 40 do if focused() ~= KS.T.SITUATIONS[id] then q:Pad("PADDDOWN") q.repeatKey, q.repeatDir = nil, nil end end
	check(focused() == KS.T.SITUATIONS[id], "down to Group: " .. focused())
	q:Pad("PADDRIGHT")
	seen = { [focused()] = true }
	for _ = 1, 40 do
		q:Pad("PADDDOWN")
		q.repeatKey, q.repeatDir = nil, nil
		seen[focused()] = true
	end
	missed = {}
	for i = 1, 12 do if not seen["Mine " .. i] then missed[#missed + 1] = "Mine " .. i end end
	for _, entry in ipairs(KP.DEFAULTS[id]) do if not seen[KP.Text(entry)] then missed[#missed + 1] = KP.Text(entry) end end
	if not seen[KS.T.ADD] then missed[#missed + 1] = KS.T.ADD end
	check(#missed == 0, "Quick messages: down reaches every line and Add a line, missed: " .. table.concat(missed, ", "))
	-- The scroll bars (situations first): shown while a column runs past its rows, which make room for them.
	local sitBar, lineBar
	for _, f in ipairs(W.frames) do
		local bar = f.kind == "Slider" and f.parent
		if bar and bar.parent == q then if sitBar then lineBar = f else sitBar = f end end
	end
	local function label(i) return q.nodes[i].region.label.text end
	local last = q.nodes[#q.nodes]
	check(sitBar.parent.shown and lineBar.parent.shown, "Quick messages: both columns show a scroll bar")
	check(last.region.w == 832 - 24 - 16 and q.nodes[1].region.w == 300 - 24 - 16, "Quick messages: rows make room for the bars")
	local bottom = label(20)
	lineBar:Fire("OnValueChanged", 0)
	check(q.focus == q.nodes[#q.nodes] and label(20) ~= bottom, "Quick messages: the lines' thumb at the top, the focus moves into view")
	local first = label(20)
	lineBar.parent.arrows[1]:Click()
	check(label(20) ~= first and q.focus == q.nodes[#q.nodes - 1], "Quick messages: the down arrow steps the lines a row")
	local sitFirst = label(1)
	q.nodes[1].region:Fire("OnMouseWheel", sitBar.parent.top > 0 and 1 or -1)
	check(label(1) ~= sitFirst and q.focus == q.nodes[#q.nodes - 1], "Quick messages: the wheel scrolls the situations, the focus stays on the line")
	q:Pad("PADDLEFT")
	check(focused() == KS.T.SITUATIONS[id], "Quick messages: left brings the selected situation back into view")
	check(dump(ns.db) == before, "Quick messages: walking it changes nothing saved")
	ns.db.keyboard.phrases.added.group = nil
	UI.CloseAll()
end

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
	-- The settings controls on the pad.
	local tw = UI.Current()
	local function left() local c = ns.Touch.Config() return c.sides and c.sides.left or c end
	local size = left().size
	focusRow(tw, L.TOUCH_SETTINGS.size)
	tw:Pad("PADDRIGHT")
	check(left().size == size + 4, "D-pad right steps the Button size slider")
	tw:Pad("PADDLEFT")
	focusTip(tw, L.TOUCH_ON)
	tw:Select()
	check(ns.Touch.Config().enabled == false, "A on the On checkbox turns the bars off")
	tw:Select()
	local shown = ns.Touch.Config().show
	focusTip(tw, L.TOUCH_SHOW_LABEL)
	tw:Select()
	check(ns.Touch.Config().show ~= shown, "A rounds the Show dropdown on")
	UI.CloseAll()
end

-- /fct rings: the Rings tab with the module, the help line without.
local logged = #W.log
SlashCmdList.FOREVERCONTROLLERTWEAKS("rings")
if has.Rings then
	check(UI.Current() and UI.Current().tabs.specs[UI.Current().tabs.index].rings, "/fct rings opens the Rings tab")
	-- Rename from the pad: X on the ring opens our box, the keyboard's Send saves and Close cancels through its hooks.
	local function renameBox()
		local r = UI.Current()
		for _, node in ipairs(r.nodes) do if node.region.id == 2 then r:Focus(node) end end
		r:Pad("PAD3")
		for _, f in ipairs(W.frames) do if rawget(f, "ForeverControllerTweaksSave") and f:IsVisible() then return f end end
	end
	local edit = renameBox()
	check(UI.Current() == nil and edit and edit:IsVisible() and edit:GetText() == "Heals", "X on a ring hides the window and shows the rename box")
	edit:SetText("Burst")
	edit.ForeverControllerTweaksSave("Burst")
	check(ns.Rings.Get(2).name == "Burst" and not edit:IsVisible() and UI.Current(), "Send renames the ring and brings the tab back")
	edit = renameBox()
	edit:SetText("Nope")
	edit.ForeverControllerTweaksCancel("Nope")
	check(ns.Rings.Get(2).name == "Burst" and not edit:IsVisible() and UI.Current(), "Close keeps the name and brings the tab back")
	assert(ns.Rings.Rename(2, "Heals"))
	-- The Slots slider and the Stick and Show dropdowns on the pad.
	local r = UI.Current()
	local function rings() local out = {} for _, ring in ipairs(ns.Rings.List()) do out[ring.id] = { ring.count, ring.stick, ring.show } end return out end
	local before = rings()
	focusRow(r, L.RINGS_SLOTS)
	r:Pad("PADDLEFT")
	local stepped
	for id, ring in pairs(rings()) do if ring[1] == before[id][1] - 1 then stepped = true end end
	check(stepped, "D-pad left steps the Slots slider")
	focusRow(r, L.RINGS_STICK)
	r:Select()
	local turned
	for id, ring in pairs(rings()) do if ring[2] ~= before[id][2] then turned = true end end
	check(turned, "A rounds the Stick dropdown on")
	focusRow(r, L.RINGS_SHOW)
	r:Pad("PADDRIGHT")
	local shown
	for id, ring in pairs(rings()) do if before[id][3] == "toggle" and ring[3] == "hold" then shown = true end end
	check(shown, "D-pad right steps Show from Toggle to Hold")
	for _, ring in ipairs(ns.Rings.List()) do assert(ns.Rings.SetShow(ring.id, "toggle")) end
	-- The preview (design/rings.md 10.8) is the in-game wheel scaled into its area, following the count, with the
	-- native highlight on the focused slot.
	local Rings = ns.Rings
	Rings.SettingsTab.Open(2)
	local wheel
	for _, f in ipairs(W.frames) do if f.w == 540 and f.h == 541 and f:GetScale() < 1 then wheel = f end end
	check(wheel and wheel:GetScale() * 541 <= 320 + 1e-9, "preview: the wheel is scaled to fit the preview area")
	local function shown(atlas)
		local n = 0
		for _, t in ipairs(wheel and wheel.textures or {}) do if t.atlas == atlas and t.shown then n = n + 1 end end
		return n
	end
	for _, n in ipairs({ 4, 6, 8 }) do
		assert(Rings.SetCount(2, n))
		r:Refresh()
		r:Focus(r.slotNodes[n])
		local buttons = 0
		for _, f in ipairs(W.frames) do if f.parent == wheel and f.shown then buttons = buttons + 1 end end
		check(shown("gamepad-radial-menu-wheelbg") == #Rings.WheelPieces(n) and buttons == n, "preview: " .. n .. " slots draw the wheel and " .. n .. " slot buttons")
		check(shown("gamepad-radial-menu-selected") == #Rings.SegmentPieces(n, n), "preview: " .. n .. " slots light the focused slot")
	end
	focusRow(r, L.RINGS_SLOTS)
	check(shown("gamepad-radial-menu-selected") == 0, "preview: the highlight goes with the focus")
	assert(Rings.SetCount(2, 8))
	UI.CloseAll()
else
	check(not UI.Current() and W.log[logged + 1] and W.log[logged + 1]:find("/fct", 1, true), "/fct rings without the module: help")
end

-- The in-game ring (design/rings.md 10) draws every count: the wheel composed from its pieces, the highlight on the
-- kept pick; no errors.
if has.Rings then
	local Rings = ns.Rings
	local ringFrame = Rings.Frame()
	local display
	for _, f in ipairs(W.frames) do if f.parent == ringFrame and f.scripts.OnGamePadStick then display = f end end
	local function shown(atlas)
		local n = 0
		for _, t in ipairs(display.textures or {}) do if t.atlas == atlas and t.shown then n = n + 1 end end
		return n
	end
	for key, value in pairs({ ["ps-ring"] = 2, ["ps-mode"] = "hold", ["ps-aimside"] = "right", ["ps-pick"] = 1 }) do ringFrame:SetAttribute(key, value) end
	for n = Rings.MIN_SLOTS, Rings.MAX_SLOTS do
		assert(Rings.SetCount(2, n))
		display.scripts.OnUpdate(display, 0.3)
		check(shown("gamepad-radial-menu-wheelbg") == #Rings.WheelPieces(n) and shown("gamepad-radial-menu-selected") == #Rings.SegmentPieces(n, 1), "ring look: " .. n .. " slots draw the wheel and the highlight")
	end
	check(not (display.strings or {})[1] and display.w == 540 and display.h == 541, "ring look: the wheel only, no title or band, the frame the wheel's size")
	assert(Rings.SetStyle(2, "compact"))
	display.scripts.OnUpdate(display, 0.3)
	-- On the ring frame or under it (the slot views sit on its slot buttons).
	local function anywhere(atlas)
		local n = 0
		for _, f in ipairs(W.frames) do
			local o = f
			while o and o ~= ringFrame do o = o.parent end
			for _, t in ipairs(o and f.shown and f.textures or {}) do if t.atlas == atlas and t.shown then n = n + 1 end end
		end
		return n
	end
	local fly = "gamepad-flyout-circular-"
	check(shown("gamepad-radial-menu-wheelbg") == 0 and shown("gamepad-radial-menu-selected") == 0 and shown(fly .. "base") == 1, "ring look: Compact draws the flyout's circular base, no wheel and no wedge highlight")
	check(shown(fly .. "slot-backdrop") == 7 and anywhere(fly .. "slot-normal") == 1, "ring look: Compact, the filled slot on its ring, a backdrop on each empty one")
	check(anywhere(fly .. "slot-over-border") == 1 and shown("gamepad-flyout-selection-indicator") == 1 and anywhere("gamepad-largecursor") == 1, "ring look: Compact, the aimed slot's over-border, the indicator and the arrow")
	local function mods() local n = 0 for _, glyph in ipairs(display.mods.glyphs) do if glyph.shown then n = n + 1 end end return n, display.mods.plus.shown end
	check(display.centre and display.centre.shown and display.centre.fallback == Rings.Icon(Rings.Get(2)) and display.centre.shape == "circle" and mods() == 0, "ring look: Compact, the ring's icon in the middle in a circle slot, no glyphs on the base layer")
	ringFrame:SetAttribute("ps-layer", "bottom")
	ringFrame:SetAttribute("ps-kind", "dpad")
	display.scripts.OnUpdate(display, 0.3)
	local glyphs, plus = mods()
	check(glyphs == 2 and plus and display.centre.shape == "square" and display.mods.glyphs[1].code ~= display.mods.glyphs[2].code, "ring look: Compact from a D-pad cell's bottom layer, a square slot and both modifiers' glyphs with a plus")
	ringFrame:SetAttribute("ps-layer", "left")
	display.scripts.OnUpdate(display, 0.3)
	glyphs, plus = mods()
	check(glyphs == 1 and not plus, "ring look: Compact on the left layer, its one modifier")
	ringFrame:SetAttribute("ps-layer", nil)
	ringFrame:SetAttribute("ps-kind", nil)
	assert(Rings.SetStyle(2, "full"))
	display.scripts.OnUpdate(display, 0.3)
	check(shown(fly .. "base") == 0 and shown(fly .. "slot-backdrop") == 0 and anywhere(fly .. "slot-normal") == 0 and anywhere("gamepad-largecursor") == 0 and shown("gamepad-radial-menu-wheelbg") == #Rings.WheelPieces(8), "ring look: back to Full, the wheel again and no flyout parts")
	check(not display.centre.shown and mods() == 0, "ring look: Full has nothing in the middle")

	-- A healer ring: Compact, 7 places, one per unit; a missing unit is the dimmed empty socket, a hostile one the
	-- disabled slot. This client stub has no Radial StatusBar, curves or calculator: the places show the track only.
	local units = { player = "WARRIOR", party1 = "PRIEST", party3 = "MAGE", target = "hostile" }
	function UnitExists(unit) return units[unit] ~= nil end
	function UnitCanAssist(_, unit) return units[unit] ~= nil and units[unit] ~= "hostile" end
	function UnitIsDeadOrGhost(unit) return unit == "party3" end
	function UnitClass(unit) return "", units[unit] end
	function UnitGroupRolesAssigned(unit) return unit == "party1" and "HEALER" or "NONE" end
	function UnitHealth() return 50 end
	function UnitHealthMax() return 100 end
	function SetPortraitTexture() end
	RAID_CLASS_COLORS = RAID_CLASS_COLORS or { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
	local hid = Rings.HealerRing({ id = "spell:2061", name = "Flash Heal", icon = 9, kind = "spell" })
	for key, value in pairs({ ["ps-ring"] = hid, ["ps-mode"] = "hold", ["ps-aimside"] = "right", ["ps-pick"] = false, ["ps-kind"] = "dpad" }) do ringFrame:SetAttribute(key, value or nil) end
	display.scripts.OnUpdate(display, 0.3)
	local meter = "gamepad-targetingradial-target-meterbg-64"
	check(hid == "hspell2061" and shown(fly .. "base") == 1 and display.centre.shown and display.centre.shape == "square", "healer look: the flyout base, the spell in the middle in the D-pad cell's square")
	check(shown(fly .. "slot-backdrop") == 3 and anywhere(fly .. "slot-normal") == 3 and anywhere(fly .. "slot-disabled") == 1 and anywhere(meter) == 4, "healer look: 4 units on their slots and health tracks (the hostile Target disabled), 3 empty sockets")
	check(anywhere("groupfinder-icon-role-micro-heal") == 1 and anywhere(fly .. "slot-over-border") == 0, "healer look: the healer's role icon, nothing aimed")
	ringFrame:SetAttribute("ps-ring", 2)
	ringFrame:SetAttribute("ps-kind", nil)
	display.scripts.OnUpdate(display, 0.3)
	check(anywhere(meter) == 0 and anywhere(fly .. "slot-disabled") == 0, "healer look: an ordinary ring after it shows no unit parts")
	local V = Rings.View
	local x, y = V.LabelOffset(30)
	check(select(2, V.LabelOffset(0)) == 60 and V.LabelOffset(90) == 60 and math.abs(x - 20) < 1e-9 and math.abs(y - 50) < 1e-9, "ring look: labels sit at textAnchorData, between its points linearly")
	check(V.LabelText("Holy Light (Highest Rank)") == "Holy Light" and V.LabelText("Fireball Rank 3") == "Fireball" and V.LabelText("Jump") == "Jump", "ring look: labels drop rank text")
	assert(Rings.SetCount(2, 8))
	for _, key in ipairs({ "ps-ring", "ps-mode", "ps-aimside", "ps-pick" }) do ringFrame:SetAttribute(key, nil) end
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
