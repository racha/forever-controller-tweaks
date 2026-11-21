-- Forever Controller Tweaks profiles, per character since 1.5.4: a layout (modifier roles, face-action positions) and
-- this character's bindings and touch buttons for it (char.cells[id], char.touchBars[id]). Which controller is plugged
-- in never picks one: the game reports one pad under several ids (Steam Link, Android, the pad itself). Hardware (raw
-- sources, family, detection, label style) stays per controller in ns.db.devices.
-- ns.db.chars[GUID].profiles[id] = { name, roles, face }; ns.db.chars[GUID].profile = the id this character plays on.
-- ns.db.lastLayout = { roles, face }: the layout of the character played last on this computer; a new character's
-- first profile starts from it.
-- Ids: p<n>, or a pad key for a profile from 1.5.1 (char.cells kept its keys). They are this character's only.
local _, ns = ...
local Profile = {}
ns.Profile = Profile

local L = {
	DEFAULT = "Default", NUMBERED = "Profile %d",
	PROFILE_LIST = "Profiles of this character: %s.", PROFILE_THIS = "%s (current)", PROFILE_NONE = "No profiles yet: this character makes its Default when it first plays.",
	PROFILE_SWITCHED = "This character now plays on the profile %s.", PROFILE_UNKNOWN = "No profile named %s (/fct profile lists them).",
	PROFILE_NO_CHAR = "The character isn't known yet: try again in a moment.",
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

local function charDB() return ns.Face and ns.Face.CharDB() end

-- This character's profiles table (made on first use), and the character; nil before the character is known.
local function store()
	local char = charDB()
	if not char then return end
	char.profiles = type(char.profiles) == "table" and char.profiles or {}
	return char.profiles, char
end

local function live(id)
	local profiles = isId(id) and store()
	local profile = profiles and profiles[id]
	if type(profile) == "table" then return profile end
end
Profile.Get = live

local function byName(a, b)
	local x, y = a.name:lower(), b.name:lower()
	if x ~= y then return x < y end
	return a.id < b.id
end

-- { { id, name }, ... } of this character's profiles, by name.
function Profile.List()
	local out = {}
	for id, profile in pairs(store() or NONE) do out[#out + 1] = { id = id, name = profile.name } end
	table.sort(out, byName)
	return out
end

-- The id this character plays on: its pick while it exists, else its first; nil before it has one.
function Profile.CurrentId()
	local char = charDB()
	if not char then return end
	if live(char.profile) then return char.profile end
	local first = Profile.List()[1]
	return first and first.id
end
-- char.cells is keyed by profile id.
Profile.CellsKey = Profile.CurrentId

function Profile.Current()
	local id = Profile.CurrentId()
	return live(id), id
end

local function changed(applied)
	ns.Fire("FCT_PROFILES_CHANGED")
	if applied then ns.Fire("FCT_LAYOUT_CHANGED", "device") end
end

local function newId(profiles)
	local n = serverTime()
	while profiles["p" .. n] do n = n + 1 end
	return "p" .. n
end

local function create(name, roles, face, id)
	local profiles = store()
	id = id or newId(profiles)
	profiles[id] = { name = uniqueName(profiles, name), roles = roles or {}, face = face or {} }
	return id
end

-- A character's first profile: Default, with the layout of the character played last here (ns.db.lastLayout), no
-- bindings. p1 on every computer, so two that make it before they sync share its bindings section. Writers call it;
-- returns Profile.Current().
function Profile.Ensure()
	local profiles, char = store()
	if not (profiles and ns.db) then return end
	if not next(profiles) then
		local last = type(ns.db.lastLayout) == "table" and ns.db.lastLayout or NONE
		char.profile = create(L.DEFAULT, copy(last.roles), copy(last.face), "p1")
		changed()
	elseif not live(char.profile) then
		char.profile = Profile.CurrentId()
	end
	return Profile.Current()
end

-- An empty profile: the native layout, no bindings. Returns its id.
function Profile.New(name)
	if not store() then return nil, "no character" end
	local id = create(name)
	changed()
	return id
end

-- A deep copy of from's layout and of this character's bindings and touch buttons for it. Returns its id.
function Profile.Copy(from, name)
	local source = live(from)
	if not source then return nil, "no such profile" end

	local char = charDB()
	local id = create(name or source.name, copy(source.roles), copy(source.face))
	if type(char.cells) == "table" and type(char.cells[from]) == "table" then char.cells[id] = copy(char.cells[from]) end
	if type(char.touchBars) == "table" and type(char.touchBars[from]) == "table" then char.touchBars[id] = copy(char.touchBars[from]) end
	changed()
	return id
end

function Profile.Rename(id, name)
	local profile = live(id)
	if not profile then return nil, "no such profile" end

	profile.name = uniqueName(store(), name, id)
	changed()
	return profile.name
end

-- Removes a profile of this character with its bindings and touch buttons; the character moves to the first one left
-- when it was on it. Returns true then.
function Profile.Forget(id)
	local profiles, char = store()
	if not profiles then return false end
	local hit = Profile.CurrentId() == id
	profiles[id] = nil
	if type(char.cells) == "table" then char.cells[id] = nil end
	if type(char.touchBars) == "table" then char.touchBars[id] = nil end
	if hit or char.profile == id then char.profile = Profile.CurrentId() end
	return hit
end

-- Out of combat with the pad free: the apply that follows re-routes the bindings.
function Profile.Delete(id)
	if not live(id) then return nil, "no such profile" end
	if #Profile.List() < 2 then return nil, "the last profile can't be deleted" end

	ns.whenPadFree("profile-delete", function()
		if not live(id) or #Profile.List() < 2 then return end
		changed(Profile.Forget(id))
	end)
	return true
end

-- This character plays on id from now on, with any controller.
function Profile.Use(id)
	if not live(id) then return nil, "no such profile" end

	ns.whenPadFree("profile-use", function()
		local char = live(id) and charDB()
		if not char then return end
		local before = Profile.CurrentId()
		char.profile = id
		changed(before ~= id)
	end)
	return true
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
-- Lossless: char.cells keeps its keys. Runs once (Core's MIGRATIONS[3]); MIGRATIONS[5] moves the result to the
-- characters.
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

-- Entries in one grid (rows[code][layer] = entry): what a character's bindings or one touch side hold.
local function entries(rows)
	local n = 0
	for _, row in pairs(type(rows) == "table" and rows or NONE) do
		for _, entry in pairs(type(row) == "table" and row or NONE) do if type(entry) == "table" then n = n + 1 end end
	end
	return n
end

local function touchEntries(sides)
	local n = 0
	for _, list in pairs(type(sides) == "table" and sides or NONE) do n = n + entries(list) end
	return n
end

-- How many bindings and touch buttons a character record holds in profile id.
function Profile.BindingsIn(char, id)
	local cells, bars = type(char.cells) == "table" and char.cells or NONE, type(char.touchBars) == "table" and char.touchBars or NONE
	local old = type(char.faceEntries) == "table" and type(char.faceEntries[id]) == "table" and char.faceEntries[id] or NONE
	local n = 0
	for _, entry in pairs(old) do if type(entry) == "table" then n = n + 1 end end
	return entries(cells[id]) + touchEntries(bars[id]) + n
end

-- Bindings that arrive under a profile id the character lacks (1.5.0's face entries, moved to cells[pad] by Face) get
-- a profile of that id with the last layout here, and the character plays on it while its own has no bindings.
function Profile.Adopt(char, id)
	if not isId(id) then return end
	char.profiles = type(char.profiles) == "table" and char.profiles or {}
	local profiles, mine = char.profiles, char.profile
	if profiles[id] == nil then
		local last = ns.db and type(ns.db.lastLayout) == "table" and ns.db.lastLayout or NONE
		local pad = ns.Sync and ns.Sync.PadName(id)
		profiles[id] = { name = (Profile.MigratedName(profiles, pad ~= id and pad or nil, 0)), roles = copy(last.roles) or {}, face = copy(last.face) or {} }
	end
	if not (type(mine) == "string" and profiles[mine]) or mine ~= id and Profile.BindingsIn(char, mine) == 0 then char.profile = id end
	changed()
end

local function sortedKeys(map)
	local out = {}
	for key in pairs(map) do out[#out + 1] = key end
	table.sort(out)
	return out
end

-- 1.5.1-1.5.3's account profiles (db.profiles, picked per controller in db.deviceProfile) go to the characters: every
-- record (GUID ones and the Name- records waiting for a claim) gets a copy of each profile it has bindings or touch
-- buttons in, and plays on db.lastProfile if that is one of them, else on the one with the most bindings. A profile id
-- with bindings but no profile left (only a b: section synced) becomes one named after its controller, so no binding
-- is ever hidden; a tombstone's bindings were deleted with it. db.lastLayout keeps the layout of db.lastProfile (else
-- the first live profile) for new characters. Copies before it deletes; idempotent. Core's MIGRATIONS[5].
function Profile.MoveToChars(db)
	local profiles = type(db.profiles) == "table" and db.profiles or NONE
	local pads = type(db.sync) == "table" and type(db.sync.pads) == "table" and db.sync.pads or NONE
	local last = db.lastProfile
	local function alive(id) return type(profiles[id]) == "table" and not profiles[id].gone end
	for _, key in ipairs(sortedKeys(type(db.chars) == "table" and db.chars or NONE)) do
		local char = db.chars[key]
		if type(char) == "table" then
			local used = {}
			for id in pairs(type(char.cells) == "table" and char.cells or NONE) do used[id] = true end
			for id in pairs(type(char.touchBars) == "table" and char.touchBars or NONE) do used[id] = true end
			for id in pairs(type(char.faceEntries) == "table" and char.faceEntries or NONE) do used[id] = true end
			local own = type(char.profiles) == "table" and char.profiles or {}
			local count, unnamed = {}, 0
			for _, id in ipairs(sortedKeys(used)) do
				local n = Profile.BindingsIn(char, id)
				local gone = type(profiles[id]) == "table" and profiles[id].gone
				if n > 0 and isId(id) and not gone then
					count[id] = n
					if own[id] == nil and alive(id) then
						local from = profiles[id]
						own[id] = { name = uniqueName(own, from.name), roles = copy(type(from.roles) == "table" and from.roles or {}), face = copy(type(from.face) == "table" and from.face or {}) }
					elseif own[id] == nil then
						local name
						name, unnamed = Profile.MigratedName(own, pads[id], unnamed)
						own[id] = { name = name, roles = {}, face = {} }
					end
				end
			end
			if next(own) then char.profiles = own end
			if not (type(char.profile) == "string" and own[char.profile]) then
				local pick, most = count[last] and own[last] and last, nil
				for _, id in ipairs(sortedKeys(count)) do
					if not most or count[id] > count[most] then most = id end
				end
				char.profile = pick or most
			end
		end
	end
	if type(db.lastLayout) ~= "table" then
		local from = alive(last) and last
		for _, id in ipairs(sortedKeys(profiles)) do from = from or alive(id) and id end
		if from then db.lastLayout = { roles = copy(profiles[from].roles), face = copy(profiles[from].face) } end
	end
	db.profiles, db.deviceProfile, db.lastProfile = nil, nil, nil
end

-- Repairs every character's profiles, its pick and ns.db.lastLayout into the shape above; fix(what) per repair. Bad
-- entries are dropped (Core's load repair already dropped a profiles field that isn't a table).
function Profile.Repair(db, fix)
	for key, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		local path = "chars." .. tostring(key)
		for id, profile in pairs(type(char.profiles) == "table" and char.profiles or NONE) do
			local repaired, fixes = ns.Layout.RepairProfile(profile, id)
			if repaired and repaired.gone then repaired, fixes = nil, { "gone" } end
			char.profiles[id] = repaired
			for _, what in ipairs(fixes) do fix(path .. ".profiles." .. tostring(id) .. ": " .. what) end
		end
		if char.profile ~= nil and not (type(char.profile) == "string" and type(char.profiles) == "table" and char.profiles[char.profile]) then
			char.profile = nil
			fix(path .. ".profile")
		end
	end
	local last = db.lastLayout
	if last == nil then return end
	local repaired = type(last) == "table" and ns.Layout.RepairProfile({ name = L.DEFAULT, roles = last.roles, face = last.face }, "p1")
	local fresh = repaired and { roles = repaired.roles, face = repaired.face }
	if not (fresh and ns.Layout.Same(fresh, last)) then fix("lastLayout") end
	db.lastLayout = fresh or nil
end

---------------------------------------------------------------------------------------------------------------------
-- Events and /fct

-- A fresh character waits for the login sync (it may bring this character's profiles from another computer) before
-- it makes its Default.
ns.On("FCT_LAYOUT_CHANGED", function(reason)
	if reason ~= "device" or not ns.db then return end
	if not ns.Sync or ns.Sync.Settled() then Profile.Ensure() end
end)
ns.On("FCT_SYNC_SETTLED", function() Profile.Ensure() end)
-- The next new character on this computer starts from this one's layout.
ns.On("PLAYER_LOGOUT", function()
	local profile = ns.db and Profile.Current()
	if profile then ns.db.lastLayout = { roles = copy(profile.roles), face = copy(profile.face) } end
end)

-- /fct profile lists this character's profiles (the current one marked); /fct profile <name> switches to one.
function ns.commands.profile(args)
	local wanted, current = table.concat(args, " "), Profile.CurrentId()
	if not charDB() then return ns.log(L.PROFILE_NO_CHAR) end
	local list = Profile.List()
	if wanted == "" then
		local names = {}
		for _, item in ipairs(list) do names[#names + 1] = item.id == current and L.PROFILE_THIS:format(item.name) or item.name end
		return ns.log(names[1] and L.PROFILE_LIST:format(table.concat(names, ", ")) or L.PROFILE_NONE)
	end
	for _, item in ipairs(list) do
		if item.name:lower() == wanted:lower() then
			Profile.Use(item.id)
			return ns.log(L.PROFILE_SWITCHED:format(item.name))
		end
	end
	ns.log(L.PROFILE_UNKNOWN:format(wanted))
end
