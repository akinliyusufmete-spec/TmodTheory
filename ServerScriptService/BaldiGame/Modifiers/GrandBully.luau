--[[
	GrandBully (ModuleScript, ServerScriptService.BaldiGame.Modifiers.GrandBully)

	Server side of the Grand Bully modifier: players can punch characters.
	ChatRevive's extra speed is already in ModifierService.

	The client (BaldiClient/Modifiers/GrandBully) plays the punch animation and
	sound and fires ModifierPunch with no arguments; everything that matters is
	decided here, so a client can't punch from across the map or spam it:
	  - only while Grand Bully is on, the round is live and the puncher is a
	    participant, at most once per COOLDOWN seconds
	  - the target is the nearest un-parked character in ctx.npcs within RANGE
	    studs AND inside a CONE_DEGREES-wide cone around where the player's
	    root faces (flat, so looking up or down doesn't matter)
	  - it is stunned for STUN_SECONDS and shoved away from the player
	  - LP sees everything: every landed punch sends him after the puncher for
	    LP_ALERT_SECONDS (even when LP is the one punched)
	The Presidential Tortoise's turtle isn't in ctx.npcs, so it can't be punched.
]]

local Players = game:GetService("Players")

local GrandBully = {}

local lastPunch = {} -- [player] = os.clock() of their last accepted punch
local connected = false

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function onPunch(env, player)
	local ctx = env.ctx
	local def = env.def
	local manager = ctx.manager
	if not env.service.has("GrandBully") then
		return
	end
	if not manager or not manager.isRoundActive() or not manager.isParticipant(player) then
		return
	end
	local now = os.clock()
	local last = lastPunch[player]
	if last and now - last < def.COOLDOWN then
		return
	end
	lastPunch[player] = now -- a miss still spends the cooldown

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local facing = flat(hrp.CFrame.LookVector)
	if facing.Magnitude < 0.01 then
		return
	end
	facing = facing.Unit
	local minDot = math.cos(math.rad(def.CONE_DEGREES / 2))

	local target, targetDistance, targetDirection = nil, math.huge, nil
	for _, npc in pairs(ctx.npcs) do
		local base = npc.base
		if base and not base.parked and base.model.Parent then
			local delta = base.root.Position - hrp.Position
			local distance = delta.Magnitude
			if distance <= def.RANGE and distance < targetDistance then
				local flatDelta = flat(delta)
				-- standing right on top of it counts as in front
				local inCone = flatDelta.Magnitude < 0.01 or flatDelta.Unit:Dot(facing) >= minDot
				if inCone then
					target = npc
					targetDistance = distance
					targetDirection = flatDelta.Magnitude >= 0.01 and flatDelta.Unit or facing
				end
			end
		end
	end
	if not target then
		return
	end

	target.base:stun(def.STUN_SECONDS, targetDirection)

	local lp = ctx.npcs.LP
	if lp and type(lp.alertTo) == "function" then
		lp.alertTo(player, def.LP_ALERT_SECONDS)
	end
end

function GrandBully.init(env)
	if connected then
		return
	end
	local remote = env.ctx.remotes and env.ctx.remotes.ModifierPunch
	if not remote then
		warn("[Tmod] Grand Bully: remote ModifierPunch is missing (add it to GameConfig.REMOTE_NAMES) — punches are off.")
		return
	end
	connected = true
	remote.OnServerEvent:Connect(function(player)
		local ok, err = pcall(onPunch, env, player)
		if not ok then
			warn("[Tmod] Grand Bully punch failed: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPunch[player] = nil
	end)
end

function GrandBully.stop()
	lastPunch = {}
end

return GrandBully
