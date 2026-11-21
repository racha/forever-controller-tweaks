-- Profiles (Profile.lua) over the engine stubs: the first controller, a new one, Use, Copy, New, Rename, Delete and
-- /fct profile: lua tests/profile_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local harness = dofile(here .. "/wow.lua")

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

local server = 1795200000
function GetServerTime() return server end

local W = harness(here .. "/..", { pads = {} })
local DS, XB = "054c/0ce6", "045e/0b13"
W.pads[1] = W.newPad("DualSense Wireless Controller", 0x054c, 0x0ce6)
W.login()
local ns = W.ns
local P, Layout, db = ns.Profile, ns.Layout, ns.db
local changes = 0
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then changes = changes + 1 end end)

-- The first controller ever: Default, the addon's own pick, no question.
check(P.CurrentId() == "p1" and db.profiles.p1.name == "Default" and db.deviceProfile[DS].at == 0 and not P.Pending(), "first controller: Default, no question")
assert(Layout.SetPreset("split"))
check(db.profiles.p1.roles.L1 == "rightmod" and db.devices[DS].roles == nil, "a layout write goes to the profile")
db.chars = { ["Ann-Realm"] = { cells = { p1 = { FB = { T = { id = "spell:133" } } } } }, ["Bob-Realm"] = { cells = { p1 = { FT = { R = { id = "spell:9" } } } } } }

-- A new controller: the question is due; it plays on the last profile meanwhile and nothing is written.
W.pads[1] = W.newPad("Xbox Wireless Controller", 0x045e, 0x0b13)
W.fire("GAME_PAD_CONNECTED")
check(ns.Device.Current().key == XB and P.Pending() and P.CurrentId() == "p1" and db.deviceProfile[XB] == nil, "new controller: pending, on the last profile, nothing written")
check(Layout.Roles().L1 == "rightmod", "it plays with that profile's layout")

-- Use: the player's pick; both controllers read one cells table.
server = server + 10
changes = 0
assert(P.Use("p1"))
check(not P.Pending() and db.deviceProfile[XB].id == "p1" and db.deviceProfile[XB].at == server, "Use: the pick, stamped")
check(changes == 0, "Use of the profile it already played on: no re-apply")
check(P.CellsKey() == "p1" and P.IdFor(DS) == "p1", "shared: one cells key")
db.chars["Ann-Realm"].cells[P.CellsKey()].FR = { T = { id = "spell:5" } }
check(db.chars["Ann-Realm"].cells[P.IdFor(DS)].FR.T.id == "spell:5", "a binding made on one shows on the other")

-- Copy: a deep copy of the layout and of every character's bindings; New: empty; names stay unique.
local copyId = P.Copy("p1", "Xbox Wireless Controller")
local ann, bob = db.chars["Ann-Realm"].cells, db.chars["Bob-Realm"].cells
check(copyId and copyId:find("^p%d+$") and copyId ~= "p1" and db.profiles[copyId].roles.L1 == "rightmod", "Copy: the layout")
check(ann[copyId].FB.T.id == "spell:133" and bob[copyId].FT.R.id == "spell:9", "Copy: every character's bindings")
ann[copyId].FB.T.id = "spell:1"
db.profiles[copyId].roles.L1 = "friendly"
check(ann.p1.FB.T.id == "spell:133" and db.profiles.p1.roles.L1 == "rightmod", "Copy: deep, the source untouched")
local newId = P.New("Default")
check(db.profiles[newId].name == "Default 2" and not next(db.profiles[newId].roles) and not next(db.profiles[newId].face) and ann[newId] == nil, "New: empty, a duplicate name gets 2")
check(P.Rename(newId, "  Couch  ") == "Couch" and P.Rename(newId, "default") == "default 2", "Rename: trimmed, unique whatever the case")
P.Rename(newId, "Couch")

-- Use another profile: re-applied as a device change, the layout follows.
changes = 0
P.Use(copyId)
check(changes == 1 and P.CurrentId() == copyId and Layout.Roles().L1 == "friendly" and db.lastProfile == copyId, "switch: applied, its layout")
check(P.IdFor(DS) == "p1", "the other controller keeps its own")

-- Out of combat only: the switch waits for the fight to end.
W.combat = true
P.Use("p1")
check(P.CurrentId() == copyId, "in combat: waits")
W.combat = false
W.run(0.5)
check(P.CurrentId() == "p1", "after the fight: switched")
P.Use(copyId)

-- Delete: a tombstone, the bindings go, its controllers move to the first one left; never the last one.
changes = 0
assert(P.Delete(copyId))
local first = P.List()[1].id
check(db.profiles[copyId].gone and ann[copyId] == nil and bob[copyId] == nil, "Delete: tombstone, bindings gone")
check(P.CurrentId() == first and db.deviceProfile[XB].id == first and changes == 1 and first == newId, "Delete: its controller on the first left (Couch), re-applied")
assert(P.Delete(newId))
check(select(2, P.Delete("p1")) and P.Get("p1"), "the last profile can't be deleted")
check(db.deviceProfile[XB].id == "p1" and P.CurrentId() == "p1", "and everything is on it")

-- /fct profile lists them and switches this controller.
P.New("Steam Deck")
W.slash("profile")
check(W.said("Profiles: Default %(this controller%), Steam Deck%."), "/fct profile lists, this one marked")
W.slash("profile steam deck")
check(P.Get(P.CurrentId()).name == "Steam Deck" and W.said("now uses the profile Steam Deck"), "/fct profile <name> switches")
W.slash("profile Nope")
check(W.said("No profile named Nope"), "an unknown name says so")

-- The known controllers, for the Settings tab.
local byKey = {}
for _, pad in ipairs(P.Controllers()) do byKey[pad.key] = pad end
check(#P.Controllers() == 2 and byKey[DS].id == "p1" and byKey[XB].id == P.CurrentId(), "controllers: both, with their profiles")

io.stdout:write(("profile_spec: %d checks passed\n"):format(checks))
