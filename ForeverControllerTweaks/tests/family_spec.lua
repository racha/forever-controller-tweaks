-- Stubbed checks of the family pick for unrecognised pads: lua tests/family_spec.lua
-- (The wizard replacing a pick is checked in detect_spec.)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local harness = dofile(here .. "/wow.lua")
local KEY = "2dc8/6001"

local W = harness(here .. "/..", { pads = {} })
local pad = W.newPad("Cheap Pad", 0x2dc8, 0x6001, 1)
pad.labelStyle = "Generic"
W.pads[1] = pad
W.login()
local ns = W.ns
local Device, entry = ns.Device, ns.db.devices[KEY]
local changes = 0
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then changes = changes + 1 end end)
assert(Device.NeedsSetup() and ns.Remap.State() == "needsSetup")
assert(ns.Layout.SetPreset("split"))
W.run()
assert(next(W.configs) == nil)

-- Suggestions only from what the pad reports: Steam's virtual gamepad is Xbox, anything else nil.
assert(Device.SuggestedFamily(KEY) == nil and Device.SuggestedFamily() == nil)
assert(Device.SuggestedFamily("28de/11ff") == "xbox" and Device.SuggestedFamily("28de/1205") == nil)

-- Custom isn't a template: false, nothing changes, the panel runs the wizard.
assert(not Device.SetFamily(KEY, "custom") and Device.NeedsSetup() and entry.family == nil and changes == 0)
assert(not Device.SetFamily(KEY, "sega") and not Device.SetFamily("9999/9999", "xbox"))
assert(not Device.SetFamily("054c/0ce6", "xbox"), "a certain vendor's family isn't picked")

-- A pick: the SDL template, the family's labels, NeedsSetup cleared, the layout applies with those labels.
entry.raw.L1 = { button = 3 }
assert(Device.SetFamily(KEY, "switch") and changes == 1)
local current = Device.Current()
assert(entry.family == "switch" and entry.familyPicked == true and entry.raw.L1.button == 9, "template replaces learned raw")
assert(current.family == "switch" and current.labelStyle == "Reverse" and current.familyPicked and not Device.NeedsSetup())
W.run()
assert(ns.Remap.State() == "ours" and W.configs[KEY].labelStyle == "Reverse")
assert(Device.SetFamily(nil, "playstation") and Device.Current().labelStyle == "Shapes")

local saved = W.copy(ns.db)

-- Reset: unrecognised again, nothing written.
assert(Device.ResetFamily(KEY) and changes == 3)
W.run()
assert(entry.family == nil and entry.familyPicked == nil and Device.NeedsSetup() and next(W.configs) == nil)

-- The chat command.
W.slash("family xbox")
assert(Device.Current().family == "xbox" and W.said("family: xbox"))
W.slash("family custom")
assert(W.said("/fct detect%)") and Device.Current().family == "xbox")
W.slash("family reset")
assert(Device.NeedsSetup())

-- Each harness replaces the globals, so the reloads come last. The pick survives a reload and the db repair.
local W2 = harness(here .. "/..", { db = saved, pads = { [1] = W.copy(pad) } })
W2.login()
assert(W2.ns.Device.Current().family == "playstation" and not W2.ns.Device.NeedsSetup())

-- A damaged pick in the db is dropped.
local W3 = harness(here .. "/..", { db = { version = 2, options = {}, devices = { [KEY] = { raw = {}, roles = {}, face = {}, family = "sega", familyPicked = true } } }, pads = { [1] = W.copy(pad) } })
W3.login()
assert(W3.ns.db.devices[KEY].family == nil and W3.ns.db.devices[KEY].familyPicked == nil and W3.ns.Device.NeedsSetup())

io.stdout:write("family_spec: all checks passed\n")
