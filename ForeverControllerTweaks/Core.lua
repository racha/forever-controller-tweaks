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
--                                  A change fires FCT_PANEL_OPEN(open).
--   ns.MigrateChar(flag, fn)       a once-per-character migration that needs the game's slots or macros, run by its
--                                  owner when it can: fn(char) runs until it returns true, which sets char[flag].
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
-- Message FCT_PAD_FREE(free): ns.padFree() changed (seen a frame after the binding stack changes, polled as a safety
-- net); also fires at every PLAYER_ENTERING_WORLD.
-- Message FCT_DETECTING(on): controller detection started or stopped.
-- CVAR_UPDATE(name) arrives as the game sends it, in any case: listeners compare name:lower().
-- A listener's error is caught: the other listeners still run, and it is reported once per session.
-- Message FCT_COMBAT_START: fired synchronously first thing in PLAYER_REGEN_DISABLED, before the lockdown
--                                  begins. Order inside that one handler: 1. FCT_COMBAT_START listeners (Panel
--                                  closes its windows, Face re-applies, Glyphs re-evaluate, detection is cancelled),
--                                  2. Remap.ApplyNow("combat"). Everything in it may still write protected state.
local addonName, ns = ...
ForeverControllerTweaks = ns

local VERSION, DEBUG_CAP = 6, 500
ns.DB_VERSION = VERSION
local PREFIX = "|cff33ff99Controller Tweaks|r "

ns.commands = {}
ns.panelOpen = false

local handlers, run = {}, nil
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

-- Registering an event the client doesn't have throws and would stop the file loading, so a removed one is skipped
-- (the check is Controller Companion's, MIT).
local function validEvent(event)
	local check = C_EventUtils and C_EventUtils.IsEventValid
	return not check or check(event)
end

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^FCT_") and validEvent(event) then eventFrame:RegisterEvent(event) end
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

-- A ring of DEBUG_CAP lines: once full, debugAt is the newest line's index. Put back in order at logout.
local debugAt, lastDebug = 0, nil

function ns.debug(fmt, ...)
	local db = ns.db
	if not (db and db.options.debug) then return end

	local log = db.debugLog
	lastDebug = date("%H:%M:%S ") .. string.format(fmt, ...)
	if #log < DEBUG_CAP then
		log[#log + 1] = lastDebug
		return
	end
	debugAt = debugAt % DEBUG_CAP + 1
	log[debugAt] = lastDebug
end

local function unroll(log)
	if debugAt == 0 or #log < DEBUG_CAP then return log end
	local out = {}
	for i = 1, #log do out[i] = log[(debugAt + i - 1) % #log + 1] end
	return out
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

local lastFree, freeTicker

local function pollFree()
	local free = ns.padFree()
	if free == lastFree then return end

	lastFree = free
	ns.Fire("FCT_PAD_FREE", free)
end

-- The stack's answer changes only in these four methods (InputBindingManager.lua), so post-hooks on them see every
-- change; the check runs a frame later, as a window can push and pop in one frame. hooksecurefunc runs our hook after
-- Blizzard's method has run and returned to secure execution, and the hook only starts a timer; the check after it is
-- the same read (IsOnlyCoreBindingSetActive) padFree always made. Nothing of the manager is written or replaced but
-- those four fields, which hooksecurefunc keeps secure (TaintWatch checks them). The poll
-- stays as a safety net for a caller that kept the old method; at 0.1 s if the hooks couldn't be set.
-- Learning it from the stack is Gamepad Suite's idea (All Rights Reserved; nothing of its code is used).
local FREE_POLL, SAFETY_POLL = 0.1, 1
local STACK_WRITERS = { "AddBindingSet", "RemoveSet", "ClearBindings", "AssumeCoreBindingsAreUsable" }
local function freeSoon() C_Timer.After(0, pollFree) end

local function hookStack()
	local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
	if not (manager and hooksecurefunc) then return false end
	for _, method in ipairs(STACK_WRITERS) do
		if type(manager[method]) ~= "function" or not pcall(hooksecurefunc, manager, method, freeSoon) then return false end
	end
	return true
end

local blockedTold

function ns.OnBlocked(event, addon, func)
	ns.debug("%s addon=%s func=%s combat=%s", tostring(event), tostring(addon), tostring(func), tostring(InCombatLockdown()))
	-- The modules (ForeverControllerTweaks_Touch, ...) are ours too.
	if type(addon) ~= "string" or addon:sub(1, #addonName) ~= addonName or blockedTold then return end

	blockedTold = true
	ns.log("Blizzard blocked " .. tostring(func) .. " — please /reload and report")
end

function ns.SetPanelOpen(open)
	open = not not open
	if open == ns.panelOpen then return end

	ns.panelOpen = open
	ns.Fire("FCT_PANEL_OPEN", open)
end

function ns.TogglePanel() end

function ForeverControllerTweaks_TogglePanel() ns.TogglePanel() end

ns.On("PLAYER_ENTERING_WORLD", function()
	updateActive()
	lastFree = nil
	pollFree()
	freeTicker = freeTicker or C_Timer.NewTicker(hookStack() and SAFETY_POLL or FREE_POLL, pollFree)
end)
-- padFree() is always true while inactive, so it can change with the option too.
ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function(newMode)
	updateActive(newMode == GAMEPAD_UI)
	pollFree()
end)
ns.On("CVAR_UPDATE", function(name)
	if not (type(name) == "string" and name:lower() == "inputdeviceinterfacestyle") then return end
	updateActive()
	pollFree()
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

-- Routed cells (Face.lua), cells[profileId][code][layer]: their shape, for every module that reads or carries them.
local CELL_LAYERS = { T = true, L = true, R = true, B = true }
-- Row codes: "face" buttons (their top-bar slot is reserved), "dpad", and "none" for the buttons without a crossbar
-- slot (the paddles, the stick presses).
local CELL_CODES = { FB = "face", FR = "face", FL = "face", FT = "face", DU = "dpad", DL = "dpad", DR = "dpad", DD = "dpad", P1 = "none", P2 = "none", P3 = "none", P4 = "none", L3 = "none", R3 = "none" }
local Cells = {}
ns.Cells = Cells

function Cells.PageCount() return ns.Actions and ns.Actions.STANDARD_PAGES or 3 end

-- True for a cell with a crossbar slot, whose entry is per crossbar page (1.5.5): cells[profileId][code][layer] =
-- { [page] = entry }, a page without one nil. The cells without one (the paddles, the stick presses, the reserved
-- top-bar face slots) keep the entry itself, one for every page. The row stays keyed by layer, so every reader still
-- finds a cell by code and layer, and a page list has no id, so it is never taken for an entry: readers, the claim's
-- fill-only merge (page by page) and sync tell the two apart by shape. A static rule (no game bars needed), so the
-- migration, sync and a machine without the Gamepad UI agree.
function Cells.Paged(code, layer)
	local kind = CELL_CODES[code]
	if not (kind and CELL_LAYERS[layer]) or kind == "none" then return false end
	return not (layer == "T" and kind == "face")
end

function Cells.IsEntry(value) return type(value) == "table" and type(value.id) == "string" end
local isEntry = Cells.IsEntry

-- fn(code, layer, entry, page) for every entry of a cells[profileId] table; page nil for a page-less one.
function Cells.EachCell(rows, fn)
	for code, row in pairs(type(rows) == "table" and rows or NONE) do
		for layer, value in pairs(type(row) == "table" and row or NONE) do
			if isEntry(value) then
				fn(code, layer, value)
			elseif type(value) == "table" then
				for page, entry in pairs(value) do if isEntry(entry) then fn(code, layer, entry, page) end end
			end
		end
	end
end

-- Puts the one entry of each paged cell on every page, in place: the stored or wire shape (a wire entry is the id
-- alone or a table with it) from before 1.5.5 and sync format 5. Idempotent; page-less cells are left as they are.
-- Returns true when it changed something.
function Cells.ExpandPages(rows)
	local changed = false
	for code, row in pairs(type(rows) == "table" and rows or NONE) do
		for layer, value in pairs(type(row) == "table" and row or NONE) do
			if Cells.Paged(code, layer) and (type(value) == "string" or isEntry(value)) then
				local pages = {}
				for page = 1, Cells.PageCount() do
					local copy = value
					if type(value) == "table" then
						copy = {}
						for key, field in pairs(value) do copy[key] = field end
					end
					pages[page] = copy
				end
				row[layer], changed = pages, true
			end
		end
	end
	return changed
end

-- Migrations keyed by the version they upgrade to; each runs once, on a repaired db.
local MIGRATIONS = {
	-- 2: a pad must be confirmed before the addon writes a config for it. Raw sources learned before v2 confirm it.
	[2] = function(db)
		for key, entry in pairs(db.devices) do
			if not entry.confirmed and not ns.Layout.Same(entry.raw, ns.Layout.DefaultsForKey(key).raw) then entry.confirmed = true end
		end
	end,
	-- 3 (1.5.1): every controller becomes its own profile (Profile.lua), under its device key.
	[3] = function(db) if ns.Profile then ns.Profile.Migrate(db) end end,
	-- 4 (1.5.2): rings go per record (ns.MoveRings), the saved stick value stays account-wide; touch buttons go per
	-- profile (ns.MoveTouchBars). Records stay under their 1.5.1 Name-Realm keys until a character claims them (Face).
	[4] = function(db)
		local rings = type(db.rings) == "table" and db.rings or nil
		if rings and db.ringAxisSaved == nil and type(rings.axisSaved) == "string" then db.ringAxisSaved = rings.axisSaved end
		if rings then rings.axisSaved = nil end
		for _, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
			if type(char) == "table" then ns.MoveTouchBars(db, char) end
		end
		ns.MoveRings(db)
	end,
	-- 5 (1.5.4): profiles belong to the characters (Profile.lua); a controller never picks one.
	[5] = function(db) if ns.Profile then ns.Profile.MoveToChars(db) end end,
	-- 6 (1.5.5): a cell with a crossbar slot holds its entry per crossbar page (Cells.Paged); the one it had goes to
	-- every page, so nothing changes until a page is edited. Every record, claimed or not, in every profile; the
	-- cells without a slot stay as they are. Each page gets a copy before the entry is replaced.
	[6] = function(db)
		for _, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
			for _, rows in pairs(type(char) == "table" and type(char.cells) == "table" and char.cells or NONE) do Cells.ExpandPages(rows) end
		end
	end,
}

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in pairs(value) do out[key] = copy(item) end
	return out
end

-- Touch buttons before 1.5.2 (char.touch.bars, one set per character) become a copy in every live profile
-- (char.touchBars[profile id]): the character's own since 1.5.4, the account's while MIGRATIONS[4] runs. A profile with
-- buttons of its own keeps them. Removed only once copied somewhere: without a profile yet they wait (Touch.Config runs
-- this again). Idempotent.
function ns.MoveTouchBars(db, char)
	local touch = type(char.touch) == "table" and char.touch or nil
	local bars = touch and touch.bars
	if bars == nil then return end
	if type(bars) ~= "table" then touch.bars = nil return end
	local copied = false
	local profiles = type(char.profiles) == "table" and char.profiles or type(db.profiles) == "table" and db.profiles or NONE
	for id, profile in pairs(profiles) do
		if type(profile) == "table" and not profile.gone then
			char.touchBars = type(char.touchBars) == "table" and char.touchBars or {}
			if char.touchBars[id] == nil then char.touchBars[id] = copy(bars) end
			copied = true
		end
	end
	if copied then touch.bars = nil end
end

-- The ring ids one character's bindings open: routed cells in every profile, touch buttons in every profile (and the
-- touch.bars of before 1.5.2).
local function ringRefs(char)
	local refs = {}
	local function grid(rows)
		for _, row in pairs(type(rows) == "table" and rows or NONE) do
			for _, entry in pairs(type(row) == "table" and row or NONE) do
				local id = type(entry) == "table" and tonumber(tostring(entry.id):match("^ring:(%d+)$"))
				if id then refs[id] = true end
			end
		end
	end
	local function bars(sides) for _, list in pairs(type(sides) == "table" and sides or NONE) do grid(list) end end
	for _, rows in pairs(type(char.cells) == "table" and char.cells or NONE) do grid(rows) end
	for _, sides in pairs(type(char.touchBars) == "table" and char.touchBars or NONE) do bars(sides) end
	bars(type(char.touch) == "table" and char.touch.bars)
	return refs
end

-- 1.5.1's account ring list, handed out at load to the records that were there (all from before 1.5.2): each gets a
-- copy of the rings its own bindings open (ids kept, so the bindings still work), and a ring nobody's bindings open
-- goes to every record. Nothing goes by who logs in: a record's rings reach its character with its claim (Face.lua),
-- so a new character starts with none. Copies before it deletes; a record keeps rings of its own and gets only those
-- it lacks. Without any record the list stays (nothing to copy it to).
function ns.MoveRings(db)
	local rings = type(db.rings) == "table" and db.rings or nil
	local list = rings and type(rings.list) == "table" and rings.list or nil
	local chars = type(db.chars) == "table" and db.chars or NONE
	if not list then
		if rings then db.rings = nil end
		return
	end
	if not next(chars) then return end
	local refsOf, anyRef = {}, {}
	for name, char in pairs(chars) do
		refsOf[name] = type(char) == "table" and ringRefs(char) or NONE
		for id in pairs(refsOf[name]) do anyRef[id] = true end
	end
	for name, char in pairs(chars) do
		if type(char) == "table" then
			local mine = type(char.rings) == "table" and type(char.rings.list) == "table" and char.rings or nil
			local have = {}
			for _, ring in ipairs(mine and mine.list or NONE) do if type(ring) == "table" then have[ring.id] = true end end
			for _, ring in ipairs(list) do
				if type(ring) == "table" and not have[ring.id] and (refsOf[name][ring.id] or not anyRef[ring.id]) then
					mine = mine or { nextId = rings.nextId, list = {} }
					mine.list[#mine.list + 1] = copy(ring)
					have[ring.id] = true
				end
			end
			if mine then
				char.rings = mine
				if type(rings.nextId) == "number" and (type(mine.nextId) ~= "number" or mine.nextId < rings.nextId) then mine.nextId = rings.nextId end
			end
		end
	end
	db.rings = nil
end

local function asTable(value) return type(value) == "table" and value or {} end
-- value - value is NaN for NaN and for an infinity.
local function finite(value) return type(value) == "number" and value - value == 0 end

local function stringList(value)
	if type(value) ~= "table" then return false end
	for key, item in pairs(value) do
		if type(key) ~= "number" or type(item) ~= "string" then return false end
	end
	return true
end

-- Drops every value that isn't a table, down to depth levels (cells[device][code][layer] is 3; a page list's entries
-- are checked by their readers).
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

-- Macro registries: { id = <catalog id> } (account ones also chars = { [GUID] = true }).
local function repairMacros(macros, path, fix)
	for name, info in pairs(macros) do
		if type(name) ~= "string" or type(info) ~= "table" or type(info.id) ~= "string" then
			macros[name] = nil
			fix(path .. "." .. tostring(name))
		end
	end
end

local CHAR_TABLES = { highest = 1, shadow = 1, placed = 1, cells = 3, faceEntries = 2, touchBars = 4, profiles = 1 }
-- The per-character migrations (ns.MigrateChar): legacyFaceDone (Face, PS:Back/Inspect macros to routed cells),
-- routedUnderDone (Face, FCT: macros left under routed cells), macroPrefixDone (Actions, PS: macros renamed FCT:).
local CHAR_FLAGS = { "legacyFaceDone", "routedUnderDone", "macroPrefixDone" }

-- Unlike MIGRATIONS (the account db, at load), these need the game's slots and macros, so each runs from its owner
-- when those can be written; a run that couldn't finish (a slot write refused) is tried again on the next call.
function ns.MigrateChar(flag, fn)
	local char = ns.Face and ns.Face.CharDB()
	if not char or char[flag] then return end
	if fn(char) then char[flag] = true end
end

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
			-- The display name Face keeps (records are keyed by GUID).
			if char.name ~= nil and type(char.name) ~= "string" then char.name = nil fix(path .. ".name") end
		end
	end
end

-- Repairs whatever the SavedVariables hold into the current shape; other top-level keys stay untouched.
local function loadDB()
	local db = asTable(ForeverControllerTweaksDB)
	local fresh = next(db) == nil
	-- A first install, not an update: What's new (Panel/WhatsNew.lua) shows nothing then.
	ns.freshDB = fresh
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
	-- toggleHold: false (the key alone) or the physical buttons held first; nil gets the Panel's default.
	if options.toggleHold ~= false and not stringList(options.toggleHold) then options.toggleHold = nil end
	if not finite(options.minimapAngle) then options.minimapAngle = nil end
	-- Onboarding's sets: { [device or onboarding key] = true }.
	for _, set in ipairs({ "onboarded", "declined" }) do
		if db[set] ~= nil and type(db[set]) ~= "table" then
			db[set] = nil
			fixes[#fixes + 1] = set
		end
	end
	local log, kept = db.debugLog, {}
	for i = math.max(1, #log - DEBUG_CAP + 1), #log do kept[#kept + 1] = log[i] end
	db.debugLog = kept

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
	if ns.Profile then ns.Profile.Repair(db, function(what) fixes[#fixes + 1] = what end) end
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

local HELP = "/fct (or /controllertweaks) opens the settings; so do L2 + R2 + Create/View and the minimap button. Commands: bindings (the Bindings window) | rings (the Rings settings)"
	.. " | setup (the first-run guide) | detect (press-each-button controller setup) | family playstation|xbox|switch|reset"
	.. " | preset native|split | role <L1 R1 L2 R2 P1-P4> <leftmod rightmod friendly hostile none>"
	.. " | face <bottom right left top> <interact inspect back jump> | learn <L1 R1 L2 R2 P1-P4>|cancel | reset (the layout)"
	.. " | whatsnew (what's new in this version; turns it back on) | cleanup (finds duplicate FCT: macros and stray hidden slots and tidies them)"
	.. " | profile (this character's) | profile <name> (this character plays on it) | sync (status; now, on, off, undo) | export | import | release (gives back every slot and macro before uninstalling) | status | selftest | ringlog | debug on|off | help"

function ns.commands.help() ns.log(HELP) end

-- Debug only, read only: issecurevariable on the Blizzard gamepad state the addon must never own. The first moment
-- each field turns insecure is logged once, with the debug line written just before it (our last action). The idea
-- is Controller Forever's TaintWatch (All Rights Reserved; nothing of its code is used).
local TAINT_POLL = 1
local TAINT_FIELDS = {
	{ "InputBindingManager", function() return GamepadSharedUtility and GamepadSharedUtility.InputBindingManager end, { "bindingSetStack", "activeBindings", "currentCoreBindingActive", "AddBindingSet", "RemoveSet", "ClearBindings", "AssumeCoreBindingsAreUsable" } },
	{ "FrameControlsManager", function() return GamepadMode and GamepadMode.FrameControlsManager end, { "focusedFrame", "isUIFocused", "shownFrames", "topSuspendedFrame" } },
	{ "PageUnit", function() return GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit end, { "activeBar", "currentState", "activeFlyoutButton", "actionBars" } },
}
local taintSeen, taintTicker = {}, nil

-- name.field -> nil (secure or not there) or who owns it ("?" when the game doesn't say).
local function taintedFields()
	local out = {}
	if not issecurevariable then return out end
	for _, watched in ipairs(TAINT_FIELDS) do
		local name, get, fields = watched[1], watched[2], watched[3]
		local owner = get()
		for _, field in ipairs(type(owner) == "table" and fields or NONE) do
			local ok, secure, by = pcall(issecurevariable, owner, field)
			if ok and not secure then out[name .. "." .. field] = by or "?" end
		end
	end
	return out
end

local function taintCheck()
	if not ns.db.options.debug then
		taintTicker:Cancel()
		taintTicker = nil
		return
	end
	for field, by in pairs(taintedFields()) do
		if not taintSeen[field] then
			taintSeen[field] = true
			ns.debug("taintwatch: %s now insecure, by %s; last before it: %s", field, by, tostring(lastDebug))
		end
	end
end

local function watchTaint()
	if ns.db.options.debug and not taintTicker then taintTicker = C_Timer.NewTicker(TAINT_POLL, taintCheck) end
end

function ns.commands.debug(args)
	local on = args[1] == "on"
	if not on and args[1] ~= "off" then return ns.log("debug log is " .. (ns.db.options.debug and "on" or "off")) end

	ns.db.options.debug = on
	watchTaint()
	ns.log("debug log " .. (on and "on (ForeverControllerTweaksDB.debugLog)" or "off"))
end

ns.On("PLAYER_LOGIN", watchTaint)
ns.On("PLAYER_LOGOUT", function()
	ns.db.debugLog = unroll(ns.db.debugLog)
	debugAt = 0
end)

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
	local tainted = {}
	for field, by in pairs(taintedFields()) do tainted[#tainted + 1] = field .. " by " .. by end
	table.sort(tainted)
	add("taintwatch: %s", not issecurevariable and "n/a" or #tainted > 0 and table.concat(tainted, ", ") or "every watched Blizzard gamepad field is secure")
	watchTaint()
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
