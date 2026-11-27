--[[
	ModifierMenuController (ModuleScript, StarterPlayerScripts.BaldiClient.ModifierMenuController)

	Drives the hand-built StarterGui.ModifiersGui: the panel where a player who
	has unlocked modifiers picks them before a Classic run. MenuController's
	requestStart opens it instead of starting straight away; its Start button
	hands the picked set back through the onStart callback. The GUI contract
	(every name looked up here) is MODIFIER_ASSETS.md section 1. This never
	builds or styles UI: it fills text, clones CardTemplate, and shows/hides
	each card's `Selected`.

	Public:
	  isUnlocked()             the server said this player may pick modifiers
	  isAvailable()            the panel GUI was found and has what it needs
	  open(modeId, onStart)    show the panel; Start calls onStart(selection).
	                           Returns false (and does nothing) if unavailable.
	  close()                  hide it without starting
	  isOpen()

	selection = { [id] = true } for each pick, and Randomizer = n (1..RANDOMIZER_MAX)
	when Randomizer is picked: the shape RequestStart and StatsData's
	modifierLoadout use. The server validates it, rolls Randomizer, saves it.

	init never yields: the GUI is looked up (at most 5s) in its own thread, and
	until it's found the panel simply counts as unavailable (a normal run).
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local ModifierConfig = require(shared:WaitForChild("ModifierConfig"))
local ModifierAssets = require(shared:WaitForChild("ModifierAssets"))

local ModifierMenuController = {}

local GUI_NAME = "ModifiersGui"
local GUI_WAIT = 5
local OPEN_SECONDS = 0.45
local CLOSE_SECONDS = 0.25
local HOLD_DELAY = 0.4 -- hold Minus/Plus this long and it starts repeating...
local HOLD_REPEAT = 0.07 -- ...one step every this many seconds

local warned = {}
local function warnOnce(path)
	if warned[path] then
		return
	end
	warned[path] = true
	warn("[Tmod] Modifier panel piece missing: " .. path .. " (see MODIFIER_ASSETS.md) — skipping that piece.")
end

local function isText(object)
	return object and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
end

local function setText(object, text)
	if isText(object) then
		object.Text = text
	end
end

local function usingGamepad()
	return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

function ModifierMenuController.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local self = {}

	local MAX = ModifierConfig.RANDOMIZER_MAX

	local unlocked = false
	local loadoutSeen = false
	local picked = {} -- [id] = true
	local randomCount = 1

	-- GUI (filled in by the lookup thread)
	local playerGui = nil
	local gui, panel, totalBonus = nil, nil, nil
	local cards = {} -- [id] = { selected, count }
	local firstToggle = nil
	local available = false

	local isOpen = false
	local openToken = 0
	local pendingStart = nil -- the onStart callback of the current open
	local previousSelection = nil -- GuiService.SelectedObject before we opened

	-- ---------- selection ----------

	local function selectionPayload()
		local out = {}
		for _, id in ipairs(ModifierConfig.ORDER) do
			if picked[id] then
				out[id] = true
			end
		end
		if out.Randomizer then
			out.Randomizer = randomCount
		end
		return out
	end

	local function refresh()
		for id, card in pairs(cards) do
			if card.selected then
				card.selected.Visible = picked[id] == true
			end
			if card.count then
				setText(card.count, tostring(randomCount))
			end
		end
		if totalBonus then
			-- Randomizer's bonus isn't known until the server rolls it
			local stacks = {}
			for id in pairs(picked) do
				if id ~= "Randomizer" then
					stacks[id] = 1
				end
			end
			local text = "Total bonus +" .. ModifierConfig.bonusFor(stacks) .. "%"
			if picked.Randomizer then
				text ..= " + Randomizer x" .. randomCount
			end
			setText(totalBonus, text)
		end
	end

	local function applyLoadout(loadout)
		picked = {}
		for id, value in pairs(loadout) do
			if id == "Randomizer" and ModifierConfig.LIST.Randomizer then
				if type(value) == "number" then
					picked.Randomizer = true
					randomCount = math.clamp(math.floor(value), 1, MAX)
				elseif value == true then
					picked.Randomizer = true
				end
			elseif type(id) == "string" and ModifierConfig.LIST[id] and value == true then
				picked[id] = true
			end
		end
		refresh()
	end

	-- panel buttons are dead while a wipe runs or a round is on, like menu buttons
	local function blocked()
		if fx.isTransitioning() then
			return true
		end
		local menu = ctx.controllers.MenuController
		return menu ~= nil and menu.inRound == true
	end

	-- ---------- open / close ----------

	function self.isUnlocked()
		return unlocked
	end

	function self.isAvailable()
		return available
	end

	function self.isOpen()
		return isOpen
	end

	function self.close()
		if not isOpen then
			return
		end
		isOpen = false
		pendingStart = nil
		openToken += 1
		local token = openToken
		-- hand the gamepad back to whatever it was on, if it's still inside the panel
		local now = GuiService.SelectedObject
		if now == nil or now:IsDescendantOf(gui) then
			local back = previousSelection
			if back and not (back.Parent and playerGui and back:IsDescendantOf(playerGui)) then
				back = nil
			end
			GuiService.SelectedObject = back
		end
		previousSelection = nil
		local home = fx.origin(panel)
		local slide = fx.tween(panel, CLOSE_SECONDS, { Position = home + UDim2.fromScale(0, 1.25) },
			Enum.EasingStyle.Back, Enum.EasingDirection.In)
		slide.Completed:Once(function()
			if token == openToken then
				gui.Enabled = false
				panel.Position = fx.origin(panel)
			end
		end)
	end

	function self.open(modeId, onStart)
		if not available then
			return false
		end
		pendingStart = onStart
		if isOpen then
			return true -- already showing: the latest caller's Start wins
		end
		isOpen = true
		openToken += 1
		refresh()
		gui.Enabled = true
		panel.Visible = true
		fx.slideIn(panel, "bottom", OPEN_SECONDS)
		previousSelection = GuiService.SelectedObject
		-- the D-pad starts on the first card (only for gamepad players: a mouse
		-- user would just see the selection outline)
		if firstToggle and usingGamepad() then
			GuiService.SelectedObject = firstToggle
		end
		return true
	end

	-- ---------- building the panel ----------

	local function child(parent, name, path, className)
		local found = parent:FindFirstChild(name)
		if not (found and found:IsA(className)) then
			warnOnce(path .. "." .. name .. " (" .. className .. ")")
			return nil
		end
		return found
	end

	local function toggle(id)
		if not isOpen or blocked() then
			return
		end
		sounds.play("click")
		picked[id] = (not picked[id]) or nil
		refresh()
	end

	-- step the Randomizer count; stepping also picks Randomizer. Returns
	-- whether the count moved (holding stops at the ends).
	local function step(delta)
		if not isOpen or blocked() then
			return false
		end
		local nextCount = math.clamp(randomCount + delta, 1, MAX)
		local moved = nextCount ~= randomCount
		randomCount = nextCount
		if moved or not picked.Randomizer then
			sounds.play("click", 1 + (randomCount / MAX) * 0.5)
		end
		picked.Randomizer = true
		refresh()
		return moved
	end

	local function bindStepper(button, delta)
		local holdThread = nil
		local repeated = false
		local function stopHold()
			if holdThread then
				local thread = holdThread
				holdThread = nil
				if coroutine.status(thread) ~= "dead" then
					task.cancel(thread)
				end
			end
		end
		button.MouseButton1Down:Connect(function()
			stopHold()
			repeated = false
			holdThread = task.delay(HOLD_DELAY, function()
				while isOpen do
					repeated = true
					if not step(delta) then
						break
					end
					task.wait(HOLD_REPEAT)
				end
				holdThread = nil
			end)
		end)
		button.MouseButton1Up:Connect(stopHold)
		button.MouseLeave:Connect(stopHold)
		button.Activated:Connect(function()
			stopHold()
			if repeated then
				repeated = false -- the hold already stepped; the release isn't another
				return
			end
			step(delta)
		end)
	end

	local function buildCards(list)
		local listPath = GUI_NAME .. ".Panel.List"
		local template = list:FindFirstChild("CardTemplate")
		for index, id in ipairs(ModifierConfig.ORDER) do
			local def = ModifierConfig.LIST[id]
			local card = list:FindFirstChild(id)
			if not card then
				if template then
					card = template:Clone()
					card.Name = id
					if card:IsA("GuiObject") then
						card.LayoutOrder = index
						card.Visible = true
					end
					card.Parent = list
				else
					warnOnce(listPath .. ".CardTemplate (or a hand-made card per modifier)")
				end
			end
			if card and def then
				local path = listPath .. "." .. id
				local entry = {}
				setText(card:FindFirstChild("Title") or warnOnce(path .. ".Title"), def.name)
				setText(card:FindFirstChild("Description") or warnOnce(path .. ".Description"), def.description)
				local bonusText = "+" .. tostring(def.bonusPct or 0) .. "%"
				if def.stackable then
					bonusText = "1–" .. MAX .. " random"
				end
				setText(card:FindFirstChild("Bonus") or warnOnce(path .. ".Bonus"), bonusText)
				local toggleButton = child(card, "Toggle", path, "GuiButton")
				if toggleButton then
					toggleButton.Activated:Connect(function()
						toggle(id)
					end)
					firstToggle = firstToggle or toggleButton
				end
				entry.selected = child(card, "Selected", path, "GuiObject")
				if def.stackable then
					local minus = child(card, "Minus", path, "GuiButton")
					local plus = child(card, "Plus", path, "GuiButton")
					if minus then
						bindStepper(minus, -1)
					end
					if plus then
						bindStepper(plus, 1)
					end
					entry.count = child(card, "Count", path, "TextLabel")
				end
				cards[id] = entry
			end
		end
	end

	local function bindButton(name, handler)
		local button = child(panel, name, GUI_NAME .. ".Panel", "GuiButton")
		if button then
			button.Activated:Connect(function()
				if not isOpen or blocked() then
					return
				end
				handler()
			end)
		end
		return button
	end

	local function setup()
		playerGui = ctx.player:WaitForChild("PlayerGui")
		gui = ModifierAssets.gui(playerGui, GUI_NAME, GUI_WAIT)
		if not gui then
			return -- ModifierAssets already warned; Play starts a normal run
		end
		if gui:IsA("ScreenGui") and gui.ResetOnSpawn then
			-- a respawn would swap in a fresh copy and strand these references
			-- (not changed here: the GUI is yours to set up)
			warn("[Tmod] StarterGui." .. GUI_NAME .. " has ResetOnSpawn = true; set it to false (see MODIFIER_ASSETS.md) or the panel stops working after a respawn.")
		end
		panel = child(gui, "Panel", GUI_NAME, "GuiObject")
		if not panel then
			return
		end
		gui.Enabled = false -- shown only while picking

		local list = child(panel, "List", GUI_NAME .. ".Panel", "GuiObject")
		if list then
			buildCards(list)
		end
		totalBonus = child(panel, "TotalBonus", GUI_NAME .. ".Panel", "TextLabel")

		local startButton = bindButton("StartButton", function()
			sounds.play("click")
			local callback = pendingStart
			local selection = selectionPayload()
			self.close()
			if callback then
				task.spawn(callback, selection)
			end
		end)
		bindButton("ClearButton", function()
			sounds.play("click")
			picked = {}
			randomCount = 1
			refresh()
		end)
		bindButton("BackButton", function()
			sounds.play("click")
			self.close()
		end)

		refresh()
		-- without a Start button the panel would trap the player: stay a normal run
		available = startButton ~= nil
	end

	-- ---------- server data ----------

	ctx.remotes.StatsData.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.modifiersUnlocked ~= nil then
			unlocked = payload.modifiersUnlocked == true
			if not unlocked then
				self.close()
			end
		end
		-- the saved loadout pre-fills the panel, but never under a player's hands
		if type(payload.modifierLoadout) == "table" and (not loadoutSeen or not isOpen) then
			loadoutSeen = true
			applyLoadout(payload.modifierLoadout)
		end
	end)

	-- a run started some other way (or raced the panel): get it off the screen
	if ctx.remotes.GameStarted then
		ctx.remotes.GameStarted.OnClientEvent:Connect(function()
			self.close()
		end)
	end

	task.spawn(function()
		local ok, err = pcall(setup)
		if not ok then
			available = false
			warn("[Tmod] Modifier panel setup failed: " .. tostring(err))
		end
	end)

	-- the server's first StatsData may have gone out before this controller
	-- listened (or before modifiers were unlock-checkable): ask again
	if ctx.remotes.StatsRequest then
		task.delay(2, function()
			ctx.remotes.StatsRequest:FireServer()
		end)
	end

	return self
end

return ModifierMenuController
