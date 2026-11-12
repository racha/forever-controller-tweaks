-- Forever Controller Tweaks remap: writes the layout as a per-device controller config (C_GamePad.SetConfig + ApplyConfigs),
-- the only remap path proven in game, and applies native while a window, the chat box or our panel holds the pad,
-- or while the Gamepad UI option is off.
-- apply() is the only writer: a 0.1 s ticker runs it while there is something to follow, and Remap.ApplyNow runs it
-- synchronously (PLAYER_REGEN_DISABLED, before the lockdown). The ticker stops when nothing can change.
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
-- A failed write is retried on the next tick; its chat line is shown once until a write works again.
local failed, failTold
-- GAME_PAD_CONFIGS_CHANGED raised by our own write isn't another addon's change.
local writing

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

-- ApplyConfigs and DeleteConfig are restricted: callers run out of combat only. Returns true when both calls worked.
local function write(what, id, fn, arg)
	writing = true
	local ok, err = pcall(fn, arg)
	local applyOk, applyErr = pcall(C_GamePad.ApplyConfigs)
	writing = false
	ns.debug("%s %s: write %s, ApplyConfigs %s", what, keyOf(id), ok and "ok" or tostring(err), applyOk and "ok" or tostring(applyErr))
	if ok and applyOk then
		failTold = nil
		return true
	end

	failed = true
	if not failTold then ns.log("controller config " .. what .. " failed: " .. tostring(err or applyErr)) end
	failTold = true
	return false
end

-- Puts back what was there before us: a foreign config we snapshotted, else nothing. Configs without our tag are
-- never touched. A snapshot is dropped instead of written back when our config is gone: either no config is left,
-- or the other addon rewrote its own while ours was applied, and that newer one stays.
local function writeNative(id)
	local key = keyOf(id)
	local entry, now = ns.db.devices[key], getConfig(id)
	written[key] = nil
	if entry and entry.foreign and not Layout.IsOurs(now) then
		ns.debug("foreign config snapshot for %s dropped: %s", key, now and "the other addon rewrote its config" or "no config is left")
		entry.foreign = nil
		return
	end
	if entry and entry.foreign then
		if write("restore", id, C_GamePad.SetConfig, entry.foreign) then entry.foreign = nil end
		return
	end
	if not Layout.IsOurs(now) then return end

	-- The snapshot is saved only at logout; after a crash the other addon's part is rebuilt from the merged config.
	local rest = Layout.Unmerge(now)
	if rest then return write("restore", id, C_GamePad.SetConfig, rest) end
	write("native", id, C_GamePad.DeleteConfig, id)
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
	if write("ours", config.configID, C_GamePad.SetConfig, merged) then written[key] = text end
end

-- A crash, a disabled addon or a logout in combat can leave our config saved; the first apply after login removes
-- it before anything else.
local function clearLeftovers()
	local dirty = ns.db.dirtyConfig
	ns.db.dirtyConfig = nil
	local ok, ids = pcall(C_GamePad.GetAllConfigIDs)
	for _, id in ipairs(ok and ids or {}) do
		if Layout.IsOurs(getConfig(id)) then
			local entry = ns.db.devices[keyOf(id)]
			if not dirty and not (entry and (next(entry.roles) or entry.detect)) then ns.log("removed a leftover controller config of ours for " .. keyOf(id) .. " (no layout set)") end
			writeNative(id)
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

-- Returns false when a write was needed but can't run now: the lockdown, or an input held on the pad. A switch under a
-- held button or trigger leaves its binding pressed (the release comes under the other mapping), so the ticker waits
-- for the release. Combat start (force) switches anyway: the fight must run on our mapping.
local function apply(force)
	local swap = ns.Device.SwapTargets()
	if swap ~= lastSwap then lastSwap, stale = swap, true end
	resolve()

	local want = wanted(force)
	if want == applied and not pending and not cleanup then return true end
	if InCombatLockdown() then
		if not combatNoted then ns.debug("combat: %s waits for the end of combat", want) end
		combatNoted = true
		return false
	end
	local held = ns.Device.Held()
	if held and not force then
		if heldNoted ~= held then ns.debug("remap: %s waits until %s is released", want, held) end
		heldNoted = held
		return false
	end
	if held then ns.debug("combat start: %s applied with %s held", want, held) end

	combatNoted, heldNoted, pending, failed = false, nil, false, false
	if cleanup then
		cleanup = false
		clearLeftovers()
	end
	if want ~= "native" then
		local config = want == "ours" and target or base
		if appliedID and not sameID(appliedID, config.configID) then writeNative(appliedID) end
		writeOurs(targetDevice, config)
		setApplied(want, config.configID, want == "ours" and targetOutputs or nil)
		pending = failed
		return true
	end
	if appliedID then writeNative(appliedID) end
	-- appliedID is kept while a restore failed, so the retry knows which config to put back.
	setApplied("native", failed and appliedID or nil)
	pending = failed
	return true
end

local function idle() return applied == "native" and not pending and not stale and not cleanup and not (ns.Active() and (target or base)) end

local function tick()
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

local function changed()
	stale = true
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
ns.On("FCT_LAYOUT_CHANGED", function(reason)
	if reason ~= "remap" then changed() end
end)

-- Leaves a clean GamePadConfig_Addons.json, so a disabled addon or a crash before next login is native. In combat the
-- write is forbidden: the next login's clean-up restores it and says so.
ns.On("PLAYER_LOGOUT", function()
	if not appliedID then return end
	if InCombatLockdown() then
		ns.db.dirtyConfig = keyOf(appliedID)
		return
	end
	writeNative(appliedID)
end)

ns.On("GAME_PAD_CONFIGS_CHANGED", function()
	if writing or applied == "native" or not appliedID or Layout.IsOurs(getConfig(appliedID)) then return end
	ns.debug("another addon replaced our controller config for %s", keyOf(appliedID))
	written[keyOf(appliedID)] = nil
	changed()
end)

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

	local layout = Layout.PresetName(ns.db.devices[device.key].roles)
	local extras = (device.hasPaddles and ", paddles" or "") .. (ns.Device.SwapTargets() and ", swap targets on" or "")
	ns.log(string.format("%s %s (%s%s): layout %s, remap %s", tostring(device.name), device.key, device.family, extras, layout, Remap.State()))
	ns.log("roles " .. table.concat(roleParts, " ") .. " | face " .. table.concat(faceParts, " "))
end

function ns.commands.preset(args) report(Layout.SetPreset((args[1] or ""):lower())) end
function ns.commands.role(args) report(Layout.SetRole((args[1] or ""):upper(), (args[2] or ""):lower())) end
function ns.commands.face(args) report(Layout.SetFace((args[1] or ""):lower(), (args[2] or ""):lower())) end
function ns.commands.reset() report(Layout.Reset()) end
