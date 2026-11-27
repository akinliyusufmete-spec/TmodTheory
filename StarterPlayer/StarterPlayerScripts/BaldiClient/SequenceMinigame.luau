--[[
	SequenceMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.SequenceMinigame)

	Purple notebooks + Impersonator mode (StarterGui.SequenceMinigameGui).
	A pattern of your USE / SWAP keys flashes in Panel.BoxRow (one box per
	symbol, cloned from Templates.BoxTemplate) — memorize it, then press it
	back in order. A wrong press is LOUD (Sportage hears it) and the preview
	replays. Touch players get Use/Swap tap buttons (MobileTaps). The panel
	slides in from below.

	Shares the NotebookMinigame remote: payloads with kind = "sequence".
]]

local RunService = game:GetService("RunService")

local SequenceMinigame = {}

local BOX_IDLE = Color3.fromRGB(40, 44, 48)
local BOX_SHOW = Color3.fromRGB(70, 120, 200)
local BOX_RIGHT = Color3.fromRGB(40, 170, 70)
local BOX_WRONG = Color3.fromRGB(120, 40, 40)

function SequenceMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local input = ctx.controllers.InputHandler
	local cfg = ctx.config.SEQUENCE_MINIGAME
	local self = { active = false }

	local gui = fx.gui("SequenceMinigameGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local phaseLabel = panel:WaitForChild("PhaseLabel")
	local row = panel:WaitForChild("BoxRow")
	local giveUpButton = panel:WaitForChild("GiveUpButton")
	local boxTemplate = gui:WaitForChild("Templates"):WaitForChild("BoxTemplate")
	local mobileTaps = gui:WaitForChild("MobileTaps")
	fx.origin(panel)

	-- clear the Studio preview boxes
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local pattern = nil
	local notebookPosition = nil
	local progress = 0
	local watching = true
	local boxes = {}
	local sessionToken = 0

	local function keyLabel(action)
		return input.getKeyName(action)
	end

	local function buildBoxes()
		for _, box in ipairs(boxes) do
			box:Destroy()
		end
		boxes = {}
		for index = 1, #pattern do
			local box = boxTemplate:Clone()
			box.Name = "Box" .. index
			box.LayoutOrder = index
			box.BackgroundColor3 = BOX_IDLE
			box.KeyLabel.Text = "?"
			box.Visible = true
			box.Parent = row
			boxes[index] = box
		end
	end

	local function close(tellServer)
		if not self.active then
			return
		end
		self.active = false
		sessionToken += 1
		gui.Enabled = false
		input.enablePrompts("SequenceMinigame")
		input.releaseMouse("SequenceMinigame")
		if tellServer then
			ctx.remotes.NotebookMinigameAction:FireServer("cancel")
		end
	end

	local function playPreview(leadIn)
		local token = sessionToken
		watching = true
		progress = 0
		phaseLabel.Text = "Watch the pattern..."
		task.spawn(function()
			task.wait(leadIn or 0)
			for index, action in ipairs(pattern) do
				if token ~= sessionToken then
					return
				end
				local box = boxes[index]
				box.KeyLabel.Text = keyLabel(action)
				box.BackgroundColor3 = BOX_SHOW
				fx.pop(box)
				sounds.play("click", action == "USE" and 1.2 or 0.9)
				task.wait(cfg.SHOW_SECONDS)
				if token ~= sessionToken then
					return
				end
				box.KeyLabel.Text = "?"
				box.BackgroundColor3 = BOX_IDLE
				task.wait(0.08)
			end
			if token ~= sessionToken then
				return
			end
			watching = false
			phaseLabel.Text = "Your turn — repeat it!"
		end)
	end

	local function open(data)
		if typeof(data.pattern) ~= "table" or #data.pattern == 0 or typeof(data.position) ~= "Vector3" then
			return
		end
		pattern = data.pattern
		notebookPosition = data.position
		sessionToken += 1
		local l = giveUpButton:FindFirstChild("Label")
		if l then
			l.Text = "GIVE UP  [" .. keyLabel("CANCEL") .. "]"
		end
		self.active = true
		gui.Enabled = true
		mobileTaps.Visible = input.touchEnabled
		fx.slideIn(panel, "bottom", 0.5)
		input.disablePrompts("SequenceMinigame")
		input.captureMouse("SequenceMinigame")
		buildBoxes()
		playPreview(0.6)
	end

	local function press(action)
		if not self.active or watching then
			return
		end
		if action == pattern[progress + 1] then
			progress += 1
			local box = boxes[progress]
			box.KeyLabel.Text = keyLabel(action)
			box.BackgroundColor3 = BOX_RIGHT
			fx.pop(box)
			sounds.play("collect", 1 + progress * 0.08)
			if progress >= #pattern then
				phaseLabel.Text = "Unlocked!"
				ctx.remotes.NotebookMinigameAction:FireServer("done")
				close(false)
			end
		else
			-- LOUD. Sportage heard that. Watch it again...
			sounds.play("error", 0.6)
			phaseLabel.Text = "WRONG — he heard that!"
			ctx.remotes.NotebookMinigameAction:FireServer("noise")
			for _, box in ipairs(boxes) do
				box.KeyLabel.Text = "?"
				box.BackgroundColor3 = BOX_WRONG
			end
			fx.shake(row, 9)
			watching = true -- swallow input until the replay finishes
			local token = sessionToken
			task.delay(0.7, function()
				if token == sessionToken and self.active then
					for _, box in ipairs(boxes) do
						box.BackgroundColor3 = BOX_IDLE
					end
					playPreview(0)
				end
			end)
		end
	end

	input.onUse(function()
		if self.active then
			press("USE")
		end
	end)
	input.onSwap(function()
		if self.active then
			press("SWAP")
		end
	end)
	input.onCancel(function()
		if self.active then
			close(true)
		end
	end)
	giveUpButton.Activated:Connect(function()
		close(true)
	end)

	-- touch: tap buttons for the two symbols
	for buttonName, action in pairs({ UseTapButton = "USE", SwapTapButton = "SWAP" }) do
		local button = mobileTaps:FindFirstChild(buttonName)
		if button then
			local function relabel()
				local l = button:FindFirstChild("Label")
				if l then
					l.Text = keyLabel(action)
				end
			end
			relabel()
			input.onBindsChanged(relabel)
			button.Activated:Connect(function()
				press(action)
			end)
		end
	end

	RunService.RenderStepped:Connect(function()
		if not self.active then
			return
		end
		local character = ctx.player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - notebookPosition).Magnitude > cfg.CANCEL_DISTANCE then
			close(true)
		end
	end)

	ctx.remotes.NotebookMinigame.OnClientEvent:Connect(function(data)
		if data == nil then
			close(false)
		elseif typeof(data) == "table" and data.kind == "sequence" then
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

	return self
end

return SequenceMinigame
