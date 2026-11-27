--[[
	VoicelineService (ModuleScript, ServerScriptService.BaldiGame.VoicelineService)

	Decides what a character says and tells every client (Voiceline remote).
	The lines, colours and HyperText text effect live in
	ReplicatedStorage.BaldiShared.CharacterConfig; the clients draw them
	(BaldiClient.VoicelineController) and play any voice clip.

	  ctx.voicelines.say(model, moment, opts)   -- an NPC talks (NpcBase:say)
	  ctx.voicelines.sayAs(name, moment, opts)  -- by character name (GameManager on a catch)
	    opts.target  the player the line is aimed at: they always get it, however far away
	    opts.force   skip the cooldown and chance rolls (big moments: Caught, Grab, ...)

	How often characters talk (CharacterConfig.Settings): one line per
	character per Cooldown seconds, GlobalCooldown between different
	characters, MomentGaps between repeats of the same moment, a Chance roll
	for the chatty moments (Idle, Chasing), and StartQuiet moments wait out
	part of their gap before their first line. A character never says the
	same line twice in a row for a moment.

	Settings.Enabled = false switches every line off (say() sends nothing).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("CharacterConfig"))

local VoicelineService = {}

function VoicelineService.init(ctx)
	local settings = CharacterConfig.Settings
	local remote = ctx.remotes.Voiceline
	local rng = Random.new()
	local lastSpokeAt = {} -- [name] = os.clock()
	local lastAnyAt = -math.huge -- the last line from anyone
	local lastMomentAt = {} -- ["name/moment"] = os.clock()
	local lastIndex = {} -- ["name/moment"] = index of the line said last

	local self = {}

	local function pickLine(key, lines)
		local last = lastIndex[key]
		local index
		if #lines == 1 then
			index = 1
		elseif last then
			index = rng:NextInteger(1, #lines - 1)
			if index >= last then
				index += 1 -- never the same line twice in a row
			end
		else
			index = rng:NextInteger(1, #lines)
		end
		lastIndex[key] = index
		return lines[index]
	end

	function self.say(model, moment, opts)
		if settings.Enabled == false then
			return false -- voicelines are switched off
		end
		if not (model and model.Parent) then
			return false
		end
		opts = opts or {}
		local name = model.Name
		local character = CharacterConfig.get(name)
		local lines = character.Voicelines and character.Voicelines[moment]
		if type(lines) == "string" then
			lines = { lines }
		end
		if type(lines) ~= "table" or #lines == 0 then
			return false
		end

		local now = os.clock()
		local key = name .. "/" .. moment
		if not opts.force then
			if now - lastAnyAt < (settings.GlobalCooldown or 0) then
				return false
			end
			if now - (lastSpokeAt[name] or -math.huge) < (settings.Cooldown or 4) then
				return false
			end
			local gap = settings.MomentGaps and settings.MomentGaps[moment]
			if gap and lastMomentAt[key] == nil and settings.StartQuiet and settings.StartQuiet[moment] then
				-- first chance for a chatty moment: start its clock (staggered) instead of talking
				lastMomentAt[key] = now - rng:NextNumber(0, gap * 0.5)
				return false
			end
			if gap and now - (lastMomentAt[key] or -math.huge) < gap then
				return false
			end
			local chance = settings.Chance and settings.Chance[moment]
			if chance and rng:NextNumber() > chance then
				lastMomentAt[key] = now -- a skipped roll still waits out the gap
				return false
			end
		end

		local line = pickLine(key, lines)
		local text, sound, animation = line, nil, nil
		if type(line) == "table" then
			text, sound, animation = line.Text, line.Sound, line.Animation
		end
		if type(text) ~= "string" or text == "" then
			return false
		end
		lastSpokeAt[name] = now
		lastMomentAt[key] = now
		lastAnyAt = now

		-- the position rides along for clients that have the model streamed out
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		local position = root and root.Position or model:GetPivot().Position
		local targetId = opts.target and opts.target.UserId or 0
		remote:FireAllClients(name, text, position, model, sound, animation, targetId)
		return true
	end

	function self.sayAs(name, moment, opts)
		for _, npc in pairs(ctx.npcs) do
			local model = type(npc) == "table" and npc.model
			if typeof(model) == "Instance" and model.Name == name then
				return self.say(model, moment, opts)
			end
		end
		return false
	end

	ctx.voicelines = self
	return self
end

return VoicelineService
