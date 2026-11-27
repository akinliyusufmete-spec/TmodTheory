-- Applies AssetConfig.WORLD_SOUNDS to the map's Sound objects. Each key is
-- matched by the Sound's ORIGINAL id, so it works on any copy of the map.
local AssetConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("AssetConfig"))
local W = AssetConfig.WORLD_SOUNDS or {}

local ORIGINAL = {
	["1807420037"] = "classroomDoorOpen",
	["2119898278"] = "classroomDoorClose",
	["1865627915"] = "swingingDoor",
	["5197628658"] = "blueDoorOpen",
	["5197628488"] = "blueDoorClose",
	["109550779401749"] = "guidelinesAmbience",
}

local function toId(v)
	v = tostring(v)
	return tonumber(v) and ("rbxassetid://" .. v) or v
end

local function apply(inst)
	if not inst:IsA("Sound") then return end
	local key = inst:GetAttribute("WorldSoundKey") or ORIGINAL[inst.SoundId:match("(%d+)$") or ""]
	if not key then return end
	inst:SetAttribute("WorldSoundKey", key)
	local v = W[key]
	if v and v ~= "" then
		local id = toId(v)
		if inst.SoundId ~= id then inst.SoundId = id end
	end
end

for _, root in ipairs({ workspace, game:GetService("ReplicatedStorage"), game:GetService("ServerStorage") }) do
	for _, d in ipairs(root:GetDescendants()) do apply(d) end
	root.DescendantAdded:Connect(apply)
end
