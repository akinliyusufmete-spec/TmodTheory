--[[
	SportageAI (ModuleScript, ServerScriptService.BaldiGame.SportageAI)

	The Impersonator-mode hunter. He replaced ChatRevive — and the rules.
	  - NOT omniscient: he hunts with his EYES (SIGHT_RANGE chase, with
	    memory) and his EARS.
	  - TRAPS: at round start he scatters TRAPS_AT_START snares around the
	    school, and lays fresh ones while he patrols. Stepping on one roots
	    you for TRAP_HOLD_SECONDS — and he knows exactly where you are.
	  - NOISES: failing his sequence lock (see NotebookSpawner) or springing
	    a trap gives him your position for HEARING_BURST seconds.
	  - Enrages after the final notebook, like the boss he replaced.

	Active only in Impersonator mode; parked otherwise (GameConfig.MODES).
	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/Sportage
	Custom trap: ReplicatedStorage/BaldiAssets/Items/SportageTrap
]]

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))
local AssetResolver = require(script.Parent.AssetResolver)

local SportageAI = {}

local COLOR_BODY = Color3.fromRGB(40, 40, 45)
local COLOR_HEAD = Color3.fromRGB(235, 130, 30)

function SportageAI.init(ctx)
	local cfg = ctx.config.NPC.SPORTAGE
	local self = { ctx = ctx, cfg = cfg, enraged = false }

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(255, 160, 60),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.SPORTAGE,
		(cfg.ROAM_SPEED + cfg.CHASE_SPEED) / 2)
	self.base = base
	self.model = model

	-- ---------- hearing ----------

	local heardAt = nil
	local heardUntil = 0

	-- Something loud happened at `position` — he investigates.
	function self.hear(position, seconds)
		heardAt = position
		heardUntil = os.clock() + (seconds or cfg.HEARING_BURST)
	end

	-- ---------- traps ----------

	local traps = {} -- [part] = true
	local trappedUntil = {} -- [player] = release time
	local trapImmuneUntil = {} -- [player] = next time they can be trapped
	local trapsSeeded = false

	function self.isTrapped(player)
		return (trappedUntil[player] or 0) > os.clock()
	end

	local function makeTrapPart(position)
		local template = AssetResolver.itemTemplate("SportageTrap")
		local trap
		if template then
			trap = AssetResolver.preparePropClone(template)
			trap:PivotTo(CFrame.new(position + Vector3.new(0, 0.3, 0)))
		else
			trap = Instance.new("Part")
			trap.Name = "SportageTrap"
			trap.Shape = Enum.PartType.Cylinder
			trap.Size = Vector3.new(0.35, 6, 6)
			trap.CFrame = CFrame.new(position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
			trap.Color = Color3.fromRGB(30, 30, 32)
			trap.Material = Enum.Material.Metal
			trap.Transparency = 1 - (cfg.TRAP_VISIBILITY or 0.45)
			trap.Anchored = true
			trap.CanCollide = false
		end
		trap:SetAttribute("SportageTrap", true)
		trap.Parent = ctx.map.pickupsFolder
		return trap
	end

	local function clearTraps()
		for trap in pairs(traps) do
			if trap.Parent then
				trap:Destroy()
			end
		end
		traps = {}
	end

	local function activeTrapCount()
		local count = 0
		for trap in pairs(traps) do
			if trap.Parent then
				count = count + 1
			else
				traps[trap] = nil
			end
		end
		return count
	end

	local function layTrap(position)
		if activeTrapCount() >= cfg.MAX_TRAPS then
			return
		end
		traps[makeTrapPart(position)] = true
	end

	-- scatter the round's starting snares on waypoints away from players
	local function seedTraps()
		local nodes = {}
		for _, node in ipairs(ctx.map.waypointsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(nodes, node.Position)
			end
		end
		local rng = Random.new()
		for i = #nodes, 2, -1 do
			local j = rng:NextInteger(1, i)
			nodes[i], nodes[j] = nodes[j], nodes[i]
		end
		local placed = 0
		for _, position in ipairs(nodes) do
			if placed >= cfg.TRAPS_AT_START then
				break
			end
			local nearPlayer = false
			for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - position).Magnitude < 25 then
					nearPlayer = true
					break
				end
			end
			if not nearPlayer then
				layTrap(position)
				placed = placed + 1
			end
		end
	end

	local function springTrap(trap, player, hrp)
		traps[trap] = nil
		local position = trap:GetPivot().Position
		trap:Destroy()

		trappedUntil[player] = os.clock() + cfg.TRAP_HOLD_SECONDS
		trapImmuneUntil[player] = os.clock() + cfg.TRAP_HOLD_SECONDS + cfg.TRAP_IMMUNITY
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.Anchored = true

		SoundLoader.playAt(hrp, {
			Id = base.character.Sounds.Trap,
			Fallback = "rbxasset://sounds/snap.mp3",
			FallbackSpeed = 0.6,
			Volume = 1,
			RollOffMaxDistance = 120,
		})

		ctx.remotes.PickupFailed:FireClient(player, "A trap! Sportage knows where you are!")
		base:say("Trap", { target = player, force = true })
		self.hear(position, cfg.HEARING_BURST)

		task.delay(cfg.TRAP_HOLD_SECONDS, function()
			trappedUntil[player] = nil
			local character = player.Character
			local nowHrp = character and character:FindFirstChild("HumanoidRootPart")
			local silver = ctx.npcs.Silver
			if nowHrp and ctx.manager.isParticipant(player)
				and not ctx.detention.isDetained(player)
				and not (silver and silver.isGrabbing and silver.isGrabbing(player)) then
				nowHrp.Anchored = false
			end
		end)
	end

	-- trap trigger scan
	RunService.Heartbeat:Connect(function()
		if base.parked or not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		for trap in pairs(traps) do
			if trap.Parent then
				local trapPosition = trap:GetPivot().Position
				for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
					if (trapImmuneUntil[player] or 0) <= os.clock() and not self.isTrapped(player) then
						local character = player.Character
						local hrp = character and character:FindFirstChild("HumanoidRootPart")
						if hrp and not hrp.Anchored
							and (hrp.Position - trapPosition).Magnitude < cfg.TRAP_RADIUS then
							springTrap(trap, player, hrp)
							break
						end
					end
				end
			end
		end
	end)

	-- ---------- hunting ----------

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	local lastScan = 0
	local cachedTarget = nil

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
			local hrp = targetRoot(player)
			if hrp then
				local distance = (hrp.Position - base.root.Position).Magnitude
				if distance < bestDistance and base:canSee(hrp, cfg.SIGHT_RANGE) then
					bestDistance = distance
					cachedTarget = player
				end
			end
		end
		return cachedTarget
	end

	local function chaseSpeed()
		return self.enraged and cfg.ENRAGED_CHASE_SPEED or cfg.CHASE_SPEED
	end

	local function chase(player)
		local lastSeenAt = os.clock()
		local lastKnown = nil
		base:beginChase(player) -- "Spotted"
		base:pursue(
			function()
				if not ctx.manager.isRoundActive() then
					return nil
				end
				local hrp = targetRoot(player)
				if not hrp or not ctx.manager.isTargetable(player) then
					return nil
				end
				if base:canSee(hrp, cfg.SIGHT_RANGE) then
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
			chaseSpeed
		)
		base:endChase() -- "Lost", if they actually got away
	end

	local function investigate()
		base:pursue(
			function()
				if os.clock() >= heardUntil or not heardAt then
					return nil
				end
				if findTarget() then
					return nil -- eyes beat ears
				end
				if (heardAt - base.root.Position).Magnitude < 5 then
					return nil -- arrived; have a look around
				end
				return heardAt
			end,
			chaseSpeed
		)
	end

	-- ---------- brain ----------

	local nextTrapAt = 0

	task.spawn(function()
		while true do
			if base.parked or not base:canAct() then
				task.wait(0.25)
			else
				if not trapsSeeded then
					trapsSeeded = true
					seedTraps()
				end
				local target = findTarget()
				if target then
					chase(target)
				elseif os.clock() < heardUntil then
					investigate()
				else
					base:roamStep(cfg.ROAM_SPEED, function()
						return findTarget() ~= nil or os.clock() < heardUntil
					end)
					-- lay a fresh snare where he stopped, now and then
					if os.clock() >= nextTrapAt then
						nextTrapAt = os.clock() + cfg.TRAP_RESTOCK
						layTrap(base.root.Position)
					end
				end
			end
		end
	end)

	-- ---------- catch ----------

	RunService.Heartbeat:Connect(function()
		if base.parked or not base:isActive() or not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			local hrp = targetRoot(player)
			if hrp and (hrp.Position - base.root.Position).Magnitude < cfg.CATCH_DISTANCE then
				ctx.manager.playerCaught(player, cfg.NAME)
			end
		end
	end)

	-- ---------- public API ----------

	function self.enrage()
		if self.enraged then
			return
		end
		self.enraged = true
		local glow = Instance.new("PointLight")
		glow.Name = "EnrageGlow"
		glow.Color = Color3.fromRGB(255, 140, 30)
		glow.Range = 12
		glow.Brightness = 2
		glow.Parent = base.root
	end

	function self.reset()
		self.enraged = false
		clearTraps()
		trapsSeeded = false
		heardAt = nil
		heardUntil = 0
		trappedUntil = {}
		local oldGlow = base.root:FindFirstChild("EnrageGlow")
		if oldGlow then
			oldGlow:Destroy()
		end
		base:resetToSpawn()
	end

	ctx.npcs.Sportage = self
	return self
end

return SportageAI
