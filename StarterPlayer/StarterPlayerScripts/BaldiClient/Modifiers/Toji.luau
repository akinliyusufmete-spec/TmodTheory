--[[
	Toji (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.Toji)

	Client half of the "TOJI-KUN" modifier: the glass look. The server
	decides who shatters (BaldiGame/Modifiers/Toji) and sets the attribute
	Glass = true on that NPC's model for def.GLASS_SECONDS; this module only
	makes it look like glass while the attribute is set. Speed is
	server-side (ModSpeedMult, applied by StaminaController).

	Where NPC models are: every character the server spawns (NpcFactory) is a
	Model parented to the map's runtime folder "Npcs"
	(workspace.BaldiMap.Npcs; other modes reuse that same folder). They are
	not tagged, so like NpcAnimatorClient this treats any Model whose parent
	is named "Npcs" anywhere in workspace as an NPC, and watches
	workspace.DescendantAdded for ones that appear later (EVIL Theory twins,
	the turtle, respawns).

	Glass look, per BasePart (skipping HumanoidRootPart and fully invisible
	parts): Material = Glass, Color = def.GLASS_COLOR, Transparency =
	max(its own, def.GLASS_TRANSPARENCY). Decals / Textures fade to at least
	the same transparency, and SurfaceAppearances (which would hide the
	material and colour on MeshParts) are unparented locally for the moment.
	Every original value is saved and put back when Glass clears, when the
	model leaves, and on stop. A property is only written back if it still
	holds the value we set, so a change the server made meanwhile wins.
]]

local Toji = {}

local DEFAULT_COLOR = Color3.fromRGB(170, 220, 255)
local DEFAULT_TRANSPARENCY = 0.4

local active = false
local env = nil
local watched = {} -- [model] = { connections }
local glassed = {} -- [model] = { saved entries }
local addedConnection = nil

local function near(a, b)
	return math.abs(a - b) < 0.001
end

-- BasePart.Color is stored as 8-bit RGB, so what we read back can differ
-- from the Color3 we wrote by up to half a step per channel
local function nearColor(a, b)
	local step = 1 / 255
	return math.abs(a.R - b.R) <= step and math.abs(a.G - b.G) <= step and math.abs(a.B - b.B) <= step
end

local function applyGlass(model)
	if glassed[model] then
		return
	end
	local def = env and env.def or {}
	local color = def.GLASS_COLOR or DEFAULT_COLOR
	local transparency = def.GLASS_TRANSPARENCY or DEFAULT_TRANSPARENCY
	local saved = {}

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Name ~= "HumanoidRootPart" and item.Transparency < 1 then
				local target = math.max(item.Transparency, transparency)
				table.insert(saved, {
					kind = "part",
					instance = item,
					material = item.Material,
					color = item.Color,
					transparency = item.Transparency,
					setTransparency = target,
				})
				item.Material = Enum.Material.Glass
				item.Color = color
				item.Transparency = target
			end
		elseif item:IsA("Decal") then -- Textures are Decals too
			if item.Transparency < 1 then
				local target = math.max(item.Transparency, transparency)
				table.insert(saved, {
					kind = "decal",
					instance = item,
					transparency = item.Transparency,
					setTransparency = target,
				})
				item.Transparency = target
			end
		elseif item:IsA("SurfaceAppearance") then
			table.insert(saved, { kind = "surface", instance = item, parent = item.Parent })
		end
	end
	-- unparent SurfaceAppearances after the scan (not while iterating)
	for _, entry in ipairs(saved) do
		if entry.kind == "surface" then
			pcall(function()
				entry.instance.Parent = nil
			end)
		end
	end

	glassed[model] = { entries = saved, color = color }
end

local function restoreGlass(model)
	local record = glassed[model]
	if not record then
		return
	end
	glassed[model] = nil
	for _, entry in ipairs(record.entries) do
		local item = entry.instance
		pcall(function()
			if entry.kind == "part" then
				if item.Material == Enum.Material.Glass then
					item.Material = entry.material
				end
				if nearColor(item.Color, record.color) then
					item.Color = entry.color
				end
				if near(item.Transparency, entry.setTransparency) then
					item.Transparency = entry.transparency
				end
			elseif entry.kind == "decal" then
				if near(item.Transparency, entry.setTransparency) then
					item.Transparency = entry.transparency
				end
			elseif entry.kind == "surface" then
				-- back under its part, if that part still exists
				if item.Parent == nil and entry.parent and entry.parent:IsDescendantOf(workspace) then
					item.Parent = entry.parent
				end
			end
		end)
	end
end

local function refresh(model)
	if active and model:GetAttribute("Glass") == true and model:IsDescendantOf(workspace) then
		applyGlass(model)
	else
		restoreGlass(model)
	end
end

local function unwatch(model)
	local connections = watched[model]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		watched[model] = nil
	end
	restoreGlass(model)
end

local function isNpc(instance)
	local parent = instance.Parent
	return instance:IsA("Model") and parent ~= nil and parent.Name == "Npcs"
end

local function watch(model)
	if watched[model] or not isNpc(model) then
		return
	end
	watched[model] = {
		model:GetAttributeChangedSignal("Glass"):Connect(function()
			refresh(model)
		end),
		model.AncestryChanged:Connect(function()
			if not isNpc(model) or not model:IsDescendantOf(workspace) then
				unwatch(model)
			end
		end),
	}
	refresh(model)
end

function Toji.stop(_env)
	active = false
	if addedConnection then
		addedConnection:Disconnect()
		addedConnection = nil
	end
	local models = {}
	for model in pairs(watched) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		unwatch(model)
	end
	-- anything left glassed without a watcher (shouldn't happen)
	for model in pairs(glassed) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		restoreGlass(model)
	end
	watched = {}
	glassed = {}
end

function Toji.start(startEnv)
	Toji.stop(startEnv)
	env = startEnv
	active = true
	for _, instance in ipairs(workspace:GetDescendants()) do
		if isNpc(instance) then
			watch(instance)
		end
	end
	addedConnection = workspace.DescendantAdded:Connect(function(instance)
		if isNpc(instance) then
			watch(instance)
		end
	end)
end

return Toji
