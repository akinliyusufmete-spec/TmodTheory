--[[
	BeansAI (ModuleScript, ServerScriptService.BaldiGame.BeansAI)

	The gum-spitter — a MULTIPLAYER-only character (parked in every mode whose
	roster doesn't list him; only MATCH does).

	He roams the halls. When a player is lined up roughly ahead of him (within
	his forward cone, SPIT_ALIGN), in sight, with clear line of sight, and his
	spit is off cooldown, he snaps to face them and SPITS a wad of gum straight
	down the lane. The wad flies in a FIXED straight line (no homing) at gum
	height:
	  - it sticks to the first character (player OR npc) within GUM_HIT_RADIUS —
	    miring them in gum, slowed to GUM_SLOW for GUM_DURATION,
	  - or it splats on a wall / closed door (real geometry stops it; open/swung
	    doorways are out of the straight line, so it passes them).
	The instant the gum lands on anything, Beans BOLTS (SCURRY_SPEED) for
	FLEE_SECONDS, settles REPOSE_DELAY, then hunts a new shot.

	Gummed players cut free early with Safety Scissors (BeansSnip remote) and
	then get GUM_IMMUNITY seconds before they can be re-gummed; gummed NPCs
	re-gum no sooner than GUM_NPC_COOLDOWN. The player-side slow + cut-free
	prompt live in BeansGumClient (driven by the BeansGum / BeansUngum remotes).

	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/Beans
]]

local Players = game:GetService("Players")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)

local BeansAI = {}

local COLOR_BODY = Color3.fromRGB(120, 75, 150)
local COLOR_HEAD = Color3.fromRGB(160, 110, 185)
local GUM_COLOR = Color3.fromRGB(150, 225, 160)

function BeansAI.init(ctx)
	local cfg = ctx.config.NPC.BEANS
	local self = { ctx = ctx, cfg = cfg }

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(210, 160, 225),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.BEANS, cfg.ROAM_SPEED)
	self.base = base
	self.model = model

	-- ---------- state ----------

	local fleeing = false
	local nextSpitAt = 0 -- earliest time he may spit again
	local gummedUntil = {} -- [player] = time their gum wears off
	local gumImmunityUntil = {} -- [player] = time they can be gummed again
	local npcGumCooldown = {} -- [npc] = next time that npc may be gummed

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	local function canGum(player)
		return (gumImmunityUntil[player] or 0) <= os.clock()
			and (gummedUntil[player] or 0) <= os.clock()
			and not ctx.detention.hasImmunity(player)
	end

	-- ---------- gum effects ----------

	local function endGumState(player)
		gummedUntil[player] = nil
		gumImmunityUntil[player] = os.clock() + cfg.GUM_IMMUNITY
	end

	local function gumPlayer(player)
		if not ctx.manager.isRoundActive() then
			return
		end
		gummedUntil[player] = os.clock() + cfg.GUM_DURATION
		ctx.remotes.BeansGum:FireClient(player, cfg.GUM_DURATION)
		base:say("Gum", { target = player, force = true })
		task.delay(cfg.GUM_DURATION, function()
			if (gummedUntil[player] or 0) <= os.clock() then
				endGumState(player) -- wore off naturally
			end
		end)
	end

	local function gumNpc(npc)
		-- can't re-gum this npc until its current gum wears off + a cooldown
		npcGumCooldown[npc] = os.clock() + cfg.GUM_DURATION + cfg.GUM_NPC_COOLDOWN
		npc.base:applySlow(cfg.GUM_SLOW, cfg.GUM_DURATION)
	end

	ctx.remotes.BeansSnip.OnServerEvent:Connect(function(player)
		if (gummedUntil[player] or 0) <= os.clock() then
			return -- not actually gummed
		end
		if ctx.economy.consumeItem(player, "SCISSORS") then
			endGumState(player)
			if player.Parent then
				ctx.remotes.BeansUngum:FireClient(player)
			end
		end
	end)

	-- ---------- the gum wad ----------

	local function makeGumWad()
		local wad = Instance.new("Part")
		wad.Name = "BeansGumWad"
		wad.Shape = Enum.PartType.Ball
		wad.Size = Vector3.new(1.1, 1.1, 1.1)
		wad.Color = GUM_COLOR
		wad.Material = Enum.Material.SmoothPlastic
		wad.Anchored = true
		wad.CanCollide = false
		wad.CanQuery = false
		wad.CanTouch = false
		return wad
	end

	-- Travel a wad in a straight line from origin along dir until it sticks to a
	-- character or splats on geometry (or flies out of range). BLOCKS until the
	-- wad lands — Beans watches his shot, then flees.
	local function spitGum(origin, dir)
		local wad = makeGumWad()
		wad:PivotTo(CFrame.new(origin))
		wad.Parent = ctx.map.projectilesFolder

		-- walls stop the wad; exclude every character + transient folder so the
		-- ray only trips on real geometry (closed/locked doors included; open
		-- doors are out of the straight line, so the wad passes them)
		local wallParams = RaycastParams.new()
		wallParams.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = { ctx.map.npcFolder, ctx.map.notebooksFolder, ctx.map.pickupsFolder, ctx.map.projectilesFolder }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(excluded, p.Character)
			end
		end
		wallParams.FilterDescendantsInstances = excluded

		local pos = origin
		local traveled = 0
		while traveled < cfg.GUM_RANGE and wad.Parent do
			if not ctx.manager or not ctx.manager.isRoundActive() then
				break
			end
			local dt = task.wait()
			local step = dir * cfg.GUM_SPEED * dt

			-- wall in this step? splat there and stop
			local hit = workspace:Raycast(pos, step, wallParams)
			if hit then
				pos = hit.Position - dir * 0.3
				break
			end
			pos = pos + step
			traveled = traveled + step.Magnitude
			wad:PivotTo(CFrame.new(pos, pos + dir))

			-- character in range? gum the first one and stop
			local landed = false
			for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
				if canGum(player) then
					local hrp = targetRoot(player)
					if hrp and (hrp.Position - pos).Magnitude < cfg.GUM_HIT_RADIUS then
						gumPlayer(player)
						landed = true
						break
					end
				end
			end
			if not landed then
				for _, npc in pairs(ctx.npcs) do
					if npc ~= self and npc.base and npc.base.model.Parent and not npc.base.parked then
						if (npcGumCooldown[npc] or 0) <= os.clock()
							and (npc.base.root.Position - pos).Magnitude < cfg.GUM_HIT_RADIUS then
							gumNpc(npc)
							landed = true
							break
						end
					end
				end
			end
			if landed then
				break
			end
		end

		-- leave the splat stuck a moment, then clean up
		if wad.Parent then
			wad:PivotTo(CFrame.new(pos))
			wad.Size = Vector3.new(1.5, 0.5, 1.5)
			task.delay(1.5, function()
				if wad.Parent then
					wad:Destroy()
				end
			end)
		end
	end

	-- ---------- flee ----------

	local function farthestWaypointFrom(fromPos)
		local best, bestDist = nil, -1
		for _, node in ipairs(ctx.map.waypointsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				local d = (node.Position - fromPos).Magnitude
				if d > bestDist then
					bestDist = d
					best = node.Position
				end
			end
		end
		return best
	end

	local function flee(awayFromPos)
		fleeing = true
		local startedAt = os.clock()
		local function fleeDone()
			return not base:canAct() or (os.clock() - startedAt) > cfg.FLEE_SECONDS
		end
		local far = farthestWaypointFrom(awayFromPos)
		if far then
			base:navigateTo(far, cfg.SCURRY_SPEED, fleeDone)
		end
		-- burn any remaining flee time wandering if the route was short
		while not fleeDone() do
			base:wanderStep(cfg.SCURRY_SPEED, fleeDone)
		end
		if base:canAct() then
			task.wait(cfg.REPOSE_DELAY)
		end
		fleeing = false
	end

	-- ---------- target scan ----------

	local lastScan = 0
	local cachedTarget = nil

	local function findSpitTarget()
		if os.clock() - lastScan < cfg.SIGHT_INTERVAL then
			return cachedTarget
		end
		lastScan = os.clock()
		cachedTarget = nil
		if not ctx.manager or fleeing or os.clock() < nextSpitAt then
			return nil
		end
		local lookFlat = Vector3.new(base.root.CFrame.LookVector.X, 0, base.root.CFrame.LookVector.Z)
		if lookFlat.Magnitude < 0.01 then
			return nil
		end
		lookFlat = lookFlat.Unit

		local bestDistance = math.huge
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			if canGum(player) then
				local hrp = targetRoot(player)
				if hrp then
					local toTarget = Vector3.new(hrp.Position.X - base.root.Position.X, 0, hrp.Position.Z - base.root.Position.Z)
					local distance = toTarget.Magnitude
					if distance > 4 and distance <= cfg.SIGHT_RANGE
						and lookFlat:Dot(toTarget.Unit) >= cfg.SPIT_ALIGN
						and distance < bestDistance
						and base:canSee(hrp, cfg.SIGHT_RANGE) then
						bestDistance = distance
						cachedTarget = player
					end
				end
			end
		end
		return cachedTarget
	end

	-- ---------- spit ----------

	local function doSpit(player)
		nextSpitAt = os.clock() + cfg.SPIT_COOLDOWN -- set now so we never double-spit
		local hrp = targetRoot(player)
		if not hrp then
			return
		end
		base:stop()

		-- snap to face the target so the spit reads as aimed
		local faceAt = Vector3.new(hrp.Position.X, base.root.Position.Y, hrp.Position.Z)
		if (faceAt - base.root.Position).Magnitude > 0.5 then
			base.root.CFrame = CFrame.lookAt(base.root.Position, faceAt)
		end
		task.wait(0.25) -- a brief wind-up so a moving player can still slip the lane

		hrp = targetRoot(player)
		if not hrp or not base:canAct() then
			return
		end
		-- fire flat at the target's torso height, from just ahead of the mouth
		local lookFlat = Vector3.new(base.root.CFrame.LookVector.X, 0, base.root.CFrame.LookVector.Z)
		lookFlat = (lookFlat.Magnitude > 0.01) and lookFlat.Unit or Vector3.new(0, 0, -1)
		local targetPos = hrp.Position
		local mouth = Vector3.new(base.root.Position.X, targetPos.Y, base.root.Position.Z) + lookFlat * 1.5
		local dir = Vector3.new(targetPos.X - mouth.X, 0, targetPos.Z - mouth.Z)
		dir = (dir.Magnitude > 0.01) and dir.Unit or lookFlat

		spitGum(mouth, dir) -- blocks until the wad lands
		flee(targetPos) -- ...then bolt
	end

	-- ---------- main brain loop ----------

	task.spawn(function()
		while true do
			if not base:canAct() or fleeing then
				task.wait(0.2)
			else
				local victim = findSpitTarget()
				if victim then
					doSpit(victim)
				else
					base:roamStep(cfg.ROAM_SPEED, function()
						return findSpitTarget() ~= nil
					end)
				end
			end
		end
	end)

	-- ---------- reset between rounds ----------

	function self.reset()
		fleeing = false
		nextSpitAt = 0
		gummedUntil = {}
		gumImmunityUntil = {}
		npcGumCooldown = {}
		base:resetToSpawn()
	end

	ctx.npcs.Beans = self
	return self
end

return BeansAI
