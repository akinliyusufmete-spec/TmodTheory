--[[
	MapResolver (ModuleScript, ServerScriptService.BaldiGame.MapResolver)

	Reads YOUR hand-built map from Workspace/BaldiMap. If no BaldiMap
	exists, PlaceholderMap generates the stand-in school (same structure),
	so the resolver treats both identically.

	With GameConfig.MAP_LOADS_ON_FIRST_RUN the map is moved to ServerStorage
	when the server starts (everything is still resolved from it there) and
	ctx.loadMap() brings it into the world when the first run begins; it then
	stays until the server closes.

	Expected structure (see STUDIO_SETUP.md for the full guide):

	  Workspace/BaldiMap
	  ├── Geometry        your walls/floors/furniture. Must contain a Part
	  │                   named "ExitDoor" and a SpawnLocation named
	  │                   "LobbySpawn" (anywhere inside, nesting is fine).
	  │                   Optional: parts/models named VendingMachine_BSODA
	  │                   and VendingMachine_ZESTY (prompts auto-added).
	  ├── Markers         invisible parts marking positions:
	  │                   RoundSpawn (players start here, facing its front),
	  │                   DetentionSpot, ChatReviveSpawn, LpSpawn,
	  │                   FrostySpawn, SilverSpawn
	  ├── SweepRoutes     optional; one folder per sweeper (Guidelines, Sai)
	  │                   holding ordered parts (1, 2, 3...) it sweeps along
	  ├── Waypoints       parts the NPCs roam between (8+ recommended)
	  ├── NotebookSpawns  parts where notebooks may appear (10+ recommended;
	  │                   parts you tag "NotebookSpawn" elsewhere also count)
	  ├── NickelSpawns    optional parts; starter coins appear here
	  │                   (spelled NickleSpawns works too)
	  ├── TrapSpawns      optional parts where Frosty's traps may be set
	  │                   (none: he uses the Waypoints)
	  └── ItemSpawns      optional parts named BSODA / ZESTY; one free
	                      pickup of each appears there per round

	Anything missing gets a clear warning and a sensible fallback, so a
	half-built map still runs.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")

local PlaceholderMap = require(script.Parent.PlaceholderMap)

local MapResolver = {}

local function ensureFolder(root, name)
	local folder = root:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
	end
	return folder
end

-- Marker part -> spawn CFrame (lifted so a humanoid stands on the floor,
-- keeping the marker's orientation so RoundSpawn controls facing).
-- With no marker, borrow one of the map's own Waypoints (spread across them so
-- characters don't stack): the hard-coded fallback coordinates only fit the
-- placeholder school, and on a custom map they can be empty void the NPC falls
-- out of the world from (that's what silently broke Guy).
local function markerCFrame(markersFolder, name, lift, fallbackCFrame, waypointFallback)
	local part = markersFolder and markersFolder:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part.CFrame + Vector3.new(0, lift, 0)
	end
	local borrowed = waypointFallback and waypointFallback()
	warn(string.format(
		"[Tmod] BaldiMap/Markers/%s not found — using %s. Add an invisible Part with that name to control it.",
		name, borrowed and "a Waypoint" or "the default position"))
	if borrowed then
		return CFrame.new(borrowed.Position + Vector3.new(0, lift, 0))
	end
	return fallbackCFrame
end

local function firstBasePart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

-- Resolve any BaldiMap-shaped folder into a map table. Used for the main
-- BaldiMap and again for an optional hand-built BaldiMapMultiplied.
function MapResolver.resolveRoot(ctx, root)
	local config = ctx.config

	local geometry = ensureFolder(root, "Geometry")
	local markers = root:FindFirstChild("Markers")
	local waypoints = ensureFolder(root, "Waypoints")
	local notebookSpawns = ensureFolder(root, "NotebookSpawns")
	local nickelSpawnsFolder = root:FindFirstChild("NickelSpawns") or root:FindFirstChild("NickleSpawns")
	local trapSpawnsFolder = root:FindFirstChild("TrapSpawns")
	local itemSpawnsFolder = root:FindFirstChild("ItemSpawns")

	-- runtime containers (created empty; filled during play)
	local notebooks = ensureFolder(root, "Notebooks")
	local pickups = ensureFolder(root, "Pickups")
	local npcFolder = ensureFolder(root, "Npcs")
	local projectiles = ensureFolder(root, "Projectiles")

	-- ---------- notebook spawn nodes ----------
	-- Children of NotebookSpawns are tagged automatically; any part you
	-- tagged "NotebookSpawn" by hand elsewhere already counts.
	for _, node in ipairs(notebookSpawns:GetChildren()) do
		if node:IsA("BasePart") and not CollectionService:HasTag(node, "NotebookSpawn") then
			CollectionService:AddTag(node, "NotebookSpawn")
		end
	end
	local taggedCount = 0
	for _, node in ipairs(CollectionService:GetTagged("NotebookSpawn")) do
		if node:IsDescendantOf(workspace) or node:IsDescendantOf(root) then
			taggedCount = taggedCount + 1
		end
	end
	if taggedCount < config.NOTEBOOK_SPAWN_COUNT then
		warn(string.format(
			"[Tmod] Only %d notebook spawn points found (want %d+). Add more parts to BaldiMap/NotebookSpawns.",
			taggedCount, config.NOTEBOOK_SPAWN_COUNT))
	end

	if #waypoints:GetChildren() == 0 then
		warn("[Tmod] BaldiMap/Waypoints is empty — NPCs have nowhere to roam. Add invisible parts around your map.")
	end

	-- hands out a different Waypoint to each spawn marker that's missing
	local waypointParts = {}
	for _, node in ipairs(waypoints:GetChildren()) do
		if node:IsA("BasePart") then
			table.insert(waypointParts, node)
		end
	end
	table.sort(waypointParts, function(a, b)
		return a.Name < b.Name
	end)
	local borrowedCount = 0
	local function borrowWaypoint()
		if #waypointParts == 0 then
			return nil
		end
		borrowedCount += 1
		return waypointParts[((borrowedCount * 3) % #waypointParts) + 1]
	end

	-- ---------- named geometry ----------
	local exitDoor = geometry:FindFirstChild("ExitDoor", true)
	if exitDoor and not exitDoor:IsA("BasePart") then
		exitDoor = firstBasePart(exitDoor)
	end
	if not exitDoor then
		warn("[Tmod] No Part named ExitDoor inside BaldiMap/Geometry — players cannot win until you add one.")
	end

	local lobbySpawn = geometry:FindFirstChild("LobbySpawn", true)
	if not (lobbySpawn and lobbySpawn:IsA("SpawnLocation")) then
		lobbySpawn = geometry:FindFirstChildWhichIsA("SpawnLocation", true)
	end
	if not lobbySpawn then
		warn("[Tmod] No SpawnLocation named LobbySpawn in BaldiMap/Geometry — players will spawn at the world origin.")
	end

	-- ---------- vending machines ----------
	-- Any part or model named VendingMachine_<ITEMID>; a ProximityPrompt is
	-- attached automatically unless you already put one on it.
	local vendingMachines = {}
	for _, child in ipairs(geometry:GetDescendants()) do
		local itemId = child.Name:match("^VendingMachine_(%u+)$")
		if itemId and (child:IsA("BasePart") or child:IsA("Model")) and config.ITEMS[itemId] then
			local part = firstBasePart(child)
			if part then
				-- NPCs phase through vending machines (the sweepers were wedging on them)
				for _, vp in ipairs(child:IsA("BasePart") and { child } or child:GetDescendants()) do
					if vp:IsA("BasePart") then
						vp.CollisionGroup = "BaldiVending"
					end
				end
				local prompt = child:FindFirstChildOfClass("ProximityPrompt")
					or part:FindFirstChildOfClass("ProximityPrompt")
				if not prompt then
					prompt = Instance.new("ProximityPrompt")
					prompt.ActionText = "Buy"
					prompt.ObjectText = config.ITEMS[itemId].displayName .. " Machine"
					prompt.HoldDuration = 0
					prompt.MaxActivationDistance = 5
					prompt.RequiresLineOfSight = false
					prompt.Parent = part
				end
				table.insert(vendingMachines, { part = part, prompt = prompt, itemId = itemId })
			end
		end
	end
	if #vendingMachines == 0 then
		print("[Tmod] No vending machines found. Name a part VendingMachine_BSODA or VendingMachine_ZESTY to add one.")
	end

	-- ---------- pickup spawn points ----------
	local nickelSpawns = {}
	if nickelSpawnsFolder then
		for _, node in ipairs(nickelSpawnsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(nickelSpawns, node.Position)
			end
		end
	end
	-- No dedicated NickelSpawns? Scatter the starter coins across the
	-- waypoints so the economy still works out of the box — otherwise
	-- NICKELS_AT_ROUND_START silently does nothing on a custom map.
	if #nickelSpawns == 0 and config.NICKELS_AT_ROUND_START > 0 then
		for _, node in ipairs(waypoints:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(nickelSpawns, node.Position)
			end
		end
		if #nickelSpawns > 0 then
			warn("[Tmod] No BaldiMap/NickelSpawns parts found — scattering starter Nickels on Waypoints instead. Add a NickelSpawns folder with parts to place them where you want.")
		else
			warn("[Tmod] No BaldiMap/NickelSpawns or Waypoints — no starter Nickels can spawn. Add a NickelSpawns folder with parts.")
		end
	end

	local itemSpawns = {}
	if itemSpawnsFolder then
		for _, node in ipairs(itemSpawnsFolder:GetChildren()) do
			if node:IsA("BasePart") and config.ITEMS[node.Name] then
				itemSpawns[node.Name] = node.Position
			end
		end
	end

	-- ---------- Frosty's trap spots ----------
	local trapSpawns = {}
	if trapSpawnsFolder then
		for _, node in ipairs(trapSpawnsFolder:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(trapSpawns, node.Position)
			end
		end
	end
	if #trapSpawns == 0 then
		for _, node in ipairs(waypoints:GetChildren()) do
			if node:IsA("BasePart") then
				table.insert(trapSpawns, node.Position)
			end
		end
		if #trapSpawns > 0 then
			print("[Tmod] No BaldiMap/TrapSpawns parts found — Frosty sets his traps on the Waypoints instead. Put parts in a TrapSpawns folder to choose the spots.")
		end
	end

	-- ---------- item spawner pads ----------
	-- Any part named "ItemSpawner" (anywhere under BaldiMap): during a round
	-- it periodically materializes a random item from GameConfig.ITEMS on
	-- itself (models resolved from ReplicatedStorage/BaldiAssets/Items).
	local itemSpawners = {}
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("BasePart") and node.Name == "ItemSpawner" then
			table.insert(itemSpawners, node.Position)
		end
	end

	-- ---------- sweep routes ----------
	-- SweepRoutes/<SweeperName> is a folder of parts walked in name order
	-- (1, 2, 3...), so a route can turn corners.
	local sweepRoutes = {}
	local routesFolder = root:FindFirstChild("SweepRoutes")
	if routesFolder then
		for _, routeFolder in ipairs(routesFolder:GetChildren()) do
			local parts = {}
			for _, child in ipairs(routeFolder:GetChildren()) do
				if child:IsA("BasePart") then
					table.insert(parts, child)
				end
			end
			table.sort(parts, function(a, b)
				return a.Name < b.Name
			end)
			if #parts >= 2 then
				local points = {}
				for _, part in ipairs(parts) do
					table.insert(points, part.Position)
				end
				sweepRoutes[routeFolder.Name] = points
			else
				warn(string.format(
					"[Tmod] BaldiMap/SweepRoutes/%s needs at least 2 parts to be a route.",
					routeFolder.Name))
			end
		end
	end

	return {
		root = root,
		geometry = geometry,
		waypointsFolder = waypoints,
		spawnNodesFolder = notebookSpawns,
		notebooksFolder = notebooks,
		pickupsFolder = pickups,
		npcFolder = npcFolder,
		projectilesFolder = projectiles,
		exitDoor = exitDoor,
		lobbySpawn = lobbySpawn,
		roundSpawnCFrame = markerCFrame(markers, "RoundSpawn", 2.5,
			CFrame.lookAt(Vector3.new(0, 3.5, -58), Vector3.new(0, 3.5, -30))),
		detentionCFrame = markerCFrame(markers, "DetentionSpot", 2.5,
			CFrame.lookAt(Vector3.new(0, 3.5, -24), Vector3.new(0, 3.5, -36))),
		npcSpawns = {
			CHATREVIVE = markerCFrame(markers, "ChatReviveSpawn", 2, CFrame.new(90, 3, 0), borrowWaypoint),
			LP = markerCFrame(markers, "LpSpawn", 2, CFrame.new(-75, 3, 0), borrowWaypoint),
			FROSTY = markerCFrame(markers, "FrostySpawn", 2, CFrame.new(0, 3, 42), borrowWaypoint),
			SILVER = markerCFrame(markers, "SilverSpawn", 2, CFrame.new(30, 3, -60), borrowWaypoint),
			SPORTAGE = markerCFrame(markers, "SportageSpawn", 2, CFrame.new(90, 3, 0), borrowWaypoint),
			GUY = markerCFrame(markers, "GuySpawn", 2, CFrame.new(-30, 3, 30), borrowWaypoint),
			CHAIN = markerCFrame(markers, "ChainSpawn", 2, CFrame.new(60, 3, 30), borrowWaypoint),
			BEANS = markerCFrame(markers, "BeansSpawn", 2, CFrame.new(-60, 3, -30), borrowWaypoint),
		},
		vendingMachines = vendingMachines,
		nickelSpawns = nickelSpawns,
		trapSpawns = trapSpawns,
		itemSpawns = itemSpawns,
		itemSpawners = itemSpawners,
		sweepRoutes = sweepRoutes,
	}
end

function MapResolver.resolve(ctx)
	-- Players never physically collide with NPCs, so a roaming character
	-- can never wedge a player into a doorway.
	pcall(function()
		PhysicsService:RegisterCollisionGroup("BaldiNpc")
		PhysicsService:RegisterCollisionGroup("BaldiPlayer")
		PhysicsService:RegisterCollisionGroup("BaldiVending")
		PhysicsService:CollisionGroupSetCollidable("BaldiNpc", "BaldiPlayer", false)
		-- NPCs phase through vending machines so the fast straight-line sweepers
		-- (Guidelines / Sai) can't wedge on them; players still bump them normally.
		PhysicsService:CollisionGroupSetCollidable("BaldiNpc", "BaldiVending", false)
	end)

	local root = workspace:FindFirstChild("BaldiMap") or ServerStorage:FindFirstChild("BaldiMap")
	if not root then
		print("[Tmod] No Workspace/BaldiMap found — generating the placeholder school. "
			.. "Build your own map in a folder named BaldiMap to replace it (see STUDIO_SETUP.md).")
		root = PlaceholderMap.generate(ctx.config)
	elseif ctx.config.MAP_LOADS_ON_FIRST_RUN ~= false and root:IsDescendantOf(workspace) then
		-- held out of the world until the first run (ctx.loadMap)
		root.Parent = ServerStorage
	end

	ctx.map = MapResolver.resolveRoot(ctx, root)
	ctx.mapRoot = root
	function ctx.loadMap()
		return MapResolver.loadMap(ctx)
	end
	return ctx.map
end

-- Brings the school into the world (the first run calls this); once in, it
-- stays until the server closes. Yields while the navmesh settles over it.
-- Returns true if it had to load.
function MapResolver.loadMap(ctx)
	local root = ctx.mapRoot
	if not root or root:IsDescendantOf(workspace) then
		return false
	end
	root.Parent = workspace
	task.wait(ctx.config.MAP_LOAD_SETTLE or 1)
	return true
end

return MapResolver
