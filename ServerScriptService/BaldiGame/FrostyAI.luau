--[[
	FrostyAI (ModuleScript, ServerScriptService.BaldiGame.FrostyAI)

	The trapper. Frosty no longer ices the halls: he sets up TRAPS.
	  - A new run already has TRAPS_AT_START_MIN..MAX traps set on random
	    BaldiMap/TrapSpawns parts (the Waypoints when there are none).
	  - Once the characters wake up he roams, and every SET_INTERVAL_MIN..MAX
	    seconds walks to a free trap spot and sets one up: his TrapSetup
	    animation loops for a random SETUP_MIN..MAX seconds, then the trap
	    is in place. A BSODA (or the round ending) mid-setup spoils it.
	  - Three kinds, picked by TRAP_WEIGHTS. Each springs once:
	      SlowMachiner 3000  frost status: FROST_SLOW slower for FROST_SECONDS
	      EnergyDrainer-40   stamina drops to DRAIN_TO, then the exhaustion
	                         status recharges it EXHAUST_REGEN_CUT slower for
	                         EXHAUST_SECONDS
	      BEARTrapper        stuck in place until you win Silver's timing
	                         minigame (BEAR_HITS hits). Like Silver's grab, a
	                         trapped player stays fair game for the hunters.
	  - He never catches anyone himself, and keeps away from players: anyone
	    within AVOID_RADIUS sends him off (even mid-setup) to the waypoint
	    furthest from everyone. He wanders and sets traps only that far out.

	Tuning: GameConfig.NPC.FROSTY. Custom rig: BaldiAssets/Npcs/Frosty.
	Trap models: ReplicatedStorage/BaldiShared/BaldiAssets/Traps holds one slot
	per kind (SlowMachiner3000, EnergyDrainer40, BEARTrapper). Build the trap
	inside its slot; an empty slot uses the placeholder. Each trap is placed
	with the bottom of its model on the floor, turned at random, and made
	anchored and non-colliding (stepping close is what springs it).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)
local AssetResolver = require(script.Parent.AssetResolver)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))

local FrostyAI = {}

local COLOR_BODY = Color3.fromRGB(190, 230, 250)
local COLOR_HEAD = Color3.fromRGB(235, 250, 255)

local SCAN_INTERVAL = 0.1 -- seconds between trap trigger checks
local SPOT_TAKEN = 4 -- studs: a trap this close to a spot occupies it
local ARRIVE_SLACK = 6 -- studs (flat) from the spot that count as "there"

-- the three kinds: their name in messages + the placeholder's look
local KINDS = {
	SlowMachiner3000 = { displayName = "SlowMachiner 3000", color = Color3.fromRGB(120, 210, 255), material = Enum.Material.Ice },
	EnergyDrainer40 = { displayName = "EnergyDrainer-40", color = Color3.fromRGB(255, 215, 50), material = Enum.Material.Neon },
	BEARTrapper = { displayName = "BEARTrapper", color = Color3.fromRGB(150, 150, 160), material = Enum.Material.Metal },
}
local KIND_ORDER = { "SlowMachiner3000", "EnergyDrainer40", "BEARTrapper" }

-- Stand-in trap, built while BaldiAssets/Traps has no model for this kind:
-- a dark plate with a coloured core (SlowMachiner / EnergyDrainer) or a
-- ring of jaws (BEARTrapper). Origin = floor centre.
local function placeholderTrap(kind)
	local look = KINDS[kind]
	local model = Instance.new("Model")
	model.Name = kind

	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Shape = Enum.PartType.Cylinder
	plate.Size = Vector3.new(0.3, 4.5, 4.5)
	plate.CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	plate.Color = Color3.fromRGB(45, 45, 50)
	plate.Material = Enum.Material.Metal
	plate.Parent = model

	if kind == "BEARTrapper" then
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2
			local tooth = Instance.new("WedgePart")
			tooth.Name = "Jaw"
			tooth.Size = Vector3.new(0.3, 0.9, 0.5)
			tooth.CFrame = CFrame.new(math.cos(angle) * 1.8, 0.75, math.sin(angle) * 1.8)
				* CFrame.Angles(0, -angle + math.pi / 2, 0)
			tooth.Color = look.color
			tooth.Material = look.material
			tooth.Parent = model
		end
	else
		local core = Instance.new("Part")
		core.Name = "Core"
		core.Size = Vector3.new(1.6, 1.3, 1.6)
		core.CFrame = CFrame.new(0, 0.95, 0)
		core.Color = look.color
		core.Material = look.material
		core.Parent = model
		local glow = Instance.new("PointLight")
		glow.Color = look.color
		glow.Range = 8
		glow.Brightness = 1
		glow.Parent = core
	end

	model.WorldPivot = CFrame.new() -- floor centre, upright
	return model
end

function FrostyAI.init(ctx)
	local cfg = ctx.config.NPC.FROSTY
	local silverCfg = ctx.config.NPC.SILVER or {}
	local self = { ctx = ctx, cfg = cfg }

	local model = NpcFactory.create({
		name         = cfg.NAME,
		bodyColor    = COLOR_BODY,
		headColor    = COLOR_HEAD,
		transparency = 0.15,
		glowColor    = Color3.fromRGB(150, 220, 255),
		tagColor     = Color3.fromRGB(170, 230, 255),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.FROSTY)
	self.base  = base
	self.model = model

	local rng = Random.new()

	-- ===== state =====
	local traps = {}       -- { model, kind, spot, position }
	local bearHeld = {}    -- [player] = { hits, lastHitAt, releaseAt }
	local immuneUntil = {} -- [player] = no trap springs on them before this
	local nextSetupAt = nil

	function self.isTrapped(player)
		return bearHeld[player] ~= nil
	end

	local function rootOf(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	-- ===== spots =====
	local function trapSpots()
		local spots = ctx.map.trapSpawns
		if spots and #spots > 0 then
			return spots
		end
		spots = {}
		for _, node in ipairs(ctx.map.waypointsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(spots, node.Position)
			end
		end
		return spots
	end

	local function spotFree(spot)
		for _, trap in ipairs(traps) do
			if (trap.spot - spot).Magnitude < SPOT_TAKEN then
				return false
			end
		end
		return true
	end

	local function pickKind()
		local weights = cfg.TRAP_WEIGHTS or {}
		local total = 0
		for _, kind in ipairs(KIND_ORDER) do
			total += math.max(0, weights[kind] or 1)
		end
		if total <= 0 then
			return KIND_ORDER[rng:NextInteger(1, #KIND_ORDER)]
		end
		local roll = rng:NextNumber() * total
		for _, kind in ipairs(KIND_ORDER) do
			roll -= math.max(0, weights[kind] or 1)
			if roll <= 0 then
				return kind
			end
		end
		return KIND_ORDER[#KIND_ORDER]
	end

	-- ===== laying traps =====
	local function trapFolder()
		local folder = ctx.map.root:FindFirstChild("FrostyTraps")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "FrostyTraps"
			folder.Parent = ctx.map.root
		end
		return folder
	end

	-- the floor under a spot (spawn parts often float a little)
	local function floorAt(spot)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignore = { ctx.map.npcFolder, ctx.map.waypointsFolder, trapFolder() }
		local spawnFolder = ctx.map.root:FindFirstChild("TrapSpawns")
		if spawnFolder then
			table.insert(ignore, spawnFolder)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
		return hit and hit.Position or spot
	end

	local function layTrap(spot, kind)
		local template = AssetResolver.trapTemplate(kind)
		local trap = template and AssetResolver.preparePropClone(template) or placeholderTrap(kind)
		trap.Name = kind
		for _, part in ipairs(trap:IsA("BasePart") and { trap } or trap:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		trap:SetAttribute("FrostyTrap", kind)

		-- stand it on the floor (keeping the model's own orientation), turned at random
		local floor = floorAt(spot)
		trap:PivotTo(CFrame.new(floor) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * trap:GetPivot().Rotation)
		local boxCFrame, boxSize
		if trap:IsA("BasePart") then
			boxCFrame, boxSize = trap.CFrame, trap.Size
		else
			boxCFrame, boxSize = trap:GetBoundingBox()
		end
		local bottom = boxCFrame.Position.Y - boxSize.Y / 2
		trap:PivotTo(trap:GetPivot() + Vector3.new(0, floor.Y - bottom, 0))
		trap.Parent = trapFolder()

		table.insert(traps, { model = trap, kind = kind, spot = spot, position = floor })
	end

	local function clearTraps()
		for _, trap in ipairs(traps) do
			if trap.model.Parent then
				trap.model:Destroy()
			end
		end
		traps = {}
	end

	-- ===== trap effects =====
	local function frostOver(player, seconds)
		local character = player.Character
		if not character then
			return
		end
		local old = character:FindFirstChild("FrostyFrost")
		if old then
			old:Destroy()
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "FrostyFrost"
		highlight.FillColor = Color3.fromRGB(150, 220, 255)
		highlight.FillTransparency = 0.4
		highlight.OutlineColor = Color3.fromRGB(225, 245, 255)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = character
		Debris:AddItem(highlight, seconds)
	end

	local function releaseBear(player)
		local held = bearHeld[player]
		if not held then
			return
		end
		bearHeld[player] = nil
		immuneUntil[player] = os.clock() + (cfg.TRAP_IMMUNITY or 3)

		-- only let go of a player the trap itself is holding: someone caught,
		-- detained or grabbed meanwhile is another system's business
		local hrp = rootOf(player)
		local silver = ctx.npcs.Silver
		local sportage = ctx.npcs.Sportage
		if hrp and ctx.manager and ctx.manager.isParticipant(player)
			and not ctx.detention.isDetained(player)
			and not (silver and silver.isGrabbing and silver.isGrabbing(player))
			and not (sportage and sportage.isTrapped and sportage.isTrapped(player)) then
			hrp.Anchored = false
		end
		if player.Parent then
			ctx.remotes.SilverReleased:FireClient(player)
		end
	end

	local function bearTrap(player, hrp)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.Anchored = true
		local held = {
			hits = 0,
			lastHitAt = 0,
			releaseAt = os.clock() + (cfg.BEAR_MAX_SECONDS or 25),
		}
		bearHeld[player] = held
		ctx.remotes.SilverGrab:FireClient(player, cfg.BEAR_HITS or 3, "BEARTrapper")

		-- lets go on the failsafe timer, the round ending, or the player being
		-- caught / detained / leaving
		task.spawn(function()
			while bearHeld[player] == held do
				if os.clock() > held.releaseAt
					or not ctx.manager.isRoundActive()
					or not ctx.manager.isParticipant(player)
					or ctx.detention.isDetained(player)
					or not rootOf(player) then
					releaseBear(player)
					return
				end
				task.wait(0.1)
			end
		end)
	end

	local function spring(trap, player, hrp)
		if trap.model.Parent then
			trap.model:Destroy()
		end
		immuneUntil[player] = os.clock() + (cfg.TRAP_IMMUNITY or 3)
		if ctx.badges then
			ctx.badges.noteTrap(player)
		end
		SoundLoader.playAt(hrp, {
			Id = base.character.Sounds and base.character.Sounds[trap.kind],
			Fallback = "rbxasset://sounds/snap.mp3",
			FallbackSpeed = trap.kind == "SlowMachiner3000" and 1.4 or 0.7,
			Volume = 1,
			RollOffMaxDistance = 90,
		})

		if trap.kind == "SlowMachiner3000" then
			local seconds = cfg.FROST_SECONDS or 6
			ctx.remotes.SpeedDebuff:FireClient(player, seconds, 1 - (cfg.FROST_SLOW or 0.6),
				"Frozen by a SlowMachiner 3000!")
			frostOver(player, seconds)
			base:say("Freeze", { target = player, force = true })
		elseif trap.kind == "EnergyDrainer40" then
			ctx.remotes.Exhausted:FireClient(player, cfg.EXHAUST_SECONDS or 7, cfg.DRAIN_TO or 10,
				1 - (cfg.EXHAUST_REGEN_CUT or 0.8))
			ctx.remotes.PickupFailed:FireClient(player, "An EnergyDrainer-40 drained your stamina!")
		elseif trap.kind == "BEARTrapper" then
			ctx.remotes.PickupFailed:FireClient(player, "A BEARTrapper! Pry it open!")
			bearTrap(player, hrp)
		end
	end

	-- the BEARTrapper's minigame shares Silver's remotes (one hold at a time:
	-- neither springs on a player who's already anchored)
	ctx.remotes.SilverHit.OnServerEvent:Connect(function(player)
		local held = bearHeld[player]
		if not held then
			return
		end
		local now = os.clock()
		if now - held.lastHitAt < (silverCfg.GRAB_MIN_HIT_GAP or 0.2) then
			return -- too fast to be a real timing hit
		end
		held.lastHitAt = now
		held.hits += 1
		if held.hits >= (cfg.BEAR_HITS or 3) then
			releaseBear(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		bearHeld[player] = nil
		immuneUntil[player] = nil
	end)

	-- ===== trigger scan =====
	local sinceScan = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceScan += dt
		if sinceScan < SCAN_INTERVAL then
			return
		end
		sinceScan = 0
		if base.parked or #traps == 0 or not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		local now = os.clock()
		local players = ctx.manager.getTargetablePlayers()
		local radius = cfg.TRAP_RADIUS or 3
		for i = #traps, 1, -1 do
			local trap = traps[i]
			if not trap.model.Parent then
				table.remove(traps, i)
				continue
			end
			for _, player in ipairs(players) do
				if (immuneUntil[player] or 0) <= now and not bearHeld[player] then
					local hrp = rootOf(player)
					if hrp and not hrp.Anchored then
						local offset = hrp.Position - trap.position
						if Vector3.new(offset.X, 0, offset.Z).Magnitude < radius and math.abs(offset.Y) < 6 then
							table.remove(traps, i)
							spring(trap, player, hrp)
							break
						end
					end
				end
			end
		end
	end)

	-- ===== keeping away from players =====
	local function playerPositions()
		local list = {}
		for _, player in ipairs(ctx.manager and ctx.manager.getTargetablePlayers() or {}) do
			local hrp = rootOf(player)
			if hrp then
				table.insert(list, hrp.Position)
			end
		end
		return list
	end

	local function nearestOf(position, players)
		local best, bestDistance = nil, math.huge
		for _, point in ipairs(players) do
			local distance = (point - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = point, distance
			end
		end
		return best, bestDistance
	end

	local function threatened()
		local _, distance = nearestOf(base.root.Position, playerPositions())
		return distance < (cfg.AVOID_RADIUS or 35)
	end

	local function waypointPositions()
		local list = {}
		for _, node in ipairs(ctx.map.waypointsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(list, node.Position)
			end
		end
		return list
	end

	-- the point to head for: as far from every player as it gets, reached by
	-- moving away from the closest one rather than past them
	local function safestOf(points)
		local players = playerPositions()
		local here = base.root.Position
		local closest = nearestOf(here, players)
		local best, bestScore = nil, -math.huge
		for _, point in ipairs(points) do
			local offset = point - here
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > ARRIVE_SLACK then
				local _, clearance = nearestOf(point, players)
				local score = math.min(clearance, 200) + rng:NextNumber(0, 15)
				if closest then
					local away = here - closest
					if away.Magnitude > 0.1 then
						score += 40 * away.Unit:Dot(offset.Unit)
					end
				end
				if score > bestScore then
					best, bestScore = point, score
				end
			end
		end
		return best
	end

	-- ===== setting traps =====
	local function pickFreeSpot()
		local players = playerPositions()
		local free = {}
		for _, spot in ipairs(trapSpots()) do
			local _, clearance = nearestOf(spot, players)
			if spotFree(spot) and clearance >= (cfg.AVOID_RADIUS or 35) then
				table.insert(free, spot)
			end
		end
		if #free == 0 then
			return nil
		end
		return safestOf(free) or free[rng:NextInteger(1, #free)]
	end

	local function cantAct()
		return not base:canAct()
	end

	local function goSetUp(spot)
		base:navigateTo(spot, cfg.ROAM_SPEED, function()
			return cantAct() or threatened()
		end)
		local offset = base.root.Position - spot
		if not base:canAct() or threatened() or Vector3.new(offset.X, 0, offset.Z).Magnitude > ARRIVE_SLACK
			or not spotFree(spot) or #traps >= (cfg.MAX_TRAPS or 12) then
			return
		end
		base:stop()
		base:playAction("TrapSetup")
		local doneAt = os.clock() + rng:NextNumber(cfg.SETUP_MIN or 2.5, cfg.SETUP_MAX or 5)
		while os.clock() < doneAt and base:canAct() and not threatened() do
			task.wait(0.1)
		end
		-- a BSODA, the round ending or a player walking up spoils it
		local finished = base:canAct() and not threatened()
		base:endAction("TrapSetup")
		if finished then
			if spotFree(spot) then
				layTrap(spot, pickKind())
			end
			task.wait(cfg.SETUP_OUTRO or 0.8)
		end
	end

	local function rollNextSetup()
		nextSetupAt = os.clock() + rng:NextNumber(cfg.SET_INTERVAL_MIN or 12, cfg.SET_INTERVAL_MAX or 25)
	end

	-- ===== brain: keep away from players, wander, set a trap now and then =====
	task.spawn(function()
		while true do
			if base.parked or not base:canAct() then
				task.wait(0.25)
			elseif threatened() then
				local point = safestOf(waypointPositions())
				if point then
					base:navigateTo(point, cfg.FLEE_SPEED or 22, function()
						-- re-plan if someone gets between him and where he's going
						local _, blocked = nearestOf(point, playerPositions())
						return cantAct() or blocked < (cfg.AVOID_RADIUS or 35) / 2
					end)
				else
					task.wait(0.25)
				end
			else
				if not nextSetupAt then
					rollNextSetup()
				end
				if os.clock() >= nextSetupAt then
					local spot = #traps < (cfg.MAX_TRAPS or 12) and pickFreeSpot()
					if spot then
						goSetUp(spot)
					end
					rollNextSetup()
				else
					base:say("Idle")
					local point = safestOf(waypointPositions())
					if point then
						base:navigateTo(point, cfg.ROAM_SPEED, function()
							return cantAct() or threatened() or os.clock() >= nextSetupAt
						end)
					else
						task.wait(0.25)
					end
				end
			end
		end
	end)

	-- ===== round flow =====

	-- a new run: the starting traps go down before anyone can move
	function self.onRoundStart()
		clearTraps()
		local spots = table.clone(trapSpots())
		for i = #spots, 2, -1 do
			local j = rng:NextInteger(1, i)
			spots[i], spots[j] = spots[j], spots[i]
		end
		local wanted = rng:NextInteger(cfg.TRAPS_AT_START_MIN or 5, cfg.TRAPS_AT_START_MAX or 9)
		local spawnPosition = ctx.map.roundSpawnCFrame and ctx.map.roundSpawnCFrame.Position
		local placed = 0
		for _, spot in ipairs(spots) do
			if placed >= wanted then
				break
			end
			if not spawnPosition or (spot - spawnPosition).Magnitude >= (cfg.START_CLEARANCE or 20) then
				layTrap(spot, pickKind())
				placed += 1
			end
		end
	end

	function self.reset()
		clearTraps()
		for player in pairs(bearHeld) do
			releaseBear(player)
		end
		bearHeld = {}
		immuneUntil = {}
		nextSetupAt = nil
		base:resetToSpawn()
	end

	ctx.npcs.Frosty = self
	return self
end

return FrostyAI
