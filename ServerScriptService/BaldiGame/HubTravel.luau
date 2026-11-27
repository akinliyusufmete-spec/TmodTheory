--[[
	HubTravel (ModuleScript, ServerScriptService.BaldiGame.HubTravel)

	Sends a player from the solo main game to the multiplayer HUB place, where
	they group up on room pads and launch into a match. Fired by the menu's
	MULTIPLAYER button (GoToHub remote).

	The main game stays 1 player and is never reserved; the actual match runs on
	a separate place the Hub reserves. So this is the only bridge from solo play
	into the multiplayer flow:  main game --GoToHub--> Hub --launch--> match.

	Teleports only exist on PUBLISHED servers — in Studio this no-ops (the menu
	already tells the player).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local HubTravel = {}

function HubTravel.init(ctx)
	local sending = {} -- [player] = true while a teleport is in flight

	ctx.remotes.GoToHub.OnServerEvent:Connect(function(player)
		if ctx.config.MULTIPLAYER_ENABLED == false then
			return -- multiplayer is switched off (GameConfig.MULTIPLAYER_ENABLED)
		end
		if RunService:IsStudio() then
			return -- no teleports in Studio
		end
		if sending[player] then
			return -- already on the way
		end
		local hubId = ctx.config.MATCH and ctx.config.MATCH.HUB_PLACE_ID
		if not hubId or hubId == 0 then
			return
		end
		-- never yank a player out of an active round
		if ctx.manager and ctx.manager.isParticipant and ctx.manager.isParticipant(player) then
			return
		end

		sending[player] = true
		task.spawn(function()
			local ok = pcall(function()
				TeleportService:TeleportAsync(hubId, { player })
			end)
			if not ok then
				sending[player] = nil -- failed: let them try again
			end
		end)
	end)

	-- TeleportAsync can "succeed" and still fail later; let them retry then
	TeleportService.TeleportInitFailed:Connect(function(player)
		sending[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		sending[player] = nil
	end)

	return {}
end

return HubTravel
