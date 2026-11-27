--[[
	MemoryMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.MemoryMinigame)

	Green notebooks (StarterGui.MemoryMinigameGui): the four tiles in
	Panel.TileRow (RedTile, BlueTile, GreenTile, YellowTile) light up in a
	random order; tap them back in the same order. A wrong tap turns them all
	red, shakes the row and closes it. The panel slides in from below.

	Shares the NotebookMinigame remote: payloads with kind = "memory".
]]

local RunService = game:GetService("RunService")

local MemoryMinigame = {}

local TILE_COLORS = {
	red = Color3.fromRGB(210, 50, 50),
	blue = Color3.fromRGB(50, 110, 220),
	green = Color3.fromRGB(40, 170, 70),
	yellow = Color3.fromRGB(215, 185, 30),
}
local TILE_DIM = Color3.fromRGB(60, 60, 70)
local TILE_NAMES = { red = "RedTile", blue = "BlueTile", green = "GreenTile", yellow = "YellowTile" }

function MemoryMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local gui = fx.gui("MemoryMinigameGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local phaseLabel = panel:WaitForChild("PhaseLabel")
	local tileRow = panel:WaitForChild("TileRow")
	local progressLabel = panel:WaitForChild("ProgressLabel")
	local giveUpButton = panel:WaitForChild("GiveUpButton")
	local progressColor = progressLabel.TextColor3
	fx.origin(panel)

	local tiles = {}
	for colorName, tileName in pairs(TILE_NAMES) do
		tiles[colorName] = tileRow:WaitForChild(tileName)
	end

	local sequence = nil
	local notebookPosition = nil
	local showEach, showGap = 0.65, 0.1
	local sessionToken = 0 -- bumped on every open/close; stale previews stop
	local watching = true -- input ignored during the preview
	local progress = 0

	local function setTile(colorName, lit)
		local tile = tiles[colorName]
		if tile then
			tile.BackgroundColor3 = lit and TILE_COLORS[colorName] or TILE_DIM
		end
	end
	local function resetTiles()
		for colorName in pairs(tiles) do
			setTile(colorName, false)
		end
	end

	local function close(tellServer)
		if not self.active then
			return
		end
		self.active = false
		sessionToken += 1
		gui.Enabled = false
		input.enablePrompts("MemoryMinigame")
		input.releaseMouse("MemoryMinigame")
		resetTiles()
		if tellServer then
			ctx.remotes.NotebookMinigameAction:FireServer("cancel")
		end
	end

	local function playPreview()
		local token = sessionToken
		watching = true
		progress = 0
		phaseLabel.Text = "Watch the sequence"
		progressLabel.Text = ""
		progressLabel.TextColor3 = progressColor
		resetTiles()
		task.spawn(function()
			task.wait(0.6) -- let the panel finish sliding in
			for _, colorName in ipairs(sequence) do
				if token ~= sessionToken then
					return
				end
				setTile(colorName, true)
				fx.pop(tiles[colorName])
				sounds.play("click", colorName == "yellow" and 1.3 or 1.0)
				task.wait(showEach)
				if token ~= sessionToken then
					return
				end
				setTile(colorName, false)
				task.wait(showGap)
			end
			if token ~= sessionToken then
				return
			end
			watching = false
			phaseLabel.Text = "Repeat the sequence"
			progressLabel.Text = "0 / " .. #sequence
		end)
	end

	local function open(data)
		if type(data.sequence) ~= "table" or typeof(data.position) ~= "Vector3" then
			return
		end
		sequence = data.sequence
		notebookPosition = data.position
		showEach = data.showEach or 0.65
		showGap = data.showGap or 0.1
		sessionToken += 1
		local l = giveUpButton:FindFirstChild("Label")
		if l then
			l.Text = "GIVE UP  [" .. input.getKeyName("CANCEL") .. "]"
		end
		self.active = true
		gui.Enabled = true
		fx.slideIn(panel, "bottom", 0.5)
		input.disablePrompts("MemoryMinigame")
		input.captureMouse("MemoryMinigame")
		sounds.play("click")
		playPreview()
	end

	local function tapTile(colorName)
		if not self.active or watching then
			return
		end
		if colorName == sequence[progress + 1] then
			progress += 1
			setTile(colorName, true)
			fx.pop(tiles[colorName])
			sounds.play("collect", 1 + progress * 0.08)
			progressLabel.Text = progress .. " / " .. #sequence
			local token = sessionToken
			task.delay(0.25, function()
				if token == sessionToken and progress < #sequence then
					setTile(colorName, false)
				end
			end)
			if progress >= #sequence then
				phaseLabel.Text = "Done!"
				progressLabel.TextColor3 = Color3.fromRGB(20, 140, 40)
				ctx.remotes.NotebookMinigameAction:FireServer("memory_done", sequence)
				-- the server answers with nil to close us
			end
		else
			sounds.play("error")
			phaseLabel.Text = "Wrong!"
			fx.shake(tileRow, 9)
			for _, tile in pairs(tiles) do
				tile.BackgroundColor3 = Color3.fromRGB(160, 30, 30)
			end
			task.delay(0.5, function()
				if self.active then
					close(true)
				end
			end)
		end
	end

	for colorName, tile in pairs(tiles) do
		tile.Activated:Connect(function()
			tapTile(colorName)
		end)
	end
	giveUpButton.Activated:Connect(function()
		close(true)
	end)
	input.onCancel(function()
		if self.active then
			close(true)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not self.active then
			return
		end
		local character = ctx.player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local cancelDist = (ctx.config.MEMORY_MINIGAME and ctx.config.MEMORY_MINIGAME.CANCEL_DISTANCE) or 12
		if not hrp or (hrp.Position - notebookPosition).Magnitude > cancelDist then
			close(true)
		end
	end)

	ctx.remotes.NotebookMinigame.OnClientEvent:Connect(function(data)
		if data == nil then
			close(false)
		elseif typeof(data) == "table" and data.kind == "memory" then
			open(data)
		end
	end)

	ctx.remotes.SendToDetention.OnClientEvent:Connect(function()
		close(true)
	end)
	for _, remote in ipairs({ ctx.remotes.RoundEnded, ctx.remotes.PlayerLost, ctx.remotes.PlayerWon }) do
		remote.OnClientEvent:Connect(function()
			close(false)
		end)
	end

	resetTiles()
	return self
end

return MemoryMinigame
