--[[
	MatchServer (ModuleScript, ServerScriptService.BaldiGame.MatchServer)

	Turns a reserved server (the dedicated Multiplayer place, launched by the
	Hub) into a SYNCHRONIZED multiplayer MATCH.

	Synchronized start — the round does NOT begin on the first arrival. Instead:
	  1. The Hub teleports the whole party with TeleportData = { source="hub",
	     leaderUserId, party = { userIds } }. We read that on arrival to learn the
	     EXPECTED roster (who, and how many, should show up).
	  2. Each match client fires the MatchReady remote once it has fully loaded
	     (character + map + UI). We collect "ready" signals.
	  3. When every expected member has arrived AND signalled ready, we start the
	     whole party together via ctx.manager.beginMatch (one get-ready countdown,
	     everyone drops in at once).
	  4. Safety valves so it can never hang: a LOBBY_WAIT timeout starts with
	     whoever is in; a disconnect during loading shrinks the expected roster; a
	     missing/invalid roster (direct join) falls back to "whoever is present".

	While waiting, MatchLobby is pushed to clients so the loading screen can show
	"players ready: X / Y".

	Studio (MATCH.STUDIO_TEST) has no reserved servers or TeleportData, so it uses
	a simple auto-seat path instead of the gate. Normal/public servers aren't
	match servers at all (isMatchServer() is false) and run the solo game.

	NOTE: reserved servers + teleports only exist on PUBLISHED servers.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MatchServer = {}

-- Validate the party roster the Hub attached, returning a clean array of userId
-- numbers (or nil). Defends against absent/garbage TeleportData.
local function readParty(player)
	local ok, data = pcall(function()
		local jd = player:GetJoinData()
		return jd and jd.TeleportData
	end)
	if not ok or type(data) ~= "table" then
		return nil, nil
	end
	if data.source ~= "hub" or type(data.party) ~= "table" then
		return nil, data.leaderUserId
	end
	local ids = {}
	for _, id in ipairs(data.party) do
		if type(id) == "number" then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return nil, data.leaderUserId
	end
	return ids, data.leaderUserId
end

function MatchServer.init(ctx)
	local self = {}
	local matchCfg = ctx.config.MATCH or {}

	local isReserved = (not RunService:IsStudio())
		and game.PrivateServerId ~= ""
		and game.PrivateServerOwnerId == 0
	local studioTest = RunService:IsStudio() and matchCfg.STUDIO_TEST == true
	local isMatch = isReserved or studioTest

	function self.isMatchServer()
		return isMatch
	end

	-- ---------- return everyone to the Hub when the match ends ----------
	local returning = false
	function self.returnAllToHub()
		if returning or RunService:IsStudio() then
			return
		end
		returning = true
		local hubId = matchCfg.HUB_PLACE_ID
		if not hubId or hubId == 0 then
			return
		end
		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end
		task.spawn(function()
			pcall(function()
				TeleportService:TeleportAsync(hubId, players)
			end)
		end)
	end

	-- ================= the synchronized-start gate (reserved servers) =========
	local function setupSyncGate()
		local expectedIds = {} -- [userId] = true (frozen roster of who should arrive)
		local expectedCount = 0
		local leaderUserId = nil
		local rosterFrozen = false
		local fallbackArmed = false

		local arrived = {} -- [userId] = true (present in this server)
		local ready = {} -- [userId] = true (fired MatchReady = fully loaded)
		local started = false

		local function countReady()
			local n = 0
			for id in pairs(expectedIds) do
				if arrived[id] and ready[id] then
					n += 1
				end
			end
			return n
		end

		local function broadcastLobby()
			if started then
				return
			end
			local info = { ready = countReady(), expected = expectedCount }
			for _, player in ipairs(Players:GetPlayers()) do
				ctx.remotes.MatchLobby:FireClient(player, info)
			end
		end

		-- ordered list: leader first, then the rest of the ready party
		local function orderedReady()
			local list = {}
			if leaderUserId and arrived[leaderUserId] and ready[leaderUserId] then
				local lp = Players:GetPlayerByUserId(leaderUserId)
				if lp then
					table.insert(list, lp)
				end
			end
			for id in pairs(ready) do
				if id ~= leaderUserId and arrived[id] then
					local p = Players:GetPlayerByUserId(id)
					if p then
						table.insert(list, p)
					end
				end
			end
			return list
		end

		local function start()
			if started then
				return
			end
			started = true
			local players = orderedReady()
			if #players == 0 then
				-- forced (timeout) with nobody flagged ready: seat whoever is present
				for _, player in ipairs(Players:GetPlayers()) do
					table.insert(players, player)
				end
			end
			if #players > 0 then
				ctx.manager.beginMatch(players)
			end
			-- if still empty: an empty reserved server — nothing to start. Late
			-- joiners route through joinMatch below and get their own countdown.
		end

		local function tryStart()
			if started or not rosterFrozen or expectedCount == 0 then
				return
			end
			for id in pairs(expectedIds) do
				if not (arrived[id] and ready[id]) then
					return -- still waiting on someone
				end
			end
			start()
		end

		local function freezeRoster(ids, leader)
			if rosterFrozen then
				return
			end
			for _, id in ipairs(ids) do
				expectedIds[id] = true
			end
			expectedCount = #ids
			leaderUserId = leader
			rosterFrozen = true
			-- hard timeout: never wait forever on a slow/failed loader
			task.delay(matchCfg.LOBBY_WAIT or 25, function()
				if not started then
					start()
				end
			end)
		end

		-- If TeleportData never brings a roster (direct join / no data), treat
		-- whoever is present as the roster after a short grace, so we still start.
		local function armRosterFallback()
			if fallbackArmed or rosterFrozen then
				return
			end
			fallbackArmed = true
			task.delay(matchCfg.ROSTER_FALLBACK or 6, function()
				if rosterFrozen or started then
					return
				end
				local ids = {}
				for id in pairs(arrived) do
					table.insert(ids, id)
				end
				if #ids > 0 then
					freezeRoster(ids, leaderUserId)
					tryStart()
				end
			end)
		end

		local function onArrive(player)
			local id = player.UserId
			arrived[id] = true
			if started then
				ctx.manager.joinMatch(player) -- straggler drops into the running round
				return
			end
			if not rosterFrozen then
				local ids, leader = readParty(player)
				leaderUserId = leaderUserId or leader
				if ids then
					freezeRoster(ids, leader)
				else
					armRosterFallback()
				end
			end
			broadcastLobby()
			tryStart()
		end

		ctx.remotes.MatchReady.OnServerEvent:Connect(function(player)
			ready[player.UserId] = true
			if started then
				ctx.manager.joinMatch(player) -- loaded after the gate opened: drop in
				return
			end
			broadcastLobby()
			tryStart()
		end)

		Players.PlayerRemoving:Connect(function(player)
			local id = player.UserId
			arrived[id] = nil
			ready[id] = nil
			if not started then
				-- shrink the expected roster so a disconnect during loading can't
				-- make the gate wait forever on someone who left
				if expectedIds[id] then
					expectedIds[id] = nil
					expectedCount = math.max(0, expectedCount - 1)
				end
				broadcastLobby()
				tryStart()
			end
		end)

		Players.PlayerAdded:Connect(onArrive)
		for _, player in ipairs(Players:GetPlayers()) do
			onArrive(player)
		end

		print("[BaldiGame] Match server ready — synchronized lobby waiting for the party.")
	end

	-- ================= Studio test: simple auto-seat (no gate) ================
	local function setupLegacySeating()
		local seated = {}
		local function seat(player)
			if seated[player] then
				return
			end
			seated[player] = true
			task.spawn(function()
				if not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) then
					player.CharacterAdded:Wait()
					task.wait(0.4)
				end
				if ctx.manager and ctx.manager.joinMatch then
					ctx.manager.joinMatch(player)
				end
			end)
		end
		Players.PlayerAdded:Connect(seat)
		for _, player in ipairs(Players:GetPlayers()) do
			seat(player)
		end
		Players.PlayerRemoving:Connect(function(player)
			seated[player] = nil
		end)
		print("[BaldiGame] Match server (Studio test) — auto-seating on the normal map.")
	end

	if isMatch then
		if studioTest then
			setupLegacySeating()
		else
			setupSyncGate()
		end
	end

	ctx.matchServer = self
	return self
end

return MatchServer
