-- Stubbed checks of Remap: lua tests/remap_spec.lua
-- Combat-start sync apply, no churn, foreign snapshot/restore, leftovers, logout in combat, idle ticker, ApplyNow.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local harness = dofile(here .. "/wow.lua")
local DS, TAG = "054c/0ce6", "Forever Controller Tweaks"
local function new(opts) return harness(here .. "/..", opts) end
local function ours(config) return config and config.comment and config.comment:sub(1, #TAG) == TAG end

-- Combat start with our window open: Panel closes on FCT_COMBAT_START, then Remap applies ours synchronously,
-- before the lockdown (the stub's combat flag flips only after the handlers ran).
local W = new()
local ns, configs = W.ns, W.configs
assert(not ns.Remap.ApplyNow("early"), "nothing applies before the first PLAYER_ENTERING_WORLD")
W.login()
assert(ns.Layout.SetPreset("split"))
W.run()
assert(ours(configs[DS]) and ns.Remap.State() == "ours")
ns.SetPanelOpen(true)
W.run()
assert(configs[DS] == nil and ns.Remap.State() == "native")
local order = {}
ns.On("FCT_COMBAT_START", function()
	order[#order + 1] = configs[DS] == nil and "start (native)" or "start (ours)"
	ns.SetPanelOpen(false)
end)
local apply = ns.Remap.ApplyNow
ns.Remap.ApplyNow = function(reason)
	order[#order + 1] = "apply " .. reason
	return apply(reason)
end
W.fire("PLAYER_REGEN_DISABLED")
W.combat = true
assert(order[1] == "start (native)" and order[2] == "apply combat", "COMBAT_START listeners run before the apply")
assert(ours(configs[DS]) and ns.Remap.State() == "ours", "the fight uses our mapping")
W.run(1)
assert(ours(configs[DS]), "nothing is written in combat")

-- A Blizzard window held open into the fight still gets ours (forced); native comes back after combat.
W.combat = false
W.padFree = false
W.run()
assert(configs[DS] == nil)
W.fire("PLAYER_REGEN_DISABLED")
W.combat = true
assert(ours(configs[DS]))
W.combat = false
W.run()
assert(configs[DS] == nil, "the window is still open after combat: native")
W.padFree = true
W.run()

-- In the lockdown itself ApplyNow can't write.
W.combat = true
ns.SetPanelOpen(true)
assert(not ns.Remap.ApplyNow("test"))
W.combat = false
ns.SetPanelOpen(false)
W.run()

-- No churn: zoning and repeated ticks write nothing new; a real change writes once.
local writes = W.calls.set
for _ = 1, 3 do
	W.fire("PLAYER_ENTERING_WORLD")
	W.run(0.5)
end
assert(W.calls.set == writes, "identical config not written again")
assert(ns.Layout.SetRole("L1", "hostile"))
W.run()
assert(W.calls.set == writes + 1)

-- Idle: with the native layout the remap ticker stops, and a layout change wakes it.
assert(ns.Layout.SetPreset("native"))
W.run()
local idle = W.liveTickers()
assert(ns.Layout.SetPreset("split"))
assert(W.liveTickers() == idle + 1, "woken by the layout change")
W.run()
assert(ours(configs[DS]))
W.active = false
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
W.run()
assert(configs[DS] == nil and W.liveTickers() == idle, "stops while the Gamepad UI is off")
W.active = true
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
W.run()
assert(ours(configs[DS]))

-- Logout in combat: nothing written, the db remembers; the next login restores first and says so.
W.combat = true
W.fire("PLAYER_LOGOUT")
assert(ns.db.dirtyConfig == DS and ours(configs[DS]))
local W2 = new({ db = W.copy(ns.db), configs = W.copy(configs) })
W2.login()
assert(W2.said("ended in combat") and W2.ns.db.dirtyConfig == nil)
assert(W2.calls.delete >= 1 and ours(W2.configs[DS]), "cleared, then our layout applied again")
W2.fire("PLAYER_LOGOUT")
assert(W2.configs[DS] == nil, "a normal logout leaves the config clean")

-- Leftover from a crash, no layout: removed at login with one line.
local W3 = new({ configs = { [DS] = { comment = TAG, configID = { vendorID = 0x054c, productID = 0x0ce6 }, rawButtonMappings = {} } } })
W3.login()
assert(W3.configs[DS] == nil and W3.said("removed a leftover"))

-- A foreign config: merged while ours, restored for native, its line shown once per session.
local foreign = { comment = "Other addon", configID = { vendorID = 0x054c, productID = 0x0ce6 }, rawButtonMappings = { { rawIndex = 3, button = "PAD4" } }, axisConfigs = {} }
local W4 = new({ configs = { [DS] = W.copy(foreign) } })
W4.login()
local entry = W4.ns.db.devices[DS]
assert(W4.ns.Layout.SetPreset("split"))
W4.run()
assert(W4.configs[DS].comment == TAG .. " (was: Other addon)" and #W4.configs[DS].rawButtonMappings == 3 and entry.foreign)
W4.padFree = false
W4.run()
assert(W4.same(W4.configs[DS], foreign) and entry.foreign == nil, "restored for native")
W4.padFree = true
W4.run()
assert(entry.foreign and ours(W4.configs[DS]) and W4.count("another controller config exists") == 1)

-- A failed restore keeps the snapshot.
local setConfig = C_GamePad.SetConfig
C_GamePad.SetConfig = function() error("refused") end
W4.padFree = false
W4.run()
assert(entry.foreign and W4.said("failed"), "snapshot kept when the restore fails")
C_GamePad.SetConfig = setConfig
W4.run()
assert(entry.foreign == nil and W4.same(W4.configs[DS], foreign))
W4.padFree = true
W4.run()

-- The foreign config disappears altogether: the stale snapshot is dropped, not written back.
W4.configs[DS] = nil
W4.fire("GAME_PAD_CONFIGS_CHANGED")
W4.run()
assert(entry.foreign == nil and W4.configs[DS].comment == TAG, "stale snapshot dropped")
W4.fire("PLAYER_LOGOUT")
assert(W4.configs[DS] == nil)

-- The other addon rewrites its config while ours is applied: its newer config stays, the old snapshot is dropped.
local W6 = new({ configs = { [DS] = W.copy(foreign) } })
W6.login()
local e6 = W6.ns.db.devices[DS]
assert(W6.ns.Layout.SetPreset("split"))
W6.run()
assert(e6.foreign and ours(W6.configs[DS]))
local newer = W.copy(foreign)
newer.comment = "Other addon v2"
W6.configs[DS] = newer
W6.padFree = false
W6.run()
assert(W6.configs[DS].comment == "Other addon v2" and e6.foreign == nil, "the newer foreign config is kept")
W6.fire("PLAYER_LOGOUT")
assert(W6.configs[DS].comment == "Other addon v2")

-- A crash lost the snapshot: the merged config left behind gives the other addon's config back, not a delete.
foreign.rawButtonMappings[2] = { rawIndex = 9, button = "PADLSHOULDER" }
local merged = W.copy(W4.ns.Layout.Merge(W.copy(foreign), W4.ns.Layout.BuildConfig(W4.ns.Device.Current(), W4.ns.Layout.PRESETS.split, false), true))
local W7 = new({ configs = { [DS] = merged } })
W7.login()
local rebuilt = W7.configs[DS]
assert(rebuilt.comment == "Other addon" and W7.same(rebuilt.rawButtonMappings, foreign.rawButtonMappings) and #rebuilt.axisConfigs == 0, "the other addon's config rebuilt from the merged one")
assert(W7.calls.delete == 0)

-- Our own write raises GAME_PAD_CONFIGS_CHANGED inside SetConfig: not taken for another addon.
local W8 = new({ configs = { [DS] = W.copy(foreign) } })
local set8 = C_GamePad.SetConfig
C_GamePad.SetConfig = function(c)
	set8(c)
	W8.fire("GAME_PAD_CONFIGS_CHANGED")
end
W8.login()
W8.ns.db.options.debug = true
assert(W8.ns.Layout.SetPreset("split"))
W8.run()
W8.padFree = false
W8.run()
W8.padFree = true
W8.run()
for _, line in ipairs(W8.ns.db.debugLog) do assert(not line:find("another addon replaced"), line) end
C_GamePad.SetConfig = set8

-- Held inputs: the panel shortcut (L2 + R2 held, Create pressed) must not switch configs under the held triggers.
-- The DualSense stub is 1-based, so raw axis 5 (RTrigger) is rawAxes[6].
local W5 = new()
local pad, Device = W5.pads[1], W5.ns.Device
W5.login()
assert(W5.ns.Layout.SetPreset("split"))
W5.run()
assert(ours(W5.configs[DS]))
pad.rawAxes[6] = 1
W5.ns.SetPanelOpen(true)
W5.run(1)
assert(ours(W5.configs[DS]) and Device.Held() == "RTrigger", "a held trigger defers the switch to native")
pad.rawAxes[6] = 0.2
W5.run()
assert(W5.configs[DS] == nil, "the release (below a quarter pull) applies it")

-- Closing the panel with a raw button still down waits for that button too.
pad.rawButtons[2] = true
W5.ns.SetPanelOpen(false)
W5.run(1)
assert(W5.configs[DS] == nil and Device.Held() == "raw button 1")
pad.rawButtons[2] = false
W5.run()
assert(ours(W5.configs[DS]))

-- Combat start forces ours even with a trigger held: the fight must run on our mapping.
W5.padFree = false
W5.run()
assert(W5.configs[DS] == nil)
pad.rawAxes[6] = 1
W5.fire("PLAYER_REGEN_DISABLED")
W5.combat = true
assert(ours(W5.configs[DS]), "combat start forces the switch")
W5.combat, W5.padFree = false, true
pad.rawAxes[6] = 0

-- A detected pad: its trigger is scaled as its config does (rest -1 is released), and an axis D-pad counts.
local current = Device.Current()
current.detect = { axes = { RTrigger = { raw = 2, shift = 1, scale = 0.5 } }, hats = { DpadUp = { raw = 3, value = -1 } } }
pad.rawAxes[3], pad.rawAxes[6] = -1, 1
assert(Device.Held() == nil, "rest -1 isn't held, and raw 5 isn't a trigger on this pad")
pad.rawAxes[3] = 0.9
assert(Device.Held() == "RTrigger")
pad.rawAxes[3], pad.rawAxes[4] = -1, -1
assert(Device.Held() == "DpadUp")
current.detect = nil

io.stdout:write("remap_spec: all checks passed\n")
