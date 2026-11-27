--[[
	GameConfig (ModuleScript, ReplicatedStorage.BaldiShared.GameConfig)
	Single source of truth for every tunable number in the game.
	Both the server and the client require this module.
]]

local GameConfig = {}

-- ========== General ==========
GameConfig.GAME_TITLE = " "
GameConfig.GAME_SUBTITLE = "defy the mods"
GameConfig.COUNTDOWN_SECONDS = 3
GameConfig.FIRST_PERSON = true -- lock camera to first person during a round

-- ========== Debug ==========
-- Playtest toggles for the cast. When DEBUG.ENABLED is true, an NPC only
-- appears if it is switched ON below AND the game mode already uses it — flip
-- any to false to bench that character so you can test one in isolation (e.g.
-- ChatRevive alone, no sweepers underfoot). Applies at the START of a round,
-- so flip a value then press Play again. Leave ENABLED = false for normal play
-- (the mode roster decides who shows up).
GameConfig.DEBUG = {
	ENABLED = true,
	NPCS = {
		ChatRevive = true,
		LP = true,
		Frosty = true,
		Silver = true,
		Guidelines = true,
		Sai = true,
		Guy = true,
		Chain = true,
		Beans = true,
		Sportage = true,
	},
}

-- ========== Map loading ==========
-- The school (Workspace/BaldiMap) is held out of the world when a server
-- starts, so joining players don't download it; it loads in when the first
-- run begins and then stays until the server closes. false = in the world
-- from the start (the old way).
GameConfig.MAP_LOADS_ON_FIRST_RUN = true
GameConfig.MAP_LOAD_SETTLE = 1 -- seconds the navmesh gets over the freshly loaded map before the countdown

-- ========== Notebooks ==========
GameConfig.NOTEBOOK_SPAWN_COUNT = 10 -- how many notebooks are placed per round
GameConfig.NOTEBOOK_PROMPT_DISTANCE = 8

-- Timing-bar minigame: E on a notebook opens a bar with a marker sweeping
-- back and forth and a green zone in the middle. Press E while the marker
-- is in the green to land a hit; HITS hits collects the notebook. Missing
-- is free — just try the next pass. F (or the X button) gives up. You stay
-- vulnerable the whole time, so pick your moment. (Silver's grab-escape
-- uses the same bar — see NPC.SILVER.)
GameConfig.NOTEBOOK_MINIGAME = {
	ENABLED = true, -- false = E collects instantly, like before
	HITS = 5, -- green-zone presses to collect (misses don't set you back)
	HIT_WINDOW = 0.2, -- half-width of the green zone, as a fraction of the bar
	BAR_PERIOD = 1.5, -- seconds for the marker to sweep across and back
	MIN_HIT_GAP = 0.2, -- server: ignore hits closer together than this
	MAX_SECONDS = 25, -- server abandons a session after this long
	CANCEL_DISTANCE = 12, -- walking this far from the notebook abandons it
}

-- Each notebook spawned in a round is randomly assigned one of these types.
-- The type determines the cover color and which minigame it opens. weight
-- controls how often each type appears relative to the others.
-- If a game mode sets MINIGAME (e.g. Impersonator), that overrides the type.
GameConfig.NOTEBOOK_TYPES = {
	{ id = "red",    color = Color3.fromRGB(200, 40,  40),  minigame = "timing",   weight = 3 },
	{ id = "blue",   color = Color3.fromRGB(50,  110, 220), minigame = "math",     weight = 3 },
	{ id = "green",  color = Color3.fromRGB(40,  160, 70),  minigame = "memory",   weight = 3 },
	{ id = "purple", color = Color3.fromRGB(130, 50,  200), minigame = "sequence", weight = 3 },
}

-- Blue notebook: a simple arithmetic question with 4 multiple-choice answers.
-- One correct pick collects it; a wrong answer closes the minigame (try again).
GameConfig.MATH_MINIGAME = {
	MAX_SECONDS     = 30,
	CANCEL_DISTANCE = 12,
}

-- Green notebook: a sequence of coloured tiles flashes one at a time — watch,
-- then tap them back in the same order. Wrong tap closes it (try again).
GameConfig.MEMORY_MINIGAME = {
	MAX_SECONDS     = 45,
	CANCEL_DISTANCE = 12,
	SEQUENCE_LENGTH = 4,   -- number of tiles to remember
	SHOW_EACH       = 0.65, -- seconds each tile glows during the preview
	SHOW_GAP        = 0.1,  -- pause between each glow
}

GameConfig.MENU_CAMERA = {
	PART_NAME = "MENU_CAMERA",
	FIELD_OF_VIEW = 60,
}

-- ========== Mobile touch controls ==========
-- Default on-screen button layout, tuned for thumb reach (Roblox thumb-zone
-- guidance: keep frequent buttons in the bottom corners, clear of the jump
-- button). x/y are screen fractions of each button's CENTRE; scale multiplies
-- its base size. Players can drag and resize these in the editor
-- (Options -> Edit Touch Controls); their layout saves to their profile.
GameConfig.MOBILE_HUD = {
	DEFAULTS = {
		sprint = { x = 0.72, y = 0.86, scale = 1 }, -- RUN, lower-right-of-centre (clear of the movement thumbstick + the USE/SWAP/jump stack)
		use    = { x = 0.915, y = 0.74, scale = 1 }, -- USE, bottom-right (above jump)
		swap   = { x = 0.915, y = 0.55, scale = 1 }, -- SWAP, above USE
	},
	BASE_SIZE = { sprint = 96, use = 96, swap = 82 },
	MIN_SCALE = 0.6,
	MAX_SCALE = 1.7,
}

-- ========== Player movement / stamina ==========
GameConfig.PLAYER = {
	WALK_SPEED = 24,
	SPRINT_SPEED = 32,
	-- on the main screen (before a run, after winning or losing) your character
	-- floats, anchored, this many studs above RoundSpawn; PLAY drops you in
	MENU_FLOAT_HEIGHT = 60,
}

GameConfig.STAMINA = {
	MAX = 100,
	DRAIN_PER_SEC = 10, -- while sprinting
	REGEN_PER_SEC = 6, -- while not sprinting
	SPRINT_REENABLE = 30, -- exhaustion lock clears at this value
	LOW_THRESHOLD = 30, -- bar turns yellow below this
}

-- ========== Items / economy ==========
GameConfig.ITEMS = {
	BSODA = {
		id = "BSODA",
		displayName = "BSODA",
		shortLabel = "BSODA",
		description = "Fires a fizzy blast that knocks a character back 20 studs and stuns it for 3 seconds.",
		cost = 1,
		color = { 40, 120, 255 }, -- RGB, built into Color3 where used
	},
	ZESTY = {
		id = "ZESTY",
		displayName = "Zesty Bar",
		shortLabel = "ZESTY",
		description = "Instantly restores your stamina to 100 and clears exhaustion.",
		cost = 1,
		color = { 250, 200, 40 },
	},
	SCISSORS = {
		id = "SCISSORS",
		displayName = "Safety Scissors",
		shortLabel = "SNIP",
		description = "Cut yourself free the instant Silver grabs you — and Silver stays snipped for a while. Only works while grabbed.",
		cost = 1,
		color = { 210, 210, 220 },
	},
	ALARM = {
		id = "ALARM",
		displayName = "Alarm Clock",
		shortLabel = "ALARM",
		description = "Drops at your feet and rings loudly. ChatRevive can't resist investigating the noise.",
		cost = 1,
		color = { 255, 150, 50 },
	},
}

-- ItemSpawner pads: any part named "ItemSpawner" in your map periodically
-- materializes a random item from ITEMS on itself (one at a time — it
-- restocks only after the previous item is taken).
GameConfig.ITEM_SPAWNER = {
	ENABLED = true,
	INTERVAL = 80, -- seconds between restock checks
}

-- ========== Cosmetics shop ==========
-- Players spend Curriculums (the win currency) on cosmetics that reskin how
-- their items look — the inventory icon, the BSODA spray, the nickel counter,
-- the notebooks. Cosmetics are purely visual and per-player; they never touch
-- gameplay.
--
-- LAYOUT: the shop has one PAGE per category (the tabs across the top). Inside
-- a page, each `target` gets its OWN labeled section with a horizontal row of
-- that item's skins. So the "Consumables" page shows a BSODA row, a Zesty row,
-- an Alarm row, and a Scissors row, each scrolling sideways on its own.
--
-- Each cosmetic:
--   id          unique string (also the DataStore key)
--   target      which thing it reskins: an ITEMS id ("BSODA"/"ZESTY"/
--               "SCISSORS"/"ALARM"), or "NICKEL", or "NOTEBOOK"
--   displayName / description   shown on the card
--   price       in Curriculums (0 = the free default everyone owns)
--   color       {r,g,b} tint applied to the placeholder visual + card swatch
--   sprayColor  {r,g,b} BSODA only: tint of the thrown spray billboard
--               (falls back to `color` when left out)
--   image       *** PASTE YOUR SKIN *IMAGE* ID HERE ("rbxassetid://...") ***
--               (an Image id, not a Decal id — a Decal id shows blank; in
--               Studio, paste the decal id into any Decal's Texture and copy
--               back the converted number)
--               When set it becomes the card preview AND the in-game look
--               (inventory icon / nickel icon / notebook cover). Leave "" to
--               fall back to the color tint until your art is ready.
--   default     true marks the baseline look (auto-owned, auto-equipped)
--
-- NOTEBOOK skins are image-based and are tinted by the notebook's TYPE color
-- (red/blue/green/purple) so the "which minigame" cue is preserved — make that
-- art light/greyscale so the type color reads through it.
--
-- BSODA's thrown spray is a camera-facing billboard of
-- BSODA_PROJECTILE.SPRAY_IMAGE, recolored by the equipped skin's `sprayColor`
-- (or its `color` if it has none); the BSODA `image` only reskins the
-- inventory icon and shop card.
--
-- Add as many as you like — the sections, rows, and tabs all scale themselves.
GameConfig.SHOP = {
	-- one tab per category; `targets` lists which item sections appear on that
	-- page, top to bottom
	CATEGORIES = {
		{ id = "consumables", label = "Consumables", targets = { "BSODA", "ZESTY", "ALARM", "SCISSORS" } },
		{ id = "coins",       label = "Coins",       targets = { "NICKEL" } },
		{ id = "notebooks",   label = "Notebooks",   targets = { "NOTEBOOK" } },
	},
	-- section header for targets that aren't in ITEMS (ITEMS targets use their
	-- own displayName)
	TARGET_LABELS = {
		NICKEL = "Nickel",
		NOTEBOOK = "Notebook",
	},
}

GameConfig.COSMETICS = {
	-- ============ Consumables ============
	-- ---- BSODA ----
	-- `sprayColor` recolors the thrown spray (see BSODA_PROJECTILE.SPRAY_IMAGE)
	{ id = "bsoda_classic",  target = "BSODA", displayName = "Classic",          description = "The original blue fizz.",   price = 0,   color = { 40, 120, 255 }, sprayColor = { 70, 150, 255 },  image = "rbxassetid://2117177940", default = true },
	{ id = "bsoda_grape",    target = "BSODA", displayName = "Grape juice",      description = "ourple",                    price = 120, color = { 140, 60, 210 }, sprayColor = { 150, 70, 220 },  image = "rbxassetid://14891565897" },
	{ id = "bsoda_cherry",   target = "BSODA", displayName = "Sprite Cranberry", description = "sprite cranberry???",       price = 120, color = { 230, 50, 60 },  sprayColor = { 230, 50, 80 },   image = "rbxassetid://107070114948600" },
	{ id = "bsoda_lime",     target = "BSODA", displayName = "7up",              description = "seven up",                  price = 200, color = { 90, 220, 90 },  sprayColor = { 120, 230, 100 }, image = "rbxassetid://14122479139" },
	{ id = "bsoda_sweet",    target = "BSODA", displayName = "Prime",            description = "who drinks this bro",       price = 200, color = { 90, 220, 90 },  sprayColor = { 110, 200, 255 }, image = "rbxassetid://76359555319234" },
	{ id = "bsoda_choco",    target = "BSODA", displayName = "Chocy milk",       description = "we yes WE ALL drinking ts", price = 200, color = { 90, 220, 90 },  sprayColor = { 125, 80, 50 },   image = "rbxassetid://5531416930" },
	{ id = "bsoda_bsoda",    target = "BSODA", displayName = "Bsoda",            description = "a fresh coat of fizz",      price = 100, color = { 40, 120, 255 }, sprayColor = { 40, 120, 255 },  image = "rbxassetid://70756532512451" },
	{ id = "bsoda_yellow",   target = "BSODA", displayName = "Yellow Soda",      description = "dont ask whats in it",      price = 120, color = { 250, 215, 50 }, sprayColor = { 255, 225, 60 },  image = "rbxassetid://126826712689144" },
	{ id = "bsoda_cocacola", target = "BSODA", displayName = "Coca-Cola",        description = "the real thing",            price = 150, color = { 220, 30, 40 },  sprayColor = { 140, 60, 35 },   image = "rbxassetid://78942956652249" },
	{ id = "bsoda_pepsi",    target = "BSODA", displayName = "Pepsi",            description = "is pepsi ok?",              price = 150, color = { 30, 70, 200 },  sprayColor = { 40, 90, 220 },   image = "rbxassetid://121887962938510" },

	-- ---- Zesty Bar ----
	{ id = "zesty_classic", target = "ZESTY", displayName = "Classic",   description = "Standard zesty wrapper.",         price = 0,   color = { 250, 200, 40 }, image = "rbxassetid://2113042957", default = true },
	{ id = "zesty_choco",   target = "ZESTY", displayName = "Hersheys",  description = "dude is this chocolate anymore?", price = 100, color = { 120, 70, 40 },  image = "rbxassetid://128028097558452" },
	{ id = "zesty_minty",   target = "ZESTY", displayName = "Feastable", description = "mr yeast",                        price = 100, color = { 80, 220, 170 }, image = "rbxassetid://129379271481077" },
	{ id = "zesty_caramio", target = "ZESTY", displayName = "Caramio",   description = "caramel crime",                   price = 120, color = { 210, 150, 70 }, image = "rbxassetid://85415498486084" },
	{ id = "zesty_lint",    target = "ZESTY", displayName = "Lint",      description = "lindt's broke cousin",            price = 120, color = { 190, 40, 50 },  image = "rbxassetid://124505395210496" },
	{ id = "zesty_twix",    target = "ZESTY", displayName = "Twix",      description = "left twix or right twix",         price = 150, color = { 205, 155, 60 }, image = "rbxassetid://119173360255980" },

	-- ---- Alarm Clock ----
	{ id = "alarm_classic",  target = "ALARM", displayName = "Classic Alarm",  description = "Plain blue clock.", price = 0,  color = { 255, 150, 50 }, image = "rbxassetid://1881831114", default = true },
	{ id = "alarm_midnight", target = "ALARM", displayName = "Midnight Alarm", description = "Deep blue clock.",    price = 90, color = { 60, 90, 200 },  image = "rbxassetid://17230790157" },

	-- ---- Safety Scissors ----
	{ id = "scissors_classic", target = "SCISSORS", displayName = "Classic Scissors", description = "Safety silver coated with purple.",  price = 0,   color = { 210, 210, 220 }, image = "rbxassetid://2113033198", default = true },
	{ id = "scissors_gold",    target = "SCISSORS", displayName = "Golden Scissors",  description = "Money money money",  price = 150, color = { 240, 200, 60 },  image = "rbxassetid://16445243190" },

	-- ============ Coins ============
	{ id = "nickel_classic", target = "NICKEL", displayName = "Classic", description = "Good olde nickel.",      price = 0,   color = { 255, 210, 70 },  image = "rbxassetid://2113042728", default = true },
	{ id = "nickel_ruby",    target = "NICKEL", displayName = "Ruby",      description = "notch what happened to rubies", price = 80,  color = { 220, 50, 80 },   image = "rbxassetid://595988530" },
	{ id = "nickel_emerald", target = "NICKEL", displayName = "Emerald",   description = "50 for mending??",     price = 80,  color = { 60, 200, 120 },  image = "rbxassetid://14738663872" },
	{ id = "nickel_diamond", target = "NICKEL", displayName = "Diamond",   description = "straight from y 11",       price = 250, color = { 170, 225, 255 }, image = "rbxassetid://300751409" },

	-- ============ Notebooks ============
	-- the default is the stock notebook (no image override — keeps whatever your
	-- Notebook model looks like). Paid skins set `image` to your notebook art;
	-- it's tinted by the type color in-game.
	{ id = "notebook_classic", target = "NOTEBOOK", displayName = "Classic", description = "He is mod farming broo",   price = 0,   color = { 235, 235, 230 }, image = "rbxassetid://84823671784681", sound = "", default = true },
	{ id = "notebook_spiral",  target = "NOTEBOOK", displayName = "Notebook",  description = "Answer the question This looks easy Wait for the next one Graphics are cheesy",  price = 120, color = { 235, 235, 230 }, image = "rbxassetid://12219834840",     sound = "" },
	{ id = "notebook_comp",    target = "NOTEBOOK", displayName = "Tablet",      description = "Brainrot device", price = 120, color = { 220, 220, 225 }, image = "rbxassetid://480045124",                                         sound = "" },
	{ id = "notebook_graph",   target = "NOTEBOOK", displayName = "Tripple T",        description = "tung tung tung sa huuuuhuhuhuhuhuuur",   price = 180, color = { 225, 235, 230 }, image = "rbxassetid://104359094015436", sound = "rbxassetid://138857089980331" },
	{ id = "notebook_galaxy",  target = "NOTEBOOK", displayName = "Pixelated",  description = "time to put sharpness on this bad boy",      price = 300, color = { 235, 235, 235 }, image = "rbxassetid://7566388691",       sound = "" },
}

GameConfig.INVENTORY_SLOTS = 2
GameConfig.PICKUP_RADIUS = 3.5 -- walking this close to a NICKEL grabs it (items use the prompt below)

-- World item pickups: a ProximityPrompt on each item. Press the key / gamepad
-- button, tap/click the prompt, or (CLICKABLE) click the item itself.
-- Same key as the notebook prompts; a visible prompt eats the press, so it
-- never also fires "use item".
GameConfig.PICKUP_PROMPT = {
	ACTION_TEXT = "Pick up",
	KEY = "R", -- Enum.KeyCode name
	GAMEPAD_KEY = "ButtonX",
	HOLD = 0, -- seconds to hold (0 = instant press)
	DISTANCE = 14, -- studs
	CLICKABLE = true, -- also allow clicking the item model (ClickDetector)
	NICKELS_WALKOVER = false, -- nickels stay walk-over; false = nickels get a prompt too
}

GameConfig.VENDING_CLOSE_DISTANCE = 9 -- vending popup closes past this distance
GameConfig.NICKELS_AT_ROUND_START = 4 -- scattered in the halls so a fresh run can buy something
GameConfig.WORLD_ITEMS_AT_ROUND_START = true -- one free BSODA + Zesty hidden in the school

-- BSODA: a spray that latches onto the FIRST character in its path and
-- shoves them along (Baldi-style) — they can't move while sprayed — until they
-- hit a wall or the spray's lifespan runs out. The spray travels through walls
-- to reach a character, and it only ever flies horizontally (X/Z): aiming up
-- or down is ignored. It looks like SPRAY_IMAGE on a camera-facing billboard,
-- recolored by the shooter's equipped BSODA skin (`sprayColor` in COSMETICS).
GameConfig.BSODA_PROJECTILE = {
	SPEED = 55,            -- spray travel speed (studs/s) while seeking a target
	RANGE = 70,            -- how far the spray reaches looking for a character
	HIT_RADIUS = 4,        -- how close the spray must get to latch on
	HIT_HEIGHT = 6,        -- vertical slack for the latch (the spray can't aim up/down)
	-- look
	SPRAY_IMAGE = "rbxassetid://124913951847441", -- SodaSprayRecolorable (white art, so the tint reads)
	SPRAY_SIZE = 4.5,      -- billboard width/height (studs)
	SPRAY_HEIGHT = 0.5,    -- flight height above the shooter's HumanoidRootPart (studs)
	-- sustained push
	PUSH_SPEED = 26,       -- studs/s the caught character is shoved along the spray
	PUSH_LIFETIME = 30,    -- max seconds the spray pushes before it dissipates
	-- legacy knockback shove, still used by Silver's scissor-snip (NpcBase:stun)
	PUSH_STUDS = 20,
	PUSH_DURATION = 0.5,
	STUN_SECONDS = 3,
}

GameConfig.ALARM_CLOCK = {
	RING_SECONDS = 12, -- how long a placed alarm distracts ChatRevive
}

-- ========== Feel & polish ==========
-- Proximity dread: a heartbeat thump that quickens and swells as
-- ChatRevive closes in (or your own looping track via SOUNDS.tension).
GameConfig.TENSION = {
	RANGE = 50, -- audible within this many studs of ChatRevive
	MAX_INTERVAL = 1.15, -- seconds between thumps at the edge of RANGE
	MIN_INTERVAL = 0.32, -- seconds between thumps right on top of you
	MAX_VOLUME = 0.9,
}

-- End-of-round report card. Your escape time sets the base grade (first
-- row the time fits); every detention and every two Silver grabs knock it
-- down a step. Losing is always an F.
GameConfig.GRADES = {
	TIME_GRADES = {
		{ 150, "A+" },
		{ 210, "A" },
		{ 280, "B" },
		{ 360, "C" },
		{ 480, "D" },
	}, -- slower than the last row = F (you escaped... technically)
	DETENTION_PENALTY = 1, -- grade steps lost per detention
	GRAB_PENALTY = 1, -- grade steps lost per two Silver grabs
}

-- Heat (escalation): every notebook you collect raises "heat" from 0 to 1,
-- and the school gets scarier as it climbs — ChatRevive accelerates toward
-- his enraged pace and repaths tighter, the sweepers rest less, and Silver
-- sees further. CURVE shapes the ramp: 1 = linear, >1 = calm early and
-- brutal near the last notebooks. Set ENABLED = false for the old behaviour
-- (no ramp; everyone just snaps to enraged on the final notebook).
GameConfig.HEAT = {
	ENABLED = true,
	CURVE = 1.8, -- >1 back-loads the dread toward the final notebooks
	REPATH_FAST = 0.1, -- ChatRevive's repath interval at full heat (from NPC.REPATH_INTERVAL)
	SWEEPER_WAIT_SCALE = 0.45, -- sweeper rest time shrinks to this fraction at full heat
	SILVER_SIGHT_BONUS = 18, -- studs added to Silver's sight range at full heat
}

-- ========== Game modes ==========
-- CLASSIC is always available. The special modes unlock after a player's
-- FIRST WIN (persisted via DataStore when the game is published; in Studio
-- without API access it unlocks for the session).
GameConfig.MODES = {
	CLASSIC = {
		id = "CLASSIC",
		displayName = "Classic",
		-- nil fields fall back to the global defaults
		NOTEBOOKS = nil,
		COUNTDOWN = nil,
		HUNTER = "ChatRevive", -- whose footsteps the heartbeat tracks
		NPCS = { ChatRevive = true, LP = true, Frosty = true, Silver = true,
			Guidelines = true, Sai = true, Guy = true },
	},
	MULTIPLIED = {
		id = "MULTIPLIED",
		displayName = "Multiplied",
		CLOSED = true, -- shelved: this in-place maze mode isn't used. Real multiplayer goes through the Hub (the menu's MULTIPLAYER button). Kept CLOSED so the server refuses it; no menu button starts it.
		LOCKED_UNTIL_WIN = true,
		COUNTDOWN = 12, -- long lobby so the whole server can pile in
		NOTEBOOKS = 15,
		USES_MAZE = true, -- played in the generated maze school (or your
		-- own map: build Workspace/BaldiMapMultiplied with the same layout
		-- rules as BaldiMap and it is used instead)
		HUNTER = "ChatRevive",
		-- no sweepers: they have no routes in a maze
		NPCS = { ChatRevive = true, LP = true, Frosty = true, Silver = true, Guy = true },
		MAZE = {
			CELLS = 13, -- maze is CELLS x CELLS rooms
			CELL_SIZE = 14, -- studs per room
			WALL_HEIGHT = 12,
			EXTRA_OPENINGS = 0.12, -- fraction of walls knocked out for loops
		},
	},
	IMPERSONATOR = {
		id = "IMPERSONATOR",
		displayName = "Impersonator",
		CLOSED = true, -- not fully developed yet: hidden/disabled in the menu and refused by the server
		LOCKED_UNTIL_WIN = true,
		SINGLE_PLAYER = true, -- nobody can join your round
		HUNTER = "Sportage",
		NPCS = { Sportage = true }, -- the ONLY threat
		MINIGAME = "sequence", -- Sportage swapped the notebook locks
	},
	-- The big multiplayer match (launched from the Hub place). Runs on a
	-- reserved server with your hand-built MATCH.MAP_NAME map; the whole party
	-- arrives and plays together. Not startable from the normal menu — only the
	-- Hub launches it (MatchServer auto-starts it on a reserved server).
	MATCH = {
		id = "MATCH",
		displayName = "Multiplayer",
		USES_MATCHMAP = true,
		COUNTDOWN = 5, -- get-ready countdown AFTER the synced lobby (everyone's loaded in by then)
		NOTEBOOKS = 20, -- a big map holds more; capped to however many spawns exist
		HUNTER = "ChatRevive",
		NPCS = { ChatRevive = true, LP = true, Frosty = true, Silver = true,
			Guidelines = true, Sai = true, Guy = true, Chain = true, Beans = true },
	},
}

-- ========== Multiplayer match ==========
-- Master switch for multiplayer. false = the menu's MULTIPLAYER button says
-- it's coming soon and the server refuses the trip to the Hub.
GameConfig.MULTIPLAYER_ENABLED = false

-- The match runs on a reserved server of THIS place, launched from the Hub.
-- Build your big map as a folder named MAP_NAME (same contract as BaldiMap) and
-- leave it in Workspace or ServerStorage — MatchMap parks it in ServerStorage on
-- every server and swaps it into Workspace only while a match runs.
GameConfig.MATCH = {
	MAP_NAME = "BaldiMapMatch", -- the big map folder you built
	HUB_PLACE_ID = 120464057538192, -- players return here when the match ends
	-- STUDIO ONLY: when true, a Studio playtest auto-starts a MATCH round on your
	-- NORMAL map (BaldiMap) so you can test the multiplayer NPCs (Chain, Beans)
	-- right now — no Hub, no reserved server, no big map needed. Set it back to
	-- false to playtest Classic again. Has NO effect on published servers (a real
	-- match always uses MAP_NAME). One match per playtest; restart to retest.
	STUDIO_TEST = false,
	-- Synchronized start (reserved match servers): the round holds in a loading
	-- lobby until every teleported party member has loaded AND signalled ready,
	-- then runs COUNTDOWN and starts everyone together. Safety valves so a slow
	-- or failed loader can never hang the lobby:
	LOBBY_WAIT = 25, -- max seconds to wait for the whole party; then start with whoever's in
	ROSTER_FALLBACK = 6, -- if no party roster arrives via TeleportData this long after the first
	-- player loads, treat whoever is present as the roster (direct-join / no-data safety)
}

-- ========== Currency ==========
-- "Curriculums" — earned by winning. The escape award is based PURELY on how
-- fast you got out: MAX at (or under) FAST_SECONDS, falling in a straight line
-- to MIN at (or over) SLOW_SECONDS. A 1-minute escape pays 200; a 10-minute
-- crawl pays 1. Leftover Nickels are cashed in on top as a separate line.
GameConfig.CURRENCY = {
	NAME = "Curriculums",
	TIME_AWARD = {
		MAX = 300,          -- escape this fast (or faster) pays the max
		MIN = 1,            -- escape this slow (or slower) pays the min
		FAST_SECONDS = 60,  -- 1:00 -> MAX
		SLOW_SECONDS = 600, -- 10:00 -> MIN
	},
	-- leftover Nickels you escape with are cashed in at this rate (so a tidy
	-- run that hoarded coins pays off). 0 disables the conversion.
	NICKEL_TO_CURRICULUMS = 20,
}

-- Per-player client preferences. They persist on the profile and ride along in
-- the StatsData payload, so a player keeps them across sessions and devices.
--   stopwatch: show the live run timer on the HUD during a round
--   sfxVolume: master SFX volume, 0..1 (scales every SoundController play)
GameConfig.DEFAULT_SETTINGS = {
	stopwatch = true,
	sfxVolume = 1,
}

-- ========== Faculty guide ==========
-- Drives the "CHARACTERS" board in the menu so players can read what each
-- character does (and how to beat them). Order = display order. `color` is a
-- small accent swatch on the card. Edit freely; the board scales to the list.
GameConfig.NPC_GUIDE = {
	{
		name = "ChatRevive", role = "Teach",
		color = { 170, 35, 35 },
		desc = "Chaser. Always chases you. Each notebook makes him faster than previously. When all notebooks are collected, no one can stop him.",
	},
	{
		name = "LP", role = "aura",
		color = { 45, 70, 170 },
		desc = "Passive Chaser. He Enforces one rule: NO RUNNING... in his watch. Each Detention lasts longer than the previous one. If you get three detentions, you get kicked out from the school",
	},
	{
		name = "Frosty", role = "ragebaiter",
		color = { 170, 225, 255 },
		desc = "Trapper. Frosty utilizes his brain power to create various widgets and trinks to make mess for the player. Every match starts with 5-9 traps already placed.",
	},
	{
		name = "Silver", role = "small chud",
		color = { 210, 210, 220 },
		desc = "Chaser. When he sees you, you can't escape it. You either play his game or hide from him.",
	},
	{
		name = "Guidelines", role = "cat",
		color = { 90, 200, 90 },
		desc = "Sweeper. Controls the Bottom and Left side of the School. He is the fastest though he needs to catch his breath to run again.",
	},
	{
		name = "Sai", role = "fat guy",
		color = { 240, 200, 60 },
		desc = "Sweeper. Controls the Top and Right side of the School. He is slower than guidelines, but he patrols the place much quicker than him.",
	},
	{
		name = "Guy", role = "mimic",
		color = { 160, 120, 200 },
		desc = "THE MIMIC!!! Hides in notebooks to stun and distract the player.",
	},
	{
		name = "Chain", role = "chin  ·  Multiplayer",
		color = { 120, 120, 130 },
		desc = "Multiplied Special - Get around him and he will chain you. Either get along with it or break free... or just cutting the chain with the scissors (Somehow)",
	},
	{
		name = "Beans", role = "annoying  ·  Multiplayer",
		color = { 200, 120, 200 },
		desc = "Multiplied Special - He likes to chew gum, a lot. To impress others, he tries to pop the bubble but instead he spits it to the player.",
	},
}

-- The memory-sequence minigame (Impersonator's notebooks): watch a short
-- pattern of your Use/Swap keys flash, then repeat it. A wrong press is a
-- LOUD mistake — Sportage hears it and comes to investigate.
GameConfig.SEQUENCE_MINIGAME = {
	LENGTH = 5, -- symbols per pattern
	SHOW_SECONDS = 0.55, -- how long each symbol flashes during the preview
	MIN_PRESS_GAP = 0.12, -- server: presses faster than this are ignored
	MAX_SECONDS = 30,
	CANCEL_DISTANCE = 12,
}

-- ========== NPCs ==========
GameConfig.NPC = {
	-- Max age of a chase path before it's recomputed in the background.
	-- A big goal move forces a recompute sooner, and with clear line of
	-- sight the NPC steers directly with no pathfinding at all.
	-- Lower = tighter tracking (less "goldfish"), slightly more CPU.
	REPATH_INTERVAL = 0.3,

	-- Pathfinding agent shape, shared by every NPC. A small radius fits
	-- through hand-made doorways; jumping clears small thresholds/lips and
	-- lets a wedged NPC hop free. Make doorways at least ~5 studs wide.
	-- One character can override these in CharacterConfig.<Name>.Pathfinding.
	AGENT = {
		RADIUS = 2,
		HEIGHT = 5,
		JUMP = false,
		JUMP_HEIGHT = 4,
	},

	-- Movement engine (NpcBase:travel), routed by SimplePath
	-- (ServerScriptService.BaldiGame.SimplePath). NPCs keep walking while a
	-- new route computes, and steer straight at the goal when there's a clear
	-- walkable line to it — no stop-and-go between route recomputes.
	PATHING = {
		POLL = 0.5, -- steering update interval (seconds)
		REPATH_DISTANCE = 6, -- re-route a chase when the goal drifts this far from the route's end
		DIRECT_RANGE = 45, -- straight-line steering allowed within this range
		ARRIVE_RADIUS = 3, -- "arrived" distance for fixed destinations
		NO_PATH_RETRY = 0.25, -- backoff between failed route computes
		STUCK_CHECKS = 2, -- SimplePath: re-routes in a row without moving before it hops and reports "stuck"
		BODY_CLEARANCE = 2, -- "can I walk straight here?" shoulder-ray half-width (~ AGENT.RADIUS). Higher hugs doorframes/corners; lower is more direct but risks kissing walls.
	},

	CHATREVIVE = {
		NAME = "ChatRevive",
		-- Knows where the nearest player is from anywhere on the map and
		-- hunts relentlessly. Set false to require line of sight within
		-- SIGHT_RANGE instead.
		OMNISCIENT = false, -- true = old always-knows-where-you-are behaviour
		ROAM_SPEED = 14, -- with CHASE_SPEED, only sets where his Walk/Chase animations switch:
		CHASE_SPEED = 28, -- he moves by slap dashes (see Baldi movement below)
		ENRAGED_CHASE_SPEED = 34,
		ENRAGED_SIGHT_INTERVAL = 0.12,
		SIGHT_RANGE = 90, -- studs, calm (grows to SIGHT_RANGE_ENRAGED with heat)
		SIGHT_INTERVAL = 0.25, -- how often he re-picks the nearest target
		MEMORY_SECONDS = 6, -- chases last-known position this long after losing sight
		CATCH_DISTANCE = 4,

		-- ----- Baldi movement -----
		-- He never glides. Each slap his Dash animation (CharacterConfig) plays
		-- once: he stands through the wind-up, and on its "DashAttack" event
		-- marker he slaps and dashes DASH_STUDS further along his route (one
		-- route per goal, through corners and doorways), then stands until the
		-- next slap. Within CLOSE_RANGE of his target the slap gap is the normal
		-- one (SLAP_INTERVAL -> SLAP_INTERVAL_FAST as notebooks are collected);
		-- further away he dashes more often and quicker, reaching
		-- FAR_SLAP_INTERVAL / FAR_DASH_SPEED at FAR_RANGE. He re-reads where his
		-- target is every RETARGET_SECONDS (sooner when he reaches the old spot,
		-- gets stuck, or hears Guy's scream), heading for where you WERE.
		DASH_STUDS = 7,             -- ground covered per dash, along the route
		DASH_SPEED = 25,            -- WalkSpeed during a dash up close
		FAR_DASH_SPEED = 38,        -- ...rising to this when far away
		CLOSE_RANGE = 15,           -- studs: within this the dashes are the normal Baldi beat
		FAR_RANGE = 80,             -- studs: at (and past) this he dashes as often as he can
		FAR_SLAP_INTERVAL = 0.25,   -- seconds between slaps when far away
		RETARGET_SECONDS = 0.6,       -- how often he re-reads where his target is
		SLAP_INTERVAL = 0.85,       -- seconds between slaps at 0 heat (calm, very beatable)
		SLAP_INTERVAL_FAST = 0.32,  -- seconds between slaps at full heat / enraged (relentless)
		-- the Dash animation's timing is read off the animation itself; these
		-- only cover a failed read (length, and when DashAttack happens, at 1x)
		DASH_ANIM_LENGTH = 0.95,
		DASH_MARKER_AT = 0.833,

		-- ----- hunting (reworked AI) -----
		SIGHT_RANGE_ENRAGED = 1000,  -- sight range at full heat
		HUNCH_INTERVAL = 10,         -- seconds between "hearing" where you are, calm
		HUNCH_INTERVAL_FAST = 1.2,  -- ...at full heat
		LEAD_SECONDS = 0.6,         -- how far ahead of your run he aims
		LUNGE_RANGE = 14,           -- within this, his slap is a telegraphed lunge
		LUNGE_STUDS = 14,           -- lunge dash length (vs. DASH_STUDS)
		LUNGE_WINDUP_SCALE = 1.35,  -- longer wind-up = the telegraph
		LUNGE_SPEED_SCALE = 1.4,
		SEARCH_SECONDS = 10,        -- how long he sweeps after losing you
		SEARCH_SPOTS = 3,           -- waypoints he checks
		SEARCH_RADIUS = 60,         -- studs (walking distance with the graph)
		USE_DIJKSTRA = false,        -- Dijkstra over the Waypoints graph for long routes
		GRAPH_MIN_DISTANCE = 80,    -- studs: shorter routes use PathfindingService first
		HEAD_ON = true,             -- charge straight at the player when there's a clear line
		ATTACK_RANGE = 45,          -- studs
		ATTACK_SPEED = 65,          -- studs/s during the charge
		ATTACK_OVERSHOOT = 8,       -- studs past where you stood before it counts as a miss
		ATTACK_TURN_RATE = 90,      -- deg/s he can steer mid-charge
		ATTACK_COOLDOWN = 1.5,      -- s between charges
		ATTACK_MIN_BEAT = 0.55,     -- s minimum wind-up (the tell)
		ATTACK_WINDUP_SCALE = 1.35,
		ATTACK_RADIUS = 1.5,        -- spherecast radius for wall hits
	},
	LP = {
		NAME = "LP",
		-- LP enforces ONE rule: no running in the halls. He wanders, ignoring
		-- anyone walking — even right past him. The moment he NOTICES a player
		-- RUNNING (moving faster than RUN_DETECT_SPEED) within sight or within
		-- DETECT_RADIUS, he flags them and gives chase; once flagged he detains
		-- on catch even if they stop. Walkers are never flagged or detained.
		-- Detention escalates and the DETENTION_FORFEIT_AT-th catch forfeits.
		ROAM_SPEED = 13,
		CHASE_SPEED = 26, -- a sprint (32) still outruns him; stop + break sight to lose him
		RUN_DETECT_SPEED = 32, -- horizontal speed above this = "running" (walk 24 < 28 < sprint 32)
		SIGHT_RANGE = 70,
		DETECT_RADIUS = 22, -- a RUNNER this close is flagged even without line of sight
		SIGHT_INTERVAL = 0.25,
		MEMORY_SECONDS = 6, -- keeps chasing your last-known spot this long after losing you
		CATCH_DISTANCE = 4,
		DETENTION_SECONDS = 12, -- first detention; +DETENTION_STEP seconds for each one after
		DETENTION_STEP = 3,
		DETENTION_FORFEIT_AT = 3, -- the Nth catch ends the run instead of detaining
		RELEASE_IMMUNITY_SECONDS = 5, -- can't be re-detained right after release
	},
	FROSTY = {
		NAME = "Frosty",
		-- Frosty doesn't ice the halls any more: he sets up TRAPS across the
		-- school. A new run already has TRAPS_AT_START_MIN..MAX of them on random
		-- BaldiMap/TrapSpawns parts; once the characters wake up he roams, and
		-- every SET_INTERVAL_MIN..MAX seconds walks to a free TrapSpawn and sets
		-- up another (his TrapSetup animation loops for SETUP_MIN..MAX seconds).
		-- He never catches anyone himself. A trap springs once, then it's gone.
		-- He also keeps away from players: anyone within AVOID_RADIUS sends him
		-- off (mid-setup too) to the waypoint that's furthest from everyone, and
		-- he only wanders to, and sets traps in, spots that far from players.
		ROAM_SPEED = 14,                -- wandering / walking to a trap spot
		FLEE_SPEED = 22,                -- getting away from a player
		AVOID_RADIUS = 35,              -- studs: a player this close makes him leave

		-- ----- Trap placement -----
		TRAPS_AT_START_MIN = 5,         -- traps already set when a run loads...
		TRAPS_AT_START_MAX = 9,         -- ...somewhere between these two
		START_CLEARANCE = 20,           -- studs: no starting trap this close to the round spawn
		MAX_TRAPS = 12,                 -- he stops setting new ones at this many
		SET_INTERVAL_MIN = 12,          -- seconds between his trap setups (once active)
		SET_INTERVAL_MAX = 25,
		SETUP_MIN = 2.5,                -- how long one setup takes (TrapSetup loops this long)
		SETUP_MAX = 5,
		SETUP_OUTRO = 0.8,              -- the animation's finish after the loop, before he moves on
		TRAP_RADIUS = 3,                -- studs: a player this close springs it
		TRAP_IMMUNITY = 3,              -- after a trap lets go, no trap springs on you for this long
		-- how often each kind gets picked (relative weights; 0 = never)
		TRAP_WEIGHTS = { SlowMachiner3000 = 1, EnergyDrainer40 = 1, BEARTrapper = 1 },

		-- ----- SlowMachiner 3000: the frost status -----
		FROST_SLOW = 0.6,               -- speed cut (0.6 = 60% slower)
		FROST_SECONDS = 6,

		-- ----- EnergyDrainer-40: drained stamina + the exhaustion status -----
		DRAIN_TO = 10,                  -- stamina drops to this (if it was higher)
		EXHAUST_REGEN_CUT = 0.8,        -- stamina recharges this much slower (0.8 = 80%)
		EXHAUST_SECONDS = 7,

		-- ----- BEARTrapper: stuck until you win Silver's minigame -----
		BEAR_HITS = 3,                  -- hits needed to pry it open (Silver's bar: NPC.SILVER timing)
		BEAR_MAX_SECONDS = 25,          -- failsafe: it lets go after this long regardless
	},
	SILVER = {
		NAME = "Silver",
		ROAM_SPEED = 20,
		CHASE_SPEED = 26, -- slower than a sprint — but sprinting risks LP
		SIGHT_RANGE = 45,
		SIGHT_INTERVAL = 0.3,
		MEMORY_SECONDS = 3,
		CATCH_DISTANCE = 4,
		-- the grab minigame: press E as the marker crosses the green zone
		-- (same bar as the notebook minigame — kept easy/consistent)
		GRAB_HITS = 3, -- hits needed to wriggle free
		GRAB_HIT_WINDOW = 0.2, -- timing tolerance (fraction of the bar around center)
		GRAB_CUBE_PERIOD = 1.5, -- seconds per full marker swing at the start
		GRAB_SPEEDUP = 1.05, -- marker speeds up this much per successful hit
		GRAB_MIN_HIT_GAP = 0.2, -- server-side: hits closer together than this are ignored
		GRAB_MAX_SECONDS = 15, -- failsafe: held at most this long
		GRAB_IMMUNITY = 10, -- can't be re-grabbed right after escaping
		GRAB_COOLDOWN = 6, -- Silver rests after any grab
		SCISSORS_DISABLE = 8, -- cutting free stuns Silver this long
	},
	-- The hall sweepers: never catch anyone, just barrel down their route
	-- and shove whoever they touch along with them.
	SWEEPERS = {
		GUIDELINES = {
			NAME = "Guidelines",
			SWEEP_SPEED = 64, -- faster than a sprint while mid-sweep
			PUSH_SPEED = 50, -- how hard victims are carried along
			SWEEP_RADIUS = 9,
			WAIT_MIN = 10, -- rest at each end of the route
			WAIT_MAX = 14,
			SWEEPS_NPCS = true, -- also shoves the other characters (use it!)
		},
		SAI = {
			NAME = "Sai",
			SWEEP_SPEED = 48,
			PUSH_SPEED = 40,
			SWEEP_RADIUS = 10,
			WAIT_MIN = 2,
			WAIT_MAX = 3,
			SWEEPS_NPCS = true,
		},
	},
	-- Impersonator mode's hunter. Not omniscient — he relies on his EARS
	-- and his TRAPS: stepping on a trap roots you and tells him exactly
	-- where you are; failing his sequence lock does the same.
	SPORTAGE = {
		NAME = "Sportage",
		ROAM_SPEED = 14,
		CHASE_SPEED = 26, -- a sprint barely outruns him
		ENRAGED_CHASE_SPEED = 33, -- after the last notebook
		SIGHT_RANGE = 60,
		SIGHT_INTERVAL = 0.25,
		MEMORY_SECONDS = 5,
		CATCH_DISTANCE = 4,
		TRAPS_AT_START = 6, -- traps scattered at round start
		MAX_TRAPS = 8,
		TRAP_RADIUS = 3.2, -- stepping this close springs it
		TRAP_HOLD_SECONDS = 2.5, -- how long a sprung trap roots you
		TRAP_IMMUNITY = 6, -- can't be re-trapped right after one
		TRAP_RESTOCK = 18, -- he lays a fresh trap this often while patrolling
		TRAP_VISIBILITY = 0.45, -- 0 = invisible, 1 = obvious (transparency is 1 - this)
		HEARING_BURST = 7, -- seconds of "he knows where you are" after a noise
	},
	-- Guy, the mimic: poses as a notebook. Starting to "collect" him is a
	-- jumpscare — a loud SCREEE that pings the hunter straight to you —
	-- then he scurries off and poses somewhere else.
	GUY = {
		NAME = "Guy",
		SCURRY_SPEED = 35, -- how fast he flees after being revealed
		SCURRY_SECONDS = 6, -- how long he runs before re-posing
		REPOSE_DELAY = 6, -- seconds after fleeing before he poses again
		PING_SECONDS = 6, -- how long the hunter knows your exact position
		WOBBLE = 1.25, -- his fake notebook bobs this much faster (the tell)
		STUN_ON_REVEAL = 3, -- you freeze this long from the jumpscare
	},
	-- Chain — the shackler. MULTIPLAYER ONLY (parked outside the MATCH
	-- roster). He roams slowly; pass within CATCH_DISTANCE and he clamps a
	-- chain onto you. You then DRAG him around like a ball-and-chain: slowed
	-- to DRAG_SLOW with Chain trailing within TETHER_LENGTH studs. You're
	-- still in play (and still fair game for the hunter) — the slow is the
	-- punishment, not a catch. Break free two ways:
	--   * MASH the tug-of-war: each press adds TUG_PER_MASH strain (server
	--     ignores presses closer than TUG_MIN_GAP); reach TUG_REQUIRED to
	--     snap it. Strain bleeds off at TUG_DECAY/sec when you stop, so it's
	--     a real struggle.
	--   * Safety Scissors cut the chain instantly and leave Chain snipped
	--     (stunned) for SCISSORS_DISABLE seconds.
	-- One victim at a time. After a break Chain rests COOLDOWN seconds and
	-- you get SHACKLE_IMMUNITY seconds before he can re-shackle you. The
	-- tug-of-war popup does NOT lock your movement — you struggle free while
	-- still dragging him (mash [USE] / tap PULL; snip [SWAP] / tap SNIP).
	CHAIN = {
		NAME = "Chain",
		ROAM_SPEED = 15,
		CHASE_SPEED = 21, -- slower than a sprint; closing in is enough
		SIGHT_RANGE = 48,
		SIGHT_INTERVAL = 0.3,
		MEMORY_SECONDS = 4, -- chases your last-known spot this long after losing sight
		CATCH_DISTANCE = 4.5, -- "passes through" you to clamp on
		TETHER_LENGTH = 20, -- studs Chain trails behind while you drag him
		DRAG_SLOW = 0.55, -- your WalkSpeed multiplier while shackled
		DRAG_FOLLOW = 0.35, -- how snappily the dragged Chain catches up (0..1 lerp/frame)
		TUG_REQUIRED = 100, -- tug-of-war strain needed to snap the chain
		TUG_PER_MASH = 9, -- strain added per valid mash
		TUG_DECAY = 14, -- strain lost per second when you stop mashing
		TUG_MIN_GAP = 0.08, -- server: ignore mashes closer together than this
		SHACKLE_IMMUNITY = 8, -- can't be re-shackled right after breaking free
		COOLDOWN = 6, -- Chain rests after releasing a victim
		SCISSORS_DISABLE = 8, -- snipping the chain stuns Chain this long
	},
	-- Beans — the gum-spitter. MULTIPLAYER ONLY (parked outside the MATCH
	-- roster). He roams and, when a player lines up in a fairly straight shot
	-- ahead of him (facing dot >= SPIT_ALIGN) within SIGHT_RANGE and clear line
	-- of sight, he SPITS a gum wad straight down the lane. The wad flies in a
	-- FIXED straight line (no homing):
	--   * it sticks to the first character (player OR npc) within GUM_HIT_RADIUS,
	--     miring them in gum — slowed to GUM_SLOW for GUM_DURATION seconds,
	--   * or it splats on a wall / closed door and stops.
	-- The instant the gum lands on ANYTHING, Beans bolts (SCURRY_SPEED) for
	-- FLEE_SECONDS, settles REPOSE_DELAY, then can spit again (spits stay at
	-- least SPIT_COOLDOWN apart). A gummed player cuts free early with Safety
	-- Scissors ([SWAP] / tap CUT) and gets GUM_IMMUNITY seconds before he can be
	-- re-gummed; gummed NPCs re-gum no sooner than GUM_NPC_COOLDOWN.
	-- The wad passes through OPEN/swung doorways naturally (they're out of the
	-- straight line); a closed/locked door is solid geometry and stops it.
	BEANS = {
		NAME = "Beans",
		ROAM_SPEED = 17,
		SCURRY_SPEED = 30, -- how fast he bolts after a gum lands
		FLEE_SECONDS = 4, -- how long he bolts before settling
		REPOSE_DELAY = 3, -- settle time after fleeing before he can spit again
		SIGHT_RANGE = 60,
		SIGHT_INTERVAL = 0.3,
		SPIT_COOLDOWN = 6, -- minimum seconds between spits
		SPIT_ALIGN = 0.25, -- target must be in his front arc (cos of angle; ~0=90° side, 1=dead ahead). He turns to face before spitting; this just stops back-of-head snipes.
		GUM_SPEED = 62, -- studs/s the wad travels
		GUM_RANGE = 95, -- max wad travel distance before it dissipates
		GUM_HIT_RADIUS = 3.6, -- how close to a character counts as a hit
		GUM_SLOW = 0.4, -- WalkSpeed multiplier while gummed
		GUM_DURATION = 10, -- seconds the gum slows a victim (players + NPCs)
		GUM_NPC_COOLDOWN = 6, -- per-NPC re-gum cooldown
		GUM_IMMUNITY = 3, -- a player can't be re-gummed right after one wears off
	},
}

-- ========== Badges ==========
-- Awarded by ServerScriptService.BaldiGame.Badges. Each entry is the badge's
-- id and its name (used in the server log). The numbers below them are what
-- the badges ask for; "Multiplied" badges count runs in MULTIPLAYER_MODES.
GameConfig.BADGES = {
	LIST = {
		TMOD_THEORY        = { id = 140186044686160,  name = "Tmod Theory" },              -- win a game
		SQUARED            = { id = 2489553340556827, name = "Tmod Theory Squared" },      -- finish a Multiplied run
		ZERO_STRIKES       = { id = 1114372725134863, name = "Zero out of Four strikes" }, -- win a run without a detention
		STYLISH            = { id = 1337732765776069, name = "Stylish" },                  -- buy a skin
		CHAT_KILL          = { id = 1255609530443035, name = "Chat Kill" },                -- lose to ChatRevive
		TMOD_CURRICULUM    = { id = 3511380453735208, name = "Tmod Curriculum" },          -- win CURRICULUM_WINS times
		ALL_I_NEED         = { id = 3466122013719117, name = "All I need is 2 Minutes." }, -- win in under TWO_MINUTES
		RAGEBAIT           = { id = 3930580467779641, name = "Ragebait SUCCESS" },         -- win a RAGEBAIT_GRADE run after more than RAGEBAIT_TRAPS of Frosty's traps
		FASHION_CHASER     = { id = 12937293743834,   name = "Fashion Chaser" },           -- own more than FASHION_CHASER_SKINS bought skins
		FASHIONISTA        = { id = 948343712859550,  name = "Fashionista!" },             -- own every skin in the shop
		PHENOMENAL_WIPEOUT = { id = 4020205363827883, name = "Phenomenal Wipeout" },       -- win in under WIPEOUT_SECONDS
		LOCKDOWN           = { id = 429401226050282,  name = "6 Hour Lockdown" },          -- win a multiplayer run in under LOCKDOWN_SECONDS
		GOOD_NOODLES       = { id = 294230308041019,  name = "Good Noodles" },             -- win a Multiplied run with GOOD_NOODLES_PLAYERS, nobody caught, no Modstat failed
		PURGE_GENERAL      = { id = 2660462273506742, name = "Purge General" },            -- win a Multiplied run with PURGE_PLAYERS in under PURGE_SECONDS
		POSCERE            = { id = 4350819004393147, name = "Poscere, Theorizare, Hypothesizare" }, -- own every other badge
	},
	MULTIPLAYER_MODES = { MATCH = true, MULTIPLIED = true }, -- runs that count as "Multiplied" / multiplayer
	CURRICULUM_WINS = 30,
	TWO_MINUTES = 120, -- seconds
	WIPEOUT_SECONDS = 80, -- 1:20
	LOCKDOWN_SECONDS = 180, -- 3:00
	RAGEBAIT_GRADE = "B",
	RAGEBAIT_TRAPS = 15, -- more than this many traps in the run
	FASHION_CHASER_SKINS = 10, -- more than this many bought skins
	GOOD_NOODLES_PLAYERS = 15, -- "max amount of people": the biggest party a run can have
	PURGE_PLAYERS = 15,
	PURGE_SECONDS = 240, -- 4:00
}

-- ========== RemoteEvents (created by the server at startup) ==========
GameConfig.REMOTES_FOLDER = "BaldiRemotes"
GameConfig.REMOTE_NAMES = {
	-- client -> server
	"RequestStart",
	"UseItem",
	"SwapSlots",
	"BuyItem",
	"SilverHit", -- one successful timing hit in Silver's grab minigame
	"SilverEscape", -- "use my scissors" while grabbed
	"ChainTug", -- one mash in Chain's tug-of-war (break free)
	"ChainSnip", -- "cut the chain with my scissors" while shackled
	"BeansSnip", -- "cut the gum with my scissors" while gummed
	"GoToHub", -- leave the solo game for the multiplayer Hub (menu MULTIPLAYER button)
	"MatchReady", -- match client -> server: "I've loaded in" (drives the synced start)
	"NotebookMinigameAction", -- "hit"/"done"/"noise"/"cancel" from notebook minigames
	"StatsRequest", -- client asks for its profile + the leaderboard
	"SaveBinds", -- client persists its rebound keys
	"SaveHudLayout", -- client persists its custom mobile button layout
	"SaveSettings", -- client persists its preferences (stopwatch toggle, SFX volume)
	"BuyCosmetic", -- client buys a cosmetic by id
	"EquipCosmetic", -- client equips an owned cosmetic by id
	-- server -> client
	"GameCountdown",
	"GameStarted",
	"RoundEnded",
	"NotebookCollected",
	"PhaseChanged",
	"PlayerWon",
	"PlayerLost",
	"NickelChanged",
	"InventoryChanged",
	"PickupFailed",
	"OpenVending",
	"BuyResult",
	"SendToDetention",
	"DetentionReleased",
	"SpeedDebuff",
	"StaminaRestore",
	"SilverGrab", -- you've been grabbed: open the minigame
	"SilverReleased", -- grab over: close it
	"ChainShackled", -- Chain clamped on: open the tug-of-war popup
	"ChainReleased", -- chain broken / round end: close the popup
	"BeansGum", -- gum stuck to you: apply the slow + show the cut-free prompt
	"BeansUngum", -- gum cut/cleared early: end the slow + prompt
	"MatchLobby", -- server -> match client: loading-lobby status (players ready / expected)
	"SweptPush", -- a sweeper is carrying you: apply the push client-side
	"NotebookMinigame", -- open a notebook minigame (nil = close it)
	"StatsData", -- profile + leaderboard payload for the records page
	"RoundAnnounce", -- server-wide banner ("X started MULTIPLIED!")
	"GuyReveal", -- the mimic got you: client-side jumpscare flash
	"CosmeticResult", -- buy/equip feedback toast for the shop
	"Voiceline", -- an NPC says a line: HyperText subtitles + voice clip (CharacterConfig)
	"Exhausted", -- an EnergyDrainer-40 got you: drain stamina + slow its recharge for a while
}

-- ===================== artwork showcase =====================
-- Cycles through game art in MainMenuGui.ChalkboardBgFrame.ArtworkFrame.
-- Add/remove entries freely; creator = "" hides the credit label.
GameConfig.ARTWORK_SHOWCASE = {
	ENABLED = true,
	INTERVAL = 10, -- seconds each artwork stays up
	FADE = 0.6, -- crossfade time (out + in)
	SHUFFLE = false, -- true = random order instead of list order
	-- image ids (the decal ids 94520027435854 / 98356000566571 / 78401460691033 resolve to these)
	IMAGES = {
		{ image = "rbxassetid://81356534975532", creator = "Sol" },
		{ image = "rbxassetid://91930167929078", creator = "Sol" },
		{ image = "rbxassetid://122049669833127", creator = "Sol" },
	},
}

return GameConfig
