--[[
	GameManager (ModuleScript, ServerScriptService.BaldiGame.GameManager)

	The round state machine:

	  IDLE ── Play pressed ──> COUNTDOWN (3s, players anchored at entrance)
	       <── all players out ── ACTIVE (notebooks spawned, NPCs gated)

	Activation gating:
	  0 notebooks    -> all NPCs frozen
	  1 notebook     -> all NPCs activate (roam loops start)
	  last notebook  -> the main chaser enrages + the exit opens

	Per-player outcomes:
	  - Caught by ChatRevive -> lose screen, a Nickel drops at the spot.
	  - Reach the open exit  -> win screen with elapsed + session best time.
	Players pressing Play during an active round simply join it.

	On the main screen (spawning, or after a run) a player's character
	floats, anchored, above RoundSpawn (GameConfig.PLAYER.MENU_FLOAT_HEIGHT).
]]

local Players = game:GetService("Players")

local GameManager = {}

function GameManager.init(ctx)
	local self = {}
	local config = ctx.config
	local remotes = ctx.remotes

	local phase = "IDLE" -- IDLE | COUNTDOWN | ACTIVE
	local participants = {} -- [player] = true
	local notebooksCollected = 0
	local notebooksTotal = config.NOTEBOOK_SPAWN_COUNT
	local roundStartedAt = 0
	local bestTimes = {} -- [userId] = seconds (session best)
	local startDebounce = {} -- [player] = next allowed RequestStart time
	local roundStats = {} -- [player] = { detentions = n, grabs = n }

	-- ===================== report card =====================

	local GRADE_LADDER = { "A+", "A", "B", "C", "D", "F" }

	local function getStats(player)
		local stats = roundStats[player]
		if not stats then
			stats = { detentions = 0, grabs = 0 }
			roundStats[player] = stats
		end
		return stats
	end

	-- DetentionSystem / SilverAI report blemishes for the report card
	function self.recordDetention(player)
		if participants[player] then
			getStats(player).detentions = getStats(player).detentions + 1
		end
	end

	function self.recordGrab(player)
		if participants[player] then
			getStats(player).grabs = getStats(player).grabs + 1
		end
	end

	-- how many times this player has been detained this round (LP escalation)
	function self.getDetentions(player)
		local stats = roundStats[player]
		return (stats and stats.detentions) or 0
	end

	local function computeGrade(player, elapsed)
		local gradeCfg = config.GRADES
		if not gradeCfg then
			return nil
		end
		local baseIndex = #GRADE_LADDER -- slower than every row = F
		for _, row in ipairs(gradeCfg.TIME_GRADES) do
			if elapsed <= row[1] then
				baseIndex = table.find(GRADE_LADDER, row[2]) or #GRADE_LADDER
				break
			end
		end
		local stats = getStats(player)
		local penalty = stats.detentions * gradeCfg.DETENTION_PENALTY
			+ math.floor(stats.grabs / 2) * gradeCfg.GRAB_PENALTY
		return GRADE_LADDER[math.min(baseIndex + penalty, #GRADE_LADDER)]
	end

	-- ===================== queries used by the AIs =====================

	function self.isRoundActive()
		return phase == "ACTIVE"
	end

	function self.isParticipant(player)
		return participants[player] == true
	end

	function self.getNotebookCounts()
		return notebooksCollected, notebooksTotal
	end

	-- 0..1 "heat" the AIs read to escalate with each notebook collected.
	-- CURVE > 1 keeps it calm early and ramps hard near the last notebooks.
	function self.getHeat()
		if not config.HEAT or not config.HEAT.ENABLED or notebooksTotal <= 0 then
			return 0
		end
		local raw = math.clamp(notebooksCollected / notebooksTotal, 0, 1)
		return raw ^ (config.HEAT.CURVE or 1)
	end

	-- ===================== game modes =====================

	local currentModeId = "CLASSIC"
	local classicMap = ctx.map -- the resolved BaldiMap; maze rounds swap it

	function self.getModeId()
		return currentModeId
	end

	function self.getModeConfig()
		return config.MODES[currentModeId] or config.MODES.CLASSIC
	end

	-- Swap the live map (and exit door + NPC posts + sight exclusions) to
	-- the maze for Multiplied rounds, and back again afterwards.
	local classicSpawns = nil
	local function applyModeMap(mode)
		local map = classicMap
		-- park every alternate map first, then activate the one this mode wants
		if ctx.maze then ctx.maze.setActive(false) end
		if ctx.match then ctx.match.setActive(false) end
		if mode.USES_MAZE and ctx.maze then
			map = ctx.maze.get() or classicMap
			if map ~= classicMap then ctx.maze.setActive(true) end
		elseif mode.USES_MATCHMAP and ctx.match then
			map = ctx.match.get() or classicMap -- missing big map falls back to Classic
			if map ~= classicMap then ctx.match.setActive(true) end
		end
		ctx.map = map
		ctx.exitDoor.setDoor(map ~= classicMap and map.exitDoor or nil)

		-- re-post the characters to the active map's spawn markers
		if map ~= classicMap then
			classicSpawns = classicSpawns or {}
			for name, npc in pairs(ctx.npcs) do
				local key = string.upper(name)
				classicSpawns[name] = classicSpawns[name] or npc.base.spawnCFrame
				npc.base.spawnCFrame = map.npcSpawns[key] or classicSpawns[name]
				npc.base:setMapExcludes(map)
			end
		elseif classicSpawns then
			for name, npc in pairs(ctx.npcs) do
				npc.base.spawnCFrame = classicSpawns[name] or npc.base.spawnCFrame
				npc.base:setMapExcludes(classicMap)
			end
			classicSpawns = nil
		end
	end

	-- Park the characters that sit this mode out (they hold far above
	-- their spawn, frozen, until a mode that uses them resets the board).
	-- whether a character takes the field this round: in the mode roster, and
	-- (when DEBUG is on) not switched off in GameConfig.DEBUG.NPCS
	local function npcEnabled(name, roster)
		if not roster[name] then
			return false
		end
		local dbg = config.DEBUG
		if dbg and dbg.ENABLED and dbg.NPCS and dbg.NPCS[name] == false then
			return false
		end
		return true
	end

	local function applyNpcSet(mode)
		local roster = mode.NPCS or {}
		for name, npc in pairs(ctx.npcs) do
			if not npcEnabled(name, roster) then
				npc.base:park()
			end
		end
	end

	function self.isTargetable(player)
		if not participants[player] then
			return false
		end
		local character = player.Character
		if not character then
			return false
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp or humanoid.Health <= 0 then
			return false
		end
		if hrp.Anchored then -- countdown or detention...
			-- ...but a player in Silver's grasp — or rooted in one of
			-- Sportage's traps or Frosty's BEARTrapper — stays fair game:
			-- getting held in the open with a hunter nearby SHOULD be lethal
			local silver = ctx.npcs.Silver
			local sportage = ctx.npcs.Sportage
			local frosty = ctx.npcs.Frosty
			local held = (silver and silver.isGrabbing and silver.isGrabbing(player))
				or (sportage and sportage.isTrapped and sportage.isTrapped(player))
				or (frosty and frosty.isTrapped and frosty.isTrapped(player))
			if not held then
				return false
			end
		end
		if ctx.detention.isDetained(player) then
			return false
		end
		return true
	end

	function self.getTargetablePlayers()
		local list = {}
		for player in pairs(participants) do
			if self.isTargetable(player) then
				table.insert(list, player)
			end
		end
		return list
	end

	-- ===================== helpers =====================

	local function teleportToRoundSpawn(player, anchored)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not hrp then
			return false
		end
		-- spread players a little so they don't stack
		local offset = CFrame.new(math.random(-3, 3), 0, math.random(-2, 2))
		character:PivotTo(ctx.map.roundSpawnCFrame * offset)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		hrp.Anchored = anchored
		-- entering a round is a fresh start: clear any items/coins from a
		-- previous round or a death + retry (every entry path lands here)
		if ctx.economy and ctx.economy.resetPlayer then
			ctx.economy.resetPlayer(player)
		end
		return true
	end

	-- Off to the main screen: the character floats, anchored, high above the
	-- classic RoundSpawn (PLAYER.MENU_FLOAT_HEIGHT) until the next run puts it
	-- on the floor there. Above the roof it's out of every character's reach,
	-- and the school is already streamed in when PLAY drops it in.
	local function teleportToLobby(player)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if character and hrp then
			local height = config.PLAYER.MENU_FLOAT_HEIGHT or 60
			character:PivotTo(classicMap.roundSpawnCFrame * CFrame.new(math.random(-4, 4), height, math.random(-4, 4)))
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.Anchored = true
		end
	end

	local function setNpcsPaused(paused)
		for _, npc in pairs(ctx.npcs) do
			if not npc.base.parked then -- parked characters sit this mode out
				npc.base:setPaused(paused)
			end
		end
	end

	local function resetNpcs()
		for _, npc in pairs(ctx.npcs) do
			if npc.reset then
				npc.reset()
			else
				npc.base:resetToSpawn()
			end
		end
	end

	-- ===================== round flow =====================

	local function endRound()
		if phase == "IDLE" then
			return
		end
		local wasMatch = currentModeId == "MATCH"
		phase = "IDLE"
		ctx.detention.releaseAll()
		ctx.notebookSpawner.clear()
		ctx.economy.clearPickups() -- clears the active (possibly maze) map
		ctx.exitDoor.close()
		-- back to the classic school before anyone teleports to the lobby
		currentModeId = "CLASSIC"
		applyModeMap(config.MODES.CLASSIC)
		for player in pairs(participants) do
			participants[player] = nil
			roundStats[player] = nil
			teleportToLobby(player)
		end
		resetNpcs()
		notebooksCollected = 0
		remotes.RoundEnded:FireAllClients()
		-- a finished match sends everyone back to the Hub to regroup
		if wasMatch and ctx.matchServer then
			ctx.matchServer.returnAllToHub()
		end
	end

	local function checkRoundEnd()
		-- End the round whenever nobody's left in it — during the countdown
		-- too, so a player who resets/leaves mid-countdown can't strand the
		-- game in a phase that never resolves.
		if phase ~= "ACTIVE" and phase ~= "COUNTDOWN" then
			return
		end
		if next(participants) == nil then
			endRound()
		end
	end

	local function fireGameStarted(player)
		local mode = self.getModeConfig()
		remotes.GameStarted:FireClient(player, notebooksTotal, currentModeId, mode.HUNTER or "ChatRevive")
	end

	local function joinActiveRound(player)
		participants[player] = true
		if ctx.badges then
			local count = 0
			for _ in pairs(participants) do
				count += 1
			end
			ctx.badges.playersInRun(count)
		end
		roundStats[player] = { detentions = 0, grabs = 0 }
		if not teleportToRoundSpawn(player, false) then
			participants[player] = nil
			return
		end
		fireGameStarted(player)
		remotes.NotebookCollected:FireClient(player, notebooksCollected, notebooksTotal)
		if ctx.exitDoor.open then
			remotes.PhaseChanged:FireClient(player, "EXIT_OPEN")
		elseif notebooksCollected > 0 then
			remotes.PhaseChanged:FireClient(player, "CHARACTERS_ACTIVE")
		end
	end

	local function beginCountdown(firstPlayer, modeId)
		currentModeId = modeId or "CLASSIC"
		local mode = self.getModeConfig()
		phase = "COUNTDOWN"
		notebooksCollected = 0
		if ctx.loadMap then
			ctx.loadMap() -- the first run brings the school into the world; it stays from then on
		end
		applyModeMap(mode) -- maze in (and bake time for its navmesh) first
		resetNpcs()
		applyNpcSet(mode) -- park whoever sits this mode out
		-- characters who set the board up before anyone moves (Frosty's starting traps)
		for name, npc in pairs(ctx.npcs) do
			if npc.onRoundStart and not npc.base.parked then
				local ok, err = pcall(npc.onRoundStart)
				if not ok then
					warn("[Tmod] " .. name .. ".onRoundStart failed: " .. tostring(err))
				end
			end
		end
		ctx.exitDoor.close()
		notebooksTotal = ctx.notebookSpawner.spawnForRound(mode.NOTEBOOKS)
		ctx.economy.onRoundStart()

		participants[firstPlayer] = true
		roundStats[firstPlayer] = { detentions = 0, grabs = 0 }
		teleportToRoundSpawn(firstPlayer, true)
		local countdownSeconds = mode.COUNTDOWN or config.COUNTDOWN_SECONDS
		remotes.GameCountdown:FireClient(firstPlayer, countdownSeconds)

		-- multiplayer modes get announced so the whole server can pile in
		if not mode.SINGLE_PLAYER and currentModeId ~= "CLASSIC" then
			remotes.RoundAnnounce:FireAllClients(
				firstPlayer.DisplayName .. " started " .. (mode.displayName or currentModeId)
				.. " — press PLAY to join!")
		end

		task.delay(countdownSeconds, function()
			if phase ~= "COUNTDOWN" then
				return
			end
			phase = "ACTIVE"
			roundStartedAt = os.clock()
			if ctx.badges then
				local count = 0
				for _ in pairs(participants) do
					count += 1
				end
				ctx.badges.runStarted(currentModeId, count)
			end
			for player in pairs(participants) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.Anchored = false
				end
				fireGameStarted(player)
				remotes.NotebookCollected:FireClient(player, notebooksCollected, notebooksTotal)
			end
			checkRoundEnd() -- everyone may have left during the countdown
		end)
	end

	-- Seat a Hub-launched player into the MATCH round: the first arrival starts
	-- the countdown, the rest join it (or the active round if it's begun).
	function self.joinMatch(player)
		if participants[player] then
			return
		end
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			return
		end
		if phase == "IDLE" then
			beginCountdown(player, "MATCH")
		elseif currentModeId == "MATCH" and phase == "COUNTDOWN" then
			participants[player] = true
			roundStats[player] = { detentions = 0, grabs = 0 }
			teleportToRoundSpawn(player, true)
			remotes.GameCountdown:FireClient(player, self.getModeConfig().COUNTDOWN or config.COUNTDOWN_SECONDS)
		elseif currentModeId == "MATCH" and phase == "ACTIVE" then
			joinActiveRound(player)
		end
	end

	-- Start a MATCH with a WHOLE loaded party at once. The synced-start gate
	-- (MatchServer) calls this exactly once, after every teleported member has
	-- loaded in and signalled ready — instead of letting the first arrival start
	-- the countdown alone. `players` is an ordered list (leader first).
	function self.beginMatch(players)
		if type(players) ~= "table" or #players == 0 then
			return
		end
		if phase == "IDLE" then
			beginCountdown(players[1], "MATCH") -- opens the round + the get-ready countdown
			for index = 2, #players do
				self.joinMatch(players[index]) -- the rest fall into the same COUNTDOWN
			end
		else
			-- already counting down / active (e.g. a straggler tripped it): just seat them
			for _, player in ipairs(players) do
				self.joinMatch(player)
			end
		end
	end

	-- ===================== notebook -> HUD + gating =====================

	function self.onNotebookCollected(byPlayer)
		notebooksCollected = notebooksCollected + 1
		remotes.NotebookCollected:FireAllClients(notebooksCollected, notebooksTotal, byPlayer.UserId)

		if notebooksCollected == 1 then
			-- first notebook: every character wakes up
			setNpcsPaused(false)
			remotes.PhaseChanged:FireAllClients("CHARACTERS_ACTIVE")
		end
		if notebooksCollected >= notebooksTotal then
			-- final notebook: enrage the mode's hunter + exit phase
			local hunter = ctx.npcs[self.getModeConfig().HUNTER or "ChatRevive"]
			if hunter and hunter.enrage then
				hunter.enrage()
			end
			ctx.exitDoor.openDoor()
			remotes.PhaseChanged:FireAllClients("EXIT_OPEN")
		end
	end

	-- ===================== outcomes =====================

	function self.playerCaught(player, catcherName)
		if not participants[player] then
			return
		end
		participants[player] = nil

		-- the catcher's "Caught" voiceline (shown to the victim over the lose screen)
		if ctx.voicelines then
			ctx.voicelines.sayAs(catcherName, "Caught", { target = player, force = true })
		end

		-- ChatRevive drops a Nickel where the victim stood
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			ctx.economy.spawnNickel(hrp.Position + Vector3.new(0, -1.5, 0))
		end

		if ctx.badges then
			ctx.badges.noteDown(player)
			ctx.badges.onCaught(player, catcherName)
		end

		ctx.detention.releasePlayer(player)
		teleportToLobby(player)
		remotes.PlayerLost:FireClient(player, catcherName,
			catcherName .. " caught you in the halls.", notebooksCollected, notebooksTotal)
		roundStats[player] = nil
		checkRoundEnd()
	end

	-- A non-catch loss: the run is forfeited (e.g. LP's third detention). Same
	-- lose flow as playerCaught but with a custom reason and no dropped Nickel.
	function self.playerForfeit(player, byName, message)
		if not participants[player] then
			return
		end
		participants[player] = nil
		if ctx.badges then
			ctx.badges.noteDown(player)
		end
		ctx.detention.releasePlayer(player)
		teleportToLobby(player)
		remotes.PlayerLost:FireClient(player, byName or "the school",
			message or "Your run was forfeited.", notebooksCollected, notebooksTotal)
		roundStats[player] = nil
		checkRoundEnd()
	end

	-- The escape's Curriculum reward is based purely on speed: TIME_AWARD.MAX at
	-- (or under) FAST_SECONDS, falling in a straight line to TIME_AWARD.MIN at
	-- (or over) SLOW_SECONDS. Rounded to a whole number.
	local function timeAward(elapsed)
		local ta = config.CURRENCY and config.CURRENCY.TIME_AWARD
		if not ta then
			return 0
		end
		local fast = ta.FAST_SECONDS or 60
		local slow = ta.SLOW_SECONDS or 600
		local maxA = ta.MAX or 200
		local minA = ta.MIN or 1
		local alpha = math.clamp((elapsed - fast) / math.max(1, slow - fast), 0, 1)
		return math.floor(maxA + (minA - maxA) * alpha + 0.5)
	end

	function self.playerWon(player)
		if not participants[player] then
			return
		end
		participants[player] = nil

		local elapsed = os.clock() - roundStartedAt
		local best = bestTimes[player.UserId]
		if not best or elapsed < best then
			best = elapsed
			bestTimes[player.UserId] = best
		end
		local grade = computeGrade(player, elapsed)

		-- breakdown: a list of { label, amount } the summary screen counts up.
		local timeReward = timeAward(elapsed)
		local award = timeReward
		local breakdown = { { label = "Escape Time", amount = timeReward } }

		-- cash in the Nickels you escaped with: each is worth NICKEL_TO_CURRICULUMS
		local rate = (config.CURRENCY and config.CURRENCY.NICKEL_TO_CURRICULUMS) or 0
		if rate > 0 and ctx.economy and ctx.economy.getNickels then
			local nickels = ctx.economy.getNickels(player)
			if nickels > 0 then
				local nickelReward = nickels * rate
				award = award + nickelReward
				table.insert(breakdown, { label = "Nickels (" .. nickels .. ")", amount = nickelReward })
			end
		end

		local balance = nil

		-- persist: wins unlock the special modes; times feed the records page
		if ctx.profiles then
			local firstWin = ctx.profiles.recordWin(player, elapsed, grade)
			if ctx.profiles.addCurrency then
				balance = ctx.profiles.addCurrency(player, award) -- before sendStats so it's current
			end
			ctx.profiles.sendStats(player)
			if firstWin then
				-- only announce special modes that are actually open
				local names = {}
				for _, m in pairs(config.MODES) do
					if m.LOCKED_UNTIL_WIN and not m.CLOSED then
						table.insert(names, m.displayName)
					end
				end
				if #names > 0 then
					remotes.RoundAnnounce:FireClient(player,
						table.concat(names, " and ") .. " are now unlocked!")
				end
			end
		end

		if ctx.badges then
			ctx.badges.onWin(player, {
				elapsed = elapsed,
				grade = grade,
				modeId = currentModeId,
				detentions = getStats(player).detentions,
				wins = ctx.profiles and ctx.profiles.get(player).wins or 0,
			})
		end

		ctx.detention.releasePlayer(player)
		teleportToLobby(player)
		remotes.PlayerWon:FireClient(player, elapsed, best, grade, award, balance, breakdown)
		roundStats[player] = nil
		checkRoundEnd()
	end

	-- ===================== player lifecycle =====================

	local function onCharacterAdded(player, character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end
		humanoid.WalkSpeed = config.PLAYER.WALK_SPEED
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "BaldiPlayer"
			end
		end
		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = "BaldiPlayer"
			end
		end)
		humanoid.Died:Connect(function()
			if participants[player] then
				participants[player] = nil
				roundStats[player] = nil
				if ctx.badges then
					ctx.badges.noteDown(player)
				end
				remotes.PlayerLost:FireClient(player, "the schoolhouse",
					"You collapsed. The school wins this time.", notebooksCollected, notebooksTotal)
				checkRoundEnd()
			end
		end)

		-- a fresh character starts on the main screen: float it (unless a run
		-- has already claimed this player, e.g. a match seating them)
		if character:WaitForChild("HumanoidRootPart", 10) then
			task.defer(function()
				if not participants[player] and player.Character == character then
					teleportToLobby(player)
				end
			end)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		if ctx.map.lobbySpawn and ctx.map.lobbySpawn:IsDescendantOf(workspace) then
			player.RespawnLocation = ctx.map.lobbySpawn
		end
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
		ctx.economy.syncAll(player)
	end)

	-- players already present when the server script started (Play Solo race)
	for _, player in ipairs(Players:GetPlayers()) do
		if ctx.map.lobbySpawn and ctx.map.lobbySpawn:IsDescendantOf(workspace) then
			player.RespawnLocation = ctx.map.lobbySpawn
		end
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
			teleportToLobby(player)
		end
		ctx.economy.syncAll(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
		roundStats[player] = nil
		ctx.detention.forget(player)
		ctx.economy.forget(player)
		startDebounce[player] = nil
		checkRoundEnd()
	end)

	-- ===================== Play button =====================

	remotes.RequestStart.OnServerEvent:Connect(function(player, requestedModeId)
		if (startDebounce[player] or 0) > os.clock() then
			return
		end
		startDebounce[player] = os.clock() + 1

		if participants[player] then
			return
		end
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			return
		end

		if phase == "IDLE" then
			-- sanitize + gate the requested mode
			local modeId = (type(requestedModeId) == "string" and config.MODES[requestedModeId])
				and requestedModeId or "CLASSIC"
			local mode = config.MODES[modeId]
			if mode.USES_MATCHMAP then
				-- the multiplayer match is launched from the Hub onto a reserved
				-- server, never from the normal Play button
				remotes.RoundAnnounce:FireClient(player, "Multiplayer is launched from the Hub!")
				return
			end
			if mode.CLOSED then
				-- mode taken offline while it's reworked: never start it
				remotes.RoundAnnounce:FireClient(player, mode.displayName .. " is being reworked — coming soon!")
				return
			end
			if mode.LOCKED_UNTIL_WIN and ctx.profiles and not ctx.profiles.isUnlocked(player) then
				remotes.RoundAnnounce:FireClient(player, "Win a round to unlock " .. mode.displayName .. "!")
				return
			end
			beginCountdown(player, modeId)
		elseif self.getModeConfig().SINGLE_PLAYER then
			-- someone's Impersonator run is in progress: can't pile in
			remotes.RoundAnnounce:FireClient(player,
				"A single-player round is in progress — hang tight!")
		elseif phase == "COUNTDOWN" then
			participants[player] = true
			roundStats[player] = { detentions = 0, grabs = 0 }
			teleportToRoundSpawn(player, true)
			remotes.GameCountdown:FireClient(player,
				self.getModeConfig().COUNTDOWN or config.COUNTDOWN_SECONDS)
		else -- ACTIVE: join the round in progress
			joinActiveRound(player)
		end
	end)

	-- characters that aren't in the Classic roster (Sportage) wait
	-- off-stage until a mode that uses them begins
	applyNpcSet(config.MODES.CLASSIC)

	ctx.manager = self
	return self
end

return GameManager
