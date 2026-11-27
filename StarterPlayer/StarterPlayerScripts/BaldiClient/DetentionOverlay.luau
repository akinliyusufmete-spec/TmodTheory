--[[
	DetentionOverlay (ModuleScript, StarterPlayerScripts.BaldiClient.DetentionOverlay)

	Shown while LP has you in detention (StarterGui.DetentionGui). The server
	anchors your character; this shows Board.QuoteLabel + Board.CountdownLabel
	and locks the sprint key so the bar doesn't drain while you stand there.
]]

local DetentionOverlay = {}

function DetentionOverlay.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local stamina = ctx.controllers.StaminaController
	local self = {}

	local gui = fx.gui("DetentionGui")
	gui.Enabled = false
	local board = gui:WaitForChild("Board")
	local quoteLabel = board:WaitForChild("QuoteLabel")
	local countdownLabel = board:WaitForChild("CountdownLabel")

	local active = false
	local countdownToken = 0

	ctx.remotes.SendToDetention.OnClientEvent:Connect(function(seconds, byName)
		active = true
		countdownToken += 1
		local token = countdownToken
		quoteLabel.Text = '"No running in the halls." — ' .. (byName or "LP")
		gui.Enabled = true
		fx.pop(board)
		stamina.setSprintLocked(true)
		sounds.play("detention")

		local releaseAt = os.clock() + seconds
		task.spawn(function()
			while active and token == countdownToken and os.clock() < releaseAt do
				countdownLabel.Text = tostring(math.max(0, math.ceil(releaseAt - os.clock())))
				task.wait(0.1)
			end
		end)
	end)

	local function release()
		if not active then
			return
		end
		active = false
		gui.Enabled = false
		stamina.setSprintLocked(false)
	end

	ctx.remotes.DetentionReleased.OnClientEvent:Connect(release)
	ctx.remotes.RoundEnded.OnClientEvent:Connect(release)
	ctx.remotes.PlayerLost.OnClientEvent:Connect(release)
	ctx.remotes.PlayerWon.OnClientEvent:Connect(release)

	self.release = release
	return self
end

return DetentionOverlay
