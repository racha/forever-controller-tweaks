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
local writes, applies = W.calls.set, W.calls.apply
for _ = 1, 3 do
	W.fire("PLAYER_ENTERING_WORLD")
	W.run(0.5)
end
assert(W.calls.set == writes and W.calls.apply == applies, "identical config: no SetConfig, no ApplyConfigs")
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

-- A failed restore keeps the snapshot, skips ApplyConfigs, names the call, and is retried after 1 s, 5 s, then 30 s.
local setConfig = C_GamePad.SetConfig
local tries = 0
C_GamePad.SetConfig = function() tries = tries + 1 error("refused") end
local applies4 = W4.calls.apply
W4.padFree = false
W4.run()
assert(entry.foreign and W4.said("restore failed %(SetConfig%): .*refused") and tries == 1, "snapshot kept when the restore fails")
assert(W4.calls.apply == applies4, "no ApplyConfigs after a failed SetConfig")
-- The failure came on the first frame of that run (0.2 s), so the retries fall at about 1, 6 and 36 s from it.
W4.run(0.6)
assert(tries == 1, "no retry every tick")
W4.run(0.3)
assert(tries == 2, "retried after 1 s")
W4.run(4.7)
assert(tries == 2)
W4.run(0.4)
assert(tries == 3, "then after 5 s")
W4.run(29.6)
assert(tries == 3)
W4.run(0.4)
assert(tries == 4 and W4.count("restore failed") == 1, "then every 30 s, the chat line shown once")
C_GamePad.SetConfig = setConfig
W4.run(30)
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

-- A held ring (design/rings.md, the stick keys): its GamePadStickAxisButtons write and restore change the controller
-- config, our config reading as not ours. While held and for the settle after, nothing is written (an ApplyConfigs
-- mid-aim drops the stick keys' state) and the change isn't taken for another addon's; once settled it is checked once.
local W9 = new()
local R9, configs9 = W9.ns.Remap, W9.configs
W9.login()
W9.ns.db.options.debug = true
assert(W9.ns.Layout.SetPreset("split"))
W9.run()
assert(ours(configs9[DS]))
local function replaced() local n = 0 for _, line in ipairs(W9.ns.db.debugLog) do if line:find("another addon replaced", 1, true) then n = n + 1 end end return n end
-- The flip as the user's log shows it: the config reads as not ours when the event comes, then is ours again.
local function flip()
	local saved = configs9[DS]
	configs9[DS] = nil
	W9.fire("GAME_PAD_CONFIGS_CHANGED")
	configs9[DS] = saved
end
local sets, applies = W9.calls.set, W9.calls.apply
R9.Hold(true)
flip()
W9.run(1)
assert(W9.calls.set == sets and W9.calls.apply == applies and replaced() == 0, "ring open: the CVar's config change writes nothing and isn't another addon's")
assert(W9.ns.Layout.SetRole("L1", "hostile"))
W9.run(1)
assert(W9.calls.apply == applies, "ring open: a layout change waits too")
W9.fire("PLAYER_REGEN_DISABLED")
W9.combat = true
assert(W9.calls.apply == applies, "ring open at combat start: still no ApplyConfigs")
W9.combat = false
R9.Hold(false)
flip()
W9.run(0.3)
assert(W9.calls.apply == applies and replaced() == 0, "settling after the restore: the restore's change writes nothing")
W9.run(0.5)
assert(W9.calls.set == sets + 1 and W9.calls.apply == applies + 1 and ours(configs9[DS]) and replaced() == 0, "settled: the waiting layout change written once; the flips were ours all along")
-- The config really lost in the flip: re-applied once, after the settle.
sets, applies = W9.calls.set, W9.calls.apply
R9.Hold(true)
configs9[DS] = nil
W9.fire("GAME_PAD_CONFIGS_CHANGED")
W9.run(1)
assert(W9.calls.apply == applies, "lost while held: not re-applied mid-aim")
R9.Hold(false)
W9.run(1)
assert(W9.calls.set == sets + 1 and W9.calls.apply == applies + 1 and ours(configs9[DS]) and replaced() == 1, "lost while held: re-applied once, after the settle")
-- Opened again inside the settle: the first settle's check doesn't run under the second ring.
sets = W9.calls.set
R9.Hold(true)
R9.Hold(false)
W9.run(0.2)
R9.Hold(true)
configs9[DS] = nil
W9.fire("GAME_PAD_CONFIGS_CHANGED")
W9.run(1)
assert(W9.calls.set == sets, "reopened in the settle: still held")
R9.Hold(false)
W9.run(1)
assert(W9.calls.set == sets + 1 and ours(configs9[DS]), "reopened in the settle: re-applied after the last one")
-- Without a ring the same change is another addon's, as before.
configs9[DS] = nil
W9.fire("GAME_PAD_CONFIGS_CHANGED")
W9.run()
assert(ours(configs9[DS]) and replaced() == 3, "no ring: a lost config is re-applied at once")

-- A failed ApplyConfigs: named, and the write is tried again (not taken as written).
local W10 = new()
W10.login()
local asleep10 = W10.liveTickers()
assert(W10.ns.Layout.SetPreset("split"))
local applyConfigs = C_GamePad.ApplyConfigs
C_GamePad.ApplyConfigs = function() error("busy") end
W10.run()
assert(W10.said("ours failed %(ApplyConfigs%): .*busy"))
C_GamePad.ApplyConfigs = applyConfigs
local sets10 = W10.calls.set
W10.run(1.2)
assert(W10.calls.set == sets10 + 1 and ours(W10.configs[DS]), "written again once ApplyConfigs works")
-- Applied and nothing waiting: the ticker stops, and the panel message wakes it.
W10.run()
assert(W10.liveTickers() == asleep10, "ours applied: the remap ticker stopped")
W10.ns.SetPanelOpen(true)
assert(W10.liveTickers() == asleep10 + 1, "the panel opening wakes the remap")
W10.run()
assert(W10.configs[DS] == nil and W10.liveTickers() == asleep10, "native applied, asleep again")
W10.ns.SetPanelOpen(false)
W10.run()
assert(ours(W10.configs[DS]))
-- The swap-targets CVar wakes it too, and the new config is written.
local swapOn = false
GetCVarBool = function(name) return name == "GamepadSwapTargetModifiers" and swapOn end
sets10 = W10.calls.set
swapOn = true
W10.fire("CVAR_UPDATE", "GAMEPADSWAPTARGETMODIFIERS")
W10.run()
assert(W10.calls.set == sets10 + 1 and W10.liveTickers() == asleep10, "the CVar change written, then asleep")
GetCVarBool = function() return false end

-- A pad switch whose restore of the old pad fails: the old ID is kept and put back once it works.
local XB = "045e/0b13"
local W11 = new({ pads = {} })
W11.pads[1] = W11.newPad("DualSense", 0x054c, 0x0ce6)
W11.login()
assert(W11.ns.Layout.SetPreset("split"))
W11.run()
assert(ours(W11.configs[DS]))
local set11, delete11 = C_GamePad.SetConfig, C_GamePad.DeleteConfig
C_GamePad.DeleteConfig = function() error("refused") end
W11.pads[1] = W11.newPad("Xbox", 0x045e, 0x0b13)
W11.fire("GAME_PAD_CONNECTED")
assert(W11.ns.Layout.SetPreset("split"))
W11.run()
assert(ours(W11.configs[XB]) and ours(W11.configs[DS]), "the new pad has ours; the old one's restore failed")
assert(W11.said("new controller Xbox %(045e/0b13, xbox%)$") and not W11.said("/fct learn"), "a known vendor's pad isn't sent to /fct learn")
C_GamePad.DeleteConfig = delete11
W11.run(1.2)
assert(W11.configs[DS] == nil and ours(W11.configs[XB]), "the old pad's config put back on the retry")
-- The same at logout: a restore still waiting is written then too.
C_GamePad.DeleteConfig = function() error("refused") end
W11.pads[1] = W11.newPad("DualSense", 0x054c, 0x0ce6)
W11.fire("GAME_PAD_CONNECTED")
W11.run()
assert(ours(W11.configs[DS]) and ours(W11.configs[XB]))
C_GamePad.DeleteConfig = delete11
W11.fire("PLAYER_LOGOUT")
assert(W11.configs[DS] == nil and W11.configs[XB] == nil, "logout restores the waiting one and the applied one")
C_GamePad.SetConfig = set11

-- A 0-based config ID list (GetAllConfigIDs): the leftover at [0] is found too.
local W12 = new({ configs = { [DS] = { comment = TAG, configID = { vendorID = 0x054c, productID = 0x0ce6 }, rawButtonMappings = {} } } })
local allIDs = C_GamePad.GetAllConfigIDs
C_GamePad.GetAllConfigIDs = function() return { [0] = { vendorID = 0x054c, productID = 0x0ce6 } } end
W12.login()
assert(W12.configs[DS] == nil and W12.said("removed a leftover"), "config [0] cleared")
C_GamePad.GetAllConfigIDs = allIDs

-- Stick keys: with GamePadStickAxisButtons on (a held ring), a stick past half way holds the switch, logged once.
local W13 = new()
local pad13, Device13 = W13.pads[1], W13.ns.Device
W13.login()
W13.ns.db.options.debug = true
assert(W13.ns.Layout.SetPreset("split"))
W13.run()
pad13.rawAxes[3] = 0.8
assert(Device13.Held() == nil, "stick keys off: a stick is never held")
GetCVarBool = function(name) return name == "GamePadStickAxisButtons" end
assert(Device13.Held() == "RStickX", "raw axis 2 (1-based [3]) is the right stick's X")
pad13.rawAxes[3] = -0.4
assert(Device13.Held() == nil, "under half way")
pad13.rawAxes[2] = -0.9
W13.ns.SetPanelOpen(true)
W13.run(1)
local waits = 0
for _, line in ipairs(W13.ns.db.debugLog) do if line:find("waits until LStickY", 1, true) then waits = waits + 1 end end
assert(ours(W13.configs[DS]) and waits == 1, "the switch waits for the stick, logged once")
pad13.rawAxes[2] = 0
W13.run()
assert(W13.configs[DS] == nil, "released: native")
local current13 = Device13.Current()
current13.detect = { axes = { LStickX = { raw = 7, shift = -0.5, scale = 2 } } }
pad13.rawAxes[8] = 0.6
assert(Device13.Held() == nil, "a detected stick is scaled: (0.6 - 0.5) * 2 = 0.2")
pad13.rawAxes[8] = 0.9
assert(Device13.Held() == "LStickX")
current13.detect, pad13.rawAxes[8] = nil, 0
GetCVarBool = function() return false end

-- A ring that never says it closed: its stillOpen check releases the hold, with one chat line.
local W14 = new()
local R14 = W14.ns.Remap
W14.login()
assert(W14.ns.Layout.SetPreset("split"))
W14.run()
local open14 = true
R14.Hold(true, function() return open14 end)
W14.ns.SetPanelOpen(true)
W14.run(1)
assert(ours(W14.configs[DS]), "held: the switch waits")
open14 = false
W14.run(1)
assert(W14.configs[DS] == nil and W14.count("a ring left the controller config held") == 1, "stillOpen false: released, then applied")
R14.Hold(true, function() error("ring broke") end)
W14.ns.SetPanelOpen(false)
W14.run(1)
assert(ours(W14.configs[DS]) and W14.count("a ring left the controller config held") == 1, "an erroring check releases it too, told once")
R14.Hold(true)
R14.Hold(false)
W14.run(1)
assert(ours(W14.configs[DS]), "without stillOpen the API is as before")

-- With the binding stack hooked (hooksecurefunc), FCT_PAD_FREE comes a frame after a stack change and the poll
-- runs at 1 s, not 0.1 s. The stub runs every ticker each frame, so the interval is read from the ticker.
local hooks = {}
function hooksecurefunc(t, key, fn)
	local orig = t[key]
	hooks[#hooks + 1] = key
	t[key] = function(...)
		local a, b = orig(...)
		fn(...)
		return a, b
	end
end
local intervals = {}
local newTicker = C_Timer.NewTicker
local W15 = new()
C_Timer.NewTicker = function(interval, fn)
	intervals[#intervals + 1] = interval
	return newTicker(interval, fn)
end
local manager = GamepadSharedUtility.InputBindingManager
local stack = 0
manager.IsOnlyCoreBindingSetActive = function() return stack == 0 end
function manager:AddBindingSet() stack = stack + 1 end
function manager:RemoveSet() stack = stack - 1 end
function manager:ClearBindings() stack = 0 end
function manager:AssumeCoreBindingsAreUsable() end
local frees = {}
W15.ns.On("FCT_PAD_FREE", function(free) frees[#frees + 1] = free end)
W15.login()
local slowPoll = false
for _, interval in ipairs(intervals) do slowPoll = slowPoll or interval == 1 end
assert(#hooks == 4 and slowPoll, "four methods hooked, the safety-net poll at 1 s")
local seen = #frees
manager:AddBindingSet()
assert(#frees == seen, "checked a frame later, not inside Blizzard's call")
for _, t in ipairs(W15.timers) do t.at = W15.now end
local due = W15.timers
W15.timers = {}
for _, t in ipairs(due) do t.fn() end
assert(frees[#frees] == false and #frees == seen + 1, "the window's push seen")
C_Timer.NewTicker = newTicker
hooksecurefunc = nil

io.stdout:write("remap_spec: all checks passed\n")
