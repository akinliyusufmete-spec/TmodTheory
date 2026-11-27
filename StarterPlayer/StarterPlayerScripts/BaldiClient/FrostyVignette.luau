--[[
	FrostyVignette (ModuleScript, StarterPlayerScripts.BaldiClient.FrostyVignette)

	Receives Frosty's SpeedDebuff remote (his SlowMachiner 3000): tells
	StaminaController to apply the WalkSpeed multiplier and shows
	StarterGui.FrostGui (icy edges + StatusLabel) until the frost wears off.
	The server can send the StatusLabel text along; without it the label
	picks a line by how strong the slow is. A spell opens with a flashbang;
	a refresh while it's showing doesn't re-flash.
]]

local FrostyVignette = {}

function FrostyVignette.init(ctx)
	local fx = ctx.controllers.UiFx
	local stamina = ctx.controllers.StaminaController
	local sounds = ctx.controllers.SoundController
	local self = {}

	local gui = fx.gui("FrostGui")
	gui.Enabled = false
	local statusLabel = gui:WaitForChild("StatusLabel")
	local designedText = statusLabel.Text -- your text for the mild tier

	local expiresAt = 0

	ctx.remotes.SpeedDebuff.OnClientEvent:Connect(function(duration, multiplier, label)
		stamina.applyDebuff(multiplier, duration)
		expiresAt = os.clock() + duration
		if not gui.Enabled then
			fx.flashbang()
			gui.Enabled = true
			sounds.play("frost")
		end
		if type(label) == "string" and label ~= "" then
			statusLabel.Text = label
		elseif multiplier <= 0 then
			statusLabel.Text = "Frozen solid!"
		elseif multiplier <= 0.35 then
			statusLabel.Text = "Deeply chilled..."
		else
			statusLabel.Text = designedText
		end
		task.delay(duration, function()
			if os.clock() >= expiresAt then
				gui.Enabled = false
			end
		end)
	end)

	local function clear()
		expiresAt = 0
		gui.Enabled = false
	end
	ctx.remotes.RoundEnded.OnClientEvent:Connect(clear)
	ctx.remotes.PlayerLost.OnClientEvent:Connect(clear)
	ctx.remotes.PlayerWon.OnClientEvent:Connect(clear)

	return self
end

return FrostyVignette
