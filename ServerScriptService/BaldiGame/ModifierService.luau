--[[
	ModifierService (ModuleScript, ServerScriptService.BaldiGame.ModifierService)

	Server side of the Modifiers system. Registers as ctx.modifiers. Numbers and
	names live in ReplicatedStorage.BaldiShared.ModifierConfig.

	Run lifecycle (driven by GameManager):
	  resolve(player, selection, modeId) -> stacks, rolled | nil
	      validates a client's panel selection: the player must have modifiers
	      unlocked and the mode must accept them; unknown ids are dropped and
	      Randomizer is expanded HERE (server-side) into N random picks.
	      stacks = { [id] = count }, rolled = what Randomizer added.
	  beginRun(player, stacks, rolled)  -- at countdown start
	  onRunActive()                      -- countdown over, the run is live
	  onPlayerJoined(player) / onPlayerLeft(player)   -- run membership
	  onNotebookCollected(player, collected, total)
	  endRun()                           -- every round end (win/forfeit/reset)

	Queries:
	  isActive(), isModifiedRun(), has(id), count(id), stacks()
	  npcSpeedMult(name)        product of every active NPC speed effect, clamped
	  playerSpeedMult(player)   same for players, incl. timed boosts, clamped
	  addTimedBoost(player, mult, seconds)   refreshes, never stacks
	  bonusPct()                additive sum over all stacks
	  heatCap()                 how far GameManager.getHeat may climb (1, or more)
	  breakdownRows(player)     extra { label, amount } win rows from features
	  notebooks()               notebooks collected this run
	  isUnlocked(player)        wins > 0 or owns the Tmod Theory badge

	Replicated state (attributes):
	  workspace.ActiveModifiers   JSON of stacks while a modified run is on
	  workspace.ModifierBonusPct  the run's total bonus %
	  Player.ModSpeedMult         that player's speed multiplier (client applies it)
	  Player.InModifiedRun        true while that player is in the modified run
	                              (clients only show effects while it's set)

	Feature modules: every ModuleScript in BaldiGame/Modifiers named after a
	modifier id is that modifier's server behaviour. A feature returns a table
	with any of:
	  init(env)                               once at server start (remotes etc.)
	  start(env, count)                       a run with this modifier begins
	  onActive(env)                           the run went live (after countdown)
	  stop(env)                               the run ended: undo EVERYTHING
	  onNotebookCollected(env, player, collected, total)
	  onPlayerJoined(env, player) / onPlayerLeft(env, player)
	  breakdownRows(env, player) -> { { label = string, amount = number } }
	  heatCap(env) -> number
	env = { ctx, service, id, def (ModifierConfig.LIST[id]), config (ModifierConfig),
	        assets (ModifierAssets), count (stacks this run, 0 when inactive) }
	Feature errors are caught and warned so one broken modifier can't break a round.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local ModifierConfig = require(shared:WaitForChild("ModifierConfig"))
local ModifierAssets = require(shared:WaitForChild("ModifierAssets"))

local ModifierService = {}

function ModifierService.init(ctx)
	local self = {}
	local LIST = ModifierConfig.LIST

	local current = nil -- stacks { [id] = count } while a modified run is on
	local runActive = false
	local members = {} -- [player] = true: players whose speed this run controls
	local boosts = {} -- [player] = { mult, untilAt, token }
	local notebookCount = 0

	-- ---------- feature modules ----------

	local features = {} -- [id] = module table
	local envs = {} -- [id] = env
	local featureFolder = script.Parent:FindFirstChild("Modifiers")
	for _, id in ipairs(ModifierConfig.ORDER) do
		local moduleScript = featureFolder and featureFolder:FindFirstChild(id)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, result = pcall(require, moduleScript)
			if ok and type(result) == "table" then
				features[id] = result
				envs[id] = {
					ctx = ctx,
					service = self,
					id = id,
					def = LIST[id],
					config = ModifierConfig,
					assets = ModifierAssets,
					count = 0,
				}
			else
				warn("[Tmod] Modifier feature " .. id .. " failed to load: " .. tostring(result))
			end
		end
	end

	local function call(id, fnName, ...)
		local feature = features[id]
		local fn = feature and feature[fnName]
		if type(fn) ~= "function" then
			return nil
		end
		local ok, result = pcall(fn, envs[id], ...)
		if not ok then
			warn("[Tmod] Modifier " .. id .. "." .. fnName .. " failed: " .. tostring(result))
			return nil
		end
		return result
	end

	-- call fnName on every feature active this run
	local function callActive(fnName, ...)
		if not current then
			return
		end
		for _, id in ipairs(ModifierConfig.ORDER) do
			if current[id] then
				call(id, fnName, ...)
			end
		end
	end

	-- ---------- queries ----------

	function self.isActive()
		return current ~= nil
	end
	self.isModifiedRun = self.isActive

	function self.has(id)
		return current ~= nil and (current[id] or 0) > 0
	end

	function self.count(id)
		return (current and current[id]) or 0
	end

	function self.stacks()
		return current
	end

	function self.notebooks()
		return notebookCount
	end

	function self.bonusPct()
		return ModifierConfig.bonusFor(current)
	end

	function self.isUnlocked(player)
		local profiles = ctx.profiles
		if profiles and (profiles.get(player).wins or 0) > 0 then
			return true
		end
		local badges = ctx.badges
		return badges ~= nil and badges.owns ~= nil and badges.owns(player, ModifierConfig.UNLOCK_BADGE) == true
	end

	-- ---------- speed ----------

	local function clamp(mult, cap)
		return math.clamp(mult, ModifierConfig.MIN_MULT, cap)
	end

	-- the character's base name: an EVIL twin "ChatReviveEvil" counts as "ChatRevive"
	local suffix = (LIST.EvilTheory and LIST.EvilTheory.SUFFIX) or "Evil"
	local function baseName(name)
		name = tostring(name or "")
		if #name > #suffix and name:sub(-#suffix) == suffix then
			return name:sub(1, #name - #suffix)
		end
		return name
	end

	function self.npcSpeedMult(name)
		if not current then
			return 1
		end
		local n = notebookCount
		local mult = 1
		local c = current.Frenzy
		if c then
			mult *= LIST.Frenzy.SPEED ^ c
		end
		c = current.Toji
		if c then
			mult *= (LIST.Toji.NPC_BASE + LIST.Toji.NPC_PER_NOTEBOOK * n) ^ c
		end
		c = current.PresidentialTortoise
		if c then
			mult *= LIST.PresidentialTortoise.NPC_SPEED ^ c
		end
		c = current.GrandBully
		if c and baseName(name) == "ChatRevive" then
			mult *= LIST.GrandBully.CHATREVIVE_SPEED ^ c
		end
		return clamp(mult, ModifierConfig.NPC_MULT_CAP)
	end

	function self.playerSpeedMult(player)
		if not current or not members[player] then
			return 1
		end
		local n = notebookCount
		local mult = 1
		local c = current.Frenzy
		if c then
			mult *= LIST.Frenzy.SPEED ^ c
		end
		c = current.Toji
		if c then
			mult *= (LIST.Toji.PLAYER_BASE + LIST.Toji.PLAYER_PER_NOTEBOOK * n) ^ c
		end
		c = current.PresidentialTortoise
		if c then
			local t = LIST.PresidentialTortoise
			mult *= (t.PLAYER_SPEED * t.PLAYER_NOTEBOOK_MULT ^ n) ^ c
		end
		local boost = boosts[player]
		if boost and os.clock() < boost.untilAt then
			mult *= boost.mult
		end
		return clamp(mult, ModifierConfig.PLAYER_MULT_CAP)
	end

	-- push the current multipliers out: every member's ModSpeedMult attribute,
	-- and every NPC's WalkSpeed (NpcBase:applySpeed reads npcSpeedMult)
	function self.refreshSpeeds()
		for player in pairs(members) do
			if player.Parent then
				player:SetAttribute("ModSpeedMult", self.playerSpeedMult(player))
			end
		end
		for _, npc in pairs(ctx.npcs) do
			if npc.base and npc.base.applySpeed then
				pcall(npc.base.applySpeed, npc.base)
			end
		end
	end

	function self.addTimedBoost(player, mult, seconds)
		if not current or not members[player] then
			return
		end
		local token = {}
		boosts[player] = { mult = mult, untilAt = os.clock() + seconds, token = token }
		self.refreshSpeeds()
		task.delay(seconds + 0.05, function()
			local boost = boosts[player]
			if boost and boost.token == token then
				boosts[player] = nil
				self.refreshSpeeds()
			end
		end)
	end

	-- ---------- heat / rewards ----------

	function self.heatCap()
		local cap = 1
		if current then
			for _, id in ipairs(ModifierConfig.ORDER) do
				if current[id] then
					local value = call(id, "heatCap")
					if type(value) == "number" and value > cap then
						cap = value
					end
				end
			end
		end
		return cap
	end

	function self.breakdownRows(player)
		local rows = {}
		if current then
			for _, id in ipairs(ModifierConfig.ORDER) do
				if current[id] then
					local list = call(id, "breakdownRows", player)
					if type(list) == "table" then
						for _, row in ipairs(list) do
							if type(row) == "table" and type(row.amount) == "number" then
								table.insert(rows, row)
							end
						end
					end
				end
			end
		end
		return rows
	end

	-- ---------- selection ----------

	-- selection from the client panel: { [id] = true | 1 } plus
	-- Randomizer = n (1..RANDOMIZER_MAX). Anything else is ignored.
	function self.resolve(player, selection, modeId)
		if type(selection) ~= "table" then
			return nil
		end
		if not ModifierConfig.MODES[modeId or "CLASSIC"] then
			return nil
		end
		if not self.isUnlocked(player) then
			return nil
		end
		local stacks = {}
		local randomizerRolls = 0
		for id, value in pairs(selection) do
			local def = type(id) == "string" and LIST[id]
			if def then
				if id == "Randomizer" then
					local n = tonumber(value)
					if n and n == n then
						randomizerRolls = math.clamp(math.floor(n), 1, ModifierConfig.RANDOMIZER_MAX)
					elseif value == true then
						randomizerRolls = 1
					end
				elseif value == true or (type(value) == "number" and value > 0) then
					stacks[id] = 1
				end
			end
		end

		local rolled = nil
		if randomizerRolls > 0 then
			rolled = {}
			local pool = {}
			for _, id in ipairs(ModifierConfig.ORDER) do
				if id ~= "Randomizer" and LIST[id] then
					table.insert(pool, id)
				end
			end
			local rng = Random.new()
			for _ = 1, randomizerRolls do
				local id = pool[rng:NextInteger(1, #pool)]
				stacks[id] = (stacks[id] or 0) + 1
				rolled[id] = (rolled[id] or 0) + 1
			end
		end

		if next(stacks) == nil then
			return nil
		end
		return stacks, rolled
	end

	-- "Frenzy x2, See Moon" in ORDER
	local function describe(list)
		local parts = {}
		for _, id in ipairs(ModifierConfig.ORDER) do
			local count = list[id]
			if count and count > 0 then
				local name = LIST[id].name
				table.insert(parts, count > 1 and (name .. " x" .. count) or name)
			end
		end
		return table.concat(parts, ", ")
	end
	self.describe = describe

	-- ---------- run lifecycle ----------

	local function setMember(player, isMember)
		members[player] = isMember or nil
		if player.Parent then
			player:SetAttribute("InModifiedRun", isMember and true or nil)
		end
		if not isMember then
			boosts[player] = nil
			if player.Parent then
				player:SetAttribute("ModSpeedMult", nil)
			end
		end
	end

	function self.beginRun(player, stacks, rolled)
		if current then
			self.endRun() -- never let two runs' state overlap
		end
		if type(stacks) ~= "table" or next(stacks) == nil then
			return
		end
		current = stacks
		runActive = false
		notebookCount = 0
		setMember(player, true)
		workspace:SetAttribute("ActiveModifiers", HttpService:JSONEncode(stacks))
		workspace:SetAttribute("ModifierBonusPct", self.bonusPct())

		for _, id in ipairs(ModifierConfig.ORDER) do
			if current[id] then
				envs[id] = envs[id] or { ctx = ctx, service = self, id = id, def = LIST[id],
					config = ModifierConfig, assets = ModifierAssets }
				envs[id].count = current[id]
				call(id, "start", current[id])
			end
		end
		self.refreshSpeeds()

		if ctx.remotes.RoundAnnounce then
			local text = "Modifiers: " .. describe(stacks) .. " (+" .. self.bonusPct() .. "% Curriculums)"
			if rolled and next(rolled) then
				text = "Randomizer rolled: " .. describe(rolled) .. " — " .. text
			end
			ctx.remotes.RoundAnnounce:FireClient(player, text)
		end
	end

	function self.onRunActive()
		if not current or runActive then
			return
		end
		runActive = true
		callActive("onActive")
	end

	function self.onPlayerJoined(player)
		if not current then
			return
		end
		setMember(player, true)
		callActive("onPlayerJoined", player)
		self.refreshSpeeds()
	end

	function self.onPlayerLeft(player)
		if not members[player] then
			return
		end
		callActive("onPlayerLeft", player)
		setMember(player, false)
	end

	function self.onNotebookCollected(player, collected, total)
		if not current then
			return
		end
		notebookCount = collected or (notebookCount + 1)
		self.refreshSpeeds()
		callActive("onNotebookCollected", player, notebookCount, total)
	end

	function self.endRun()
		if not current then
			return
		end
		callActive("stop")
		for id in pairs(current) do
			if envs[id] then
				envs[id].count = 0
			end
		end
		for player in pairs(members) do
			setMember(player, false)
		end
		members = {}
		boosts = {}
		current = nil
		runActive = false
		notebookCount = 0
		workspace:SetAttribute("ActiveModifiers", nil)
		workspace:SetAttribute("ModifierBonusPct", nil)
		self.refreshSpeeds() -- NPCs back to their normal speed
	end

	-- one-time hookups (remotes) for every feature present
	for id in pairs(features) do
		call(id, "init")
	end

	Players.PlayerRemoving:Connect(function(player)
		self.onPlayerLeft(player)
		members[player] = nil
		boosts[player] = nil
	end)

	-- a fresh server never has a stale run
	workspace:SetAttribute("ActiveModifiers", nil)
	workspace:SetAttribute("ModifierBonusPct", nil)

	ctx.modifiers = self
	return self
end

return ModifierService
