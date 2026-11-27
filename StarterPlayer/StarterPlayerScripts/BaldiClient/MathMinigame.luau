--[[
	MathMinigame (ModuleScript, StarterPlayerScripts.BaldiClient.MathMinigame)

	Blue notebooks (StarterGui.MathMinigameGui): an arithmetic question with
	four answers in Panel.AnswerGrid (Answer1-4). Right answer collects the
	notebook; wrong flashes the buttons red and closes it (walk back and try
	again). The panel slides in from below.

	Shares the NotebookMinigame remote: payloads with kind = "math".
]]

local RunService = game:GetService("RunService")

local MathMinigame = {}

function MathMinigame.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local gui = fx.gui("MathMinigameGui")
	gui.Enabled = false
	local panel = gui:WaitForChild("Panel")
	local questionLabel = panel:WaitForChild("QuestionLabel")
	local grid = panel:WaitForChild("AnswerGrid")
	local giveUpButton = panel:WaitForChild("GiveUpButton")
	fx.origin(panel)

	local choiceButtons = {}
	for i = 1, 4 do
		choiceButtons[i] = grid:WaitForChild("Answer" .. i)
	end

	local function label(button)
		return button:FindFirstChild("Label")
	end

	local function paint(button, color, dimmed)
		fx.setButtonColor(button, color)
		button.ImageTransparency = dimmed and 0.55 or 0
		local l = label(button)
		if l then
			l.TextTransparency = dimmed and 0.45 or 0
		end
	end

	local notebookPosition = nil
	local pendingAnswer = false

	local function close(tellServer)
		if not self.active then
			return
		end
		self.active = false
		pendingAnswer = false
		gui.Enabled = false
		input.enablePrompts("MathMinigame")
		input.releaseMouse("MathMinigame")
		if tellServer then
			ctx.remotes.NotebookMinigameAction:FireServer("cancel")
		end
	end

	local function open(data)
		if typeof(data.position) ~= "Vector3" or typeof(data.question) ~= "string" or type(data.choices) ~= "table" then
			return
		end
		notebookPosition = data.position
		questionLabel.Text = data.question
		pendingAnswer = false
		local l = label(giveUpButton)
		if l then
			l.Text = "GIVE UP  [" .. input.getKeyName("CANCEL") .. "]"
		end
		for i, button in ipairs(choiceButtons) do
			local value = data.choices[i]
			local bl = label(button)
			if bl then
				bl.Text = value ~= nil and tostring(value) or ""
			end
			button.Visible = value ~= nil
			paint(button, "green", false)
		end
		self.active = true
		gui.Enabled = true
		fx.slideIn(panel, "bottom", 0.5)
		input.disablePrompts("MathMinigame")
		input.captureMouse("MathMinigame")
		sounds.play("click")
	end

	local function pickChoice(index)
		if not self.active or pendingAnswer then
			return
		end
		local l = label(choiceButtons[index])
		local value = l and tonumber(l.Text)
		if not value then
			return
		end
		pendingAnswer = true
		for i, button in ipairs(choiceButtons) do
			paint(button, "green", i ~= index)
		end
		ctx.remotes.NotebookMinigameAction:FireServer("math_answer", value)
	end

	for i, button in ipairs(choiceButtons) do
		button.Activated:Connect(function()
			pickChoice(i)
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

	-- walk-away abort
	RunService.RenderStepped:Connect(function()
		if not self.active then
			return
		end
		local character = ctx.player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local cancelDist = (ctx.config.MATH_MINIGAME and ctx.config.MATH_MINIGAME.CANCEL_DISTANCE) or 12
		if not hrp or (hrp.Position - notebookPosition).Magnitude > cancelDist then
			close(true)
		end
	end)

	ctx.remotes.NotebookMinigame.OnClientEvent:Connect(function(data)
		if data == nil then
			close(false)
		elseif typeof(data) == "table" and data.kind == "math" then
			open(data)
		elseif typeof(data) == "table" and data.kind == "math_wrong" and self.active then
			-- wrong answer: red flash + shake, then the server closes us
			sounds.play("error")
			for _, button in ipairs(choiceButtons) do
				paint(button, "red", false)
			end
			fx.shake(panel, 10)
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

return MathMinigame
