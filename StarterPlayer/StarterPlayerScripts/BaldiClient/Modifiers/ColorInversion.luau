--[[
	ColorInversion (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.ColorInversion)

	Client half of the Color Inversion modifier: every PostEffect you put in
	BaldiAssets.Modifiers.ColorInversion (see MODIFIER_ASSETS.md) is cloned
	into Lighting while the modifier is active, and the clones are destroyed
	when it clears. The originals are never touched, so the look is tuned in
	Studio only.
]]

local Lighting = game:GetService("Lighting")

local ColorInversion = {}

local clones = {}

function ColorInversion.stop(_env)
	for _, clone in ipairs(clones) do
		clone:Destroy()
	end
	clones = {}
end

function ColorInversion.start(env)
	ColorInversion.stop(env) -- never leave a second set behind
	clones = env.assets.cloneEffects("ColorInversion", Lighting)
end

return ColorInversion
