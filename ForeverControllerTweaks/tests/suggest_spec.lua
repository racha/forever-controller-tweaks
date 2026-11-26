-- Plain-Lua checks for the keyboard suggestions: lua tests/suggest_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."

-- The game, as a table the stubs read. Scenarios change it and fire the events the client would. Its clock only
-- runs forward, a long step between scenarios, as the game's does.
local SECRET = {}
-- The client's chat-type aliases (GlobalStrings), as the keyboard reads them.
SLASH_SAY1, SLASH_SAY2, SLASH_YELL1, SLASH_YELL2, SLASH_EMOTE1, SLASH_EMOTE2 = "/s", "/say", "/y", "/yell", "/e", "/me"
SLASH_PARTY1, SLASH_PARTY2, SLASH_RAID1, SLASH_RAID2, SLASH_RAID_WARNING1, SLASH_INSTANCE_CHAT1, SLASH_INSTANCE_CHAT2 = "/p", "/party", "/ra", "/raid", "/rw", "/i", "/instance"
SLASH_GUILD1, SLASH_GUILD2, SLASH_OFFICER1, SLASH_REPLY1, SLASH_REPLY2 = "/g", "/guild", "/o", "/r", "/reply"
SLASH_SMART_WHISPER1, SLASH_SMART_WHISPER2, SLASH_WHISPER1 = "/w", "/whisper", "/tell"
SLASH_GUILD_DISCORD1, SLASH_GUILD_DISCORD2 = "/gd", "/guilddiscord"
local world
local function fresh()
	world = {
		now = (world and world.now or 0) + 1000, clock = 86400 * 20000, hour = 20, zone = "Westfall", subzone = "Sentinel Hill", resting = false, instance = nil, instanceName = nil,
		raid = false, group = false, lfgGroup = false, size = 0, role = "NONE", guild = false, combat = false, dead = false,
		health = 100, mana = 100, quest = nil, lfg = nil,
		units = { player = { name = "Tester", level = 24, player = true, friend = true } },
		channels = { 1, "General - Westfall", false, 2, "Trade - City", false, 4, "LookingForGroup", false },
		bags = { [0] = { "Linen Cloth", "Minor Healing Potion" }, [1] = { "Hearthstone", "Linen Cloth", "Healing Potion" } },
		friends = { "Morwen", "Hesk-Realm" }, roster = { "Gildor-Realm", "Morwen-Realm", "Tester-Realm" },
	}
end
fresh()

issecretvalue = function(value) return value == SECRET end
function GetTime() return world.now end
function time() return world.clock end
function GetGameTime() return world.hour, 0 end
local function unitField(key, default) return function(unit) local u = world.units[unit] if u then return u[key] end return default end end
function UnitName(unit) local u = world.units[unit] if u then return u.name, u.realm end end
function UnitClass() return "Priest", "PRIEST" end
UnitLevel, UnitIsPlayer, UnitIsDead, UnitClassification = unitField("level"), unitField("player"), unitField("dead"), unitField("kind")
function UnitIsFriend(_, unit) local u = world.units[unit] return u and u.friend end
function UnitCanAttack(_, unit) local u = world.units[unit] return u and u.hostile end
function UnitIsUnit(a, b) return a == b end
function IsInInstance() return world.instance ~= nil, world.instance or "none" end
function GetInstanceInfo() return world.instanceName, world.instance end
function GetRealZoneText() return world.zone end
function GetSubZoneText() return world.subzone end
function IsResting() return world.resting end
function IsInRaid() return world.raid end
function IsInGroup(category) if category then return world.lfgGroup end return world.group end
function GetNumGroupMembers() return world.size end
function UnitIsGroupLeader() return false end
function UnitGroupRolesAssigned() return world.role end
function IsInGuild() return world.guild end
function UnitAffectingCombat() return world.combat end
function UnitIsDeadOrGhost() return world.dead end
function UnitHealth() return world.health end
function UnitHealthMax() return 100 end
function UnitPower() return world.mana end
function UnitPowerMax() return 100 end
function GetLFGMode() return world.lfg end
function GetChannelList() return (unpack or table.unpack)(world.channels) end
function GetQuestLink(id) return "|cffffff00|Hquest:" .. id .. ":24|h[The Defias Brotherhood]|h|r" end
function GetNormalizedRealmName() return "Realm" end
function GetNumGuildMembers() return #world.roster end
function GetGuildRosterInfo(i) return world.roster[i] end
C_FriendList = { GetNumFriends = function() return #world.friends end, GetFriendInfoByIndex = function(i) return { name = world.friends[i] } end }
C_Container = {
	GetContainerNumSlots = function(bag) return world.bags[bag] and 4 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local name = world.bags[bag][slot]
		if name then return { itemName = bag == 0 and name or nil, hyperlink = "|cffffffff|Hitem:1|h[" .. name .. "]|h|r" } end
	end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return world.quest end }
local questReads, timers = 0, {}
C_QuestLog = {
	GetTitleForQuestID = function() return "The Defias Brotherhood" end,
	GetQuestObjectives = function()
		questReads = questReads + 1
		return world.objectives
	end,
	IsComplete = function() return world.questDone end,
	IsUnitOnQuest = function(unit) return world.onQuest == unit end,
}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function elapse()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do fn() end
end

local handlers = {}
local ns = { Active = function() return true end, db = { keyboard = { enabled = true, suggestions = true } } }
ns.On = function(event, fn) handlers[event] = handlers[event] or {} table.insert(handlers[event], fn) end
local function fire(event, ...) for _, fn in ipairs(handlers[event] or {}) do fn(...) end end
ForeverControllerTweaks = ns
-- A module file as the game loads it: its own addon name and private table; it reads the core's namespace global.
local function loadModule(file) assert(loadfile(here .. "/../../ForeverControllerTweaks_Keyboard/" .. file .. ".lua"))("ForeverControllerTweaks_Keyboard", {}) end
for _, file in ipairs({ "Engine", "Phrases", "Context", "Suggest" }) do loadModule(file) end
local K = ns.Keyboard
local P, C, S = K.Library, K.Context, K.Suggest

local function chatBox(kind, target, channel)
	local attrs = { chatType = kind, tellTarget = target, channelTarget = channel }
	return { GetAttribute = function(_, key) return attrs[key] end }
end
local SAY = chatBox("SAY")

-- A new scenario: a fresh world, nothing heard or pending, every section read again.
local function scene(changes)
	fresh()
	for key, value in pairs(changes or {}) do world[key] = value end
	local state = C.state
	state.prompts, state.inbox, state.joinedAt = {}, {}, nil
	for i = #state.whisperers, 1, -1 do state.whisperers[i] = nil end
	fire("PLAYER_ENTERING_WORLD")
	return K.Settings({})
end
-- The chat box as the player would have it: on the group's channel when grouped, else on say.
local function home() return chatBox(world.lfgGroup and "INSTANCE_CHAT" or world.raid and "RAID" or world.group and "PARTY" or "SAY") end
local function full(settings, text, box, results) return S.List(settings, C.Snapshot(box or home()), text or "", #(text or ""), results) end
-- An empty box's first page (S.MAX rows), which the checks below are about; full() has the rows under it too.
local function list(settings, text, box, results)
	local rows, head, fix = full(settings, text, box, results)
	if (text or ""):match("^%s*$") then for i = #rows, S.MAX + 1, -1 do rows[i] = nil end end
	return rows, head, fix
end
local function top(rows, n) return { (unpack or table.unpack)(rows, 1, math.min(n, #rows)) } end
local function show(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = row.text .. " [" .. row.tag .. "]" end
	return table.concat(out, " | ")
end
local function find(rows, text) for i, row in ipairs(rows) do if row.text == text then return row, i end end end
local function countOf(rows, category)
	local n = 0
	for _, row in ipairs(rows) do if row.category == category then n = n + 1 end end
	return n
end
local DUNGEON = { instance = "party", instanceName = "The Deadmines", zone = "The Deadmines", subzone = "", group = true, size = 5 }

-- A dungeon group with a ready check: the answer leads, on the party channel, ahead of the dungeon's own lines.
local settings = scene(DUNGEON)
fire("READY_CHECK", "Leader-Realm", 30)
local rows, head = list(settings)
assert(rows[1].text == "Ready" and rows[1].category == "Ready" and rows[1].tag == "Ready" and rows[1].channel.kind == "PARTY", show(rows))
assert(rows[2].category == "Ready" and rows[3].category == "Dungeon" and rows[3].channel.kind == "PARTY", show(rows))
assert(head.kind == "phrases" and head.place == "The Deadmines" and #rows <= S.MAX and #rows >= S.FILL, show(rows))
local all = full(settings)
assert(#all > S.MAX and #all <= S.SCROLL and show(top(all, S.FILL)) == "Ready [Ready] | Not ready, one sec [Ready] | Ready when you are [Dungeon] | Wait, I'm behind [Dungeon] | On my way [Group] | Wait for me [Group]", "under the first page the rest of the pool: " .. show(all))
world.now = world.now + 31
assert(countOf(list(settings), "Ready") == 0, "the ready check's lines go when it times out")
fire("READY_CHECK", "Leader-Realm", 30)
fire("READY_CHECK_FINISHED")
assert(countOf(list(settings), "Ready") == 0, "and when it finishes")
fire("READY_CHECK", "Tester", 30)
assert(countOf(list(settings), "Ready") == 0, "the player's own ready check needs no answer")
fire("READY_CHECK", SECRET, SECRET)
assert(countOf(list(settings), "Ready") == 2, "a secret name and time: still a ready check, for the default time")
fire("READY_CHECK_FINISHED")

-- A whisper "inv?": the replies show once the box is whispering the sender. On another channel there is only a
-- hint row: the keyboard never switches the chat, and no row carries a command.
settings = scene({ resting = true, zone = "Stormwind City", subzone = "Trade District" })
fire("CHAT_MSG_WHISPER", "inv?", "Aria-Stormrage")
rows = list(settings)
local hint, hintAt = find(rows, "Reply to Aria: switch to Whisper")
assert(countOf(rows, "Reply") == 0 and hint and hint.mode == "switch" and hint.tag == "/w" and countOf(rows, "Hint") == 1, "on say: a switch row, no reply rows. " .. show(rows))
assert(hintAt == math.min(#rows, S.FILL) and rows[1].mode == "phrase", "the hint is last on the first page; row 1 can be taken")
local text, cur = S.Apply(hint, "", 0)
assert(text == "/w Aria-Stormrage " and cur == #text and K.Slash(text) == "switch", "R1 on it types the whisper's own command: " .. text)
assert(S.Apply(hint, " hi", 3) == "/w Aria-Stormrage hi", "ahead of what is typed")
local toSender = chatBox("WHISPER", "Aria")
rows = list(settings, "", toSender)
assert(rows[1].text == "Sure, inviting!" and rows[1].tag == "Reply" and rows[2].text == "Inviting now" and countOf(rows, "Hint") == 0, show(rows))
assert(rows[1].channel.kind == "WHISPER" and rows[1].channel.target == "Aria-Stormrage" and S.Apply(rows[1], "", 0) == "Sure, inviting!", "only its own words go in")
assert(find(rows, "Hey, got a minute?").category == "Whisper" and not find(rows, "24 Priest LFG, whisper me"), "lines for another channel are not offered: " .. show(rows))
assert(countOf(list(settings, "", chatBox("WHISPER", "Bob")), "Reply") == 0, "whispering someone else: not their reply")
world.now = world.now + 60
local later = list(settings, "", toSender)
assert(later[1].text == "Sure, inviting!" and later[1].score < rows[1].score, "a reply decays with the age of its line")
world.now = world.now + C.HEARD_TTL
assert(countOf(list(settings, "", toSender), "Reply") == 0 and countOf(list(settings), "Hint") == 0 and #C.state.inbox == 0, "and is gone after three minutes")

-- A city with no tracked quest: city lines on the joined channels, no quest lines.
settings = scene({ resting = true, zone = "Stormwind City", subzone = "Trade District" })
rows = list(settings)
assert(countOf(rows, "Quest") == 0 and rows[1].text == "Where is the Priest trainer?" and rows[1].tag == "City", "on say: the city lines for say. " .. show(rows))
assert(not find(rows, "24 Priest LFG, whisper me") and countOf(rows, "Hint") == 0, "the LFG lines wait for the LFG channel; no hint for a line no better than the best shown")
local lfgRows = list(settings, "", chatBox("CHANNEL", nil, 4))
assert(lfgRows[1].text == "24 Priest LFG, whisper me" and lfgRows[1].channel.id == 4 and not find(lfgRows, "Where is the Priest trainer?"), show(lfgRows))
for _, row in ipairs(rows) do assert(not row.text:find("{", 1, true), "no unfilled token: " .. row.text) end
assert(find(rows, "Where is the Priest trainer?").channel.kind == "SAY")

-- A super-tracked quest: at most two quest lines, even when the list is short and other categories get a third.
settings = scene({ quest = 166 })
rows = list(settings)
assert(countOf(rows, "Quest") == 2 and rows[1].text:find("|Hquest:166", 1, true), show(rows))
S.PER_TAG = 1
assert(countOf(full(settings), "Quest") <= S.QUEST_MAX and countOf(top(list(settings), S.FILL), "Anywhere") == 2, "the fill pass doubles a category, never past the quest cap")
S.PER_TAG = 2
world.quest = 0
fire("SUPER_TRACKING_CHANGED")
assert(countOf(list(settings), "Quest") == 0, "untracked: the quest lines go")

-- "lf": shorthand expansions lead, as whole lines on the LFG channel; an expansion with an unfilled token is skipped.
settings = scene(DUNGEON)
local correction
rows, head, correction = list(settings, "lf", SAY, K.Rank(settings.dictionary, "lf"))
assert(rows[1].text == "LFG The Deadmines" and rows[2].text == "LF1M healer for The Deadmines" and rows[1].mode == "line" and rows[1].tag == "Phrase", show(rows))
assert(head.kind == "words" and correction == nil and rows[4].mode == "word", "then the words; a known shorthand is not corrected")
text, cur = S.Apply(rows[2], "lf", 2)
assert(text == "LF1M healer for The Deadmines" and cur == #text, "an expansion is its own words, on whatever channel the box is: " .. text)
settings = scene({ resting = true, zone = "Stormwind City" })
rows = list(settings, "lf", SAY, K.Rank(settings.dictionary, "lf"))
assert(rows[1].text == "LFG Stormwind City" and rows[2].text == "24 Priest LFG" and rows[3].mode == "word", "no instance: those expansions are skipped. " .. show(rows))
rows, head, correction = list(settings, "wya", SAY, K.Rank(settings.dictionary, "wya"))
assert(rows[1].text == "Where are you?" and correction == nil and find(rows, "way"), show(rows))
rows, head, correction = list(settings, "teh", SAY, K.Rank(settings.dictionary, "teh"))
assert(rows[1].text == "the" and correction == 1 and rows[1].mode == "word", "a typo still pre-focuses its correction: " .. show(rows))
text, cur = S.Apply(rows[1], "so teh", 6)
assert(text == "so the " and cur == 7, text)

-- Next word: the shipped phrases predict out of the box; the player's own sent lines outweigh them once learned.
settings = scene(DUNGEON)
rows = list(settings, "on my ")
assert(rows[1].text == "way" and rows[1].mode == "next" and rows[1].tag == "Next", show(rows))
text, cur = S.Apply(rows[1], "on my ", 6)
assert(text == "on my way " and cur == 10, text)
assert(S.Apply(rows[1], "on my", 5) == "on my way ", "a missing space is added")
assert(not find(list(settings, "need a "), "quick"))
local party = chatBox("PARTY")
for _ = 1, 2 do S.Sent(settings, "need a quick mana break", C.Snapshot(party)) end
rows = list(settings, "need a ")
assert(rows[1].text == "quick" and rows[1].mode == "next", "trained: " .. show(rows))
assert(list(settings, "need a quick ")[1].text == "mana", "the triple leads")
local own = find(rows, "need a quick mana break")
assert(own and own.mode == "line" and own.category == "Yours", "and the line itself completes: " .. show(rows))
rows = list(settings)
assert(rows[1].text == "need a quick mana break" and rows[1].tag == "Yours" and rows[1].channel.kind == "PARTY", "a line sent twice here is offered here: " .. show(rows))
assert(not find(list(settings, "", SAY), "need a quick mana break"), "and only on the kind of channel it was sent on")
settings.dictionary.wanted, settings.dictionary.wander = 5, 5
S.Sent(settings, "most wanted list", C.Snapshot(party))
local ranked, plainOrder = K.Rank(settings.dictionary, "wan"), {}
for i, result in ipairs(ranked) do plainOrder[result.word] = i end
rows = list(settings, "most wan", SAY, ranked)
assert(plainOrder.wander < plainOrder.wanted and rows[1].text == "wanted", "word completions follow the words before them: " .. show(rows))
local grams = settings.suggest.grams
S.Sent(settings, "/roll 100", C.Snapshot(party))
S.Sent(settings, "check [link] |cff0070dd|Hitem:1|h[Sword]|h|r", C.Snapshot(party))
S.Sent(settings, "secret auction text", C.Snapshot({}))
assert(not grams["/roll"] and not grams.roll and not grams.check and not grams.secret, "commands, links and other boxes are not learned")
settings = scene({ resting = true, zone = "Stormwind City" })
settings.suggest = { lines = { ["need a quick mana break"] = { n = 2, d = 20000, sit = "dungeon", via = "group" } } }
assert(not find(list(settings), "need a quick mana break"), "a dungeon line stays out of the city")

-- Ranking and diversity: best first, two a category, no near-duplicates, the same list every time.
settings = scene({ combat = true, mana = 10, group = true, size = 3, guild = true, units = { player = { name = "Tester", level = 24 }, target = { name = "Defias Pillager", hostile = true, level = 25 } } })
rows = top(list(settings), S.FILL)
assert(rows[1].text == "Out of mana!" and rows[2].text == "Help!" and rows[1].tag == "Combat", "what fits the moment leads its category: " .. show(rows))
local perTag, seen = {}, {}
for i, row in ipairs(rows) do
	perTag[row.category] = (perTag[row.category] or 0) + 1
	assert(perTag[row.category] <= S.PER_TAG and not seen[row.text:lower()], "two a category, no repeats: " .. show(rows))
	assert(i == 1 or rows[i - 1].score >= row.score, "sorted by score")
	seen[row.text:lower()] = true
end
assert(perTag.Combat == 2 and perTag.Group == 2 and perTag.Anywhere == 2 and #rows == 6, show(rows))
assert(find(rows, "Need mana, one moment").category == "Group", "the same line from two situations shows once")
assert(show(top(list(settings), S.FILL)) == show(rows), "deterministic")
world.mana = SECRET
assert(not find(list(settings), "Out of mana!"), "a secret power value is unknown, not low")

-- Two conversations: one reply to each before a second to either; a reply for another channel is a hint only;
-- answering one clears it.
settings = scene({ group = true, size = 5 })
fire("CHAT_MSG_PARTY", SECRET, "Aria-Realm")
fire("CHAT_MSG_PARTY", "ready?", SECRET)
fire("CHAT_MSG_SAY", "nice weather today", "Bob-Realm")
fire("CHAT_MSG_SAY", "ready?", "Bob-Realm")
fire("CHAT_MSG_PARTY", "ready?", "Tester-Realm")
assert(#C.state.inbox == 0, "secret lines, small talk, public lines not for the player and the player's own are not kept")
fire("CHAT_MSG_SAY", "hey tester, wanna join us?", "Bob-Realm")
fire("CHAT_MSG_PARTY_LEADER", "ready?", "Aria-Realm")
fire("CHAT_MSG_PARTY", "where are you", "Cid-Realm")
rows = top(list(settings), S.FILL)
assert(rows[1].text == "Ready" and rows[2].text == "In Sentinel Hill" and countOf(rows, "Reply") == 2, "on party: one reply to each party line. " .. show(rows))
assert(find(rows, "Reply to Bob: switch to Say").command == "/s " and not find(rows, "Yes please, invite me"), "the better reply is for say: a hint")
rows = list(settings, "", SAY)
assert(rows[1].text == "Yes please, invite me" and rows[1].channel.kind == "SAY" and not find(rows, "Ready") and countOf(rows, "Hint") == 0, "on say: Bob's replies, no hint for the weaker ones. " .. show(rows))
S.Sent(settings, "Ready", C.Snapshot(chatBox("PARTY")))
rows = list(settings)
assert(not find(rows, "Ready") and not find(rows, "In Sentinel Hill") and countOf(rows, "Reply") == 0, "answered on its channel: " .. show(rows))
for i = 1, C.INBOX + 4 do fire("CHAT_MSG_WHISPER", "hello " .. i, "Friend" .. i .. "-Realm") end
assert(#C.state.inbox == C.INBOX and C.state.inbox[1].name == "Friend" .. (C.INBOX + 4), "the inbox keeps the newest eight")
assert(settings.suggest.inbox == nil and not next(settings.suggest.usage), "incoming lines are never saved")

-- A public call the player can answer: a healer hears "LF healer" and is offered a whisper to the caller.
settings = scene({ resting = true, zone = "Ironforge" })
fire("CHAT_MSG_CHANNEL", "LF healer for Deadmines", "Borin-Realm", "", "4. LookingForGroup", "", "", 26, 4)
fire("CHAT_MSG_CHANNEL", "LF tank for Deadmines", "Durak-Realm", "", "4. LookingForGroup", "", "", 26, 4)
rows = list(settings)
assert(find(rows, "Reply to Borin: switch to Whisper") and countOf(rows, "Reply") == 0, "a public call is answered in a whisper: a hint until the box is there. " .. show(rows))
rows = list(settings, "", chatBox("WHISPER", "Borin-Realm"))
assert(rows[1].text == "I can heal" and rows[1].channel.target == "Borin-Realm", show(rows))
for _, row in ipairs(rows) do assert(row.text ~= "I can tank", "a priest is not offered to tank") end

-- Tokens: filled from the situation; a line whose token has no value is skipped.
settings = scene({ subzone = "" })
rows = list(settings)
assert(not find(rows, "Anyone around  want to group?") and find(rows, "Anyone questing in Westfall? Want to team up?"), show(rows))
settings = scene({ group = true, size = 2, units = { player = { name = "Tester", level = 24 }, target = { name = "Innkeeper Farley", friend = true, level = 30 } } })
assert(find(list(settings), "I'm at Innkeeper Farley"), "{npc}: the friendly NPC targeted")
fire("MERCHANT_SHOW")
rows = list(settings)
assert(rows[1].text == "Selling and repairing, one sec" and rows[1].tag == "Nearby", "a vendor, once their window opened: " .. show(rows))
world.units.target = nil
fire("PLAYER_TARGET_CHANGED")
assert(find(list(settings), "I'm at Innkeeper Farley"), "still nearby for a while")
world.now = world.now + C.NEARBY_TTL + 1
assert(not find(list(settings), "I'm at Innkeeper Farley"), "then not")
settings = scene({ hour = 9, resting = true, guild = true, zone = "Ironforge" })
local guildBox = chatBox("GUILD")
assert(find(list(settings, "", guildBox), "Good morning all") and not find(list(settings, "", guildBox), "Good night all"), "{time}")
P.Set(settings, "anywhere", nil, "{role} here")
P.Set(settings, "anywhere", nil, "Meet at {nowhere}")
rows = list(settings)
assert(find(rows, "DPS here") and not find(rows, "Meet at {nowhere}") and not find(rows, "Meet at "), "a leading token is capitalised; an unknown one skips the line")

-- Channels: a line belongs on a channel, and is offered only while the box is on it.
local function offered(changes, line, box) return find(list(scene(changes), "", box), line) end
local GROUPED = { group = true, size = 3 }
assert(offered(GROUPED, "Wait for me", chatBox("PARTY")).channel.kind == "PARTY" and not offered(GROUPED, "Wait for me", SAY) and not offered(GROUPED, "Wait for me", chatBox("GUILD")))
assert(offered(GROUPED, "Group lines: switch to Party", SAY).command == "/p ", "on say in a party: the switch row types /p")
assert(offered({ group = true, raid = true, size = 12 }, "Wait for me", chatBox("RAID")) and not offered({ group = true, raid = true, size = 12 }, "Wait for me", chatBox("PARTY")))
assert(offered({ group = true, lfgGroup = true, size = 5 }, "Wait for me", chatBox("INSTANCE_CHAT")) and offered({ group = true, lfgGroup = true, size = 5 }, "Group lines: switch to Instance", SAY))
assert(not offered({}, "Wait for me", chatBox("PARTY")), "no group: no group lines")
assert(offered({ resting = true, guild = true }, "Hello guild!", chatBox("GUILD")) and not offered({ resting = true, guild = true }, "Hello guild!", SAY) and not offered({ resting = true }, "Hello guild!", chatBox("GUILD")))
assert(offered({ quest = 166, group = true, size = 2 }, "Anyone doing " .. GetQuestLink(166) .. "?", chatBox("PARTY")), "a quest line belongs to the group when there is one")
assert(offered({ quest = 166 }, "Anyone doing " .. GetQuestLink(166) .. "?", chatBox("GUILD")), "and to any channel when alone")
local friend = { player = { name = "Tester", level = 24 }, target = { name = "Aria", realm = "Stormrage", player = true, friend = true, level = 24 } }
assert(offered({ units = friend }, "Want to group up?", chatBox("WHISPER", "Aria-Stormrage")).channel.target == "Aria-Stormrage" and not offered({ units = friend }, "Want to group up?", SAY))
assert(offered({ units = friend }, "Hi Aria!", SAY) and not offered({ units = friend }, "Hi Aria!", chatBox("WHISPER", "Aria-Stormrage")))
assert(offered({}, "Thanks!", SAY) and offered({}, "Thanks!", chatBox("GUILD")) and offered(GROUPED, "Thanks!", chatBox("WHISPER", "Aria")), "a line with no channel of its own shows everywhere")
settings = scene({ resting = true })
local trade = list(settings, "wts", SAY)[1]
assert(trade.text == "WTS, whisper me" and trade.tag == "Phrase" and trade.channel == nil, "a shorthand expansion is plain text")
assert(#list(scene({ resting = true }), "", {}) == 0, "a box that is not chat gets no phrases")
fire("TRADE_SHOW")
assert(#list(settings, "", {}) == 0)
world.units.NPC = { name = "Borin", player = true, friend = true }
settings = scene({ units = world.units })
fire("TRADE_SHOW")
rows = list(settings, "", chatBox("WHISPER", "Borin"))
assert(rows[1].category == "Trade" and rows[1].channel.target == "Borin", show(rows))
assert(find(list(settings), "Trade lines: switch to Whisper"), "on say: the hint")
fire("TRADE_CLOSED")
assert(countOf(list(settings, "", chatBox("WHISPER", "Borin")), "Trade") == 0 and countOf(list(settings), "Hint") == 0)

-- Inserting: only the row's own words. A phrase replaces an empty box and goes in at the cursor otherwise.
local phrase = { text = "On my way", mode = "phrase" }
assert(S.Apply(phrase, "  ", 2) == "On my way")
text, cur = S.Apply(phrase, "ok", 2)
assert(text == "ok On my way" and cur == #text, text)
assert(S.Apply({ text = "On my way", mode = "line" }, "on my w", 7) == "On my way")
assert(not P.Set(K.Settings({}), "anywhere", nil, "/dance") and not P.Set(K.Settings({}), "anywhere", nil, "/p hello"), "a slash command can't be added as a phrase")
for key, lines in pairs(P.DEFAULTS) do for _, line in ipairs(lines) do assert(P.Text(line):sub(1, 1) ~= "/" and line.via ~= "command", "no command lines: " .. key) end end
-- No row puts a slash command in the box but a switch row, and that one is always a channel switch.
local busy = { group = true, size = 3, guild = true, resting = true, quest = 166, units = friend }
for _, kind in ipairs({ "SAY", "PARTY", "GUILD", "WHISPER", "CHANNEL" }) do
	settings = scene(busy)
	fire("READY_CHECK", "Leader-Realm", 30)
	fire("CHAT_MSG_WHISPER", "inv?", "Aria-Stormrage")
	fire("CHAT_MSG_PARTY", "ready?", "Cid-Realm")
	local where = chatBox(kind, kind == "WHISPER" and "Aria-Stormrage" or nil, kind == "CHANNEL" and 4 or nil)
	for _, typed in ipairs({ "", "lf", "hello ", "inv", "wts", "can you " }) do
		for _, row in ipairs(list(settings, typed, where, {})) do
			local put = S.Apply(row, typed, #typed)
			assert(put:sub(1, 1) ~= "/" or row.mode == "switch" and K.Slash(put) == "switch", kind .. " '" .. typed .. "': " .. row.text)
		end
	end
end

-- Learning from choices: a taken line rises, lines passed over sink, and both fade.
settings = scene(DUNGEON)
rows = list(settings)
local taken, index = find(rows, "On my way")
assert(index > 1)
local ctx = C.Snapshot(SAY)
S.Accept(settings, taken, rows, ctx)
local usage = settings.suggest.usage
assert(usage["On my way"].a == 1 and usage["On my way"].d == ctx.day and usage[rows[1].key].i == 1)
local after = list(settings)
assert(select(2, find(after, "On my way")) < index and find(after, "On my way").score > taken.score, "reinforced: " .. show(after))
for _ = 1, 6 do S.Accept(settings, taken, rows, ctx) end
assert(list(settings)[1].text == "On my way", "a habit leads the list: " .. show(list(settings)))
world.clock = world.clock + 86400 * 28
assert(find(list(settings), "On my way").score < find(after, "On my way").score + 0.3, "recency fades over weeks")
S.Prune(settings)
assert(usage["On my way"].a == 6.65 and usage[rows[1].key].i == 3.5, "at logout accepts fade by 5% and ignores by half")
for _ = 1, 8 do S.Prune(settings) end
assert(usage[rows[1].key] == nil and usage["On my way"], "an ignored line is forgotten; a habit lasts")

-- Caps: n-grams, learned lines and usage stay bounded, in the session and at logout.
settings = scene(DUNGEON)
local store = S.Store(settings)
local function entries(map) local n = 0 for _, row in pairs(map) do for _ in pairs(row) do n = n + 1 end end return n end
for i = 1, 4000 do S.Sent(settings, "alpha" .. i .. " beta" .. i .. " gamma" .. i, C.Snapshot(party)) end
for _ = 1, 3 do S.Sent(settings, "keep this line", C.Snapshot(party)) end
assert(entries(store.grams) <= S.GRAM_CAP * 1.25 and store.grams.keep.this == 3, "learning prunes itself in the session: " .. entries(store.grams))
local lineCount = 0
for _ in pairs(store.lines) do lineCount = lineCount + 1 end
assert(lineCount <= S.LINE_CAP * 1.25 and store.lines["keep this line"].n == 3, "lines too: " .. lineCount)
store.grams.keep.this = S.COUNT_MAX + 50
S.Prune(settings)
lineCount = 0
for _ in pairs(store.lines) do lineCount = lineCount + 1 end
assert(entries(store.grams) == S.GRAM_CAP and lineCount == S.LINE_CAP and store.lines["keep this line"], "logout cuts to the caps, most used kept")
assert(store.grams.keep.this == (S.COUNT_MAX + 50) / 2 and store.grams["keep this"].line == 2, "and halves the counts once one is past the limit")
local small = { a = { b = 3, c = 1 }, d = { e = 1, f = 2 } }
S.PruneGrams(small, 2)
assert(small.a.b == 3 and small.d.f == 2 and not small.a.c and not small.d.e, "the lowest counts go first")
S.Sent(settings, string.rep("long ", 30), C.Snapshot(party))
assert(not store.lines[string.rep("long ", 30):sub(1, -2)], "a long line teaches words, not a phrase")
S.Sent(settings, "LFM The Deadmines need healer", C.Snapshot(party))
assert(store.lines["LFM {instance} need healer"], "a typed place name becomes its token")

-- SavedVariables: the defaults are never copied; the player's edits are kept apart and survive new defaults.
settings = scene()
assert(settings.phrases == nil and P.Lines(settings.phrases, "anywhere") == P.DEFAULTS.anywhere, "untouched: the defaults themselves")
assert(P.Set(settings, "anywhere", nil, "Mine") and not P.Set(settings, "anywhere", nil, "Mine"), "no duplicates")
assert(P.Remove(settings, "anywhere", "Thanks!") and not P.Remove(settings, "anywhere", "Never there"))
local lines = P.Lines(settings.phrases, "anywhere")
assert(lines[1] == "Mine" and lines[2] == "On my way" and #lines == #P.DEFAULTS.anywhere, "the player's lines first, removed defaults gone")
assert(settings.phrases.added.anywhere[1] == "Mine" and settings.phrases.removed.anywhere["Thanks!"] and P.DEFAULTS.anywhere[1] == "Thanks!")
rows = list(settings)
assert(find(rows, "Mine") and not find(rows, "Thanks!"), show(rows))
table.insert(P.DEFAULTS.anywhere, "New in this version")
assert(P.Lines(settings.phrases, "anywhere")[#P.DEFAULTS.anywhere] == "New in this version", "a later default still arrives")
table.remove(P.DEFAULTS.anywhere)
P.Remove(settings, "anywhere", "Mine")
P.Restore(settings, "anywhere")
assert(#settings.phrases.added.anywhere == 0 and P.Lines(settings.phrases, "anywhere")[1] == "Thanks!", "own line removed, the hidden default restored")
-- Quick messages: the player's own lines per situation and "always" come first, in their order, tokens filled.
settings = scene({ group = true, size = 3 })
assert(P.Set(settings, "anywhere", nil, "Always mine") and P.Set(settings, "group", nil, "  Second, {player} ") and P.Set(settings, "group", nil, "First mine"))
assert(not P.Set(settings, "group", nil, "First mine") and P.Set(settings, "group", 2, "First mine") and P.Move(settings, "group", 2, -1) and not P.Move(settings, "group", 1, -1))
P.Set(settings, "dungeon", nil, "Not here")
assert(settings.phrases.added.group[1] == "First mine" and settings.phrases.added.group[2] == "Second, {player}", "set trims, edits in place, moves")
rows = list(settings)
assert(rows[1].text == "First mine" and rows[2].text == "Second, Tester" and rows[3].text == "Always mine" and rows[3].tag == "Anywhere", show(rows))
assert(rows[1].tag == "Group" and rows[1].channel.kind == "PARTY" and not find(list(settings, "", chatBox("SAY")), "First mine"), "a situation's channel rules hold for the player's lines")
assert(find(full(settings, "firs"), "First mine"), "and they complete a typed line")
assert(not find(rows, "Not here") and find(rows, "Wait for me"), "another situation's lines stay out; the built-in lines follow")
local groupLines = #P.Builtin(settings.phrases, "group")
P.Set(settings, "group", nil, "Wait for me")
assert(P.Remove(settings, "group", "Wait for me", true) == "Wait for me" and settings.phrases.removed.group["Wait for me"])
assert(#P.Builtin(settings.phrases, "group") == groupLines - 1 and P.Own(settings.phrases, "group")[3] == "Wait for me", "one built-in line hidden by its text; the player's own line of that text stays")
P.Remove(settings, "group", "Wait for me")
rows = list(settings)
assert(rows[1].text == "First mine" and not find(rows, "Wait for me") and find(rows, "Thanks!"), "a hidden built-in line leaves the suggestions; the player's and the others' stay")
P.Restore(settings, "group")
assert(find(list(settings), "Wait for me") and #P.Builtin(settings.phrases, "group") == groupLines, "Restore brings the situation's hidden lines back")
for i = 1, P.LINES_MAX do P.Set(settings, "raid", nil, "Line " .. i) end
assert(not P.Set(settings, "raid", nil, "One too many") and not P.Set(settings, "raid", nil, ("x"):rep(P.LINE_MAX + 1)) and not P.Set(settings, "raid", nil, "  ") and not P.Set(settings, "raid", nil, "/dance"), "limits")
local broken = K.Settings({ phrases = { added = { group = { "Ok", "Ok", 7, "/dance", ("y"):rep(300), "Fine" }, bad = "x" }, removed = { anywhere = true, raid = { kept = true, [3] = true, odd = "no" } }, hidden = { group = true, dead = "yes", nope = true } } })
local fixed = broken.phrases
assert(#fixed.added.group == 2 and fixed.added.group[2] == "Fine" and #fixed.added.bad == 0 and fixed.removed.anywhere == nil and next(fixed.removed.raid) == "kept" and next(fixed.removed.raid, "kept") == nil, "repaired on load")
assert(fixed.hidden == nil and #P.Builtin(fixed, "group") == 0 and #P.Builtin(fixed, "dead") == #P.DEFAULTS.dead and fixed.removed.nope == nil, "a hidden situation from an older save: each of its built-in lines hidden")
assert(K.Settings({ phrases = "junk" }).phrases == nil)
for key, defaults in pairs(P.DEFAULTS) do
	for _, line in ipairs(defaults) do
		local value = P.Text(line)
		assert(type(value) == "string" and #value <= 60, key .. ": " .. tostring(value))
		if type(line) == "table" then for field in pairs(line) do assert(field == 1 or field == "role" or field == "class" or field == "need" or field == "no" or field == "via", key .. ": " .. tostring(field)) end end
	end
end
for _, rule in ipairs(P.INTENTS) do assert(P.DEFAULTS["reply." .. rule.id], "every intent has replies: " .. rule.id) end
for _, sit in ipairs(P.SITUATIONS) do assert(P.DEFAULTS[sit.id], "every situation has lines: " .. sit.id) end

-- Quest progress: the super-tracked quest's first unfinished objective, with its numbers, ahead of the generic
-- quest lines; still two quest lines at most.
local function objective(text, have, need) return { text = text, finished = have >= need, numFulfilled = have, numRequired = need } end
local OBJECTIVES = { objective("8/8 Defias Trapper slain", 8, 8), objective("3/8 Defias Pillager slain", 3, 8), objective("Red Silk Bandana: 0/15", 0, 15) }
local QUEST = GetQuestLink(166)
settings = scene({ quest = 166, group = true, size = 3, objectives = OBJECTIVES })
rows = list(settings)
assert(rows[1].text == QUEST .. ": Defias Pillager 3/8" and rows[1].tag == "Quest" and rows[1].channel.kind == "PARTY", "the first unfinished objective and its count: " .. show(rows))
assert(rows[2].text == "Need 5 more Defias Pillager" and countOf(rows, "Quest") == 2 and not find(rows, "Anyone doing " .. QUEST .. "?"), "two quest lines; progress outranks the generic ones")
world.now = world.now + 61
local reads, steady = questReads, list(settings)[1].score
for _ = 1, 3 do list(settings) end
assert(questReads == reads, "the quest log is not read again without an event")
for _ = 1, 5 do fire("QUEST_LOG_UPDATE") end
fire("UNIT_QUEST_LOG_CHANGED", "player")
list(settings)
assert(#timers == 1 and questReads == reads, "a burst of quest events waits as one timer")
OBJECTIVES[2] = objective("4/8 Defias Pillager slain", 4, 8)
elapse()
rows = list(settings)
assert(questReads == reads + 1 and rows[1].text == QUEST .. ": Defias Pillager 4/8" and rows[2].text == "Need 4 more Defias Pillager", "then it is read once: " .. show(rows))
assert(rows[1].score > steady + 0.19, "progress that just moved is lifted")
world.now = world.now + 30
assert(math.abs(list(settings)[1].score - steady - 0.1) < 1e-9, "the lift fades over a minute")
world.now = world.now + 31
assert(list(settings)[1].score == steady)
fire("READY_CHECK", "Leader-Realm", 30)
fire("CHAT_MSG_WHISPER", "inv?", "Aria-Stormrage")
rows = list(settings)
assert(rows[1].category == "Ready" and select(2, find(rows, QUEST .. ": Defias Pillager 4/8")) == 3, "under a prompt: " .. show(rows))
rows = list(settings, "", chatBox("WHISPER", "Aria-Stormrage"))
assert(rows[1].category == "Reply" and not find(rows, QUEST .. ": Defias Pillager 4/8"), "a party line is not offered in a whisper: " .. show(rows))
world.onQuest = "party2"
fire("QUEST_LOG_UPDATE")
elapse()
world.now = world.now + 61
rows = list(scene({ quest = 166, group = true, size = 3, objectives = OBJECTIVES, onQuest = "party2" }))
assert(rows[1].text == "Let's finish " .. QUEST .. " together" and rows[2].text == QUEST .. ": Defias Pillager 4/8" and countOf(rows, "Quest") == 2, "a party member on the quest: " .. show(rows))

settings = scene({ quest = 166, objectives = OBJECTIVES })
rows = list(settings, "", chatBox("CHANNEL", nil, 4))
local solo = find(rows, "Anyone want to group for " .. QUEST .. "? I'm at 4/8")
assert(solo and solo.tag == "Quest" and solo.channel.id == 4 and countOf(rows, "Quest") == 2 and not find(rows, "Need 4 more Defias Pillager"), "alone: the call for a group, on the LFG channel: " .. show(rows))
assert(not find(list(settings), solo.text) and find(list(settings), "Quest lines: switch to channel 4"), "on say: a hint")
world.channels = {}
fire("CHANNEL_UI_UPDATE")
assert(find(list(settings), solo.text).channel == nil, "no LFG channel joined: any channel")

settings = scene({ quest = 166, group = true, size = 3, objectives = OBJECTIVES, questDone = true })
rows = list(settings)
assert(rows[1].text == "Done with " .. QUEST .. ", turning in" and rows[2].text == QUEST .. " done! Anyone still need it?" and countOf(rows, "Quest") == 2, "complete: " .. show(rows))
for _, row in ipairs(rows) do assert(not row.text:find("4/8", 1, true) and not row.text:find("Need %d"), "no progress lines for a finished quest: " .. row.text) end
rows = list(scene({ quest = 166, group = true, size = 3, objectives = { objective("2/2 Defias Pillager slain", 2, 2) } }))
assert(rows[1].text == "Done with " .. QUEST .. ", turning in", "every objective finished counts as done")

rows = list(scene({ quest = 166, group = true, size = 3, objectives = { objective("Speak to Gryan Stoutmantle", 0, 1) } }))
assert(rows[1].text == "Anyone else need Speak to Gryan Stoutmantle?" and not find(rows, "Need 1 more Speak to Gryan Stoutmantle"), "an objective with no count: the lines with {progress} and {left} are skipped. " .. show(rows))
rows = list(scene({ quest = 166, group = true, size = 3, objectives = { { text = SECRET, finished = false, numFulfilled = SECRET, numRequired = SECRET } } }))
assert(countOf(rows, "Quest") == 2 and rows[1].text ~= nil and find(rows, "Anyone doing " .. QUEST .. "?"), "secret objectives: the generic quest lines only. " .. show(rows))
local readObjectives = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function() error("not in this client") end
assert(find(list(scene({ quest = 166, group = true, size = 3 })), "Anyone doing " .. QUEST .. "?"), "an API that errors is skipped")
C_QuestLog.GetQuestObjectives = readObjectives
assert(countOf(list(scene({ group = true, size = 3, objectives = OBJECTIVES })), "Quest") == 0, "no super-tracked quest: no quest lines, whatever the log holds")

-- Fields: what a box is for decides what it is offered. A frame is known by its name, its parents' names or its
-- dialog; only chat fields get phrases.
local function field(name, parent, extra)
	local frame = { GetName = function() return name end, GetParent = function() return parent end }
	for key, value in pairs(extra or {}) do frame[key] = value end
	return frame
end
local function kinds(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = row.mode end
	return table.concat(out, ",")
end
settings = scene({ resting = true, guild = true, group = true, size = 2, units = { player = { name = "Tester", level = 24 }, party1 = { name = "Pim", realm = "Other" } } })
local bag = field("BagItemSearchBox", field("ContainerFrame1"))
rows, head = list(settings, "", bag)
assert(head.kind == "items" and show(rows) == "Healing Potion [Item] | Hearthstone [Item] | Linen Cloth [Item] | Minor Healing Potion [Item]", "a bag search: what the bags hold, each once. " .. show(rows))
rows = list(settings, "pot", bag)
assert(show(rows) == "Healing Potion [Item] | Minor Healing Potion [Item]" and rows[1].mode == "line", show(rows))
assert(list(settings, "he", bag)[1].text == "Healing Potion" and list(settings, "he", bag)[2].text == "Hearthstone", "items that start with the text first")
assert(S.Apply(rows[2], "pot", 3) == "Minor Healing Potion" and #list(settings, "linen cloth", bag) == 0, "the item replaces the text; a full match needs no row")
S.Sent(settings, "cloth", C.Snapshot(bag))
S.Sent(settings, "Potion", C.Snapshot(bag))
S.Sent(settings, "CLOTH", C.Snapshot(bag))
assert(table.concat(settings.suggest.recent.bag, ",") == "CLOTH,Potion" and not next(settings.suggest.grams), "searches are remembered, newest first, once; they teach no words")
rows = list(settings, "", bag)
assert(rows[1].text == "CLOTH" and rows[1].tag == "Recent" and rows[3].tag == "Item", "an empty bag search leads with recent searches: " .. show(rows))
for i = 1, S.RECENT + 5 do S.Sent(settings, "search " .. i, C.Snapshot(bag)) end
assert(#settings.suggest.recent.bag == S.RECENT and settings.suggest.recent.bag[1] == "search " .. (S.RECENT + 5), "at most twenty")
world.bags[0][3] = "Silk Cloth"
assert(not find(list(settings, "silk", bag), "Silk Cloth"), "the bags are read once")
fire("BAG_UPDATE_DELAYED")
assert(find(list(settings, "silk", bag), "Silk Cloth"), "and again after they change")

local auction = field(nil, field(nil, field("AuctionHouseFrame")))
S.Sent(settings, "Copper Ore", C.Snapshot(auction))
rows, head = list(settings, "", auction)
assert(head.kind == "items" and rows[1].text == "Copper Ore" and rows[1].tag == "Recent" and rows[2].tag == "Item" and settings.suggest.recent.auction[1] == "Copper Ore", show(rows))
assert(#list(settings, "", field(nil, field("AuctionHouseFrame"), { IsNumeric = function() return true end })) == 0, "its price boxes are numeric")

fire("CHAT_MSG_WHISPER", "hi", "Aria-Stormrage")
local mailTo = field("SendMailNameEditBox", field("SendMailFrame"))
rows, head = list(settings, "", mailTo)
assert(head.kind == "names" and show(rows) == "Aria-Stormrage [Whisper] | Pim-Other [Group] | Morwen [Friend] | Hesk [Friend] | Gildor [Guild]", "a name field: people, nearest first, own realm dropped: " .. show(rows))
assert(show(list(settings, "m", mailTo)) == "Morwen [Friend]" and S.Apply(list(settings, "m", mailTo)[1], "m", 1) == "Morwen", "a name must start with the text")
assert(show(list(settings, "ari", mailTo)) == "Aria-Stormrage [Whisper]" and #list(settings, "hello ", mailTo) == 0 and settings.suggest.names == nil, "no words, no next word; names are never saved")
for _, name in ipairs({ "WhoFrameEditBox", "AddFriendNameEditBox" }) do assert(select(2, list(settings, "", field(name))).kind == "names", name) end
local popup = { which = "ADD_FRIEND" }
local popupBox = field("StaticPopup1EditBox", popup)
assert(select(2, list(settings, "", popupBox)).kind == "names", "a dialog's edit box is known by the dialog")
popup.which = "SET_FRIENDNOTE"
assert(select(2, list(settings, "", popupBox)).kind == "names", "the field is worked out once, when the box takes the focus")
C.Focus(popupBox)
assert(select(2, list(settings, "", popupBox)).kind == "words" and list(settings, "on my ", popupBox)[1].text == "way", "focused again for another dialog: free text")

local numeric = field("StackSplitBox", nil, { IsNumeric = function() return true end })
rows, head = list(settings, "12", numeric)
assert(#rows == 0 and head.kind == "none" and #list(settings, "", numeric) == 0, "a numeric box gets nothing")

-- Our quick message editor (field "quick"): the fill-ins with what each gives now; "{" or a fill-in's start filters
-- them; R1 puts the token in; other words still come while typing; chat boxes never list them.
local quick = field(nil, nil, { ForeverControllerTweaksField = "quick" })
local function tokens(rows)
	local out = {}
	for _, row in ipairs(rows) do if row.mode == "fill" then out[#out + 1] = row.token end end
	return table.concat(out, " ")
end
rows, head = full(settings, "", quick)
assert(head.kind == "fills" and #rows == #S.FILLS and rows[1].token == "{target}" and rows[1].text == "{target}  Your target's name", "an empty quick message lists every fill-in: " .. show(rows))
local values = {}
for _, row in ipairs(rows) do values[row.token] = row.tag end
assert(values["{player}"] == "Tester" and values["{level}"] == "24" and values["{from}"] == "", "each shows its value now, none when it has none")
rows, head = full(settings, "Hi {", quick)
assert(head.kind == "fills" and #rows == #S.FILLS, "\"{\" lists them all")
rows, head = full(settings, "Hi {s", quick)
assert(head.kind == "fills" and tokens(rows) == "{subzone} {spec}" and #rows == 2, "\"{s\" filters to the fill-ins that start so: " .. tokens(rows))
assert(S.Apply(rows[2], "Hi {s", 5) == "Hi {spec} " and select(2, S.Apply(rows[2], "Hi {s", 5)) == 10, "R1 replaces the typed start with the token and a space")
rows, head = full(settings, "{zz", quick)
assert(#rows == 0 and head.kind == "fills", "nothing matches: no rows")
rows, head = full(settings, "inv ta", quick, K.Rank(settings.dictionary or {}, "ta"))
assert(rows[1].token == "{target}" and rows[2] and rows[2].mode == "word" and head.kind == "words", "a fill-in's start without the brace: it leads the words: " .. show(rows))
assert(S.Apply(rows[1], "inv ta", 6) == "inv {target} ", "and goes in for the word")
assert(S.Apply(full(settings, "Hi {ta", quick)[1], "Hi {ta there", 6) == "Hi {target}  there", "text after the cursor stays")
rows = full(settings, "on my ", quick)
assert(rows[1].mode == "fill" and find(rows, "way"), "at a word boundary: the fill-ins, then the next words")
assert(countOf(full(settings, "", home()), "Fill-in") == 0 and countOf(full(settings, "ta", home()), "Fill-in") == 0, "a chat box never lists fill-ins")

local addon = field("SomeAddonNoteBox", field("SomeAddonFrame"))
rows, head = list(settings, "", addon)
assert(#rows == 0 and head.kind == "words", "an unknown box: no phrases")
rows = list(settings, "hel", addon, K.Rank(settings.dictionary, "hel"))
assert(kinds(rows) == "word,word,word,word" and rows[1].text == "help", "word completion only: " .. show(rows))
assert(#list(settings, "hello ", addon) == 0, "and no next word")

local mailBody = field("SendMailBodyEditBox", field("SendMailFrame"))
assert(#list(settings, "", mailBody) == 0, "free text that is not chat: no phrases")
rows = list(settings, "on my ", mailBody)
assert(rows[1].text == "way" and kinds(rows):find("line") == nil, "but the next word, and no chat lines: " .. show(rows))
assert(kinds(list(settings, "hel", mailBody, K.Rank(settings.dictionary, "hel"))) == "word,word,word,word")
assert(select(2, list(settings, "", field("MacroFrameText"))).kind == "words" and #list(settings, "", field(nil, nil, { IsMultiLine = function() return true end })) == 0)
S.Sent(settings, "dear friend", C.Snapshot(mailBody))
assert(not settings.suggest.grams.dear, "mail is not learned")

local search = field(nil, field("SettingsPanel"), { searchIcon = {} })
S.Sent(settings, "camera", C.Snapshot(search))
rows, head = list(settings, "", search)
assert(head.kind == "searches" and show(rows) == "camera [Recent]" and #list(settings, "camera ", search) == 0, show(rows))
rows = list(settings, "cam", search, { { word = "came", dist = 0, score = -1 } })
assert(rows[1].text == "camera" and rows[2].text == "came" and rows[2].mode == "word", "another search box: its own recent searches, then words: " .. show(rows))
assert(settings.suggest.recent.bag[1] ~= "camera", "each kind of search has its own list")

rows, head = list(settings, "", chatBox("GUILD"))
assert(head.kind == "phrases" and find(rows, "Hello guild!").tag == "Guild" and find(rows, "Hello guild!").channel.kind == "GUILD", "a chat box: phrases, on its channel")
for key, lines in pairs(P.DEFAULTS) do
	for _, line in ipairs(lines) do assert(not find(list(settings, "", mailBody), P.Text(line)) and not find(list(settings, "", bag), P.Text(line)), key) end
end

-- A whisper field: replies to that person only, and nothing for another channel. A prompt for the party is a hint.
settings = scene({ group = true, size = 5 })
fire("CHAT_MSG_WHISPER", "inv?", "Aria-Stormrage")
fire("CHAT_MSG_PARTY", "ready?", "Bob-Realm")
local toAria = chatBox("WHISPER", "Aria-Stormrage")
rows = top(list(settings, "", toAria), S.FILL)
assert(rows[1].text == "Sure, inviting!" and countOf(rows, "Reply") == 2 and countOf(rows, "Whisper") == 2 and not find(rows, "Ready"), show(rows))
for _, row in ipairs(rows) do assert(not row.channel or row.channel.kind == "WHISPER", "nothing leaves the whisper: " .. row.text) end
assert(countOf(rows, "Group") == 0 and countOf(list(settings, "", SAY), "Whisper") == 0, "group lines stay out; whisper lines stay out of say")
fire("READY_CHECK", "Leader-Realm", 30)
rows = list(settings, "", toAria)
assert(rows[1].text == "Sure, inviting!" and not find(rows, "Ready") and find(rows, "Ready lines: switch to Party").command == "/p ", "a ready check while whispering: " .. show(rows))

-- Next word: the seed predicts on a fresh install; the last two words beat the last one; what the player sends
-- takes over.
settings = scene()
rows, head = list(settings, "hello ")
assert(head.kind == "words" and rows[1].text == "everyone" and rows[2].text == "there" and rows[3].text == "all" and rows[1].mode == "next", "the seed: " .. show(rows))
assert(#rows <= S.NEXT + S.COMPLETE and rows[5].text == "Hello everyone!" and rows[5].mode == "line" and rows[6].text == "Hello, anyone up for a dungeon?", "four picks, the lines that continue it, the other picks: " .. show(rows))
for _, row in ipairs(rows) do assert(row.mode ~= "phrase", "no quick phrases mid-line: " .. row.text) end
assert(S.Apply(rows[5], "hello ", 6) == "Hello everyone!", "a continuation replaces the line from its start")
assert(S.Apply(find(list(settings, "ok. hello "), "Hello everyone!"), "ok. hello ", 10) == "ok. Hello everyone!", "or only its own sentence")
assert(list(settings, "thanks ")[1].text == "for" and list(settings, "need ")[1].text == "a" and list(settings, "anyone ")[1].text == "up" and list(settings, "lf ")[1].text == "healer")
assert(list(settings, "can you ")[1].text == "help" and list(settings, "can i ")[1].text == "join" and list(settings, "can ")[1].text == "you", "the last two words decide")
assert(list(settings, "zxqv ")[1].text == "hello" and #list(settings, "zxqv ") == S.NEXT, "unknown words: sentence starters")
for _ = 1, 40 do S.Sent(settings, "you are", C.Snapshot(SAY)) end
assert(list(settings, "you ")[1].text == "are" and list(settings, "can you ")[1].text == "help", "a triple beats even a strong pair")
for i = 1, 3 do
	S.Sent(settings, "hello world", C.Snapshot(SAY))
	assert((list(settings, "so hello ")[1].text == "world") == (i > 1), "the player's own words overtake the seed as they accumulate: " .. i)
end
assert(list(settings, "hello ")[1].text == "world" and list(settings, "hello ")[2].text == "everyone", "hello world, sent three times, leads")
rows = list(settings, "zxqv ")
assert(rows[1].text == "you" and rows[2].text == "hello" and #rows == S.NEXT, "unknown words: sentence starters, the player's own first. " .. show(rows))
rows = list(settings, "ready? ")
assert(rows[1].text == "You" and rows[2].text == "Hello", "capitals after ? ! . : " .. show(rows))
assert(list(settings, "ok. ")[2].text == "Hello" and list(settings, "ok! ")[2].text == "Hello" and list(settings, "ok, ")[1].text:match("^%l"))
assert(find(list(settings, "can "), "I") and find(list(settings, "where do "), "I"), "I is always a capital")
rows = list(settings, "can you help ")
local mark, at = find(rows, "?")
assert(mark and at <= 4 and mark.mode == "next", "a line that opens like a question is offered its mark: " .. show(rows))
text, cur = S.Apply(mark, "can you help ", 13)
assert(text == "can you help? " and cur == 14, text)
assert(not find(list(settings, "thanks for "), "?") and not find(list(settings, "can "), "?"), "not otherwise, and not after one word")
assert(list(settings, "")[1].mode == "phrase" and select(2, list(settings, "")).kind == "phrases", "an empty box: quick phrases")
assert(list(settings, "i ne", SAY, K.Rank(settings.dictionary, "ne"))[1].text == "need", "a predicted word the letters start leads the completions")
rows = list(settings, "hello wor", SAY, {})
assert(rows[1].text == "world" and rows[1].mode == "word", "a learned next word completes while it is typed: " .. show(rows))

-- Real answers: a question the game can answer gets the answer first, on the channel it came on. A secret value
-- (or a missing API) gives no answer row.
C_SpecializationInfo = { GetSpecialization = function() return world.spec and 2 end, GetSpecializationInfo = function() return 257, world.spec.name, "", 0, world.spec.role end }
function GetAverageItemLevel() return world.ilvl, world.ilvl end
C_Map = { GetBestMapForUnit = function() return world.map and 1456 end, GetPlayerMapPosition = function() local map = world.map return { GetXY = function() return map[1], map[2] end } end }
function UnitExists(unit) return world.units[unit] ~= nil end
function UnitIsDeadOrGhost(unit) if unit == "player" then return world.dead end return world.units[unit] and world.units[unit].dead end
local HOLY = { name = "Holy", role = "HEALER" }
local function asked(changes, line, kind, sender, box)
	local answers = scene(changes)
	fire(kind or "CHAT_MSG_WHISPER", line, sender or "Aria-Stormrage")
	return list(answers, "", box or chatBox("WHISPER", "Aria-Stormrage"))
end
local function priestless(rows) for _, row in ipairs(rows) do if row.text:find("Priest") then return false end end return true end
rows = asked({ spec = HOLY }, "what lvl?")
assert(rows[1].text == "24 Holy Priest" and rows[1].tag == "Reply" and rows[1].channel.kind == "WHISPER" and rows[1].channel.target == "Aria-Stormrage" and rows[2].text == "Level 24 Priest", show(rows))
assert(asked({}, "ur spec?")[1].text == "Level 24 Priest", "no specialization: the class only")
GetNumTalentTabs, GetTalentTabInfo = function() return 3 end, function(i) return ({ "Discipline", "Holy", "Shadow" })[i], "icon", ({ 0, 5, 21 })[i] end
assert(asked({}, "what class are you")[1].text == "24 Shadow Priest", "an older client: the talent tree with the most points")
GetNumTalentTabs, GetTalentTabInfo = nil, nil
assert(asked({ spec = { name = SECRET } }, "what spec?")[1].text == "Level 24 Priest", "a secret spec name: the class only")
rows = asked({ spec = HOLY, units = { player = { name = "Tester", level = SECRET, player = true, friend = true } } }, "what lvl?")
assert(priestless(rows), "a secret level: no answer row. " .. show(rows))
assert(priestless(asked({ spec = HOLY }, "what lvl?", "CHAT_MSG_SAY", "Bob-Realm", SAY)), "only lines aimed at the player")

local BLUFF = { zone = "Thunder Bluff", subzone = "", resting = true, map = { 0.392, 0.551 } }
rows = asked(BLUFF, "where r u?")
assert(rows[1].text == "Thunder Bluff, near 39, 55" and rows[1].channel.kind == "WHISPER", "where, with the map position, not a ready check: " .. show(rows))
local partyWhere = { group = true, size = 3, zone = "Westfall", subzone = "Sentinel Hill", map = { 0.5, 0.47 } }
rows = asked(partyWhere, "wya", "CHAT_MSG_PARTY", "Cid-Realm", chatBox("PARTY"))
assert(rows[1].text == "Sentinel Hill, near 50, 47" and rows[1].channel.kind == "PARTY", "group chat is answered in group chat: " .. show(rows))
assert(asked(BLUFF, "loc?")[1].text == "Thunder Bluff, near 39, 55")
rows = asked({ zone = "Thunder Bluff", subzone = "", map = { SECRET, 0.5 } }, "where are you")
assert(rows[1].text == "In Thunder Bluff" and not find(rows, "Thunder Bluff, near 50, 50"), "a secret position: the zone only. " .. show(rows))
assert(asked({ zone = "Thunder Bluff", subzone = "" }, "where are you")[1].text == "In Thunder Bluff", "no map API answer: the zone only")

local LEFT = { objective("3/8 Defias Pillager slain", 3, 8) }
rows = asked({ quest = 166, objectives = LEFT }, "how many left?")
assert(rows[1].text == "3/8 Defias Pillager" and rows[1].channel.kind == "WHISPER", "the tracked quest's objective: " .. show(rows))
assert(asked({ quest = 166, objectives = LEFT, questDone = true }, "done yet?")[1].text == "Done, turning in")
rows = asked({ quest = 166, objectives = { { text = SECRET, finished = false, numFulfilled = SECRET, numRequired = SECRET } } }, "how far are you?")
assert(not find(rows, "Done, turning in") and not rows[1].text:find("/") and not rows[1].text:find("Still need"), "secret objectives: no answer row. " .. show(rows))

local tankOrHeal = function(changes) return asked(changes, "tank or heal?", "CHAT_MSG_PARTY", "Cid-Realm", chatBox("PARTY")) end
rows = tankOrHeal({ group = true, size = 3, spec = HOLY, role = "HEALER" })
assert(rows[1].text == "Healer, Holy Priest" and rows[1].channel.kind == "PARTY", show(rows))
assert(tankOrHeal({ group = true, size = 3, spec = { name = "Protection", role = "TANK" } })[1].text == "Tank, Protection Priest", "no group role: the spec's")
assert(tankOrHeal({ group = true, size = 3, role = "DAMAGER" })[1].text == "DPS", "no spec: the group role alone")
rows = tankOrHeal({ group = true, size = 3, role = SECRET })
assert(not find(rows, "DPS") and not find(rows, "Healer"), "a secret role and no spec: no answer row. " .. show(rows))

assert(asked({ ilvl = 52.7 }, "what's ur ilvl?")[1].text == "Item level 52")
assert(not find(asked({ ilvl = SECRET }, "what's ur ilvl?"), "Item level 52"), "a secret item level: no row")

-- Whole lines while typing: from three characters, the player's own lines first, then the situation's, by the
-- start of each word, forgiving one slip per word past its third letter.
settings = scene()
S.Sent(settings, "anyone up for a quick deadmines run", C.Snapshot(SAY))
rows = list(settings, "any", SAY, {})
assert(rows[1].text == "anyone up for a quick deadmines run" and rows[1].category == "Yours" and rows[1].mode == "line", show(rows))
assert(rows[2].mode == "line" and rows[2].category ~= "Yours" and rows[2].text:find("^Anyone"), "then a phrase that fits here: " .. show(rows))
text, cur = S.Apply(rows[2], "any", 3)
assert(text == rows[2].text and cur == #text, "R1 replaces the text with the line")
rows = list(settings, "anyoen", SAY, {})
assert(rows[1].text == "anyone up for a quick deadmines run" and rows[2].text:find("^Anyone"), "a swapped pair still matches: " .. show(rows))
for _, typo in ipairs({ "anyne", "anyoone", "anyome" }) do assert(list(settings, typo, SAY, {})[1].category == "Yours", "one missing, extra or wrong letter: " .. typo) end
rows = list(settings, "an up fo", SAY, {})
assert(rows[1].text == "for" and rows[2].text == "anyone up for a quick deadmines run", "every word by its start, after the predicted word: " .. show(rows))
assert(not find(list(settings, "anyxyz", SAY, {}), "anyone up for a quick deadmines run") and not find(list(settings, "amyone", SAY, {}), "anyone up for a quick deadmines run"), "two slips, or one in the first three letters: no match")
assert(#list(settings, "an", SAY, {}) == 0, "under three characters: no lines")
rows = list(settings, "anyone ")
assert(rows[1].mode == "next" and rows[1].text == "up" and rows[5].category == "Yours", "after a space the next word still leads: " .. show(rows))
S.Sent(settings, "on my way to deadmines", C.Snapshot(SAY))
rows = list(settings, "on my wa", SAY, {})
assert(rows[1].text == "way" and rows[1].mode == "word" and rows[2].text == "on my way to deadmines" and rows[2].mode == "line", "a predicted word, then the lines: " .. show(rows))
S.SCAN = 1
rows = list(settings, "any", SAY, {})
assert(#rows == 1 and rows[1].category == "Yours", "the scan stops at S.SCAN lines; the player's own come first: " .. show(rows))
S.SCAN = 160

-- What just happened: short-lived lines for a level, a boss, a wipe, a drop and a buff.
settings = scene()
fire("PLAYER_LEVEL_UP", 25)
rows = list(settings)
assert(rows[1].text == "Ding 25!" and rows[1].tag == "Level" and rows[2].text == "Level 25, finally!", show(rows))
world.now = world.now + C.REACT_TTL + 1
assert(countOf(list(settings), "Level") == 0, "and it passes")
GetAchievementInfo = function(id) return id, "Explorer" end
fire("ACHIEVEMENT_EARNED", 6)
assert(list(settings)[1].text == "Got Explorer!")
GetAchievementInfo = nil

settings = scene(DUNGEON)
fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
rows = list(settings)
assert(rows[1].text == "gg" and rows[1].tag == "Boss" and rows[1].channel.kind == "PARTY" and find(rows, "Nice one all"), show(rows))
fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 0)
rows = list(settings)
assert(rows[1].text == "Wipe, run back" and rows[1].tag == "Wipe" and find(rows, "What went wrong?") and countOf(rows, "Boss") == 0, "a failed pull: " .. show(rows))
world.now = world.now + C.REACT_TTL + 1
assert(countOf(list(settings), "Wipe") == 0, "and it passes")
fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, SECRET)
assert(countOf(list(settings), "Boss") == 0 and countOf(list(settings), "Wipe") == 0, "a secret result: nothing")

local fallen = { player = { name = "Tester", level = 24, player = true }, party1 = { name = "Pim", dead = true }, party2 = { name = "Cid", dead = true } }
rows = list(scene({ group = true, size = 3, dead = true, units = fallen }))
assert(rows[1].text == "Wipe, run back" and rows[1].tag == "Dead", "everyone dead, no boss: the dead lines lean wipe. " .. show(rows))
fallen.party2.dead = false
assert(not find(list(scene({ group = true, size = 3, dead = true, units = fallen })), "Wipe, run back"), "someone standing: no wipe")

LOOT_ITEM_SELF = "You receive loot: %s."
settings = scene()
fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ4:|Hitem:5191::|h[Cruel Barb]|h|r.")
rows = list(settings)
assert(rows[1].text == "Finally got Cruel Barb!" and rows[1].tag == "Loot", show(rows))
settings = scene()
fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2589::|h[Linen Cloth]|h|r.")
fire("CHAT_MSG_LOOT", "Bob receives loot: |cnIQ4:|Hitem:5191::|h[Cruel Barb]|h|r.")
assert(countOf(list(settings), "Loot") == 0, "not a common item, not someone else's")

local auras = {}
C_UnitAuras = { GetAuraDataByAuraInstanceID = function(_, id) return auras[id] end }
local function buff(aura)
	auras[7] = aura
	fire("UNIT_AURA", "player", { addedAuras = { { auraInstanceID = 7 } } })
end
local FORT = { name = "Power Word: Fortitude", sourceUnit = "target", isHelpful = true, duration = 1800 }
local morwen = { player = { name = "Tester", level = 24, player = true }, target = { name = "Morwen", player = true, friend = true } }
settings = scene({ units = morwen })
buff(FORT)
rows = list(settings)
assert(rows[1].text == "Thanks for the Power Word: Fortitude, Morwen!" and rows[1].tag == "Buff" and rows[1].channel.kind == "SAY", show(rows))
rows = list(settings, "", chatBox("WHISPER", "Morwen"))
assert(rows[1].text == "Thanks for the Power Word: Fortitude!" and rows[1].channel.target == "Morwen", "or in a whisper to the caster: " .. show(rows))
C.Clear("buffed")
world.now = world.now + C.THANKS_WAIT - 1
buff(FORT)
assert(not C.state.prompts.buffed, "the same caster's same buff: once per five minutes")
world.now = world.now + 1
buff(FORT)
assert(C.state.prompts.buffed, "then again")
C.Clear("buffed")
for _, other in ipairs({ { name = "Renew", sourceUnit = "target", isHelpful = true, duration = 15 }, { name = "Inner Fire", sourceUnit = "player", isHelpful = true, duration = 600 }, { name = SECRET, sourceUnit = "target", isHelpful = true, duration = 1800 }, { name = "Thorns", sourceUnit = "target", isHelpful = true, duration = SECRET } }) do
	buff(other)
	assert(not C.state.prompts.buffed, "no thanks for a short, own or secret buff")
end

print("suggest_spec: engine ok")

-- The view (ForeverControllerTweaks_Keyboard/View.lua) on a small frame stub: every widget method (a capitalised name) is a no-op unless
-- listed; other fields stay nil.
local focus, enters = nil, 0
local Obj = {}
Obj.__index = function(_, name) return rawget(Obj, name) or type(name) == "string" and name:match("^%u") and function() end or nil end
local function new(kind, parent) return setmetatable({ kind = kind, parent = parent, shown = true, scripts = {} }, Obj) end
function Obj:Show() self.shown = true end
function Obj:Hide() self.shown = false end
function Obj:SetShown(on) self.shown = on end
function Obj:IsShown() return self.shown end
function Obj:IsVisible() return self.shown end
function Obj:SetScript(name, fn) self.scripts[name] = fn end
function Obj:CreateTexture() return new("Texture", self) end
function Obj:CreateFontString() return new("FontString", self) end
function Obj:CreateLine() return new("Line", self) end
function Obj:SetText(value) self.text = value end
function Obj:GetText() return self.text end
function Obj:GetStringWidth() return 8 * #(self.text or "") end
function Obj:GetWidth() return 1365 end
function Obj:GetHeight() return 768 end
function Obj:GetEffectiveScale() return 1 end
unpack = unpack or table.unpack
UIParent = new("Frame")
function CreateFrame(kind, name, parent)
	local f = new(kind, parent)
	if name then
		_G[name] = f
		function f:GetName() return name end
	end
	return f
end
local inCombat, bindings = false, {}
function InCombatLockdown() return inCombat end
function SetOverrideBindingClick(_, _, key, name, button) bindings[key] = "CLICK " .. name .. ":" .. button end
function ClearOverrideBindings() for key in pairs(bindings) do bindings[key] = nil end end
function GetBindingAction(key) return bindings[key] end
function GetCurrentKeyBoardFocus() return focus end
function PlaySound() end
function debugprofilestop() return world.now * 1000 end
function IsSecureCmd() return false end
local scripts = {}
function ExecuteFrameScript(_, script) scripts[#scripts + 1] = script end
SOUNDKIT = {}

-- A chat EditBox: text, a byte cursor, and the chat type the client keeps as an attribute.
local function newChat(kind, target)
	local edit = chatBox(kind, target)
	setmetatable(edit, Obj)
	edit.text, edit.cursor, edit.shown, edit.scripts = "", 0, true, {}
	function edit:IsObjectType(t) return t == "EditBox" end
	function edit:GetText() return self.text end
	function edit:SetText(value) self.text, self.cursor = value, #value end
	function edit:SetCursorPosition(c) self.cursor = c end
	function edit:Insert(value) self.text, self.cursor = self.text:sub(1, self.cursor) .. value .. self.text:sub(self.cursor + 1), self.cursor + #value end
	function edit:GetUTF8CursorPosition() return self.cursor end
	function edit:GetRect() return 17, 60, 410, 32 end
	return edit
end

scene(DUNGEON)
ns.db = { keyboard = { open = "always" } }
-- The keyboard goes by the physical button; native here (no config of ours applied).
assert(loadfile(here .. "/../Layout.lua"))("ForeverControllerTweaks", ns)
ns.Remap = { Outputs = function() end }
ns.UI = { ART = "", L = {}, CODE = {}, Glyph = function(parent) return new("Frame", parent) end }
loadModule("View")
local V = K.View
fire("PLAYER_LOGIN")
-- Our secure Send button: the game clicks it when the press goes on to the bindings and its key is bound to it.
local sender, macros = ForeverControllerTweaksChatSend, {}
sender.attrs = {}
function sender:SetAttribute(key, value) self.attrs[key] = value end
local function send(key)
	key = key or "PAD2"
	V.Press(key)
	if bindings[key] ~= "CLICK ForeverControllerTweaksChatSend:LeftButton" then return end
	macros[#macros + 1] = sender.attrs.macrotext
	sender.scripts.PostClick(sender, "LeftButton", true)
	assert(bindings[key], "the release still goes to our button")
	sender.scripts.PostClick(sender, "LeftButton", false)
end
-- Shift + Erase empties the line.
local function clear()
	V.Press("PADLTRIGGER")
	V.Press("PAD3")
	V.Release("PAD3")
	V.Release("PADLTRIGGER")
end
local function line() return V.State().draft end
local function lineKind() return V.State().channel and V.State().channel.kind end
local edit = newChat("SAY")
focus = edit
V.Observe()
V.Tick()
local state = V.State()
local switchRow, switchAt = find(state.suggestions, "Dungeon lines: switch to Party")
assert(switchRow and switchRow.mode == "switch" and switchAt <= S.FILL and state.suggestions[1].category == "Anywhere", "on say in a dungeon party: " .. show(state.suggestions))
for _ = 1, switchAt do V.Press("PADDDOWN") end
V.Press("PADRSHOULDER")
assert(lineKind() == "PARTY" and line() == "" and edit.text == "", "R1 on the switch row types the party's command: the line takes it as its channel; the chat box is not written to")
V.Tick()
assert(V.State().suggestions[1].category == "Dungeon", "the list follows the line's channel at once: " .. show(V.State().suggestions))
edit = newChat("PARTY")
focus = edit
V.Observe()
V.Tick()
state = V.State()
assert(state.head.place == "The Deadmines" and state.suggestions[1].category == "Dungeon", "an empty chat box shows the situation's lines: " .. show(state.suggestions))
local same = state.suggestions
V.Tick()
assert(V.State().suggestions == same, "nothing changed: nothing is ranked again")
fire("READY_CHECK", "Leader-Realm", 30)
V.Tick()
state = V.State()
assert(state.suggestions ~= same and state.suggestions[1].text == "Ready", "an event re-ranks the open tab: " .. show(state.suggestions))
V.Press("PADDDOWN")
V.Press("PADDDOWN")
fire("GROUP_ROSTER_UPDATE")
V.Tick()
assert(V.State().row == 2 and V.State().suggestions ~= state.suggestions, "re-ranked by an event, the chosen row stays focused")
V.Press("PADRSHOULDER")
assert(line() == "Not ready, one sec" and V.State().at == #line(), "R1 puts the chosen row's own words in: " .. line())
local saved = ns.db.keyboard
assert(saved.suggest.usage["Not ready, one sec"].a == 1 and saved.suggest.usage.Ready.i == 1, "the choice is remembered")
edit = newChat("PARTY")
focus = edit
V.Observe()
V.Type("pull the zorbly one")
send()
assert(macros[1] == "/p pull the zorbly one" and edit.text == "", "Send: the line goes out through our button as a macro line on the box's channel; the chat box is never written")
assert(bindings.PAD2 == nil and sender.attrs.macrotext == nil, "once it ran, the line and the binding come off")
assert(saved.suggest.grams.pull.the == 1 and saved.suggest.lines["pull the zorbly one"].via == "group" and saved.dictionary.zorbly == 1, "Send teaches the line, with where it was sent")
V.Observe()
assert(not V.Frame():IsShown() and V.Box() == nil, "Send closes the keyboard")
V.Observe()
V.Observe()
assert(not V.Frame():IsShown(), "the same box still focused: it stays closed, even with Open: Always")
focus = nil
V.Observe()
focus = edit
V.Observe()
assert(V.Frame():IsShown() and V.Box() == edit, "the box lost the focus and got it back: it opens")
V.Type("pull ")
V.Tick()
state = V.State()
assert(state.suggestions[1].text == "the" and state.suggestions[1].mode == "next" and state.head.kind == "words", show(state.suggestions))
V.Press("PADRSHOULDER")
assert(line() == "pull the ", line())
clear()
V.Type("can ")
V.Tick()
for _ = 1, 3 do V.Press("PADRSHOULDER") end
assert(line() == "can you help me " and V.State().suggestions[1].mode == "next", "R1 again and again builds a sentence, a space after each word: " .. line())

-- Past the first screen: D-pad down scrolls, arrows show rows above and below, the wheel scrolls too, R1 takes the
-- focused row wherever it is.
local scrolled = newChat("PARTY")
focus = scrolled
V.Observe()
V.Tick()
local tab = V.Frame().tab
state = V.State()
assert(#state.suggestions > S.MAX and state.scroll == 0 and not tab.inner.up.shown and tab.inner.down.shown, "a long list: an arrow below only. " .. show(state.suggestions))
for _ = 1, S.MAX do V.Press("PADDDOWN") end
assert(V.State().row == S.MAX and V.State().scroll == S.MAX - 6 and tab.inner.rows[6].item == state.suggestions[S.MAX] and tab.inner.up.shown, "down past the last shown row scrolls")
tab.scripts.OnMouseWheel(tab, 1)
assert(V.State().scroll == S.MAX - 7 and V.State().row == S.MAX - 1, "the wheel scrolls up; the focus stays on a shown row")
V.Press("PADRSHOULDER")
assert(line() == state.suggestions[S.MAX - 1].text, "R1 takes the scrolled row: " .. line())

-- Send runs the line on our button for this press: out of combat the press goes on to the bindings (the only
-- input-setting call), and the chat box keeps the focus, open and empty. Close leaves a chat box only through the
-- game's own B; our code never clears the focus.
local propagate = {}
V.Frame().SetPropagateKeyboardInput = function(_, on) propagate[#propagate + 1] = on end
local chatFrame = new("Frame")
local leaving = newChat("PARTY")
leaving.chatFrame = chatFrame
SmartNavigation = { bindingActive = true, activeInfo = { frame = chatFrame } }
focus = leaving
V.Observe()
V.Type("on my way")
send()
assert(macros[#macros] == "/p on my way" and propagate[1] == true and #propagate == 1, "Send on B: the press goes on to our button, which sends")
V.Observe()
assert(not V.Frame():IsShown() and propagate[2] == false and focus == leaving and leaving.text == "", "the box keeps the focus: the keyboard closes and the pad is ours again")
focus = nil
V.Observe()
focus = leaving
V.Observe()
V.Type("never mind")
V.Press("PAD4")
assert(#propagate == 2 and focus == leaving and not V.Frame():IsShown(), "Close on Y: the box keeps the focus")
V.Observe()
assert(not V.Frame():IsShown(), "and the keyboard stays closed until the focus leaves")
focus = nil
V.Observe()
focus = leaving
V.Observe()
assert(line() == "never mind", "the closed line waits: it is back when the keyboard opens on the box again")
-- Our button can't take the key (another binding wins): nothing is sent and the line stays.
local bind = SetOverrideBindingClick
SetOverrideBindingClick = function() end
local count = #macros
send()
assert(#macros == count and line() == "never mind" and V.Frame():IsShown() and #propagate == 2 and sender.attrs.macrotext == nil, "the key isn't ours: refused with a note, nothing left on the button")
SetOverrideBindingClick = bind
-- In combat no secure button changes: party, raid, instance, guild and whispers go through the chat API; say waits.
local said = {}
C_ChatInfo = { SendChatMessage = function(msg, kind, _, target) said[#said + 1] = { msg, kind, target } end, InChatMessagingLockdown = function() return false end }
inCombat = true
send()
assert(#said == 1 and said[1][1] == "never mind" and said[1][2] == "PARTY" and #macros == count and #propagate == 2 and not V.Frame():IsShown(), "in combat: sent by the chat API; no binding, no propagation")
focus = newChat("SAY")
V.Observe()
V.Type("hello all")
send()
assert(#said == 1 and V.Frame():IsShown() and line() == "hello all", "say in combat: the line waits with the note")
focus = newChat("WHISPER", "Aria")
V.Observe()
V.Type("brb")
send()
assert(#said == 2 and said[2][1] == "brb" and said[2][2] == "WHISPER" and said[2][3] == "Aria", "a whisper in combat goes to its name")
C_ChatInfo.InChatMessagingLockdown = function() return true end
focus = newChat("PARTY")
V.Observe()
V.Type("pull")
send()
assert(#said == 2 and line() == "pull", "chat locked down (an encounter): the line waits")
inCombat, C_ChatInfo = false, nil
focus = nil
V.Observe()
SmartNavigation = nil
-- Bag search: its Enter is EditBox_ClearFocus, whose focus-lost hook changes the Gamepad UI's bindings. B goes on to
-- its footer's Back while the frame manager works on the box; nothing of the box runs in our call.
local bagBox = newChat()
GamepadMode = { FrameControlsManager = { isUIFocused = true, focusedFrame = bagBox } }
focus = bagBox
V.Observe()
bagBox:SetText("potion")
local ran = #scripts
V.Press("PAD2")
assert(#scripts == ran and propagate[3] == true and bagBox.text == "potion", "bag search Send on B: no Enter in our call, the press goes on to the game's Back")
focus = nil
V.Observe()
assert(propagate[4] == false and not V.Frame():IsShown())
GamepadMode = nil
assert(#scripts == 0, "no box handler ever runs in our call")

-- The field is taken when the box takes the focus: a bag search shows items and runs no word search.
edit = newChat()
function edit:GetName() return "BagItemSearchBox" end
focus = edit
V.Observe()
V.Tick()
state = V.State()
assert(state.head.kind == "items" and state.suggestions[1].tag == "Item", show(state.suggestions))
edit:SetText("pot")
V.Tick()
assert(V.State().suggestions[1].text == "Healing Potion", "typed text narrows the items in the same frame")
V.Press("PADRSHOULDER")
assert(edit.text == "Healing Potion")
V.Press("PAD2")
assert(saved.suggest.recent.bag[1] == "Healing Potion", "Send remembers the search")
edit = newChat()
function edit:IsNumeric() return true end
focus = edit
V.Observe()
edit:SetText("12")
V.Tick()
assert(#V.State().suggestions == 0 and V.State().head.kind == "none" and V.State().charset == "numbers", "a numeric box: digits, no suggestions")

-- A chat box runs a line that opens with "/" inside our call: only channel switches are typed or sent.
assert(K.Slash("hello") == "text" and K.Slash("/") == "typing" and K.Slash("/da") == "typing" and K.Slash("/dance") == "typing", "a command still being typed")
for _, line in ipairs({ "/s ", "/say hi", "/y ", "/p hello", "/P hello", "/party x", "/ra ", "/raid go", "/rw pull", "/i hi", "/g ", "/o hi", "/w ", "/w Aria hi", "/whisper Aria-Realm hi", "/tell Aria hi", "/r hi", "/e waves", "/1 hi", "/20 x" }) do
	assert(K.Slash(line) == "switch" and K.Slash(line, true) == "switch", "a channel switch: " .. line)
end
for _, line in ipairs({ "/gd ", "/guilddiscord hi", "/dance ", "/cast x", "/reload ", "/readycheck ", "/fct ", "/0 hi", "/21 hi", "/ ", "/run x" }) do
	assert(K.Slash(line) == "refused", "refused once complete: " .. line)
end
assert(K.Slash("/reload", true) == "refused" and K.Slash("/p", true) == "switch" and K.Slash("/gd", true) == "refused", "on Send a bare command counts as complete")
assert(K.SwitchCommand({ kind = "PARTY" }) == "/p " and K.SwitchCommand({ kind = "WHISPER", target = "Aria-Realm" }) == "/w Aria-Realm " and K.SwitchCommand({ kind = "CHANNEL", id = 4 }) == "/4 ")
assert(K.SwitchCommand({ kind = "INSTANCE_CHAT" }) == "/i " and K.SwitchCommand({ kind = "RAID" }) == "/ra " and K.SwitchCommand({ kind = "BN_WHISPER" }) == nil and K.SwitchCommand({ kind = "WHISPER" }) == nil)
assert(SLASH_GUILD_DISCORD1 == "/gd" and SLASH_PARTY1 == "/p" and hash_ChatTypeInfoList == nil, "the client's alias strings are only read; no hash table is made or written")

-- The chat line Send runs as a macro line: the box's channel command and the text, a typed switch as it is, one line.
local macro, message, dest = K.ChatLine("  hi all  ", { kind = "PARTY" })
assert(macro == "/p hi all" and message == "hi all" and dest.kind == "PARTY", tostring(macro))
assert(K.ChatLine("hello", { kind = "SAY" }) == "/s hello" and K.ChatLine("hi", { kind = "GUILD" }) == "/g hi" and K.ChatLine("hi", { kind = "YELL" }) == "/y hi")
assert(K.ChatLine("hi", { kind = "WHISPER", target = "Aria-Realm" }) == "/w Aria-Realm hi" and K.ChatLine("hi", { kind = "CHANNEL", id = 4 }) == "/4 hi" and K.ChatLine("hi", { kind = "REPLY" }) == "/r hi")
assert(K.ChatLine("hi", { kind = "INSTANCE_CHAT" }) == "/i hi" and K.ChatLine("#hi", { kind = "SAY" }) == "/s #hi", "a # line keeps a command in front (the macro code skips # lines)")
assert(K.ChatLine("line one\nline two", { kind = "SAY" }) == "/s line one line two", "always one macro line: no second line can run")
macro, message, dest = K.ChatLine("/w Aria-Realm see you", { kind = "SAY" })
assert(macro == "/w Aria-Realm see you" and message == "see you" and dest.kind == "WHISPER" and dest.target == "Aria-Realm", "a typed switch goes as it is")
macro, message, dest = K.ChatLine("/1 lfg", { kind = "SAY" })
assert(macro == "/1 lfg" and message == "lfg" and dest.kind == "CHANNEL" and dest.id == 1)
for _, empty in ipairs({ "", "   ", "/p", "/p  ", "/w Aria" }) do assert(select(2, K.ChatLine(empty, { kind = "SAY" })) == "empty", "nothing to send: " .. empty) end
for _, refused in ipairs({ "/cast Fireball", "/run print(1)", "/dance", "/gd hi", "/reload" }) do assert(select(2, K.ChatLine(refused, { kind = "SAY" })) == "command", "never a macro: " .. refused) end
assert(select(2, K.ChatLine("hi", { kind = "BN_WHISPER" })) == "channel" and select(2, K.ChatLine("hi", {})) == "channel" and select(2, K.ChatLine("hi")) == "channel")
assert(select(2, K.ChatLine(("x"):rep(K.LINE_MAX + 1), { kind = "SAY" })) == "long" and K.ChatLine(("x"):rep(K.LINE_MAX), { kind = "SAY" }), "the chat's length limit")
local taken, rest = K.TakeSwitch("/p hello")
assert(taken.kind == "PARTY" and rest == "hello")
taken, rest = K.TakeSwitch("/w Aria hi")
assert(taken.kind == "WHISPER" and taken.target == "Aria" and rest == "hi")
assert(K.TakeSwitch("/w ") == nil and K.TakeSwitch("/w Aria") == nil and K.TakeSwitch("/p") == nil and K.TakeSwitch("/dance x") == nil and K.TakeSwitch("/gd x") == nil and K.TakeSwitch("/0 x") == nil, "only a complete switch")

-- The keyboard's channel keys switch the line at once: the command goes at the start, and a complete switch becomes
-- the line's channel with the text after it (as the chat box does while typed into: ProcessChatType).
local switched = newChat("SAY")
focus = switched
V.Observe()
ns.UI.CODE.PAD4 = "FT"
local function pick(set, key)
	V.Press("PADLTRIGGER")
	V.Press("PADRTRIGGER")
	V.Stick("Left", set[1], set[2])
	V.Stick("Right", key[1], key[2])
	V.Stick("Right", 0, 0)
	V.Release("PADLTRIGGER")
	V.Release("PADRTRIGGER")
	V.Stick("Left", 0, 0)
end
local function cursorTo(n) while V.State().at > n do V.Press("PADDLEFT") V.Release("PADDLEFT") end end
local NORTH, NE, EAST, RIGHT, BOTTOM = { 0, 1 }, { 0.7, 0.7 }, { 1, 0 }, { 0.6, 0 }, { 0, -0.6 }
pick(NORTH, RIGHT)
assert(lineKind() == "PARTY" and line() == "", "/p on an empty line: the line is on Party, empty. " .. line())
V.Type("hello")
pick(NORTH, { -0.6, 0 })
assert(lineKind() == "GUILD" and line() == "hello" and V.State().at == 5, "/g with hello typed: Guild, and hello stays. " .. line())
cursorTo(2)
pick(NE, { 0, 0.6 })
assert(lineKind() == "YELL" and line() == "hello", "the command goes at the start wherever the cursor is")
pick(NE, RIGHT)
assert(lineKind() == "YELL" and line() == "hello" and V.State().set == nil, "/w on a line with text: refused with the note, nothing changes")
clear()
pick(NE, RIGHT)
assert(line() == "/w " and lineKind() == "YELL", "/w on an empty line waits for the name")
V.Type("Aria hi")
assert(lineKind() == "WHISPER" and V.State().channel.target == "Aria" and line() == "hi" and V.State().at == 2)
assert(V.Frame().tab.inner.text.text == "/w Aria hi", "the field shows the line's channel: " .. tostring(V.Frame().tab.inner.text.text))
pick(EAST, { 0, -0.6 })
assert(K.CHARSETS.symbols[3][3] == "%t" and line() == "hi%t", "the %t key is plain text")
clear()
pick(EAST, { -0.6, 0 })
assert(K.CHARSETS.symbols[3][4] == "/ready" and line() == "" and not K.SwitchKind("/ready"), "/ready is not a channel switch: refused")
assert(switched.text == "", "the chat box itself is never written")
assert(K.SwitchKind("/p") == "PARTY" and K.SwitchKind("/raid") == "RAID" and K.SwitchKind("/rw") == "RAID_WARNING" and K.SwitchKind("/i") == "INSTANCE_CHAT")
assert(K.SwitchKind("/gd") == nil and K.SwitchKind("/") == nil and K.SwitchKind("a") == nil, "a Discord alias is never a channel key")
assert(K.PutSwitch("/w Ari", "/p") == "/p Ari" and K.PutSwitch("/w ", "/p") == "/p " and K.PutSwitch("  hi there", "/s") == "/s hi there" and K.PutSwitch("hi", "/w") == false)

edit = newChat("SAY")
focus = edit
V.Observe()
local function typeKeys(keys)
	for _, key in ipairs(keys) do
		if key == " " then V.Press("PAD1") else V.Type(key) end
	end
end
V.Press("PADLTRIGGER")
V.Press("PADRTRIGGER")
V.Stick("Left", 0, 1)
assert(V.State().charset == "symbols" and K.CHARSETS.symbols[1][2] == "/p")
V.Stick("Right", 0.6, 0)
V.Stick("Right", 0, 0)
assert(lineKind() == "PARTY" and line() == "", "the /p key switches the line to Party: " .. line())
V.Release("PADLTRIGGER")
V.Release("PADRTRIGGER")
V.Stick("Left", 0, 0)
typeKeys({ "h", "e", "l", "l", "o" })
send()
assert(macros[#macros] == "/p hello", "/p hello goes out as the macro line: the game switches and sends")
focus = nil
V.Observe()
focus = edit
V.Observe()
for typed, kind in pairs({ ["/s"] = "SAY", ["/y"] = "YELL", ["/g"] = "GUILD", ["/w Name"] = "WHISPER", ["/r"] = "REPLY", ["/1"] = "CHANNEL" }) do
	clear()
	V.Type(typed)
	V.Press("PAD1")
	assert(lineKind() == kind and line() == "", "the space after " .. typed .. " switches the line")
end
for _, typed in ipairs({ "/gd", "/dance", "/reload" }) do
	clear()
	V.Type(typed)
	V.Press("PAD1")
	assert(line() == typed, "the space that would run " .. typed .. " is refused")
end
clear()
V.Type("/cast x")
assert(line() == "", "another command can't even be typed into a chat line")
V.Type("x/dance now")
cursorTo(1)
V.Press("PAD3")
V.Release("PAD3")
assert(line() == "x/dance now", "erasing down to a refused command is refused")
clear()
V.Type("x/p now")
cursorTo(1)
V.Press("PAD3")
V.Release("PAD3")
assert(lineKind() == "PARTY" and line() == "now", "erasing down to a switch switches the line")
assert(edit.text == "", "nothing of it is in the chat box")
local other = newChat()
focus = other
V.Observe()
other.text, other.cursor = "/dance", 6
V.Press("PAD1")
assert(other.text == "/dance ", "a box that is not chat takes any slash: nothing parses it")
local hidden = newChat()
function hidden:GetText() return SECRET end
focus = hidden
V.Observe()
assert(not V.Frame():IsShown(), "a box whose text the game hides: the keyboard neither reads nor types it")
focus = newChat("WHISPER", SECRET)
V.Observe()
V.Type("hi")
V.Tick()
send()
assert(line() == "hi" and V.Frame():IsShown(), "a whisper to a hidden name: no command is made of it, the line waits")
focus = nil
V.Observe()

-- A row cut short by the tab's width shows its full line in the addon's tooltip while focused or hovered.
local tips = {}
ns.UI.Tooltip = function(owner, spec) tips.owner, tips.spec = owner, spec end
ns.UI.HideTooltip = function(owner) if not owner or tips.owner == owner then tips.owner, tips.spec = nil, nil end end
local party = newChat("PARTY")
focus = party
V.Observe()
V.Tick()
local rowsDrawn, cut = V.Frame().tab.inner.rows, nil
local LONG_LINE = "Ready when you are"
for _, row in ipairs(rowsDrawn) do row.text.IsTruncated = function(self) return self.text == LONG_LINE end end
for i, item in ipairs(V.State().suggestions) do if item.text == LONG_LINE then cut = i end end
assert(cut and cut > 1, "a long row and a short first row: " .. show(V.State().suggestions))
V.Press("PADDDOWN")
assert(tips.spec == nil, "a row that fits: no tooltip")
for _ = 2, cut do V.Press("PADDDOWN") end
local long = V.State().suggestions[cut]
assert(tips.spec and tips.spec.lines[1] == long.text and tips.owner == rowsDrawn[cut] and tips.spec.side == "right", "focused and cut: the full line, beside the tab")
assert(tips.spec.title == long.category and tips.spec.lines[2] == "Channel: Party", "with its category and channel")
V.Press("PADDUP")
assert(tips.spec == nil, "focus moves to a row that fits: hidden")
rowsDrawn[cut].scripts.OnEnter(rowsDrawn[cut])
assert(tips.spec and tips.spec.lines[1] == long.text, "hovered with the mouse: shown")
rowsDrawn[cut].scripts.OnLeave(rowsDrawn[cut])
assert(tips.spec == nil, "and gone when the mouse leaves")
V.Press("PADDDOWN")
assert(tips.spec)
V.Type("x")
V.Tick()
assert(tips.spec == nil, "the list refreshes: hidden")
clear()
V.Tick()
for _ = 1, cut do V.Press("PADDDOWN") end
assert(tips.spec)
V.Press("PAD4")
assert(tips.spec == nil and not V.Frame():IsShown(), "the keyboard closes: hidden")

-- Boxes the game blocks addons from typing into: the keyboard stays closed and says why, once per box.
local notes = {}
ns.log = function(msg) notes[#notes + 1] = msg end
local function inside(parent, name)
	local made = newChat()
	function made:GetParent() return parent end
	function made:GetName() return name end
	return made
end
local function opens(made)
	focus = made
	V.Observe()
	return V.Frame():IsShown() and V.Box() == made
end
SettingsPanel, LFGListFrame, SpellSearchBoxMixin = new("Frame"), new("Frame"), { OnTextChanged = function() end }
local settingsSearch = inside(inside(SettingsPanel))
assert(not opens(settingsSearch) and #notes == 1 and notes[1] == K.T.DENIED, "the Options search box: not opened, and the player is told")
V.Press("PAD1")
assert(not opens(settingsSearch) and #notes == 1 and settingsSearch.text == "", "told once; nothing is typed")
assert(not opens(inside(LFGListFrame)) and #notes == 2, "the group finder's boxes")
local spellSearch = newChat()
spellSearch.OnTextChanged = SpellSearchBoxMixin.OnTextChanged
assert(not opens(spellSearch) and #notes == 3, "the spell and talent search")
edit = newChat("SAY")
assert(opens(edit))
V.Press("PAD1")
assert(line() == " " and edit.text == "" and #notes == 3, "a chat box still opens and types (into its line)")
assert(not opens(settingsSearch) and not V.Frame():IsShown(), "focus moving to a denied box closes the keyboard")

-- A block right after the keyboard typed teaches the box: denied from then on, and after a reload by its name.
local addonBox = inside(nil, "SomeAddonSearchBox")
assert(opens(addonBox))
V.Press("PAD1")
fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Protected()")
assert(opens(addonBox), "another addon's block is not ours")
fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "Protected()")
assert(not opens(addonBox) and not (saved.blocked and saved.blocked[1]) and #notes == 4, "blocked within a second of typing: closed and said, for this session only")
local reloaded = inside(nil, "SomeAddonSearchBox")
assert(opens(reloaded), "a block any of our modules may have caused is not saved: after a reload the box works")
V.Press("PAD1")
fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "SomeAddonSearchBox:SetText()")
assert(not opens(reloaded) and saved.blocked[1] == "someaddonsearchbox" and #notes == 5, "the box's own function blocked: saved")
assert(not opens(inside(nil, "SomeAddonSearchBox")) and #notes == 6, "a new frame of that name (after a reload) is denied from the saved list")
local chatEdit = inside({ GetName = function() return "ChatFrame1" end }, "ChatFrame1EditBox")
assert(opens(chatEdit))
V.Press("PAD1")
fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "Protected()")
assert(opens(chatEdit) and saved.blocked[1] == "someaddonsearchbox" and #notes == 6, "a chat box is never denied")
table.insert(saved.blocked, 1, "chatframe3editbox chatframe3 uiparent")
fire("FCT_READY")
assert(saved.blocked[1] == "someaddonsearchbox" and #saved.blocked == 1, "a chat box saved by an older version is dropped on load")
local slow = inside(nil, "SlowBox")
assert(opens(slow))
V.Press("PAD1")
world.now = world.now + 2
fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "Protected()")
assert(opens(slow) and #saved.blocked == 1, "a block long after the last keystroke is not blamed on the box")
local dialog = { which = "SOME_DIALOG" }
local popupEdit = inside(dialog, "StaticPopup1EditBox")
assert(opens(popupEdit))
V.Press("PAD2")
fire("ADDON_ACTION_FORBIDDEN", "ForeverControllerTweaks", "StaticPopup1EditBox:SetText()")
assert(not opens(popupEdit) and saved.blocked[1] == "staticpopup1editbox SOME_DIALOG", "Send counts too; a dialog's box is learned for that dialog")
dialog.which = "ADD_FRIEND"
focus = nil
V.Observe()
assert(opens(popupEdit), "the same box under another dialog (shown again, focused again) still works")
for i = 1, C.BLOCKED + 5 do C.Deny(inside(nil, "Box" .. i), saved, true) end
assert(#saved.blocked == C.BLOCKED and saved.blocked[1] == "box" .. (C.BLOCKED + 5), "the saved list is capped")
local nameless = newChat()
C.Deny(nameless, saved, true)
assert(#saved.blocked == C.BLOCKED and saved.blocked[1] ~= "" and C.Denied(nameless, saved), "a box with no name is remembered for the session only")

saved.suggest.usage.Ready.i = 0.2
fire("PLAYER_LOGOUT")
assert(saved.suggest.usage.Ready == nil and saved.suggest.usage["Not ready, one sec"].a == 0.95, "logout prunes the store")

print("suggest_spec: view ok")
