-- Forever Controller Tweaks core: namespace, SavedVariables, events and messages, the pad-free job queue, logging, /fct.
--
-- Core API for the other files (all on the addon namespace `ns`, also the global ForeverControllerTweaks, which the
-- Touch, Keyboard and Rings modules read as their `ns`: separate addons don't share the private one):
--   ns.db                          ForeverControllerTweaksDB, ready from ADDON_LOADED on (FCT_READY fires then).
--   ns.On(event, fn)               fn(...) on a WoW event, or on an internal message (any name starting FCT_).
--                                  FCT_READY registered once ns.db is ready runs fn at once (a module loads after it).
--   ns.Fire(msg, ...)              sends an internal message.
--   ns.whenPadFree(what, fn, opts)
--                                  runs fn once only the core gamepad binding set is active (no chat box or Blizzard
--                                  window holds the pad) and, unless opts.combatOk, out of combat (combat waits for its
--                                  end). Jobs are keyed by what: a new job replaces the queued one of the same name only.
--                                  They wait forever unless opts.timeout (seconds) is set; user commands use 15.
--                                  opts may also be a plain boolean, meaning combatOk.
--   ns.log(msg)                    one chat line.
--   ns.debug(fmt, ...)             appends to ns.db.debugLog (capped) when /fct debug on.
--   ns.padFree()                   true while only the core binding set is active (always true while inactive).
--   ns.OnBlocked(event, addon, func)
--                                  the one ADDON_ACTION_BLOCKED/FORBIDDEN reporter (Core registers both events): debug
--                                  log always, one chat line per session when addon is this one. Other files may call
--                                  it for their own caught errors.
--   ns.Active()                    true while the game's "Enable Gamepad UI (Beta)" option is on. The addon does nothing
--                                  else while it is off: native config, no face bindings, no glyphs, no learning.
--   ns.SetPanelOpen(open)          the settings screen reports open/closed; Remap applies native while it is open.
--   ns.TogglePanel()               no-op until the settings screen replaces it; the binding and plain /fct call it.
--   ns.commands[name] = fn(args)   adds a /fct subcommand.
--   ns.Device.Current()            { key = "054c/0ce6", family = "playstation"|"xbox"|"switch"|"generic", raw = <db raw>,
--                                  hasPaddles, vendorID, productID, name, deviceID, motionAxes, labelStyle, detect,
--                                  confirmed, familyPicked } or nil.
--   ns.Device.NeedsSetup()         true for a pad the addon can't trust yet (no known vendor, no learn, no detection):
--                                  no config is written for it, and Remap.State() is "needsSetup".
--   ns.Device.SetFamily(key, family) "playstation"|"xbox"|"switch" for an unrecognised pad (key nil = current): its SDL
--                                  raw order and labels, NeedsSetup cleared; true, or false and a reason ("custom" is
--                                  always false: run the detect wizard). ResetFamily(key) makes it unrecognised again.
--   ns.Device.SuggestedFamily(key) "xbox" for Steam's virtual gamepad (28de/11ff), else nil: the panel's preselection.
--   ns.Device.Learn(phys) / LearnCancel()  and the detection API (DetectStart/Skip/Back/Cancel/Finish/Reset).
--   ns.Layout.Roles() / Face()     effective roles { L1 = "rightmod", ... } and face { bottom = "jump", ... }.
--   ns.Layout.PhysicalFor(key)     native key and name of the physical button that now outputs key (for glyphs).
--   ns.Remap.State()               "ours" (our config applied), "native" (a layout is set but native is applied now),
--                                  "off" (native layout or no controller), "needsSetup" (see Device.NeedsSetup).
--   ns.Remap.ApplyNow(reason)      applies the wanted config synchronously; "combat" applies ours as if no window or
--                                  panel held the pad. Returns false when it can't write (lockdown).
-- Message FCT_LAYOUT_CHANGED(reason): "layout" (roles/face/raw edited), "device" (controller changed),
-- "remap" (applied state changed; second arg is Remap.State()).
-- Message FCT_ACTIVE_CHANGED(active): the Gamepad UI option changed; also fires once at the first
-- PLAYER_ENTERING_WORLD.
-- Message FCT_PAD_FREE(free): ns.padFree() changed (polled at 0.1 s); also fires at every PLAYER_ENTERING_WORLD.
-- CVAR_UPDATE(name) arrives as the game sends it, in any case: listeners compare name:lower().
-- A listener's error is caught: the other listeners still run, and it is reported once per session.
-- Message FCT_COMBAT_START: fired synchronously first thing in PLAYER_REGEN_DISABLED, before the lockdown
--                                  begins. Order inside that one handler: 1. FCT_COMBAT_START listeners (Panel
--                                  closes its windows, Face re-applies, Glyphs re-evaluate, detection is cancelled),
--                                  2. Remap.ApplyNow("combat"). Everything in it may still write protected state.
local addonName, ns = ...
ForeverControllerTweaks = ns

local VERSION, DEBUG_CAP = 2, 500
local PREFIX = "|cff33ff99Controller Tweaks|r "

ns.commands = {}
ns.panelOpen = false

local handlers, run = {}, nil
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^FCT_") then eventFrame:RegisterEvent(event) end
	end
	local list = handlers[event]
	list[#list + 1] = fn
	if event == "FCT_READY" and ns.db then run(event, fn) end
end

function ns.log(msg) print(PREFIX .. msg) end

-- One listener's error must not stop the rest: combat start runs the remap after its listeners.
local NONE, errorTold = {}, {}

function run(msg, fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then return end

	ns.debug("%s listener error: %s", msg, tostring(err))
	if not errorTold[fn] then ns.log("an error in " .. msg .. " was skipped — please /reload and report: " .. tostring(err)) end
	errorTold[fn] = true
end

function ns.Fire(msg, ...)
	for _, fn in ipairs(handlers[msg] or NONE) do run(msg, fn, ...) end
end

function ns.debug(fmt, ...)
	local db = ns.db
	if not (db and db.options.debug) then return end

	local log = db.debugLog
	log[#log + 1] = date("%H:%M:%S ") .. string.format(fmt, ...)
	while #log > DEBUG_CAP do table.remove(log, 1) end
end

local GAMEPAD_UI = Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad or 1
local active

-- Read only: the option is the CVar InputDeviceInterfaceStyle, which the addon never writes.
local function readActive()
	local ok, on = pcall(InputUtil and InputUtil.IsGamepadUIEnabled)
	if ok then return not not on end
	return GetCVar("InputDeviceInterfaceStyle") == tostring(GAMEPAD_UI)
end

function ns.Active()
	if active == nil then return readActive() end
	return active
end

local function updateActive(now)
	if now == nil then now = readActive() end
	if now == active then return end

	active = now
	ns.debug("gamepad UI %s", active and "on" or "off")
	ns.Fire("FCT_ACTIVE_CHANGED", active)
end

-- Without the Gamepad UI no Blizzard gamepad binding set is pushed, so there is nothing to wait for.
function ns.padFree()
	if not ns.Active() then return true end

	local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
	if not manager then return true end

	local ok, onlyCore = pcall(manager.IsOnlyCoreBindingSetActive, manager)
	return not ok or onlyCore ~= false
end

-- The chat box pushes a Blizzard binding set while a slash command runs, and binding pad keys while a Blizzard set
-- is active is a recorded taint cause, so jobs wait for the core set alone.
local QUEUE_POLL = 0.1
local jobs, order, queueTicker = {}, {}, nil

local function dropJob(name)
	jobs[name] = nil
	for i = #order, 1, -1 do
		if order[i] == name then table.remove(order, i) end
	end
end

-- A job's timeout counts only the time the pad is busy; combat pauses it. User jobs (with a timeout) say why they wait.
-- Returns true when it removed the job (ran it or gave up), which changes the order.
local function debugTell(msg) ns.debug("%s", msg) end

local function runJob(job, now, free)
	local tell = job.timeout and ns.log or debugTell
	if not job.combatOk and InCombatLockdown() then
		job.started = now
		if job.told ~= "combat" then tell(job.what .. ": waits for combat to end") end
		job.told = "combat"
		return
	end
	if job.timeout and now - job.started > job.timeout then
		dropJob(job.what)
		ns.log(job.what .. ": gave up, the chat box or a window still holds the pad")
		return true
	end
	if free then
		dropJob(job.what)
		job.fn()
		return true
	end

	if job.told == "pad" then return end
	job.told = "pad"
	ns.debug("%s: waiting for the chat box / window to close", job.what)
end

-- No copy of the order: after a job is removed (a job may also queue or replace others) the walk starts over; jobs
-- already looked at only wait again.
local function queueTick()
	local now, free, i = GetTime(), ns.padFree(), 1
	while order[i] do
		local job = jobs[order[i]]
		if job and runJob(job, now, free) then i = 1 else i = i + 1 end
	end
	if next(jobs) or not queueTicker then return end

	queueTicker:Cancel()
	queueTicker = nil
end

function ns.whenPadFree(what, fn, opts)
	if type(opts) ~= "table" then opts = { combatOk = opts } end
	if jobs[what] then ns.debug("%s replaces the queued one", what) else order[#order + 1] = what end

	jobs[what] = { what = what, fn = fn, combatOk = opts.combatOk, timeout = opts.timeout, started = GetTime() }
	queueTick()
	if next(jobs) and not queueTicker then queueTicker = C_Timer.NewTicker(QUEUE_POLL, queueTick) end
end

local FREE_POLL = 0.1
local lastFree, freeTicker

local function pollFree()
	local free = ns.padFree()
	if free == lastFree then return end

	lastFree = free
	ns.Fire("FCT_PAD_FREE", free)
end

local blockedTold

function ns.OnBlocked(event, addon, func)
	ns.debug("%s addon=%s func=%s combat=%s", tostring(event), tostring(addon), tostring(func), tostring(InCombatLockdown()))
	-- The modules (ForeverControllerTweaks_Touch, ...) are ours too.
	if type(addon) ~= "string" or addon:sub(1, #addonName) ~= addonName or blockedTold then return end

	blockedTold = true
	ns.log("Blizzard blocked " .. tostring(func) .. " — please /reload and report")
end

function ns.SetPanelOpen(open) ns.panelOpen = not not open end

function ns.TogglePanel() end

function ForeverControllerTweaks_TogglePanel() ns.TogglePanel() end

ns.On("PLAYER_ENTERING_WORLD", function()
	updateActive()
	lastFree = nil
	pollFree()
	freeTicker = freeTicker or C_Timer.NewTicker(FREE_POLL, pollFree)
end)
ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function(newMode) updateActive(newMode == GAMEPAD_UI) end)
ns.On("CVAR_UPDATE", function(name)
	if type(name) == "string" and name:lower() == "inputdeviceinterfacestyle" then updateActive() end
end)

-- The lockdown starts after this event, so the panel can close and the remap can still be written for the fight.
ns.On("PLAYER_REGEN_DISABLED", function()
	ns.Fire("FCT_COMBAT_START")
	if ns.Remap then ns.Remap.ApplyNow("combat") end
end)

ns.On("ADDON_ACTION_BLOCKED", function(addon, func) ns.OnBlocked("ADDON_ACTION_BLOCKED", addon, func) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(addon, func) ns.OnBlocked("ADDON_ACTION_FORBIDDEN", addon, func) end)

BINDING_HEADER_FOREVERCONTROLLERTWEAKS = "Forever Controller Tweaks"
BINDING_NAME_FOREVERCONTROLLERTWEAKS_TOGGLE = "Toggle Controller Tweaks"

-- Migrations keyed by the version they upgrade to; each runs once, on a repaired db.
local MIGRATIONS = {
	-- 2: a pad must be confirmed before the addon writes a config for it. Raw sources learned before v2 confirm it.
	[2] = function(db)
		for key, entry in pairs(db.devices) do
			if not entry.confirmed and not ns.Layout.Same(entry.raw, ns.Layout.DefaultsForKey(key).raw) then entry.confirmed = true end
		end
	end,
}

local function asTable(value) return type(value) == "table" and value or {} end

-- Drops every value that isn't a table, down to depth levels (cells[device][code][layer] is 3).
local function tablesDown(map, depth, path, fix)
	for key, value in pairs(map) do
		if type(value) ~= "table" then
			map[key] = nil
			fix(path .. "." .. tostring(key))
		elseif depth > 1 then
			tablesDown(value, depth - 1, path .. "." .. tostring(key), fix)
		end
	end
end

-- Macro registries: { id = <catalog id> } (account ones also chars = { ["Name-Realm"] = true }).
local function repairMacros(macros, path, fix)
	for name, info in pairs(macros) do
		if type(name) ~= "string" or type(info) ~= "table" or type(info.id) ~= "string" then
			macros[name] = nil
			fix(path .. "." .. tostring(name))
		end
	end
end

local CHAR_TABLES = { highest = 1, shadow = 1, cells = 3, faceEntries = 2 }
local CHAR_FLAGS = { "legacyFaceDone", "routedUnderDone" }

-- The face, action and macro stores are other files' data; only their shape is repaired here, so a damaged one can't
-- break the load. Bad entries are dropped.
local function repairStores(db, fix)
	if db.macros ~= nil and type(db.macros) ~= "table" then db.macros = nil fix("macros") end
	if db.chars ~= nil and type(db.chars) ~= "table" then db.chars = nil fix("chars") end
	if db.faceEntries ~= nil and type(db.faceEntries) ~= "table" then db.faceEntries = nil fix("faceEntries") end
	if db.faceEntries then tablesDown(db.faceEntries, 2, "faceEntries", fix) end
	if db.macros then
		repairMacros(db.macros, "macros", fix)
		for name, info in pairs(db.macros) do
			if type(info.chars) ~= "table" then info.chars = {} fix("macros." .. name .. ".chars") end
		end
	end
	for key, char in pairs(db.chars or NONE) do
		if type(key) ~= "string" or type(char) ~= "table" then
			db.chars[key] = nil
			fix("chars." .. tostring(key))
		else
			local path = "chars." .. key
			if char.macros ~= nil and type(char.macros) ~= "table" then char.macros = nil fix(path .. ".macros") end
			if char.macros then repairMacros(char.macros, path .. ".macros", fix) end
			for field, depth in pairs(CHAR_TABLES) do
				if char[field] ~= nil and type(char[field]) ~= "table" then char[field] = nil fix(path .. "." .. field) end
				if char[field] then tablesDown(char[field], depth, path .. "." .. field, fix) end
			end
			for _, flag in ipairs(CHAR_FLAGS) do
				if char[flag] ~= nil and type(char[flag]) ~= "boolean" then char[flag] = nil fix(path .. "." .. flag) end
			end
		end
	end
end

-- Repairs whatever the SavedVariables hold into the current shape; other top-level keys stay untouched.
local function loadDB()
	local db = asTable(ForeverControllerTweaksDB)
	local fresh = next(db) == nil
	-- 0, negative, fractional, NaN or infinite counts as the first version (inf % 1 and NaN % 1 are NaN).
	local version = db.version
	if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then db.version = fresh and VERSION or 1 end
	db.options, db.debugLog = asTable(db.options), asTable(db.debugLog)
	if type(db.devices) ~= "table" then db.devices = {} end
	if type(db.dirtyConfig) ~= "string" then db.dirtyConfig = nil end

	local options, fixes = db.options, {}
	if type(options.glyphs) ~= "boolean" then options.glyphs = true end
	if type(options.toggleKey) ~= "string" then options.toggleKey = "PADSOCIAL" end
	options.debug = options.debug == true
	while #db.debugLog > DEBUG_CAP do table.remove(db.debugLog, 1) end

	for key, entry in pairs(db.devices) do
		local repaired, entryFixes = ns.Layout.RepairDevice(entry, key)
		db.devices[key] = repaired
		for _, fix in ipairs(entryFixes) do fixes[#fixes + 1] = key .. ": " .. fix end
	end
	repairStores(db, function(what) fixes[#fixes + 1] = what end)
	if db.version > VERSION then
		ns.log("these settings were saved by a newer version of Controller Tweaks; some may be ignored")
	else
		for version = db.version + 1, VERSION do MIGRATIONS[version](db) end
		db.version = VERSION
	end
	ForeverControllerTweaksDB = db
	return db, fixes
end

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end

	local db, fixes = loadDB()
	ns.db = db
	for _, fix in ipairs(fixes) do ns.debug("db repaired %s", fix) end
	if #fixes > 0 then ns.log(string.format("repaired %d damaged saved setting%s", #fixes, #fixes == 1 and "" or "s")) end
	ns.Fire("FCT_READY")
end)

local HELP = "/fct (or /controllertweaks) opens the settings. Commands: status | preset native|split | release (gives back every slot and macro before uninstalling)"
	.. " | role <L1 R1 L2 R2 P1-P4> <leftmod rightmod friendly hostile none> | face <bottom right left top> <interact inspect back jump>"
	.. " | family playstation|xbox|switch|reset | detect | reset | selftest"

function ns.commands.help() ns.log(HELP) end

function ns.commands.debug(args)
	local on = args[1] == "on"
	if not on and args[1] ~= "off" then return ns.log("debug log is " .. (ns.db.options.debug and "on" or "off")) end

	ns.db.options.debug = on
	ns.log("debug log " .. (on and "on (ForeverControllerTweaksDB.debugLog)" or "off"))
end

-- Pcall'd: the reading is for a bug report, so a missing API or another file's error must not stop it.
local function safe(fn, ...)
	if type(fn) ~= "function" then return "n/a" end
	local ok, a, b = pcall(fn, ...)
	if not ok then return "error: " .. tostring(a) end
	return tostring(a), tostring(b)
end

function ns.commands.selftest()
	ns.db.options.debug = true
	local function add(fmt, ...)
		local line = string.format(fmt, ...)
		ns.log("selftest: " .. line)
		ns.debug("selftest %s", line)
	end

	local version, build, _, interface = GetBuildInfo()
	add("build %s.%s, interface %s, Gamepad UI %s", tostring(version), tostring(build), tostring(interface), ns.Active() and "on" or "off")
	local device = ns.Device.Refresh()
	if device then
		local vendor, product = string.format("%04x", device.vendorID or 0), string.format("%04x", device.productID or 0)
		add("device %s, vendor %s, product %s, labelStyle %s, family %s, confirmed %s", tostring(device.name), vendor, product, tostring(device.labelStyle), device.family, tostring(device.confirmed))
		add("raw tables %s-based, detected %s", tostring(ns.Device.RawBase()), device.detect and "yes" or "no")
	else
		add("no controller found")
	end
	add("first gamepad action storage slot %s", safe(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex))
	local account, character = safe(GetNumMacros)
	add("macros: %s account, %s character", account, character or "?")
	add("remap %s, face %s, glyphs %s", ns.Remap.State(), safe(ns.Face and ns.Face.State), safe(ns.Glyphs and ns.Glyphs.Mode))
	ns.log("selftest: the debug log is on (/fct debug off to stop). For a taint check type /console taintLog 2, then /reload.")
end

SLASH_FOREVERCONTROLLERTWEAKS1 = "/fct"
SLASH_FOREVERCONTROLLERTWEAKS2 = "/controllertweaks"
SlashCmdList.FOREVERCONTROLLERTWEAKS = function(msg)
	local args = {}
	for word in msg:gmatch("%S+") do args[#args + 1] = word end

	if not ns.db then return ns.log("not loaded yet") end

	local name = (table.remove(args, 1) or ""):lower()
	if name == "" then return ns.TogglePanel() end

	local handler = ns.commands[name] or ns.commands.help
	handler(args)
end
