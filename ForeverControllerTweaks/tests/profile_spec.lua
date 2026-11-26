-- Profiles (Profile.lua) over the engine stubs, per character since 1.5.4: the first Default, Use, Copy, New, Rename,
-- Delete, another pad id, another character and /fct profile: lua tests/profile_spec.lua
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
local ANN, BOB = W.guid, "Player-1-00000002"
W.pads[1] = W.newPad("DualSense Wireless Controller", 0x054c, 0x0ce6)
W.login()
local ns = W.ns
local P, Layout, db = ns.Profile, ns.Layout, ns.db
local changes = 0
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then changes = changes + 1 end end)
local ann = db.chars[ANN]

-- The first character: Default, no question, no account profiles.
check(P.CurrentId() == "p1" and ann.profile == "p1" and ann.profiles.p1.name == "Default" and db.profiles == nil and db.deviceProfile == nil, "first character: Default")
check(P.Pending == nil and P.IdFor == nil and P.Controllers == nil, "no controller picks left")
assert(Layout.SetPreset("split"))
check(ann.profiles.p1.roles.L1 == "rightmod" and db.devices["054c/0ce6"].roles == nil, "a layout write goes to the character's profile")
ann.cells = { p1 = { FB = { T = { id = "spell:133" } } } }

-- Another pad id (Steam Link, Android, the pad itself): the same profile, nothing written.
for _, pad in ipairs({ W.newPad("Xbox 360 Controller", 0x045e, 0x028e), W.newPad("Steam Virtual Gamepad", 0x0001, 0x11fb), W.newPad("GameSir", 0x3537, 0x1116) }) do
	W.pads[1] = pad
	W.fire("GAME_PAD_CONNECTED")
	W.run()
	check(P.CurrentId() == "p1" and Layout.Roles().L1 == "rightmod" and ann.cells[P.CellsKey()].FB.T.id == "spell:133", "pad " .. ns.Device.Current().key .. ": the same profile, its bindings")
end
local count = 0
for _ in pairs(ann.profiles) do count = count + 1 end
check(count == 1 and #P.List() == 1, "no profile made per pad")

-- Copy: a deep copy of the layout and of this character's bindings; New: empty; names stay unique.
ann.cells.p1.DU = { L = { { id = "ring:1" }, nil, { id = "face:jump" } } }
local copyId = P.Copy("p1", "Couch")
check(ann.cells[copyId].DU.L[1].id == "ring:1" and ann.cells[copyId].DU.L[2] == nil and ann.cells[copyId].DU.L[3].id == "face:jump" and ann.cells[copyId].DU.L ~= ann.cells.p1.DU.L, "Copy: a paged cell's pages, deep")
ann.cells.p1.DU, ann.cells[copyId].DU = nil, nil
check(copyId and copyId:find("^p%d+$") and copyId ~= "p1" and ann.profiles[copyId].roles.L1 == "rightmod" and ann.cells[copyId].FB.T.id == "spell:133", "Copy: the layout and the bindings")
ann.cells[copyId].FB.T.id = "spell:1"
ann.profiles[copyId].roles.L1 = "friendly"
check(ann.cells.p1.FB.T.id == "spell:133" and ann.profiles.p1.roles.L1 == "rightmod", "Copy: deep, the source untouched")
local newId = P.New("Default")
check(ann.profiles[newId].name == "Default 2" and not next(ann.profiles[newId].roles) and ann.cells[newId] == nil, "New: empty, a duplicate name gets 2")
check(P.Rename(newId, "  Desk  ") == "Desk" and P.Rename(newId, "couch") == "couch 2", "Rename: trimmed, unique whatever the case")
P.Rename(newId, "Desk")

-- Use: this character's pick, re-applied, the layout follows.
changes = 0
assert(P.Use(copyId))
check(changes == 1 and P.CurrentId() == copyId and ann.profile == copyId and Layout.Roles().L1 == "friendly", "switch: applied, its layout")
assert(P.Use(copyId))
check(changes == 1, "Use of the profile it already plays on: no re-apply")
check(not P.Use("p404"), "an unknown profile: refused")

-- Out of combat only: the switch waits for the fight to end.
W.combat = true
P.Use("p1")
check(P.CurrentId() == copyId, "in combat: waits")
W.combat = false
W.run(0.5)
check(P.CurrentId() == "p1", "after the fight: switched")
P.Use(copyId)

-- Delete: the profile and its bindings go, the character moves to the first one left; never the last one.
changes = 0
assert(P.Delete(copyId))
check(ann.profiles[copyId] == nil and ann.cells[copyId] == nil, "Delete: gone with its bindings, no tombstone")
check(P.CurrentId() == P.List()[1].id and ann.profile == P.CurrentId() and changes == 1, "Delete: on the first one left, re-applied")
assert(P.Delete(newId))
check(select(2, P.Delete("p1")) and P.Get("p1"), "the last profile can't be deleted")
check(P.CurrentId() == "p1" and ann.cells.p1.FB.T.id == "spell:133", "and the character is on it with its bindings")

-- Another character: its own Default from the last layout, none of Ann's profiles; Ann's stay hers.
P.New("Steam Deck")
db.lastLayout = { roles = { L1 = "rightmod", L2 = "leftmod" }, face = {} }
W.guid = BOB
check(P.CurrentId() == nil and #P.List() == 0, "Bob before his first apply: nothing")
P.Ensure()
local bob = db.chars[BOB]
check(P.Current().name == "Default" and P.Current().roles.L1 == "rightmod" and bob.cells == nil and bob.touchBars == nil, "Bob: Default with the last layout, no bindings")
check(#P.List() == 1 and P.Get("p1") ~= ann.profiles.p1, "Bob sees his profiles only")
P.Rename("p1", "Bob's")
W.guid = ANN
check(P.Current().name == "Default" and #P.List() == 2, "Ann's profiles untouched")

-- The last layout follows the character played last on this computer.
assert(Layout.SetPreset("native"))
W.fire("PLAYER_LOGOUT")
check(db.lastLayout and next(db.lastLayout.roles) == nil and db.lastLayout.roles ~= ann.profiles.p1.roles, "logout: a copy of this character's layout")

-- /fct profile lists this character's profiles and switches between them.
W.slash("profile")
check(W.said("Profiles of this character: Default %(current%), Steam Deck%."), "/fct profile lists, the current one marked")
W.slash("profile steam deck")
check(P.Current().name == "Steam Deck" and W.said("now plays on the profile Steam Deck"), "/fct profile <name> switches")
W.slash("profile Bob's")
check(W.said("No profile named Bob's"), "another character's profile is unknown here")

io.stdout:write(("profile_spec: %d checks passed\n"):format(checks))
