-- The Settings tab (Panel/SettingsTab.lua) and the new-controller question on the panel stub, the core's TOC files
-- loaded as the game loads them: lua tests/settings_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local W = dofile(here .. "/panel_stub.lua")
local function pad(name, vendor, product)
	local raw = { name = name, vendorID = vendor, productID = product, rawButtons = {}, rawAxes = {} }
	for i = 0, 20 do raw.rawButtons[i] = false end
	for i = 0, 9 do raw.rawAxes[i] = 0 end
	return raw
end
local DS, XB = "054c/0ce6", "045e/0b13"
W.raw = pad("DualSense Wireless Controller", 0x054c, 0x0ce6)
Settings = setmetatable({}, { __index = function() return function() return {}, { AddInitializer = function() end } end end })
function SecureHandlerSetFrameRef(frame, label, ref) frame:SetAttribute("frameref-" .. label, ref) end
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
ChatFontNormal = "ChatFontNormal"
W.server = 1795200000
function GetServerTime() return W.server end
function GetMacroBody(i) return W.macros[i] and W.macros[i].body end
function EditMacro(i, name, icon, body)
	local m = W.macros[i]
	m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
end
-- The codec: a checksum (Zlib's Adler-32) and hex for Base64.
local function sum(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
	return h
end
C_EncodingUtil = {
	CompressString = function(s) return "Z" .. sum(s) .. ":" .. s end,
	DecompressString = function(s)
		local check, body = s:match("^Z(%d+):(.*)$")
		assert(check and tonumber(check) == sum(body), "adler")
		return body
	end,
	EncodeBase64 = function(s) return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end)) end,
	DecodeBase64 = function(s) return (s:gsub("..", function(h) return string.char(tonumber(h, 16)) end)) end,
}
Enum.CompressionMethod, Enum.CompressionLevel = { Zlib = 1 }, { OptimizeForSize = 2 }

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

-- A 1.5.0 store: the DualSense with a split layout and Ann's bindings on it.
ForeverControllerTweaksDB = {
	version = 2,
	devices = { [DS] = { raw = {}, roles = { L2 = "leftmod", L1 = "rightmod", R1 = "friendly", R2 = "hostile" }, face = {}, confirmed = true } },
	sync = { pads = { [DS] = "DualSense Wireless Controller" } },
	chars = { ["Ann-Realm"] = { cells = { [DS] = { FB = { R = { id = "spell:133", name = "Fireball", icon = 1, kind = "spell" } } } } } },
}
local ns = {}
for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
	if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
end
W.fire("ADDON_LOADED", "ForeverControllerTweaks")
W.fire("PLAYER_LOGIN")
W.fire("PLAYER_ENTERING_WORLD")
W.fire("UPDATE_MACROS")
W.advance(6)
local UI, L, P, db = ns.UI, ns.UI.L, ns.Profile, ns.db
local ST = UI.SettingsTab.T
UI.CloseAll()

-- Migrated: no change for an existing player, no question.
check(db.profiles[DS].name == "DualSense Wireless Controller" and db.profiles[DS].roles.L1 == "rightmod" and db.devices[DS].roles == nil, "the DualSense became its own profile")
check(not P.Pending() and not UI.DialogShown() and UI.Current() == nil, "an existing controller: no question")

-- The tab: the last side tab, four sections, the profile rows first.
check(UI.TABS[#UI.TABS].settings and UI.TABS[#UI.TABS][2] == "Settings", "Settings is the last side tab")
UI.SettingsTab.Open()
local w = UI.Current()
check(w and w == UI.SettingsTab.Window() and w.tabs.index == #UI.TABS, "the tab opens as its own side tab")
local function texts(parent)
	local out = {}
	for _, fs in ipairs(parent.strings or {}) do if type(fs.text) == "string" and fs.text ~= "" then out[fs.text] = true end end
	return out
end
local headers = {}
for _, f in ipairs(W.frames) do if f.parent == w and f.text and type(f.text) == "table" and f.text.text then headers[f.text.text] = true end end
check(headers[ST.PROFILE] and headers[ST.CONTROLLERS] and headers[ST.SYNC] and headers[ST.BACKUP], "four section headers")
local function node(title)
	for _, n in ipairs(w.nodes) do
		local tip = n.tip
		if tip and tip.title == title then return n end
	end
end
check(w.focus == node(ST.THIS) and w.focus.region.control.text.text == "DualSense Wireless Controller", "opens on This controller, its profile shown")
for _, title in ipairs({ ST.NAME, ST.NEW, ST.COPY, ST.DELETE, L.SYNC_ON, L.SYNC_NOW, L.SYNC_EXPORT, L.SYNC_IMPORT }) do check(node(title), "a row for " .. title) end
local shown = texts(w)
check(shown["DualSense Wireless Controller"] and shown["Profile: DualSense Wireless Controller · this controller"], "the controllers list: name and profile")
local function footer()
	local out = {}
	for _, prompt in ipairs(w.footer.prompts) do if prompt:IsShown() then out[prompt.key] = prompt.label.text end end
	return out
end
local prompts = footer()
check(prompts.PAD1 == L.SELECT and prompts.PAD4 == L.MORE and prompts.PAD2 == L.CLOSE and prompts.PADLSHOULDER == UI.TABS[#UI.TABS - 1].prompt, "footer: Select, More, the tab before, Close")

-- Sync between machines: the switch here, this computer only.
local syncNode = node(L.SYNC_ON)
w:Focus(syncNode)
w:Select()
check(db.sync.on == false and not syncNode.region.control.check.shown, "A turns sync off on this computer")
check(not ns.Sync.Encode(ns.Sync.Sections(db).tweaks or {}):find("sync"), "not a tweak")
w:Select()
check(db.sync.on == nil, "A turns it on again")
ns.Sync.SetOn(false)
W.advance(0.2)
check(not node(L.SYNC_ON).region.control.check.shown, "turned off elsewhere: the row redraws")
ns.Sync.SetOn(true)
W.advance(0.2)

-- New: an empty profile for this controller, used at once; the stepper steps between profiles.
node(ST.NEW).select()
W.advance(0.2)
local newId = P.CurrentId()
check(newId ~= DS and db.profiles[newId].name == ST.NEW_NAME and not next(db.profiles[newId].roles) and db.deviceProfile[DS].id == newId, "New: an empty profile, this controller on it")
check(ns.Layout.Roles().L1 ~= "rightmod", "and its layout is the game's")
w:Focus(node(ST.THIS))
w:Pad("PADDLEFT")
W.advance(0.2)
check(P.CurrentId() == DS and ns.Layout.Roles().L1 == "rightmod", "the stepper switches back, the layout follows")
w:Pad("PADDLEFT")
W.advance(0.2)
check(P.CurrentId() == DS and w.focus == node(ST.THIS), "past the first: nothing changes, the focus stays")

-- Rename: the name box, Enter keeps it; Copy copies every character's bindings.
local box
for _, f in ipairs(W.frames) do if f.scripts.OnEnterPressed and f.scripts.OnEditFocusLost and f.parent == node(ST.NAME).region then box = f end end
check(box and not box:GetAttribute("ForeverControllerTweaksNoKeyboard"), "the name box takes the on-screen keyboard")
box:SetText("Couch pad")
box.scripts.OnEditFocusLost(box)
check(db.profiles[DS].name == "Couch pad", "a typed name is kept")
node(ST.COPY).select()
W.advance(0.2)
local copyId = P.CurrentId()
check(copyId ~= DS and db.profiles[copyId].name == "Couch pad 2" and db.chars["Ann-Realm"].cells[copyId].FB.R.id == "spell:133" and db.profiles[copyId].roles.L1 == "rightmod", "Copy: this profile's layout and bindings, a unique name")

-- Delete asks first, then moves this controller to the first profile left.
node(ST.DELETE).select()
check(UI.DialogShown(), "Delete asks first")
UI.Dialog():OnPad("PAD2")
check(not UI.DialogShown() and P.Get(copyId), "Cancel keeps it")
node(ST.DELETE).select()
UI.Dialog():OnPad("PAD1")
W.advance(0.2)
check(db.profiles[copyId].gone and db.chars["Ann-Realm"].cells[copyId] == nil and P.CurrentId() == P.List()[1].id, "Delete: gone, bindings gone, this controller on the first left")
P.Use(DS)
W.advance(0.2)
P.Delete(newId)
W.advance(0.2)
local last = node(ST.DELETE)
last.select()
check(#P.List() == 1 and last.tip.lines[1] == ST.DELETE_LAST and not UI.DialogShown(), "the last profile: Delete is off and says why")
UI.CloseAll()

-- A second controller: the question, after the delay, over the Settings tab; it plays on the last profile meanwhile.
P.New("Arcade")
W.raw = pad("Xbox Wireless Controller", 0x045e, 0x0b13)
ns.Device.Refresh(true)
check(P.Pending() and P.CurrentId() == DS and db.deviceProfile[XB] == nil, "new controller: on the last profile, nothing written")
W.advance(1)
check(not UI.DialogShown(), "not at once: the setup guide and What's new come first")
W.advance(4)
local dialog = UI.Dialog()
check(UI.DialogShown() and UI.Current() == UI.SettingsTab.Window() and dialog.Text.text == ST.ASK:format("Xbox Wireless Controller"), "the question, over the Settings tab")
check(dialog.Button1.text == ST.ASK_USE:format("Couch pad") and dialog.Button2.text == ST.ASK_COPY:format("Couch pad") and dialog.Button3.text == ST.ASK_NEW and dialog.Button3:IsShown(), "Use, Copy… and New empty, on the last profile used")
check(dialog.Stepper:IsShown() and dialog.Stepper.text.text == "Couch pad", "two profiles: a stepper")
UI.Current().ClosePanelButton.scripts.OnClick()
check(UI.DialogShown(), "the X waits for an answer")
dialog:OnPad("PADDUP")
dialog:OnPad("PADDLEFT")
check(dialog.Stepper.text.text == "Arcade" and dialog.Button1.text == ST.ASK_USE:format("Arcade"), "the stepper picks what Use and Copy act on")
dialog:OnPad("PADDDOWN")
dialog:OnPad("PAD2")
W.advance(0.2)
local arcade
for _, item in ipairs(P.List()) do if item.name == "Arcade" then arcade = item.id end end
check(not UI.DialogShown() and db.deviceProfile[XB].id == arcade and P.CurrentId() == arcade and not P.Pending(), "B answers Use")
check(db.deviceProfile[DS].id == DS, "the other controller keeps its own")

-- Copy from the question: a new profile named after the controller, every character's bindings with it.
UI.CloseAll()
W.raw = pad("8BitDo Pro 2", 0x2dc8, 0x6003)
ns.Device.Refresh(true)
W.advance(5)
dialog:OnPad("PADDUP")
dialog:OnPad("PADDRIGHT")
dialog:OnPad("PADDDOWN")
dialog:OnPad("PADDRIGHT")
dialog:OnPad("PAD1")
W.advance(0.2)
local copied = P.Get(P.CurrentId())
check(copied and copied.name == "8BitDo Pro 2" and db.chars["Ann-Realm"].cells[P.CurrentId()].FB.R.id == "spell:133" and db.deviceProfile["2dc8/6003"], "Copy…: a copy named after the controller, with the bindings")

-- In a fight or a loading screen the question waits until it ends.
UI.CloseAll()
W.raw = pad("Steam Virtual Gamepad", 0x28de, 0x11ff)
W.combat = true
ns.Device.Refresh(true)
W.advance(5)
check(not UI.DialogShown(), "no question in combat")
W.combat = false
W.fire("LOADING_SCREEN_ENABLED")
W.fire("PLAYER_REGEN_ENABLED")
W.advance(5)
check(not UI.DialogShown(), "never over a loading screen")
W.fire("LOADING_SCREEN_DISABLED")
W.advance(5)
check(UI.DialogShown(), "after the fight and the loading screen it asks")
dialog:OnPad("PADDRIGHT")
dialog:OnPad("PADDRIGHT")
dialog:OnPad("PAD1")
W.advance(0.2)
local fresh = P.Get(P.CurrentId())
check(fresh and fresh.name == "Steam Virtual Gamepad" and not next(fresh.roles) and db.chars["Ann-Realm"].cells[P.CurrentId()] == nil, "New empty: the game's layout, no bindings")
UI.CloseAll()

io.stdout:write(("settings_spec: %d checks passed\n"):format(checks))
