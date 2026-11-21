-- Forever Controller Tweaks remap: writes the layout as a per-device controller config (C_GamePad.SetConfig + ApplyConfigs),
-- the only remap path proven in game, and applies native while a window, the chat box or our panel holds the pad,
-- or while the Gamepad UI option is off.
-- apply() is the only writer: a 0.1 s ticker runs it while a switch waits or a ring holds the remap, and Remap.ApplyNow
-- runs it synchronously (PLAYER_REGEN_DISABLED, before the lockdown). Once what is wanted is applied the ticker stops;
-- the messages and events that can change what is wanted wake it.
local _, ns = ...
local Remap = {}
ns.Remap = Remap

local Layout = ns.Layout
local TICK = 0.1
local applied, appliedID, appliedOutputs
local target, targetDevice, targetOutputs, base
local stale, pending, cleanup, combatNoted, heldNoted, lastSwap, ticker, started
-- Per device key: what we last wrote (to skip identical writes), and whether the foreign-config line was shown.
local written, foreignTold = {}, {}
-- A failed write is retried after 1 s, 5 s, then every 30 s; its chat line is shown once until a write works again.
local BACKOFF = { 1, 5, 30 }
local failed, failTold, failures, retryAt = false, nil, 0, nil
-- Device key -> config ID that still needs native put back: a pad switch or a native apply whose restore failed.
local restoring = {}
-- GAME_PAD_CONFIGS_CHANGED raised by our own write isn't another addon's change.
local writing
-- A held ring (Rings.lua) holds the remap while it is open: it switches GamePadStickAxisButtons, and the game answers
-- that (and its restore) with GAME_PAD_CONFIGS_CHANGED, our config reading as not ours. Re-applying then ran
-- ApplyConfigs mid-aim, which drops the pad's key state: a stick key down got no up, and diagonals (two keys) stuck.
-- So while held, and SETTLE seconds after, nothing is written and a config change isn't taken for another addon's;
-- once settled it is checked once, and re-applied only if it still isn't ours.
local SETTLE = 0.5
local holding, settling, missed, holdNoted, holdGen = false, false, false, false, 0
-- The open ring's stillOpen, asked every tick while held; holdTold: its failsafe line was shown this session.
local holdCheck, holdTold

local function getConfig(id)
	local ok, config = pcall(C_GamePad.GetConfig, id)
	return ok and config or nil
end

local function keyOf(id) return Layout.Key(id.vendorID, id.productID) end
local function sameID(a, b) return a.vendorID == b.vendorID and a.productID == b.productID end

local function serialize(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys, parts = {}, {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. serialize(value[key]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- method: "SetConfig" or "DeleteConfig". ApplyConfigs and DeleteConfig are restricted: callers run out of combat
-- only. ApplyConfigs runs only after the write worked. Returns true, or false and the call that failed.
local function write(what, id, method, arg)
	writing = true
	local ok, err = pcall(C_GamePad[method], arg)
	local applyOk, applyErr = false, nil
	if ok then applyOk, applyErr = pcall(C_GamePad.ApplyConfigs) end
	writing = false
	ns.debug("%s %s: %s %s, ApplyConfigs %s", what, keyOf(id), method, ok and "ok" or tostring(err), ok and (applyOk and "ok" or tostring(applyErr)) or "skipped")
	if applyOk then
		failTold = nil
		return true
	end

	local call = ok and "ApplyConfigs" or method
	failed = true
	if not failTold then ns.log(("controller config %s failed (%s): %s"):format(what, call, tostring(ok and applyErr or err))) end
	failTold = true
	return false, call
end

-- Puts back what was there before us: a foreign config we snapshotted, else nothing. Configs without our tag are
-- never touched. A snapshot is dropped instead of written back when our config is gone: either no config is left,
-- or the other addon rewrote its own while ours was applied, and that newer one stays. Returns true unless a write
-- failed.
local function writeNative(id)
	local key = keyOf(id)
	local entry, now = ns.db.devices[key], getConfig(id)
	written[key] = nil
	if entry and entry.foreign and not Layout.IsOurs(now) then
		ns.debug("foreign config snapshot for %s dropped: %s", key, now and "the other addon rewrote its config" or "no config is left")
		entry.foreign = nil
		return true
	end
	if entry and entry.foreign then
		local ok = write("restore", id, "SetConfig", entry.foreign)
		if ok then entry.foreign = nil end
		return ok
	end
	if not Layout.IsOurs(now) then return true end

	-- The snapshot is saved only at logout; after a crash the other addon's part is rebuilt from the merged config.
	local rest = Layout.Unmerge(now)
	if rest then return (write("restore", id, "SetConfig", rest)) end
	return (write("native", id, "DeleteConfig", id))
end

local function writeOurs(device, config)
	local key, entry = device.key, ns.db.devices[device.key]
	local existing = getConfig(config.configID)
	if existing and not Layout.IsOurs(existing) then
		entry.foreign, written[key] = Layout.Copy(existing), nil
		if not foreignTold[key] then ns.log("another controller config exists for " .. key .. "; Controller Tweaks builds on it and restores it for native") end
		foreignTold[key] = true
	elseif not existing and entry.foreign then
		ns.debug("foreign config snapshot for %s dropped: no config is left", key)
		entry.foreign = nil
	end

	local merged = Layout.Merge(entry.foreign, config, true)
	local text = serialize(merged)
	if written[key] == text and Layout.IsOurs(existing) then return ns.debug("ours %s: unchanged, not written", key) end
	if write("ours", config.configID, "SetConfig", merged) then written[key] = text end
end

-- A crash, a disabled addon or a logout in combat can leave our config saved; the first apply after login removes
-- it before anything else.
local function clearLeftovers()
	local dirty = ns.db.dirtyConfig
	ns.db.dirtyConfig = nil
	for _, id in ipairs(ns.Device.Listed(C_GamePad.GetAllConfigIDs)) do
		if Layout.IsOurs(getConfig(id)) then
			local key = keyOf(id)
			local entry, profile = ns.db.devices[key], ns.Profile and ns.Profile.Get(ns.Profile.IdFor(key))
			if not dirty and not (entry and (next(profile and profile.roles or {}) or entry.detect)) then ns.log("removed a leftover controller config of ours for " .. key .. " (no layout set)") end
			if not writeNative(id) then restoring[key] = id end
		end
	end
	if dirty then ns.log("the last session ended in combat, so the controller config was restored now (" .. dirty .. ")") end
end

local function resolve()
	if not stale then return end

	local device, roles, swap = ns.Device.Current(), Layout.Roles(), ns.Device.SwapTargets()
	target, targetDevice = device and Layout.BuildConfig(device, roles, swap), device
	targetOutputs = target and Layout.Outputs(device.raw, roles, swap)
	-- A detected pad keeps its detected mapping (without the roles) while a window or the panel holds the pad.
	base = device and device.detect and Layout.BuildConfig(device, {}, swap)
	stale, pending = false, true
end

local function setApplied(state, id, outputs)
	local changed = state ~= applied
	applied, appliedID, appliedOutputs = state, id, outputs
	if changed then ns.Fire("FCT_LAYOUT_CHANGED", "remap", Remap.State()) end
end

-- Detection reads the pad raw, with the game's own mapping and nothing of ours in the way. force (combat start)
-- applies ours as if no window or panel held the pad, since the fight would otherwise run on native.
local function wanted(force)
	local onPad = ns.Active() and not ns.Device.Detecting()
	if onPad and target and (force or ns.padFree() and not ns.panelOpen) then return "ours" end
	if onPad and base then return "base" end
	return "native"
end

-- Returns false when a write was needed but can't run now: the lockdown, a failed write's backoff, or an input held on
-- the pad. A switch under a held button, trigger or stick key leaves its binding pressed (the release comes under the
-- other mapping), so the ticker waits for the release. Combat start (force) switches anyway: the fight must run on our
-- mapping.
local function apply(force)
	local swap = ns.Device.SwapTargets()
	if swap ~= lastSwap then lastSwap, stale = swap, true end
	resolve()

	local want = wanted(force)
	if want == applied and not pending and not cleanup and not next(restoring) then return true end
	-- Combat start too: a write under an aiming ring breaks it, so the fight starts on what is applied.
	if holding or settling then
		if not holdNoted then ns.debug("remap: %s waits until the ring closes", want) end
		holdNoted = true
		return false
	end
	if InCombatLockdown() then
		if not combatNoted then ns.debug("combat: %s waits for the end of combat", want) end
		combatNoted = true
		return false
	end
	if retryAt and not force and GetTime() < retryAt then return false end
	local held = ns.Device.Held()
	if held and not force then
		if not heldNoted then ns.debug("remap: %s waits until %s is released", want, held) end
		heldNoted = held
		return false
	end
	if held then ns.debug("combat start: %s applied with %s held", want, held) end

	combatNoted, heldNoted, holdNoted, pending, failed = false, nil, false, false, false
	if cleanup then
		cleanup = false
		clearLeftovers()
	end
	local config = want ~= "native" and (want == "ours" and target or base)
	if appliedID and not (config and sameID(appliedID, config.configID)) then restoring[keyOf(appliedID)] = appliedID end
	if config then restoring[keyOf(config.configID)] = nil end
	for key, id in pairs(restoring) do
		if writeNative(id) then restoring[key] = nil end
	end
	if config then
		writeOurs(targetDevice, config)
		setApplied(want, config.configID, want == "ours" and targetOutputs or nil)
	else
		setApplied("native")
	end
	pending, failures = failed, failed and failures + 1 or 0
	retryAt = failed and GetTime() + BACKOFF[math.min(failures, #BACKOFF)] or nil
	if failed then ns.debug("remap: write failed, retried in %d s", BACKOFF[math.min(failures, #BACKOFF)]) end
	return true
end

local function idle() return not (stale or pending or cleanup or holding or settling or next(restoring)) and wanted(false) == applied end

-- A ring that never says it closed (an error in Rings) must not keep the remap frozen for the session.
local function checkHold()
	local ok, open = pcall(holdCheck)
	if ok and open then return end

	ns.debug("remap: the ring hold was released, %s", ok and "the ring reports it closed" or "its check failed: " .. tostring(open))
	if not holdTold then ns.log("a ring left the controller config held; it was released (/fct ringlog shows the ring's last events)") end
	holdTold = true
	Remap.Hold(false)
end

local function tick()
	if holding and holdCheck then checkHold() end
	apply(false)
	if not (ticker and idle()) then return end

	ticker:Cancel()
	ticker = nil
end

local function wake()
	if started and not ticker then ticker = C_Timer.NewTicker(TICK, tick) end
end

function Remap.ApplyNow(reason)
	if not started then return false end

	local ok = apply(reason == "combat")
	ns.debug("remap apply now (%s): %s", tostring(reason), ok and Remap.State() or "not now (lockdown or a held input)")
	wake()
	return ok
end

-- "ours": our config is applied; "native": a layout is set, native (or only a detected pad's base mapping) is applied
-- now; "off": native layout or no pad; "needsSetup": the pad must be learned or detected before the addon writes.
function Remap.State()
	resolve()
	if ns.Device.NeedsSetup() then return "needsSetup" end
	if not target then return "off" end
	return applied == "ours" and "ours" or "native"
end

-- Physical button -> native key it outputs while our config is applied, else nil.
function Remap.Outputs() return applied == "ours" and appliedOutputs or nil end

-- A layout change is tried at once, even inside a failed write's backoff.
local function changed()
	stale, retryAt = true, nil
	wake()
end

ns.On("PLAYER_ENTERING_WORLD", function()
	ns.Device.Refresh()
	stale = true
	if not started then started, cleanup = true, true end
	wake()
	tick()
end)

ns.On("FCT_ACTIVE_CHANGED", changed)
ns.On("FCT_PAD_FREE", wake)
ns.On("FCT_PANEL_OPEN", wake)
ns.On("FCT_DETECTING", wake)
ns.On("FCT_LAYOUT_CHANGED", function(reason)
	if reason ~= "remap" then changed() end
end)
ns.On("CVAR_UPDATE", function(name)
	if type(name) == "string" and name:lower() == "gamepadswaptargetmodifiers" then wake() end
end)

-- Leaves a clean GamePadConfig_Addons.json, so a disabled addon or a crash before next login is native. In combat the
-- write is forbidden: the next login's clean-up restores it and says so.
ns.On("PLAYER_LOGOUT", function()
	if appliedID then restoring[keyOf(appliedID)] = appliedID end
	local key = next(restoring)
	if not key then return end
	if InCombatLockdown() then
		ns.db.dirtyConfig = key
		return
	end
	for _, id in pairs(restoring) do writeNative(id) end
end)

local function checkForeign()
	if writing or applied == "native" or not appliedID or Layout.IsOurs(getConfig(appliedID)) then return end
	ns.debug("another addon replaced our controller config for %s", keyOf(appliedID))
	written[keyOf(appliedID)] = nil
	changed()
end

ns.On("GAME_PAD_CONFIGS_CHANGED", function()
	if not (holding or settling) then return checkForeign() end
	missed = true
	local now = appliedID and getConfig(appliedID)
	ns.debug("remap: configs changed while a ring holds the remap (%s), checked once it settles", now and "comment " .. tostring(now.comment) or "no config")
end)

-- on: a held ring opens (before its CVar write); off: it closed and its CVar is back (after the write).
-- stillOpen (optional): asked every tick while held; false or an error releases the hold and logs it.
function Remap.Hold(on, stillOpen)
	on = not not on
	holdCheck = on and stillOpen or nil
	if on == holding then return end
	holding, holdGen = on, holdGen + 1
	if on then
		settling = false
		wake()
		return ns.debug("remap: held by a ring")
	end
	settling = true
	local gen = holdGen
	C_Timer.After(SETTLE, function()
		if gen ~= holdGen then return end
		settling = false
		ns.debug("remap: ring settled%s", missed and ", configs checked" or "")
		if missed then
			missed = false
			checkForeign()
		end
		wake()
	end)
end

local function report(ok, err)
	if not ok then return ns.log(err) end
	ns.commands.status()
end

function ns.commands.status()
	if not ns.Active() then ns.log("Gamepad UI off — Controller Tweaks is inactive (Options > Gamepad (Beta) > Enable Gamepad UI)") end

	local device = ns.Device.Current() or ns.Device.Refresh()
	if not device then return ns.log("no controller found; remap " .. Remap.State()) end
	if ns.Device.NeedsSetup() then ns.log("this controller isn't recognised yet: /fct family playstation|xbox|switch, or /fct detect, sets it up") end

	local roles, face, roleParts, faceParts = Layout.Roles(), Layout.Face(), {}, {}
	for _, phys in ipairs(Layout.PHYSICAL) do
		if device.raw[phys] then roleParts[#roleParts + 1] = phys .. "=" .. (roles[phys] or "none") end
	end
	for _, pos in ipairs(Layout.FACE_POSITIONS) do faceParts[#faceParts + 1] = pos .. "=" .. face[pos] end

	local profile = ns.Profile and ns.Profile.Current()
	local layout = Layout.PresetName(profile and profile.roles)
	local extras = (device.hasPaddles and ", paddles" or "") .. (ns.Device.SwapTargets() and ", swap targets on" or "")
	ns.log(string.format("%s %s (%s%s): profile %s, layout %s, remap %s", tostring(device.name), device.key, device.family, extras, profile and profile.name or "none", layout, Remap.State()))
	ns.log("roles " .. table.concat(roleParts, " ") .. " | face " .. table.concat(faceParts, " "))
end

function ns.commands.preset(args) report(Layout.SetPreset((args[1] or ""):lower())) end
function ns.commands.role(args) report(Layout.SetRole((args[1] or ""):upper(), (args[2] or ""):lower())) end
function ns.commands.face(args) report(Layout.SetFace((args[1] or ""):lower(), (args[2] or ""):lower())) end
function ns.commands.reset() report(Layout.Reset()) end
