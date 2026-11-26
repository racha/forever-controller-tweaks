-- Forever Controller Tweaks action rings (design/rings.md): radial menus of catalog actions, per character, opened from
-- any routed face or D-pad cell (Face.lua) or touch button (Touch.lua) that holds the entry "ring:<id>".
--
-- Storage: ns.db.chars[char].rings = { nextId, list = { { id, name, icon, count, stick, show, style, middle, slots = { [i] = { id, name,
-- icon, kind } } } } } (1.5.1 kept one list for the account in ns.db.rings: Core.MoveRings hands it out at load).
-- Per character, the slot each ring fired last: ns.db.chars[char].ringLast[ring id] = { i, slot id } (healer rings by
-- their "h<entry id>"); kept only while that slot still holds that action.
-- ns.db.ringAxisSaved: the player's GamePadStickAxisButtons value while a held ring has it switched on by a saved write
-- (a client that refuses the temp value), until put back. It and ns.db.ringMarker stay account-wide.
-- stick: which stick aims a held ring, "right", "left" or "dynamic" (opened from a D-pad cell: right; from a face
-- button cell: left, the hand that isn't on the button; from a stick press: the other stick). Touch rings are tapped.
-- show: how a held ring stays up. "toggle": a press opens it and it stays until a slot is used, the button is pressed
-- again or B; "hold": up only while the button is held, its release uses the slot aimed at or just closes.
-- style: "full" (the game-menu radial wheel) or "compact" (the radial flyout, the aura and stance picker).
-- middle: what letting go in the middle of a held ring does (and A with nothing aimed). "cancel": nothing; "last":
-- the slot this character used last fires, and the ring's buttons show its icon (Rings.LiveIcon).
-- A slot keeps the catalog id, so a spell group resolves to each character's own highest rank. icon nil: the first
-- filled slot's icon.
--
-- Secure engine: one protected frame (ForeverControllerTweaksRing) holds, out of combat, every ring's slot actions as
-- attributes (r<id>n count, r<id>t<i> type, r<id>k<i> attribute, r<id>v<i> value) and the slot directions per count
-- (dx<n>-<i>, dy<n>-<i>). Its snippets run in its own environment, called with RunAttribute from the router or the
-- touch button that owns the press. RunAttribute scrubs its arguments to nil, booleans, numbers and strings (a frame
-- handle arrives as nil), so a button is passed by the name of the ring frame's frame ref to it: "slot<i>" for its
-- slots, the router's own name for each Face router (Face.lua sets those refs).
--   _open(id, mode, kind, own, at, layer) lays out and arms the slot buttons, picks the aiming stick (kind: the
--                         opening cell, "face" or "dpad", for a dynamic ring) and shows the ring ("hold" or "touch").
--                         A held ring binds its keys (below) but own, the key that opened it; that key pressed again
--                         closes it. at: the name of the ring frame's ref to the button a Compact ring opens on, and
--                         layer its crossbar layer (a mouse click on a crossbar cell, Face.lua's catcher);
--   _pick(key)            the slot the aiming stick points at (the largest dot product with a slot direction), nil
--                         inside the dead zone, where a stick key's own direction stands in; nil on the slot the
--                         stick pointed at as the ring opened, until it re-centres or moves off it;
--   _release(ref)         on the held button's release: aimed (or with a pick the stick keys kept), closes the ring
--                         and arms that button's typerelease with the slot's action; nothing aimed, a Hold ring
--                         closes and a Toggle ring stays open;
--   _key(key, down)       a key the open held ring bound, through the key button: the aiming stick's directions keep
--                         the pick, and the release that leaves none down (the stick back in the middle) closes the
--                         ring and fires it, as the native radial menu does; A fires the slot aimed at (or the kept
--                         pick), nothing aimed keeps it open; B and the stick's press close;
--   _held()               how many of the aiming stick's direction keys are down, and their names;
--   _last(id)             the slot a middle release fires with middle "last": the last one used, if it still fires
--                         (a healer place only while its unit can be helped); nil otherwise;
--   _hover()              the slot the mouse is on (ps-hover, below), as _pick answers: false on a healer place whose
--                         unit can't be helped;
--   _used(i)              a tapped slot of the open ring becomes its last (r<id>l, as every fire sets it);
--   _toggle(id, at, kind, layer) a touch tap or a mouse click: opens the ring as "touch" (at, kind, layer as _open),
--                         or closes it when it is the one open;
--   _close()              hides it; _arm(ref, which, id, i) writes one slot's action on a button.
-- No action slot is used: the actions fire through direct secure attributes (spell, item, toy, macrotext).
-- Healer mode (design/healer-mode.md): a binding with healer = true opens a healer ring, id "h<entry id>", made from the
-- binding (Rings.HealerRing), not stored: always Hold, Dynamic stick, Compact, 7 slots that all fire the
-- binding's spell or item, slot i on unit HEALER_UNITS[i] (r<id>u<i>). _arm sets the button's unit (and drops the
-- self/focus/mouseover cast checks there); _pick skips a slot whose unit is missing or can't be helped (dead allies
-- can), returning false so a kept pick is dropped too; a tapped slot does the same check.
-- The mouse, as on the game's radial flyout: in every mode a slot under the pointer lights (View.lua) and a left click
-- fires it through its own secure click; any other button closes the ring. A held ring also takes the hovered slot as
-- its aim: the button's release and A fire it when the stick aims at nothing (the stick wins). The slots' OnEnter and
-- OnLeave are wrapped by the ring frame, so in combat too their snippets keep ps-hover (the slot's index) on the ring
-- for _release and _key to read; nothing insecure decides what fires. The wrap runs them only for a pointer that moved
-- (the motion argument), so a hidden cursor resting where a ring opens never aims.
-- Stick keys: the game sends a stick's directions as keys (PADRSTICKUP...) only while the CVar GamePadStickAxisButtons
-- is on, so a held ring switches it on while it is open (below). Without the keys it fires on the button's release or A.
-- That CVar covers both sticks, but the other stick's keys are left unbound: an unbound stick key doesn't stop the
-- analog stick, so that stick keeps walking or moving the camera as the game's own (Stick pass and block, below).
local ns = ForeverControllerTweaks
local Rings = {}
ns.Rings = Rings

local MAX_RINGS, MIN_SLOTS, MAX_SLOTS, DEFAULT_SLOTS, NAME_MAX = 12, 4, 8, 8, 24
Rings.MAX_RINGS, Rings.MIN_SLOTS, Rings.MAX_SLOTS, Rings.NAME_MAX = MAX_RINGS, MIN_SLOTS, MAX_SLOTS, NAME_MAX
local STICKS = { right = true, left = true, dynamic = true }
Rings.STICKS = { "right", "left", "dynamic" }
local SHOWS = { toggle = true, hold = true }
Rings.SHOWS = { "toggle", "hold" }
local STYLES = { full = true, compact = true }
Rings.STYLES = { "full", "compact" }
local MIDDLES = { cancel = true, last = true }
Rings.MIDDLES = { "cancel", "last" }
-- After a held ring closes its aiming stick is still pushed: kept from the game until it is back within RECENTRE of
-- the middle, at most HOLD_MAX seconds outside a cast, so a reading that never settles can't block movement or the
-- camera.
local RECENTRE, HOLD_MAX = 0.2, 1
-- The native radial menu's selection threshold is 0.5; a ring cancels a little closer to the centre, so a thumb
-- easing off as the button lets go still counts.
local DEADZONE = 0.4
-- A stick key's release decides by where the stick is, not by the keys still marked down (a release can be lost):
-- under LET_GO from the middle the stick is let go, whatever the keys say; with every key released, a stick still at
-- RIM or out is rolling round the edge and fires nothing. LET_GO sits above the native 0.5 the keys release around.
local LET_GO, RIM = 0.6, 0.9
-- What an open held ring binds, per aiming stick, under every modifier prefix (a trigger may emulate one): its four
-- directions (with their unit vectors), its press (close), A (use) and B (close).
local MODS = { "", "ALT-", "CTRL-", "SHIFT-", "ALT-CTRL-", "ALT-SHIFT-", "CTRL-SHIFT-", "ALT-CTRL-SHIFT-" }
local DIRS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local KEYS = { left = { "PAD1", "PAD2", "PADLSTICK" }, right = { "PAD1", "PAD2", "PADRSTICK" } }
local ROLE = { PAD1 = "use", PAD2 = "close", PADLSTICK = "close", PADRSTICK = "close" }
for side, list in pairs(KEYS) do
	for way in pairs(DIRS) do list[#list + 1] = "PAD" .. side:sub(1, 1):upper() .. "STICK" .. way end
	table.sort(list)
end
Rings.KEYS, Rings.MODS = KEYS, MODS
-- The native radial's geometry (design/rings.md 10.1, UI units at scale 1): wheel radius, slot icon centre radius,
-- icon size, highlight centre radius, a slot button's square (the icon and 12 round it). Compact: the radial flyout's
-- offsetRadius (FlyoutRadial.lua CIRCLE_STYLE_PROPERTIES) and a button square round its 36 icon that stays clear of
-- the neighbour at 8 slots (42.4 apart across at 45 degrees); the flyout's size (GamepadFlyoutTemplate), the frame's
-- in Compact so the clamp keeps it on its button.
Rings.GEO = { WHEEL = 270, SLOT_R = 130, ICON = 38, HL_R = 150, HIT = 62, COMPACT_R = 60, COMPACT_HIT = 42, FLY = 200 }

-- The native wheel art is cut for 8 slots: segments SEG apart, dividers 2 * GAP wide between them, so a segment's
-- middle PIECE degrees is clear of them; the highlight's gold edges are SEG apart. Other counts are composed from
-- pieces of that art (View.lua draws them), in degrees clockwise from the top; a piece is { turn, centre, width }:
-- the art turned by turn and kept to the sector width wide about centre (no width: all of it).
local SEG, GAP, PIECE, OVERLAP = 45, 7, 30, 0.2
Rings.ART = { SEG = SEG, GAP = GAP, PIECE = PIECE, OVERLAP = OVERLAP }

-- The wheel: per wedge equal fill pieces at most PIECE wide with a segment's middle on each, per divider the art's own
-- divider (SEG / 2 clockwise from the top) on it, all touching, none overlapping.
function Rings.WheelPieces(n)
	if n == 8 then return { { 0 } } end
	local out, step = {}, 360 / n
	local span = step - 2 * GAP
	local count = math.ceil(span / PIECE - 1e-9)
	for i = 1, n do
		local theta = (i - 1) * step
		for j = 1, count do
			local centre = theta - span / 2 + (j - 0.5) * span / count
			out[#out + 1] = { centre, centre, span / count }
		end
		local divider = theta + step / 2
		out[#out + 1] = { divider - SEG / 2, divider, 2 * GAP, divider = true }
	end
	return out
end

-- The highlight (or disabled) art on slot i of n: { at, centre, width }, the art placed and turned as for a slot at
-- `at`. At 8 one piece; below, an outer piece at each side keeping its gold
-- edge up to SEG / 2 + 7.5 in, middle pieces between, OVERLAP into each neighbour.
function Rings.SegmentPieces(n, i)
	local theta, half = (i - 1) * 360 / n, 180 / n
	if n == 8 then return { { theta } } end
	local edge = math.min(PIECE, half)
	local keep = edge + OVERLAP
	local out = { { theta - half + SEG / 2, theta - half + keep / 2, keep }, { theta + half - SEG / 2, theta + half - keep / 2, keep } }
	local gap = 2 * (half - edge)
	local count = math.ceil(gap / PIECE - 1e-9)
	for j = 1, count do
		local centre = theta - gap / 2 + (j - 0.5) * gap / count
		out[#out + 1] = { centre, centre, gap / count + 2 * OVERLAP }
	end
	return out
end

-- The sector mask for a piece width: Art/ring-sector-<centidegrees>.tga.
function Rings.SectorFile(width) return ("ring-sector-%d.tga"):format(math.floor(width * 100 + 0.5)) end
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local COMBAT = "Controller Tweaks changes rings out of combat only."
local NONE = {}
-- Fixed places, clockwise from the top: muscle memory. In a raid party1-4 are the player's own subgroup.
local HEALER_UNITS = { "player", "party1", "party2", "party3", "party4", "target", "focus" }
Rings.HealerUnits = HEALER_UNITS
local HEALER_KINDS = { spell = true, spellgroup = true, item = true }
local KIND_WORD = { mount = "mount", toy = "toy", macro = "macro", set = "equipment set", game = "game action", face = "face action", hold = "hold action", ring = "ring", pet = "pet spell", addon = "key binding" }

local function ringOf(id) return tonumber(tostring(id):match("^ring:(%d+)$")) end

-- The unit direction of slot i of n, clockwise from the top (y up, as the stick reports it).
local function dir(n, i)
	local a = (i - 1) * 2 * math.pi / n
	return math.sin(a), math.cos(a)
end
Rings.Dir = dir

-- The slot (1..count) the stick at (x, y) points at, nil inside the dead zone. The snippet picks the same way.
function Rings.SlotAt(x, y, count)
	if not (x and y and count) or x * x + y * y < DEADZONE * DEADZONE then return nil end
	local best, bestDot
	for i = 1, count do
		local dx, dy = dir(count, i)
		local dot = x * dx + y * dy
		if not bestDot or dot > bestDot then best, bestDot = i, dot end
	end
	return best
end

---------------------------------------------------------------------------------------------------------------------
-- Storage

-- This character's rings; nil before the character is known. create: made on first write.
local function store(create)
	local char = ns.db and ns.Face and ns.Face.CharDB()
	if not char then return end
	if create and type(char.rings) ~= "table" then char.rings = { nextId = 1, list = {} } end
	return type(char.rings) == "table" and char.rings or nil
end

function Rings.List()
	local rings = store()
	return rings and rings.list or NONE
end

function Rings.Get(id)
	for _, ring in ipairs(Rings.List()) do
		if ring.id == id then return ring end
	end
end

-- The ring's own icon, else its first filled slot's, else the question mark.
function Rings.Icon(ring)
	if ring.icon then return ring.icon end
	for i = 1, ring.count do
		local slot = ring.slots[i]
		if slot and slot.icon then return slot.icon end
	end
	return QUESTION
end

-- This character's last pick per ring id, made on first write; nil before the character is known.
local function lastPicks(create)
	local char = ns.db and ns.Face and ns.Face.CharDB()
	if not char then return end
	if create and type(char.ringLast) ~= "table" then char.ringLast = {} end
	return type(char.ringLast) == "table" and char.ringLast or nil
end

-- The slot a ring fired last on this character, while that slot still holds the same action; else nil, and true when
-- a stored pick no longer fits (the slot was edited or emptied, or the count shrank).
local function lastIndex(ring)
	local picks = lastPicks()
	local pick = picks and picks[ring.id]
	if not pick then return end
	local i, slotId = pick[1], pick[2]
	local slot = i <= ring.count and ring.slots[i]
	if slot and slot.id == slotId then return i end
	return nil, true
end
Rings.LastIndex = lastIndex

-- The icon a ring's buttons show: with middle "last" and a last pick, that slot's (what a middle release fires);
-- otherwise Rings.Icon.
function Rings.LiveIcon(id)
	local ring = Rings.Get(id)
	if not ring then return QUESTION end
	local i = ring.middle == "last" and lastIndex(ring)
	local slot = i and ring.slots[i]
	return slot and slot.icon or Rings.Icon(ring)
end

-- The catalog entries of the Rings category (Actions.lua): "Open ring: <name>".
function Rings.Entries()
	local out = {}
	for _, ring in ipairs(Rings.List()) do
		out[#out + 1] = { id = "ring:" .. ring.id, category = "Rings", name = "Open ring: " .. ring.name, icon = Rings.Icon(ring), kind = "ring", payload = ring.id }
	end
	return out
end

-- Every stored binding of one character that holds a ring: routed cells cells[profile][code][layer] (a paged cell's
-- [page] under it, ns.Cells) and touch buttons touchBars[profile][side][i][layer] (touch.bars before 1.5.2).
-- fn(holder, key, ringId) may set holder[key] (nil drops it); an emptied page list, row or button goes too.
local function eachBinding(char, fn)
	local function walk(parent, rows)
		for rowKey, row in pairs(rows) do
			if type(row) == "table" then
				for key, entry in pairs(row) do
					local id = type(entry) == "table" and ringOf(entry.id)
					if id then fn(row, key, id) end
				end
				if not next(row) then parent[rowKey] = nil end
			end
		end
	end
	if type(char) ~= "table" then return end
	local function walkBars(bars)
		for _, list in pairs(type(bars) == "table" and bars or NONE) do
			if type(list) == "table" then walk(list, list) end
		end
	end
	for _, byCode in pairs(type(char.cells) == "table" and char.cells or NONE) do
		if type(byCode) == "table" then
			for _, row in pairs(byCode) do
				local lists = {}
				for layer, value in pairs(type(row) == "table" and row or NONE) do
					if type(value) == "table" and not ns.Cells.IsEntry(value) then lists[layer] = value end
				end
				walk(row, lists)
			end
			walk(byCode, byCode)
		end
	end
	for _, bars in pairs(type(char.touchBars) == "table" and char.touchBars or NONE) do walkBars(bars) end
	walkBars(type(char.touch) == "table" and char.touch.bars)
end
Rings.EachBinding = eachBinding

-- Bindings keep a copy of the ring's name and icon for the panels and glyphs; they follow every change. This
-- character's only: another one's ring:<id> is its own ring.
local function syncBindings()
	eachBinding(ns.Face.CharDB(), function(row, key, id)
		local ring = Rings.Get(id)
		if not ring then row[key] = nil return end
		local entry = row[key]
		entry.name, entry.icon, entry.kind = "Open ring: " .. ring.name, Rings.Icon(ring), "ring"
	end)
end

local apply

-- Every edit: bindings follow, the secure attributes are written, the catalog and the panels redraw.
local function changed()
	syncBindings()
	apply()
	ns.Fire("FCT_RINGS_CHANGED")
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
	return true
end

local function editable(id)
	if InCombatLockdown() then return nil, COMBAT end
	if not ns.db then return nil, "not loaded yet" end
	if id == nil then return true end
	local ring = Rings.Get(id)
	if not ring then return nil, "unknown ring " .. tostring(id) end
	return ring
end

local function cleanName(name)
	name = tostring(name or ""):gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return name:sub(1, NAME_MAX)
end

-- A new empty ring named "Ring <n>" (the first free n). Returns the ring, or nil and a reason.
function Rings.New()
	local ok, err = editable()
	if not ok then return nil, err end
	local rings = store(true)
	if not rings then return nil, "no character yet" end
	if #rings.list >= MAX_RINGS then return nil, ("You have %d rings, the most there can be. Delete one first."):format(MAX_RINGS) end

	local taken = {}
	for _, ring in ipairs(rings.list) do taken[ring.name] = true end
	local n = 1
	while taken["Ring " .. n] do n = n + 1 end
	local ring = { id = rings.nextId, name = "Ring " .. n, count = DEFAULT_SLOTS, stick = "right", show = "toggle", style = "full", middle = "cancel", slots = {} }
	rings.nextId = rings.nextId + 1
	rings.list[#rings.list + 1] = ring
	changed()
	return ring
end

function Rings.Rename(id, name)
	local ring, err = editable(id)
	if not ring then return nil, err end
	name = cleanName(name)
	if name == "" then return nil, "A ring needs a name." end

	ring.name = name
	return changed()
end

-- icon: a texture path or file id, or nil for the first slot's icon.
function Rings.SetIcon(id, icon)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then return nil, "not an icon: " .. tostring(icon) end

	ring.icon = icon
	return changed()
end

-- Slots beyond a smaller count are kept, unused, until the count grows again.
function Rings.SetCount(id, count)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if type(count) ~= "number" or count % 1 ~= 0 or count < MIN_SLOTS or count > MAX_SLOTS then return nil, ("A ring has %d to %d slots."):format(MIN_SLOTS, MAX_SLOTS) end

	ring.count = count
	return changed()
end

-- stick: "right", "left" or "dynamic".
function Rings.SetStick(id, stick)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if not STICKS[stick] then return nil, "unknown stick " .. tostring(stick) end

	ring.stick = stick
	return changed()
end

-- show: "toggle" or "hold".
function Rings.SetShow(id, show)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if not SHOWS[show] then return nil, "unknown show " .. tostring(show) end

	ring.show = show
	return changed()
end

-- style: "full" or "compact".
function Rings.SetStyle(id, style)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if not STYLES[style] then return nil, "unknown style " .. tostring(style) end

	ring.style = style
	return changed()
end

-- middle: "cancel" or "last".
function Rings.SetMiddle(id, middle)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if not MIDDLES[middle] then return nil, "unknown middle " .. tostring(middle) end

	ring.middle = middle
	return changed()
end

function Rings.SlotEntry(id, i)
	local ring = Rings.Get(id)
	return ring and ring.slots[i]
end

-- entry: a catalog entry, or nil to empty the slot.
function Rings.SetSlot(id, i, entry)
	local ring, err = editable(id)
	if not ring then return nil, err end
	if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > ring.count then return nil, "unknown slot " .. tostring(i) end
	if entry and entry.disabled then return nil, entry.note end
	local kind = entry and ns.Actions.KindOf(entry)
	if kind == "ring" then return nil, "A ring can't open another ring." end

	ring.slots[i] = entry and { id = entry.id, name = entry.name, icon = entry.icon, kind = kind } or nil
	return changed()
end

-- Deletes this character's ring and every binding of its that opens it.
function Rings.Delete(id)
	local ring, err = editable(id)
	if not ring then return nil, err end

	local list = store().list
	for i = #list, 1, -1 do
		if list[i] == ring then table.remove(list, i) end
	end
	local char = ns.Face.CharDB()
	if type(char.ringLast) == "table" then char.ringLast[id] = nil end
	return changed()
end

-- How many of this character's bindings open this ring (the delete confirmation says so).
function Rings.BindingCount(id)
	local n = 0
	eachBinding(ns.Face.CharDB(), function(_, _, ringId) if ringId == id then n = n + 1 end end)
	return n
end

local function validIcon(icon) return type(icon) == "string" or type(icon) == "number" end

local function repairSlots(ring, path, fix)
	if type(ring.slots) ~= "table" then
		ring.slots = {}
		return fix(path .. ".slots")
	end
	for i, slot in pairs(ring.slots) do
		local good = type(i) == "number" and i % 1 == 0 and i >= 1 and i <= MAX_SLOTS and type(slot) == "table" and type(slot.id) == "string" and not ringOf(slot.id)
		if not good then
			ring.slots[i] = nil
			fix(path .. ".slots." .. tostring(i))
		else
			if type(slot.name) ~= "string" then slot.name = slot.id end
			if not validIcon(slot.icon) then slot.icon = nil end
			slot.kind = slot.id:match("^(%a+):")
		end
	end
end

-- One ring list ({ nextId, list }) into the shape above: bad rings and slots are dropped, missing fields get their
-- defaults, ids stay unique, at most MAX_RINGS. Returns the set of ring ids kept.
local function repairList(rings, base, fix)
	if type(rings.list) ~= "table" then
		if rings.list ~= nil then fix(base .. ".list") end
		rings.list = {}
	end
	-- In list order, so the first of two rings with one id is the one kept.
	local kept, seen, top = {}, {}, 0
	for key, ring in pairs(rings.list) do
		local id = type(ring) == "table" and ring.id
		if type(key) ~= "number" or type(id) ~= "number" or id < 1 or id % 1 ~= 0 then fix(base .. ".list." .. tostring(key)) else kept[#kept + 1] = { key, ring } end
	end
	table.sort(kept, function(a, b) return a[1] < b[1] end)
	local list = {}
	for _, pair in ipairs(kept) do
		local ring, path = pair[2], base .. "." .. pair[2].id
		if #list >= MAX_RINGS or seen[ring.id] then
			fix(path)
		else
			local name = type(ring.name) == "string" and cleanName(ring.name) or ""
			if name ~= ring.name or name == "" then
				ring.name = name ~= "" and name or "Ring " .. ring.id
				fix(path .. ".name")
			end
			if ring.icon ~= nil and not validIcon(ring.icon) then
				ring.icon = nil
				fix(path .. ".icon")
			end
			local count = ring.count
			if type(count) ~= "number" or count % 1 ~= 0 or count < MIN_SLOTS or count > MAX_SLOTS then
				ring.count = DEFAULT_SLOTS
				fix(path .. ".count")
			end
			-- Rings made before the setting have none: right, as they aimed.
			if ring.stick ~= nil and not STICKS[ring.stick] then fix(path .. ".stick") end
			if not STICKS[ring.stick] then ring.stick = "right" end
			-- Rings made before the setting have none: toggle, as they worked.
			if ring.show ~= nil and not SHOWS[ring.show] then fix(path .. ".show") end
			if not SHOWS[ring.show] then ring.show = "toggle" end
			-- Rings made before the setting have none: full, as they looked.
			if ring.style ~= nil and not STYLES[ring.style] then fix(path .. ".style") end
			if not STYLES[ring.style] then ring.style = "full" end
			-- Rings made before the setting have none: cancel, as they worked.
			if ring.middle ~= nil and not MIDDLES[ring.middle] then fix(path .. ".middle") end
			if not MIDDLES[ring.middle] then ring.middle = "cancel" end
			repairSlots(ring, path, fix)
			seen[ring.id] = true
			list[#list + 1] = ring
			top = math.max(top, ring.id)
		end
	end
	rings.list = list
	if type(rings.nextId) ~= "number" or rings.nextId % 1 ~= 0 or rings.nextId <= top then
		if rings.nextId ~= nil then fix(base .. ".nextId") end
		rings.nextId = top + 1
	end
	return seen
end

-- Repairs every character's rings, and 1.5.1's account list if it is still there (Core.MoveRings had no record to
-- give it to): a record without rings of its own is checked against that list. Bindings to rings the character
-- doesn't have are dropped. fix(path) per repair.
function Rings.Repair(db, fix)
	if db.rings ~= nil and type(db.rings) ~= "table" then
		db.rings = nil
		fix("rings")
	end
	local legacy = type(db.rings) == "table" and repairList(db.rings, "rings", fix) or nil
	if db.ringAxisSaved ~= nil and type(db.ringAxisSaved) ~= "string" then
		db.ringAxisSaved = nil
		fix("ringAxisSaved")
	end
	-- The ring marker setting: true, false or nil (on).
	if db.ringMarker ~= nil and type(db.ringMarker) ~= "boolean" then
		db.ringMarker = nil
		fix("ringMarker")
	end
	for name, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		if type(char) == "table" then
			local path = "chars." .. tostring(name)
			if char.rings ~= nil and type(char.rings) ~= "table" then
				char.rings = nil
				fix(path .. ".rings")
			end
			local seen = char.rings and repairList(char.rings, path .. ".rings", fix) or legacy or NONE
			eachBinding(char, function(row, key, id)
				if seen[id] then return end
				row[key] = nil
				fix(path .. ": binding to deleted ring " .. id)
			end)
			-- Last target (healerLast) is true on a binding in Healer mode, or not there.
			for _, byCode in pairs(type(char.cells) == "table" and char.cells or NONE) do
				ns.Cells.EachCell(byCode, function(code, layer, entry)
					if entry.healerLast ~= nil and not (entry.healerLast == true and entry.healer) then
						entry.healerLast = nil
						fix("healerLast " .. tostring(code) .. " " .. tostring(layer))
					end
				end)
			end
			-- A last pick: { slot index, slot id } of a ring that exists, or of a healer ring (its binding decides).
			local last = char.ringLast
			if last ~= nil and type(last) ~= "table" then
				char.ringLast = nil
				fix(path .. ".ringLast")
			end
			for id, pick in pairs(type(last) == "table" and last or NONE) do
				local good = type(pick) == "table" and type(pick[1]) == "number" and pick[1] % 1 == 0 and pick[1] >= 1 and pick[1] <= MAX_SLOTS and type(pick[2]) == "string"
				if not (good and (seen[id] or type(id) == "string" and id:find("^h"))) then
					last[id] = nil
					fix(path .. ".ringLast." .. tostring(id))
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Slot actions

-- How a catalog entry fires on a secure button: type, attribute, value; nil when it can't (unknown to this
-- character, a Lua key binding, a ring). Spell groups cast this character's highest rank; the player's macros,
-- equipment sets, pet spells, the random mount and game commands run their secure macro text.
function Rings.Attributes(entry)
	if not entry or entry.disabled then return end
	local Actions = ns.Actions
	local kind, payload = entry.kind, entry.payload
	if kind == "spell" then return "spell", "spell", payload end
	if kind == "spellgroup" then
		local top = entry.ranks and entry.ranks[2]
		if top then return "spell", "spell", top.payload end
		return
	end
	if kind == "item" then return "item", "item", "item:" .. payload end
	if kind == "toy" then return "toy", "toy", payload end
	if kind == "mount" and type(payload) == "table" then return "spell", "spell", payload.spellID end
	if kind == "game" then return "macro", "macrotext", payload.text end
	if kind == "face" then
		local button = ns.Face.ActionButton(payload)
		if button then return "macro", "macrotext", ns.Face.ClickBoth(button:GetName()) end
		return
	end
	if kind == "ring" then return end
	local text = Actions.TextFor(entry.id)
	if text then return "macro", "macrotext", text end
end

-- The catalog by id (a spell group's ranks included, the group itself first).
local function catalogIndex()
	local index = {}
	for _, category in ipairs(ns.Actions.Catalog()) do
		for _, entry in ipairs(category.entries) do
			index[entry.id] = index[entry.id] or entry
			for _, rank in ipairs(entry.ranks or NONE) do index[rank.id] = index[rank.id] or rank end
		end
	end
	return index
end

-- What a stored slot is for this character now: the catalog entry, or nil when it doesn't resolve.
function Rings.Resolve(slot)
	return slot and ns.Actions.Find(slot.id)
end

-- Whether a binding's entry can use Healer mode: only spells, spell groups and items cast on a unit. nil and why not.
function Rings.HealerAllowed(entry)
	if not entry then return nil, "This button is empty." end
	local kind = ns.Actions.KindOf(entry)
	if HEALER_KINDS[kind] then return true end
	local word = KIND_WORD[kind]
	return nil, word and ("This button holds a %s."):format(word) or "This button holds another kind of action."
end

---------------------------------------------------------------------------------------------------------------------
-- Secure frames

-- Clears every attribute a slot can use first, so a slot never fires what an earlier one left.
local ARM = [[
	local ref, which, id, i = ...
	local button = self:GetFrameRef(ref)
	if not button then return end
	local prefix = "r" .. id
	local actionType = self:GetAttribute(prefix .. "t" .. i)
	button:SetAttribute(which, actionType)
	button:SetAttribute("spell", nil)
	button:SetAttribute("item", nil)
	button:SetAttribute("toy", nil)
	button:SetAttribute("macrotext", nil)
	if actionType then button:SetAttribute(self:GetAttribute(prefix .. "k" .. i), self:GetAttribute(prefix .. "v" .. i)) end
	local unit = self:GetAttribute(prefix .. "u" .. i)
	button:SetAttribute("unit", unit)
	local cast = (actionType == "spell" or actionType == "item") and not unit or nil
	button:SetAttribute("checkselfcast", cast)
	button:SetAttribute("checkfocuscast", cast)
	button:SetAttribute("checkmouseovercast", cast)
]]

local OPEN = ([[
	local id, mode, kind, own, from, fromLayer = ...
	local n = id and self:GetAttribute("r" .. id .. "n")
	if not n then return end
	if mode == "hold" and self:IsShown() and self:GetAttribute("ps-ring") == id and self:GetAttribute("ps-mode") == "hold" then return self:RunAttribute("_close") end
	local stick = self:GetAttribute("r" .. id .. "s")
	if stick == "dynamic" then stick = (kind == "face" or kind == "rstick") and "left" or "right" end
	local side = stick == "left" and "left" or "right"
	self:SetAttribute("ps-aimside", side)
	self:SetAttribute("ps-aim", stick == "left" and self:GetAttribute("ps-lstick") or self:GetAttribute("ps-rstick"))
	self:SetAttribute("ps-pick", nil)
	self:SetAttribute("ps-hover", nil)
	for k = 1, self:GetAttribute("ps-keyn") do
		self:SetAttribute("ps-dn-" .. self:GetAttribute("ps-bindleft" .. k), nil)
		self:SetAttribute("ps-dn-" .. self:GetAttribute("ps-bindright" .. k), nil)
	end
	self:ClearBindings()
	for k = 1, mode == "hold" and %d or 0 do
		local key = self:GetAttribute("ps-bind" .. side .. k)
		for m = 1, key ~= own and %d or 0 do self:SetBindingClick(true, self:GetAttribute("ps-mod" .. m) .. key, "ForeverControllerTweaksRingKey", key) end
	end
	local compact = self:GetAttribute("r" .. id .. "y") == "compact"
	local r, hit = compact and %d or %d, compact and %d or %d
	-- The routed cell that opened a held ring: its router has the ring on the layer it is pressing (ps-curlayer and
	-- ps-curring, the ring of the page shown, set just before this call) and the key own; its native slot button on
	-- that layer is where Compact opens. A mouse click on a cell names its button (from) and layer instead.
	local at = from and self:GetFrameRef(from)
	local layer = at and fromLayer or nil
	for k = 1, mode == "hold" and self:GetAttribute("ps-routern") or 0 do
		local router = self:GetFrameRef(self:GetAttribute("ps-router" .. k))
		local pressed = router and router:GetAttribute("ps-curlayer")
		if pressed and router:GetAttribute("ps-curring") == id and (not own or router:GetAttribute("ps-key") == own) then
			layer, at = pressed, router:GetFrameRef("slot-" .. pressed) or router:GetFrameRef("bar-" .. pressed)
			break
		end
	end
	-- Compact centres on that button, read live (the bars move as they expand and with the UI scale); else, and Full,
	-- the screen centre. Clamped to the screen.
	local l, b, w, h
	if compact and at then l, b, w, h = at:GetRect() end
	self:ClearAllPoints()
	self:SetWidth(compact and %d or %d)
	self:SetHeight(compact and %d or %d)
	if l then
		local scale = at:GetEffectiveScale() / self:GetEffectiveScale()
		self:SetPoint("CENTER", "$screen", "BOTTOMLEFT", (l + w / 2) * scale, (b + h / 2) * scale)
	else
		self:SetPoint("CENTER")
	end
	self:SetAttribute("ps-layer", layer)
	self:SetAttribute("ps-kind", kind)
	self:SetAttribute("ps-at", l and true or nil)
	for i = 1, %d do
		local slot = self:GetFrameRef("slot" .. i)
		if i <= n then
			slot:ClearAllPoints()
			slot:SetWidth(hit)
			slot:SetHeight(hit)
			slot:SetPoint("CENTER", self, "CENTER", r * self:GetAttribute("dx" .. n .. "-" .. i), r * self:GetAttribute("dy" .. n .. "-" .. i))
			self:RunAttribute("_arm", "slot" .. i, "type", id, i)
			slot:Show()
		else
			slot:Hide()
		end
	end
	self:SetAttribute("ps-ring", id)
	self:SetAttribute("ps-mode", mode)
	self:SetAttribute("ps-stale", nil)
	if mode == "hold" then self:SetAttribute("ps-stale", (self:RunAttribute("_pick"))) end
	self:SetAttribute("ps-trace", format("open %%s %%s %%s%%s%%s", id, mode, side, self:GetAttribute("ps-stale") and " stale=" .. self:GetAttribute("ps-stale") or "", l and " at=" .. layer or ""))
	self:Show()
]]):format(#KEYS.right, #MODS, Rings.GEO.COMPACT_R, Rings.GEO.SLOT_R, Rings.GEO.COMPACT_HIT, Rings.GEO.HIT, Rings.GEO.FLY, 2 * Rings.GEO.WHEEL, Rings.GEO.FLY, 2 * Rings.GEO.WHEEL + 1, MAX_SLOTS)

-- Closed first, then the keys given back: a key event the unbinding sets off finds no ring.
local CLOSE = [[
	self:SetAttribute("ps-ring", nil)
	self:SetAttribute("ps-mode", nil)
	self:SetAttribute("ps-pick", nil)
	self:SetAttribute("ps-hover", nil)
	self:SetAttribute("ps-stale", nil)
	self:SetAttribute("ps-trace", "close")
	self:ClearBindings()
	self:Hide()
]]

-- A held ring opened with its stick already pushed (walking, turning the camera) must not fire where the stick was:
-- that slot (ps-stale, set by _open) is ignored until the stick is back in the dead zone or points at another slot.
local PICK = ([[
	local key = ...
	local id = self:GetAttribute("ps-ring")
	local n = id and self:GetAttribute("r" .. id .. "n")
	if not n then return end
	local state = GetGamePadState()
	local stick = state and state.sticks and state.sticks[self:GetAttribute("ps-aim") or 2]
	local x, y = stick and stick.x or 0, stick and stick.y or 0
	local len = x * x + y * y
	if len < %s then
		self:SetAttribute("ps-stale", nil)
		if not (key and self:GetAttribute("ps-kx-" .. key)) then return nil, len end
		x, y = self:GetAttribute("ps-kx-" .. key), self:GetAttribute("ps-ky-" .. key)
	end
	local best, bestDot
	for i = 1, n do
		local dot = x * self:GetAttribute("dx" .. n .. "-" .. i) + y * self:GetAttribute("dy" .. n .. "-" .. i)
		if not bestDot or dot > bestDot then best, bestDot = i, dot end
	end
	local stale = self:GetAttribute("ps-stale")
	if best == stale then return nil, len end
	if stale then self:SetAttribute("ps-stale", nil) end
	local unit = self:GetAttribute("r" .. id .. "u" .. best)
	if unit and not (UnitExists(unit) and PlayerCanAssist(unit)) then return false, len end
	return best, len
]]):format(DEADZONE * DEADZONE)

-- The aiming stick's direction keys down now (ps-dn-<key>, set and cleared by _key): how many and their names.
local HELD = [[
	local side, n, names = self:GetAttribute("ps-aimside"), 0, ""
	for k = 1, self:GetAttribute("ps-keyn") do
		local key = self:GetAttribute("ps-bind" .. side .. k)
		if self:GetAttribute("ps-dn-" .. key) then n, names = n + 1, names .. " " .. key end
	end
	return n, names
]]

-- The button's release fires the slot aimed at, else a pick the stick keys kept (the button and the stick let go
-- together, the release can read the stick already centred while its direction key is still down; that key's release
-- then finds the ring closed), else on a Hold ring the slot the mouse is on, and closes the ring. With nothing to fire
-- a Hold ring closes, a Toggle ring stays open (its release only opened it, the pointer may rest on a slot).
local RELEASE = [[
	local ref = ...
	local button = ref and self:GetFrameRef(ref)
	if not button then return end
	button:SetAttribute("typerelease", nil)
	local id = self:GetAttribute("ps-ring")
	if not id or self:GetAttribute("ps-mode") ~= "hold" then return self:SetAttribute("ps-trace", "release " .. ref .. ": no ring") end
	local now, len = self:RunAttribute("_pick")
	local pick = now
	if pick == nil then pick = self:GetAttribute("ps-pick") end
	local _, held = self:RunAttribute("_held")
	local show = self:GetAttribute("r" .. id .. "h")
	if pick == nil and show == "hold" then pick = self:RunAttribute("_hover") end
	self:SetAttribute("ps-trace", format("release %s len=%.2f now=%s kept=%s mouse=%s down=%s show=%s", ref, len or -1, tostring(now), tostring(self:GetAttribute("ps-pick")), tostring(self:GetAttribute("ps-hover")), held, tostring(show)))
	-- A Hold ring let go in the middle fires its last pick with middle "last"; a Toggle ring's release only opened it.
	if pick == nil and show == "hold" then pick = self:RunAttribute("_last", id) end
	if not pick and show ~= "hold" then return end
	self:RunAttribute("_close")
	if not pick then return end
	self:RunAttribute("_arm", ref, "typerelease", id, pick)
	if self:GetAttribute("r" .. id .. "t" .. pick) then self:SetAttribute("r" .. id .. "l", pick) end
	self:SetAttribute("ps-trace", "fire " .. ref .. " slot " .. pick)
]]

-- With middle "last": the last pick, while it still fires (a healer place only while its unit can be helped).
local LAST = [[
	local id = ...
	local i = self:GetAttribute("r" .. id .. "m") == "last" and self:GetAttribute("r" .. id .. "l")
	if not (i and self:GetAttribute("r" .. id .. "t" .. i)) then return nil end
	local unit = self:GetAttribute("r" .. id .. "u" .. i)
	if unit and not (UnitExists(unit) and PlayerCanAssist(unit)) then return nil end
	return i
]]

local HOVER = [[
	local id, i = self:GetAttribute("ps-ring"), self:GetAttribute("ps-hover")
	if not (id and i) then return nil end
	local unit = self:GetAttribute("r" .. id .. "u" .. i)
	if unit and not (UnitExists(unit) and PlayerCanAssist(unit)) then return false end
	return i
]]

-- A tapped slot (index i) of the open ring is its last pick. Only a slot that fires is remembered, here and above.
local USED = [[
	local i = ...
	local id = self:GetAttribute("ps-ring")
	if id and i and self:GetAttribute("r" .. id .. "t" .. i) then self:SetAttribute("r" .. id .. "l", i) end
]]

-- Each direction key is kept by name (ps-dn-<key>), not counted: a repeated press or a release the ring never saw the
-- press of can't leave it waiting. A release that finds the stick under LET_GO closes the ring and fires the pick, if
-- any, whatever is still marked down (an up that never comes, as after an ApplyConfigs mid-aim, can't keep a
-- diagonal open). Further out it waits for every key to be released, and then fires unless the stick is at the RIM.
-- A release with nothing to fire keeps the ring open: a stick pushed as the ring opened comes back to aim.
-- ponytail: the pick moves only on a key event, so a stick rolled within one direction key's range keeps the pick
-- made where that key went down; the display shows the live slot. Reading the stick every frame needs an insecure
-- poll, which can't fire.
local KEY = ([[
	local key, down = ...
	local id = self:GetAttribute("ps-ring")
	if not id or self:GetAttribute("ps-mode") ~= "hold" then return self:SetAttribute("ps-trace", format("key %%s %%s: no ring", key, down and "down" or "up")) end
	local role = self:GetAttribute("ps-role-" .. key)
	if role == "close" then
		if down then self:RunAttribute("_close") end
		return
	end
	local pick
	if role == "use" then
		if down then return end
		pick = self:RunAttribute("_pick")
		if pick == nil then pick = self:GetAttribute("ps-pick") end
		if pick == nil then pick = self:RunAttribute("_hover") end
		if pick == nil then pick = self:RunAttribute("_last", id) end
	else
		local now, len = self:RunAttribute("_pick", down and not self:GetAttribute("ps-pick") and key or nil)
		if now ~= nil then self:SetAttribute("ps-pick", now or nil) end
		self:SetAttribute("ps-dn-" .. key, down or nil)
		local held, names = self:RunAttribute("_held")
		local free = not down and len < %s
		self:SetAttribute("ps-trace", format("key %%s %%s len=%%.2f now=%%s kept=%%s down=%%s%%s", key, down and "down" or "up", len or -1, tostring(now), tostring(self:GetAttribute("ps-pick")), names, free and " let go" or ""))
		if down or not free and (held > 0 or len >= %s) then return end
		pick = self:GetAttribute("ps-pick")
	end
	if not pick then return end
	self:RunAttribute("_close")
	self:RunAttribute("_arm", "key", "typerelease", id, pick)
	if self:GetAttribute("r" .. id .. "t" .. pick) then self:SetAttribute("r" .. id .. "l", pick) end
	self:SetAttribute("ps-trace", "fire key slot " .. pick)
]]):format(LET_GO * LET_GO, RIM * RIM)

local TOGGLE = [[
	local id, at, kind, layer = ...
	if self:IsShown() and self:GetAttribute("ps-ring") == id then return self:RunAttribute("_close") end
	self:RunAttribute("_open", id, "touch", kind, nil, at, layer)
]]

-- The slots' and the catcher's taps: a slot fires its action (its own click), then the ring closes.
-- A healer slot whose unit can't be helped now is tapped in vain: nothing fires and the ring stays. A right (or any
-- other) mouse button only closes the ring.
local SLOT_PRE = [[
	if button ~= "LeftButton" then
		self:GetFrameRef("ring"):RunAttribute("_close")
		return false
	end
	local unit = self:GetAttribute("unit")
	if unit and not (UnitExists(unit) and PlayerCanAssist(unit)) then return false end
	return nil, "close"
]]
-- The key button: whatever an earlier key armed is gone first; the release fires what _key armed.
local KEY_PRE = [[
	self:SetAttribute("typerelease", nil)
	self:GetFrameRef("ring"):RunAttribute("_key", button, down)
]]
local SLOT_POST = [[
	local ring = self:GetFrameRef("ring")
	ring:RunAttribute("_used", self:GetAttribute("ps-index"))
	ring:RunAttribute("_close")
]]
-- The pointer moved onto or off a slot (the wrap runs these only for motion): ps-hover follows it.
local SLOT_ENTER = [[self:GetFrameRef("ring"):SetAttribute("ps-hover", self:GetAttribute("ps-index"))]]
local SLOT_LEAVE = [[
	local ring = self:GetFrameRef("ring")
	if ring:GetAttribute("ps-hover") == self:GetAttribute("ps-index") then ring:SetAttribute("ps-hover", nil) end
]]
local CATCH = [[self:GetFrameRef("ring"):RunAttribute("_close")]]
-- Vehicles, override and possess bars and pet battles take the routed keys away (Face.lua), so a release could be
-- lost: the ring closes there.
local GUARD = "[vehicleui][overridebar][possessbar][bonusbar:5][petbattle] off; on"
local ONGUARD = [[if newstate == "off" then self:RunAttribute("_close") end]]

local frame = CreateFrame("Frame", "ForeverControllerTweaksRing", UIParent, "SecureHandlerStateTemplate")
frame:SetSize(2 * Rings.GEO.WHEEL, 2 * Rings.GEO.WHEEL + 1)
frame:SetClampedToScreen(true)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:Hide()
-- A tap outside the slots (touch rings) closes the ring. The catcher sits under the disc art (View.lua draws at the
-- ring's level + 1), the slots above both.
local catcher = CreateFrame("Button", "ForeverControllerTweaksRingCatcher", frame, "SecureHandlerClickTemplate")
catcher:SetAllPoints(UIParent)
catcher:SetFrameLevel(frame:GetFrameLevel())
catcher:RegisterForClicks("AnyUp")
-- The open held ring's keys click it, with the key's name as the button (a key's release fires, as on the routers).
local keyButton = CreateFrame("Button", "ForeverControllerTweaksRingKey", UIParent, "SecureActionButtonTemplate")
keyButton:SetSize(1, 1)
keyButton:EnableMouse(false)
keyButton:RegisterForClicks("AnyDown", "AnyUp")
local slots = {}
for i = 1, MAX_SLOTS do
	local slot = CreateFrame("Button", "ForeverControllerTweaksRingSlot" .. i, frame, "SecureActionButtonTemplate")
	-- A finger's target: the icon and around it, short of the neighbour at 8 slots; _open sizes it per style.
	slot:SetSize(Rings.GEO.HIT, Rings.GEO.HIT)
	slot:SetFrameLevel(frame:GetFrameLevel() + 3)
	slot:RegisterForClicks("AnyUp")
	slot:Hide()
	slots[i] = slot
end

-- The protected ring frame: Face and Touch set it as the "rings" frame ref of their buttons.
function Rings.Frame() return frame end
-- Whether ring id is open now (its buttons' markers hide meanwhile). ps-ring is set before the open shows the frame and
-- cleared by every close.
function Rings.IsOpen(id) return frame:GetAttribute("ps-ring") == id end
function Rings.Slot(i) return slots[i] end

-- Snippets, frame refs and the state driver are protected calls: written once, out of combat.
local setUp
local function setup()
	if setUp then return end
	setUp = true
	frame:SetAttribute("_arm", ARM)
	frame:SetAttribute("_open", OPEN)
	frame:SetAttribute("_close", CLOSE)
	frame:SetAttribute("_release", RELEASE)
	frame:SetAttribute("_pick", PICK)
	frame:SetAttribute("_key", KEY)
	frame:SetAttribute("_held", HELD)
	frame:SetAttribute("_last", LAST)
	frame:SetAttribute("_used", USED)
	frame:SetAttribute("_hover", HOVER)
	frame:SetAttribute("ps-keyn", #KEYS.right)
	frame:SetAttribute("_toggle", TOGGLE)
	for m, prefix in ipairs(MODS) do frame:SetAttribute("ps-mod" .. m, prefix) end
	for side, list in pairs(KEYS) do
		for k, key in ipairs(list) do
			frame:SetAttribute("ps-bind" .. side .. k, key)
			local way = DIRS[key:match("STICK(%u+)$") or ""]
			frame:SetAttribute("ps-role-" .. key, ROLE[key] or "aim")
			if way then
				frame:SetAttribute("ps-kx-" .. key, way[1])
				frame:SetAttribute("ps-ky-" .. key, way[2])
			end
		end
	end
	keyButton:SetAttribute("pressAndHoldAction", true)
	SecureHandlerSetFrameRef(keyButton, "ring", frame)
	SecureHandlerSetFrameRef(frame, "key", keyButton)
	frame:WrapScript(keyButton, "OnClick", KEY_PRE)
	frame:SetAttribute("_onstate-guard", ONGUARD)
	RegisterStateDriver(frame, "guard", GUARD)
	SecureHandlerSetFrameRef(catcher, "ring", frame)
	catcher:SetAttribute("_onclick", CATCH)
	for i, slot in ipairs(slots) do
		SecureHandlerSetFrameRef(frame, "slot" .. i, slot)
		SecureHandlerSetFrameRef(slot, "ring", frame)
		slot:SetAttribute("ps-index", i)
		frame:WrapScript(slot, "OnClick", SLOT_PRE, SLOT_POST)
		frame:WrapScript(slot, "OnEnter", SLOT_ENTER)
		frame:WrapScript(slot, "OnLeave", SLOT_LEAVE)
	end
	for n = MIN_SLOTS, MAX_SLOTS do
		for i = 1, n do
			local dx, dy = dir(n, i)
			frame:SetAttribute("dx" .. n .. "-" .. i, dx)
			frame:SetAttribute("dy" .. n .. "-" .. i, dy)
		end
	end
end

-- The mapped state's 1-based indexes of the left ("Movement") and right ("Camera") sticks; 1 and 2 when they can't be
-- read.
local function stickIndexes()
	local left, right = 1, 2
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	for i = 1, ok and type(state) == "table" and state.stickCount or 0 do
		local okName, name = pcall(C_GamePad.StickIndexToConfigName, i - 1)
		if okName and (name == "Movement" or name == "Left") then left = i end
		if okName and (name == "Camera" or name == "Right") then right = i end
	end
	return left, right
end

-- Ring ids whose attributes are written, to clear them when a ring goes.
local written, pending = {}, nil
-- Healer rings by id, made from bindings as they apply (Rings.HealerRing); kept for the session, so applyNow writes
-- them again. One no binding holds any more is harmless: nothing opens it.
local healers = {}

-- One ring's attributes, out of combat; index: the catalog by id.
local function write(ring, index)
	local prefix = "r" .. ring.id
	frame:SetAttribute(prefix .. "n", ring.count)
	frame:SetAttribute(prefix .. "s", ring.stick)
	frame:SetAttribute(prefix .. "h", ring.show)
	frame:SetAttribute(prefix .. "y", ring.style)
	frame:SetAttribute(prefix .. "m", ring.middle == "last" and "last" or nil)
	-- The snippets keep the last pick from here on; one that no longer fits is dropped.
	local last, stale = lastIndex(ring)
	if stale then lastPicks()[ring.id] = nil end
	frame:SetAttribute(prefix .. "l", last)
	for i = 1, ring.count do
		local slot = ring.slots[i]
		local actionType, key, value = Rings.Attributes(slot and index[slot.id])
		frame:SetAttribute(prefix .. "t" .. i, actionType)
		frame:SetAttribute(prefix .. "k" .. i, actionType and key)
		frame:SetAttribute(prefix .. "v" .. i, actionType and value)
		frame:SetAttribute(prefix .. "u" .. i, ring.units and ring.units[i])
	end
	written[ring.id] = true
end

-- The healer ring a binding's entry opens: its id, written now (out of combat). nil when the entry can't use Healer
-- mode, or in combat for a ring not written yet.
function Rings.HealerRing(entry)
	if not (entry and Rings.HealerAllowed(entry)) then return end
	-- A binding with Last target (healerLast) gets its own ring: the middle is the ring's, and %W keeps "_" unique.
	local id = "h" .. tostring(entry.id):gsub("%W", "") .. (entry.healerLast and "_last" or "")
	if InCombatLockdown() then return written[id] and id or nil end
	local slots = {}
	for i = 1, #HEALER_UNITS do slots[i] = entry end
	local middle = entry.healerLast and "last" or "cancel"
	local ring = { id = id, name = entry.name, icon = entry.icon, count = #HEALER_UNITS, stick = "dynamic", show = "hold", style = "compact", middle = middle, healer = true, entry = entry, units = HEALER_UNITS, slots = slots }
	healers[id] = ring
	setup()
	write(ring, { [entry.id] = ns.Actions.Find(entry.id) })
	return id
end

-- A healer ring by id (View draws it), or nil.
function Rings.Healer(id) return healers[id] end

local function applyNow()
	if InCombatLockdown() then
		pending = true
		return
	end
	if not ns.db then return end
	pending = nil
	setup()
	local index = catalogIndex()
	for id in pairs(written) do
		frame:SetAttribute("r" .. id .. "n", nil)
		frame:SetAttribute("r" .. id .. "s", nil)
		frame:SetAttribute("r" .. id .. "h", nil)
		frame:SetAttribute("r" .. id .. "y", nil)
		frame:SetAttribute("r" .. id .. "m", nil)
		frame:SetAttribute("r" .. id .. "l", nil)
		for i = 1, MAX_SLOTS do
			for _, part in ipairs({ "t", "k", "v", "u" }) do frame:SetAttribute("r" .. id .. part .. i, nil) end
		end
	end
	written = {}
	for _, ring in ipairs(Rings.List()) do write(ring, index) end
	for _, ring in pairs(healers) do write(ring, index) end
	-- Face's routers by name, as its header lists them: the open snippet finds the one that opened a ring. Read only.
	local header, k = _G.ForeverControllerTweaksFaceHeader, 0
	while header and header:GetAttribute("ps-router" .. (k + 1)) do
		k = k + 1
		frame:SetAttribute("ps-router" .. k, header:GetAttribute("ps-router" .. k))
	end
	frame:SetAttribute("ps-routern", k)
	local left, right = stickIndexes()
	frame:SetAttribute("ps-lstick", left)
	frame:SetAttribute("ps-rstick", right)
	-- A ring that is no more can't stay open.
	local open = frame:GetAttribute("ps-ring")
	if open and not (Rings.Get(open) or healers[open]) then frame:Execute(CLOSE) end
	ns.debug("rings: %d written, sticks left %d right %d", #Rings.List(), left, right)
end

-- A Lua error must not stop later applies.
local failed
function apply()
	local ok, err = pcall(applyNow)
	if ok then failed = nil end
	if ok or failed then return end
	failed = true
	ns.debug("rings apply failed: %s", tostring(err))
end

ns.On("FCT_READY", function()
	local fixes = {}
	Rings.Repair(ns.db, function(what) fixes[#fixes + 1] = what end)
	for _, what in ipairs(fixes) do ns.debug("db repaired %s", what) end
	if #fixes > 0 then ns.log(("repaired %d damaged ring setting%s"):format(#fixes, #fixes == 1 and "" or "s")) end
end)
ns.On("PLAYER_ENTERING_WORLD", apply)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then apply() end end)
-- Spell ranks, macro bodies and set names change what a slot fires; one apply per frame.
local queued
ns.On("FCT_CATALOG_CHANGED", function(event)
	if queued or not (ns.Actions.TEXT_EVENTS[event] and next(Rings.List())) then return end
	queued = true
	C_Timer.After(0, function()
		queued = nil
		apply()
	end)
end)
---------------------------------------------------------------------------------------------------------------------
-- Stick pass and block: the stick a held ring aims with is kept from the game, the other stays the game's own analog
-- stick. Each frame the game sends the raw sticks in a fixed order (Left, Right, Gyro), then their virtual twins in the
-- same order (Movement, Camera, Look), and moves the character and the camera by the twins; a twin comes only after its
-- raw stick did that frame. Whether a frame hands a stick on is SetPropagateKeyboardInput's alone (OnGamePadStick's
-- return value is ignored), and that can't change in combat; Show and Hide on an insecure frame can. So two insecure
-- frames under UIParent, set up once out of combat, taking no mouse and no buttons: pass (BACKGROUND, propagates) sees
-- every stick and hands it on; block (TOOLTIP, doesn't) is shown just before the aiming stick's twin, swallows it and
-- hides. Pass is shown while a held ring is open and while the hold-off after its close (Rings.HoldStick) runs; its
-- OnUpdate, at the end of each frame, starts the next one clean, so a twin that never came can't leave block up.
-- Gyro and Look are never blocked.

local RAW_ORDER = { "Left", "Right", "Gyro" }
local TWIN = { Left = "Movement", Right = "Camera", Gyro = "Look" }
local AIM_RAW = { left = "Left", right = "Right" }
Rings.TWIN, Rings.AIM_RAW = TWIN, AIM_RAW

local function stickFrame(name, strata)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(1, 1)
	f:SetPoint("CENTER")
	f:SetAlpha(0)
	f:EnableMouse(false)
	f:SetFrameStrata(strata)
	f:Hide()
	return f
end
local pass = stickFrame("ForeverControllerTweaksRingStickPass", "BACKGROUND")
local block = stickFrame("ForeverControllerTweaksRingStickBlock", "TOOLTIP")

local function stickOffset(index)
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	local stick = ok and type(state) == "table" and state.sticks and state.sticks[index]
	return stick and stick.x * stick.x + stick.y * stick.y or 0
end

-- A heal aimed with the left stick is still casting when its ring closes: moving would break it, so HOLD_MAX doesn't
-- run while the player casts or channels. Plain flags from the player's own spellcast events (registered for "player",
-- so no unit is compared); their payloads and UnitCastingInfo may be secret and are never read. FAILED and SUCCEEDED
-- are left out: a spell pressed mid-cast fails, and an off-GCD instant (a trinket) succeeds, without ending the cast in
-- progress; STOP always follows a cast.
-- ponytail: a STOP lost to a loading screen would keep the flag up; the flags reset on entering the world, and the stick
-- coming back to the middle still frees it.
local CAST_EVENTS = {
	UNIT_SPELLCAST_START = { "casting", true }, UNIT_SPELLCAST_STOP = { "casting" }, UNIT_SPELLCAST_INTERRUPTED = { "casting" },
	UNIT_SPELLCAST_CHANNEL_START = { "channelling", true }, UNIT_SPELLCAST_CHANNEL_STOP = { "channelling" },
	UNIT_SPELLCAST_EMPOWER_START = { "channelling", true }, UNIT_SPELLCAST_EMPOWER_STOP = { "channelling" },
}
local busy = {}
local validEvent = C_EventUtils and C_EventUtils.IsEventValid
for event in pairs(CAST_EVENTS) do
	if not validEvent or validEvent(event) then pass:RegisterUnitEvent(event, "player") end
end
pass:SetScript("OnEvent", function(_, event)
	local flag = CAST_EVENTS[event]
	if flag then busy[flag[1]] = flag[2] end
end)
ns.On("PLAYER_ENTERING_WORLD", function() busy = {} end)

-- This frame's raw sticks so far, and the twin block waits for before it goes up.
local seen, armed = {}, nil

-- Every stick event either frame gets. The aiming raw stick raises block at once, unless a raw stick before it fired
-- this frame: block up now would swallow that one's twin too, so it goes up once that twin has passed.
local function onStick(stick)
	if not TWIN[stick] then
		if stick == armed then armed = nil block:Show() end
		return
	end
	seen[stick] = true
	if stick ~= AIM_RAW[pass.side] then return end
	local wait
	for _, raw in ipairs(RAW_ORDER) do
		if raw == stick then break end
		if seen[raw] then wait = TWIN[raw] end
	end
	if wait then armed = wait else block:Show() end
end
pass:SetScript("OnGamePadStick", function(_, stick) onStick(stick) end)
-- A raw stick that reaches block (the right one while the left aims) is swallowed: harmless, the game acts on twins.
block:SetScript("OnGamePadStick", function(self, stick)
	if TWIN[stick] then return onStick(stick) end
	if stick == TWIN[AIM_RAW[pass.side]] then self:Hide() end
end)

local function passOff()
	pass.left = nil
	block:Hide()
	pass:Hide()
end

pass:SetScript("OnUpdate", function(self, elapsed)
	seen, armed = {}, nil
	block:Hide()
	if not self.left then return end
	if not (busy.casting or busy.channelling) then self.left = self.left - elapsed end
	if self.left <= 0 or stickOffset(self.index) <= RECENTRE * RECENTRE then passOff() end
end)

local sticksReady
local function readySticks()
	if sticksReady or InCombatLockdown() then return end
	sticksReady = true
	pass:SetPropagateKeyboardInput(true)
	pass:EnableGamePadStick(true)
	block:SetPropagateKeyboardInput(false)
	block:EnableGamePadStick(true)
end
readySticks()
ns.On("PLAYER_REGEN_ENABLED", readySticks)

-- side ("left" | "right") aims: pass up, from a clean frame. Loaded in combat: nothing until the fight ends.
local function passOn(side)
	if not sticksReady then return end
	pass.side, seen, armed = side, {}, nil
	block:Hide()
	pass:Show()
end

-- A held ring closed: side and index (its GetGamePadState().sticks index) name the stick that aimed. It stays kept from
-- the game until it is back within RECENTRE, or HOLD_MAX outside a cast has passed; nothing while already near the
-- middle.
function Rings.HoldStick(side, index)
	if not (sticksReady and AIM_RAW[side] and index) or stickOffset(index) <= RECENTRE * RECENTRE then return end
	passOn(side)
	pass.index, pass.left = index, HOLD_MAX
end

-- A held ring opening takes pass over, from a hold-off too; any other mode lets it go, unless a hold-off runs. The
-- close's own hold-off starts after this, from the display's OnHide.
frame:HookScript("OnAttributeChanged", function(_, name, value)
	if name ~= "ps-mode" then return end
	if value == "hold" then
		pass.left = nil
		return passOn(frame:GetAttribute("ps-aimside") == "left" and "left" or "right")
	end
	if not pass.left then passOff() end
end)

---------------------------------------------------------------------------------------------------------------------
-- Stick keys: GamePadStickAxisButtons on while a held ring is open (touch rings don't aim). Driven by the ring frame's
-- ps-mode, not its OnShow: a held ring can open over a touch ring already up, and a touch ring over a held one.
-- First as a temp value (C_CVar.SetTempCVar, never saved, so a /reload or a crash mid-ring leaves nothing behind), read
-- back; a client that refuses it gets the saved write, the player's value kept in ns.db.ringAxisSaved and put back
-- at the next login if the ring never closed. A close in combat puts it back after the fight. Never written when it
-- already holds the wanted value. A failed write leaves the button's release and A to fire.
-- The write and its restore change the controller config, so a held ring holds Remap (Remap.Hold) from its open until
-- the CVar is back: no ApplyConfigs mid-aim or with the stick keys still on.
-- ponytail: a saved 1 the client didn't apply at login (a known client issue) reads as 1 and isn't rewritten, so
-- for a player who keeps it on the keys may not come until it is toggled; writing 0 then 1 on open would cover that.

local AXIS = "GamePadStickAxisButtons"
-- engaged: a held ring switched the keys on (or found them on) and holds Remap; temp: on as a temp value; restoring:
-- the restore is queued for the next frame.
local engaged, temp, restoring

local function writeAxis(value)
	local ok, done = pcall(SetCVar, AXIS, value)
	return ok and done ~= false
end

local function setTemp()
	local cvar = C_CVar
	if not (cvar and cvar.SetTempCVar) or not pcall(cvar.SetTempCVar, AXIS, "1") then return false end
	if GetCVar(AXIS) == "1" then return true end
	pcall(cvar.RemoveTempCVar, AXIS)
	return false
end

-- Remap's failsafe asks this: held while the ring aims, until its restore has run (in combat Remap can't apply anyway).
local function stillHeld() return frame:GetAttribute("ps-mode") == "hold" or restoring or InCombatLockdown() end

-- A held button our controller config moves off its native key (L1 as the right modifier), by its physical name.
local function movedHeld()
	for phys, key in pairs(ns.Remap.Outputs and ns.Remap.Outputs() or NONE) do
		local ok, down = pcall(IsKeyDown, key)
		if key ~= ns.Layout.NATIVE_KEY[phys] and ok and down then return phys end
	end
end

-- The keys on: a temp value first, read back, else the saved write.
local function keysOn()
	local current = GetCVar(AXIS)
	if current == "1" then return end
	-- Every change of the CVar drops our controller config until Remap writes it again (GetConfig reads nil after each
	-- one), so the pad runs native meanwhile. A moved button held across that went down as its role's key and comes up
	-- as its native one: the role's binding never sees the release, and with a crossbar modifier the Gamepad UI keeps
	-- that bar. With one held the keys stay off; the button's release and A still fire.
	local moved = movedHeld()
	if moved then return ns.debug("rings: stick keys left off, %s (moved by the layout) is held", moved) end
	temp = setTemp()
	if temp then return end
	if ns.db.ringAxisSaved == nil then ns.db.ringAxisSaved = current end
	writeAxis("1")
end

local function engage()
	if not ns.db then return end
	-- Opened again before the last close's restore ran: the keys are still on.
	if engaged then return end
	engaged = true
	ns.Remap.Hold(true, stillHeld)
	keysOn()
end

local function restoreAxis()
	restoring = nil
	if frame:GetAttribute("ps-mode") == "hold" then return end
	local db = ns.db
	local saved = db and db.ringAxisSaved
	-- Remap stays held while the keys are still on.
	if (temp or saved ~= nil) and InCombatLockdown() then return end
	-- Removing the temp value doesn't refresh the controller: the stick keeps sending keys (the game's own radial
	-- flyout then closes on the first push) until a real write. Flip it and back, ending on the player's value.
	if temp and pcall(C_CVar.RemoveTempCVar, AXIS) then local value = GetCVar(AXIS) writeAxis(value == "1" and "0" or "1") writeAxis(value) end
	temp = nil
	if saved ~= nil then
		ns.Remap.Hold(true, stillHeld)
		if GetCVar(AXIS) == saved or writeAxis(saved) then db.ringAxisSaved = nil end
	end
	engaged = nil
	-- After the write: Remap's settle starts from it.
	ns.Remap.Hold(false)
end

frame:HookScript("OnAttributeChanged", function(_, name, value)
	if name == "ps-ring" then return ns.Fire("FCT_RING_MARKS") end
	if name ~= "ps-mode" then return end
	if value == "hold" then return engage() end
	if not engaged or restoring then return end
	-- Next frame, out of the click that closed the ring and fires its slot.
	restoring = true
	C_Timer.After(0, restoreAxis)
end)
ns.On("PLAYER_REGEN_ENABLED", restoreAxis)

-- Every pick the snippets record (r<id>l, in combat too) is saved for this character with its slot's action, and the
-- buttons showing the ring's live icon redraw. A cleared attribute (applyNow rewriting) changes nothing.
frame:HookScript("OnAttributeChanged", function(_, name, value)
	local key = type(value) == "number" and name:match("^r(.+)l$")
	if not key then return end
	local id = tonumber(key) or key
	local ring = Rings.Get(id) or healers[id]
	local slot = ring and ring.slots[value]
	local picks = slot and lastPicks(true)
	if not picks then return end
	local old = picks[id]
	if old and old[1] == value and old[2] == slot.id then return end
	picks[id] = { value, slot.id }
	ns.Fire("FCT_RING_LAST", id)
end)
-- After the repair above (FCT_READY handlers run in order).
ns.On("FCT_READY", restoreAxis)

---------------------------------------------------------------------------------------------------------------------
-- /fct ringlog: the last ring events the snippets wrote (ps-trace: opens, releases, stick keys, closes) with the time,
-- so a player can send the order a release came in.

local TRACE_MAX, trace = 40, {}
frame:HookScript("OnAttributeChanged", function(_, name, value)
	if name ~= "ps-trace" or not value then return end
	trace[#trace + 1] = ("%.3f %s"):format(GetTime(), value)
	if #trace > TRACE_MAX then table.remove(trace, 1) end
	-- With /fct debug on it also lands in the saved debug log, so a stuck ring can be read after /reload.
	ns.debug("ring %s", value)
end)
Rings.Trace = trace

function ns.commands.ringlog()
	if not trace[1] then return ns.log("ringlog: no ring events yet. Open a ring, use it, then type /fct ringlog.") end
	for _, line in ipairs(trace) do ns.log("ringlog: " .. line) end
end

-- Bars and the stick config can change with the Gamepad UI or the controller.
ns.On("FCT_ACTIVE_CHANGED", apply)
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then apply() end end)
