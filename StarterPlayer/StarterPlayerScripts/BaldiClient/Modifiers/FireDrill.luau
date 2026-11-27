--[[
	FireDrill (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.FireDrill)

	Client half of the Fire Drill modifier: alarms, red lights, shaking
	halls, and the countdown. The time limit itself is server-side: the
	server sets workspace attribute FireDrillEndsAt (GetServerTimeNow scale)
	while the drill runs and ends the run at 0:00.

	  Red lights  every PostEffect in BaldiAssets.Modifiers.FireDrill is
	              cloned into Lighting. The values YOU set on it are the "on"
	              look; each frame the clone eases between neutral and those
	              values, one full pulse per def.PULSE_PERIOD seconds.
	              Neutral: ColorCorrection TintColor white and Brightness /
	              Contrast / Saturation 0, Bloom / SunRays Intensity 0, Blur
	              Size 0, DepthOfField Near/FarIntensity 0. Any other
	              PostEffect blinks (Enabled on for the upper half of the
	              pulse). Atmosphere / Sky clones just stay as they are.
	  Siren       Modifiers.FireDrill.Siren (Sound) is cloned into
	              SoundService and played (Looped as you set it; volume scaled
	              by the player's SFX slider). The original is never touched.
	  Shake       camera pass (CAMERA_ORDER 10, before See Moon's mirror):
	              smooth math.noise offset of about def.SHAKE_STUDS at
	              def.SHAKE_SPEED.
	  Countdown   OPTIONAL label StarterGui.ModifierHudGui.FireDrillTimer
	              (TextLabel, anywhere inside ModifierHudGui) shows "M:SS",
	              in red under def.WARN_SECONDS. Its own Text / colour /
	              Visible are put back on stop. Without that label the time
	              left is announced with HudController.banner at 2:00, 1:00,
	              0:30 and 0:10 instead.

	stop destroys every clone, stops the siren and restores the label.
]]

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local FireDrill = {}

FireDrill.CAMERA_ORDER = 10

local RED = Color3.fromRGB(255, 70, 60)
local TIMER_LABEL = "FireDrillTimer"
local FALLBACK_MARKS = { 120, 60, 30, 10 } -- banner announcements without a label

-- the "off" value of each property that pulses
local NEUTRAL = {
	ColorCorrectionEffect = {
		TintColor = Color3.new(1, 1, 1),
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
	},
	BloomEffect = { Intensity = 0 },
	SunRaysEffect = { Intensity = 0 },
	BlurEffect = { Size = 0 },
	DepthOfFieldEffect = { FarIntensity = 0, NearIntensity = 0 },
}

local token = 0 -- bumps on every start / stop so a late label lookup gives up
local clones = {}
local pulses = {} -- { instance, props = { [name] = { neutral, on } } } or { instance, blink = true }
local siren = nil
local startedAt = 0

local timer = nil -- { label, text, color, visible } while we drive the label
local hasLabel = false -- the label lookup finished and found one
local lastShown = nil -- whole seconds last written / announced
local announced = {} -- [mark] = true
local startBanner = false

local function lerp(a, b, alpha)
	if typeof(a) == "Color3" then
		return a:Lerp(b, alpha)
	end
	return a + (b - a) * alpha
end

local function formatTime(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function setupPulses()
	pulses = {}
	for _, clone in ipairs(clones) do
		if clone:IsA("PostEffect") then
			local neutral = NEUTRAL[clone.ClassName]
			if neutral then
				local props = {}
				for name, off in pairs(neutral) do
					props[name] = { neutral = off, on = clone[name] }
				end
				table.insert(pulses, { instance = clone, props = props })
			elseif clone.Enabled then
				table.insert(pulses, { instance = clone, blink = true })
			end
		end
	end
end

local function restoreLabel()
	if timer then
		local saved = timer
		timer = nil
		pcall(function()
			saved.label.Text = saved.text
			saved.label.TextColor3 = saved.color
			saved.label.Visible = saved.visible
		end)
	end
	hasLabel = false
end

-- find the optional timer label without ever yielding the frame step
local function findLabel(env, myToken)
	task.spawn(function()
		local gui = env.assets.gui(env.playerGui, "ModifierHudGui", 5)
		if myToken ~= token then
			return
		end
		local label = gui and gui:FindFirstChild(TIMER_LABEL, true)
		if label and label:IsA("TextLabel") then
			timer = {
				label = label,
				text = label.Text,
				color = label.TextColor3,
				visible = label.Visible,
			}
			hasLabel = true
			label.Visible = false -- shown once the end time is known
			lastShown = nil
		end
	end)
end

function FireDrill.stop(_env)
	token += 1
	for _, clone in ipairs(clones) do
		clone:Destroy()
	end
	clones = {}
	pulses = {}
	if siren then
		pcall(function()
			siren:Stop()
		end)
		siren:Destroy()
		siren = nil
	end
	restoreLabel()
	lastShown = nil
	announced = {}
	startBanner = false
end

function FireDrill.start(env)
	FireDrill.stop(env)
	local myToken = token
	startedAt = os.clock()

	clones = env.assets.cloneEffects("FireDrill", Lighting)
	setupPulses()

	local original = env.assets.find("FireDrill", "Siren")
	if original and original:IsA("Sound") then
		siren = original:Clone()
		siren.Name = "Modifier_FireDrill_Siren"
		local sounds = env.ctx.controllers.SoundController
		local master = sounds and sounds.getMasterVolume and sounds.getMasterVolume() or 1
		siren.Volume = original.Volume * master
		siren.Parent = SoundService
		siren:Play()
	elseif original then
		warn("[Tmod] Modifiers.FireDrill.Siren should be a Sound, it is a " .. original.ClassName)
	end

	findLabel(env, myToken)
end

local function updatePulse(def)
	local period = math.max(0.05, def.PULSE_PERIOD or 1)
	-- 0 at the start of each pulse, 1 halfway, eased like a sine
	local alpha = 0.5 - 0.5 * math.cos((os.clock() - startedAt) / period * 2 * math.pi)
	for _, pulse in ipairs(pulses) do
		local instance = pulse.instance
		if pulse.blink then
			instance.Enabled = alpha >= 0.5
		else
			for name, values in pairs(pulse.props) do
				instance[name] = lerp(values.neutral, values.on, alpha)
			end
		end
	end
end

local function updateTimer(env)
	local def = env.def
	local endsAt = workspace:GetAttribute("FireDrillEndsAt")
	if type(endsAt) ~= "number" then
		if timer then
			timer.label.Visible = false
		end
		return
	end
	local remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
	local whole = math.ceil(remaining)
	if whole == lastShown then
		return
	end
	local firstShow = lastShown == nil
	lastShown = whole

	local hud = env.ctx.controllers.HudController
	local warnAt = def.WARN_SECONDS or 30
	local red = remaining < warnAt

	if not startBanner and hud and hud.banner then
		startBanner = true
		hud.banner("FIRE DRILL! " .. formatTime(whole) .. " to escape!", RED)
	end

	if timer then
		local label = timer.label
		label.Visible = true
		label.Text = formatTime(whole)
		label.TextColor3 = red and RED or timer.color
	elseif not hasLabel and hud and hud.banner and not firstShow then
		-- no label (yet): announce the marks we pass instead
		for _, mark in ipairs(FALLBACK_MARKS) do
			if whole <= mark and not announced[mark] then
				announced[mark] = true
				if whole == mark then
					hud.banner(formatTime(mark) .. " left!", mark < warnAt and RED or nil)
				end
			end
		end
	end
end

function FireDrill.step(env, _dt)
	updatePulse(env.def)
	updateTimer(env)
end

function FireDrill.camera(env, cf, _dt)
	local def = env.def
	local strength = def.SHAKE_STUDS or 0.12
	local t = os.clock() * (def.SHAKE_SPEED or 18)
	-- math.noise stays mostly within +-0.5, so x2 makes the peak about SHAKE_STUDS;
	-- non-integer seeds because noise is 0 at integer coordinates
	local offset = Vector3.new(
		math.noise(t, 0.31, 0.17),
		math.noise(0.73, t, 2.41),
		math.noise(4.17, 1.93, t)
	) * (strength * 2)
	return cf * CFrame.new(offset)
end

return FireDrill
