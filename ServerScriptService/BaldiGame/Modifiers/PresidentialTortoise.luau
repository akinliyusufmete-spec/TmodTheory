--[[
	PresidentialTortoise (ModuleScript, ServerScriptService.BaldiGame.Modifiers.PresidentialTortoise)

	Server side of the Presidential Tortoise modifier. The crawl (every NPC
	and player slowed, players speeding up per notebook) is already in
	ModifierService's speed multipliers; this file only runs the turtle.

	  start     build the turtle once (TortoiseAI), then place it at the NPC
	            spawn farthest from the starting player, frozen
	  onActive  it starts crawling after the nearest targetable participant
	  notebook  its WalkSpeed = TURTLE_SPEED * TURTLE_NOTEBOOK_MULT ^ notebooks
	  catch     within TURTLE_CATCH_DISTANCE: CatchSound, then that player's
	            run is forfeited
	  stop      the turtle is parked (reused next run, never destroyed)

	The turtle is not in ctx.npcs, so BSODA, punches, Toji's glass and round
	resets never touch it (see TortoiseAI).

	Asset: BaldiAssets.Modifiers.PresidentialTortoise.CatchSound (Sound)
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local TortoiseAI = require(script.Parent.Parent.TortoiseAI)

local PresidentialTortoise = {}

local turtle = nil -- built on the first run, reused after
local speed = 0 -- the turtle's current WalkSpeed

local function turtleSpeed(env)
	local def = env.def
	return def.TURTLE_SPEED * def.TURTLE_NOTEBOOK_MULT ^ env.service.notebooks()
end

-- where the run's players stand right now (at the round spawn during the
-- countdown); the map's round spawn if nobody has a character yet
local function startingPosition(ctx)
	local manager = ctx.manager
	for _, player in ipairs(Players:GetPlayers()) do
		if manager and manager.isParticipant(player) then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				return hrp.Position
			end
		end
	end
	local spawnCFrame = ctx.map and ctx.map.roundSpawnCFrame
	return spawnCFrame and spawnCFrame.Position or nil
end

local function farthestSpawn(ctx)
	local spawns = ctx.map and ctx.map.npcSpawns
	if not spawns then
		return nil
	end
	local from = startingPosition(ctx)
	local best, bestDistance = nil, -1
	for _, spawnCFrame in pairs(spawns) do
		if typeof(spawnCFrame) == "CFrame" then
			local distance = from and (spawnCFrame.Position - from).Magnitude or 0
			if distance > bestDistance then
				best, bestDistance = spawnCFrame, distance
			end
		end
	end
	return best
end

local function playCatchSound(env, player)
	local template = env.assets.find("PresidentialTortoise", "CatchSound")
	if not template or not template:IsA("Sound") then
		return
	end
	-- on the caught player's own root: the forfeit teleports them to the
	-- lobby right after, and the sound travels with them so they hear it
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local parent = hrp or (turtle and turtle.base.root)
	if not parent then
		return
	end
	local sound = template:Clone()
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 1)
end

function PresidentialTortoise.start(env)
	local ctx = env.ctx
	speed = turtleSpeed(env)
	if not turtle then
		turtle = TortoiseAI.new(ctx, {
			catchDistance = env.def.TURTLE_CATCH_DISTANCE,
			repath = env.def.TURTLE_REPATH,
		})
	end
	turtle.place(farthestSpawn(ctx))
end

function PresidentialTortoise.onActive(env)
	if not turtle then
		return
	end
	local ctx = env.ctx
	speed = turtleSpeed(env)
	turtle.run(function()
		return speed
	end, function(player)
		local manager = ctx.manager
		if not manager or not manager.isParticipant(player) then
			return
		end
		playCatchSound(env, player)
		manager.playerForfeit(player, "Presidential Tortoise", "The Presidential Tortoise caught you.")
	end)
end

function PresidentialTortoise.onNotebookCollected(env)
	speed = turtleSpeed(env) -- travel() reads it on its next tick
end

function PresidentialTortoise.stop()
	if turtle then
		turtle.halt()
	end
	speed = 0
end

return PresidentialTortoise
