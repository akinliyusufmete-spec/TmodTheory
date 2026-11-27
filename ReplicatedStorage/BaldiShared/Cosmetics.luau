--[[
	Cosmetics (ModuleScript, ReplicatedStorage.BaldiShared.Cosmetics)

	Shared lookup helpers over GameConfig.COSMETICS so the server (validation,
	persistence, BSODA spray tint) and the client (shop UI, HUD tint) agree on
	exactly what every cosmetic is, what it costs, and what color it paints.

	Cosmetics are purely visual and per-player. A cosmetic "targets" one thing
	to reskin — an ITEMS id ("BSODA"/"ZESTY"/"SCISSORS"/"ALARM") or "NICKEL".
	Each target has exactly one `default = true` cosmetic: free, owned by
	everyone, and equipped until the player buys and equips something else.
]]

local GameConfig = require(script.Parent.GameConfig)

local Cosmetics = {}

-- id -> cosmetic def, built once
local byId = {}
-- target -> default cosmetic def
local defaultsByTarget = {}
for _, cosmetic in ipairs(GameConfig.COSMETICS) do
	byId[cosmetic.id] = cosmetic
	if cosmetic.default then
		defaultsByTarget[cosmetic.target] = cosmetic
	end
end

function Cosmetics.all()
	return GameConfig.COSMETICS
end

function Cosmetics.byId(id)
	return id and byId[id] or nil
end

function Cosmetics.defaultFor(target)
	return defaultsByTarget[target]
end

-- Every cosmetic is owned if it's free (default/price 0) OR explicitly in the
-- owned set. Centralizing this keeps "do I own it" identical on both sides.
function Cosmetics.isOwned(cosmetic, ownedSet)
	if not cosmetic then
		return false
	end
	if cosmetic.default or (cosmetic.price or 0) <= 0 then
		return true
	end
	return ownedSet ~= nil and ownedSet[cosmetic.id] == true
end

-- The cosmetic the player has equipped for a target (falling back to the
-- default), given their equipped map { [target] = id }.
function Cosmetics.equippedFor(target, equippedMap, ownedSet)
	local id = equippedMap and equippedMap[target]
	local cosmetic = id and byId[id]
	-- only honor an equipped id the player actually owns and that still targets
	-- this thing; otherwise fall back to the default look
	if cosmetic and cosmetic.target == target and Cosmetics.isOwned(cosmetic, ownedSet) then
		return cosmetic
	end
	return defaultsByTarget[target]
end

-- Convenience: the Color3 a target should render with for this player.
function Cosmetics.colorFor(target, equippedMap, ownedSet)
	local cosmetic = Cosmetics.equippedFor(target, equippedMap, ownedSet)
	if cosmetic and cosmetic.color then
		return Color3.fromRGB(cosmetic.color[1], cosmetic.color[2], cosmetic.color[3])
	end
	return nil
end

-- The skin image asset id a target should render with (nil/"" treated as none).
function Cosmetics.imageFor(target, equippedMap, ownedSet)
	local cosmetic = Cosmetics.equippedFor(target, equippedMap, ownedSet)
	if cosmetic and type(cosmetic.image) == "string" and cosmetic.image ~= "" then
		return cosmetic.image
	end
	return nil
end

-- A Color3 from a cosmetic def's raw {r,g,b}, or nil. Handy for card previews.
function Cosmetics.colorOf(cosmetic)
	if cosmetic and cosmetic.color then
		return Color3.fromRGB(cosmetic.color[1], cosmetic.color[2], cosmetic.color[3])
	end
	return nil
end

-- The equipped skin's sound asset id for a target, or nil if it has none.
function Cosmetics.soundFor(target, equippedMap, ownedSet)
	local cosmetic = Cosmetics.equippedFor(target, equippedMap, ownedSet)
	if cosmetic and type(cosmetic.sound) == "string" and cosmetic.sound ~= "" then
		return cosmetic.sound
	end
	return nil
end

-- The color a cosmetic tints the BSODA spray billboard (GameConfig.BSODA_PROJECTILE.SPRAY_IMAGE):
-- its `sprayColor` if set, else its regular `color`, else nil (the spray keeps its default blue).
function Cosmetics.sprayColorOf(cosmetic)
	if not cosmetic then
		return nil
	end
	local c = cosmetic.sprayColor
	if typeof(c) == "Color3" then
		return c
	elseif type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return Cosmetics.colorOf(cosmetic)
end

-- The equipped skin's spray tint for a target, or nil for the default look.
function Cosmetics.sprayColorFor(target, equippedMap, ownedSet)
	return Cosmetics.sprayColorOf(Cosmetics.equippedFor(target, equippedMap, ownedSet))
end

return Cosmetics
