--[[
	Toji (ModuleScript, ServerScriptService.BaldiGame.Modifiers.Toji)

	Server side of "You're not.. TOJI-KUN!!!". The speeds (players far faster,
	NPCs a little faster per notebook) are already in ModifierService; this
	file only does the glass.

	Every CHECK_INTERVAL: a targetable participant within GLASS_RADIUS of a
	character shatters it — stunned for GLASS_SECONDS, and its model's "Glass"
	attribute is on for that long (clients draw the glass look from it).

	Arming is per player + character pair, so standing next to someone can't
	keep them frozen forever: after a shatter that pair is disarmed until the
	player leaves the radius, then re-arms REARM_COOLDOWN seconds later.

	Skips parked characters and any whose NpcBase ignores modifiers (the
	Presidential Tortoise's turtle, which isn't in ctx.npcs anyway).
]]

local Toji = {}

local loopToken = nil -- a fresh table per run; the loop exits when it changes
local pairsState = {} -- [player] = { [base] = { inside = bool, rearmAt = number } }
local glassTokens = {} -- [model] = token of the shatter that set Glass

local function clearGlass()
	for model in pairs(glassTokens) do
		if model.Parent then
			model:SetAttribute("Glass", nil)
		end
	end
	glassTokens = {}
end

local function shatter(def, base)
	base:stun(def.GLASS_SECONDS)
	local model = base.model
	local token = {}
	glassTokens[model] = token
	model:SetAttribute("Glass", true)
	task.delay(def.GLASS_SECONDS, function()
		-- a later shatter (another player) owns the attribute now
		if glassTokens[model] == token then
			glassTokens[model] = nil
			model:SetAttribute("Glass", nil)
		end
	end)
end

local function tick(env)
	local ctx = env.ctx
	local def = env.def
	local manager = ctx.manager
	if not manager or not manager.isRoundActive() then
		return
	end
	local now = os.clock()
	local radius = def.GLASS_RADIUS
	for _, player in ipairs(manager.getTargetablePlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and manager.isParticipant(player) then
			local mine = pairsState[player]
			if not mine then
				mine = {}
				pairsState[player] = mine
			end
			for _, npc in pairs(ctx.npcs) do
				local base = npc.base
				if base and not base.parked and not base.ignoreModifiers and base.model.Parent then
					local entry = mine[base]
					local inside = (base.root.Position - hrp.Position).Magnitude <= radius
					if inside then
						if not entry or (not entry.inside and now >= entry.rearmAt) then
							shatter(def, base)
						end
						-- disarmed for as long as they stay close
						if entry then
							entry.inside = true
						else
							mine[base] = { inside = true, rearmAt = 0 }
						end
					elseif entry and entry.inside then
						entry.inside = false
						entry.rearmAt = now + def.REARM_COOLDOWN
					end
				end
			end
		end
	end
end

function Toji.onActive(env)
	local token = {}
	loopToken = token
	task.spawn(function()
		while loopToken == token do
			local ok, err = pcall(tick, env)
			if not ok then
				warn("[Tmod] Toji glass check failed: " .. tostring(err))
			end
			task.wait(env.def.CHECK_INTERVAL)
		end
	end)
end

function Toji.onPlayerLeft(_env, player)
	pairsState[player] = nil
end

function Toji.stop()
	loopToken = nil
	pairsState = {}
	clearGlass()
end

return Toji
