-- Stubbed checks of the SavedVariables repair and migrations: lua tests/db_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local harness = dofile(here .. "/wow.lua")
local function new(db) return harness(here .. "/..", { db = db }) end

local log = {}
for i = 1, 600 do log[i] = "line " .. i end

-- A damaged v1 db: wrong types, bad keys, invalid raw sources, a duplicate role, a broken detect, unknown fields.
local W = new({
	version = 1,
	options = { glyphs = "yes", toggleKey = 5, debug = "on", glyphHide = "overlay" },
	debugLog = log,
	faceEntries = { ["054c/0ce6"] = { bottom = { kind = "spell" } } },
	onboarded = { playstation = true },
	devices = {
		["054c/0ce6"] = {
			raw = { L1 = { button = 9 }, R1 = { button = "ten" }, X9 = { button = 1 }, L2 = { axis = "LTrigger", button = 3 }, R2 = { axis = "RTrigger" } },
			roles = { L1 = "friendly", R1 = "friendly" },
			face = { bottom = "interact", right = "back", left = "jump", top = "inspect" },
			detect = { buttons = "bad" },
			junk = 1,
		},
		["bad key"] = {},
		["045e/0b12"] = "not a table",
		["2dc8/6001"] = { raw = { L1 = { button = 4 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }, roles = {}, face = {} },
		["2dc8/6002"] = { raw = { L1 = { button = 9 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }, roles = {}, face = {} },
		["057e/2009"] = { roles = { L1 = "rightmod", R1 = "friendly", L2 = "leftmod", R2 = "hostile" }, face = { bottom = "jump" } },
		["28de/11ff"] = { raw = {}, roles = {}, face = {}, detect = { version = 1, buttons = { PAD1 = 0 }, axes = { LStickX = { raw = 0, scale = 1 } }, hats = {}, labelStyle = "Comic" } },
	},
})
W.login()
local db = W.ns.db
local options, devices = db.options, db.devices
assert(db.version == 5 and ForeverControllerTweaksDB == db)
assert(options.glyphs == true and options.toggleKey == "PADSOCIAL" and options.debug == false and options.glyphHide == "overlay")
assert(#db.debugLog == 500 and db.debugLog[1] == "line 101", "debug log capped, newest kept")
assert(db.faceEntries["054c/0ce6"].bottom.kind == "spell" and db.onboarded.playstation, "other units' keys untouched")

local ds = devices["054c/0ce6"]
assert(W.same(ds.raw, { L1 = { button = 9 }, R2 = { axis = "RTrigger" } }), "bad raw sources dropped")
assert(ds.roles == nil and ds.face == nil and ds.detect == nil and ds.junk == nil, "the layout moved to the profile")
-- v3 made every pad its own profile; v5 gives them to the characters (none has bindings here) and keeps the first
-- one's layout for new characters: the bad duplicate role dropped, the good face kept.
assert(db.profiles == nil and db.deviceProfile == nil and db.lastProfile == nil, "no account profiles or picks")
assert(next(db.lastLayout.roles) == nil and db.lastLayout.face.bottom == "interact", "the last layout: the repaired one")
local mine = W.ns.Profile.Current()
assert(mine and mine.name == "Default" and mine.face.bottom == "interact", "the character's Default starts from it")
assert(devices["bad key"] == nil and devices["045e/0b12"] == nil)
assert(devices["2dc8/6001"].confirmed == true, "v2 migration: learned before v2 counts as confirmed")
assert(devices["2dc8/6002"].confirmed == nil, "default raw: still needs setup")
assert(devices["057e/2009"].raw.L1.button == 9 and devices["057e/2009"].roles == nil)
assert(devices["28de/11ff"].detect.buttons.PAD1 == 0 and devices["28de/11ff"].detect.labelStyle == nil)
assert(W.said("repaired %d+ damaged saved settings"))
assert(W.ns.Device.Current().key == "054c/0ce6" and W.ns.Remap.State() == "off", "the repaired db runs")

-- Fresh install: nothing to repair, the current version, no line.
local fresh = new(nil)
fresh.login()
local fdb = fresh.ns.db
assert(fdb.version == 5 and not fresh.said("repaired") and fdb.devices["054c/0ce6"].roles == nil)
-- The first character: a Default profile with the game's layout.
local me = fdb.chars[fresh.guid]
assert(me.profile == "p1" and me.profiles.p1.name == "Default" and not next(me.profiles.p1.roles) and fdb.profiles == nil, "first character: Default")

-- Not a table at all.
local junk = new("garbage")
junk.login()
assert(type(junk.ns.db.devices) == "table" and junk.ns.db.version == 5)

-- Saved by a newer the addon: kept as it is, no migration down.
local newer = new({ version = 9, options = {}, devices = {} })
newer.login()
assert(newer.ns.db.version == 9 and newer.said("newer version of Controller Tweaks"))

-- A nonsense version counts as the first one, so every migration runs and the db loads.
for _, version in ipairs({ 0, -3, 1.5, 0 / 0, math.huge }) do
	local odd = new({ version = version, options = {}, devices = { ["2dc8/6001"] = { raw = { L1 = { button = 4 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }, roles = {}, face = {} } } })
	odd.login()
	assert(odd.ns.db and odd.ns.db.version == 5 and odd.ns.db.devices["2dc8/6001"].confirmed and odd.ns.db.lastLayout, "version " .. tostring(version))
end

-- The macro and character stores: wrong types and bad entries are dropped, good ones kept.
local stores = new({
	version = 2,
	options = {},
	devices = {},
	macros = { ["FCT:Sit"] = { id = "game:sit", chars = { ["Ann-Realm"] = true } }, ["FCT:Bad"] = "x", ["FCT:NoId"] = {}, ["FCT:Chars"] = { id = "game:bags", chars = 3 } },
	faceEntries = { ["054c/0ce6"] = { bottom = { id = "spell:1" }, top = 7 } },
	chars = {
		["Ann-Realm"] = {
			macros = { ["FCT:Sit"] = { id = "game:sit" }, ["FCT:Bad"] = 1 },
			highest = { [145] = { name = "Fireball", id = "spell:133" }, [146] = "x" },
			shadow = "broken",
			placed = { [150] = { holds = "spell:133" }, [151] = "x" },
			cells = { ["054c/0ce6"] = { FT = { T = { id = "spell:133" }, B = 5 }, FR = true, P1 = { R = { id = "face:jump" }, L = "x" }, P3 = 4 } },
			legacyFaceDone = "yes",
			routedUnderDone = true,
			macroPrefixDone = 1,
		},
		["Bob-Realm"] = "not a table",
		[7] = {},
	},
})
stores.login()
local sdb = stores.ns.db
local ann = sdb.chars["Ann-Realm"]
assert(sdb.macros["FCT:Sit"].chars["Ann-Realm"] and sdb.macros["FCT:Bad"] == nil and sdb.macros["FCT:NoId"] == nil)
assert(type(sdb.macros["FCT:Chars"].chars) == "table" and sdb.faceEntries["054c/0ce6"].bottom and sdb.faceEntries["054c/0ce6"].top == nil)
assert(ann.macros["FCT:Sit"] and ann.macros["FCT:Bad"] == nil and ann.highest[145] and ann.highest[146] == nil and ann.shadow == nil and ann.placed[150] and ann.placed[151] == nil)
assert(ann.cells["054c/0ce6"].FT.T.id == "spell:133" and ann.cells["054c/0ce6"].FT.B == nil and ann.cells["054c/0ce6"].FR == nil)
-- Back paddle cells sit next to the face cells and are repaired the same way.
assert(ann.cells["054c/0ce6"].P1.R.id == "face:jump" and ann.cells["054c/0ce6"].P1.L == nil and ann.cells["054c/0ce6"].P3 == nil)
assert(ann.legacyFaceDone == nil and ann.routedUnderDone == true and ann.macroPrefixDone == nil and sdb.chars["Bob-Realm"] == nil and sdb.chars[7] == nil)
-- Bindings of a pad with no devices entry: still a profile of the character's (lossless), and it plays on it.
assert(ann.profiles["054c/0ce6"] and ann.profile == "054c/0ce6" and ann.cells["054c/0ce6"].FT.T.id == "spell:133", "cells keep their key")

-- A character's profiles: bad ids, shapes and tombstones dropped; a pick of a missing profile goes; a bad last layout
-- is repaired.
local profs = new({ version = 5, options = {}, devices = {}, lastLayout = { roles = 3, face = { L1 = "jump" } },
	chars = { ["Player-0-Zed"] = { profile = "p9", profiles = { p1 = { name = "Mine", roles = { L1 = "friendly" }, face = {} }, p2 = { gone = true }, ["bad"] = {}, p4 = "x", p5 = { name = "  ", roles = 3 } } }, ["Player-0-Yan"] = { profile = 4, profiles = 7 } } })
profs.login()
local pdb = profs.ns.db
local zed, yan = pdb.chars["Player-0-Zed"], pdb.chars["Player-0-Yan"]
assert(next(zed.profiles.p1.roles) == nil and zed.profiles.p1.name == "Mine", "a broken role set: native")
assert(zed.profiles.p2 == nil and zed.profiles.bad == nil and zed.profiles.p4 == nil, "tombstones, bad ids and shapes dropped")
assert(zed.profiles.p5.name == "Profile" and next(zed.profiles.p5.roles) == nil, "an empty name gets one")
assert(zed.profile == nil and yan.profile == nil and yan.profiles == nil, "a pick of a missing profile goes")
assert(next(pdb.lastLayout.roles) == nil and next(pdb.lastLayout.face) == nil and profs.said("repaired %d+ damaged saved settings"), "the last layout repaired")
assert(stores.said("repaired %d+ damaged saved settings"))

-- An early GAME_PAD_* event before ADDON_LOADED doesn't touch the missing db.
local early = new(nil)
early.fire("GAME_PAD_CONNECTED")
assert(early.ns.db == nil and early.ns.Device.Current() == nil)
early.login()
assert(early.ns.Device.Current())

-- Panel and onboarding values: a wrong type is dropped (the Panel's default takes over), a good one kept.
local log = {}
for i = 1, 520 do log[i] = "line " .. i end
local opts = new({ version = 2, devices = {}, debugLog = log, onboarded = "x", declined = { ["054c/0ce6"] = true },
	options = { toggleHold = { "L2", 5 }, minimapAngle = 0 / 0, glyphs = true } })
opts.login()
local odb = opts.ns.db
assert(odb.options.toggleHold == nil and odb.options.minimapAngle == nil and odb.onboarded == nil and odb.declined["054c/0ce6"])
assert(#odb.debugLog == 500 and odb.debugLog[1] == "line 21" and odb.debugLog[500] == "line 520", "the log keeps its newest 500 lines")
for _, good in ipairs({ { toggleHold = false, minimapAngle = 45 }, { toggleHold = { "L2", "R2" }, minimapAngle = -10.5 } }) do
	local kept = new({ version = 2, devices = {}, options = W.copy(good) })
	kept.login()
	assert(W.same(kept.ns.db.options.toggleHold, good.toggleHold) and kept.ns.db.options.minimapAngle == good.minimapAngle)
end
for _, bad in ipairs({ { "L2", "45" }, { 1, math.huge }, { true, -math.huge }, { { a = "L2" }, true } }) do
	local fixed = new({ version = 2, devices = {}, options = { toggleHold = bad[1], minimapAngle = bad[2] } })
	fixed.login()
assert(fixed.ns.db.options.toggleHold == nil and fixed.ns.db.options.minimapAngle == nil, tostring(bad))
end

-- The debug log is a ring: full, a new line replaces the oldest in place; at logout it is put back in order.
odb.options.debug = true
for i = 1, 3 do opts.ns.debug("new %d", i) end
assert(#odb.debugLog == 500 and odb.debugLog[1]:find("new 1") and odb.debugLog[3]:find("new 3") and odb.debugLog[4] == "line 24")
opts.fire("PLAYER_LOGOUT")
assert(#odb.debugLog == 500 and odb.debugLog[1] == "line 24" and odb.debugLog[497] == "line 520" and odb.debugLog[500]:find("new 3"), "in order at logout")

-- Per-character migrations: run until fn says done, then never again; no character, nothing runs.
local mig = new({ version = 2, options = {}, devices = {} })
mig.login()
local char = {}
mig.ns.Face = { CharDB = function() return char end }
local runs = 0
local function step() runs = runs + 1 return runs >= 2 end
mig.ns.MigrateChar("testDone", step)
assert(runs == 1 and char.testDone == nil, "not finished: the flag stays off")
mig.ns.MigrateChar("testDone", step)
mig.ns.MigrateChar("testDone", step)
assert(runs == 2 and char.testDone == true, "finished once, then skipped")
char = nil
mig.ns.MigrateChar("otherDone", step)
assert(runs == 2)

-- /fct help lists every user command.
mig.slash("help")
local help = mig.lines[#mig.lines]
for _, name in ipairs({ "bindings", "rings", "setup", "detect", "family", "preset", "role", "face", "learn", "reset", "profile", "release", "status", "selftest", "ringlog", "debug", "help" }) do
	assert(help:find("%f[%w]" .. name .. "%f[%W]"), "help names " .. name)
end

-- An event the client doesn't know is skipped instead of breaking the file (C_EventUtils.IsEventValid).
C_EventUtils = { IsEventValid = function(event) return event ~= "REMOVED_EVENT" end }
local frame = mig.frames[1]
mig.ns.On("REMOVED_EVENT", function() end)
mig.ns.On("NEW_EVENT", function() end)
assert(not frame.events.REMOVED_EVENT and frame.events.NEW_EVENT)
C_EventUtils = nil

-- TaintWatch (debug only): the first moment a watched Blizzard field turns insecure is logged once, with the line
-- before it; /fct selftest lists what is insecure now.
local tainted = {}
function issecurevariable(t, key)
	if t == GamepadSharedUtility.InputBindingManager and tainted[key] then return false, "SomeAddon" end
	return true
end
mig.slash("debug on")
mig.run(1.1)
mig.ns.debug("face: placed something")
tainted.bindingSetStack = true
mig.run(1.1)
mig.run(1.1)
local found = 0
for _, line in ipairs(mig.ns.db.debugLog) do
	if line:find("taintwatch: InputBindingManager.bindingSetStack now insecure, by SomeAddon; last before it: 12:00:00 face: placed something", 1, true) then found = found + 1 end
end
assert(found == 1, "logged once, with our last line")
mig.slash("selftest")
assert(mig.said("selftest: taintwatch: InputBindingManager.bindingSetStack by SomeAddon"))
issecurevariable = nil

io.stdout:write("db_spec: all checks passed\n")
