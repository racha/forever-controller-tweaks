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
assert(db.version == 2 and ForeverControllerTweaksDB == db)
assert(options.glyphs == true and options.toggleKey == "PADSOCIAL" and options.debug == false and options.glyphHide == "overlay")
assert(#db.debugLog == 500 and db.debugLog[1] == "line 101", "debug log capped, newest kept")
assert(db.faceEntries["054c/0ce6"].bottom.kind == "spell" and db.onboarded.playstation, "other units' keys untouched")

local ds = devices["054c/0ce6"]
assert(W.same(ds.raw, { L1 = { button = 9 }, R2 = { axis = "RTrigger" } }), "bad raw sources dropped")
assert(next(ds.roles) == nil and ds.face.bottom == "interact" and ds.detect == nil and ds.junk == nil)
assert(devices["bad key"] == nil and devices["045e/0b12"] == nil)
assert(devices["2dc8/6001"].confirmed == true, "v2 migration: learned before v2 counts as confirmed")
assert(devices["2dc8/6002"].confirmed == nil, "default raw: still needs setup")
assert(devices["057e/2009"].raw.L1.button == 9 and devices["057e/2009"].roles.L1 == "rightmod" and next(devices["057e/2009"].face) == nil)
assert(devices["28de/11ff"].detect.buttons.PAD1 == 0 and devices["28de/11ff"].detect.labelStyle == nil)
assert(W.said("repaired %d+ damaged saved settings"))
assert(W.ns.Device.Current().key == "054c/0ce6" and W.ns.Remap.State() == "off", "the repaired db runs")

-- Fresh install: nothing to repair, the current version, no line.
local fresh = new(nil)
fresh.login()
assert(fresh.ns.db.version == 2 and not fresh.said("repaired") and next(fresh.ns.db.devices["054c/0ce6"].roles) == nil)

-- Not a table at all.
local junk = new("garbage")
junk.login()
assert(type(junk.ns.db.devices) == "table" and junk.ns.db.version == 2)

-- Saved by a newer the addon: kept as it is, no migration down.
local newer = new({ version = 9, options = {}, devices = {} })
newer.login()
assert(newer.ns.db.version == 9 and newer.said("newer version of Controller Tweaks"))

-- A nonsense version counts as the first one, so every migration runs and the db loads.
for _, version in ipairs({ 0, -3, 1.5, 0 / 0, math.huge }) do
	local odd = new({ version = version, options = {}, devices = { ["2dc8/6001"] = { raw = { L1 = { button = 4 }, R1 = { button = 10 }, L2 = { axis = "LTrigger" }, R2 = { axis = "RTrigger" } }, roles = {}, face = {} } } })
	odd.login()
	assert(odd.ns.db and odd.ns.db.version == 2 and odd.ns.db.devices["2dc8/6001"].confirmed, "version " .. tostring(version))
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
			cells = { ["054c/0ce6"] = { FT = { T = { id = "spell:133" }, B = 5 }, FR = true, P1 = { R = { id = "face:jump" }, L = "x" }, P3 = 4 } },
			legacyFaceDone = "yes",
			routedUnderDone = true,
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
assert(ann.macros["FCT:Sit"] and ann.macros["FCT:Bad"] == nil and ann.highest[145] and ann.highest[146] == nil and ann.shadow == nil)
assert(ann.cells["054c/0ce6"].FT.T.id == "spell:133" and ann.cells["054c/0ce6"].FT.B == nil and ann.cells["054c/0ce6"].FR == nil)
-- Back paddle cells sit next to the face cells and are repaired the same way.
assert(ann.cells["054c/0ce6"].P1.R.id == "face:jump" and ann.cells["054c/0ce6"].P1.L == nil and ann.cells["054c/0ce6"].P3 == nil)
assert(ann.legacyFaceDone == nil and ann.routedUnderDone == true and sdb.chars["Bob-Realm"] == nil and sdb.chars[7] == nil)
assert(stores.said("repaired %d+ damaged saved settings"))

-- An early GAME_PAD_* event before ADDON_LOADED doesn't touch the missing db.
local early = new(nil)
early.fire("GAME_PAD_CONNECTED")
assert(early.ns.db == nil and early.ns.Device.Current() == nil)
early.login()
assert(early.ns.Device.Current())

io.stdout:write("db_spec: all checks passed\n")
