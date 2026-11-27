--[[
	TortoiseAI (ModuleScript, ServerScriptService.BaldiGame.TortoiseAI)

	The Presidential Tortoise modifier's turtle (driven by
	BaldiGame/Modifiers/PresidentialTortoise). It crawls after the nearest
	targetable participant for the whole run and ends the run of anyone it
	touches.

	Deliberately NOT registered in ctx.npcs: everything that affects "the
	characters" (BSODA, Grand Bully punches, Toji's glass, mode rosters, round
	resets, modifier speed refreshes) iterates ctx.npcs, so the turtle is
	immune to all of it by construction. Its NpcBase is also created with
	ignoreModifiers, so its WalkSpeed is exactly what the feature asks for.

	One rig is built lazily on the first run and reused: between runs it is
	parked (anchored far above its spawn), never destroyed, so no thread or
	connection is ever left pointing at a dead model.

	  TortoiseAI.new(ctx) -> turtle
	  turtle.place(spawnCFrame)            into the active map, at the spawn, frozen
	  turtle.run(getSpeed, onCatch)        start chasing (getSpeed() read every tick;
	                                       onCatch(player) when it touches someone)
	  turtle.halt()                        stop chasing and park out of play

	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/Tortoise (else the placeholder)
	Look / voicelines: CharacterConfig.Tortoise
]]

local RunService = game:GetService("RunService")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)

local TortoiseAI = {}

local NAME = "Tortoise"
local COLOR_BODY = Color3.fromRGB(70, 120, 60)
local COLOR_HEAD = Color3.fromRGB(150, 190, 110)

-- the catch distance comes from the feature; this is only a safety default
local DEFAULT_CATCH_DISTANCE = 3

function TortoiseAI.new(ctx, opts)
	opts = opts or {}
	local self = {}
	local catchDistance = opts.catchDistance or DEFAULT_CATCH_DISTANCE
	local repath = opts.repath

	local model = NpcFactory.create({
		name = NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(150, 230, 130),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.roundSpawnCFrame or model:GetPivot(), nil, { ignoreModifiers = true })
	-- in case this NpcBase predates the opts argument: the field is what it reads
	base.ignoreModifiers = true
	self.base = base
	self.model = model

	local runToken = nil -- a fresh table per run(); every loop checks it
	local catchConn = nil

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	-- nearest targetable participant's root (the turtle has no sight rules:
	-- it always knows where you are)
	local function nearestRoot()
		local manager = ctx.manager
		if not manager then
			return nil
		end
		local best, bestDistance = nil, math.huge
		for _, player in ipairs(manager.getTargetablePlayers()) do
			local hrp = targetRoot(player)
			if hrp then
				local distance = (hrp.Position - base.root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = hrp, distance
				end
			end
		end
		return best
	end

	-- Move into the active map (ctx.map can swap between rounds) at
	-- spawnCFrame, frozen until run().
	function self.place(spawnCFrame)
		self.halt()
		local map = ctx.map
		if map and map.npcFolder and model.Parent ~= map.npcFolder then
			model.Parent = map.npcFolder
		end
		if map then
			base:setMapExcludes(map)
		end
		if spawnCFrame then
			base.spawnCFrame = spawnCFrame
		end
		base:unpark() -- unanchors, then resetToSpawn (which leaves it paused)
	end

	function self.run(getSpeed, onCatch)
		local token = {}
		runToken = token
		base:setPaused(false)

		-- brain: pursue whoever is nearest, re-picked on every goal read
		task.spawn(function()
			while runToken == token do
				if not base:canAct() then
					task.wait(0.2)
				elseif not nearestRoot() then
					base:stop()
					task.wait(0.25)
				else
					base:pursue(
						function()
							if runToken ~= token or not ctx.manager or not ctx.manager.isRoundActive() then
								return nil
							end
							local hrp = nearestRoot()
							return hrp and hrp.Position or nil
						end,
						getSpeed,
						nil,
						repath and function()
							return repath
						end or nil
					)
					if runToken == token then
						task.wait(0.1) -- pursue ended (nobody to chase / stunned): breathe before retrying
					end
				end
			end
		end)

		-- catch check every frame (the turtle is slow, so a coarse check could
		-- let a sprinting player clip through its radius)
		if catchConn then
			catchConn:Disconnect()
		end
		catchConn = RunService.Heartbeat:Connect(function()
			if runToken ~= token or base.parked or not model.Parent then
				return
			end
			local manager = ctx.manager
			if not manager or not manager.isRoundActive() then
				return
			end
			for _, player in ipairs(manager.getTargetablePlayers()) do
				local hrp = targetRoot(player)
				if hrp and (hrp.Position - base.root.Position).Magnitude <= catchDistance then
					base:say("Caught", { target = player, force = true })
					onCatch(player)
					-- the catch may have ended the round (and halted us)
					if runToken ~= token then
						return
					end
				end
			end
		end)
	end

	function self.halt()
		runToken = nil
		if catchConn then
			catchConn:Disconnect()
			catchConn = nil
		end
		if not base.parked then
			base:park() -- pauses (stopping any travel) and freezes it out of play
		end
	end

	return self
end

return TortoiseAI
