--[[
	NotebookMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.NotebookMinigame)

	Red notebooks: the timing bar (StarterGui.NotebookMinigameGui). A marker
	sweeps across Panel.BarBack; press USE (or click HIT / the bar) while it's
	in the green Zone. HITS hits collects the notebook; a miss just shakes the
	bar. CANCEL (or GIVE UP) gives up. The panel slides in from below.

	You are NOT protected while doing this — keep one eye on the hall. The
	client times the marker; the SERVER counts the hits (rate-limited).
	Tuning: GameConfig.NOTEBOOK_MINIGAME.
]]

local RunService = game:GetService("RunService")

local NotebookMinigame = {}

function NotebookMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local input = ctx.controllers.InputHandler
	local cfg = ctx.config.NOTEBOOK_MINIGAME
	local self = { active = false }

	local gui = fx.gui("NotebookMinigameGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local hintLabel = panel:WaitForChild("HintLabel")
	local progressLabel = panel:WaitForChild("ProgressLabel")
	local barBack = panel:WaitForChild("BarBack")
	local zone = barBack:WaitForChild("Zone")
	local marker = barBack:WaitForChild("Marker")
	local hitButton = panel:WaitForChild("HitButton")
	local giveUpButton = panel:WaitForChild("GiveUpButton")
	local progressColor = progressLabel.TextColor3
	local zoneTransparency = zone.BackgroundTransparency
	fx.origin(panel)

	-- the green zone is exactly the server's hit window
	zone.Size = UDim2.new(cfg.HIT_WINDOW * 2, 0, zone.Size.Y.Scale, zone.Size.Y.Offset)

	local function setText(button, text)
		local label = button:FindFirstChild("Label")
		if label then
			label.Text = text
		end
	end

	local notebookPosition = nil
	local hits = 0
	local hitsRequired = cfg.HITS
	local clock = 0
	local alpha = 0.5
	local done = false

	local function close(tellServer)
		if not self.active then
			return
		end
		self.active = false
		gui.Enabled = false
		input.enablePrompts("NotebookMinigame")
		input.releaseMouse("NotebookMinigame")
		if tellServer then
			ctx.remotes.NotebookMinigameAction:FireServer("cancel")
		end
	end

	local function open(data)
		if typeof(data) ~= "table" or typeof(data.position) ~= "Vector3" then
			return
		end
		if data.kind ~= nil and data.kind ~= "timing" then
			return -- a different minigame module owns this payload
		end
		local useKey = input.getKeyName("USE")
		hintLabel.Text = "Press " .. useKey .. " when the marker is in the green!"
		setText(hitButton, "HIT!  [" .. useKey .. "]")
		setText(giveUpButton, "GIVE UP  [" .. input.getKeyName("CANCEL") .. "]")
		notebookPosition = data.position
		hits = 0
		hitsRequired = data.hits or cfg.HITS
		clock = 0
		done = false
		progressLabel.Text = "0 / " .. hitsRequired
		progressLabel.TextColor3 = progressColor
		self.active = true
		gui.Enabled = true
		fx.slideIn(panel, "bottom", 0.5)
		input.disablePrompts("NotebookMinigame")
		input.captureMouse("NotebookMinigame")
		sounds.play("click")
	end

	RunService.RenderStepped:Connect(function(dt)
		if not self.active then
			return
		end
		-- abandon if we've wandered off the notebook
		local character = ctx.player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - notebookPosition).Magnitude > cfg.CANCEL_DISTANCE then
			close(true)
			return
		end
		clock = clock + dt
		alpha = 0.5 + 0.5 * math.sin(clock * math.pi * 2 / cfg.BAR_PERIOD)
		marker.Position = UDim2.new(alpha, 0, marker.Position.Y.Scale, marker.Position.Y.Offset)
	end)

	local function attemptHit()
		if not self.active or done then
			return
		end
		if math.abs(alpha - 0.5) <= cfg.HIT_WINDOW then
			hits = hits + 1
			progressLabel.Text = hits .. " / " .. hitsRequired
			ctx.remotes.NotebookMinigameAction:FireServer("hit")
			sounds.play("collect", 1 + hits * 0.1)
			zone.BackgroundTransparency = 0
			fx.tween(zone, 0.25, { BackgroundTransparency = zoneTransparency })
			fx.pop(progressLabel)
			if hits >= hitsRequired then
				done = true -- the server validates and closes us
				progressLabel.Text = "GOT IT!"
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
	giveUpButton.Activated:Connect(function()
		close(true)
	end)
	input.onUse(function()
		if self.active then
			attemptHit()
		end
	end)
	input.onCancel(function()
		if self.active then
			close(true)
		end
	end)

	ctx.remotes.NotebookMinigame.OnClientEvent:Connect(function(data)
		if data == nil then
			close(false)
		else
			open(data)
		end
	end)

	-- anything that takes control of the player ends the attempt
	ctx.remotes.SilverGrab.OnClientEvent:Connect(function()
		close(true)
	end)
	ctx.remotes.SendToDetention.OnClientEvent:Connect(function()
		close(true)
	end)
	for _, remote in ipairs({ ctx.remotes.RoundEnded, ctx.remotes.PlayerLost, ctx.remotes.PlayerWon }) do
		remote.OnClientEvent:Connect(function()
			close(false)
		end)
	end

	return self
end

return NotebookMinigame
