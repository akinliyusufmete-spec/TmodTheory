--[[
	SummerClasses (ModuleScript, ServerScriptService.BaldiGame.Modifiers.SummerClasses)

	Server behaviour of the Summer Classes modifier (numbers in
	ModifierConfig.LIST.SummerClasses). Loaded by ModifierService.

	  - When the LAST regular notebook is collected (collected == total), EXTRAS
	    extra notebooks appear on free spawn nodes (NotebookSpawner.spawnExtra).
	  - Each extra collected (collected > total — GameManager keeps counting
	    past the total) credits that player and spawns one replacement, so
	    EXTRAS stay on the map until the round ends. If the map has no free
	    nodes left, fewer appear; nothing errors.
	  - Win breakdown: "Summer Classes (k)" worth k * CURRICULUMS_PER_NOTEBOOK.
	  - Heat may climb past 1, up to GameConfig.HEAT.SUMMER_MAX, as the
	    collected count keeps rising (GameManager.getHeat reads heatCap).
	  - Toji / Presidential Tortoise keep scaling per notebook on their own:
	    ModifierService feeds them the collected count, extras included.

	The extras themselves are removed by NotebookSpawner.clear(), which
	GameManager's endRound calls on every round end.
]]

local SummerClasses = {}

local extrasBy = {} -- [player] = extras collected this run

local function spawner(env)
	local notebookSpawner = env.ctx.notebookSpawner
	if notebookSpawner and notebookSpawner.spawnExtra then
		return notebookSpawner
	end
	return nil
end

function SummerClasses.start(_env, _count)
	extrasBy = {} -- never carry a previous run's tally over
end

function SummerClasses.onNotebookCollected(env, player, collected, total)
	if type(collected) ~= "number" or type(total) ~= "number" or total <= 0 then
		return
	end
	local notebookSpawner = spawner(env)
	if collected == total then
		-- the last regular notebook: summer school is in session
		if notebookSpawner then
			notebookSpawner.spawnExtra(env.def.EXTRAS or 3)
		end
	elseif collected > total then
		-- an extra was picked up: credit it, then top the map back up
		if player then
			extrasBy[player] = (extrasBy[player] or 0) + 1
		end
		if notebookSpawner then
			notebookSpawner.spawnExtra(1)
		end
	end
end

function SummerClasses.breakdownRows(env, player)
	local k = extrasBy[player] or 0
	if k <= 0 then
		return nil
	end
	return {
		{ label = "Summer Classes (" .. k .. ")", amount = k * (env.def.CURRICULUMS_PER_NOTEBOOK or 25) },
	}
end

function SummerClasses.heatCap(env)
	local heat = env.ctx.config and env.ctx.config.HEAT
	return (heat and heat.SUMMER_MAX) or 1.5
end

function SummerClasses.stop(_env)
	extrasBy = {}
end

return SummerClasses
