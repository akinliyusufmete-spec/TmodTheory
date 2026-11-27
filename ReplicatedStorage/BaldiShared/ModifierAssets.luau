--[[
	ModifierAssets (ModuleScript, ReplicatedStorage.BaldiShared.ModifierAssets)

	Finds the hand-made modifier assets by name. Code never builds or tunes an
	asset: it looks one up here, then clones / enables / plays / tweens it.
	Every name looked up is listed in MODIFIER_ASSETS.md.

	A missing asset returns nil and warns ONCE with the full path it expected,
	so only that piece is skipped. Nothing here yields forever.

	  folder(id)                 BaldiAssets.Modifiers.<id> (Folder) or nil
	  find(id, name)             BaldiAssets.Modifiers.<id>.<name> or nil
	  findClass(id, className)   every child of that folder that IsA(className)
	  npcRig(name)               BaldiAssets.Npcs.<name> or nil
	  gui(playerGui, name, wait) PlayerGui.<name>, waiting at most `wait` seconds
	                             (default 5), or nil
	  cloneEffects(id, parent)   clones every PostEffect / Atmosphere / Sky child
	                             of the folder into parent; returns the clones
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierAssets = {}

local warned = {} -- [path] = true

local function warnOnce(path)
	if warned[path] then
		return
	end
	warned[path] = true
	warn("[Tmod] Modifier asset missing: " .. path .. " (see MODIFIER_ASSETS.md) — skipping that piece.")
end

-- same lookup as AssetResolver: ReplicatedStorage.BaldiAssets, else
-- ReplicatedStorage.BaldiShared.BaldiAssets
local function assetsRoot()
	local root = ReplicatedStorage:FindFirstChild("BaldiAssets")
	if root then
		return root
	end
	local shared = ReplicatedStorage:FindFirstChild("BaldiShared")
	return shared and shared:FindFirstChild("BaldiAssets")
end

function ModifierAssets.folder(id)
	local root = assetsRoot()
	local modifiers = root and root:FindFirstChild("Modifiers")
	local folder = modifiers and modifiers:FindFirstChild(id)
	if not folder then
		warnOnce("ReplicatedStorage.BaldiShared.BaldiAssets.Modifiers." .. tostring(id))
	end
	return folder
end

function ModifierAssets.find(id, name)
	local folder = ModifierAssets.folder(id)
	if not folder then
		return nil
	end
	local asset = folder:FindFirstChild(name)
	if not asset then
		warnOnce("ReplicatedStorage.BaldiShared.BaldiAssets.Modifiers." .. tostring(id) .. "." .. tostring(name))
	end
	return asset
end

function ModifierAssets.findClass(id, className)
	local list = {}
	local folder = ModifierAssets.folder(id)
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA(className) then
				table.insert(list, child)
			end
		end
	end
	return list
end

function ModifierAssets.npcRig(name)
	local root = assetsRoot()
	local npcs = root and root:FindFirstChild("Npcs")
	local rig = npcs and npcs:FindFirstChild(name)
	if not rig then
		warnOnce("ReplicatedStorage.BaldiShared.BaldiAssets.Npcs." .. tostring(name))
	end
	return rig
end

function ModifierAssets.gui(playerGui, name, waitSeconds)
	local gui = playerGui:FindFirstChild(name) or playerGui:WaitForChild(name, waitSeconds or 5)
	if not gui then
		warnOnce("StarterGui." .. tostring(name))
	end
	return gui
end

-- PostEffects (ColorCorrection, Bloom, Blur, SunRays, DepthOfField),
-- Atmosphere and Sky: the things a modifier folder can drop into Lighting
local EFFECT_CLASSES = { "PostEffect", "Atmosphere", "Sky" }

function ModifierAssets.cloneEffects(id, parent)
	local clones = {}
	local folder = ModifierAssets.folder(id)
	if not folder then
		return clones
	end
	for _, child in ipairs(folder:GetChildren()) do
		for _, className in ipairs(EFFECT_CLASSES) do
			if child:IsA(className) then
				local copy = child:Clone()
				copy.Name = "Modifier_" .. id .. "_" .. child.Name
				copy.Parent = parent
				table.insert(clones, copy)
				break
			end
		end
	end
	return clones
end

return ModifierAssets
