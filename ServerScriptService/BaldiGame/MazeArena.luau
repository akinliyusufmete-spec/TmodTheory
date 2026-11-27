--[[
	MazeArena (ModuleScript, ServerScriptService.BaldiGame.MazeArena)

	The Multiplied mode arena: a large maze-like schoolhouse, generated once
	per server (recursive-backtracker maze with extra openings so it loops),
	kept in ServerStorage and parented into Workspace only while a
	Multiplied round runs — so its notebook spawn points never leak into
	Classic rounds.

	Prefer your own build? Make a Workspace/BaldiMapMultiplied folder with
	the same layout rules as BaldiMap (Geometry/ExitDoor, Markers,
	Waypoints, NotebookSpawns, ...) and it is used instead of the
	generated maze.

	ctx.maze API:
	  get()            -> the resolved map table (builds on first call)
	  setActive(bool)  -> parent the arena into / out of Workspace
]]

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local MapResolver = require(script.Parent.MapResolver)

local MazeArena = {}

local ORIGIN = Vector3.new(0, 0, 1500) -- far from any hand-built map

local function basePart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

local function invisibleNode(name, position, parent)
	local node = basePart({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	node.Parent = parent
	return node
end

function MazeArena.init(ctx)
	local self = {}
	local built = nil -- { root, map }
	local classicMap = ctx.map
	local rng = Random.new()

	-- ---------- generation ----------

	local function buildMaze()
		local mazeCfg = (ctx.config.MODES.MULTIPLIED and ctx.config.MODES.MULTIPLIED.MAZE) or {}
		local n = mazeCfg.CELLS or 13
		local cellSize = mazeCfg.CELL_SIZE or 14
		local wallHeight = mazeCfg.WALL_HEIGHT or 12
		local extraOpenings = mazeCfg.EXTRA_OPENINGS or 0.12
		local span = n * cellSize

		local root = Instance.new("Folder")
		root.Name = "BaldiMazeArena"

		local geometry = Instance.new("Folder")
		geometry.Name = "Geometry"
		geometry.Parent = root
		local waypoints = Instance.new("Folder")
		waypoints.Name = "Waypoints"
		waypoints.Parent = root
		local spawnNodes = Instance.new("Folder")
		spawnNodes.Name = "NotebookSpawns"
		spawnNodes.Parent = root
		local notebooks = Instance.new("Folder")
		notebooks.Name = "Notebooks"
		notebooks.Parent = root
		local pickups = Instance.new("Folder")
		pickups.Name = "Pickups"
		pickups.Parent = root
		local projectiles = Instance.new("Folder")
		projectiles.Name = "Projectiles"
		projectiles.Parent = root

		local function cellCenter(x, z)
			return ORIGIN + Vector3.new(
				(x - 0.5) * cellSize - span / 2,
				0,
				(z - 0.5) * cellSize - span / 2
			)
		end

		-- carve the maze: recursive backtracker over an n x n grid
		local wallEast = {} -- wallEast[x][z]: wall between (x,z) and (x+1,z)
		local wallSouth = {} -- wallSouth[x][z]: wall between (x,z) and (x,z+1)
		local visited = {}
		for x = 1, n do
			wallEast[x], wallSouth[x], visited[x] = {}, {}, {}
			for z = 1, n do
				wallEast[x][z] = true
				wallSouth[x][z] = true
				visited[x][z] = false
			end
		end

		local stack = { { 1, 1 } }
		visited[1][1] = true
		while #stack > 0 do
			local top = stack[#stack]
			local x, z = top[1], top[2]
			local options = {}
			if x > 1 and not visited[x - 1][z] then table.insert(options, { x - 1, z, "W" }) end
			if x < n and not visited[x + 1][z] then table.insert(options, { x + 1, z, "E" }) end
			if z > 1 and not visited[x][z - 1] then table.insert(options, { x, z - 1, "N" }) end
			if z < n and not visited[x][z + 1] then table.insert(options, { x, z + 1, "S" }) end
			if #options == 0 then
				table.remove(stack)
			else
				local pick = options[rng:NextInteger(1, #options)]
				local nx, nz, dir = pick[1], pick[2], pick[3]
				if dir == "E" then
					wallEast[x][z] = false
				elseif dir == "W" then
					wallEast[nx][nz] = false
				elseif dir == "S" then
					wallSouth[x][z] = false
				elseif dir == "N" then
					wallSouth[nx][nz] = false
				end
				visited[nx][nz] = true
				table.insert(stack, { nx, nz })
			end
		end

		-- knock out extra walls so the maze loops (multiple escape routes)
		for x = 1, n do
			for z = 1, n do
				if x < n and wallEast[x][z] and rng:NextNumber() < extraOpenings then
					wallEast[x][z] = false
				end
				if z < n and wallSouth[x][z] and rng:NextNumber() < extraOpenings then
					wallSouth[x][z] = false
				end
			end
		end

		-- ---------- build the parts ----------

		local floorColor = Color3.fromRGB(155, 145, 125)
		local wallColor = Color3.fromRGB(95, 120, 90)

		basePart({
			Name = "MazeFloor",
			Size = Vector3.new(span + 4, 2, span + 4),
			CFrame = CFrame.new(ORIGIN + Vector3.new(0, -1, 0)),
			Color = floorColor,
			Material = Enum.Material.Slate,
		}).Parent = geometry

		local function wallPart(centerPosition, sizeX, sizeZ)
			basePart({
				Name = "MazeWall",
				Size = Vector3.new(sizeX, wallHeight, sizeZ),
				CFrame = CFrame.new(centerPosition + Vector3.new(0, wallHeight / 2, 0)),
				Color = wallColor,
				Material = Enum.Material.Brick,
			}).Parent = geometry
		end

		-- perimeter
		local half = span / 2
		wallPart(ORIGIN + Vector3.new(0, 0, -half - 1), span + 4, 2)
		wallPart(ORIGIN + Vector3.new(0, 0, half + 1), span + 4, 2)
		wallPart(ORIGIN + Vector3.new(-half - 1, 0, 0), 2, span + 4)
		wallPart(ORIGIN + Vector3.new(half + 1, 0, 0), 2, span + 4)

		-- internal walls (skip a couple of studs so doorway gaps stay walkable)
		for x = 1, n do
			for z = 1, n do
				if x < n and wallEast[x][z] then
					local center = cellCenter(x, z) + Vector3.new(cellSize / 2, 0, 0)
					wallPart(center, 2, cellSize + 2)
				end
				if z < n and wallSouth[x][z] then
					local center = cellCenter(x, z) + Vector3.new(0, 0, cellSize / 2)
					wallPart(center, cellSize + 2, 2)
				end
			end
		end

		-- the exit: a door part flush against the far corner's outer wall
		local exitCell = cellCenter(n, n)
		local exitDoor = basePart({
			Name = "ExitDoor",
			Size = Vector3.new(8, 10, 1),
			CFrame = CFrame.new(exitCell + Vector3.new(0, 5, cellSize / 2 - 0.6)),
			Color = Color3.fromRGB(140, 30, 30),
			Material = Enum.Material.SmoothPlastic,
		})
		exitDoor.Parent = geometry

		-- ---------- gameplay nodes ----------

		-- waypoints at every cell center; lights every third cell
		for x = 1, n do
			for z = 1, n do
				local center = cellCenter(x, z)
				invisibleNode(x .. "_" .. z, center + Vector3.new(0, 1, 0), waypoints)
				if x % 3 == 2 and z % 3 == 2 then
					local lamp = invisibleNode("MazeLamp", center + Vector3.new(0, wallHeight - 2, 0), geometry)
					local glow = Instance.new("PointLight")
					glow.Range = cellSize * 1.8
					glow.Brightness = 0.8
					glow.Color = Color3.fromRGB(255, 240, 200)
					glow.Parent = lamp
				end
			end
		end

		-- shuffle all cells (minus the player spawn and exit corners), then
		-- deal them out: notebooks, nickels, items, spawner pads
		local cells = {}
		for x = 1, n do
			for z = 1, n do
				if not (x == 1 and z == 1) and not (x == n and z == n) then
					table.insert(cells, { x, z })
				end
			end
		end
		for i = #cells, 2, -1 do
			local j = rng:NextInteger(1, i)
			cells[i], cells[j] = cells[j], cells[i]
		end

		local dealIndex = 0
		local function deal()
			dealIndex = dealIndex + 1
			local cell = cells[dealIndex] or cells[#cells]
			return cellCenter(cell[1], cell[2])
		end

		for _ = 1, math.min(45, #cells - 25) do
			local node = invisibleNode("MazeNotebookSpawn", deal() + Vector3.new(0, 1, 0), spawnNodes)
			CollectionService:AddTag(node, "NotebookSpawn")
		end

		local nickelSpawns = {}
		for _ = 1, 14 do
			table.insert(nickelSpawns, deal() + Vector3.new(0, 1, 0))
		end

		local itemSpawns = {}
		for _, itemId in ipairs({ "BSODA", "ZESTY", "SCISSORS", "ALARM" }) do
			if ctx.config.ITEMS[itemId] then
				itemSpawns[itemId] = deal() + Vector3.new(0, 1, 0)
			end
		end

		local itemSpawners = {}
		for _ = 1, 3 do
			table.insert(itemSpawners, deal() + Vector3.new(0, 1, 0))
		end

		-- character posts: corners and mid-points, away from the player spawn
		local mid = math.ceil(n / 2)
		local npcSpawns = {
			CHATREVIVE = CFrame.new(cellCenter(n, 1) + Vector3.new(0, 3, 0)),
			LP = CFrame.new(cellCenter(1, n) + Vector3.new(0, 3, 0)),
			FROSTY = CFrame.new(cellCenter(mid, mid) + Vector3.new(0, 3, 0)),
			SILVER = CFrame.new(cellCenter(mid, n) + Vector3.new(0, 3, 0)),
			GUY = CFrame.new(cellCenter(n, mid) + Vector3.new(0, 3, 0)),
			SPORTAGE = CFrame.new(cellCenter(n, 1) + Vector3.new(0, 3, 0)),
		}

		local spawnCenter = cellCenter(1, 1)
		local map = {
			root = root,
			geometry = geometry,
			waypointsFolder = waypoints,
			spawnNodesFolder = spawnNodes,
			notebooksFolder = notebooks,
			pickupsFolder = pickups,
			npcFolder = classicMap.npcFolder, -- the characters themselves don't move folders
			projectilesFolder = projectiles,
			exitDoor = exitDoor,
			lobbySpawn = classicMap.lobbySpawn, -- losers/winners return to the real lobby
			roundSpawnCFrame = CFrame.lookAt(spawnCenter + Vector3.new(0, 3.5, 0), ORIGIN + Vector3.new(0, 3.5, 0)),
			detentionCFrame = CFrame.new(cellCenter(2, n) + Vector3.new(0, 3.5, 0)),
			npcSpawns = npcSpawns,
			vendingMachines = {},
			nickelSpawns = nickelSpawns,
			itemSpawns = itemSpawns,
			itemSpawners = itemSpawners,
			sweepRoutes = {},
		}
		return root, map
	end

	-- ---------- public API ----------

	function self.get()
		if built then
			return built.map
		end
		-- your own arena takes priority over the generated maze
		local custom = workspace:FindFirstChild("BaldiMapMultiplied")
			or ServerStorage:FindFirstChild("BaldiMapMultiplied")
		if custom then
			local map = MapResolver.resolveRoot(ctx, custom)
			map.npcFolder = classicMap.npcFolder
			map.lobbySpawn = map.lobbySpawn or classicMap.lobbySpawn
			built = { root = custom, map = map }
		else
			local root, map = buildMaze()
			built = { root = root, map = map }
			print("[Tmod] Generated the Multiplied maze arena ("
				.. "build a Workspace/rah folder to replace it).")
		end
		built.root.Parent = ServerStorage -- inert until a Multiplied round
		return built.map
	end

	function self.setActive(active)
		if not built then
			return
		end
		built.root.Parent = active and workspace or ServerStorage
	end

	ctx.maze = self
	return self
end

return MazeArena
