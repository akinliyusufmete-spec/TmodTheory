--[[
	BeansGumClient (ModuleScript, StarterPlayerScripts.BaldiClient.BeansGumClient)

	Reacts to Beans' gum (MULTIPLAYER). When a wad sticks to you (BeansGum) you
	are slowed for the duration and StarterGui.BeansGumGui shows (opened with a
	flashbang). With Safety Scissors you can cut free early: SWAP on PC, the
	CutFreeButton on touch. It does NOT lock your movement.

	The slow lifts after the duration, on BeansUngum (you snipped it), or when
	the round ends. Tuning lives in GameConfig.NPC.BEANS.
]]

local RunService = game:GetService("RunService")

local BeansGumClient = {}

function BeansGumClient.init(ctx)
	local fx = ctx.controllers.UiFx
	local cfg = ctx.config.NPC.BEANS
	local sounds = ctx.controllers.SoundController
	local stamina = ctx.controllers.StaminaController
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local gui = fx.gui("BeansGumGui")
	gui.Enabled = false
	local sub = gui:WaitForChild("Panel"):WaitForChild("SubLabel")
	local cutButton = gui:WaitForChild("CutFreeButton")
	local designedSub = sub.Text -- your text when there's nothing to cut with

	-- On short screens (phones in landscape) the Panel stops shrinking at its
	-- UISizeConstraint MinSize, so its bottom edge would run into the button.
	-- The button keeps its designed spot, pushed down just enough to clear it.
	local panel = sub.Parent
	local designedCutPos = cutButton.Position
	local CUT_GAP = 0.015 -- the designed gap, as a share of screen height
	local function placeCutButton()
		local screenHeight = gui.AbsoluteSize.Y
		if screenHeight <= 0 then
			return
		end
		local panelBottom = panel.AbsolutePosition.Y - gui.AbsolutePosition.Y + panel.AbsoluteSize.Y
		local designedTop = designedCutPos.Y.Scale * screenHeight + designedCutPos.Y.Offset
		local clearTop = panelBottom + math.max(6, screenHeight * CUT_GAP)
		local push = math.max(0, math.ceil(clearTop - designedTop))
		cutButton.Position = designedCutPos + UDim2.fromOffset(0, push)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCutButton)
	panel:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeCutButton)
	placeCutButton()

	local function hasScissors()
		local items = ctx.controllers.ItemUseClient
		return items ~= nil and (items.slots[1] == "SCISSORS" or items.slots[2] == "SCISSORS")
	end

	local function snip()
		if self.active and hasScissors() then
			ctx.remotes.BeansSnip:FireServer()
		end
	end
	cutButton.Activated:Connect(snip)
	input.onSwap(function()
		if self.active then
			snip()
		end
	end)

	local function refresh()
		local has = hasScissors()
		cutButton.Visible = has and input.touchEnabled
		if has and not input.touchEnabled then
			sub.Text = "Slog on, or [" .. input.getKeyName("SWAP") .. "] to cut free"
		elseif has then
			sub.Text = "Tap CUT FREE to snip loose"
		else
			sub.Text = designedSub
		end
	end

	-- keep the gum slow dominant + refreshed while it holds
	RunService.RenderStepped:Connect(function()
		if self.active then
			stamina.applyDebuff(cfg.GUM_SLOW, 0.25)
		end
	end)

	local hideAt = 0
	local function close()
		if not self.active then
			return
		end
		self.active = false
		gui.Enabled = false
	end

	ctx.remotes.BeansGum.OnClientEvent:Connect(function(duration)
		duration = tonumber(duration) or cfg.GUM_DURATION
		if not self.active then
			fx.flashbang()
		end
		self.active = true
		gui.Enabled = true
		hideAt = os.clock() + duration
		refresh()
		placeCutButton()
		sounds.play("frost") -- a wet squelch stand-in until you add a gum sound
		task.delay(duration, function()
			if os.clock() >= hideAt - 0.05 then
				close()
			end
		end)
	end)

	ctx.remotes.BeansUngum.OnClientEvent:Connect(function()
		if self.active then
			sounds.play("buy", 1.4)
		end
		close()
		stamina.applyDebuff(1, 0) -- clear the slow immediately
	end)

	ctx.remotes.RoundEnded.OnClientEvent:Connect(close)
	ctx.remotes.PlayerLost.OnClientEvent:Connect(close)
	ctx.remotes.PlayerWon.OnClientEvent:Connect(close)

	ctx.remotes.InventoryChanged.OnClientEvent:Connect(function()
		if self.active then
			refresh()
		end
	end)

	self.close = close
	return self
end

return BeansGumClient
