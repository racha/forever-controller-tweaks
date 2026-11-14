-- Forever Controller Tweaks keyboard engine (design/keyboard.md): charsets, stick sectors, UTF-8 safe editing on
-- (text, byte cursor), the word list and its ranking, quick phrases and placement. No frames: Keyboard/View.lua draws
-- and drives it, tests/keyboard_spec.lua runs it under plain Lua.
local ns = ForeverControllerTweaks
local K = {}
ns.Keyboard = K

-- Stick thresholds (the native radial's): a set focuses past SET_ON; a key lights past KEY_HOVER, types once past
-- KEY_TYPE and re-arms at or below it.
K.SET_ON, K.KEY_HOVER, K.KEY_TYPE = 0.5, 0.15, 0.5
K.CAP = 20000

-- Eight sets clockwise from the top; each is [top, right, bottom, left] = [FT, FR, FB, FL].
local RT = { "{rt1}", "{rt2}", "{rt3}", "{rt4}" }
local RT2 = { "{rt5}", "{rt6}", "{rt7}", "{rt8}" }
K.CHARSETS = {
	lower = { title = "abc", { "a", "b", "c", "d" }, { "e", "f", "g", "h" }, { "i", "j", "k", "l" }, { "m", "n", "o", "p" }, { "q", "r", "s", "t" }, { "u", "v", "w", "x" }, { "y", "z", "-", '"' }, { "!", "?", ",", "." } },
	upper = { title = "ABC", { "A", "B", "C", "D" }, { "E", "F", "G", "H" }, { "I", "J", "K", "L" }, { "M", "N", "O", "P" }, { "Q", "R", "S", "T" }, { "U", "V", "W", "X" }, { "Y", "Z", "_", "'" }, { "!", "?", ";", ":" } },
	numbers = { title = "123", { "1", "2", "3", "4" }, { "5", "6", "7", "8" }, { "9", "0", "<", ">" }, { "@", "&", "$", "%" }, { "/", "(", "\\", ")" }, { "+", "*", "=", "~" }, RT, RT2 },
	symbols = { title = "#+=", { "/s", "/p", "/i", "/g" }, { "/y", "/w", "/e", "/r" }, { "/raid", "/rw", "%t", "/ready" }, { "^", "#", "€", "£" }, { "½", "[", "|", "]" }, { "§", "{", "¿", "}" }, RT, RT2 },
}
-- A face button's key in a set: FT top, FR right, FB bottom, FL left.
K.FACE_KEY = { FT = 1, FR = 2, FB = 3, FL = 4 }

-- L1 Shift, L2 Symbols, both: symbols; a numeric box starts on numbers.
function K.Charset(shift, symbols, numeric)
	if shift and symbols then return "symbols" end
	if shift then return "upper" end
	if symbols or numeric then return "numbers" end
	return "lower"
end

-- What a key puts in the box: a marker as is, "|" escaped, a command with its trailing space (the box turns it into
-- its chat-type header), /ready as /readycheck.
function K.InsertText(key)
	if key == "|" then return "||" end
	if key == "/ready" then return "/readycheck " end
	if #key > 1 and key:sub(1, 1) == "/" then return key .. " " end
	return key
end

function K.Marker(key) return tonumber(key:match("^{rt(%d)}$")) end

-- Slash commands in a chat box. The box parses a line that opens with "/" inside whatever call changed it once a
-- space follows the command, and on Enter (Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua ParseText :218). From
-- our call that runs as addon code. For a chat type's own command it only switches the box's channel (HandleChatType
-- :192, ProcessChatType :145: SetChatType, SetTellTarget, SetText, UpdateHeader; the whisper target lookup uses
-- C_AutoComplete, unrestricted), so those are allowed. GUILD_DISCORD's branch calls C_Discord.IsUserOAuthed (:180),
-- which the game restricts, and every other command (an emote, a secure or an addon's command) runs its handler on
-- Enter: those are refused.
local SWITCHES = { "SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING", "INSTANCE_CHAT", "GUILD", "OFFICER", "SMART_WHISPER", "WHISPER", "REPLY" }
local switches, shortest

local function aliasesOf(kind)
	local list, i = {}, 1
	while type(_G["SLASH_" .. kind .. i]) == "string" do
		list[#list + 1] = _G["SLASH_" .. kind .. i]:upper()
		i = i + 1
	end
	return list
end

-- The client's own aliases (/s, /say, /p, ...), read once from its SLASH_<TYPE><n> strings; a Discord alias is never
-- a switch, even if it shares a name.
local function aliases()
	if switches then return switches end
	switches, shortest = {}, {}
	for _, kind in ipairs(SWITCHES) do
		for _, alias in ipairs(aliasesOf(kind)) do
			switches[alias] = kind
			local best = shortest[kind]
			if not best or #alias < #best then shortest[kind] = alias end
		end
	end
	for _, alias in ipairs(aliasesOf("GUILD_DISCORD")) do switches[alias] = false end
	return switches
end

local function channels()
	local constants = Constants and Constants.ChatFrameConstants
	return constants and tonumber(constants.MaxChatChannels) or 20
end

-- The chat type a keyboard key switches to (/p PARTY, /raid RAID, ...), or nil when the key is not a channel switch
-- in this client (/ready, an alias the client doesn't have).
function K.SwitchKind(key)
	if #key < 2 or key:sub(1, 1) ~= "/" then return end
	return aliases()[key:upper()] or nil
end

-- A channel key picked in a chat box: its command goes at the start of the line, in place of a command already
-- there, so the box switches at once and keeps the message (ChatFrameEditBox.lua ProcessChatType: SetChatType, then
-- SetText of what follows). A whisper key needs a name first, so it takes an empty line only: false otherwise.
function K.PutSwitch(text, key)
	local rest = text:gsub("^%s+", "")
	if rest:sub(1, 1) == "/" then rest = rest:gsub("^%S*%s*", "") end
	local kind = K.SwitchKind(key)
	if (kind == "WHISPER" or kind == "SMART_WHISPER") and rest ~= "" then return false end
	return key .. " " .. rest
end

-- What a chat box would make of a line: "text" (no command), "typing" (a command with nothing after it yet: the box
-- parses nothing while typing), "switch" (a channel switch), or "refused". sending: the line is about to be sent, so
-- a bare command counts as complete.
function K.Slash(text, sending)
	if text:sub(1, 1) ~= "/" then return "text" end
	if not sending and not text:find("%s") then return "typing" end
	local command = text:match("^(/%S*)"):upper()
	local number = tonumber(command:match("^/(%d+)$"))
	if number then return number >= 1 and number <= channels() and "switch" or "refused" end
	return aliases()[command] and "switch" or "refused"
end

-- The command that switches a chat box to a channel ({ kind, target, id }), with its space; nil when there is none
-- (a Battle.net whisper has no name to type). A whisper uses the smart whisper's alias when the client has one.
function K.SwitchCommand(channel)
	local kind, target, id = channel.kind, channel.target, channel.id
	if kind == "CHANNEL" then return id and id >= 1 and id <= channels() and "/" .. id .. " " or nil end
	local known = aliases()
	local alias = kind == "WHISPER" and (shortest.SMART_WHISPER or shortest.WHISPER) or shortest[kind]
	if not (alias and known[alias]) or kind == "WHISPER" and not target then return end
	return alias:lower() .. " " .. (kind == "WHISPER" and target .. " " or "")
end

local function angle(x, y) return math.deg(math.atan2 and math.atan2(x, y) or math.atan(x, y)) % 360 end

-- Left stick: 8 sectors of 45° clockwise from north; nil at or below SET_ON.
function K.SetAt(x, y)
	if math.sqrt(x * x + y * y) <= K.SET_ON then return end
	return math.floor(((angle(x, y) + 22.5) % 360) / 45) + 1
end

-- Right stick: [top, right, bottom, left] sectors of 90°; nil at or below threshold (KEY_HOVER by default).
function K.KeyAt(x, y, threshold)
	if math.sqrt(x * x + y * y) <= (threshold or K.KEY_HOVER) then return end
	return math.floor(((angle(x, y) + 45) % 360) / 90) + 1
end

-- Editing on (text, cursor): cursor is the byte count before it (EditBox:SetCursorPosition). A {rtN} marker and an
-- escaped || move and erase as one unit; otherwise one UTF-8 character.
local function isCont(byte) return byte and byte >= 0x80 and byte < 0xC0 end

local function unitBefore(text, cur)
	local head = text:sub(1, cur)
	if head:match("{rt%d}$") then return 5 end
	if head:match("||$") then return 2 end
	local n = 1
	while cur - n > 0 and isCont(text:byte(cur - n + 1)) do n = n + 1 end
	return math.min(n, cur)
end

local function unitAfter(text, cur)
	local tail = text:sub(cur + 1)
	if tail:match("^{rt%d}") then return 5 end
	if tail:match("^||") then return 2 end
	local n = 1
	while isCont(text:byte(cur + n + 1)) do n = n + 1 end
	return math.min(n, #text - cur)
end

function K.Left(text, cur) return math.max(0, cur - unitBefore(text, cur)) end
function K.Right(text, cur) return math.min(#text, cur + unitAfter(text, cur)) end

function K.Erase(text, cur)
	if cur <= 0 then return text, 0 end
	local n = unitBefore(text, cur)
	return text:sub(1, cur - n) .. text:sub(cur + 1), cur - n
end

function K.Insert(text, cur, s) return text:sub(1, cur) .. s .. text:sub(cur + 1), cur + #s end

-- Characters (GetUTF8CursorPosition) to bytes.
function K.CharToByte(text, chars)
	local pos, seen = 0, 0
	while seen < chars and pos < #text do
		pos = pos + 1
		while isCont(text:byte(pos + 1)) do pos = pos + 1 end
		seen = seen + 1
	end
	return pos
end

-- The word touching the cursor: the run of [%a][%w']* around it. Returns word, first byte, last byte (or nil).
function K.WordAt(text, cur)
	local first, last = cur + 1, cur
	while first > 1 and text:sub(first - 1, first - 1):match("[%w']") do first = first - 1 end
	while last < #text and text:sub(last + 1, last + 1):match("[%w']") do last = last + 1 end
	while first <= last and not text:sub(first, first):match("%a") do first = first + 1 end
	if first > last then return end
	return text:sub(first, last), first, last
end

-- Word list: our own base words (weight 1) plus every sent line's words (+1 each), capped at K.CAP.
K.BASE = [[
a about after again all almost alone already also always am an and any anyone anything are area around as ask at
away back bad bag be because been before behind best better big bit boss both brb bring busy but buy by call came
can cant cast cave check chest city class clear close come coming cool could craft damage dead deal did die died
do does doing done dont door down drop dungeon each east easy else end enough even ever every everyone fast fight
find fine first fish follow food for found free friend from full fun gear get give glad go going gold gone good got
great group guild had half hand has have he heal healer heals health hello help her here hey hi him his hold home
hope how hunter i if im in inn instance invite is it item its join just keep kill know last later leave left let
level like line little look loot lost lot mage mail make man many map mate maybe me mean mine minute moment more
most mount move much must my need never new next nice night no none north not now of off ok okay old on once one
only open or other our out over party pet play player please port pull put quest quick raid ready really rest
right rogue run safe said same say see sell send she ship should side since so some someone something soon sorry
south spell stay still stop stuff summon sure take talk tank thank thanks that the their them then there these they
thing think this those through time tired to today together too town trade try turn two under until up us use very
wait walk want warrior was water way we well went west what when where which while who why will wipe with without
wont work world would yes yet you your
]]

local function lowerWords(line, fn) for word in line:gmatch("%a[%w']*") do if #word >= 2 then fn(word:lower()) end end end

function K.Seed(dict) lowerWords(K.BASE, function(word) dict[word] = dict[word] or 1 end) end

function K.Learn(dict, line)
	lowerWords(line or "", function(word) dict[word] = (dict[word] or 0) + 1 end)
	K.Cap(dict, K.CAP)
end

local function byWeight(dict)
	local list = {}
	for word, weight in pairs(dict) do list[#list + 1] = { word, weight } end
	table.sort(list, function(a, b) return a[2] < b[2] or a[2] == b[2] and a[1] > b[1] end)
	return list
end

-- Lowest weights go first; ties drop the alphabetically last word.
function K.Cap(dict, cap)
	local count = 0
	for _ in pairs(dict) do count = count + 1 end
	if count <= cap then return end
	local list = byWeight(dict)
	for i = 1, count - cap do dict[list[i][1]] = nil end
end

-- At logout: weights become ranks 1..n in their order, so one burst of a word can't swamp the list.
function K.Normalize(dict) for rank, pair in ipairs(byWeight(dict)) do dict[pair[1]] = rank end end

-- Edit distance with a swapped pair as one edit (optimal string alignment), stopping once past limit.
local function distance(a, b, limit)
	local la, lb = #a, #b
	if math.abs(la - lb) > limit then return limit + 1 end
	local before, prev = nil, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		local row, best = { [0] = i }, i
		local ca = a:byte(i)
		for j = 1, lb do
			local cb = b:byte(j)
			local cost = ca == cb and 0 or 1
			row[j] = math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
			if before and i > 1 and j > 1 and ca == b:byte(j - 1) and a:byte(i - 1) == cb then row[j] = math.min(row[j], before[j - 2] + 1) end
			if row[j] < best then best = row[j] end
		end
		if best > limit then return limit + 1 end
		before, prev = prev, row
	end
	return prev[lb]
end
K.Distance = distance

-- Ranking: score = edit distance - substring bonus (1) - prefix bonus (2) - weight (0..1 of the heaviest word); the
-- lowest wins. Up to 8 kept. tick() (optional) is called every 64 words so a caller can yield in a coroutine. The case
-- follows the typed word: a capitalised word gets capitalised suggestions.
function K.Rank(dict, typed, tick)
	local word, results, heaviest, n = typed:lower(), {}, 1, 0
	for _, weight in pairs(dict) do if weight > heaviest then heaviest = weight end end
	for cand, weight in pairs(dict) do
		n = n + 1
		if tick and n % 64 == 0 then tick() end
		local prefix = cand:sub(1, #word) == word
		local dist = distance(word, cand, 3)
		if dist <= 3 or prefix then
			local sub = cand:find(word, 1, true) ~= nil
			local score = dist - (sub and 1 or 0) - (prefix and 2 or 0) - weight / heaviest
			results[#results + 1] = { word = cand, dist = dist, score = score, weight = weight }
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then return a.score < b.score end
		return a.word < b.word
	end)
	for i = #results, 9, -1 do results[i] = nil end
	if typed:match("^%u") then for _, r in ipairs(results) do r.word = r.word:sub(1, 1):upper() .. r.word:sub(2) end end
	return results
end

-- The result to pre-focus as "Correction": the typed word isn't known and the best result is 2 edits or fewer away.
function K.Correction(dict, typed, results)
	local best = results[1]
	if dict[typed:lower()] or not best or best.dist > 2 or best.word:lower() == typed:lower() then return end
	return 1
end

-- Quick phrases: situations most specific first, with their defaults. Tokens: {quest} {target} {zone} {dungeon}.
K.SITUATIONS = { "combat", "whisper", "dungeon", "raid", "quest", "group", "city", "anywhere" }
K.PHRASES = {
	combat = { "Help!", "Heal please", "Run!" },
	whisper = { "Sure, invite me", "Sorry, busy right now", "Give me a minute", "Thanks!" },
	dungeon = { "Ready to pull?", "Need mana, one moment", "Wait, I'm out of range", "Good run, thanks all!", "Can someone summon me to {dungeon}?" },
	raid = { "Ready", "Need a res please", "AFK 2 min", "Invite to raid please" },
	quest = { "Can anyone help with {quest}?", "Group up for {quest}?", "Are you doing {quest}?", "Where do I go for {quest}?" },
	group = { "Wait for me", "Follow me", "Where are you?", "Need a break, 2 min", "Ready" },
	city = { "Looking for a group for {quest}", "Anyone going to {dungeon}?", "Selling, whisper me" },
	anywhere = { "Can you help me?", "Invite me please", "Thanks!", "On my way", "One moment please", "Sorry, typing on a controller" },
}

-- ctx: { combat, whisper, instance = "party" | "raid" | ..., raid, group, resting, quest = the super-tracked quest's
-- link (nil when the player follows none), zone, dungeon }.
function K.Situations(ctx)
	local inInstance = ctx.instance and ctx.instance ~= "none"
	local on = {
		combat = ctx.combat, whisper = ctx.whisper, dungeon = ctx.instance == "party", raid = ctx.instance == "raid" or ctx.raid,
		quest = ctx.quest ~= nil, group = ctx.group and not ctx.raid, city = ctx.resting and not inInstance, anywhere = true,
	}
	local list = {}
	for _, id in ipairs(K.SITUATIONS) do if on[id] then list[#list + 1] = id end end
	return list
end

-- A phrase with its tokens filled, or nil when one can't be.
function K.Fill(phrase, ctx)
	local values, missing = { quest = ctx.quest, target = "%t", zone = ctx.zone, dungeon = ctx.dungeon }, false
	local text = phrase:gsub("{(%a+)}", function(token)
		local value = values[token]
		if value == nil or value == "" then missing = true end
		return value
	end)
	if not missing then return text end
end

-- Every true situation's phrases (saved lists over the defaults), joined, filled, deduplicated: { text, situation }.
-- At most QUEST_MAX lines name the quest and PHRASE_MAX in all, so the list stays short and mostly situational.
K.QUEST_MAX, K.PHRASE_MAX = 2, 8

function K.Phrases(ctx, saved)
	local list, seen, quests = {}, {}, 0
	for _, id in ipairs(K.Situations(ctx)) do
		for _, phrase in ipairs(saved and saved[id] or K.PHRASES[id]) do
			local text = #list < K.PHRASE_MAX and K.Fill(phrase, ctx)
			local quest = phrase:find("{quest}", 1, true) ~= nil
			if quest and quests >= K.QUEST_MAX then text = nil end
			if text and not seen[text] then
				if quest then quests = quests + 1 end
				seen[text] = true
				list[#list + 1] = { text = text, situation = id }
			end
		end
	end
	return list
end

-- Placement (UIParent units, origin bottom-left). The block is 674 x 408 at k: the disc (centre 187,221 from its
-- top-left, radius 187), the tab beside it (to 674, or mirrored to the left) and the modifier row over it. Rects are
-- { left, bottom, right, top }. box: the edit box; chat: the whole chat frame (log, tab, box); avoid: the player
-- frame, the crossbar, the touch bars. pin: { position = "auto" | "centre" | "custom", x, y }.
-- Auto walks the disc's centre from the box's centre E toward the screen centre C and stops at the first point where
-- the disc, tab and modifier row clear the chat frame by GAP (clamped to the screen); the tab goes on the side the
-- line heads to (away from the chat), else the other. Past C it keeps going if it still covers the chat; a point that
-- clears the chat but covers the crossbar or unit frame slides on, and is kept only when nothing better comes by C.
-- Nothing clears: the lower centre above the crossbar. Returns left, bottom, scale, where ("line" | "centre"),
-- mirror (tab on the left), and the disc centre x, y.
K.BLOCK_W, K.BLOCK_H, K.DISC_X, K.DISC_Y, K.DISC_R = 674, 408, 187, 221, 187
local GAP, EDGE, STEP, TAB_IN, TAB_HALF, ROW_HALF, ROW_TOP = 12, 8, 4, 129, 120, 140, 34

local function overlaps(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end
K.Overlaps = overlaps

-- Does a circle (x, y, r) reach into the rect?
local function circleHits(x, y, r, rect)
	local nx, ny = math.max(rect[1], math.min(x, rect[3])), math.max(rect[2], math.min(y, rect[4]))
	return (x - nx) ^ 2 + (y - ny) ^ 2 < r * r
end
K.CircleHits = circleHits

function K.Place(box, chat, avoid, width, height, k, pin, noTab)
	avoid, chat = avoid or {}, chat or box
	local scale = k
	if K.BLOCK_H * scale > height - 2 * EDGE then scale = (height - 2 * EDGE) / K.BLOCK_H end
	local w, h, r = K.BLOCK_W * scale, K.BLOCK_H * scale, K.DISC_R * scale
	local function toLeft(m) return (m and K.BLOCK_W - K.DISC_X or K.DISC_X) * scale end
	local below = (K.BLOCK_H - K.DISC_Y) * scale
	local function clampD(x, y, m)
		local l = math.max(EDGE, math.min(width - EDGE - w, x - toLeft(m)))
		local b = math.max(EDGE, math.min(height - EDGE - h, y - below))
		return l + toLeft(m), b + below
	end
	-- The tab and the modifier row as rects (the disc is tested as a circle).
	local function parts(x, y, m)
		local list = { { x - ROW_HALF * scale, y + r - 10 * scale, x + ROW_HALF * scale, y + (K.DISC_Y) * scale } }
		if not noTab then
			local near, far = TAB_IN * scale, (K.BLOCK_W - K.DISC_X) * scale
			list[2] = m and { x - far, y - TAB_HALF * scale, x - near, y + TAB_HALF * scale } or { x + near, y - TAB_HALF * scale, x + far, y + TAB_HALF * scale }
		end
		return list
	end
	local function hits(x, y, m, rect, gap)
		local grown = { rect[1] - gap, rect[2] - gap, rect[3] + gap, rect[4] + gap }
		if circleHits(x, y, r, grown) then return true end
		for _, part in ipairs(parts(x, y, m)) do if overlaps(part, grown) then return true end end
	end
	local function result(x, y, m, where) return x - toLeft(m), y - below, scale, where, m, x, y end
	local function centre()
		local l, b = (width - w) / 2, EDGE
		for _, rr in ipairs(avoid) do if rr[2] < height / 2 and rr[1] < l + w and l < rr[3] then b = math.max(b, rr[4] + 16) end end
		b = math.max(EDGE, math.min(height - EDGE - h, b))
		return l + K.DISC_X * scale, b + below
	end

	pin = pin or {}
	if pin.position == "centre" or pin.position == "custom" then
		local x, y = centre()
		if pin.position == "custom" then x, y = clampD(x + (pin.x or 0), y + (pin.y or 0), false) end
		return result(x, y, false, "centre")
	end

	local ex, ey = (box[1] + box[3]) / 2, (box[2] + box[4]) / 2
	local dx, dy = width / 2 - ex, height / 2 - ey
	local toCentre = math.sqrt(dx * dx + dy * dy)
	if toCentre < 1 then dx, dy, toCentre = 0, 1, 0 else dx, dy = dx / toCentre, dy / toCentre end
	local prefer = dx < 0
	-- fallback: the first point clear of the chat (it may cover the crossbar or unit frame); slid from before the
	-- centre, the slide stops at the centre; from past it, at the screen edge.
	local fallback, last
	for t = 0, width + height, STEP do
		local moved = false
		for _, m in ipairs({ prefer, not prefer }) do
			local x, y = clampD(ex + dx * t, ey + dy * t, m)
			if m == prefer then
				moved = not last or math.abs(x - last[1]) + math.abs(y - last[2]) > 0.01
				last = { x, y }
			end
			if not hits(x, y, m, chat, GAP) and not hits(x, y, m, box, GAP) then
				local covered = false
				for _, rr in ipairs(avoid) do if hits(x, y, m, rr, 0) then covered = true end end
				if not covered then return result(x, y, m, "line") end
				if not fallback then fallback = { x, y, m, t } end
				if fallback[4] < toCentre and t >= toCentre then return result(x, y, m, "line") end
			end
		end
		if fallback and not moved then break end
	end
	if fallback then return result(fallback[1], fallback[2], fallback[3], "line") end
	local x, y = centre()
	return result(x, y, false, "centre")
end

-- The leader: a cubic from the rim point facing the box end to that end, as 24 points. disc = { x, y, r }.
function K.Leader(disc, ex, ey)
	local a = math.atan2 and math.atan2(ey - disc[2], ex - disc[1]) or math.atan(ey - disc[2], ex - disc[1])
	local sx, sy = disc[1] + disc[3] * math.cos(a), disc[2] + disc[3] * math.sin(a)
	local my = (sy + ey) / 2
	local points = {}
	for i = 0, 23 do
		local t = i / 23
		local u = 1 - t
		local b0, b1, b2, b3 = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
		points[i + 1] = { b0 * sx + b1 * sx + b2 * ex + b3 * ex, b0 * sy + b1 * my + b2 * (my + 10) + b3 * ey }
	end
	return points
end

-- Settings and their defaults (ForeverControllerTweaksDB.keyboard).
K.BUTTONS = {
	space = "PAD1", send = "PAD2", erase = "PAD3", close = "PAD4", shift = "PADLSHOULDER", symbols = "PADLTRIGGER",
	insert = "PADRSHOULDER", prev = "PADDUP", next = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT",
}
K.DEFAULTS = { enabled = true, open = "controller", layout = "ring", scale = 1, suggestions = true, position = "auto", x = 0, y = 0 }

-- The saved table with every default filled in (button by button, so an old save gains new actions).
function K.Settings(saved)
	saved = type(saved) == "table" and saved or {}
	for key, value in pairs(K.DEFAULTS) do if saved[key] == nil then saved[key] = value end end
	saved.buttons = type(saved.buttons) == "table" and saved.buttons or {}
	for action, key in pairs(K.BUTTONS) do if not saved.buttons[action] then saved.buttons[action] = key end end
	saved.dictionary = type(saved.dictionary) == "table" and saved.dictionary or {}
	if not next(saved.dictionary) then K.Seed(saved.dictionary) end
	return saved
end

-- The action a button runs (buttons: action -> key).
function K.ActionOf(buttons, key)
	for action, bound in pairs(buttons) do if bound == key then return action end end
end

-- Rebinding swaps: the action that had the key takes the old one.
function K.Bind(buttons, action, key)
	local other, old = K.ActionOf(buttons, key), buttons[action]
	buttons[action] = key
	if other and other ~= action then buttons[other] = old end
end
