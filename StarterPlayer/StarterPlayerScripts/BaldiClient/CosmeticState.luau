--[[
	CosmeticState (ModuleScript, StarterPlayerScripts.BaldiClient.CosmeticState)

	The client's single source of truth for which cosmetics the player owns and
	has equipped. The server pushes this inside every StatsData payload;
	MenuController forwards it here via apply(). Anything that needs to render a
	skin — HudController (item slots + nickel icon), the shop UI — reads from
	here and subscribes to onChanged() to repaint when the player buys/equips.

	Initialized early (before HudController) so the HUD can subscribe at build
	time; until the first payload arrives, getColor() just returns the config
	defaults, so visuals are always correct.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("Cosmetics"))

local CosmeticState = {}

function CosmeticState.init(ctx)
	local self = {}

	local owned = {} -- { [id] = true }
	local equipped = {} -- { [target] = id }
	local listeners = {}

	-- Replace the held state from a StatsData payload's `cosmetics` field and
	-- notify everyone listening. Tolerates a nil/partial payload.
	function self.apply(payload)
		owned = {}
		equipped = {}
		if type(payload) == "table" then
			if type(payload.owned) == "table" then
				for id, isOwned in pairs(payload.owned) do
					if isOwned then
						owned[id] = true
					end
				end
			end
			if type(payload.equipped) == "table" then
				for target, id in pairs(payload.equipped) do
					equipped[target] = id
				end
			end
		end
		for _, callback in ipairs(listeners) do
			task.spawn(callback)
		end
	end

	-- The Color3 a target ("BSODA"/"ZESTY"/"SCISSORS"/"ALARM"/"NICKEL"/
	-- "NOTEBOOK") should render with, honoring the equipped skin and falling
	-- back to the default.
	function self.getColor(target)
		return Cosmetics.colorFor(target, equipped, owned)
	end

	-- The equipped skin's image asset id for a target, or nil if it has none.
	function self.getImage(target)
		return Cosmetics.imageFor(target, equipped, owned)
	end

	-- The equipped skin's sound asset id for a target, or nil if it has none.
	function self.getSound(target)
		return Cosmetics.soundFor(target, equipped, owned)
	end

	function self.getEquippedId(target)
		local cosmetic = Cosmetics.equippedFor(target, equipped, owned)
		return cosmetic and cosmetic.id or nil
	end

	function self.isOwned(id)
		return Cosmetics.isOwned(Cosmetics.byId(id), owned)
	end

	-- fire callback now is the caller's job; this just registers for changes
	function self.onChanged(callback)
		table.insert(listeners, callback)
	end

	-- thin wrappers so callers don't touch remotes directly
	function self.requestBuy(id)
		ctx.remotes.BuyCosmetic:FireServer(id)
	end

	function self.requestEquip(id)
		ctx.remotes.EquipCosmetic:FireServer(id)
	end

	return self
end

return CosmeticState
