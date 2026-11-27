--[[
	ChatReviveAI (ModuleScript, ServerScriptService.BaldiGame.ChatReviveAI)

	The relentless chaser (the "Baldi" of this game). He never walks: he
	moves in dashes.
	  - Each cycle he picks a goal (the nearest player, an alarm clock, where
	    he last saw you, or a wander node) and spherecasts toward it. If the
	    line is clear he dashes straight at it (at most DASH_DISTANCE).
	  - If walls block the way, he computes a path and follows its waypoints
	    only until the next corner (CORNER_THRESHOLD) or until DASH_DISTANCE,
	    whichever comes first, so he moves in clean bursts down corridors and
	    turns at corners instead of clipping through walls.
	  - A final spherecast shortens the dash if anything is still in the way.
	  - Movement is a LinearVelocity (root.DashVelocity) that pushes only on
	    the horizontal axes, so gravity still works. WalkSpeed stays 0 so he
	    never walks, and his horizontal velocity is zeroed after every dash so
	    he doesn't slide. The server owns his physics.
	  - Before each dash he winds up (WIND_UP -> WIND_UP_FAST with heat,
	    model attribute Telegraph = true), then rests DASH_COOLDOWN.
	  - Events: self.DashStarted(direction, length, speed) and
	    self.Caught(player) (also BindableEvents "DashStarted" / "Caught" on
	    the model) - hook sounds, trails, animations or game logic there
	    without touching the movement code. The slap animation + sound are
	    played from DashStarted.
	  - He always faces the player he's chasing (otherwise the dash direction).
	  - Catch (within CATCH_DISTANCE): game over for that player.
	  - Enrages when all notebooks are collected: faster dashes, glows red.
	The rig's "AIState" attribute shows Chase / Investigate / Wander.

	Tuning: longer DASH_COOLDOWN / WIND_UP = fairer. CORNER_THRESHOLD ~0.8
	follows gentle curves, ~0.99 gives strict grid moves. Keep the
	Pathfinding AgentRadius a bit under half the corridor width, and
	SPHERE_RADIUS under AgentRadius.

	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/ChatRevive
	Slap sound: CharacterConfig.ChatRevive.Sounds.Chase, else
	AssetConfig.SOUNDS.chase, else a built-in snap (SoundLoader)
	Voicelines: CharacterConfig.ChatRevive (Spotted/Chasing/Lost/Caught/Stunned/Idle)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))

local ChatReviveAI = {}

local COLOR_BODY = Color3.fromRGB(170, 35, 35)
local COLOR_HEAD = Color3.fromRGB(220, 60, 50)
local COLOR_ENRAGED = Color3.fromRGB(90, 10, 10)

local DASH_ACTION = "Dash" -- the slap animation's name in CharacterConfig
local WAYPOINT_REACHED = 2.5
local JUMP_ACTION = Enum.PathWaypointAction.Jump

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function ChatReviveAI.init(ctx)
	local cfg = ctx.config.NPC.CHATREVIVE
	local self = {
		ctx = ctx,
		cfg = cfg,
		enraged = false,
	}

	local DASH_DISTANCE = cfg.DASH_DISTANCE or 16
	local SPHERE_RADIUS = cfg.SPHERE_RADIUS or 1.5
	local MIN_DASH = cfg.MIN_DASH or 1.5
	local ROAM_DASH_SPEED = cfg.ROAM_DASH_SPEED or 30
	local DASH_SPEED = cfg.DASH_SPEED or 45

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(255, 90, 80),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.CHATREVIVE,
		(ROAM_DASH_SPEED + DASH_SPEED) / 2)
	self.base = base
	self.model = model
	local humanoid = base.humanoid
	humanoid.AutoRotate = false -- the facing loop below turns him
	base:stop() -- WalkSpeed 0: he only ever moves by dashing

	-- the slap sound, once per dash
	self.slapSound = SoundLoader.attach(base.root, "ChaseSound", {
		Id = base.character.Sounds.Chase,
		Asset = "chase",
		Fallback = "rbxasset://sounds/snap.mp3",
		Volume = 0.8,
		RollOffMaxDistance = 90,
	})

	-- ---------- dash mover: horizontal-only LinearVelocity ----------

	local dashAttachment = base.root:FindFirstChild("DashAttachment")
	if not dashAttachment then
		dashAttachment = Instance.new("Attachment")
		dashAttachment.Name = "DashAttachment"
		dashAttachment.Parent = base.root
	end
	local dashVelocity = base.root:FindFirstChild("DashVelocity")
	if not dashVelocity then
		dashVelocity = Instance.new("LinearVelocity")
		dashVelocity.Name = "DashVelocity"
	end
	dashVelocity.Attachment0 = dashAttachment
	dashVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	dashVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	dashVelocity.PrimaryTangentAxis = Vector3.xAxis
	dashVelocity.SecondaryTangentAxis = Vector3.zAxis
	dashVelocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	dashVelocity.MaxForce = 0
	dashVelocity.PlaneVelocity = Vector2.zero
	dashVelocity.Enabled = false
	dashVelocity.Parent = base.root

	-- ---------- events ----------

	local function makeEvent(name)
		local bindable = model:FindFirstChild(name)
		if not (bindable and bindable:IsA("BindableEvent")) then
			bindable = Instance.new("BindableEvent")
			bindable.Name = name
			bindable.Parent = model
		end
		return bindable
	end
	local dashStartedEvent = makeEvent("DashStarted")
	local caughtEvent = makeEvent("Caught")
	self.DashStarted = dashStartedEvent.Event -- (direction: Vector3, length: number, speed: number)
	self.Caught = caughtEvent.Event -- (player: Player)

	-- ---------- helpers ----------

	local lastScan = 0
	local cachedTarget = nil
	local committedUntil = 0
	local alertUntil = 0

	local function heat()
		if self.enraged then
			return 1
		end
		return (ctx.manager and ctx.manager.getHeat and ctx.manager.getHeat()) or 0
	end

	local function lerpHeat(calm, hot)
		return calm + (hot - calm) * heat()
	end

	local function sightRange()
		return lerpHeat(cfg.SIGHT_RANGE, cfg.SIGHT_RANGE_ENRAGED or cfg.SIGHT_RANGE * 2)
	end

	local brain -- defined below; alertBurst only flags a re-plan

	-- Guy's scream: look around fast for a few seconds and cut the rest short
	function self.alertBurst(seconds)
		alertUntil = os.clock() + (seconds or 5)
		if brain then
			brain.replan = true
		end
	end

	local function sightInterval()
		if os.clock() < alertUntil then
			return cfg.ENRAGED_SIGHT_INTERVAL
		end
		return cfg.SIGHT_INTERVAL + (cfg.ENRAGED_SIGHT_INTERVAL - cfg.SIGHT_INTERVAL) * heat()
	end

	local function playSlap()
		pcall(function()
			self.slapSound.PlaybackSpeed = self.enraged and 1.3 or (0.85 + heat() * 0.45)
			self.slapSound:Play()
		end)
	end

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	local function isValidTarget(player)
		if not player or not ctx.manager then
			return false
		end
		local hrp = targetRoot(player)
		if not hrp or not ctx.manager.isTargetable(player) then
			return false
		end
		return cfg.OMNISCIENT or base:canSee(hrp, sightRange())
	end

	-- nearest visible player, re-scanned every sightInterval(); sticks with a
	-- target for TARGET_STICK_SECONDS unless another is TARGET_SWITCH_MARGIN nearer
	local function findTarget()
		if os.clock() - lastScan < sightInterval() then
			return cachedTarget
		end
		lastScan = os.clock()
		if not ctx.manager then
			cachedTarget = nil
			return nil
		end
		local nearest, nearestDistance = nil, math.huge
		local currentDistance = math.huge
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			local hrp = targetRoot(player)
			if hrp and (cfg.OMNISCIENT or base:canSee(hrp, sightRange())) then
				local distance = (hrp.Position - base.root.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearest = player
				end
				if player == cachedTarget then
					currentDistance = distance
				end
			end
		end
		local stick = cfg.TARGET_STICK_SECONDS or 6
		if isValidTarget(cachedTarget) and os.clock() < committedUntil then
			local margin = cfg.TARGET_SWITCH_MARGIN or 16
			if nearest and nearest ~= cachedTarget and nearestDistance < currentDistance - margin then
				cachedTarget = nearest
				committedUntil = os.clock() + stick
			end
		else
			cachedTarget = nearest
			committedUntil = os.clock() + stick
		end
		return cachedTarget
	end

	-- HUNT: the nearest targetable player, seen or not
	local function huntTarget()
		if cfg.HUNT == false or not ctx.manager then
			return nil
		end
		local nearest, nearestDistance = nil, math.huge
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			local hrp = targetRoot(player)
			if hrp then
				local distance = (hrp.Position - base.root.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearest = player
				end
			end
		end
		return nearest
	end

	local function getDistraction()
		return ctx.economy and ctx.economy.getDistraction() or nil
	end

	-- ---------- brain ----------

	brain = {
		state = "Wander",
		target = nil, -- player being chased
		lastSeenPos = nil,
		lastSeenAt = -math.huge,
		wanderGoal = nil,
		replan = false, -- cut the cooldown short (alertBurst)
		dashing = false,
		faceDir = nil, -- flat direction of the planned / current dash
		fails = 0, -- dashes in a row that couldn't go anywhere
		acting = false, -- slap animation is playing
		cycle = 0,
		caughtAt = {}, -- [player] = os.clock() of the last Caught event
	}
	model:SetAttribute("AIState", brain.state)

	local function setState(state)
		if brain.state ~= state then
			brain.state = state
			model:SetAttribute("AIState", state)
		end
	end

	local function dropChase()
		if brain.target then
			base:endChase() -- "Lost"
			brain.target = nil
		end
	end

	local function pickWander()
		local folder = ctx.map.waypointsFolder
		if not folder then
			return nil
		end
		local nodes = {}
		for _, node in ipairs(folder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(nodes, node.Position)
			end
		end
		if #nodes == 0 then
			return nil
		end
		base:say("Idle")
		return nodes[base.rng:NextInteger(1, #nodes)]
	end

	-- Where should he go right now? Returns goal position and the player
	-- (only when chasing one).
	local function decide()
		local distraction = getDistraction()
		if distraction then
			dropChase()
			setState("Investigate")
			return distraction.position, nil
		end

		local player = findTarget()
		local hrp = player and targetRoot(player)
		if hrp then
			brain.lastSeenPos = hrp.Position
			brain.lastSeenAt = os.clock()
		else
			player = huntTarget()
			hrp = player and targetRoot(player)
		end
		if hrp then
			if brain.target ~= player then
				dropChase()
				base:beginChase(player) -- "Spotted"
				brain.target = player
			else
				base:chaseTick() -- "Chasing"
			end
			brain.wanderGoal = nil
			setState("Chase")
			return hrp.Position, player
		end

		dropChase()
		if brain.lastSeenPos and os.clock() - brain.lastSeenAt < (cfg.MEMORY_SECONDS or 6) then
			setState("Investigate")
			return brain.lastSeenPos, nil
		end
		brain.lastSeenPos = nil
		setState("Wander")
		if not brain.wanderGoal or flatDistance(brain.wanderGoal, base.root.Position) < WAYPOINT_REACHED * 2 then
			brain.wanderGoal = pickWander()
		end
		return brain.wanderGoal, nil
	end

	-- ---------- casts ----------

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.RespectCanCollide = true -- non-collidable decor never blocks a dash

	-- map excludes (npcs, notebooks, pickups, projectiles) + every player
	local function refreshCastParams()
		local list = base.rayParams.FilterDescendantsInstances
		table.insert(list, model)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		castParams.FilterDescendantsInstances = list
	end

	-- how far he can dash along flat unit dir before touching something.
	-- Spherecast for his body width + a center ray (shapecasts ignore parts
	-- they already overlap, e.g. a wall he's pressed against).
	local function clearDistance(origin, dir, length)
		local best = length
		local ok, hit = pcall(function()
			return workspace:Spherecast(origin, SPHERE_RADIUS, dir * length, castParams)
		end)
		if ok and hit then
			best = math.min(best, hit.Distance)
		end
		local ray = workspace:Raycast(origin, dir * length, castParams)
		if ray then
			best = math.min(best, ray.Distance)
		end
		return best
	end

	local function hasFloor(point)
		return workspace:Raycast(point, Vector3.new(0, -8, 0), castParams) ~= nil
	end

	-- follow path waypoints until the next corner or DASH_DISTANCE
	-- returns the dash end (at origin height) and whether to jump
	local function cornerEnd(origin, waypoints)
		local threshold = cfg.CORNER_THRESHOLD or 0.9
		local prev = origin
		local prevDir = nil
		local travelled = 0
		local endPos = nil
		for i = 2, #waypoints do
			local wp = waypoints[i]
			local p = Vector3.new(wp.Position.X, origin.Y, wp.Position.Z)
			local seg = flat(p - prev)
			local segLength = seg.Magnitude
			local jump = wp.Action == JUMP_ACTION
			if segLength > 0.05 then
				local segDir = seg.Unit
				if prevDir and prevDir:Dot(segDir) < threshold then
					return endPos, false -- corner: stop at the turn
				end
				local remaining = DASH_DISTANCE - travelled
				if segLength >= remaining then
					return prev + segDir * remaining, false
				end
				travelled += segLength
				prev = p
				endPos = p
				prevDir = segDir
			end
			if jump then
				-- jump point right next to him: hop as this dash starts;
				-- otherwise stop there and hop on the next dash
				if travelled < 4 then
					return endPos, true
				end
				return endPos, false
			end
		end
		return endPos, false
	end

	-- plan one dash toward goal: returns flat unit dir, length, jump
	local function planDash(goal)
		refreshCastParams()
		local origin = base.root.Position
		local toGoal = flat(goal - origin)
		local distance = toGoal.Magnitude
		if distance < 0.05 then
			return nil
		end
		local dir = toGoal.Unit
		local length = math.min(distance, DASH_DISTANCE)
		local endPos, jump = nil, false

		local clear = clearDistance(origin, dir, length)
		if clear >= length - 0.05
			and hasFloor(origin + dir * (length * 0.5))
			and hasFloor(origin + dir * length) then
			endPos = origin + dir * length -- clear line: straight at it
		else
			local waypoints = base:computePath(goal)
			if waypoints and #waypoints >= 2 then
				endPos, jump = cornerEnd(origin, waypoints)
			end
			if not endPos then
				endPos = origin + dir * length -- no path: straight at it anyway
			end
		end

		-- final spherecast: shorten the dash if anything is still in the way
		local delta = flat(endPos - origin)
		length = delta.Magnitude
		if length < 0.05 then
			return nil
		end
		dir = delta.Unit
		clear = clearDistance(origin, dir, length)
		if clear < length then
			length = math.max(clear - 0.5, 0)
		end
		return dir, length, jump
	end

	-- boxed in twice in a row: short hop in the clearest of 8 directions,
	-- preferring ones that point at the goal
	local function escapeDash(goal)
		refreshCastParams()
		local origin = base.root.Position
		local toGoal = flat(goal - origin)
		local goalDir = toGoal.Magnitude > 0.05 and toGoal.Unit or flat(base.root.CFrame.LookVector).Unit
		local bestDir, bestLength, bestScore = nil, 0, -math.huge
		for i = 0, 7 do
			local angle = i * math.pi / 4
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local length = math.max(clearDistance(origin, dir, 5) - 0.5, 0)
			if length >= MIN_DASH and hasFloor(origin + dir * length) then
				local score = length / 5 + dir:Dot(goalDir) * 0.5
				if score > bestScore then
					bestDir, bestLength, bestScore = dir, length, score
				end
			end
		end
		return bestDir, bestLength
	end

	-- ---------- dash execution ----------

	local function holdStill()
		if humanoid.WalkSpeed ~= 0 then
			humanoid.WalkSpeed = 0
		end
		base.desiredSpeed = 0
	end

	local function dashSpeed()
		local speed = ROAM_DASH_SPEED
		if brain.state == "Chase" then
			speed = (self.enraged and cfg.ENRAGED_DASH_SPEED) or DASH_SPEED
		end
		if os.clock() < (base.slowUntil or 0) then
			speed *= base.slowMultiplier or 1 -- Frosty's slow
		end
		return speed
	end

	local function cantDash()
		return base.parked or not base:canAct()
	end

	local function zeroHorizontal()
		local root = base.root
		if not root.Anchored then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end

	-- wind up, dash dir * length at speed, stop dead. Returns
	-- "done" / "stalled" / "timeout" / "stunned" / "abort"
	local function runDash(dir, length, jump, speed)
		brain.faceDir = dir
		local windUp = lerpHeat(cfg.WIND_UP or 0.3, cfg.WIND_UP_FAST or 0.12)
		if os.clock() < alertUntil then
			windUp = math.min(windUp, cfg.WIND_UP_FAST or 0.12)
		end
		model:SetAttribute("Telegraph", true)
		local waited = 0
		while waited < windUp do
			waited += task.wait()
			if cantDash() then
				model:SetAttribute("Telegraph", false)
				return base:isStunned() and "stunned" or "abort"
			end
		end
		model:SetAttribute("Telegraph", false)

		local root = base.root
		local start = root.Position
		brain.dashing = true
		dashStartedEvent:Fire(dir, length, speed)
		dashVelocity.MaxForce = root.AssemblyMass * (cfg.DASH_ACCEL or 1500)
		dashVelocity.PlaneVelocity = Vector2.new(dir.X * speed, dir.Z * speed)
		dashVelocity.Enabled = true
		if jump then
			humanoid.Jump = true
		end

		local limit = length / speed * 1.6 + 0.2
		local elapsed, slowFor = 0, 0
		local result = "done"
		while true do
			local dt = task.wait()
			elapsed += dt
			if base:isStunned() then
				result = "stunned"
				break
			end
			if cantDash() then
				result = "abort"
				break
			end
			if flat(root.Position - start):Dot(dir) >= length - 0.3 then
				break -- arrived
			end
			if elapsed > limit then
				result = "timeout"
				break
			end
			if elapsed > 0.15 and flat(root.AssemblyLinearVelocity).Magnitude < speed * 0.2 then
				slowFor += dt
				if slowFor >= 0.15 then
					result = "stalled"
					break
				end
			else
				slowFor = 0
			end
		end

		dashVelocity.Enabled = false
		brain.dashing = false
		if result ~= "stunned" then
			zeroHorizontal() -- no sliding (a BSODA push owns his velocity while stunned)
		end
		return result
	end

	-- slap animation + sound on every dash
	self.DashStarted:Connect(function()
		brain.acting = true
		base:playAction(DASH_ACTION)
		brain.cycle += 1
		model:SetAttribute("ActionRate", 1)
		model:SetAttribute("ActionCycle", brain.cycle)
		playSlap()
	end)

	local function goIdle()
		if brain.acting then
			brain.acting = false
			base:endAction(DASH_ACTION)
		end
		brain.faceDir = nil
	end

	-- ---------- dash loop ----------

	task.spawn(function()
		while true do
			if base:canAct() and ctx.manager and not base.parked then
				holdStill()
				brain.replan = false
				local goal = decide()
				local pos = base.root.Position
				if not goal then
					goIdle()
					task.wait(0.2)
				elseif brain.state ~= "Chase" and flatDistance(goal, pos) < WAYPOINT_REACHED then
					-- reached a spot (last-seen, alarm clock): forget the last-seen spot
					if brain.state == "Investigate" and brain.lastSeenPos
						and flatDistance(brain.lastSeenPos, pos) < WAYPOINT_REACHED then
						brain.lastSeenPos = nil
					end
					goIdle()
					task.wait(0.1)
				else
					local dir, length, jump = planDash(goal)
					if not dir or length < MIN_DASH then
						brain.fails += 1
						dir, length, jump = nil, 0, false
						if brain.fails >= 2 then
							dir, length = escapeDash(goal)
							brain.fails = 0
						end
					end
					if dir and length >= MIN_DASH then
						local result = runDash(dir, length, jump, dashSpeed())
						if result == "done" then
							brain.fails = 0
						elseif result == "stalled" or result == "timeout" then
							brain.fails += 1
						end
						if result ~= "stunned" and result ~= "abort" then
							local cooldown = lerpHeat(cfg.DASH_COOLDOWN or 0.4, cfg.DASH_COOLDOWN_FAST or 0.15)
							local rested = 0
							while rested < cooldown and not brain.replan and not cantDash() do
								rested += task.wait()
							end
						end
					else
						task.wait(0.1)
					end
				end
			else
				if dashVelocity.Enabled then
					dashVelocity.Enabled = false
				end
				goIdle()
				task.wait(0.2)
			end
		end
	end)

	-- ---------- always facing the player ----------

	local function facingDir(pos)
		if brain.state == "Chase" then
			local hrp = targetRoot(brain.target)
			if hrp then
				local toTarget = flat(hrp.Position - pos)
				if toTarget.Magnitude > 0.05 then
					return toTarget
				end
			end
		end
		return brain.faceDir
	end

	RunService.Heartbeat:Connect(function()
		local root = base.root
		if base.parked or not model.Parent or root.Anchored or base:isStunned() or not base:isActive() then
			return
		end
		local pos = root.Position
		local dir = facingDir(pos)
		if not dir or dir.Magnitude < 0.05 or root.CFrame.LookVector:Dot(dir.Unit) > 0.9995 then
			return
		end
		root.CFrame = CFrame.lookAt(pos, pos + dir.Unit)
	end)

	-- ---------- catch check ----------

	RunService.Heartbeat:Connect(function()
		if not base:isActive() or not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			local hrp = targetRoot(player)
			if hrp and (hrp.Position - base.root.Position).Magnitude < cfg.CATCH_DISTANCE then
				local now = os.clock()
				if now - (brain.caughtAt[player] or -math.huge) > 1 then
					brain.caughtAt[player] = now
					caughtEvent:Fire(player)
				end
				ctx.manager.playerCaught(player, cfg.NAME)
			end
		end
	end)

	-- ---------- public API ----------

	local isPlaceholder = model:GetAttribute("BaldiPlaceholderRig") == true

	function self.enrage()
		if self.enraged then
			return
		end
		self.enraged = true
		if isPlaceholder then
			for _, part in ipairs(model:GetChildren()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "FaceMark" then
					part.Color = COLOR_ENRAGED
				end
			end
		else
			-- tint your rig without overwriting its colors
			local tint = Instance.new("Highlight")
			tint.Name = "EnrageTint"
			tint.FillColor = Color3.fromRGB(180, 20, 20)
			tint.FillTransparency = 0.7
			tint.OutlineColor = Color3.fromRGB(120, 0, 0)
			tint.OutlineTransparency = 0.4
			tint.Parent = model
		end
		local glow = Instance.new("PointLight")
		glow.Name = "EnrageGlow"
		glow.Color = Color3.fromRGB(255, 40, 40)
		glow.Range = 12
		glow.Brightness = 2
		glow.Parent = base.root
	end

	function self.reset()
		self.enraged = false
		alertUntil = 0
		cachedTarget = nil
		committedUntil = 0
		dashVelocity.Enabled = false
		dashVelocity.PlaneVelocity = Vector2.zero
		brain.target = nil
		brain.lastSeenPos = nil
		brain.lastSeenAt = -math.huge
		brain.wanderGoal = nil
		brain.replan = false
		brain.dashing = false
		brain.faceDir = nil
		brain.fails = 0
		brain.caughtAt = {}
		goIdle()
		setState("Wander")
		model:SetAttribute("Telegraph", false)
		local oldGlow = base.root:FindFirstChild("EnrageGlow")
		if oldGlow then
			oldGlow:Destroy()
		end
		local oldTint = model:FindFirstChild("EnrageTint")
		if oldTint then
			oldTint:Destroy()
		end
		if isPlaceholder then
			for _, part in ipairs(model:GetChildren()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "FaceMark" then
					part.Color = (part.Name == "Head") and COLOR_HEAD or COLOR_BODY
				end
			end
		end
		base:resetToSpawn()
		holdStill()
	end

	ctx.npcs.ChatRevive = self
	return self
end

return ChatReviveAI
