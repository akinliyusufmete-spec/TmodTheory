--[[
	EvilTheory (ModuleScript, ServerScriptService.BaldiGame.Modifiers.EvilTheory)

	"Every character has an evil twin." (ModifierConfig.LIST.EvilTheory)

	The twins are real copies of the characters: on the FIRST EVIL run each AI
	ModuleScript (ChatReviveAI, LpAI, ...) is cloned next to its original (so
	its script.Parent.NpcBase / NpcFactory requires still resolve) and the
	clone's init runs with { suffix = SUFFIX, spawnOffset = SPAWN_OFFSET }.
	Requiring a clone runs the module fresh, so every twin has its own state.
	A twin registers as ctx.npcs[<Name> .. SUFFIX] ("ChatReviveEvil"), wears
	its original's rig and CharacterConfig, and spawns SPAWN_OFFSET away from
	it. SweeperAI makes GuidelinesEvil AND SaiEvil from one init. Only the AIs
	with a character in the run's roster are twinned (Chain/Beans sit Classic
	out); twins are kept for every later EVIL run, never rebuilt.

	Lifecycle:
	  start  twins of the mode's roster are reset to their spawn (unparked,
	         paused — the first notebook wakes them with everyone else) and
	         set their board up (onRoundStart); the rest stay parked
	  onNotebookCollected  the last notebook enrages the mode hunter's twin
	         too (GameManager only enrages ctx.npcs[HUNTER])
	  stop   every twin is reset and parked
	Between runs (and in runs without this modifier) a twin is parked: its
	reset() is wrapped so GameManager's resetNpcs, which unparks everyone,
	parks it again unless an EVIL run is on; GameManager.npcEnabled keeps it
	off the field too.
]]

local EvilTheory = {}

-- the AI modules to twin, in Main.server's init order, and the characters
-- (GameConfig.NPC.*.NAME) each one makes
local SOURCES = {
	{ module = "ChatReviveAI", names = { "ChatRevive" } },
	{ module = "LpAI", names = { "LP" } },
	{ module = "FrostyAI", names = { "Frosty" } },
	{ module = "SilverAI", names = { "Silver" } },
	{ module = "SweeperAI", names = { "Guidelines", "Sai" } },
	{ module = "GuyAI", names = { "Guy" } },
	{ module = "ChainAI", names = { "Chain" } },
	{ module = "BeansAI", names = { "Beans" } },
}

local twins = {} -- { { name = "ChatReviveEvil", base = "ChatRevive", npc = <AI table> } }
local attempted = {} -- [module name] = true once its twins were made (or failed: never retried)
local enraged = false -- the hunter's twin was enraged this run

local function debugOff(config, baseName)
	local dbg = config.DEBUG
	return dbg ~= nil and dbg.ENABLED and dbg.NPCS ~= nil and dbg.NPCS[baseName] == false
end

-- park the twin whenever it's reset outside an EVIL run (GameManager's
-- resetNpcs unparks every character at round start/end)
local function wrapReset(env, npc)
	local reset = npc.reset
	npc.reset = function()
		if reset then
			reset()
		else
			npc.base:resetToSpawn()
		end
		if not env.service.has(env.id) then
			npc.base:park()
		end
	end
end

local function createTwins(env, roster)
	local ctx = env.ctx
	local engine = script.Parent.Parent -- BaldiGame
	local suffix = env.def.SUFFIX or "Evil"
	for _, source in ipairs(SOURCES) do
		local wanted = false
		for _, name in ipairs(source.names) do
			if roster[name] then
				wanted = true
			end
		end
		if wanted and not attempted[source.module] then
			attempted[source.module] = true
			local original = engine:FindFirstChild(source.module)
			if original and original:IsA("ModuleScript") then
				local ok, err = pcall(function()
					local copy = original:Clone()
					copy.Name = source.module .. suffix
					copy.Parent = engine -- beside the original: its sibling requires resolve
					local module = require(copy)
					module.init(ctx, { suffix = suffix, spawnOffset = env.def.SPAWN_OFFSET })
				end)
				if not ok then
					warn("[Tmod] EVIL Theory: couldn't make the " .. source.module .. " twin: " .. tostring(err))
				end
			else
				warn("[Tmod] EVIL Theory: no " .. source.module .. " module to twin")
			end
			for _, name in ipairs(source.names) do
				local npc = ctx.npcs[name .. suffix]
				if type(npc) == "table" and npc.base then
					wrapReset(env, npc)
					table.insert(twins, { name = name .. suffix, base = name, npc = npc })
				end
			end
		end
	end
end

function EvilTheory.start(env)
	local ctx = env.ctx
	enraged = false
	local mode = (ctx.manager and ctx.manager.getModeConfig()) or {}
	local roster = mode.NPCS or {}
	createTwins(env, roster)
	for _, twin in ipairs(twins) do
		local npc = twin.npc
		local ok, err = pcall(function()
			if roster[twin.base] and not debugOff(ctx.config, twin.base) then
				npc.reset() -- the run is on: back at its spawn, unparked, paused
				if npc.base.parked then
					npc.base:unpark()
				end
				if npc.onRoundStart then
					npc.onRoundStart() -- e.g. Frosty's twin lays its starting traps
				end
			else
				npc.base:park()
			end
		end)
		if not ok then
			warn("[Tmod] EVIL Theory: " .. twin.name .. " failed to take the field: " .. tostring(err))
		end
	end
end

function EvilTheory.onNotebookCollected(env, _player, collected, total)
	local ctx = env.ctx
	if enraged or not ctx.manager then
		return
	end
	if not total then
		total = select(2, ctx.manager.getNotebookCounts())
	end
	if not collected or not total or collected < total then
		return
	end
	enraged = true
	local hunter = ctx.manager.getModeConfig().HUNTER or "ChatRevive"
	for _, twin in ipairs(twins) do
		local npc = twin.npc
		if twin.base == hunter and npc.enrage and not npc.base.parked then
			local ok, err = pcall(npc.enrage)
			if not ok then
				warn("[Tmod] EVIL Theory: " .. twin.name .. ".enrage failed: " .. tostring(err))
			end
		end
	end
end

function EvilTheory.stop(_env)
	enraged = false
	for _, twin in ipairs(twins) do
		local ok, err = pcall(function()
			twin.npc.reset() -- drops any grab/trap/shackle and its round state
			twin.npc.base:park()
		end)
		if not ok then
			warn("[Tmod] EVIL Theory: couldn't park " .. twin.name .. ": " .. tostring(err))
		end
	end
end

return EvilTheory
