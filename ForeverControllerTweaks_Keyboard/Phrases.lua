-- Forever Controller Tweaks keyboard phrase library (design/suggestions.md): the default lines per situation, the
-- reply sets, the shorthand expansions and the intent rules that read incoming chat. Data, plus the merge with the
-- player's own edits (ForeverControllerTweaksDB.keyboard.phrases), which are stored apart from the defaults so a new
-- version's lines still arrive.
local ns = ForeverControllerTweaks
local K = ns.Keyboard
local P = {}
K.Library = P

-- Situations, most specific first. weight is the context match (0..1); tag is the category shown on the row; via is
-- the channel its lines belong on (a line may override it): "group" the party / raid / instance channel, "auto" that
-- channel when grouped, "say", "guild", "lfg" / "trade" the joined city channel, "target" a whisper to the friendly
-- target, "reply" back to whoever asked; none is any channel. A line shows only while the box is on its channel:
-- the keyboard never switches it. urgent situations live only while their
-- prompt does (a ready check, a trade window). fresh lifts a situation's lines for a minute after the tracked
-- quest's progress moved. field limits a situation to one kind of field ("whisper"); every
-- situation is for chat and whisper fields only, never a search, name or other box.
P.SITUATIONS = {
	{ id = "ready", tag = "Ready", weight = 1, via = "group", urgent = true },
	{ id = "resurrect", tag = "Res", weight = 1, via = "auto", urgent = true },
	{ id = "summon", tag = "Summon", weight = 0.95, via = "auto", urgent = true },
	{ id = "invite", tag = "Invite", weight = 0.95, via = "reply", urgent = true },
	{ id = "trade", tag = "Trade", weight = 0.9, via = "reply", urgent = true },
	{ id = "duel", tag = "Duel", weight = 0.9, via = "reply", urgent = true },
	{ id = "roll", tag = "Loot", weight = 0.85, via = "group", urgent = true },
	{ id = "proposal", tag = "Queue", weight = 0.85, urgent = true },
	{ id = "dead", tag = "Dead", weight = 0.8, via = "auto" },
	{ id = "combat", tag = "Combat", weight = 0.75, via = "auto" },
	{ id = "newgroup", tag = "Group", weight = 0.7, via = "group" },
	{ id = "battleground", tag = "PvP", weight = 0.65, via = "group" },
	{ id = "dungeon", tag = "Dungeon", weight = 0.6, via = "group" },
	{ id = "raid", tag = "Raid", weight = 0.6, via = "group" },
	{ id = "progress", tag = "Quest", weight = 0.62, via = "auto", fresh = true },
	{ id = "quest", tag = "Quest", weight = 0.55, via = "auto" },
	{ id = "whisper", tag = "Whisper", weight = 0.5, field = "whisper" },
	{ id = "friend", tag = "Target", weight = 0.5, via = "target" },
	{ id = "enemy", tag = "Target", weight = 0.5, via = "auto" },
	{ id = "npc", tag = "Nearby", weight = 0.45, via = "auto" },
	{ id = "group", tag = "Group", weight = 0.45, via = "group" },
	{ id = "queue", tag = "Queue", weight = 0.4, via = "auto" },
	{ id = "city", tag = "City", weight = 0.4 },
	{ id = "guild", tag = "Guild", weight = 0.35, via = "guild" },
	{ id = "world", tag = "Zone", weight = 0.3 },
	{ id = "anywhere", tag = "Anywhere", weight = 0.2 },
}

-- A line is a string, or { text, role =, class =, need =, no =, via =, field = }: role is "tank" | "healer" | "damage", class a
-- class token; need / no name a context flag that must be set / unset (Suggest.lua lists them; a role, or a need
-- that names a passing state such as lowMana or vendor, also lifts the line). Tokens: {target}
-- {friend} {enemy} {npc} {from} {zone} {subzone} {instance} {quest} {objective} {progress} {left} {class}
-- {role} {player} {level} {time} ({objective} {progress} {left}: the tracked quest's first unfinished objective, its
-- "3/8" and what is still missing); a
-- line with a token that can't be filled is skipped. field ("chat" | "whisper") keeps a line to that kind of field.
-- Keys: a situation id, "reply.<intent>", "short.<typed word>", or "typing": lines offered only as the continuation
-- of what is being typed.
P.DEFAULTS = {
	ready = { "Ready", "Not ready, one sec", { "Need mana first", need = "lowMana" }, "AFK, back in a minute" },
	resurrect = { "Thanks for the res!", "Taking the res, thanks", "One sec" },
	summon = { "Thanks for the summon!", "Coming, one sec" },
	invite = { "Thanks for the invite!", "One moment, finishing something", "No thanks, maybe later" },
	trade = { "Thanks!", "How much?", "One sec", "That's everything, thanks" },
	duel = { "Good luck!", "Not now, sorry", "Good duel!" },
	roll = { "Anyone need this?", "Need for main spec", "Grats!", "Passing" },
	proposal = { "Queue popped, be right back", "Dungeon time, talk later" },
	dead = { "Res please", { "Can someone res me?", need = "grouped" }, "I'm dead, running back", "Releasing", { "Wipe, run back", need = "grouped" } },
	combat = {
		"Help!", { "Heal please", no = "healer" }, { "Out of mana!", need = "lowMana" }, "Run!", { "Kill {enemy} first", need = "grouped" },
		{ "Need help with {enemy}!", need = "solo", via = "say" }, "Adds incoming",
	},
	newgroup = { "Hey all", "Hello!", "Thanks for the invite", { "{role} here, ready when you are", need = "inside" } },
	battleground = { "Inc {subzone}", "Need help at {subzone}", "{subzone} is clear", "On my way", "Defending {subzone}", "Good game all" },
	dungeon = {
		{ "Pulling", role = "tank" }, { "Ready to pull?", role = "tank" }, { "Mana break, one moment", role = "healer" },
		{ "Need mana, one moment", need = "lowMana" }, { "Everyone ready?", need = "leader" }, { "Ready when you are", no = "tank" },
		"Wait, I'm behind", "Which way?", "Skip this pack?", "Good run, thanks all!",
	},
	raid = { "Ready", { "Need mana, one moment", need = "lowMana" }, "AFK 2 min", "Which group am I in?", "What's the plan here?", "Thanks for the raid!" },
	progress = {
		{ "Done with {quest}, turning in", need = "questDone" }, { "{quest} done! Anyone still need it?", need = "questDone" },
		{ "Let's finish {quest} together", need = "questShared", no = "questDone" }, { "{quest}: {objective} {progress}", need = "grouped" },
		{ "Need {left} more {objective}", need = "grouped" }, { "Anyone else need {objective}?", need = "grouped" },
		{ "Anyone want to group for {quest}? I'm at {progress}", need = "solo", via = "lfg" },
	},
	quest = { "Anyone doing {quest}?", "Can anyone help with {quest}?", "Want to group for {quest}?", "Where do I go for {quest}?" },
	whisper = { "Hey, got a minute?", "Sure, invite me", "Thanks!", "Sorry, busy right now", "Give me a minute", "Are you still looking for more?" },
	friend = { { "Hi {friend}!", via = "say" }, { "Want to group up?", need = "solo" }, { "Thanks {friend}!", via = "say" }, "Need a hand?" },
	enemy = { { "Anyone want to help kill {enemy}?", need = "elite" }, { "Need help with {enemy} in {subzone}", need = "elite" } },
	npc = {
		{ "Selling and repairing, one sec", need = "vendor" }, { "Training, back in a minute", need = "trainer" },
		{ "Taking the flight path, be there soon", need = "flight" }, { "Turning in quests, one sec", need = "questgiver" },
		"I'm at {npc}", "Meet me at {npc} in {zone}",
	},
	group = {
		"On my way", "Wait for me", "Where are you?", "I'm in {subzone}", { "Need mana, one moment", need = "lowMana" },
		{ "Need a heal please", need = "lowHealth", no = "healer" }, "Follow me", { "Who else do we need?", need = "forming" }, "Need a break, 2 min",
		{ "Anyone need to repair or sell first?", need = "resting" }, "Thanks for the group!",
	},
	queue = { "In the queue, should pop soon", "Queued as {role}" },
	city = {
		{ "{level} {class} LFG, whisper me", via = "lfg", need = "solo" }, { "Any groups need a {role}?", via = "lfg", need = "solo" },
		{ "Where is the {class} trainer?", via = "say" }, { "Where is the flight master?", via = "say" },
		{ "{level} {class} looking for a guild", via = "lfg", no = "guild" }, { "Selling, whisper me", via = "trade" }, { "Buying, whisper me", via = "trade" },
	},
	guild = { "Hello guild!", "Good {time} all", "Anyone up for a dungeon?", { "Good night all", need = "night" }, "Grats!" },
	world = { { "Anyone around {subzone} want to group?", via = "say" }, { "Anyone questing in {zone}? Want to team up?", via = "say" } },
	anywhere = { "Thanks!", "On my way", "One moment please", "Can you help me?", "Invite me please", "Sorry, typing on a controller" },

	["reply.invite_offer"] = { "Yes please, invite me", "Sure, one sec", "No thanks, I'm good" },
	["reply.invite_ask"] = { "Sure, inviting!", "Inviting now", "Group is full, sorry" },
	["reply.ready_ask"] = { "Ready", "One sec", { "Need mana", need = "lowMana" } },
	["reply.where"] = { "In {subzone}", "In {zone}", "On my way", "Coming to you" },
	["reply.greet"] = { "Hey!", "Hello {from}!", "Hi, how are you?" },
	["reply.thanks"] = { "No problem!", "You're welcome", "Anytime!" },
	["reply.bye"] = { "GG, thanks all!", "Thanks for the run!", "See you!", { "Good night!", need = "night" } },
	["reply.lf_healer"] = { "I can heal", "I can heal, invite me", "{level} {class} healer here" },
	["reply.lf_tank"] = { "I can tank", "I can tank, invite me", "{level} {class} tank here" },
	["reply.lf_dps"] = { "DPS here, invite me", "{level} {class} DPS, invite please" },
	["reply.lfm"] = { "{level} {class} here, invite me", "What do you need?" },
	["reply.help_ask"] = { "Sure, where are you?", "On my way", "Sorry, busy right now" },
	["reply.summon_ask"] = { "On my way to summon", "Can't summon right now, sorry" },
	["reply.wait"] = { "Ok, no rush", "No problem", "Waiting" },
	["reply.sorry"] = { "No worries", "All good" },
	["reply.oom"] = { "Ok, waiting for mana", { "Drinking too", need = "lowMana" } },
	["reply.res_ask"] = { { "Ressing you now", need = "canRes" }, { "Coming to res", need = "canRes" }, { "Can't res, sorry", no = "canRes" } },
	["reply.pull"] = { "Go ahead", { "Wait, need mana", need = "lowMana" }, "Ready" },
	["reply.ding"] = { "Grats!", "Nice, grats!" },
	["reply.grats"] = { "Thanks!", "Thank you!" },
	["reply.portal"] = { "Sure, where to?", "Open trade when ready" },
	["reply.buff"] = { "Sure, one sec", "Buffing now" },
	["reply.question"] = { "Yes", "No", "Not sure", "One moment" },
	["reply.whisper"] = { "Ok!", "Thanks!", "Sorry, busy right now", "Give me a minute" },

	typing = {
		"Hello everyone!", "Hello, anyone up for a dungeon?", "Hi all!", "Hey, how are you?", "Thanks for the group!", "Thanks for the help!",
		"Thanks for the run!", "Thank you!", "Can you help me?", "Can you invite me?", "Can someone summon me?", "Can I join?",
		"Anyone up for a dungeon?", "Anyone want to group?", "Need a healer for {instance}", "Need a tank for {instance}", "Need one more for {quest}",
		"Where are you?", "Where do I go?", "I'm on my way", "I need mana", { "I can heal", need = "canHeal" }, { "I can tank", need = "canTank" },
		"Be right back", "One sec please", "Good job everyone!", "Good night all!", "Sorry about that", "No problem!", "Wait for me please",
		"Looking for a group", "Looking for more for {instance}", "LF healer for {instance}", "LF tank for {instance}", "What do you need?",
		"Who needs a summon?", "How much?", "Give me a minute", "Out of mana", "See you later!", "Let me know",
	},

	["short.lf"] = {
		"LFG {zone}", "LF1M healer for {instance}", "LF1M tank for {instance}",
		"LF2M DPS for {instance}", "{level} {class} LFG",
	},
	["short.lfg"] = { "LFG {zone}", "{level} {class} LFG", "{role} LFG, whisper me" },
	["short.lfm"] = { "LFM {instance}, whisper me", "LFM {quest}", "LFM, need all" },
	["short.lf1m"] = { "LF1M healer for {instance}", "LF1M tank for {instance}", "LF1M DPS for {instance}" },
	["short.wts"] = { "WTS, whisper me" },
	["short.wtb"] = { "WTB, whisper me" },
	["short.omw"] = { "On my way" },
	["short.brb"] = { "Be right back" },
	["short.afk"] = { "AFK 2 min", "AFK, back in a minute" },
	["short.ty"] = { "Thank you!", "Thanks for the group!" },
	["short.thx"] = { "Thanks!" },
	["short.np"] = { "No problem!" },
	["short.gg"] = { "GG, thanks all!" },
	["short.inv"] = { "Invite me please", "Inviting now" },
	["short.rdy"] = { "Ready" },
	["short.oom"] = { "Out of mana!" },
	["short.res"] = { "Res please" },
	["short.sum"] = { "Can I get a summon?" },
	["short.gl"] = { "Good luck!" },
	["short.gz"] = { "Grats!" },
	["short.idk"] = { "I don't know" },
	["short.wya"] = { "Where are you?" },
	["short.sry"] = { "Sorry!" },
}

-- Next-word seed: after the words on the left (one word, or two; "^" is the start of a sentence), the words on the
-- right, likeliest first. What the player sends outweighs it as it is learned.
P.SEED = {
	["^"] = "hello hi hey thanks can anyone need lf i where sorry ready",
	hello = "everyone there all guild", hi = "all there everyone guys", hey = "all there guys everyone", thanks = "for all everyone guys",
	["thanks for"] = "the your", ["for the"] = "group run help invite res summon heals", thank = "you", need = "a heal mana help more one",
	["need a"] = "healer tank hand break summon res", can = "you i someone anyone we", ["can you"] = "help invite summon heal res wait",
	["can i"] = "join get come have", ["can someone"] = "help invite summon res", ["can anyone"] = "help summon", anyone = "up want going need here know",
	["anyone up"] = "for", ["up for"] = "a some", ["anyone want"] = "to", ["anyone going"] = "to", ["anyone know"] = "where how",
	lf = "healer tank dps group", lfg = "for", lfm = "for need", lf1m = "healer tank dps", looking = "for", ["looking for"] = "a group more healer tank",
	i = "can need am will have", ["i can"] = "heal tank help come", ["i need"] = "a to mana help", ["i am"] = "on ready here coming",
	["i will"] = "be go wait", im = "on ready here coming", ["i'm"] = "on ready here coming", on = "my the", ["on my"] = "way",
	be = "right there back", ["be right"] = "back there", one = "sec moment more", give = "me", ["give me"] = "a", wait = "for a",
	["wait for"] = "me", where = "are is do", ["where are"] = "you we", ["where is"] = "the", ["where do"] = "i we", what = "is do are",
	who = "is wants needs", how = "do much many", is = "there anyone it", are = "you we", ["are you"] = "ready there coming",
	ready = "to when for", ["ready to"] = "go pull", ["ready when"] = "you", good = "job run game luck night morning", sorry = "about for my",
	["sorry about"] = "that", my = "bad way", no = "problem worries thanks", out = "of", ["out of"] = "mana range", want = "to",
	["want to"] = "join group come", going = "to", ["going to"] = "the", invite = "me please", inv = "me please", summon = "me please",
	heal = "me please", res = "me please", follow = "me", help = "me with please", ["help with"] = "this the", let = "me us", ["let me"] = "know",
	got = "it to", back = "in to", ["back in"] = "a", ["in"] = "a the", see = "you", ["see you"] = "later soon", run = "back to",
	we = "need can are", ["we need"] = "a one", you = "too can are", please = "invite wait", any = "healers tanks groups", nice = "one job",
	well = "done played", gg = "all thanks", ty = "all for", the = "group way boss", to = "the go join", a = "sec minute moment group healer",
	["for"] = "the a me", me = "please too",
}

-- First words that make a line a question: "?" is then offered as a pick.
P.QUESTIONS = { can = true, where = true, anyone = true, who = true, what = true, how = true, is = true, does = true, are = true, ["do"] = true, will = true, could = true, would = true, when = true, why = true, any = true }

-- Intent rules for an incoming line, tried in order. A rule matches when one of its has substrings is in the
-- lowercased line, or one of its any words is a whole word (and, when given, one of its with words too, in a line
-- of at most max words). question needs a "?". Only the first matching rule of a group counts. scope: who the
-- line must be for: "direct" (a whisper or a line naming the player), "group" (also party / raid / instance chat; the
-- default) or "public" (any channel). need / class gate the rule on the player (flags as for lines). to = "sender"
-- answers a public line in a whisper.
local ASK = { "pls", "plz", "please", "can", "could", "need", "me", "someone", "anyone" }
local LF = { "lf", "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "need", "looking", "seeking" }
P.INTENTS = {
	{ id = "invite_offer", group = "invite", score = 1, has = { "want an inv", "want inv", "want a inv", "wanna join", "want to join", "need a group", "join us", "want invite", "want an invite" } },
	{ id = "invite_ask", group = "invite", score = 1, max = 3, any = { "inv", "invite", "invy" }, has = { "invite me", "inv me", "inv pls", "inv plz", "inv please", "invite pls", "invite please", "get an inv", "can i join", "room for" } },
	{ id = "ready_ask", group = "ready", score = 1, has = { "everyone ready", "all ready", "you ready", "u ready", "ready check" } },
	{ id = "ready_ask", group = "ready", score = 1, question = true, max = 4, any = { "ready", "rdy", "r" } },
	{ id = "where", score = 0.9, has = { "where are you", "where r u", "where are u", "where u at", "where you at", "wya" } },
	{ id = "lf_healer", score = 0.9, scope = "public", to = "sender", need = "canHeal", any = { "healer", "heals", "heal", "healz" }, with = LF },
	{ id = "lf_tank", score = 0.9, scope = "public", to = "sender", need = "canTank", any = { "tank", "tanks" }, with = LF },
	{ id = "lf_dps", score = 0.7, scope = "public", to = "sender", need = "solo", any = { "dps", "dd", "damage" }, with = LF },
	{ id = "lfm", score = 0.5, scope = "public", to = "sender", need = "solo", any = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m" } },
	{ id = "help_ask", score = 0.8, has = { "can you help", "can u help", "help me", "need help", "could you help", "anyone help", "little help" } },
	{ id = "res_ask", group = "res", score = 0.9, any = { "res", "rez", "ress", "rezz", "resurrect" }, with = ASK },
	{ id = "res_ask", group = "res", score = 0.9, question = true, max = 2, any = { "res", "rez", "ress", "rezz" } },
	{ id = "summon_ask", score = 0.8, any = { "summon", "summ", "summons" }, with = ASK },
	{ id = "portal", score = 0.8, scope = "public", to = "sender", class = "MAGE", any = { "port", "portal", "water", "food" }, with = { "pls", "plz", "please", "can", "wtb", "lf", "need", "any" } },
	{ id = "buff", score = 0.7, any = { "buff", "buffs", "fort", "motw" }, with = { "pls", "plz", "please", "can", "got" } },
	{ id = "pull", score = 0.7, question = true, any = { "pull", "pulling" } },
	{ id = "oom", score = 0.7, any = { "oom", "mana", "drink", "drinking" } },
	{ id = "wait", score = 0.6, any = { "afk", "brb", "wait", "bio", "sec", "moment" } },
	{ id = "bye", score = 0.6, any = { "gg", "bye", "cya", "gtg", "gn" }, has = { "good run", "thanks for the group", "thanks for the run", "see you", "good night" } },
	{ id = "thanks", score = 0.6, any = { "thanks", "thx", "ty", "tyvm", "tysm", "thank", "cheers" } },
	{ id = "sorry", score = 0.5, any = { "sorry", "sry", "oops" }, has = { "my bad" } },
	{ id = "ding", score = 0.6, any = { "ding", "dinged" }, has = { "level up" } },
	{ id = "grats", score = 0.5, scope = "direct", any = { "grats", "gz", "gratz", "congrats" } },
	{ id = "greet", score = 0.5, max = 4, any = { "hi", "hello", "hey", "hiya", "heya", "yo", "sup", "greetings" } },
	{ id = "question", score = 0.4, scope = "direct", question = true },
}

local NONE = {}

function P.Text(line) return type(line) == "table" and line[1] or line end

local function edits(settings)
	local saved = type(settings.phrases) == "table" and settings.phrases or {}
	settings.phrases = saved
	saved.added = type(saved.added) == "table" and saved.added or {}
	saved.removed = type(saved.removed) == "table" and saved.removed or {}
	return saved
end

-- The lines of one key: the player's own first, then the defaults they haven't removed.
-- saved = { added = { [key] = { "line", ... } }, removed = { [key] = { ["default line"] = true } } }.
function P.Lines(saved, key)
	local added, removed = saved and saved.added and saved.added[key], saved and saved.removed and saved.removed[key]
	if not (added or removed) then return P.DEFAULTS[key] or NONE end
	local list = {}
	for _, line in ipairs(added or NONE) do list[#list + 1] = line end
	for _, line in ipairs(P.DEFAULTS[key] or NONE) do if not (removed and removed[P.Text(line)]) then list[#list + 1] = line end end
	return list
end

-- The phrase editor's writes: they only touch the saved edits. Add puts a new line first, or restores a removed
-- default in its place; false when the line is already there, or is a slash command (the keyboard never types one).
function P.Add(settings, key, text)
	if text:sub(1, 1) == "/" then return false end
	local saved = edits(settings)
	local removed = saved.removed[key]
	if removed and removed[text] then
		removed[text] = nil
		return true
	end
	for _, line in ipairs(P.Lines(saved, key)) do if P.Text(line) == text then return false end end
	saved.added[key] = saved.added[key] or {}
	table.insert(saved.added[key], 1, text)
	return true
end

function P.Remove(settings, key, text)
	local saved = edits(settings)
	for i, line in ipairs(saved.added[key] or NONE) do if line == text then return table.remove(saved.added[key], i) end end
	for _, line in ipairs(P.DEFAULTS[key] or NONE) do
		if P.Text(line) == text then
			saved.removed[key] = saved.removed[key] or {}
			saved.removed[key][text] = true
			return text
		end
	end
end

-- Back to the defaults: one key, or everything.
function P.Reset(settings, key)
	local saved = edits(settings)
	if not key then saved.added, saved.removed = {}, {} return end
	saved.added[key], saved.removed[key] = nil, nil
end
