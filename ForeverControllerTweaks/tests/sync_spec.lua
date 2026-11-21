-- Stubbed WoW check of sync between machines and export / import (design/sync.md 8): lua tests/sync_spec.lua
-- Two machines run Core.lua and Sync.lua each, with their own SavedVariables, over one account macro list. The
-- compression stub carries a checksum (as Zlib's Adler-32 does), Base64 is hex.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local out = io.write
local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then passed = passed + 1 else
		failed = failed + 1
		out("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
	end
end

local W = { now = 100, server = 1795200000, combat = false, timers = {}, tickers = {}, lines = {} }
local account = {}
local current

_G.print = function(msg) W.lines[#W.lines + 1] = tostring(msg) end
function date(fmt, t) return os.date(fmt, t) end
function GetTime() return W.now end
function GetServerTime() return W.server end
function InCombatLockdown() return W.combat end
function GetCVar() return nil end
function IsMacClient() return true end
SlashCmdList = {}
Enum = { InputDeviceInterfaceType = { Gamepad = 1 }, CompressionMethod = { Zlib = 1 }, CompressionLevel = { OptimizeForSize = 2 } }
InputUtil = { IsGamepadUIEnabled = function() return true end }

function CreateFrame()
	local f = { events = {}, scripts = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	current.frames[#current.frames + 1] = f
	return f
end
C_Timer = {
	NewTicker = function(_, fn)
		local t = { fn = fn }
		function t:Cancel() self.dead = true end
		W.tickers[#W.tickers + 1] = t
		return t
	end,
	After = function(delay, fn) W.timers[#W.timers + 1] = { at = W.now + delay, fn = fn } end,
}

local function sum(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
	return h
end
C_EncodingUtil = {
	CompressString = function(s, method)
		assert(method == 1, "zlib")
		return "Z" .. sum(s) .. ":" .. s
	end,
	DecompressString = function(s, method)
		assert(method == 1, "zlib")
		local check, body = s:match("^Z(%d+):(.*)$")
		assert(check and tonumber(check) == sum(body), "adler")
		return body
	end,
	EncodeBase64 = function(s) return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end)) end,
	DecodeBase64 = function(s)
		assert(#s % 2 == 0 and not s:find("[^0-9A-F]"), "base64")
		return (s:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
	end,
}

-- Account macros: indexes 1..#account.
-- W.hidden: the list isn't loaded yet (a login reads it empty for a moment).
function GetNumMacros()
	if W.hidden then return 0, 0 end
	return #account, 0
end
function GetMacroInfo(i)
	local m = account[i]
	if m then return m.name, m.icon, m.body end
end
function GetMacroBody(i) return account[i] and account[i].body end
local creates, edits, deletes = 0, 0, 0
function CreateMacro(name, icon, body, perChar)
	assert(not perChar, "sync macros are account macros")
	if #account >= 120 then return nil end
	creates = creates + 1
	account[#account + 1] = { name = name, icon = icon, body = body }
	return #account
end
function EditMacro(i, name, icon, body)
	edits = edits + 1
	local m = account[i]
	m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
end
function DeleteMacro(i)
	deletes = deletes + 1
	table.remove(account, i)
end

local function run(seconds)
	for _ = 1, math.max(1, math.floor((seconds or 0.2) * 10)) do
		W.now = W.now + 0.1
		for _, t in ipairs(W.tickers) do if not t.dead then t.fn() end end
		local due = {}
		for i = #W.timers, 1, -1 do if W.timers[i].at <= W.now then table.insert(due, 1, table.remove(W.timers, i)) end end
		for _, t in ipairs(due) do t.fn() end
	end
end

local CATALOG = {
	{ name = "Spells", entries = {
		{ id = "spell:20271", name = "Judgement", icon = "icon-judgement", kind = "spell" },
		{ id = "spellgroup:Holy Light", name = "Holy Light", icon = "icon-holy", kind = "spellgroup", ranks = { { id = "spellgroup:Holy Light", name = "Holy Light (Highest Rank)", icon = "icon-holy" } } },
	} },
	{ name = "Windows", entries = { { id = "game:bags", name = "Backpack", icon = "icon-bag", kind = "game" } } },
	{ name = "AddOns", entries = { { id = "addon:CLICK X:LeftButton", name = "X: Y", icon = "icon-addon", kind = "game" } } },
}

-- A machine: Core.lua and Sync.lua over its own SavedVariables, a DualSense, and the character "Ann-Realm".
local function machine(db, opts)
	opts = opts or {}
	local m = { frames = {}, ns = {}, db = db }
	current = m
	ForeverControllerTweaksDB = db
	local ns = m.ns
	assert(loadfile(dir .. "/Core.lua"))("ForeverControllerTweaks", ns)
	ns.Layout = { RepairDevice = function(entry) return entry, {} end }
	ns.Device = { Current = function() return opts.noPad and nil or { key = opts.pad or "054c/0ce6", name = opts.padName or "DualSense Wireless Controller" } end }
	ns.Face = { CharDB = function()
		if not ns.db then return end
		ns.db.chars = ns.db.chars or {}
		ns.db.chars["Ann-Realm"] = ns.db.chars["Ann-Realm"] or {}
		return ns.db.chars["Ann-Realm"], "Ann-Realm"
	end }
	local writing = 0
	ns.Actions = {
		Catalog = function() return CATALOG end,
		Busy = function() return writing > 0 end,
		Guard = function(fn) return function(...)
			writing = writing + 1
			local out = { pcall(fn, ...) }
			writing = writing - 1
			assert(out[1], out[2])
			return select(2, (unpack or table.unpack)(out))
		end end,
	}
	assert(loadfile(dir .. "/Sync.lua"))("ForeverControllerTweaks", ns)
	function m.fire(event, ...)
		current = m
		for _, f in ipairs(m.frames) do
			if f.events[event] then f.scripts.OnEvent(f, event, ...) end
		end
	end
	m.settled = 0
	ns.On("FCT_SYNC_SETTLED", function() m.settled = m.settled + 1 end)
	m.layout = 0
	ns.On("FCT_LAYOUT_CHANGED", function() m.layout = m.layout + 1 end)
	function m.login()
		m.fire("ADDON_LOADED", "ForeverControllerTweaks")
		m.fire("PLAYER_LOGIN")
		m.fire("PLAYER_ENTERING_WORLD")
		m.fire("UPDATE_MACROS")
		run(0.5)
	end
	return m
end

local function ourMacros()
	local n = 0
	for _, macro in ipairs(account) do if macro.name:find("^FCT:Sync %d+$") and macro.body:find("^#FCT") then n = n + 1 end end
	return n
end

local function settingsA()
	return {
		version = 2,
		options = { glyphs = true, toggleKey = "PADSOCIAL", debug = true, minimapAngle = 200.5 },
		tweaks = { sellJunk = true, lightBar = "class" },
		rings = { nextId = 2, axisSaved = "1", list = { { id = 1, name = "Ring 1", count = 6, slots = { [1] = { id = "spell:20271", name = "Judgement", icon = "icon-judgement", kind = "spell" }, [3] = { id = "game:bags", name = "Backpack", icon = "icon-bag", kind = "game" } } } } },
		ringMarker = false,
		keyboard = { enabled = true, layout = "ring", dictionary = { hello = 3 }, suggest = { learned = 1 }, blocked = { "box" }, phrases = { anywhere = { "hi all" } } },
		devices = { ["054c/0ce6"] = { raw = { L1 = 10 }, roles = { L1 = "rightmod" }, face = { bottom = "jump" }, confirmed = true } },
		chars = { ["Ann-Realm"] = {
			cells = { ["054c/0ce6"] = { FB = { R = { id = "spellgroup:Holy Light", name = "Holy Light (Highest Rank)", icon = "icon-holy", kind = "spellgroup", healer = true, healerLast = true } }, DR = { T = { id = "ring:1", name = "Open ring: Ring 1", icon = "icon-judgement", kind = "ring" } } } },
			touch = { enabled = true, show = "gamepad", sides = { left = { count = 6 } }, bars = { left = { [1] = { T = { id = "addon:CLICK X:LeftButton", name = "X: Y", icon = "icon-addon", kind = "game" } } } } },
			ringLast = { [1] = { 1, "spell:20271" } }, shadow = { [180] = { code = "FB", layer = "R", id = "x" } }, macros = { ["FCT:Bags"] = { id = "game:bags" } }, highest = { [5] = { name = "Holy Light", id = 1 } },
		} },
		macros = { ["FCT:Bags"] = { id = "game:bags", chars = {} } },
		news = { seen = "1.4.0" }, debugLog = { "a line" }, onboarded = { ["054c/0ce6"] = true },
	}
end

---------------------------------------------------------------------------------------------------------------------
-- The text form

do
	local m = machine({})
	local Sync = m.ns.Sync
	local a, b = {}, {}
	for i = 1, 20 do a["k" .. i] = i * 1.5 end
	for i = 20, 1, -1 do b["k" .. i] = i * 1.5 end
	check("text form is the same whatever the insertion order", Sync.Encode(a) == Sync.Encode(b))
	local value = { 1, 2, x = { y = "a:b{}s3:", z = false, [10] = 0.1 }, n = -3.25e-7, t = true, big = 1795212345 }
	local back = Sync.Decode(Sync.Encode(value))
	check("text form round-trips", back and Sync.Encode(back) == Sync.Encode(value) and back.x.y == "a:b{}s3:" and back.x[10] == 0.1 and back.big == 1795212345 and back[2] == 2)
	check("NaN and functions are left out", Sync.Encode({ a = 0 / 0, b = print, c = 1 }) == Sync.Encode({ c = 1 }))
	local text = Sync.Encode(value)
	check("a cut text is damaged", Sync.Decode(text:sub(1, -2)) == nil)
	check("trailing letters are damaged", Sync.Decode(text .. "t") == nil)
	check("a wrong string length is damaged", Sync.Decode("s9:abc") == nil)
	check("deep nesting is refused", Sync.Decode(string.rep("{s1:a", 40) .. "t" .. string.rep("}", 40)) == nil)
	check("pack and unpack round-trip", Sync.Encode(Sync.Unpack(Sync.Pack(value))) == Sync.Encode(value))
	local packed = Sync.Pack(value)
	local flipped = packed:sub(1, 20) .. (packed:sub(21, 21) == "4" and "5" or "4") .. packed:sub(22)
	check("an edited pack fails its checksum", Sync.Unpack(flipped) == nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Bodies

do
	local m = machine({})
	local Sync = m.ns.Sync
	local text = string.rep("ABCDEF0123", 120)
	local bodies = Sync.Bodies(text, 1795212345)
	local longest, joined = 0, {}
	for i, body in ipairs(bodies) do
		longest = math.max(longest, #body)
		local part, total, gen, data = body:match("^#FCT1 (%d+)/(%d+) (%w+) (%S*)$")
		check("body " .. i .. " parses", tonumber(part) == i and tonumber(total) == #bodies and tonumber(gen, 36) + 1735689600 == 1795212345)
		joined[#joined + 1] = data
	end
	check("bodies are at most 255 letters", longest <= 255, longest)
	check("bodies join back", table.concat(joined) == text)
	check("1200 letters need 6 parts", #bodies == 6, #bodies)
	check("only the body alphabet", not table.concat(bodies):find("[|\"\n]"))
	local twenty = Sync.Bodies(string.rep("A", 236 * 20), 1795212345)
	check("part 20 of 20 is still at most 255", #twenty == 20 and #twenty[20] <= 255, #twenty[20])
	check("a sync macro is known by name and body", Sync.IsSyncMacro("FCT:Sync 2", "#FCT1 1/1 x y\n") and not Sync.IsSyncMacro("FCT:Sync 2", "/say hi") and not Sync.IsSyncMacro("FCT:Bags", "#FCT1"))
end

---------------------------------------------------------------------------------------------------------------------
-- Merge rules (design 4)

do
	local m = machine({})
	local Sync, E = m.ns.Sync, m.ns.Sync.Encode
	local function R(d, t) return { d = d, t = t or 0 } end
	local plan = Sync.Merge({ tweaks = { a = true } }, {}, {}, {}, false, false)
	check("1: R absent keeps L", plan.keep.tweaks and not plan.take.tweaks)
	plan = Sync.Merge({}, { tweaks = R({ a = true }) }, {}, {}, false, false)
	check("2: L absent takes R", plan.take.tweaks and plan.take.tweaks.a)
	plan = Sync.Merge({ ["b:A-R:054c/0ce6"] = {} }, { ["b:A-R:054c/0ce6"] = R({ FB = { T = "spell:1" } }) }, {}, {}, true, false)
	check("2: empty bindings never synced take R", plan.take["b:A-R:054c/0ce6"] ~= nil)
	plan = Sync.Merge({ ["b:A-R:054c/0ce6"] = {} }, { ["b:A-R:054c/0ce6"] = R({ FB = { T = "spell:1" } }, 5) }, { ["b:A-R:054c/0ce6"] = E({ FB = { T = "spell:1" } }) }, { ["b:A-R:054c/0ce6"] = 9 }, false, false)
	check("2: bindings cleared here after a sync are a change, not empty", plan.keep["b:A-R:054c/0ce6"] and not plan.take["b:A-R:054c/0ce6"])
	plan = Sync.Merge({ tweaks = { a = true } }, { tweaks = R({ a = true }) }, {}, {}, true, true)
	check("3: equal agrees", plan.agree.tweaks == E({ a = true }) and not plan.conflicts[1])
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }) }, { tweaks = E({ a = 1 }) }, { tweaks = 50 }, false, true)
	check("4: L unchanged since the base takes R", plan.take.tweaks and plan.take.tweaks.a == 2 and not plan.both.tweaks)
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }, 99) }, { tweaks = E({ a = 2 }) }, { tweaks = 10 }, false, true)
	check("5: R unchanged since the base keeps L", plan.keep.tweaks and not plan.take.tweaks)
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }, 60) }, { tweaks = E({ a = 3 }) }, { tweaks = 50 }, false, true)
	check("6: both changed, R newer takes R", plan.take.tweaks and plan.both.tweaks)
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }, 40) }, { tweaks = E({ a = 3 }) }, { tweaks = 50 }, false, true)
	check("6: both changed, L newer keeps L", plan.keep.tweaks and not plan.take.tweaks)
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }, 50) }, { tweaks = E({ a = 3 }) }, { tweaks = 50 }, false, true)
	check("6: a tie keeps L", plan.keep.tweaks and not plan.take.tweaks)
	plan = Sync.Merge({ tweaks = { a = 1 }, options = { g = true } }, { tweaks = R({ a = 2 }), keyboard = R({ k = 1 }) }, {}, {}, true, true)
	check("first sync with own settings: a conflict, the rest merges", plan.conflicts[1] == "tweaks" and #plan.conflicts == 1 and plan.take.keyboard and plan.keep.options)
	plan = Sync.Merge({ tweaks = { a = 1 } }, { tweaks = R({ a = 2 }) }, {}, {}, true, false)
	check("first sync without own settings takes R silently", plan.take.tweaks and not plan.conflicts[1] and not plan.both.tweaks)
	check("own settings: bindings, touch buttons or rings", Sync.HasOwn({ ["b:A-R:054c/0ce6"] = { FB = { T = "spell:1" } } }) and Sync.HasOwn({ rings = { list = { { id = 1 } } } }))
	check("own settings: tweaks, options or a device that differ from the defaults", Sync.HasOwn({ tweaks = { a = true } }) and Sync.HasOwn({ options = { glyphs = false, toggleKey = "PADSOCIAL" } }) and Sync.HasOwn({ ["dev:054c/0ce6"] = { raw = {}, roles = { L1 = "rightmod" }, face = {} } }))
	check("defaults are not own settings", not Sync.HasOwn({ tweaks = {}, options = { glyphs = true, toggleKey = "PADSOCIAL" }, setup = { onboarded = { x = true } }, rings = { list = {} }, ["t:A-R"] = { bars = { left = {} } }, ["dev:054c/0ce6"] = { raw = {}, roles = {}, face = {} } }))
end

---------------------------------------------------------------------------------------------------------------------
-- Sections: what syncs, slim and fat

do
	local m = machine(settingsA())
	m.login()
	local Sync, db = m.ns.Sync, m.ns.db
	local s = Sync.Sections(db, {})
	local text = Sync.Encode(s)
	check("debug, the debug log and What's new don't sync", s.options.debug == nil and not text:find("a line") and not text:find("1%.4%.0"))
	check("ringLast, shadow, registries and highest don't sync", not text:find("ringLast") and not text:find("shadow") and not text:find("macros") and not text:find("highest"))
	check("learned words and blocked boxes don't sync", not text:find("dictionary") and not text:find("hello") and not text:find("suggest") and not text:find("blocked"))
	check("Rings' saved stick CVar doesn't sync", s.rings.axisSaved == nil and s.rings.marker == false)
	check("quick messages sync", s.keyboard.phrases.anywhere[1] == "hi all")
	check("all section kinds", s.options and s.tweaks and s.rings and s.keyboard and s.setup and s["dev:054c/0ce6"] and s["b:Ann-Realm:054c/0ce6"] and s["t:Ann-Realm"])
	local cells = s["b:Ann-Realm:054c/0ce6"]
	check("slim entries keep the id and flags", cells.FB.R.id == "spellgroup:Holy Light" and cells.FB.R.healer and cells.FB.R.healerLast and cells.FB.R.name == nil and cells.FB.R.kind == nil)
	check("a plain slim entry is its id", cells.DR.T == "ring:1" and s.rings.list[1].slots[1] == "spell:20271")
	check("a kind the id doesn't say is kept", s["t:Ann-Realm"].bars.left[1].T.kind == "game")
	check("no empty bindings section until it synced once", Sync.Sections({ chars = { X = { cells = { ["054c/0ce6"] = {} } } } }, {})["b:X:054c/0ce6"] == nil and Sync.Sections({ chars = { X = { cells = { ["054c/0ce6"] = {} } } } }, { ["b:X:054c/0ce6"] = "{}" })["b:X:054c/0ce6"] ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Two machines: A writes, a fresh B takes everything before the take-back

account = {}
local A = machine(settingsA())
A.login()
check("A settles at login", A.settled == 1 and A.ns.Sync.Settled())
run(6)
check("A wrote its settings into sync macros", ourMacros() >= 1, ourMacros())
check("A's macros are account macros with the note icon", account[1].icon == "INV_Misc_Note_01" and account[1].name == "FCT:Sync 1")
check("A's status is up to date", A.ns.Sync.Status().state == "ok", A.ns.Sync.Status().state)
check("in step: the take-back may free slots other machines placed", A.ns.Sync.InStep())
local partsA = ourMacros()

local B = machine({})
local settledBefore
B.ns.On("FCT_SYNC_SETTLED", function() settledBefore = B.ns.db.chars and B.ns.db.chars["Ann-Realm"] and B.ns.db.chars["Ann-Realm"].cells end)
B.login()
local bdb = B.ns.db
local bcell = bdb.chars["Ann-Realm"].cells["054c/0ce6"].FB.R
check("B took the bindings", bcell.id == "spellgroup:Holy Light" and bcell.healer and bcell.healerLast)
check("the bindings are applied before FCT_SYNC_SETTLED", settledBefore ~= nil)
check("B rebuilt names and icons from its catalog", bcell.name == "Holy Light" and bcell.icon == "icon-holy" and bcell.kind == "spellgroup", bcell.name)
check("B took rings, touch, tweaks, keyboard, layout, setup", bdb.rings.list[1].slots[3].name == "Backpack" and bdb.chars["Ann-Realm"].touch.bars.left[1].T.kind == "game" and bdb.tweaks.lightBar == "class" and bdb.keyboard.phrases.anywhere[1] == "hi all" and bdb.devices["054c/0ce6"].roles.L1 == "rightmod" and bdb.onboarded["054c/0ce6"])
check("B kept its own debug switch and learned words", bdb.options.debug == false and bdb.keyboard.dictionary == nil)
check("B took nothing local from A", bdb.chars["Ann-Realm"].ringLast == nil and bdb.chars["Ann-Realm"].shadow == nil and bdb.macros == nil and bdb.news == nil)
check("B said what it synced", B.ns and (function() for _, line in ipairs(W.lines) do if line:find("Synced from Mac · DualSense Wireless Controller") then return true end end end)())
check("B's layout changed once applied", B.layout > 0)
local before = creates + edits
run(40)
check("B agrees with the macros: nothing more is written", creates + edits == before and ourMacros() == partsA, creates + edits - before)

---------------------------------------------------------------------------------------------------------------------
-- A change on B goes out and is stamped only where it changed; A takes it at its next login

W.server = W.server + 100
bdb.tweaks.sellJunk = false
B.ns.Sync.Check()
run(1)
local bs = bdb.sync
check("only the changed section is stamped", bs.stamps.tweaks == W.server and bs.stamps.options ~= W.server)
local A2 = machine(A.db)
A2.login()
check("A took B's tweaks at its next login", A2.ns.db.tweaks.sellJunk == false)
check("A's rule-4 take is not a conflict line", not (function() for _, line in ipairs(W.lines) do if line:find("changed on both computers") then return true end end end)())

---------------------------------------------------------------------------------------------------------------------
-- Both change the same section offline: the newer stamp wins, the loser is kept, Undo puts it back

-- B changes it with sync off and quits (stamped then); A changes it later and writes.
W.server = W.server + 100
local B1 = machine(B.db)
B1.login()
B1.ns.Sync.SetOn(false)
B1.ns.db.tweaks.lightBar = "off"
B1.fire("PLAYER_LOGOUT")
W.server = W.server + 100
A2.ns.db.tweaks.lightBar = "custom"
A2.ns.Sync.Check(true)
run(1)
W.server = W.server + 100
local B2 = machine(B.db)
B2.login()
B2.ns.Sync.SetOn(true)
run(1)
check("A's newer copy won on B", B2.ns.db.tweaks.lightBar == "custom", B2.ns.db.tweaks.lightBar)
check("the conflict line was said", (function() for _, line in ipairs(W.lines) do if line:find("Tweaks changed on both computers") or line:find("tweaks changed on both computers") then return true end end end)())
check("B's copy is in the backup", B2.db.sync.backup and B2.db.sync.backup.s.tweaks.d.lightBar == "off")
B2.ns.Sync.Undo()
run(1)
check("Undo put B's copy back", B2.ns.db.tweaks.lightBar == "off" and not B2.db.sync.backup)

---------------------------------------------------------------------------------------------------------------------
-- First sync on a machine with its own settings asks once; nothing is applied or written until then

do
	local own = settingsA()
	own.tweaks.lightBar = "game"
	own.chars["Ann-Realm"].cells["054c/0ce6"].FB.R = { id = "spell:20271", name = "Judgement", icon = "icon-judgement", kind = "spell" }
	local writes = creates + edits + deletes
	local C = machine(own)
	local asked = 0
	C.ns.On("FCT_SYNC_CHOICE", function() asked = asked + 1 end)
	C.login()
	run(40)
	local choice = C.ns.Sync.Choice()
	check("the first sync asks", asked == 1 and choice and choice.host == "Mac · DualSense Wireless Controller" and #choice.conflicts >= 2)
	check("waiting: not settled, the take-back waits", not C.ns.Sync.Settled() and C.settled == 0)
	check("waiting: nothing applied", C.ns.db.tweaks.lightBar == "game")
	check("waiting: nothing written", creates + edits + deletes == writes)
	check("waiting: the status says so", C.ns.Sync.Status().state == "choice")
	check("waiting for the choice: not in step", not C.ns.Sync.InStep())
	C.ns.Sync.Choose(true)
	run(1)
	check("Use synced applied the other copy", C.ns.db.tweaks.lightBar ~= "game" and C.ns.db.chars["Ann-Realm"].cells["054c/0ce6"].FB.R.id == "spellgroup:Holy Light")
	check("Use synced kept this machine's copy for Undo", C.db.sync.backup and C.db.sync.backup.s.tweaks.d.lightBar == "game")
	check("settled after the choice", C.ns.Sync.Settled() and C.settled == 1)

	local mine = settingsA()
	mine.tweaks.lightBar = "game"
	local D = machine(mine)
	D.login()
	D.ns.Sync.Choose(false)
	run(40)
	check("Keep mine keeps this machine's copy", D.ns.db.tweaks.lightBar == "game")
	local E = machine({})
	E.login()
	check("Keep mine wrote it out for the others", E.ns.db.tweaks.lightBar == "game", E.ns.db.tweaks.lightBar)
end

---------------------------------------------------------------------------------------------------------------------
-- Damaged, deleted, the player's own FCT:Sync 3, a full list, a newer format

do
	-- A body edited by hand: corrupt, local kept, written again.
	local saved = {}
	for i, macro in ipairs(account) do saved[i] = { name = macro.name, icon = macro.icon, body = macro.body } end
	for _, macro in ipairs(account) do
		if macro.name == "FCT:Sync 1" then macro.body = macro.body:sub(1, 40) .. (macro.body:sub(41, 41) == "0" and "1" or "0") .. macro.body:sub(42) end
	end
	-- A machine that synced before (a base): its copy replaces the damaged set.
	local F = machine(settingsA())
	F.db.tweaks.lightBar = "mine"
	F.db.sync = { base = { setup = "{}" } }
	F.login()
	check("a damaged set is corrupt: local kept, settled", F.ns.db.tweaks.lightBar == "mine" and F.ns.Sync.Settled() and F.ns.Sync.Status().state == "corrupt")
	W.lines = {}
	run(6)
	check("a damaged set is written again, once said", F.ns.Sync.Status().state == "ok" and #W.lines >= 1 and W.lines[#W.lines]:find("written again"), W.lines[#W.lines])
	local G = machine({})
	G.login()
	check("the rewritten set reads", G.ns.db.tweaks.lightBar == "mine")

	-- A missing part: the newest gen is incomplete, an older complete set doesn't exist either.
	for i = #account, 1, -1 do if account[i].name == "FCT:Sync 1" then table.remove(account, i) end end
	local H = machine({})
	H.login()
	check("a missing part counts as corrupt", H.ns.Sync.Status().state == "corrupt" and H.ns.db.tweaks == nil)

	-- The player's own FCT:Sync 3 with another body: never touched, our parts skip 3.
	account = { { name = "FCT:Sync 3", icon = "x", body = "/say mine" } }
	local big = settingsA()
	for i = 1, 40 do big.chars["Ann-Realm"].cells["054c/0ce6"]["K" .. i] = { T = { id = "spell:" .. (1000 + i), name = "S" .. i } } end
	local J = machine(big)
	J.login()
	run(6)
	local three, names = nil, {}
	for _, macro in ipairs(account) do
		if macro.name == "FCT:Sync 3" then three = macro.body end
		names[macro.name] = true
	end
	check("the player's FCT:Sync 3 is untouched", three == "/say mine")
	check("our parts skip 3", names["FCT:Sync 4"] and names["FCT:Sync 2"] and ourMacros() >= 3, ourMacros())
	local K = machine({})
	K.login()
	check("parts are read by body, not by number", K.ns.db.chars["Ann-Realm"].cells["054c/0ce6"].K40.T.id == "spell:1040")

	-- A full list: no partial write, the pause says how many to free.
	account = {}
	for i = 1, 119 do account[i] = { name = "M" .. i, icon = "x", body = "/say " .. i } end
	local before = creates
	local M = machine(big)
	M.login()
	run(6)
	local status = M.ns.Sync.Status()
	check("a full list writes nothing", creates == before and ourMacros() == 0)
	check("a full list pauses with what it needs", status.state == "full" and status.need and status.need >= 1, status.state)
	for i = 1, 30 do table.remove(account) end
	M.ns.Sync.Now()
	run(1)
	check("Sync now retries a full pause", M.ns.Sync.Status().state == "ok" and ourMacros() >= 2, M.ns.Sync.Status().state)
	local players = 0
	for _, macro in ipairs(account) do if macro.name:find("^M%d+$") then players = players + 1 end end
	check("the player's macros are never deleted", players == 89)

	-- A newer format on the server: no apply, no write.
	account = { { name = "FCT:Sync 1", icon = "x", body = "#FCT2 1/1 abcdef XYZ" } }
	local writes = creates + edits + deletes
	local N = machine(settingsA())
	N.login()
	run(40)
	check("a newer format pauses: no write", creates + edits + deletes == writes and N.ns.Sync.Status().state == "newer")
	check("a newer format still settles the take-back", N.ns.Sync.Settled())
	account = saved
end

---------------------------------------------------------------------------------------------------------------------
-- Off, release

do
	local off = settingsA()
	off.sync = { on = false }
	local writes = creates + edits + deletes
	local P = machine(off)
	P.login()
	P.ns.db.tweaks.sellJunk = false
	P.ns.Sync.Check(true)
	run(40)
	P.ns.Sync.SetOn(true)
	check("on again here", P.ns.db.sync.on == nil)
	P.ns.Sync.SetOn(false)
	check("off again here", P.ns.db.sync.on == false)
	check("off: settled, no read, no write", P.ns.Sync.Settled() and creates + edits + deletes == writes and P.ns.Sync.Status().state == "off")
	check("off: not in step", not P.ns.Sync.InStep())
	account[#account + 1] = { name = "FCT:Sync 9", icon = "x", body = "/say mine" }
	local Q = machine(settingsA())
	Q.login()
	local count = Q.ns.Sync.Release()
	check("release deletes our sync macros only", count >= 1 and ourMacros() == 0 and account[#account].body == "/say mine")
	check("release turns sync off here", Q.ns.db.sync.on == false)
end

---------------------------------------------------------------------------------------------------------------------
-- Export and import

do
	account = {}
	local X = machine(settingsA())
	X.login()
	local text, held = X.ns.Sync.Export()
	check("an export starts FCT1:", text and text:find("^FCT1:"))
	local plain = C_EncodingUtil.DecodeBase64(text:sub(6))
	check("no character or realm name in an export", not plain:find("Ann") and not plain:find("Realm"))
	check("an export holds this pad's bindings and the layout", held.bindings.FB.R.healer and held.layout.roles.L1 == "rightmod" and held.layout.raw == nil)
	check("a bad prefix is bad", select(2, X.ns.Sync.ReadExport("hello")) == "bad" and select(2, X.ns.Sync.ReadExport("FCT1:00ZZ")) == "bad")
	check("a newer export is newer", select(2, X.ns.Sync.ReadExport("FCT2:ABCD")) == "newer")
	local spaced = text:sub(1, 30) .. "\n  " .. text:sub(31, 300) .. "\t" .. text:sub(301)
	local payload = X.ns.Sync.ReadExport(spaced)
	check("whitespace anywhere is ignored", payload and payload.kind == "export")
	local rows = X.ns.Sync.Preview(payload)
	local allSame = true
	for _, row in ipairs(rows) do allSame = allSame and row.same end
	check("an export previews as no change on its own machine", #rows == 7 and allSame)

	local Y = machine({ version = 2, chars = { ["Ann-Realm"] = { cells = { ["054c/0ce6"] = { FT = { T = { id = "spell:9", name = "Nine" } } } } } }, devices = { ["054c/0ce6"] = { raw = { L1 = 3 }, roles = {}, face = {} } } })
	Y.login()
	rows = Y.ns.Sync.Preview(payload)
	local byId = {}
	for _, row in ipairs(rows) do byId[row.id] = row end
	check("preview counts changed buttons", byId.bindings.count == 3 and not byId.bindings.same, byId.bindings.count)
	check("preview counts rings", byId.rings.rings == 1 and byId.rings.yours == 0)
	check("preview counts the layout", byId.layout.count == 2, byId.layout.count)
	Y.ns.Sync.Import(payload, { "bindings", "layout", "rings" })
	run(1)
	local ydb = Y.ns.db
	check("import replaced the ticked parts", ydb.chars["Ann-Realm"].cells["054c/0ce6"].FB.R.id == "spellgroup:Holy Light" and ydb.chars["Ann-Realm"].cells["054c/0ce6"].FT == nil and ydb.rings.list[1].name == "Ring 1" and ydb.devices["054c/0ce6"].roles.L1 == "rightmod")
	check("import kept the raw learn data", ydb.devices["054c/0ce6"].raw.L1 == 3)
	check("import left unticked parts alone", ydb.tweaks == nil)
	check("import keeps the replaced parts for Undo", ydb.sync.backup and ydb.sync.backup.s["b:Ann-Realm:054c/0ce6"].d.FT.T == "spell:9")
	Y.ns.Sync.Undo()
	run(1)
	check("Undo after an import puts the old bindings back", ydb.chars["Ann-Realm"].cells["054c/0ce6"].FT.T.id == "spell:9" and ydb.chars["Ann-Realm"].cells["054c/0ce6"].FB == nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Copy bindings from another pad

do
	account = {}
	local data = settingsA()
	local Z = machine(data, { pad = "045e/0b13", padName = "Xbox Wireless Controller" })
	Z.login()
	Z.db.sync.pads["054c/0ce6"] = "DualSense Wireless Controller"
	local key, name = Z.ns.Sync.OtherPad()
	check("another pad with bindings is offered", key == "054c/0ce6" and name == "DualSense Wireless Controller")
	Z.ns.Sync.CopyFrom(key)
	run(1)
	local cells = Z.ns.db.chars["Ann-Realm"].cells
	check("its bindings are copied onto this pad", cells["045e/0b13"].FB.R.id == "spellgroup:Holy Light" and cells["054c/0ce6"].FB.R.id == "spellgroup:Holy Light")
	check("nothing is offered once this pad has bindings", Z.ns.Sync.OtherPad() == nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Review fixes (2026-11-21): no write over a set this machine hasn't merged

local function remoteTweaks()
	local m = machine({})
	local remote = m.ns.Sync.ReadRemote()
	return remote and remote.s.tweaks and remote.s.tweaks.d
end

do
	-- 1: a forced read while the list reads empty must not write over the server's set.
	account = {}
	local A = machine(settingsA())
	A.login()
	run(6)
	check("review 1: A's set is on the server", remoteTweaks() and (remoteTweaks() or {}).lightBar == "class")
	W.hidden = true
	local B = machine({})
	B.fire("ADDON_LOADED", "ForeverControllerTweaks")
	B.fire("PLAYER_LOGIN")
	B.fire("PLAYER_ENTERING_WORLD")
	run(5)
	check("follow-up 1: not settled while it may still arrive", not B.ns.Sync.Settled())
	W.lines = {}
	B.ns.Sync.Now()
	check("follow-up 2: Sync now says it's waiting for the macro list", W.lines[#W.lines] and W.lines[#W.lines]:find("waiting for the macro list"), W.lines[#W.lines])
	run(35)
	check("follow-up 1: settled after the wait, so the take-back runs", B.ns.Sync.Settled() and B.settled == 1)
	W.hidden = false
	check("review 1: nothing written while the list read empty", (remoteTweaks() or {}).lightBar == "class")
	B.fire("UPDATE_MACROS")
	run(40)
	check("review 1: the list's arrival reads again and merges", B.ns.db.tweaks and B.ns.db.tweaks.lightBar == "class", B.ns.db.tweaks and B.ns.db.tweaks.lightBar)
	check("review 1: the server set survived", (remoteTweaks() or {}).lightBar == "class")

	-- 5: a set written by another session after this one merged is merged before writing.
	W.server = W.server + 100
	local C = machine(settingsA())
	C.login()
	run(40)
	local A2 = machine(A.db)
	A2.login()
	W.server = W.server + 100
	A2.ns.db.tweaks.lightBar = "custom"
	A2.ns.Sync.Check(true)
	run(1)
	W.server = W.server + 100
	C.ns.db.options.glyphs = false
	C.ns.Sync.Check(true)
	run(1)
	check("review 5: the other session's change was merged, not overwritten", (remoteTweaks() or {}).lightBar == "custom" and C.ns.db.tweaks.lightBar == "custom", (remoteTweaks() or {}).lightBar)
	local m = machine({})
	local remote = m.ns.Sync.ReadRemote()
	check("review 5: this session's change went out too", remote and remote.s.options and remote.s.options.d.glyphs == false)

	-- 2: a damaged set and a fresh machine: nothing is written until the player asks.
	for _, macro in ipairs(account) do
		if macro.name == "FCT:Sync 1" then macro.body = macro.body:sub(1, 40) .. (macro.body:sub(41, 41) == "0" and "1" or "0") .. macro.body:sub(42) end
	end
	local damagedBodies = {}
	for i, macro in ipairs(account) do damagedBodies[i] = macro.body end
	local D = machine({})
	D.login()
	run(40)
	local same = true
	for i, macro in ipairs(account) do same = same and macro.body == damagedBodies[i] end
	check("review 2: a fresh machine doesn't push its defaults over a damaged set", same and D.ns.Sync.Status().state == "corrupt")
	check("follow-up 3: the status says it isn't written again by itself", D.ns.Sync.Status().rewriting == false)
	D.ns.Sync.Now()
	run(1)
	check("review 2: Sync now writes it on request", D.ns.Sync.Status().state == "ok" and machine({}).ns.Sync.ReadRemote() ~= nil)

	-- 3: a newer pause from an earlier session clears once the server no longer holds a newer set.
	account = { { name = "Mine", icon = "x", body = "/say mine" } }
	local stale = settingsA()
	stale.sync = { paused = "newer" }
	local E = machine(stale)
	E.login()
	run(6)
	check("review 3: a stale newer pause clears", E.ns.Sync.Status().state == "ok" and ourMacros() >= 1, E.ns.Sync.Status().state)
	account = { { name = "FCT:Sync 1", icon = "x", body = "#FCT2 1/1 abcdef XYZ" } }
	local G = machine(settingsA())
	G.login()
	check("review 3: newer pauses", G.ns.Sync.Status().state == "newer")
	check("paused: not in step", not G.ns.Sync.InStep())
	account = {}
	G.ns.Sync.Now()
	run(1)
	check("review 3: Sync now reads again and clears it", G.ns.Sync.Status().state == "ok", G.ns.Sync.Status().state)

	-- 4: a change made while sync was off keeps its time: it wins over an older change from the other machine.
	account = {}
	W.server = W.server + 100
	local H = machine(settingsA())
	H.login()
	run(6)
	local K = machine(settingsA())
	K.login()
	run(40)
	K.ns.Sync.SetOn(false)
	W.server = W.server + 100
	local H2 = machine(H.db)
	H2.login()
	H2.ns.db.tweaks.lightBar = "older"
	H2.ns.Sync.Check(true)
	run(1)
	W.server = W.server + 100
	K.ns.db.tweaks.lightBar = "newer"
	K.fire("PLAYER_LOGOUT")
	W.server = W.server + 100
	local K2 = machine(K.db)
	K2.login()
	K2.ns.Sync.SetOn(true)
	run(40)
	check("review 4: the change made while off is the newer one", K2.ns.db.tweaks.lightBar == "newer" and (remoteTweaks() or {}).lightBar == "newer", K2.ns.db.tweaks.lightBar)

	-- 6: Keep mine keeps the other copy for Undo.
	account = {}
	local P = machine(settingsA())
	P.login()
	run(6)
	local mine = settingsA()
	mine.tweaks.lightBar = "mine"
	local Q = machine(mine)
	Q.login()
	Q.ns.Sync.Choose(false)
	run(1)
	check("review 6: Keep mine backs up the other copy", Q.db.sync.backup and Q.db.sync.backup.s.tweaks and Q.db.sync.backup.s.tweaks.d.lightBar == "class")
	Q.ns.Sync.Undo()
	run(1)
	check("review 6: Undo after Keep mine takes the other copy", Q.ns.db.tweaks.lightBar == "class")

	-- 7: an export is untrusted: wrong shapes are refused, not crashed on.
	local R = machine({})
	R.login()
	local Sync = R.ns.Sync
	local function export(s) return "FCT1:" .. Sync.Pack({ v = 1, db = 2, kind = "export", at = 1, s = s }) end
	local okRun, read = pcall(function()
		local out = {}
		for _, s in ipairs({ { rings = 5 }, { rings = { list = 5 } }, { bindings = { FB = 3 } }, { layout = { roles = "x" } }, { tweaks = "x" }, { touch = { bars = 1 } }, { bindings = { FB = { T = { id = 4 } } } } }) do
			local payload = Sync.ReadExport(export(s))
			if payload then Sync.Preview(payload) end
			out[#out + 1] = payload == nil
		end
		return out
	end)
	local allBad = okRun
	for _, bad in ipairs(okRun and read or {}) do allBad = allBad and bad end
	check("review 7: malformed exports are refused without an error", allBad, okRun and "accepted" or read)
	check("review 7: a good export still reads", Sync.ReadExport(export({ tweaks = { a = true }, rings = { list = { { id = 1, slots = { "spell:1" } } } } })) ~= nil)

	-- 10: the gen stays 6 letters well past 2038, so every body stays within 255.
	local later = Sync.Bodies(string.rep("A", 236 * 20), 2300000000)
	local longest = 0
	for _, body in ipairs(later) do longest = math.max(longest, #body) end
	check("review 10: bodies fit in 2042", longest <= 255, longest)
end

---------------------------------------------------------------------------------------------------------------------
-- Placed slots (p:<Name-Realm>, Actions.lua's list of the bars 6-8 slots the addon placed on any machine): the union per
-- slot, the newer entry wins, no removals carried, never a first-sync question

do
	local m = machine({})
	local Sync, E = m.ns.Sync, m.ns.Sync.Encode
	local function R(d, t) return { d = d, t = t or 0 } end
	local K = "p:Ann-Realm"
	local mine = { [150] = { holds = "spell:1", at = 10 }, [151] = { holds = "spell:2", at = 5 } }
	local theirs = { [150] = { holds = "spell:9", at = 20 }, [152] = { holds = "macro:FCT:Bags", at = 3 } }
	local plan = Sync.Merge({ [K] = mine }, { [K] = R(theirs) }, {}, {}, false, false)
	local got = plan.take[K]
	check("placed: the union of both, the newer entry per slot", got and plan.merged[K] and got[150].holds == "spell:9" and got[151].holds == "spell:2" and got[152].holds == "macro:FCT:Bags")
	plan = Sync.Merge({ [K] = mine }, { [K] = R({ [150] = { holds = "spell:9", at = 10 } }) }, {}, {}, false, false)
	check("placed: a tie keeps this machine's entry", plan.keep[K] and not plan.take[K])
	plan = Sync.Merge({ [K] = { [150] = mine[150] } }, { [K] = R(mine) }, {}, {}, false, false)
	check("placed: R holds all of L: taken as it is", plan.take[K] and not plan.merged[K])
	plan = Sync.Merge({ [K] = mine }, { [K] = R({ [151] = mine[151] }) }, { [K] = E(mine) }, {}, false, false)
	check("placed: an entry R lacks isn't a removal", plan.keep[K] and not plan.take[K])
	plan = Sync.Merge({ [K] = mine }, { [K] = R(theirs) }, {}, {}, true, true)
	check("placed: a first sync with own settings never asks about it", not plan.conflicts[1] and plan.take[K])
	check("placed: not own settings", not Sync.HasOwn({ [K] = mine }))
	check("placed: a section once the list has entries", Sync.Sections({ chars = { ["Ann-Realm"] = { placed = mine } } }, {})[K] ~= nil and Sync.Sections({ chars = { ["Ann-Realm"] = { placed = {} } } }, {})[K] == nil)
end

-- Two machines: each placed its own slot; both lists end up with both slots. Earlier machines' timers stop here.
account, W.timers, W.tickers = {}, {}, {}
local PA = machine({ version = 2, chars = { ["Ann-Realm"] = { placed = { [150] = { holds = "spell:1", at = W.server } } } } })
PA.login()
run(6)
local PB = machine({ version = 2, chars = { ["Ann-Realm"] = { placed = { [160] = { holds = "spell:2", at = W.server } } } } })
PB.login()
local pb = PB.ns.db.chars["Ann-Realm"].placed
check("placed: B has A's slot and its own after the login", pb[150] and pb[150].holds == "spell:1" and pb[160] and pb[160].holds == "spell:2")
check("placed: never in the backup (no Undo for it)", not (PB.ns.db.sync.backup and PB.ns.db.sync.backup.s["p:Ann-Realm"]))
run(40)
local PA2 = machine(PA.db)
PA2.login()
local pa = PA2.ns.db.chars["Ann-Realm"].placed
check("placed: B wrote the union; A has both at its next login", pa[150] and pa[160] and pa[160].holds == "spell:2")
-- A damaged list from the macros is left out; the rest still merges.
do
	local payload = { v = 1, db = 2, at = W.server + 500, by = "zzzzzz", host = "PC", s = { ["p:Ann-Realm"] = { t = 1, d = { [150] = { holds = 5 } } }, tweaks = { t = 1, d = { sellJunk = true } } } }
	account = {}
	for i, body in ipairs(PA2.ns.Sync.Bodies(PA2.ns.Sync.Pack(payload), payload.at)) do account[i] = { name = "FCT:Sync " .. i, icon = "INV_Misc_Note_01", body = body } end
	local remote = PA2.ns.Sync.ReadRemote()
	check("placed: a bad entry drops the section on read", remote and remote.s["p:Ann-Realm"] == nil and remote.s.tweaks ~= nil)
	payload.s["p:Ann-Realm"].d = { [150] = { holds = "macro:Mine", body = "/say hi", at = 1 } }
	account = {}
	for i, body in ipairs(PA2.ns.Sync.Bodies(PA2.ns.Sync.Pack(payload), payload.at)) do account[i] = { name = "FCT:Sync " .. i, icon = "INV_Misc_Note_01", body = body } end
	remote = PA2.ns.Sync.ReadRemote()
	check("placed: no macro bodies in the list", remote and remote.s["p:Ann-Realm"] == nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Repair

do
	local R = machine({})
	local Sync = R.ns.Sync
	local fixes = {}
	local db = { sync = { on = "yes", id = 5, base = { a = 1, b = "x" }, stamps = { a = "x", b = 0 / 0, c = 3 }, marks = "no", pads = { k = "Pad", j = 3 }, last = { at = "x" }, wrote = { at = 5 }, backup = { at = 1, s = { k = 3 } }, paused = "weird", need = "two" } }
	local s = Sync.Repair(db, function(what) fixes[#fixes + 1] = what end)
	check("repair: on is nil or false", s.on == nil)
	check("repair: a machine id is made", type(s.id) == "string" and #s.id == 6)
	check("repair: maps keep only good entries", s.base.b == "x" and s.base.a == nil and s.stamps.c == 3 and s.stamps.a == nil and s.stamps.b == nil and next(s.marks) == nil and s.pads.k == "Pad" and s.pads.j == nil)
	check("repair: bad status and backup go", s.last == nil and s.wrote.at == 5 and s.backup == nil and s.paused == nil and s.need == nil)
	check("repair: every fix is reported", #fixes >= 8, #fixes)
	local again = Sync.Repair({ sync = "broken" })
	check("repair: a non-table becomes a fresh state", type(again.base) == "table" and again.on == nil)
end

out(string.format("sync_spec: %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
