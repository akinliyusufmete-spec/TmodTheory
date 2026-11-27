--[[
	LoadingScreen (LocalScript, ReplicatedFirst.LoadingScreen)

	The first thing a joining player sees. Replaces Roblox's default loading
	screen with LoadingGui (a child of this script; restyle it freely, keep
	the names), then preloads every asset the game uses before fading out:

	  - every image, texture, mesh, sound and animation referenced by the
	    instances in ReplicatedStorage, StarterGui, StarterPlayer, Workspace
	    (the menu scene), Lighting, SoundService and MaterialService
	  - the ids in the shared configs (CharacterConfig animations and sounds,
	    AssetConfig, GameConfig)
	  - the fonts and images of every screen in your PlayerGui

	Everything is preloaded through the instance that uses it (config ids get
	a stand-in Animation / Sound / Decal), so Roblox fetches each id as the
	right kind of asset. The bar fills as assets finish (loaded or failed: a
	broken id never holds the screen up). A Skip button appears after
	SKIP_AFTER seconds; skipping only hides the screen, the preloading carries
	on underneath. When done it sets the player's "AssetsLoaded" attribute.

	The school map isn't part of this: it loads into the world when the
	first run starts (GameConfig.MAP_LOADS_ON_FIRST_RUN).
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local BATCH = 20 -- assets handed to PreloadAsync at a time
local SKIP_AFTER = 15 -- seconds before the Skip button shows
local FADE = 0.6
local TIP_EVERY = 4

local TIPS = {
	"Don't run in the halls. LP is always watching.",
	"ChatRevive slaps before he dashes. Count the beat.",
	"Frosty's traps stay put until someone steps on one.",
	"A BEARTrapper holds you until you win the minigame.",
	"Silver wants to play. Hit the zone to wriggle free.",
	"A BSODA knocks any character back and stuns them.",
	"Nickels buy items from the vending machines.",
}

-- every property that can hold an asset id, by class
local CONTENT_PROPERTIES = {
	ImageLabel = { "Image" },
	ImageButton = { "Image", "HoverImage", "PressedImage" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	FileMesh = { "MeshId", "TextureId" },
	Sound = { "SoundId" },
	Animation = { "AnimationId" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" },
	MaterialVariant = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
	Shirt = { "ShirtTemplate" },
	Pants = { "PantsTemplate" },
	ShirtGraphic = { "Graphic" },
	VideoFrame = { "Video" },
}

local player = Players.LocalPlayer
local gui = script:WaitForChild("LoadingGui"):Clone()
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local background = gui:WaitForChild("Background")
local barBack = background:WaitForChild("BarBack")
local fill = barBack:WaitForChild("Fill")
local status = background:WaitForChild("Status")
local percent = background:WaitForChild("Percent")
local tip = background:WaitForChild("Tip")
local skipButton = background:WaitForChild("SkipButton")
skipButton.Visible = false
fill.Size = UDim2.fromScale(0, 1)

local finished = false
local hidden = false

-- rotating tips until the screen goes
task.spawn(function()
	local index = math.random(1, #TIPS)
	while not hidden do
		tip.Text = TIPS[index]
		index = index % #TIPS + 1
		task.wait(TIP_EVERY)
	end
end)

local function setProgress(done, total)
	local alpha = total > 0 and math.clamp(done / total, 0, 1) or 1
	TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(alpha, 1) }):Play()
	percent.Text = math.floor(alpha * 100 + 0.5) .. "%"
	status.Text = string.format("Loading assets... %d / %d", done, total)
end

local function hide()
	if hidden then
		return
	end
	hidden = true
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("GuiObject") then
			local goal = { BackgroundTransparency = 1 }
			if object:IsA("TextLabel") or object:IsA("TextButton") then
				goal.TextTransparency = 1
			elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
				goal.ImageTransparency = 1
			end
			TweenService:Create(object, info, goal):Play()
		elseif object:IsA("UIStroke") then
			TweenService:Create(object, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(FADE, function()
		gui:Destroy()
	end)
end

skipButton.Activated:Connect(hide)
task.delay(SKIP_AFTER, function()
	if not finished and not hidden then
		skipButton.Visible = true
	end
end)

-- ===================== gathering =====================
-- Assets are preloaded through the instances that use them, so Roblox knows
-- what each one is: an animation or mesh id handed over as a bare string is
-- fetched as an image and fails ("Asset type does not match").

status.Text = "Waiting for the game..."
if not game:IsLoaded() then
	game.Loaded:Wait()
end
status.Text = "Finding assets..."
task.wait()

local seen = {} -- content id -> true
local holders = {} -- { instance, assets }: each queued once, counted per new id
local total = 0

-- a web asset id, or nil (blank, 0, or a built-in rbxasset:// file that
-- never needs fetching)
local function assetId(value)
	if typeof(value) ~= "string" or value == "" or value == "rbxassetid://0" then
		return nil
	end
	if value:match("^rbxassetid://%d+") or value:match("^https?://") then
		return value
	end
	if value:match("^%d%d%d%d%d%d+$") then
		return "rbxassetid://" .. value
	end
	return nil
end

local function addHolder(object, values)
	local fresh = 0
	for _, value in ipairs(values) do
		local id = assetId(value)
		if id and not seen[id] then
			seen[id] = true
			fresh += 1
		end
	end
	if fresh > 0 then
		total += fresh
		table.insert(holders, { object, fresh })
	end
end

local function scanInstances(root)
	for _, object in ipairs(root:GetDescendants()) do
		local properties = CONTENT_PROPERTIES[object.ClassName]
		if properties then
			local values = {}
			for _, property in ipairs(properties) do
				local ok, value = pcall(function()
					return object[property]
				end)
				if ok then
					table.insert(values, value)
				end
			end
			addHolder(object, values)
		end
	end
end

-- ids written into the configs get a stand-in of the right kind, judged by
-- the table they sit in (Animations -> Animation, Sounds -> Sound, else image)
local MAKE_HOLDER = {
	Animation = function(id)
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		return animation
	end,
	Sound = function(id)
		local sound = Instance.new("Sound")
		sound.SoundId = id
		return sound
	end,
	Image = function(id)
		local decal = Instance.new("Decal")
		decal.Texture = id
		return decal
	end,
}

local function scanTable(value, kind, depth)
	if depth > 6 then
		return
	end
	if typeof(value) == "table" then
		for key, inner in pairs(value) do
			local innerKind = kind
			if typeof(key) == "string" then
				local lower = key:lower()
				if lower:find("anim") then
					innerKind = "Animation"
				elseif lower:find("sound") or lower:find("music") or lower:find("sfx") then
					innerKind = "Sound"
				end
			end
			scanTable(inner, innerKind, depth + 1)
		end
	else
		local id = assetId(value)
		if id and not seen[id] then
			addHolder(MAKE_HOLDER[kind](id), { id })
		end
	end
end

for _, service in ipairs({
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterGui"),
	game:GetService("StarterPlayer"),
	workspace,
	game:GetService("Lighting"),
	game:GetService("SoundService"),
	game:GetService("MaterialService"),
}) do
	pcall(scanInstances, service)
	task.wait()
end

local shared = game:GetService("ReplicatedStorage"):FindFirstChild("BaldiShared")
for _, name in ipairs({ "CharacterConfig", "AssetConfig", "GameConfig" }) do
	local module = shared and shared:FindFirstChild(name)
	if module then
		local ok, config = pcall(require, module)
		if ok then
			scanTable(config, "Image", 0)
		end
	end
end

-- ===================== preloading =====================

local screens = {}
for _, screen in ipairs(player.PlayerGui:GetChildren()) do
	if screen:IsA("ScreenGui") and screen ~= gui then
		table.insert(screens, screen) -- their fonts and images
	end
end
total += #screens

local done = 0
setProgress(0, total)

local function counted()
	done = math.min(done + 1, total)
	setProgress(done, total)
end

local settled = 0 -- assets in the batches that have finished
for start = 1, #holders, BATCH do
	local batch = {}
	for i = start, math.min(start + BATCH - 1, #holders) do
		table.insert(batch, holders[i][1])
		settled += holders[i][2]
	end
	pcall(function()
		ContentProvider:PreloadAsync(batch, counted)
	end)
	-- loaded or failed, everything in this batch is settled now
	done = math.max(done, math.min(settled, total))
	setProgress(done, total)
end

for _, screen in ipairs(screens) do
	pcall(function()
		ContentProvider:PreloadAsync({ screen })
	end)
	settled += 1
	done = math.max(done, math.min(settled, total))
	setProgress(done, total)
end

finished = true
player:SetAttribute("AssetsLoaded", true)
status.Text = "Ready!"
task.wait(0.35)
hide()
