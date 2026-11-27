--[[
	AnimationLoader (ModuleScript, ReplicatedStorage.BaldiShared.AnimationLoader)

	Loads animations onto a rig's Animator once and keeps the tracks, so
	nothing loads the same animation twice. Works on any rig with a Humanoid
	or an AnimationController, on the client or the server.

	  local loader = AnimationLoader.new(model)
	  loader:load("Wave", "rbxassetid://123", { Looped = false, Priority = Enum.AnimationPriority.Action })
	  loader:play("Wave", fade?, weight?, speed?)  -> the track
	  loader:playOnce("Wave", fade?)               -> plays a looping track just once
	  loader:switch("Walk", fade?)                 -> exclusive "state" layer (Idle/Walk/Chase):
	                                                 crossfades out of the previous state
	  loader:stop("Wave", fade?) / loader:stopAll(fade?)
	  loader:get(name) / loader:has(name) / loader:count()
	  loader:destroy()

	  AnimationLoader.forCharacter(model, config)
	    builds a loader for an NPC: every id in config.Animations (CharacterConfig),
	    plus the Animation instances in the rig's own "Animations" folder that the
	    config doesn't override (false in the config skips the rig's entry too).
	    Idle / Walk / Chase / Run load as looping movement tracks; anything else
	    loads as an Action-priority track. An entry can be a table,
	    { Id = ..., Loop, LoopStart, LoopEnd, Finish }; loader:action(name)
	    returns it (NpcAnimatorClient plays those settings).

	Ids can be "rbxassetid://123", "123", 123 or an Animation instance. A blank
	id, an id that fails to load, or one that never gets a length (not owned by
	the place's creator, or made for the other rig type R6/R15) prints a warning
	naming the rig and the animation.
]]

local AnimationLoader = {}
AnimationLoader.__index = AnimationLoader

local MOVEMENT = { Idle = true, Walk = true, Chase = true, Run = true }

local function normalizeId(value)
	if typeof(value) == "number" then
		return value > 0 and ("rbxassetid://" .. value) or nil
	elseif typeof(value) == "string" then
		local trimmed = value:match("^%s*(.-)%s*$")
		if trimmed == "" then
			return nil
		end
		if tonumber(trimmed) then
			return "rbxassetid://" .. trimmed
		end
		return trimmed
	end
	return nil
end

local function findAnimator(model)
	local owner = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not owner then
		return nil
	end
	local animator = owner:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = owner
	end
	return animator
end

function AnimationLoader.new(model)
	return setmetatable({
		model = model,
		animator = findAnimator(model),
		tracks = {},
		owned = {}, -- Animation instances this loader made (destroyed with it)
		state = nil, -- name of the playing exclusive state track
		actions = {}, -- [name] = the config table of an action animation
	}, AnimationLoader)
end

function AnimationLoader:load(name, source, opts)
	if self.tracks[name] then
		return self.tracks[name]
	end
	opts = opts or {}
	local rigName = self.model and self.model.Name or "?"
	if not self.animator then
		warn(string.format("[AnimationLoader] %s has no Humanoid or AnimationController, can't load %s.", rigName, name))
		return nil
	end

	local animation
	if typeof(source) == "Instance" and source:IsA("Animation") then
		animation = source
		if animation.AnimationId == "" then
			warn(string.format("[AnimationLoader] %s/%s has a blank AnimationId.", rigName, name))
			return nil
		end
	else
		local id = normalizeId(source)
		if not id then
			return nil -- blank in the config: nothing to load
		end
		animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = id
		table.insert(self.owned, animation)
	end

	-- a freshly cloned rig can need a couple of tries before the Animator
	-- accepts a LoadAnimation
	local track
	for _ = 1, 3 do
		local ok, result = pcall(self.animator.LoadAnimation, self.animator, animation)
		if ok and result then
			track = result
			break
		end
		task.wait(0.1)
	end
	if not track then
		warn(string.format("[AnimationLoader] %s/%s (%s) failed to load.", rigName, name, animation.AnimationId))
		return nil
	end
	if opts.Looped ~= nil then
		track.Looped = opts.Looped
	end
	if opts.Priority then
		track.Priority = opts.Priority
	end
	self.tracks[name] = track

	-- LoadAnimation "succeeds" even when the asset can't be fetched; the
	-- track just stays length 0 and nothing visibly plays. Say so.
	task.spawn(function()
		local deadline = os.clock() + 6
		while track.Length == 0 and os.clock() < deadline do
			task.wait(0.25)
		end
		if track.Length == 0 and self.tracks[name] == track then
			warn(string.format(
				"[AnimationLoader] %s/%s (%s) loaded but stays length 0: publish it under the place's creator and check the rig type (R6 vs R15).",
				rigName, name, animation.AnimationId))
		end
	end)
	return track
end

function AnimationLoader:get(name)
	return self.tracks[name]
end

-- The settings an action animation was configured with ({} for a plain id).
function AnimationLoader:action(name)
	return self.actions[name] or {}
end

function AnimationLoader:has(name)
	return self.tracks[name] ~= nil
end

function AnimationLoader:count()
	local n = 0
	for _ in pairs(self.tracks) do
		n += 1
	end
	return n
end

function AnimationLoader:play(name, fade, weight, speed)
	local track = self.tracks[name]
	if track then
		pcall(function()
			track:Play(fade or 0.2, weight or 1, speed or 1)
		end)
	end
	return track
end

-- Play once even if the animation is set to loop (an emote during a voiceline).
function AnimationLoader:playOnce(name, fade)
	local track = self.tracks[name]
	if not track then
		return nil
	end
	local wasLooped = track.Looped
	track.Looped = false
	pcall(function()
		track:Play(fade or 0.1)
	end)
	if wasLooped then
		track.Stopped:Once(function()
			track.Looped = true
		end)
	end
	return track
end

-- The exclusive movement layer: only one state track plays at a time.
function AnimationLoader:switch(name, fade)
	if self.state == name then
		local current = self.tracks[name]
		if current and current.IsPlaying then
			return current
		end
	end
	local previous = self.state and self.tracks[self.state]
	if previous and self.state ~= name then
		pcall(function()
			previous:Stop(fade or 0.2)
		end)
	end
	self.state = name
	return self:play(name, fade)
end

function AnimationLoader:stop(name, fade)
	local track = self.tracks[name]
	if track then
		pcall(function()
			track:Stop(fade or 0.2)
		end)
	end
	if self.state == name then
		self.state = nil
	end
end

function AnimationLoader:stopAll(fade)
	for _, track in pairs(self.tracks) do
		pcall(function()
			track:Stop(fade or 0.2)
		end)
	end
	self.state = nil
end

function AnimationLoader:destroy()
	self:stopAll(0)
	for _, track in pairs(self.tracks) do
		pcall(function()
			track:Destroy()
		end)
	end
	for _, animation in ipairs(self.owned) do
		animation:Destroy()
	end
	table.clear(self.tracks)
	table.clear(self.owned)
end

function AnimationLoader.forCharacter(model, config)
	local loader = AnimationLoader.new(model)
	local sources = {}

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local folder = model:FindFirstChild("Animations") or (humanoid and humanoid:FindFirstChild("Animations"))
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Animation") then
				sources[child.Name] = child
			end
		end
	end
	for name, entry in pairs((config and config.Animations) or {}) do
		if entry == false then
			sources[name] = nil -- switched off, even if the rig has one
		else
			local id = type(entry) == "table" and entry.Id or entry
			if normalizeId(id) then
				sources[name] = id -- the config wins over the rig's folder
				if type(entry) == "table" then
					loader.actions[name] = entry
				end
			end
		end
	end

	for name, source in pairs(sources) do
		if MOVEMENT[name] then
			loader:load(name, source, { Looped = true, Priority = Enum.AnimationPriority.Movement })
		else
			local action = loader.actions[name]
			loader:load(name, source, {
				Priority = Enum.AnimationPriority.Action,
				Looped = action and action.Loop == true or nil,
			})
		end
	end
	return loader
end

return AnimationLoader
