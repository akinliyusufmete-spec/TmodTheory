--[[
	NpcBase (ModuleScript, ServerScriptService.BaldiGame.NpcBase)

	Shared locomotion for every NPC: pathfinding, roaming, pursuit of a
	moving target, line-of-sight raycasts, stun/knockback (BSODA), slow
	(Frosty), voicelines, and reset between rounds.

	The AIs only differ in WHAT triggers a chase and WHERE the goal is —
	that lives in ChatReviveAI / LpAI / FrostyAI / etc. Everything
	mechanical (how to actually get somewhere without wedging on a wall or
	a doorway) lives here.

	Routing runs on SimplePath (ServerScriptService.BaldiGame.SimplePath),
	one Path object per NPC. travel() is the movement loop everything uses:
	  - with a clear, walkable straight line to the goal (same level, within
	    DIRECT_RANGE) the NPC skips routing and steers at the live goal every
	    tick — this is what makes a close chase feel relentless,
	  - otherwise SimplePath computes a route and walks it waypoint by
	    waypoint (jumping where the route jumps). A moving goal is re-routed
	    when it drifts REPATH_DISTANCE from the route's end or the route ages
	    past the repath interval; SimplePath's Blocked / unreachable / stuck
	    reports trigger a fresh route too,
	  - routes compute while the NPC keeps walking its current one, so a
	    re-route never freezes it mid-stride,
	  - stuck detection + an unstick nudge recover from wedging on geometry
	    (SimplePath also hops when it sees the agent not moving),
	  - no route to a fixed destination three times running = give up
	    ("noPath"), so nothing grinds into a wall forever.

	Voicelines: say(moment) asks VoicelineService (ctx.voicelines) for a line
	from CharacterConfig.<Name>.Voicelines. beginChase / endChase wrap a chase
	so Spotted / Chasing / Lost happen on their own; Idle and Stunned are
	said from here too.

	Per-character agent size / jumping / route dots: CharacterConfig.<Name>.Pathfinding.
	Tuning: GameConfig.NPC.PATHING.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimplePath = require(script.Parent.SimplePath)
local CharacterConfig = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("CharacterConfig"))

local NpcBase = {}
NpcBase.__index = NpcBase

local STEP_POLL = 0.08 -- how often a single MoveTo leg samples progress
local STUCK_PROGRESS = 2 -- studs we must gain to count as "still moving"
local STUCK_GRACE = 0.55 -- seconds of no progress before we call it stuck
local ARRIVE_RADIUS = 4 -- "close enough" when picking the next roam waypoint
local ROUTE_ACTIVE = SimplePath.StatusType.Active

-- chaseAnimThreshold: WalkSpeed above which the rig's "Chase" animation
-- plays (omit for characters that never chase).
function NpcBase.new(ctx, model, spawnCFrame, chaseAnimThreshold)
	local self = setmetatable({}, NpcBase)
	self.ctx = ctx
	self.model = model
	self.humanoid = model:WaitForChild("Humanoid")
	self.root = model:WaitForChild("HumanoidRootPart")
	self.spawnCFrame = spawnCFrame
	self.character = CharacterConfig.get(model.Name)

	self.paused = true -- activation gating: frozen until the first notebook
	self.stunnedUntil = 0
	self.slowUntil = 0
	self.slowMultiplier = 1
	self.desiredSpeed = 0
	self.rng = Random.new()
	self.chaseTarget = nil -- set by beginChase while hunting someone

	-- the client animator (NpcAnimatorClient) switches Walk -> Chase above this
	if chaseAnimThreshold then
		model:SetAttribute("ChaseAnimSpeed", chaseAnimThreshold)
	end

	-- agent params: a tighter radius fits hand-made doorways, and jumping
	-- lets the NPC clear small lips/thresholds and unstick itself
	local agent = ctx.config.NPC.AGENT or {}
	local overrides = self.character.Pathfinding or {}
	self.agentParams = {
		AgentRadius = overrides.AgentRadius or agent.RADIUS or 2,
		AgentHeight = overrides.AgentHeight or agent.HEIGHT or 5,
		AgentCanJump = if overrides.AgentCanJump ~= nil then overrides.AgentCanJump else agent.JUMP ~= false,
		AgentJumpHeight = overrides.AgentJumpHeight or agent.JUMP_HEIGHT or 4,
		WaypointSpacing = overrides.WaypointSpacing or 4,
		Costs = overrides.Costs,
	}

	-- travel-engine tuning (see GameConfig.NPC.PATHING for the knobs)
	local pathing = ctx.config.NPC.PATHING or {}
	self.pathing = {
		poll = pathing.POLL or 0.05,
		repathDistance = pathing.REPATH_DISTANCE or 6,
		directRange = pathing.DIRECT_RANGE or 45,
		arriveRadius = pathing.ARRIVE_RADIUS or 3,
		computeRetry = pathing.NO_PATH_RETRY or 0.25,
		bodyClearance = pathing.BODY_CLEARANCE or self.agentParams.AgentRadius,
	}

	-- raycast params for sight checks: ignore everything that isn't level
	-- geometry or the player being checked
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = {
		ctx.map.npcFolder,
		ctx.map.notebooksFolder,
		ctx.map.pickupsFolder,
		ctx.map.projectilesFolder,
	}

	model.PrimaryPart = self.root
	model:PivotTo(spawnCFrame)

	-- SimplePath drives the humanoid along computed routes (one Path per NPC,
	-- reused for every trip). Its events feed whichever travel() is running.
	self.path = SimplePath.new(model, self.agentParams, {
		TIME_VARIANCE = 0.07,
		COMPARISON_CHECKS = pathing.STUCK_CHECKS or 2,
		JUMP_WHEN_STUCK = self.agentParams.AgentCanJump,
	})
	self.path.Visualize = overrides.Visualize == true
	self.travelState = nil
	self.path.Reached:Connect(function()
		local state = self.travelState
		if state then
			state.reached = true
		end
	end)
	self.path.Blocked:Connect(function()
		local state = self.travelState
		if state then
			state.needRoute = true
		end
	end)
	self.path.Error:Connect(function(errorType)
		local state = self.travelState
		if state and (errorType == SimplePath.ErrorType.TargetUnreachable
			or errorType == SimplePath.ErrorType.AgentStuck) then
			state.needRoute = true
		end
	end)

	-- for one-off "where would a route go" checks (lunges, wander probes)
	self.probePath = PathfindingService:CreatePath(self.agentParams)

	-- server owns NPC physics so AI movement is smooth and authoritative.
	-- Ownership can't be set while anchored, and anchoring drops it back to
	-- auto (= the nearest player's client), so re-claim on EVERY unanchor:
	-- Frosty, Guy and parked characters spend most of a round anchored.
	local function claimOwnership()
		if self.root.Anchored or not self.root:IsDescendantOf(workspace) then
			return
		end
		pcall(function()
			self.root:SetNetworkOwner(nil)
		end)
	end
	self.root:GetPropertyChangedSignal("Anchored"):Connect(function()
		task.defer(claimOwnership)
	end)
	-- ...and when the map it stands in loads into the world (the first run)
	model.AncestryChanged:Connect(function()
		task.defer(claimOwnership)
	end)
	task.defer(claimOwnership)

	return self
end

-- ===================== state helpers =====================

function NpcBase:isStunned()
	return os.clock() < self.stunnedUntil
end

function NpcBase:isActive()
	return (not self.paused) and (not self:isStunned()) and self.model.Parent ~= nil
end

-- True only while a round is running AND this NPC may move.
function NpcBase:canAct()
	local manager = self.ctx.manager
	return self:isActive() and manager ~= nil and manager.isRoundActive()
end

function NpcBase:setPaused(paused)
	self.paused = paused
	if paused then
		self:stop()
	end
end

function NpcBase:resetToSpawn()
	self:endAction()
	self.stunnedUntil = 0
	self.slowUntil = 0
	self.slowMultiplier = 1
	self.chaseTarget = nil
	self:setPaused(true)
	self.parked = false
	self.root.Anchored = false
	local flash = self.model:FindFirstChild("StunFlash")
	if flash then
		flash:Destroy()
	end
	self.model:PivotTo(self.spawnCFrame)
	self.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

-- Park: freeze the NPC far above its spawn, out of sight and out of play.
-- Used for characters that sit out the current game mode (e.g. ChatRevive
-- during Impersonator). resetToSpawn / unpark bring it back.
function NpcBase:park()
	self:endAction()
	self:setPaused(true)
	self.parked = true
	self.model:PivotTo(self.spawnCFrame + Vector3.new(0, 400, 0))
	self.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	self.root.Anchored = true
end

function NpcBase:unpark()
	self.parked = false
	self.root.Anchored = false
	self:resetToSpawn()
end

-- Re-point the sight-check exclusions at the active map's runtime folders
-- (called when a round swaps to the maze and back).
function NpcBase:setMapExcludes(map)
	self.rayParams.FilterDescendantsInstances = {
		map.npcFolder,
		map.notebooksFolder,
		map.pickupsFolder,
		map.projectilesFolder,
	}
end

-- Hand the humanoid back from SimplePath. Anything that calls
-- humanoid:MoveTo itself must do this first, or SimplePath would read that
-- MoveTo's finish as "waypoint reached" and steer off on its old route.
function NpcBase:stopPath()
	if self.path.Status == ROUTE_ACTIVE then
		self.path:Stop()
	end
end

function NpcBase:stop()
	self:stopPath()
	self.desiredSpeed = 0
	self.humanoid.WalkSpeed = 0
	self.humanoid:MoveTo(self.root.Position)
end

-- ===================== action animations =====================

-- Play one of this character's action animations (a name in
-- CharacterConfig.<Name>.Animations: LP's Rulebreak, Silver's Caught,
-- Frosty's TrapSetup). Every client's NpcAnimatorClient plays it for as long
-- as the rig's "Action" attribute holds the name, looping per its config.
function NpcBase:playAction(name)
	self.model:SetAttribute("Action", name)
end

-- End the action (only `name`, if given): it fades out, or plays to its end
-- when its config says Finish.
function NpcBase:endAction(name)
	if name == nil or self.model:GetAttribute("Action") == name then
		self.model:SetAttribute("Action", nil)
	end
end

-- ===================== voicelines =====================

-- moment: a key in CharacterConfig.<Name>.Voicelines. opts = { target, force }
-- (see VoicelineService). Returns true if a line was said.
function NpcBase:say(moment, opts)
	local voicelines = self.ctx.voicelines
	if not voicelines or self.parked then
		return false
	end
	return voicelines.say(self.model, moment, opts)
end

-- Wrap a chase: says Spotted now, Chasing now and then while travelling
-- (chaseTick), and Lost at endChase if the target got away.
function NpcBase:beginChase(player)
	self.chaseTarget = player
	self:say("Spotted", { target = player })
end

function NpcBase:chaseTick()
	if self.chaseTarget then
		self:say("Chasing", { target = self.chaseTarget })
	end
end

function NpcBase:endChase()
	local player = self.chaseTarget
	self.chaseTarget = nil
	if not player or not player.Parent then
		return
	end
	-- only a real give-up gets a line: not a catch, an escape, a detention,
	-- a stun, or the round ending
	local manager = self.ctx.manager
	local detention = self.ctx.detention
	if manager and manager.isRoundActive() and manager.isTargetable(player)
		and not (detention and detention.isDetained(player))
		and self:isActive() then
		self:say("Lost", { target = player })
	end
end

-- ===================== speed / debuffs =====================

function NpcBase:applySpeed()
	local multiplier = (os.clock() < self.slowUntil) and self.slowMultiplier or 1
	self.humanoid.WalkSpeed = self.desiredSpeed * multiplier
end

function NpcBase:setMoveSpeed(speed)
	self.desiredSpeed = speed
	self:applySpeed()
end

-- Frosty's chill: also used on other NPCs when SLOWS_NPCS is on
function NpcBase:applySlow(multiplier, duration)
	self.slowMultiplier = multiplier
	self.slowUntil = os.clock() + duration
	self:applySpeed()
	task.delay(duration + 0.05, function()
		self:applySpeed()
	end)
end

-- BSODA hit: knock back and freeze in place for a few seconds.
-- The white flash is a Highlight, so it works on any rig (yours or the
-- placeholder) without touching part colors.
function NpcBase:stun(duration, pushDirection)
	local cfg = self.ctx.config.BSODA_PROJECTILE
	local alreadyStunned = self:isStunned()
	self.stunnedUntil = os.clock() + duration
	self:stopPath()
	self.humanoid.WalkSpeed = 0
	self.humanoid:MoveTo(self.root.Position)

	if not alreadyStunned then
		self:say("Stunned")
		local flash = Instance.new("Highlight")
		flash.Name = "StunFlash"
		flash.FillColor = Color3.fromRGB(235, 235, 245)
		flash.FillTransparency = 0.25
		flash.OutlineTransparency = 0.6
		flash.Parent = self.model
		task.spawn(function()
			while self:isStunned() do
				task.wait(0.1)
			end
			flash:Destroy()
			self:applySpeed()
		end)
	end

	-- physics shove: constant velocity for PUSH_DURATION covers PUSH_STUDS
	if pushDirection and pushDirection.Magnitude > 0.01 then
		local flat = Vector3.new(pushDirection.X, 0, pushDirection.Z)
		if flat.Magnitude > 0.01 then
			local pushVelocity = flat.Unit * (cfg.PUSH_STUDS / cfg.PUSH_DURATION)
			task.spawn(function()
				local started = os.clock()
				while os.clock() - started < cfg.PUSH_DURATION do
					if not self.root.Parent then
						return
					end
					self.root.AssemblyLinearVelocity = Vector3.new(pushVelocity.X, self.root.AssemblyLinearVelocity.Y, pushVelocity.Z)
					task.wait()
				end
				self.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end)
		end
	end
end

-- BSODA sustained push: freeze the NPC's brain and shove it along `direction`
-- at `speed` studs/s for up to maxDuration seconds — or until it runs into a
-- wall (a short ray cast with stopParams, which should exclude characters so
-- only real geometry counts). The classic Baldi spray: the character can't
-- move while sprayed, and the spray dissipates when it pins them to a wall or
-- its lifespan runs out. Yields until the push ends.
function NpcBase:pushBy(direction, speed, maxDuration, stopParams)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	local dir = flat.Unit
	local alreadyStunned = self:isStunned()
	self.stunnedUntil = os.clock() + maxDuration
	self:stopPath()
	self.humanoid.WalkSpeed = 0
	self.humanoid:MoveTo(self.root.Position)

	-- blue spray flash for the push (Highlight works on any rig)
	if not alreadyStunned then
		self:say("Stunned")
		local flash = Instance.new("Highlight")
		flash.Name = "StunFlash"
		flash.FillColor = Color3.fromRGB(120, 180, 255)
		flash.FillTransparency = 0.35
		flash.OutlineTransparency = 0.5
		flash.Parent = self.model
		task.spawn(function()
			while self:isStunned() do
				task.wait(0.1)
			end
			flash:Destroy()
			self:applySpeed()
		end)
	end

	local started = os.clock()
	while os.clock() - started < maxDuration do
		if not self.root.Parent then
			return
		end
		-- pinned against a wall? the spray dissipates and lets them go
		if stopParams and workspace:Raycast(self.root.Position, dir * 3.5, stopParams) then
			break
		end
		self.root.AssemblyLinearVelocity =
			Vector3.new(dir.X * speed, self.root.AssemblyLinearVelocity.Y, dir.Z * speed)
		task.wait()
	end
	self.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	self.stunnedUntil = os.clock() -- release the brain now
	self:applySpeed()
end

-- ===================== sight =====================

-- True when there is a clear line of sight from this NPC to targetRoot.
function NpcBase:canSee(targetRoot, maxDistance)
	if not targetRoot or not targetRoot.Parent then
		return false
	end
	local origin = self.root.Position + Vector3.new(0, 1.5, 0)
	local delta = targetRoot.Position - origin
	if delta.Magnitude > maxDistance then
		return false
	end
	local result = workspace:Raycast(origin, delta, self.rayParams)
	if result == nil then
		return true
	end
	return result.Instance:IsDescendantOf(targetRoot.Parent)
end

-- True when the NPC can WALK straight to targetPos without pathfinding:
-- three knee-height rays (center + both shoulders, so body width is
-- accounted for) hit no geometry, and there is floor under the midpoint.
-- Knee height catches desks and rails a torso-height ray would skim over.
-- trim shortens the ray near the goal (default 2.5) so a player standing
-- AT the goal doesn't read as a wall; pass 0 when the goal is geometry
-- and the full line must be checked.
function NpcBase:walkableLine(targetPos, trim)
	local origin = self.root.Position + Vector3.new(0, -1, 0)
	local delta = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
	local distance = delta.Magnitude
	if distance < 2 then
		return true
	end
	local direction = delta / distance
	local reach = math.max(distance - (trim or 2.5), 1)
	local side = Vector3.new(-direction.Z, 0, direction.X) * self.pathing.bodyClearance -- shoulders at the body radius, so it never green-lights a line its body would clip

	for _, offset in ipairs({ Vector3.zero, side, -side }) do
		if workspace:Raycast(origin + offset, direction * reach, self.rayParams) then
			return false
		end
	end

	-- don't straight-line over a hole: require floor under the midpoint
	-- (gentle ramps still pass; anything resembling a pit fails to pathfinding)
	local mid = origin + direction * (reach * 0.5)
	return workspace:Raycast(mid, Vector3.new(0, -7, 0), self.rayParams) ~= nil
end

-- ===================== pathfinding core =====================

-- One-off route check (no movement): the waypoints a route to targetPosition
-- would take, or nil. Used by the Baldi-style lunge and the wander probe.
function NpcBase:computePath(targetPosition)
	local ok = pcall(function()
		self.probePath:ComputeAsync(self.root.Position, targetPosition)
	end)
	if ok and self.probePath.Status == Enum.PathStatus.Success then
		return self.probePath:GetWaypoints()
	end
	return nil
end

-- Back out of a wedge: shove away from whatever we're pressed against,
-- hop, and turn, so the next route starts from open floor.
function NpcBase:unstickNudge()
	self:stopPath()
	local back = -self.root.CFrame.LookVector
	local sideSign = (self.rng:NextNumber() > 0.5) and 1 or -1
	local side = self.root.CFrame.RightVector * sideSign
	local escape = (back + side)
	if escape.Magnitude > 0.01 then
		escape = escape.Unit
		self.humanoid:MoveTo(self.root.Position + escape * 5)
	end
	if self.agentParams.AgentCanJump then
		self.humanoid.Jump = true
	end
	task.wait(0.3)
end

-- Move toward a single point and WAIT for arrival. Only used for legs where
-- stopping at the exact point is the intent (SweeperAI's straight sweep
-- runs, the lunge). Everything else goes through the travel engine below.
-- Returns:
--   "reached"    arrived
--   "stuck"      no progress for STUCK_GRACE seconds (caller should recompute)
--   "abort"      abortCheck() asked us to stop
--   "interrupted" paused/stunned mid-leg
--   "timeout"    maxDuration elapsed while still moving (caller repaths)
--   "blocked"    humanoid gave up on this point
function NpcBase:stepTo(position, abortCheck, maxDuration)
	local humanoid = self.humanoid
	local root = self.root
	if humanoid.Health <= 0 then
		return "interrupted"
	end
	self:stopPath()

	local finished, reached = false, false
	local conn = humanoid.MoveToFinished:Connect(function(ok)
		finished = true
		reached = ok
	end)
	humanoid:MoveTo(position)

	local startTime = os.clock()
	local distance = (position - root.Position).Magnitude
	local walkTimeout = distance / math.max(humanoid.WalkSpeed, 1) + 1.5
	local lastProgressPos = root.Position
	local lastProgressTime = startTime
	local result

	while true do
		if finished then
			result = reached and "reached" or "blocked"
			break
		end
		if self.paused or self:isStunned() then
			result = "interrupted"
			break
		end
		if abortCheck and abortCheck() then
			result = "abort"
			break
		end
		local now = os.clock()
		if maxDuration and now - startTime > maxDuration then
			result = "timeout"
			break
		end
		if now - startTime > walkTimeout then
			result = "stuck"
			break
		end
		local moved = (root.Position - lastProgressPos).Magnitude
		if moved > STUCK_PROGRESS then
			lastProgressPos = root.Position
			lastProgressTime = now
		elseif now - lastProgressTime > STUCK_GRACE then
			result = "stuck"
			break
		end
		task.wait(STEP_POLL)
	end

	conn:Disconnect()
	return result
end

-- ===================== travel engine (SimplePath) =====================

-- Drive the NPC toward a (possibly live) goal. opts:
--   getGoal()      -> Vector3 to head for right now, or nil to end travel
--   getSpeed()     -> current WalkSpeed (read every tick, so eased speeds work)
--   abortCheck()   optional; true ends travel with "aborted"
--   onTick()       optional; fired about every 0.25s (e.g. the chase noise)
--   getRepath()    optional; max seconds a chase route may age before re-routing
--   movingGoal     true for pursuit: keep re-routing as the goal moves and
--                  never give up on a failed route (the target may come back)
--   arriveRadius   "arrived" distance (default GameConfig PATHING.ARRIVE_RADIUS)
-- Returns "reached" | "ended" (goal nil) | "aborted" | "interrupted" | "noPath".
function NpcBase:travel(opts)
	local humanoid = self.humanoid
	local root = self.root
	local path = self.path
	local tuning = self.pathing
	local arriveRadius = opts.arriveRadius or tuning.arriveRadius
	local defaultRepath = self.ctx.config.NPC.REPATH_INTERVAL or 0.35

	-- this trip's state; SimplePath's event handlers (see new) write into it
	local state = {
		needRoute = true, -- ask SimplePath for a (fresh) route
		routing = false, -- a path:Run() is computing right now
		reached = false, -- SimplePath walked the whole route
		closed = false, -- the trip is over: ignore late results
		direct = false, -- steering straight at the goal, no route
		routeGoal = nil, -- where the current route leads
		routeBornAt = 0,
		failures = 0, -- routes in a row that couldn't be computed
		retryAt = 0,
	}
	self:stopPath()
	self.travelState = state

	local lastTickAt = 0
	local lastProgressPos = root.Position
	local lastProgressAt = os.clock()

	local function finish(result)
		state.closed = true
		-- let an in-flight route land before handing the humanoid back, or
		-- its first MoveTo would hijack whatever moves the NPC next
		local deadline = os.clock() + 1
		while state.routing and os.clock() < deadline do
			task.wait()
		end
		self:stopPath()
		if self.travelState == state then
			self.travelState = nil
		end
		return result
	end

	local function requestRoute(goal)
		state.routing = true
		state.needRoute = false
		state.reached = false
		task.spawn(function()
			local ok = path:Run(goal) -- yields while computing; the NPC keeps walking meanwhile
			state.routing = false
			if state.closed or state.direct then
				self:stopPath()
				return
			end
			if ok then
				state.routeGoal = goal
				state.routeBornAt = os.clock()
				state.failures = 0
			else
				-- LimitReached only means "asked again too soon"
				if path.LastError ~= SimplePath.ErrorType.LimitReached then
					state.failures += 1
				end
				state.needRoute = true
				state.retryAt = os.clock() + tuning.computeRetry
			end
		end)
	end

	while true do
		if humanoid.Health <= 0 or not self.model.Parent or self.paused or self:isStunned() then
			return finish("interrupted")
		end
		if opts.abortCheck and opts.abortCheck() then
			return finish("aborted")
		end
		local goal = opts.getGoal()
		if not goal then
			return finish("ended")
		end

		self:setMoveSpeed(opts.getSpeed())

		local now = os.clock()
		if now - lastTickAt > 0.25 then
			lastTickAt = now
			if opts.onTick then
				opts.onTick()
			end
			self:chaseTick()
		end

		local pos = root.Position
		local toGoal = goal - pos
		local flatDistance = Vector3.new(toGoal.X, 0, toGoal.Z).Magnitude

		-- arrival
		if flatDistance <= arriveRadius and math.abs(toGoal.Y) < 6 then
			if opts.movingGoal then
				-- press onto the live goal (catch checks live in the AIs)
				if not state.direct then
					state.direct = true
					self:stopPath()
				end
				humanoid:MoveTo(goal)
				lastProgressPos = pos
				lastProgressAt = now
				task.wait(tuning.poll)
				continue
			end
			local result = finish("reached")
			humanoid:MoveTo(root.Position)
			return result
		end

		-- Y gate clears a player's jump arc (~5 studs) but still excludes
		-- goals on a floor above/below, which need a real route
		if math.abs(toGoal.Y) < 7 and flatDistance <= tuning.directRange and self:walkableLine(goal) then
			-- clear straight shot on our level: no route, re-aim every tick
			if not state.direct then
				state.direct = true
				self:stopPath()
			end
			humanoid:MoveTo(goal)
			state.failures = 0
		else
			if state.direct then
				state.direct = false
				state.needRoute = true -- left the straight line: route from here
			end
			if state.reached then
				if not opts.movingGoal then
					-- the route got us as close as the navmesh allows: arrived
					local result = finish("reached")
					humanoid:MoveTo(root.Position)
					return result
				end
				state.needRoute = true -- walked the whole route but the goal moved on
			end
			if path.Status ~= ROUTE_ACTIVE and not state.routing then
				state.needRoute = true
			elseif opts.movingGoal and state.routeGoal then
				local maxAge = (opts.getRepath and opts.getRepath()) or defaultRepath
				if (goal - state.routeGoal).Magnitude > tuning.repathDistance
					or now - state.routeBornAt > maxAge then
					state.needRoute = true
				end
			end
			if state.needRoute and not state.routing and now >= state.retryAt then
				requestRoute(goal)
			end
			if not opts.movingGoal and state.failures >= 3 and not state.routing then
				local result = finish("noPath")
				humanoid:MoveTo(root.Position)
				return result
			end
		end

		-- stuck detection: trying to move but gaining no ground -> nudge free
		-- and route again from open floor
		if (state.direct or path.Status == ROUTE_ACTIVE) and humanoid.WalkSpeed > 0 then
			if (pos - lastProgressPos).Magnitude > STUCK_PROGRESS then
				lastProgressPos = pos
				lastProgressAt = now
			elseif now - lastProgressAt > STUCK_GRACE then
				self:unstickNudge()
				state.direct = false
				state.needRoute = true
				lastProgressPos = root.Position
				lastProgressAt = os.clock()
			end
		else
			lastProgressPos = pos
			lastProgressAt = now
		end

		task.wait(tuning.poll)
	end
end

-- ===================== Baldi-style stepped movement =====================

-- One Baldi lunge: SimplePath routes to goalPosition and the NPC bursts
-- along that route (around corners, through doorways, jumping where it
-- jumps) at `speed` until it has covered stepStuds of ground or moveTime
-- runs out, then stops dead. The caller plays the slap and handles the
-- pause between lunges — this is ChatRevive's stop-and-go cadence.
-- Yields until the lunge ends; returns the studs actually covered.
function NpcBase:stepToward(goalPosition, stepStuds, speed, moveTime)
	local humanoid = self.humanoid
	local root = self.root
	local path = self.path
	self:stopPath()
	self:setMoveSpeed(speed)

	-- route this lunge; with no route this time (or asked too soon), lunge
	-- straight at the goal rather than freezing
	local routed = path:Run(goalPosition)
	if not routed then
		humanoid:MoveTo(goalPosition)
	end

	local startedAt = os.clock()
	local last = root.Position
	local covered = 0
	while covered < stepStuds and os.clock() - startedAt < moveTime do
		if self.paused or self:isStunned() or not self.model.Parent or humanoid.Health <= 0 then
			break
		end
		if routed and path.Status ~= ROUTE_ACTIVE then
			break -- walked the whole route: we're on top of the goal
		end
		task.wait()
		local pos = root.Position
		covered += Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
		last = pos
	end

	-- dead stop until the next slap
	self:stopPath()
	humanoid.WalkSpeed = 0
	humanoid:MoveTo(root.Position)
	return covered
end

-- ===================== roaming (fixed destination) =====================

-- Walk a full route to a fixed point. Returns true only if we actually
-- arrived. abortCheck() bailing returns false early.
function NpcBase:navigateTo(targetPosition, speed, abortCheck)
	return self:travel({
		getGoal = function()
			return targetPosition
		end,
		getSpeed = function()
			return speed
		end,
		abortCheck = abortCheck,
	}) == "reached"
end

-- One roam leg: walk to a random waypoint part. With no waypoints, wander
-- to a random nearby point we can actually reach (never into a wall).
function NpcBase:roamStep(speed, abortCheck)
	self:say("Idle")
	local parts = {}
	for _, node in ipairs(self.ctx.map.waypointsFolder:GetChildren()) do
		if node:IsA("BasePart") then
			table.insert(parts, node)
		end
	end
	if #parts == 0 then
		self:wanderStep(speed, abortCheck)
		return
	end
	-- prefer a waypoint that isn't the one we're already standing on
	local node = parts[self.rng:NextInteger(1, #parts)]
	if #parts > 1 and (node.Position - self.root.Position).Magnitude < ARRIVE_RADIUS then
		node = parts[self.rng:NextInteger(1, #parts)]
	end
	self:navigateTo(node.Position, speed, abortCheck)
end

-- Fallback roam when the map has no Waypoints folder: try a few random
-- nearby offsets and walk to the first one a route actually exists to.
function NpcBase:wanderStep(speed, abortCheck)
	for _ = 1, 6 do
		if abortCheck and abortCheck() then
			return
		end
		local angle = self.rng:NextNumber(0, math.pi * 2)
		local dist = self.rng:NextNumber(12, 28)
		local candidate = self.root.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		if self:computePath(candidate) then
			self:navigateTo(candidate, speed, abortCheck)
			return
		end
	end
	task.wait(0.3)
end

-- ===================== pursuit (moving target) =====================

-- Continuously chase a moving target. getGoal() returns the Vector3 to head
-- for right now (the target's live position, or a remembered spot), or nil
-- to stop chasing. getSpeed() returns the current chase speed. onTick() runs
-- about every quarter second (e.g. the chase noise). The caller's getGoal
-- decides memory and give-up logic; this drives the movement and recovers
-- from wedging. getRepath (optional): max seconds a route may age before
-- re-routing (ChatRevive tightens it as heat rises) — a big goal move
-- always forces an immediate re-route regardless, and with a clear straight
-- line no routing happens at all.
function NpcBase:pursue(getGoal, getSpeed, onTick, getRepath)
	while self:canAct() do
		local result = self:travel({
			getGoal = getGoal,
			getSpeed = getSpeed,
			onTick = onTick,
			getRepath = getRepath,
			movingGoal = true,
			arriveRadius = 1.5,
		})
		if result ~= "interrupted" then
			return
		end
		-- interrupted = stunned/paused mid-chase; canAct() gates the retry
		task.wait(0.1)
	end
end

return NpcBase
