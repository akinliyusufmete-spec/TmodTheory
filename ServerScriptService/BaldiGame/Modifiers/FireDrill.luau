--[[
	FireDrill (ModuleScript, ServerScriptService.BaldiGame.Modifiers.FireDrill)

	Server side of the Fire Drill modifier: the run has SECONDS to escape.

	The deadline goes out as workspace.FireDrillEndsAt (server time, from
	workspace:GetServerTimeNow()), so every client — including one that joins
	mid-run — counts down to the same moment. It is set in onActive, not
	start: start runs at the countdown, and the clock should start with the
	run itself.

	At 0:00 every remaining participant's run is forfeited. stop cancels the
	watcher and clears the attribute. The siren, red lights and shake are
	client-side (BaldiClient/Modifiers/FireDrill).
]]

local Players = game:GetService("Players")

local FireDrill = {}

local ATTRIBUTE = "FireDrillEndsAt"

local watchToken = nil -- a fresh table per run; a stale timer sees it changed

function FireDrill.onActive(env)
	local ctx = env.ctx
	local seconds = env.def.SECONDS
	local token = {}
	watchToken = token
	workspace:SetAttribute(ATTRIBUTE, workspace:GetServerTimeNow() + seconds)

	task.delay(seconds, function()
		if watchToken ~= token then
			return -- the run ended (or a new one started) before time ran out
		end
		local manager = ctx.manager
		if not manager then
			return
		end
		-- collect first: each forfeit can end the round and change the set
		local remaining = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if manager.isParticipant(player) then
				table.insert(remaining, player)
			end
		end
		for _, player in ipairs(remaining) do
			-- playerForfeit ignores anyone who already left the run; pcall so
			-- one failed forfeit can't spare everyone after it
			local ok, err = pcall(manager.playerForfeit, player, "Fire Drill", "Time's up — you didn't get out in time.")
			if not ok then
				warn("[Tmod] Fire Drill forfeit failed: " .. tostring(err))
			end
		end
	end)
end

function FireDrill.stop()
	watchToken = nil
	workspace:SetAttribute(ATTRIBUTE, nil)
end

return FireDrill
