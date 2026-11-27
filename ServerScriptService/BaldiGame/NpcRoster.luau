--[[
	NpcRoster (ModuleScript, ServerScriptService.BaldiGame.NpcRoster)

	Lookups over ctx.npcs that also see EVIL Theory twins. A twin is
	registered as ctx.npcs[<Name> .. SUFFIX] ("SilverEvil") next to its
	original ("Silver"); code asking "is this player held by Silver?" must ask
	every Silver, not just ctx.npcs.Silver.

	  NpcRoster.baseName(name)            "SilverEvil" -> "Silver"
	  NpcRoster.isTwin(name)              true for "SilverEvil"
	  NpcRoster.named(ctx, name)          { original?, twins... } of that character
	  NpcRoster.any(ctx, name, fn, ...)   true if any of them answers npc[fn](...) truthily
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("CharacterConfig"))

local NpcRoster = {}

NpcRoster.SUFFIX = CharacterConfig.TWIN_SUFFIX or "Evil"

function NpcRoster.baseName(name)
	return CharacterConfig.baseName(name)
end

function NpcRoster.isTwin(name)
	return CharacterConfig.baseName(name) ~= tostring(name or "")
end

-- the original first (if registered), then its twins
function NpcRoster.named(ctx, name)
	local list = {}
	local npcs = ctx.npcs or {}
	local original = npcs[name]
	if original then
		table.insert(list, original)
	end
	for key, npc in pairs(npcs) do
		if key ~= name and CharacterConfig.baseName(key) == name then
			table.insert(list, npc)
		end
	end
	return list
end

function NpcRoster.any(ctx, name, fnName, ...)
	for _, npc in ipairs(NpcRoster.named(ctx, name)) do
		local fn = type(npc) == "table" and npc[fnName]
		if type(fn) == "function" and fn(...) then
			return true
		end
	end
	return false
end

return NpcRoster
