-- Forever Controller Tweaks face router: moves Interact, Inspect, Back and Jump between the face buttons, and runs any
-- catalog entry on any face or D-pad button, or on a back paddle without a role, per crossbar layer (a "cell").
--
-- Each routed key is bound (a non-priority override, so Blizzard's window binding sets still win) to a secure macro button. Its snippet reads the held pad buttons, picks the layer, and writes
-- `/click <Blizzard button> LeftButton 1` on press and `/click <Blizzard button> LeftButton` on release, which keeps
-- Interact hold-to-loot and Jump's release (verified in game). Unmodified face presses go to the reserved top-bar
-- button of the chosen action; other presses go to the native slot of that physical key on the bar Blizzard would
-- activate, so they behave exactly as without the addon.
-- A cell can instead hold a catalog entry (Actions.lua), stored per character and controller: a face action is a
-- click of its reserved top-bar button on that layer; anything a slot holds sits in its own shadow action slot
-- (Actions.Shadow) and fires with type "action" like Blizzard's buttons (ps-action-<layer>); when no shadow slot can
-- be placed it runs its secure macro text instead (ps-entry-<layer>). Routed cells apply on every crossbar page, and
-- a click catcher over the cell's crossbar slot takes mouse clicks, hover and gamepad focus.
-- A back paddle has no crossbar slot: only its cells route (a layer without one does nothing), and only while the
-- paddle has no role, so it still outputs PADPADDLEn.
-- The header owns the bindings and drops them in vehicles, override/possess bars and pet battles, in combat too.
local _, ns = ...
local Layout = ns.Layout

local ACTION_SLOT = { interact = 5, inspect = 6, back = 7, jump = 8 }
-- The game's default bindings (bar slots 1-8), used only when the core binding context can't be read.
local ASSUMED_SLOT = { PADDLEFT = 1, PADDUP = 2, PADDRIGHT = 3, PADDDOWN = 4, PAD3 = 5, PAD4 = 6, PAD2 = 7, PAD1 = 8 }
-- Cells use the Bindings grid's ids: row codes (face positions first, in Layout.FACE_POSITIONS order, as the router
-- index; the paddles last, so Glyphs' ps-key1..8 stay the crossbar keys) and layers T/L/R/B (top, left, right, bottom bar).
local CODES = { "FB", "FR", "FL", "FT", "DU", "DL", "DR", "DD", "P1", "P2", "P3", "P4" }
local CODE_KEY = {
	FB = "PAD1", FR = "PAD2", FL = "PAD3", FT = "PAD4", DU = "PADDUP", DL = "PADDLEFT", DR = "PADDRIGHT", DD = "PADDDOWN",
	P1 = "PADPADDLE1", P2 = "PADPADDLE2", P3 = "PADPADDLE3", P4 = "PADPADDLE4",
}
local CODE_POS = { FB = "bottom", FR = "right", FL = "left", FT = "top" }
local POS_CODE = { bottom = "FB", right = "FR", left = "FL", top = "FT" }
local ROUTER_NAME = { DU = "DpadUp", DL = "DpadLeft", DR = "DpadRight", DD = "DpadDown", P1 = "Paddle1", P2 = "Paddle2", P3 = "Paddle3", P4 = "Paddle4" }
local PADDLES = { P1 = true, P2 = true, P3 = true, P4 = true }
local CELL_LAYERS = { "T", "L", "R", "B" }
local CELL_LAYER = { T = "top", L = "left", R = "right", B = "bottom" }
local CELL_BAR = { T = "topBar", L = "leftBar", R = "rightBar", B = "bottomBar" }
local CORE_CTX = Enum.BindingContext and Enum.BindingContext.GamepadModeInGameCore or 9
local BARS = { left = "leftBar", right = "rightBar", bottom = "bottomBar", friendly = "friendlyTargetingBar", hostile = "hostileTargetingBar", shortcuts = "shortcutsBar" }
local MOD_ROLES = { "leftmod", "rightmod" }
local TARGET_LAYERS = { friendly = true, hostile = true, shortcuts = true }
-- Blizzard checks the possess bar before the stance bar (PageUnit.overrideBars).
local OVERRIDES = {
	{ kind = "pet", bar = "possessBar", cvar = "GamepadPossessBarOverride", condition = "[pet]" },
	{ kind = "stance", bar = "stanceBar", cvar = "GamepadStanceBarOverride", condition = "[bonusbar]" },
}
local GUARD = "[vehicleui][overridebar][possessbar][bonusbar:5][petbattle] native; "
local BAR_RETRIES = 10

-- Same order as PageUnit:ActionBarModKeyDownStateCheck: crossbar modifiers (held only) win, then a targeting bar in
-- place of the top bar. Targeting bars latch with the modifier-toggle option and follow Blizzard's own rules when one
-- of two held modifiers is let go (HoldBindings.lua:87-96, 127-200), and a bar shows exactly while it is active
-- (StaticOverrideActionBar ActivateOverrideBar), so the shown bar decides, not the held buttons.
-- An override bar replaces its layer only on its page; restricted code can't read the page, but the bar's
-- (protected) button is visible exactly when Blizzard shows that bar in place of the layer's bar.
local ROUTER_SNIPPET = [[
	local name, layer, slot
	if down then
		-- A healer ring's release armed this button with a unit; no other route may cast on it.
		self:SetAttribute("unit", nil)
		local state = GetGamePadState()
		local held = state and state.buttons
		layer = "top"
		if held then
			local lm, rm = held[self:GetAttribute("ps-ileftmod") or 0], held[self:GetAttribute("ps-irightmod") or 0]
			if lm and rm then layer = "bottom"
			elseif lm then layer = "left"
			elseif rm then layer = "right" end
		end
		if layer == "top" then
			for _, kind in ipairs(TARGET_KINDS) do
				local shown = self:GetFrameRef("bar-" .. kind)
				if shown and shown:IsVisible() then
					layer = kind
					break
				end
			end
		end
		name = self:GetAttribute("ps-" .. layer)
		for _, kind in ipairs(OVERRIDE_KINDS) do
			if control:GetAttribute("state-" .. kind) == "on" and self:GetAttribute("ps-" .. kind .. "layer") == layer then
				local button = self:GetFrameRef(kind)
				if button and button:IsVisible() then
					name, layer = button:GetName(), kind
					break
				end
			end
		end
		slot = self:GetAttribute("ps-action-" .. layer)
		if slot then name = "action"
		elseif self:GetAttribute("ps-entry-" .. layer) then name = "entry"
		elseif self:GetAttribute("ps-ring-" .. layer) then name = "ring"
		else
			-- Since 11.0.2 a macro can't /click a button that runs another macro (dropped without an error), so a
			-- player macro in the native slot fires as that slot, as Blizzard's button would. Anything else keeps the
			-- /click: the button's flyout radial and press dent. ID 0: an empty or reserved slot.
			local native = self:GetFrameRef("slot-" .. layer)
			local id = native and native:GetName() == name and native:GetID() or 0
			if id > 0 and GetActionInfo(id) == "macro" then name, slot = "action", id end
		end
		self:SetAttribute("ps-cur", name)
		self:SetAttribute("ps-curlayer", name and layer or nil)
	else
		name, layer = self:GetAttribute("ps-cur"), "release"
		self:SetAttribute("ps-curlayer", nil)
	end
	if self:GetAttribute("ps-debug") then self:SetAttribute("ps-route", format("%s %s %s %s", self:GetAttribute("ps-pos"), down and "down" or "up", layer, tostring(name))) end
	if not name then return false end
	-- A ring (Rings.lua): the press opens it (or closes it, open), the release fires the slot the stick points at.
	if name == "ring" then
		local rings = self:GetFrameRef("rings")
		self:SetAttribute("type", nil)
		self:SetAttribute("typerelease", nil)
		if rings and down then rings:RunAttribute("_open", self:GetAttribute("ps-ring-" .. layer), "hold", self:GetAttribute("ps-kind"), self:GetAttribute("ps-key")) end
		if rings and not down then rings:RunAttribute("_release", self:GetName()) end
		return
	end
	-- A shadow slot, or a macro's native slot: the pair Blizzard's action buttons use, UseAction on press and
	-- ReleaseAction on release (hold-to-cast, empower). The release keeps what the press set.
	-- The cast checks only on that route: on a macro press they'd look up a stale or default action.
	if name == "action" then
		if down then
			self:SetAttribute("type", "action")
			self:SetAttribute("typerelease", "actionrelease")
			self:SetAttribute("action", slot)
			self:SetAttribute("checkselfcast", true)
			self:SetAttribute("checkfocuscast", true)
			self:SetAttribute("checkmouseovercast", true)
		end
		return
	end
	self:SetAttribute("type", "macro")
	self:SetAttribute("typerelease", "macro")
	self:SetAttribute("checkselfcast", nil)
	self:SetAttribute("checkfocuscast", nil)
	self:SetAttribute("checkmouseovercast", nil)
	if name == "entry" then
		self:SetAttribute("macrotext", down and self:GetAttribute("ps-entry-" .. layer) or "")
		return
	end
	self:SetAttribute("macrotext", "/click " .. name .. (down and " LeftButton 1" or " LeftButton"))
]]

local Face = {}
ns.Face = Face

-- Shared with Actions.lua and Touch.lua. Press and release in one click, for the reserved buttons that act on press
-- (Jump, Back, Interact) or release (Inspect): a "click" type only sends the release.
Face.CLICK_BOTH = "/click %s LeftButton 1\n/click %s LeftButton"
function Face.ClickBoth(name) return Face.CLICK_BOTH:format(name, name) end
-- Self, focus and mouseover cast modifiers, as Blizzard's action buttons set them (ActionButton.lua OnLoad).
Face.CHECK_CASTS = { "checkselfcast", "checkfocuscast", "checkmouseovercast" }

local function charKey()
	local name = UnitName and UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	return name and realm and name .. "-" .. realm
end

-- The character can't change before a reload, so its key is read once from PLAYER_LOGIN on.
local loggedKey
ns.On("PLAYER_LOGIN", function() loggedKey = charKey() end)

-- This character's table in ns.db.chars["Name-Realm"], and its key; nil before the name is known.
function Face.CharDB()
	local key = loggedKey or charKey()
	if not (ns.db and key) then return nil end

	ns.db.chars = ns.db.chars or {}
	ns.db.chars[key] = ns.db.chars[key] or {}
	return ns.db.chars[key], key
end

-- An apply in progress, or any slot write (Actions.Busy), holds off a nested apply; the one that follows covers it.
local busy


-- Routed cells per character and controller: ns.db.chars[char].cells[deviceKey][code][layer] = { id, name, icon, kind }.
-- Written out of combat only (the router attributes follow on the next apply). Older stores move in once: the
-- account-wide ns.db.faceEntries to the first character seen, a character's faceEntries[deviceKey][pos] to the
-- base layer of that face button.
local function resolveCells(create)
	local device, char = ns.Device.Current(), Face.CharDB()
	if not (device and char) then return nil, false end
	if ns.db.faceEntries then
		char.faceEntries = char.faceEntries or ns.db.faceEntries
		ns.db.faceEntries = nil
	end
	char.cells = char.cells or {}
	for deviceKey, list in pairs(char.faceEntries or {}) do
		local byCode = char.cells[deviceKey] or {}
		char.cells[deviceKey] = byCode
		for pos, entry in pairs(list) do
			local code = POS_CODE[pos]
			if code then
				byCode[code] = byCode[code] or {}
				byCode[code].T = byCode[code].T or { id = entry.id, name = entry.name, icon = entry.icon, kind = ns.Actions.KindOf(entry) }
			end
		end
	end
	char.faceEntries = nil
	local list = char.cells[device.key]
	if not list and create then
		list = {}
		char.cells[device.key] = list
	end
	return list, true
end

-- Glyphs reads cells many times a second, so the resolved table is kept (false: none yet for this device) until the
-- layout, the device or the character changes.
local cellCache
local function cells(create)
	if cellCache == nil or (create and not cellCache) then
		local list, known = resolveCells(create)
		if not known then return nil end
		cellCache = list or false
	end
	return cellCache or nil
end

local function entryText(entry)
	return entry and (ns.Actions and ns.Actions.TextFor(entry.id) or entry.text)
end

-- True when this entry on this cell must go through the router: a face button's base layer (its storage slot is
-- reserved for the face actions), or an entry no storage slot can hold (a face action) on any layer. Everything
-- else goes into the cell's storage slot (Actions.Assign), D-pad base layer included. A paddle has no storage slot.
function Face.Routable(code, layer, entry)
	if not (CODE_KEY[code] and CELL_LAYER[layer]) then return false end
	if PADDLES[code] or layer == "T" and CODE_POS[code] then return true end
	return not not (entry and not ns.Actions.SLOT_KINDS[ns.Actions.KindOf(entry)])
end

-- True when a back paddle carries its cells: it has no role (so it still outputs PADPADDLEn) and this pad has it.
function Face.PaddleFree(code)
	local device = PADDLES[code] and ns.Device.Current()
	return not not (device and device.raw and device.raw[code] and not Layout.Roles()[code])
end

-- The routed entry { id, name, icon, kind } on a cell, or nil. Callers must not modify it.
function Face.CellEntry(code, layer)
	local list = cells()
	local row = list and list[code]
	return row and row[layer]
end

local function nativeSlot(key)
	local ok, action = pcall(GetBindingAction, key, nil, CORE_CTX)
	local slot = tonumber((ok and action or ""):match("^GAMEPADACTIONBUTTON(%d)$"))
	return slot or ASSUMED_SLOT[key]
end

local BAR_INDEX = { T = 1, L = 2, R = 3, B = 4 }

-- A cell's storage slot on a crossbar page; nil for the reserved top-bar face slots, the paddles, or without the
-- Gamepad action bars.
local function storageSlot(code, layer, page)
	local util = GamepadActionBarBindingUtil
	local storage = util and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID
	if not storage or PADDLES[code] or (layer == "T" and CODE_POS[code]) then return end

	local ok, slot = pcall(storage, page, (BAR_INDEX[layer] - 1) * ns.Actions.PER_BAR + nativeSlot(CODE_KEY[code]))
	return ok and slot or nil
end

-- A routed cell applies on every crossbar page, so the cell's storage slots sit under it: shown around the routed entry
-- and fired natively when the router stands down. page: the page being edited, whose slot is emptied whatever it
-- holds; on every other page (or without a page) only the addon's own FCT: macros go, never the player's actions.
-- The reserved top-bar face slots and the paddles have none.
local function clearUnder(code, layer, page)
	local Actions = ns.Actions
	for p = 1, Actions.STANDARD_PAGES do
		local slot = storageSlot(code, layer, p)
		if slot and (p == page and C_ActionBar.HasAction(slot) or Actions.Ours(slot)) then
			local cleared, err = Actions.Clear(slot)
			if not cleared then return nil, err end
		end
	end
	return true
end

-- entry = { id, name, icon[, kind] } (a passed text is ignored: it is built from the id) or nil to give the cell
-- back (a face button's base layer goes back to its face action). page (1-3): the crossbar page shown while editing.
-- Fires FCT_LAYOUT_CHANGED("layout").
function Face.SetCellEntry(code, layer, entry, page)
	if InCombatLockdown() then return nil, "out of combat only" end
	if not (CODE_KEY[code] and CELL_LAYER[layer]) then return nil, "unknown cell " .. tostring(code) .. " " .. tostring(layer) end
	if page ~= nil and not (type(page) == "number" and page >= 1 and page <= ns.Actions.STANDARD_PAGES and page % 1 == 0) then return nil, "unknown page " .. tostring(page) end
	if entry and not Face.Routable(code, layer, entry) then return nil, tostring(entry.name) .. " goes into this button's crossbar slot, not the router" end
	-- An addon's Lua key binding: restricted code can't run a binding command, and the layer is known only at the
	-- press, too late to bind the key to it.
	if entry and entry.disabled then return nil, entry.note end
	if entry and PADDLES[code] and not Face.PaddleFree(code) then return nil, "this paddle has a role; set its role to None to use it for actions" end
	local list = cells(true)
	if not list then return nil, "no controller found" end

	local row = list[code] or {}
	local new = entry and { id = entry.id, name = entry.name, icon = entry.icon, kind = ns.Actions.KindOf(entry) }
	-- A slot kind gets its shadow slot now (a full range is refused here); anything else gives the cell's slot back.
	-- With the Gamepad UI off, nothing is written; the next apply while it is on places or releases the slot.
	local Actions = ns.Actions
	if ns.Active() then
		local done, ok, err = pcall(function()
			if new and Actions.SLOT_KINDS[new.kind] then return Actions.Shadow(code, layer, new) end
			return Actions.ReleaseShadow(code, layer)
		end)
		if not done then return nil, "Controller Tweaks couldn't place the action: " .. tostring(ok) end
		if not ok then return nil, err end
	end
	-- After the shadow slot: a slot kind placed there had an empty cursor, so this can't fail half way.
	if new then
		local ok, err = clearUnder(code, layer, page)
		if not ok then return nil, err end
	end
	row[layer] = new
	list[code] = next(row) and row or nil
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
	return true
end

-- Healer mode on a cell (Rings.HealerRing): its entry gets healer = true and the cell opens a ring of the group. A cell
-- without an entry copies the spell or item in its crossbar slot on page (default 1) as an entry with native = true,
-- and that slot stays as it is: Off drops the copy, so the slot fires natively again. Fires FCT_LAYOUT_CHANGED("layout").
function Face.SetHealer(code, layer, on, page)
	if InCombatLockdown() then return nil, "out of combat only" end
	if not (CODE_KEY[code] and CELL_LAYER[layer]) then return nil, "unknown cell " .. tostring(code) .. " " .. tostring(layer) end
	if not ns.Rings then return nil, "Healer mode needs the Rings module (Forever Controller Tweaks - Rings) turned on." end
	local list = cells(true)
	if not list then return nil, "no controller found" end

	local row = list[code] or {}
	local entry = row[layer]
	if not entry and not on then return true end
	if not entry then
		local slot = storageSlot(code, layer, page or 1)
		local found = slot and ns.Actions.Find(ns.Actions.CurrentId(slot) or "")
		entry = found and { id = found.id, name = found.name, icon = found.icon, kind = ns.Actions.KindOf(found), native = true }
	end
	if on then
		local ok, err = ns.Rings.HealerAllowed(entry)
		if not ok then return nil, err end
	end

	local new = {}
	for key, value in pairs(entry) do new[key] = value end
	new.healer = on or nil
	if new.native and not on then new = nil end
	row[layer] = new
	list[code] = next(row) and row or nil
	ns.Fire("FCT_LAYOUT_CHANGED", "layout")
	return true
end

local APPLY_SNIPPET = ([[
	self:ClearBindings()
	local routed = self:GetAttribute("state-face") == "routed" and self:GetAttribute("ps-enabled")
	for i = 1, self:GetAttribute("ps-catchers") or 0 do
		local catcher = self:GetFrameRef("catcher" .. i)
		if catcher and routed and catcher:GetAttribute("ps-on") then catcher:Show() elseif catcher then catcher:Hide() end
	end
	-- Standing down (state change or ps-enabled off) ends any held press for Face.Pressed.
	if not routed then
		for i = 1, %d do
			local router = self:GetFrameRef("router" .. i)
			if router then router:SetAttribute("ps-curlayer", nil) end
		end
		return
	end
	for i = 1, %d do
		local key = self:GetAttribute("ps-key" .. i)
		if key then self:SetBindingClick(false, key, self:GetAttribute("ps-router" .. i), "LeftButton") end
	end
]]):format(#CODES, #CODES)
-- A state change drops a press in flight, so a later release can't go to the button it was aimed at.
local ONSTATE_SNIPPET = ([[
	for i = 1, %d do
		local router = self:GetFrameRef("router" .. i)
		if router then router:SetAttribute("ps-cur", nil) end
	end
]]):format(#CODES) .. APPLY_SNIPPET

local header = CreateFrame("Frame", "ForeverControllerTweaksFaceHeader", UIParent, "SecureHandlerStateTemplate")
local routers = {}
for i, code in ipairs(CODES) do
	local pos = CODE_POS[code]
	local name = "ForeverControllerTweaks" .. (pos and "Face" .. pos:gsub("^%l", string.upper) or ROUTER_NAME[code])
	local router = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	router:SetSize(1, 1)
	router:EnableMouse(false)
	router:RegisterForClicks("AnyDown", "AnyUp")
	routers[i] = router
end

-- Snippets and state drivers are protected calls, so they wait for the first out-of-combat apply.
local setUp
local function setup()
	if setUp then return end
	setUp = true

	header:Execute("OVERRIDE_KINDS = newtable('pet', 'stance'); TARGET_KINDS = newtable('shortcuts', 'friendly', 'hostile')")
	header:SetAttribute("_onstate-face", ONSTATE_SNIPPET)
	for _, override in ipairs(OVERRIDES) do RegisterStateDriver(header, override.kind, override.condition .. " on; off") end
	for i, router in ipairs(routers) do
		router:SetAttribute("ps-pos", CODE_POS[CODES[i]] or CODES[i])
		-- A dynamic ring aims with the stick of the hand that isn't on the button (Rings.lua); a paddle, like a
		-- D-pad button, with the right one.
		router:SetAttribute("ps-kind", CODE_POS[CODES[i]] and "face" or PADDLES[CODES[i]] and "paddle" or "dpad")
		router:SetAttribute("type", "macro")
		router:SetAttribute("typerelease", "macro")
		router:SetAttribute("pressAndHoldAction", true)
		header:WrapScript(router, "OnClick", ROUTER_SNIPPET)
		header:SetAttribute("ps-router" .. i, router:GetName())
		SecureHandlerSetFrameRef(header, "router" .. i, router)
	end
end

-- The ring arms the router by name: RunAttribute can't carry a frame handle. On the first apply with the Rings
-- module loaded, which may come after setup: an apply can run while the core loads, before any module.
local ringsLinked
local function linkRings()
	if ringsLinked or not ns.Rings then return end
	ringsLinked = true
	for _, router in ipairs(routers) do
		SecureHandlerSetFrameRef(router, "rings", ns.Rings.Frame())
		SecureHandlerSetFrameRef(ns.Rings.Frame(), router:GetName(), router)
	end
end

-- The per-press route line costs an insecure hook on every press, so it exists only once debug was on and the
-- snippet writes ps-route only while it is on.
local hooked
local function syncDebug()
	local on = ns.db and ns.db.options.debug or nil
	if on and not hooked then
		hooked = true
		for _, router in ipairs(routers) do
			router:HookScript("OnAttributeChanged", function(_, name, value)
				if name == "ps-route" then ns.debug("face %s combat=%s", value, tostring(InCombatLockdown())) end
			end)
		end
	end
	for _, router in ipairs(routers) do router:SetAttribute("ps-debug", on) end
end

local function bars()
	local frame = GamepadMainActionBarFrame
	return frame and frame.PageUnit and frame.PageUnit.actionBars
end

local function button(actionBars, barKey, slot)
	local bar = actionBars[barKey]
	return bar and bar.actionButtons and bar.actionButtons[slot]
end

-- The reserved top-bar button a face action ("jump", "back"...) clicks, or nil without the Gamepad action bars.
function Face.ActionButton(action)
	local actionBars = bars()
	return actionBars and ACTION_SLOT[action] and button(actionBars, "topBar", ACTION_SLOT[action])
end

-- Click catchers: our own secure button over each crossbar slot that shows a routed cell, so a mouse click, hover
-- and gamepad focus reach the routed action. A child of the native slot button: it follows its visibility, scale
-- and press dent, and sits one frame level above it (a child's default level). Made and set out of combat; shown by the header's snippets
-- only while routed. Keyed "code/layer".
local catchers, catcherCount, shadowOf = {}, 0, {}

-- Blizzard's tooltip for an action button (ActionBarActionButtonMixin:SetTooltip), on the shadow slot.
local function catcherTooltip(self)
	if not self.shadow then return end
	if GetCVar("UberTooltips") == "1" then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
	self.UpdateTooltip = GameTooltip:SetAction(self.shadow) and catcherTooltip or nil
end

local function catcherLeave(self)
	self.UpdateTooltip = nil
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function catcherFor(actionBars, code, layer, slot)
	local key = code .. "/" .. layer
	local catcher = catchers[key]
	if InCombatLockdown() then return catcher end
	local target = button(actionBars, CELL_BAR[layer], slot)
	if not target then return catcher end
	-- The key's native slot moved (a rebind, or the assumed slot before the bindings could be read).
	if catcher then
		if catcher:GetParent() ~= target then
			catcher:SetParent(target)
			catcher:ClearAllPoints()
			catcher:SetAllPoints(target)
		end
		return catcher
	end

	catcher = CreateFrame("Button", "ForeverControllerTweaksCatcher" .. code .. layer, target, "SecureActionButtonTemplate")
	catcher:SetAllPoints(target)
	catcher:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")
	catcher:SetScript("OnEnter", catcherTooltip)
	-- A post-hook on our own frame: one debug line per mouse click, to tell a catcher click from a pad press.
	catcher:HookScript("OnClick", function(self, mouseButton, down)
		if not ns.db.options.debug then return end
		ns.debug("face catcher %s/%s %s %s: %s", code, layer, mouseButton, down and "down" or "up", tostring(self:GetAttribute("type") == "action" and "action " .. tostring(self:GetAttribute("action")) or self:GetAttribute("macrotext")))
	end)
	catcher:SetScript("OnLeave", catcherLeave)
	catcher:Hide()
	catcherCount = catcherCount + 1
	SecureHandlerSetFrameRef(header, "catcher" .. catcherCount, catcher)
	header:SetAttribute("ps-catchers", catcherCount)
	catchers[key] = catcher
	return catcher
end

-- route = { how, value } as the router runs it, or nil to stand the catcher down.
-- A face action's reserved button acts on press (Jump, Back, Interact) or release (Inspect), and a "click" type only
-- sends the release, so the catcher clicks it down and up, as Actions' game commands do.
local function aimCatcher(catcher, route, actionBars)
	local how, value = route and route[1], route and route[2]
	local click = how == "click" and button(actionBars, "topBar", ACTION_SLOT[value])
	local name = click and click:GetName()
	-- A hold action's button, clicked once from a catcher: its toggle (RightButton).
	local text = name and Face.ClickBoth(name) or how == "text" and value or how == "hold" and "/click " .. value .. " RightButton" or nil
	catcher:SetAttribute("type", how == "action" and "action" or text and "macro" or nil)
	catcher:SetAttribute("typerelease", how == "action" and "actionrelease" or nil)
	catcher:SetAttribute("action", how == "action" and value or nil)
	catcher:SetAttribute("macrotext", text)
	for _, check in ipairs(Face.CHECK_CASTS) do catcher:SetAttribute(check, how == "action" or nil) end
	catcher:SetAttribute("ps-on", how and true or nil)
	catcher.shadow = how == "action" and value or nil
end

-- The layer ("top", "left", "right", "bottom") an override bar replaces per its CVar, false for None, nil when unknown.
local function overrideLayer(cvar)
	local enum, value = Enum[cvar], tonumber(GetCVar(cvar))
	if not (enum and value) then return nil end

	for name, v in pairs(enum) do
		if v == value then
			if name == "None" then return false end
			local where = name:match("(%u%l+)Bar$")
			return where and where:lower()
		end
	end
end

local function sameFace(face)
	for pos, action in pairs(Layout.NATIVE_FACE) do
		if face[pos] ~= action then return false end
	end
	return true
end

-- GetGamePadState().buttons indexes of the crossbar modifiers, { leftmod, rightmod }; Touch.lua picks layers by them too.
local function modifierIndexes()
	local out = {}
	for _, role in ipairs(MOD_ROLES) do
		local index = C_GamePad.ButtonBindingToIndex(Layout.RoleKey(role))
		out[role] = index and index + 1
	end
	return out
end
Face.ModifierIndexes = modifierIndexes

-- How a routed cell runs: ("click", face action), ("hold", our hold button's name: clicked down on the press and up
-- on the release, like a face action), ("ring", ring id, a healer ring's too) or ("text", secure macro text); nil
-- when the entry no longer resolves, and for a Healer mode copy without the Rings module (its slot fires natively).
local function resolve(entry)
	local healer = entry.healer and ns.Rings and ns.Rings.HealerRing(entry)
	if healer then return "ring", healer end
	if entry.native then return end
	local action = tostring(entry.id):match("^face:(%a+)$")
	if action then return ACTION_SLOT[action] and "click", action end
	local hold = tostring(entry.id):match("^hold:(%a+)$")
	if hold then
		local name = ns.Actions and ns.Actions.HoldButton(hold)
		return name and "hold", name
	end
	local ring = tonumber(tostring(entry.id):match("^ring:(%d+)$"))
	if ring then
		if ns.Rings and ns.Rings.Get(ring) then return "ring", ring end
		return
	end
	local text = entryText(entry)
	if text then return "text", text end
end

-- Writes one router's targets (unresolved collects the override kinds it could not resolve); returns the key's slot
-- in a bar, nil for a paddle: it has none, so it has no native target, no targeting layer and no override bar.
local function aim(router, actionBars, code, action, routes, mods, unresolved)
	local slot = not PADDLES[code] and nativeSlot(CODE_KEY[code]) or nil
	for layer, barKey in pairs(BARS) do
		local target = slot and button(actionBars, barKey, slot)
		router:SetAttribute("ps-" .. layer, target and target:GetName() or nil)
		if TARGET_LAYERS[layer] and target then SecureHandlerSetFrameRef(router, "bar-" .. layer, target) end
		-- The snippet reads the slot a native target fires, to run a macro there without /click.
		if target then SecureHandlerSetFrameRef(router, "slot-" .. layer, target) end
	end
	-- Top: a face button's chosen face action, a D-pad button's own top-bar slot.
	local top = slot and button(actionBars, "topBar", action and ACTION_SLOT[action] or slot)
	router:SetAttribute("ps-top", top and top:GetName() or nil)
	-- A face button's top target is a reserved button: its scripts act, not a slot.
	if top and not action then SecureHandlerSetFrameRef(router, "slot-top", top) end
	for cellLayer, route in pairs(routes) do
		if route[1] == "click" then
			local target = button(actionBars, "topBar", ACTION_SLOT[route[2]])
			router:SetAttribute("ps-" .. CELL_LAYER[cellLayer], target and target:GetName())
		elseif route[1] == "hold" then
			router:SetAttribute("ps-" .. CELL_LAYER[cellLayer], route[2])
		end
	end
	for role, index in pairs(mods) do router:SetAttribute("ps-i" .. role, index) end

	for _, override in ipairs(slot and OVERRIDES or {}) do
		local kind, layer = override.kind, overrideLayer(override.cvar)
		local target = layer and button(actionBars, override.bar, slot)
		if layer and not (target and target:IsProtected()) then layer = nil end
		if layer == nil then unresolved[kind] = true end
		router:SetAttribute("ps-" .. kind .. "layer", layer or nil)
		if layer then SecureHandlerSetFrameRef(router, kind, target) end
	end
	return slot
end

local driver, summary, retries, refresh = nil, "not applied yet", 0, nil

-- Back and Inspect used to be PS: game macros (Actions.LEGACY_FACE). Once per character, with the Gamepad UI on and
-- out of combat: routed cells with the old id become the face action, and crossbar slots holding the old macro become
-- routed cells (on every page, as routed cells are) and are cleared, so the registry deletes the macro.
-- The 96 slots are scanned once; a write that failed (Clear, ReleaseShadow) is kept in legacyLeft for the session and
-- only those are tried again on the next applies, so the scan and its chat lines don't repeat.
local legacyLeft

local function retryLegacy(Actions)
	for what, cell in pairs(legacyLeft) do
		local ok = type(cell) == "table" and Actions.ReleaseShadow(cell[1], cell[2]) or type(cell) ~= "table" and Actions.Clear(what)
		if ok then legacyLeft[what] = nil end
	end
	return next(legacyLeft) == nil
end

local function migrateLegacyFace(char)
	local Actions, list = ns.Actions, cells(true)
	local legacy = Actions.LEGACY_FACE
	if not (legacy and list) then return false end
	if legacyLeft and next(legacyLeft) then return retryLegacy(Actions) end

	legacyLeft = {}
	local function faceEntry(oldID)
		local entry = Actions.Find(legacy[oldID])
		return entry and { id = entry.id, name = entry.name, icon = entry.icon, kind = "face" }
	end
	local changed = false
	for code, row in pairs(list) do
		for layer, entry in pairs(row) do
			if legacy[entry.id] then
				row[layer], changed = faceEntry(entry.id) or entry, true
				if not Actions.ReleaseShadow(code, layer) then legacyLeft[code .. "/" .. layer] = { code, layer } end
			end
		end
	end
	local util = GamepadActionBarBindingUtil
	local storage = util and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID
	for page = 1, storage and Actions.STANDARD_PAGES or 0 do
		for _, code in ipairs(CODES) do
			for layer, barIndex in pairs(not PADDLES[code] and BAR_INDEX or {}) do
				local ok, slot = pcall(storage, page, (barIndex - 1) * Actions.PER_BAR + nativeSlot(CODE_KEY[code]))
				local oldID = ok and slot and Actions.CurrentId(slot)
				-- An unregistered PS: macro from an older build is taken on only when its body is the addon's own.
				if ok and slot and not legacy[oldID] then
					local adopted, foreign = Actions.AdoptLegacy(slot)
					oldID = adopted
					if foreign then ns.log(("your macro %s on page %d (%s, %s bar) isn't one Controller Tweaks wrote, so it was left as is. To route %s there, pick it again in the Bindings window (/fct)."):format(foreign, page, CODE_KEY[code], CELL_LAYER[layer], foreign:sub(4))) end
				end
				if oldID and legacy[oldID] then
					list[code] = list[code] or {}
					list[code][layer], changed = list[code][layer] or faceEntry(oldID), true
					if not Actions.Clear(slot) then legacyLeft[slot] = true end
					ns.debug("face: %s on page %d moved from a macro slot to a routed cell %s/%s", oldID, page, code, layer)
				end
			end
		end
	end
	-- Panel and glyphs redraw; the refresh it asks for is covered by the apply running now.
	if changed then ns.Fire("FCT_LAYOUT_CHANGED", "layout") end
	return next(legacyLeft) == nil
end

-- Once per character: cells routed before SetCellEntry emptied the slot underneath may still have a FCT: macro there.
local function clearUnderRouted()
	local list = cells()
	if not (list and GamepadActionBarBindingUtil) then return false end

	local done = true
	for code, row in pairs(list) do
		for layer, entry in pairs(row) do
			-- A Healer mode copy keeps its slot: Off gives the cell back to it.
			if not entry.native and not clearUnder(code, layer) then done = false end
		end
	end
	return done
end

-- ignorePanel: combat is starting and the settings screen closes in the same frame.
local function applyNow(ignorePanel)
	setup()
	linkRings()
	syncDebug()

	local face, actionBars = Layout.Face(), bars()
	local known = cells()
	local list = known or {}
	local enabled = ns.Active() and (ignorePanel or not ns.panelOpen) and (not sameFace(face) or next(list)) and actionBars and button(actionBars, "topBar", 5)
	local mods, unresolved, parts, short = modifierIndexes(), {}, {}, {}
	-- Shadow slots are written only with the Gamepad UI on (bars 6-8 are the player's otherwise), out of combat and
	-- not at combat start, and only with this pad's cells known: an unplugged or sleeping pad, or one without cells
	-- yet, keeps every slot and FCT: macro as they are.
	local Actions = ns.Actions
	local writable = known and Actions and ns.Active() and not ignorePanel and not InCombatLockdown()
	if writable then
		ns.MigrateChar("legacyFaceDone", migrateLegacyFace)
		ns.MigrateChar("routedUnderDone", clearUnderRouted)
	end
	for i, code in ipairs(CODES) do
		local router, key, pos, row = routers[i], CODE_KEY[code], CODE_POS[code], list[code] or {}
		local action, label, routes = pos and face[pos], pos or code, {}
		-- A paddle with a role keeps its cells, unrouted and without shadow slots, until it is freed again.
		local carried = not PADDLES[code] or Face.PaddleFree(code)
		for _, cellLayer in ipairs(CELL_LAYERS) do
			local entry = carried and row[cellLayer] or nil
			local how, value
			if entry then how, value = resolve(entry) end
			-- A slot kind fires its shadow slot; placed now unless combat starts (else it stays macro text).
			local slotKind = entry and Actions and Actions.SLOT_KINDS[Actions.KindOf(entry)]
			if how == "text" and slotKind then
				local slot = Actions.ShadowSlot(code, cellLayer, entry.id)
				if not slot and writable then slot = Actions.Shadow(code, cellLayer, entry) end
				if slot then how, value = "action", slot end
			end
			-- A cell that no longer holds a slot kind gives its shadow slot back.
			if writable and not slotKind then Actions.ReleaseShadow(code, cellLayer) end
			local where = label .. (cellLayer == "T" and "" or "/" .. cellLayer)
			if how then routes[cellLayer] = { how, value, entry.name } end
			if entry and not how then parts[#parts + 1] = string.format("%s entry %s unavailable", where, tostring(entry.id)) end
		end
		local moved = enabled and (next(routes) or (pos and action ~= Layout.NATIVE_FACE[pos]))
		local slot = moved and aim(router, actionBars, code, action, routes, mods, unresolved)
		for cellLayer, layer in pairs(CELL_LAYER) do
			local route = routes[cellLayer]
			local how = moved and route and route[1]
			router:SetAttribute("ps-entry-" .. layer, how == "text" and route[2] or nil)
			router:SetAttribute("ps-action-" .. layer, how == "action" and route[2] or nil)
			router:SetAttribute("ps-ring-" .. layer, how == "ring" and route[2] or nil)
			shadowOf[code .. "/" .. cellLayer] = route and route[1] == "action" and route[2] or nil
			-- A moved face action on the base layer is a routed cell too.
			local shown = how and route or slot and cellLayer == "T" and pos and action ~= Layout.NATIVE_FACE[pos] and { "click", action }
			local catcher = shown and slot and catcherFor(actionBars, code, cellLayer, slot) or catchers[code .. "/" .. cellLayer]
			if catcher then aimCatcher(catcher, shown or nil, actionBars) end
		end
		header:SetAttribute("ps-key" .. i, moved and key or nil)
		-- An open ring binds A and B but the key that opened it.
		router:SetAttribute("ps-key", moved and key or nil)
		if moved then
			local cellParts = {}
			for _, cellLayer in ipairs(CELL_LAYERS) do
				local route = routes[cellLayer]
				local what = route and route[3] or cellLayer == "T" and pos and action ~= Layout.NATIVE_FACE[pos] and action
				if what then cellParts[#cellParts + 1] = (cellLayer == "T" and key or key .. "/" .. cellLayer) .. "=" .. what end
			end
			for _, part in ipairs(cellParts) do short[#short + 1] = part end
			parts[#parts + 1] = string.format("%s(%s%s) %s", label, key, slot and ", slot " .. slot or "", table.concat(cellParts, " "))
		end
	end

	-- An override bar whose layer can't be resolved sends the routed keys back to native while it can be active.
	local native = ""
	for _, override in ipairs(OVERRIDES) do
		if unresolved[override.kind] then native = native .. override.condition end
	end
	local states = GUARD .. (native ~= "" and native .. " native; " or "") .. "routed"
	header:SetAttribute("ps-enabled", not not enabled)
	if states ~= driver then RegisterStateDriver(header, "face", states) end
	driver = states

	header:Execute(APPLY_SNIPPET)
	summary = (enabled and "routed " or "off ") .. (#short > 0 and table.concat(short, " ") or "nothing moved")
	-- Shown in /fct status: the keys go back to native while that bar can be up.
	for _, override in ipairs(OVERRIDES) do
		if enabled and unresolved[override.kind] then summary = summary .. ("; %s bar unresolved: moved actions pause while %s"):format(override.kind, override.condition) end
	end
	Face.paused = enabled and (unresolved.pet and "pet" or unresolved.stance and "stance") or nil
	-- The bars can appear a few frames after the Gamepad UI turns on.
	if not actionBars and ns.Active() and retries < BAR_RETRIES and C_Timer.After then
		retries = retries + 1
		C_Timer.After(0, refresh)
	end
	if not actionBars then ns.debug("face: Gamepad action bars not found (gamepad UI off?)") end
	ns.debug("face %s: %s; states %s", enabled and "routed" or "off", #parts > 0 and table.concat(parts, " ") or "nothing moved", states)
end

-- A Lua error must not leave busy set (it would freeze the router until /reload). Each one goes to the debug log; the
-- first after a working apply also gets one chat line, and the next apply runs normally.
local failed
local function apply(ignorePanel)
	if busy or (ns.Actions and ns.Actions.Busy()) then return end
	busy = true
	local ok, err = pcall(applyNow, ignorePanel)
	busy = false
	if ok then
		failed = nil
		return
	end

	local message = tostring(err):match("^[^\n]*"):gsub("^.-([%w_]+%.lua:%d+:)", "%1")
	ns.debug("face apply failed: %s", tostring(err))
	if not failed then ns.log("button routing skipped an update after an error (/reload to retry): " .. message) end
	failed = true
end

-- A short state for /fct selftest, e.g. "routed PAD1=interact PAD3=jump PADDUP/L=jump, state routed".
function Face.State()
	local shown = 0
	for _, catcher in pairs(catchers) do
		if catcher:GetAttribute("ps-on") then shown = shown + 1 end
	end
	local shadow = ns.Actions and ns.Actions.ShadowState and ns.Actions.ShadowState() or "none"
	return string.format("%s, state %s, shadow %s, catchers %d", summary, tostring(header:GetAttribute("state-face")), shadow, shown)
end

-- The shadow action slot a routed cell fires, or nil (as of the last apply).
function Face.Slot(code, layer) return shadowOf[code .. "/" .. tostring(layer)] end

-- True while this key's router is held down and its press went to this layer (T/L/R/B); a stance or pet bar that
-- took the press, a state change and a stand-down all read false. Readable in combat. Glyphs presses its mirror by it.
function Face.Pressed(code, layer)
	for i, c in ipairs(CODES) do
		if c == code then return CELL_LAYER[layer] ~= nil and routers[i]:GetAttribute("ps-curlayer") == CELL_LAYER[layer] end
	end
	return false
end

-- The click catcher over a routed cell's crossbar slot, or nil while it has none.
function Face.Catcher(code, layer)
	local catcher = catchers[code .. "/" .. tostring(layer)]
	return catcher and catcher:GetAttribute("ps-on") and catcher or nil
end

-- Applies now when the pad is free, so the queue isn't used for nothing.
function refresh()
	if not InCombatLockdown() and ns.padFree() then return apply() end
	ns.whenPadFree("face router", apply)
end

-- The settings screen owns the pad while open.
ns.On("FCT_PANEL_OPEN", function() refresh() end)

-- /fct debug on|off adds or drops the per-press route line.
local debugCommand = ns.commands.debug
function ns.commands.debug(args)
	debugCommand(args)
	refresh()
end

-- Registered before the refresh handlers below, so they read the new cells.
local function dropCells() cellCache = nil end
ns.On("PLAYER_ENTERING_WORLD", dropCells)
ns.On("FCT_LAYOUT_CHANGED", dropCells)
ns.On("FCT_ACTIVE_CHANGED", dropCells)
ns.On("PLAYER_ENTERING_WORLD", refresh)
ns.On("FCT_ACTIVE_CHANGED", function()
	retries = 0
	refresh()
end)
-- Fires synchronously before the lockdown starts: the last chance to apply for the fight.
ns.On("FCT_COMBAT_START", function() if ns.padFree() then apply(true) end end)
-- Closing a Blizzard window clears its SetOverrideBinding(UIParent, false, key, "") masks, which can leave ours
-- masked too; binding again restores them (out of combat; in combat it waits for the end).
ns.On("FCT_PAD_FREE", function(free) if free then refresh() end end)
-- Actions.lua clears its spellbook cache first, then sends this.
ns.On("FCT_CATALOG_CHANGED", function(event)
	local list = ns.Actions.TEXT_EVENTS[event] and cells()
	if list and next(list) then refresh() end
end)
ns.On("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED", refresh)
ns.On("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED", refresh)
-- "remap" only reports which config is applied; the router reads native key names either way.
ns.On("FCT_LAYOUT_CHANGED", function(reason) if reason ~= "remap" then refresh() end end)
