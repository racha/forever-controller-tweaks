-- Forever Controller Tweaks "Tweaks" side tab, in the Keyboard tab's language: the hint in the header, four insets
-- with section headers (Bags & vendors and Quests & NPCs; Rumble; Controller; Loot & gear and Group & social), one
-- value per row: a checkbox (A toggles; left/right move between the columns), a dropdown (left/right step it, A rounds
-- it) or a slider (left/right step it). A dropdown or slider at its end hands left/right back, so the next press moves
-- to the next column: the Rumble column is never a dead end. Y opens More (Undo, Learn, the minimap button...).
-- Everything goes through ns.Tweaks (Tweaks.lua): Get / Set, saved in ForeverControllerTweaksDB.tweaks. The Settings
-- tab (Panel/SettingsTab.lua) uses the same insets and rows: its geometry is S.GEO.
local _, ns = ...
local UI = ns.UI
local L = UI.L

local S = {}
UI.TweaksTab = S

local T = {
	TAB = "Tweaks", TITLE = "Controller Tweaks · Tweaks", HINT = "Small conveniences for every character. Most are off until you turn them on.",
	TEST = "Test", BAGS = "Bags & vendors", NPCS = "Quests & NPCs", SOCIAL = "Group & social", CONTROLLER = "Controller", GEAR = "Loot & gear",
	RUMBLE = "Rumble", CAMERA = "Camera", YARDS = "%d yd",
	CHOICES = {
		lightBar = { default = "Game default", class = "Class colour", custom = "Custom" },
		-- The stick presses by this pad's own glyph names (L3 / LS).
		sortKey = setmetatable({ off = "Off" }, { __index = function(_, code) return UI.Name(code) end }),
		pattern = {
			off = "Off", tap = "Tap", double = "Double tap", triple = "Triple tap", long = "Long buzz", heartbeat = "Heartbeat",
			ramp = "Ramp up", fade = "Fade out",
		},
		lightColor = {
			red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", teal = "Teal", cyan = "Cyan", blue = "Blue",
			purple = "Purple", pink = "Pink", white = "White",
		},
	},
	ROWS = {
		sortBags = { "Sort bags button", "A Sort button on your bags. With the controller: Clean Up in the bag menu, or the picker\'s Sort bags action." },
		sortKey = { "Sort bags key", "While your bags are open, this stick press sorts them. Bags closed: it works as usual. L3 (default), R3 or Off." },
		sellJunk = { "Sell junk", "Sells your grey items when you talk to a merchant." },
		repair = { "Repair", "Repairs your gear when you talk to a merchant who repairs." },
		repairGuild = { "Use guild funds first", "Pays from the guild bank when the guild allows it, else from your own money." },
		buyStack = { "Buy a full stack", "A Stack button on stackable merchant items. The picker's action buys the item under the cursor." },
		skipGossip = { "Skip one-option talk", "Picks the only thing an NPC offers: a single quest, or a vendor, trainer, flight map or bank. Never a teleport, an event or one that costs money." },
		learnAll = { "Trainer: Learn all", "A Learn all button on the trainer for every skill you can afford." },
		openMail = { "Mail: Open all", "An Open all button on the mailbox. Skips cash-on-delivery mail and stops when your bags are full." },
		acceptInvites = { "Accept friend & guild invites", "Joins a group when a friend, Battle.net friend or guild member invites you. Never one that would drop your queue." },
		declineDuels = { "Decline duels", "Turns down every duel request." },
		acceptRes = { "Accept resurrect and summon", "Out of combat: any resurrection without sickness, and a summon from a friend or guild member, never inside an instance." },

		whisperAlert = { "Whisper alert", "A card with who whispered you and how the message starts. Rumbles too if Rumble is on." },
		lightBar = { "Light bar", "Your class colour or a colour you pick. Light-bar pads only; Steam may take it over." },
		lightColor = { "Colour", "The light bar's colour when Light bar is Custom." },
		combatFlash = { "Combat flash", "The light bar turns red while you are in combat." },
		rumble = { "Rumble on events", "The controller rumbles for the events below, each group with its own pattern." },
		rumbleStrength = { "Strength", "How strong every rumble is." },
		["rumble:group"] = { "Group", "A ready check, group invite, summon or resurrection offer." },
		["rumble:whisper"] = { "Whisper", "Someone whispers you." },
		["rumble:tradeDuel"] = { "Trade & duel", "A trade or duel request." },
		["rumble:danger"] = { "Danger", "You die, get stunned or feared, gain aggro, or your cast is interrupted." },
		["rumble:enemy"] = { "Enemies", "An enemy-faction player's name plate shows. Needs enemy name plates on (Options, Nameplates)." },
		["rumble:rare"] = { "Rare nearby", "A rare shows on the minimap or by its name plate." },
		["rumble:levelUp"] = { "Level ups", "You gain a level or earn an achievement." },
		["rumble:procs"] = { "Procs", "A spell on your bars lights up, your target dies, or you land a critical strike (solo)." },
		battery = { "Low battery warning", "One chat line when the controller's battery runs low." },
		batteryIcon = { "Battery on the minimap", "A round button on the minimap's ring, next to the others, with the controller's charge. Hidden for pads that don't report one." },
		rareAlert = { "Rare nearby alert", "A line on screen and a rumble when a rare is near. Once per rare, never in a fight." },
		fastLoot = { "Fast loot", "Takes all loot at once. Bind-on-pickup items still ask; with full bags only coins are taken." },
		passUnusable = { "Pass on unusable rolls", "Passes loot rolls on armor or weapons your class can never use. When unsure, you roll." },
		upgradeArrows = { "Upgrade arrows", "A green arrow on gear you can wear with a higher item level than what you wear there." },
		wearRewards = { "Wear quest rewards", "After a quest, an upgrade reward gets a card: hold the top face button to wear it." },
		cameraZoom = { "Camera zoom", "Where the camera sits. Moving it zooms now; the camera goes back here when you log in." },
	},
}
S.T = T

-- Four insets, 12 apart; rows 8 inside them. Each control ends CONTROL_END in from its row's left: a checkbox, a
-- dropdown (its value CHOICE_W wide, with its steppers) or a slider (SLIDER_W, its value text after it).
local X, TOP, INSET_W, INSET_H, HEADER_W = { 24, 315, 606, 897 }, 84, 279, 526, 197
local ROW_W, ROW_H, ROW_PITCH, SUB_INDENT, CONTROL_END, CHOICE_W, SLIDER_W, SLIDER_TEXT = 263, 28, 44, 24, 255, 100, 110, 36
S.GEO = { X = X, TOP = TOP, INSET_W = INSET_W, INSET_H = INSET_H, HEADER_W = HEADER_W, ROW_W = ROW_W, ROW_H = ROW_H, ROW_PITCH = ROW_PITCH, CONTROL_END = CONTROL_END, CHOICE_W = CHOICE_W }
local RUMBLE_ROWS = { "rumble", "rumbleStrength" }
for _, group in ipairs(ns.Tweaks.RUMBLE_GROUPS) do RUMBLE_ROWS[#RUMBLE_ROWS + 1] = "rumble:" .. group end
local COLUMNS = {
	{ side = "right", sections = { { T.BAGS, { "sortBags", "sortKey", "sellJunk", "repair", "repairGuild", "buyStack" } }, { T.NPCS, { "skipGossip", "learnAll", "openMail" } } } },
	{ side = "right", sections = { { T.RUMBLE, RUMBLE_ROWS } } },
	{ side = "left", sections = { { T.CONTROLLER, { "battery", "batteryIcon", "rareAlert", "lightBar", "lightColor", "combatFlash" } }, { T.CAMERA, { "cameraZoom" } } } },
	{ side = "left", sections = { { T.GEAR, { "fastLoot", "passUnusable", "upgradeArrows", "wearRewards" } }, { T.SOCIAL, { "acceptInvites", "declineDuels", "acceptRes", "whisperAlert" } } } },
}
-- A sub-row: its label is indented. A row in IDLE greys while the row above doesn't use it.
local INDENT = { repairGuild = true, lightColor = true, rumbleStrength = true }
local IDLE = {
	repairGuild = function(get) return not get("repair") end,
	lightColor = function(get) return get("lightBar") ~= "custom" end,
	rumbleStrength = function(get) return not get("rumble") end,
}

local window
local rows = {}
-- A rumble group's row: its pattern (Off included), saved per group. A on it plays that pattern once; A on Strength
-- plays a Double tap at the strength, Rumble on events on or not. A press while one plays restarts it: patterns
-- never stack. The group rows grey while Rumble on events is off.
local CUSTOM, TEST = {}, {}
for _, group in ipairs(ns.Tweaks.RUMBLE_GROUPS) do
	local key = "rumble:" .. group
	CUSTOM[key] = {
		options = function() return ns.Tweaks.PATTERN_ORDER end,
		get = function() return ns.Tweaks.RumblePattern(group) end,
		set = function(v) ns.Tweaks.SetRumbleGroup(group, v) end,
	}
	TEST[key] = function() ns.Tweaks.Rumble(group, true) end
	IDLE[key] = function(get) return not get("rumble") end
	T.CHOICES[key] = T.CHOICES.pattern
end
TEST.rumbleStrength = function() ns.Tweaks.PlayPattern("double", nil, "test strength") end
-- Camera zoom: the saved distance, else where the camera is now; up to the game's limit, read when the tab opens.
CUSTOM.cameraZoom = {
	range = function() return { 0, ns.Tweaks.CameraMax(), 1 } end,
	get = function() return math.floor((ns.Tweaks.Get("cameraZoom") or ns.Tweaks.CameraNow() or 0) + 0.5) end,
	set = function(v) ns.Tweaks.Set("cameraZoom", math.min(v, ns.Tweaks.CameraMax())) end,
	text = function(v) return T.YARDS:format(v) end,
}

local function get(key)
	local custom = CUSTOM[key]
	if custom then return custom.get() end
	return ns.Tweaks.Get(key)
end
local function optionsOf(key) return CUSTOM[key] and CUSTOM[key].options and CUSTOM[key].options() or ns.Tweaks.CHOICES[key] end
local function rangeOf(key) return CUSTOM[key] and CUSTOM[key].range and CUSTOM[key].range() or ns.Tweaks.NUMBERS[key] end

local function set(key, value)
	if CUSTOM[key] then CUSTOM[key].set(value) else ns.Tweaks.Set(key, value) end
	window:Refresh()
end

local function toggle(key) set(key, not get(key)) end

-- One step through a choice's options; false past an end (nothing changes), round with wrap (A).
local function step(key, by, wrap)
	local options, index = optionsOf(key), 1
	for i, option in ipairs(options) do if option == get(key) then index = i end end
	local option = options[wrap and (index + by - 1) % #options + 1 or index + by]
	if not option then return false end
	set(key, option)
end

-- One step of a number within its range; false past an end.
local function nudge(key, by)
	local range = rangeOf(key)
	local value = math.floor((get(key) + by * range[3]) / range[3] + 0.5) / (1 / range[3])
	if value < range[1] or value > range[2] then return false end
	set(key, value)
end

local function percent(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end
local function valueText(key, value) return CUSTOM[key] and CUSTOM[key].text and CUSTOM[key].text(value) or percent(value) end

local function newRow(x, y, key)
	local row = CreateFrame("Button", nil, window)
	row:SetSize(ROW_W, ROW_H)
	UI.At(row, window, x + (INSET_W - ROW_W) / 2, y)
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetColorTexture(1, 1, 1, 0.1)
	row.wash:SetAllPoints()
	row.wash:Hide()
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT", INDENT[key] and 10 + SUB_INDENT or 10, 0)
	row.label:SetText(T.ROWS[key][1])
	local range = rangeOf(key)
	if optionsOf(key) then
		row.control = UI.Dropdown(row, CHOICE_W, function(by, wrap) step(key, by, wrap) end)
	elseif range then
		row.control = UI.Slider(row, SLIDER_W, range[1], range[2], range[3], function(by) return nudge(key, by) end, function(value) set(key, value) end)
	else
		row.control = UI.Checkbox(row, function() toggle(key) end)
	end
	local width = range and SLIDER_W + SLIDER_TEXT or row.control:GetWidth()
	row.control:SetPoint("LEFT", row, "LEFT", CONTROL_END - width, 0)
	row.key = key
	return row
end

local function prompts() return { { "PAD1", L.SELECT }, { "PAD4", L.MORE }, UI.TabPrompt("tweaks", -1), { "PAD2", L.CLOSE } } end

local function node(row, key, tip)
	local options, range, value, test = optionsOf(key), rangeOf(key), get(key), TEST[key]
	local function focus(focused)
		row.wash:SetShown(focused)
		if row.control.SetFocused then row.control:SetFocused(focused) end
	end
	if options then
		for i, option in ipairs(options) do if option == value then row.control:Set(T.CHOICES[key][option], i == 1, i == #options) end end
		tip.lines[2] = L.CHOICE_TIP
		if test then tip.actions = { { "PAD1", T.TEST } } end
		return UI.Node(window, row, function() if test then test() else step(key, 1, true) end end, { cursorX = 0, onDir = function(by) return step(key, by) end, tip = tip, onFocus = focus })
	end
	if range then
		row.control:Set(value, valueText(key, value))
		tip.lines[2] = L.STEPPER_TIP
		if test then tip.actions = { { "PAD1", T.TEST } } end
		return UI.Node(window, row, function() if test then test() end end, { cursorX = 0, onDir = function(by) return nudge(key, by) end, tip = tip, onFocus = focus })
	end
	row.control:Set(value)
	return UI.Node(window, row, function() toggle(key) end, { cursorX = 0, onFocus = focus, tip = tip })
end

local function refresh()
	local nodes = {}
	for _, column in ipairs(COLUMNS) do
		for _, section in ipairs(column.sections) do
			for _, key in ipairs(section[2]) do
				local row = rows[key]
				row.label:SetFontObject(IDLE[key] and IDLE[key](ns.Tweaks.Get) and "GameFontDisable" or "GameFontNormal")
				nodes[#nodes + 1] = node(row, key, { title = T.ROWS[key][1], lines = { T.ROWS[key][2] }, side = column.side })
			end
		end
	end
	window:SetNodes(nodes)
	if not UI.DialogShown() then window:SetPrompts(prompts()) end
end

local function build()
	local geo = UI.Bindings.GEO
	local index
	for i, spec in ipairs(UI.TABS) do if spec.tweaks then index = i end end
	window = UI.NewWindow(geo.WIDTH, geo.HEIGHT)
	window.tabs = UI.SideTabs(window, UI.TABS, index)
	window:SetTitle(T.TITLE)
	UI.Text(window, "GameFontDisableSmall", 24, 33, T.HINT)
	for i, column in ipairs(COLUMNS) do
		local x = X[i]
		UI.Inset(window, x, TOP, INSET_W, INSET_H)
		local y = TOP + 12
		for _, section in ipairs(column.sections) do
			UI.SectionHeader(window, x + (INSET_W - HEADER_W) / 2, y, HEADER_W, section[1])
			y = y + 50
			for _, key in ipairs(section[2]) do
				rows[key] = newRow(x, y, key)
				y = y + ROW_PITCH
			end
			y = y + 12
		end
	end

	window.OnRefresh = refresh
	window.OnFocusChanged = function() if not UI.DialogShown() then window:SetPrompts(prompts()) end end
	window.OnBack = function() UI.CloseAll() end
	window.OnKey = function(_, key)
		if key ~= "PAD4" then return end
		UI.OpenMore(window)
		return true
	end

end

function S.Open()
	if not ns.db then return end
	if not window then build() end
	UI.Show(window)
end

-- After the modules' tabs (Bindings, Touch, Keyboard, Rings, of those loaded), before Settings.
UI.AddTab({ "Interface\\Icons\\INV_Misc_Wrench_01", T.TAB, function() S.Open() end, tweaks = true, order = 5, prompt = T.TAB })
