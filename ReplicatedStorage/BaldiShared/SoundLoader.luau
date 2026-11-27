--[[
	SoundLoader (ModuleScript, ReplicatedStorage.BaldiShared.SoundLoader)

	One place that turns ids into ready-to-play Sounds, so every system (NPCs,
	items, voicelines) builds sounds the same way and falls back the same way
	when an id is blank. Works on the server and the client.

	A "spec" is an id ("rbxassetid://123", "123" or 123) or a table:
	  {
	    Id = "rbxassetid://123",          -- first choice (e.g. CharacterConfig.<Name>.Sounds.X)
	    Asset = "chase",                  -- else AssetConfig.SOUNDS[Asset]
	    Fallback = "rbxasset://sounds/snap.mp3", -- else this built-in sound
	    FallbackSpeed = 0.6,              -- PlaybackSpeed used only when the fallback plays
	    Name, Volume, PlaybackSpeed, Looped, RollOffMaxDistance, RollOffMinDistance, RollOffMode
	  }

	  SoundLoader.resolve(spec)              -> soundId or nil, usedFallback
	  SoundLoader.create(spec)               -> a new unparented Sound (nil if nothing resolves)
	  SoundLoader.attach(parent, name, spec) -> a persistent Sound under parent. A Sound
	                                            already there with that name (e.g. one you
	                                            put in the rig) is used as-is.
	  SoundLoader.playAt(where, spec)        -> plays a one-shot copy at a BasePart /
	                                            Attachment / Vector3 (3D), or 2D when where
	                                            is nil. Cleans itself up when it ends.
	  SoundLoader.preload(specs)             -> client only: loads the sounds up front
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local AssetConfig = require(script.Parent:WaitForChild("AssetConfig"))

local SoundLoader = {}

local PROPS = { "Volume", "PlaybackSpeed", "Looped", "RollOffMaxDistance", "RollOffMinDistance", "RollOffMode" }
local MAX_ONESHOT_SECONDS = 15 -- safety net if a one-shot never reports Ended

-- "123" / 123 -> "rbxassetid://123"; full asset strings pass through; blank -> nil
function SoundLoader.normalizeId(value)
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

function SoundLoader.resolve(spec)
	if typeof(spec) ~= "table" then
		return SoundLoader.normalizeId(spec), false
	end
	local id = SoundLoader.normalizeId(spec.Id)
	if not id and spec.Asset then
		id = SoundLoader.normalizeId(AssetConfig.SOUNDS[spec.Asset])
	end
	if id then
		return id, false
	end
	local fallback = SoundLoader.normalizeId(spec.Fallback)
	return fallback, fallback ~= nil
end

function SoundLoader.create(spec)
	local id, usedFallback = SoundLoader.resolve(spec)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	if typeof(spec) == "table" then
		for _, prop in ipairs(PROPS) do
			if spec[prop] ~= nil then
				sound[prop] = spec[prop]
			end
		end
		if usedFallback and spec.FallbackSpeed then
			sound.PlaybackSpeed = spec.FallbackSpeed
		end
		if spec.Name then
			sound.Name = spec.Name
		end
	end
	return sound
end

function SoundLoader.attach(parent, name, spec)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Sound") then
		return existing
	end
	local sound = SoundLoader.create(spec)
	if sound then
		sound.Name = name
		sound.Parent = parent
	end
	return sound
end

function SoundLoader.playAt(where, spec)
	local sound = SoundLoader.create(spec)
	if not sound then
		return nil
	end
	sound.Looped = false
	local holder = nil
	if typeof(where) == "Vector3" then
		-- a throwaway attachment so the sound is 3D at that spot
		holder = Instance.new("Attachment")
		holder.Name = "SoundAt"
		holder.Parent = workspace.Terrain
		holder.WorldPosition = where
		sound.Parent = holder
	elseif typeof(where) == "Instance" then
		sound.Parent = where
	else
		sound.Parent = SoundService
	end
	local cleanup = holder or sound
	sound.Ended:Once(function()
		cleanup:Destroy()
	end)
	Debris:AddItem(cleanup, MAX_ONESHOT_SECONDS)
	pcall(function()
		sound:Play()
	end)
	return sound
end

function SoundLoader.preload(specs)
	if not RunService:IsClient() then
		return
	end
	local list = {}
	for _, spec in ipairs(specs) do
		local id = SoundLoader.resolve(spec)
		if id then
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(list, sound)
		end
	end
	if #list > 0 then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, list)
		end)
	end
end

return SoundLoader
