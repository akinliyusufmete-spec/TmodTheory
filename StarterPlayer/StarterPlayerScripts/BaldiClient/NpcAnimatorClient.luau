--[[
	NpcAnimatorClient (ModuleScript, StarterPlayerScripts.BaldiClient.NpcAnimatorClient)

	Drives NPC animations entirely on the client (so they don't have to be
	published under the game owner's account to play). For each NPC model
	that appears under an "Npcs" folder in workspace:
	  - AnimationLoader.forCharacter loads its tracks once: the ids in
	    CharacterConfig.<Name>.Animations, plus the rig's own Animations
	    folder for anything the config leaves blank.
	  - Idle / Walk / Chase switch by the NPC's movement: Chase above the
	    rig's "ChaseAnimSpeed" attribute (NpcBase sets it per character),
	    Walk below it, Idle when standing. Walk's playback speed follows how
	    fast the NPC actually moves (CharacterConfig WalkAnimSpeed = 1x).
	  - Actions: while the rig's "Action" attribute names one of its
	    animations (NpcBase:playAction), it plays over the movement layer.
	    Its CharacterConfig entry decides how: Loop repeats it whole,
	    LoopStart / LoopEnd repeat the stretch between two event markers,
	    and Finish lets it play to the end once the action is over (instead
	    of fading out). A Cycle action is restarted by the server each beat
	    instead (the rig's ActionCycle / ActionRate attributes): ChatRevive's
	    Dash plays once per slap, in step on every client.
	  - A rig with no usable tracks at all (the placeholder rigs) gets a
	    procedural R6 limb swing instead.

	Every client runs this on its own, so all players see NPCs animate
	without any cross-client coordination. The returned controller has
	playOneShot(model, name) for voicelines that come with an emote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local AnimationLoader = require(shared:WaitForChild("AnimationLoader"))
local CharacterConfig = require(shared:WaitForChild("CharacterConfig"))

local NpcAnimatorClient = {}

local POLL_INTERVAL = 0.12
local MOVING_THRESHOLD = 0.5 -- studs/sec; below = "standing"
local DEFAULT_CHASE_SPEED = 28 -- when the rig has no ChaseAnimSpeed attribute
local WALK_RATE_MIN = 0.3 -- Walk playback speed limits (x normal)
local WALK_RATE_MAX = 4
local ACTION_FADE = 0.15

-- Standard R6 swing joints and direction sign.
local SWING_JOINTS = {
	["Left Hip"]      =  1,
	["Right Hip"]     = -1,
	["Left Shoulder"] = -1,
	["Right Shoulder"] = 1,
}

-- ===================== track animation =====================

local function runTrackLoop(model, humanoid, loader, state)
	local walkReference = math.max(1, CharacterConfig.get(model.Name).WalkAnimSpeed or 16)

	-- the state to play when the wanted one is missing: Chase -> Walk, and a
	-- rig with only a Walk loop still moves while standing
	local function available(name)
		if loader:has(name) then
			return name
		end
		if (name == "Chase" or name == "Idle") and loader:has("Walk") then
			return "Walk"
		end
		return nil
	end

	task.spawn(function()
		while state.running and model.Parent do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local vel = root.AssemblyLinearVelocity
				local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
				local wanted
				if speed < MOVING_THRESHOLD then
					wanted = "Idle"
				elseif humanoid.WalkSpeed > (model:GetAttribute("ChaseAnimSpeed") or DEFAULT_CHASE_SPEED) then
					wanted = "Chase"
				else
					wanted = "Walk"
				end
				local name = available(wanted)
				if name then
					local track = loader:switch(name, 0.2)
					if track and name == "Walk" then
						-- steps keep pace with the ground covered
						local rate = wanted == "Idle" and 1
							or math.clamp(speed / walkReference, WALK_RATE_MIN, WALK_RATE_MAX)
						track:AdjustSpeed(rate)
					end
				end
			end
			task.wait(POLL_INTERVAL)
		end
		loader:stopAll(0.15)
	end)
end

-- ===================== actions =====================

local function runActions(model, loader, state)
	local current = nil -- { name, track, settings, holding, connections }

	local function disconnect(entry)
		for _, connection in ipairs(entry.connections) do
			connection:Disconnect()
		end
		table.clear(entry.connections)
	end

	-- cutOff: another action takes over, so fade this one out regardless
	local function release(entry, cutOff)
		entry.holding = false
		disconnect(entry)
		if entry.settings.Finish and not cutOff then
			entry.track.Looped = false -- play on to the end, then stop
		else
			entry.track:Stop(ACTION_FADE)
		end
	end

	local function start(name)
		local track = loader:get(name)
		if not track then
			return
		end
		local settings = loader:action(name)
		local entry = { name = name, track = track, settings = settings, holding = true, connections = {} }
		current = entry

		local loopFrom = nil -- where the LoopStart marker sits (found on the first pass)
		local markerLoop = settings.LoopStart ~= nil or settings.LoopEnd ~= nil
		-- a marker loop keeps the track looping while held, so it can't run out
		-- and stop at its end (a LoopEnd marker often sits on the last frame)
		track.Looped = settings.Loop == true or markerLoop

		if settings.LoopStart then
			table.insert(entry.connections, track:GetMarkerReachedSignal(settings.LoopStart):Connect(function()
				loopFrom = loopFrom or track.TimePosition
			end))
		end
		if settings.LoopEnd then
			table.insert(entry.connections, track:GetMarkerReachedSignal(settings.LoopEnd):Connect(function()
				if entry.holding then
					track.TimePosition = loopFrom or 0
				end
			end))
		end
		if markerLoop then
			-- reaching the end while held: jump back just before the track wraps
			table.insert(entry.connections, RunService.Heartbeat:Connect(function(dt)
				if entry.holding and track.IsPlaying and track.Length > 0
					and track.TimePosition >= track.Length - dt * 1.5 then
					track.TimePosition = loopFrom or 0
				end
			end))
			table.insert(entry.connections, track.DidLoop:Connect(function()
				if entry.holding and loopFrom then
					track.TimePosition = loopFrom
				end
			end))
		end

		-- a Cycle action waits for the AI's beat (ActionCycle) to start it
		if not settings.Cycle then
			pcall(function()
				track:Play(ACTION_FADE)
			end)
		end
	end

	-- the AI's beat (ChatRevive's slaps): restart the action from the top at
	-- the rate the server picked, so every client shows the same moment
	local function restartBeat()
		if not current or not current.holding then
			return
		end
		local track = current.track
		local rate = model:GetAttribute("ActionRate") or 1
		if not track.IsPlaying then
			pcall(function()
				track:Play(0.05, 1, rate)
			end)
		end
		track.TimePosition = 0
		track:AdjustSpeed(rate)
	end

	local function apply()
		local wanted = model:GetAttribute("Action")
		if wanted == "" then
			wanted = nil
		end
		if current and current.holding and current.name == wanted then
			return
		end
		if current then
			release(current, wanted ~= nil)
			current = nil
		end
		if wanted then
			start(wanted)
		end
	end

	table.insert(state.cleanup, model:GetAttributeChangedSignal("Action"):Connect(apply))
	table.insert(state.cleanup, model:GetAttributeChangedSignal("ActionCycle"):Connect(restartBeat))
	table.insert(state.cleanup, {
		Disconnect = function()
			if current then
				disconnect(current)
				current = nil
			end
		end,
	})
	apply()
end

-- ===================== procedural walk fallback =====================

local function runProceduralLoop(model, state)
	local joints = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") and SWING_JOINTS[desc.Name] then
			table.insert(joints, { motor = desc, base = desc.C0, sign = SWING_JOINTS[desc.Name] })
		end
	end
	if #joints == 0 then return end

	task.spawn(function()
		local phase = 0
		while state.running and model.Parent do
			local dt = task.wait()
			local root = model:FindFirstChild("HumanoidRootPart")
			if not root then continue end
			local vel = root.AssemblyLinearVelocity
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if speed > MOVING_THRESHOLD then
				phase = phase + dt * (4 + math.clamp(speed, 0, 24) * 0.5)
				local swing = math.sin(phase) * math.rad(38)
				for _, j in ipairs(joints) do
					j.motor.C0 = j.base * CFrame.Angles(swing * j.sign, 0, 0)
				end
			else
				for _, j in ipairs(joints) do
					j.motor.C0 = j.motor.C0:Lerp(j.base, 0.2)
				end
			end
		end
	end)
end

-- ===================== per-model setup =====================

local function startAnimating(model, managed)
	if managed[model] then return end

	local state = { running = true, loader = nil, cleanup = {} }
	managed[model] = state

	-- Clean up when the model leaves workspace.
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			state.running = false
			managed[model] = nil
			for _, connection in ipairs(state.cleanup) do
				connection:Disconnect()
			end
			table.clear(state.cleanup)
			if state.loader then
				state.loader:destroy()
				state.loader = nil
			end
		end
	end)

	-- Streaming can hand the model over before its body (the map loading in
	-- at the first run does exactly that), so wait for the Humanoid and root
	-- for as long as it takes, then give it one more frame to settle.
	task.spawn(function()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		while state.running and not (humanoid and model:FindFirstChild("HumanoidRootPart")) do
			task.wait(0.25)
			humanoid = model:FindFirstChildOfClass("Humanoid")
		end
		if not state.running then return end
		task.wait()
		if not state.running then return end
		local loader = AnimationLoader.forCharacter(model, CharacterConfig.get(model.Name))
		if not state.running then
			loader:destroy()
			return
		end
		state.loader = loader
		if loader:count() > 0 then
			runTrackLoop(model, humanoid, loader, state)
			runActions(model, loader, state)
		else
			-- Procedural walk for placeholder rigs or models with no animations.
			runProceduralLoop(model, state)
		end
	end)
end

-- ===================== module entry point =====================

function NpcAnimatorClient.init(_ctx)
	local managed = {} -- [model] = state table

	-- Scan all current descendants and watch for new ones.
	local function tryAdd(instance)
		if not instance:IsA("Model") then return end
		local parent = instance.Parent
		if not parent or parent.Name ~= "Npcs" then return end
		startAnimating(instance, managed)
	end

	-- Catch NPCs already in workspace (client joined mid-game or Play Solo).
	-- tryAdd never yields, so no thread per descendant is needed.
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("Model") then
			tryAdd(desc)
		end
	end

	workspace.DescendantAdded:Connect(tryAdd)

	local self = {}

	-- Play one of this NPC's animations once (a voiceline's emote).
	function self.playOneShot(model, name)
		local state = model and managed[model]
		if state and state.loader then
			return state.loader:playOnce(name)
		end
		return nil
	end

	return self
end

return NpcAnimatorClient
