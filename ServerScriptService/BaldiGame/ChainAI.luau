--[[
	ChainAI (ModuleScript, ServerScriptService.BaldiGame.ChainAI)

	The shackler — a MULTIPLAYER-only character (he's parked in every mode
	whose roster doesn't list him; only MATCH does).

	He roams slowly and, when he spots a free player, closes in. The moment he
	gets within CATCH_DISTANCE he CLAMPS a chain onto that player. From then on
	the victim DRAGS Chain around like a ball-and-chain:
	  - the victim is slowed to DRAG_SLOW (applied client-side via the
	    ChainShackled popup, which reads the multiplier from GameConfig),
	  - Chain is anchored and dragged each Heartbeat so it trails the victim
	    within TETHER_LENGTH studs (a visible Beam links the two),
	  - the victim stays fully in play — still fair game for the hunter — so
	    the slow, not the grab, is the punishment.

	Breaking free (one victim at a time):
	  - MASH the tug-of-war (ChainTug remote): each valid press adds
	    TUG_PER_MASH strain; reaching TUG_REQUIRED snaps the chain. Strain
	    bleeds off at TUG_DECAY/sec, so stopping loses ground.
	  - Safety Scissors (ChainSnip remote) cut it instantly and leave Chain
	    snipped (stunned) for SCISSORS_DISABLE seconds.
	  - A BSODA hit on Chain mid-drag also shakes the chain loose.

	After any release the victim gets SHACKLE_IMMUNITY seconds of protection
	and Chain rests for COOLDOWN before hunting again.

	Server-side validation: the client only reports mashes; the server counts
	them, ignores any closer together than TUG_MIN_GAP, and owns the snap.

	Custom rig: ReplicatedStorage/BaldiAssets/Npcs/Chain
]]

local RunService = game:GetService("RunService")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)

local ChainAI = {}

local COLOR_BODY = Color3.fromRGB(95, 98, 108)
local COLOR_HEAD = Color3.fromRGB(130, 133, 143)
local LINK_COLOR = Color3.fromRGB(70, 72, 80)

function ChainAI.init(ctx)
	local cfg = ctx.config.NPC.CHAIN
	local self = { ctx = ctx, cfg = cfg }

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(185, 188, 198),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.CHAIN,
		(cfg.ROAM_SPEED + cfg.CHASE_SPEED) / 2)
	self.base = base
	self.model = model

	-- ---------- shackle state ----------

	local shackled = nil -- { player, hrp, strain, lastTugAt, link }
	local immunityUntil = {} -- [player] = time they can be shackled again
	local cooldownUntil = 0 -- Chain rests after releasing a victim
	local collideSnapshot = nil -- part -> original CanCollide, restored on release

	function self.isShackling(player)
		return shackled ~= nil and shackled.player == player
	end

	-- ---------- the chain visual (a Beam from Chain to the victim) ----------

	local function makeLink(hrp)
		local a0 = Instance.new("Attachment")
		a0.Name = "ChainLink0"
		a0.Parent = base.root
		local a1 = Instance.new("Attachment")
		a1.Name = "ChainLink1"
		a1.Parent = hrp
		local beam = Instance.new("Beam")
		beam.Name = "ShackleChain"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 0.55
		beam.Width1 = 0.55
		beam.FaceCamera = true
		beam.Segments = 16
		beam.CurveSize0 = 4 -- a little droop, like a heavy chain
		beam.CurveSize1 = 4
		beam.Color = ColorSequence.new(LINK_COLOR)
		beam.LightInfluence = 1
		-- (optional) paste a chain-link texture id here for real links:
		beam.Texture = "rbxassetid://12694722890"  beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.Parent = base.root
		return { a0 = a0, a1 = a1, beam = beam }
	end

	local function destroyLink(link)
		if not link then
			return
		end
		if link.beam then link.beam:Destroy() end
		if link.a0 then link.a0:Destroy() end
		if link.a1 then link.a1:Destroy() end
	end

	-- ---------- release ----------

	local function releaseShackle(reason)
		if not shackled then
			return
		end
		local player = shackled.player
		destroyLink(shackled.link)
		shackled = nil
		cooldownUntil = os.clock() + cfg.COOLDOWN
		immunityUntil[player] = os.clock() + cfg.SHACKLE_IMMUNITY

		-- let the dragged Chain rejoin the world
		base.root.Anchored = false
		if collideSnapshot then
			for part, was in pairs(collideSnapshot) do
				if part.Parent then
					part.CanCollide = was
				end
			end
			collideSnapshot = nil
		end
		base.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

		if player.Parent then
			ctx.remotes.ChainReleased:FireClient(player, reason)
		end
	end

	-- ---------- target finding ----------

	local function targetRoot(player)
		local character = player and player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end

	local function canShackle(player)
		return (immunityUntil[player] or 0) <= os.clock()
			and not ctx.detention.hasImmunity(player)
			and not self.isShackling(player)
	end

	-- ---------- shackle ----------

	local function startShackle(player, hrp)
		shackled = {
			player = player,
			hrp = hrp,
			strain = 0,
			lastTugAt = 0,
			link = makeLink(hrp),
		}

		base:stop()
		-- freeze Chain so it can be dragged by CFrame without physics fighting:
		-- drop collisions (so a dragged body never snags on geometry) and anchor
		-- the root; the Heartbeat below moves it.
		collideSnapshot = {}
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				collideSnapshot[part] = part.CanCollide
				part.CanCollide = false
			end
		end
		base.root.Anchored = true
		base.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

		-- face the victim as he clamps on
		local look = Vector3.new(hrp.Position.X, base.root.Position.Y, hrp.Position.Z)
		if (look - base.root.Position).Magnitude > 0.5 then
			base.root.CFrame = CFrame.lookAt(base.root.Position, look)
		end

		ctx.remotes.ChainShackled:FireClient(player)
		base:say("Shackle", { target = player, force = true })

		-- watcher: end the shackle if the round/victim conditions break
		task.spawn(function()
			while shackled and shackled.player == player do
				if not ctx.manager.isRoundActive() or not ctx.manager.isParticipant(player) then
					releaseShackle("ended")
					return
				end
				if ctx.detention.isDetained(player) then
					releaseShackle("ended") -- hauled to detention: the chain comes off
					return
				end
				if base:isStunned() then -- BSODA'd mid-drag: the chain shakes loose
					releaseShackle("ended")
					return
				end
				local character = player.Character
				if not character or character:FindFirstChild("HumanoidRootPart") ~= shackled.hrp then
					releaseShackle("ended")
					return
				end
				task.wait(0.1)
			end
		end)
	end

	-- ---------- drag + strain decay (Heartbeat) ----------

	RunService.Heartbeat:Connect(function(dt)
		if shackled then
			-- strain bleeds off when the victim stops mashing
			shackled.strain = math.max(0, shackled.strain - cfg.TUG_DECAY * dt)

			local hrp = shackled.hrp
			if not hrp or not hrp.Parent then
				releaseShackle("ended")
				return
			end

			-- drag Chain so it trails the victim within TETHER_LENGTH studs
			local chainPos = base.root.Position
			local playerPos = hrp.Position
			local flat = Vector3.new(playerPos.X - chainPos.X, 0, playerPos.Z - chainPos.Z)
			local dist = flat.Magnitude
			local targetPos
			if dist > cfg.TETHER_LENGTH and dist > 0.001 then
				local dir = flat.Unit -- taut: reel Chain in to exactly tether length
				targetPos = Vector3.new(
					playerPos.X - dir.X * cfg.TETHER_LENGTH,
					chainPos.Y,
					playerPos.Z - dir.Z * cfg.TETHER_LENGTH
				)
			else
				targetPos = chainPos -- slack: dead weight, stays put
			end
			-- follow the victim's height loosely so ramps/stairs don't strand him
			local targetY = chainPos.Y + (playerPos.Y - chainPos.Y) * 0.1
			targetPos = Vector3.new(targetPos.X, targetY, targetPos.Z)

			local look = Vector3.new(playerPos.X, targetPos.Y, playerPos.Z)
			local goalCF = ((look - targetPos).Magnitude > 0.5)
				and CFrame.lookAt(targetPos, look)
				or CFrame.new(targetPos)
			base.root.CFrame = base.root.CFrame:Lerp(goalCF, cfg.DRAG_FOLLOW)
			return
		end

		-- not shackled: clamp onto a free player who wanders too close
		if not base:isActive() or os.clock() < cooldownUntil then
			return
		end
		if not ctx.manager or not ctx.manager.isRoundActive() then
			return
		end
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			if canShackle(player) then
				local hrp = targetRoot(player)
				if hrp and (hrp.Position - base.root.Position).Magnitude < cfg.CATCH_DISTANCE then
					startShackle(player, hrp)
					break
				end
			end
		end
	end)

	-- ---------- break-free remotes ----------

	ctx.remotes.ChainTug.OnServerEvent:Connect(function(player)
		if not shackled or shackled.player ~= player then
			return
		end
		local now = os.clock()
		if now - shackled.lastTugAt < cfg.TUG_MIN_GAP then
			return -- too fast to be a real mash
		end
		shackled.lastTugAt = now
		shackled.strain = math.min(cfg.TUG_REQUIRED, shackled.strain + cfg.TUG_PER_MASH)
		if shackled.strain >= cfg.TUG_REQUIRED then
			releaseShackle("snapped")
		end
	end)

	ctx.remotes.ChainSnip.OnServerEvent:Connect(function(player)
		if not shackled or shackled.player ~= player then
			return
		end
		if ctx.economy.consumeItem(player, "SCISSORS") then
			releaseShackle("snipped")
			base:stun(cfg.SCISSORS_DISABLE, nil) -- snipped! (after release unanchors him)
		end
	end)

	-- ---------- target scan ----------

	local lastScan = 0
	local cachedTarget = nil

	local function findVictim()
		if os.clock() - lastScan < cfg.SIGHT_INTERVAL then
			return cachedTarget
		end
		lastScan = os.clock()
		cachedTarget = nil
		if not ctx.manager or shackled or os.clock() < cooldownUntil then
			return nil
		end
		local bestDistance = math.huge
		for _, player in ipairs(ctx.manager.getTargetablePlayers()) do
			if canShackle(player) then
				local hrp = targetRoot(player)
				if hrp then
					local distance = (hrp.Position - base.root.Position).Magnitude
					if distance < bestDistance and base:canSee(hrp, cfg.SIGHT_RANGE) then
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
		base:beginChase(player) -- "Spotted"

		base:pursue(
			function()
				if shackled or os.clock() < cooldownUntil then
					return nil
				end
				if not ctx.manager.isRoundActive() then
					return nil
				end
				local hrp = targetRoot(player)
				if not hrp or not ctx.manager.isTargetable(player) or not canShackle(player) then
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
			function()
				return cfg.CHASE_SPEED
			end
		)
		base:endChase() -- "Lost", if they actually got away
	end

	-- ---------- main brain loop ----------

	task.spawn(function()
		while true do
			if not base:canAct() or shackled then
				task.wait(0.2)
			else
				local victim = findVictim()
				if victim then
					chase(victim)
				else
					base:roamStep(cfg.ROAM_SPEED, function()
						return findVictim() ~= nil
					end)
				end
			end
		end
	end)

	-- ---------- reset between rounds ----------

	function self.reset()
		releaseShackle("ended")
		immunityUntil = {}
		cooldownUntil = 0
		base:resetToSpawn()
	end

	ctx.npcs.Chain = self
	return self
end

return ChainAI
