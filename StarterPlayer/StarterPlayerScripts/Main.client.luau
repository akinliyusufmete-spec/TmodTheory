--[[
	Main (LocalScript, StarterPlayerScripts.Main) — the SOLO client bootstrap.

	Lives OUTSIDE the BaldiClient controller folder so each place's Rojo project
	can share every controller ModuleScript while supplying its own auto-running
	client. The dedicated Multiplayer place uses match-src/.../MatchMain.client
	instead of this one (loading screen, no main menu).

	Waits for the shared config + remotes, then initializes every controller in
	dependency order: sound/input first, HUD next, then everything that draws on
	it, and the menu last since it orchestrates all of them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Guard: never let a duplicate/stale client bootstrap double-init the
-- controllers — that would create TWO of every minigame + menu (stateful ones
-- desync: "2 bars", "no progress", a second escape screen behind the first).
local _pg = Players.LocalPlayer:WaitForChild("PlayerGui")
if _pg:FindFirstChild("BaldiClientLoaded") then
	return
end
do
	local marker = Instance.new("BoolValue")
	marker.Name = "BaldiClientLoaded"
	marker.Parent = _pg
end

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local config = require(shared:WaitForChild("GameConfig"))
local assets = require(shared:WaitForChild("AssetConfig"))

local remotesFolder = ReplicatedStorage:WaitForChild(config.REMOTES_FOLDER)
local remotes = {}
for _, name in ipairs(config.REMOTE_NAMES) do
	remotes[name] = remotesFolder:WaitForChild(name)
end

local ctx = {
	player = Players.LocalPlayer,
	config = config,
	assets = assets, -- your image/sound ids from AssetConfig
	remotes = remotes,
	controllers = {},
}

-- the shared controllers: a sibling folder of this bootstrap
local BaldiClient = script.Parent:WaitForChild("BaldiClient")

-- UiFx first: every controller below drives a StarterGui screen through it
local INIT_ORDER = {
	"UiFx",
	"SoundController",
	"InputHandler",
	"DeviceUi", -- sizes every screen for this device (+ gamepad menus); before anything animates
	"NpcAnimatorClient",
	"CosmeticState",
	"NotebookSkinner",
	"HudController",
	"StaminaController",
	"ItemUseClient",
	"VendingMachineUI",
	"DetentionOverlay",
	"FrostyVignette",
	"SilverMinigame",
	"ChainMinigame",
	"BeansGumClient",
	"NotebookMinigame",
	"SequenceMinigame",
	"MathMinigame",
	"MemoryMinigame",
	"ChaseTension",
	"GuyRevealFlash",
	"VoicelineController", -- NPC subtitles (HyperText); after NpcAnimatorClient for line emotes
	"KeystrokesController",
	"MenuController",
}

for _, moduleName in ipairs(INIT_ORDER) do
	local module = require(BaldiClient:WaitForChild(moduleName))
	ctx.controllers[moduleName] = module.init(ctx)
end

print("[Tmod] Client ready.")
