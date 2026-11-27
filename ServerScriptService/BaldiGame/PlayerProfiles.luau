--[[
	PlayerProfiles (ModuleScript, ServerScriptService.BaldiGame.PlayerProfiles)

	Persistence for everything the menus show:
	  - wins        -> special modes unlock after the FIRST win
	  - bestTime    -> fastest escape (also pushed to a global leaderboard)
	  - bestGrade   -> best report card ("best score")
	  - recent      -> the last 5 escape times
	  - binds       -> custom keybinds from the Options page

	Every DataStore call is pcall-wrapped: in Studio without API access the
	game still runs, profiles just live for the session. Changes are
	batched and flushed by an autosave loop, on leave, and on server close.
	A profile that failed to load is never saved, so stored data is never
	overwritten with a blank one.

	Leaderboard: an OrderedDataStore of best times (milliseconds), fetched
	at most once a minute and cached.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("Cosmetics"))

local PlayerProfiles = {}

local GRADE_LADDER = { "A+", "A", "B", "C", "D", "F" }

local function gradeRank(grade)
	return table.find(GRADE_LADDER, grade) or (#GRADE_LADDER + 1)
end

function PlayerProfiles.init(ctx)
	local self = {}
	local profiles = {} -- [player] = profile table
	local loading = {} -- [player] = true while their first load is in flight
	local loadFailed = {} -- [player] = true: never save over data we couldn't read
	local dirty = {} -- [player] = true: unsaved changes (flushed by the autosave loop)
	local bestDirty = {} -- [player] = true: best time improved since the last leaderboard write
	local AUTOSAVE_INTERVAL = 20 -- seconds; well clear of the 6s per-key write cooldown
	local profileStore, timeStore
	pcall(function()
		profileStore = DataStoreService:GetDataStore("TmodProfiles_v1")
		timeStore = DataStoreService:GetOrderedDataStore("TmodBestTimes_v1")
	end)

	local DEFAULT_BINDS = { USE = "E", SWAP = "Q", SPRINT = "LeftShift", CANCEL = "F" }

	local function freshProfile()
		return {
			wins = 0,
			curriculums = 0, -- earned currency balance
			bestTime = nil, -- seconds
			bestGrade = nil,
			recent = {}, -- newest-first escape times, capped at 5
			binds = nil, -- nil = defaults
			hudLayout = nil, -- nil = default mobile button layout
			settings = nil, -- nil = config DEFAULT_SETTINGS (stopwatch, sfxVolume)
			ownedCosmetics = {}, -- set of purchased cosmetic ids { [id] = true }
			equippedCosmetics = {}, -- [target] = cosmetic id currently worn
		}
	end

	-- ---------- load / save ----------

	local function fetchStored(player)
		-- retry briefly: one failed GetAsync must not cost a player their data
		for attempt = 1, 3 do
			local ok, stored = pcall(function()
				return profileStore:GetAsync("p" .. player.UserId)
			end)
			if ok then
				return true, stored
			end
			-- Studio without API access fails the same way every time: don't stall
			if tostring(stored):find("403") or tostring(stored):lower():find("not allowed") then
				break
			end
			if attempt < 3 then
				task.wait(attempt * 2)
			end
		end
		return false, nil
	end

	local function load(player)
		local profile = freshProfile()
		if profileStore then
			local ok, stored = fetchStored(player)
			if not ok then
				loadFailed[player] = true
				warn(string.format(
					"[Tmod] Couldn't load %s's profile — playing on a session-only profile and NOT saving, so their stored data is never overwritten.",
					player.Name))
			end
			pcall(function()
				if type(stored) == "table" then
					profile.wins = tonumber(stored.wins) or 0
					profile.curriculums = tonumber(stored.curriculums) or 0
					profile.bestTime = tonumber(stored.bestTime)
					profile.bestGrade = type(stored.bestGrade) == "string" and stored.bestGrade or nil
					if type(stored.recent) == "table" then
						for index = 1, math.min(5, #stored.recent) do
							local t = tonumber(stored.recent[index])
							if t then
								table.insert(profile.recent, t)
							end
						end
					end
					if type(stored.binds) == "table" then
						profile.binds = stored.binds
					end
					if type(stored.hudLayout) == "table" then
						profile.hudLayout = stored.hudLayout
					end
					if type(stored.settings) == "table" then
						profile.settings = stored.settings
					end
					if type(stored.ownedCosmetics) == "table" then
						for id, owned in pairs(stored.ownedCosmetics) do
							-- keep only ids that still exist in the config
							if owned == true and Cosmetics.byId(id) then
								profile.ownedCosmetics[id] = true
							end
						end
					end
					if type(stored.equippedCosmetics) == "table" then
						for target, id in pairs(stored.equippedCosmetics) do
							local cosmetic = Cosmetics.byId(id)
							if cosmetic and cosmetic.target == target then
								profile.equippedCosmetics[target] = id
							end
						end
					end
				end
			end)
		end
		return profile
	end

	local function save(player)
		local profile = profiles[player]
		if not profile or not profileStore or loadFailed[player] then
			return
		end
		dirty[player] = nil
		local ok, err = pcall(function()
			profileStore:SetAsync("p" .. player.UserId, {
				wins = profile.wins,
				curriculums = profile.curriculums,
				bestTime = profile.bestTime,
				bestGrade = profile.bestGrade,
				recent = profile.recent,
				binds = profile.binds,
				hudLayout = profile.hudLayout,
				settings = profile.settings,
				ownedCosmetics = profile.ownedCosmetics,
				equippedCosmetics = profile.equippedCosmetics,
			})
		end)
		if not ok then
			dirty[player] = true -- retry on the next autosave pass
			warn("[Tmod] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		end
		-- the leaderboard only needs a write when the best time actually improved
		if bestDirty[player] and profile.bestTime and timeStore then
			bestDirty[player] = nil
			local okBest = pcall(function()
				-- ascending leaderboard: store milliseconds
				timeStore:SetAsync(tostring(player.UserId), math.floor(profile.bestTime * 1000))
			end)
			if not okBest then
				bestDirty[player] = true
			end
		end
	end

	-- Changes are batched: mark dirty here, the autosave loop (and leaving /
	-- server close) writes. Saving on every click would burn the DataStore
	-- budget and trip the per-key write cooldown.
	local function markDirty(player)
		dirty[player] = true
	end

	-- One load per player, ever: concurrent callers wait for the first load
	-- instead of racing a second GetAsync whose result could clobber the first.
	function self.get(player)
		local profile = profiles[player]
		if profile then
			return profile
		end
		if loading[player] then
			while loading[player] and player.Parent do
				task.wait()
			end
			return profiles[player] or freshProfile()
		end
		loading[player] = true
		profile = load(player)
		loading[player] = nil
		if player.Parent then
			profiles[player] = profile
		end
		return profile
	end

	function self.isUnlocked(player)
		return self.get(player).wins > 0
	end

	-- ---------- round results ----------

	-- Returns true when this was the player's FIRST win (modes just unlocked).
	function self.recordWin(player, elapsed, grade)
		local profile = self.get(player)
		local firstWin = profile.wins == 0
		profile.wins = profile.wins + 1
		table.insert(profile.recent, 1, elapsed)
		while #profile.recent > 5 do
			table.remove(profile.recent)
		end
		if not profile.bestTime or elapsed < profile.bestTime then
			profile.bestTime = elapsed
			bestDirty[player] = true
		end
		if grade and gradeRank(grade) < gradeRank(profile.bestGrade) then
			profile.bestGrade = grade
		end
		markDirty(player)
		return firstWin
	end

	-- Add (or subtract) currency; returns the new balance.
	function self.addCurrency(player, amount)
		local profile = self.get(player)
		profile.curriculums = math.max(0, (profile.curriculums or 0) + (amount or 0))
		markDirty(player)
		return profile.curriculums
	end

	function self.getCurrency(player)
		return self.get(player).curriculums or 0
	end

	-- ---------- cosmetics ----------

	-- the { owned, equipped } snapshot the client needs to render shop + HUD
	local function cosmeticPayload(profile)
		local owned = {}
		for id in pairs(profile.ownedCosmetics or {}) do
			owned[id] = true
		end
		local equipped = {}
		for target, id in pairs(profile.equippedCosmetics or {}) do
			equipped[target] = id
		end
		return { owned = owned, equipped = equipped }
	end

	function self.getCosmetics(player)
		return cosmeticPayload(self.get(player))
	end

	-- The Color3 a target (item id / "NICKEL") should render with for this
	-- player — used server-side for the BSODA spray tint.
	function self.getEquippedColor(player, target)
		local profile = self.get(player)
		return Cosmetics.colorFor(target, profile.equippedCosmetics, profile.ownedCosmetics)
	end

	-- tint for the BSODA spray billboard (the skin's sprayColor, falling back to its color)
	function self.getEquippedSprayColor(player, target)
		local profile = self.get(player)
		return Cosmetics.sprayColorFor(target, profile.equippedCosmetics, profile.ownedCosmetics)
	end

	-- Buy a cosmetic. Returns ok, message. Server-authoritative: validates the
	-- id, that it isn't already owned, and that the balance covers the price.
	function self.buyCosmetic(player, id)
		local cosmetic = Cosmetics.byId(id)
		if not cosmetic then
			return false, "Unknown item"
		end
		local profile = self.get(player)
		if Cosmetics.isOwned(cosmetic, profile.ownedCosmetics) then
			return false, "Already owned"
		end
		local price = cosmetic.price or 0
		if (profile.curriculums or 0) < price then
			return false, "Not enough " .. ((ctx.config.CURRENCY and ctx.config.CURRENCY.NAME) or "Curriculums")
		end
		profile.curriculums = profile.curriculums - price
		profile.ownedCosmetics[id] = true
		markDirty(player)
		return true, "Purchased " .. cosmetic.displayName .. "!"
	end

	-- Equip an owned cosmetic for its target. Returns ok, message.
	function self.equipCosmetic(player, id)
		local cosmetic = Cosmetics.byId(id)
		if not cosmetic then
			return false, "Unknown item"
		end
		local profile = self.get(player)
		if not Cosmetics.isOwned(cosmetic, profile.ownedCosmetics) then
			return false, "You don't own that"
		end
		profile.equippedCosmetics[cosmetic.target] = id
		markDirty(player)
		return true, "Equipped " .. cosmetic.displayName
	end

	-- ---------- keybinds ----------

	local VALID_ACTIONS = { USE = true, SWAP = true, SPRINT = true, CANCEL = true }

	function self.saveBinds(player, binds)
		if type(binds) ~= "table" then
			return false
		end
		local clean = {}
		for action, keyName in pairs(binds) do
			if VALID_ACTIONS[action] and type(keyName) == "string" then
				local ok = pcall(function()
					return Enum.KeyCode[keyName]
				end)
				if ok then
					clean[action] = keyName
				end
			end
		end
		local profile = self.get(player)
		profile.binds = clean
		markDirty(player)
		return true
	end

	-- ---------- mobile HUD layout ----------

	local HUD_KEYS = { sprint = true, use = true, swap = true }

	function self.saveHudLayout(player, layout)
		if type(layout) ~= "table" then
			return false
		end
		local cfg = ctx.config.MOBILE_HUD or {}
		local minScale = cfg.MIN_SCALE or 0.6
		local maxScale = cfg.MAX_SCALE or 1.7
		local clean = {}
		for key, entry in pairs(layout) do
			if HUD_KEYS[key] and type(entry) == "table" then
				local x, y, scale = tonumber(entry.x), tonumber(entry.y), tonumber(entry.scale)
				if x and y and scale then
					clean[key] = {
						x = math.clamp(x, 0, 1),
						y = math.clamp(y, 0, 1),
						scale = math.clamp(scale, minScale, maxScale),
					}
				end
			end
		end
		local profile = self.get(player)
		profile.hudLayout = clean
		markDirty(player)
		return true
	end

	-- ---------- client settings (stopwatch toggle, SFX volume) ----------

	function self.saveSettings(player, settings)
		if type(settings) ~= "table" then
			return false
		end
		local defaults = ctx.config.DEFAULT_SETTINGS or {}
		local clean = {}
		if settings.stopwatch == nil then
			clean.stopwatch = defaults.stopwatch ~= false
		else
			clean.stopwatch = settings.stopwatch == true
		end
		local vol = tonumber(settings.sfxVolume)
		clean.sfxVolume = vol and math.clamp(vol, 0, 1) or (defaults.sfxVolume or 1)
		local profile = self.get(player)
		profile.settings = clean
		markDirty(player)
		return true
	end

	-- ---------- leaderboard ----------

	local leaderboardCache = {} -- { { name, time } } sorted fastest first
	local leaderboardFetchedAt = 0
	local nameCache = {} -- [userId] = display name

	local function lookupName(userId)
		if nameCache[userId] then
			return nameCache[userId]
		end
		local inServer = Players:GetPlayerByUserId(userId)
		local name = inServer and inServer.DisplayName or nil
		if not name then
			pcall(function()
				name = Players:GetNameFromUserIdAsync(userId)
			end)
		end
		name = name or ("Player " .. userId)
		nameCache[userId] = name
		return name
	end

	local function refreshLeaderboard()
		if not timeStore or os.clock() - leaderboardFetchedAt < 60 then
			return
		end
		leaderboardFetchedAt = os.clock()
		pcall(function()
			local page = timeStore:GetSortedAsync(true, 10):GetCurrentPage()
			local fresh = {}
			for _, entry in ipairs(page) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(fresh, {
						name = lookupName(userId),
						time = entry.value / 1000,
					})
				end
			end
			leaderboardCache = fresh
		end)
	end

	-- ---------- stats payload for the menus ----------

	function self.sendStats(player)
		local profile = self.get(player)
		ctx.remotes.StatsData:FireClient(player, {
			wins = profile.wins,
			curriculums = profile.curriculums or 0,
			unlocked = profile.wins > 0,
			bestTime = profile.bestTime,
			bestGrade = profile.bestGrade,
			recent = profile.recent,
			binds = profile.binds or DEFAULT_BINDS,
			hudLayout = profile.hudLayout,
			settings = profile.settings or ctx.config.DEFAULT_SETTINGS,
			cosmetics = cosmeticPayload(profile),
			leaderboard = leaderboardCache,
		})
	end

	-- ---------- wiring ----------

	local statsDebounce = {} -- [player] = next allowed StatsRequest time
	ctx.remotes.StatsRequest.OnServerEvent:Connect(function(player)
		if (statsDebounce[player] or 0) > os.clock() then
			return
		end
		statsDebounce[player] = os.clock() + 1
		task.spawn(function()
			refreshLeaderboard()
			self.sendStats(player)
		end)
	end)

	ctx.remotes.SaveBinds.OnServerEvent:Connect(function(player, binds)
		self.saveBinds(player, binds)
	end)

	ctx.remotes.SaveHudLayout.OnServerEvent:Connect(function(player, layout)
		self.saveHudLayout(player, layout)
	end)

	ctx.remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		self.saveSettings(player, settings)
	end)

	ctx.remotes.BuyCosmetic.OnServerEvent:Connect(function(player, id)
		if type(id) ~= "string" then
			return
		end
		local ok, message = self.buyCosmetic(player, id)
		if ok and ctx.badges then
			ctx.badges.checkCosmetics(player, self.get(player).ownedCosmetics)
		end
		ctx.remotes.CosmeticResult:FireClient(player, ok, message, id, "buy")
		self.sendStats(player) -- refresh balance + owned set on the client
	end)

	ctx.remotes.EquipCosmetic.OnServerEvent:Connect(function(player, id)
		if type(id) ~= "string" then
			return
		end
		local ok, message = self.equipCosmetic(player, id)
		ctx.remotes.CosmeticResult:FireClient(player, ok, message, id, "equip")
		self.sendStats(player) -- refresh equipped set on the client
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self.get(player)
			refreshLeaderboard()
			self.sendStats(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self.get(player)
			refreshLeaderboard()
			self.sendStats(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		if dirty[player] or bestDirty[player] then
			save(player)
		end
		profiles[player] = nil
		dirty[player] = nil
		bestDirty[player] = nil
		loadFailed[player] = nil
		statsDebounce[player] = nil
	end)

	-- autosave: flush whoever has unsaved changes
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in pairs(dirty) do
				if player.Parent then
					task.spawn(save, player)
				else
					dirty[player] = nil
				end
			end
		end
	end)

	if not RunService:IsStudio() then
		game:BindToClose(function()
			-- save everyone in parallel, then wait (BindToClose allows ~30s)
			local pending = 0
			for _, player in ipairs(Players:GetPlayers()) do
				if dirty[player] or bestDirty[player] then
					pending += 1
					task.spawn(function()
						save(player)
						pending -= 1
					end)
				end
			end
			local deadline = os.clock() + 25
			while pending > 0 and os.clock() < deadline do
				task.wait(0.1)
			end
		end)
	end

	ctx.profiles = self
	return self
end

return PlayerProfiles
