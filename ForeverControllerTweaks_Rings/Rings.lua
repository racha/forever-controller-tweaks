-- Forever Controller Tweaks action rings (design/rings.md): radial menus of catalog actions, account-wide, opened from
-- any routed face or D-pad cell (Face.lua) or touch button (Touch.lua) that holds the entry "ring:<id>".
--
-- Storage: ns.db.rings = { nextId, list = { { id, name, icon, count, stick, slots = { [i] = { id, name, icon, kind } } } } }.
-- stick: which stick aims a held ring, "right", "left" or "dynamic" (opened from a D-pad cell: right; from a face
-- button cell: left, the hand that isn't on the button). Touch rings are tapped.
-- A slot keeps the catalog id, so a spell group resolves to each character's own highest rank. icon nil: the first
-- filled slot's icon.
--
-- Secure engine: one protected frame (ForeverControllerTweaksRing) holds, out of combat, every ring's slot actions as
-- attributes (r<id>n count, r<id>t<i> type, r<id>k<i> attribute, r<id>v<i> value) and the slot directions per count
-- (dx<n>-<i>, dy<n>-<i>). Its snippets run in its own environment, called with RunAttribute from the router or the
-- touch button that owns the press. RunAttribute scrubs its arguments to nil, booleans, numbers and strings (a frame
-- handle arrives as nil), so a button is passed by the name of the ring frame's frame ref to it: "slot<i>" for its
-- slots, the router's own name for each Face router (Face.lua sets those refs).
--   _open(id, mode, kind) lays out and arms the slot buttons, picks the aiming stick (kind: the opening cell, "face" or
--                         "dpad", for a dynamic ring) and shows the ring ("hold" or "touch");
--   _release(ref)         on the held button's release: picks the slot the aiming stick points at (the largest dot
--                         product with a slot direction, nothing inside the dead zone), hides the ring and arms that
--                         button's typerelease with that slot's action;
--   _toggle(id)           a touch tap: opens the ring, or closes it when it is the one open;
--   _close()              hides it; _arm(ref, which, id, i) writes one slot's action on a button.
-- No action slot is used: the actions fire through direct secure attributes (spell, item, toy, macrotext).
local ns = ForeverControllerTweaks
local Rings = {}
ns.Rings = Rings

local MAX_RINGS, MIN_SLOTS, MAX_SLOTS, DEFAULT_SLOTS, NAME_MAX = 12, 4, 12, 8, 24
Rings.MAX_RINGS, Rings.MIN_SLOTS, Rings.MAX_SLOTS, Rings.NAME_MAX = MAX_RINGS, MIN_SLOTS, MAX_SLOTS, NAME_MAX
local STICKS = { right = true, left = true, dynamic = true }
Rings.STICKS = { "right", "left", "dynamic" }
-- The names OnGamePadStick reports one physical stick by.
Rings.AIM_NAMES = { right = { Right = true, Camera = true, Look = true }, left = { Left = true, Movement = true } }
-- After a held ring closes its aiming stick is still pushed: kept from the game until it is back within RECENTRE of
-- the middle, at most HOLD_MAX seconds, so a reading that never settles can't block movement or the camera.
local RECENTRE, HOLD_MAX = 0.2, 1
-- The native radial menu's selection threshold is 0.5; a ring cancels a little closer to the centre, so a thumb
-- easing off as the button lets go still counts.
local DEADZONE = 0.4
-- Disc radius, slot centre radius, slot icon size, hub radius (UI units at scale 1).
Rings.GEO = { DISC = 160, SLOT_R = 112, ICON = 46, HUB = 54 }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local COMBAT = "Controller Tweaks changes rings out of combat only."
local NONE = {}

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

local function store()
	ns.db.rings = ns.db.rings or { nextId = 1, list = {} }
	return ns.db.rings
end

function Rings.List() return ns.db and store().list or NONE end

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

-- The catalog entries of the Rings category (Actions.lua): "Open ring: <name>".
function Rings.Entries()
	local out = {}
	for _, ring in ipairs(Rings.List()) do
		out[#out + 1] = { id = "ring:" .. ring.id, category = "Rings", name = "Open ring: " .. ring.name, icon = Rings.Icon(ring), kind = "ring", payload = ring.id }
	end
	return out
end

-- Every stored binding that holds a ring, on every character: routed cells cells[device][code][layer] and touch
-- buttons touch.bars[side][i][layer]. fn(holder, key, ringId) may set holder[key] (nil drops it); an emptied row or
-- button goes too.
local function eachBinding(db, fn)
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
	for _, char in pairs(type(db.chars) == "table" and db.chars or NONE) do
		if type(char) == "table" then
			for _, byCode in pairs(type(char.cells) == "table" and char.cells or NONE) do walk(byCode, byCode) end
			local bars = type(char.touch) == "table" and type(char.touch.bars) == "table" and char.touch.bars or NONE
			for _, list in pairs(bars) do
				if type(list) == "table" then walk(list, list) end
			end
		end
	end
end

-- Bindings keep a copy of the ring's name and icon for the panels and glyphs; they follow every change.
local function syncBindings()
	eachBinding(ns.db, function(row, key, id)
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
	local rings = store()
	if #rings.list >= MAX_RINGS then return nil, ("You have %d rings, the most there can be. Delete one first."):format(MAX_RINGS) end

	local taken = {}
	for _, ring in ipairs(rings.list) do taken[ring.name] = true end
	local n = 1
	while taken["Ring " .. n] do n = n + 1 end
	local ring = { id = rings.nextId, name = "Ring " .. n, count = DEFAULT_SLOTS, stick = "right", slots = {} }
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

-- Deletes the ring and every binding that opens it, on every character.
function Rings.Delete(id)
	local ring, err = editable(id)
	if not ring then return nil, err end

	local list = store().list
	for i = #list, 1, -1 do
		if list[i] == ring then table.remove(list, i) end
	end
	return changed()
end

-- How many stored bindings open this ring, every character counted (the delete confirmation says so).
function Rings.BindingCount(id)
	local n = 0
	eachBinding(ns.db, function(_, _, ringId) if ringId == id then n = n + 1 end end)
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

-- Repairs ns.db.rings into the shape above: bad rings and slots are dropped, missing fields get their defaults, ids
-- stay unique, at most MAX_RINGS, and bindings to rings that no longer exist are dropped. fix(path) per repair.
function Rings.Repair(db, fix)
	local rings = db.rings
	if rings ~= nil and type(rings) ~= "table" then fix("rings") end
	rings = type(rings) == "table" and rings or {}
	db.rings = rings
	if type(rings.list) ~= "table" then
		if rings.list ~= nil then fix("rings.list") end
		rings.list = {}
	end

	-- In list order, so the first of two rings with one id is the one kept.
	local kept, seen, top = {}, {}, 0
	for key, ring in pairs(rings.list) do
		local id = type(ring) == "table" and ring.id
		if type(key) ~= "number" or type(id) ~= "number" or id < 1 or id % 1 ~= 0 then fix("rings.list." .. tostring(key)) else kept[#kept + 1] = { key, ring } end
	end
	table.sort(kept, function(a, b) return a[1] < b[1] end)
	local list = {}
	for _, pair in ipairs(kept) do
		local ring, path = pair[2], "rings." .. pair[2].id
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
			repairSlots(ring, path, fix)
			seen[ring.id] = true
			list[#list + 1] = ring
			top = math.max(top, ring.id)
		end
	end
	rings.list = list
	if type(rings.nextId) ~= "number" or rings.nextId % 1 ~= 0 or rings.nextId <= top then
		if rings.nextId ~= nil then fix("rings.nextId") end
		rings.nextId = top + 1
	end

	eachBinding(db, function(row, key, id)
		if seen[id] then return end
		row[key] = nil
		fix("binding to deleted ring " .. id)
	end)
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
	local cast = (actionType == "spell" or actionType == "item") or nil
	button:SetAttribute("checkselfcast", cast)
	button:SetAttribute("checkfocuscast", cast)
	button:SetAttribute("checkmouseovercast", cast)
]]

local OPEN = ([[
	local id, mode, kind = ...
	local n = id and self:GetAttribute("r" .. id .. "n")
	if not n then return end
	local stick = self:GetAttribute("r" .. id .. "s")
	if stick == "dynamic" then stick = kind == "face" and "left" or "right" end
	self:SetAttribute("ps-aimside", stick == "left" and "left" or "right")
	self:SetAttribute("ps-aim", stick == "left" and self:GetAttribute("ps-lstick") or self:GetAttribute("ps-rstick"))
	for i = 1, %d do
		local slot = self:GetFrameRef("slot" .. i)
		if i <= n then
			slot:ClearAllPoints()
			slot:SetPoint("CENTER", self, "CENTER", %d * self:GetAttribute("dx" .. n .. "-" .. i), %d * self:GetAttribute("dy" .. n .. "-" .. i))
			self:RunAttribute("_arm", "slot" .. i, "type", id, i)
			slot:Show()
		else
			slot:Hide()
		end
	end
	self:SetAttribute("ps-ring", id)
	self:SetAttribute("ps-mode", mode)
	self:Show()
]]):format(MAX_SLOTS, Rings.GEO.SLOT_R, Rings.GEO.SLOT_R)

local CLOSE = [[
	self:SetAttribute("ps-ring", nil)
	self:SetAttribute("ps-mode", nil)
	self:Hide()
]]

local RELEASE = ([[
	local ref = ...
	local button = ref and self:GetFrameRef(ref)
	if not button then return end
	button:SetAttribute("typerelease", nil)
	local id = self:GetAttribute("ps-ring")
	if not id or self:GetAttribute("ps-mode") ~= "hold" then return end
	local n = self:GetAttribute("r" .. id .. "n")
	local state = GetGamePadState()
	local stick = state and state.sticks and state.sticks[self:GetAttribute("ps-aim") or 2]
	self:RunAttribute("_close")
	local x, y = stick and stick.x or 0, stick and stick.y or 0
	if not n or x * x + y * y < %s then return end
	local best, bestDot
	for i = 1, n do
		local dot = x * self:GetAttribute("dx" .. n .. "-" .. i) + y * self:GetAttribute("dy" .. n .. "-" .. i)
		if not bestDot or dot > bestDot then best, bestDot = i, dot end
	end
	self:RunAttribute("_arm", ref, "typerelease", id, best)
]]):format(DEADZONE * DEADZONE)

local TOGGLE = [[
	local id = ...
	if self:IsShown() and self:GetAttribute("ps-ring") == id then return self:RunAttribute("_close") end
	self:RunAttribute("_open", id, "touch")
]]

-- The slots' and the catcher's taps: a slot fires its action (its own click), then the ring closes.
local SLOT_PRE = [[return nil, "close"]]
local SLOT_POST = [[self:GetFrameRef("ring"):RunAttribute("_close")]]
local CATCH = [[self:GetFrameRef("ring"):RunAttribute("_close")]]
-- Vehicles, override and possess bars and pet battles take the routed keys away (Face.lua), so a release could be
-- lost: the ring closes there.
local GUARD = "[vehicleui][overridebar][possessbar][bonusbar:5][petbattle] off; on"
local ONGUARD = [[if newstate == "off" then self:RunAttribute("_close") end]]

local frame = CreateFrame("Frame", "ForeverControllerTweaksRing", UIParent, "SecureHandlerStateTemplate")
frame:SetSize(2 * Rings.GEO.DISC, 2 * Rings.GEO.DISC)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:Hide()
-- A tap outside the slots (touch rings) closes the ring. The catcher sits under the disc art (View.lua draws at the
-- ring's level + 1), the slots above both.
local catcher = CreateFrame("Button", "ForeverControllerTweaksRingCatcher", frame, "SecureHandlerClickTemplate")
catcher:SetAllPoints(UIParent)
catcher:SetFrameLevel(frame:GetFrameLevel())
catcher:RegisterForClicks("AnyUp")
local slots = {}
for i = 1, MAX_SLOTS do
	local slot = CreateFrame("Button", "ForeverControllerTweaksRingSlot" .. i, frame, "SecureActionButtonTemplate")
	slot:SetSize(Rings.GEO.ICON, Rings.GEO.ICON)
	slot:SetFrameLevel(frame:GetFrameLevel() + 3)
	slot:RegisterForClicks("AnyUp")
	slot:Hide()
	slots[i] = slot
end

-- The protected ring frame: Face and Touch set it as the "rings" frame ref of their buttons.
function Rings.Frame() return frame end
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
	frame:SetAttribute("_toggle", TOGGLE)
	frame:SetAttribute("_onstate-guard", ONGUARD)
	RegisterStateDriver(frame, "guard", GUARD)
	SecureHandlerSetFrameRef(catcher, "ring", frame)
	catcher:SetAttribute("_onclick", CATCH)
	for i, slot in ipairs(slots) do
		SecureHandlerSetFrameRef(frame, "slot" .. i, slot)
		SecureHandlerSetFrameRef(slot, "ring", frame)
		frame:WrapScript(slot, "OnClick", SLOT_PRE, SLOT_POST)
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
		for i = 1, MAX_SLOTS do
			for _, part in ipairs({ "t", "k", "v" }) do frame:SetAttribute("r" .. id .. part .. i, nil) end
		end
	end
	written = {}
	for _, ring in ipairs(Rings.List()) do
		local prefix = "r" .. ring.id
		frame:SetAttribute(prefix .. "n", ring.count)
		frame:SetAttribute(prefix .. "s", ring.stick)
		for i = 1, ring.count do
			local slot = ring.slots[i]
			local actionType, key, value = Rings.Attributes(slot and index[slot.id])
			frame:SetAttribute(prefix .. "t" .. i, actionType)
			frame:SetAttribute(prefix .. "k" .. i, actionType and key)
			frame:SetAttribute(prefix .. "v" .. i, actionType and value)
		end
		written[ring.id] = true
	end
	local left, right = stickIndexes()
	frame:SetAttribute("ps-lstick", left)
	frame:SetAttribute("ps-rstick", right)
	-- A ring that is no more can't stay open.
	local open = frame:GetAttribute("ps-ring")
	if open and not Rings.Get(open) then frame:Execute(CLOSE) end
	ns.debug("rings: %d written, sticks left %d right %d", #Rings.List(), left, right)
end

-- A Lua error must not stop later applies.
local failed
function apply()
	local ok, err = pcall(applyNow)
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
-- Stick hold-off: our own insecure frame under UIParent (not the secure ring frame's child, which hides with it). It
-- has EnableGamePadStick set once out of combat; shown, it keeps the aiming stick's events and hands the other stick
-- on, and takes no buttons and no mouse. Shown and hidden from insecure code, in combat too: nothing on it is
-- protected. Its OnUpdate runs only while shown.

local hold = CreateFrame("Frame", "ForeverControllerTweaksRingStickHold", UIParent)
hold:SetSize(1, 1)
hold:SetPoint("CENTER")
hold:SetAlpha(0)
hold:EnableMouse(false)
hold:Hide()

local function stickOffset(index)
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	local stick = ok and type(state) == "table" and state.sticks and state.sticks[index]
	return stick and stick.x * stick.x + stick.y * stick.y or 0
end

hold:SetScript("OnGamePadStick", function(self, stick) return not Rings.AIM_NAMES[self.side][stick] end)
hold:SetScript("OnUpdate", function(self, elapsed)
	self.left = self.left - elapsed
	if self.left <= 0 or stickOffset(self.index) <= RECENTRE * RECENTRE then self:Hide() end
end)

local holdReady
local function readyHold()
	if holdReady or InCombatLockdown() then return end
	holdReady = true
	hold:EnableGamePadStick(true)
end
readyHold()
ns.On("PLAYER_REGEN_ENABLED", readyHold)

-- A held ring closed: side ("left" | "right") and index (its GetGamePadState().sticks index) name the stick that aimed.
-- Nothing to do while it is already near the middle.
function Rings.HoldStick(side, index)
	if not (holdReady and Rings.AIM_NAMES[side] and index) or stickOffset(index) <= RECENTRE * RECENTRE then return end
	hold.side, hold.index, hold.left = side, index, HOLD_MAX
	hold:Show()
end

-- Bars and the stick config can change with the Gamepad UI or the controller.
ns.On("FCT_ACTIVE_CHANGED", apply)
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason == "device" then apply() end end)
