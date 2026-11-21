-- What's new (Panel/WhatsNew.lua, design/whats-new.md) on the full panel stub (real TOC files, Glyphs aside):
-- lua tests/news_spec.lua. The version compare and dev-build detection, the notes picked (5 newest, the older line),
-- the saved state from a first install, an update, a downgrade and a dev build, the window opening on its own (after
-- another window, not twice), its checkbox (never ticked on open, stored only by a close), combat closing it unread
-- and opening it once after, /fct whatsnew, and the generator (tools/make_news.py) with the shipped News.lua.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local W = dofile(here .. "/panel_stub.lua")
local raw = { name = "Test Pad", vendorID = 0x045e, productID = 0x0b00, rawButtons = {}, rawAxes = {} }
for i = 0, 20 do raw.rawButtons[i] = false end
for i = 0, 9 do raw.rawAxes[i] = 0 end
W.raw = raw

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

W.version = "1.5.0"
C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return W.version end if field == "X-Website" then return "https://example.test/" end end }
-- An existing player's save from before the window: no news key.
ForeverControllerTweaksDB = { version = 2, options = {}, onboarded = { ["045e/0b00"] = true } }
local ns = {}
for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
	if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
end
local UI, L = ns.UI, ns.UI.L
local News = UI.WhatsNew
local cmp, parse = News.CompareVersions, News.ParseVersion

-- Versions.
check(cmp("1.2.1-beta.1", "1.2.1-beta.2") == -1 and cmp("1.2.1-beta.2", "1.2.1") == -1 and cmp("1.2.1", "1.3.0") == -1, "order: beta.1 < beta.2 < release < next minor")
check(cmp("1.0.0-beta.2", "1.0.0-rc.0") == -1 and cmp("1.0.0-rc.0", "1.0.0") == -1 and cmp("1.0.0", "1.0.1") == -1, "order: beta < rc < release < patch")
check(cmp("1.10.0", "1.9.0") == 1 and cmp("v1.4.0", "1.4.0") == 0 and cmp("1.4.0", "1.4.0") == 0, "numbers, not strings; a leading v; equal")
check(cmp("1.0.0-alpha", "1.0.0-alpha.1") == -1 and cmp("1.0.0-1", "1.0.0-alpha") == -1, "a shorter pre-release is lower; numbers below words")
for _, dev in ipairs({ "@project-version@", "1.4.0-3-gabc1234", "", "1.4", "1.4.0-", "1.4.0-beta..1", "1.4.0 beta" }) do
	check(parse(dev) == nil and cmp(dev, "1.4.0") == nil and cmp("1.4.0", dev) == nil, "dev build: " .. dev)
end
check(parse(nil) == nil and parse("1.4.0-rc.0").pre[1] == "rc" and parse("1.4.0-rc.0").pre[2] == 0, "parse: nil, pre-release identifiers")

-- The notes: newer than seen, not newer than running, newest first, at most 5, then the older line.
local list = {}
for _, v in ipairs({ "1.6.0", "1.5.0", "1.4.0", "1.3.0", "1.2.1", "1.2.1-beta.2", "1.2.0", "1.1.0" }) do list[#list + 1] = { version = v, date = "", blocks = { { "p", v } } } end
local entries, older = News.Entries(list, "1.1.0", "1.5.0", 5)
check(#entries == 5 and entries[1].version == "1.5.0" and entries[5].version == "1.2.1-beta.2" and older, "5 newest up to the running version, older ones left out")
entries, older = News.Entries(list, "1.3.0", "1.5.0", 5)
check(#entries == 2 and entries[2].version == "1.4.0" and not older, "only what is newer than seen")
entries = News.Entries(list, "1.5.0-beta.1", "1.5.0", 5)
check(#entries == 1 and entries[1].version == "1.5.0", "a pre-release to its release shows the release")

-- Saved state.
local fresh = {}
News.Init(fresh, true, "1.5.0")
check(fresh.news.seen == "1.5.0" and fresh.news.never == nil, "first install: seen is the running version (nothing shows)")
local existing = { version = 2 }
News.Init(existing, false, "1.5.0")
check(existing.news.seen == "1.4.0", "an existing player starts at 1.4.0")
local dev = { version = 2 }
News.Init(dev, false, "@project-version@")
check(dev.news == nil, "dev build: nothing written")
local broken = { news = "x" }
News.Init(broken, false, "1.5.0")
check(type(broken.news) == "table" and broken.news.seen == "1.4.0", "a broken news value repairs to a table")
local bad = { news = { seen = 5, never = "yes" } }
News.Init(bad, false, "1.5.0")
check(bad.news.seen == "1.4.0" and bad.news.never == nil, "a bad seen or never is repaired")
local kept = { news = { seen = "9.0.0", never = true } }
News.Init(kept, false, "1.5.0")
check(kept.news.seen == "9.0.0" and kept.news.never == true, "a good one is kept")

-- In play: an existing player's first login on 1.5.0.
W.fire("ADDON_LOADED", "ForeverControllerTweaks")
check(ns.db.news.seen == "1.4.0", "loaded: seen starts at the baseline")
ns.NEWS = list
W.fire("PLAYER_LOGIN")
W.fire("PLAYER_ENTERING_WORLD")
-- Another window of ours open first: it waits for it to close.
UI.Bindings.Open()
W.advance(3.5)
check(UI.Current() ~= nil and UI.Current().NineSlice.Text.text ~= L.NEWS_TITLE, "waits while another window is open")
UI.CloseAll()
W.advance(2.5)
local w = UI.Current()
check(w and w.NineSlice.Text.text == "Controller Tweaks · What's new", "opens once the other closes: " .. tostring(w and w.NineSlice.Text.text))
local function strings(frame, out)
	out = out or {}
	for _, fs in ipairs(frame.strings or {}) do if fs.shown then out[#out + 1] = fs.text end end
	return out
end
local function shows(text)
	for _, f in ipairs(W.frames) do
		for _, fs in ipairs(f.strings or {}) do if fs.shown and fs.text == text and f:IsVisible() then return true end end
	end
	return false
end
check(shows("Version 1.5.0 · updated from 1.4.0") and shows("1.5.0") and not shows("1.4.0") and not shows("1.6.0"), "the version line and only 1.5.0's notes")
local box
for _, f in ipairs(W.frames) do if f.check and f.Set and f:IsVisible() then box = f end end
check(box and box.check.shown == false, "the box starts unticked")
local function footer()
	local out = {}
	for _, prompt in ipairs(w.footer.prompts) do if prompt:IsShown() then out[#out + 1] = prompt.key end end
	return table.concat(out, " ")
end
check(footer() == "PAD2", "footer on the notes: Close (the notes fit: no Scroll)")
local function press(key) w:Pad(key) w.repeatKey, w.repeatDir = nil, nil end
press("PAD1")
check(box.check.shown == false, "A on the notes does nothing")
press("PADDUP")
check(w.focus and w.focus.region == box:GetParent() and footer():find("PAD1", 1, true), "D-pad Up at the top: the box, Select in the footer")
press("PAD1")
check(box.check.shown == true and ns.db.news.never == nil, "A ticks it; nothing stored yet")
press("PADDDOWN")
check(w.focus.region ~= box:GetParent(), "D-pad Down: back to the notes")

-- Combat closes it unread, the tick dropped; after the fight it opens once more, unticked.
W.fire("PLAYER_REGEN_DISABLED")
W.combat = true
check(UI.Current() == nil and ns.db.news.seen == "1.4.0" and ns.db.news.never == nil, "combat: closed, nothing stored")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
W.advance(2.5)
check(UI.Current() == w and box.check.shown == false, "after the fight: open again, unticked")
press("PADDUP")
press("PAD1")
press("PAD2")
check(UI.Current() == nil and ns.db.news.seen == "1.5.0" and ns.db.news.never == true, "B with the box ticked: seen and never stored")
W.fire("PLAYER_REGEN_DISABLED")
W.fire("PLAYER_REGEN_ENABLED")
W.advance(3)
check(UI.Current() == nil, "once per session")
News.Check()
check(UI.Current() == nil and News.Due() == nil, "never set: nothing due")

-- /fct whatsnew: never cleared, this version's notes only, unticked; closed unticked, never stays off.
W.log = {}
SlashCmdList.FOREVERCONTROLLERTWEAKS("whatsnew")
check(ns.db.news.never == nil and W.log[1] and W.log[1]:find(L.NEWS_ON, 1, true), "the command turns it back on, with a line")
check(UI.Current() == w and shows("Version 1.5.0") and box.check.shown == false and shows("1.5.0") and not shows("1.4.0"), "the command: this version's notes, unticked")
w.ClosePanelButton:Click()
check(UI.Current() == nil and ns.db.news.never == nil and ns.db.news.seen == "1.5.0", "the X closes, never stays off")
W.combat = true
W.log = {}
SlashCmdList.FOREVERCONTROLLERTWEAKS("whatsnew")
check(UI.Current() == nil and W.log[1] and W.log[1]:find(L.COMBAT, 1, true), "in combat: the combat line, nothing opens")
W.combat = false

-- A version with no notes for it: the empty line.
W.version = "1.5.1"
SlashCmdList.FOREVERCONTROLLERTWEAKS("whatsnew")
check(shows(L.NEWS_EMPTY), "no entry for the running version: the empty line")
UI.CloseAll()

-- Downgrade and dev builds: nothing due, nothing written.
ns.db.news.seen = "9.0.0"
W.version = "1.5.0"
check(News.Due() == nil, "downgrade: nothing due")
ns.db.news.seen = "1.4.0"
W.version = "@project-version@"
check(News.Due() == nil, "dev build: nothing due")
SlashCmdList.FOREVERCONTROLLERTWEAKS("whatsnew")
check(UI.Current() == w and shows("Development build · notes for 1.6.0"), "dev build: the command shows the newest notes")
press("PAD2")
check(ns.db.news.seen == "1.4.0", "dev build: closing stores nothing")

-- More than 5 versions behind: the 5 newest, then the older line with the website.
W.version = "1.6.0"
ns.db.news.seen = "1.0.0"
local due, more = News.Due()
check(#due == 5 and more, "6 or more newer: 5 shown, older ones left out")

-- The generator and the shipped data: the tool's own self-test and News.lua current with the changelog (in the
-- development repo, which has tools/; the public one has neither the tool nor release/), then News.lua's shape.
local root = dir .. "/.."
local tool = io.open(root .. "/tools/make_news.py")
if tool then
	tool:close()
	local function run(args) local ok = os.execute("python3 -I '" .. root .. "/tools/make_news.py' " .. args .. " >/dev/null") return ok == true or ok == 0 end
	check(run("--self-test"), "make_news.py self-test")
	check(run("'" .. root .. "/release/public/CHANGELOG.md' '" .. dir .. "/News.lua' --check"), "News.lua is current with CHANGELOG.md")
end
local shipped = {}
assert(loadfile(dir .. "/News.lua"))("ForeverControllerTweaks", shipped)
local first, shapeOk = shipped.NEWS and shipped.NEWS[1], true
for _, entry in ipairs(shipped.NEWS or {}) do
	shapeOk = shapeOk and parse(entry.version) ~= nil and type(entry.blocks) == "table" and #entry.blocks > 0
	for _, block in ipairs(entry.blocks) do shapeOk = shapeOk and (block[1] == "h" or block[1] == "p" or block[1] == "b" and (block[3] == 1 or block[3] == 2)) and type(block[2]) == "string" end
end
check(first and shapeOk and #shipped.NEWS <= 10, "News.lua: versions newest first, h / p / b blocks, at most 10")

io.stdout:write(("news_spec: %d checks passed\n"):format(checks))
