--[[
	StillYou (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.StillYou)

	"It's still you." — fully client-side. While active, every frame records
	the local character's HumanoidRootPart CFrame and its playing animation
	tracks into a short history (DELAY + 1 seconds). After the first notebook
	an inverted-colour copy of the character replays that history DELAY
	seconds behind you. Walking into it (HIT_DISTANCE) despawns it, inverts
	your movement for INVERT_SECONDS and brings it back RESPAWN_SECONDS later
	(still DELAY behind: it just resumes replaying the history).

	The clone:
	  - a Clone() of the live character, parented to workspace on this client
	    only (nothing replicates), named StillYouClone
	  - every script, sound, ForceField and prompt stripped
	  - the Humanoid is KEPT (Shirt / Pants / BodyColors only render on a
	    model with a Humanoid, and its Animator plays the replayed tracks) but
	    its state machine is switched off, so it never walks, falls or dies
	  - only the HumanoidRootPart is anchored. Every other part stays
	    unanchored but jointed (Motor6D / welds) to it, so the whole assembly
	    is anchored all the same, yet the Animator can still move the limbs.
	    Anchoring every part would freeze the Motor6Ds and the replayed
	    animations would show nothing. A stray part that isn't jointed to the
	    root is anchored on its own so it can't fall away.
	  - CanCollide / CanTouch / CanQuery off (the camera never pops on it)
	  - colours inverted: parts, decals, textures, BodyColors, and the tint
	    of Shirt / Pants / ShirtGraphic (a tint can only darken, so clothing
	    comes out as dark as its tint inverts to — white tint becomes black,
	    which reads as the "shadow" version of you)

	Movement inversion wraps the default PlayerModule's ControlModule:
	  1. ControlModule.moveFunction(player, moveVector, relativeToCamera) is
	     replaced by a wrapper that negates moveVector, and put back after.
	  2. If that field is missing but GetMoveVector exists, a render step
	     right after the ControlModule's (RenderPriority.Input + 1) calls
	     humanoid:Move(-moveVector, true), overriding its move each frame.
	  3. If the PlayerModule can't be found at all, WASD / arrows / the left
	     thumbstick are sunk with ContextActionService and the negated vector
	     is fed to humanoid:Move each frame.
	The camera is never inverted.
]]

local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local StillYou = {}

local CLONE_NAME = "StillYouClone"
local OVERRIDE_BIND = "TmodStillYouInvert"
local SINK_ACTION = "TmodStillYouSink"
local PLAYER_MODULE_WAIT = 10 -- seconds; never wait forever for the PlayerModule
local TELEPORT_STUDS = 20 -- a jump bigger than this between two samples is a teleport: don't sweep across it
local REBUILD_RETRY = 1 -- seconds between attempts if a clone couldn't be built

-- the ControlModule (resolved once, in the background)
local controls = nil

-- everything a run changes; nil while inactive. Background tasks compare
-- against their own copy so they never act on a run that has stopped.
local state = nil

-- ---------- helpers ----------

local function invertColor(color)
	return Color3.new(1 - color.R, 1 - color.G, 1 - color.B)
end

local function characterParts(player)
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end
	return character, root, humanoid
end

local function resolveControls(player)
	local playerScripts = player:FindFirstChild("PlayerScripts") or player:WaitForChild("PlayerScripts", 5)
	if not playerScripts then
		return nil
	end
	local moduleScript = playerScripts:WaitForChild("PlayerModule", PLAYER_MODULE_WAIT)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall(require, moduleScript)
	if not ok or type(playerModule) ~= "table" or type(playerModule.GetControls) ~= "function" then
		return nil
	end
	local gotControls, result = pcall(playerModule.GetControls, playerModule)
	if gotControls and type(result) == "table" then
		return result
	end
	return nil
end

-- ---------- recording ----------

-- { [AnimationId] = { time, speed, weight } } for what the character plays now
local function snapshotTracks(humanoid)
	local tracks = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return tracks
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local animation = track.Animation
		local id = animation and animation.AnimationId
		if id and id ~= "" then
			local weight = track.WeightCurrent
			local existing = tracks[id]
			if not existing or existing.weight < weight then
				tracks[id] = { time = track.TimePosition, speed = track.Speed, weight = weight }
			end
		end
	end
	return tracks
end

-- the CFrame at time t, the sample at/before t, and seconds since that sample
local function sampleAt(buffer, t)
	local count = #buffer
	if count == 0 or buffer[1].t > t then
		return nil -- not DELAY seconds of history yet
	end
	local index = 1
	while index < count and buffer[index + 1].t <= t do
		index += 1
	end
	local a = buffer[index]
	local b = buffer[index + 1]
	if not b or b.t <= a.t or (b.cf.Position - a.cf.Position).Magnitude > TELEPORT_STUDS then
		return a.cf, a, t - a.t
	end
	local alpha = math.clamp((t - a.t) / (b.t - a.t), 0, 1)
	return a.cf:Lerp(b.cf, alpha), a, t - a.t
end

-- ---------- the clone ----------

local function destroyClone(s)
	local clone = s.clone
	if not clone then
		return
	end
	s.clone = nil
	for _, track in pairs(clone.tracks) do
		if track then
			pcall(function()
				track:Stop(0)
				track:Destroy()
			end)
		end
	end
	for _, animation in pairs(clone.animations) do
		animation:Destroy()
	end
	clone.model:Destroy()
end

local function stripAndInvert(model, root)
	for _, item in ipairs(model:GetDescendants()) do
		if
			item:IsA("LuaSourceContainer")
			or item:IsA("Sound")
			or item:IsA("ForceField")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
		then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = item == root
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
			item.Color = invertColor(item.Color)
		elseif item:IsA("Decal") then -- Texture is a Decal subclass
			item.Color3 = invertColor(item.Color3)
		elseif item:IsA("BodyColors") then
			item.HeadColor3 = invertColor(item.HeadColor3)
			item.TorsoColor3 = invertColor(item.TorsoColor3)
			item.LeftArmColor3 = invertColor(item.LeftArmColor3)
			item.RightArmColor3 = invertColor(item.RightArmColor3)
			item.LeftLegColor3 = invertColor(item.LeftLegColor3)
			item.RightLegColor3 = invertColor(item.RightLegColor3)
		elseif item:IsA("Clothing") or item:IsA("ShirtGraphic") then
			item.Color3 = invertColor(item.Color3)
		elseif item:IsA("SurfaceAppearance") then
			-- newer engines expose a tint on SurfaceAppearance; skip if not
			pcall(function()
				item.Color = invertColor(item.Color)
			end)
		end
	end
end

local function buildClone(character)
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, model = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not model then
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		model:Destroy()
		return nil
	end

	stripAndInvert(model, root)

	-- keep the Humanoid for clothing + Animator, but make it inert
	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	model.Name = CLONE_NAME
	model.PrimaryPart = root
	-- where the model's pivot sits relative to the root, so PivotTo can
	-- place the ROOT exactly on the recorded HumanoidRootPart CFrame
	local pivotOffset = root.CFrame:ToObjectSpace(model:GetPivot())
	model.Parent = workspace

	-- a part with no joint to the root would drop out of the model: anchor it
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored and part.AssemblyRootPart ~= root then
			part.Anchored = true
		end
	end

	return {
		model = model,
		root = root,
		animator = animator,
		pivotOffset = pivotOffset,
		tracks = {}, -- [AnimationId] = AnimationTrack, or false if it failed to load
		animations = {}, -- [AnimationId] = Animation
	}
end

-- mirror the recorded tracks: same ids, time position (advanced by the
-- recorded speed since the sample), weight. Speed is held at 0 and the time
-- is set every frame, so the clone never drifts from the recording.
local function driveTracks(clone, frame, elapsed)
	local seen = {}
	for id, info in pairs(frame.tracks) do
		local track = clone.tracks[id]
		if track == nil then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			clone.animations[id] = animation
			local ok, loaded = pcall(function()
				return clone.animator:LoadAnimation(animation)
			end)
			track = (ok and loaded) or false
			clone.tracks[id] = track
		end
		if track then
			seen[id] = true
			if not track.IsPlaying then
				track:Play(0.1, info.weight, 0)
			end
			track:AdjustSpeed(0)
			track:AdjustWeight(info.weight, 0)
			local position = info.time + elapsed * info.speed
			local length = track.Length
			if length > 0 then
				if track.Looped then
					position = position % length
				else
					position = math.clamp(position, 0, length)
				end
			end
			track.TimePosition = math.max(position, 0)
		end
	end
	for id, track in pairs(clone.tracks) do
		if track and not seen[id] and track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

-- ---------- movement inversion ----------

local MOVE_KEYS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}
local STICK_DEADZONE = 0.2

local function beginInvert(s, player)
	if s.invert then
		return
	end
	local invert = {}
	s.invert = invert

	if controls and type(controls.moveFunction) == "function" then
		-- 1. wrap ControlModule.moveFunction. The wrapper checks a flag
		-- rather than relying only on being swapped out, so if something
		-- else wrapped it on top of ours, ours still turns into a pass-through.
		local original = controls.moveFunction
		local wrapper
		wrapper = function(who, moveVector, ...)
			if invert.active and typeof(moveVector) == "Vector3" then
				return original(who, -moveVector, ...)
			end
			return original(who, moveVector, ...)
		end
		invert.mode = "wrap"
		invert.active = true
		invert.original = original
		invert.wrapper = wrapper
		controls.moveFunction = wrapper
		return
	end

	local function humanoidNow()
		local _, _, humanoid = characterParts(player)
		return humanoid
	end

	if controls and type(controls.GetMoveVector) == "function" then
		-- 2. override the ControlModule's move right after it runs
		invert.mode = "override"
		RunService:BindToRenderStep(OVERRIDE_BIND, Enum.RenderPriority.Input.Value + 1, function()
			local humanoid = humanoidNow()
			if not humanoid then
				return
			end
			local ok, moveVector = pcall(controls.GetMoveVector, controls)
			if ok and typeof(moveVector) == "Vector3" then
				humanoid:Move(-moveVector, true)
			end
		end)
		return
	end

	-- 3. no PlayerModule: take the movement keys ourselves
	invert.mode = "sink"
	local held = {}
	local stick = Vector3.zero
	local keys = { Enum.KeyCode.Thumbstick1 }
	for keyCode in pairs(MOVE_KEYS) do
		table.insert(keys, keyCode)
	end
	ContextActionService:BindActionAtPriority(SINK_ACTION, function(_, inputState, input)
		local ended = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local p = input.Position
			if ended or Vector2.new(p.X, p.Y).Magnitude < STICK_DEADZONE then
				stick = Vector3.zero
			else
				stick = Vector3.new(p.X, 0, -p.Y)
			end
		else
			held[input.KeyCode] = not ended
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	RunService:BindToRenderStep(OVERRIDE_BIND, Enum.RenderPriority.Input.Value + 1, function()
		local humanoid = humanoidNow()
		if not humanoid then
			return
		end
		local moveVector = stick
		for keyCode, isHeld in pairs(held) do
			if isHeld then
				moveVector += MOVE_KEYS[keyCode]
			end
		end
		if moveVector.Magnitude > 1 then
			moveVector = moveVector.Unit
		end
		humanoid:Move(-moveVector, true)
	end)
end

local function endInvert(s)
	local invert = s.invert
	if not invert then
		return
	end
	s.invert = nil
	invert.active = false
	if invert.mode == "wrap" then
		if controls and controls.moveFunction == invert.wrapper then
			controls.moveFunction = invert.original
		end
	else
		pcall(function()
			RunService:UnbindFromRenderStep(OVERRIDE_BIND)
		end)
		if invert.mode == "sink" then
			ContextActionService:UnbindAction(SINK_ACTION)
		end
	end
end

-- ---------- feature ----------

function StillYou.init(env)
	-- PlayerModule is required once in the background: it can take a moment
	-- to appear on join and must never hold up the controller
	task.spawn(function()
		controls = resolveControls(env.player)
		if not controls then
			warn("[Tmod] StillYou: PlayerModule controls not found; movement inversion falls back to key sinking.")
		end
	end)
end

function StillYou.start(env, _count)
	if state then
		StillYou.stop(env)
	end
	local s = {
		buffer = {}, -- { t, cf, tracks }, oldest first
		clone = nil,
		armed = false, -- true once the first notebook is in
		respawnAt = 0, -- os.clock() before which the clone stays away
		nextBuildAt = 0,
		invert = nil,
		invertUntil = 0,
	}
	state = s

	local function readNotebooks()
		local collected = workspace:GetAttribute("NotebooksCollected")
		s.armed = type(collected) == "number" and collected >= 1
		if not s.armed then
			destroyClone(s) -- a fresh run reset the count
		end
	end
	s.notebookConnection = workspace:GetAttributeChangedSignal("NotebooksCollected"):Connect(readNotebooks)
	readNotebooks()
end

function StillYou.stop(_env)
	local s = state
	if not s then
		return
	end
	state = nil
	if s.notebookConnection then
		s.notebookConnection:Disconnect()
		s.notebookConnection = nil
	end
	destroyClone(s)
	endInvert(s)
	table.clear(s.buffer)
end

function StillYou.step(env, _dt)
	local s = state
	if not s then
		return
	end
	local def = env.def
	local now = os.clock()
	local character, root, humanoid = characterParts(env.player)

	-- record this frame, then drop what's older than DELAY + 1 seconds
	-- (always keeping one sample at/before the replay time to lerp from)
	local buffer = s.buffer
	if root then
		table.insert(buffer, { t = now, cf = root.CFrame, tracks = snapshotTracks(humanoid) })
	end
	local cutoff = now - def.DELAY - 1
	while #buffer >= 2 and buffer[2].t <= cutoff do
		table.remove(buffer, 1)
	end

	if s.invert and now >= s.invertUntil then
		endInvert(s)
	end

	if not s.armed or now < s.respawnAt then
		return
	end

	local cf, frame, elapsed = sampleAt(buffer, now - def.DELAY)
	if not cf then
		destroyClone(s) -- not enough history: stay out of the way
		return
	end

	if s.clone and not s.clone.model:IsDescendantOf(workspace) then
		destroyClone(s) -- something removed it; rebuild
	end
	if not s.clone then
		if not character or now < s.nextBuildAt then
			return
		end
		s.clone = buildClone(character)
		if not s.clone then
			s.nextBuildAt = now + REBUILD_RETRY
			return
		end
	end

	local clone = s.clone
	clone.model:PivotTo(cf * clone.pivotOffset)
	driveTracks(clone, frame, elapsed)

	if root and humanoid.Health > 0 and (cf.Position - root.Position).Magnitude <= def.HIT_DISTANCE then
		destroyClone(s)
		s.respawnAt = now + def.RESPAWN_SECONDS
		s.invertUntil = now + def.INVERT_SECONDS
		beginInvert(s, env.player)
	end
end

return StillYou
