-- The Settings tab (Panel/SettingsTab.lua) on the panel stub, profiles per character (no controller question), the core's TOC files
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
	chars = { ["Player-0-Ann"] = { cells = { [DS] = { FB = { R = { id = "spell:133", name = "Fireball", icon = 1, kind = "spell" } } } } } },
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

-- Migrated: no change for an existing player, no question; the profile is the character's.
local ann = db.chars["Player-0-Ann"]
check(ann.profiles[DS].name == "DualSense Wireless Controller" and ann.profiles[DS].roles.L1 == "rightmod" and ann.profile == DS and db.devices[DS].roles == nil, "the DualSense profile became Ann's")
check(db.profiles == nil and db.deviceProfile == nil and not UI.DialogShown() and UI.Current() == nil, "no account profiles, no question")

-- The tab: the last side tab, three sections, the profile rows first.
check(UI.TABS[#UI.TABS].settings and UI.TABS[#UI.TABS][2] == "Settings", "Settings is the last side tab")
UI.SettingsTab.Open()
local w = UI.Current()
check(w and w == UI.SettingsTab.Window() and w.tabs.index == #UI.TABS, "the tab opens as its own side tab")
local function texts(parent)
	local out = {}
	for _, fs in ipairs(parent.strings or {}) do if type(fs.text) == "string" and fs.text ~= "" then out[fs.text] = true end end
	return out
end
local headers, count = {}, 0
for _, f in ipairs(W.frames) do
	if f.parent == w and f.text and type(f.text) == "table" and f.text.text then
		headers[f.text.text] = true
		count = count + 1
	end
end
check(headers[ST.PROFILE] and headers[ST.SYNC] and headers[ST.BACKUP] and count == 3 and ST.CONTROLLERS == nil, "three section headers, no Controllers")
local function node(title)
	for _, n in ipairs(w.nodes) do
		local tip = n.tip
		if tip and tip.title == title then return n end
	end
end
check(w.focus == node(ST.THIS) and w.focus.region.control.text.text == "DualSense Wireless Controller", "opens on This character, its profile shown")
for _, title in ipairs({ ST.NAME, ST.NEW, ST.COPY, ST.DELETE, L.SYNC_ON, L.SYNC_NOW, L.SYNC_EXPORT, L.SYNC_IMPORT }) do check(node(title), "a row for " .. title) end
local shown = texts(w)
for text in pairs(shown) do check(not text:find("this controller"), "no controller picks: " .. text) end
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

-- New: an empty profile for this character, used at once; the stepper steps between profiles.
node(ST.NEW).select()
W.advance(0.2)
local newId = P.CurrentId()
check(newId ~= DS and ann.profiles[newId].name == ST.NEW_NAME and not next(ann.profiles[newId].roles) and ann.profile == newId, "New: an empty profile, this character on it")
check(ns.Layout.Roles().L1 ~= "rightmod", "and its layout is the game's")
w:Focus(node(ST.THIS))
w:Pad("PADDLEFT")
W.advance(0.2)
check(P.CurrentId() == DS and ns.Layout.Roles().L1 == "rightmod", "the stepper switches back, the layout follows")
w:Pad("PADDLEFT")
W.advance(0.2)
check(P.CurrentId() == DS and w.focus == node(ST.THIS), "past the first: nothing changes, the focus stays")

-- Rename: the name box, Enter keeps it; Copy copies this character's bindings.
local box
for _, f in ipairs(W.frames) do if f.scripts.OnEnterPressed and f.scripts.OnEditFocusLost and f.parent == node(ST.NAME).region then box = f end end
check(box and not box:GetAttribute("ForeverControllerTweaksNoKeyboard"), "the name box takes the on-screen keyboard")
box:SetText("Couch pad")
box.scripts.OnEditFocusLost(box)
check(ann.profiles[DS].name == "Couch pad", "a typed name is kept")
node(ST.COPY).select()
W.advance(0.2)
local copyId = P.CurrentId()
check(copyId ~= DS and ann.profiles[copyId].name == "Couch pad 2" and ann.cells[copyId].FB.R.id == "spell:133" and ann.profiles[copyId].roles.L1 == "rightmod", "Copy: this profile's layout and bindings, a unique name")

-- Another controller id: no question, the same profile and bindings.
W.raw = pad("Xbox Wireless Controller", 0x045e, 0x0b13)
ns.Device.Refresh(true)
W.advance(6)
check(not UI.DialogShown() and P.CurrentId() == copyId and ns.Layout.Roles().L1 == "rightmod" and ns.Face.CellEntry("FB", "R").id == "spell:133", "a new pad id: no question, nothing changes")
W.raw = pad("DualSense Wireless Controller", 0x054c, 0x0ce6)
ns.Device.Refresh(true)
W.advance(0.2)

-- Delete asks first, then moves this character to the first profile left.
node(ST.DELETE).select()
check(UI.DialogShown(), "Delete asks first")
UI.Dialog():OnPad("PAD2")
check(not UI.DialogShown() and P.Get(copyId), "Cancel keeps it")
node(ST.DELETE).select()
UI.Dialog():OnPad("PAD1")
W.advance(0.2)
check(ann.profiles[copyId] == nil and ann.cells[copyId] == nil and P.CurrentId() == P.List()[1].id, "Delete: gone, bindings gone, this character on the first left")
P.Use(DS)
W.advance(0.2)
P.Delete(newId)
W.advance(0.2)
local last = node(ST.DELETE)
last.select()
check(#P.List() == 1 and last.tip.lines[1] == ST.DELETE_LAST and not UI.DialogShown(), "the last profile: Delete is off and says why")
UI.CloseAll()

-- Another character sees its own profiles only: a Default from the last layout, none of Ann's.
local realGUID = UnitGUID
function UnitGUID(unit) if unit == "player" then return "Player-0-Bob" end end
P.Ensure()
UI.SettingsTab.Open()
w = UI.Current()
w:Refresh()
check(#P.List() == 1 and P.Current().name == "Default" and node(ST.THIS).region.control.text.text == "Default", "Bob: his Default only")
check(db.chars["Player-0-Bob"].cells == nil and ann.profiles[DS].name == "Couch pad", "Bob: no bindings; Ann's profile untouched")
UI.CloseAll()
UnitGUID = realGUID

io.stdout:write(("settings_spec: %d checks passed\n"):format(checks))
