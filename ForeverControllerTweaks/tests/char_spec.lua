-- Stubbed WoW check of the character key (1.5.2): lua tests/char_spec.lua
-- Core.lua, Profile.lua and Face.lua over a SavedVariables table: records keyed by GUID (Forever has no realms and
-- UnitName is only the first name), 1.5.1's Name-Realm records claimed only by the character that knows every spell in
-- them, the rings and touch buttons handed out at load, and the user's real data replayed.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local passed = 0
local function check(ok, name)
	if not ok then error("FAIL " .. name, 2) end
	passed = passed + 1
end

local W = { name = "House", guid = "Player-1-0001", timers = {}, known = {} }
local frame = setmetatable({}, { __index = function() return function() end end })
local Frame = { __index = function(_, key) if key:match("^%u") then return function() end end end }
function CreateFrame()
	local f = setmetatable({ events = {}, scripts = {} }, Frame)
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	W.frame = W.frame or f
	return f
end
UIParent = frame
function print() end
function date() return "12:00:00 " end
function GetTime() return 0 end
function InCombatLockdown() return W.combat end
function GetCVar() end
function UnitName() return W.name end
function UnitGUID() return W.guid end
function issecretvalue(value) return value == W.secret end
function RegisterStateDriver() end
function SecureHandlerSetFrameRef() end
SlashCmdList = {}
Enum = { InputDeviceInterfaceType = { Gamepad = 1 } }
InputUtil = { IsGamepadUIEnabled = function() return false end }
C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end, NewTicker = function() return { Cancel = function() end } end }

-- The catalog: W.known lists this character's spells (spell:<id> and spellgroup:<name>); empty = spellbook not loaded.
local actions = {
	Catalog = function()
		local entries = {}
		for id in pairs(W.known) do entries[#entries + 1] = { id = id, kind = id:match("^(%a+):") } end
		return { { name = "Spells", entries = entries } }
	end,
	Find = function(id) return W.known[id] and { id = id } or nil end,
}

local function boot(db)
	W.frame = nil
	ForeverControllerTweaksDB = db
	local ns = {}
	assert(loadfile(dir .. "/Core.lua"))("ForeverControllerTweaks", ns)
	ns.Layout = { RepairDevice = function(entry) return entry, {} end, RepairProfile = function(profile) return profile, {} end, Same = function() return true end }
	ns.Device = { Current = function() return W.pad end }
	assert(loadfile(dir .. "/Profile.lua"))("ForeverControllerTweaks", ns)
	assert(loadfile(dir .. "/Face.lua"))("ForeverControllerTweaks", ns)
	ns.Actions = actions
	local function fire(event, ...) W.frame.scripts.OnEvent(W.frame, event, ...) end
	fire("ADDON_LOADED", "ForeverControllerTweaks")
	return ns, fire
end

local function spells(list)
	local out = {}
	for _, id in ipairs(list) do out[id] = true end
	return out
end

-- The key: the GUID; nil or a secret is unknown, and then nothing is made. The first name is kept for display.
do
	local ns, fire = boot({})
	W.guid = nil
	check(ns.Face.CharKey() == nil and ns.Face.CharDB() == nil, "no GUID: no key, no record")
	W.guid = "secret-guid"
	W.secret = "secret-guid"
	check(ns.Face.CharKey() == nil, "a secret GUID is unknown")
	W.secret = nil
	check(ns.db.chars == nil or next(ns.db.chars) == nil, "nothing was made while the key was unknown")
	W.guid = nil
	fire("PLAYER_LOGIN")
	fire("PLAYER_ENTERING_WORLD")
	check(#W.timers == 1, "unknown at the world entry: a retry is queued")
	local layout
	ns.On("FCT_LAYOUT_CHANGED", function(reason) layout = reason end)
	W.guid = "Player-1-0001"
	table.remove(W.timers, 1)()
	local char, key = ns.Face.CharDB()
	check(key == "Player-1-0001" and char.name == "House" and layout == "device", "the retry learned it, the first name kept for display, refreshed")
	W.timers = {}
end

-- Claim: only an old record of this first name whose every spell this character knows, newest first, fill-only.
do
	local ns = boot({})
	local Face = ns.Face
	local paladin = spells({ "spell:20271", "spellgroup:Holy Light", "spell:19750" })
	local function known(id) return paladin[id] end
	local chars = {
		["House-"] = { cells = { p1 = { FB = { T = { id = "spell:20271" } } } }, touch = { enabled = true }, placed = { [170] = { holds = "spell:20271" } } },
		["House-R"] = { cells = { p1 = { FB = { T = { id = "spellgroup:Holy Light" } } }, p2 = { DU = { T = { id = "spell:19750" } } } }, touch = { enabled = false }, placed = { [171] = { holds = "x" } }, legacyFaceDone = true },
		["House-Mage"] = { cells = { p1 = { FB = { T = { id = "spell:133" } } } } },
		["House-Empty"] = { cells = { p1 = { FB = { T = { id = "game:bags" } } } } },
		["Other-R"] = { cells = { p1 = { FB = { T = { id = "spell:20271" } } } } },
		["Player-1-0001"] = { name = "House" },
	}
	check(Face.Owns(chars["House-"], known) and not Face.Owns(chars["House-Mage"], known) and not Face.Owns(chars["House-Empty"], known), "owns: every spell known; a spell unknown or no spell at all is ambiguous")
	local order = Face.Candidates(chars, "House", { ["b:House-R:p1"] = 50, ["b:House-:p1"] = 10 })
	check(order[1] == "House-R" and order[2] == "House-", "newest first by sync stamp")
	check(Face.Candidates(chars, "House")[1] == "House-", "no stamps: Name- first")
	local claimed = Face.ClaimOld(chars, "Player-1-0001", "House", known, {})
	local own = chars["Player-1-0001"]
	check(#claimed == 2 and chars["House-"] == nil and chars["House-R"] == nil, "both of this character's records claimed and removed")
	check(chars["House-Mage"] and chars["House-Empty"] and chars["Other-R"], "ambiguous and other names' records left alone")
	check(own.cells.p1.FB.T.id == "spell:20271" and own.cells.p2.DU.T.id == "spell:19750", "fill-only per profile, the newest (Name-) first")
	check(own.touch.enabled == true and own.placed[170] and own.placed[171] and own.legacyFaceDone, "settings from the newest, bookkeeping merged per key")
	check(#Face.ClaimOld(chars, "Player-1-0001", "House", known, {}) == 0, "idempotent")
	-- A synced GUID record already there: the claim only fills what it lacks.
	local synced = { ["Player-1-0002"] = { name = "House", cells = { p1 = { FB = { T = { id = "spell:1" } } } } }, ["House-"] = { cells = { p1 = { FT = { T = { id = "spell:20271" } } }, p9 = { FT = { T = { id = "spell:20271" } } } } } }
	Face.ClaimOld(synced, "Player-1-0002", "House", known, {})
	check(synced["Player-1-0002"].cells.p1.FB.T.id == "spell:1" and synced["Player-1-0002"].cells.p1.FT.T.id == "spell:20271" and synced["Player-1-0002"].cells.p9, "a synced record keeps its own cells, gets only the ones it lacks")
	-- Paged cells (1.5.5): the fill goes page by page, an old record's spells on any page count for the claim.
	local paged = { ["Player-1-0003"] = { name = "House", cells = { p1 = { DU = { L = { [1] = { id = "ring:1" } } } } } }, ["House-"] = { cells = { p1 = { DU = { L = { { id = "spell:20271" }, { id = "spellgroup:Holy Light" } } }, FB = { T = { id = "spell:19750" } } } } } }
	check(Face.Owns(paged["House-"], known) and #Face.SpellsOf(paged["House-"]) == 3, "a page list's spells read for the claim")
	Face.ClaimOld(paged, "Player-1-0003", "House", known, {})
	local pl = paged["Player-1-0003"].cells.p1
	check(pl.DU.L[1].id == "ring:1" and pl.DU.L[2].id == "spellgroup:Holy Light" and pl.DU.L[3] == nil and pl.FB.T.id == "spell:19750", "fill-only per page: its own page kept, the missing page filled")
end

-- A record the first apply already touched (empty cells and touch sides, an empty placed list, a migration flag)
-- still gets everything of the old records it claims: the merge fills all the way down.
do
	local ns = boot({})
	local known = spells({ "spellgroup:Holy Light", "spell:20271", "spell:1022", "spell:21084", "spell:19750" })
	local DS = "054c/0ce6"
	local function e(id) return { id = id, name = id } end
	local chars = {
		["Player-1-PALADIN"] = { name = "House", cells = { [DS] = {} }, touchBars = { [DS] = { left = {}, right = {} } }, placed = {}, legacyFaceDone = true },
		["House-"] = {
			cells = { [DS] = { DR = { T = e("spellgroup:Holy Light") }, FT = { T = e("spell:20271") }, DU = { L = e("spell:1022"), T = e("ring:5") }, FR = { L = e("face:back"), T = e("spell:21084") }, DL = { T = e("spell:19750") } } },
			touchBars = { [DS] = { left = { { T = e("spell:19750") }, { T = e("spellgroup:Holy Light") } }, right = { { T = e("spell:20271") } } } },
			placed = { [170] = { holds = "a" }, [171] = { holds = "b" }, [172] = { holds = "c" }, [173] = { holds = "d" }, [174] = { holds = "e" } },
		},
		["House-CAMWOWEU4Realm7PvE"] = { cells = { [DS] = { DR = { T = e("spell:20271"), B = e("face:inspect") }, FB = { R = e("spellgroup:Holy Light") } } } },
	}
	local claimed = ns.Face.ClaimOld(chars, "Player-1-PALADIN", "House", function(id) return known[id] end, {})
	local c = chars["Player-1-PALADIN"].cells[DS]
	check(#claimed == 2 and chars["House-"] == nil and chars["House-CAMWOWEU4Realm7PvE"] == nil, "early record: both claimed")
	check(c.DR.T.id == "spellgroup:Holy Light" and c.FT.T.id == "spell:20271" and c.DU.L.id == "spell:1022" and c.DU.T.id == "ring:5" and c.FR.L.id == "face:back" and c.FR.T.id == "spell:21084" and c.DL.T.id == "spell:19750", "early record: every House- cell, the newest")
	check(c.DR.B.id == "face:inspect" and c.FB.R.id == "spellgroup:Holy Light", "early record: the older record's extras House- lacks")
	local bars, placed = chars["Player-1-PALADIN"].touchBars[DS], chars["Player-1-PALADIN"].placed
	check(#bars.left == 2 and bars.right[1].T.id == "spell:20271", "early record: the 3 touch buttons")
	local n = 0
	for _ in pairs(placed) do n = n + 1 end
	check(n == 5 and chars["Player-1-PALADIN"].legacyFaceDone == true, "early record: the 5 placed slots, its own flag kept")
	check(c.DR.T.name == "spellgroup:Holy Light" and c.DR.T ~= chars["Player-1-PALADIN"].cells[DS].DR.B, "early record: entries whole, never mixed")
end

-- Rings at load: each old record gets the rings its bindings open; rings nobody opens go to every record.
do
	local ring = function(id, name) return { id = id, name = name or ("R" .. id), count = 6, slots = {} } end
	local db = { version = 3, rings = { nextId = 6, axisSaved = "0", list = { ring(1), ring(2), ring(5, "Buffs") } }, chars = {
		["Ann-R"] = { cells = { p1 = { FB = { T = { id = "ring:1" } } } } },
		["Bob-R"] = { touch = { bars = { left = { [1] = { L = { id = "ring:2" } } } } } },
		["Cid-R"] = {},
	} }
	local ns = boot(db)
	local chars = ns.db.chars
	local function ids(char)
		local out = {}
		for _, r in ipairs(char.rings and char.rings.list or {}) do out[#out + 1] = r.id end
		table.sort(out)
		return table.concat(out, ",")
	end
	check(ns.db.rings == nil and ns.db.ringAxisSaved == "0", "db 4: the account list is handed out at load, the stick value account-wide")
	check(ids(chars["Ann-R"]) == "1,5" and ids(chars["Bob-R"]) == "2,5" and ids(chars["Cid-R"]) == "5", "each record its own rings, the unreferenced one to every record")
	check(chars["Ann-R"].rings.nextId == 6 and chars["Ann-R"].rings.list[1] ~= chars["Bob-R"].rings.list[1], "next id kept, copies not shared")
	ns.MoveRings(ns.db)
	check(ids(chars["Ann-R"]) == "1,5", "idempotent")
	local own = { rings = { nextId = 9, list = { { id = 1, name = "Mine" } } }, cells = { p1 = { FB = { T = { id = "ring:1" } } } } }
	ns.MoveRings({ rings = { nextId = 2, list = { ring(1) } }, chars = { X = own } })
	check(own.rings.list[1].name == "Mine" and #own.rings.list == 1 and own.rings.nextId == 9, "a record's own rings are never replaced")
end

-- Touch buttons per profile: 1.5.1's per-character buttons copied to every live profile, then removed.
do
	local buttons = { left = { [1] = { T = { id = "spell:1" } } }, right = {} }
	local db = { version = 3, profiles = { p1 = { name = "A", roles = {}, face = {} }, p2 = { name = "B", roles = {}, face = {} }, p3 = { gone = true } }, deviceProfile = {}, chars = {
		["Ann-R"] = { touch = { enabled = true, sides = { left = { size = 40 } }, bars = buttons } },
		["Bob-R"] = { touch = { enabled = false, bars = buttons }, touchBars = { p2 = { left = { [2] = { T = { id = "spell:2" } } } } } },
	} }
	local ns = boot(db)
	local ann, bob = ns.db.chars["Ann-R"], ns.db.chars["Bob-R"]
	check(ann.touch.bars == nil and ann.touch.sides.left.size == 40 and ann.touchBars.p1.left[1].T.id == "spell:1" and ann.touchBars.p2.left[1].T.id == "spell:1" and ann.touchBars.p3 == nil, "db 4: the buttons in every live profile, the layout stays")
	check(ann.touchBars.p1 ~= ann.touchBars.p2, "db 4: copies, not one shared table")
	check(bob.touchBars.p2.left[2].T.id == "spell:2" and bob.touchBars.p2.left[1] == nil and bob.touchBars.p1.left[1].T.id == "spell:1", "db 4: a profile with buttons of its own keeps them")
	ns.MoveTouchBars(ns.db, ann)
	check(ann.touchBars.p1.left[1].T.id == "spell:1", "idempotent")
	local waiting = { touch = { bars = buttons } }
	ns.MoveTouchBars({ profiles = {} }, waiting)
	check(waiting.touch.bars == buttons and waiting.touchBars == nil, "no profile: nothing moved, nothing lost")
	check(ann.profiles.p1.name == "A" and ann.profiles.p2.name == "B" and ann.profiles.p3 == nil and bob.profiles.p2, "db 5: each record gets the profiles its buttons are in, no tombstone")
	check(ns.db.profiles == nil and ns.db.deviceProfile == nil and ns.db.lastLayout, "db 5: the account profiles are gone, the last layout kept")
	W.guid = "Ann-R"
	local fresh = ns.Profile.New("C")
	check(ann.touchBars[fresh] == nil and ann.cells == nil and ann.profiles[fresh] and bob.profiles[fresh] == nil, "a new profile: this character's only, no bindings, no touch buttons")
	local copied = ns.Profile.Copy("p1", "D")
	check(ann.touchBars[copied].left[1].T.id == "spell:1" and ann.touchBars[copied] ~= ann.touchBars.p1, "Copy copies the touch buttons")
	ns.Profile.Forget("p2")
	check(ann.touchBars.p2 == nil and ann.profiles.p2 == nil and bob.touchBars.p2 and bob.profiles.p2 and ann.touchBars.p1 ~= nil, "Delete drops this character's profile and touch buttons, never another's")
	W.guid = "Player-1-0001"
end

-- The user's real shape: House- (newest: 7 cells, touch on, 3 touch buttons) and House-CAMWOWEU4Realm7PvE, both with
-- Paladin spells, and ring 5 "Buffs". A new non-paladin House logs in first after the update: it claims neither and
-- starts empty. Then the Paladin logs in and claims both, ring 5 with them.
do
	local cells = { FB = { T = { id = "spell:20271" } }, FR = { T = { id = "spellgroup:Holy Light" } }, FL = { T = { id = "spell:19750" } }, FT = { T = { id = "face:jump" } }, DU = { T = { id = "ring:5" } }, DL = { T = { id = "game:bags" } }, DR = { T = { id = "spell:20271" } } }
	local db = { version = 3, profiles = { ["054c/0ce6"] = { name = "DualSense", roles = {}, face = {} } }, deviceProfile = {}, chars = {
		["House-"] = { cells = { ["054c/0ce6"] = cells }, touch = { enabled = true, bars = { left = { { T = { id = "spell:19750" } }, { T = { id = "spellgroup:Holy Light" } } }, right = { { T = { id = "ring:5" } } } } }, placed = { [170] = { holds = "spell:19750" } } },
		["House-CAMWOWEU4Realm7PvE"] = { cells = { ["054c/0ce6"] = { FB = { T = { id = "spellgroup:Holy Light" } } }, p2 = { FB = { T = { id = "spell:20271" } } } }, touch = { enabled = false } },
	}, rings = { nextId = 6, list = { { id = 5, name = "Buffs", count = 6, slots = { [1] = { id = "spell:20217" } } } } }, macros = { ["FCT:Bags"] = { id = "game:bags", chars = { ["House-"] = true } } } }

	-- A new mage named House, first after the update.
	W.name, W.guid, W.known = "House", "Player-1-MAGE", spells({ "spell:133", "spell:168" })
	local ns, fire = boot(db)
	fire("PLAYER_LOGIN")
	fire("PLAYER_ENTERING_WORLD")
	local mage = ns.db.chars["Player-1-MAGE"]
	check(mage and mage.cells == nil and mage.touchBars == nil and mage.rings == nil and mage.name == "House", "real data: the new House starts empty: no bindings, no touch buttons, no rings")
	check(ns.db.chars["House-"] and ns.db.chars["House-CAMWOWEU4Realm7PvE"], "real data: both old records left alone")

	-- The Paladin: the spellbook loads after the login, the claim follows it.
	W.guid, W.known = "Player-1-PALADIN", {}
	local ns2, fire2 = boot(ns.db)
	fire2("PLAYER_LOGIN")
	fire2("PLAYER_ENTERING_WORLD")
	check(ns2.db.chars["House-"] ~= nil, "real data: nothing claimed before the spellbook is known")
	W.known = spells({ "spell:20271", "spellgroup:Holy Light", "spell:19750", "spell:20217" })
	fire2("FCT_CATALOG_CHANGED", "SPELLS_CHANGED")
	local pal = ns2.db.chars["Player-1-PALADIN"]
	check(ns2.db.chars["House-"] == nil and ns2.db.chars["House-CAMWOWEU4Realm7PvE"] == nil, "real data: the Paladin claims both old records")
	local n = 0
	for _ in pairs(pal.cells["054c/0ce6"]) do n = n + 1 end
	check(n == 7 and pal.cells["054c/0ce6"].FB.T.id == "spell:20271" and pal.cells.p2.FB.T.id == "spell:20271", "real data: the 7 newest cells, the older record's other profile filled in")
	check(pal.touch.enabled and #pal.touchBars["054c/0ce6"].left == 2 and pal.touchBars["054c/0ce6"].right[1].T.id == "ring:5", "real data: touch on, the 3 newest touch buttons in the profile")
	check(pal.rings and pal.rings.list[1].id == 5 and pal.rings.list[1].name == "Buffs" and #pal.rings.list == 1, "real data: ring 5 Buffs came with the claim")
	check(ns2.db.chars["Player-1-MAGE"].rings == nil, "real data: the mage still has no rings")
	check(ns2.db.macros["FCT:Bags"].chars["Player-1-PALADIN"] and ns2.db.macros["FCT:Bags"].chars["House-"] == nil, "real data: the account macro the old record used is the Paladin's now")
	W.guid, W.known = "Player-1-0001", {}
end

-- 1.5.4: the user's real 1.5.3 store (21:36). Account profiles picked per pad id: the Warlock's pads all on "Warlock",
-- Steam's 0001/11fb on the DualSense profile, two tombstones. After the update each character owns its profiles: the
-- Warlock plays on "Warlock" whatever id the pad reports, the old House records each get the DualSense profile and keep
-- it for the Paladin's claim, and a new character starts on Default with the last layout and no bindings.
do
	local DS, WL = "054c/0ce6", "p1795273533"
	local function e(id) return { id = id, name = id } end
	local db = { version = 4, lastProfile = WL,
		profiles = {
			[WL] = { name = "Warlock", roles = { L1 = "rightmod", L2 = "leftmod" }, face = {} },
			[DS] = { name = "DualSense Wireless Controller", roles = {}, face = {} },
			["045e/028e"] = { name = "Profile 1", roles = {}, face = {} },
			["0001/11fb"] = { gone = true }, ["3537/1116"] = { gone = true },
		},
		deviceProfile = { [DS] = { id = WL, at = 5 }, ["045e/028e"] = { id = WL, at = 5 }, ["3537/1116"] = { id = WL, at = 5 }, ["0001/11fb"] = { id = DS, at = 5 } },
		sync = { pads = { [DS] = "DualSense Wireless Controller" } },
		chars = {
			["Player-6941-WARLOCK"] = { name = "House", cells = { [WL] = { FR = { T = e("spell:686"), L = e("face:back") }, FT = { T = e("spell:348") }, DU = { B = e("game:zoomin") }, DD = { B = e("game:zoomout") } } } },
			["House-"] = { cells = { [DS] = { FB = { T = e("spell:20271") }, FR = { T = e("spellgroup:Holy Light") }, FL = { T = e("spell:19750") }, DL = { T = e("game:bags") }, DR = { T = e("spell:20271") } } },
				touchBars = { [DS] = { left = { { T = e("spell:19750") }, { T = e("spellgroup:Holy Light") } }, right = { { T = e("spell:20271") } } } } },
			["House-CAMWOWEU4Realm7PvE"] = { cells = { [DS] = { FB = { R = e("spellgroup:Holy Light") }, FT = { T = e("spell:20271") }, DU = { T = e("spell:19750") }, DD = { T = e("spell:20271") } } } },
		},
	}
	W.name, W.guid, W.known, W.pad = "House", "Player-6941-WARLOCK", spells({ "spell:686", "spell:348" }), { key = DS }
	local ns, fire = boot(db)
	fire("PLAYER_LOGIN")
	fire("PLAYER_ENTERING_WORLD")
	local P, chars = ns.Profile, ns.db.chars
	local wl = chars["Player-6941-WARLOCK"]
	check(ns.db.version == 6 and ns.db.profiles == nil and ns.db.deviceProfile == nil and ns.db.lastProfile == nil, "real 1.5.3: the account profiles and picks are gone")
	check(ns.db.lastLayout and ns.db.lastLayout.roles.L1 == "rightmod", "real 1.5.3: the last layout is the Warlock profile's")
	check(wl.profile == WL and wl.profiles[WL].name == "Warlock" and wl.profiles[DS] == nil and wl.profiles["045e/028e"] == nil, "real 1.5.3: the Warlock owns Warlock only")
	for _, key in ipairs({ DS, "045e/028e", "0001/11fb", "3537/1116", "2dc8/6001" }) do
		W.pad = { key = key }
		ns.Fire("FCT_LAYOUT_CHANGED", "device")
		check(P.CurrentId() == WL and P.Current().name == "Warlock", "real 1.5.3: the Warlock on Warlock with pad " .. key)
		check(ns.Face.CellEntry("FR", "T").id == "spell:686" and ns.Face.CellEntry("FR", "L").id == "face:back" and ns.Face.CellEntry("FT", "T").id == "spell:348" and ns.Face.CellEntry("DU", "B").id == "game:zoomin" and ns.Face.CellEntry("DD", "B").id == "game:zoomout", "real 1.5.3: Shadow Bolt, Back, Immolate, Zoom in and out with pad " .. key)
	end
	for _, old in ipairs({ "House-", "House-CAMWOWEU4Realm7PvE" }) do
		local record = chars[old]
		check(record.profile == DS and record.profiles[DS].name == "DualSense Wireless Controller" and record.profiles["p1795273533"] == nil, "real 1.5.3: " .. old .. " keeps the DualSense profile for its claim")
	end
	check(chars["House-"].profiles[DS] ~= chars["House-CAMWOWEU4Realm7PvE"].profiles[DS], "real 1.5.3: copies, not one shared table")
	P.MoveToChars(ns.db)
	check(wl.profile == WL and chars["House-"].profile == DS and not ns.db.profiles, "real 1.5.3: the migration again changes nothing")

	-- The Paladin's first login: Default first (the spellbook isn't there), then the claim brings the DualSense profile
	-- and the Paladin plays on it.
	W.guid, W.known = "Player-6941-PALADIN", {}
	local ns2, fire2 = boot(ns.db)
	fire2("PLAYER_LOGIN")
	fire2("PLAYER_ENTERING_WORLD")
	local P2 = ns2.Profile
	P2.Ensure()
	local pal = ns2.db.chars["Player-6941-PALADIN"]
	check(P2.Current().name == "Default" and P2.Current().roles.L1 == "rightmod" and pal.cells == nil and pal.touchBars == nil, "new character: Default with the last layout, no bindings")
	W.known = spells({ "spell:20271", "spellgroup:Holy Light", "spell:19750" })
	fire2("FCT_CATALOG_CHANGED", "SPELLS_CHANGED")
	check(ns2.db.chars["House-"] == nil and ns2.db.chars["House-CAMWOWEU4Realm7PvE"] == nil, "real 1.5.3: the Paladin claims both House records")
	check(P2.CurrentId() == DS and P2.Current().name == "DualSense Wireless Controller" and pal.profiles.p1.name == "Default", "real 1.5.3: the claim carries the profile, the Paladin plays on it")
	check(ns2.Face.CellEntry("FB", "T").id == "spell:20271" and ns2.Face.CellEntry("FB", "R").id == "spellgroup:Holy Light" and #pal.touchBars[DS].left == 2, "real 1.5.3: the Paladin's bindings and touch buttons on it")
	check(ns2.db.chars["Player-6941-WARLOCK"].profile == WL and ns2.db.chars["Player-6941-WARLOCK"].profiles[DS] == nil, "real 1.5.3: the Warlock never sees the Paladin's profiles")
	W.guid, W.known, W.pad = "Player-1-0001", {}, nil
end

io.write(("char_spec: %d checks passed\n"):format(passed))
