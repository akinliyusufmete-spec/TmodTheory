--[[
	SilverMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.SilverMinigame)

	Shown while Silver has you grabbed (StarterGui.SilverGrabGui). Opens with
	a flashbang. A Cube slides back and forth in Panel.BarBack; hit USE (or
	HIT / the bar) while it's in the Zone. GRAB_HITS hits wriggle you free;
	each hit speeds the cube up. Carrying Safety Scissors shows CUT FREE.

	The server validates hits (minimum gap) and releases you; this closes on
	SilverReleased. Tuning lives in GameConfig.NPC.SILVER.

	Frosty's BEARTrapper reuses it (SilverGrab with source "BEARTrapper"):
	same bar, its own title, and no scissors button.
]]

local RunService = game:GetService("RunService")

local SilverMinigame = {}

function SilverMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local cfg = ctx.config.NPC.SILVER
	local sounds = ctx.controllers.SoundController
	local stamina = ctx.controllers.StaminaController
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local gui = fx.gui("SilverGrabGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local hintLabel = panel:WaitForChild("HintLabel")
	local progressLabel = panel:WaitForChild("ProgressLabel")
	local barBack = panel:WaitForChild("BarBack")
	local zone = barBack:WaitForChild("Zone")
	local cube = barBack:WaitForChild("Cube")
	local hitButton = panel:WaitForChild("HitButton")
	local scissorsButton = panel:WaitForChild("CutFreeButton")
	local titleLabel = gui:FindFirstChild("TitleLabel", true)
	local designedTitle = titleLabel and titleLabel.Text
	local progressColor = progressLabel.TextColor3
	local zoneTransparency = zone.BackgroundTransparency

	zone.Size = UDim2.new(cfg.GRAB_HIT_WINDOW * 2, 0, zone.Size.Y.Scale, zone.Size.Y.Offset)

	local hits = 0
	local hitsRequired = cfg.GRAB_HITS
	local bearTrapped = false -- held by Frosty's BEARTrapper, not Silver
	local period = cfg.GRAB_CUBE_PERIOD
	local clock = 0
	local alpha = 0.5

	local function hasScissors()
		local items = ctx.controllers.ItemUseClient
		return items ~= nil and (items.slots[1] == "SCISSORS" or items.slots[2] == "SCISSORS")
	end

	RunService.RenderStepped:Connect(function(dt)
		if not self.active then
			return
		end
		clock = clock + dt
		alpha = 0.5 + 0.5 * math.sin(clock * math.pi * 2 / period)
		cube.Position = UDim2.new(alpha, 0, cube.Position.Y.Scale, cube.Position.Y.Offset)
	end)

	local function attemptHit()
		if not self.active then
			return
		end
		if math.abs(alpha - 0.5) <= cfg.GRAB_HIT_WINDOW then
			hits = hits + 1
			period = period / cfg.GRAB_SPEEDUP -- faster every time
			progressLabel.Text = hits .. " / " .. hitsRequired
			ctx.remotes.SilverHit:FireServer()
			sounds.play("click", 1 + hits * 0.12)
			zone.BackgroundTransparency = 0
			fx.tween(zone, 0.25, { BackgroundTransparency = zoneTransparency })
			fx.pop(progressLabel)
			if hits >= hitsRequired then
				progressLabel.Text = "FREE!"
				progressLabel.TextColor3 = Color3.fromRGB(20, 140, 40)
			end
		else
			sounds.play("error")
			fx.shake(barBack, 8)
		end
	end

	hitButton.Activated:Connect(attemptHit)
	barBack.InputBegan:Connect(function(press)
		if press.UserInputType == Enum.UserInputType.MouseButton1
			or press.UserInputType == Enum.UserInputType.Touch then
			attemptHit()
		end
	end)
	input.onUse(function()
		if self.active then
			attemptHit()
		end
	end)
	scissorsButton.Activated:Connect(function()
		if self.active and not bearTrapped and hasScissors() then
			ctx.remotes.SilverEscape:FireServer()
		end
	end)

	ctx.remotes.SilverGrab.OnClientEvent:Connect(function(required, source)
		hits = 0
		hitsRequired = required or cfg.GRAB_HITS
		bearTrapped = source == "BEARTrapper"
		if titleLabel then
			titleLabel.Text = bearTrapped and "BEARTRAPPED!" or designedTitle
		end
		local useKey = input.getKeyName("USE")
		hintLabel.Text = "Hit the zone [" .. useKey .. "]"
		local l = hitButton:FindFirstChild("Label")
		if l then
			l.Text = "HIT!  [" .. useKey .. "]"
		end
		period = cfg.GRAB_CUBE_PERIOD
		clock = 0
		progressLabel.Text = "0 / " .. hitsRequired
		progressLabel.TextColor3 = progressColor
		scissorsButton.Visible = not bearTrapped and hasScissors()
		self.active = true
		fx.flashbang()
		gui.Enabled = true
		stamina.setSprintLocked(true)
		input.captureMouse("SilverMinigame")
		input.disablePrompts("SilverGrab") -- can't re-trigger a notebook prompt while held
		sounds.play("grab")
	end)

	local function close()
		if not self.active then
			return
		end
		self.active = false
		gui.Enabled = false
		stamina.setSprintLocked(false)
		input.releaseMouse("SilverMinigame")
		input.enablePrompts("SilverGrab")
	end

	ctx.remotes.SilverReleased.OnClientEvent:Connect(close)
	ctx.remotes.RoundEnded.OnClientEvent:Connect(close)
	ctx.remotes.PlayerLost.OnClientEvent:Connect(close)
	ctx.remotes.PlayerWon.OnClientEvent:Connect(close)

	-- keep the scissors button honest if inventory changes mid-grab
	ctx.remotes.InventoryChanged.OnClientEvent:Connect(function()
		if self.active then
			scissorsButton.Visible = not bearTrapped and hasScissors()
		end
	end)

	self.close = close
	return self
end

return SilverMinigame
