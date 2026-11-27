--[[
	GuyAI (ModuleScript, ServerScriptService.BaldiGame.GuyAI)

	Guy, the mimic. He hides his body and poses as a notebook at one of the
	map's notebook spawn points. Try to collect him and:
	  - JUMPSCARE (GuyReveal flash on your screen, brief freeze)
	  - a loud SCREEE the hunter homes in on (ChatRevive gets an alert
	    burst; Sportage hears it outright)
	  - Guy scurries off, then poses somewhere new

	The tell: his fake notebook bobs noticeably faster than a real one
	(GameConfig.NPC.GUY.WOBBLE). Sharp eyes save your skin.

	Custom rig:  ReplicatedStorage/BaldiAssets/Npcs/Guy
	Custom fake: ReplicatedStorage/BaldiAssets/Items/GuyMimic
	             (else your Notebook model, so the disguise always matches)
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local NpcFactory = require(script.Parent.NpcFactory)
local NpcBase = require(script.Parent.NpcBase)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))
local AssetResolver = require(script.Parent.AssetResolver)

local GuyAI = {}

local COLOR_BODY = Color3.fromRGB(120, 60, 140)
local COLOR_HEAD = Color3.fromRGB(160, 90, 180)

function GuyAI.init(ctx)
	local cfg = ctx.config.NPC.GUY
	local self = { ctx = ctx, cfg = cfg }

	local model = NpcFactory.create({
		name = cfg.NAME,
		bodyColor = COLOR_BODY,
		headColor = COLOR_HEAD,
		tagColor = Color3.fromRGB(200, 130, 220),
	}, ctx.map.npcFolder)
	local base = NpcBase.new(ctx, model, ctx.map.npcSpawns.GUY)
	self.base = base
	self.model = model

	-- ---------- state ----------

	local state = "hidden" -- hidden | posing | scurrying
	local fake = nil -- the fake notebook model
	local nextPoseAt = 0
	local scurryUntil = 0
	local rng = Random.new()

	-- hide the body without "parking" (park = sat out of the whole mode)
	local function hideBody()
		base:stop()
		base.root.Anchored = true
		model:PivotTo(base.spawnCFrame + Vector3.new(0, 400, 0))
	end

	local function showBodyAt(cframe)
		base.root.Anchored = false
		model:PivotTo(cframe)
	end

	-- ---------- the fake notebook ----------

	local function buildFake()
		local template = AssetResolver.itemTemplate("GuyMimic")
			or AssetResolver.itemTemplate("Notebook")
		local prop
		if template then
			prop = AssetResolver.preparePropClone(template)
		else
			local stored = game:GetService("ReplicatedStorage"):FindFirstChild("BaldiModels")
			local notebook = stored and stored:FindFirstChild("Notebook")
			if notebook then
				prop = notebook:Clone()
				for _, descendant in ipairs(prop:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
						descendant.CanCollide = false
					end
				end
			else
				prop = Instance.new("Part")
				prop.Name = "Notebook"
				prop.Size = Vector3.new(1.7, 0.35, 2.2)
				prop.Color = Color3.fromRGB(200, 40, 40)
				prop.Anchored = true
				prop.CanCollide = false
			end
		end
		return prop
	end

	local function unpose()
		if fake then
			fake:Destroy()
			fake = nil
		end
	end

	-- the reveal: jumpscare, noise ping, then scurry
	local function reveal(player)
		if state ~= "posing" or not fake then
			return
		end
		local position = fake:GetPivot().Position
		unpose()
		state = "scurrying"
		scurryUntil = os.clock() + cfg.SCURRY_SECONDS

		-- Guy no longer has a body in the world: he haunts the victim's screen (GuyRevealFlash)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		-- the SCREEE
		SoundLoader.playAt(position, {
			Id = base.character.Sounds.Scream,
			Asset = "guy",
			Fallback = "rbxasset://sounds/uuhhh.mp3",
			FallbackSpeed = 1.55,
			Volume = 1,
			RollOffMaxDistance = 140,
		})

		-- jumpscare flash + brief freeze for the victim
		if player.Parent then
			ctx.remotes.GuyReveal:FireClient(player)
		end
		base:say("Reveal", { target = player, force = true })
		if hrp and not hrp.Anchored and ctx.manager.isParticipant(player) then
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.Anchored = true
			task.delay(cfg.STUN_ON_REVEAL, function()
				local nowCharacter = player.Character
				local nowHrp = nowCharacter and nowCharacter:FindFirstChild("HumanoidRootPart")
				local silver = ctx.npcs.Silver
				local sportage = ctx.npcs.Sportage
				if nowHrp and ctx.manager.isParticipant(player)
					and not ctx.detention.isDetained(player)
					and not (silver and silver.isGrabbing and silver.isGrabbing(player))
					and not (sportage and sportage.isTrapped and sportage.isTrapped(player)) then
					nowHrp.Anchored = false
				end
			end)
		end

		-- the hunter heard that
		local chatRevive = ctx.npcs.ChatRevive
		if chatRevive and chatRevive.alertBurst and not chatRevive.base.parked then
			chatRevive.alertBurst(cfg.PING_SECONDS)
		end
		local sportage = ctx.npcs.Sportage
		if sportage and sportage.hear and not sportage.base.parked then
			sportage.hear(position, cfg.PING_SECONDS)
		end
	end

	-- pick a notebook spawn node in the ACTIVE map, away from players
	local function pickPoseSpot()
		local candidates = {}
		for _, node in ipairs(CollectionService:GetTagged("NotebookSpawn")) do
			if node:IsDescendantOf(ctx.map.root) then
				local farEnough = true
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					if hrp and (hrp.Position - node.Position).Magnitude < 30 then
						farEnough = false
						break
					end
				end
				if farEnough then
					table.insert(candidates, node)
				end
			end
		end
		if #candidates == 0 then
			return nil
		end
		return candidates[rng:NextInteger(1, #candidates)]
	end

	local function pose()
		local node = pickPoseSpot()
		if not node then
			nextPoseAt = os.clock() + 3 -- everywhere is watched; try later
			return
		end
		hideBody()
		unpose()
		fake = buildFake()
		local baseCFrame = CFrame.new(node.Position + Vector3.new(0, 0.8, 0))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		fake:PivotTo(baseCFrame)

		local promptParent = fake:IsA("BasePart") and fake
			or fake.PrimaryPart
			or fake:FindFirstChildWhichIsA("BasePart", true)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Collect" -- identical to the real thing
		prompt.ObjectText = "Notebook"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = ctx.config.NOTEBOOK_PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent

		-- Guy's loop (AssetConfig.SOUNDS.guyLoop); dies with the fake
		local loop = promptParent and SoundLoader.attach(promptParent, "GuyLoop", {
			Asset = "guyLoop",
			Looped = true,
			Volume = 0.6,
			RollOffMaxDistance = 60,
		})
		if loop then
			loop:Play()
		end
		prompt.Triggered:Connect(function(player)
			if ctx.manager.isRoundActive() and ctx.manager.isParticipant(player) then
				reveal(player)
			end
		end)

		-- dressed exactly like a real notebook (type color, skin, client-side
		-- spin/bob) — the tell is that it bobs a touch too fast (WOBBLE)
		if ctx.notebookSpawner and ctx.notebookSpawner.disguise then
			ctx.notebookSpawner.disguise(fake, cfg.WOBBLE or 1.25)
		end

		fake.Parent = ctx.map.notebooksFolder
		state = "posing"
	end

	-- ---------- brain ----------

	-- Guy only exists in the open while scurrying; the rest of the time his
	-- body waits anchored out of sight (never left free-standing at a spawn
	-- that might have no floor under it)
	hideBody()

	task.spawn(function()
		while true do
			if base.parked or not base:canAct() then
				-- between rounds / sat out: clean the disguise up
				if fake then
					unpose()
					state = "hidden"
					nextPoseAt = 0
				end
				task.wait(0.3)
			elseif state == "hidden" then
				if os.clock() >= nextPoseAt then
					pose()
				else
					task.wait(0.2)
				end
			elseif state == "posing" then
				-- round swept the notebooks folder? back to hiding
				if not fake or not fake.Parent then
					unpose()
					state = "hidden"
					nextPoseAt = os.clock() + 2
				end
				task.wait(0.25)
			elseif state == "scurrying" then
				if os.clock() < scurryUntil then
					task.wait(0.2)
				else
					hideBody()
					state = "hidden"
					nextPoseAt = os.clock() + cfg.REPOSE_DELAY
				end
			end
		end
	end)

	-- ---------- public API ----------

	function self.reset()
		unpose()
		state = "hidden"
		nextPoseAt = 0
		base:resetToSpawn()
		hideBody()
	end

	-- failing a notebook minigame can summon Guy's screen haunt (NotebookSpawner calls this)
	function self.onNotebookFail(player)
		if not player.Parent or base.parked then
			return false
		end
		if not (ctx.manager.isRoundActive() and ctx.manager.isParticipant(player)) then
			return false
		end
		if ctx.detention.isDetained(player) then
			return false
		end
		local silver = ctx.npcs.Silver
		local sportage = ctx.npcs.Sportage
		if (silver and silver.isGrabbing and silver.isGrabbing(player))
			or (sportage and sportage.isTrapped and sportage.isTrapped(player)) then
			return false
		end
		self._failCooldown = self._failCooldown or setmetatable({}, { __mode = "k" })
		if (self._failCooldown[player] or 0) > os.clock() then
			return false
		end
		if rng:NextNumber() >= (cfg.FAIL_HAUNT_CHANCE or 0.35) then
			return false
		end
		self._failCooldown[player] = os.clock() + (cfg.FAIL_HAUNT_COOLDOWN or 20)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			SoundLoader.playAt(hrp.Position, {
				Id = base.character.Sounds.Scream,
				Asset = "guy",
				Fallback = "rbxasset://sounds/uuhhh.mp3",
				FallbackSpeed = 1.55,
				Volume = 1,
				RollOffMaxDistance = 140,
			})
		end
		ctx.remotes.GuyReveal:FireClient(player)
		base:say("Reveal", { target = player, force = true })
		if hrp and not hrp.Anchored then
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.Anchored = true
			task.delay(cfg.STUN_ON_REVEAL, function()
				local nowCharacter = player.Character
				local nowHrp = nowCharacter and nowCharacter:FindFirstChild("HumanoidRootPart")
				local silverNow = ctx.npcs.Silver
				local sportageNow = ctx.npcs.Sportage
				if nowHrp and ctx.manager.isParticipant(player)
					and not ctx.detention.isDetained(player)
					and not (silverNow and silverNow.isGrabbing and silverNow.isGrabbing(player))
					and not (sportageNow and sportageNow.isTrapped and sportageNow.isTrapped(player)) then
					nowHrp.Anchored = false
				end
			end)
		end
		local chatRevive = ctx.npcs.ChatRevive
		if chatRevive and chatRevive.alertBurst and not chatRevive.base.parked then
			chatRevive.alertBurst(cfg.PING_SECONDS)
		end
		if hrp and sportage and sportage.hear and not sportage.base.parked then
			sportage.hear(hrp.Position, cfg.PING_SECONDS)
		end
		return true
	end

	ctx.npcs.Guy = self
	return self
end

return GuyAI
