--[[
	MatchMap (ModuleScript, ServerScriptService.BaldiGame.MatchMap)

	Loads the hand-built big map for multiplayer MATCH rounds. You build a folder
	named GameConfig.MATCH.MAP_NAME ("BaldiMapMatch") using the same contract as
	BaldiMap (Geometry/ExitDoor, Markers, Waypoints, NotebookSpawns, SweepRoutes,
	NickelSpawns, ItemSpawns).

	To keep normal single-player servers clean, the match map is PARKED in
	ServerStorage on every server at startup (even if you built it in Workspace),
	and swapped into Workspace only while a match runs — exactly like MazeArena.
	So its markers/waypoints/notebook spawns never overlap the Classic map.

	ctx.match API (mirrors ctx.maze):
	  get()            -> the resolved map table (resolves on first call), or nil
	                      if the map folder is missing
	  setActive(bool)  -> parent the map into / out of Workspace
]]

local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local MapResolver = require(script.Parent.MapResolver)

local MatchMap = {}

function MatchMap.init(ctx)
	local self = {}
	local classicMap = ctx.map
	local mapName = (ctx.config.MATCH and ctx.config.MATCH.MAP_NAME) or "BaldiMapMatch"
	local built = nil -- { root, map }

	-- park any Workspace copy into ServerStorage right away, so a normal server
	-- never has the big map (and its tagged notebook spawns) live in Workspace
	local source = workspace:FindFirstChild(mapName)
	if source then
		source.Parent = ServerStorage
	end

	function self.get()
		-- Studio test: run the match on the NORMAL map (return nil so GameManager
		-- falls back to the classic map). The big map stays parked in ServerStorage.
		if RunService:IsStudio() and ctx.config.MATCH and ctx.config.MATCH.STUDIO_TEST then
			return nil
		end
		if built then
			return built.map
		end
		local root = ServerStorage:FindFirstChild(mapName) or workspace:FindFirstChild(mapName)
		if not root then
			warn(string.format(
				"[BaldiGame] No %s folder found in ServerStorage or Workspace — the match has no map. "
					.. "Build it (BaldiMap contract) and name it %s.", mapName, mapName))
			return nil
		end
		root.Parent = ServerStorage -- ensure parked until activated
		local map = MapResolver.resolveRoot(ctx, root)
		map.npcFolder = classicMap.npcFolder -- characters never change folders
		map.lobbySpawn = map.lobbySpawn or classicMap.lobbySpawn

		-- Safety net: a hand-built map that isn't fully anchored would FREE-FALL
		-- the instant setActive() swaps it from ServerStorage into Workspace
		-- (parked parts don't simulate, so it looks fine at rest, then the floors
		-- and walls drop away the moment a match starts — the "I don't see the
		-- map / fall through the world" bug). Force-anchor any stray STATIC part
		-- so the map can never scatter. The runtime folders (Npcs/Notebooks/
		-- Pickups/Projectiles) hold dynamic objects and are left alone (they're
		-- empty at resolve time anyway).
		local runtimeFolders = { map.npcFolder, map.notebooksFolder, map.pickupsFolder, map.projectilesFolder }
		local function inRuntimeFolder(inst)
			for _, folder in ipairs(runtimeFolders) do
				if folder and inst:IsDescendantOf(folder) then
					return true
				end
			end
			return false
		end
		local floated = 0
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("BasePart") and not descendant.Anchored and not inRuntimeFolder(descendant) then
				descendant.Anchored = true
				floated += 1
			end
		end
		if floated > 0 then
			warn(string.format(
				"[BaldiGame] %s had %d un-anchored part(s) — anchored them so the map can't fall "
					.. "through the world. Anchor your geometry in Studio to be safe.", mapName, floated))
		end

		built = { root = root, map = map }
		return built.map
	end

	function self.setActive(active)
		if not built then
			return
		end
		built.root.Parent = active and workspace or ServerStorage
	end

	ctx.match = self
	return self
end

return MatchMap
