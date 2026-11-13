-- Forever Controller Tweaks keyboard suggestions (design/suggestions.md): the ranked list for the tab beside the
-- disc, by the field being typed into. An empty chat box gets lines for the situation (prompts, replies to recent
-- chat, the phrase library, the player's own lines); a typed word gets shorthand expansions, word completions and
-- lines that continue it; a finished word gets the next word. A search box gets item names and recent searches, a
-- name box people. Every chat line carries its category and channel. Pure Lua on a context table
-- (Keyboard/Context.lua) and the saved store: no frames, no game calls, the same input always gives the same list.
local _, ns = ...
local K = ns.Keyboard
local P = K.Library
local S = {}
K.Suggest = S

-- At most MAX lines, PER_TAG a category (twice that only to reach FILL lines), QUEST_MAX quest lines always.
S.MAX, S.FILL, S.PER_TAG, S.QUEST_MAX, S.POOL, S.LEARNED = 8, 6, 2, 2, 200, 20
S.WORDS, S.NEXT, S.EXPAND, S.COMPLETE = 4, 8, 3, 2
S.GRAM_CAP, S.LINE_CAP, S.USAGE_CAP, S.COUNT_MAX, S.LINE_MAX, S.RECENT, S.SEARCH_MAX = 6000, 150, 300, 100, 80, 20, 40
-- score = context + 1.5 urgency + 0.6 personal + 0.3 recency - 0.03 order (see the design note).
local W_URGENCY, W_PERSONAL, W_RECENCY, W_ORDER, W_FOLLOWS = 1.5, 0.6, 0.3, 0.03, 1
local MATCH_BONUS, REPLY_WEIGHT, YOURS_WEIGHT, TYPING_WEIGHT, ALIKE, FRESH_BONUS, FRESH_TIME = 0.15, 0.7, 0.5, 0.3, 0.75, 0.2, 60
local REPLY_HALF_LIFE, GREET_TIME, RECENCY_DAYS, OWN = 45, 120, 7, 3
local QUEST_TAG, REPLY_TAG, YOURS_TAG, PHRASE_TAG, NEXT_TAG, ITEM_TAG, RECENT_TAG = "Quest", "Reply", "Yours", "Phrase", "Next", "Item", "Recent"
-- Fields: chat phrases and replies only where the player talks; the next word also in other free text; a typed
-- search is remembered for its kind of box.
local TALK = { chat = true, whisper = true }
local PROSE = { chat = true, whisper = true, text = true }
local SEARCHES = { bag = true, auction = true, search = true }
-- Fields whose rows never come from the word list: the view skips its word search there.
S.LOOKUP = { numeric = true, bag = true, auction = true, name = true }
local ROLE = { tank = "tank", healer = "healer", damage = "DPS" }
-- A hint row: the best line is for another channel, which only the chat's own controls may switch to.
S.HINT_REPLY, S.HINT_LINES = "Reply to %s: switch the chat to %s first", "%s lines: switch the chat to %s first"
local CHANNEL_NAME = { WHISPER = "Whisper", BN_WHISPER = "Whisper", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild", SAY = "Say" }
local GROUP_KINDS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local WHISPERS = { WHISPER = true, BN_WHISPER = true }
-- How a learned line travels: the channel it was sent on, as a via.
local VIA = { PARTY = "group", RAID = "group", INSTANCE_CHAT = "group", GUILD = "guild", SAY = "say", WHISPER = "whisper", BN_WHISPER = "whisper" }
-- Needs that name a passing state rather than a standing condition: a line that asks for one fits the moment.
local MOMENT = {
	lowMana = true, lowHealth = true, elite = true, vendor = true, trainer = true, flight = true, questgiver = true, night = true, questDone = true,
	questShared = true,
}
local BUCKETS = { "battleground", "dungeon", "raid", "city", "group", "world" }
local LEARN_TOKENS = { "instance", "subzone", "zone", "target" }
local NONE = {}

function S.Store(settings)
	local store = type(settings.suggest) == "table" and settings.suggest or {}
	settings.suggest = store
	for _, key in ipairs({ "grams", "lines", "usage", "recent" }) do if type(store[key]) ~= "table" then store[key] = {} end end
	return store
end

local function short(name) return name:match("^[^-]+") or name end

---------------------------------------------------------------------------------------------------------------------
-- The situation: flags a line or rule can ask for, the live situations, token values.

local function flagsOf(ctx)
	local target, npc, quest, grouped = ctx.target, ctx.npc, ctx.quest, ctx.group ~= "none"
	local flags = {
		lowMana = ctx.lowMana, lowHealth = ctx.lowHealth, canHeal = ctx.canHeal, canTank = ctx.canTank, canRes = ctx.canRes, guild = ctx.guild,
		grouped = grouped, solo = not grouped, leader = ctx.leader, resting = ctx.resting, inside = ctx.instance ~= "none", elite = target and target.elite,
		forming = ctx.group == "party" and ctx.size < 5 and ctx.instance == "none", questDone = quest and quest.done, questShared = quest and quest.shared,
	}
	flags[ctx.role or "damage"] = true
	if npc and npc.kind then flags[npc.kind] = true end
	if ctx.time then flags[ctx.time] = true end
	return flags
end

local ACTIVE = {
	dead = function(c) return c.dead end,
	combat = function(c) return c.combat and not c.dead end,
	newgroup = function(c, f) return f.grouped and c.joinedAt ~= nil and c.now - c.joinedAt < GREET_TIME end,
	battleground = function(c) return c.instance == "pvp" or c.instance == "arena" end,
	dungeon = function(c) return c.instance == "party" end,
	raid = function(c) return c.instance == "raid" or c.group == "raid" and c.instance == "none" end,
	quest = function(c) return c.quest ~= nil end,
	progress = function(c) return c.quest ~= nil end,
	whisper = function(c) return c.field == "whisper" end,
	friend = function(c)
		local target = c.target
		return target ~= nil and target.player and target.friendly and not target.self
	end,
	enemy = function(c)
		local target = c.target
		return target ~= nil and target.hostile and not target.player and not target.dead
	end,
	npc = function(c, f) return c.npc ~= nil and f.grouped end,
	group = function(_, f) return f.grouped end,
	queue = function(c) return c.lfg ~= nil end,
	city = function(c, f) return c.resting and not f.inside end,
	guild = function(c) return c.guild and (c.resting or c.box.kind == "GUILD") end,
	world = function(c, f) return not c.resting and not f.inside and f.solo end,
	anywhere = function() return true end,
}

local function bucketOf(ctx, flags)
	for _, id in ipairs(BUCKETS) do if ACTIVE[id](ctx, flags) then return id end end
	return "anywhere"
end

local function valuesOf(ctx)
	local target, quest, npc, zone, subzone = ctx.target, ctx.quest, ctx.npc, ctx.zone, ctx.subzone
	local name, open = target and target.name, quest and not quest.done and quest or nil
	local have, need = open and open.have, open and open.need
	local counted = have and need and need > 1 and have < need
	return {
		objective = open and open.objective, progress = counted and have .. "/" .. need, left = counted and need - have,
		target = name, friend = target and target.player and target.friendly and not target.self and name,
		enemy = target and target.hostile and not target.dead and name, npc = npc and npc.name, zone = zone, subzone = subzone ~= zone and subzone,
		instance = ctx.instanceName, quest = quest and (quest.link or quest.title), class = ctx.className, role = ROLE[ctx.role], player = ctx.me,
		level = ctx.level, time = ctx.time,
	}
end

-- A line with its tokens filled, or nil when one can't be. A line that opens with a token starts with a capital.
local function fill(template, values, from)
	local missing = false
	local text = template:gsub("{(%a+)}", function(token)
		local value = token == "from" and from or values[token]
		if not value or value == "" then missing = true end
		return tostring(value)
	end)
	if missing then return end
	return template:sub(1, 1) == "{" and text:sub(1, 1):upper() .. text:sub(2) or text
end

---------------------------------------------------------------------------------------------------------------------
-- Channels. The keyboard never switches the chat's channel: a slash command in the box is parsed by the box inside
-- our call (ChatFrameEditBox.lua ParseText -> ProcessChatType), which the game blocks. So a line is offered only
-- when the box is already on its channel. route: where a via leads, as { kind, target, id }; nil is no channel of
-- its own (any box); false means the line has nowhere to go and is dropped.

-- A reply goes back where the line came from (a yell is answered in say); a prompt, a whisper and a public call
-- such as "LF healer" are answered in a whisper to the sender.
local function replyRoute(msg, rule)
	local kind, from, id = msg.kind, msg.from, msg.channel
	if kind == "BN_WHISPER" then return { kind = kind } end
	local private = not kind or kind == "WHISPER" or kind == "CHANNEL" and not id or not GROUP_KINDS[kind] and rule ~= nil and rule.to == "sender"
	if private then return from and { kind = "WHISPER", target = from } or nil end
	return { kind = kind == "YELL" and "SAY" or kind, id = id }
end

local function route(via, ctx, msg, rule)
	local target, groupChannel = ctx.target, ctx.groupChannel
	if via == "group" then return groupChannel and { kind = groupChannel } or false end
	if via == "auto" then return groupChannel and { kind = groupChannel } or nil end
	if via == "say" then return { kind = "SAY" } end
	if via == "guild" then return ctx.guild and { kind = "GUILD" } or false end
	if via == "whisper" and not WHISPERS[ctx.box.kind] then return false end
	if via == "target" then return target and target.player and target.friendly and not target.self and { kind = "WHISPER", target = target.full } or false end
	if via == "reply" then return replyRoute(msg, rule) end
	local id = (via == "lfg" or via == "trade") and ctx.channels[via]
	return id and { kind = "CHANNEL", id = id } or nil
end

-- Whether the box is on a channel already (its chat type, whisper target or channel number, as read).
local function onChannel(channel, box)
	local kind = channel.kind
	if box.kind ~= kind then return false end
	if kind == "WHISPER" then return box.target ~= nil and short(box.target):lower() == short(channel.target):lower() end
	return kind ~= "CHANNEL" or tonumber(box.channel) == channel.id
end

---------------------------------------------------------------------------------------------------------------------
-- Candidates and their score.

local function habit(usage, key, day)
	local entry = usage[key]
	if not entry then return 0 end
	local accepts, ignores, last = entry.a, entry.i, entry.d
	local personal = math.max(-0.3, (accepts - 0.25 * ignores) / (accepts + ignores + 3))
	return W_PERSONAL * personal + W_RECENCY * (last and 0.5 ^ (math.max(0, day - last) / RECENCY_DAYS) or 0)
end

-- One line of a source as a row, or nil when its conditions or tokens fail, it is for another kind of field, it
-- has no channel to go to, or the box is on another channel. The best line lost to another channel is kept as
-- env.elsewhere, for the hint row.
-- source = { tag, context, urgency, via, msg, rule, thread, bonus, mode, field }.
local function make(env, source, line, order)
	local ctx, flags, via, msg, tag, field = env.ctx, env.flags, source.via, source.msg, source.tag, source.field
	local template, matched = line, 0
	if type(line) == "table" then
		local role, need, no, class = line.role, line.need, line.no, line.class
		if role and not flags[role] or need and not flags[need] or no and flags[no] or class and class ~= ctx.class then return end
		template, via, matched, field = line[1], line.via or via, (role or MOMENT[need]) and MATCH_BONUS or 0, line.field or field
	end
	if field and field ~= ctx.field then return end
	local from, thread = msg and (msg.name or msg.from and short(msg.from)), source.thread
	local text = fill(template, env.values, from)
	if not text or text:sub(1, 1) == "/" then return end

	local channel, elsewhere = route(via, ctx, msg, source.rule), env.elsewhere
	if channel == false then return end
	local score = source.context + matched + W_URGENCY * (source.urgency or 0) + habit(env.usage, template, ctx.day) + (source.bonus or 0) - W_ORDER * math.min(order, 10)
	if channel and not onChannel(channel, ctx.box) then
		if not elsewhere or score > elsewhere.score then env.elsewhere = { score = score, channel = channel, tag = tag, from = thread and from } end
		return
	end
	return { text = text, key = template, category = tag, tag = tag, channel = channel, mode = source.mode or "phrase", thread = thread, score = score }
end

local function offer(env, source, lines)
	local pool, order = env.pool, 0
	for _, line in ipairs(lines) do
		local item = #pool < S.POOL and make(env, source, line, order)
		if item then pool[#pool + 1], order = item, order + 1 end
	end
end

-- The player's own lines: sent twice or more in this kind of place, or (while typing) starting with what is typed.
local function offerLearned(env, lines, typed)
	local ctx, list = env.ctx, {}
	local bucket = bucketOf(ctx, env.flags)
	for template, entry in pairs(lines) do
		local fits = typed and template:lower():sub(1, #typed) == typed or not typed and entry.n >= 2 and (entry.sit == bucket or entry.sit == "anywhere")
		if fits then list[#list + 1] = template end
	end
	table.sort(list, function(a, b)
		local na, nb = lines[a].n, lines[b].n
		if na ~= nb then return na > nb end
		return a < b
	end)
	for i = 1, math.min(#list, S.LEARNED) do
		local template = list[i]
		local entry = lines[template]
		local n, last = entry.n, entry.d
		local bonus = W_PERSONAL * n / (n + 3) + W_RECENCY * (last and 0.5 ^ (math.max(0, ctx.day - last) / RECENCY_DAYS) or 0)
		offer(env, { tag = YOURS_TAG, context = YOURS_WEIGHT, via = entry.via, bonus = bonus }, { template })
	end
end

-- Every line that fits the situation and the box's channel, scored. typed (the sentence so far, lowercase) adds
-- the lines kept for continuing a sentence and the player's own lines that start the way it does.
local function gather(settings, ctx, typed)
	local store, now, saved = S.Store(settings), ctx.now, settings.phrases
	local flags = flagsOf(ctx)
	local env = { ctx = ctx, flags = flags, values = valuesOf(ctx), usage = store.usage, pool = {} }

	for _, sit in ipairs(P.SITUATIONS) do
		local id, prompt, urgency = sit.id, nil, 0
		local live = not sit.urgent and ACTIVE[id](ctx, flags)
		if sit.urgent then
			prompt = ctx.prompts[id]
			live = prompt ~= nil and now - prompt.at < prompt.ttl
			if live then urgency = 1 - 0.5 * (now - prompt.at) / prompt.ttl end
		end
		local moved = sit.fresh and ctx.quest and ctx.quest.changedAt
		local bonus = moved and FRESH_BONUS * math.max(0, 1 - (now - moved) / FRESH_TIME) or nil
		if live then
			offer(env, { tag = sit.tag, context = sit.weight, urgency = urgency, via = sit.via, msg = prompt, field = sit.field, bonus = bonus }, P.Lines(saved, id))
		end
	end

	for _, msg in ipairs(ctx.inbox) do
		local kind, intents = msg.kind, msg.intents
		local strength = (msg.direct and 1 or GROUP_KINDS[kind] and 0.7 or 0.5) * 0.5 ^ ((now - msg.at) / REPLY_HALF_LIFE)
		local answered = false
		for _, rule in ipairs(P.INTENTS) do
			local id, need, class = rule.id, rule.need, rule.class
			if intents[id] == rule and (not need or flags[need]) and (not class or class == ctx.class) then
				answered = true
				offer(env, { tag = REPLY_TAG, context = REPLY_WEIGHT, urgency = rule.score * strength, via = "reply", msg = msg, rule = rule, thread = msg }, P.Lines(saved, "reply." .. id))
			end
		end
		if not answered and WHISPERS[kind] then
			offer(env, { tag = REPLY_TAG, context = REPLY_WEIGHT, urgency = 0.5 * strength, via = "reply", msg = msg, thread = msg }, P.Lines(saved, "reply.whisper"))
		end
	end

	if typed then offer(env, { tag = PHRASE_TAG, context = TYPING_WEIGHT }, P.Lines(saved, "typing")) end
	offerLearned(env, store.lines, typed)
	return env
end

---------------------------------------------------------------------------------------------------------------------
-- Choosing: best first, no near-duplicates, a cap per category.

local function byScore(a, b)
	if a.score ~= b.score then return a.score > b.score end
	if a.text ~= b.text then return a.text < b.text end
	return a.tag < b.tag
end

local function readable(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|[hr]", "")):lower() end

local function wordsOf(item)
	if item.words then return item.words, item.count end
	local words, count = {}, 0
	for word in readable(item.text):gmatch("[%w\128-\255']+") do if not words[word] then words[word], count = true, count + 1 end end
	item.words, item.count = words, count
	return words, count
end

-- The same words, or nearly (ALIKE of them shared), as a line already chosen.
local function duplicate(item, chosen)
	local words, count = wordsOf(item)
	for _, other in ipairs(chosen) do
		local theirs, total = wordsOf(other)
		local shared = 0
		for word in pairs(words) do if theirs[word] then shared = shared + 1 end end
		if shared == count + total - shared or shared / (count + total - shared) >= ALIKE then return true end
	end
	return false
end

-- With two conversations waiting, the first pass takes one reply to each before a second to either.
local function choose(pool, most)
	table.sort(pool, byScore)
	local chosen, perTag, perThread, threads = {}, {}, {}, 0
	for _, item in ipairs(pool) do
		local thread = item.thread
		if thread and not perThread[thread] then perThread[thread], threads = 0, threads + 1 end
	end
	for pass = 1, 2 do
		local cap, stop = S.PER_TAG * pass, math.min(most, pass == 1 and S.MAX or S.FILL)
		for _, item in ipairs(pool) do
			if #chosen >= stop then break end
			local category, thread = item.category, item.thread
			local limit = category == QUEST_TAG and math.min(cap, S.QUEST_MAX) or cap
			local crowded = pass == 1 and threads > 1 and thread and perThread[thread] >= 1
			if not item.chosen and not crowded and (perTag[category] or 0) < limit and not duplicate(item, chosen) then
				item.chosen, perTag[category] = true, (perTag[category] or 0) + 1
				if thread then perThread[thread] = perThread[thread] + 1 end
				chosen[#chosen + 1] = item
			end
		end
	end
	table.sort(chosen, byScore)
	return chosen
end

---------------------------------------------------------------------------------------------------------------------
-- Typing: the next word. Pairs and triples of the player's sent lines, and of the shipped seed, say what follows
-- the last two words, else the last one, else what starts a sentence.

local function tokens(text)
	local list = {}
	for word in text:lower():gmatch("[%w\128-\255']+") do list[#list + 1] = word end
	return list
end

local function count(grams, context, word, n)
	local row = grams[context]
	if not row then
		row = {}
		grams[context] = row
	end
	row[word] = (row[word] or 0) + n
end

-- One line's sentences: grams["^"]["on"], grams["on"]["my"], grams["on my"]["way"] ("^" starts a sentence). Only
-- a sentence's first 16 words count.
local function train(grams, text)
	for part in text:gmatch("[^%.!%?]+") do
		local before, last = nil, "^"
		for i, word in ipairs(tokens(part)) do
			if i > 16 then break end
			count(grams, last, word, 1)
			if before then count(grams, before .. " " .. last, word, 1) end
			before, last = last, word
		end
	end
end

local shipped

-- The seed (K.Library.SEED) as counts: its words weigh 3, 2, then 1 by their place.
local function shippedGrams()
	if shipped then return shipped end
	shipped = {}
	for context, words in pairs(P.SEED) do for i, word in ipairs(tokens(words)) do count(shipped, context, word, math.max(1, 4 - i)) end end
	return shipped
end

-- The words after one context that have no score yet get lift + their share; a count of the player's own is worth
-- OWN shipped ones. True when the context is known at all.
local function tier(scores, store, context, lift)
	local counts, total = {}, 0
	for word, n in pairs(store.grams[context] or NONE) do counts[word], total = n * OWN, total + n * OWN end
	for word, n in pairs(shippedGrams()[context] or NONE) do counts[word], total = (counts[word] or 0) + n, total + n end
	for word, n in pairs(counts) do if not scores[word] then scores[word] = lift + n / total end end
	return total > 0
end

-- { word = score } after the words in list (a sentence so far, led by "^"): 2 and up for a word that follows the
-- last two, 1 and up for one that follows the last, under 1 for a sentence starter when neither is known.
function S.Predict(store, list)
	local last, before, scores = list[#list], list[#list - 1], {}
	local known = before ~= nil and tier(scores, store, before .. " " .. last, 2)
	known = tier(scores, store, last, 1) or known
	if not known then tier(scores, store, "^", 0) end
	return scores
end

-- The sentence the cursor is in: its words led by "^", the byte it starts at, and whether the next word opens it.
local function sentence(head)
	local start = 1
	for after in head:gmatch("[%.!%?]+%s+()") do start = after end
	local list = tokens(head:sub(start))
	table.insert(list, 1, "^")
	return list, start, head:match("^%s*$") ~= nil or head:match("[%.!%?]%s*$") ~= nil
end

-- What is typed of that sentence so far, lowercase, and the byte it starts at.
local function typedOf(head)
	local _, start = sentence(head)
	return head:sub(start):match("^%s*(.-)%s*$"):lower(), start
end

-- A pick as it is typed: "I" and its contractions always capital, any pick capital when it opens a sentence.
local function cased(word, opens)
	if word == "i" or word:sub(1, 2) == "i'" then return "I" .. word:sub(2) end
	return opens and word:sub(1, 1):upper() .. word:sub(2) or word
end

-- Up to NEXT picks for the word after head. A sentence that opens like a question also gets "?", fourth at most.
local function nextWords(store, head)
	local list, _, opens = sentence(head)
	local scores, words, items = S.Predict(store, list), {}, {}
	for word in pairs(scores) do words[#words + 1] = word end
	table.sort(words, function(a, b)
		if scores[a] ~= scores[b] then return scores[a] > scores[b] end
		return a < b
	end)
	for i = 1, math.min(#words, S.NEXT) do items[i] = { text = cased(words[i], opens), mode = "next", category = NEXT_TAG, tag = NEXT_TAG } end
	if P.QUESTIONS[list[2]] and #list > 2 then
		table.insert(items, math.min(4, #items + 1), { text = "?", mode = "next", category = NEXT_TAG, tag = NEXT_TAG })
		items[S.NEXT + 1] = nil
	end
	return items
end

-- Engine's word results, re-ranked by how well each follows the words before it in the sentence (the share of a
-- pair, 1 more for a triple). A predicted word that the typed letters start goes ahead of every other, in the
-- dictionary or not. The first word of a sentence is left as ranked. The case follows the typed word.
local function rerank(store, before, typed, results)
	local list = sentence(before)
	local follows, ranked, seen, lower = #list > 1 and S.Predict(store, list) or NONE, {}, {}, typed:lower()
	for i, result in ipairs(results) do
		local word = result.word
		local key = word:lower()
		local follow = follows[key] or 0
		local continues = follow >= 1 and key:sub(1, #lower) == lower
		ranked[i], seen[key] = { word = word, dist = result.dist, score = continues and -3 - follow or result.score - W_FOLLOWS * math.max(0, follow - 1) }, true
	end
	for word, follow in pairs(follows) do
		if follow >= 1 and #word > #lower and word:sub(1, #lower) == lower and not seen[word] then
			ranked[#ranked + 1] = { word = typed:match("^%u") and word:sub(1, 1):upper() .. word:sub(2) or word, dist = #word - #lower, score = -3 - follow }
		end
	end
	table.sort(ranked, function(a, b)
		if a.score ~= b.score then return a.score < b.score end
		return a.word < b.word
	end)
	return ranked
end

-- Lines of the pool that continue the sentence being typed (2 characters or more of it), best first. Taking one
-- replaces the text from where that sentence starts.
local function continuations(pool, head, taken)
	local list, typed, start = {}, typedOf(head)
	if #typed < 2 then return list end
	table.sort(pool, byScore)
	for _, item in ipairs(pool) do
		local text = readable(item.text)
		if #list < S.COMPLETE and #text > #typed and text:sub(1, #typed) == typed and not taken[text] then
			taken[text], item.mode, item.start = true, "line", start
			list[#list + 1] = item
		end
	end
	return list
end

local function append(list, items, first, last) for i = first or 1, math.min(last or #items, #items) do list[#list + 1] = items[i] end end

---------------------------------------------------------------------------------------------------------------------
-- Fields that look something up: a bag or auction search, a name, another search box.

-- Rows from lists of values that hold the typed text (those that start with it first), each list in its turn.
-- sources = { { values, tag, most =, starts = }, ... }: at most `most` of a list; starts keeps only values that
-- start with the text (names). A value is a string or { name, tag }.
local function lookup(text, sources)
	local typed, rows, seen, order = text:match("^%s*(.-)%s*$"):lower(), {}, {}, 0
	for _, source in ipairs(sources) do
		local values, tag, starts = source[1], source[2], source.starts
		for i = 1, math.min(#values, source.most or #values) do
			local value = values[i]
			local name, label = type(value) == "table" and value.name or value, type(value) == "table" and value.tag or tag
			local lower = name:lower()
			local at = typed == "" and 1 or lower:find(typed, 1, true)
			if at and (at == 1 or not starts) and lower ~= typed and not seen[lower] then
				seen[lower], order = true, order + 1
				rows[#rows + 1] = { text = name, mode = "line", category = label, tag = label, rank = at == 1 and 0 or 1, order = order }
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.order < b.order
	end)
	for i = #rows, S.MAX + 1, -1 do rows[i] = nil end
	return rows
end

-- The one row that can't be taken: it says which channel the best line needs. It sits last on the first page, so
-- row 1 stays a line R1 can insert.
local function hintRow(elsewhere)
	local channel, from = elsewhere.channel, elsewhere.from
	local name = CHANNEL_NAME[channel.kind] or "channel " .. tostring(channel.id)
	return { text = from and S.HINT_REPLY:format(from, name) or S.HINT_LINES:format(elsewhere.tag, name), mode = "hint", category = "Hint", tag = "", channel = channel, score = elsewhere.score }
end

local HEADS = { words = { kind = "words" }, items = { kind = "items" }, names = { kind = "names" }, searches = { kind = "searches" }, none = { kind = "none" } }

local function plainWords(list, results) for i = 1, math.min(#results, S.WORDS) do list[#list + 1] = { text = results[i].word, mode = "word", category = "Word", tag = "" } end end

-- The rows for the tab, by the field (ctx.field) the box is:
--   chat, whisper   phrases for the situation in an empty box; while typing: shorthand, words, the next word and
--                   lines that continue the sentence
--   text            words and the next word (mail, a macro, a note)
--   bag, auction    item names carried and recent searches
--   name            people: whoever whispered, the group, friends, the guild
--   search          recent searches, then words
--   numeric         nothing
--   unknown         words only
-- results: Engine's K.Rank for the word under the cursor (nil when there is none, or fewer than two letters).
-- Returns the rows ({ text, tag, category, channel, mode, key }), the heading ({ kind, place }) and the
-- row to pre-focus as a correction.
function S.List(settings, ctx, text, cur, results)
	local field, store = ctx.field, S.Store(settings)
	local recent, blank = store.recent[field] or NONE, text:match("^%s*$") ~= nil
	if field == "numeric" then return {}, HEADS.none end
	if field == "bag" then return lookup(text, blank and { { recent, RECENT_TAG, most = 3 }, { ctx.items, ITEM_TAG } } or { { ctx.items, ITEM_TAG }, { recent, RECENT_TAG } }), HEADS.items end
	if field == "auction" then return lookup(text, { { recent, RECENT_TAG }, { ctx.items, ITEM_TAG } }), HEADS.items end
	if field == "name" then return lookup(text, { { ctx.whisperers, "Whisper", starts = true }, { ctx.names, starts = true } }), HEADS.names end

	local talk, prose, list = TALK[field], PROSE[field], field == "search" and lookup(text, { { recent, RECENT_TAG, most = S.WORDS } }) or {}
	local head = field == "search" and HEADS.searches or HEADS.words
	if blank then
		if not talk then return list, head end
		local env = gather(settings, ctx)
		local rows, elsewhere = choose(env.pool, S.MAX), env.elsewhere
		if elsewhere and not (rows[1] and rows[1].score >= elsewhere.score) then table.insert(rows, math.min(#rows + 1, S.FILL), hintRow(elsewhere)) end
		rows[S.MAX + 1] = nil
		return rows, { kind = "phrases", place = ctx.instanceName or ctx.zone or "" }
	end

	local word, first = K.WordAt(text, cur)
	if not word and not prose then return list, head end
	local taken, env = {}, talk and gather(settings, ctx, (typedOf(text:sub(1, cur))))
	if not word then
		local picks, lines = nextWords(store, text:sub(1, cur)), env and continuations(env.pool, text:sub(1, cur), taken) or NONE
		append(list, picks, 1, 4)
		append(list, lines)
		append(list, picks, 5)
		return list, head
	end

	if not prose then
		plainWords(list, results or NONE)
		return list, head
	end
	local expansions, pool = {}, env and env.pool
	if env then
		env.pool = expansions
		offer(env, { tag = PHRASE_TAG, context = 1, mode = "line" }, P.Lines(settings.phrases, "short." .. text:match("^%s*(.-)%s*$"):lower()))
		table.sort(expansions, byScore)
		for i = #expansions, S.EXPAND + 1, -1 do expansions[i] = nil end
		for _, item in ipairs(expansions) do taken[readable(item.text)] = true end
	end
	append(list, expansions)

	local ranked = rerank(store, text:sub(1, first - 1), word, results or NONE)
	local fix = #expansions == 0 and K.Correction(settings.dictionary or NONE, word, ranked) and #list + 1 or nil
	plainWords(list, ranked)
	if pool then append(list, continuations(pool, text:sub(1, cur), taken)) end
	return list, head, fix
end

---------------------------------------------------------------------------------------------------------------------
-- Inserting, and learning from what the player does.

-- The box after a row is taken: the new text and byte cursor. Only the row's own words go in, never a command.
-- A word replaces the word under the cursor; a next word goes in at the cursor with a space after it ("?" closes
-- up to the word before); a line replaces the text, or only the sentence it continues when that isn't the first; a
-- phrase does the same in an empty box and otherwise goes in at the cursor; a hint changes nothing.
function S.Apply(item, text, cur)
	local mode, value, start = item.mode, item.text, item.start or 1
	if mode == "hint" then return text, cur end
	if mode == "word" then
		local _, first, last = K.WordAt(text, cur)
		if not first then return text, cur end
		return text:sub(1, first - 1) .. value .. " " .. text:sub(last + 1), first + #value
	end
	local gap = cur > 0 and not text:sub(cur, cur):match("%s") and " " or ""
	if mode == "next" and value:match("^%p$") then
		local head = text:sub(1, cur):gsub("%s+$", "")
		return head .. value .. " " .. text:sub(cur + 1), #head + #value + 1
	end
	if mode == "next" then return K.Insert(text, cur, gap .. value .. " ") end
	if mode ~= "line" and not text:match("^%s*$") then return K.Insert(text, cur, gap .. value) end
	local line = start > 1 and text:sub(1, start - 1) .. value or value
	return line, #line
end

-- A taken row is reinforced; the phrases shown with it and passed over count as ignored.
function S.Accept(settings, item, shown, ctx)
	local key, usage = item.key, S.Store(settings).usage
	if not key then return end
	local function entry(id)
		usage[id] = usage[id] or { a = 0, i = 0 }
		return usage[id]
	end
	local taken = entry(key)
	taken.a, taken.d = taken.a + 1, ctx.day
	for i = 1, math.min(#shown, S.FILL) do
		local other = shown[i].key
		if other and other ~= key then entry(other).i = entry(other).i + 1 end
	end
end

local function size(map)
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	return n
end

-- Keeps the cap best keys of map (better(a, b) on keys) and drops the rest.
local function keep(map, cap, better)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	if #keys <= cap then return end
	table.sort(keys, better)
	for i = cap + 1, #keys do map[keys[i]] = nil end
end

local function pruneLines(lines, cap)
	keep(lines, cap, function(a, b)
		local la, lb = lines[a], lines[b]
		if la.n ~= lb.n then return la.n > lb.n end
		if (la.d or 0) ~= (lb.d or 0) then return (la.d or 0) > (lb.d or 0) end
		return a < b
	end)
end

local function entries(grams)
	local n = 0
	for _, row in pairs(grams) do n = n + size(row) end
	return n
end

-- The most counted pairs and triples stay; ties drop in alphabetical order from the end.
function S.PruneGrams(grams, cap)
	local all = {}
	if entries(grams) <= cap then return end
	for context, row in pairs(grams) do for word, n in pairs(row) do all[#all + 1] = { context, word, n } end end
	table.sort(all, function(a, b)
		if a[3] ~= b[3] then return a[3] > b[3] end
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	for i = cap + 1, #all do
		local context, word = all[i][1], all[i][2]
		grams[context][word] = nil
		if not next(grams[context]) then grams[context] = nil end
	end
end

-- The line with the place and target names the player typed turned back into tokens, so it fits the next place.
local function templated(line, values)
	for _, token in ipairs(LEARN_TOKENS) do
		local value = values[token]
		local first, last = nil, nil
		if type(value) == "string" and #value >= 4 then first, last = line:find(value, 1, true) end
		if first then line = line:sub(1, first - 1) .. "{" .. token .. "}" .. line:sub(last + 1) end
	end
	return line
end

-- Incoming lines this send answers leave the inbox: a whisper to their sender, or a line on their channel.
local function answer(inbox, box)
	local kind, target = box.kind, box.target and short(box.target):lower()
	for i = #inbox, 1, -1 do
		local msg = inbox[i]
		local name = msg.name
		local toSender = kind == "WHISPER" and name and name:lower() == target
		if toSender or kind ~= "WHISPER" and kind ~= "CHANNEL" and msg.kind == kind then table.remove(inbox, i) end
	end
end

-- What the player entered with the keyboard. A search is remembered for its kind of box (the newest RECENT). A
-- chat line teaches its word pairs and triples, and the line itself for this kind of place. Commands, links and
-- every other box are not learned.
function S.Sent(settings, text, ctx)
	local box, field, store = ctx.box, ctx.field, S.Store(settings)
	local line = text:gsub("{rt%d}", ""):gsub("%s+", " "):match("^ ?(.-) ?$")
	if SEARCHES[field] and #line > 0 and #line <= S.SEARCH_MAX then
		local recent = store.recent[field] or {}
		store.recent[field] = recent
		for i = #recent, 1, -1 do if recent[i]:lower() == line:lower() then table.remove(recent, i) end end
		table.insert(recent, 1, line)
		recent[S.RECENT + 1] = nil
	end
	if not TALK[field] or text:find("^%s*/") or text:find("|", 1, true) then return end
	local grams, lines = store.grams, store.lines
	answer(ctx.inbox, box)
	if #line < 2 then return end
	train(grams, line)
	if entries(grams) > S.GRAM_CAP * 1.25 then S.PruneGrams(grams, S.GRAM_CAP) end
	if #line > S.LINE_MAX then return end

	local template = templated(line, valuesOf(ctx))
	local entry = lines[template] or { n = 0 }
	lines[template] = entry
	entry.n, entry.d, entry.sit, entry.via = entry.n + 1, ctx.day, bucketOf(ctx, flagsOf(ctx)), VIA[box.kind]
	if size(lines) > S.LINE_CAP * 1.25 then pruneLines(lines, S.LINE_CAP) end
end

local function round(value) return math.floor(value * 100 + 0.5) / 100 end

-- At logout: the caps, and aging. Counts halve once one passes COUNT_MAX, so new habits can overtake old ones;
-- accepts fade by 5% and ignores by half, and a phrase with neither left is forgotten.
function S.Prune(settings)
	local store = S.Store(settings)
	local grams, lines, usage, top = store.grams, store.lines, store.usage, 0
	for _, row in pairs(grams) do for _, n in pairs(row) do if n > top then top = n end end end
	if top > S.COUNT_MAX then for _, row in pairs(grams) do for word, n in pairs(row) do row[word] = math.ceil(n / 2) end end end
	S.PruneGrams(grams, S.GRAM_CAP)
	pruneLines(lines, S.LINE_CAP)
	for key, entry in pairs(usage) do
		entry.a, entry.i = round(entry.a * 0.95), round(entry.i * 0.5)
		if entry.a < 0.2 and entry.i < 0.2 then usage[key] = nil end
	end
	keep(usage, S.USAGE_CAP, function(a, b)
		local ua, ub = usage[a], usage[b]
		if ua.a ~= ub.a then return ua.a > ub.a end
		return a < b
	end)
end
