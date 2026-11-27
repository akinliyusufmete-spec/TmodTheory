--[[
	CharacterConfig (ModuleScript, ReplicatedStorage.BaldiShared.CharacterConfig)

	One entry per character, keyed by the character's name (the rig name under
	BaldiAssets/Npcs, same as GameConfig.NPC.<X>.NAME). Every field is
	optional: anything you leave out falls back to CharacterConfig.Defaults.

	  DisplayName       name shown above the subtitle (defaults to the key)

	  Voicelines        what the character says, grouped by moment. Each moment
	                    is a list; a line is a plain string, or a table when it
	                    also has a voice clip and/or a one-shot animation:
	                      "Get back here!"
	                      { Text = "Get back here!", Sound = "rbxassetid://123", Animation = "Point" }
	                    (Animation names one of this character's Animations below.)
	                    Moments every chaser uses:
	                      Spotted   starts chasing someone
	                      Chasing   now and then mid-chase
	                      Lost      gives up a chase
	                      Caught    catches someone
	                      Stunned   hit by a BSODA
	                      Idle      now and then while wandering
	                    Character-specific moments are noted on each entry.

	  TextColor         main colour of the subtitle text
	  TextAltColor      second colour: the text blends TextColor (top) -> TextAltColor (bottom)
	  TextOutlineColor  outline colour
	  TextEffect        how the text appears: HyperText markups (ReplicatedStorage.Packages.HyperText,
	                    every markup + attribute is listed at github.com/lopjoss/HyperText).
	                    Each key is a markup; give it a value, or { value, attribute = ... }:
	                      interval = 0.03                    seconds between letters (typewriter speed)
	                      anim = false                       no entrance animation (plain typewriter)
	                      anim = { "slide", dur = .3, dir = "down", offset = .6, rot = 0 }
	                      anim = { "bounce", dur = .5 }      anim = { "grow", dur = .35, startScale = 0 }
	                      anim = { "wiggle", loop = true, freq = 1.5, amp = .15 }
	                      shake = { true, loop = true, maxOffset = .03, maxRot = 3, freq = 20 }
	                      decode = { true, dur = .25 }       letters scramble, then lock in
	                      trans = { 0, tweenDur = .3 }       letters fade in
	                      rainbow = true   shiny = true   fog = true   shadow = true
	                      soundId = { "rbxassetid://123", volume = .4 }   typewriter blip per letter
	                      size = 40                          px (default: fits the subtitle box)
	                    A line can also style single words with the same tags, e.g.
	                      "Get back <shake=true loop=true>HERE</shake>!"

	  Animations        AnimationLoader ids by name. Idle / Walk / Chase drive movement;
	                    Walk plays faster or slower with the character's speed (WalkAnimSpeed).
	                    Leave one out (or "") to use the rig's own Animations folder entry;
	                    false = skip the rig's entry too (no Chase: Walk covers the chase).
	                    Any other name is an action the AI plays (LP's Rulebreak, Silver's
	                    Caught, Frosty's TrapSetup) or a voiceline emote (Taunt = "rbxassetid://...").
	                    An action can be a table instead of a plain id:
	                      { Id = "rbxassetid://...", Loop = true }   loops the whole animation
	                      { Id = ..., LoopStart = "Marker", LoopEnd = "Marker" }
	                          repeats the stretch between two animation event markers while
	                          the action lasts (no LoopEnd: from LoopStart to the end)
	                      Finish = true   once the action ends, play on to the end of the
	                                      animation instead of fading it out
	                      Cycle = true    the AI restarts it each beat (ChatRevive's Dash:
	                                      once per slap) instead of it playing on its own

	  WalkAnimSpeed     studs/second at which Walk plays at normal speed; faster movement
	                    speeds it up, slower movement slows it down

	  Sounds            SoundLoader ids for this character's sounds. Blank = AssetConfig's
	                    id, then the built-in default. Names used: ChatRevive.Chase,
	                    LP.Whistle, Guy.Scream, Sportage.Trap, the sweepers' Sweep.

	  Pathfinding       SimplePath agent overrides for this character: AgentRadius,
	                    AgentHeight, AgentCanJump, AgentJumpHeight, WaypointSpacing,
	                    Costs, Visualize (true = draw the route as dots; debug only)

	CharacterConfig.Settings (bottom of the file) tunes how often characters
	talk, how far a line carries and how long it stays on screen. Its Enabled
	switch turns voicelines off entirely (set it back to true to bring them back).
]]

local CharacterConfig = {}

CharacterConfig.Defaults = {
	Voicelines = {},
	TextColor = Color3.fromRGB(255, 255, 255),
	TextAltColor = Color3.fromRGB(205, 205, 205),
	TextOutlineColor = Color3.fromRGB(20, 20, 20),
	TextEffect = { interval = 0.03, anim = { "slide", dir = "down", offset = 0.5, rot = 0, dur = 0.25 } },
	Animations = {},
	WalkAnimSpeed = 16,
	Sounds = {},
	Pathfinding = {},
}

-- Placeholder lines: replace them with your own.
CharacterConfig.Characters = {
	ChatRevive = {
		Voicelines = {
			Spotted = { "THERE YOU ARE.", "Found you!", "Class isn't OVER YET!!!" },
			Chasing = { "You can't run forever..!", "I'll see you in MY OFFICE.", "GET BACK HERE." },
			Lost = { "Where did you.. Huh?", "You can hide but you can't RUN...!" },
			Caught = { "You're coming with me to DETENTION.", "Finally got you." },
			Stunned = { "wuh, YOU CAN'T DO THAT", "Thats UNFAIIIIIRRR", "Oh COME ON!!!!!" },
			Idle = { "find my 4 modstats......", "So quiet in here...", "Hello student" },
		},
		TextColor = Color3.fromRGB(255, 207, 19),
		TextAltColor = Color3.fromRGB(254, 255, 252),
		TextOutlineColor = Color3.fromRGB(0, 0, 0),
		TextEffect = { interval = 0.025, anim = false, shake = { true, loop = true, maxOffset = 0.025, maxRot = 3, freq = 20 } },
		Animations = {
			Idle = "",
			-- one animation for all his movement
			Walk = "rbxassetid://120653382731254",
			Chase = "rbxassetid://120653382731254",
			-- his Baldi slap: plays once per slap, and he dashes on its
			-- "DashAttack" event marker (GameConfig.NPC.CHATREVIVE)
			Dash = { Id = "rbxassetid://120653382731254", Cycle = true },
		},
		Sounds = { Chase = "" }, -- the slap (blank = AssetConfig.SOUNDS.chase)
	},

	LP = {
		Voicelines = {
			Spotted = { "No running in the halls.", "You'll be coming to my office.", "You just broke a rule!" },
			Chasing = { "Get back here right NOW!" },
			Lost = { "I'll see you at exit." },
			Caught = { "You'll be spending time at my office today.", "Rules are for everyone!" }, -- LP's catch = detention
			Stunned = { "Okay you're getting double detention now", "You just made it worser for you.. why??" },
			Idle = { "Hello student", "Having a good time at here?" },
		},
		TextColor = Color3.fromRGB(255, 253, 242),
		TextAltColor = Color3.fromRGB(41, 42, 44),
		TextOutlineColor = Color3.fromRGB(0, 0, 0),
		TextEffect = { interval = 0.035, anim = false },
		Animations = {
			Idle = "rbxassetid://122979130651895",
			Walk = "rbxassetid://88938251443324",
			Chase = false, -- Walk speeds up for the chase
			-- plays over his walk while he chases a rule breaker, until he catches them
			Rulebreak = { Id = "rbxassetid://137441824121955", Loop = true },
		},
		Sounds = { Whistle = "" }, -- blank = AssetConfig.SOUNDS.whistle
	},

	-- extra moment: Grab (Silver grabs someone)
	Silver = {
		Voicelines = {
			Spotted = { "Lets play!!", "A friend I can play with!!" },
			Chasing = { "I want to play!!" },
			Lost = { "You got no taste in games dude.." },
			Grab = { "LETS PLAY!!", "HOORAAYY!!" },
			Stunned = { "you could've said so!?!?", "why so rude??" },
			Idle = { "Shiny..." },
		},
		TextColor = Color3.fromRGB(225, 230, 240),
		TextAltColor = Color3.fromRGB(140, 150, 170),
		TextOutlineColor = Color3.fromRGB(30, 30, 40),
		TextEffect = { interval = 0.04, anim = false },
		Animations = {
			Idle = "rbxassetid://117373045641451",
			Walk = "rbxassetid://115590313575383",
			Chase = false,
			-- holding the player he caught: repeats LoopStart -> end until they escape
			Caught = { Id = "rbxassetid://93041413465853", LoopStart = "LoopStart" },
		},
	},

	-- extra moment: Freeze (someone steps in his SlowMachiner 3000)
	Frosty = {
		Voicelines = {
			Freeze = { "CHILLS🥶🥶🥶", "brosty got FROZEN🥶🥶🥶", "clear out the halls!!!" },
			Stunned = { "nah im gonna freeze you next time" },
			Idle = { "yo.", "Stay frosty with brosty🥶🥶🥶." },
		},
		TextColor = Color3.fromRGB(123, 242, 255),
		TextAltColor = Color3.fromRGB(0, 103, 255),
		TextOutlineColor = Color3.fromRGB(8, 28, 40),
		TextEffect = { interval = 0.04, anim = { "grow", dur = 0.35, startScale = 0.3 } },
		Animations = {
			Idle = "rbxassetid://118330450379610",
			Walk = "rbxassetid://100785552491363",
			Chase = false,
			-- setting up a trap: repeats TrapSetupStart -> TrapSetupLoopEnd until the
			-- trap is done (a random time, GameConfig.NPC.FROSTY), then plays to the end
			TrapSetup = { Id = "rbxassetid://91171409422561", LoopStart = "TrapSetupStart", LoopEnd = "TrapSetupLoopEnd", Finish = true },
		},
	},

	-- extra moment: Shackle (Chain clamps onto someone)
	Chain = {
		Voicelines = {
			Spotted = { "I see you..!", "You cant escape from me!" },
			Chasing = { "COME HERE!!" },
			Lost = { "Where did you go?" },
			Shackle = { "YOU CAN'T RUN NOW!!", "You're mine now." },
			Stunned = { "aw shucks" },
			Idle = { "*rattle*" },
		},
		TextColor = Color3.fromRGB(219, 3, 209),
		TextAltColor = Color3.fromRGB(113, 0, 139),
		TextOutlineColor = Color3.fromRGB(0, 0, 0),
		TextEffect = { interval = 0.02, anim = false, decode = { true, dur = 0.2 } },
	},

	-- extra moment: Gum (Beans' gum sticks to someone)
	Beans = {
		Voicelines = {
			Gum = { "*spits*", "hehehehehehhehe" },
			Stunned = { "OW!!!", "WHY DID YOU DO THAT??????" },
			Idle = { "chin", "want gum?", "yo", "how you doing?" },
		},
		TextColor = Color3.fromRGB(255, 150, 205),
		TextAltColor = Color3.fromRGB(255, 225, 240),
		TextOutlineColor = Color3.fromRGB(90, 20, 60),
		TextEffect = { interval = 0.035, anim = { "grow", dur = 0.3, startScale = 0 } },
	},

	-- extra moment: Reveal (the fake notebook turns out to be Guy).
	-- No Idle lines on purpose: he'd give his disguise away.
	Guy = {
		Voicelines = {
			Reveal = { "You won't escape.", "Sorry for you... I have your data.", "You think an Antivirus will delete me?" },
			Stunned = { "HOW DID YOU EVEN STUN ME??", "okay thats impossible what" },
		},
		TextColor = Color3.fromRGB(173, 49, 255),
		TextAltColor = Color3.fromRGB(128, 1, 176),
		TextOutlineColor = Color3.fromRGB(255, 255, 255),
		TextEffect = { interval = 0.02, anim = false, decode = { true, dur = 0.3 } },
		Sounds = { Scream = "" }, -- blank = AssetConfig.SOUNDS.guy
	},

	-- extra moment: Trap (someone steps on one of Sportage's traps)
	Sportage = {
		Voicelines = {
			Spotted = { "I knew it!" },
			Chasing = { "Heads up!" },
			Lost = { "Out of bounds..." },
			Caught = { "Game over!" },
			Trap = { "Snap! I heard that." },
			Stunned = { "Foul!" },
			Idle = { "Listening..." },
		},
		TextColor = Color3.fromRGB(255, 175, 60),
		TextAltColor = Color3.fromRGB(255, 235, 150),
		TextOutlineColor = Color3.fromRGB(70, 30, 0),
		TextEffect = { interval = 0.035, anim = { "slide", dir = "down", offset = 0.6, rot = 0, dur = 0.25 } },
		Sounds = { Trap = "" },
	},

	-- the sweepers. Extra moment: Sweep (starts a sweep run)
	Guidelines = {
		Voicelines = {
			Sweep = { "*sweep.wav*", "###########" },
		},
		TextColor = Color3.fromRGB(252, 241, 241),
		TextAltColor = Color3.fromRGB(206, 0, 15),
		TextOutlineColor = Color3.fromRGB(64, 3, 0),
		TextEffect = { interval = 0.03, anim = { "slide", dir = "down", offset = 0.6, rot = 0, dur = 0.2 } },
		Sounds = { Sweep = "" }, -- blank = AssetConfig.SOUNDS.sweep
	},
	Sai = {
		Voicelines = {
			Sweep = { "out of MY WAY!!", "CLEAR OUT THE HALLS!!", "COMING THROUGH!!" },
		},
		TextColor = Color3.fromRGB(255, 247, 240),
		TextAltColor = Color3.fromRGB(191, 190, 190),
		TextOutlineColor = Color3.fromRGB(0, 0, 0),
		TextEffect = { interval = 0.03, anim = { "slide", dir = "down", offset = 0.6, rot = 0, dur = 0.2 } },
		Sounds = { Sweep = "" },
	},
}

-- How characters talk (read by VoicelineService on the server and
-- VoicelineController on the client).
CharacterConfig.Settings = {
	Enabled = false, -- false = characters say nothing: no subtitles, voice clips or line emotes (NPC sounds like the slap still play)
	HearDistance = 70, -- studs: farther players don't get the line (the player a line is aimed at always does)
	Cooldown = 4, -- seconds between any two lines from the same character
	GlobalCooldown = 1.5, -- seconds between lines from different characters (big forced moments ignore it)
	MomentGaps = { Idle = 22, Chasing = 9, Lost = 6, Stunned = 3, Sweep = 12 }, -- extra minimum gap per moment
	Chance = { Idle = 0.5, Chasing = 0.6 }, -- chance a moment actually produces a line
	StartQuiet = { Idle = true, Sweep = true }, -- these wait out (part of) their gap before the first line, so a round doesn't open with everyone talking
	HoldBase = 1.4, -- seconds a finished line stays up...
	HoldPerLetter = 0.045, -- ...plus this much per letter...
	HoldMax = 5, -- ...capped here

	-- subtitle text style (HyperText); per-character extras go in TextEffect
	Font = "rbxasset://fonts/families/Kalam.json",
	FontWeight = Enum.FontWeight.Bold,
	TextScale = 0.5, -- text size as a fraction of the subtitle box height (unless TextEffect sets size); long lines shrink to fit
	OutlineThickness = 0.08, -- outline width, relative to the letter size
	FadeOut = 0.3, -- seconds a finished line takes to fade away
}

local resolved = {}

-- The full config for one character, with every missing field filled in
-- from Defaults. Treat the result as read-only (it's shared).
function CharacterConfig.get(name)
	local cached = resolved[name]
	if cached then
		return cached
	end
	local entry = CharacterConfig.Characters[name] or {}
	local merged = {}
	for key, value in pairs(CharacterConfig.Defaults) do
		merged[key] = value
	end
	for key, value in pairs(entry) do
		merged[key] = value
	end
	merged.Name = name
	merged.DisplayName = entry.DisplayName or name
	resolved[name] = merged
	return merged
end

return CharacterConfig
