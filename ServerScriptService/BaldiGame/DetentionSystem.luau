--[[
	DetentionSystem (ModuleScript, ServerScriptService.BaldiGame.DetentionSystem)

	LP's punishment: teleport the offender to the detention room, anchor them
	for DETENTION_SECONDS while the client shows the countdown overlay, then
	release with a short immunity window so LP can't instantly re-detain.
]]

local DetentionSystem = {}

function DetentionSystem.init(ctx)
	local self = {}
	local detained = {} -- [player] = { releaseAt = t }
	local immunityUntil = {} -- [player] = t

	local function release(player)
		local info = detained[player]
		if not info then
			return
		end
		detained[player] = nil
		immunityUntil[player] = os.clock() + ctx.config.NPC.LP.RELEASE_IMMUNITY_SECONDS

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
		end
		if player.Parent then
			ctx.remotes.DetentionReleased:FireClient(player)
		end
	end

	-- Detain the player. Duration escalates with how many times they've already
	-- been caught this round (DETENTION_SECONDS + prior * DETENTION_STEP), and
	-- the catch that reaches DETENTION_FORFEIT_AT ends the run instead.
	function self.detain(player, byName)
		if detained[player] then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end

		local lpCfg = ctx.config.NPC.LP
		local prior = (ctx.manager and ctx.manager.getDetentions and ctx.manager.getDetentions(player)) or 0

		-- the catch that hits the threshold forfeits the run
		if prior + 1 >= (lpCfg.DETENTION_FORFEIT_AT or 3) then
			if ctx.manager and ctx.manager.playerForfeit then
				ctx.manager.playerForfeit(player, byName or "LP",
					"Sent to detention " .. (prior + 1) .. " times — you're expelled!")
			end
			return
		end

		local seconds = (lpCfg.DETENTION_SECONDS or 12) + prior * (lpCfg.DETENTION_STEP or 3)

		local info = { releaseAt = os.clock() + seconds }
		detained[player] = info
		character:PivotTo(ctx.map.detentionCFrame)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.Anchored = true
		ctx.remotes.SendToDetention:FireClient(player, seconds, byName)
		if ctx.manager and ctx.manager.recordDetention then
			ctx.manager.recordDetention(player) -- report card blemish + escalation counter
		end

		task.delay(seconds, function()
			-- only end THIS detention: if the player was released early (round
			-- end, catch) and detained again since, the newer one keeps running
			if detained[player] == info then
				release(player)
			end
		end)
	end

	function self.isDetained(player)
		return detained[player] ~= nil
	end

	function self.hasImmunity(player)
		return (immunityUntil[player] or 0) > os.clock()
	end

	function self.releasePlayer(player)
		release(player)
	end

	function self.releaseAll()
		for player in pairs(detained) do
			release(player)
		end
	end

	function self.forget(player)
		detained[player] = nil
		immunityUntil[player] = nil
	end

	ctx.detention = self
	return self
end

return DetentionSystem
