-- Forever Controller Tweaks keyboard context (design/suggestions.md): the situation the player is typing in, and
-- the kind of field they are typing into. Events only mark a section stale, set a prompt or file an incoming chat
-- line; the game is read when the keyboard asks for a snapshot, never per frame. Every game value passes plain(): a
-- secret value (chat and unit names are secret in a messaging lockdown) counts as unknown. Frames are only read
-- (names, parents, attributes), never written. Nothing here is saved: incoming lines live in memory for three minutes.
local ns = ForeverControllerTweaks
local K = ns.Keyboard
local P = K.Library
local C = { rev = 0 }
K.Context = C

C.INBOX, C.HEARD_TTL, C.NEARBY_TTL, C.NPC_CAP, C.TEXT_MAX = 8, 180, 30, 40, 160
C.WHISPERERS, C.ITEMS, C.FRIENDS, C.GUILD, C.BLOCKED, C.QUEST_WAIT = 10, 200, 200, 300, 30, 0.5
-- What just happened: how long its lines last, the least item quality worth a line, and buffs: the shortest worth
-- thanks (a heal over time is not), and how long before the same caster's same buff is thanked again.
C.REACT_TTL, C.LOOT_QUALITY, C.BUFF_MIN, C.THANKS_WAIT = 60, 3, 120, 300
local HEALS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }
local TANKS = { WARRIOR = true, DRUID = true, PALADIN = true }
local ROLES = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
local GROUP_KINDS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
-- Who a rule's line must be for, against who a heard line was for: a rule reaches its own scope and every closer one.
local REACH = { direct = 1, group = 2, public = 3 }
local SECTIONS = { "place", "group", "self", "target", "quest", "lfg", "channels", "items", "names" }
-- Sections only some fields use: read when the box is one of them.
local ONLY = { items = { bag = true, auction = true }, names = { name = true } }

-- The field a box is, by the lowercased names of the box and its parents (first match), then by a dialog's type.
-- Frames checked in this client's UI source; an unnamed search box is known by the search template's parts.
local FIELD_NAMES = {
	{ "bagitemsearchbox", "bag" }, { "bankitemsearchbox", "bag" }, { "auctionhouseframe", "auction" },
	{ "sendmailnameeditbox", "name" }, { "whoframeeditbox", "name" }, { "addfriendnameeditbox", "name" }, { "calendarcreateeventinviteedit", "name" },
	{ "sendmailsubjecteditbox", "text" }, { "sendmailbodyeditbox", "text" }, { "macroframetext", "text" }, { "communities", "text" },
	{ "search", "search" },
}
local FIELD_DIALOGS = {
	ADD_FRIEND = "name", ADD_IGNORE = "name", ADD_GUILDMEMBER = "name", CHANNEL_INVITE = "name", INVITE_COMMUNITY_MEMBER = "name",
	SET_FRIENDNOTE = "text", SET_BNFRIENDNOTE = "text", SET_GUILDPLAYERNOTE = "text", SET_GUILDOFFICERNOTE = "text", SET_COMMUNITY_MEMBER_NOTE = "text",
}

local state = { prompts = {}, inbox = {}, channels = {}, whisperers = {}, items = {}, names = {}, group = "none", instance = "none", size = 0 }
local dirty, npcKinds, npcCount, nearby, focused, focus = {}, {}, 0, nil, nil, "unknown"
for _, section in ipairs(SECTIONS) do dirty[section] = true end
C.state = state

-- Always one value: a secret becomes nil (never "no value", which tonumber and the like refuse).
local function plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local function plain3(a, b, c) return plain(a), plain(b), plain(c) end

local function api(name, ...)
	local fn = _G[name]
	if fn then return plain3(fn(...)) end
end

local function filled(value) if type(value) == "string" and value ~= "" then return value end end

-- A call that may be missing or fail on this client: its first five results, each plain.
local function try(fn, ...)
	local ok, a, b, c, d, e = pcall(fn, ...)
	if not ok then return nil end
	return plain(a), plain(b), plain(c), plain(d), plain(e)
end

-- rev changes whenever the suggestions could: an open keyboard compares it and asks again.
local function bump() C.rev = C.rev + 1 end

local function mark(section)
	dirty[section] = true
	bump()
end

local function markAll() for _, section in ipairs(SECTIONS) do mark(section) end end

local function listening()
	local s = ns.db and ns.db.keyboard
	return s and s.enabled ~= false and s.suggestions ~= false and ns.Active()
end

local function unit(token)
	local name, realm = api("UnitName", token)
	if not name then return end
	local player, kind = api("UnitIsPlayer", token) and true or false, api("UnitClassification", token)
	return {
		name = name, full = filled(realm) and name .. "-" .. realm or name, player = player, level = api("UnitLevel", token),
		friendly = api("UnitIsFriend", "player", token) and true or false, hostile = api("UnitCanAttack", "player", token) and true or false,
		dead = api("UnitIsDead", token) and true or false, self = api("UnitIsUnit", token, "player") and true or false,
		elite = kind == "elite" or kind == "rareelite" or kind == "worldboss", npc = not player and npcKinds[name] or nil,
	}
end

local READ = {}

function READ.place(s)
	local inside, kind = api("IsInInstance")
	s.zone, s.subzone = filled(api("GetRealZoneText")) or filled(api("GetZoneText")), filled(api("GetSubZoneText"))
	s.resting = api("IsResting") and true or false
	s.instance, s.instanceName = inside and kind or "none", inside and filled(api("GetInstanceInfo")) or nil
end

function READ.group(s)
	local raid, grouped = api("IsInRaid"), api("IsInGroup")
	s.group = raid and "raid" or grouped and "party" or "none"
	s.groupChannel = grouped and (api("IsInGroup", LE_PARTY_CATEGORY_INSTANCE or 2) and "INSTANCE_CHAT" or raid and "RAID" or "PARTY") or nil
	s.size, s.leader = api("GetNumGroupMembers") or 0, api("UnitIsGroupLeader", "player") and true or false
	s.assigned = ROLES[api("UnitGroupRolesAssigned", "player")]
	s.role = s.assigned or "damage"
	if not grouped then s.joinedAt = nil end
end

-- The specialization's name and role, else the talent tree with the most points (its tab info is name, icon, points
-- on an older client, id, name, description, icon, points on a newer one).
local function specOf()
	local info = C_SpecializationInfo or {}
	local index = try(info.GetSpecialization or GetSpecialization)
	if type(index) == "number" and index > 0 then
		local _, name, _, _, role = try(info.GetSpecializationInfo or GetSpecializationInfo, index)
		if filled(name) then return name, ROLES[role] end
	end
	local best, most = nil, 0
	for i = 1, tonumber(try(GetNumTalentTabs)) or 0 do
		local a, b, c, _, e = try(GetTalentTabInfo, i)
		local name, points = filled(a) or filled(b), tonumber(filled(a) and c or e) or 0
		if name and points > most then best, most = name, points end
	end
	return best
end

function READ.self(s)
	s.me, s.level = api("UnitName", "player"), api("UnitLevel", "player")
	s.className, s.class = api("UnitClass", "player")
	s.guild, s.combat = api("IsInGuild") and true or false, api("UnitAffectingCombat", "player") and true or false
	s.dead = api("UnitIsDeadOrGhost", "player") and true or false
	s.canHeal, s.canTank, s.canRes = HEALS[s.class] or false, TANKS[s.class] or false, HEALS[s.class] or false
	s.spec, s.specRole = specOf()
	local _, equipped = try(GetAverageItemLevel)
	s.ilvl = type(equipped) == "number" and equipped > 0 and math.floor(equipped) or nil
end

function READ.target(s) s.target = unit("target") end

-- One C_QuestLog call, guarded: a missing function or an error counts as unknown.
local function questLog(name, ...)
	local fn = C_QuestLog and C_QuestLog[name]
	if not fn then return end
	local ok, value = pcall(fn, ...)
	if ok then return plain(value) end
end

-- An objective's text without its count ("3/8 Defias Pillager slain", "Defias Pillager slain: 3/8") and without
-- the English "slain", so it reads as a name: "Need 5 more Defias Pillager".
local function objectiveName(text) return (text:gsub("^%d+/%d+%s+", ""):gsub("%s*:%s*%d+/%d+$", ""):gsub(" slain$", "")) end

-- Quest lines come only from the quest the player is super-tracking: its name, its first unfinished objective
-- (objective, have, need), whether it is done, and whether a party member is on it. changedAt is when its counts
-- last moved while it was tracked.
local questSeen = {}

function READ.quest(s)
	local track = C_SuperTrack
	local ok, id = pcall(track and track.GetSuperTrackedQuestID or function() end)
	id, s.quest = ok and plain(id), nil
	if not (type(id) == "number" and id > 0) then return end
	local title, link = filled(questLog("GetTitleForQuestID", id)), filled(api("GetQuestLink", id))
	if not (title or link) then return end

	local quest, counts, open = { id = id, title = title, link = link }, {}, 0
	for i, entry in ipairs(questLog("GetQuestObjectives", id) or {}) do
		local text, have, need, finished = filled(plain(entry.text)), tonumber(plain(entry.numFulfilled)), tonumber(plain(entry.numRequired)), plain(entry.finished)
		counts[i] = tostring(have) .. "/" .. tostring(need)
		if not finished then open = open + 1 end
		if not finished and text and not quest.objective then quest.objective, quest.have, quest.need = objectiveName(text), have, need end
	end
	quest.done = (questLog("IsComplete", id) or questLog("ReadyForTurnIn", id) or #counts > 0 and open == 0) and true or false
	for i = 1, s.group == "party" and 4 or 0 do quest.shared = quest.shared or questLog("IsUnitOnQuest", "party" .. i, id) and true or false end

	local signature = table.concat(counts, " ") .. (quest.done and " done" or "")
	if questSeen.id == id and questSeen.signature ~= signature then questSeen.changedAt = GetTime() end
	if questSeen.id ~= id then questSeen.changedAt = nil end
	questSeen.id, questSeen.signature, quest.changedAt = id, signature, questSeen.changedAt
	s.quest = quest
end

function READ.lfg(s)
	local mode, list = api("GetLFGMode", LE_LFG_CATEGORY_LFD or 1), C_LFGList
	local listed = list and list.HasActiveEntryInfo and plain(list.HasActiveEntryInfo())
	s.lfg = (mode == "queued" or mode == "rolecheck" or mode == "proposal") and "queued" or listed and "listed" or nil
end

-- The joined city channels by their English names; another locale's names don't match and those lines keep the
-- box's own channel.
local CHANNEL_NAMES = { lfg = "^lookingforgroup", trade = "^trade", general = "^general" }

function READ.channels(s)
	local list, found = GetChannelList and { GetChannelList() } or {}, {}
	for i = 1, #list, 3 do
		local id, name = plain(list[i]), plain(list[i + 1])
		if type(id) == "number" and type(name) == "string" then
			for key, pattern in pairs(CHANNEL_NAMES) do if name:lower():find(pattern) then found[key] = id end end
		end
	end
	s.channels = found
end

-- The realm's time of day, for "Good {time}".
-- What the bags hold, by name: what a bag or auction search is most likely for.
function READ.items(s)
	local bags, list, seen = C_Container, {}, {}
	for bag = 0, bags and bags.GetContainerNumSlots and bags.GetContainerItemInfo and (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) or -1 do
		for slot = 1, plain(bags.GetContainerNumSlots(bag)) or 0 do
			local info = bags.GetContainerItemInfo(bag, slot)
			local name = info and (filled(plain(info.itemName)) or (plain(info.hyperlink) or ""):match("%[(.-)%]"))
			if name and not seen[name] and #list < C.ITEMS then list[#list + 1], seen[name] = name, true end
		end
	end
	table.sort(list)
	s.items = list
end

-- People a name field is likely for, nearest first: the group, friends, the guild. (Whoever whispered comes before
-- them, from state.whisperers.)
function READ.names(s)
	local list, seen, realm, friends = {}, {}, filled(api("GetNormalizedRealmName")), C_FriendList
	local function add(name, tag)
		name = filled(plain(name))
		if not name then return end
		local short, home = name:match("^([^-]+)-(.+)$")
		if home == realm then name = short end
		if name ~= s.me and not seen[name] then list[#list + 1], seen[name] = { name = name, tag = tag }, true end
	end
	for i = 1, s.group == "raid" and s.size or 0 do add(api("GetRaidRosterInfo", i), "Group") end
	for i = 1, s.group == "party" and 4 or 0 do
		local name, home = api("UnitName", "party" .. i)
		add(name and filled(home) and name .. "-" .. home or name, "Group")
	end
	for i = 1, math.min(friends and friends.GetNumFriends and friends.GetFriendInfoByIndex and plain(friends.GetNumFriends()) or 0, C.FRIENDS) do
		local info = friends.GetFriendInfoByIndex(i)
		add(info and info.name, "Friend")
	end
	for i = 1, math.min(s.guild and api("GetNumGuildMembers") or 0, C.GUILD) do add(api("GetGuildRosterInfo", i), "Guild") end
	s.names = list
end

local function timeOfDay()
	local hour = api("GetGameTime") or tonumber((date or os.date)("%H"))
	return hour < 5 and "night" or hour < 12 and "morning" or hour < 18 and "afternoon" or hour < 23 and "evening" or "night"
end

-- The player's map position as "39, 55", read only while someone asked where they are.
local function coords()
	local map = C_Map or {}
	local id = try(map.GetBestMapForUnit, "player")
	local position = id and try(map.GetPlayerMapPosition, id, "player")
	local x, y
	if type(position) == "table" and position.GetXY then x, y = try(position.GetXY, position) else x, y = try(GetPlayerMapPosition, "player") end
	if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then return math.floor(x * 100 + 0.5) .. ", " .. math.floor(y * 100 + 0.5) end
end

local function asked(inbox, id) for _, msg in ipairs(inbox) do if msg.intents[id] then return true end end end

-- Everyone in the group dead or a ghost: a wipe, even with no boss.
local function wiped(s)
	local prefix = s.group == "raid" and "raid" or "party"
	for i = 1, s.group == "raid" and s.size or 4 do
		local token = prefix .. i
		if api("UnitExists", token) and not api("UnitIsUnit", token, "player") and not api("UnitIsDeadOrGhost", token) then return false end
	end
	return true
end

local function low(current, most, part) return current ~= nil and most ~= nil and most > 0 and current / most < part end

-- The lowercased names of a box and its parents, nearest first.
local function pathOf(box)
	local names, frame = {}, box
	for _ = 1, 6 do
		names[#names + 1] = frame and frame.GetName and filled(plain(frame:GetName())) or nil
		frame = frame and frame.GetParent and frame:GetParent()
	end
	return table.concat(names, " "):lower()
end

local function classify(box)
	if box.IsNumeric and plain(box:IsNumeric()) then return "numeric" end
	if box.GetAttribute and plain(box:GetAttribute("chatType")) then return "chat" end
	local path, parent = pathOf(box), box.GetParent and box:GetParent()
	for _, rule in ipairs(FIELD_NAMES) do if path:find(rule[1], 1, true) then return rule[2] end end
	local dialog = parent and FIELD_DIALOGS[plain(parent.which) or ""]
	if dialog then return dialog end
	if box.IsMultiLine and plain(box:IsMultiLine()) then return "text" end
	return (box.searchIcon or box.clearButton) and "search" or "unknown"
end

-- Boxes the keyboard must not type into. A box's own text handlers run inside our Insert / SetText call, so
-- whatever they reach runs as addon code; when that is protected or gamepad-focus code the game blocks it ("has been
-- blocked from an action only available to the Blizzard UI"). No addon can put text in such a box cleanly.
local function unsafe(box)
	-- Spell book, talent and legacy tree search (SpellSearchBoxMixin): OnTextChanged shows the preview list
	-- (Blizzard_SpellSearchTemplates.lua:313 -> :388), whose OnShow drives GamepadMode.FrameControlsManager (:73-79).
	local spellSearch, frame = SpellSearchBoxMixin, box
	if spellSearch and box.OnTextChanged == spellSearch.OnTextChanged then return true end
	for _ = 1, 10 do
		if not frame then return false end
		-- Options (and the key bindings in it): the search box's OnTextChanged rebuilds the settings list, binding rows
		-- included, in the same call (Blizzard_SettingsPanel.lua:83 -> :686 OnSearchTextChanged -> :933 DisplayLayout).
		-- The group finder: its search and name boxes are securityDisableSetText (LFGList.xml:1067, :1730).
		if frame == SettingsPanel or frame == LFGListFrame then return true end
		frame = frame.GetParent and frame:GetParent()
	end
	return false
end

local verdicts = setmetatable({}, { __mode = "k" })

local function listed(settings, key)
	for _, saved in ipairs(type(settings.blocked) == "table" and settings.blocked or {}) do if saved == key then return true end end
	return false
end

-- A dialog's edit box is one frame for many dialogs: its key carries the dialog's type.
local function keyOf(box, which) return pathOf(box) .. (which and " " .. which or "") end

-- True for a box on the list above, or one the game blocked us in before (C.Deny): by frame this session, by its
-- name key (settings.blocked) after a reload. The verdict is kept per frame, and per dialog type for a dialog's box.
function C.Denied(box, settings)
	local parent = box.GetParent and box:GetParent()
	local which, seen = parent and plain(parent.which) or false, verdicts[box]
	if seen and seen.which == which then return seen.denied end
	local key = keyOf(box, which)
	local denied = unsafe(box) or key ~= "" and listed(settings, key)
	verdicts[box] = { which = which, denied = denied }
	return denied
end

-- Chat is a supported box: a block seen while typing there (ChatFrame1EditBox, ...) is never blamed on it.
local function chatKey(key) return (key .. " "):find("^chatframe%d+editbox ") ~= nil end

-- The game blocked an action right after the keyboard changed this box's text: never type into it again. Its key
-- is saved (the newest C.BLOCKED); a box with no name anywhere in its parents is remembered for the session only.
function C.Deny(box, settings)
	local parent = box.GetParent and box:GetParent()
	local which = parent and plain(parent.which) or false
	local key = keyOf(box, which)
	if chatKey(key) then return end
	verdicts[box] = { which = which, denied = true }
	if key == "" or listed(settings, key) then return end
	settings.blocked = type(settings.blocked) == "table" and settings.blocked or {}
	table.insert(settings.blocked, 1, key)
	settings.blocked[C.BLOCKED + 1] = nil
end

-- Chat boxes saved by an older version, which could deny them, are dropped.
function C.Forget(settings)
	local saved = settings.blocked
	if type(saved) ~= "table" then return end
	for i = #saved, 1, -1 do if type(saved[i]) == "string" and chatKey(saved[i]) then table.remove(saved, i) end end
end

-- The box that took the focus: its field is worked out once, here. "chat" becomes "whisper" in a snapshot while the
-- box is on a whisper.
function C.Focus(box) focused, focus = box, classify(box) end

-- The situation now, for the box being typed in. The returned table is the live state: read it, don't keep it.
function C.Snapshot(box)
	local s, now = state, GetTime()
	if box ~= focused then C.Focus(box) end
	local kind = focus == "chat" and plain(box:GetAttribute("chatType")) or nil
	s.field = kind and ((kind == "WHISPER" or kind == "BN_WHISPER") and "whisper" or "chat") or focus ~= "chat" and focus or "unknown"
	for _, section in ipairs(SECTIONS) do
		if dirty[section] and (not ONLY[section] or ONLY[section][s.field]) then
			READ[section](s)
			dirty[section] = nil
		end
	end
	for i = #s.inbox, 1, -1 do if now - s.inbox[i].at > C.HEARD_TTL then table.remove(s.inbox, i) end end
	for kind, prompt in pairs(s.prompts) do if now - prompt.at > prompt.ttl then s.prompts[kind] = nil end end
	s.coords = asked(s.inbox, "where") and coords() or nil
	s.wiped = s.dead and s.group ~= "none" and wiped(s)

	local target = s.target
	s.now, s.day = now, math.floor((time or os.time)() / 86400)
	s.time = timeOfDay()
	s.lowHealth = not s.dead and low(api("UnitHealth", "player"), api("UnitHealthMax", "player"), 0.35)
	s.lowMana = low(api("UnitPower", "player", 0), api("UnitPowerMax", "player", 0), 0.25)
	s.npc = target and not target.player and target.friendly and not target.dead and { name = target.name, kind = target.npc }
		or nearby and now - nearby.at < C.NEARBY_TTL and nearby or nil
	s.box = kind and { chat = true, kind = kind, target = plain(box:GetAttribute("tellTarget")), channel = plain(box:GetAttribute("channelTarget")) } or { chat = false }
	return s
end

-- A prompt waiting on the player (ready check, loot roll, resurrect, trade, duel, invite, summon, queue pop), or
-- something that just happened (a level, a boss, a drop, a buff). fills: token values only it knows ({ level = 18 }).
function C.Prompt(kind, from, ttl, fills)
	state.prompts[kind] = { at = GetTime(), from = filled(plain(from)), ttl = tonumber(plain(ttl)) or 60, fills = fills }
	bump()
end

function C.Clear(kind)
	if not state.prompts[kind] then return end
	state.prompts[kind] = nil
	bump()
end

local function anyOf(list, words) for _, word in ipairs(list) do if words[word] then return true end end end

local function matches(rule, lower, words, count, question)
	if rule.question and not question or rule.unless and anyOf(rule.unless, words) then return false end
	for _, part in ipairs(rule.has or {}) do if lower:find(part, 1, true) then return true end end
	if not rule.any then return not rule.has end
	return not (rule.max and count > rule.max) and anyOf(rule.any, words) and (not rule.with or anyOf(rule.with, words))
end

-- The intents of one line: { [intent id] = its rule }.
function C.Intents(line)
	local lower, words, count, found, groups = line:lower(), {}, 0, {}, {}
	for word in lower:gmatch("[%w']+") do words[word], count = true, count + 1 end
	local question = lower:find("?", 1, true) ~= nil
	for _, rule in ipairs(P.INTENTS) do
		local id, group = rule.id, rule.group
		if not found[id] and not (group and groups[group]) and matches(rule, lower, words, count, question) then
			found[id] = rule
			if group then groups[group] = true end
		end
	end
	return found
end

local function mentions(lower, name)
	local first, last = lower:find(name, 1, true)
	return first ~= nil and not lower:sub(first - 1, first - 1):match("%a") and not lower:sub(last + 1, last + 1):match("%a")
end

-- An incoming chat line. Kept (newest first, at most C.INBOX) only when it is a whisper or carries an intent that
-- reaches the player: a line naming them, group chat, or a public call such as "LF healer".
function C.Hear(kind, message, sender, channel)
	message, sender = plain(message), plain(sender)
	if type(message) ~= "string" or type(sender) ~= "string" or not listening() then return end
	local s = state
	if dirty.self then
		READ.self(s)
		dirty.self = nil
	end
	local me, line, name = s.me, message:sub(1, C.TEXT_MAX), kind ~= "BN_WHISPER" and sender:match("^[^-]+") or nil
	if name and name == me then return end
	local whisper = kind == "WHISPER" or kind == "BN_WHISPER"
	local direct = whisper or me ~= nil and mentions(line:lower(), me:lower())
	local reach, intents = REACH[direct and "direct" or GROUP_KINDS[kind] and "group" or "public"], {}
	for id, rule in pairs(C.Intents(line)) do if REACH[rule.scope or "group"] >= reach then intents[id] = rule end end
	if not (whisper or next(intents)) then return end
	table.insert(s.inbox, 1, { text = line, from = sender, name = name, kind = kind, at = GetTime(), intents = intents, channel = tonumber(plain(channel)), direct = direct })
	s.inbox[C.INBOX + 1] = nil
	if kind == "WHISPER" then
		local recent, short, home = s.whisperers, sender:match("^([^-]+)-(.+)$")
		local who = home == api("GetNormalizedRealmName") and short or sender
		for i = #recent, 1, -1 do if recent[i] == who then table.remove(recent, i) end end
		table.insert(recent, 1, who)
		recent[C.WHISPERERS + 1] = nil
	end
	bump()
end

local function met(kind)
	local name = api("UnitName", "npc") or api("UnitName", "target")
	if not name then return end
	if not npcKinds[name] then
		if npcCount >= C.NPC_CAP then npcKinds, npcCount = {}, 0 end
		npcCount = npcCount + 1
	end
	npcKinds[name], nearby = kind, { name = name, kind = kind, at = GetTime() }
	mark("target")
end

ns.On("PLAYER_ENTERING_WORLD", markAll)
for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING" }) do ns.On(event, function() mark("place") end) end
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do ns.On(event, function() mark("group") end) end
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE" }) do ns.On(event, function() dirty.names = true end) end
ns.On("BAG_UPDATE_DELAYED", function() dirty.items = true end)
ns.On("GROUP_ROSTER_UPDATE", function() dirty.quest = true end)
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_LEVEL_UP", "PLAYER_GUILD_UPDATE" }) do ns.On(event, function() mark("self") end) end
-- Events another client may not have: registering an unknown one is an error there.
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do pcall(ns.On, event, function() mark("self") end) end
for _, event in ipairs({ "LFG_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }) do ns.On(event, function() mark("lfg") end) end
ns.On("PLAYER_TARGET_CHANGED", function() mark("target") end)
ns.On("SUPER_TRACKING_CHANGED", function() mark("quest") end)

-- Quest log events come in bursts: the quest is marked stale once, C.QUEST_WAIT after the first of a burst.
local questPending = false
local function questChanged()
	if questPending then return end
	questPending = true
	C_Timer.After(C.QUEST_WAIT, function()
		questPending = false
		mark("quest")
	end)
end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_TURNED_IN" }) do ns.On(event, questChanged) end
ns.On("CHANNEL_UI_UPDATE", function() mark("channels") end)

ns.On("GROUP_JOINED", function()
	state.joinedAt = GetTime()
	C.Clear("invite")
	mark("group")
end)
ns.On("GROUP_LEFT", function() mark("group") end)

for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
	ns.On(event, function()
		C.Clear("resurrect")
		mark("self")
	end)
end

ns.On("READY_CHECK", function(from, left)
	local name = plain(from)
	if not (name and name:match("^[^-]+") == api("UnitName", "player")) then C.Prompt("ready", name, tonumber(plain(left)) or 30) end
end)
ns.On("READY_CHECK_FINISHED", function() C.Clear("ready") end)
ns.On("START_LOOT_ROLL", function(_, duration) C.Prompt("roll", nil, (tonumber(plain(duration)) or 60000) / 1000) end)
ns.On("RESURRECT_REQUEST", function(from) C.Prompt("resurrect", from, 60) end)
ns.On("CONFIRM_SUMMON", function() C.Prompt("summon", nil, 120) end)
ns.On("CANCEL_SUMMON", function() C.Clear("summon") end)
ns.On("PARTY_INVITE_REQUEST", function(from) C.Prompt("invite", from, 60) end)
ns.On("DUEL_REQUESTED", function(from) C.Prompt("duel", from, 60) end)
ns.On("DUEL_FINISHED", function() C.Clear("duel") end)
ns.On("TRADE_SHOW", function() C.Prompt("trade", api("UnitName", "NPC"), 300) end)
ns.On("TRADE_CLOSED", function() C.Clear("trade") end)
ns.On("LFG_PROPOSAL_SHOW", function() C.Prompt("proposal", nil, 40) end)
for _, event in ipairs({ "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED" }) do ns.On(event, function() C.Clear("proposal") end) end

-- What just happened. A handler only files a prompt: no frame, no chat box.
ns.On("PLAYER_LEVEL_UP", function(level) C.Prompt("levelup", nil, C.REACT_TTL, { level = tonumber(plain(level)) }) end)
pcall(ns.On, "ACHIEVEMENT_EARNED", function(id)
	local _, name = try(GetAchievementInfo, plain(id))
	if filled(name) then C.Prompt("achievement", nil, C.REACT_TTL, { achievement = name }) end
end)

local function encounter(won)
	C.Clear(won and "wipe" or "bosskill")
	C.Prompt(won and "bosskill" or "wipe", nil, C.REACT_TTL)
end
local hasEncounters = pcall(ns.On, "ENCOUNTER_END", function(_, _, _, _, success)
	local result = plain(success)
	if result ~= nil then encounter(result == 1) end
end)
if not hasEncounters then pcall(ns.On, "BOSS_KILL", function() encounter(true) end) end

-- Loot lines are the player's own when they open the way this client's own-loot strings do ("You receive loot: ").
local OWN_LOOT = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }
local function ownLoot(text)
	for _, key in ipairs(OWN_LOOT) do
		local lead = type(_G[key]) == "string" and _G[key]:match("^(.-)%%")
		if filled(lead) and text:sub(1, #lead) == lead then return true end
	end
end

ns.On("CHAT_MSG_LOOT", function(text)
	text = plain(text)
	local link = type(text) == "string" and listening() and ownLoot(text) and text:match("|c[^|]*|Hitem:.-|h|r")
	local name = link and filled(link:match("%[(.-)%]"))
	if not name then return end
	local item = C_Item or {}
	local quality = tonumber(try(item.GetItemQualityByID, link)) or tonumber((select(3, try(item.GetItemInfo or GetItemInfo, link)))) or tonumber(link:match("|cnIQ(%d+)"))
	if quality and quality >= C.LOOT_QUALITY then C.Prompt("looted", nil, C.REACT_TTL, { item = name }) end
end)

-- A lasting buff another player put on the player: thanks, once per caster and buff every C.THANKS_WAIT.
local thanked = {}
local function buffed(aura, now)
	local source, name, duration = plain(aura.sourceUnit), filled(plain(aura.name)), plain(aura.duration)
	if not (plain(aura.isHelpful) and name and type(source) == "string" and type(duration) == "number" and duration >= C.BUFF_MIN) then return end
	if not api("UnitIsPlayer", source) or api("UnitIsUnit", source, "player") then return end
	local caster, realm = api("UnitName", source)
	local key = caster and caster .. "\0" .. name
	if not key or now - (thanked[key] or -C.THANKS_WAIT) < C.THANKS_WAIT then return end
	for seen, at in pairs(thanked) do if now - at >= C.THANKS_WAIT then thanked[seen] = nil end end
	thanked[key] = now
	C.Prompt("buffed", filled(realm) and caster .. "-" .. realm or caster, C.REACT_TTL, { buff = name })
end

ns.On("UNIT_AURA", function(token, info)
	local added = token == "player" and type(plain(info)) == "table" and plain(info.addedAuras)
	if type(added) ~= "table" or not listening() then return end
	local auras, now = C_UnitAuras or {}, GetTime()
	for _, entry in ipairs(added) do
		entry = plain(entry)
		local aura = type(entry) == "table" and (try(auras.GetAuraDataByAuraInstanceID, "player", plain(entry.auraInstanceID)) or entry)
		if type(aura) == "table" then buffed(aura, now) end
	end
end)

ns.On("MERCHANT_SHOW", function() met("vendor") end)
ns.On("TRAINER_SHOW", function() met("trainer") end)
ns.On("TAXIMAP_OPENED", function() met("flight") end)
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_GREETING", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do ns.On(event, function() met("questgiver") end) end

-- A friendly NPC under the cursor counts as nearby for a while: "I'm at <name>".
ns.On("UPDATE_MOUSEOVER_UNIT", function()
	local name = listening() and api("UnitName", "mouseover")
	if not name or api("UnitIsPlayer", "mouseover") or not api("UnitIsFriend", "player", "mouseover") or api("UnitIsDead", "mouseover") then return end
	nearby = { name = name, kind = npcKinds[name], at = GetTime() }
end)

local HEARD = {
	CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_BN_WHISPER = "BN_WHISPER", CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
	CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_RAID_WARNING = "RAID", CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT", CHAT_MSG_GUILD = "GUILD", CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL", CHAT_MSG_CHANNEL = "CHANNEL",
}
for event, kind in pairs(HEARD) do ns.On(event, function(message, sender, _, _, _, _, _, channel) C.Hear(kind, message, sender, channel) end) end
