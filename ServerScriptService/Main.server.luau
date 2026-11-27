--[[
	Main (Script, ServerScriptService.Main)

	Server bootstrap — SHARED by the solo place AND the dedicated Multiplayer
	match place (both Rojo projects map this same file). It lives OUTSIDE the
	BaldiGame module folder on purpose: that folder is now pure ModuleScripts, so
	each place's project can share the whole engine by $path-ing BaldiGame while
	supplying its OWN auto-running bootstrap. (If the bootstrap lived inside
	BaldiGame, every place that shared the folder would also run it.)

	Builds the shared context table and initializes every system in dependency
	order:
	  config/assets -> remotes -> map -> NPCs -> economy/detention/
	  notebooks/exit -> GameManager (last) -> MatchServer -> HubTravel

	Same build, two behaviors at runtime: on a normal/public server it runs the
	solo game; on a reserved server (the match place, launched by the Hub)
	MatchServer detects it and runs the synchronized multiplayer match.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local GameConfig = require(shared:WaitForChild("GameConfig"))
local AssetConfig = require(shared:WaitForChild("AssetConfig"))

-- the shared engine: a sibling folder of this bootstrap (was script.Parent when
-- this Script lived inside BaldiGame; now resolve it by name)
local engine = script.Parent:WaitForChild("BaldiGame")

local RemoteSetup = require(engine.RemoteSetup)
local VoicelineService = require(engine.VoicelineService)
local MapResolver = require(engine.MapResolver)
local MazeArena = require(engine.MazeArena)
local MatchMap = require(engine.MatchMap)
local PlayerProfiles = require(engine.PlayerProfiles)
local DoorService = require(engine.DoorService)
local ChatReviveAI = require(engine.ChatReviveAI)
local LpAI = require(engine.LpAI)
local FrostyAI = require(engine.FrostyAI)
local SilverAI = require(engine.SilverAI)
local SweeperAI = require(engine.SweeperAI)
local SportageAI = require(engine.SportageAI)
local GuyAI = require(engine.GuyAI)
local ChainAI = require(engine.ChainAI)
local BeansAI = require(engine.BeansAI)
local DetentionSystem = require(engine.DetentionSystem)
local ItemEconomy = require(engine.ItemEconomy)
local NotebookSpawner = require(engine.NotebookSpawner)
local ExitDoorManager = require(engine.ExitDoorManager)
local GameManager = require(engine.GameManager)
local MatchServer = require(engine.MatchServer)
local HubTravel = require(engine.HubTravel)
local Badges = require(engine.Badges)

local ctx = {
	config = GameConfig,
	assets = AssetConfig, -- your image/sound ids (NPC sounds read these)
	remotes = nil, -- RemoteSetup
	map = nil, -- MapResolver (your BaldiMap, or the placeholder school)
	npcs = {}, -- ChatReviveAI / LpAI / FrostyAI register themselves
	manager = nil, -- GameManager
	economy = nil, -- ItemEconomy
	detention = nil, -- DetentionSystem
	notebookSpawner = nil, -- NotebookSpawner
	exitDoor = nil, -- ExitDoorManager
	voicelines = nil, -- VoicelineService (NPC lines from CharacterConfig)
}

RemoteSetup.init(ctx)
VoicelineService.init(ctx) -- before the NPCs, which talk through it
MapResolver.resolve(ctx)
DoorService.init(ctx) -- syncs tagged doors' CanQuery to their "Open" attribute (sight blocking)
MazeArena.init(ctx) -- the Multiplied arena (built lazily on first use)
MatchMap.init(ctx) -- the big multiplayer map (parked in ServerStorage until a match)
PlayerProfiles.init(ctx) -- persistence: wins, unlocks, times, binds

-- Give the navmesh a moment to bake over freshly generated geometry
-- before the first paths are computed (paths fail gracefully anyway).
task.wait(1)

DetentionSystem.init(ctx) -- before LpAI/SilverAI, which read ctx.detention

ChatReviveAI.init(ctx)
LpAI.init(ctx)
FrostyAI.init(ctx)
SilverAI.init(ctx)
SweeperAI.init(ctx) -- Guidelines + Sai
SportageAI.init(ctx) -- the Impersonator hunter (parked in other modes)
GuyAI.init(ctx) -- the mimic
ChainAI.init(ctx) -- the shackler (Multiplayer/MATCH only; parked elsewhere)
BeansAI.init(ctx) -- the gum-spitter (Multiplayer/MATCH only; parked elsewhere)

ItemEconomy.init(ctx)
NotebookSpawner.init(ctx)
ExitDoorManager.init(ctx)
GameManager.init(ctx)
MatchServer.init(ctx) -- after GameManager: seats a Hub-launched party (synced start)
HubTravel.init(ctx) -- the menu's MULTIPLAYER button: teleport solo players to the Hub
Badges.init(ctx) -- awards the badges (GameConfig.BADGES); last, it reads profiles + the round


