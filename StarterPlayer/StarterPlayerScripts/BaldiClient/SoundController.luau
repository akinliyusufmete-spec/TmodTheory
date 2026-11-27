--[[
	SoundController (ModuleScript, StarterPlayerScripts.BaldiClient.SoundController)

	UI / feedback sounds. Each named sound checks AssetConfig.SOUNDS first —
	paste your own sound id there and it replaces the built-in placeholder
	(placeholders are rbxasset:// files that ship with the engine, so
	nothing depends on marketplace assets). Every play is wrapped in
	pcall — a missing sound never breaks gameplay.
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local SoundController = {}

local LIBRARY = {
	click = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.4, volume = 0.4 },
	collect = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.0, volume = 0.7 },
	nickel = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.8, volume = 0.6 },
	buy = { id = "rbxasset://sounds/snap.mp3", speed = 1.2, volume = 0.6 },
	error = { id = "rbxasset://sounds/snap.mp3", speed = 0.55, volume = 0.6 },
	exhausted = { id = "rbxasset://sounds/snap.mp3", speed = 0.4, volume = 0.5 },
	caught = { id = "rbxasset://sounds/uuhhh.mp3", speed = 1.0, volume = 1 },
	detention = { id = "rbxasset://sounds/snap.mp3", speed = 0.35, volume = 0.8 },
	frost = { id = "rbxasset://sounds/snap.mp3", speed = 0.6, volume = 0.7 },
	use = { id = "rbxasset://sounds/snap.mp3", speed = 1.2, volume = 0.6 },
	win = { id = "", speed = 1.0, volume = 0.8 }, -- placeholder is the jingle below
	grab = { id = "rbxasset://sounds/snap.mp3", speed = 0.7, volume = 0.9 }, -- Silver caught you
	swept = { id = "rbxasset://sounds/snap.mp3", speed = 0.8, volume = 0.8 }, -- a sweeper hit you
	notebookSolved = { id = "", speed = 1.0, volume = 0.8 }, -- notebook solved (silent until AssetConfig sets it)
}

function SoundController.init(ctx)
	local self = {}
	local overrides = ctx.assets.SOUNDS

	-- one unparented template per sound id; plays clone it (cheaper than
	-- building a Sound from scratch, and the asset is already fetched)
	local templates = {}
	local function templateFor(id)
		local template = templates[id]
		if not template then
			template = Instance.new("Sound")
			template.SoundId = id
			templates[id] = template
		end
		return template
	end

	-- preload every library sound up front so the first click/collect/catch
	-- doesn't play late (or silently) while its asset downloads
	task.spawn(function()
		local toLoad = {}
		for name, entry in pairs(LIBRARY) do
			local override = overrides[name]
			local id = (override and override ~= "") and override or entry.id
			if id ~= "" then
				table.insert(toLoad, templateFor(id))
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(toLoad)
		end)
	end)

	-- master SFX volume (0..1), driven by the player's Settings slider; scales
	-- every sound this controller plays. Defaults to full until settings load.
	local masterVolume = 1
	function self.setMasterVolume(value)
		masterVolume = math.clamp(tonumber(value) or 1, 0, 1)
	end
	function self.getMasterVolume()
		return masterVolume
	end

	function self.play(name, pitchOverride)
		local entry = LIBRARY[name]
		if not entry then
			return
		end
		local override = overrides[name]
		local custom = override and override ~= ""
		local id = custom and override or entry.id
		if id == "" then
			return
		end
		pcall(function()
			local sound = templateFor(id):Clone()
			sound.Volume = entry.volume * masterVolume
			-- your sound plays at its natural pitch unless a pitch is forced
			sound.PlaybackSpeed = pitchOverride or (custom and 1 or entry.speed)
			sound.Parent = SoundService
			sound:Play()
			Debris:AddItem(sound, 6)
		end)
	end

	-- Play any arbitrary asset id directly (used for per-cosmetic audio cues).
	function self.playId(assetId, volume, pitch)
		if not assetId or assetId == "" then return end
		pcall(function()
			local sound = templateFor(assetId):Clone()
			sound.Volume = (volume or 0.85) * masterVolume
			sound.PlaybackSpeed = pitch or 1
			sound.Parent = SoundService
			sound:Play()
			Debris:AddItem(sound, 6)
		end)
	end

	-- win fanfare: your SOUNDS.win asset, or a little rising arpeggio
	function self.winJingle()
		if overrides.win and overrides.win ~= "" then
			self.play("win")
			return
		end
		task.spawn(function()
			for _, pitch in ipairs({ 1.0, 1.26, 1.5 }) do
				self.play("collect", pitch)
				task.wait(0.18)
			end
		end)
	end

	return self
end

return SoundController
