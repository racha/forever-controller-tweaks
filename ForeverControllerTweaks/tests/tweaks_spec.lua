-- The Tweaks tab and its ten tweaks, on the full panel stub (real TOC files, Glyphs aside): lua tests/tweaks_spec.lua.
-- Saved settings and their repair, everything off by default (events do nothing), the tab on the pad, then each tweak
-- by its events with stubbed APIs. The Blizzard windows are read-only proxies (a field write fails), and the popup,
-- panel and CVar calls the taint rules forbid are traps.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."
local W = dofile(here .. "/panel_stub.lua")
-- The sync state line colours (Blizzard globals), read when Panel/Sync.lua loads.
for _, name in ipairs({ "GRAY_FONT_COLOR", "GREEN_FONT_COLOR", "RED_FONT_COLOR", "NORMAL_FONT_COLOR" }) do _G[name] = _G[name] or { GetRGB = function() return 1, 1, 1 end } end
-- A secure header's wrap keeps its snippet, so the spec can run it.
getmetatable(W.new("Frame")).WrapScript = function(_, target, _, pre) target.wrap = pre end
-- A colour texture keeps its colour, so the battery's bars can be read.
getmetatable(W.new("Frame")).SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
local raw = { name = "Test Pad", vendorID = 0x045e, productID = 0x0b00, rawButtons = {}, rawAxes = {} }
for i = 0, 20 do raw.rawButtons[i] = false end
for i = 0, 9 do raw.rawAxes[i] = 0 end
W.raw = raw

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

-- Calls the tweaks make, by name: { args... } per call.
local calls = {}
local function record(name, result) return function(...) calls[name] = calls[name] or {} table.insert(calls[name], { ... }) return result end end
local function count(name) return calls[name] and #calls[name] or 0 end
local function reset() calls = {} W.log = {} end
local function saidPlain(text)
	for _, line in ipairs(W.log) do if line:find(text, 1, true) then return true end end
	return false
end
local function said(pattern)
	for _, line in ipairs(W.log) do if line:find(pattern) then return true end end
	return false
end

for _, name in ipairs({ "StaticPopup_Hide", "StaticPopup_Show", "StaticPopupSpecial_Hide", "ShowUIPanel", "SetCVar", "CloseGossip", "CloseMerchant" }) do
	_G[name] = function() error("Tweaks called " .. name, 2) end
end

-- A Blizzard frame: reads only. visible, id, strata and level come from the spec table, which the test changes.
local function blizz(spec)
	return setmetatable({}, {
		__index = {
			IsVisible = function() return spec.visible end,
			IsShown = function() return spec.visible end,
			GetID = function() return spec.id end,
			GetFrameStrata = function() return spec.strata or "MEDIUM" end,
			GetFrameLevel = function() return spec.level or 5 end,
			-- Anchoring our frames reads the anchor's position in the stub.
			Abs = function() return 0, 0 end,
			selectedTab = spec.selectedTab, CloseButton = spec.CloseButton,
			OpenAllMail = spec.OpenAllMail, gamepadFooter = spec.gamepadFooter,
		},
		__newindex = function(_, k) error("Tweaks wrote " .. tostring(k) .. " on a Blizzard frame", 2) end,
	})
end

-- The world: money, the bags, a merchant, gossip, a trainer, mail.
local money = 1000000
function GetMoney() return money end
function GetMoneyString(copper) return copper .. "c" end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
NUM_BAG_SLOTS = 4
local bags = {}
C_Container.GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end
C_Container.GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] or nil end
C_Container.UseContainerItem = function(bag, slot)
	record("UseContainerItem")(bag, slot)
	bags[bag][slot] = false
end
C_Container.SortBags = record("SortBags")
local freeSlots = 10
C_Container.CalculateTotalNumberOfFreeBagSlots = function() return freeSlots end
local prices = { [10] = 5, [11] = 7, [12] = 0, [13] = 100 }
C_Item.GetItemInfo = function(id) return "Item" .. id, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[id] end
Enum.ItemQuality = { Poor = 0, Common = 1 }
local function junkBags()
	bags = { [0] = {
		{ itemID = 10, quality = 0, stackCount = 2, hyperlink = "[Linen Scrap]" },
		{ itemID = 13, quality = 1, stackCount = 1, hyperlink = "[Sword]" },
		{ itemID = 11, quality = 0, stackCount = 1, hyperlink = "[Broken Fang]" },
		{ itemID = 12, quality = 0, stackCount = 1, hyperlink = "[Pebble]" },
		{ itemID = 10, quality = 0, stackCount = 1, hasNoValue = true, hyperlink = "[Linen Scrap]" },
	}, [1] = {} }
end

-- Selling all junk empties every priced grey slot, as the merchant does.
local function sellAll()
	record("SellAllJunkItems")()
	for _, list in pairs(bags) do
		for slot, info in pairs(list) do
			if info and info.quality == 0 and not info.hasNoValue and (prices[info.itemID] or 0) > 0 then list[slot] = false end
		end
	end
end
C_MerchantFrame = { SellAllJunkItems = sellAll, IsSellAllJunkEnabled = function() return true end }
local merchant = { [1] = { price = 100, stackCount = 1, max = 20, name = "Arrow" }, [2] = { price = 50, stackCount = 1, max = 1, name = "Sword" }, [3] = { price = 10000000, stackCount = 1, max = 20, name = "Gem" }, [4] = { price = 10, stackCount = 5, max = 200, name = "Shot", hasExtendedCost = true } }
C_MerchantFrame.GetItemInfo = function(i)
	local m = merchant[i]
	return m and { price = m.price, stackCount = m.stackCount, numAvailable = -1, isPurchasable = true, hasExtendedCost = m.hasExtendedCost, name = m.name }
end
function GetMerchantItemMaxStack(i) return merchant[i] and merchant[i].max or 1 end
BuyMerchantItem = record("BuyMerchantItem")
local repairCost, guildWithdraw, guildBank, guildRepair = 500, 0, 0, false
function CanMerchantRepair() return true end
function GetRepairAllCost() return repairCost, repairCost > 0 end
function CanGuildBankRepair() return guildRepair end
function GetGuildBankWithdrawMoney() return guildWithdraw end
function GetGuildBankMoney() return guildBank end
RepairAllItems = record("RepairAllItems")
local merchantSpec = { visible = false, selectedTab = 1, strata = "HIGH", level = 20 }
MerchantFrame = blizz(merchantSpec)
local rowSpecs = {}
for i = 1, 10 do
	rowSpecs[i] = { visible = false, id = i }
	_G["MerchantItem" .. i] = blizz(rowSpecs[i])
	_G["MerchantItem" .. i .. "ItemButton"] = blizz(rowSpecs[i])
end
local bagClose = blizz({ visible = true })
-- The combined bags' gamepad footer (PromptedBindingFooter): read only, its legend frame shown with the bags' focus.
local legendSpec = { visible = true }
local bagLegend = blizz(legendSpec)
local bagSpec = { visible = false, CloseButton = bagClose, gamepadFooter = setmetatable({ inputLegend = bagLegend }, { __newindex = function(_, k) error("Tweaks wrote " .. tostring(k) .. " on the bag footer", 2) end }) }
ContainerFrameCombinedBags = blizz(bagSpec)
local backpackSpec = { visible = false }
ContainerFrame1 = blizz(backpackSpec)

local gossip = { options = {}, available = {}, active = {}, force = false }
C_GossipInfo = {
	GetOptions = function() return gossip.options end,
	GetAvailableQuests = function() return gossip.available end,
	GetActiveQuests = function() return gossip.active end,
	ForceGossip = function() return gossip.force end,
	SelectOption = record("SelectOption"),
	SelectAvailableQuest = record("SelectAvailableQuest"),
	SelectActiveQuest = record("SelectActiveQuest"),
}
local greeting = { available = 0, active = 0 }
function GetNumAvailableQuests() return greeting.available end
function GetNumActiveQuests() return greeting.active end
SelectAvailableQuest = record("GreetingAvailable")
SelectActiveQuest = record("GreetingActive")

local services = {}
function GetNumTrainerServices() return #services end
function GetTrainerServiceInfo(i) return "Skill" .. i, services[i].kind end
function GetTrainerServiceCost(i) return services[i].cost end
function BuyTrainerService(i)
	record("BuyTrainerService")(i)
	services[i].kind = "used"
	money = money - services[i].cost
end
-- Blizzard's Train button is hidden in the Gamepad UI (its footer trains); the trainer window shows.
local trainSpec = { visible = false }
ClassTrainerTrainButton = blizz({ visible = false })
ClassTrainerFrame = blizz(trainSpec)

local mails = {}
function GetInboxNumItems() return #mails end
function GetInboxHeaderInfo(i)
	local m = mails[i]
	return nil, nil, "Bob", "Hi", m.money, m.cod, 30, #m.items, false, false, false, true, m.gm
end
function GetInboxItem(i, a) return mails[i].items[a] end
function TakeInboxMoney(i) record("TakeInboxMoney")(i) mails[i].money = 0 end
function TakeInboxItem(i, a)
	record("TakeInboxItem")(i, a)
	table.remove(mails[i].items, a)
	freeSlots = freeSlots - 1
end
-- Blizzard's own Open All button is hidden in the Gamepad UI.
local inboxSpec = { visible = false, OpenAllMail = blizz({ visible = false }) }
InboxFrame = blizz(inboxSpec)

-- Friends by GUID and by name (Ann: a game friend; Gil-Stormrage: a guildmate on another realm; Bea: a Battle.net
-- friend on Argent Dawn).
local friends = { ["Player-1-FRIEND"] = true }
local friendNames = { Ann = true }
local roster = { "Gil-Stormrage", "Hal-ArgentDawn", SECRET }
local bnet = { { { characterName = "Bea", realmName = "Argent Dawn" } }, { { characterName = SECRET, realmName = "Argent Dawn" } } }
C_FriendList = { IsFriend = function(guid) return friends[guid] == true end, GetFriendInfo = function(who) if friendNames[who] then return { name = who } end end }
C_BattleNet = {
	GetGameAccountInfoByGUID = function(guid) if guid == "Player-1-BNET" then return {} end end,
	GetFriendNumGameAccounts = function(i) return #bnet[i] end, GetFriendGameAccountInfo = function(i, j) return bnet[i][j] end,
}
function BNGetNumFriends() return #bnet, #bnet end
function GetNumGuildMembers() return #roster end
function GetGuildRosterInfo(i) return roster[i] end
function GetNormalizedRealmName() return "ArgentDawn" end
function IsGuildMember(guid) return guid == "Player-1-GUILD" end
local queued = false
function WillAcceptInviteRemoveQueues() return queued end
AcceptGroup = record("AcceptGroup")
CancelDuel = record("CancelDuel")
AcceptResurrect = record("AcceptResurrect")
local sickness = false
function ResurrectHasSickness() return sickness end
C_SummonInfo = { ConfirmSummon = record("ConfirmSummon"), GetSummonConfirmSummoner = function() return "Ann" end, GetSummonConfirmAreaName = function() return "Goldshire" end }
function PlayerCanTeleport() return true end

-- A saved table from an older or damaged save: bad values are repaired, unknown keys dropped.
C_GamePad.SetLedColor = function(color) record("SetLedColor")(color.r, color.g, color.b) end
C_GamePad.ClearLedColor = record("ClearLedColor")
function CreateColor(r, g, b) return { r = r, g = g, b = b } end
function UnitClass() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
ForeverControllerTweaksDB = { version = 2, tweaks = { sellJunk = "yes", repair = true, bogus = 1, lightBar = "rainbow", rumbleStrength = 0.9 } }
local ns = {}
for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
	if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
end
local UI, Tweaks = ns.UI, ns.Tweaks
W.fire("ADDON_LOADED", "ForeverControllerTweaks")
W.fire("PLAYER_LOGIN")
W.fire("PLAYER_ENTERING_WORLD")
W.advance(2.5)
UI.CloseAll()

-- Settings: every key a boolean, off unless saved on.
local saved = ns.db.tweaks
check(saved.sellJunk == false and saved.repair == true and saved.bogus == nil, "repair: a bad value is off, a good one kept, an unknown key dropped")
for _, key in ipairs(Tweaks.KEYS) do check(type(saved[key]) == "boolean", key .. " is a boolean") end
check(#Tweaks.KEYS == 21, "twenty on/off tweaks and the guild-funds sub-row: " .. #Tweaks.KEYS)
check(saved.lightBar == "default" and saved.lightColor == "red", "choices start at their first option")
local groups = saved.rumbleGroups
check(groups and groups.group == "double" and groups.whisper == "tap" and groups.tradeDuel == "tap" and groups.danger == "long" and groups.enemy == "double" and groups.rare == "heartbeat" and groups.levelUp == "ramp" and groups.procs == "off", "each group starts at its own pattern (Procs off)")
check(saved.rumbleStrength == 0.9 and saved.rumbleEvents == nil, "one strength, kept (90%)")
local old = { readyCheck = { pattern = "triple", strength = 0.4 }, invite = { pattern = "tap", strength = 1 }, trade = { pattern = "rtrigger", strength = 0.7 }, death = { pattern = "nope", strength = 0.6 }, proc = { pattern = "fade" } }
local moved = Tweaks.RepairRumbleGroups(nil, old)
check(moved.group == "triple" and moved.tradeDuel == "tap" and moved.danger == "long" and moved.procs == "fade" and moved.whisper == "tap", "from per-event settings: a group takes its first event's pattern; a trigger one becomes Tap; unknown -> default")
check(Tweaks.MigrateRumbleStrength(nil, old) == 0.7 and Tweaks.MigrateRumbleStrength(0.3, old) == 0.3 and Tweaks.MigrateRumbleStrength(nil, nil) == 0.6, "strength: kept, else the per-event average (0.675 -> 70%), else 60%")
check(Tweaks.RepairRumbleGroups({ danger = "triggers" }).danger == "tap" and Tweaks.RepairRumbleGroups({ whisper = "fade" }).whisper == "fade", "a saved trigger pattern becomes Tap")
for _, name in ipairs(Tweaks.PATTERN_ORDER) do check(not name:find("trigger"), "no trigger patterns: " .. name) end
for event, group in pairs(Tweaks.RUMBLE_GROUP_OF) do check(Tweaks.RUMBLE_GROUP_DEFAULT[group], event .. " belongs to a group") end
check(Tweaks.Repair(nil).sellJunk == false and Tweaks.Repair("x").acceptRes == false, "a missing or broken table repairs to all off")
Tweaks.Set("repair", false)
for _, key in ipairs(Tweaks.KEYS) do check(Tweaks.Get(key) == false, key .. " is off by default") end
-- The ring free stick settings are gone (1.5.5): a saved ringMove / ringTurn is dropped by the repair, Set still fires.
check(Tweaks.ON_KEYS == nil and Tweaks.Repair({ ringMove = false, ringTurn = true }).ringMove == nil and Tweaks.Repair({ ringTurn = false }).ringTurn == nil, "a saved ringMove / ringTurn is dropped")
local tweakChanged
ns.On("FCT_TWEAKS_CHANGED", function(key) tweakChanged = key end)
Tweaks.Set("sellJunk", true)
check(Tweaks.Get("sellJunk") == true and tweakChanged == "sellJunk", "Set saves and fires the change")
Tweaks.Set("sellJunk", false)

-- Off by default: every event leaves the game alone.
local function everything()
	junkBags()
	merchantSpec.visible, rowSpecs[1].visible = true, true
	W.fire("MERCHANT_SHOW")
	gossip.options = { { gossipOptionID = 7, name = "Fly", status = 0, flags = 0, rewards = {} } }
	W.fire("GOSSIP_SHOW")
	W.fire("GOSSIP_CLOSED")
	W.fire("PARTY_INVITE_REQUEST", "Fred", false, false, false, true, false, false, "Player-1-FRIEND", false)
	W.fire("DUEL_REQUESTED", "Fred")
	W.fire("RESURRECT_REQUEST", "Fred")
	W.fire("CONFIRM_SUMMON")
	W.advance(1)
end
reset()
everything()
check(next(calls) == nil and #W.log == 0, "all off: nothing sold, repaired, picked, accepted or declined")
merchantSpec.visible = false
W.fire("MERCHANT_CLOSED")

-- The tab: the side tab before Settings, four columns of rows under six headers.
local L = UI.L
check(UI.TABS[#UI.TABS - 1].tweaks and UI.TABS[#UI.TABS - 1][2] == "Tweaks" and UI.TABS[#UI.TABS].settings, "Tweaks is the side tab before Settings")
UI.TweaksTab.Open()
local w = UI.Current()
local ST = UI.TweaksTab.T
check(w and w.tabs.index == #UI.TABS - 1, "the tab opens as its own side tab")
check(#w.nodes == 34, "thirty-four rows: " .. #w.nodes)
local headers = {}
for _, f in ipairs(W.frames) do if f.parent == w and f.text and type(f.text) == "table" and f.text.text then headers[f.text.text] = true end end
check(headers[ST.BAGS] and headers[ST.NPCS] and headers[ST.RUMBLE] and headers[ST.CONTROLLER] and headers[ST.GEAR] and headers[ST.SOCIAL] and headers[ST.CAMERA], "seven section headers")
local function footer()
	local out = {}
	for _, prompt in ipairs(w.footer.prompts) do if prompt:IsShown() then out[prompt.key] = prompt.label.text end end
	return out
end
local prompts = footer()
check(prompts.PAD1 == L.SELECT and prompts.PAD4 == L.MORE and prompts.PAD2 == L.CLOSE and prompts.PADLSHOULDER == UI.TABS[#UI.TABS - 2].prompt, "footer: Select, More, the tab before, Close")
local function focused() return w.focus.region.key end
check(focused() == "sortBags", "opens on the first row")
for _, node in ipairs(w.nodes) do check(type(node.tip) == "table" and node.tip.title and node.tip.lines[1], node.region.key .. " has a tooltip") end
-- Down walks each column in order; right from a checkbox crosses to the next column's level row, left comes back.
local function press(key) w:Pad(key) w.repeatKey, w.repeatDir = nil, nil end
local function walk(n)
	local order = {}
	for _ = 1, n do order[#order + 1] = focused() press("PADDDOWN") end
	return table.concat(order, ",")
end
check(walk(9) == "sortBags,sortKey,sellJunk,repair,repairGuild,buyStack,skipGossip,learnAll,openMail", "first column order")
local function focusKey(key) for _, node in ipairs(w.nodes) do if node.region.key == key then w:Focus(node) end end end
focusKey("sortBags")
press("PADDRIGHT")
check(focused() == "rumble", "right goes to the Rumble column: " .. focused())
check(walk(10) == "rumble,rumbleStrength,rumble:group,rumble:whisper,rumble:tradeDuel,rumble:danger,rumble:enemy,rumble:rare,rumble:levelUp,rumble:procs", "Rumble column order")
focusKey("rumble")
press("PADDRIGHT")
check(focused() == "battery", "right goes to the Controller column: " .. focused())
local controller = walk(7)
check(controller:find("^battery,batteryIcon,rareAlert,lightBar,lightColor,combatFlash") and not controller:find("ring"), "Controller column order (Sync between machines moved to Settings), ending at Combat flash: " .. controller)
focusKey("battery")
press("PADDRIGHT")
check(focused() == "fastLoot", "right again goes to the last column: " .. focused())
check(walk(8) == "fastLoot,passUnusable,upgradeArrows,wearRewards,acceptInvites,declineDuels,acceptRes,whisperAlert", "last column order")
focusKey("fastLoot")
press("PADDLEFT")
check(focused() == "battery", "left comes back: " .. focused())
-- The rumble rows: one strength; a pattern per group (Off included). Left/right always cross the columns from a
-- pattern row; A opens its list (the game's dropdown): up/down move, A picks, B closes.
local gs = ns.db.tweaks.rumbleGroups
local FIRST_COLUMN = { sortBags = 1, sortKey = 1, sellJunk = 1, repair = 1, repairGuild = 1, buyStack = 1, skipGossip = 1, learnAll = 1, openMail = 1 }
-- The open dropdown list's helpers, in one table (the spec's main chunk is near Lua's 200-local limit).
local D = {}
function D.list() for _, f in ipairs(W.frames) do if f.rows and f.catcher and f.bar then return f end end end
function D.open(win) local f = D.list() return f and f.shown and (win or w).modal == UI.Choices end
function D.focus() for _, row in ipairs(D.list().rows) do if row.shown and row.highlight.shown then return row.index, row.text.text end end end
function D.tip() for _, f in ipairs(W.frames) do if f.title and type(f.lines) == "table" and type(f.actions) == "table" then return f.shown end end end
do
local list, listOpen, listFocus, tooltipShown = D.list, D.open, D.focus, D.tip
focusKey("rumble:group")
check(w.focus.region.label.text == "Group", "Group: its name first")
press("PADDLEFT")
check(FIRST_COLUMN[focused()] and gs.group == "double", "left from Rumble Group crosses to the first column, changing nothing: " .. focused())
focusKey("rumble:group")
press("PADDRIGHT")
check(not focused():find("^rumble"), "and right crosses to the Controller column: " .. focused())
focusKey("rumbleStrength")
press("PADDRIGHT")
check(not focused():find("^rumble") and ns.db.tweaks.rumbleStrength == 0.9, "right from Strength crosses too, the strength kept: " .. focused())
focusKey("rumble:whisper")
check(w.focus.region.control.text.text == "Tap" and w.focus.region.label.text == "Whisper", "Whisper: its name, then its pattern")
check(footer().PAD1 == L.CHANGE and not footer().PADDLEFT and not w.editing, "a choice row's footer: A Change, no D-pad hint")
press("PAD1")
check(listOpen() and not w.editing and gs.whisper == "tap", "A opens Whisper's list, changing nothing, grabbing nothing")
check(#Tweaks.PATTERN_ORDER == 8 and listFocus() == 2 and select(2, listFocus()) == "Tap", "the list: every pattern, the focus on the current one (Tap)")
check(footer().PAD1 == L.SELECT and footer().PAD2 == L.CLOSE and not footer().PAD4, "list footer: A Select, B Close")
check(not tooltipShown(), "the row's tooltip hides while the list is up")
check(w.cursor.rel == list().rows[2], "the window's chevron on the focused option")
press("PADDLEFT")
press("PADDRIGHT")
check(listOpen() and listFocus() == 2 and gs.whisper == "tap", "left/right in the list do nothing")
press("PADDDOWN")
check(listFocus() == 3 and gs.whisper == "tap", "down moves the focus only")
press("PAD1")
check(not listOpen() and gs.whisper == "double" and gs.group == "double" and focused() == "rumble:whisper" and w.focus.region.control.text.text == "Double tap", "A picks the next pattern and closes, the focus stays on the row")
check(footer().PAD1 == L.CHANGE and tooltipShown(), "the row's footer and tooltip are back")
press("PAD1")
press("PADDUP")
press("PADDUP")
press("PADDUP")
check(listFocus() == 1, "up stops at the first option (no wrap)")
press("PAD2")
check(not listOpen() and gs.whisper == "double" and w:IsShown() and focused() == "rumble:whisper", "B closes, nothing changes, the window stays")
press("PAD1")
press("PADDUP")
press("PADDUP")
press("PAD1")
check(gs.whisper == "off" and w.focus.region.control.text.text == "Off", "Off is a pattern: the group switches off right there")
press("PADDDOWN")
check(focused() == "rumble:tradeDuel" and gs.whisper == "off", "down moves on")
press("PADDRIGHT")
check(not focused():find("^rumble"), "right leaves the column again: " .. focused())
focusKey("rumble:procs")
press("PAD1")
for _ = 1, #Tweaks.PATTERN_ORDER do press("PADDDOWN") end
check(listFocus() == #Tweaks.PATTERN_ORDER, "down stops at the last option")
-- Held down repeats in the list too; L1 closes it, switching nothing.
press("PAD1")
check(gs.procs == "fade" and not listOpen(), "the last pattern picked")
press("PAD1")
w:Pad("PADDUP")
W.advance(0.6)
check(listFocus() < #Tweaks.PATTERN_ORDER - 1, "held up repeats: " .. tostring(listFocus()))
w:Fire("OnGamePadButtonUp", "PADDUP")
w:Fire("OnGamePadButtonDown", "PADLSHOULDER")
w:Fire("OnGamePadButtonUp", "PADLSHOULDER")
check(not listOpen() and UI.Current() == w and gs.procs == "fade", "L1 closes the list, the tab stays")
-- The mouse: a click on the box opens, a click on an option picks, a click outside closes.
local procs
for _, node in ipairs(w.nodes) do if node.region.key == "rumble:procs" then procs = node.region end end
procs.control:Click()
check(listOpen() and listFocus() == #Tweaks.PATTERN_ORDER, "a click on the box opens the list")
list().rows[2]:Fire("OnEnter")
check(listFocus() == 2 and w.cursor.rel == list().rows[2], "hover focuses an option")
list().rows[2]:Click()
check(not listOpen() and gs.procs == "tap", "a click on an option picks it")
procs.control:Click()
list().catcher:Click()
check(not listOpen() and gs.procs == "tap", "a click outside closes, nothing picked")
-- The control: one value box over the old stepper row's width, no arrow buttons; open, it shows its open art.
check(procs.control.steppers == nil and procs.control:GetWidth() == 161 and procs.control.text.font == "GameFontNormal", "no arrow buttons: the box spans the control's whole width")
procs.control:Click()
check(procs.control.bg.atlas == "common-dropdown-c-button-open", "open: the box takes its open art")
check(list().point == "TOPLEFT" and list().rel == procs.control and list():GetWidth() >= procs.control:GetWidth(), "the list hangs under the box, its left edge, at least as wide")
press("PAD2")
check(procs.control.bg.atlas == "common-dropdown-c-button", "closed: the plain box again")
-- A long list scrolls (10 rows), keeping the focus in view.
local long = {}
for i = 1, 14 do long[i] = "Option " .. i end
local picked
UI.OpenChoices({ anchor = procs.control, labels = long, current = 12, pick = function(i) picked = i end })
local function shownRows() local n = 0 for _, row in ipairs(list().rows) do if row.shown then n = n + 1 end end return n end
check(shownRows() == 10 and listFocus() == 12 and list().bar.shown, "14 options: 10 rows with a scroll bar, scrolled to the current one")
for _ = 1, 11 do press("PADDUP") end
check(listFocus() == 1 and list().rows[1].index == 1, "up to the first: scrolled back to the top")
for _ = 1, 13 do press("PADDDOWN") end
check(listFocus() == 14 and list().rows[10].index == 14, "down to the last: scrolled to the end")
press("PAD1")
check(picked == 14 and not listOpen(), "picks the 14th")
UI.OpenChoices({ anchor = procs.control, labels = { "One", "Two" }, current = 1, pick = function() end })
check(not list().bar.shown, "a short list has no scroll bar")
press("PAD2")
-- A dialog's stepper is a dropdown too: A opens a list of its numbers over the dialog, a pick redraws it in place.
local count = 2
local numbers = { "1", "2", "3", "4", "5" }
UI.Dialog():Open(w, { text = "How many?", buttons = { L.OK, L.CANCEL }, stepper = { options = function() return numbers, count end, pick = function(i) count = i end } })
local dialog = UI.Dialog()
check(dialog.Stepper.steppers == nil and dialog.Stepper.text.text == "2", "the dialog's stepper: one box, no arrows, its value")
press("PADDUP")
press("PAD1")
check(listOpen() and listFocus() == 2 and UI.DialogShown(), "A on it opens the number list over the dialog")
check(list():GetFrameLevel() > dialog:GetFrameLevel() + 2 and list().catcher:GetFrameLevel() > dialog:GetFrameLevel() + 2, "the list and its catcher sit above the dialog and its children")
check(footer().PAD1 == L.SELECT and footer().PAD2 == L.CLOSE, "list footer over the dialog")
press("PADDDOWN")
press("PAD1")
check(count == 3 and dialog.Stepper.text.text == "3" and UI.DialogShown() and not listOpen() and dialog.index == 0, "a pick sets 3, the dialog stays with the focus on its stepper")
check(footer().PAD1 == L.SELECT and footer().PAD2 == L.BACK and w.cursor.rel == dialog.Stepper, "the dialog's footer and cursor are back")
press("PAD1")
press("PAD2")
check(count == 3 and UI.DialogShown() and not listOpen(), "B closes the list, not the dialog")
press("PAD2")
check(not UI.DialogShown(), "B again closes the dialog")
Tweaks.SetRumbleGroup("procs", "fade")
end
Tweaks.SetRumbleGroup("procs", "off")
Tweaks.SetRumbleGroup("whisper", "tap")
focusKey("rumbleStrength")
press("PAD1")
press("PADDLEFT")
check(ns.db.tweaks.rumbleStrength == 0.8 and focused() == "rumbleStrength", "one strength for all")
press("PADDRIGHT")
check(ns.db.tweaks.rumbleStrength == 0.9, "back to 90%")
press("PADLSHOULDER")
check(not w.editing and w:IsShown(), "L1 lets go")
-- A toggles and saves; the guild row greys while Repair is off.
local function rowOf(key) for _, node in ipairs(w.nodes) do if node.region.key == key then return node.region end end end
check(rowOf("repairGuild").label.font == "GameFontDisable", "Use guild funds greys while Repair is off")
check(rowOf("rumbleStrength").label.font == "GameFontDisable" and rowOf("rumble:group").label.font == "GameFontDisable" and rowOf("rumbleStrength").control.value.text == "90%", "the rumble rows grey while Rumble is off; the slider shows the strength")
for _, node in ipairs(w.nodes) do if node.region.key == "repair" then w:Focus(node) end end
w:Select()
check(ns.db.tweaks.repair == true and rowOf("repair").control.check.shown and rowOf("repairGuild").label.font == "GameFontNormal" and not w.editing, "A turns Repair on, checks it and lights its sub-row, never grabbing it")
w:Select()
check(ns.db.tweaks.repair == false and not rowOf("repair").control.check.shown, "A again turns it off")
rowOf("declineDuels").control:Click()
check(ns.db.tweaks.declineDuels == true, "a click on the checkbox toggles too")
Tweaks.Set("declineDuels", false)
-- Sync between machines lives in the Settings tab now: no Tweaks row, never a tweak.
check(rowOf("syncOn") == nil and ns.db.tweaks.syncOn == nil and not ns.Sync.Encode(ns.Sync.Sections(ns.db).tweaks):find("sync"), "no Sync row in Tweaks, not a tweak")
-- Tooltips: beside the focused row, never over it (right of its column, left from the last column), text wrapped
-- at a native width.
local function tooltipFrame() for _, f in ipairs(W.frames) do if f.title and type(f.lines) == "table" and type(f.actions) == "table" then return f end end end
for _, node in ipairs(w.nodes) do
	w:Focus(node)
	local tip = tooltipFrame()
	check(tip and tip.shown and tip:GetWidth() <= UI.TIP_TEXT_W + 1 + 20, node.region.key .. ": tooltip at most the native width: " .. tostring(tip and tip:GetWidth()))
	check(tip.rel == node.region and (tip.point == "TOPLEFT" and node.tip.side == "right" or tip.point == "TOPRIGHT" and node.tip.side == "left"), node.region.key .. ": tooltip beside its row, on its column's side")
	for _, line in ipairs(tip.lines) do check(not line.shown or line:GetWidth() <= UI.TIP_TEXT_W + 1, node.region.key .. ": a long line wraps") end
end
w:Focus(w.nodes[1])
-- Light bar: a dropdown row; A opens its list, left/right move the focus; Custom colour greys until Custom. Sliders
-- keep edit mode: A grabs, left/right step, a click anywhere lets go.
for _, node in ipairs(w.nodes) do if node.region.key == "lightBar" then w:Focus(node) end end
check(w.focus.choice and not w.focus.onDir and not w.editing, "Light bar: a choice row, never grabbed")
check(footer().PAD1 == L.CHANGE and footer().PAD4 == L.MORE and not footer().PADDLEFT, "choice row footer: A Change, Y More, no D-pad hint")
local function tipActions()
	local out = {}
	for _, action in ipairs(tooltipFrame().actions) do
		if action.shown then out[#out + 1] = action.glyph.code .. (action.glyph2.shown and "+" .. action.glyph2.code or "") .. "=" .. action.text.text end
	end
	return table.concat(out, ",")
end
check(tipActions() == "PAD1=" .. L.CHANGE, "choice row tip: A Change: " .. tipActions())
check(rowOf("lightBar").control.text.text == "Game default" and rowOf("lightColor").label.font == "GameFontDisable", "Game default; Custom colour greyed")
w:Pad("PADDLEFT")
w.repeatKey, w.repeatDir = nil, nil
check(ns.db.tweaks.lightBar == "default" and focused():find("^rumble"), "left on a choice row moves the focus, never the value: " .. focused())
for _, node in ipairs(w.nodes) do if node.region.key == "lightBar" then w:Focus(node) end end
w:Pad("PADDRIGHT")
w.repeatKey, w.repeatDir = nil, nil
check(ns.db.tweaks.lightBar == "default" and focused() ~= "lightBar", "right too: " .. focused())
for _, node in ipairs(w.nodes) do if node.region.key == "lightBar" then w:Focus(node) end end
w:Select()
w:Pad("PADDDOWN")
w:Pad("PAD1")
w.repeatKey, w.repeatDir = nil, nil
check(ns.db.tweaks.lightBar == "class" and rowOf("lightBar").control.text.text == "Class colour" and focused() == "lightBar", "the list picks Class colour")
w:Select()
w:Pad("PADDDOWN")
w:Pad("PAD1")
w.repeatKey, w.repeatDir = nil, nil
check(ns.db.tweaks.lightBar == "custom" and rowOf("lightColor").label.font == "GameFontNormal" and not w.editing, "Custom lights its colour row")
for _, node in ipairs(w.nodes) do if node.region.key == "cameraZoom" then w:Focus(node) end end
w:Select()
check(w.editing == w.focus and tipActions() == "PADDLEFT+PADDRIGHT=" .. L.CHANGE .. ",PAD1=" .. L.DONE .. ",PAD2=" .. L.DONE, "a slider still grabs: D-pad Change, A Done, B Done: " .. tipActions())
W.fire("GLOBAL_MOUSE_DOWN")
check(not w.editing and tipActions() == "PAD1=" .. L.CHANGE, "a click anywhere lets go")
Tweaks.Set("lightBar", "default")
UI.CloseAll()

local function turn(key) Tweaks.Set(key, true) end

-- 1. Sort bags: our button where Blizzard's sits, on whichever bag window shows; the picker action clicks our button.
local function sortButton()
	for _, f in ipairs(W.frames) do if f.scripts.OnClick == Tweaks.SortBags then return f end end
end
turn("sortBags")
local sort = sortButton()
check(sort and sort.parent == UIParent and not sort.shown, "Sort: our own frame on UIParent, hidden while the bags are closed")
bagSpec.visible = true
W.advance(0.3)
check(sort.shown and sort.rel == ContainerFrameCombinedBags and sort.point == "TOPRIGHT" and sort.x == -3 and sort.w == 22, "combined bags (their search box spans the top): Sort on the title bar, where the hidden close X sits")
-- The bags are a toplevel window that raises itself over its whole strata on a click or show: Sort sits one strata
-- up at a fixed level, so a raised bag never buries it and the levels never climb.
check(sort.strata == "HIGH" and sort.level == 10, "combined bags: Sort one strata above the bags, a fixed level")
bagSpec.level = 9000
W.advance(0.3)
check(sort.shown and sort.strata == "HIGH" and sort.level == 10, "a raised bag window doesn't move Sort's level")
bagSpec.level = nil
bagSpec.visible, backpackSpec.visible = false, true
W.advance(0.3)
check(sort.shown and sort.rel == ContainerFrame1 and sort.point == "TOPRIGHT" and sort.x == -9 and sort.w == 28 and sort.strata == "HIGH", "separate bags: Blizzard's own sort button's place, above the bags too")
backpackSpec.visible, bagSpec.visible = false, true
W.advance(0.3)
sort.scripts.OnEnter(sort)
local sortTip
for _, f in ipairs(W.frames) do if f.title and type(f.lines) == "table" and type(f.actions) == "table" then sortTip = f end end
check(sortTip.lines[1].text:find("bag menu", 1, true), "its tooltip names the pad's ways: the bag menu or the picker action")
sort.scripts.OnLeave(sort)
reset()
sort:Click()
check(count("SortBags") == 1, "Sort sorts the bags")
W.combat = true
sort:Click()
W.combat = false
check(count("SortBags") == 1 and said("Not in combat"), "not in combat")
bagSpec.visible = false
W.advance(0.3)
check(not sort.shown, "hides with the bags")
check(ns.Actions.TextFor("game:sortbags") == "/click ForeverControllerTweaksSortBags", "picker: Sort bags clicks our button")
ForeverControllerTweaksSortBags:Click()
check(count("SortBags") == 2, "and that button sorts")
Tweaks.Set("sortBags", false)

-- 1b. Sort bags key (design/1.5.0.md 3.2): on by default (L3), its own choice, not in the all-off keys. While a bag
-- frame shows, a priority override binding on our own button; closed, none. Out of combat only; a shoulder or trigger
-- held: nothing.
check(Tweaks.Repair(nil).sortKey == "L3" and Tweaks.Repair({ sortKey = "R3" }).sortKey == "R3" and Tweaks.Repair({ sortKey = "PAD1" }).sortKey == "L3" and Tweaks.Get("sortKey") == "L3", "sort key: L3 by default, R3 or off kept, anything else L3")
W.override = nil
W.advance(0.3)
check(W.override == nil and Tweaks.SortKeyWanted() == nil, "sort key: bags closed, nothing bound (the stick works as usual)")
backpackSpec.visible = true
W.advance(0.3)
check(W.override == "PADLSTICK->CLICK ForeverControllerTweaksSortKey (priority)", "sort key: bags open, L3 clicks our button, a priority binding: " .. tostring(W.override))
reset()
ForeverControllerTweaksSortKey:Click()
check(count("SortBags") == 1, "sort key: the press sorts")
W.held = { PADLTRIGGER = true }
ForeverControllerTweaksSortKey:Click()
W.held = {}
check(count("SortBags") == 1, "sort key: with a trigger held, nothing")
Tweaks.Set("sortKey", "R3")
W.advance(0.3)
check(W.override == "PADRSTICK->CLICK ForeverControllerTweaksSortKey (priority)", "sort key: R3")
W.fire("PLAYER_REGEN_DISABLED")
check(W.override == nil, "sort key: cleared as a fight starts")
W.combat = true
W.advance(0.3)
check(W.override == nil, "sort key: not set again in combat")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(W.override == "PADRSTICK->CLICK ForeverControllerTweaksSortKey (priority)", "sort key: back after the fight")
backpackSpec.visible = false
W.advance(0.3)
check(W.override == nil, "sort key: cleared when the bags close")
Tweaks.Set("sortKey", "off")
backpackSpec.visible = true
W.advance(0.3)
check(W.override == nil, "sort key: Off binds nothing")
backpackSpec.visible = false
Tweaks.Set("sortKey", "L3")
W.advance(0.3)

-- The footer prompt: "<stick> Sort" in our own footer segment while the key is bound. Combined bags: joined to the
-- right end of their gamepad footer as one box: over its 8-wide right cap, our art's own left cap clipped off; hidden
-- while that footer hides (the search box has the pad).
-- Separate bags: alone under the backpack. One strata above the bags. Never shown unbound: closed, Off, in combat.
local function sortPrompt()
	for _, f in ipairs(W.frames) do if f.glyph and f.label and f.label.text == Tweaks.T.SORT then return f end end
end
check(sortPrompt() == nil or not sortPrompt():IsShown(), "prompt: none while the bags are closed")
bagSpec.visible = true
W.advance(0.3)
local prompt = sortPrompt()
check(prompt and prompt:IsShown() and prompt.rel == bagLegend and prompt.point == "TOPLEFT" and prompt.x == -8 and prompt.h == 44, "prompt: joined to the combined bags' footer over its 8-wide right cap, 44 tall")
check(prompt.art.x == -8 and prompt.art.parent == prompt, "prompt: joined, the art starts a cap further left (its left cap clipped off: no line between Close and Sort)")
check(prompt.glyph.x == 13 and prompt.glyph.rel == prompt and prompt.glyph.parent == prompt.art, "prompt: the glyph 15 after Close's end (the native gap), clear of the covered cap")
check(prompt.glyph.code == "PADLSTICK" and prompt.label.text == "Sort" and prompt.strata == "HIGH" and prompt.w == 13 + 24 + 4 + #"Sort" * 6 + 10, "prompt: the L3 glyph, Sort, one strata above the bags, 10 to our right cap")
legendSpec.visible = false
W.advance(0.05)
check(not prompt:IsShown(), "prompt: hidden the frame the footer hides (search box focused)")
legendSpec.visible = true
W.advance(0.05)
check(prompt:IsShown(), "prompt: back with the footer")
Tweaks.Set("sortKey", "R3")
W.advance(0.3)
check(prompt:IsShown() and prompt.glyph.code == "PADRSTICK", "prompt: follows the key, R3")
Tweaks.Set("sortKey", "off")
W.advance(0.3)
check(not prompt:IsShown(), "prompt: Off, none")
Tweaks.Set("sortKey", "L3")
W.advance(0.3)
W.fire("PLAYER_REGEN_DISABLED")
W.combat = true
W.advance(0.3)
check(not prompt:IsShown(), "prompt: none in combat (the key isn't bound)")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(prompt:IsShown(), "prompt: back after the fight")
bagSpec.visible, backpackSpec.visible = false, true
W.advance(0.3)
check(prompt:IsShown() and prompt.rel == ContainerFrame1 and prompt.x == 0, "prompt: separate bags, alone under the backpack")
check(prompt.art.x == 0 and prompt.glyph.x == 10 and prompt.w == 10 + 24 + 4 + #"Sort" * 6 + 10, "prompt: separate bags, the whole frame (all four sides), the native padding")
backpackSpec.visible = false
W.advance(0.3)
check(not prompt:IsShown() and Tweaks.SortKeyBound() == nil, "prompt: gone with the bags")

-- 2. Sell junk: SellAllJunkItems when the client has it, with one line counting the greys that have a price.
turn("sellJunk")
junkBags()
reset()
W.fire("MERCHANT_SHOW")
check(count("SellAllJunkItems") == 1 and #W.log == 0, "sells all junk at once; the line waits for the bags")
W.advance(1.1)
check(saidPlain("Sold 3 junk items for 17c: [Linen Scrap] x2, [Broken Fang]."), "the line lists what sold, with counts: " .. tostring(W.log[1]))
-- Without it: one grey a step, priced ones only, stopping when the merchant closes.
C_MerchantFrame.SellAllJunkItems = nil
junkBags()
reset()
W.fire("MERCHANT_SHOW")
W.advance(0.25)
check(count("UseContainerItem") == 1, "one item per step")
W.advance(1.5)
check(count("UseContainerItem") == 2 and W.log[1]:find("Sold 3 junk items for 17c: [Linen Scrap] x2, [Broken Fang].", 1, true), "both priced greys sold, then the line with their links: " .. tostring(W.log[1]))
check(calls.UseContainerItem[1][2] == 1 and calls.UseContainerItem[2][2] == 3, "slots 1 and 3 (not the white, the priceless or the no-value one)")
junkBags()
reset()
W.fire("MERCHANT_SHOW")
W.fire("MERCHANT_CLOSED")
W.advance(1)
check(count("UseContainerItem") == 0 and #W.log == 0, "stops when the merchant closes; nothing sold, no line")
junkBags()
reset()
W.fire("MERCHANT_SHOW")
W.advance(0.25)
W.fire("MERCHANT_CLOSED")
W.advance(2)
check(count("UseContainerItem") == 1 and saidPlain("Sold 2 junk items for 10c: [Linen Scrap] x2."), "closed mid-run: only what sold before: " .. tostring(W.log[1]))
-- A sale the merchant refused (the item stays) is not listed.
local useItem = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot) record("UseContainerItem")(bag, slot) if slot == 1 then bags[bag][slot] = false end end
junkBags()
reset()
W.fire("MERCHANT_SHOW")
W.advance(2)
check(saidPlain("Sold 2 junk items for 10c: [Linen Scrap] x2."), "a refused item stays out of the line: " .. tostring(W.log[1]))
C_Container.UseContainerItem = useItem
-- Long lists: 8 links, then "and N more" (a secret link counts among the more).
C_MerchantFrame.SellAllJunkItems = sellAll
local many = {}
for i = 1, 10 do
	prices[100 + i] = 1
	many[i] = { itemID = 100 + i, quality = 0, stackCount = 1, hyperlink = "[Junk" .. i .. "]" }
end
prices[111] = 1
many[11] = { itemID = 111, quality = 0, stackCount = 1, hyperlink = SECRET }
bags = { [0] = many }
reset()
W.fire("MERCHANT_SHOW")
W.advance(1.1)
check(saidPlain("Sold 11 junk items for 11c: [Junk1], [Junk2], [Junk3], [Junk4], [Junk5], [Junk6], [Junk7], [Junk8], and 3 more."), "capped at 8 links: " .. tostring(W.log[1]))
C_MerchantFrame.SellAllJunkItems = nil
bags = {}
reset()
W.fire("MERCHANT_SHOW")
W.advance(1)
check(#W.log == 0, "no junk, no line")
Tweaks.Set("sellJunk", false)

-- 3. Repair: own money, or the guild's first when allowed and enough.
turn("repair")
reset()
W.fire("MERCHANT_SHOW")
check(count("RepairAllItems") == 1 and calls.RepairAllItems[1][1] == nil and said("Repaired for 500c"), "repairs with own money")
turn("repairGuild")
guildRepair, guildWithdraw, guildBank = true, 1000, 300
reset()
W.fire("MERCHANT_SHOW")
check(count("RepairAllItems") == 1 and calls.RepairAllItems[1][1] == nil, "the guild's limit (bank 300) doesn't cover it: own money")
guildWithdraw, guildBank = -1, 9000
reset()
W.fire("MERCHANT_SHOW")
check(count("RepairAllItems") == 1 and calls.RepairAllItems[1][1] == true and said("guild funds"), "guild funds first (unlimited withdraw)")
guildRepair, money = false, 100
reset()
W.fire("MERCHANT_SHOW")
check(count("RepairAllItems") == 0 and said("Not enough money"), "not enough money: says so, repairs nothing")
money, repairCost = 1000000, 0
reset()
W.fire("MERCHANT_SHOW")
check(count("RepairAllItems") == 0 and #W.log == 0, "nothing to repair: silent")
Tweaks.Set("repair", false)
Tweaks.Set("repairGuild", false)
W.fire("MERCHANT_CLOSED")

-- 4. Buy a full stack: a Stack button on each stackable row; the picker action buys the item under the gamepad cursor.
turn("buyStack")
local stacks = {}
for _, f in ipairs(W.frames) do if f.text == "Stack" and f.parent == UIParent then stacks[#stacks + 1] = f end end
check(#stacks == 10, "ten Stack buttons")
merchantSpec.visible = true
for i = 1, 4 do rowSpecs[i].visible = true end
W.advance(0.3)
check(stacks[1].shown and stacks[1].rel == MerchantItem1 and not stacks[2].shown and stacks[3].shown and not stacks[4].shown and not stacks[5].shown, "on stackable gold items only (not a single, an alt-currency item or an empty row)")
reset()
stacks[1]:Click()
check(count("BuyMerchantItem") == 1 and calls.BuyMerchantItem[1][1] == 1 and calls.BuyMerchantItem[1][2] == 20 and said("Bought 20 x Arrow"), "Stack buys a full stack")
money = 1000000000
stacks[3]:Click()
check(count("BuyMerchantItem") == 1 and said("Multi%-buy"), "a stack at Blizzard's confirm price is refused, pointing to Multi-buy")
money = 450
stacks[1]:Click()
check(calls.BuyMerchantItem[2][2] == 4, "as many as the money covers")
money = 50
reset()
stacks[1]:Click()
check(count("BuyMerchantItem") == 0 and said("Not enough money"), "none affordable")
money = 1000000
W.tooltipShown, W.tooltipOwner = true, MerchantItem1ItemButton
reset()
check(ns.Actions.TextFor("game:buystack") == "/click ForeverControllerTweaksBuyStack", "picker: Buy a full stack clicks our button")
ForeverControllerTweaksBuyStack:Click()
check(count("BuyMerchantItem") == 1 and calls.BuyMerchantItem[1][1] == 1 and calls.BuyMerchantItem[1][2] == 20, "the action buys the item under the cursor")
W.tooltipOwner = nil
reset()
ForeverControllerTweaksBuyStack:Click()
check(count("BuyMerchantItem") == 0 and said("Point the cursor"), "no item under the cursor: says so")
W.tooltipShown = false
merchantSpec.visible = false
W.advance(0.3)
check(not stacks[1].shown, "the buttons hide with the merchant")
Tweaks.Set("buyStack", false)

-- 5. Skip one-option talk: one option or one quest is picked, once per conversation; an option only with a service
-- icon (vendor, trainer, flight map, bank), never a priced, flagged, spell or chat-bubble one.
turn("skipGossip")
local function talk(options, available, active)
	gossip.options, gossip.available, gossip.active = options or {}, available or {}, active or {}
	W.fire("GOSSIP_SHOW")
end
local TAXI, VENDOR, CHAT = 132057, 132060, 132053
local fly = { gossipOptionID = 7, name = "Show me where I can fly.", icon = TAXI, status = 0, flags = 0, rewards = {} }
reset()
talk({ fly })
check(count("SelectOption") == 1 and calls.SelectOption[1][1] == 7, "one flight-map option: picked")
talk({ fly })
check(count("SelectOption") == 1, "once per conversation")
W.fire("QUEST_FINISHED")
talk({ fly })
check(count("SelectOption") == 1, "a quest page closing isn't the end of the talk: not picked again")
W.fire("GOSSIP_CLOSED")
talk({ { gossipOptionID = 6, name = "Let me browse your goods.", icon = VENDOR, status = 0, flags = 0, rewards = {} } })
check(count("SelectOption") == 2 and calls.SelectOption[2][1] == 6, "after GOSSIP_CLOSED, a vendor option: picked")
W.fire("GOSSIP_CLOSED")
talk({ fly, { gossipOptionID = 8, name = "Bye", status = 0, flags = 0, rewards = {} } })
check(count("SelectOption") == 2, "two options: left to the player")
W.fire("GOSSIP_CLOSED")
talk({ fly }, { { questID = 99 } })
check(count("SelectOption") == 2 and count("SelectAvailableQuest") == 0, "an option and a quest: left alone")
W.fire("GOSSIP_CLOSED")
talk({}, { { questID = 97, isIgnored = true } })
check(count("SelectAvailableQuest") == 0, "an ignored quest: left alone")
W.fire("GOSSIP_CLOSED")
talk({}, { { questID = 99 } })
check(count("SelectAvailableQuest") == 1 and calls.SelectAvailableQuest[1][1] == 99, "one available quest: picked")
W.fire("GOSSIP_CLOSED")
talk({}, {}, { { questID = 98 } })
check(count("SelectActiveQuest") == 1 and calls.SelectActiveQuest[1][1] == 98, "one active quest: picked")
for _, bad in ipairs({
	{ gossipOptionID = 9, name = "Learn", icon = VENDOR, status = 0, flags = 0, rewards = { { id = 1, quantity = 10, rewardType = 1 } } },
	{ gossipOptionID = 9, name = "Locked", icon = VENDOR, status = 2, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Quest", icon = VENDOR, status = 0, flags = 1, rewards = {} },
	{ gossipOptionID = 9, name = "Auto", icon = VENDOR, status = 0, flags = 0, rewards = {}, selectOptionWhenOnlyOption = true },
	{ gossipOptionID = 9, name = "Pay |TInterface\\MoneyFrame\\UI-GoldIcon:0|t", icon = VENDOR, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = SECRET, icon = VENDOR, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Take me to the Dark Portal.", icon = CHAT, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "I'm ready to begin.", icon = CHAT, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Skip the story.", status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Fly", icon = TAXI, overrideIconID = CHAT, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Portal", icon = VENDOR, spellID = 3565, status = 0, flags = 0, rewards = {} },
	{ gossipOptionID = 9, name = "Hidden", icon = SECRET, status = 0, flags = 0, rewards = {} },
}) do
	W.fire("GOSSIP_CLOSED")
	talk({ bad })
end
check(count("SelectOption") == 2, "a cost, a lock, a flag, an auto-pick, a priced or secret label, a chat bubble (teleport, event start), no icon, an overriding chat icon, a spell, a secret icon: never picked")
check(Tweaks.SafeOption(fly) and Tweaks.SAFE_GOSSIP_ICONS[132058] == "trainer" and Tweaks.SAFE_GOSSIP_ICONS[132050] == "banker", "the allowlist: vendor, trainer, flight map, bank")
W.fire("GOSSIP_CLOSED")
gossip.force = true
talk({ fly })
check(count("SelectOption") == 2, "an NPC that forces its gossip: shown")
gossip.force = false
W.fire("GOSSIP_CLOSED")
greeting.available = 1
W.fire("QUEST_GREETING")
check(count("GreetingAvailable") == 1, "a quest greeting with one quest: picked")
W.fire("QUEST_GREETING")
check(count("GreetingAvailable") == 1, "once per greeting window")
W.fire("QUEST_FINISHED")

greeting.available, greeting.active = 1, 1
W.fire("QUEST_GREETING")
check(count("GreetingAvailable") == 1 and count("GreetingActive") == 0, "two quests: left alone")
Tweaks.Set("skipGossip", false)

-- 6. Trainer: Learn all on the trainer buys every affordable available service, last first, a step apart.
turn("learnAll")
local learn
for _, f in ipairs(W.frames) do if f.text == "Learn all" then learn = f end end
check(learn and not learn.shown, "Learn all: hidden while no trainer shows")
trainSpec.visible = true
W.advance(0.3)
check(learn.shown and learn.rel == ClassTrainerTrainButton and learn.point == "RIGHT", "beside the (hidden) Train button while the trainer shows")
services = { { kind = "available", cost = 100 }, { kind = "unavailable", cost = 1 }, { kind = "used", cost = 1 }, { kind = "available", cost = 300 }, { kind = "available", cost = 5000 } }
money = 500
W.fire("TRAINER_SHOW")
reset()
learn:Click()
W.advance(1.5)
check(count("BuyTrainerService") == 2 and calls.BuyTrainerService[1][1] == 4 and calls.BuyTrainerService[2][1] == 1, "learns 4 then 1; not the one it can't afford")
check(said("Learned 2 skills for 400c"), "one line with the cost")
services[1].kind, money = "available", 1000
reset()
learn:Click()
W.fire("TRAINER_CLOSED")
W.advance(1)
check(count("BuyTrainerService") == 0, "stops when the trainer closes")
trainSpec.visible, money = false, 1000000
Tweaks.Set("learnAll", false)

-- 7. Mail: Open all where Blizzard's own button sits, money then items, skipping COD and GM mail, stopping on full bags.
turn("openMail")
local mail
for _, f in ipairs(W.frames) do if f.text == "Open all" then mail = f end end
inboxSpec.visible = true
W.advance(0.3)
check(mail.shown and mail.rel == InboxFrame.OpenAllMail, "Open all on the inbox, at Blizzard's Open All spot (hidden in the Gamepad UI)")
mails = { { money = 250, cod = 0, items = { "Ore" } }, { money = 0, cod = 50, items = { "Bad" } }, { money = 0, cod = 0, items = { "Herb", "Silk" } }, { money = 900, cod = 0, items = {}, gm = true } }
W.fire("MAIL_SHOW")
reset()
mail:Click()
W.advance(3)
check(count("TakeInboxMoney") == 1 and count("TakeInboxItem") == 3, "money and three items: " .. count("TakeInboxMoney") .. ", " .. count("TakeInboxItem"))
for _, c in ipairs(calls.TakeInboxItem) do check(c[1] ~= 2, "COD mail is skipped") end
check(said("Opened mail: 3 items and 250c"), "one line")
mails, freeSlots = { { money = 0, cod = 0, items = { "Ore", "Ore" } } }, 1
reset()
mail:Click()
W.advance(2)
check(count("TakeInboxItem") == 1 and said("bags are full"), "stops when the bags are full")
mails, freeSlots = { { money = 0, cod = 0, items = { "Ore" } } }, 10
reset()
mail:Click()
W.fire("MAIL_CLOSED")
W.advance(1)
check(count("TakeInboxItem") == 0, "stops when the mailbox closes")
inboxSpec.visible = false
W.advance(0.3)
check(not mail.shown, "hides with the inbox")
Tweaks.Set("openMail", false)

-- 8. Invites: a friend, Battle.net friend or guildmate; never a stranger, a role check, a quest session or a secret.
turn("acceptInvites")
reset()
local function invite(guid, tank, quest) W.fire("PARTY_INVITE_REQUEST", "Fred", tank or false, false, false, true, false, false, guid, quest or false) end
invite("Player-1-FRIEND")
invite("Player-1-BNET")
invite("Player-1-GUILD")
check(count("AcceptGroup") == 3 and said("Accepted the group invite from Fred"), "friend, Battle.net friend, guildmate")
invite("Player-1-STRANGER")
invite("Player-1-FRIEND", true)
invite("Player-1-FRIEND", false, true)
invite(SECRET)
check(count("AcceptGroup") == 3, "a stranger, a role check, a quest session invite or a secret GUID: left to the player")
queued = true
invite("Player-1-GUILD")
queued = false
check(count("AcceptGroup") == 3, "a guildmate's invite that would drop a dungeon or PvP queue: left to the player")
W.fire("PARTY_INVITE_REQUEST", SECRET, false, false, false, true, false, false, "Player-1-FRIEND", false)
check(count("AcceptGroup") == 4 and said("from someone"), "a secret name is never printed")
Tweaks.Set("acceptInvites", false)

-- 9. Duels.
turn("declineDuels")
reset()
W.fire("DUEL_REQUESTED", "Fred")
check(count("CancelDuel") == 1 and said("Declined a duel from Fred"), "declined")
Tweaks.Set("declineDuels", false)

-- 10. Resurrect and summon: out of combat, never with sickness.
turn("acceptRes")
reset()
W.fire("RESURRECT_REQUEST", "Pat")
check(count("AcceptResurrect") == 1 and said("resurrection from Pat"), "resurrection accepted")
sickness = true
W.fire("RESURRECT_REQUEST", "Pat")
sickness, W.combat = false, true
W.fire("RESURRECT_REQUEST", "Pat")
W.fire("CONFIRM_SUMMON")
W.combat = false
check(count("AcceptResurrect") == 1 and count("ConfirmSummon") == 0, "not with sickness, not in combat")
W.fire("CONFIRM_SUMMON")
check(count("ConfirmSummon") == 1 and said("summon from Ann to Goldshire"), "a friend's summon: accepted")
local function summonFrom(who)
	C_SummonInfo.GetSummonConfirmSummoner = function() return who end
	W.fire("CONFIRM_SUMMON")
end
summonFrom("Gil-Stormrage")
summonFrom("Hal")
summonFrom("Bea")
check(count("ConfirmSummon") == 4, "a guildmate on another realm, one on mine by short name, a Battle.net friend: accepted")
summonFrom("Stranger")
summonFrom("Gil")
summonFrom(SECRET)
summonFrom(nil)
check(count("ConfirmSummon") == 4, "a stranger, a guildmate's name on the wrong realm, a secret or missing name: left to the player")
check(Tweaks.TrustedName("Bea-ArgentDawn") and not Tweaks.TrustedName("Bea-Stormrage") and Tweaks.Trusted("Player-1-FRIEND") and not Tweaks.Trusted(SECRET), "trust by name and by GUID")
C_SummonInfo.GetSummonConfirmSummoner = function() return "Ann" end
W.instance = "party"

W.fire("CONFIRM_SUMMON")
W.instance = nil
check(count("ConfirmSummon") == 4, "never inside an instance")
function PlayerCanTeleport() return false end
W.fire("CONFIRM_SUMMON")
check(count("ConfirmSummon") == 4, "not while the game says no teleport")


-- 11. Light bar: written only on a change, cleared only after we set it.
reset()
Tweaks.Set("lightBar", "default")
check(count("SetLedColor") == 0 and count("ClearLedColor") == 0, "Game default never touches the light")
Tweaks.Set("lightBar", "class")
check(count("SetLedColor") == 1 and calls.SetLedColor[1][1] == 0.25 and calls.SetLedColor[1][3] == 0.92, "Class colour")
Tweaks.Set("lightBar", "class")
W.fire("PLAYER_ENTERING_WORLD")
check(count("SetLedColor") == 1, "the same colour is not written again")
W.fire("GAME_PAD_CONNECTED")
check(count("SetLedColor") == 2, "a controller plugged in gets it again")
local lightChoices = table.concat(Tweaks.CHOICES.lightBar, " ")
check(lightChoices == "default class custom", "no Health on the light bar: " .. lightChoices)
check(Tweaks.Repair({ lightBar = "health" }).lightBar == "custom", "a saved Health becomes Custom, the player's own colour")
reset()
W.fire("UNIT_HEALTH", "player")
check(count("SetLedColor") == 0 and count("ClearLedColor") == 0, "the player's health never writes the light")
Tweaks.Set("lightBar", "custom")
Tweaks.Set("lightColor", "purple")
check(calls.SetLedColor[#calls.SetLedColor][1] == 0.6 and calls.SetLedColor[#calls.SetLedColor][3] == 1, "Custom: the picked colour")
Tweaks.Set("lightColor", "nope")
check(ns.db.tweaks.lightColor == "red", "an unknown colour repairs to the first")
Tweaks.Set("lightColor", "blue")
Tweaks.Set("combatFlash", true)
reset()
W.fire("PLAYER_REGEN_DISABLED")
check(count("SetLedColor") == 1 and calls.SetLedColor[1][1] == 1 and calls.SetLedColor[1][2] == 0, "Combat flash: red in a fight")
W.fire("PLAYER_REGEN_ENABLED")
check(count("SetLedColor") == 2 and calls.SetLedColor[2][3] == 1, "then back to the colour before")
Tweaks.Set("lightBar", "default")
check(count("ClearLedColor") == 1, "back to Game default gives the light back")
W.fire("PLAYER_REGEN_DISABLED")
W.fire("PLAYER_REGEN_ENABLED")
check(count("SetLedColor") == 3 and count("ClearLedColor") == 2, "Combat flash on Game default: red, then the game's own")
Tweaks.Set("combatFlash", false)
Tweaks.Set("lightBar", "class")
reset()
W.fire("PLAYER_LOGOUT")
check(count("ClearLedColor") == 1, "logout gives the light back")
Tweaks.Set("lightBar", "class")
W.gamepadUI = false
reset()
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
check(count("ClearLedColor") == 1, "the Gamepad UI going off gives the light back")
W.gamepadUI = true
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1)
Tweaks.Set("lightBar", "default")

-- Batch 2 stubs: rumble, battery, vignettes and name plates, loot, rolls, gear, quests.
C_GamePad.SetVibration = record("SetVibration")
C_GamePad.StopVibration = record("StopVibration")
local function noticeFrame()
	for _, f in ipairs(W.frames) do if f.parent == UIParent and f.title and f.text and type(f.text) == "table" and f.text.SetMaxLines then return f end end
end
local function noticeSays() local f = noticeFrame() return f and f.shown and (f.title.text .. " | " .. f.text.text) or "" end

-- 12. Rumble on events: each event plays its own pattern at its own strength; only events the player must answer.
Tweaks.Set("acceptRes", false)
turn("rumble")
Tweaks.Set("rumbleStrength", 0.8)
ns.db.options.debug = true
reset()
W.fire("READY_CHECK", "Bob")
check(count("StopVibration") == 0 and count("SetVibration") == 2 and calls.SetVibration[1][1] == "High" and calls.SetVibration[2][1] == "Low" and calls.SetVibration[2][2] == 0.8, "a ready check: Double tap at its strength, the heavy motor last, no stop first")
W.advance(0.15)
check(count("SetVibration") == 2 and count("StopVibration") == 1, "then the gap: motors stopped")
W.advance(0.12)
check(count("SetVibration") == 4 and count("StopVibration") == 1, "the second tap")
W.advance(0.5)
check(count("SetVibration") == 4 and count("StopVibration") == 2, "then stopped: tap, gap, tap, end")
local logged = false
for _, line in ipairs(ns.db.debugLog) do if line:find("rumble readyCheck: double at 80%%, device 1: High true, Low true") then logged = true end end
check(logged, "/fct debug logs each pattern, its result and the pad: " .. tostring(ns.db.debugLog[#ns.db.debugLog]))
ns.db.options.debug = false
-- The patterns.
local P = Tweaks.PATTERNS
for _, name in ipairs(Tweaks.PATTERN_ORDER) do check(name == "off" or P[name], name .. " exists") end
local function length(name) local t = 0 for _, step in ipairs(P[name]) do t = t + step[1] end return t end
check(#P.double == 3 and #P.triple == 5 and P.double[2][2] == nil, "taps with gaps between")
check(math.abs(length("long") - 0.8) < 1e-9 and #P.heartbeat == 7, "Long buzz 0.8 s; Heartbeat two double beats")
check(P.ramp[1][2] < P.ramp[4][2] and P.fade[1][2] > P.fade[4][2], "Ramp up rises, Fade out falls")
reset()
Tweaks.PlayPattern("tap", 1, "spec")
check(count("SetVibration") == 2 and calls.SetVibration[1][1] == "High" and calls.SetVibration[2][1] == "Low" and calls.SetVibration[2][2] == 1, "a pattern runs the two motors, the heavy one last")
Tweaks.PlayPattern("tap", nil, "spec")
check(calls.SetVibration[4][2] == 0.8, "with no strength given, the Rumble strength")
W.advance(0.5)
reset()
Tweaks.PlayPattern("long", 0.8, "spec")
W.advance(0.9)
check(count("SetVibration") == 8 and count("StopVibration") == 1, "Long buzz: four steps with no stop between them, one stop at the end")
check(calls.SetVibration[1][1] == "High" and calls.SetVibration[1][2] == 0.5, "the High motor's half share at 80% (0.4) runs at the 0.5 floor")
check(Tweaks.MotorPower("High", 1, 0.1) == 0.5 and Tweaks.MotorPower("High", nil, 1) == 0 and Tweaks.MotorPower("Low", 1, 0.1) == 0.1 and Tweaks.MotorPower("High", 1, 0.9) == 0.9, "the floor: High never under 0.5 unless off; Low as set")
reset()
Tweaks.PlayPattern("long", 1, "spec")

W.advance(0.1)
Tweaks.PlayPattern("tap", 0.5, "spec")
W.advance(1)
check(count("SetVibration") == 4 and calls.SetVibration[4][2] == 0.5, "a new pattern replaces a running one: never stacked")
-- The events' wiring.
reset()
W.fire("READY_CHECK", "Ann")
W.fire("LOSS_OF_CONTROL_ADDED", "target")
check(count("SetVibration") == 0, "not for my own ready check or another unit's stun")
-- Procs start Off: on for these checks.
Tweaks.SetRumbleGroup("procs", "tap")
for _, case in ipairs({
	{ "death", "PLAYER_DEAD" }, { "lossOfControl", "LOSS_OF_CONTROL_ADDED", "player" }, { "levelUp", "PLAYER_LEVEL_UP", 10 },
	{ "trade", "TRADE_REQUEST", "Bob" }, { "duel", "DUEL_REQUESTED", "Bob" }, { "summon", "CONFIRM_SUMMON" },
	{ "resurrect", "RESURRECT_REQUEST", "Bob" }, { "whisper", "CHAT_MSG_WHISPER", "hi", "Bob" },
	{ "invite", "PARTY_INVITE_REQUEST", "Bob", false, false, false, true, false, false, "Player-1-STRANGER", false },
	{ "interrupted", "UNIT_SPELLCAST_INTERRUPTED", "player" }, { "proc", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 133 },
	{ "achievement", "ACHIEVEMENT_EARNED", 6 },
}) do
	W.advance(3)
	reset()
	ns.db.options.debug = true
	W.fire(unpack(case, 2))
	ns.db.options.debug = false
	local line = ns.db.debugLog[#ns.db.debugLog] or ""
	check(count("SetVibration") >= 1 and line:find("rumble " .. case[1] .. ": " .. Tweaks.RumblePattern(case[1]), 1, true), case[2] .. " plays " .. case[1] .. "'s group pattern: " .. line)
end
reset()
W.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
check(count("SetVibration") == 0, "another unit's interrupted cast: nothing")
W.advance(3)
reset()
W.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 133)
W.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 134)
W.advance(1)
local procs = count("SetVibration")
W.advance(1.2)
W.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 135)
check(procs == 2 and count("SetVibration") == 4, "procs: a 2 s cooldown")
W.advance(3)
local unpackAll = table.unpack or unpack
for _, case in ipairs({
	{ "whisper", "CHAT_MSG_WHISPER", "hi", "Bob" }, { "trade", "TRADE_REQUEST", "Bob" },
	{ "invite", "PARTY_INVITE_REQUEST", "Bob", false, false, false, true, false, false, "Player-1-STRANGER", false },
}) do
	local function fire() W.fire(select(2, unpackAll(case))) end
	reset()
	fire()
	W.advance(0.5)
	local first = count("SetVibration")
	fire()
	W.advance(2)
	fire()
	local held = count("SetVibration")
	W.advance(1.2)
	fire()
	check(Tweaks.RUMBLE_COOLDOWN[case[1]] == 3 and first >= 2 and held == first and count("SetVibration") > held, case[1] .. ": a 3 s cooldown")
	W.advance(2)
end


local threatNow = 0
function UnitThreatSituation() return threatNow end
reset()
threatNow = 3
W.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
W.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
W.fire("UNIT_THREAT_SITUATION_UPDATE", "target")
check(count("SetVibration") == 2, "aggro: once when it turns to 3 (Danger's Long buzz, first step)")
W.advance(4)
threatNow = SECRET
W.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
threatNow = 0
W.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
threatNow = 3
reset()
W.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
check(count("SetVibration") == 2, "lost and gained again: again; a secret state compares nothing")
W.advance(4)
local targetIsDead = false
function UnitIsDead() return targetIsDead end
function UnitCanAttack() return true end
W.fire("PLAYER_TARGET_CHANGED")
reset()
W.fire("UNIT_HEALTH", "target")
targetIsDead = true
W.fire("UNIT_HEALTH", "target")
W.fire("UNIT_HEALTH", "target")
check(count("SetVibration") == 2, "target died: once")
W.advance(3)
-- Critical strike on an enemy target, solo only; 1 s cooldown. Hostility is read when the target changes.
local grouped, canAttack = false, true
function IsInGroup() return grouped end
function UnitCanAttack() return canAttack end
local function newTarget(enemy)
	targetIsDead, canAttack = false, enemy
	W.fire("PLAYER_TARGET_CHANGED")
end
newTarget(true)
reset()
W.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", SECRET, 1)
W.advance(0.5)
local first = count("SetVibration")
W.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", SECRET, 1)
W.advance(0.2)
check(Tweaks.RUMBLE_GROUP_OF.crit == "procs" and first >= 1 and count("SetVibration") == first, "a crit on an enemy target: one rumble, then a 1 s cooldown")
W.advance(1)
W.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", SECRET, 1)
check(count("SetVibration") > first, "after the cooldown: again")
W.advance(2)
for _, case in ipairs({
	{ "in a group", true, true, "target", "WOUND", "CRITICAL" }, { "a hit that isn't a crit", false, true, "target", "WOUND", "" },
	{ "a friendly target", false, false, "target", "WOUND", "CRITICAL" }, { "the player's own unit", false, true, "player", "WOUND", "CRITICAL" },
	{ "a crit heal", false, true, "target", "HEAL", "CRITICAL" }, { "a secret unit", false, true, SECRET, "WOUND", "CRITICAL" },
}) do
	grouped = case[2]
	newTarget(case[3])
	reset()
	W.fire("UNIT_COMBAT", case[4], case[5], case[6], SECRET, 1)
	check(count("SetVibration") == 0, "crit: nothing for " .. case[1])
	W.advance(2)
end
grouped = false
-- A killing blow: the dead target is no longer attackable, and a crit that kills rumbles once (one shared cooldown).
local function kill(crit)
	reset()
	targetIsDead, canAttack = true, false
	if crit then W.fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", SECRET, 1) end
	W.fire("UNIT_HEALTH", "target")
	W.advance(0.5)
	local played = count("SetVibration")
	W.advance(2)
	return played
end
newTarget(true)
check(kill(true) == first, "a crit that kills an enemy: one rumble")
newTarget(true)
check(kill(false) == first, "a kill without a crit: one rumble")
newTarget(false)
check(kill(true) == 0, "a friendly target: no rumble, crit or death")
newTarget(true)
canAttack = false
W.fire("UNIT_FACTION", "target")
check(kill(true) == 0, "a target that turns friendly: no rumble")
function IsInGroup() return false end
Tweaks.SetRumbleGroup("tradeDuel", "off")
reset()
W.fire("TRADE_REQUEST", "Bob")
check(count("SetVibration") == 0, "Off: that event is quiet")
-- Enemy player nearby: an other-faction player's name plate; once per player per 2 minutes, one rumble per group
-- (10 s), never in battlegrounds, arenas or sanctuaries; any secret skips the unit; the card says who.
local foes = {
	nameplate1 = { true, true, "Horde", "Horde", "Grim", "Player-1-A", 22 }, nameplate2 = { true, true, "Horde", "Horde", "Kor", "Player-1-B", 30 },
	nameplate3 = { false, true, "Horde", "Horde", "Boar", "Creature-9", 10 }, nameplate4 = { true, false, "Alliance", "Alliance", "Pal", "Player-1-C", 30 },
	nameplate5 = { true, true, "Horde", "Horde", SECRET, "Player-1-D", 30 }, nameplate6 = { true, true, "Horde", "Horde", "Ogg", "Player-1-E", 40 },
}
function UnitIsPlayer(unit) return foes[unit] and foes[unit][1] end
function UnitIsEnemy(_, unit) return foes[unit] and foes[unit][2] end
function UnitFactionGroup(unit) if unit == "player" then return "Alliance", "Alliance" end return foes[unit][3], foes[unit][4] end
function UnitName(unit) return foes[unit] and foes[unit][5] or "Ann" end
function UnitGUID(unit) return foes[unit] and foes[unit][6] or unit == "player" and "Player-0-Ann" or nil end
function UnitLevel(unit) return foes[unit] and foes[unit][7] or 10 end
local zone = "contested"
C_PvP = { GetZonePVPInfo = function() return zone end }
check(Tweaks.RumblePattern("enemy") == "double", "Enemies starts as Double tap")
W.advance(11)
reset()
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
check(count("SetVibration") == 0, "an NPC, a friendly player or a secret name: nothing")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(count("SetVibration") == 2 and calls.SetVibration[2][2] == 0.8 and noticeSays() == "Horde nearby | Grim, level 22", "an enemy player: the rumble at the strength and the card: " .. noticeSays())
reset()
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
check(count("SetVibration") == 0, "the rest of the group within 10 s: no second rumble")
W.advance(11)
reset()
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
check(count("SetVibration") == 0, "players already seen wait 2 minutes, the group's ones too")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
check(count("SetVibration") == 2, "a new player after the cooldown: again")
W.advance(121)
reset()
W.instance = "pvp"
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
W.instance = "arena"
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
W.instance = nil
zone = "sanctuary"
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(count("SetVibration") == 0, "not in a battleground, an arena or a sanctuary")
zone = "contested"
reset()
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(count("SetVibration") == 2, "out in the world again, after 2 minutes: again")
W.advance(11)
function UnitIsPlayer() return false end
turn("declineDuels")
reset()
W.fire("DUEL_REQUESTED", "Bob")
check(count("CancelDuel") == 1 and count("SetVibration") == 0, "a duel a tweak declines doesn't rumble")
Tweaks.Set("declineDuels", false)
Tweaks.Set("rumble", false)
reset()
W.fire("PLAYER_DEAD")
check(count("SetVibration") == 0, "Rumble off: nothing")
-- Y on a group's row plays its pattern; Y on Strength a Double tap; Rumble on events on or not. A pick from a group's
-- list plays its pattern once; Strength, grabbed, plays the test on each change.
UI.TweaksTab.Open()
local tab = UI.Current()
for _, key in ipairs({ "rumble:danger", "rumbleStrength" }) do
	for _, node in ipairs(tab.nodes) do if node.region.key == key then tab:Focus(node) end end
	check(tab.focus.tip.actions and tab.focus.tip.actions[1][1] == "PAD4" and tab.focus.tip.actions[1][2] == "Test", key .. ": the tooltip offers Y: Test")
	reset()
	ns.db.options.debug = true
	W.press(tab, "PAD4")
	ns.db.options.debug = false
	local line = ns.db.debugLog[#ns.db.debugLog] or ""
	check(count("SetVibration") == 2 and calls.SetVibration[2][2] == 0.8 and line:find(key == "rumbleStrength" and ": double at 80%" or ": long at 80%", 1, true) and ns.db.tweaks.rumbleGroups.danger == "long" and not UI.DialogShown(), key .. ": Y plays the test, changes nothing, opens no More: " .. line)
	W.advance(1)
	reset()
	W.press(tab, "PAD1")
	local list = key == "rumble:danger"
	check(count("SetVibration") == 0 and (list and D.open(tab) or not list and tab.editing), key .. (list and ": A opens its list" or ": A grabs it") .. ", no test")
	W.press(tab, list and "PADDDOWN" or "PADDLEFT")
	check(count("SetVibration") == 0 or not list, key .. ": moving in the list plays nothing")
	if list then W.press(tab, "PAD1") end
	check(count("SetVibration") == 2 and (not list or ns.db.tweaks.rumbleGroups.danger == "heartbeat"), key .. (list and ": a pick plays the pattern once" or ": a change plays the test once"))
	W.advance(1)
	if list then
		W.press(tab, "PAD1")
		W.press(tab, "PADDUP")
		W.press(tab, "PAD1")
	else
		W.press(tab, "PADDRIGHT")
		W.press(tab, "PAD1")
	end
	check(not tab.editing and not D.open(tab) and ns.db.tweaks.rumbleGroups.danger == "long" and ns.db.tweaks.rumbleStrength == 0.8, key .. ": back")
	W.advance(1)
end
UI.CloseAll()

-- 13. Low battery: once a session, only for a drop the game reports after Medium or High.
turn("battery")
reset()
W.fire("GAME_PAD_POWER_CHANGED", 1)
check(#W.log == 0, "a Low with nothing before it (no battery reported yet) doesn't warn")
W.fire("GAME_PAD_POWER_CHANGED", 3)
W.fire("GAME_PAD_POWER_CHANGED", 1)
check(said("battery is low"), "High then Low warns")
reset()
W.fire("GAME_PAD_POWER_CHANGED", 2)
W.fire("GAME_PAD_POWER_CHANGED", 0)
check(#W.log == 0, "once a session")

-- 13b. Battery on the minimap: a round minimap button of our own on the ring with its neighbours, a tinted icon and a
-- level bar, hidden without a battery.
-- The spot: the neighbours' radius, one of their steps below the lowest on the left side.
local function near(a, b) return math.abs(a - b) < 0.01 end
-- Within a unit: a measured radius carries float noise, which can round a .5 the other way.
local function at(frame, x, y) return math.abs(frame.x - x) <= 1 and math.abs(frame.y - y) <= 1 end
local r, a = Tweaks.BatterySpot({ { angle = 135, radius = 96 }, { angle = 155, radius = 98 }, { angle = 175, radius = 97 }, { angle = 195, radius = 97 }, { angle = 30, radius = 97 } }, 184)
check(near(r, 97) and near(a, 215), "four left-edge neighbours 20 apart down to 195: radius 97, angle 215 (" .. r .. ", " .. a .. ")")
r, a = Tweaks.BatterySpot({ { angle = 160, radius = 100 } }, 184)
check(near(r, 100) and near(a, 182), "one neighbour: its radius, 22 below it")
r, a = Tweaks.BatterySpot({}, 184)
check(near(r, 98) and near(a, 220), "none: the game's own button radius (half width + 6) at 220")
-- Forever's minimap (Blizzard_Minimap/Mainline/Minimap.xml): a 198 map, the 215 x 226 MinimapBackdrop centred on it,
-- ExpansionLandingPageMinimapButton 53 units at its TOPLEFT -3, -150: that button's centre from the map's centre.
local nx, ny = -3 + 53 / 2 - 215 / 2, -150 - 53 / 2 + 226 / 2
r, a = Tweaks.BatterySpot({}, 198)
check(math.abs(r - math.sqrt(nx * nx + ny * ny)) < 1 and math.abs(a - (math.deg(math.atan2 and math.atan2(ny, nx) or math.atan(ny, nx)) % 360)) < 5, "none: on the native button's ring radius, beside it (" .. r .. " vs " .. math.sqrt(nx * nx + ny * ny) .. ")")
-- Layer: over the ring art's frame (a child of the map, a level up), in the highest strata of the two.
local function frameAt(strata, level) return { GetFrameStrata = function() return strata end, GetFrameLevel = function() return level end } end
local strata, lvl = Tweaks.BatteryLayer({ frameAt("LOW", 3), frameAt("LOW", 4) })
check(strata == "LOW" and lvl == 14, "over the ring frame: its strata, ten over its level")
strata, lvl = Tweaks.BatteryLayer({ frameAt("LOW", 30), frameAt("MEDIUM", 2) })
check(strata == "MEDIUM" and lvl == 12, "a ring frame in a higher strata wins")
strata, lvl = Tweaks.BatteryLayer({ frameAt("LOW", 9995) })
check(lvl == 10000, "never past the level cap")
r, a = Tweaks.BatterySpot({ { angle = 200, radius = 97 }, { angle = 240, radius = 97 } }, 184)
check(near(a, 250), "never past 250 (the coordinates text is at the bottom)")
local ox, oy = Tweaks.BatteryOffset(100, 180)
check(ox == -100 and oy == 0, "the offset from the map's centre")

local function batteryFrame() for _, f in ipairs(W.frames) do if f.segments and f.edge and f.ring and f.parent == UIParent then return f end end end
-- The lit segments' count, the first segment's colour, and whether every segment past the lit ones is dark.
local function level()
	local b = batteryFrame()
	local lit, dark = 0, true
	for _, segment in ipairs(b.segments) do
		local c = segment.color
		if c[4] == 1 then lit = lit + 1 else dark = dark and c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0.6 end
	end
	return lit, b.segments[1].color, dark, b.bars
end
local padLevel = 3
C_GamePad.GetPowerLevel = function() return padLevel end
Minimap.IsVisible = function() return true end
Minimap.GetCenter = function() return 500, 400 end
-- Three neighbours (any addon's round minimap buttons): on the ring at radius 75 (half of 140 + 5), 20 apart.
local function neighbour(name, angle)
	local button = CreateFrame("Button", name, Minimap)
	button:SetSize(31, 31)
	button.IsObjectType = function(_, kind) return kind == "Button" end
	local rad = math.rad(angle)
	button.GetCenter = function() return 500 + 75 * math.cos(rad), 400 + 75 * math.sin(rad) end
	return button
end
neighbour("LibDBIcon10_A", 150)
neighbour("LibDBIcon10_B", 170)
local lowest = neighbour("LibDBIcon10_C", 190)
-- The ring art's frame, raised over the map (a toplevel cluster's children shift with it).
MinimapBackdrop = { GetFrameStrata = function() return Minimap:GetFrameStrata() end, GetFrameLevel = function() return Minimap:GetFrameLevel() + 12 end }
MinimapCompassTexture = { GetParent = function() return MinimapBackdrop end }
turn("batteryIcon")
check(batteryFrame(), "turned on: the button is made")
W.fire("PLAYER_ENTERING_WORLD")
W.advance(0.3)
local b = batteryFrame()
local textures = {}
for _, tex in ipairs(b.textures or {}) do if tex.texture then textures[tex.texture] = tex end end
check(b.kind == "Button" and b.w == 31 and b.parent == UIParent, "a 31-unit button of our own, like its neighbours")
check(textures["Interface\\Minimap\\MiniMap-TrackingBorder"] and textures["Interface\\Minimap\\UI-Minimap-Background"], "the game's gold ring and dark round background")
check(not textures["Interface\\Icons\\Spell_Nature_Lightning"] and #b.textures == 11, "no icon art: background, ring, five outline pieces and four segments")
local edge = b.edge
check(edge.top.w == 15 and edge.top.h == 1 and edge.left.w == 1 and edge.left.h == 9 and edge.bottom.w == 15 and edge.right.h == 9, "a 15 x 9 body with a one-pixel outline at scale 1")
check(edge.bottom.rel == edge.top and edge.bottom.y == -8 and edge.right.point == "TOPRIGHT" and edge.right.rel == edge.top, "bottom and right edges hang off the top edge")
check(edge.cap.w == 2 and edge.cap.h == 3 and edge.cap.rel == edge.top and edge.cap.x == 0 and edge.cap.y == -3, "a 2 x 3 cap centred on the right")
check(edge.top.color[1] == 0.9 and edge.cap.color[1] == 0.9 and edge.top.color[4] == 1, "the outline in parchment")
local s1, s4 = b.segments[1], b.segments[4]
check(s1.w == 2 and s1.h == 5 and s1.x == 2 and s1.y == -2 and s4.x == 11 and s4.w == 2, "four 2 x 5 segments with one-pixel gaps, inside the outline")
check(edge.top.rel == b and edge.top.point == "TOPLEFT" and edge.top.x == -8 and edge.top.y == 5, "the battery centred, one unit up, as the icon was")
local x, y = Tweaks.BatteryOffset(75, 210)
check(b.level == Minimap:GetFrameLevel() + 22 and b.strata == Minimap:GetFrameStrata(), "drawn over the ring art's frame, not just the map: " .. tostring(b.level) .. " " .. tostring(b.strata))
check(b.shown and b.rel == Minimap and b.point == "CENTER" and at(b, x, y), "on the ring with its neighbours: radius 75, one step (20) below the lowest (190): " .. tostring(b.x) .. ", " .. tostring(b.y) .. " want " .. x .. ", " .. y .. " shown " .. tostring(b.shown) .. " rel " .. tostring(b.rel == Minimap) .. " " .. tostring(b.point))
local lit, color, dark, bars = level()
check(lit == 4 and bars == 4 and color[1] == 0.1 and color[2] == 1, "High: four green")
W.fire("GAME_PAD_POWER_CHANGED", 2)
lit, color, dark = level()
check(lit == 3 and dark and color[1] == 1 and color[2] == 0.82, "Medium: three yellow, one dark")
W.fire("GAME_PAD_POWER_CHANGED", 1)
lit, color, dark = level()
check(lit == 2 and dark and color[2] == 0.5, "Low: two orange, two dark")
W.fire("GAME_PAD_POWER_CHANGED", 0)
lit, color, dark = level()
check(lit == 1 and dark and color[2] == 0.1, "Critical: one red, three dark")
W.fire("GAME_PAD_POWER_CHANGED", 4)
lit, color = level()
check(lit == 4 and color[3] == 1, "Wired: four blue")
-- Its neighbours move or the minimap scales: placed again, at the minimap's scale.
lowest.GetCenter = function() local rad = math.rad(200) return 500 + 75 * math.cos(rad), 400 + 75 * math.sin(rad) end
-- A child's effective scale is its parent's (the stub inherits it, as the client does).
Minimap.scale = 0.8
W.advance(0.3)
x, y = Tweaks.BatteryOffset(75, 225)
check(at(b, x, y) and b.scale == 0.8, "follows its neighbours and the minimap's scale")
check(near(edge.left.w, 1.25) and near(edge.top.w, 15 * 1.25), "laid out again in whole pixels at the new scale")
Minimap.scale = nil
lowest:Hide()
W.advance(0.3)
x, y = Tweaks.BatteryOffset(75, 190)
check(at(b, x, y), "a hidden neighbour doesn't count")
b.scripts.OnMouseDown(b)
check(edge.top.x == -8 + 1 and edge.top.y == 5 - 1, "pressed: the battery nudges like its neighbours' icons")
b.scripts.OnMouseUp(b)
check(edge.top.x == -8 and edge.top.y == 5, "released: back")
b.scripts.OnEnter(b)
local tip
for _, f in ipairs(W.frames) do if f.title and type(f.lines) == "table" and type(f.actions) == "table" then tip = f end end
check(tip and tip.shown and tip.lines[1].text == "Wired (charging)", "the tooltip names the level")
b.scripts.OnLeave(b)
W.fire("GAME_PAD_POWER_CHANGED", 5)
W.advance(0.3)
check(not b.shown, "Unknown: hidden")
padLevel = 2
W.fire("GAME_PAD_CONNECTED")
W.advance(0.3)
check(b.shown and level() == 3, "a pad connects: read again, Medium")
Minimap.IsVisible = function() return false end
W.advance(0.3)
check(not b.shown, "hidden while the minimap is")
Minimap.IsVisible = function() return true end
Tweaks.Set("batteryIcon", false)
W.advance(0.3)
check(not b.shown, "off: hidden")
Tweaks.Set("battery", false)
MinimapBackdrop, MinimapCompassTexture = nil, nil

-- 14. Rare nearby: from the vignette (readable name) or the name plate (only when readable); once per rare.
turn("rareAlert")
turn("rumble")
local vignettes = { v1 = { atlasName = "VignetteKillElite", name = "Gorg", objectGUID = "Creature-1" }, v2 = { atlasName = "VignetteLoot", name = "Chest", objectGUID = "GameObject-2" } }
C_VignetteInfo = { GetVignetteInfo = function(guid) return vignettes[guid] end }
reset()
W.fire("VIGNETTE_MINIMAP_UPDATED", "v2", true)
check(noticeSays() == "", "a treasure vignette: nothing")
W.fire("VIGNETTE_MINIMAP_UPDATED", "v1", true)
check(noticeSays():find("Rare elite nearby | Gorg", 1, true) and count("SetVibration") == 2 and calls.SetVibration[1][2] == 0 and calls.SetVibration[2][1] == "Low", "a rare elite: the card and one rumble (Heartbeat's first beat, Low only): "
 .. noticeSays())
W.advance(2)
reset()
W.fire("VIGNETTE_MINIMAP_UPDATED", "v1", true)
check(count("SetVibration") == 0, "once per rare")
local plates = { nameplate1 = { "rare", "Snort", "Creature-3", 24 }, nameplate2 = { "rare", SECRET, "Creature-4", 30 }, nameplate3 = { "elite", "Brute", "Creature-5", 30 } }
function UnitClassification(unit) return plates[unit] and plates[unit][1] end
function UnitName(unit) return plates[unit] and plates[unit][2] or "Ann" end
function UnitGUID(unit) return plates[unit] and plates[unit][3] or unit == "player" and "Player-0-Ann" or nil end
function UnitLevel(unit) return plates[unit] and plates[unit][4] or 10 end
function UnitCanAttack() return true end
function UnitIsDead() return false end
function UnitIsDeadOrGhost() return false end
W.advance(6)
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
check(noticeSays() == "", "a secret name or a plain elite: nothing")
W.fire("PLAYER_REGEN_DISABLED")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(noticeSays() == "", "quiet in a fight")
W.fire("PLAYER_REGEN_ENABLED")
W.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(noticeSays() == "Rare nearby | Snort, level 24", "after the fight it shows: " .. noticeSays())
W.advance(6)
check(noticeSays() == "", "the card goes after 5 seconds")
Tweaks.Set("rareAlert", false)
Tweaks.Set("rumble", false)

-- 15. Whisper alert: the sender and the start of the message; nothing readable while secret.
turn("whisperAlert")
W.fire("CHAT_MSG_WHISPER", "need a heal?", "Bob-Realm")
check(noticeSays() == "Whisper from Bob-Realm | need a heal?", "the card: " .. noticeSays())
W.fire("CHAT_MSG_WHISPER", string.rep("a", 120), "Bob")
check(#noticeFrame().text.text == 90 and noticeFrame().text.text:sub(-3) == "...", "a long message is cut")
W.fire("CHAT_MSG_BN_WHISPER", SECRET, SECRET)
check(noticeSays() == "Whisper from someone | (the game hides this message right now)", "secret: only that a whisper came")
Tweaks.Set("whisperAlert", false)

-- Items for the loot, roll and gear checks: link -> { equipLoc, classID, subClassID, item level }.
local items = {
	["item:cloth20"] = { "INVTYPE_CHEST", 4, 1, 20 }, ["item:cloth30"] = { "INVTYPE_CHEST", 4, 1, 30 }, ["item:plate40"] = { "INVTYPE_CHEST", 4, 4, 40 },
	["item:ring15"] = { "INVTYPE_FINGER", 4, 0, 15 }, ["item:ring20"] = { "INVTYPE_FINGER", 4, 0, 20 }, ["item:ring12"] = { "INVTYPE_FINGER", 4, 0, 12 },
	["item:staff"] = { "INVTYPE_2HWEAPON", 2, 10, 25 }, ["item:mace2h"] = { "INVTYPE_2HWEAPON", 2, 5, 50 }, ["item:pole"] = { "INVTYPE_WEAPON", 2, 20, 5 },
	["item:boots"] = { "INVTYPE_FEET", 4, 1, 8 }, ["item:shield"] = { "INVTYPE_SHIELD", 4, 6, 30 }, ["item:later"] = { "INVTYPE_HEAD", 4, 1, 99, 60 },
	["item:unloaded"] = { "INVTYPE_HEAD", 4, 1 },
}
local ids = {}
for link in pairs(items) do ids[#ids + 1] = link end
table.sort(ids)
for i, link in ipairs(ids) do items[link].id = 1000 + i end
local byID = {}
for link, item in pairs(items) do byID[item.id] = link end
local function linkOf(item) return type(item) == "number" and byID[item] or item end
C_Item.GetItemInfoInstant = function(item)
	local link = linkOf(item)
	local i = items[link]
	if i then return i.id, nil, nil, i[1], 77, i[2], i[3] end
	local food = { [2001] = 5, [2002] = 5, [2003] = 5, [2004] = 1 }
	if food[item] then return item, nil, nil, "", 1, 0, food[item] end
end
C_Item.GetDetailedItemLevelInfo = function(item) local i = items[linkOf(item)] return i and i[4] end
local foods = { [2001] = { "Food", 5, 1 }, [2002] = { "Food", 15, 10 }, [2003] = { "Drink", 20, 15 }, [2004] = { "Drink", 1, 1 } }
C_Item.GetItemInfo = function(item)
	local i = items[linkOf(item)]
	if i then return "Item", linkOf(item), 2, i[4], i[5] or 1 end
	local f = foods[item]
	if f then return "Snack", nil, 1, f[3], f[2] end
	return "Item" .. tostring(item), nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[item]
end
C_Item.GetItemSpell = function(item) return foods[item] and foods[item][1] end
-- As in the client: "usable" means a use effect, so plain gear is not (the upgrade rule must not ask it).
C_Item.IsUsableItem = function() return false end
local worn = { [5] = "item:cloth30", [11] = "item:ring20", [12] = "item:ring12", [16] = "item:staff" }
function GetInventoryItemLink(_, slot) return worn[slot] end
local function upgradesFresh() W.fire("PLAYER_EQUIPMENT_CHANGED") end

-- 16. The upgrade rule.
local Gear = Tweaks.Gear
UnitLevel = function() return 30 end
upgradesFresh()
check(Gear.Upgrade("item:cloth20") == nil and Gear.Upgrade("item:plate40") == nil, "lower than worn, or plate for a mage: no")
worn[5] = "item:cloth20"
upgradesFresh()
check(Gear.Upgrade("item:cloth30") == 5, "higher than the worn chest: the chest slot")
check(Gear.Upgrade("item:ring15") == 12, "a ring compares with the weaker worn ring")
check(Gear.Upgrade("item:boots") == 8, "an empty slot takes anything that goes there")
check(Gear.Upgrade("item:mace2h") == nil and Gear.Upgrade("item:shield") == nil, "a weapon or shield a mage never uses: no")
check(Gear.Upgrade("item:later") == nil, "above the character's level: no")
check(Gear.Upgrade("item:unloaded") == nil, "not loaded: no answer yet")
items["item:unloaded"][4] = 5
W.fire("GET_ITEM_INFO_RECEIVED", 1)
check(Gear.Upgrade("item:unloaded") == 1, "once loaded it is judged")
worn[5] = "item:cloth30"
W.fire("GET_ITEM_INFO_RECEIVED", 2)
check(Gear.Upgrade("item:cloth30") == 5, "an item arriving drops no answer already known (only the gear changing does)")
worn[5] = "item:cloth20"
items["item:secret"] = { "INVTYPE_WAIST", 4, 1, SECRET, id = 1999 }
byID[1999] = "item:secret"
check(Gear.Upgrade("item:secret") == nil, "a secret item level is never compared: no arrow")
check(Gear.CanEver("WARRIOR", 4, 4) == true and Gear.CanEver("ROGUE", 4, 3) == false and Gear.CanEver("HUNTER", 2, 4) == nil and Gear.CanEver("MAGE", 2, 19) == true and Gear.CanEver("ROGUE", 2, 19) == false, "class rules: plate, mail, unsure, wands")
check(Gear.CanEver("MAGE", 2, 20) == nil and Gear.CanEver("NEWCLASS", 4, 4) == nil and Gear.CanEver("MAGE", 4, 5) == nil, "fishing poles, an unknown class or cosmetic armor: unsure")
check(Gear.CanEver("WARRIOR", 4, 1) == true and Gear.CanEver("PALADIN", 4, 7) == true and Gear.CanEver("PRIEST", 4, 6) == false, "lighter armor is wearable; librams and shields by class")

-- 17. Upgrade arrows on bag buttons: our own frames, anchored on the button, shown while it shows.
local bagLinks = { [0] = { "item:cloth30", "item:cloth20", "item:boots" } }
C_Container.GetContainerItemLink = function(bag, slot) return bagLinks[bag] and bagLinks[bag][slot] end
local bagButtons = {}
for slot = 1, 3 do bagButtons[slot] = blizz({ visible = true, id = slot }) end
for _, button in ipairs(bagButtons) do getmetatable(button).__index.GetBagID = function() return 0 end end
local combined = { visible = true, Items = bagButtons }
ContainerFrameCombinedBags = setmetatable({}, { __index = function(_, k)
	if k == "Items" then return combined.Items end
	return ({ IsVisible = function() return combined.visible end, IsShown = function() return combined.visible end, GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 5 end, Abs = function() return 0, 0 end })[k]
end, __newindex = function(_, k) error("Tweaks wrote " .. tostring(k) .. " on the bags", 2) end })
ns.db.options.debug = true
turn("upgradeArrows")
W.advance(0.3)
local arrowLog = 0
for _, line in ipairs(ns.db.debugLog) do if line:find("arrows: 3 items in open windows, 2 marked", 1, true) then arrowLog = arrowLog + 1 end end
W.advance(0.6)
for _, line in ipairs(ns.db.debugLog) do if line:find("arrows: 3 items in open windows, 2 marked", 1, true) then arrowLog = arrowLog + 1 end end
check(arrowLog == 2, "/fct debug logs the items seen and marked, once while it stays the same: " .. arrowLog)
ns.db.options.debug = false
local shownArrows = {}
for _, f in ipairs(W.frames) do if f.parent == UIParent and f.textures and f.textures[1] and f.textures[1].atlas == "bags-greenarrow" and f.shown then shownArrows[#shownArrows + 1] = f end end
check(#shownArrows == 2, "two arrows (cloth30 and the boots): " .. #shownArrows)
for _, arrow in ipairs(shownArrows) do check(arrow.parent == UIParent and not arrow.mouse and arrow.kind == "Frame", "an arrow: our own plain frame, never a child of the bags, never taking the mouse") end
check((shownArrows[1].rel == bagButtons[1] or shownArrows[1].rel == bagButtons[3]) and shownArrows[1].point == "TOPLEFT", "on the item's button, top left")
for _, arrow in ipairs(shownArrows) do arrow.cleared = false end
W.advance(0.6)
check(not shownArrows[1].cleared and not shownArrows[2].cleared and shownArrows[1].shown, "polls keep each arrow's anchor while its button is the same")

combined.visible = false
W.advance(0.3)
local still = 0
for _, f in ipairs(shownArrows) do if f.shown then still = still + 1 end end
check(still == 0, "the arrows hide with the bags")
Tweaks.Set("upgradeArrows", false)

-- 18. Fast loot: every unlocked slot, last first, once per window; never when the game auto-loots; full bags take coins only.
local loot = { { locked = false, kind = 1 }, { locked = true, kind = 1 }, { locked = false, kind = 2 } }
function GetNumLootItems() return #loot end
function GetLootSlotInfo(slot) return nil, "Thing", 1, nil, 1, loot[slot].locked end
function GetLootSlotType(slot) return loot[slot].kind end
LootSlot = record("LootSlot")
turn("fastLoot")
freeSlots = 5
reset()
W.fire("LOOT_READY", false)
W.fire("LOOT_OPENED", false, false)
check(count("LootSlot") == 2 and calls.LootSlot[1][1] == 3 and calls.LootSlot[2][1] == 1, "slots 3 and 1 (not the locked one), once")
check(count("ConfirmLootSlot") == 0, "a bind-on-pickup prompt is never answered")
W.fire("LOOT_CLOSED")
reset()
W.fire("LOOT_READY", true)
check(count("LootSlot") == 0, "the game's own auto loot: left to it")
W.fire("LOOT_CLOSED")
freeSlots = 0
reset()
W.fire("LOOT_READY", false)
check(count("LootSlot") == 1 and calls.LootSlot[1][1] == 3 and said("bags are full, 1 item left"), "full bags: the coins only, one line")
W.fire("LOOT_CLOSED")
freeSlots = 10
Tweaks.Set("fastLoot", false)

-- 19. Pass on unusable rolls: plate for a mage passes with a line; a staff or an unsure item is the player's.
local rolls = { [1] = "item:plate40", [2] = "item:staff", [3] = "item:pole", [4] = SECRET }
function GetLootRollItemLink(id) return rolls[id] end
RollOnLoot = record("RollOnLoot")
turn("passUnusable")
reset()
for id = 1, 4 do W.fire("START_LOOT_ROLL", id, 60) end
check(count("RollOnLoot") == 1 and calls.RollOnLoot[1][1] == 1 and calls.RollOnLoot[1][2] == 0 and said("Passed on item:plate40"), "passes plate only")
Tweaks.Set("passUnusable", false)
reset()
W.fire("START_LOOT_ROLL", 1, 60)
check(count("RollOnLoot") == 0, "off: never")

-- 20. Wear quest rewards: a reward that lands in the bags as an upgrade gets the card; hold the top button to wear it.
C_Item.EquipItemByName = record("EquipItemByName")
local questChoices = { "item:boots", "item:cloth20" }
function GetNumQuestChoices() return #questChoices end
function GetNumQuestRewards() return 0 end
function GetQuestItemLink(kind, i) return kind == "choice" and questChoices[i] or nil end
turn("wearRewards")
bags = { [0] = { { itemID = items["item:boots"].id } } }
bagLinks = { [0] = { "item:boots" } }
W.fire("QUEST_COMPLETE")
W.fire("QUEST_TURNED_IN", 7, 0, 0)
W.fire("BAG_UPDATE_DELAYED")
local card
for _, f in ipairs(W.frames) do if f.offer then card = f end end
check(card and card.shown and card.name.text == "item:boots" and card.hint.text:find("to wear it"), "the card names the reward")
local listener
for _, f in ipairs(W.frames) do if f.scripts.OnGamePadButtonDown and f.scripts.OnGamePadButtonUp and f.parent == UIParent and f.shown and f.propagate == true then listener = f end end
check(listener, "a pad listener that passes every press on")
listener:Fire("OnGamePadButtonDown", "PAD4")
W.advance(0.3)
listener:Fire("OnGamePadButtonUp", "PAD4")
check(count("EquipItemByName") == 0 and card.shown, "a tap does nothing here")
listener:Fire("OnGamePadButtonDown", "PAD4")
W.advance(1.2)
listener:Fire("OnGamePadButtonUp", "PAD4")
check(count("EquipItemByName") == 1 and calls.EquipItemByName[1][1] == "item:boots" and calls.EquipItemByName[1][2] == 8 and not card.shown, "a one-second hold wears it in its slot")
W.fire("QUEST_COMPLETE")
W.fire("QUEST_TURNED_IN", 8, 0, 0)
W.fire("BAG_UPDATE_DELAYED")
check(card.shown, "offered again for the next quest")
W.fire("PLAYER_REGEN_DISABLED")
check(not card.shown and not listener.shown, "combat hides it")
W.fire("PLAYER_REGEN_ENABLED")
Tweaks.Set("wearRewards", false)

-- 21. Eat & drink: our own secure button; the best food and, for mana users, the best drink, written out of combat.
local eat = ForeverControllerTweaksEatDrink
check(ns.Actions.TextFor("game:eatdrink") == "/click ForeverControllerTweaksEatDrink" and ns.Actions.TextFor("game:questitem") == "/click ForeverControllerTweaksQuestItem", "picker: both click our own buttons")
function UnitPowerType() return 0 end
bags = { [0] = { { itemID = 2001 }, { itemID = 2002 }, { itemID = 2003 }, { itemID = 2004 } } }
W.fire("BAG_UPDATE_DELAYED")
W.advance(0.05)
check(eat:GetAttribute("type") == "macro" and eat:GetAttribute("macrotext") == "/use [nocombat] item:2002\n/use [nocombat] item:2003", "the best food (level 15) and drink (level 20): " .. tostring(eat:GetAttribute("macrotext")))
function UnitPowerType() return 1 end
W.fire("BAG_UPDATE_DELAYED")
W.fire("BAG_UPDATE_DELAYED")
local bagReads, readSlot = 0, C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function(...) bagReads = bagReads + 1 return readSlot(...) end
W.advance(0.05)
check(eat:GetAttribute("macrotext") == "/use [nocombat] item:2002", "no mana: food only")
check(bagReads == 4, "a burst of bag events: one pass over the bags for every kind: " .. bagReads)
W.combat = true
bags = {}
bagReads = 0
W.fire("BAG_UPDATE_DELAYED")
W.fire("QUEST_LOG_UPDATE")
W.advance(0.05)
check(eat:GetAttribute("macrotext") == "/use [nocombat] item:2002" and bagReads == 0, "in combat nothing is scanned or written")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(eat:GetAttribute("macrotext") == "", "after combat it is: nothing to eat")
reset()
eat:Fire("PreClick")
check(said("no food or drink"), "and a press says so")

-- 22. Quest item: the super-tracked quest's item, else the nearest quest's.
local quests = { { questID = 11, isHeader = true }, { questID = 12 }, { questID = 13 }, { questID = 14 } }
local questItems = { [3] = "|cffffffff|Hitem:5003::|h[Rod]|h|r", [4] = "|cffffffff|Hitem:5004::|h[Bell]|h|r" }
local distance = { [13] = 400, [14] = 100 }
local tracked
C_QuestLog = {
	GetNumQuestLogEntries = function() return #quests end,
	GetInfo = function(i) return quests[i] end,
	GetLogIndexForQuestID = function(id) for i, q in ipairs(quests) do if q.questID == id then return i end end end,
	GetDistanceSqToQuest = function(id) return distance[id] end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return tracked end }
function GetQuestLogSpecialItemInfo(i) return questItems[i] end
W.fire("QUEST_LOG_UPDATE")
W.advance(0.05)
check(ForeverControllerTweaksQuestItem:GetAttribute("macrotext") == "/use item:5004", "the nearest quest's item")
tracked = 13
W.fire("SUPER_TRACKING_CHANGED")
W.advance(0.05)
check(ForeverControllerTweaksQuestItem:GetAttribute("macrotext") == "/use item:5003", "the super-tracked quest's item first")
questItems = {}
W.fire("QUEST_LOG_UPDATE")
W.advance(0.05)
check(ForeverControllerTweaksQuestItem:GetAttribute("macrotext") == "", "none: empty")

-- Batch 4: picker actions.
local function text(id) return ns.Actions.TextFor(id) end
check(text("game:cancel") == "/stopcasting\n/stopspelltarget\n/cleartarget" and text("game:readycheck") == "/readycheck" and text("game:pull") == "/countdown 5", "Cancel, Ready check and Pull countdown: secure macro text")
for _, id in ipairs({ "healpotion", "manapotion", "grenade", "tracknearest", "marknext", "minimapzoom" }) do
	check(text("game:" .. id) and text("game:" .. id):find("^/click ForeverControllerTweaks"), id .. ": clicks our own button")
end
local lookEntry, mapEntry = ns.Actions.Find("hold:lookbehind"), ns.Actions.Find("hold:peekmap")
check(lookEntry and lookEntry.kind == "hold" and mapEntry and mapEntry.category == "Windows", "the hold actions are in the picker")
check(text("hold:lookbehind") == "/click ForeverControllerTweaksLookBehind RightButton", "a touch button or ring taps a hold action once (its toggle)")
check(ns.Actions.Assign(300, lookEntry) == nil, "a hold action never goes into a crossbar slot")

-- Look behind: round on the press, back on the release; a lost release is made good by the next press; combat turns back.
FlipCameraYaw = record("FlipCameraYaw")
local look = ForeverControllerTweaksLookBehind
reset()
look:Fire("OnClick", "LeftButton", true)
look:Fire("OnClick", "LeftButton", false)
check(count("FlipCameraYaw") == 2 and calls.FlipCameraYaw[1][1] == 180, "press and release: round and back")
look:Fire("OnClick", "LeftButton", true)
look:Fire("OnClick", "LeftButton", true)
look:Fire("OnClick", "LeftButton", false)
check(count("FlipCameraYaw") == 4, "a lost release: the next press only turns back, its release does nothing")
look:Fire("OnClick", "LeftButton", true)
W.fire("PLAYER_REGEN_DISABLED")
look:Fire("OnClick", "LeftButton", false)
W.fire("PLAYER_REGEN_ENABLED")
check(count("FlipCameraYaw") == 6, "combat start turns back; the late release does nothing")
look:Fire("OnClick", "RightButton", false)
check(count("FlipCameraYaw") == 7, "a tap turns round (a toggle)")
look:Fire("OnClick", "RightButton", false)

-- Peek map: our secure button clicks the game's own map button on press and release; on an open map a press only closes.
local map = ForeverControllerTweaksPeekMap
check(map:GetAttribute("type") == "click" and map:GetAttribute("typerelease") == "click" and map:GetAttribute("pressAndHoldAction") and map:GetAttribute("useOnKeyDown"), "press-and-hold: the click on the press and on the release")
check(map:GetAttribute("clickbutton") == nil, "no map button in this stub: nothing to click")
QuestLogMicroButton = W.new("Button")
local mapSpec = { visible = false }
WorldMapFrame = blizz(mapSpec)
W.fire("PLAYER_ENTERING_WORLD")
check(map:GetAttribute("clickbutton") == QuestLogMicroButton, "the game's own map button")
map:Fire("PreClick", "LeftButton", true)
check(map:GetAttribute("typerelease") == "click", "map closed at the press: the release closes it")
mapSpec.visible = true
map:Fire("PreClick", "LeftButton", true)
check(map:GetAttribute("typerelease") == nil, "map already open (a lost release): this press only closes it")
map:Fire("PreClick", "RightButton", false)
check(map:GetAttribute("typerelease") == "click", "a tap toggles")
mapSpec.visible = false

-- Track nearest quest: the nearest, then the next nearest.
quests = { { questID = 21, title = "Far" }, { questID = 22, title = "Near" }, { questID = 23, title = "Mid" }, { questID = 24, isHeader = true } }
distance = { [21] = 900, [22] = 10, [23] = 50 }
tracked = nil
C_SuperTrack.SetSuperTrackedQuestID = function(id) record("SuperTrack")(id) tracked = id end
reset()
ForeverControllerTweaksTrackQuest:Click()
check(tracked == 22 and said("Tracking: Near"), "the nearest quest")
ForeverControllerTweaksTrackQuest:Click()
ForeverControllerTweaksTrackQuest:Click()
check(calls.SuperTrack[2][1] == 23 and tracked == 21, "again: the next nearest, then the next")
ForeverControllerTweaksTrackQuest:Click()
check(tracked == 22, "and round")

-- Mark next: kill order from skull, stepped by the secure snippet on the release, back to skull after combat.
local mark = ForeverControllerTweaksMarkNext
local function markPress()
	local env = setmetatable({}, { __index = _G })
	local fn = (loadstring or load)("local self, button, down = ...\n" .. mark.wrap)
	if setfenv then setfenv(fn, env) end
	fn(mark, "LeftButton", true)
	fn(mark, "LeftButton", false)
	return mark:GetAttribute("macrotext")
end
check(mark.wrap and markPress() == "/tm 8" and markPress() == "/tm 7" and markPress() == "/tm 6", "skull, cross, square")
for _ = 1, 5 do markPress() end
check(markPress() == "/tm 8", "after star: skull again")
W.fire("PLAYER_REGEN_ENABLED")
check(markPress() == "/tm 8", "after combat it starts at skull")

-- Potions and grenades: the best of each kind the character can use, in combat too.
-- { spell, subclass, level, name, class }: 3004 an old trade-goods explosive; 3005 a reagent (no use spell); 3006 a
-- quest item with "Bomb" in its name; 3007 a newer consumable device.
local potions = {
	[3001] = { "Healing Potion", 1, 5, "Minor Healing Potion" }, [3002] = { "Healing Potion", 1, 25, "Greater Healing Potion" },
	[3003] = { "Restore Mana", 1, 20, "Mana Potion" }, [3004] = { "Iron Grenade", 2, 20, "Iron Grenade", 7 },
	[3005] = { nil, 2, 21, "Explosive Charge", 7 }, [3006] = { "Throw", 0, 21, "Bomb Crate", 12 }, [3007] = { "Boom", 14, 1, "Bomb Bot", 0 },
}
local itemInstant, itemInfo, itemSpell = C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemSpell
C_Item.GetItemInfoInstant = function(item) local p = potions[item] if p then return item, nil, nil, "", 1, p[5] or 0, p[2] end return itemInstant(item) end
C_Item.GetItemInfo = function(item) local p = potions[item] if p then return p[4], nil, 1, p[3], p[3] end return itemInfo(item) end
C_Item.GetItemSpell = function(item) local p = potions[item] if p then return p[1] end return itemSpell(item) end
UnitLevel = function() return 22 end
bags = { [0] = { { itemID = 3001 }, { itemID = 3002 }, { itemID = 3003 }, { itemID = 3004 }, { itemID = 3005 }, { itemID = 3006 } } }
W.fire("BAG_UPDATE_DELAYED")
W.advance(0.05)
local buttons = Tweaks.ItemButtons
check(buttons.heal:GetAttribute("macrotext") == "/use item:3001", "healing: the best one the level allows (not level 25): " .. tostring(buttons.heal:GetAttribute("macrotext")))
check(buttons.mana:GetAttribute("macrotext") == "/use item:3003" and buttons.grenade:GetAttribute("macrotext") == "/use item:3004", "mana and grenade (not the higher reagent or the quest item named like one)")
check(Tweaks.Explosive({ classID = 0, subClassID = 14, name = "Bomb Bot", spell = "Boom" }) and not Tweaks.Explosive({ classID = 12, subClassID = 0, name = "Bomb Crate", spell = "Throw" }) and not Tweaks.Explosive({ classID = 7, subClassID = 2, name = "Explosive Charge", spell = "" }), "a grenade: an explosive's class and a use spell, then the name")
check(buttons.heal:GetAttribute("useOnKeyDown") == false, "acts on the action's /click release")
bags = {}
W.fire("BAG_UPDATE_DELAYED")
W.advance(0.05)
check(buttons.heal:GetAttribute("macrotext") == "", "none: nothing happens")
local function lines(text) local n = 0 for _, line in ipairs(W.log) do if line:find(text, 1, true) then n = n + 1 end end return n end
W.log = {}
buttons.heal:Fire("PreClick", "LeftButton", true)
buttons.heal:Fire("PreClick", "LeftButton", false)
check(lines(Tweaks.ActionsT.NO_HEAL) == 1, "none: a press says so once (the release)")
W.combat = true
buttons.heal:Fire("PreClick", "LeftButton", false)
buttons.mana:Fire("PreClick", "LeftButton", false)
W.combat = false
check(lines(Tweaks.ActionsT.NO_HEAL) == 1 and lines(Tweaks.ActionsT.NO_MANA) == 0, "none in combat: silent")

-- A potion filed under another subclass counts by its name; a Healthstone or bandage never does. An item not loaded
-- yet is asked for, and its arrival rescans.
potions[3008] = { "Healing Potion", 1, 22, "Major Healing Potion" }
potions[3009] = { "Healing Potion", 0, 21, "Superior Healing Potion" }
potions[3010] = { "Healthstone", 0, 22, "Major Healthstone" }
potions[3011] = { "First Aid", 7, 22, "Heavy Healing Bandage" }
local loaded, asked = false, {}
local potionInfo, potionSpell = C_Item.GetItemInfo, C_Item.GetItemSpell
C_Item.GetItemInfo = function(item) if item == 3008 and not loaded then return nil end return potionInfo(item) end
C_Item.GetItemSpell = function(item) if item == 3008 and not loaded then return nil end return potionSpell(item) end
C_Item.RequestLoadItemDataByID = function(item) asked[#asked + 1] = item end
bags = { [0] = { { itemID = 3008 }, { itemID = 3009 }, { itemID = 3010 }, { itemID = 3011 } } }
W.fire("BAG_UPDATE_DELAYED")
W.advance(0.05)
check(buttons.heal:GetAttribute("macrotext") == "/use item:3009" and asked[1] == 3008, "not loaded yet: asked for; a Potion by name, not the Healthstone or bandage: " .. tostring(buttons.heal:GetAttribute("macrotext")))
W.fire("GET_ITEM_INFO_RECEIVED", 4242, true)
W.advance(0.05)
check(buttons.heal:GetAttribute("macrotext") == "/use item:3009", "another item's arrival: no rescan")
loaded = true
W.fire("GET_ITEM_INFO_RECEIVED", 3008, true)
W.advance(0.05)
check(buttons.heal:GetAttribute("macrotext") == "/use item:3008", "its arrival rescans: " .. tostring(buttons.heal:GetAttribute("macrotext")))
C_Item.GetItemInfo, C_Item.GetItemSpell, C_Item.RequestLoadItemDataByID = potionInfo, potionSpell, nil
bags = {}
W.fire("BAG_UPDATE_DELAYED")
W.advance(0.05)


-- Minimap zoom: the minimap's own buttons, in until fully in, then out.
local zoomLevel = 0
Minimap.ZoomIn, Minimap.ZoomOut = W.new("Button"), W.new("Button")
function Minimap:GetZoom() return zoomLevel end
function Minimap:GetZoomLevels() return 3 end
local zoom = ForeverControllerTweaksMinimapZoom
zoom:Fire("PreClick", "LeftButton", false)
check(zoom:GetAttribute("type") == "click" and zoom:GetAttribute("clickbutton") == Minimap.ZoomIn, "zooms in")
zoomLevel = 2
zoom:Fire("PreClick", "LeftButton", false)
check(zoom:GetAttribute("clickbutton") == Minimap.ZoomOut, "fully in: zooms out")
zoomLevel = 1
zoom:Fire("PreClick", "LeftButton", false)
check(zoom:GetAttribute("clickbutton") == Minimap.ZoomOut, "keeps going out")
zoomLevel = 0
zoom:Fire("PreClick", "LeftButton", false)
check(zoom:GetAttribute("clickbutton") == Minimap.ZoomIn, "fully out: in again")

-- The Gamepad UI off: no tweak acts.
for _, key in ipairs(Tweaks.KEYS) do turn(key) end
W.gamepadUI = false
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
check(not ns.Active(), "the Gamepad UI is off")
reset()
everything()
check(next(calls) == nil, "Gamepad UI off: nothing")
check(not sortButton().shown and not stacks[1].shown, "and no window buttons")
W.gamepadUI = true
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1)

-- Combat stops a run.
W.fire("MERCHANT_CLOSED")
mails = { { money = 0, cod = 0, items = { "Ore", "Ore" } } }
W.fire("MAIL_SHOW")
reset()
mail:Click()
W.combat = true
W.advance(1)
W.combat = false
W.advance(1)
check(count("TakeInboxItem") == 0, "combat stops Open all")

-- Panel: the setup guide closed with X (or a close key) counts as Not now; the Gamepad UI going off doesn't.
local pad = ns.Device.Current()
ns.db.declined = {}
UI.Onboarding.Start()
check(UI.Current() and not ns.db.declined[pad.key], "the guide is open, nothing declined yet")
UI.CloseAll()
check(ns.db.declined[pad.key] == true, "closed with X: declined, so a pad event doesn't bring it back")
ns.db.declined = {}
UI.Onboarding.Start()
W.gamepadUI = false
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0)
check(not UI.Current() and not ns.db.declined[pad.key], "the Gamepad UI going off closes it without declining")
W.gamepadUI = true
W.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1)

-- The interact notice never opens over controller setup (Esc there would press "Don't show again").
ns.db.options.interactNoticeOff, ns.db.options.interactNoticed = nil, nil
UI.Bindings.Open()
assert(ns.Layout.SetFace("bottom", "interact"))
W.advance(0.1)
check(UI.DialogShown(), "interact moved with Bindings open: the notice shows")
UI.Dialog():Press(1)
assert(ns.Layout.SetFace("left", "interact"))
W.advance(0.1)
UI.Detect.Open()
UI.Dialog():Press(1)
local detectWindow = UI.Current()
check(detectWindow and detectWindow.detect and not UI.DialogShown(), "controller setup runs, no dialog")
assert(ns.Layout.SetFace("bottom", "interact"))
W.advance(0.1)
check(not UI.DialogShown() and not ns.db.options.interactNoticeOff, "the same move during setup: no notice over it")
ns.Device.DetectCancel()
UI.CloseAll()
assert(ns.Layout.SetFace("left", "interact"))
W.advance(0.1)


-- A burst of slot changes redraws the open Bindings window once, on the next frame.
UI.Bindings.Open()
local bindings, redraws = UI.Current(), 0
local redraw = bindings.OnRefresh
bindings.OnRefresh = function(...) redraws = redraws + 1 return redraw(...) end
for _ = 1, 5 do W.fire("ACTIONBAR_SLOT_CHANGED", 1) end
W.fire("FCT_LAYOUT_CHANGED")
check(redraws == 0, "nothing redrawn in the same frame")
W.advance(0.05)
check(redraws == 1, "one redraw for the burst: " .. redraws)
bindings.OnRefresh = redraw
UI.CloseAll()


-- Camera zoom: the hold actions step on the press and keep moving while held; the Tweaks slider moves the camera by
-- the difference now and once at the next login, never past the game's limit.
do
	local cam, moves = { zoom = 10 }, {}
	function GetCameraZoom() return cam.zoom end
	function CameraZoomIn(by) cam.zoom = cam.zoom - by moves[#moves + 1] = ("in %g"):format(by) end
	function CameraZoomOut(by) cam.zoom = cam.zoom + by moves[#moves + 1] = ("out %g"):format(by) end
	function MoveViewInStart() moves[#moves + 1] = "in start" end
	function MoveViewInStop() moves[#moves + 1] = "in stop" end
	W.cvars.cameraDistanceMaxZoomFactor = "2"
	local T = ns.Tweaks
	check(T.CameraMax() == 30 and T.Get("cameraZoom") == nil, "zoom: the limit is the game's (factor x 15 yards); untouched it is nil")
	check(ns.Actions.Find("hold:zoomin") and ns.Actions.Find("hold:zoomout") and ns.Actions.Find("hold:zoomin").category == "Misc", "zoom: Zoom in and Zoom out are Misc hold actions")
	local zin = _G.ForeverControllerTweaksZoomIn
	zin.scripts.OnClick(zin, "LeftButton", true)
	zin.scripts.OnClick(zin, "LeftButton", false)
	W.advance(0.5)
	check(table.concat(moves, ",") == "in 1", "zoom: a press is one step, a quick release starts nothing: " .. table.concat(moves, ","))
	moves = {}
	zin.scripts.OnClick(zin, "LeftButton", true)
	W.advance(0.5)
	zin.scripts.OnClick(zin, "LeftButton", false)
	check(table.concat(moves, ",") == "in 1,in start,in stop", "zoom: held, it keeps moving until the release: " .. table.concat(moves, ","))
	moves = {}
	zin.scripts.OnClick(zin, "LeftButton", true)
	W.advance(0.5)
	W.fire("PLAYER_REGEN_DISABLED")
	check(moves[#moves] == "in stop", "zoom: a fight starting stops it (a lost release)")
	W.fire("PLAYER_REGEN_ENABLED")
	moves = {}
	zin.scripts.OnClick(zin, "RightButton", false)
	check(table.concat(moves, ",") == "in 1", "zoom: a tap (touch button, ring) is one step")
	cam.zoom, moves = 10, {}
	T.Set("cameraZoom", 25)
	check(T.Get("cameraZoom") == 25 and cam.zoom == 25 and moves[1] == "out 15", "zoom: the setting moves the camera by the difference: " .. tostring(T.Get("cameraZoom")) .. " " .. cam.zoom .. " " .. table.concat(moves, ","))
	T.Set("cameraZoom", 99)
	check(cam.zoom == 30, "zoom: never past the game's limit")
	T.Set("cameraZoom", 5)
	check(cam.zoom == 5 and moves[#moves] == "in 25", "zoom: in by the difference")
	check(T.Repair({ cameraZoom = "x" }).cameraZoom == nil and T.Repair({ cameraZoom = 12.4 }).cameraZoom == 12 and T.Repair({ cameraZoom = -3 }).cameraZoom == nil, "zoom: repair keeps whole yards in range, else nil")
	ns.db.tweaks.cameraZoom = nil
	UI.TweaksTab.Open()
	local tab = UI.Current()
	local row
	for _, node in ipairs(tab.nodes) do if node.region.key == "cameraZoom" then row = node.region end end
	check(row and row.control.value.text == "5 yd", "zoom: the slider shows where the camera is when nothing is saved: " .. tostring(row and row.control.value.text))
	UI.CloseAll()
end

io.stdout:write("tweaks_spec: " .. checks .. " checks passed\n")
