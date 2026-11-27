--[[
	CramSchool (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.CramSchool)

	Client half of the Cram School modifier ("The school is dark."):
	  - Lighting properties: each name in ModifierConfig.CRAM_LIGHTING_ATTRIBUTES
	    that BaldiAssets.Modifiers.CramSchool has as an ATTRIBUTE is applied to
	    Lighting (names the folder doesn't set are left alone). The original
	    values are saved first and written back on stop.
	  - The place's own Atmosphere is taken out of Lighting while active.
	    Atmosphere has no Enabled property, and two Atmospheres in Lighting
	    don't blend (Roblox just uses one), so the only reliable "off" is to
	    unparent it. This is a client-side reparent: it only affects this
	    player's view, the server copy is untouched, and stop puts each one
	    back under the exact parent it came from. The same is done for the
	    place's own Sky, but only when the folder brings a Sky of its own
	    (otherwise the place keeps its sky).
	  - Every Atmosphere / Sky / PostEffect in the folder is cloned into
	    Lighting (ModifierAssets.cloneEffects) and destroyed on stop.

	Clones other modifiers dropped into Lighting (named "Modifier_...") are
	never hidden.
]]

local Lighting = game:GetService("Lighting")

local CramSchool = {}

local savedLighting = {} -- [property] = original value
local hidden = {} -- { instance, parent } for the place's own Atmosphere / Sky
local clones = {}

local function isModifierClone(instance)
	return string.sub(instance.Name, 1, 9) == "Modifier_"
end

local function hideOwn(className)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA(className) and not isModifierClone(child) then
			table.insert(hidden, { instance = child, parent = child.Parent })
			child.Parent = nil
		end
	end
end

function CramSchool.stop(_env)
	for _, clone in ipairs(clones) do
		clone:Destroy()
	end
	clones = {}

	-- put the place's own Atmosphere / Sky back where they were (unless the
	-- server destroyed or moved them meanwhile)
	for _, entry in ipairs(hidden) do
		local instance = entry.instance
		pcall(function()
			if instance.Parent == nil and entry.parent and entry.parent.Parent ~= nil then
				instance.Parent = entry.parent
			end
		end)
	end
	hidden = {}

	for property, value in pairs(savedLighting) do
		pcall(function()
			Lighting[property] = value
		end)
	end
	savedLighting = {}
end

function CramSchool.start(env)
	CramSchool.stop(env) -- never stack on a previous start

	local folder = env.assets.folder("CramSchool")

	if folder then
		for _, property in ipairs(env.config.CRAM_LIGHTING_ATTRIBUTES) do
			local value = folder:GetAttribute(property)
			if value ~= nil then
				local ok, original = pcall(function()
					return Lighting[property]
				end)
				if ok then
					local applied = pcall(function()
						Lighting[property] = value
					end)
					if applied then
						savedLighting[property] = original
					else
						warn("[Tmod] CramSchool attribute " .. property .. " has the wrong type for Lighting." .. property)
					end
				end
			end
		end
	end

	-- the place's own Atmosphere always goes; its Sky only if we bring one
	hideOwn("Atmosphere")
	local bringsSky = folder ~= nil and folder:FindFirstChildWhichIsA("Sky") ~= nil
	if bringsSky then
		hideOwn("Sky")
	end

	clones = env.assets.cloneEffects("CramSchool", Lighting)
end

return CramSchool
