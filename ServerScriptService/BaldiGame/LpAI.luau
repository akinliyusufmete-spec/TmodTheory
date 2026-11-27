--[[
	LpAI (ModuleScript, ServerScriptService.BaldiGame.LpAI)

	The patrolling principal — hunts on presence, not on speeding.
	  - Wanders the halls between waypoints, ignoring nobody in particular.
	  - Chases the moment he NOTICES a player: line of sight within SIGHT_RANGE,
	    or anyone who strays within DETECT_RADIUS even out of sight.
	  - Once chasing he continuously re-paths to your live position (he follows
	    you through doorways) and only loses interest after MEMORY_SECONDS of
	    noticing nothing. A sprint (32) still outruns his CHASE_SPEED, so the
	    escape is to put distance + a wall between you.
	  - On catch: hands the player to DetentionSystem (teleport + lock), then
	    goes straight back to wandering. Detention escalates each time and the
	    DETENTION_FORFEIT_AT-th catch ends the run.

	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/LP
	Alert sound: AssetConfig.SOUNDS.whistle (else a built-in ping)
]]

local RunService = game:GetService("RunService")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))

local LpAI = {}

local COLOR_BODY = Color3.fromRGB(35, 50, 120)
local COLOR_HEAD = Color3.fromRGB(225, 200, 170)

function LpAI.init(ctx)
	local cfg = ctx.config.NPC.LP
	local self = { ctx = ctx, cfg = cfg }

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(120, 150, 255),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.LP,
		(cfg.ROAM_SPEED + cfg.CHASE_SPEED) / 2)
	self.base = base
	self.model = model

	local whistle = SoundLoader.attach(base.root, "Whistle", {
		Id = base.character.Sounds.Whistle,
		Asset = "whistle",
		Fallback = "rbxasset://sounds/electronicpingshort.wav",
		FallbackSpeed = 0.6,
		Volume = 0.9,
		RollOffMaxDistance = 80,
	})

	-- ---------- helpers ----------

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	-- The one rule LP enforces: no running. True when the player is actually
	-- moving faster than a walk (horizontal speed only, so jumps/falls and a
	-- Frosty-chilled "sprint" that's been slowed under the bar don't count).
	local function isBreakingRule(hrp)
		if not hrp then
			return false
		end
		local velocity = hrp.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		return flatSpeed > cfg.RUN_DETECT_SPEED
	end

	-- True when LP can perceive this player: line of sight within SIGHT_RANGE,
	-- OR simply too close (within DETECT_RADIUS) to miss. Perception alone does
	-- NOT flag anyone — only a rule-breaker who is also perceived gets chased.
	local function detects(hrp)
		if not hrp then
			return false
		end
		local distance = (hrp.Position - base.root.Position).Magnitude
		if distance <= cfg.DETECT_RADIUS then
			return true
		end
		return distance <= cfg.SIGHT_RANGE and base:canSee(hrp, cfg.SIGHT_RANGE)
	end

	-- the player LP is currently locked onto (flagged for running). Once
	-- flagged he detains on catch even if they stop — but a walker who never
	-- got flagged is never detained.
	local activeTarget = nil

	local lastScan = 0
	local cachedTarget = nil

	-- nearest player LP currently notices (throttled scan), skipping anyone
	-- detained or briefly immune after a release
	local function findTarget()
		if os.clock() - lastScan < cfg.SIGHT_INTERVAL then
			return cachedTarget
		end
		lastScan = os.clock()
		cachedTarget = nil
		if not ctx.manager then
			return nil
		end
		local bestDistance = math.huge
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			if not ctx.detention.hasImmunity(player) and not ctx.detention.isDetained(player) then
				local hrp = targetRoot(player)
				-- flag only RUNNERS LP can perceive; walkers are invisible to him
				if isBreakingRule(hrp) and detects(hrp) then
					local distance = (hrp.Position - base.root.Position).Magnitude
					if distance < bestDistance then
						bestDistance = distance
						cachedTarget = player
					end
				end
			end
		end
		return cachedTarget
	end

	-- ---------- chase ----------

	local function chase(player)
		local lastSeenAt = os.clock()
		local lastKnown = nil
		activeTarget = player -- flagged: LP will detain on catch even if they stop
		pcall(function()
			whistle:Play()
		end)
		base:beginChase(player) -- "Spotted"
		base:playAction("Rulebreak") -- over his walk until the chase ends (caught or lost)

		base:pursue(
			function()
				if not ctx.manager.isRoundActive() then
					return nil
				end
				local hrp = targetRoot(player)
				if not hrp or not ctx.manager.isTargetable(player) or ctx.detention.isDetained(player) then
					return nil
				end
				-- keep coming while LP still notices them (sight or proximity);
				-- losing both for MEMORY_SECONDS calms him back to wandering
				if detects(hrp) then
					lastSeenAt = os.clock()
					lastKnown = hrp.Position
					return lastKnown
				end
				if os.clock() - lastSeenAt > cfg.MEMORY_SECONDS then
					return nil
				end
				if lastKnown and (lastKnown - base.root.Position).Magnitude < 4 then
					return nil
				end
				return lastKnown
			end,
			function()
				return cfg.CHASE_SPEED
			end
		)
		base:endAction("Rulebreak")
		base:endChase() -- "Lost", if they actually got away
		activeTarget = nil -- gave up (or caught them): no longer flagged
	end

	-- ---------- main brain loop: wander, chase on detect, back to wandering ----------

	task.spawn(function()
		while true do
			if not base:canAct() then
				task.wait(0.2)
			else
				local target = findTarget()
				if target then
					chase(target)
				else
					base:roamStep(cfg.ROAM_SPEED, function()
						return findTarget() ~= nil
					end)
				end
			end
		end
	end)

	-- ---------- catch check: detention, not game over ----------

	RunService.Heartbeat:Connect(function()
		if not base:isActive() or not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		local silver = ctx.npcs.Silver
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			if not ctx.detention.hasImmunity(player)
				and not ctx.detention.isDetained(player)
				and not (silver and silver.isGrabbing(player)) then -- Silver's victim is Silver's
				local hrp = targetRoot(player)
				-- only detain a rule-breaker: the player LP flagged for running
				-- (and is actively chasing), or anyone caught running right now.
				-- A walker who merely bumps into LP is let off.
				if hrp and (hrp.Position - base.root.Position).Magnitude < cfg.CATCH_DISTANCE
					and (player == activeTarget or isBreakingRule(hrp)) then
					base:say("Caught", { target = player, force = true })
					ctx.detention.detain(player, cfg.NAME)
				end
			end
		end
	end)

	function self.reset()
		base:resetToSpawn()
	end

	ctx.npcs.LP = self
	return self
end

return LpAI
