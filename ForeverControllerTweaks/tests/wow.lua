-- Shared WoW stubs for the engine specs (Core, Device, Layout, Remap). Not a spec itself.
-- local W = dofile(here .. "/wow.lua")(here .. "/..", { db = ..., configs = ... })
return function(dir, opts)
	opts = opts or {}
	local W = { now = 100, combat = false, padFree = true, active = true, lines = {}, frames = {}, tickers = {}, calls = { set = 0, delete = 0, apply = 0 } }
	W.configs = opts.configs or {}

	local function copy(v)
		if type(v) ~= "table" then return v end
		local o = {}
		for k, x in pairs(v) do o[k] = copy(x) end
		return o
	end
	W.copy = copy

	function W.same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then return a == b end
		for k, v in pairs(a) do if not W.same(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end

	local function idKey(id) return string.format("%04x/%04x", id.vendorID, id.productID) end

	-- One pad by default: the DualSense, with 1-based raw tables.
	local function newPad(name, vendorID, productID, base)
		local buttons, axes = {}, {}
		base = base or 1
		for i = base, base + 21 do buttons[i] = false end
		for i = base, base + 9 do axes[i] = 0 end
		return { name = name, vendorID = vendorID, productID = productID, rawButtons = buttons, rawAxes = axes, labelStyle = "Shapes" }
	end
	W.newPad = newPad
	W.pads = opts.pads or { [1] = newPad("DualSense", 0x054c, 0x0ce6) }

	function print(msg) W.lines[#W.lines + 1] = tostring(msg) end
	function date() return "12:00:00 " end
	function GetTime() return W.now end
	function InCombatLockdown() return W.combat end
	function GetCVar() return nil end
	function GetCVarBool() return false end
	function GetBuildInfo() return "1.60.1", "12345", "", 16001 end
	function GetNumMacros() return 3, 1 end
	C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 145 end }
	SlashCmdList = {}
	Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
	InputUtil = { IsGamepadUIEnabled = function() return W.active end }
	GamepadSharedUtility = { InputBindingManager = { IsOnlyCoreBindingSetActive = function() return W.padFree end } }

	function CreateFrame()
		local f = { events = {}, scripts = {}, shown = true }
		function f:RegisterEvent(e) self.events[e] = true end
		function f:SetScript(name, fn) self.scripts[name] = fn end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		W.frames[#W.frames + 1] = f
		return f
	end
	C_Timer = { NewTicker = function(_, fn)
		local t = { fn = fn }
		function t:Cancel() self.cancelled = true end
		W.tickers[#W.tickers + 1] = t
		return t
	end }

	C_GamePad = {
		GetActiveDeviceID = function() return 1 end,
		GetAllDeviceIDs = function()
			local ids = {}
			for id in pairs(W.pads) do ids[#ids + 1] = id end
			table.sort(ids)
			return ids
		end,
		GetDeviceRawState = function(id)
			local pad = W.pads[id]
			return pad and copy(pad)
		end,
		GetDeviceMappedState = function(id)
			local pad = W.pads[id]
			return pad and { labelStyle = pad.labelStyle }
		end,
		GetConfig = function(id) return copy(W.configs[idKey(id)]) end,
		SetConfig = function(c)
			W.calls.set = W.calls.set + 1
			W.configs[idKey(c.configID)] = copy(c)
		end,
		DeleteConfig = function(id)
			W.calls.delete = W.calls.delete + 1
			W.configs[idKey(id)] = nil
		end,
		ApplyConfigs = function()
			assert(not W.combat, "ApplyConfigs in combat")
			W.calls.apply = W.calls.apply + 1
		end,
		GetAllConfigIDs = function()
			local ids = {}
			for _, c in pairs(W.configs) do ids[#ids + 1] = copy(c.configID) end
			return ids
		end,
	}

	ForeverControllerTweaksDB = opts.db
	W.ns = {}
	for _, file in ipairs(opts.files or { "Core.lua", "Device.lua", "Layout.lua", "Remap.lua" }) do
		assert(loadfile(dir .. "/" .. file))("ForeverControllerTweaks", W.ns)
	end

	function W.fire(event, ...)
		for _, f in ipairs(W.frames) do
			if f.events[event] then f.scripts.OnEvent(f, event, ...) end
		end
	end

	-- Advances the clock in 1/30 s frames, running OnUpdate scripts and every live ticker each frame.
	function W.run(seconds)
		for _ = 1, math.max(1, math.floor((seconds or 0.2) * 30)) do
			W.now = W.now + 1 / 30
			for _, f in ipairs(W.frames) do
				if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1 / 30) end
			end
			for _, t in ipairs(W.tickers) do if not t.cancelled then t.fn() end end
		end
	end

	function W.liveTickers()
		local n = 0
		for _, t in ipairs(W.tickers) do if not t.cancelled then n = n + 1 end end
		return n
	end

	function W.login()
		W.fire("ADDON_LOADED", "ForeverControllerTweaks")
		W.fire("PLAYER_LOGIN")
		W.fire("PLAYER_ENTERING_WORLD")
		W.run()
	end

	function W.slash(msg) SlashCmdList.FOREVERCONTROLLERTWEAKS(msg) end

	function W.said(pattern)
		for _, line in ipairs(W.lines) do if line:find(pattern) then return true end end
		return false
	end

	function W.count(pattern)
		local n = 0
		for _, line in ipairs(W.lines) do if line:find(pattern) then n = n + 1 end end
		return n
	end

	return W
end
