-- Stubbed checks of Core: the pad-free queue, FCT_PAD_FREE, ns.OnBlocked, plain /fct and selftest.
-- lua tests/queue_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local W = dofile(here .. "/wow.lua")(here .. "/..")
local ns = W.ns
W.login()

local ran = {}
local function job(name) return function() ran[#ran + 1] = name end end

-- Jobs are keyed by name: different names all run, in order; the same name replaces the queued one.
W.padFree = false
ns.whenPadFree("a", job("a1"))
ns.whenPadFree("b", job("b"))
ns.whenPadFree("a", job("a2"))
W.run(1)
assert(#ran == 0)
W.padFree = true
W.run()
assert(ran[1] == "a2" and ran[2] == "b" and #ran == 2, "a replaced in its place, b kept")

-- No timeout by default: an internal job waits a whole minute for the pad.
ran = {}
W.padFree = false
ns.whenPadFree("face router", job("face"))
W.run(60)
W.padFree = true
W.run()
assert(ran[1] == "face")

-- A user job with a timeout gives up after 15 s of a busy pad, and says so.
ran = {}
W.padFree = false
ns.whenPadFree("learn", job("learn"), { timeout = 15 })
W.run(16)
W.padFree = true
W.run()
assert(#ran == 0 and W.said("learn: gave up"))

-- Combat pauses everything that isn't combatOk, and doesn't count towards the timeout.
ran = {}
W.combat = true
ns.whenPadFree("bind", job("bind"), { timeout = 15 })
ns.whenPadFree("read", job("read"), true)
W.run()
assert(ran[1] == "read" and #ran == 1 and W.said("bind: waits for combat to end"))
W.run(30)
W.combat = false
W.run()
assert(ran[2] == "bind", "the 30 s fight didn't time it out")

-- A job may queue another one from inside.
ran = {}
ns.whenPadFree("outer", function()
	ran[#ran + 1] = "outer"
	ns.whenPadFree("inner", job("inner"))
end)
W.run()
assert(ran[1] == "outer" and ran[2] == "inner")

-- FCT_PAD_FREE: on every change, and at every PLAYER_ENTERING_WORLD.
local free = {}
ns.On("FCT_PAD_FREE", function(value) free[#free + 1] = value end)
W.padFree = false
W.run()
W.padFree = true
W.run()
assert(free[1] == false and free[2] == true and #free == 2)
W.fire("PLAYER_ENTERING_WORLD")
assert(free[3] == true)

-- ns.OnBlocked: one chat line per session for us, debug lines for everything.
ns.db.options.debug = true
W.fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpell")
assert(not W.said("Blizzard blocked"))
W.fire("ADDON_ACTION_BLOCKED", "ForeverControllerTweaks", "SetBinding")
W.fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "ClearOverrideBindings")
assert(W.count("Blizzard blocked SetBinding — please /reload and report") == 1 and not W.said("Blizzard blocked Clear"))
local logged = 0
for _, line in ipairs(ns.db.debugLog) do
	if line:find("ADDON_ACTION_") then logged = logged + 1 end
end
assert(logged == 3)

-- Plain /fct only toggles the panel; status stays on /fct status.
local toggled, lines = 0, #W.lines
ns.TogglePanel = function() toggled = toggled + 1 end
W.slash("")
assert(toggled == 1 and #W.lines == lines, "no status print")
W.slash("status")
assert(#W.lines > lines)

-- selftest turns debug on and reports the environment.
ns.db.options.debug = false
W.slash("selftest")
assert(ns.db.options.debug and W.said("selftest: build 1.60.1.12345, interface 16001, Gamepad UI on"))
assert(W.said("vendor 054c, product 0ce6, labelStyle Shapes, family playstation, confirmed true"))
assert(W.said("raw tables 1%-based") and W.said("storage slot 145") and W.said("3 account, 1 character"))
assert(W.said("remap off, face n/a, glyphs n/a") and W.said("taintLog 2"))

-- A listener's error doesn't stop the others; combat start still applies the remap. One chat line per listener.
local after = 0
ns.On("FCT_COMBAT_START", function() error("boom") end)
ns.On("FCT_COMBAT_START", function() after = after + 1 end)
local applied = 0
local applyNow = ns.Remap.ApplyNow
ns.Remap.ApplyNow = function(reason) applied = applied + 1 return applyNow(reason) end
W.fire("PLAYER_REGEN_DISABLED")
W.fire("PLAYER_REGEN_DISABLED")
assert(after == 2 and applied == 2, "later listeners and the remap still ran")
assert(W.count("an error in FCT_COMBAT_START was skipped") == 1 and W.said("boom"))
ns.Remap.ApplyNow = applyNow

-- Waiting jobs don't allocate a table per tick: the queue walks its order in place.
W.padFree = false
-- Measured against the same number of idle ticks, so the test harness's own per-tick garbage cancels out.
local function growth(ticks)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	W.run(ticks)
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	return grew
end
local idle = growth(30)
ns.whenPadFree("w1", job("w1"))
ns.whenPadFree("w2", job("w2"))
local waiting = growth(30)
W.padFree = true
W.run()
assert(waiting - idle < 2, "about 0 KB more than idle while waiting, was " .. (waiting - idle))

io.stdout:write("queue_spec: all checks passed\n")
