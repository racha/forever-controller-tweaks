-- Plain-Lua checks for the keyboard: lua tests/keyboard_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ns = {}
ForeverControllerTweaks = ns
-- A module file as the game loads it: its own addon name and private table; it reads the core's namespace global.
local function loadModule(file) assert(loadfile(here .. "/../../ForeverControllerTweaks_Keyboard/" .. file .. ".lua"))("ForeverControllerTweaks_Keyboard", {}) end
loadModule("Engine")
local K = ns.Keyboard

-- Sectors: the left stick picks one of 8 sets clockwise from north past 0.5; the right stick one of 4 keys past 0.15.
local d = math.sqrt(0.5)
assert(K.SetAt(0, 0.4) == nil and K.SetAt(0, 0.5) == nil, "at or below 0.5 no set")
assert(K.SetAt(0, 1) == 1 and K.SetAt(d, d) == 2 and K.SetAt(1, 0) == 3 and K.SetAt(d, -d) == 4)
assert(K.SetAt(0, -1) == 5 and K.SetAt(-d, -d) == 6 and K.SetAt(-1, 0) == 7 and K.SetAt(-d, d) == 8)
assert(K.SetAt(0.38, 0.92) == 1 and K.SetAt(0.39, 0.92) == 2, "the N/NE border is 22.5°")
assert(K.KeyAt(0, 0.15) == nil and K.KeyAt(0, 0.2) == 1 and K.KeyAt(0.2, 0) == 2 and K.KeyAt(0, -0.2) == 3 and K.KeyAt(-0.2, 0) == 4)
assert(K.KeyAt(0.3, 0.3) == 2 and K.KeyAt(-0.3, 0.31) == 1, "45° borders")
assert(K.KeyAt(0, 0.4, K.KEY_TYPE) == nil and K.KeyAt(0, 0.6, K.KEY_TYPE) == 1, "typing needs past 0.5")

-- Charsets: L1 upper, L2 numbers, both symbols; numeric boxes start on numbers. Exact characters per the spec.
assert(K.Charset() == "lower" and K.Charset(true) == "upper" and K.Charset(false, true) == "numbers" and K.Charset(true, true) == "symbols")
assert(K.Charset(false, false, true) == "numbers")
local function flat(name)
	local out = {}
	for i = 1, 8 do out[i] = table.concat(K.CHARSETS[name][i], " ") end
	return table.concat(out, " | ")
end
assert(flat("lower") == 'a b c d | e f g h | i j k l | m n o p | q r s t | u v w x | y z - " | ! ? , .', flat("lower"))
assert(flat("upper") == "A B C D | E F G H | I J K L | M N O P | Q R S T | U V W X | Y Z _ ' | ! ? ; :", flat("upper"))
assert(flat("numbers") == "1 2 3 4 | 5 6 7 8 | 9 0 < > | @ & $ % | / ( \\ ) | + * = ~ | {rt1} {rt2} {rt3} {rt4} | {rt5} {rt6} {rt7} {rt8}", flat("numbers"))
assert(flat("symbols") == "/s /p /i /g | /y /w /e /r | /raid /rw %t /ready | ^ # € £ | ½ [ | ] | § { ¿ } | {rt1} {rt2} {rt3} {rt4} | {rt5} {rt6} {rt7} {rt8}", flat("symbols"))
assert(K.CHARSETS.lower.title == "abc" and K.CHARSETS.upper.title == "ABC" and K.CHARSETS.numbers.title == "123" and K.CHARSETS.symbols.title == "#+=")
assert(K.InsertText("|") == "||" and K.InsertText("/p") == "/p " and K.InsertText("/ready") == "/readycheck " and K.InsertText("/") == "/")
assert(K.InsertText("%t") == "%t" and K.InsertText("{rt3}") == "{rt3}" and K.Marker("{rt3}") == 3 and not K.Marker("a"))
assert(K.FACE_KEY.FT == 1 and K.FACE_KEY.FR == 2 and K.FACE_KEY.FB == 3 and K.FACE_KEY.FL == 4)

-- Editing: UTF-8 safe, markers and || as one unit.
local text, cur = K.Insert("", 0, "h")
text, cur = K.Insert(text, cur, "é")
text, cur = K.Insert(text, cur, "{rt1}")
text, cur = K.Insert(text, cur, "||")
assert(text == "hé{rt1}||" and cur == #text)
text, cur = K.Erase(text, cur)
assert(text == "hé{rt1}" and cur == #text, "|| erases as one")
text, cur = K.Erase(text, cur)
assert(text == "hé" and cur == 3, "a marker erases as one")
text, cur = K.Erase(text, cur)
assert(text == "h" and cur == 1, "é erases as one character (2 bytes)")
text, cur = K.Erase(K.Erase("", 0))
assert(text == "" and cur == 0, "erase at the start does nothing")
text = "a€{rt2}b"
assert(K.Left(text, #text) == #text - 1 and K.Left(text, #text - 1) == 4 and K.Left(text, 4) == 1 and K.Left(text, 1) == 0 and K.Left(text, 0) == 0)
assert(K.Right(text, 0) == 1 and K.Right(text, 1) == 4 and K.Right(text, 4) == 9 and K.Right(text, 9) == 10 and K.Right(text, 10) == 10)
text, cur = K.Erase("a€b", 4)
assert(text == "ab" and cur == 1, "erase mid-text at the cursor")
assert(K.CharToByte("a€b", 2) == 4 and K.CharToByte("a€b", 0) == 0 and K.CharToByte("a€b", 9) == 5)

-- The word under the cursor.
assert(K.WordAt("need a heal", 11) == "heal" and select(2, K.WordAt("need a heal", 11)) == 8)
assert(K.WordAt("don't go", 3) == "don't" and K.WordAt("hi ", 3) == nil and K.WordAt("", 0) == nil)
assert(K.WordAt("x 12ab", 6) == "ab", "a word starts with a letter")

-- Suggestions: ranking, case, autocorrect, cap, normalise.
local dict = {}
K.Seed(dict)
assert(dict.heal == 1 and dict.the == 1 and not dict.a, "seeded from our own base list, 2+ letters")
K.Learn(dict, "Healer healer heals")
local r = K.Rank(dict, "heal")
assert(r[1].word == "heal" and r[2].word == "heals" and r[3].word == "healer", "exact first, then by edits and weight: " .. r[1].word .. " " .. r[2].word)
assert(#r <= 8)
r = K.Rank(dict, "Heal")
assert(r[1].word == "Heal" and r[3].word == "Healer", "case follows the typed word")
r = K.Rank(dict, "wya")
assert(r[1].word == "way" and K.Correction(dict, "wya", r) == 1, "wya: way, pre-focused as a correction")
assert(not K.Correction(dict, "heal", K.Rank(dict, "heal")), "a known word is no correction")
local ticks = 0
K.Rank(dict, "he", function() ticks = ticks + 1 end)
assert(ticks > 0, "the ranking calls tick so it can yield")
local small = { aa = 5, bb = 1, cc = 3, dd = 1 }
K.Cap(small, 2)
assert(small.aa and small.cc and not small.bb and not small.dd, "the cap drops the lowest weights")
local norm = { x = 10, y = 3, z = 99 }
K.Normalize(norm)
assert(norm.y == 1 and norm.x == 2 and norm.z == 3, "normalised to ranks")
local big = {}
for i = 1, K.CAP + 5 do big["w" .. i] = i end
K.Learn(big, "hello")
local count = 0
for _ in pairs(big) do count = count + 1 end
assert(count == K.CAP and big["w" .. (K.CAP + 5)], "learning keeps the cap: " .. count)

-- Quick phrases: situations most specific first, tokens filled, unfillable skipped, duplicates removed.
local ctx = { instance = "party", group = true, dungeon = "The Deadmines", zone = "Westfall" }
local list = K.Phrases(ctx)
assert(list[1].text == "Ready to pull?" and list[1].situation == "dungeon")
local texts = {}
for _, p in ipairs(list) do texts[p.text] = (texts[p.text] or 0) + 1 end
assert(texts["Can someone summon me to The Deadmines?"] == 1 and not texts["Are you doing {quest}?"])
local thanks = 0
for _, p in ipairs(K.Phrases({ whisper = true })) do if p.text == "Thanks!" then thanks = thanks + 1 end end
assert(thanks == 1, "Thanks! (whisper and anywhere) appears once")
for _, p in ipairs(list) do assert(not p.text:find("{quest}", 1, true), "a quest phrase with no quest is skipped") end
list = K.Phrases({ combat = true, whisper = true, quest = "|cffffff00[Q]|r" })
assert(list[1].situation == "combat" and list[4].situation == "whisper")
local q = false
for _, p in ipairs(list) do if p.text == "Can anyone help with |cffffff00[Q]|r?" then q = true end end
assert(q, "{quest} becomes the link")
assert(K.Fill("Target {target}", {}) == "Target %t" and K.Fill("{zone}", {}) == nil)
list = K.Phrases({}, { anywhere = { "Mine" } })
assert(#list == 1 and list[1].text == "Mine", "saved phrases replace the defaults")
-- Quest lines: at most 2, the most useful first; the list stays short.
list = K.Phrases({ quest = "[Q]", resting = true, group = true })
local questLines = {}
for _, p in ipairs(list) do if p.text:find("[Q]", 1, true) then questLines[#questLines + 1] = p.text end end
assert(#questLines == 2 and questLines[1] == "Can anyone help with [Q]?" and questLines[2] == "Group up for [Q]?", table.concat(questLines, " / "))
assert(#list <= K.PHRASE_MAX and list[3].situation == "group", "then situational lines, " .. #list .. " in all")
list = K.Phrases({ resting = true })
for _, p in ipairs(list) do assert(not p.text:find("{quest}", 1, true) and p.situation ~= "quest", "no quest followed: no quest lines") end
local s = K.Situations({ instance = "raid", group = true, raid = true, resting = true })
assert(table.concat(s, ",") == "raid,anywhere", table.concat(s, ","))

-- Placement: from the edit box toward the screen centre. The disc's centre lies on the E->C line, the first point
-- where disc, tab and modifier row clear the chat frame (12 gap); the tab on the side the line heads to; clamped;
-- over the crossbar or unit frame it slides on; no room: the lower centre. Pins: centre, custom offsets.
local W, H = 1365.33, 768
local crossbar, player = { 380, 0, 985, 110 }, { 1100, 650, 1350, 750 }
local avoid = { crossbar, player }
local function check(name, box, chat, wantDir, opts)
	opts = opts or {}
	local l, b, sc, where, mir, x, y = K.Place(box, chat, opts.avoid or avoid, W, H, opts.k or 1, opts.pin)
	assert(l >= 8 - 1e-9 and b >= 8 - 1e-9 and l + K.BLOCK_W * sc <= W - 8 + 1e-9 and b + K.BLOCK_H * sc <= H - 8 + 1e-9, name .. ": on screen")
	local r = K.DISC_R * sc
	assert(not K.CircleHits(x, y, r + 11, chat), name .. ": the disc clears the chat frame")
	local tab = mir and { l, y - 120 * sc, l + 358 * sc, y + 120 * sc } or { l + 316 * sc, y - 120 * sc, l + K.BLOCK_W * sc, y + 120 * sc }
	assert(not K.Overlaps(tab, chat), name .. ": the tab clears the chat frame")
	local ex, ey = (box[1] + box[3]) / 2, (box[2] + box[4]) / 2
	local cx, cy = W / 2 - ex, H / 2 - ey
	if opts.onLine ~= false then
		local len = math.sqrt(cx * cx + cy * cy)
		local off = math.abs((x - ex) * cy - (y - ey) * cx) / len
		assert(off < 1, name .. ": on the E->C line, off by " .. off)
		assert((x - ex) * cx + (y - ey) * cy > 0, name .. ": toward the centre")
	end
	if wantDir then
		assert((x > ex) == (wantDir[1] > 0) or wantDir[1] == 0, name .. ": horizontal direction")
		assert((y > ey) == (wantDir[2] > 0), name .. ": vertical direction")
		if wantDir[1] == 0 then assert(math.abs(x - ex) < 8, name .. ": straight up") end
	end
	for _, rr in ipairs(opts.clearOf or {}) do assert(not K.CircleHits(x, y, r, rr), name .. ": the disc clears the crossbar / unit frame") end
	return l, b, sc, where, mir, x, y
end
-- Corners: box at the chat's foot, the chat 410 x 230 above it.
local function chatAt(left, bottom) return { left, bottom, left + 410, bottom + 32 }, { left, bottom, left + 410, bottom + 230 } end
local box, chat = chatAt(17, 130)
local _, _, _, where, mir = check("bottom-left", box, chat, { 1, 1 }, { clearOf = { crossbar } })
assert(where == "line" and not mir, "bottom-left: tab on the right, away from the chat")
box, chat = chatAt(17, 530)
check("top-left (the user's)", box, chat, { 1, -1 })
box, chat = chatAt(938, 130)
_, _, _, _, mir = check("bottom-right", box, chat, { -1, 1 })
assert(mir, "bottom-right: tab on the left, away from the chat")
box, chat = chatAt(938, 470)
check("top-right", box, chat, { -1, -1 })
box, chat = { 480, 120, 880, 152 }, { 480, 120, 880, 330 }
check("bottom-centre", box, chat, { 0, 1 })
box, chat = { 17, 120, 560, 152 }, { 17, 120, 560, 640 }
_, _, _, where = check("a large chat frame", box, chat, { 1, 1 })
assert(where == "line", "a large chat frame: still on the line, past the centre")
-- The crossbar in the way: it slides on along the line.
box, chat = { 480, 112, 880, 144 }, { 480, 112, 880, 200 }
local unit = { 300, 210, 1060, 290 }
local _, _, _, _, _, _, slid = check("past a frame in the way", box, chat, { 0, 1 }, { avoid = { crossbar, unit }, clearOf = { unit } })
local _, _, _, _, _, _, first = K.Place(box, chat, { crossbar }, W, H, 1)
assert(slid > first, "it slid further along the line")
-- No room anywhere: the lower centre, above the crossbar.
local l, b, sc, where2 = K.Place({ 8, 300, W - 8, 332 }, { 8, 8, W - 8, H - 8 }, avoid, W, H, 1)
assert(where2 == "centre" and math.abs(l + K.BLOCK_W / 2 - W / 2) < 1e-6 and b == crossbar[4] + 16, "no room: lower centre above the crossbar")
-- Pins.
box, chat = chatAt(17, 530)
local cl, cb = K.Place(box, chat, avoid, W, H, 1, { position = "centre" })
assert(cb == crossbar[4] + 16 and math.abs(cl + K.BLOCK_W / 2 - W / 2) < 1e-6, "pinned to the centre")
local ml, mb = K.Place(box, chat, avoid, W, H, 1, { position = "custom", x = 40, y = -20 })
assert(ml == cl + 40 and mb == cb - 20, "custom offsets move the pin")
ml, mb = K.Place(box, chat, avoid, W, H, 1, { position = "custom", x = 5000, y = 5000 })
assert(ml + K.BLOCK_W <= W - 8 + 1e-9 and mb + K.BLOCK_H <= H - 8 + 1e-9, "offsets are clamped to the screen")
local _, _, s1 = K.Place(box, chat, avoid, W, H, 1.5)
local _, _, s2 = K.Place(box, chat, avoid, W, H, 2)
assert(s1 == 1.5 and math.abs(s2 - (H - 16) / K.BLOCK_H) < 1e-9, "scale kept when it fits, else fit to the height")
local p = K.Leader({ 0, 0, 10 }, -50, -50)
assert(#p == 24 and math.abs(p[1][1] + 7.0710678) < 1e-6 and math.abs(p[1][2] + 7.0710678) < 1e-6 and p[24][1] == -50 and p[24][2] == -50, "the leader leaves the rim facing the box")

-- Settings: defaults fill in; rebinding swaps.
local saved = K.Settings({ buttons = { send = "PAD1" } })
assert(saved.enabled and saved.open == "controller" and saved.scale == 1 and saved.suggestions and saved.layout == "ring")
assert(saved.buttons.close == "PAD4" and next(saved.dictionary))
local b = K.Settings().buttons
K.Bind(b, "send", "PAD1")
assert(b.send == "PAD1" and b.space == "PAD2" and K.ActionOf(b, "PAD1") == "send")

print("keyboard_spec: engine ok")

-- View: a small frame stub. Every widget method is a no-op unless listed; input-setting calls are recorded.
local now, combat, focus, inputCalls, sounds = 100, false, nil, {}, 0
local Obj = {}
Obj.__index = function(_, name) return rawget(Obj, name) or (name:match("^%u") and function() end or nil) end
local function new(kind, parent) return setmetatable({ kind = kind, parent = parent, shown = true, scripts = {} }, Obj) end
function Obj:Show() if not self.shown then self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end end
function Obj:Hide() if self.shown then self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end end
function Obj:SetShown(on) if on then self:Show() else self:Hide() end end
function Obj:IsShown() return self.shown end
function Obj:IsVisible() return self.shown end
function Obj:SetScript(name, fn) self.scripts[name] = fn end
function Obj:GetScript(name) return self.scripts[name] end
function Obj:CreateTexture() return new("Texture", self) end
function Obj:CreateFontString() return new("FontString", self) end
function Obj:CreateLine() return new("Line", self) end
function Obj:SetText(t) self.text = t end
function Obj:GetText() return self.text end
function Obj:GetStringWidth() return 8 * #(self.text or "") end
function Obj:GetWidth() return 1365 end
function Obj:GetHeight() return 768 end
function Obj:GetEffectiveScale() return 1 end
function Obj:SetAlpha(a) self.alpha = a end
function Obj:GetAlpha() return self.alpha or 1 end
for _, name in ipairs({ "EnableGamePadButton", "EnableGamePadStick", "SetPropagateKeyboardInput", "EnableKeyboard" }) do
	Obj[name] = function(self, on) inputCalls[#inputCalls + 1] = { self, name, on, combat } end
end
unpack = unpack or table.unpack
UIParent = new("Frame")
function CreateFrame(kind, _, parent) return new(kind, parent) end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetCurrentKeyBoardFocus() return focus end
function PlaySound() sounds = sounds + 1 end
function debugprofilestop() return now * 1000 end
function IsSecureCmd(cmd) return cmd:lower() == "/cast" or cmd:lower() == "/target" end
function UnitAffectingCombat() return combat end
function IsInInstance() return false, "none" end
function GetZoneText() return "Westfall" end
SOUNDKIT = { GAMEPAD_RADIAL_MENU_OPEN = 1, GAMEPAD_RADIAL_MENU_CLOSE = 2, GAMEPAD_RADIAL_MENU_HIGHLIGHT = 3 }
local escapes, enters = 0, 0
function ExecuteFrameScript(edit, script)
	if script == "OnEnterPressed" then enters = enters + 1 edit.text, focus = "", nil end
	if script == "OnEscapePressed" then escapes = escapes + 1 focus = nil end
end

-- A chat-like EditBox: text, a byte cursor, Insert at it, the UTF-8 cursor read the client way.
local function newBox()
	local edit = new("EditBox")
	edit.text, edit.cursor = "", 0
	function edit:IsObjectType(t) return t == "EditBox" end
	function edit:GetText() return self.text end
	function edit:SetText(t) self.text, self.cursor = t, #t end
	function edit:SetCursorPosition(c) self.cursor = c end
	function edit:Insert(t) self.text, self.cursor = self.text:sub(1, self.cursor) .. t .. self.text:sub(self.cursor + 1), self.cursor + #t end
	function edit:GetUTF8CursorPosition() local n = 0 for _ in self.text:sub(1, self.cursor):gmatch("[^\128-\191]") do n = n + 1 end return n end
	function edit:GetRect() return 17, 60, 410, 32 end
	return edit
end

local handlers = {}
ns.On = function(event, fn) handlers[event] = handlers[event] or {} table.insert(handlers[event], fn) end
local function fire(event) for _, fn in ipairs(handlers[event] or {}) do fn() end end
ns.Active = function() return true end
ns.db = { keyboard = { open = "always" } }
ns.UI = { ART = "", L = {}, CODE = { PAD1 = "FB", PAD2 = "FR", PAD3 = "FL", PAD4 = "FT" }, Glyph = function(parent) return new("Frame", parent) end }
for _, file in ipairs({ "Phrases", "Context", "Suggest", "View" }) do loadModule(file) end
local V = K.View

-- Loaded in combat (a /reload): nothing is created until combat ends.
combat = true
fire("PLAYER_LOGIN")
assert(not V.Frame() and #inputCalls == 0, "in combat the keyboard waits")
combat = false
fire("PLAYER_REGEN_ENABLED")
local frame = V.Frame()
assert(frame and not frame:IsShown(), "built after combat, hidden")
local mine = {}
for _, c in ipairs(inputCalls) do if c[1] == frame then mine[c[2]] = c[3] end assert(not c[4], "no input call in combat") end
assert(mine.EnableGamePadButton == true and mine.EnableGamePadStick == true and mine.SetPropagateKeyboardInput == false, "the pad is taken only by the shown frame")
local created = #inputCalls

-- Focus opens it; typing goes through the box's own methods.
local edit = newBox()
focus = edit
V.Observe()
assert(frame:IsShown() and V.Box() == edit and sounds == 1, "a valid focus opens the keyboard")
V.Press("PAD1")
assert(edit.text == " ", "Space")
V.Stick("Left", 0, 1)
assert(V.State().set == 1, "the left stick picks set 1")
V.Press("PAD4")
assert(edit.text == " a", "FT types the top key: " .. edit.text)
V.Stick("Right", 0.6, 0)
assert(edit.text == " ab" and V.State().key == 2, "a right flick types once")
V.Stick("Right", 0.7, 0)
assert(edit.text == " ab", "and not again until it re-arms")
V.Stick("Right", 0.2, 0)
V.Stick("Right", 0.6, 0)
assert(edit.text == " abb", "re-armed")
V.Stick("Left", 0, 0)
V.Press("PADLSHOULDER")
assert(V.State().charset == "upper", "L1 held: upper")
V.Press("PADLTRIGGER")
assert(V.State().charset == "symbols", "L1 + L2: symbols")
V.Release("PADLSHOULDER")
assert(V.State().charset == "numbers", "L2 alone: numbers")
V.Stick("Left", -1, 0)
V.Press("PAD4")
assert(edit.text == " abb{rt1}", "set 7 of numbers: a marker")
V.Release("PADLTRIGGER")
V.Stick("Left", 0, 0)
V.Press("PAD3")
assert(edit.text == " abb", "Erase takes the marker as one")
V.Release("PAD3")
V.Press("PADDLEFT")
V.Release("PADDLEFT")
assert(edit.cursor == 3, "cursor left")
V.Press("PADDRIGHT")
V.Release("PADDRIGHT")
assert(edit.cursor == 4, "cursor right")

-- Send: a secure command stays; other text goes through the box's own Enter and teaches its words.
edit.text, edit.cursor = "/cast Fireball", 14
V.Press("PAD2")
assert(enters == 0 and edit.text == "/cast Fireball", "a secure command is not sent")
edit.text, edit.cursor = "zorbly greetings", 16
V.Press("PAD2")
assert(enters == 1 and ns.db.keyboard.dictionary.zorbly == 1, "sent through OnEnterPressed; its words learned")
V.Observe()
assert(not frame:IsShown() and V.Box() == nil, "chat clears focus after Enter: the keyboard closes")

-- Combat: opening, typing and closing change no input settings.
combat = true
focus = edit
V.Observe()
assert(frame:IsShown(), "opens in combat")
V.Press("PAD1")
V.Press("PAD4")
assert(escapes == 1 and not frame:IsShown(), "Close runs OnEscapePressed and hides")
assert(#inputCalls == created, "no input-setting call after creation")
combat = false

-- With the controller: no open after a mouse or key input; a valid box that loses validity closes it.
ns.db.keyboard.open = "controller"
focus = newBox()
V.Observe()
assert(not frame:IsShown(), "controller mode needs a pad press first")
ns.db.keyboard.open = "always"
V.Observe()
assert(frame:IsShown())
function focus:IsPassword() return true end
V.Observe()
assert(not frame:IsShown(), "a password box closes it")
ns.Active = function() return false end
function focus:IsPassword() return false end
V.Observe()
assert(not frame:IsShown(), "never with the Gamepad UI off")

-- Quest phrases come from the super-tracked quest only.
ns.Active = function() return true end
local tracked
C_SuperTrack = { GetSuperTrackedQuestID = function() return tracked end }
C_QuestLog = { GetQuestIDForQuestWatchIndex = function() return 77 end }
function GetQuestLink(id) return "[Quest " .. id .. "]" end
function IsInGroup() return false end
function IsInRaid() return false end
function IsResting() return false end
focus = newBox()
function focus:GetAttribute(key) return key == "chatType" and "SAY" or nil end
V.Observe()
assert(frame:IsShown())
local function questRows()
	local n = 0
	for _, p in ipairs(V.State().suggestions) do if p.text:find("[Quest", 1, true) then n = n + 1 end end
	return n
end
V.Tick()
assert(questRows() == 0, "a watched but not super-tracked quest gives no quest phrases")
tracked = 42
fire("SUPER_TRACKING_CHANGED")
V.Tick()
assert(questRows() == 2, "the super-tracked quest gives two lines: " .. questRows())
print("keyboard_spec: view ok")
