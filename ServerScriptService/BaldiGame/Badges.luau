--[[
	Badges (ModuleScript, ServerScriptService.BaldiGame.Badges)

	Awards the game's badges (GameConfig.BADGES: their ids, and the numbers
	each one asks for). The rest of the game reports what happens through
	ctx.badges:

	  runStarted(modeId, playerCount)  a run went live (GameManager)
	  playersInRun(count)              someone joined the live run (GameManager)
	  noteDown(player)                 a player was caught / collapsed / forfeited (GameManager)
	  noteModstatFailed(player)        a notebook minigame was failed (NotebookSpawner)
	  noteTrap(player)                 one of Frosty's traps got a player (FrostyAI)
	  onWin(player, info)              escaped: { elapsed, grade, modeId, detentions, wins } (GameManager)
	  onCaught(player, catcherName)    lost to a character (GameManager)
	  checkCosmetics(player, owned)    after a shop purchase (PlayerProfiles)

	Players who join also get anything their profile already earned (wins,
	skins bought before badges existed). What each player owns is read once
	per join (CheckUserBadgesAsync) and kept up to date, so nothing is
	awarded twice; once they own the other fourteen, "Poscere, Theorizare,
	Hypothesizare" follows.

	Badges only award on servers of the experience that owns them; a failed
	award (Studio, a disabled badge) is just logged.
]]

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("Cosmetics"))

local Badges = {}

local CHECK_BATCH = 10 -- CheckUserBadgesAsync takes at most this many ids
local COMPLETIONIST = "POSCERE"

function Badges.init(ctx)
	local cfg = ctx.config.BADGES or {}
	local list = cfg.LIST or {}
	local self = {}

	local owned = {} -- [player] = { [badgeId] = true }
	local fetching = {} -- [player] = true while their owned set loads

	-- the current run: who's in it and what has happened in it
	local run = { modeId = nil, peakPlayers = 0, someoneDown = false, modstatFailed = false, traps = {} }

	-- ---------- ownership ----------

	local function fetchOwned(player)
		local set = {}
		local ids = {}
		for _, badge in pairs(list) do
			table.insert(ids, badge.id)
		end
		for start = 1, #ids, CHECK_BATCH do
			local chunk = table.move(ids, start, math.min(start + CHECK_BATCH - 1, #ids), 1, {})
			local ok, result = pcall(function()
				return BadgeService:CheckUserBadgesAsync(player.UserId, chunk)
			end)
			if ok and type(result) == "table" then
				for _, id in ipairs(result) do
					set[id] = true
				end
			end
		end
		return set
	end

	local function ownedSet(player)
		if owned[player] then
			return owned[player]
		end
		if fetching[player] then
			while fetching[player] and player.Parent do
				task.wait(0.1)
			end
			return owned[player] or {}
		end
		fetching[player] = true
		owned[player] = fetchOwned(player)
		fetching[player] = nil
		return owned[player]
	end

	-- ---------- awarding ----------

	local award

	local function checkCompletionist(player)
		local set = ownedSet(player)
		for key, badge in pairs(list) do
			if key ~= COMPLETIONIST and not set[badge.id] then
				return
			end
		end
		award(player, COMPLETIONIST)
	end

	-- yields; call from a spawned thread
	function award(player, key)
		local badge = list[key]
		if not badge or not badge.id or not player.Parent then
			return
		end
		local set = ownedSet(player)
		if set[badge.id] then
			return
		end
		local ok, result = pcall(function()
			return BadgeService:AwardBadge(player.UserId, badge.id)
		end)
		if ok and result then
			set[badge.id] = true
			print(string.format("[Tmod] %s earned the badge \"%s\"", player.Name, badge.name or key))
			if key ~= COMPLETIONIST then
				checkCompletionist(player)
			end
		elseif not ok then
			warn(string.format("[Tmod] Couldn't award \"%s\" to %s: %s", badge.name or key, player.Name, tostring(result)))
		end
	end

	local function awardLater(player, key)
		task.spawn(award, player, key)
	end

	-- ---------- run tracking ----------

	function self.runStarted(modeId, playerCount)
		run = {
			modeId = modeId,
			peakPlayers = playerCount or 0,
			someoneDown = false,
			modstatFailed = false,
			traps = {},
		}
	end

	function self.playersInRun(count)
		run.peakPlayers = math.max(run.peakPlayers, count or 0)
	end

	function self.noteDown(_player)
		run.someoneDown = true
	end

	function self.noteModstatFailed(_player)
		run.modstatFailed = true
	end

	function self.noteTrap(player)
		run.traps[player] = (run.traps[player] or 0) + 1
	end

	-- ---------- outcomes ----------

	local function isMultiplayer(modeId)
		return cfg.MULTIPLAYER_MODES ~= nil and cfg.MULTIPLAYER_MODES[modeId] == true
	end

	function self.onWin(player, info)
		info = info or {}
		local elapsed = info.elapsed or math.huge
		local traps = run.traps[player] or 0
		local peak = run.peakPlayers
		local clean = not run.someoneDown and not run.modstatFailed
		task.spawn(function()
			award(player, "TMOD_THEORY")
			if (info.wins or 0) >= (cfg.CURRICULUM_WINS or 30) then
				award(player, "TMOD_CURRICULUM")
			end
			if elapsed < (cfg.TWO_MINUTES or 120) then
				award(player, "ALL_I_NEED")
			end
			if elapsed < (cfg.WIPEOUT_SECONDS or 80) then
				award(player, "PHENOMENAL_WIPEOUT")
			end
			if (info.detentions or 0) == 0 then
				award(player, "ZERO_STRIKES")
			end
			if info.grade == (cfg.RAGEBAIT_GRADE or "B") and traps > (cfg.RAGEBAIT_TRAPS or 15) then
				award(player, "RAGEBAIT")
			end
			if isMultiplayer(info.modeId) then
				award(player, "SQUARED")
				if elapsed < (cfg.LOCKDOWN_SECONDS or 180) then
					award(player, "LOCKDOWN")
				end
				if peak >= (cfg.PURGE_PLAYERS or 15) and elapsed < (cfg.PURGE_SECONDS or 240) then
					award(player, "PURGE_GENERAL")
				end
				if peak >= (cfg.GOOD_NOODLES_PLAYERS or 15) and clean then
					award(player, "GOOD_NOODLES")
				end
			end
		end)
	end

	function self.onCaught(player, catcherName)
		if catcherName == "ChatRevive" then
			awardLater(player, "CHAT_KILL")
		end
	end

	-- skins: Stylish (one), Fashion Chaser (more than FASHION_CHASER_SKINS),
	-- Fashionista (every one the shop sells)
	function self.checkCosmetics(player, ownedCosmetics)
		local bought, forSale = 0, 0
		for _, cosmetic in ipairs(Cosmetics.all()) do
			if not cosmetic.default and (cosmetic.price or 0) > 0 then
				forSale += 1
				if ownedCosmetics and ownedCosmetics[cosmetic.id] then
					bought += 1
				end
			end
		end
		task.spawn(function()
			if bought >= 1 then
				award(player, "STYLISH")
			end
			if bought > (cfg.FASHION_CHASER_SKINS or 10) then
				award(player, "FASHION_CHASER")
			end
			if forSale > 0 and bought >= forSale then
				award(player, "FASHIONISTA")
			end
		end)
	end

	-- ---------- joining ----------

	-- whatever the profile already earned, then the completionist check
	local function onJoin(player)
		task.spawn(function()
			ownedSet(player)
			local profile = ctx.profiles and ctx.profiles.get(player)
			if profile and player.Parent then
				if (profile.wins or 0) >= 1 then
					award(player, "TMOD_THEORY")
				end
				if (profile.wins or 0) >= (cfg.CURRICULUM_WINS or 30) then
					award(player, "TMOD_CURRICULUM")
				end
				self.checkCosmetics(player, profile.ownedCosmetics)
			end
			if player.Parent then
				checkCompletionist(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		onJoin(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		fetching[player] = nil
		run.traps[player] = nil
	end)

	ctx.badges = self
	return self
end

return Badges
