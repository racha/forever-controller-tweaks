-- Forever Controller Tweaks "Tweaks": small account-wide conveniences, each off until turned on in the Tweaks tab.
-- Saved in ns.db.tweaks (one boolean per key, repaired on load). Like the rest of the addon they act only while the
-- Gamepad UI is on.
-- Taint: no StaticPopup, ShowUIPanel/HideUIPanel, FrameControlsManager, SmartNavigation, InputBindingManager or menu
-- call, no field written on a Blizzard frame, no CVar. The window buttons (Sort, Stack, Learn all, Open all) are our
-- own frames parented to UIParent and only anchored to the Blizzard window; a poll reads that window's visibility.
-- Popups Blizzard shows for an invite, duel, resurrect or summon are left alone: duel and resurrect ones hide
-- themselves on DUEL_FINISHED / PLAYER_ALIVE, a summon's on CANCEL_SUMMON, an invite's on PARTY_INVITE_CANCEL.
--   Tweaks.KEYS                    the on/off setting keys in tab order.
--   Tweaks.CHOICES                 the choice settings: key -> its options, the first the default.
--   Tweaks.Repair(saved)           a clean settings table: every key a boolean (false unless saved true), every choice
--                                  one of its options.
--   Tweaks.Get(key) / Set(key, v)  the saved value; Set also redraws the window buttons and the light bar.
--   Tweaks.LIGHT                   the Custom light colours: id -> { r, g, b }.
--   Tweaks.NUMBERS                 the number settings: key -> { min, max, step, default }.
--   Tweaks.Rumble(event[, test])   the event's group pattern (Tweaks.RUMBLE_GROUP_OF) while Rumble on events is on.
--   Tweaks.Notice(title, text, s)  our own on-screen card for s seconds (a rare, a whisper).
--   Tweaks.Is(key), Call, Name, Money  helpers for TweaksGear.lua: a tweak acts now; a guarded API call; a printable
--                                  name (never a secret); coins as text.
--   Tweaks.SortBags()              sorts the bags (the Sort button and the picker's Sort bags action).
--   Tweaks.BuyStack(index)         buys a full stack of merchant item index; no index: the item under the cursor.
local _, ns = ...
local Tweaks = {}
ns.Tweaks = Tweaks

Tweaks.KEYS = {
	"sortBags", "sellJunk", "repair", "repairGuild", "buyStack",
	"skipGossip", "learnAll", "openMail",
	"acceptInvites", "declineDuels", "acceptRes",
	"combatFlash", "rumble", "battery", "batteryIcon", "rareAlert",
	"fastLoot", "passUnusable", "upgradeArrows", "wearRewards",
	"whisperAlert",
}
Tweaks.NUMBERS = { rumbleStrength = { 0.1, 1, 0.1, 0.6 } }
Tweaks.CHOICES = {
	lightBar = { "default", "class", "custom" },
	lightColor = { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "purple", "pink", "white" },
}
Tweaks.LIGHT = {
	red = { 1, 0, 0 }, orange = { 1, 0.45, 0 }, yellow = { 1, 0.85, 0 }, green = { 0, 1, 0 }, teal = { 0, 0.8, 0.55 },
	cyan = { 0, 0.85, 1 }, blue = { 0, 0.25, 1 }, purple = { 0.6, 0, 1 }, pink = { 1, 0.3, 0.7 }, white = { 1, 1, 1 },
}

local T = {
	SORT = "Sort", SORT_TIP = "Sort bags", SORT_PAD = "With the controller: Clean Up in the bag menu, or the picker's Sort bags action.", STACK = "Stack", STACK_TIP = "Buy a full stack", LEARN = "Learn all", OPEN = "Open all",
	SOLD = "Sold %d junk item%s for %s.", SOLD_LIST = "Sold %d junk item%s for %s: %s.", SOLD_MORE = "and %d more", REPAIRED = "Repaired for %s.", REPAIRED_GUILD = "Repaired for %s (guild funds).",
	REPAIR_POOR = "Not enough money to repair (%s).", BOUGHT = "Bought %d x %s for %s.", NO_STACK = "Point the cursor at a stackable merchant item first.",
	STACK_COST = "That stack costs %s: buy it with Multi-buy, which asks first.", STACK_POOR = "Not enough money for that item.", SOLD_OUT = "That item is sold out.",
	LEARNED = "Learned %d skill%s for %s.", MAIL = "Opened mail: %d item%s and %s.", BAGS_FULL = "Open all stopped: your bags are full.",
	INVITE = "Accepted the group invite from %s.", DUEL = "Declined a duel from %s.", RES = "Accepted the resurrection from %s.",
	SUMMON = "Accepted the summon from %s to %s.", COMBAT = "Not in combat.", SOMEONE = "someone",
	BATTERY_LOW = "Controller battery is low.", BATTERY_CRITICAL = "Controller battery is almost empty.",
	BATTERY_LEVEL = { [0] = "Almost empty", [1] = "Low", [2] = "Medium", [3] = "Full", [4] = "Wired (charging)" }, CONTROLLER = "Controller",
	RARE = "Rare nearby", RARE_ELITE = "Rare elite nearby", LEVEL = "%s, level %s", ENEMY = "%s nearby", ENEMY_PLAYER = "Enemy player",
	WHISPER = "Whisper from %s", WHISPER_HIDDEN = "(the game hides this message right now)",
}
Tweaks.T = T

-- Every step of a throttled run (junk, mail, the trainer) waits this long, so the server keeps up.
local STEP = { junk = 0.2, learn = 0.3, mail = 0.4 }
-- Same as Blizzard's merchant: a buy at or above this asks first, so one press never spends it.
local HIGH_PRICE = MERCHANT_HIGH_PRICE_COST or 1500000
local POLL = 0.25
local MERCHANT_ROWS = MERCHANT_ITEMS_PER_PAGE or 10
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0

-- Choices that are gone: key -> old option -> what it becomes. Health on the light bar never worked (the game keeps
-- the player's health secret from addons); it becomes Custom, the player's own colour.
local RETIRED = { lightBar = { health = "custom" } }

function Tweaks.Repair(saved)
	saved = type(saved) == "table" and saved or {}
	local out = {}
	for _, key in ipairs(Tweaks.KEYS) do out[key] = saved[key] == true end
	for key, options in pairs(Tweaks.CHOICES) do
		local value = RETIRED[key] and RETIRED[key][saved[key]] or saved[key]
		out[key] = options[1]
		for _, option in ipairs(options) do if value == option then out[key] = option end end
	end
	for key, range in pairs(Tweaks.NUMBERS) do
		local value = tonumber(saved[key])
		-- On the step grid (tenths), inside the range; NaN fails both comparisons.
		value = value and math.floor(value / range[3] + 0.5) / (1 / range[3])
		out[key] = value and value >= range[1] and value <= range[2] and value or range[4]
	end
	return out
end

function Tweaks.Get(key)
	local saved = ns.db and ns.db.tweaks
	if not saved then return false end
	return saved[key]
end

-- A tweak acts only while it is on and the Gamepad UI is.
local function on(key) return Tweaks.Get(key) and ns.Active() end

local function plural(n) return n == 1 and "" or "s" end

local function money(copper)
	if GetMoneyString then return GetMoneyString(copper, true) end
	return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Unit and chat names may be secret values in this client: never compared or concatenated then.
local function name(value)
	if value == nil or issecretvalue and issecretvalue(value) or value == "" then return T.SOMEONE end
	return value
end

-- A client API that may be missing or fail: nothing then, else every return.
local function pass(ok, ...) if ok then return ... end end
local function call(fn, ...) if fn then return pass(pcall(fn, ...)) end end

local function secret(value) return issecretvalue and issecretvalue(value) or false end

Tweaks.Is, Tweaks.Call, Tweaks.Name, Tweaks.Money, Tweaks.Secret = on, call, name, money, secret

-- In a fight from PLAYER_REGEN_DISABLED (before the lockdown starts) to PLAYER_REGEN_ENABLED.
local fighting

-- One throttled run per name: step() every STEP[name] seconds until it returns false, combat starts or a new run of
-- the same name replaces it.
local runs = {}

local function stop(what)
	if runs[what] then runs[what]:Cancel() end
	runs[what] = nil
end

local function drip(what, step)
	stop(what)
	local ticker
	ticker = C_Timer.NewTicker(STEP[what], function()
		if runs[what] ~= ticker then return ticker:Cancel() end
		if InCombatLockdown() or not step() then stop(what) end
	end)
	runs[what] = ticker
end

-- Which NPC windows are open, from their own events.
local open = {}

---------------------------------------------------------------------------------------------------------------------
-- Bags.

local function bagSlots(fn)
	for bag = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0), NUM_BAG_SLOTS or 4 do
		for slot = 1, call(C_Container.GetContainerNumSlots, bag) or 0 do
			local info = call(C_Container.GetContainerItemInfo, bag, slot)
			if info and fn(bag, slot, info) then return end
		end
	end
end

-- A grey item with a sell price: its value per item, else nil.
local function junkPrice(info)
	if info.quality ~= POOR or info.hasNoValue or not info.itemID then return end
	local price = select(11, call(C_Item.GetItemInfo, info.itemID))
	if price and price > 0 then return price end
end

function Tweaks.SortBags()
	if InCombatLockdown() then return ns.log(T.COMBAT) end
	if PlaySound and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
	C_Container.SortBags()
end

---------------------------------------------------------------------------------------------------------------------
-- Vendors.

-- The junk in the bags: { bag, slot, id, link, count, price } per priced grey slot, read before a sale.
local function junkScan()
	local list = {}
	bagSlots(function(bag, slot, info)
		local price = junkPrice(info)
		if price then list[#list + 1] = { bag = bag, slot = slot, id = info.itemID, link = info.hyperlink, count = info.stackCount or 1, price = price } end
	end)
	return list
end

-- One line for what left the bags since the scan: the count, the coins and the first SOLD_LIST links (with counts),
-- then "and N more". A secret or missing link is counted among the more.
local SOLD_LIST, SOLD_WAIT = 8, 1

local function soldLine(before)
	local count, value, order, byLink, hidden = 0, 0, {}, {}, 0
	for _, item in ipairs(before) do
		local now = call(C_Container.GetContainerItemInfo, item.bag, item.slot)
		local gone = item.count - (now and now.itemID == item.id and (now.stackCount or 1) or 0)
		if gone > 0 then
			count, value = count + gone, value + gone * item.price
			if type(item.link) ~= "string" or secret(item.link) then
				hidden = hidden + 1
			else
				if not byLink[item.link] then order[#order + 1] = item.link end
				byLink[item.link] = (byLink[item.link] or 0) + gone
			end
		end
	end
	if count == 0 then return end
	local parts = {}
	for i, link in ipairs(order) do
		if i <= SOLD_LIST then parts[#parts + 1] = byLink[link] > 1 and link .. " x" .. byLink[link] or link end
	end
	local more = math.max(0, #order - SOLD_LIST) + hidden
	if #parts == 0 then return ns.log(T.SOLD:format(count, plural(count), money(value))) end
	if more > 0 then parts[#parts + 1] = T.SOLD_MORE:format(more) end
	ns.log(T.SOLD_LIST:format(count, plural(count), money(value), table.concat(parts, ", ")))
end

local function sellJunk()
	local before = junkScan()
	if #before == 0 then return end
	local function report() C_Timer.After(SOLD_WAIT, function() soldLine(before) end) end

	local enabled = C_MerchantFrame and C_MerchantFrame.IsSellAllJunkEnabled
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and (not enabled or enabled()) then
		C_MerchantFrame.SellAllJunkItems()
		return report()
	end

	-- One item per step; a slot is tried once, so an item the merchant won't take can't stall the run. It stops when
	-- the merchant closes; either way the line lists only what left the bags.
	local tried = {}
	drip("junk", function()
		if not open.merchant then
			report()
			return false
		end
		local done = true
		bagSlots(function(bag, slot, info)
			local key, price = bag .. ":" .. slot, junkPrice(info)
			if not price or info.isLocked or tried[key] then return end
			tried[key], done = true, false
			C_Container.UseContainerItem(bag, slot)
			return true
		end)
		if done then report() end
		return not done
	end)
end

local function repair()
	if not call(CanMerchantRepair) then return end
	local cost, needed = call(GetRepairAllCost)
	if not (needed and cost and cost > 0) then return end

	if on("repairGuild") and call(CanGuildBankRepair) then
		local withdraw, bank = call(GetGuildBankWithdrawMoney) or 0, call(GetGuildBankMoney) or 0
		local limit = withdraw == -1 and bank or math.min(withdraw, bank)
		if limit >= cost then
			RepairAllItems(true)
			return ns.log(T.REPAIRED_GUILD:format(money(cost)))
		end
	end
	if GetMoney() < cost then return ns.log(T.REPAIR_POOR:format(money(cost))) end
	RepairAllItems()
	ns.log(T.REPAIRED:format(money(cost)))
end

-- The merchant item the gamepad cursor is on: the cursor runs the row's OnEnter, which gives the tooltip to its button.
local function focusedMerchantIndex()
	if not (MerchantFrame and MerchantFrame:IsVisible() and GameTooltip and GameTooltip:IsShown()) then return end
	local owner = GameTooltip:GetOwner()
	for i = 1, MERCHANT_ROWS do
		if owner and owner == _G["MerchantItem" .. i .. "ItemButton"] then return owner:GetID() end
	end
end

-- How many of item index a full stack buys now, its cost and name, and whether it is sold out; nil when it isn't a
-- plain gold buy of a stackable item.
local function stackOf(index)
	local max = call(GetMerchantItemMaxStack, index) or 0
	local info = call(C_MerchantFrame.GetItemInfo, index)
	if max <= 1 or not info or info.hasExtendedCost or info.isPurchasable == false then return end
	local each = (info.price or 0) / math.max(1, info.stackCount or 1)
	local count = max
	if info.numAvailable and info.numAvailable >= 0 then count = math.min(count, info.numAvailable) end
	if each > 0 then count = math.min(count, math.floor(GetMoney() / each)) end
	return count, math.floor(count * each + 0.5), info.name, info.numAvailable == 0
end

function Tweaks.BuyStack(index)
	index = index or focusedMerchantIndex()
	if not index then return ns.log(T.NO_STACK) end
	local count, cost, item, soldOut = stackOf(index)
	if not count then return ns.log(T.NO_STACK) end
	if soldOut then return ns.log(T.SOLD_OUT) end

	if count < 1 then return ns.log(T.STACK_POOR) end
	if cost >= HIGH_PRICE then return ns.log(T.STACK_COST:format(money(cost))) end

	BuyMerchantItem(index, count)
	ns.log(T.BOUGHT:format(count, item or "?", money(cost)))
end

ns.On("MERCHANT_SHOW", function()
	open.merchant = true
	if on("repair") then repair() end
	if on("sellJunk") then sellJunk() end
end)

-- A junk run sees the merchant gone at its next step and reports what sold.
ns.On("MERCHANT_CLOSED", function() open.merchant = false end)

---------------------------------------------------------------------------------------------------------------------
-- Gossip and quest greetings: one thing on offer is picked, once per conversation. A quest only opens its own page.
-- An option is picked only when its icon is a plain service (vendor, trainer, flight map, bank): the chat bubble
-- also starts events, teleports and story skips, so it is never picked.

-- The gossip icons' file ids (Interface/GossipFrame/*GossipIcon).
Tweaks.SAFE_GOSSIP_ICONS = { [132060] = "vendor", [132058] = "trainer", [132057] = "taxi", [132050] = "banker" }
-- Gossip: until GOSSIP_CLOSED (a quest page opened from it closes with QUEST_FINISHED, and the gossip shows again).
-- Greeting: until QUEST_FINISHED, its window's close.
local picked, greeted

-- A gossip option safe to pick unasked: a service icon (no override), available, no cost, reward, spell or flag, no
-- special label, not one Blizzard already picks itself (selectOptionWhenOnlyOption). An option that still asks to
-- confirm (GOSSIP_CONFIRM) gets Blizzard's own popup, which is left to the player.
function Tweaks.SafeOption(option)
	local label, icon = option.name, option.overrideIconID or option.icon
	if secret(label) or secret(icon) or not Tweaks.SAFE_GOSSIP_ICONS[icon] then return false end
	if option.selectOptionWhenOnlyOption or option.status ~= 0 or (option.flags or 0) ~= 0 or option.failureDescription or option.spellID then return false end
	if option.rewards and #option.rewards > 0 then return false end
	return type(label) ~= "string" or not label:find("|[TA]")
end

local function plainQuest(quest) return quest.questID and not quest.isIgnored and not secret(quest.questID) end

local function skipGossip()
	local G = C_GossipInfo
	if picked or not G or call(G.ForceGossip) then return end
	local options, available, active = call(G.GetOptions) or {}, call(G.GetAvailableQuests) or {}, call(G.GetActiveQuests) or {}
	if #options + #available + #active ~= 1 then return end

	picked = true
	if available[1] then return plainQuest(available[1]) and G.SelectAvailableQuest(available[1].questID) end
	if active[1] then return plainQuest(active[1]) and G.SelectActiveQuest(active[1].questID) end
	if Tweaks.SafeOption(options[1]) then G.SelectOption(options[1].gossipOptionID) end
end

local function skipGreeting()
	local available, active = call(GetNumAvailableQuests) or 0, call(GetNumActiveQuests) or 0
	if greeted or available + active ~= 1 then return end

	greeted = true
	if available == 1 then return SelectAvailableQuest(1) end
	SelectActiveQuest(1)
end

ns.On("GOSSIP_SHOW", function() if on("skipGossip") then skipGossip() end end)
ns.On("QUEST_GREETING", function() if on("skipGossip") then skipGreeting() end end)
ns.On("GOSSIP_CLOSED", function() picked = nil end)
ns.On("QUEST_FINISHED", function() greeted = nil end)


---------------------------------------------------------------------------------------------------------------------
-- Trainer: every available service the money covers, last first (a buy never moves the ones above it).

local function learnAll()
	if InCombatLockdown() then return ns.log(T.COMBAT) end
	local tried, learned, spent = {}, 0, 0
	drip("learn", function()
		if not open.trainer then return false end
		for i = call(GetNumTrainerServices) or 0, 1, -1 do
			local _, kind = call(GetTrainerServiceInfo, i)
			local cost = call(GetTrainerServiceCost, i) or 0
			if kind == "available" and not tried[i] and cost <= GetMoney() then
				tried[i], learned, spent = true, learned + 1, spent + cost
				BuyTrainerService(i)
				return true
			end
		end
		if learned > 0 then ns.log(T.LEARNED:format(learned, plural(learned), money(spent))) end
		return false
	end)
end

ns.On("TRAINER_SHOW", function() open.trainer = true end)
ns.On("TRAINER_CLOSED", function()
	open.trainer = false
	stop("learn")
end)

---------------------------------------------------------------------------------------------------------------------
-- Mail: money, then items, one per step, skipping COD and GM mail. Money or an attachment is tried twice at most, so
-- one that won't come out can't stall the run.

local function openAll()
	if InCombatLockdown() then return ns.log(T.COMBAT) end
	local tried, items, gold = {}, 0, 0
	local function finish()
		if items + gold > 0 then ns.log(T.MAIL:format(items, plural(items), money(gold))) end
		return false
	end
	drip("mail", function()
		if not open.mail then return false end
		for i = 1, call(GetInboxNumItems) or 0 do
			local _, _, _, _, cash, cod, _, count, _, _, _, _, isGM = call(GetInboxHeaderInfo, i)
			if (cod or 0) <= 0 and not isGM then
				local key = i .. ":money:" .. tostring(cash)
				if (cash or 0) > 0 and (tried[key] or 0) < 2 then
					tried[key], gold = (tried[key] or 0) + 1, gold + cash
					TakeInboxMoney(i)
					return true
				end
				for a = 1, (count or 0) > 0 and ATTACHMENTS or 0 do
					local item = call(GetInboxItem, i, a)
					local key = i .. ":" .. a .. ":" .. tostring(item)
					if item and (tried[key] or 0) < 2 then
						if (call(C_Container.CalculateTotalNumberOfFreeBagSlots) or 0) <= 0 then
							ns.log(T.BAGS_FULL)
							return finish()
						end
						tried[key], items = (tried[key] or 0) + 1, items + 1
						TakeInboxItem(i, a)
						return true
					end
				end
			end
		end
		return finish()
	end)
end

ns.On("MAIL_SHOW", function() open.mail = true end)
ns.On("MAIL_CLOSED", function()
	open.mail = false
	stop("mail")
end)

---------------------------------------------------------------------------------------------------------------------
-- Rumble: events in groups (Group, Whisper, Trade & duel, Danger, Enemy players, Rare nearby, Level ups, Procs);
-- each group has one pattern (tweaks.rumbleGroups[group], "off" included), and one Rumble strength serves them all.
-- A pattern is a list of steps { seconds, Low, High }: each step sets both motors, the one it doesn't use to 0, at
-- their share of the strength ("High" first, then "Low", the heavy motor, so it is felt whatever the pad keeps). The
-- motors are never stopped between two buzzing steps (a stop and a start in one frame is felt as a stutter); a gap
-- step and the pattern's end call StopVibration. The light High motor is felt only from about half power, so a High
-- share that isn't 0 runs at HIGH_FLOOR at least (idea from Improved Forever, MIT, by markg). SetVibration takes no pad: the active one rumbles. There are no trigger patterns: the
-- game drives only Xbox impulse triggers, not a DualSense's. A new pattern replaces a running one (never stacked);
-- frequent events wait a short cooldown of their own. /fct debug logs each pattern played.

local TAP, GAP = 0.12, 0.1
local PATTERNS = {
	tap = { { TAP, 1, 1 } },
	double = { { TAP, 1, 1 }, { GAP }, { TAP, 1, 1 } },
	triple = { { TAP, 1, 1 }, { GAP }, { TAP, 1, 1 }, { GAP }, { TAP, 1, 1 } },
	long = { { 0.2, 1, 0.5 }, { 0.2, 1, 0.5 }, { 0.2, 1, 0.5 }, { 0.2, 1, 0.5 } },
	heartbeat = { { TAP, 1 }, { 0.08 }, { TAP, 0.6 }, { 0.45 }, { TAP, 1 }, { 0.08 }, { TAP, 0.6 } },
	ramp = { { 0.15, 0.3 }, { 0.15, 0.55 }, { 0.15, 0.8 }, { 0.15, 1, 0.5 } },
	fade = { { 0.15, 1, 0.5 }, { 0.15, 0.8 }, { 0.15, 0.55 }, { 0.15, 0.3 } },
}
Tweaks.PATTERNS = PATTERNS
Tweaks.PATTERN_ORDER = { "off", "tap", "double", "triple", "long", "heartbeat", "ramp", "fade" }
-- Saved patterns of older builds that are gone: what they become.
local PATTERN_NOW = { ltrigger = "tap", rtrigger = "tap", triggers = "tap" }
-- The groups in the tab's order, their starting pattern, and each event's group (the first event of a group is the
-- one an older build's per-event setting carries over from).
Tweaks.RUMBLE_GROUPS = { "group", "whisper", "tradeDuel", "danger", "enemy", "rare", "levelUp", "procs" }
Tweaks.RUMBLE_GROUP_DEFAULT = {
	group = "double", whisper = "tap", tradeDuel = "tap", danger = "long", enemy = "double", rare = "heartbeat",
	levelUp = "ramp", procs = "off",
}
Tweaks.RUMBLE_GROUP_EVENTS = {
	group = { "readyCheck", "invite", "summon", "resurrect" }, whisper = { "whisper" }, tradeDuel = { "trade", "duel" },
	danger = { "death", "lossOfControl", "aggro", "interrupted" }, enemy = { "enemy" }, rare = { "rare" },
	levelUp = { "levelUp", "achievement" }, procs = { "proc", "targetDied", "crit" },
}
local GROUP_OF = {}
for group, events in pairs(Tweaks.RUMBLE_GROUP_EVENTS) do for _, event in ipairs(events) do GROUP_OF[event] = group end end
Tweaks.RUMBLE_GROUP_OF = GROUP_OF
-- Seconds an event waits before it rumbles again; enemy: one rumble for a whole group of enemy players (each player
-- also waits ENEMY_AGAIN on its own). Whispers, invites and trades come in bursts.
local COOLDOWN = { target = 1, interrupted = 1, proc = 2, aggro = 3, whisper = 3, invite = 3, trade = 3, enemy = 10 }
Tweaks.RUMBLE_COOLDOWN = COOLDOWN
-- Events that share a cooldown: a crit that kills the target rumbles once, not crit then targetDied in one frame.
local COOLDOWN_OF = { crit = "target", targetDied = "target" }

-- The motor of each step field, in the order they are set: the heavy one last.
local MOTORS = { { 3, "High" }, { 2, "Low" } }
local HIGH_FLOOR = 0.5

local function snap(value, range)
	value = tonumber(value)
	value = value and math.floor(value / range[3] + 0.5) / (1 / range[3])
	return value and value >= range[1] and value <= range[2] and value or nil
end
Tweaks.Snap = snap

local function pattern(name)
	name = PATTERN_NOW[name] or name
	return (name == "off" or PATTERNS[name]) and name or nil
end

-- Every group's pattern, repaired. Without one saved, an older build's per-event setting (oldEvents[event].pattern)
-- of the group's first event carries over, else the group's default. Gone trigger patterns become Tap.
function Tweaks.RepairRumbleGroups(saved, oldEvents)
	saved, oldEvents = type(saved) == "table" and saved or {}, type(oldEvents) == "table" and oldEvents or {}
	local out = {}
	for _, group in ipairs(Tweaks.RUMBLE_GROUPS) do
		local first = oldEvents[Tweaks.RUMBLE_GROUP_EVENTS[group][1]]
		out[group] = pattern(saved[group]) or type(first) == "table" and pattern(first.pattern) or Tweaks.RUMBLE_GROUP_DEFAULT[group]
	end
	return out
end

-- The one strength: saved, else the average of an older build's per-event strengths, else 60%.
function Tweaks.MigrateRumbleStrength(saved, oldEvents)
	local range = Tweaks.NUMBERS.rumbleStrength
	local kept = snap(saved, range)
	if kept then return kept end
	local sum, n = 0, 0
	for _, entry in pairs(type(oldEvents) == "table" and oldEvents or {}) do
		local strength = type(entry) == "table" and snap(entry.strength, range)
		if strength then sum, n = sum + strength, n + 1 end
	end
	return n > 0 and snap(sum / n, range) or range[4]
end

function Tweaks.RumblePattern(event)
	local groups = ns.db and ns.db.tweaks and ns.db.tweaks.rumbleGroups
	local group = GROUP_OF[event] or event
	return groups and groups[group] or Tweaks.RUMBLE_GROUP_DEFAULT[group]
end

function Tweaks.SetRumbleGroup(group, value)
	local groups = ns.db and ns.db.tweaks and ns.db.tweaks.rumbleGroups
	if groups and Tweaks.RUMBLE_GROUP_DEFAULT[group] then groups[group] = Tweaks.RepairRumbleGroups({ [group] = value })[group] end
end

local playing, cooled = 0, {}

-- A motor's power for a step's share; the High motor's never under HIGH_FLOOR unless it is off.
function Tweaks.MotorPower(motor, share, strength)
	local power = math.min(1, (share or 0) * strength)
	return motor == "High" and power > 0 and math.max(power, HIGH_FLOOR) or power
end

local function setMotors(step, strength)
	local G = C_GamePad
	if not (step[2] or step[3]) then return call(G.StopVibration) end
	local results = {}
	for _, motor in ipairs(MOTORS) do
		local kind = motor[2]
		results[#results + 1] = kind .. " " .. tostring(pcall(G.SetVibration, kind, Tweaks.MotorPower(kind, step[motor[1]], strength)))
	end
	return table.concat(results, ", ")
end


local function strength() return Tweaks.Get("rumbleStrength") or Tweaks.NUMBERS.rumbleStrength[4] end

-- Plays a pattern at a strength (default: the Rumble strength) from its first step; false when there is nothing to
-- play.
function Tweaks.PlayPattern(name, power, why)
	local G, steps = C_GamePad, PATTERNS[name]
	if not (G and G.SetVibration and steps) then return false end
	power = power or strength()
	playing = playing + 1
	local this, i = playing, 0
	local function nextStep()
		if this ~= playing then return end
		i = i + 1
		local step = steps[i]
		if not step then return call(G.StopVibration) end
		local result = setMotors(step, power)
		if i == 1 then ns.debug("rumble %s: %s at %d%%, device %s: %s", tostring(why), name, power * 100, tostring(call(G.GetActiveDeviceID)), result) end
		C_Timer.After(step[1], nextStep)
	end
	nextStep()
	return true
end

-- An event's group pattern while Rumble on events is on; test (the tab's A, with a group's name as the event) plays
-- it either way, without the cooldown.
function Tweaks.Rumble(event, test)
	if not test and not on("rumble") then return end
	local key = COOLDOWN_OF[event] or event
	local now, wait = GetTime(), COOLDOWN[key]
	if not test and wait and cooled[key] and now - cooled[key] < wait then return end
	local name = Tweaks.RumblePattern(event)
	if name == "off" then return end
	local played = Tweaks.PlayPattern(name, nil, test and "test " .. event or event)
	if played and wait then cooled[key] = now end
	return played
end

ns.On("ACHIEVEMENT_EARNED", function() Tweaks.Rumble("achievement") end)

-- The card: GameTooltip's art (TooltipDefaultLayout) on our own frame, near the top of the screen.
local notice, notices = nil, 0
local NOTICE_W, NOTICE_PAD = 420, 12

function Tweaks.Notice(title, text, seconds)
	if not notice then
		notice = CreateFrame("Frame", nil, UIParent)
		notice:SetFrameStrata("HIGH")
		notice:SetPoint("TOP", UIParent, "TOP", 0, -150)
		if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then NineSliceUtil.ApplyLayoutByName(notice, "TooltipDefaultLayout") end
		local color = TOOLTIP_DEFAULT_BACKGROUND_COLOR
		if notice.Center and color and color.GetRGB then notice.Center:SetVertexColor(color:GetRGB()) end
		notice.title = notice:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		notice.title:SetPoint("TOP", 0, -NOTICE_PAD)
		notice.text = notice:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		notice.text:SetPoint("TOP", notice.title, "BOTTOM", 0, -4)
		notice.text:SetWidth(NOTICE_W - 2 * NOTICE_PAD)
		notice.text:SetMaxLines(2)
	end
	notice.title:SetText(title)
	notice.text:SetText(text or "")
	notice:SetSize(NOTICE_W, notice.title:GetStringHeight() + notice.text:GetStringHeight() + 2 * NOTICE_PAD + 4)
	notice:Show()
	notices = notices + 1
	local this = notices
	C_Timer.After(seconds, function() if this == notices then notice:Hide() end end)
end

ns.On("READY_CHECK", function(initiator) if secret(initiator) or initiator ~= UnitName("player") then Tweaks.Rumble("readyCheck") end end)
ns.On("PLAYER_DEAD", function() Tweaks.Rumble("death") end)
ns.On("LOSS_OF_CONTROL_ADDED", function(unit) if not secret(unit) and unit == "player" then Tweaks.Rumble("lossOfControl") end end)
ns.On("PLAYER_LEVEL_UP", function() Tweaks.Rumble("levelUp") end)
ns.On("TRADE_REQUEST", function() Tweaks.Rumble("trade") end)
-- A proc: a spell on the bars starts to glow.
ns.On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function() Tweaks.Rumble("proc") end)
-- Aggro: the player's own threat state turns to 3 (tanking); one unit token, so not secret.
local threat
ns.On("UNIT_THREAT_SITUATION_UPDATE", function(unit)
	if secret(unit) or unit ~= "player" then return end
	local now = call(UnitThreatSituation, "player")
	if secret(now) then return end
	if now == 3 and threat ~= 3 then Tweaks.Rumble("aggro") end
	threat = now
end)
-- The target's hostility, read when it changes (or its faction does) while alive: a target that just died is no
-- longer attackable, so a check after the killing blow would miss it.
local targetDead, targetEnemy
ns.On("PLAYER_TARGET_CHANGED", function()
	local dead, enemy = call(UnitIsDead, "target"), call(UnitCanAttack, "player", "target")
	targetDead = secret(dead) or dead
	targetEnemy = not secret(enemy) and enemy
end)
ns.On("UNIT_FACTION", function(unit)
	if secret(unit) or unit ~= "target" then return end
	local dead, enemy = call(UnitIsDead, "target"), call(UnitCanAttack, "player", "target")
	if not secret(dead) and not dead then targetEnemy = not secret(enemy) and enemy end
end)
-- Target died: the target's health changes and it is dead, once per target.
ns.On("UNIT_HEALTH", function(unit)
	if secret(unit) or unit ~= "target" or targetDead then return end
	local dead = call(UnitIsDead, "target")
	if secret(dead) or not dead then return end
	targetDead = true
	if targetEnemy then Tweaks.Rumble("targetDied") end
end)
-- Critical strike: a critical hit on an enemy target, only while not in a group: the event doesn't say who hit, so
-- in a group other players' crits would count. Only the amount is secret, and it is never read.
ns.On("UNIT_COMBAT", function(unit, action, flag)
	if secret(unit) or secret(action) or secret(flag) or unit ~= "target" or action ~= "WOUND" or flag ~= "CRITICAL" or call(IsInGroup) then return end
	if targetEnemy then Tweaks.Rumble("crit") end
end)
-- Interrupted: the player's own cast (not secret for the player).
ns.On("UNIT_SPELLCAST_INTERRUPTED", function(unit) if not secret(unit) and unit == "player" then Tweaks.Rumble("interrupted") end end)

---------------------------------------------------------------------------------------------------------------------
-- Low battery: one line a session, for a drop the game reports after a plain Medium or High. A level read at login
-- never warns, and a pad without a battery (Unknown, Wired, a Steam Deck's Unknown then Critical) never does.

local POWER = Enum and Enum.GamePadPowerLevel or { Critical = 0, Low = 1, Medium = 2, High = 3, Wired = 4, Unknown = 5 }
local power, powerTold

ns.On("PLAYER_ENTERING_WORLD", function()
	if power == nil and C_GamePad then power = call(C_GamePad.GetPowerLevel) end
end)

ns.On("GAME_PAD_POWER_CHANGED", function(level)
	local was = power
	power = level
	if powerTold or not on("battery") or not (was == POWER.Medium or was == POWER.High) then return end
	if level ~= POWER.Low and level ~= POWER.Critical then return end

	powerTold = true
	ns.log(level == POWER.Critical and T.BATTERY_CRITICAL or T.BATTERY_LOW)
end)

---------------------------------------------------------------------------------------------------------------------
-- Battery on the minimap: a round minimap button like its neighbours on the minimap's left edge (the gold
-- MiniMap-TrackingBorder ring on the dark UI-Minimap-Background, the zoom buttons' highlight, the battery nudged while
-- pressed). Inside, a battery drawn from colour textures (the client has no battery art): a parchment outline with a
-- cap on the right and four segments, the first ones lit in the level's colour, the rest dark: High 4 green, Medium
-- 3 yellow, Low 2 orange, Critical 1 red, Wired 4 blue; hidden for Unknown or no pad.
-- The battery is laid out in whole screen pixels at the button's scale, so its lines and gaps stay sharp and even.
-- Placement: on the ring with its neighbours, read from the minimap's own child buttons (read only): their radius
-- and spacing, at the next step below the lowest of them on the left side. Without neighbours, LibDBIcon's default
-- radius (the map's half width + 5) at 220 degrees. Our frame takes the minimap's scale, so it matches the
-- neighbours' size, and is placed again when the map, its scale or the neighbours change.
-- The level changes only on the game's events; the window-button poll places and shows it (read only).

local BATTERY_BARS = { [POWER.Critical] = 1, [POWER.Low] = 2, [POWER.Medium] = 3, [POWER.High] = 4, [POWER.Wired] = 4 }
local BATTERY_RGB = {
	[POWER.Critical] = { 1, 0.1, 0.1 }, [POWER.Low] = { 1, 0.5, 0 }, [POWER.Medium] = { 1, 0.82, 0 },
	[POWER.High] = { 0.1, 1, 0.1 }, [POWER.Wired] = { 0.25, 0.65, 1 },
}
local BATTERY_OUTLINE, BATTERY_UNLIT = { 0.9, 0.8, 0.55, 1 }, { 0, 0, 0, 0.6 }
local BATTERY_SIZE = 31
-- Without neighbours: LibDBIcon's ring offset and an angle below the usual left-edge buttons. With them: their step,
-- kept between STEP_MIN and STEP_MAX, never past ANGLE_MAX (the coordinates text sits at the bottom, 270).
local RING_OFFSET, ANGLE_DEFAULT, STEP_DEFAULT, STEP_MIN, STEP_MAX, ANGLE_MAX = 5, 220, 22, 15, 40, 250
local battery, batteryLevel

-- One screen pixel in units of a region at this effective scale (the client's PixelUtil factor).
local function pixelSize(scale)
	local _, height = call(GetPhysicalScreenSize)
	return 768 / ((height and height > 0 and height or 768) * (scale or 1))
end

local function round(x) return math.floor(x + 0.5) end

-- The battery in whole pixels, about 15 x 9 units with a 2 x 4 cap: lines and gaps one pixel per whole unit, the
-- segments share the rest. Everything hangs off the top edge, so moving it moves the battery.
local function layoutBattery()
	local edge, p = battery.edge, pixelSize(battery:GetEffectiveScale())
	local f = 1 / p
	local line = math.max(1, math.floor(f))
	local width, height = math.max(2, round((round(15 * f) - 7 * line) / 4)), math.max(3, round(9 * f) - 4 * line)
	local bodyW, bodyH, capW, capInset = 7 * line + 4 * width, 4 * line + height, math.max(1, round(2 * f)), round(2.5 * f)
	edge.top:SetSize(bodyW * p, line * p)
	edge.bottom:SetSize(bodyW * p, line * p)
	edge.bottom:SetPoint("TOPLEFT", edge.top, "TOPLEFT", 0, -(bodyH - line) * p)
	edge.left:SetSize(line * p, bodyH * p)
	edge.left:SetPoint("TOPLEFT", edge.top, "TOPLEFT")
	edge.right:SetSize(line * p, bodyH * p)
	edge.right:SetPoint("TOPRIGHT", edge.top, "TOPRIGHT")
	edge.cap:SetSize(capW * p, math.max(1, bodyH - 2 * capInset) * p)
	edge.cap:SetPoint("TOPLEFT", edge.top, "TOPRIGHT", 0, -capInset * p)
	for i, segment in ipairs(battery.segments) do
		segment:SetSize(width * p, height * p)
		segment:SetPoint("TOPLEFT", edge.top, "TOPLEFT", (2 * line + (i - 1) * (width + line)) * p, -2 * line * p)
	end
	battery.ox, battery.oy, battery.nudge = -math.floor((bodyW + capW) / 2) * p, (math.floor(bodyH / 2) + line) * p, line * p
	edge.top:SetPoint("TOPLEFT", battery, "CENTER", battery.ox, battery.oy)
end

-- Pressed: the battery moves right and down by a line, as its neighbours' icons do.
local function pressBattery(self, down)
	local nudge = down and self.nudge or 0
	self.edge.top:SetPoint("TOPLEFT", self, "CENTER", self.ox + nudge, self.oy - nudge)
end

local function batteryRect(color)
	local texture = battery:CreateTexture(nil, "ARTWORK")
	texture:SetSnapToPixelGrid(false)
	texture:SetTexelSnappingBias(0)
	if color then texture:SetColorTexture(color[1], color[2], color[3], color[4]) end
	return texture
end

local function buildBattery()
	battery = CreateFrame("Button", nil, UIParent)
	battery:SetSize(BATTERY_SIZE, BATTERY_SIZE)
	local background = battery:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	battery.edge, battery.segments = {}, {}
	for _, side in ipairs({ "top", "bottom", "left", "right", "cap" }) do battery.edge[side] = batteryRect(BATTERY_OUTLINE) end
	for i = 1, 4 do battery.segments[i] = batteryRect() end
	layoutBattery()
	battery.ring = battery:CreateTexture(nil, "OVERLAY")
	battery.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	battery.ring:SetSize(53, 53)
	battery.ring:SetPoint("TOPLEFT")
	battery:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	battery:SetScript("OnMouseDown", function(self) pressBattery(self, true) end)
	battery:SetScript("OnMouseUp", function(self) pressBattery(self, false) end)
	battery:SetScript("OnEnter", function(self)
		local device = ns.Device and ns.Device.Current and ns.Device.Current()
		if ns.UI then ns.UI.Tooltip(self, { title = device and device.name or T.CONTROLLER, lines = { T.BATTERY_LEVEL[batteryLevel] or "" }, side = "right" }) end
	end)
	battery:SetScript("OnLeave", function(self) if ns.UI then ns.UI.HideTooltip(self) end end)
	battery:Hide()
end

local function drawBattery()
	local bars, rgb = BATTERY_BARS[batteryLevel], BATTERY_RGB[batteryLevel]
	if not (battery and bars) then return end
	layoutBattery()
	for i, segment in ipairs(battery.segments) do
		local color = i <= bars and { rgb[1], rgb[2], rgb[3], 1 } or BATTERY_UNLIT
		segment:SetColorTexture(color[1], color[2], color[3], color[4])
	end
	battery.bars = bars
end

local function readBattery(level)
	if level == nil and C_GamePad then level = call(C_GamePad.GetPowerLevel) end
	batteryLevel = not secret(level) and level or nil
	drawBattery()
end

ns.On("PLAYER_ENTERING_WORLD", function() readBattery() end)
ns.On("GAME_PAD_POWER_CHANGED", readBattery)
for _, event in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "GAME_PAD_ACTIVE_CHANGED" }) do ns.On(event, function() readBattery() end) end

-- The spot on the ring from the neighbours ({ angle, radius } each, degrees counter-clockwise from the right, in the
-- map's units): their average radius, one step (their average spacing) below the lowest on the left side.
function Tweaks.BatterySpot(neighbours, mapWidth)
	local left = {}
	for _, n in ipairs(neighbours or {}) do if n.angle >= 90 and n.angle < 270 then left[#left + 1] = n end end
	if #left == 0 then return mapWidth / 2 + RING_OFFSET, ANGLE_DEFAULT end
	table.sort(left, function(a, b) return a.angle < b.angle end)
	local radius = 0
	for _, n in ipairs(left) do radius = radius + n.radius end
	local step = #left > 1 and (left[#left].angle - left[1].angle) / (#left - 1) or STEP_DEFAULT
	step = math.max(STEP_MIN, math.min(STEP_MAX, step))
	return radius / #left, math.min(ANGLE_MAX, left[#left].angle + step)
end

function Tweaks.BatteryOffset(radius, angle)
	local a = math.rad(angle)
	return math.floor(radius * math.cos(a) + 0.5), math.floor(radius * math.sin(a) + 0.5)
end

-- The minimap's own round buttons near its ring (any addon's or the game's, shown), in the map's units.
local function neighbours(map)
	local mx, my = map:GetCenter()
	local scale, width, out = map:GetEffectiveScale(), map:GetWidth(), {}
	if not (mx and scale and width) then return out end
	for _, child in ipairs({ map:GetChildren() }) do
		local button = child ~= battery and child:IsShown() and child.IsObjectType and child:IsObjectType("Button")
		local cx, cy
		if button then cx, cy = child:GetCenter() end
		local size = cx and cy and child:GetWidth()
		if size and size >= 20 and size <= 40 then
			local s = child:GetEffectiveScale() / scale
			local dx, dy = cx * s - mx, cy * s - my
			local radius = math.sqrt(dx * dx + dy * dy)
			if radius >= width / 2 * 0.85 and radius <= width / 2 + 30 then out[#out + 1] = { angle = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)) % 360, radius = radius } end
		end
	end
	return out
end

-- Shown with the minimap while on and the pad reports a battery or a cable, on the ring beside its neighbours.
function Tweaks.UpdateBattery(wanted)
	if wanted and not battery then buildBattery() end
	if not battery then return end
	local map = wanted and BATTERY_BARS[batteryLevel] and Minimap and Minimap:IsVisible() and Minimap
	if not map then return battery:Hide() end
	local width = map:GetWidth() or 0
	local ok, list = pcall(neighbours, map)
	local x, y = Tweaks.BatteryOffset(Tweaks.BatterySpot(ok and list or nil, width))
	local scale = (map:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	-- The pixel size joins the key, so a UI scale or window change lays the battery out again.
	local spot = x .. " " .. y .. " " .. scale .. " " .. pixelSize(map:GetEffectiveScale())
	if battery.spot ~= spot or battery.anchor ~= map then
		battery.spot, battery.anchor = spot, nil
		battery:SetScale(scale)
		drawBattery()
	end
	Tweaks.Place(battery, map, "CENTER", "CENTER", x, y)
end

---------------------------------------------------------------------------------------------------------------------
-- Rare nearby: once per rare a session, from its minimap vignette (whose name is readable) or its name plate (only
-- when the game lets us read its name). Quiet in a fight, on a flight path and while dead; a rare met then can
-- still show later.

local RARE_ATLAS = { VignetteKill = "rare", VignetteKillElite = "rareelite" }
local rares = {}

local function rareSeen(key, label, kind, level)
	if not key or rares[key] or fighting or InCombatLockdown() or call(UnitIsDeadOrGhost, "player") or call(UnitOnTaxi, "player") then return end
	rares[key] = true
	Tweaks.Notice(kind == "rareelite" and T.RARE_ELITE or T.RARE, level and T.LEVEL:format(label, level) or label, 5)
	Tweaks.Rumble("rare")
end

ns.On("VIGNETTE_MINIMAP_UPDATED", function(guid, onMinimap)
	if not (onMinimap and on("rareAlert") and C_VignetteInfo) then return end
	local info = call(C_VignetteInfo.GetVignetteInfo, guid)
	local kind = info and not secret(info.atlasName) and RARE_ATLAS[info.atlasName]
	if not kind or info.isDead then return end
	local key = not secret(info.objectGUID) and info.objectGUID or not secret(guid) and guid or nil
	rareSeen(key, name(info.name), kind)
end)

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
	if not on("rareAlert") or secret(unit) then return end
	local kind = call(UnitClassification, unit)
	if secret(kind) or kind ~= "rare" and kind ~= "rareelite" then return end
	local label, guid, level = call(UnitName, unit), call(UnitGUID, unit), call(UnitLevel, unit)
	if secret(label) or secret(guid) or not guid or call(UnitIsDead, unit) or not call(UnitCanAttack, "player", unit) then return end
	rareSeen(guid, label, kind, not secret(level) and level and level > 0 and level or "??")
end)

---------------------------------------------------------------------------------------------------------------------
-- Enemy player nearby: a player of the other faction's name plate shows (so enemy name plates must be on). Once per
-- player every ENEMY_AGAIN seconds; the event's own cooldown makes a group one rumble. Not in battlegrounds, arenas
-- or sanctuaries. The rare card says who, when the rumble plays. Any secret read skips the unit.

local ENEMY_AGAIN = 120
local enemies = {}

local function quietZone()
	local _, kind = call(IsInInstance)
	if kind == "pvp" or kind == "arena" then return true end
	return C_PvP and call(C_PvP.GetZonePVPInfo) == "sanctuary"
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
	if not on("rumble") or secret(unit) or Tweaks.RumblePattern("enemy") == "off" then return end
	local isPlayer, enemy = call(UnitIsPlayer, unit), call(UnitIsEnemy, "player", unit)
	local theirs, faction = call(UnitFactionGroup, unit)
	local mine = call(UnitFactionGroup, "player")
	local label, guid, level = call(UnitName, unit), call(UnitGUID, unit), call(UnitLevel, unit)
	for _, value in ipairs({ isPlayer, enemy, theirs, faction, mine, label, guid, level }) do if secret(value) then return end end
	if not (isPlayer and enemy and guid and theirs and theirs ~= mine) or quietZone() then return end
	local now = GetTime()
	if enemies[guid] and now - enemies[guid] < ENEMY_AGAIN then return end
	enemies[guid] = now
	if Tweaks.Rumble("enemy") then Tweaks.Notice(T.ENEMY:format(faction or T.ENEMY_PLAYER), T.LEVEL:format(name(label), level and level > 0 and level or "??"), 5) end
end)

---------------------------------------------------------------------------------------------------------------------
-- Group and social.

-- A friend (game or Battle.net) or a guild member, by GUID.
function Tweaks.Trusted(guid)
	if not guid or secret(guid) then return false end
	if call(C_FriendList and C_FriendList.IsFriend, guid) then return true end
	if call(C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID, guid) then return true end
	return not not call(IsGuildMember, guid)
end

-- "Name-Realm" (realm without spaces or dashes, as the guild roster has it); nil for a secret or missing name.
local function fullName(who, realm)
	if type(who) ~= "string" or secret(who) or who == "" then return end
	if who:find("-", 1, true) then return who end
	realm = realm or call(GetNormalizedRealmName)
	if secret(realm) then return end
	return type(realm) == "string" and who .. "-" .. (realm:gsub("[%s%-]", "")) or who

end

-- The same trust by name, for a summoner (the summon gives no GUID).
function Tweaks.TrustedName(who)
	local want = fullName(who)
	if not want then return false end
	if call(C_FriendList and C_FriendList.GetFriendInfo, who) then return true end
	for i = 1, call(GetNumGuildMembers) or 0 do
		if fullName((call(GetGuildRosterInfo, i))) == want then return true end
	end
	local B = C_BattleNet
	for i = 1, B and call(BNGetNumFriends) or 0 do
		for j = 1, call(B.GetFriendNumGameAccounts, i) or 0 do
			local game = call(B.GetFriendGameAccountInfo, i, j)
			if game and fullName(game.characterName, game.realmName) == want then return true end
		end
	end
	return false
end

-- A plain invite only: a role check (LFG), a quest session invite, or one that would drop the player's dungeon or
-- PvP queue (Blizzard warns about that in the popup) needs the player's answer.
-- Each one the player still has to answer rumbles (Rumble on events); one a tweak answered doesn't.
ns.On("PARTY_INVITE_REQUEST", function(inviter, tank, healer, damage, _, _, _, guid, questSession)
	local ask = tank or healer or damage or questSession or call(WillAcceptInviteRemoveQueues)
	if not on("acceptInvites") or ask or not Tweaks.Trusted(guid) then return Tweaks.Rumble("invite") end
	AcceptGroup()
	ns.log(T.INVITE:format(name(inviter)))
end)

ns.On("DUEL_REQUESTED", function(challenger)
	if not on("declineDuels") then return Tweaks.Rumble("duel") end
	CancelDuel()
	ns.log(T.DUEL:format(name(challenger)))
end)

-- A resurrection that brings sickness is the player's call; a spirit healer's goes through CONFIRM_XP_LOSS, not here.
ns.On("RESURRECT_REQUEST", function(offerer)
	if not on("acceptRes") or InCombatLockdown() or call(ResurrectHasSickness) then return Tweaks.Rumble("resurrect") end
	AcceptResurrect()
	ns.log(T.RES:format(name(offerer)))
end)

-- A summon from a friend or guild member only, and never inside an instance (it would take the player out).
ns.On("CONFIRM_SUMMON", function()
	local S = C_SummonInfo
	local summoner, area = call(S.GetSummonConfirmSummoner), call(S.GetSummonConfirmAreaName)
	local stay = InCombatLockdown() or call(IsInInstance) or PlayerCanTeleport and not PlayerCanTeleport()
	if not on("acceptRes") or stay or not Tweaks.TrustedName(summoner) then return Tweaks.Rumble("summon") end
	S.ConfirmSummon()

	ns.log(T.SUMMON:format(name(summoner), name(area)))
end)

-- Whisper alert: the sender and the start of the message on the card; while the game keeps them secret, only that a
-- whisper came.
local WHISPER_CUT = 90

local function whispered(text, sender)
	Tweaks.Rumble("whisper")
	if not on("whisperAlert") then return end
	local hidden = secret(text) or secret(sender) or type(text) ~= "string"
	local who = hidden and T.SOMEONE or Ambiguate and call(Ambiguate, sender, "short") or name(sender)
	local body = hidden and T.WHISPER_HIDDEN or #text > WHISPER_CUT and text:sub(1, WHISPER_CUT - 3):gsub("[\192-\255][\128-\191]*$", "") .. "..." or text
	Tweaks.Notice(T.WHISPER:format(who), body, 6)
end

ns.On("CHAT_MSG_WHISPER", whispered)
ns.On("CHAT_MSG_BN_WHISPER", whispered)

---------------------------------------------------------------------------------------------------------------------
-- Window buttons: our own, over the Blizzard window, shown while it is visible.

local buttons = {}

local function tip(button, title, line)
	button:SetScript("OnEnter", function(self) if ns.UI then ns.UI.Tooltip(self, { title = title, lines = { line } }) end end)
	button:SetScript("OnLeave", function(self) if ns.UI then ns.UI.HideTooltip(self) end end)
end

local function textButton(text, width, onClick)
	local button = CreateFrame("Button", nil, UIParent, "SharedButtonSmallTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:Hide()
	return button
end

-- Shows button on anchor (point, relative point, x, y) while shown (default: anchor) is visible, a level above it.
local function place(button, anchor, point, relativePoint, x, y, shown)
	shown = shown or anchor
	if not (anchor and shown and shown:IsVisible()) then return button:Hide() end
	if button.anchor ~= anchor then
		button:ClearAllPoints()
		button:SetPoint(point, anchor, relativePoint, x, y)
		button.anchor = anchor
	end
	button:SetFrameStrata(anchor:GetFrameStrata())
	button:SetFrameLevel(anchor:GetFrameLevel() + 10)
	button:Show()
end

-- Sort on the combined bags' title bar: the size of the title bar's close button.
local SORT_SMALL = 22

local function build()
	-- Blizzard's own sort button's art. Our frames here are never children of Blizzard windows, so the pad cursor
	-- (SmartNavigation walks only a window's own children) can't land on them or be blocked by them.
	local sort = CreateFrame("Button", nil, UIParent)
	sort:SetSize(28, 26)
	sort:SetNormalAtlas("bags-button-autosort-up")
	sort:SetPushedAtlas("bags-button-autosort-down")
	sort:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	sort:SetScript("OnClick", Tweaks.SortBags)
	tip(sort, T.SORT_TIP, T.SORT_PAD)
	sort:Hide()
	buttons.sort = sort

	buttons.stack = {}
	for i = 1, MERCHANT_ROWS do
		local stack = textButton(T.STACK, 48, function(self) Tweaks.BuyStack(self.index) end)
		tip(stack, T.STACK_TIP)
		buttons.stack[i] = stack
	end
	buttons.learn = textButton(T.LEARN, 96, learnAll)
	buttons.mail = textButton(T.OPEN, 96, openAll)
end

local function rows(fn)
	for i = 1, MERCHANT_ROWS do fn(buttons.stack[i], _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"]) end
end

local function update()
	if not buttons.sort then return end
	-- Combined bags (the Gamepad UI's): their search box spans the whole top row, so Sort sits on the title bar, left
	-- of the close button. Separate bags: Blizzard's own sort button's place (hidden in the Gamepad UI).
	local combined = ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() and ContainerFrameCombinedBags
	local close = combined and combined.CloseButton
	if close then
		buttons.sort:SetSize(SORT_SMALL, SORT_SMALL)
		place(buttons.sort, on("sortBags") and close, "RIGHT", "LEFT", -2, 0, combined)
	else
		buttons.sort:SetSize(28, 26)
		place(buttons.sort, on("sortBags") and (combined or ContainerFrame1), "TOPRIGHT", "TOPRIGHT", combined and -30 or -9, combined and -3 or -34)
	end

	local buying = on("buyStack") and MerchantFrame and MerchantFrame:IsVisible() and MerchantFrame.selectedTab == 1
	rows(function(stack, row, item)
		stack.index = item and item:GetID()
		local stackable = buying and item and item:IsVisible() and stackOf(stack.index)
		place(stack, stackable and row, "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2)
	end)

	place(buttons.learn, on("learnAll") and ClassTrainerTrainButton, "RIGHT", "LEFT", -4, 0)
	-- Blizzard's own Open All spot: that button is hidden in the Gamepad UI (its footer has Open All instead).
	place(buttons.mail, on("openMail") and InboxFrame and InboxFrame.OpenAllMail, "CENTER", "CENTER", 0, 0, InboxFrame)
end

-- ponytail: one poll for every window button and arrow while any of them is on, instead of hooks on Blizzard frames:
-- a few IsVisible reads every POLL seconds. Tweaks.Poll(keys, fn) adds one (TweaksGear.lua's arrows).
local poller
local polls = { { keys = { "sortBags", "buyStack", "learnAll", "openMail" }, fn = function() update() end } }

local function wanted(poll)
	for _, key in ipairs(poll.keys) do if on(key) then return true end end
	return false
end

local function tick()
	for _, poll in ipairs(polls) do poll.fn(wanted(poll)) end
end

function Tweaks.Poll(keys, fn) polls[#polls + 1] = { keys = keys, fn = fn } end

Tweaks.Place = place
Tweaks.Poll({ "batteryIcon" }, function(wanted) Tweaks.UpdateBattery(wanted) end)

function Tweaks.Refresh()
	local any = false
	for _, poll in ipairs(polls) do any = any or wanted(poll) end
	if not buttons.sort and wanted(polls[1]) then build() end
	tick()
	if any and not poller then poller = C_Timer.NewTicker(POLL, tick) end
	if poller and not any then
		poller:Cancel()
		poller = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The controller's light bar (DualSense, DualShock 4): the game's own colour, the class colour or a Custom colour;
-- Combat flash is red in a fight. No health colour: the game keeps the player's health secret from addons. The
-- light is written only when its colour changes, and given back to the game (ClearLedColor) only after we set it:
-- when the choice goes back to Game default, the Gamepad UI goes off, and at logout.

local lit

local function classColour()
	local _, class = UnitClass("player")
	local color = class and (C_ClassColor and call(C_ClassColor.GetClassColor, class) or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if color then return { color.r, color.g, color.b } end
end

local function wantedLight()
	if not ns.Active() then return end
	if fighting and Tweaks.Get("combatFlash") then return Tweaks.LIGHT.red end
	local mode = Tweaks.Get("lightBar")
	if mode == "class" then return classColour() end
	if mode == "custom" then return Tweaks.LIGHT[Tweaks.Get("lightColor")] end
end

-- force: write again although the colour is the same (another controller, or one plugged back in).
function Tweaks.Light(force)
	local G = C_GamePad
	if not (G and G.SetLedColor and G.ClearLedColor) then return end
	local color = wantedLight()
	local key = color and string.format("%.2f %.2f %.2f", color[1], color[2], color[3])
	if key == lit and not force then return end

	if key then
		G.SetLedColor(CreateColor and CreateColor(color[1], color[2], color[3]) or { r = color[1], g = color[2], b = color[3] })
	elseif lit then
		G.ClearLedColor()
	end
	lit = key
end

ns.On("PLAYER_REGEN_DISABLED", function() fighting = true Tweaks.Light() end)
ns.On("PLAYER_REGEN_ENABLED", function() fighting = false Tweaks.Light() end)
ns.On("PLAYER_ENTERING_WORLD", function() Tweaks.Light() end)
ns.On("GAME_PAD_ACTIVE_CHANGED", function() Tweaks.Light(true) end)
ns.On("GAME_PAD_CONNECTED", function() Tweaks.Light(true) end)
ns.On("PLAYER_LOGOUT", function()
	if lit and C_GamePad and C_GamePad.ClearLedColor then C_GamePad.ClearLedColor() end
	lit = nil
end)

function Tweaks.Set(key, value)
	if not ns.db then return end
	if Tweaks.CHOICES[key] or Tweaks.NUMBERS[key] then ns.db.tweaks[key] = Tweaks.Repair({ [key] = value })[key] else ns.db.tweaks[key] = not not value end
	Tweaks.Refresh()
	Tweaks.Light()
end

ns.On("FCT_READY", function()
	local old = type(ns.db.tweaks) == "table" and ns.db.tweaks or {}
	ns.db.tweaks = Tweaks.Repair(old)
	-- Rumble: a pattern per group and one strength; an older build's per-event settings carry over.
	ns.db.tweaks.rumbleGroups = Tweaks.RepairRumbleGroups(old.rumbleGroups, old.rumbleEvents)
	ns.db.tweaks.rumbleStrength = Tweaks.MigrateRumbleStrength(old.rumbleStrength, old.rumbleEvents)
	Tweaks.Refresh()
	Tweaks.Light()
end)
ns.On("FCT_ACTIVE_CHANGED", function()
	Tweaks.Refresh()
	Tweaks.Light()
end)
