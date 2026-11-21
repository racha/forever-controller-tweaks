-- Forever Controller Tweaks sync (design/sync.md): the settings follow the account in account macros "FCT:Sync 1..n",
-- read at login and written when they change; and the codec of /fct export and /fct import.
--
-- Sections (design 3.1), each one unit with its own server-time stamp (nothing inside a section is merged): options
-- (the ring marker in it), tweaks, keyboard, setup, dev:<pad> (a controller's hardware), cp:<GUID> (the character's
-- profiles and the one it plays on: { profiles = { [id] = { name, roles, face } }, profile }), b:<GUID>:<profile id>
-- (bindings), t:<GUID> (the touch bars' layout), tb:<GUID>:<profile id> (touch buttons, { bars = { left, right } }),
-- r:<GUID> (the character's rings; met for the first time, the union of both by ring id); and one merged per entry
-- (the union, the newer entry wins): p:<GUID>, the bars 6-8 slots the addon placed on any machine (Actions.lua).
-- 1.5.1-1.5.3's account profiles (prof:<id>) and per-controller picks (map) are never read or written. Local or
-- derived state never syncs: the debug log, the macro registries and shadow records (which
-- cell holds which slot; the take-back rebuilds them), ringLast and the healer last target, What's new, the keyboard's
-- learned words, Rings' saved stick CVar.
-- Wire: a sorted-key text form (CBOR's map order isn't stable, and the base comparisons need one string per state),
-- C_EncodingUtil Zlib (its Adler-32 makes an edited or cut payload fail) and Base64, cut into account macro bodies
-- "#FCT1 <part>/<total> <gen> <data>" of at most 255 letters. A "#" line is a metacommand: pressed, the macro does
-- nothing. Entries go slim (their id and flags; name and icon come back from the catalog).
-- State, this machine only: ns.db.sync = { on (nil = on, false = off here), id, base, stamps, marks, last, wrote,
-- backup, paused, need, pads }. base[key] is the section as this machine and the macros last agreed on it.
-- Merge per section at login (design 4): R absent: keep L; L absent or empty and never synced: take R; equal: agree;
-- L == base: take R; R == base: keep L; both changed: the newer stamp wins (a tie keeps L); p: takes the union
-- of both (it goes out again when it differs from R) and never ask. A first sync on a machine
-- with its own bindings or rings asks once (Sync.Choice, the panel's dialog). Replaced sections go to backup (Undo).
-- Writes and applies run out of combat with the pad free (ns.whenPadFree), never while a ring is open, a slot write
-- runs or the Macros window is shown, at most every 30 s, and only whole sets: free slots are counted first.
-- Messages: FCT_SYNC_SETTLED (once a session: the login read is done; the take-back waits for it),
-- FCT_SYNC_CHANGED (status changed: the panel redraws), FCT_SYNC_CHOICE (the first-sync question is due).
local _, ns = ...
local Sync = {}
ns.Sync = Sync

local L = {
	SYNC_MAC = "Mac", SYNC_WINDOWS = "Windows", SYNC_PC = "PC",
	SYNC_TODAY = "Today %s", SYNC_YESTERDAY = "Yesterday %s",
	SYNC_GOT = "Synced from %s (%s): %s.",
	SYNC_BOTH = "%s changed on both computers: kept the newer one from %s (%s). Settings → Undo last sync brings yours back.",
	SYNC_REWROTE = "The sync macros were missing or damaged: written again from this computer.",
	SYNC_LINE_FULL = "Sync is waiting: free %d account macros (Esc → Macros).",
	SYNC_LINE_NEWER = "Sync is paused: another computer has a newer Controller Tweaks. Update the addon here.",
	SYNC_LINE_BIG = "Too much to sync (over %d macros). Export still works.",
	SYNC_LINE_OFF = "Sync is off on this computer.",
	SYNC_LINE_ON = "Sync is on.",
	SYNC_LINE_STATUS = "Sync %s · last %s from %s · %d macros",
	SYNC_LINE_NONE = "No sync macros found yet: this computer's settings go out after the next change.",
	SYNC_LINE_NEVER = "never",
	SYNC_LINE_WAITING = "Sync is still waiting for the macro list: it reads as soon as the game has loaded it.",
	SYNC_LINE_CHOICE = "Sync is waiting for your choice: Use synced or Keep mine.",
	SYNC_LINE_HELP = "/fct sync: the status; now, on, off, undo.",
	SYNC_UNAVAILABLE = "Sync, export and import need the game's C_EncodingUtil, which this client doesn't have: they are off.",
	SYNC_UNDONE = "Put back: %s.",
	SYNC_NO_UNDO = "Nothing to undo.",
	SYNC_ON_WORD = "on", SYNC_OFF_WORD = "off",
	SYNC_REPAIRED = "repaired %d damaged sync settings", SYNC_REPAIRED_ONE = "repaired 1 damaged sync setting",
	SYNC_THIS = "this computer (%s)",
	IMPORT_DONE = "Imported: %s.",
	SEC = { bindings = "Bindings in this profile", touch = "Touch bars", rings = "Rings", tweaks = "Tweaks", keyboard = "Keyboard", layout = "Profile layout", setup = "Setup guide", options = "Options", device = "Controller setup", profile = "Profiles" },
	-- Sections in chat lines: "bindings, rings".
	SEC_LOWER = { bindings = "bindings", touch = "touch bars", rings = "rings", tweaks = "tweaks", keyboard = "keyboard", layout = "profile layout", setup = "setup guide", options = "options", device = "controller setup", profile = "profiles" },
}
Sync.L = L

-- 2 (1.5.1): profiles. 3 (1.5.2): rings per character (r:), touch buttons per profile (tb:). 4 (1.5.4): profiles per
-- character (cp:), no account profiles or controller picks. An older machine pauses on a newer one ("newer") and writes
-- nothing; a format 2 or 3 set reads here without its account sections (rings, prof:, map) and its name-keyed ones (an
-- older export still imports: its rings go to this character, its touch buttons and layout to this character's
-- profile).
local FORMAT, MAX_PARTS, BODY_MAX = 4, 20, 255
local HEADER = "#FCT%d %d/%d %s "
-- The gen is the write's server time since GEN_EPOCH (2025-01-01) in base36: 6 letters until 2094. The header is
-- then at most 19 letters ("#FCT1 20/20 " and the gen and a space).
local GEN_EPOCH = 1735689600
local DATA = BODY_MAX - 19
local EXPORT_PREFIX = "FCT" .. FORMAT .. ":"
local ICON = "INV_Misc_Note_01"
local NAME = "FCT:Sync %d"
local MACRO_CONSTS = Constants and Constants.MacroConsts or {}
local MAX_ACCOUNT = MACRO_CONSTS.MAX_ACCOUNT_MACROS or 120
local CHECK_DELAY, WRITE_GAP, POLL, LIST_WAIT = 5, 30, 1, 10
local MAX_DEPTH = 24
local PAUSES = { newer = true, full = true, big = true, corrupt = true }
local LOCAL_KEYBOARD = { dictionary = true, suggest = true, blocked = true }
local NONE = {}

local function call(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in pairs(value) do out[key] = copy(item) end
	return out
end
Sync.Copy = copy

local function serverTime() return call(GetServerTime) or 0 end
local function isPad(key) return type(key) == "string" and key:find("^%x%x%x%x/%x%x%x%x$") ~= nil end
local function isId(id) return isPad(id) or type(id) == "string" and id:find("^p%d+$") ~= nil end

-- b:<GUID>:<profile id>: the character and the id, else nil.
local function bindingsKey(key)
	local name, id = key:match("^b:(.+):([^:]+)$")
	if name and isId(id) then return name, id end
end
-- The character a per-character section belongs to (b:, tb:, t:, p:, r:, cp:), else nil.
local function charOfKey(key) return key:match("^t?b:(.+):[^:]+$") or key:match("^[tpr]:(.+)$") or key:match("^cp:(.+)$") end
-- Characters are keyed by GUID since 1.5.2 (Face.lua): 1.5.1's Name-Realm records were shared by every character of
-- that first name. A per-character section under any other key is never read, put or written; the record stays
-- local until its character claims it.
local function isGuid(name) return type(name) == "string" and name:find("^Player%-") ~= nil end
-- 1.5.1's account "rings" section counts as name-keyed too: the rings of the old records were handed out at load
-- (Core.MoveRings) and reach a character only with its claim, never the one that happens to read the set. A pasted
-- export's rings row still goes to this character (Sync.Import puts it as r:<GUID>).
local function nameKeyed(key)
	if key == "rings" then return true end
	local name = charOfKey(key)
	return name ~= nil and not isGuid(name)
end
-- Sections a format 4 machine never reads, puts or writes: the name-keyed ones and 1.5.1-1.5.3's account profiles and
-- per-controller picks (each character carries its own profiles in cp:).
local function dropped(key) return nameKeyed(key) or key == "map" or key:find("^prof:") ~= nil end
Sync.Dropped = dropped
local function finite(value) return type(value) == "number" and value - value == 0 end
local function trimmed(body) return type(body) == "string" and (body:gsub("%s+$", "")) or nil end

---------------------------------------------------------------------------------------------------------------------
-- The text form: s<len>:<bytes>, n<number>;, t, f, {<key><value>...} with keys sorted (numbers first). Anything else
-- (functions, NaN, an infinity) is left out.

local function storable(value)
	local kind = type(value)
	return kind == "string" or kind == "boolean" or kind == "table" or finite(value)
end

local function keyOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta == "number" end
	return a < b
end

local function encode(value, out)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
	elseif kind == "boolean" then
		out[#out + 1] = value and "t" or "f"
	elseif kind == "table" then
		local keys = {}
		for key, item in pairs(value) do
			if (type(key) == "string" or finite(key)) and storable(item) then keys[#keys + 1] = key end
		end
		table.sort(keys, keyOrder)
		out[#out + 1] = "{"
		for _, key in ipairs(keys) do
			encode(key, out)
			encode(value[key], out)
		end
		out[#out + 1] = "}"
	end
end

function Sync.Encode(value)
	local out = {}
	encode(value, out)
	return table.concat(out)
end
local enc = Sync.Encode

local function parse(text, at, depth)
	local tag = text:sub(at, at)
	if tag == "t" then return true, at + 1 end
	if tag == "f" then return false, at + 1 end
	if tag == "s" then
		local digits = text:match("^(%d+):", at + 1)
		local length = tonumber(digits)
		assert(length, "string")
		local from = at + #digits + 2
		local value = text:sub(from, from + length - 1)
		assert(#value == length, "short string")
		return value, from + length
	end
	if tag == "n" then
		local digits = text:match("^([^;]+);", at + 1)
		local value = tonumber(digits)
		assert(finite(value), "number")
		return value, at + #digits + 2
	end
	assert(tag == "{" and depth < MAX_DEPTH, "value")
	local out, pos = {}, at + 1
	while text:sub(pos, pos) ~= "}" do
		local key, value
		key, pos = parse(text, pos, depth + 1)
		assert(type(key) == "string" or type(key) == "number", "key")
		value, pos = parse(text, pos, depth + 1)
		out[key] = value
	end
	return out, pos + 1
end

-- The value, or nil when the text is damaged or has anything after it.
function Sync.Decode(text)
	if type(text) ~= "string" then return end
	local ok, value, after = pcall(parse, text, 1, 0)
	if ok and after == #text + 1 then return value end
end

-- C_EncodingUtil's compress and Base64 (Blizzard_CooldownViewer's chain, CBOR swapped for the text form).
function Sync.Available()
	local E = C_EncodingUtil
	return not not (E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64)
end

local function zlib() return Enum.CompressionMethod and Enum.CompressionMethod.Zlib or 1 end

function Sync.Pack(value)
	if not Sync.Available() then return end
	local E = C_EncodingUtil
	local level = Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize or 2
	local ok, out = pcall(function() return E.EncodeBase64(E.CompressString(enc(value), zlib(), level)) end)
	if ok and type(out) == "string" then return out end
end

function Sync.Unpack(text)
	if not (Sync.Available() and type(text) == "string" and text ~= "") then return end
	local E = C_EncodingUtil
	local ok, plain = pcall(function() return E.DecompressString(E.DecodeBase64(text), zlib()) end)
	local value = ok and Sync.Decode(plain)
	if type(value) == "table" then return value end
end

-- A 32-bit hash of a section's text form: the stamp marks (when the section last changed here).
local function hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return h
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function base36(number)
	local out, n = "", math.floor(number)
	repeat
		local d = n % 36
		out = DIGITS:sub(d + 1, d + 1) .. out
		n = (n - d) / 36
	until n == 0
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Sections. Entries go slim on the wire: the id alone, or a table of the id and its flags (healer, healerLast,
-- native, and kind when the id's prefix doesn't say it); name and icon are display copies, rebuilt on arrival.

local DISPLAY = { name = true, icon = true }

local function slimEntry(entry)
	if type(entry) ~= "table" or type(entry.id) ~= "string" then return nil end
	local out, flags = {}, false
	for key, value in pairs(entry) do
		if not DISPLAY[key] and not (key == "kind" and value == entry.id:match("^(%a+):")) then
			out[key] = copy(value)
			flags = flags or key ~= "id"
		end
	end
	return flags and out or entry.id
end

-- rows[row][slot] = entry, the cells' and a touch side's shape.
local function slimGrid(rows)
	local out = {}
	for row, slots in pairs(type(rows) == "table" and rows or NONE) do
		local kept = {}
		for slot, entry in pairs(type(slots) == "table" and slots or NONE) do kept[slot] = slimEntry(entry) end
		if next(kept) then out[row] = kept end
	end
	return out
end

local function slimSides(sides)
	local out = {}
	for side, list in pairs(type(sides) == "table" and sides or NONE) do out[side] = slimGrid(list) end
	return out
end

-- The layout; buttons only while they wait for a profile (Core.MoveTouchBars) or in an export row.
local function slimTouch(touch)
	local out = copy(touch)
	out.bars = type(touch.bars) == "table" and slimSides(touch.bars) or nil
	return out
end

local function slimRings(rings)
	local list = {}
	for i, ring in ipairs(type(rings.list) == "table" and rings.list or NONE) do
		local out = copy(ring)
		out.slots = {}
		for slot, entry in pairs(type(ring.slots) == "table" and ring.slots or NONE) do out.slots[slot] = slimEntry(entry) end
		list[i] = out
	end
	return { list = list, nextId = rings.nextId }
end

local function hasEntries(rows)
	for _, slots in pairs(type(rows) == "table" and rows or NONE) do
		if type(slots) == "table" and next(slots) then return true end
	end
	return false
end

local function touchHasEntries(touch)
	for _, list in pairs(type(touch) == "table" and type(touch.bars) == "table" and touch.bars or NONE) do
		if hasEntries(list) then return true end
	end
	return false
end

-- Every section of db: key -> plain data (slim). base: a bindings section that was synced once stays in, empty, so
-- clearing every button goes out too.
function Sync.Sections(db, base)
	local out = {}
	base = base or NONE
	if type(db.options) == "table" then
		out.options = copy(db.options)
		out.options.debug = nil
		out.options.ringMarker = db.ringMarker ~= false
	end
	if type(db.tweaks) == "table" then out.tweaks = copy(db.tweaks) end
	if type(db.keyboard) == "table" then
		out.keyboard = copy(db.keyboard)
		for key in pairs(LOCAL_KEYBOARD) do out.keyboard[key] = nil end
	end
	if db.onboarded ~= nil or db.declined ~= nil then out.setup = { onboarded = copy(db.onboarded), declined = copy(db.declined) } end
	for pad, entry in pairs(type(db.devices) == "table" and db.devices or NONE) do out["dev:" .. pad] = copy(entry) end
	for name, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		if not isGuid(name) then char = nil end
		local profiles = type(char) == "table" and type(char.profiles) == "table" and char.profiles
		if profiles and (next(profiles) or base["cp:" .. name]) then
			local list = {}
			for id, profile in pairs(profiles) do list[id] = { name = profile.name, roles = copy(profile.roles), face = copy(profile.face) } end
			out["cp:" .. name] = { profiles = list, profile = char.profile }
		end
		for pad, rows in pairs(type(char) == "table" and type(char.cells) == "table" and char.cells or NONE) do
			local key = "b:" .. name .. ":" .. pad
			if hasEntries(rows) or base[key] then out[key] = slimGrid(rows) end
		end
		if type(char) == "table" and type(char.touch) == "table" then out["t:" .. name] = slimTouch(char.touch) end
		for id, sides in pairs(type(char) == "table" and type(char.touchBars) == "table" and char.touchBars or NONE) do
			local key = "tb:" .. name .. ":" .. id
			local data = { bars = slimSides(sides) }
			if touchHasEntries(data) or base[key] then out[key] = data end
		end
		if type(char) == "table" and (type(char.rings) == "table" or base["r:" .. name]) then out["r:" .. name] = slimRings(type(char.rings) == "table" and char.rings or NONE) end
		if type(char) == "table" and type(char.placed) == "table" and (next(char.placed) or base["p:" .. name]) then out["p:" .. name] = copy(char.placed) end
	end
	return out
end

-- Shapes a section (or an export row) must have before it's merged, previewed or put: sync macros and exports are
-- read from outside, and a player or another addon may have written them.
local function validEntry(entry) return type(entry) == "string" or type(entry) == "table" and type(entry.id) == "string" end

local function validGrid(rows)
	if type(rows) ~= "table" then return false end
	for _, slots in pairs(rows) do
		if type(slots) ~= "table" then return false end
		for _, entry in pairs(slots) do if not validEntry(entry) then return false end end
	end
	return true
end

local function optionalTables(data, fields)
	for _, field in ipairs(fields) do if data[field] ~= nil and type(data[field]) ~= "table" then return false end end
	return true
end

local function validRow(kind, data)
	if kind == "bindings" then return validGrid(data) end
	if type(data) ~= "table" then return false end
	if kind == "placed" then
		for slot, item in pairs(data) do
			if not (finite(slot) and type(item) == "table" and type(item.holds) == "string" and item.body == nil and (item.at == nil or finite(item.at))) then return false end
		end
		return true
	end
	if kind == "touch" then
		if not optionalTables(data, { "bars", "sides" }) then return false end
		for _, list in pairs(data.bars or NONE) do if not validGrid(list) then return false end end
		return true
	end
	if kind == "rings" then
		if not optionalTables(data, { "list" }) then return false end
		for _, ring in pairs(data.list or NONE) do
			if type(ring) ~= "table" or not optionalTables(ring, { "slots" }) then return false end
			for _, entry in pairs(ring.slots or NONE) do if not validEntry(entry) then return false end end
		end
		return true
	end
	if kind == "profile" then
		if not (optionalTables(data, { "profiles" }) and (data.profile == nil or type(data.profile) == "string")) then return false end
		for id, profile in pairs(data.profiles or NONE) do
			if not (isId(id) and type(profile) == "table" and (profile.name == nil or type(profile.name) == "string") and optionalTables(profile, { "roles", "face" })) then return false end
		end
		return true
	end
	if kind == "layout" then return (data.name == nil or type(data.name) == "string") and optionalTables(data, { "roles", "face" }) end
	-- roles and face: format 1.
	if kind == "device" then return optionalTables(data, { "raw", "roles", "face", "detect" }) end
	if kind == "setup" then return optionalTables(data, { "onboarded", "declined" }) end
	return true
end

-- Kinds of section, for chat lines and the status: "bindings", "touch", "device" or the key itself.
local function kindOf(key)
	if key:find("^b:") then return "bindings" end
	if key:find("^r:") then return "rings" end
	if key:find("^t:") or key:find("^tb:") then return "touch" end
	if key:find("^dev:") then return "device" end
	if key:find("^p:") then return "placed" end
	if key:find("^cp:") then return "profile" end
	return key
end
Sync.KindOf = kindOf

-- True for a section with nothing of the player's in it: no bindings, no touch buttons, no rings.
local function empty(key, data)
	if data == nil then return true end
	local kind = kindOf(key)
	if kind == "bindings" then return not hasEntries(data) end
	if kind == "touch" then return not touchHasEntries(data) end
	if kind == "rings" then return not (type(data.list) == "table" and data.list[1]) end
	if kind == "placed" then return next(data) == nil end
	if kind == "profile" then return not (type(data.profiles) == "table" and next(data.profiles)) end
	return false
end

-- What a fresh install has: options, tweaks and keyboard settings as their repairs fill them, a pad with its default
-- raw sources and no roles, face actions or detection.
local function freshDefault(key, data)
	local kind = kindOf(key)
	if kind == "bindings" or kind == "touch" or kind == "rings" then return empty(key, data) end
	-- Bookkeeping, not a setting of the player's.
	if kind == "placed" then return true end
	-- Only Defaults with the game's layout.
	if kind == "profile" then
		for _, profile in pairs(type(data) == "table" and type(data.profiles) == "table" and data.profiles or NONE) do
			if next(profile.roles or NONE) or next(profile.face or NONE) then return false end
		end
		return true
	end
	if kind == "setup" then return true end
	if kind == "options" then
		local options = copy(data)
		if options.ringMarker == true then options.ringMarker = nil end
		return enc(options) == enc({ glyphs = true, toggleKey = "PADSOCIAL" })
	end
	if kind == "tweaks" then
		local T = ns.Tweaks
		if not (T and T.Repair) then return next(data) == nil end
		local fresh = T.Repair({})
		fresh.rumbleGroups, fresh.rumbleStrength = T.RepairRumbleGroups(nil), T.MigrateRumbleStrength(nil)
		return enc(data) == enc(fresh)
	end
	if kind == "keyboard" then
		local K = ns.Keyboard
		if not (K and K.Settings) then return next(data) == nil end
		local fresh = K.Settings({})
		for field in pairs(LOCAL_KEYBOARD) do fresh[field] = nil end
		return enc(data) == enc(fresh)
	end
	if kind == "device" then
		if type(data) ~= "table" or data.detect or data.familyPicked then return false end
		local Layout, pad = ns.Layout, key:match("^dev:(.+)$")
		return not (Layout and Layout.Same and Layout.DefaultsForKey) or Layout.Same(data.raw, Layout.DefaultsForKey(pad).raw)
	end
	return false
end

-- True when any section here differs from a fresh install: a first sync then asks before replacing it.
function Sync.HasOwn(sections)
	for key, data in pairs(sections) do
		if not freshDefault(key, data) then return true end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- Merge (design 4). Pure, for the specs. localS: key -> data; remote: key -> { t, d }; base: key -> text form;
-- stamps: key -> server time; first: no base yet on this machine; own: Sync.HasOwn(localS).
-- Returns { take = { key = data }, agree = { key = text }, keep = { key = true }, conflicts = { key, ... } (a first
-- sync with own settings: the choice decides), both = { key = true } (both changed, R won), merged = { key = true }
-- (taken as the union of both: it goes out again) }.

-- Placed slots per slot: the newer entry (a tie keeps L). Removals aren't carried: a placed entry the slot no longer
-- holds is dropped where it is read (Actions.lua).
-- A character's rings met for the first time (no base yet): both copies came from 1.5.1's one account list, handed
-- out and claimed on each computer on its own, so every ring of either is kept (L's copy of a shared id).
local function ringUnion(L, R)
	local out, have = copy(L or NONE), {}
	out.list = type(out.list) == "table" and out.list or {}
	for _, ring in ipairs(out.list) do have[ring.id] = true end
	for _, ring in ipairs(type(R) == "table" and type(R.list) == "table" and R.list or NONE) do
		if type(ring) == "table" and not have[ring.id] then out.list[#out.list + 1], have[ring.id] = copy(ring), true end
	end
	out.nextId = math.max(tonumber(out.nextId) or 1, tonumber(R and R.nextId) or 1)
	return out
end

local function union(L, R)
	local out = copy(L or NONE)
	for slot, item in pairs(R or NONE) do
		local mine = out[slot]
		if type(item) == "table" and (type(mine) ~= "table" or (tonumber(item.at) or 0) > (tonumber(mine.at) or 0)) then out[slot] = copy(item) end
	end
	return out
end

function Sync.Merge(localS, remote, base, stamps, first, own)
	local plan = { take = {}, agree = {}, keep = {}, conflicts = {}, both = {}, merged = {} }
	local keys = {}
	for key in pairs(localS) do keys[key] = true end
	for key in pairs(remote) do keys[key] = true end
	for key in pairs(keys) do
		local L, R, B = localS[key], remote[key], base[key]
		local ls, rs = L ~= nil and enc(L), R and enc(R.d)
		local joined = R and kindOf(key) == "placed" and union(L, R.d) or R and L ~= nil and B == nil and key:find("^r:") and ringUnion(L, R.d)
		local js = joined and enc(joined)
		if not R then
			plan.keep[key] = true
		elseif joined then
			if js == ls and js == rs then plan.agree[key] = rs
			elseif js == rs then plan.take[key] = R.d
			elseif js == ls then plan.keep[key] = true
			else plan.take[key], plan.merged[key] = joined, true end
		elseif empty(key, L) and B == nil then
			plan.take[key] = R.d
		elseif ls == rs then
			plan.agree[key] = rs
		elseif B ~= nil and ls == B then
			plan.take[key] = R.d
		elseif B ~= nil and rs == B then
			plan.keep[key] = true
		elseif first and own then
			plan.conflicts[#plan.conflicts + 1] = key
		elseif first or (R.t or 0) > (stamps[key] or 0) then
			plan.take[key] = R.d
			if not first then plan.both[key] = true end
		else
			plan.keep[key] = true
		end
	end
	table.sort(plan.conflicts)
	return plan
end

---------------------------------------------------------------------------------------------------------------------
-- Putting sections back into the db: entries get their name and icon from this machine's catalog, else from the
-- copy that was in the same place, else from the game (spells and items by id).

local function catalogIndex()
	local map = {}
	local ok, catalog = pcall(function() return ns.Actions and ns.Actions.Catalog() end)
	for _, category in ipairs(ok and type(catalog) == "table" and catalog or NONE) do
		for _, entry in ipairs(category.entries) do
			map[entry.id] = map[entry.id] or entry
			for _, rank in ipairs(entry.ranks or NONE) do map[rank.id] = map[rank.id] or rank end
		end
	end
	return map
end

local function gameName(id)
	local kind, value = id:match("^(%a+):(.+)$")
	local number = tonumber(value)
	if (kind == "spell" or kind == "pet") and C_Spell then return call(C_Spell.GetSpellName, number), call(C_Spell.GetSpellTexture, number) end
	if (kind == "item" or kind == "toy") and C_Item then return call(C_Item.GetItemNameByID, number), call(C_Item.GetItemIconByID, number) end
	if kind == "macro" or kind == "spellgroup" then return value end
end

local function fatEntry(wire, old, index)
	local entry = type(wire) == "string" and { id = wire } or type(wire) == "table" and copy(wire) or nil
	if not (entry and type(entry.id) == "string") then return nil end
	local same = type(old) == "table" and old.id == entry.id and old or nil
	local known = index[entry.id]
	local name, icon = gameName(entry.id)
	entry.kind = entry.kind or known and known.kind or entry.id:match("^(%a+):")
	entry.name = same and same.name or known and known.name or name or entry.id
	entry.icon = same and same.icon or known and known.icon or icon
	return entry
end

local function fatGrid(rows, oldRows, index)
	local out = {}
	oldRows = type(oldRows) == "table" and oldRows or NONE
	for row, slots in pairs(type(rows) == "table" and rows or NONE) do
		local kept, old = {}, type(oldRows[row]) == "table" and oldRows[row] or NONE
		for slot, wire in pairs(type(slots) == "table" and slots or NONE) do kept[slot] = fatEntry(wire, old[slot], index) end
		if next(kept) then out[row] = kept end
	end
	return out
end

local function fatSides(sides, old, index)
	local out = {}
	old = type(old) == "table" and old or NONE
	for side, list in pairs(type(sides) == "table" and sides or NONE) do out[side] = fatGrid(list, old[side], index) end
	return out
end

local function charOf(db, name)
	db.chars = type(db.chars) == "table" and db.chars or {}
	db.chars[name] = type(db.chars[name]) == "table" and db.chars[name] or {}
	return db.chars[name]
end

-- options keeps this machine's debug switch; Core's load repair, for what a sync can bring.
local function putOptions(db, data)
	local options = type(data) == "table" and copy(data) or {}
	options.debug = type(db.options) == "table" and db.options.debug == true
	if type(options.glyphs) ~= "boolean" then options.glyphs = true end
	if type(options.toggleKey) ~= "string" then options.toggleKey = "PADSOCIAL" end
	if options.toggleHold ~= nil and options.toggleHold ~= false and type(options.toggleHold) ~= "table" then options.toggleHold = nil end
	if options.minimapAngle ~= nil and not finite(options.minimapAngle) then options.minimapAngle = nil end
	if options.minimapIcon ~= nil and type(options.minimapIcon) ~= "boolean" then options.minimapIcon = nil end
	-- The ring marker lives in db.ringMarker (nil: on); a format 2 set has none in options and leaves it as it is.
	if options.ringMarker == true then db.ringMarker = nil elseif options.ringMarker == false then db.ringMarker = false end
	options.ringMarker = nil
	db.options = options
end

local function putTweaks(db, data)
	local T = ns.Tweaks
	local saved = type(data) == "table" and copy(data) or {}
	if not T then
		db.tweaks = saved
		return
	end
	db.tweaks = T.Repair(saved)
	db.tweaks.rumbleGroups = T.RepairRumbleGroups(saved.rumbleGroups)
	db.tweaks.rumbleStrength = T.MigrateRumbleStrength(saved.rumbleStrength)
end

-- A character's rings (r:<GUID>).
local function putRings(db, name, data, index)
	if not name then return end
	local char = charOf(db, name)
	local function repaired() if ns.Rings and ns.Rings.Repair then ns.Rings.Repair(db, function(what) ns.debug("sync: rings repaired %s", what) end) end end
	if data == nil then
		char.rings = nil
		return repaired()
	end
	local old = type(char.rings) == "table" and char.rings or {}
	local oldList = type(old.list) == "table" and old.list or NONE
	local list = {}
	for i, ring in ipairs(type(data) == "table" and type(data.list) == "table" and data.list or NONE) do
		if type(ring) == "table" then
			local before
			for _, candidate in ipairs(oldList) do if type(candidate) == "table" and candidate.id == ring.id then before = candidate end end
			local out = copy(ring)
			out.slots = {}
			local oldSlots = before and type(before.slots) == "table" and before.slots or NONE
			for slot, wire in pairs(type(ring.slots) == "table" and ring.slots or NONE) do out.slots[slot] = fatEntry(wire, oldSlots[slot], index) end
			list[i] = out
		end
	end
	data = type(data) == "table" and data or NONE
	char.rings = { list = list, nextId = data.nextId }
	repaired()
end

local function putKeyboard(db, data)
	local old = type(db.keyboard) == "table" and db.keyboard or {}
	local new = type(data) == "table" and copy(data) or {}
	for key in pairs(LOCAL_KEYBOARD) do new[key] = old[key] end
	db.keyboard = ns.Keyboard and ns.Keyboard.Settings and ns.Keyboard.Settings(new) or new
end

local function putDevice(db, pad, data)
	db.devices = type(db.devices) == "table" and db.devices or {}
	if data == nil then
		db.devices[pad] = nil
		return
	end
	data = copy(data)
	-- Format 1 (an Undo kept from before profiles): the layout is the profile's now.
	data.roles, data.face = nil, nil
	local repaired = ns.Layout and ns.Layout.RepairDevice and ns.Layout.RepairDevice(data, pad)
	if repaired or not ns.Layout then db.devices[pad] = repaired or data end
end

-- A character's profiles (cp:<GUID>): the set replaces this machine's, repaired; nil removes it (an Undo of a sync that
-- brought it: the character makes its Default again). Bindings of a profile it no longer has stay where they are.
local function putProfiles(db, name, data)
	local char = charOf(db, name)
	if data == nil then
		char.profiles, char.profile = nil, nil
		return
	end
	local profiles = {}
	for id, profile in pairs(type(data.profiles) == "table" and data.profiles or NONE) do
		local repaired = isId(id) and type(profile) == "table" and copy(profile)
		if repaired and ns.Layout and ns.Layout.RepairProfile then repaired = ns.Layout.RepairProfile(repaired, id) end
		if repaired and not repaired.gone then profiles[id] = repaired end
	end
	char.profiles = profiles
	char.profile = type(data.profile) == "string" and profiles[data.profile] and data.profile or next(profiles)
end

-- Bindings or touch buttons that came for a profile the character lacks (a format 3 set: its profiles were account
-- ones) get one, so nothing synced is hidden. A cp: in the same set replaces the profiles anyway.
local function adopt(char, id, data)
	if data == nil or not ns.Profile or type(char.profiles) == "table" and char.profiles[id] then return end
	ns.Profile.Adopt(char, id)
end

-- One section into db (data nil removes what can be removed). index: catalogIndex().
local function put(db, key, data, index)
	if dropped(key) then return end
	if key == "options" then return putOptions(db, data) end
	if key == "tweaks" then return putTweaks(db, data) end
	if key:find("^r:") then return putRings(db, key:sub(3), data, index) end
	if key == "keyboard" then return putKeyboard(db, data) end
	if key == "setup" then
		local setup = type(data) == "table" and data or NONE
		db.onboarded = type(setup.onboarded) == "table" and copy(setup.onboarded) or nil
		db.declined = type(setup.declined) == "table" and copy(setup.declined) or nil
		return
	end
	local pad = key:match("^dev:(%x%x%x%x/%x%x%x%x)$")
	if pad then return putDevice(db, pad, data) end
	local name, cellsId = key:match("^cp:(.+)$")
	if name then return putProfiles(db, name, data) end
	name, cellsId = bindingsKey(key)
	if name then
		local char = charOf(db, name)
		char.cells = type(char.cells) == "table" and char.cells or {}
		char.cells[cellsId] = data ~= nil and fatGrid(data, char.cells[cellsId], index) or nil
		return adopt(char, cellsId, data)
	end
	name = key:match("^p:(.+)$")
	if name then
		charOf(db, name).placed = type(data) == "table" and copy(data) or {}
		return
	end
	local id
	name, id = key:match("^tb:(.+):([^:]+)$")
	if name then
		if not isId(id) then return end
		local char = charOf(db, name)
		char.touchBars = type(char.touchBars) == "table" and char.touchBars or {}
		char.touchBars[id] = type(data) == "table" and fatSides(data.bars, char.touchBars[id], index) or nil
		return adopt(char, id, data)
	end
	name = key:match("^t:(.+)$")
	if not name then return end
	local char = charOf(db, name)
	if type(data) ~= "table" then
		char.touch = nil
		return
	end
	local touch = copy(data)
	touch.bars = nil
	-- Buttons in t: (a format 2 set, an export row, an Undo of either) go to this character's profile.
	if type(data.bars) == "table" then
		local pid = ns.Profile and ns.Profile.CurrentId()
		local old = pid and type(char.touchBars) == "table" and char.touchBars[pid] or type(char.touch) == "table" and char.touch.bars
		local sides = fatSides(data.bars, old, index)
		if pid then
			char.touchBars = type(char.touchBars) == "table" and char.touchBars or {}
			char.touchBars[pid] = sides
		else
			touch.bars = sides
		end
	end
	char.touch = touch
end

-- Puts sections (key -> data, or false to remove) into ns.db, rings first so ring entries find their names (and the
-- rings repair checks bindings against the new lists before the bindings that came with them are put), then
-- every module applies again. "device": the one FCT_LAYOUT_CHANGED reason every module re-applies on (Rings re-applies
-- only on a controller change).
local function putAll(sections)
	local db = ns.db
	local function ringKey(key) return key:find("^r:") ~= nil end
	local rings = false
	for key, data in pairs(sections) do
		if ringKey(key) then
			put(db, key, data or nil, catalogIndex())
			rings = true
		end
	end
	if rings then ns.Fire("FCT_RINGS_CHANGED") end
	local index = catalogIndex()
	for key, data in pairs(sections) do
		if not ringKey(key) then put(db, key, data or nil, index) end
	end
	if ns.Tweaks then
		if ns.Tweaks.Refresh then ns.Tweaks.Refresh() end
		if ns.Tweaks.Light then ns.Tweaks.Light() end
	end
	local view = ns.Keyboard and ns.Keyboard.View
	if view and view.Wake then view.Wake() end
	ns.Fire("FCT_LAYOUT_CHANGED", "device")
	ns.Fire("FCT_RING_MARKS")
end
Sync.PutAll = putAll

---------------------------------------------------------------------------------------------------------------------
-- State

local function state() return ns.db and ns.db.sync end

-- This character's db table and its key, or nil before the name is known.
local function me()
	if ns.Face then return ns.Face.CharDB() end
end

local function newId()
	local out = ""
	for _ = 1, 6 do
		local d = math.random(1, 36)
		out = out .. DIGITS:sub(d, d)
	end
	return out
end

-- Repairs ns.db.sync into the shape above; fix(what) per repair.
function Sync.Repair(db, fix)
	fix = fix or function() end
	if db.sync ~= nil and type(db.sync) ~= "table" then fix("sync") end
	local s = type(db.sync) == "table" and db.sync or {}
	db.sync = s
	if s.on ~= nil and s.on ~= false then
		s.on = nil
		fix("sync.on")
	end
	if type(s.id) ~= "string" or not s.id:find("^%w+$") then s.id = newId() end
	for _, field in ipairs({ "base", "stamps", "marks", "pads" }) do
		if s[field] ~= nil and type(s[field]) ~= "table" then fix("sync." .. field) end
		s[field] = type(s[field]) == "table" and s[field] or {}
	end
	local want = { base = "string", stamps = "number", marks = "number", pads = "string" }
	for field, kind in pairs(want) do
		for key, value in pairs(s[field]) do
			if type(key) ~= "string" or type(value) ~= kind or kind == "number" and not finite(value) then
				s[field][key] = nil
				fix("sync." .. field .. "." .. tostring(key))
			end
		end
	end
	for _, field in ipairs({ "last", "wrote" }) do
		if s[field] ~= nil and not (type(s[field]) == "table" and finite(s[field].at)) then
			s[field] = nil
			fix("sync." .. field)
		end
	end
	local backup = s.backup
	if backup ~= nil and not (type(backup) == "table" and finite(backup.at) and type(backup.s) == "table") then
		s.backup = nil
		fix("sync.backup")
	end
	for key, item in pairs(s.backup and s.backup.s or NONE) do
		if type(key) ~= "string" or type(item) ~= "table" then
			s.backup.s[key] = nil
			fix("sync.backup." .. tostring(key))
		end
	end
	if s.backup and not next(s.backup.s) then s.backup = nil end
	if s.paused ~= nil and not PAUSES[s.paused] then
		s.paused = nil
		fix("sync.paused")
	end
	if s.need ~= nil and not finite(s.need) then s.need = nil end
	-- 1.5.3's account profile sections: the base of a section that is never written again.
	for _, field in ipairs({ "base", "stamps", "marks" }) do
		for key in pairs(s[field]) do if key == "map" or key:find("^prof:") then s[field][key] = nil end end
	end
	for key in pairs(s.backup and s.backup.s or NONE) do if key == "map" or key:find("^prof:") then s.backup.s[key] = nil end end
	if s.backup and not next(s.backup.s) then s.backup = nil end
	Sync.SplitDevices(db, s)
	return s
end

-- Base, marks and the backup from before profiles (1.5.0) held a pad's roles and face in dev:<pad>: they are the
-- profile's since, so they are dropped there and the first merge after the update compares like with like. A section
-- changed here since its last stamp keeps that stamp. Runs on every load; only a dev: with roles or face is touched.
function Sync.SplitDevices(db, s)
	local now = Sync.Sections(db)
	for key, text in pairs(s.base) do
		local pad = key:match("^dev:(.+)$")
		local data = isPad(pad) and Sync.Decode(text)
		if type(data) == "table" and (data.roles or data.face) then
			local pending = s.marks[key] ~= nil and s.marks[key] ~= hash(text)
			data.roles, data.face = nil, nil
			s.base[key] = enc(data)
			s.marks[key] = pending and now[key] ~= nil and hash(enc(now[key])) or hash(s.base[key])
		end
	end
	for key, item in pairs(s.backup and s.backup.s or NONE) do
		local data = isPad(key:match("^dev:(.+)$")) and type(item.d) == "table" and item.d
		if data then data.roles, data.face = nil, nil end
	end
end

local function dbVersion() return ns.db and tonumber(ns.db.version) or ns.DB_VERSION or 2 end

local function platform()
	if call(IsMacClient) then return L.SYNC_MAC end
	if call(IsWindowsClient) then return L.SYNC_WINDOWS end
	return L.SYNC_PC
end

-- "Mac · DualSense Wireless Controller": the label other machines show for this one.
function Sync.Host()
	local device = ns.Device and ns.Device.Current()
	return device and device.name and platform() .. " · " .. device.name or platform()
end

function Sync.PadName(key)
	local s = state()
	return s and s.pads[key] or key
end

local function rememberPad()
	local s, device = state(), ns.Device and ns.Device.Current()
	if s and device and type(device.name) == "string" then s.pads[device.key] = device.name end
end

-- "Today 14:02", "Yesterday 21:15", "20 Nov 14:02".
function Sync.When(at)
	if not finite(at) then return "?" end
	local now = serverTime()
	local day, today = date("*t", at), date("*t", now)
	local clock = date("%H:%M", at)
	if day.year == today.year and day.yday == today.yday then return L.SYNC_TODAY:format(clock) end
	local yesterday = date("*t", now - 86400)
	if day.year == yesterday.year and day.yday == yesterday.yday then return L.SYNC_YESTERDAY:format(clock) end
	return date("%d %b ", at) .. clock
end

-- "bindings, rings": the kinds of the keys, deduplicated, in a fixed order.
local KIND_ORDER = { "bindings", "profile", "touch", "rings", "device", "tweaks", "keyboard", "options", "setup", "layout" }
function Sync.KindList(keys)
	local seen, out = {}, {}
	for _, key in ipairs(keys) do seen[kindOf(key)] = true end
	for _, kind in ipairs(KIND_ORDER) do if seen[kind] then out[#out + 1] = L.SEC_LOWER[kind] end end
	return table.concat(out, ", ")
end

---------------------------------------------------------------------------------------------------------------------
-- The account macros

-- Our sync macros (account list, a sync name and a "#FCT" body), and the numbers the player's own macros of that
-- name hold.
local function syncMacros()
	local count = call(GetNumMacros) or 0
	local ours, taken = {}, {}
	for index = 1, math.min(count, MAX_ACCOUNT) do
		local name = call(GetMacroInfo, index)
		local n = type(name) == "string" and tonumber(name:match("^FCT:Sync (%d+)$"))
		if n then
			local body = trimmed(call(GetMacroBody, index))
			if body and body:find("^#FCT%d") then ours[#ours + 1] = { index = index, name = name, n = n, body = body } else taken[n] = true end
		end
	end
	return ours, taken
end
Sync.Macros = syncMacros

function Sync.IsSyncMacro(name, body)
	return type(name) == "string" and name:find("^FCT:Sync %d+$") ~= nil and (trimmed(body) or ""):find("^#FCT%d") ~= nil
end

-- The bodies of one write: text cut into DATA-letter slices behind the header.
function Sync.Bodies(text, at)
	local gen, total, out = base36(math.max(0, at - GEN_EPOCH)), math.max(1, math.ceil(#text / DATA)), {}
	for i = 1, total do out[i] = HEADER:format(FORMAT, i, total, gen) .. text:sub((i - 1) * DATA + 1, i * DATA) end
	return out
end

-- The newest complete write on the server: payload, parts; or nil and why ("none", "corrupt", "newer").
function Sync.ReadRemote()
	local ours = syncMacros()
	if not ours[1] then return nil, "none" end
	local groups = {}
	for _, macro in ipairs(ours) do
		if tonumber(macro.body:match("^#FCT(%d+)")) > FORMAT then return nil, "newer" end
		local fmt, part, total, gen, data = macro.body:match("^#FCT(%d+) (%d+)/(%d+) (%w+) (%S*)$")
		part, total = tonumber(part), tonumber(total)
		if fmt and part >= 1 and total >= 1 and part <= total and total <= MAX_PARTS then
			local group = groups[gen] or { total = total, parts = {}, at = (tonumber(gen, 36) or 0) + GEN_EPOCH }
			groups[gen] = group
			if group.total == total then group.parts[part] = data end
		end
	end
	local best
	for _, group in pairs(groups) do
		local complete = true
		for i = 1, group.total do complete = complete and group.parts[i] ~= nil end
		if complete and (not best or group.at > best.at) then best = group end
	end
	if not best then return nil, "corrupt" end
	local payload = Sync.Unpack(table.concat(best.parts, "", 1, best.total))
	if not (payload and type(payload.s) == "table") then return nil, "corrupt" end
	if (tonumber(payload.v) or 0) > FORMAT or (tonumber(payload.db) or 0) > dbVersion() then return nil, "newer" end
	payload.at = finite(payload.at) and payload.at or 0
	local sections = {}
	for key, item in pairs(payload.s) do
		if type(key) == "string" and type(item) == "table" and not dropped(key) and validRow(kindOf(key), item.d) then sections[key] = { t = finite(item.t) and item.t or 0, d = item.d } end
	end
	payload.s = sections
	return payload, best.total
end

-- Slot writes run guarded (Actions.Busy): the UPDATE_MACROS each edit raises must not start applies half way.
local function guarded(fn)
	local guard = ns.Actions and ns.Actions.Guard
	return guard and guard(fn) or fn
end

local function findOurs(name)
	for _, macro in ipairs((syncMacros())) do
		if macro.name == name then return macro.index end
	end
end

-- Writes bodies as FCT:Sync 1..n (numbers the player's macros hold are skipped). New ones are made first, so a refused
-- create leaves the last complete set as it was. Returns true, or false and how many more free slots it needs.
local writeBodies = guarded(function(bodies)
	local ours, taken = syncMacros()
	local names, n = {}, 0
	while #names < #bodies do
		n = n + 1
		if not taken[n] then names[#names + 1] = NAME:format(n) end
	end
	local have = {}
	for _, macro in ipairs(ours) do have[macro.name] = true end
	local creates = 0
	for _, name in ipairs(names) do if not have[name] then creates = creates + 1 end end
	local free = MAX_ACCOUNT - (call(GetNumMacros) or 0)
	if creates > free then return false, creates - free end

	for i, name in ipairs(names) do
		if not have[name] then
			local ok, index = pcall(CreateMacro, name, ICON, bodies[i], false)
			if not (ok and index) then return false, 0 end
		end
	end
	for i, name in ipairs(names) do
		local index = findOurs(name)
		if index and trimmed(call(GetMacroBody, index)) ~= bodies[i] then EditMacro(index, nil, nil, bodies[i]) end
	end
	-- Indexes shift with each delete: the list is read again. Ours past the set go, and a second copy of a name.
	local keep = {}
	for _, name in ipairs(names) do keep[name] = true end
	for _ = 1, MAX_ACCOUNT do
		local doomed, seen = nil, {}
		for _, macro in ipairs((syncMacros())) do
			if not doomed and (not keep[macro.name] or seen[macro.name]) then doomed = macro.index end
			seen[macro.name] = true
		end
		if not doomed then break end
		DeleteMacro(doomed)
	end
	return true
end)

local deleteAll = guarded(function()
	local count = 0
	for _ = 1, MAX_ACCOUNT do
		local macro = syncMacros()[1]
		if not macro then break end
		DeleteMacro(macro.index)
		count = count + 1
	end
	return count
end)

---------------------------------------------------------------------------------------------------------------------
-- Login read, apply, check and write

local settled, settledFired = false, false
-- "idle" (before the first world entry), "waiting" (for the macro list), "choice" (the first-sync question),
-- "applying", "done".
local phase = "idle"
-- rewrite: this machine's copy must go out (kept sections, none or damaged macros); damaged: say so once written.
-- writable: this session merged the server's set, or found none on a loaded list, or may replace a damaged one (this
-- machine agreed with the set before, or the player pressed Sync now). Nothing is written before.
local listSeen, rewrite, damaged, writable, choice, toldOnce = false, false, false, false, nil, {}
local lastWrite, checkToken, forceNext, forcedNow = nil, 0, false, false

local function tell(key, text)
	if toldOnce[key] then return end
	toldOnce[key] = true
	ns.log(text)
end

local function changed() ns.Fire("FCT_SYNC_CHANGED") end

local function settle()
	settled = true
	if settledFired then return end
	settledFired = true
	ns.debug("sync: settled")
	ns.Fire("FCT_SYNC_SETTLED")
end

function Sync.Settled()
	local s = state()
	return settled or not Sync.Available() or not s or s.on == false
end

local function macroFrameShown()
	local frame = _G.MacroFrame
	return not not (frame and frame.IsShown and frame:IsShown())
end

-- The account list is known once UPDATE_MACROS came, or it already reads macros: an empty read before that is the
-- list not loaded yet, never "no sync macros".
local function listKnown() return listSeen or (call(GetNumMacros) or 0) > 0 end

local function ringOpen()
	local frame = ns.Rings and ns.Rings.Frame and ns.Rings.Frame()
	return not not (frame and frame.GetAttribute and frame:GetAttribute("ps-ring"))
end

local function busy() return InCombatLockdown() or ringOpen() or macroFrameShown() or ns.Actions and ns.Actions.Busy and ns.Actions.Busy() or false end

local function pause(why, need)
	local s = state()
	s.paused, s.need = why, need
	if why == "full" then tell("full", L.SYNC_LINE_FULL:format(need or 1)) end
	if why == "newer" then tell("newer", L.SYNC_LINE_NEWER) end
	if why == "big" then tell("big", L.SYNC_LINE_BIG:format(MAX_PARTS)) end
	changed()
end

-- Records that this machine and the macros agree on key at text (stamp t).
local function agree(key, text, t)
	local s = state()
	s.base[key], s.marks[key] = text, hash(text)
	if t then s.stamps[key] = t end
end

-- Stamps the sections that changed here since they were stamped; true when any differs from what was agreed.
local function stamp()
	local s = state()
	local now, any = serverTime(), false
	for key, data in pairs(Sync.Sections(ns.db, s.base)) do
		local text = enc(data)
		if text ~= s.base[key] then
			any = true
			local h = hash(text)
			if s.marks[key] ~= h then s.marks[key], s.stamps[key] = h, now end
		end
	end
	return any
end

local schedule, read

local function write()
	local s = state()
	if not (s and s.on ~= false and settled and writable and not choice and s.paused ~= "newer") then return end
	if busy() or not listKnown() then return schedule() end
	local gap = lastWrite and WRITE_GAP - (GetTime() - lastWrite) or 0
	if gap > 0 and not forceNext then return schedule(gap) end
	-- Another computer or session wrote after this one last merged or wrote: merge that set first, never over it.
	local remote, why = Sync.ReadRemote()
	if why == "newer" then return pause("newer") end
	local seen = math.max(s.wrote and s.wrote.at or 0, s.last and s.last.at or 0)
	if remote and remote.at > seen then return read() end
	forceNext = false
	rememberPad()

	local sections = Sync.Sections(ns.db, s.base)
	local at = math.max(serverTime(), (s.wrote and s.wrote.at or 0) + 1)
	local payload = { v = FORMAT, db = dbVersion(), at = at, by = s.id, host = Sync.Host(), pads = copy(s.pads), s = {} }
	for key, data in pairs(sections) do payload.s[key] = { t = s.stamps[key] or 0, d = data } end
	local text = Sync.Pack(payload)
	if not text then return end
	local bodies = Sync.Bodies(text, at)
	if #bodies > MAX_PARTS then return pause("big") end
	local ok, need = writeBodies(bodies)
	if not ok then return pause("full", need) end

	lastWrite = GetTime()
	for key, data in pairs(sections) do agree(key, enc(data)) end
	if damaged then tell("rewrote", L.SYNC_REWROTE) end
	s.wrote, s.last, s.paused, s.need, rewrite, damaged = { at = at, parts = #bodies }, { at = at, by = s.id, host = payload.host }, nil, nil, false, false
	ns.debug("sync: wrote %d parts", #bodies)
	changed()
end

-- Stamps what changed and queues a write when anything differs from the macros. force: Sync now (no 30 s gap).
function Sync.Check(force)
	local s = state()
	if not (s and Sync.Available() and settled and not choice) then return end
	-- Off: stamps only, so a change made here keeps its time for when sync is on again.
	if s.on == false then return stamp() end
	if not stamp() and not rewrite and not force then return changed() end
	if force then forceNext = true end
	if s.paused == "newer" then return end
	changed()
	ns.whenPadFree("sync-write", write)
end

function schedule(delay)
	checkToken = checkToken + 1
	local token = checkToken
	C_Timer.After(delay or CHECK_DELAY, function() if token == checkToken then Sync.Check() end end)
end

-- Applies a merge plan out of combat: takes, agreements, the backup of what it replaced, the chat lines.
-- kept: backups of the other copy for sections this machine kept (Keep mine).
local function applyPlan(plan, remote, kept)
	local s = state()
	local current = Sync.Sections(ns.db, s.base)
	local replaced, taken = copy(kept or NONE), {}
	for key, data in pairs(plan.take) do
		-- The placed list is bookkeeping: no chat line, no Undo.
		local setting = kindOf(key) ~= "placed"
		if setting then taken[#taken + 1] = key end
		if setting and current[key] ~= nil and enc(current[key]) ~= enc(data) then replaced[key] = { d = current[key] } end
	end
	if next(plan.take) then putAll(plan.take) end
	-- A union agrees with what the macros hold, so it differs here and goes out with the next write.
	for key, data in pairs(plan.take) do agree(key, enc(plan.merged[key] and remote.s[key].d or data), remote.s[key].t) end
	for key, text in pairs(plan.agree) do agree(key, text, remote.s[key].t) end
	if next(plan.keep) then rewrite = true end
	if next(replaced) then s.backup = { at = serverTime(), host = remote.host, s = replaced } end
	s.last, writable = { at = remote.at, by = remote.by, host = remote.host }, true
	local when = Sync.When(remote.at)
	table.sort(taken)
	if taken[1] then ns.log(L.SYNC_GOT:format(tostring(remote.host), when, Sync.KindList(taken))) end
	local both = {}
	for key in pairs(plan.both) do both[#both + 1] = key end
	table.sort(both)
	if both[1] then ns.log(L.SYNC_BOTH:format(Sync.KindList(both), tostring(remote.host), when)) end
end

local remoteSeen

local function finish()
	phase = "done"
	settle()
	changed()
	if not forcedNow then return schedule(rewrite and 1 or CHECK_DELAY) end
	forcedNow = false
	rewrite = rewrite or writable
	Sync.Check(true)
end

-- Reads the macros and merges (on a known list only). A first sync with conflicts waits for Sync.Choose.
function read()
	local s = state()
	phase = "applying"
	rememberPad()
	-- Changes made since the last stamp (while sync was off, or before this login) get their time before the merge.
	stamp()
	local remote, why = Sync.ReadRemote()
	if why ~= "newer" and s.paused == "newer" then s.paused, toldOnce.newer = nil, nil end
	if not remote then
		if why == "newer" then pause("newer") end
		if why == "corrupt" then s.paused = "corrupt" end
		-- A damaged set is replaced only by a machine that agreed with it before, or on Sync now: a fresh machine
		-- would push its defaults over the other computer's settings.
		writable = why == "none" or why == "corrupt" and (next(s.base) ~= nil or forcedNow)
		-- No macros although this machine wrote some: the player deleted them.
		rewrite, damaged = writable, writable and (why == "corrupt" or why == "none" and s.wrote ~= nil)
		return finish()
	end
	if s.paused ~= "full" and s.paused ~= "big" then s.paused, s.need = nil, nil end
	remoteSeen = remote
	for key, name in pairs(type(remote.pads) == "table" and remote.pads or NONE) do
		if type(key) == "string" and type(name) == "string" and not s.pads[key] then s.pads[key] = name end
	end
	local localS = Sync.Sections(ns.db, s.base)
	local plan = Sync.Merge(localS, remote.s, s.base, s.stamps, not next(s.base), Sync.HasOwn(localS))
	if plan.conflicts[1] then
		phase, choice = "choice", { plan = plan, remote = remote }
		changed()
		return ns.Fire("FCT_SYNC_CHOICE")
	end
	ns.whenPadFree("sync-apply", function()
		applyPlan(plan, remote)
		finish()
	end)
end

local function tryRead()
	local s = state()
	if phase ~= "waiting" then return end
	if not (s and Sync.Available()) or s.on == false then
		phase = "done"
		return settle()
	end
	if macroFrameShown() then return C_Timer.After(POLL, tryRead) end
	-- Waits for the list: the first UPDATE_MACROS reads (the take-back waits with it, it has nothing to take back yet).
	if not listKnown() then return ns.debug("sync: waiting for the macro list") end
	read()
end

-- The first-sync question: { host, at, conflicts = { key, ... } } while it waits, else nil.
function Sync.Choice()
	if not choice then return end
	local remote = choice.remote
	return { host = remote.host, at = remote.at, when = Sync.When(remote.at), conflicts = choice.plan.conflicts }
end

-- useSynced: the other computer's copy of every conflicting section; else this one's, written out.
function Sync.Choose(useSynced)
	if not choice then return end
	local plan, remote, kept = choice.plan, choice.remote, {}
	for _, key in ipairs(plan.conflicts) do
		if useSynced then plan.take[key] = remote.s[key].d else plan.keep[key], kept[key] = true, { d = remote.s[key].d } end
	end
	plan.conflicts = {}
	ns.whenPadFree("sync-apply", function()
		choice = nil
		applyPlan(plan, remote, kept)
		finish()
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Status and the player's actions

-- What the window shows: { state, on, last, me, macros, top, free, max, need, chars, rings, backup }. state: "off",
-- "unavailable", "choice", "newer", "full", "big", "corrupt", "pending", "ok".
function Sync.Status()
	local s = state()
	if not s then return { state = "unavailable" } end
	local ours = syncMacros()
	local top = 0
	for _, macro in ipairs(ours) do top = math.max(top, macro.n) end
	local sections, chars, rings = Sync.Sections(ns.db, s.base), {}, 0
	for key, data in pairs(sections) do
		local name = bindingsKey(key)
		if name and hasEntries(data) then chars[name] = true end
	end
	local charCount = 0
	for _ in pairs(chars) do charCount = charCount + 1 end
	local _, name = me()
	local mine = name and sections["r:" .. name]
	if mine then rings = #mine.list end
	local pending = rewrite
	for key, data in pairs(sections) do pending = pending or enc(data) ~= s.base[key] end
	local status = s.on == false and "off" or not Sync.Available() and "unavailable" or choice and "choice" or s.paused or pending and "pending" or "ok"
	local account = call(GetNumMacros) or 0
	-- rewriting: a damaged set goes out again by itself (false: only on Sync now).
	return { state = status, rewriting = writable, on = s.on ~= false, last = s.last, me = s.id, macros = #ours, top = top, free = MAX_ACCOUNT - account, max = MAX_ACCOUNT, need = s.need, chars = charCount, rings = rings, backup = s.backup, choice = Sync.Choice() }
end

-- True while this machine is in step with the sync macros: on, the login read merged (or found none), no pause, no
-- first-sync question. Only then may the take-back free slots another machine placed: this machine's bindings are the
-- account's.
function Sync.InStep()
	local s = state()
	return not not (s and s.on ~= false and Sync.Available() and phase == "done" and writable and not choice and not s.paused)
end

-- Sync now: reads the macros again (a newer pause clears if the newer set is gone, a damaged set may be replaced),
-- retries a full or too-big pause and writes at once (out of combat, the pad free).
function Sync.Now()
	local s = state()
	if not (s and Sync.Available()) then return ns.log(L.SYNC_UNAVAILABLE) end
	if s.on == false then return ns.log(L.SYNC_LINE_OFF) end
	if choice then return ns.log(L.SYNC_LINE_CHOICE) end
	if phase == "waiting" then return ns.log(L.SYNC_LINE_WAITING) end
	if phase ~= "done" then return end
	if s.paused == "full" or s.paused == "big" then s.paused, s.need, toldOnce.full, toldOnce.big = nil, nil, nil, nil end
	forcedNow, phase = true, "waiting"
	tryRead()
end

-- On reads at once and merges (base kept: no first-sync question); off stops reading and writing here only.
function Sync.SetOn(on)
	local s = state()
	if not s then return end
	if on then s.on = nil else s.on = false end
	checkToken = checkToken + 1
	changed()
	if not on or phase == "idle" then return end
	phase = "waiting"
	tryRead()
end

function Sync.Undo()
	local s = state()
	local backup = s and s.backup
	if not backup then return ns.log(L.SYNC_NO_UNDO) end
	ns.whenPadFree("sync-undo", function()
		local sections, keys = {}, {}
		for key, item in pairs(backup.s) do
			sections[key] = item.d ~= nil and item.d or false
			keys[#keys + 1] = key
		end
		s.backup = nil
		putAll(sections)
		table.sort(keys)
		ns.log(L.SYNC_UNDONE:format(Sync.KindList(keys)))
		Sync.Check()
	end)
end

-- /fct release: our sync macros go and sync stops on this machine. Returns how many were deleted.
function Sync.Release()
	local s = state()
	if s then s.on = false end
	checkToken = checkToken + 1
	return deleteAll()
end

---------------------------------------------------------------------------------------------------------------------
-- Export and import (design 3.4): this character's profile (its name, roles and face actions, and the bindings in it),
-- the touch bars, rings, tweaks, keyboard and options, under neutral keys. No character name is ever in it; the
-- profile's name is the one name. An import goes into this character's current profile.

local EXPORT_ROWS = { "bindings", "touch", "rings", "tweaks", "keyboard", "layout", "options" }

-- The local data an export row stands for: data, and the section key it lives in (nil for layout).
local function localRow(row)
	local db = ns.db
	local char, name = me()
	local profile, id
	if ns.Profile then profile, id = ns.Profile.Current() end
	if row == "bindings" then
		if not (id and char) then return end
		return slimGrid(type(char.cells) == "table" and char.cells[id] or NONE), "b:" .. name .. ":" .. id
	end
	if row == "rings" then
		if not char then return end
		return slimRings(type(char.rings) == "table" and char.rings or NONE), "r:" .. name
	end
	-- The layout and this profile's buttons, as one row.
	if row == "touch" then
		if not char then return end
		if type(char.touch) ~= "table" then return nil, "t:" .. name end
		local out = slimTouch(char.touch)
		local bars = id and type(char.touchBars) == "table" and char.touchBars[id]
		out.bars = slimSides(bars or char.touch.bars)
		return out, "t:" .. name
	end
	if row == "layout" then return profile and { name = profile.name, roles = copy(profile.roles), face = copy(profile.face) } or nil end
	return Sync.Sections(db)[row], row
end

-- The export string, and what it holds (row -> data).
function Sync.Export()
	local s = {}
	for _, row in ipairs(EXPORT_ROWS) do s[row] = (localRow(row)) end
	local text = Sync.Pack({ v = FORMAT, db = dbVersion(), kind = "export", at = serverTime(), s = s })
	return text and EXPORT_PREFIX .. text, s
end

-- An export string, whitespace anywhere: the payload, or nil and "bad" | "newer".
function Sync.ReadExport(text)
	text = type(text) == "string" and text:gsub("%s+", "") or ""
	local fmt, data = text:match("^FCT(%d+):(.+)$")
	if not fmt then return nil, "bad" end
	if tonumber(fmt) > FORMAT then return nil, "newer" end
	local payload = Sync.Unpack(data)
	if not (payload and payload.kind == "export" and type(payload.s) == "table") then return nil, "bad" end
	if (tonumber(payload.v) or 0) > FORMAT or (tonumber(payload.db) or 0) > dbVersion() then return nil, "newer" end
	for _, row in ipairs(EXPORT_ROWS) do
		if payload.s[row] ~= nil and not validRow(row, payload.s[row]) then return nil, "bad" end
	end
	return payload
end

-- How many leaves (cells, touch buttons) differ between two grids.
local function gridChanges(a, b)
	local count, seen = 0, {}
	local function walk(x, y)
		for row, slots in pairs(x) do
			for slot, entry in pairs(type(slots) == "table" and slots or NONE) do
				local id = tostring(row) .. "/" .. tostring(slot)
				if not seen[id] then
					seen[id] = true
					local other = type(y[row]) == "table" and y[row][slot]
					if enc(entry) ~= enc(other) then count = count + 1 end
				end
			end
		end
	end
	walk(a or NONE, b or NONE)
	walk(b or NONE, a or NONE)
	return count
end

local function touchChanges(a, b)
	local count, abars, bbars = 0, a and a.bars or NONE, b and b.bars or NONE
	for _, side in ipairs({ "left", "right" }) do count = count + gridChanges(abars[side], bbars[side]) end
	local x, y = copy(a or NONE), copy(b or NONE)
	x.bars, y.bars = nil, nil
	for key in pairs(x) do if enc(x[key]) ~= enc(y[key]) then count = count + 1 end end
	for key in pairs(y) do if x[key] == nil then count = count + 1 end end
	return count
end

local function keyChanges(a, b)
	local count = 0
	for key, value in pairs(a or NONE) do if enc(value) ~= enc((b or NONE)[key]) then count = count + 1 end end
	for key in pairs(b or NONE) do if (a or NONE)[key] == nil then count = count + 1 end end
	return count
end

-- The import preview: one row per part of the export, in order: { id, count, rings, yours, same, missing }. same: equal
-- to this machine's; missing: this machine can't take it (no controller or character yet).
function Sync.Preview(payload)
	local out = {}
	for _, id in ipairs(EXPORT_ROWS) do
		local incoming = payload.s[id]
		if incoming ~= nil then
			local mine = localRow(id)
			local row = { id = id, same = enc(incoming) == enc(mine) }
			-- The name is the exporter's: an import keeps this profile's.
			if id == "layout" then row.same = keyChanges(incoming.roles, mine and mine.roles) + keyChanges(incoming.face, mine and mine.face) == 0 end
			row.missing = (id == "bindings" or id == "layout" or id == "touch" or id == "rings") and not me()
			if id == "bindings" then row.count = gridChanges(incoming, mine)
			elseif id == "touch" then row.count = touchChanges(incoming, mine)
			elseif id == "rings" then row.rings, row.yours = #(incoming.list or NONE), mine and #(mine.list or NONE) or 0
			elseif id == "layout" then row.count = keyChanges(incoming.roles, mine and mine.roles) + keyChanges(incoming.face, mine and mine.face)
			else row.count = keyChanges(incoming, mine) end
			out[#out + 1] = row
		end
	end
	return out
end

-- Imports the ticked rows (out of combat): they replace this machine's, the replaced ones become the backup (Undo),
-- and the next sync write sends them out.
function Sync.Import(payload, ids)
	ns.whenPadFree("sync-import", function()
		local sections, backup, names = {}, {}, {}
		local profileId
		if ns.Profile then profileId = select(2, ns.Profile.Ensure()) end
		local _, name = me()
		for _, id in ipairs(ids) do
			local incoming = payload.s[id]
			local mine, key = localRow(id)
			if incoming ~= nil and id == "layout" then
				key = profileId and name and "cp:" .. name
				local set = key and Sync.Sections(ns.db)[key]
				if set and set.profiles[profileId] then
					backup[key] = { d = copy(set) }
					local profile = set.profiles[profileId]
					profile.roles, profile.face = copy(incoming.roles or {}), copy(incoming.face or {})
					sections[key] = set
					names[#names + 1] = id
				end
			elseif incoming ~= nil and key then
				backup[key] = { d = mine ~= nil and mine or false }
				sections[key] = incoming
				names[#names + 1] = id
			end
		end
		if not names[1] then return end
		putAll(sections)
		state().backup = { at = serverTime(), host = Sync.Host(), s = backup }
		local list = {}
		for _, id in ipairs(names) do list[#list + 1] = L.SEC_LOWER[id] end
		ns.log(L.IMPORT_DONE:format(table.concat(list, ", ")))
		Sync.Check()
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- Events and /fct

ns.On("FCT_READY", function()
	local fixes = 0
	Sync.Repair(ns.db, function(what)
		fixes = fixes + 1
		ns.debug("db repaired %s", what)
	end)
	if fixes > 0 then ns.log(fixes == 1 and L.SYNC_REPAIRED_ONE or L.SYNC_REPAIRED:format(fixes)) end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	if phase ~= "idle" then return end
	phase = "waiting"
	if not Sync.Available() then tell("unavailable", L.SYNC_UNAVAILABLE) end
	tryRead()
	-- No UPDATE_MACROS after a /reload and no account macros: settled anyway, so the take-back runs this session. The
	-- list stays unknown (nothing is read or written) and a later UPDATE_MACROS still reads.
	C_Timer.After(LIST_WAIT, function()
		if phase ~= "waiting" or settled then return end
		ns.debug("sync: no macro list after %d s, settled without a read", LIST_WAIT)
		settle()
		changed()
	end)
end)

ns.On("UPDATE_MACROS", function()
	listSeen = true
	tryRead()
end)

for _, event in ipairs({ "FCT_LAYOUT_CHANGED", "FCT_RINGS_CHANGED", "FCT_RING_MARKS", "PLAYER_REGEN_ENABLED" }) do
	ns.On(event, function() if phase == "done" then schedule() end end)
end
ns.On("FCT_PANEL_OPEN", function(open) if not open and phase == "done" then schedule() end end)
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then rememberPad() end end)
-- Stamps only: a change made just before quitting goes out at the next login here.
ns.On("PLAYER_LOGOUT", function()
	local s = state()
	if s and settled and not choice then stamp() end
end)

function ns.commands.sync(args)
	local what = (args[1] or ""):lower()
	if what == "now" then return Sync.Now() end
	if what == "on" or what == "off" then
		Sync.SetOn(what == "on")
		return ns.log(what == "on" and L.SYNC_LINE_ON or L.SYNC_LINE_OFF)
	end
	if what == "undo" then return Sync.Undo() end
	if what ~= "" then return ns.log(L.SYNC_LINE_HELP) end
	local status = Sync.Status()
	if status.state == "unavailable" then return ns.log(L.SYNC_UNAVAILABLE) end
	if status.macros == 0 then ns.log(L.SYNC_LINE_NONE) end
	local last = status.last
	local from = last and (last.by == status.me and L.SYNC_THIS:format(Sync.Host()) or tostring(last.host)) or "-"
	ns.log(L.SYNC_LINE_STATUS:format(status.on and L.SYNC_ON_WORD or L.SYNC_OFF_WORD, last and Sync.When(last.at) or L.SYNC_LINE_NEVER, from, status.macros))
end

-- The windows (Panel/Sync.lua) open once the pad is free: the slash came from the chat box.
local function openWindow(what)
	return function()
		if not Sync.Available() then return ns.log(L.SYNC_UNAVAILABLE) end
		ns.whenPadFree(what, function()
			local panel = ns.UI and ns.UI.Sync
			if panel and panel[what] then panel[what]() end
		end, { timeout = 15 })
	end
end
ns.commands.export = openWindow("OpenExport")
ns.commands.import = openWindow("OpenImport")
