-- Forever Controller Tweaks picker actions with buttons of their own (Actions.lua lists them; the plain-text ones,
-- Cancel, Ready check and Pull countdown, are only macro text there):
--   Look behind (hold)  the camera turns round while held (FlipCameraYaw, as the game's own flip binding does) and
--                       back on the release. A lost release (a window took the pad) is made good by the next press,
--                       and combat start turns it back. A tap from a touch button or ring is a toggle.
--   Peek map (hold)     our secure button clicks the game's own map button on the press and again on the release.
--                       When the map is already open at a press (its window kept the last release), that press only
--                       closes it. A tap is a toggle. Nothing is shown or hidden by our own code.
--   Track nearest quest the nearest quest by distance; again for the next nearest (C_SuperTrack).
--   Mark next           the next raid mark in kill order (skull, cross, square, moon, triangle, diamond, circle, star)
--                       on the target with /tm, counted in a secure snippet so it works in combat too; back to skull
--                       after combat and when the group changes.
--   Best healing potion, Best mana potion, Best grenade
--                       /use of the best of that kind in the bags (Gear.Best's one pass, see Gear.Dirty), written out
--                       of combat on bag changes.
--   Minimap zoom        our secure button clicks the minimap's own zoom-in button, then zoom-out once fully in, and
--                       back. Blizzard's button does the zooming; nothing of the minimap is written here.
local _, ns = ...
local Tweaks = ns.Tweaks
local Gear = Tweaks.Gear
local call, secret = Tweaks.Call, Tweaks.Secret

local T = { TRACKING = "Tracking: %s", NO_QUEST = "Track nearest quest: no quest with a place on the map." }
Tweaks.ActionsT = T

---------------------------------------------------------------------------------------------------------------------
-- Look behind.

local look = CreateFrame("Button", "ForeverControllerTweaksLookBehind", UIParent)
look:RegisterForClicks("AnyUp", "AnyDown")
local behind, spent

local function turn()
	if FlipCameraYaw then FlipCameraYaw(180) end
	behind = not behind
end

look:SetScript("OnClick", function(_, button, down)
	if button == "RightButton" then return turn() end
	if down then
		-- Still behind: the last release never came. This press only turns back, and its own release does nothing.
		spent = behind
		return turn()
	end
	if spent then spent = false return end
	if behind then turn() end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
	if behind then turn() end
	spent = false
end)

---------------------------------------------------------------------------------------------------------------------
-- Peek map: a press-and-hold secure button (type on the press, typerelease on the release).

local MAP_BUTTONS = { "QuestLogMicroButton", "WorldMapMicroButton" }
local map = CreateFrame("Button", "ForeverControllerTweaksPeekMap", UIParent, "SecureActionButtonTemplate")
map:RegisterForClicks("AnyUp", "AnyDown")
map:SetAttribute("useOnKeyDown", true)
map:SetAttribute("pressAndHoldAction", true)
map:SetAttribute("type", "click")
map:SetAttribute("typerelease", "click")

local function mapOpen() return WorldMapFrame and WorldMapFrame:IsShown() or false end

-- Out of combat only (attributes are locked in combat): a press on an open map closes it and leaves its release be.
map:SetScript("PreClick", function(self, button, down)
	if InCombatLockdown() then return end
	if button == "RightButton" then return self:SetAttribute("typerelease", "click") end
	if down then self:SetAttribute("typerelease", not mapOpen() and "click" or nil) end
end)

local function aimMap()
	if InCombatLockdown() or map:GetAttribute("clickbutton") then return end
	for _, name in ipairs(MAP_BUTTONS) do
		if _G[name] then return map:SetAttribute("clickbutton", _G[name]) end
	end
end
ns.On("PLAYER_ENTERING_WORLD", aimMap)

---------------------------------------------------------------------------------------------------------------------
-- Track nearest quest.

local function nearest()
	local Q, list = C_QuestLog, {}
	if not Q then return list end
	for i = 1, call(Q.GetNumQuestLogEntries) or 0 do
		local info = call(Q.GetInfo, i)
		local distance = info and not info.isHeader and info.questID and call(Q.GetDistanceSqToQuest, info.questID)
		if distance and not secret(distance) then list[#list + 1] = { id = info.questID, title = info.title, distance = distance } end
	end
	table.sort(list, function(a, b) return a.distance < b.distance end)
	return list
end

function Tweaks.TrackNearest()
	local list = nearest()
	if not (list[1] and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return ns.log(T.NO_QUEST) end
	local current, pick = call(C_SuperTrack.GetSuperTrackedQuestID), list[1]
	for i, quest in ipairs(list) do
		if quest.id == current then pick = list[i % #list + 1] end
	end
	C_SuperTrack.SetSuperTrackedQuestID(pick.id)
	ns.log(T.TRACKING:format(Tweaks.Name(pick.title)))
end

local track = CreateFrame("Button", "ForeverControllerTweaksTrackQuest", UIParent)
track:SetScript("OnClick", function() Tweaks.TrackNearest() end)

---------------------------------------------------------------------------------------------------------------------
-- Mark next: the snippet steps the mark on each release (the action's /click) before the macro runs.

local MARK_SNIPPET = [[
	if down then return end
	local i = self:GetAttribute("fct-next") or 1
	self:SetAttribute("macrotext", "/tm " .. (9 - i))
	self:SetAttribute("fct-next", i % 8 + 1)
]]
local markHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local mark = Gear.SecureButton("ForeverControllerTweaksMarkNext")
mark:SetAttribute("fct-next", 1)
mark:SetAttribute("macrotext", "/tm 8")
markHeader:WrapScript(mark, "OnClick", MARK_SNIPPET)

local function markFromSkull() if not InCombatLockdown() then mark:SetAttribute("fct-next", 1) end end
ns.On("PLAYER_REGEN_ENABLED", markFromSkull)
ns.On("GROUP_ROSTER_UPDATE", markFromSkull)

---------------------------------------------------------------------------------------------------------------------
-- Potions and grenades (in combat too: that is what they are for).
-- ponytail: told apart by English item and spell names ("Heal", "Mana", "Grenade"...); on another client language
-- nothing is found and the press does nothing.

local ITEM_CLASS, SUBCLASS = Enum and Enum.ItemClass or {}, Enum and Enum.ItemConsumableSubclass or {}
local CONSUMABLE, TRADE_GOODS = ITEM_CLASS.Consumable or 0, ITEM_CLASS.Tradegoods or 7
local POTION = SUBCLASS.Potion or 1
-- Where explosives are filed: the consumables' "Explosives and Devices" (Generic 0) and Device (14), and the old
-- trade goods' Explosives (2). A grenade also has a use spell, which the reagents that share a name lack.
local EXPLOSIVE = { [CONSUMABLE] = { [SUBCLASS.Generic or 0] = true, [SUBCLASS.Device or 14] = true }, [TRADE_GOODS] = { [2] = true } }

local function potionOf(word) return function(item) return item.classID == CONSUMABLE and item.subClassID == POTION and (item.spell:find(word) or item.name:find(word)) ~= nil end end
function Tweaks.Explosive(item)
	local filed = EXPLOSIVE[item.classID]
	if not (filed and filed[item.subClassID] and item.spell ~= "") then return false end
	for _, word in ipairs({ "Grenade", "Bomb", "Dynamite", "Explosive" }) do
		if item.name:find(word) then return true end
	end
	return false
end
local KINDS = { heal = potionOf("Heal"), mana = potionOf("Mana"), grenade = Tweaks.Explosive }
for kind, fits in pairs(KINDS) do Gear.KINDS[kind] = fits end
local items = {
	heal = Gear.SecureButton("ForeverControllerTweaksHealPotion"),
	mana = Gear.SecureButton("ForeverControllerTweaksManaPotion"),
	grenade = Gear.SecureButton("ForeverControllerTweaksGrenade"),
}
Tweaks.ItemButtons = items

function Tweaks.RefreshItems(best)
	for kind, button in pairs(items) do Gear.SetText(button, best[kind] and "/use item:" .. best[kind].id or "") end
end
Gear.ON_BEST[#Gear.ON_BEST + 1] = function(best) Tweaks.RefreshItems(best) end

---------------------------------------------------------------------------------------------------------------------
-- Minimap zoom: in step by step, then out, then in again. The direction turns at the ends (read out of combat).

local zoom = CreateFrame("Button", "ForeverControllerTweaksMinimapZoom", UIParent, "SecureActionButtonTemplate")
zoom:SetAttribute("type", "click")
zoom:SetAttribute("useOnKeyDown", false)
zoom:RegisterForClicks("AnyUp", "AnyDown")
local zoomingIn = true

zoom:SetScript("PreClick", function(self, _, down)
	if down or InCombatLockdown() or not (Minimap and Minimap.ZoomIn and Minimap.ZoomOut) then return end
	local level, levels = call(Minimap.GetZoom, Minimap), call(Minimap.GetZoomLevels, Minimap)
	if level and levels then
		if level >= levels - 1 then zoomingIn = false elseif level <= 0 then zoomingIn = true end
	end
	self:SetAttribute("clickbutton", zoomingIn and Minimap.ZoomIn or Minimap.ZoomOut)
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	if not InCombatLockdown() and Minimap and Minimap.ZoomIn and not zoom:GetAttribute("clickbutton") then zoom:SetAttribute("clickbutton", Minimap.ZoomIn) end
end)
