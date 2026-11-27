--[[
	ChainMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.ChainMinigame)

	Shown while Chain has you shackled (MULTIPLAYER) — StarterGui.ChainShackleGui,
	opened with a flashbang. It does NOT lock your movement: you keep dragging
	Chain around while you struggle, slowed to a trudge.

	Mash USE (or PULL / tap the bar) to fill Panel.BarBack (Fill + Knot); strain
	bleeds off when you stop. Fill it and the chain SNAPS. Carrying Safety
	Scissors, SWAP (or SNIP) cuts it instantly. The meter is a local
	prediction — the server owns the snap (ChainReleased).

	Tuning lives in GameConfig.NPC.CHAIN.
]]

local RunService = game:GetService("RunService")

local ChainMinigame = {}

function ChainMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local cfg = ctx.config.NPC.CHAIN
	local sounds = ctx.controllers.SoundController
	local stamina = ctx.controllers.StaminaController
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local gui = fx.gui("ChainShackleGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local hint = panel:WaitForChild("HintLabel")
	local barBack = panel:WaitForChild("BarBack")
	local fill = barBack:WaitForChild("Fill")
	local knot = barBack:WaitForChild("Knot")
	local pullButton = panel:WaitForChild("PullButton")
	local snipButton = panel:WaitForChild("SnipButton")
	local designedHint = hint.Text -- your text, used on touch devices
	local hintColor = hint.TextColor3
	local knotColor = knot.BackgroundColor3

	local required = cfg.TUG_REQUIRED
	local strain = 0
	local lastMashAt = 0

	local function hasScissors()
		local items = ctx.controllers.ItemUseClient
		return items ~= nil and (items.slots[1] == "SCISSORS" or items.slots[2] == "SCISSORS")
	end

	local function mash()
		if not self.active then
			return
		end
		local now = os.clock()
		if now - lastMashAt < cfg.TUG_MIN_GAP then
			return -- match the server's anti-spam gate so the meter stays honest
		end
		lastMashAt = now
		strain = math.min(required, strain + cfg.TUG_PER_MASH)
		ctx.remotes.ChainTug:FireServer()
		sounds.play("click", 1 + (strain / required) * 0.5)
		knot.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
		fx.tween(knot, 0.12, { BackgroundColor3 = knotColor })
		if strain >= required then
			hint.Text = "SNAP!"
			hint.TextColor3 = Color3.fromRGB(20, 140, 40)
		end
	end

	local function snip()
		if self.active and hasScissors() then
			ctx.remotes.ChainSnip:FireServer()
		end
	end

	pullButton.Activated:Connect(mash)
	snipButton.Activated:Connect(snip)
	barBack.InputBegan:Connect(function(press)
		if press.UserInputType == Enum.UserInputType.MouseButton1
			or press.UserInputType == Enum.UserInputType.Touch then
			mash()
		end
	end)
	input.onUse(function()
		if self.active then
			mash()
		end
	end)
	input.onSwap(function()
		if self.active then
			snip()
		end
	end)

	-- drag-slow + strain decay + rope render, every frame while shackled
	RunService.RenderStepped:Connect(function(dt)
		if not self.active then
			return
		end
		stamina.applyDebuff(cfg.DRAG_SLOW, 0.2)
		strain = math.max(0, strain - cfg.TUG_DECAY * dt)
		local alpha = math.clamp(strain / required, 0, 1)
		fill.Size = UDim2.new(alpha, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		knot.Position = UDim2.new(alpha, 0, knot.Position.Y.Scale, knot.Position.Y.Offset)
	end)

	local function refreshButtons()
		local mobile = input.touchEnabled
		snipButton.Visible = hasScissors() and mobile
		pullButton.Visible = mobile
	end

	ctx.remotes.ChainShackled.OnClientEvent:Connect(function()
		strain = 0
		required = cfg.TUG_REQUIRED
		local useKey, swapKey = input.getKeyName("USE"), input.getKeyName("SWAP")
		if input.touchEnabled then
			hint.Text = designedHint
		else
			local text = "Mash [" .. useKey .. "] to break free!"
			if hasScissors() then
				text = text .. "    ·    [" .. swapKey .. "] to snip"
			end
			hint.Text = text
		end
		hint.TextColor3 = hintColor
		for button, text in pairs({ [pullButton] = "PULL!  [" .. useKey .. "]", [snipButton] = "SNIP  [" .. swapKey .. "]" }) do
			local l = button:FindFirstChild("Label")
			if l then
				l.Text = text
			end
		end
		fill.Size = UDim2.new(0, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		knot.Position = UDim2.new(0, 0, knot.Position.Y.Scale, knot.Position.Y.Offset)
		refreshButtons()
		self.active = true
		fx.flashbang()
		gui.Enabled = true
		sounds.play("grab")
	end)

	local function close()
		if not self.active then
			return
		end
		self.active = false
		gui.Enabled = false
	end

	ctx.remotes.ChainReleased.OnClientEvent:Connect(function(reason)
		if self.active and reason == "snipped" then
			sounds.play("buy", 1.4)
		end
		close()
	end)
	ctx.remotes.RoundEnded.OnClientEvent:Connect(close)
	ctx.remotes.PlayerLost.OnClientEvent:Connect(close)
	ctx.remotes.PlayerWon.OnClientEvent:Connect(close)

	ctx.remotes.InventoryChanged.OnClientEvent:Connect(function()
		if self.active then
			refreshButtons()
		end
	end)

	self.close = close
	return self
end

return ChainMinigame
