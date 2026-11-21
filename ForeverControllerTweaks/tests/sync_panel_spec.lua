-- The Export and Import windows and the first-sync dialog on the panel stub (design/sync.md 6), the
-- core's TOC files loaded as the game loads them: lua tests/sync_panel_spec.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local dir = here .. "/.."

local W = dofile(here .. "/panel_stub.lua")
local raw = { name = "DualSense Wireless Controller", vendorID = 0x054c, productID = 0x0ce6, rawButtons = {}, rawAxes = {} }
for i = 0, 20 do raw.rawButtons[i] = false end
for i = 0, 9 do raw.rawAxes[i] = 0 end
W.raw = raw
Settings = setmetatable({}, { __index = function() return function() return {}, { AddInitializer = function() end } end end })
function SecureHandlerSetFrameRef(frame, label, ref) frame:SetAttribute("frameref-" .. label, ref) end
GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
ChatFontNormal = "ChatFontNormal"

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
	DecodeBase64 = function(s)
		assert(#s % 2 == 0 and not s:find("[^0-9A-F]"), "base64")
		return (s:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
	end,
}
Enum.CompressionMethod, Enum.CompressionLevel = { Zlib = 1 }, { OptimizeForSize = 2 }
W.server = 1795200000
function GetServerTime() return W.server end
function GetMacroBody(i) return W.macros[i] and W.macros[i].body end
function EditMacro(i, name, icon, body)
	local m = W.macros[i]
	m.name, m.icon, m.body = name or m.name, icon or m.icon, body or m.body
end

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then error("FAIL: " .. msg, 2) end
end

-- Another machine's settings already on the server: a first sync for this one, which has its own bindings.
-- Each boot is a fresh machine: the earlier one's frames and timers go (its events and writes would still run).
local function boot(db)
	W.frames, W.timers, W.log = {}, {}, {}
	ForeverControllerTweaksDB = db
	local ns = {}
	for line in io.lines(dir .. "/ForeverControllerTweaks.toc") do
		if line:match("%.lua$") and not line:match("Glyphs%.lua") then assert(loadfile(dir .. "/" .. line))("ForeverControllerTweaks", ns) end
	end
	W.fire("ADDON_LOADED", "ForeverControllerTweaks")
	W.fire("PLAYER_LOGIN")
	W.fire("PLAYER_ENTERING_WORLD")
	W.fire("UPDATE_MACROS")
	W.advance(6)
	return ns
end

local ns = boot({
	version = 2,
	tweaks = { sellJunk = true },
	chars = { ["Player-0-Ann"] = { cells = { ["054c/0ce6"] = { FB = { R = { id = "spell:133", name = "Fireball", icon = 1, kind = "spell" } } } } } },
})
local UI, L, Sync = ns.UI, ns.UI.L, ns.Sync
UI.CloseAll()

local function errors()
	local out = {}
	for _, line in ipairs(W.log) do
		if line:find("error") or line:find("failed") or line:find("blocked") then out[#out + 1] = line end
	end
	return table.concat(out, " | ")
end
check(errors() == "", "no errors while loading: " .. errors())
local syncMacros = 0
for _, m in ipairs(W.macros) do if m.name:find("^FCT:Sync %d+$") then syncMacros = syncMacros + 1 end end
check(syncMacros >= 1, "the first machine wrote its sync macros")

local function pickerRows()
	local out = {}
	for _, f in ipairs(W.frames) do
		if f.tick and f.name and f:IsVisible() and f.index then out[f.index] = f.name.text end
	end
	return out
end
local function indexOf(list, value)
	for i, v in ipairs(list) do if v == value then return i end end
end

-- More has no Sync & backup any more: its switch, status, Sync now, Undo, Export and Import are the Settings tab's.
UI.Bindings.Open()
UI.OpenMore(UI.Current())
local more = pickerRows()
check(indexOf(more, L.LEARN) and not indexOf(more, "Sync & backup"), "More: no Sync & backup")
UI.ActionPicker.Close()
UI.CloseAll()

-- Export: the text, selected, starts FCT4:.
UI.Sync.OpenExport()
local export = UI.Current()
check(export and export.NineSlice.Text.text == L.EXPORT_TITLE, "Export opens")
local text
for _, f in ipairs(W.frames) do
	if f.parent and type(f.text) == "string" and f.text:find("^FCT4:") then text = f.text end
end
check(text and #text > 10, "the export text is in the box")
check(not text:find("Ann"), "no character name in the export")
-- No Print to chat: chat lines can't be selected, so the selected box is the only copy path.
check(#export.nodes == 2, "Export offers Select all and Close only: " .. #export.nodes)
UI.CloseAll()

-- Import on another machine: paste, preview, Import, the confirm, applied, Undo offered.
W.macros = {}
local other = boot({ version = 2, tweaks = { sellJunk = false }, devices = { ["054c/0ce6"] = { raw = {}, roles = {}, face = {} } } })
UI, L, Sync = other.UI, other.UI.L, other.Sync
UI.CloseAll()
UI.Sync.OpenImport()
local import = UI.Current()
check(import and import.NineSlice.Text.text == L.IMPORT_TITLE, "Import opens")
local box
for _, f in ipairs(W.frames) do
	if f.parent and f.scripts.OnTextChanged and f:GetAttribute("ForeverControllerTweaksNoKeyboard") and f.parent.parent == import then box = f end
end
check(box, "the import box skips the on-screen keyboard")
box:SetText("hello")
box.scripts.OnTextChanged(box, true)
W.advance(0.3)
check(#import.nodes == 3, "a bad paste previews nothing: the box, Import and Cancel only")
box:SetText(text)
box.scripts.OnTextChanged(box, true)
W.advance(0.3)
local rows = {}
for _, node in ipairs(import.nodes) do if node.region.label and node.region:IsVisible() then rows[#rows + 1] = node.region.label.text end end
check(indexOf(rows, L.SEC.bindings) and indexOf(rows, L.SEC.tweaks), "the preview lists the parts: " .. table.concat(rows, ", "))
local go
for _, node in ipairs(import.nodes) do if node.region.GetText and node.region:GetText() == L.IMPORT_GO then go = node end end
go.select()
check(UI.DialogShown(), "Import asks first")
UI.Dialog():OnPad("PAD1")
W.advance(0.5)
check(other.db.tweaks.sellJunk == true and other.db.chars["Player-0-Ann"].cells[other.Profile.CurrentId()].FB.R.id == "spell:133", "the import applied")
local name = other.db.chars["Player-0-Ann"].cells[other.Profile.CurrentId()].FB.R.name
check(name and name ~= "spell:133", "names come back from the game: " .. tostring(name))
local after = UI.Current()
local undoShown = false
for _, node in ipairs(after and after.nodes or {}) do undoShown = undoShown or node.region.GetText and node.region:GetText():find("^Undo last sync") ~= nil end
check(after and after == UI.SettingsTab.Window() and undoShown, "back in the Settings tab, with Undo last sync")
UI.CloseAll()
-- The import goes out with the next write, 30 s after the login one.
W.advance(31)

-- The first sync on a machine with its own settings: the dialog over the Settings tab; B asks again; a choice applies.
local own = boot({ version = 2, tweaks = { sellJunk = false, lightBar = "game" }, chars = { ["Player-0-Ann"] = { cells = { ["054c/0ce6"] = { FT = { T = { id = "spell:9", name = "Nine", icon = 2, kind = "spell" } } } } } } })
UI, L, Sync = own.UI, own.UI.L, own.Sync
W.advance(3)
check(Sync.Choice() ~= nil, "the first sync waits for a choice")
check(UI.DialogShown() and UI.Current() and UI.Current() == UI.SettingsTab.Window(), "the dialog opens over the Settings tab")
UI.Current().ClosePanelButton.scripts.OnClick()
check(UI.DialogShown(), "the X waits while the question is up")
UI.Dialog():OnPad("PAD2")
W.advance(0.1)
check(UI.DialogShown() and Sync.Choice(), "B asks again")
UI.Dialog():OnPad("PAD1")
W.advance(0.5)
check(not Sync.Choice() and own.db.chars["Player-0-Ann"].cells[own.Profile.CurrentId()].FB and own.db.sync.backup.s["cp:Player-0-Ann"], "Use synced applied, the old copy backed up")
check(errors() == "", "no errors: " .. errors())

io.stdout:write(("sync_panel_spec: %d checks passed\n"):format(checks))
