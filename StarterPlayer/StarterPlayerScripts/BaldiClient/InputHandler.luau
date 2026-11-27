--[[
	InputHandler (ModuleScript, StarterPlayerScripts.BaldiClient.InputHandler)
	Routes raw input to gameplay callbacks so the other controllers never
	talk to UserInputService directly. The keys themselves are REBINDABLE
	(Options page) and persist via the server profile:

	  USE    (default E)         use slot 1 / minigame press
	  SWAP   (default Q)         swap slots / minigame press
	  SPRINT (default LeftShift) hold to sprint
	  CANCEL (default F)         give up the notebook minigame

	USE and SWAP also report held-state (onUseHeld / onSwapHeld) for the
	minigames. Mobile equivalents are on-screen buttons created by
	HudController / the minigame UIs; they call the same notify* functions.

	Gamepads use fixed buttons (GAMEPAD): X = USE, Y = SWAP, L2 or L3 =
	SPRINT, B = CANCEL. While the last input was a gamepad, getKeyName
	returns those button names, so on-screen hints match the controller.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InputHandler = {}

local DEFAULT_BINDS = { USE = "E", SWAP = "Q", SPRINT = "LeftShift", CANCEL = "F" }

-- gamepad buttons per action, and how hints name them
local GAMEPAD = {
	[Enum.KeyCode.ButtonX] = "USE",
	[Enum.KeyCode.ButtonY] = "SWAP",
	[Enum.KeyCode.ButtonL2] = "SPRINT",
	[Enum.KeyCode.ButtonL3] = "SPRINT",
	[Enum.KeyCode.ButtonB] = "CANCEL",
}
local GAMEPAD_LABELS = { USE = "X", SWAP = "Y", SPRINT = "L2", CANCEL = "B" }

local function isGamepad(inputType)
	return inputType.Name:find("Gamepad") ~= nil
end

function InputHandler.init(ctx)
	local self = {
		touchEnabled = UserInputService.TouchEnabled,
	}
	local binds = {}
	for action, keyName in pairs(DEFAULT_BINDS) do
		binds[action] = keyName
	end

	local sprintCallbacks = {}
	local useCallbacks = {}
	local swapCallbacks = {}
	local useHeldCallbacks = {}
	local swapHeldCallbacks = {}
	local cancelCallbacks = {}
	local bindsChangedCallbacks = {}

	local function fire(callbacks, ...)
		for _, callback in ipairs(callbacks) do
			callback(...)
		end
	end

	-- ---------- keybinds ----------

	local function isValidKey(keyName)
		local ok = pcall(function()
			return Enum.KeyCode[keyName]
		end)
		return ok
	end

	function self.getBinds()
		local copy = {}
		for action, keyName in pairs(binds) do
			copy[action] = keyName
		end
		return copy
	end

	function self.getKeyName(action)
		if isGamepad(UserInputService:GetLastInputType()) and GAMEPAD_LABELS[action] then
			return GAMEPAD_LABELS[action]
		end
		return binds[action] or DEFAULT_BINDS[action]
	end

	-- Rebind one action. If the key is already used by another action the
	-- two actions swap keys, so binds can never silently collide.
	function self.setBind(action, keyName)
		if DEFAULT_BINDS[action] == nil or type(keyName) ~= "string" or not isValidKey(keyName) then
			return false
		end
		for otherAction, otherKey in pairs(binds) do
			if otherAction ~= action and otherKey == keyName then
				binds[otherAction] = binds[action]
			end
		end
		binds[action] = keyName
		fire(bindsChangedCallbacks, self.getBinds())
		return true
	end

	-- bulk-apply (profile load from the server)
	function self.applyBinds(map)
		if type(map) ~= "table" then
			return
		end
		for action in pairs(DEFAULT_BINDS) do
			local keyName = map[action]
			if type(keyName) == "string" and isValidKey(keyName) then
				binds[action] = keyName
			end
		end
		fire(bindsChangedCallbacks, self.getBinds())
	end

	function self.onBindsChanged(callback)
		table.insert(bindsChangedCallbacks, callback)
	end

	-- ---------- subscriptions ----------

	function self.onSprint(callback)
		table.insert(sprintCallbacks, callback)
	end

	function self.onUse(callback)
		table.insert(useCallbacks, callback)
	end

	function self.onSwap(callback)
		table.insert(swapCallbacks, callback)
	end

	-- held-state versions of USE / SWAP, fired (true) on press and (false)
	-- on release — minigames read these
	function self.onUseHeld(callback)
		table.insert(useHeldCallbacks, callback)
	end

	function self.onSwapHeld(callback)
		table.insert(swapHeldCallbacks, callback)
	end

	function self.onCancel(callback)
		table.insert(cancelCallbacks, callback)
	end

	-- mobile buttons (and anything else) report through these
	function self.notifySprint(held)
		fire(sprintCallbacks, held)
	end

	function self.notifyUse()
		fire(useCallbacks)
	end

	function self.notifySwap()
		fire(swapCallbacks)
	end

	function self.notifyUseHeld(held)
		fire(useHeldCallbacks, held)
	end

	function self.notifySwapHeld(held)
		fire(swapHeldCallbacks, held)
	end

	function self.notifyCancel()
		fire(cancelCallbacks)
	end

	-- ---------- raw input ----------

	local function matchesSprint(keyName)
		if keyName == binds.SPRINT then
			return true
		end
		-- with the default LeftShift bind, RightShift sprints too
		return binds.SPRINT == "LeftShift" and keyName == "RightShift"
	end

	-- gamepad: fixed buttons, same callbacks as the keys
	local function gamepadInput(input, began)
		local action = GAMEPAD[input.KeyCode]
		if action == "SPRINT" then
			self.notifySprint(began)
		elseif action == "USE" then
			if began then
				self.notifyUse()
			end
			self.notifyUseHeld(began)
		elseif action == "SWAP" then
			if began then
				self.notifySwap()
			end
			self.notifySwapHeld(began)
		elseif action == "CANCEL" and began then
			self.notifyCancel()
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and isGamepad(input.UserInputType) then
			gamepadInput(input, true)
			return
		end
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local keyName = input.KeyCode.Name
		if matchesSprint(keyName) then
			self.notifySprint(true)
		end
		if keyName == binds.USE then
			self.notifyUse()
			self.notifyUseHeld(true)
		elseif keyName == binds.SWAP then
			self.notifySwap()
			self.notifySwapHeld(true)
		elseif keyName == binds.CANCEL then
			self.notifyCancel()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isGamepad(input.UserInputType) then
			gamepadInput(input, false)
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local keyName = input.KeyCode.Name
		if matchesSprint(keyName) then
			self.notifySprint(false)
		end
		if keyName == binds.USE then
			self.notifyUseHeld(false)
		elseif keyName == binds.SWAP then
			self.notifySwapHeld(false)
		end
	end)

	-- ===================== mouse management =====================
	-- Any UI that needs a free cursor calls captureMouse(key); when it
	-- closes it calls releaseMouse(key). A RenderStepped loop enforces
	-- the free state every frame so the default camera scripts can't
	-- override it while a UI is open.

	local mouseOwners = {} -- set of string keys currently requesting a free mouse
	local enforceConn = nil

	local function startEnforcing()
		if enforceConn then return end
		enforceConn = RunService.RenderStepped:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	end

	local function stopEnforcing()
		if enforceConn then
			enforceConn:Disconnect()
			enforceConn = nil
		end
		UserInputService.MouseIconEnabled = false
	end

	-- Call this when opening any UI that needs mouse interaction.
	-- key should be a unique string identifying the caller (e.g. "MathMinigame").
	function self.captureMouse(key)
		mouseOwners[key] = true
		startEnforcing()
	end

	-- Call this when the UI closes. The mouse stays free until ALL callers
	-- have released it, so overlapping UIs don't accidentally re-lock early.
	function self.releaseMouse(key)
		mouseOwners[key] = nil
		if not next(mouseOwners) then
			stopEnforcing()
		end
	end

	-- true while some menu or minigame wants the cursor (gamepad selection uses it)
	function self.isCursorFree()
		return next(mouseOwners) ~= nil
	end

	-- ===================== proximity-prompt gate =====================
	-- ProximityPromptService.Enabled is a single GLOBAL flag, so when two
	-- systems each flip it on close they fight: e.g. a notebook minigame closing
	-- (on a Silver grab) would re-enable prompts while Silver still holds you at
	-- the notebook — pressing E to escape then re-triggers the notebook prompt
	-- (the "2 bars" + infinite-trap bug). Reference-count it like the mouse:
	-- prompts stay OFF until EVERY caller has released.

	local promptOwners = {} -- set of keys that currently want prompts off

	function self.disablePrompts(key)
		promptOwners[key] = true
		ProximityPromptService.Enabled = false
	end

	function self.enablePrompts(key)
		promptOwners[key] = nil
		if not next(promptOwners) then
			ProximityPromptService.Enabled = true
		end
	end

	return self
end

return InputHandler
