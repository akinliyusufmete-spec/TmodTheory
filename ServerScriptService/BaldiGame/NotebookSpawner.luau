--[[
	NotebookSpawner (ModuleScript, ServerScriptService.BaldiGame.NotebookSpawner)

	Random notebook generation:
	  1. Your map provides spawn points (BaldiMap/NotebookSpawns children,
	     plus anything you tagged "NotebookSpawn" yourself).
	  2. CollectionService:GetTagged("NotebookSpawn") collects them.
	  3. Fisher-Yates shuffle, take the first NOTEBOOK_SPAWN_COUNT (10).
	  4. Clone the notebook model at each chosen node — YOUR model from
	     ReplicatedStorage/BaldiAssets/Items/Notebook if it exists, else a
	     placeholder built in code.
	  5. Each notebook is randomly assigned a type from NOTEBOOK_TYPES
	     (red/blue/green/purple). The type sets the cover color and which
	     minigame it opens (timing bar, math, memory tile, or sequence).
	  6. ProximityPrompt collect -> starts the notebook's minigame.

	The gentle spin/bob that makes notebooks read as pickups runs on each
	CLIENT (NotebookSkinner), driven by the BobPhase / BobSpeed attributes set
	here — the server never moves a notebook after placing it, so there's no
	per-frame CFrame replication.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetResolver = require(script.Parent.AssetResolver)

local NotebookSpawner = {}

local function buildPlaceholderTemplate()
	local folder = ReplicatedStorage:FindFirstChild("BaldiModels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BaldiModels"
		folder.Parent = ReplicatedStorage
	end
	local existing = folder:FindFirstChild("Notebook")
	if existing then
		return existing
	end

	local model = Instance.new("Model")
	model.Name = "Notebook"

	local cover = Instance.new("Part")
	cover.Name = "Cover"
	cover.Size = Vector3.new(1.7, 0.35, 2.2)
	cover.Color = Color3.fromRGB(200, 40, 40)
	cover.Material = Enum.Material.SmoothPlastic
	cover.Anchored = true
	cover.CanCollide = false
	cover.TopSurface = Enum.SurfaceType.Smooth
	cover.BottomSurface = Enum.SurfaceType.Smooth
	cover.Parent = model

	local pages = Instance.new("Part")
	pages.Name = "Pages"
	pages.Size = Vector3.new(1.5, 0.12, 2)
	pages.Color = Color3.fromRGB(245, 245, 235)
	pages.Material = Enum.Material.SmoothPlastic
	pages.Anchored = true
	pages.CanCollide = false
	pages.CFrame = cover.CFrame * CFrame.new(0, 0.23, 0)
	pages.Parent = model

	model.PrimaryPart = cover
	model.Parent = folder
	return model
end

-- Weighted random pick from NOTEBOOK_TYPES
local function pickType(types, rng)
	if not types or #types == 0 then
		return { id = "red", color = Color3.fromRGB(200, 40, 40), minigame = "timing" }
	end
	local total = 0
	for _, t in ipairs(types) do
		total = total + (t.weight or 1)
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, t in ipairs(types) do
		acc = acc + (t.weight or 1)
		if roll <= acc then
			return t
		end
	end
	return types[#types]
end

-- Tint the notebook cover to the type's color. Handles both a plain BasePart
-- model (user's Part > BillboardGui > ImageLabel) and a Model with a "Cover".
local function recolorNotebook(notebook, color)
	local cover
	if notebook:IsA("BasePart") then
		cover = notebook
	else
		cover = notebook:FindFirstChild("Cover")
			or notebook.PrimaryPart
			or notebook:FindFirstChildWhichIsA("BasePart")
	end
	if cover then
		cover.Color = color
	end
	-- Also tint any BillboardGui ImageLabel so image-based notebooks pick it up
	local label = notebook:FindFirstChildWhichIsA("ImageLabel", true)
	if label then
		label.ImageColor3 = color
	end
end

function NotebookSpawner.init(ctx)
	local self = {}
	local active = {} -- [model] = { kind = string }
	local rng = Random.new()
	local sessions = {} -- [player] = { kind, notebook, position, ... }
	local minigameCfg  = ctx.config.NOTEBOOK_MINIGAME
	local sequenceCfg  = ctx.config.SEQUENCE_MINIGAME
	local notebookTypes = ctx.config.NOTEBOOK_TYPES

	-- ===================== session limits per kind =====================

	local function sessionLimits(kind)
		if kind == "sequence" then
			return sequenceCfg.MAX_SECONDS, sequenceCfg.CANCEL_DISTANCE
		elseif kind == "math" then
			local c = ctx.config.MATH_MINIGAME or {}
			return c.MAX_SECONDS or 30, c.CANCEL_DISTANCE or 12
		elseif kind == "memory" then
			local c = ctx.config.MEMORY_MINIGAME or {}
			return c.MAX_SECONDS or 45, c.CANCEL_DISTANCE or 12
		end
		return minigameCfg.MAX_SECONDS, minigameCfg.CANCEL_DISTANCE
	end

	-- ===================== notebook minigames =====================

	local function clearSession(player, tellClient)
		if not sessions[player] then
			return
		end
		sessions[player] = nil
		if tellClient and player.Parent then
			ctx.remotes.NotebookMinigame:FireClient(player, nil)
		end
	end

	local function collect(player, notebook)
		if not active[notebook] then
			return
		end
		active[notebook] = nil
		notebook:Destroy()
		ctx.manager.onNotebookCollected(player)
	end

	local function startSession(player, notebook)
		local position = notebook:GetPivot().Position

		-- mode MINIGAME overrides notebook type (Impersonator forces "sequence")
		local modeCfg = ctx.manager.getModeConfig and ctx.manager.getModeConfig() or nil
		local modeOverride = modeCfg and modeCfg.MINIGAME
		local kind = modeOverride
			or (active[notebook] and active[notebook].kind)
			or "timing"

		local session = {
			kind      = kind,
			notebook  = notebook,
			position  = position,
			hits      = 0,
			lastHitAt = 0,
			startedAt = os.clock(),
		}
		local payload = { kind = kind, position = position }

		if kind == "sequence" then
			local pattern = {}
			for _ = 1, sequenceCfg.LENGTH do
				table.insert(pattern, rng:NextInteger(1, 2) == 1 and "USE" or "SWAP")
			end
			session.pattern = pattern
			session.minSeconds = sequenceCfg.LENGTH * sequenceCfg.SHOW_SECONDS
				+ sequenceCfg.LENGTH * sequenceCfg.MIN_PRESS_GAP
			payload.pattern = pattern
			payload.show    = sequenceCfg.SHOW_SECONDS

		elseif kind == "math" then
			-- generate a simple arithmetic question and four choices
			local ops = { "+", "-", "*" }
			local op = ops[rng:NextInteger(1, #ops)]
			local a, b, answer
			if op == "+" then
				a = rng:NextInteger(1, 20); b = rng:NextInteger(1, 20); answer = a + b
			elseif op == "-" then
				a = rng:NextInteger(11, 30); b = rng:NextInteger(1, a - 1); answer = a - b
			else
				a = rng:NextInteger(2, 9); b = rng:NextInteger(2, 9); answer = a * b
			end
			local question = a .. " " .. op .. " " .. b .. " = ?"
			local choices = { answer }
			local attempts = 0
			while #choices < 4 and attempts < 40 do
				attempts += 1
				local spread = (op == "*")
					and rng:NextInteger(-15, 15)
					or  rng:NextInteger(-9, 9)
				if spread == 0 then spread = rng:NextInteger(1, 5) end
				local wrong = answer + spread
				if wrong > 0 then
					local dupe = false
					for _, c in ipairs(choices) do
						if c == wrong then dupe = true end
					end
					if not dupe then table.insert(choices, wrong) end
				end
			end
			-- shuffle choices
			for i = #choices, 2, -1 do
				local j = rng:NextInteger(1, i)
				choices[i], choices[j] = choices[j], choices[i]
			end
			session.answer   = answer
			payload.question = question
			payload.choices  = choices

		elseif kind == "memory" then
			local memCfg = ctx.config.MEMORY_MINIGAME or {}
			local length   = memCfg.SEQUENCE_LENGTH or 4
			local showEach = memCfg.SHOW_EACH or 0.65
			local showGap  = memCfg.SHOW_GAP  or 0.1
			local colors   = { "red", "blue", "green", "yellow" }
			local sequence = {}
			for _ = 1, length do
				table.insert(sequence, colors[rng:NextInteger(1, #colors)])
			end
			session.sequence   = sequence
			session.minSeconds = length * (showEach + showGap)
			payload.sequence   = sequence
			payload.showEach   = showEach
			payload.showGap    = showGap

		else -- "timing"
			payload.hits = minigameCfg.HITS
		end

		sessions[player] = session
		ctx.remotes.NotebookMinigame:FireClient(player, payload)

		-- watcher: abandon if the player walks off, gets grabbed, round ends, etc.
		local maxSeconds, cancelDistance = sessionLimits(kind)
		task.spawn(function()
			while sessions[player] == session do
				local character = player.Parent and player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if os.clock() - session.startedAt > maxSeconds
					or not active[notebook]
					or not ctx.manager.isRoundActive()
					or not ctx.manager.isParticipant(player)
					or not hrp
					or hrp.Anchored
					or (hrp.Position - position).Magnitude > cancelDistance then
					clearSession(player, true)
					return
				end
				task.wait(0.25)
			end
		end)
	end

	-- ===================== action handler =====================

	ctx.remotes.NotebookMinigameAction.OnServerEvent:Connect(function(player, action, extra)
		local session = sessions[player]
		if not session then
			return
		end
		if action == "cancel" then
			clearSession(player, false)
			return
		end
		if session.locked then
			return -- a wrong math answer already ended this attempt
		end
		if not ctx.manager.isRoundActive() or not ctx.manager.isParticipant(player) then
			clearSession(player, true)
			return
		end
		local _, cancelDistance = sessionLimits(session.kind)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - session.position).Magnitude > cancelDistance then
			clearSession(player, true)
			return
		end

		-- ---- timing ----
		if action == "hit" and session.kind == "timing" then
			if os.clock() - session.lastHitAt < minigameCfg.MIN_HIT_GAP then
				return
			end
			session.lastHitAt = os.clock()
			session.hits = session.hits + 1
			if session.hits >= minigameCfg.HITS then
				local notebook = session.notebook
				clearSession(player, true)
				collect(player, notebook)
			end

		-- ---- sequence ----
		elseif action == "noise" and session.kind == "sequence" then
			if os.clock() - session.lastHitAt < 1 then
				return
			end
			session.lastHitAt = os.clock()
			if ctx.badges then
				ctx.badges.noteModstatFailed(player) -- a slip in the sequence lock
			end
			if ctx.npcs.Guy and ctx.npcs.Guy.onNotebookFail then
				ctx.npcs.Guy.onNotebookFail(player)
			end
			local sportage = ctx.npcs.Sportage
			if sportage and sportage.hear and not sportage.base.parked then
				sportage.hear(hrp.Position)
			end
		elseif action == "done" and session.kind == "sequence" then
			if os.clock() - session.startedAt < (session.minSeconds or 0) * 0.6 then
				clearSession(player, true)
				return
			end
			local notebook = session.notebook
			clearSession(player, true)
			collect(player, notebook)

		-- ---- math ----
		elseif action == "math_answer" and session.kind == "math" then
			if type(extra) ~= "number" then
				return
			end
			if extra == session.answer then
				local notebook = session.notebook
				clearSession(player, true)
				collect(player, notebook)
			else
				-- wrong: lock the session (no firing all four answers during the
				-- shake), tell the client so it can shake, then close it
				session.locked = true
				if ctx.badges then
					ctx.badges.noteModstatFailed(player)
				end
				ctx.remotes.NotebookMinigame:FireClient(player, { kind = "math_wrong" })
				task.delay(0.8, function()
					if sessions[player] == session then
						clearSession(player, true)
					end
				end)
				if ctx.npcs.Guy and ctx.npcs.Guy.onNotebookFail then
					ctx.npcs.Guy.onNotebookFail(player)
				end
			end

		-- ---- memory ----
		elseif action == "memory_done" and session.kind == "memory" then
			if type(extra) ~= "table" then
				clearSession(player, true)
				return
			end
			-- timing check: can't complete faster than the preview takes
			if os.clock() - session.startedAt < (session.minSeconds or 0) * 0.5 then
				clearSession(player, true)
				return
			end
			-- validate sequence
			if #extra ~= #session.sequence then
				if ctx.badges then
					ctx.badges.noteModstatFailed(player)
				end
				clearSession(player, true)
				if ctx.npcs.Guy and ctx.npcs.Guy.onNotebookFail then
					ctx.npcs.Guy.onNotebookFail(player)
				end
				return
			end
			for i, v in ipairs(session.sequence) do
				if extra[i] ~= v then
					if ctx.badges then
						ctx.badges.noteModstatFailed(player)
					end
					clearSession(player, true)
					if ctx.npcs.Guy and ctx.npcs.Guy.onNotebookFail then
						ctx.npcs.Guy.onNotebookFail(player)
					end
					return
				end
			end
			local notebook = session.notebook
			clearSession(player, true)
			collect(player, notebook)
		end
	end)

	-- ===================== public API =====================

	-- Dress any notebook-shaped prop as a live notebook: a random type color,
	-- the BaldiNotebook tag (so each client applies its notebook skin and
	-- spin/bob), and the bob attributes. Returns the picked type. Guy's fake
	-- uses this too, so the only tell left is his faster wobble (bobSpeed).
	function self.disguise(notebook, bobSpeed)
		local nbType = pickType(notebookTypes, rng)
		recolorNotebook(notebook, nbType.color)
		notebook:SetAttribute("BobPhase", rng:NextNumber(0, math.pi * 2))
		notebook:SetAttribute("BobSpeed", bobSpeed or 1)
		CollectionService:AddTag(notebook, "BaldiNotebook")
		return nbType
	end

	function self.clear()
		for player in pairs(sessions) do
			clearSession(player, true)
		end
		for model in pairs(active) do
			active[model] = nil
			if model.Parent then
				model:Destroy()
			end
		end
		ctx.map.notebooksFolder:ClearAllChildren()
	end

	function self.remainingCount()
		local count = 0
		for model in pairs(active) do
			if model.Parent then
				count = count + 1
			end
		end
		return count
	end

	-- Returns how many notebooks were actually placed this round.
	function self.spawnForRound(countOverride)
		self.clear()

		local template = AssetResolver.itemTemplate("Notebook") or buildPlaceholderTemplate()

		local nodes = {}
		for _, node in ipairs(CollectionService:GetTagged("NotebookSpawn")) do
			if node:IsDescendantOf(ctx.map.root) then
				table.insert(nodes, node)
			end
		end

		-- Fisher-Yates shuffle
		for index = #nodes, 2, -1 do
			local swap = rng:NextInteger(1, index)
			nodes[index], nodes[swap] = nodes[swap], nodes[index]
		end

		local count = math.min(countOverride or ctx.config.NOTEBOOK_SPAWN_COUNT, #nodes)
		for index = 1, count do
			local node = nodes[index]

			local notebook = AssetResolver.preparePropClone(template)
			local baseCFrame = CFrame.new(node.Position + Vector3.new(0, 0.8, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			notebook:PivotTo(baseCFrame)

			-- pick and apply a random type (color + minigame), tag it for the
			-- client skinner + spin/bob
			local nbType = self.disguise(notebook, 1)

			-- collect prompt
			local promptParent = notebook:IsA("BasePart") and notebook
				or notebook.PrimaryPart
				or notebook:FindFirstChildWhichIsA("BasePart", true)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Collect"
			prompt.ObjectText = "Notebook"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = ctx.config.NOTEBOOK_PROMPT_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.Parent = promptParent

			prompt.Triggered:Connect(function(player)
				if not active[notebook] then
					return
				end
				if not ctx.manager.isRoundActive() or not ctx.manager.isParticipant(player) then
					return
				end
				if minigameCfg and minigameCfg.ENABLED then
					if not sessions[player] then
						startSession(player, notebook)
					end
				else
					collect(player, notebook)
				end
			end)

			notebook.Parent = ctx.map.notebooksFolder
			active[notebook] = {
				kind = nbType.minigame, -- "timing" | "math" | "memory" | "sequence"
			}
		end

		return count
	end

	ctx.notebookSpawner = self
	return self
end

return NotebookSpawner
