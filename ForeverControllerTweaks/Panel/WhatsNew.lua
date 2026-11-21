-- Forever Controller Tweaks "What's new" (design/whats-new.md): a one-time window after an update with the changelog
-- notes since the version the player last saw (ns.NEWS, generated into News.lua by tools/make_news.py).
--
-- State, account-wide: ns.db.news = { seen = "x.y.z", never = true | nil }. A first install records the running
-- version and shows nothing; an existing player without the key starts as having seen NEWS_BASELINE. Dev builds
-- (an unreplaced @project-version@, an untagged git-describe tail) never show it and never write.
-- It opens 3 s after the first world entry of a session (Onboarding's guide, 2 s, wins a tie) when every gate holds
-- (no combat or loading screen, the Gamepad UI on, the pad free, no other window of ours), else waits for the next of
-- those to change. Closing (B, Escape, the X, the toggle combo) stores seen = running, and never = true when "Never
-- show again" is ticked; the box starts unticked on every open and its tick is never kept. Hidden any other way
-- (combat, UIParent hidden, the Gamepad UI off) stores nothing; after combat it opens again once.
-- /fct whatsnew clears never and opens this version's notes. Own frames on FCT's window base with native atlases; no
-- Blizzard frame, binding stack or CVar is written.
local addonName, ns = ...
local UI = ns.UI
local L = UI.L

local News = {}
UI.WhatsNew = News

local STRINGS = {
	NEWS_TITLE = "Controller Tweaks · What's new", NEWS_VERSION = "Version %s", NEWS_UPDATED = "Version %s · updated from %s",
	NEWS_DEV = "Development build · notes for %s", NEWS_NEVER = "Never show again",
	NEWS_NEVER_TIP = "What's new won't open after updates.\nType /fct whatsnew to see it again.", NEWS_SCROLL = "Scroll",
	NEWS_OLDER = "Older versions: %s", NEWS_EMPTY = "Nothing new for players in this version.",
	NEWS_ON = "What's new is on again: it opens after each update.",
}
for key, text in pairs(STRINGS) do L[key] = text end

-- The last released version without this window: existing players start from it, so they see the first one's notes.
local NEWS_BASELINE = "1.4.0"
local SHOW_MAX = 5
local ARM_DELAY, RECHECK_DELAY = 3, 2

---------------------------------------------------------------------------------------------------------------------
-- Versions: semver-ish, with pre-releases. Pure, for the specs.

-- { major, minor, patch, pre = { identifiers } | nil }, or nil for a dev build.
function News.ParseVersion(text)
	if type(text) ~= "string" then return end
	local major, minor, patch, rest = text:gsub("^v", ""):match("^(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major then return end
	local version = { tonumber(major), tonumber(minor), tonumber(patch) }
	if rest == "" then return version end
	-- A git-describe tail (1.4.0-3-gabc1234) is an untagged build, not a pre-release.
	if rest:find("^%-%d+%-g%x+$") or not rest:find("^%-[%w]+[%w.]*$") or rest:find("%.%.") or rest:find("%.$") then return end
	version.pre = {}
	for part in rest:sub(2):gmatch("[^.]+") do version.pre[#version.pre + 1] = tonumber(part) or part end
	return version
end

local function comparePre(a, b)
	if not a and not b then return 0 end
	if not a then return 1 end
	if not b then return -1 end
	for i = 1, math.max(#a, #b) do
		local x, y = a[i], b[i]
		if x == nil then return -1 end
		if y == nil then return 1 end
		if x ~= y then
			local xn, yn = type(x) == "number", type(y) == "number"
			if xn ~= yn then return xn and -1 or 1 end
			return x < y and -1 or 1
		end
	end
	return 0
end

-- -1, 0 or 1; nil when either is a dev build.
function News.CompareVersions(a, b)
	local x, y = News.ParseVersion(a), News.ParseVersion(b)
	if not (x and y) then return end
	for i = 1, 3 do
		if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
	end
	return comparePre(x.pre, y.pre)
end
ns.CompareVersions = News.CompareVersions

-- The notes after seen up to running, newest first, at most max; and whether older ones were left out.
function News.Entries(list, seen, running, max)
	local out, older = {}, false
	for _, entry in ipairs(list or {}) do
		local version = entry.version
		local newer = seen == nil or News.CompareVersions(version, seen) == 1
		if newer and News.CompareVersions(version, running) ~= 1 then
			if #out < max then out[#out + 1] = entry else older = true end
		end
	end
	return out, older
end

-- The running version as the toc gives it.
local function running() return C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") end

-- Repairs ns.db.news and records where this player starts: a first install at the running version, an existing
-- player at the baseline. A dev build only repairs what is there.
function News.Init(db, fresh, version)
	local news = db.news
	if news ~= nil and type(news) ~= "table" then
		news = {}
		db.news = news
	end
	if news then
		if not News.ParseVersion(news.seen) then news.seen = nil end
		if news.never ~= true then news.never = nil end
	end
	if not News.ParseVersion(version) then return end
	db.news = news or {}
	db.news.seen = db.news.seen or fresh and version or NEWS_BASELINE
end

---------------------------------------------------------------------------------------------------------------------
-- The window (design/whats-new.md 3): FCT's window base re-skinned as a portrait frame.

local W_, H_, PAD, TOP_Y, DIVIDER_Y, NOTES_H = 560, 520, 24, 68, 60, 436
local NOTES_W, TEXT_W = W_ - 2 * PAD, 490
local BODY_ALPHA = 0.75
local LINE = 14.4
local SCROLL_LINES = 3
local STICK_DEAD = 0.1
local ICON = "Interface\\AddOns\\ForeverControllerTweaks\\Art\\icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CLAMP = "CLAMPTOBLACKADDITIVE"
local STICK_RIGHT = { Right = true, Camera = true, Look = true }

local window, scroll, child, bar, versionLine, boxRow, box, hint, notesNode, boxNode
local pools, counts = { header = {}, text = {} }, { header = 0, text = 0 }
local offset, contentH = 0, 0
local mode, closing, stickY = nil, false, 0
-- This session: the window opened on its own; it may open again once after a fight that closed it.
local shownOnce, reopen, reopened, armed, loading = false, false, false, false, false

-- A version header (UI-Character-Info-Title with its centred text) or a text block, from its pool.
local function make(kind)
	if kind == "text" then
		local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetJustifyH("LEFT")
		fs:SetSpacing(2)
		return fs
	end
	local header = CreateFrame("Frame", nil, child)
	header:SetSize(201, 32)
	header.art = header:CreateTexture(nil, "BACKGROUND")
	header.art:SetAtlas("UI-Character-Info-Title")
	header.art:SetAllPoints()
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.text:SetPoint("TOP", 0, -8)
	return header
end

local function region(kind)
	local list, n = pools[kind], counts[kind] + 1
	counts[kind] = n
	list[n] = list[n] or make(kind)
	list[n]:Show()
	return list[n]
end

-- A text block at x, width w, gap above it; returns the new bottom.
local function text(y, gap, font, x, w, value)
	local fs = region("text")
	fs:SetFontObject(font)
	fs:SetWidth(w)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(y + gap))
	fs:SetText(value)
	return y + gap + fs:GetStringHeight()
end

local BULLET = { [1] = { 8, 18 }, [2] = { 24, 34 } }

local function drawNotes(entries, older)
	for kind, list in pairs(pools) do
		for _, item in ipairs(list) do item:Hide() end
		counts[kind] = 0
	end
	local y = 0
	for n, entry in ipairs(entries) do
		local header = region("header")
		header:ClearAllPoints()
		y = y + (n == 1 and 4 or 18)
		header:SetPoint("TOP", child, "TOPLEFT", TEXT_W / 2, -y)
		header.text:SetText(entry.date ~= "" and ("%s  ·  %s"):format(entry.version, entry.date) or entry.version)
		y = y + 32 + 6
		for _, block in ipairs(entry.blocks) do
			local kind, value, depth = block[1], block[2], block[3]
			if kind == "h" then y = text(y, 9, "GameFontNormal", 4, TEXT_W - 4, value) + 3
			elseif kind == "p" then y = text(y, 2, "GameFontHighlight", 4, TEXT_W - 4, value)
			else
				local at = BULLET[depth] or BULLET[1]
				text(y, 3, "GameFontHighlight", at[1], 10, "•")
				y = text(y, 3, "GameFontHighlight", at[2], TEXT_W - at[2], value)
			end
		end
	end
	if not entries[1] then y = text(y, 4, "GameFontDisable", 4, TEXT_W - 4, L.NEWS_EMPTY) end
	if older then
		local site = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "X-Website") or ""
		y = text(y, 14, "GameFontDisable", 4, TEXT_W - 4, L.NEWS_OLDER:format(site))
	end
	contentH = y + 8
	child:SetHeight(contentH)
end

local function overflows() return contentH > NOTES_H end

local function scrollTo(y)
	offset = math.max(0, math.min(y, math.max(0, contentH - NOTES_H)))
	scroll:SetVerticalScroll(offset)
	bar:Set(math.floor(offset + 0.5), NOTES_H, math.ceil(contentH))
end

local function prompts()
	local list = {}
	if window.focus == boxNode then list[#list + 1] = { "PAD1", L.SELECT } end
	if overflows() then list[#list + 1] = { GAMEPAD_STICK_RIGHT_VERTICAL or "PADRSTICKUP", L.NEWS_SCROLL } end
	list[#list + 1] = { "PAD2", L.CLOSE }
	return list
end

-- The single close: what it stores, then every window of ours goes.
local function close()
	local news = ns.db and ns.db.news
	if mode ~= "dev" and news then
		news.seen = running()
		if box.on then news.never = true end
	end
	closing = true
	UI.CloseAll()
	closing = false
end

local function toggleBox()
	box.on = not box.on
	box:Set(box.on)
end

local function build()
	window = UI.NewWindow(W_, H_)
	window:SetTitle(L.NEWS_TITLE)
	-- The Character window's frame: Blizzard's pure layout code on our own NineSlice.
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then pcall(NineSliceUtil.ApplyLayoutByName, window.NineSlice, "PortraitFrameTemplate") end
	window.glow = UI.Glow(window, window.NineSlice, "gamepad-uiframemetal-largeportrait-focus", -20, 24, 14, -14)
	-- A quarter of the world shows through the body; the frame, text and controls stay opaque.
	window.underlay:Hide()
	if window.Bg then window.Bg:SetAlpha(BODY_ALPHA) end
	local portrait = window:CreateTexture(nil, "ARTWORK")
	portrait:SetSize(62, 62)
	portrait:SetPoint("TOPLEFT", -5, 7)
	portrait:SetTexture(ICON)
	local mask = window:CreateMaskTexture()
	mask:SetTexture(PORTRAIT_MASK, CLAMP, CLAMP)
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, 0)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 4)
	portrait:AddMaskTexture(mask)
	window.ClosePanelButton:SetScript("OnClick", close)

	versionLine = UI.Text(window, "GameFontHighlight", 62, 31, "")
	boxRow = CreateFrame("Button", nil, window)
	boxRow:SetSize(176, 29)
	boxRow:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -PAD)
	boxRow.wash = boxRow:CreateTexture(nil, "BACKGROUND")
	boxRow.wash:SetColorTexture(1, 1, 1, 0.1)
	boxRow.wash:SetPoint("TOPLEFT", -10, 0)
	boxRow.wash:SetPoint("BOTTOMRIGHT", 5, 0)
	boxRow.wash:Hide()
	box = UI.Checkbox(boxRow, toggleBox)
	box:SetPoint("RIGHT")
	local label = boxRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("RIGHT", box, "LEFT", -6, 0)
	label:SetText(L.NEWS_NEVER)
	hint = UI.Glyph(boxRow, 20, "PADDUP")
	hint:SetPoint("RIGHT", label, "LEFT", -4, 0)
	boxRow:SetScript("OnClick", toggleBox)

	local divider = window:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("Options_HorizontalDivider")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", PAD, -DIVIDER_Y)
	divider:SetPoint("TOPRIGHT", -PAD, -DIVIDER_Y)

	scroll = CreateFrame("ScrollFrame", nil, window)
	scroll:SetSize(NOTES_W, NOTES_H)
	scroll:SetPoint("TOPLEFT", PAD, -TOP_Y)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(TEXT_W, NOTES_H)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(offset - delta * SCROLL_LINES * LINE) end)
	-- The bar steps by one of its units on an arrow or the wheel: a step of three lines here.
	bar = UI.ScrollBar(window, NOTES_H, function(top)
		local step = top - math.floor(offset + 0.5)
		scrollTo(math.abs(step) == 1 and offset + step * SCROLL_LINES * LINE or top)
	end)
	bar:SetPoint("TOPLEFT", window, "TOPLEFT", W_ - 32, -TOP_Y)
	-- The cursor sits by the first version header.
	local notesAnchor = CreateFrame("Frame", nil, window)
	notesAnchor:SetSize(1, 32)
	notesAnchor:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)

	notesNode = UI.Node(window, scroll, function() end, { cursorRegion = notesAnchor, onFocus = function(on) if on then hint:SetCode("PADDUP") end end })
	boxNode = UI.Node(window, boxRow, toggleBox, {
		onFocus = function(on)
			boxRow.wash:SetShown(on)
			if on then hint:SetCode("PAD1") end
		end,
		tip = { title = L.NEWS_NEVER, lines = { L.NEWS_NEVER_TIP }, side = "under" },
	})
	-- D-pad up / down scroll the notes (held, they repeat through the window's own repeat); up at the top reaches the
	-- box, down from it comes back. Left / right do nothing: there are no tabs.
	function window:Move(_, dy)
		if dy == 0 then return end
		if self.focus == boxNode then
			if dy < 0 then self:Focus(notesNode) end
			return
		end
		if dy > 0 and offset <= 0 then return self:Focus(boxNode) end
		scrollTo(offset - dy * SCROLL_LINES * LINE)
	end
	window.OnFocusChanged = function() window:SetPrompts(prompts()) end
	window.OnBack = close
	-- The toggle combo and the other close keys close it like B.
	window.OnKey = function(_, key)
		if not (key == "PADFORWARD" or key == "PADSOCIAL" or UI.Toggle().keys[key]) then return end
		close()
		return true
	end
	window.OnRefresh = function()
		window:SetNodes({ notesNode, boxNode })
		window:SetPrompts(prompts())
	end
	-- Hidden without close(): combat closes it unread, and after the fight it opens again once.
	window.OnClosed = function()
		if not closing and mode == "auto" and UI.combatClosing and not reopened then reopen = true end
	end
	-- Right stick: smooth scroll by SmartNavigation's rule, offset - y * speed * elapsed (its CVar only read).
	window:EnableGamePadStick(true)
	window:SetScript("OnGamePadStick", function(_, stick, _, y)
		if not STICK_RIGHT[stick] then return true end
		stickY = math.abs(y or 0) > STICK_DEAD and y or 0
		return false
	end)
	window:HookScript("OnUpdate", function(_, elapsed)
		if stickY == 0 then return end
		local speed = GetCVarNumberOrDefault and GetCVarNumberOrDefault("SmartNavigationScrollSpeed") or 400
		scrollTo(offset - stickY * speed * elapsed)
	end)
	window:HookScript("OnHide", function() stickY = 0 end)
end

-- Opens the window: how ("auto" | "command" | "dev"), its notes and older flag, its version line.
local function open(how, entries, older, line)
	if InCombatLockdown() then return ns.log(L.COMBAT) end
	if not window then build() end
	mode = how
	box.on = false
	box:Set(false)
	versionLine:SetText(line)
	drawNotes(entries, older)
	window.focus = nil
	UI.Show(window)
	if not window:IsShown() then return end
	scrollTo(0)
	window:Focus(notesNode)
end

---------------------------------------------------------------------------------------------------------------------
-- When it opens on its own.

-- The notes the player hasn't seen, or nil when nothing is due (a dev build, never, no update, a downgrade).
function News.Due()
	local news, version = ns.db and ns.db.news, running()
	if not (news and news.seen and not news.never and News.CompareVersions(version, news.seen) == 1) then return end
	return News.Entries(ns.NEWS, news.seen, version, SHOW_MAX)
end

local function gatesOpen() return not (InCombatLockdown() or loading) and ns.Active() and ns.padFree() and not UI.Current() end

function News.Check()
	if not armed then return end
	local entries, older = News.Due()
	if not entries then
		armed = false
		return
	end
	-- An update with nothing for players: seen moves on quietly.
	if not entries[1] then
		ns.db.news.seen = running()
		armed = false
		return
	end
	if not gatesOpen() then return end
	armed = false
	shownOnce = true
	local seen = ns.db.news.seen
	open("auto", entries, older, seen and L.NEWS_UPDATED:format(running(), seen) or L.NEWS_VERSION:format(running()))
end

local function recheck() if armed then C_Timer.After(RECHECK_DELAY, News.Check) end end

ns.On("FCT_READY", function() News.Init(ns.db, ns.freshDB, running()) end)
ns.On("PLAYER_ENTERING_WORLD", function()
	if shownOnce or armed then return end
	armed = true
	C_Timer.After(ARM_DELAY, News.Check)
end)
ns.On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.On("LOADING_SCREEN_DISABLED", function()
	loading = false
	recheck()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	if reopen then
		reopen, reopened, armed = false, true, true
	end
	recheck()
end)
ns.On("FCT_ACTIVE_CHANGED", function(active) if active then recheck() end end)
ns.On("FCT_PAD_FREE", function(free) if free then recheck() end end)
ns.On("FCT_PANEL_OPEN", function(isOpen) if not isOpen then recheck() end end)

-- /fct whatsnew: turns it back on and shows this version's notes (a dev build: the newest, storing nothing).
function ns.commands.whatsnew()
	local news = ns.db and ns.db.news
	if news and news.never then
		news.never = nil
		ns.log(L.NEWS_ON)
	end
	if not ns.NEWS then return ns.log(L.NEWS_EMPTY) end
	local version = running()
	if not News.ParseVersion(version) then
		local newest = ns.NEWS[1]
		return open("dev", { newest }, false, L.NEWS_DEV:format(newest and newest.version or "?"))
	end
	local entries = {}
	for _, entry in ipairs(ns.NEWS) do if News.CompareVersions(entry.version, version) == 0 then entries[1] = entry end end
	open("command", entries, false, L.NEWS_VERSION:format(version))
end
