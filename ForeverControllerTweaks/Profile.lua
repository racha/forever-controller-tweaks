-- Forever Controller Tweaks profiles: a layout (modifier roles, face-action positions) and every character's bindings
-- for it (ns.db.chars[char].cells[id]), shared by the controllers that use it. Hardware (raw sources, family,
-- detection, label style) stays per controller in ns.db.devices.
-- ns.db.profiles[id] = { name, roles, face }, or { gone = true } once deleted, so sync carries the deletion.
-- ns.db.deviceProfile[deviceKey] = { id, at }: at is the server time the player picked it, 0 for the addon's own pick
-- (a migrated controller, the first Default), which a pick made on any computer beats.
-- ns.db.lastProfile: the one last used on this computer; a new controller plays on it until the player answers.
-- Ids: a controller from before profiles keeps its device key, so char.cells needed no rename; a new one is p<n>.
local _, ns = ...
local Profile = {}
ns.Profile = Profile

local L = {
	DEFAULT = "Default", NUMBERED = "Profile %d",
	PROFILE_LIST = "Profiles: %s.", PROFILE_THIS = "%s (this controller)", PROFILE_NONE = "No profiles yet: connect a controller.",
	PROFILE_SWITCHED = "This controller now uses the profile %s.", PROFILE_UNKNOWN = "No profile named %s (/fct profile lists them).",
	PROFILE_NO_PAD = "No controller found.",
}
Profile.L = L

local NAME_MAX = 32
local NONE = {}

local function isPad(key) return type(key) == "string" and key:find("^%x%x%x%x/%x%x%x%x$") ~= nil end
local function isId(id) return isPad(id) or type(id) == "string" and id:find("^p%d+$") ~= nil end
Profile.IsId = isId

local function finite(value) return type(value) == "number" and value - value == 0 end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in pairs(value) do out[key] = copy(item) end
	return out
end

local function serverTime()
	local ok, now = pcall(GetServerTime)
	return ok and finite(now) and now or 0
end

-- At most NAME_MAX bytes, never half a UTF-8 letter.
local function cut(text)
	if #text <= NAME_MAX then return text end
	return (text:sub(1, NAME_MAX):gsub("[\192-\255][\128-\191]*$", ""))
end

-- The name, trimmed, or "Default"; " 2", " 3"... when another live profile in profiles has it (except: its own id).
local function uniqueName(profiles, name, except)
	name = cut(type(name) == "string" and name:match("^%s*(.-)%s*$") or "")
	if name == "" then name = L.DEFAULT end
	local taken = {}
	for id, profile in pairs(profiles) do
		if id ~= except and type(profile) == "table" and not profile.gone and type(profile.name) == "string" then taken[profile.name:lower()] = true end
	end
	if not taken[name:lower()] then return name end
	local n = 2
	while taken[(name .. " " .. n):lower()] do n = n + 1 end
	return name .. " " .. n
end
Profile.UniqueName = uniqueName

local function live(id)
	local profile = isId(id) and ns.db and type(ns.db.profiles) == "table" and ns.db.profiles[id]
	if type(profile) == "table" and not profile.gone then return profile end
end
Profile.Get = live

-- { { id, name }, ... } of the live profiles, by name.
function Profile.List()
	local out = {}
	for id, profile in pairs(ns.db and ns.db.profiles or NONE) do
		if not profile.gone then out[#out + 1] = { id = id, name = profile.name } end
	end
	table.sort(out, function(a, b)
		local x, y = a.name:lower(), b.name:lower()
		if x ~= y then return x < y end
		return a.id < b.id
	end)
	return out
end

-- The profile the player (or the migration) picked for this controller, while it exists.
function Profile.Picked(key)
	local pick = ns.db and ns.db.deviceProfile[key]
	return pick and live(pick.id) and pick.id or nil
end
local picked = Profile.Picked

local function fallback()
	local last = ns.db and ns.db.lastProfile
	if live(last) then return last end
	local first = Profile.List()[1]
	return first and first.id
end

-- The id a controller plays on: its pick, else the last one used here, else the first; nil before any exists.
function Profile.IdFor(key) return key and (picked(key) or fallback()) or nil end

local function device() return ns.Device and ns.Device.Current() end

function Profile.CurrentId()
	local pad = device()
	return pad and Profile.IdFor(pad.key)
end
-- char.cells is keyed by profile id.
Profile.CellsKey = Profile.CurrentId

function Profile.Current()
	local id = Profile.CurrentId()
	return live(id), id
end

-- True while this controller has no pick of its own and plays on another profile: the new-controller question is due.
function Profile.Pending()
	local pad = device()
	return not not (pad and not picked(pad.key) and fallback())
end

local function changed(applied)
	ns.Fire("FCT_PROFILES_CHANGED")
	if applied then ns.Fire("FCT_LAYOUT_CHANGED", "device") end
end

local function newId()
	local n = serverTime()
	while ns.db.profiles["p" .. n] do n = n + 1 end
	return "p" .. n
end

local function create(name, roles, face, id)
	id = id or newId()
	ns.db.profiles[id] = { name = uniqueName(ns.db.profiles, name), roles = roles or {}, face = face or {} }
	return id
end

-- The first controller ever (nothing to migrate, nothing synced): a Default profile, without a question. Writers call
-- it; returns Profile.Current().
function Profile.Ensure()
	local pad = device()
	if not (pad and ns.db) then return end
	if not fallback() then
		local id = create(L.DEFAULT, nil, nil, not ns.db.profiles.p1 and "p1" or nil)
		ns.db.deviceProfile[pad.key], ns.db.lastProfile = { id = id, at = 0 }, id
		changed()
	end
	return Profile.Current()
end

-- An empty profile: the native layout, no bindings. Returns its id.
function Profile.New(name)
	local id = create(name)
	changed()
	return id
end

-- A deep copy of from's layout and of every character's bindings for it. Returns its id.
function Profile.Copy(from, name)
	local source = live(from)
	if not source then return nil, "no such profile" end

	local id = create(name or source.name, copy(source.roles), copy(source.face))
	for _, char in pairs(type(ns.db.chars) == "table" and ns.db.chars or NONE) do
		local cells = type(char) == "table" and type(char.cells) == "table" and char.cells
		if cells and type(cells[from]) == "table" then cells[id] = copy(cells[from]) end
	end
	changed()
	return id
end

function Profile.Rename(id, name)
	local profile = live(id)
	if not profile then return nil, "no such profile" end

	profile.name = uniqueName(ns.db.profiles, name, id)
	changed()
	return profile.name
end

-- A deleted profile (here, or on another computer by sync): a tombstone, every character's bindings for it gone, its
-- controllers on the first profile left (at: their pick's time). Returns true when this controller was on it.
function Profile.Forget(id, at)
	local db = ns.db
	local hit = Profile.CurrentId() == id
	db.profiles[id] = { gone = true }
	for _, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		if type(char) == "table" and type(char.cells) == "table" then char.cells[id] = nil end
	end
	local first = (Profile.List()[1] or NONE).id
	for key, pick in pairs(db.deviceProfile) do
		if pick.id == id then db.deviceProfile[key] = first and { id = first, at = at or 0 } or nil end
	end
	if db.lastProfile == id then db.lastProfile = first end
	return hit
end

-- Out of combat with the pad free: the apply that follows re-routes the bindings.
function Profile.Delete(id)
	if not live(id) then return nil, "no such profile" end
	if #Profile.List() < 2 then return nil, "the last profile can't be deleted" end

	ns.whenPadFree("profile-delete", function()
		if not live(id) or #Profile.List() < 2 then return end
		changed(Profile.Forget(id, serverTime()))
	end)
	return true
end

-- This controller (or key) plays on id from now on, on every computer: the player's pick.
function Profile.Use(id, key)
	key = key or (device() or NONE).key
	if not (live(id) and isPad(key)) then return nil, "no such profile" end

	ns.whenPadFree("profile-use", function()
		if not live(id) then return end
		local pad = device()
		local here = pad and pad.key == key
		local before = here and Profile.CurrentId()
		ns.db.deviceProfile[key] = { id = id, at = serverTime() }
		if here then ns.db.lastProfile = id end
		changed(here and before ~= id)
	end)
	return true
end

-- The known controllers: { { key, name, id }, ... } by name; id is the profile each plays on.
function Profile.Controllers()
	local out, pads = {}, type(ns.db.sync) == "table" and type(ns.db.sync.pads) == "table" and ns.db.sync.pads or NONE
	for key in pairs(ns.db.devices) do out[#out + 1] = { key = key, name = pads[key] or key, id = Profile.IdFor(key) } end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.key < b.key
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- SavedVariables

-- The name a pad's migrated profile gets: the controller's own name, else "Profile n" (n: the unnamed count so far).
function Profile.MigratedName(profiles, name, unnamed)
	if type(name) == "string" and name:find("%S") then return uniqueName(profiles, name), unnamed end
	unnamed = unnamed + 1
	return uniqueName(profiles, L.NUMBERED:format(unnamed)), unnamed
end

-- Every pad of an older store (a devices entry, or bindings of any character) becomes its own profile under its device
-- key, with the roles and face actions its devices entry held; a controller of this computer gets the addon's pick.
-- Lossless: char.cells keeps its keys. Runs once (Core's MIGRATIONS[3]), before Profile.Repair.
function Profile.Migrate(db)
	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	db.deviceProfile = type(db.deviceProfile) == "table" and db.deviceProfile or {}
	local devices = type(db.devices) == "table" and db.devices or NONE
	local pads = type(db.sync) == "table" and type(db.sync.pads) == "table" and db.sync.pads or NONE
	local keys, seen = {}, {}
	local function add(key)
		if isPad(key) and not seen[key] then keys[#keys + 1], seen[key] = key, true end
	end
	local function addAll(map) for key in pairs(type(map) == "table" and map or NONE) do add(key) end end
	addAll(devices)
	addAll(db.faceEntries)
	for _, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		if type(char) == "table" then
			addAll(char.cells)
			addAll(char.faceEntries)
		end
	end
	table.sort(keys)
	local unnamed = 0
	for _, key in ipairs(keys) do
		local entry = type(devices[key]) == "table" and devices[key] or nil
		if not db.profiles[key] then
			local name
			name, unnamed = Profile.MigratedName(db.profiles, pads[key], unnamed)
			db.profiles[key] = { name = name, roles = entry and type(entry.roles) == "table" and entry.roles or {}, face = entry and type(entry.face) == "table" and entry.face or {} }
		end
		if entry then
			entry.roles, entry.face = nil, nil
			db.deviceProfile[key] = db.deviceProfile[key] or { id = key, at = 0 }
		end
	end
end

-- Repairs the three stores into the shape above; fix(what) per repair. Bad entries are dropped.
function Profile.Repair(db, fix)
	for _, field in ipairs({ "profiles", "deviceProfile" }) do
		if type(db[field]) ~= "table" then
			if db[field] ~= nil then fix(field) end
			db[field] = {}
		end
	end
	for id, profile in pairs(db.profiles) do
		local repaired, fixes = ns.Layout.RepairProfile(profile, id)
		db.profiles[id] = repaired
		for _, what in ipairs(fixes) do fix("profiles." .. tostring(id) .. ": " .. what) end
	end
	for key, pick in pairs(db.deviceProfile) do
		if not (isPad(key) and type(pick) == "table" and isId(pick.id) and finite(pick.at)) then
			db.deviceProfile[key] = nil
			fix("deviceProfile." .. tostring(key))
		end
	end
	if db.lastProfile ~= nil and not isId(db.lastProfile) then
		db.lastProfile = nil
		fix("lastProfile")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Events and /fct

-- A controller with a pick becomes the last one used. A fresh computer waits for the login sync (it may bring the
-- profiles of another computer) before it makes its Default.
ns.On("FCT_LAYOUT_CHANGED", function(reason)
	if reason ~= "device" or not ns.db then return end
	local pad = device()
	local id = pad and picked(pad.key)
	if id then ns.db.lastProfile = id end
	if not ns.Sync or ns.Sync.Settled() then Profile.Ensure() end
end)
ns.On("FCT_SYNC_SETTLED", function() Profile.Ensure() end)

-- /fct profile lists the profiles (this controller's marked); /fct profile <name> switches this controller to one.
function ns.commands.profile(args)
	local wanted, current = table.concat(args, " "), Profile.CurrentId()
	local list = Profile.List()
	if wanted == "" then
		local names = {}
		for _, item in ipairs(list) do names[#names + 1] = item.id == current and L.PROFILE_THIS:format(item.name) or item.name end
		return ns.log(names[1] and L.PROFILE_LIST:format(table.concat(names, ", ")) or L.PROFILE_NONE)
	end
	for _, item in ipairs(list) do
		if item.name:lower() == wanted:lower() then
			if not device() then return ns.log(L.PROFILE_NO_PAD) end
			Profile.Use(item.id)
			return ns.log(L.PROFILE_SWITCHED:format(item.name))
		end
	end
	ns.log(L.PROFILE_UNKNOWN:format(wanted))
end
