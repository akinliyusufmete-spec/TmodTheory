--[[
	HudController (ModuleScript, StarterPlayerScripts.BaldiClient.HudController)

	Drives the hand-built StarterGui.GameplayMenuGui (shown only during a round):
	  NotebookCounterFrame  NotebookCount "x/y" (pops on each collect)
	  NickleCounter         NickleCount + NickleImage (coin skin)
	  StopwatchFrame        StopwatchCounter "MM:SS" over an analog face: the
	                        LongHand jumps a numeral every 5 s (1 turn / 60 s), the
	                        ShortHand tracks minutes (1 turn / 60 min), both
	                        tweened in step with the counter
	  StaminaFrame          StaminaBlocker hides the spent part of StaminaBgFrame,
	                        StaminaCounter reads it out
	  InventoryFrame        two slots: ItemImageLabel, ItemNameLabel, key badge
	  ObjectiveLabel / WarningLabel / BannerLabel / ColdLabel
	  MobileControls        RUN / USE / SWAP on touch devices (layout saved per player)

	Subscribes to its own data remotes: NotebookCollected, NickelChanged,
	PickupFailed, PhaseChanged. InventoryChanged is consumed by ItemUseClient,
	which calls setSlots.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HudController = {}

local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(255, 220, 60)
local RED = Color3.fromRGB(255, 70, 60)

function HudController.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local input = ctx.controllers.InputHandler
	local cosmetics = ctx.controllers.CosmeticState
	local images = ctx.assets.IMAGES
	local self = { mobile = {} }

	local gui = fx.gui("GameplayMenuGui")
	gui.Enabled = false
	local main = gui:WaitForChild("MainFrame")

	-- ===================== notebooks / objective =====================

	local notebookFrame = main:WaitForChild("NotebookCounterFrame")
	local notebookCount = notebookFrame:WaitForChild("NotebookCount")
	local objectiveLabel = main:WaitForChild("ObjectiveLabel")
	local warningLabel = main:WaitForChild("WarningLabel")
	local bannerLabel = main:WaitForChild("BannerLabel")
	local coldLabel = main:WaitForChild("ColdLabel")

	-- the transient labels start clear; remember their stroke to fade it too
	local function hideText(label)
		label:SetAttribute("HudStroke", label.TextStrokeTransparency)
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	local function showText(label)
		label.TextTransparency = 0
		label.TextStrokeTransparency = label:GetAttribute("HudStroke") or 0
	end
	local function fadeText(label, seconds)
		fx.tween(label, seconds, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end
	hideText(warningLabel)
	hideText(bannerLabel)
	coldLabel.Visible = false

	-- ===================== stopwatch =====================

	local stopwatchFrame = main:WaitForChild("StopwatchFrame")
	local stopwatchCounter = stopwatchFrame:WaitForChild("StopwatchCounter")
	-- long hand = seconds in 5 s steps (one turn per minute), short hand = minutes (one turn per hour)
	local secondHand = stopwatchFrame:WaitForChild("StopwatchLongHandImageLabel")
	local minuteHand = stopwatchFrame:WaitForChild("StopwatchShortHandImageLabel")

	local stopwatchEnabled = true -- the player's setting (Settings page)
	local stopwatchRunning = false -- true only while a round is active
	local stopwatchStart = 0
	local lastSecond = -1

	local LONG_STEP_SECONDS = 5 -- long hand moves once every 5 seconds,
	local DEG_PER_LONG_STEP = 360 / 12 -- jumping 30 degrees onto the next numeral
	local DEG_PER_MINUTE = 360 / 60 -- short hand: 6 degrees per minute mark
	-- the long hand snaps onto each numeral with a small overshoot, like a real tick;
	-- the minute hand glides the 0.1 degrees it moves every second
	local SECOND_TICK = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local MINUTE_GLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local handTweens = {}
	local lastLongAngle = nil -- the long hand's current target, so it only tweens on a new step

	local function formatStopwatch(seconds)
		local minutes = math.floor(seconds / 60)
		return string.format("%02d:%02d", minutes, math.floor(seconds - minutes * 60))
	end

	local function stopHandTweens()
		for hand, tween in pairs(handTweens) do
			tween:Cancel()
			handTweens[hand] = nil
		end
	end

	local function tweenHand(hand, info, rotation)
		local previous = handTweens[hand]
		if previous then
			previous:Cancel()
		end
		local tween = TweenService:Create(hand, info, { Rotation = rotation })
		handTweens[hand] = tween
		tween:Play()
	end

	-- Angles are cumulative (65 s = 390 degrees, not 30), so a hand always moves
	-- clockwise and never spins back round at the top of the dial.
	local function setHands(wholeSeconds, animate)
		local longAngle = math.floor(wholeSeconds / LONG_STEP_SECONDS) * DEG_PER_LONG_STEP
		local minuteAngle = (wholeSeconds / 60) * DEG_PER_MINUTE
		if animate then
			-- the long hand holds still between 5 s marks; only tick it on a new step
			if longAngle ~= lastLongAngle then
				tweenHand(secondHand, SECOND_TICK, longAngle)
			end
			tweenHand(minuteHand, MINUTE_GLIDE, minuteAngle)
		else
			stopHandTweens()
			secondHand.Rotation = longAngle
			minuteHand.Rotation = minuteAngle
		end
		lastLongAngle = longAngle
	end
	setHands(0, false)

	RunService.Heartbeat:Connect(function()
		if not (stopwatchRunning and stopwatchEnabled and gui.Enabled) then
			return
		end
		local elapsed = os.clock() - stopwatchStart
		local second = math.floor(elapsed)
		if second ~= lastSecond then
			-- after a hidden stretch (HUD off) jump straight to the time instead of
			-- sweeping through every missed second
			local caughtUp = lastSecond >= 0 and second - lastSecond > 2
			lastSecond = second
			stopwatchCounter.Text = formatStopwatch(elapsed)
			setHands(second, not caughtUp)
		end
	end)

	-- ===================== inventory =====================

	local inventory = main:WaitForChild("InventoryFrame")
	local function slotParts(frame)
		local badge = frame:FindFirstChild("KeyHintLabel")
		return {
			frame = frame,
			image = frame:WaitForChild("ItemImageLabel"),
			name = frame:WaitForChild("ItemNameLabel"),
			key = badge and badge:FindFirstChild("KeyLabel"),
		}
	end
	local slot1 = slotParts(inventory:WaitForChild("InventoryFirstSlotFrame"))
	local slot2 = slotParts(inventory:WaitForChild("InventorySecondSlotFrame"))

	local function refreshBindHints()
		if slot1.key then
			slot1.key.Text = input.getKeyName("USE")
		end
		if slot2.key then
			slot2.key.Text = input.getKeyName("SWAP")
		end
	end
	refreshBindHints()
	input.onBindsChanged(refreshBindHints)

	local function renderSlot(slot, itemId)
		if itemId then
			local def = ctx.config.ITEMS[itemId]
			local skinImage = cosmetics and cosmetics.getImage(itemId)
			slot.image.Image = skinImage or (images.ITEMS and images.ITEMS[itemId]) or ""
			slot.name.Text = def and def.displayName or itemId
		else
			slot.image.Image = ""
			slot.name.Text = "Empty"
		end
	end

	local currentSlots = { nil, nil }
	function self.setSlots(itemId1, itemId2)
		local gained = (itemId1 and itemId1 ~= currentSlots[1]) or (itemId2 and itemId2 ~= currentSlots[2])
		currentSlots[1] = itemId1
		currentSlots[2] = itemId2
		renderSlot(slot1, itemId1)
		renderSlot(slot2, itemId2)
		if gained and gui.Enabled then
			fx.pop(itemId1 ~= nil and slot1.image or slot2.image)
		end
	end

	-- ===================== nickels =====================

	local nickelFrame = main:WaitForChild("NickleCounter")
	local nickelCount = nickelFrame:WaitForChild("NickleCount")
	local nickelImage = nickelFrame:WaitForChild("NickleImage")
	local defaultNickelImage = nickelImage.Image

	function self.setNickels(count)
		nickelCount.Text = tostring(count)
	end

	-- repaint everything a cosmetic can touch
	local function applyCosmetics()
		renderSlot(slot1, currentSlots[1])
		renderSlot(slot2, currentSlots[2])
		local coinImage = cosmetics and cosmetics.getImage("NICKEL")
		nickelImage.Image = coinImage or defaultNickelImage
	end
	if cosmetics then
		cosmetics.onChanged(applyCosmetics)
	end
	applyCosmetics()

	-- ===================== stamina =====================

	local staminaFrame = main:WaitForChild("StaminaFrame")
	local staminaBg = staminaFrame:WaitForChild("StaminaBgFrame")
	local staminaBlocker = staminaFrame:WaitForChild("StaminaBlocker")
	local staminaCounter = staminaFrame:WaitForChild("StaminaCounter")
	local bgPos, bgSize = staminaBg.Position, staminaBg.Size
	local blockerY, blockerH = staminaBlocker.Position.Y, staminaBlocker.Size.Y

	local lastMode = "ok"
	local lastShown = -1
	-- mode: "ok" | "low" | "exhausted"; cold: boolean
	function self.setStamina(alpha, mode, cold)
		alpha = math.clamp(alpha, 0, 1)
		-- the black blocker covers the spent (right-hand) part of the bar
		staminaBlocker.Visible = alpha < 0.999
		staminaBlocker.Position = UDim2.new(bgPos.X.Scale + bgSize.X.Scale * alpha, bgPos.X.Offset + bgSize.X.Offset * alpha, blockerY.Scale, blockerY.Offset)
		staminaBlocker.Size = UDim2.new(bgSize.X.Scale * (1 - alpha), bgSize.X.Offset * (1 - alpha), blockerH.Scale, blockerH.Offset)
		local shown = math.floor(alpha * 100 + 0.5)
		if shown ~= lastShown then
			lastShown = shown
			staminaCounter.Text = "Stamina: " .. shown
		end
		coldLabel.Visible = cold == true
		if mode ~= lastMode then
			lastMode = mode
			staminaCounter.TextColor3 = (mode == "exhausted" and RED) or (mode == "low" and YELLOW) or WHITE
			if mode == "exhausted" then
				local home = fx.origin(staminaFrame)
				task.spawn(function()
					for i = 1, 4 do
						staminaFrame.Position = home + UDim2.fromOffset(i % 2 == 0 and 7 or -7, 0)
						task.wait(0.04)
					end
					staminaFrame.Position = home
				end)
				sounds.play("exhausted")
			end
		end
	end

	function self.flashStaminaFull()
		staminaBg.BackgroundTransparency = 0.6
		fx.tween(staminaBg, 0.4, { BackgroundTransparency = 0 })
	end

	-- ===================== messages =====================

	function self.setObjective(text)
		objectiveLabel.Text = text
	end

	local lastNotebookCount = 0
	function self.setNotebooks(collected, total)
		notebookCount.Text = string.format("%d/%d", collected, total)
		if collected > lastNotebookCount then
			sounds.play("collect")
			fx.pop(notebookFrame)
		end
		lastNotebookCount = collected
	end

	function self.resetForRound(total)
		lastNotebookCount = 0
		notebookCount.Text = string.format("0/%d", total)
		self.setObjective("Collect all " .. total .. " notebooks")
	end

	local flashToken = 0
	function self.flashPickupFailed(message)
		flashToken += 1
		local token = flashToken
		warningLabel.Text = message or "Inventory full"
		showText(warningLabel)
		sounds.play("error")
		task.delay(1.5, function()
			if token == flashToken then
				fadeText(warningLabel, 0.4)
			end
		end)
	end

	local bannerToken = 0
	function self.banner(text, color)
		bannerToken += 1
		local token = bannerToken
		bannerLabel.Text = text
		bannerLabel.TextColor3 = color or YELLOW
		showText(bannerLabel)
		fx.pop(bannerLabel)
		task.delay(2.2, function()
			if token == bannerToken then
				fadeText(bannerLabel, 0.6)
			end
		end)
	end

	-- ===================== mobile buttons =====================

	local mobileFrame = main:WaitForChild("MobileControls")
	mobileFrame.Visible = input.touchEnabled
	if input.touchEnabled then
		local mobileCfg = ctx.config.MOBILE_HUD or {}
		local defaults = mobileCfg.DEFAULTS or {}
		local baseSize = mobileCfg.BASE_SIZE or { sprint = 96, use = 96, swap = 82 }
		local sprintButton = mobileFrame:WaitForChild("RunButton")
		local useButton = mobileFrame:WaitForChild("UseButton")
		local swapButton = mobileFrame:WaitForChild("SwapButton")

		local buttons = { sprint = sprintButton, use = useButton, swap = swapButton }
		self.mobile = { sprintButton = sprintButton, useButton = useButton, swapButton = swapButton }
		self.mobileButtons = buttons
		self.mobileBaseSize = baseSize

		local layout = {}
		for key, d in pairs(defaults) do
			layout[key] = { x = d.x, y = d.y, scale = d.scale or 1 }
		end

		-- position + size every button from a layout table (editor + profile)
		function self.applyHudLayout(newLayout)
			for key, button in pairs(buttons) do
				local entry = (newLayout and newLayout[key]) or layout[key] or defaults[key]
				if entry then
					layout[key] = { x = entry.x, y = entry.y, scale = entry.scale or 1 }
					local px = (baseSize[key] or 90) * (entry.scale or 1)
					button.Position = UDim2.fromScale(entry.x, entry.y)
					button.Size = UDim2.fromOffset(px, px)
				end
			end
		end

		function self.getHudLayout()
			local out = {}
			for key, entry in pairs(layout) do
				out[key] = { x = entry.x, y = entry.y, scale = entry.scale }
			end
			return out
		end

		self.applyHudLayout(layout)

		ctx.remotes.StatsData.OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and type(payload.hudLayout) == "table" and next(payload.hudLayout) then
				self.applyHudLayout(payload.hudLayout)
			end
		end)

		-- sprint is a toggle on mobile
		local sprintOn = false
		local sprintLabel = sprintButton:FindFirstChild("Label")
		sprintButton.Activated:Connect(function()
			sprintOn = not sprintOn
			if sprintLabel then
				sprintLabel.TextColor3 = sprintOn and YELLOW or WHITE
			end
			input.notifySprint(sprintOn)
		end)
		useButton.Activated:Connect(function()
			input.notifyUse()
		end)
		swapButton.Activated:Connect(function()
			input.notifySwap()
		end)
	end

	-- ===================== API =====================

	function self.show()
		gui.Enabled = true
	end

	function self.hide()
		gui.Enabled = false
	end

	function self.setStopwatchEnabled(enabled)
		stopwatchEnabled = enabled ~= false
		stopwatchFrame.Visible = stopwatchEnabled
	end

	function self.startStopwatch()
		stopwatchRunning = true
		stopwatchStart = os.clock()
		lastSecond = -1
		stopwatchCounter.Text = formatStopwatch(0)
		setHands(0, false)
	end

	function self.stopStopwatch()
		stopwatchRunning = false
	end

	-- ===================== remote subscriptions =====================

	ctx.remotes.NotebookCollected.OnClientEvent:Connect(function(collected, total, collectorUserId)
		self.setNotebooks(collected, total)
		if collectorUserId == ctx.player.UserId then
			local cosmeticSound = cosmetics and cosmetics.getSound("NOTEBOOK")
			if cosmeticSound then
				sounds.playId(cosmeticSound)
			end
			sounds.play("notebookSolved")
		end
	end)

	ctx.remotes.NickelChanged.OnClientEvent:Connect(function(count)
		local previous = nickelCount.Text
		self.setNickels(count)
		if gui.Enabled and previous ~= nickelCount.Text then
			sounds.play("nickel")
			fx.pop(nickelImage)
		end
	end)

	ctx.remotes.PickupFailed.OnClientEvent:Connect(function(message)
		self.flashPickupFailed(message)
	end)

	ctx.remotes.PhaseChanged.OnClientEvent:Connect(function(phaseName)
		if phaseName == "CHARACTERS_ACTIVE" then
			self.banner("You hear footsteps...", RED)
			self.setObjective("Keep collecting — they're awake.")
		elseif phaseName == "EXIT_OPEN" then
			self.banner("ALL NOTEBOOKS! GET TO THE EXIT!", Color3.fromRGB(150, 255, 150))
			self.setObjective("Escape through the EXIT door!")
			sounds.play("collect", 0.7)
		end
	end)

	renderSlot(slot1, nil)
	renderSlot(slot2, nil)
	return self
end

return HudController
