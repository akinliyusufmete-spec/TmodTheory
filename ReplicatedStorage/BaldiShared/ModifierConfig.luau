--[[
	ModifierConfig (ModuleScript, ReplicatedStorage.BaldiShared.ModifierConfig)

	Single source of truth for the Modifiers system: what each modifier is
	called, what it says, how much Curriculum bonus it gives, and every
	gameplay number it uses. Server (ModifierService + BaldiGame/Modifiers/*)
	and client (ModifierMenuController, ModifierClient + BaldiClient/Modifiers/*)
	both read it. Tune numbers here; no logic lives in this file.

	icon = the card sprite (an Image asset id) shown in the panel's optional
	`Icon` image on each card.

	Ids double as the asset folder names under
	ReplicatedStorage.BaldiShared.BaldiAssets.Modifiers.<id> (see
	MODIFIER_ASSETS.md) and as the module names under BaldiGame/Modifiers and
	BaldiClient/Modifiers.

	Unlock: a player with at least one win OR the "Tmod Theory" badge
	(GameConfig.BADGES.LIST.TMOD_THEORY) can pick modifiers when starting a
	Classic run. Other modes always start with none.

	Stacking (Randomizer can roll the same modifier more than once):
	  - bonusPct adds up per stack, with no cap
	  - speed multipliers multiply per stack (two Tortoise stacks = 0.2 * 0.2)
	  - everything else is on/off and applies once however often it's rolled
]]

local ModifierConfig = {}

-- clamps for the combined speed multipliers (player and NPC)
ModifierConfig.MIN_MULT = 0.1
ModifierConfig.PLAYER_MULT_CAP = 5
ModifierConfig.NPC_MULT_CAP = 5

ModifierConfig.RANDOMIZER_MAX = 66
ModifierConfig.UNLOCK_BADGE = "TMOD_THEORY" -- key in GameConfig.BADGES.LIST
ModifierConfig.MODES = { CLASSIC = true } -- modes that accept modifiers

-- the order the panel lists them in
ModifierConfig.ORDER = {
	"Frenzy",
	"Toji",
	"PresidentialTortoise",
	"ColorInversion",
	"SeeMoon",
	"StillYou",
	"EvilTheory",
	"GrandBully",
	"Randomizer",
	"FireDrill",
	"SummerClasses",
	"CramSchool",
}

ModifierConfig.LIST = {
	Frenzy = {
		name = "Frenzy",
		icon = "rbxassetid://139763262026608", -- card sprite
		description = "Everyone moves almost twice as fast. Zesty Bars give an extra burst of speed.",
		type = "Regular",
		bonusPct = 10,
		SPEED = 1.9, -- player AND NPC speed multiplier
		FOV = 120, -- camera field of view during the run
		ZESTY_MULT = 1.5, -- extra player speed after eating a Zesty Bar...
		ZESTY_TIME = 7, -- ...for this many seconds (refreshes, doesn't stack)
	},
	Toji = {
		name = "You're not.. TOJI-KUN!!!",
		icon = "rbxassetid://83774687425000", -- card sprite
		description = "You're far faster and get faster with every notebook. Get close to a character and it shatters like glass for a moment.",
		type = "Regular",
		bonusPct = 2,
		PLAYER_BASE = 1.85, -- player speed = PLAYER_BASE + PLAYER_PER_NOTEBOOK * notebooks
		PLAYER_PER_NOTEBOOK = 0.15,
		NPC_BASE = 1, -- NPC speed = NPC_BASE + NPC_PER_NOTEBOOK * notebooks
		NPC_PER_NOTEBOOK = 0.05,
		GLASS_RADIUS = 6, -- studs: an NPC this close turns to glass
		GLASS_SECONDS = 1, -- how long it stays glass (and stunned)
		REARM_COOLDOWN = 0.5, -- after leaving the radius, seconds before that NPC can shatter again
		CHECK_INTERVAL = 0.1,
		-- client look of a glass NPC
		GLASS_COLOR = Color3.fromRGB(170, 220, 255),
		GLASS_TRANSPARENCY = 0.4,
	},
	PresidentialTortoise = {
		name = "Presidential Tortoise",
		icon = "rbxassetid://126737004388827", -- card sprite
		description = "Everyone crawls — but you speed up with each notebook. A presidential turtle follows you the whole run. Don't let it touch you.",
		type = "Regular",
		bonusPct = 14,
		NPC_SPEED = 0.2, -- every NPC's speed multiplier
		PLAYER_SPEED = 0.2, -- player speed at the start of the run...
		PLAYER_NOTEBOOK_MULT = 1.4, -- ...multiplied by this per notebook (0.2 * 1.4^n)
		TURTLE_SPEED = 2, -- turtle WalkSpeed = TURTLE_SPEED * TURTLE_NOTEBOOK_MULT^n
		TURTLE_NOTEBOOK_MULT = 1.2,
		TURTLE_CATCH_DISTANCE = 3, -- studs: touching you ends the run
		TURTLE_REPATH = 0.5, -- seconds between re-aims at the player
	},
	ColorInversion = {
		name = "Color Inversion",
		icon = "rbxassetid://88719752627345", -- card sprite
		description = "The colors of the world are inverted.",
		type = "Regular",
		bonusPct = 1,
	},
	SeeMoon = {
		name = "See Moon",
		icon = "rbxassetid://119693730899742", -- card sprite
		description = "The whole world is mirrored left to right.",
		type = "Regular",
		bonusPct = 9,
	},
	StillYou = {
		name = "\"It's still you.\"",
		icon = "rbxassetid://79020522253998", -- card sprite
		description = "After your first notebook, an inverted copy of you retraces your steps a few seconds behind. Touching it scrambles your controls.",
		type = "Regular",
		bonusPct = 8,
		DELAY = 4, -- seconds the clone trails behind you
		HIT_DISTANCE = 3, -- studs: closer than this = it caught you
		INVERT_SECONDS = 10, -- movement is inverted this long after a hit
		RESPAWN_SECONDS = 5, -- the clone comes back this long after a hit
	},
	EvilTheory = {
		name = "EVIL Theory",
		icon = "rbxassetid://103971994877470", -- card sprite
		description = "Every character has an evil twin.",
		type = "Regular",
		bonusPct = 20,
		SUFFIX = "Evil", -- twin names: ChatReviveEvil, LPEvil, ...
		SPAWN_OFFSET = Vector3.new(6, 0, 6), -- twin spawns this far from the original's spawn
	},
	GrandBully = {
		name = "Grand Bully",
		icon = "rbxassetid://79916161469880", -- card sprite
		description = "You can punch characters to stun them — but LP sees everything and comes for you. ChatRevive is a little faster.",
		type = "Regular",
		bonusPct = 6,
		COOLDOWN = 0.2, -- seconds between punches (server-enforced)
		RANGE = 8, -- studs
		CONE_DEGREES = 60, -- full cone width in front of you
		STUN_SECONDS = 6,
		LP_ALERT_SECONDS = 40, -- LP chases you this long after each punch
		CHATREVIVE_SPEED = 1.2, -- ChatRevive's speed multiplier
	},
	Randomizer = {
		name = "Randomizer",
		icon = "rbxassetid://121188785689518", -- card sprite
		description = "Rolls 1 to 66 random modifiers. You find out which when the run starts.",
		type = "Regular",
		bonusPct = 0, -- the rolled modifiers carry their own bonus
		stackable = true, -- the panel shows a 1..RANDOMIZER_MAX stepper
	},
	FireDrill = {
		name = "Fire Drill",
		icon = "rbxassetid://137350618095270", -- card sprite
		description = "You have 3 minutes to escape. Alarms, red lights, shaking halls.",
		type = "Regular",
		bonusPct = 16,
		SECONDS = 180, -- the run's time limit; 0:00 = you lose
		WARN_SECONDS = 30, -- the HUD timer turns red under this
		PULSE_PERIOD = 1, -- seconds per red-light pulse
		SHAKE_STUDS = 0.12, -- camera shake strength
		SHAKE_SPEED = 18, -- camera shake frequency
	},
	SummerClasses = {
		name = "Summer Classes",
		icon = "rbxassetid://118226186138106", -- card sprite
		description = "After the last notebook, extra notebooks keep appearing until you escape. Each one is worth extra Curriculums — and makes the school angrier.",
		type = "Regular",
		bonusPct = 0,
		EXTRAS = 3, -- extra notebooks kept on the map after the last one
		CURRICULUMS_PER_NOTEBOOK = 25, -- per extra notebook collected
		-- heat may climb past 1 up to GameConfig.HEAT.SUMMER_MAX while this is on
	},
	CramSchool = {
		name = "Cram School",
		icon = "rbxassetid://113119812719801", -- card sprite
		description = "The school is dark.",
		type = "Regular",
		bonusPct = 2,
	},
}

-- the Lighting properties CramSchool reads off its asset folder's attributes
ModifierConfig.CRAM_LIGHTING_ATTRIBUTES = { "Brightness", "Ambient", "OutdoorAmbient", "FogColor", "FogEnd", "ClockTime" }

function ModifierConfig.get(id)
	return ModifierConfig.LIST[id]
end

-- total bonus % for a stacks table { [id] = count }
function ModifierConfig.bonusFor(stacks)
	local total = 0
	for id, count in pairs(stacks or {}) do
		local def = ModifierConfig.LIST[id]
		if def and type(count) == "number" then
			total += (def.bonusPct or 0) * count
		end
	end
	return total
end

-- Curriculums the bonus adds on top of `base`
function ModifierConfig.bonusAmount(base, pct)
	return math.floor((base or 0) * (pct or 0) / 100)
end

return ModifierConfig
