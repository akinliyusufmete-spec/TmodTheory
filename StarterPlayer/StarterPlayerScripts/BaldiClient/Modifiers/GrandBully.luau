--[[
	GrandBully (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.GrandBully)

	Grand Bully — client input for punching. While active:
	  - Left click (when not over a clickable GUI) or gamepad R2 punches,
	    through one ContextActionService action ("TmodPunch").
	  - On touch devices, StarterGui.ModifierHudGui.PunchButton is shown and
	    its Activated punches. It is hidden again when the modifier clears.

	A punch plays Modifiers.GrandBully.PunchAnim on your character and
	PunchSound at your root, then fires ModifierPunch with the camera look
	direction. The client cooldown (def.COOLDOWN) only stops spam; the server
	checks range, cone and cooldown itself and decides who gets stunned.
	Either asset may be missing: ModifierAssets warns once and that piece is
	skipped.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local GrandBully = {}

local ACTION = "TmodPunch"
local HUD_NAME = "ModifierHudGui"
local BUTTON_NAME = "PunchButton"

local active = false
local session = 0 -- bumped on every start/stop so stale background lookups do nothing
local lastPunch = -math.huge
local buttonConnection = nil
local punchButton = nil
local warnedButton = false

-- cached punch track, per character (a respawn needs a fresh load)
local trackCharacter = nil
local punchTrack = nil

local function stopTrack()
	if punchTrack then
		pcall(function()
			punchTrack:Stop(0.1)
		end)
	end
end

local function playAnimation(env, character)
	local animation = env.assets.find("GrandBully", "PunchAnim")
	if not animation or not animation:IsA("Animation") then
		return
	end
	if trackCharacter ~= character or not punchTrack then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not track then
			return
		end
		trackCharacter = character
		punchTrack = track
	end
	punchTrack:Play()
end

local function playSound(env, root)
	local sound = env.assets.find("GrandBully", "PunchSound")
	if not sound or not sound:IsA("Sound") then
		return
	end
	if root then
		local copy = sound:Clone()
		copy.Parent = root
		copy:Play()
		Debris:AddItem(copy, math.max(copy.TimeLength, 2) + 1)
	else
		SoundService:PlayLocalSound(sound)
	end
end

local function punch(env)
	if not active then
		return
	end
	local now = os.clock()
	if now - lastPunch < (env.def.COOLDOWN or 0) then
		return
	end
	local character = env.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	lastPunch = now

	pcall(playAnimation, env, character)
	pcall(playSound, env, character:FindFirstChild("HumanoidRootPart"))

	local remote = env.ctx.remotes and env.ctx.remotes.ModifierPunch
	if remote then
		local camera = env.camera
		if camera then
			remote:FireServer(camera.CFrame.LookVector)
		else
			remote:FireServer()
		end
	end
end

-- a click on a button / textbox / Active frame belongs to the UI, not a punch.
-- Plain decorative frames (Active = false) don't count, so a full-screen HUD
-- overlay doesn't swallow every click.
local function overClickableGui(env, position)
	local ok, objects = pcall(function()
		return env.playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
	end)
	if not ok or not objects then
		return false
	end
	for _, object in ipairs(objects) do
		if object.Active or object:IsA("GuiButton") or object:IsA("TextBox") then
			return true
		end
	end
	return false
end

function GrandBully.init(env)
	-- keep the touch button hidden until the modifier turns it on, even if it
	-- was left visible in Studio. Plain WaitForChild (no warning): this runs
	-- for everyone, not just players with the modifier.
	task.spawn(function()
		local hud = env.playerGui:WaitForChild(HUD_NAME, 10)
		local button = hud and hud:FindFirstChild(BUTTON_NAME)
		if button and button:IsA("GuiObject") and not active then
			button.Visible = false
		end
	end)
end

function GrandBully.start(env, _count)
	if active then
		GrandBully.stop(env)
	end
	active = true
	session += 1
	local mySession = session

	ContextActionService:BindAction(ACTION, function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and overClickableGui(env, input.Position) then
			return Enum.ContextActionResult.Pass
		end
		punch(env)
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	-- the HUD may still be arriving: look it up without blocking start
	task.spawn(function()
		local hud = env.assets.gui(env.playerGui, HUD_NAME, 5)
		if not active or session ~= mySession or not hud then
			return
		end
		local button = hud:FindFirstChild(BUTTON_NAME)
		if not button or not button:IsA("GuiButton") then
			if warnedButton then
				return
			end
			warnedButton = true
			warn("[Tmod] Modifier asset missing: StarterGui." .. HUD_NAME .. "." .. BUTTON_NAME .. " (see MODIFIER_ASSETS.md) — skipping that piece.")
			return
		end
		punchButton = button
		button.Visible = UserInputService.TouchEnabled
		buttonConnection = button.Activated:Connect(function()
			punch(env)
		end)
	end)
end

function GrandBully.stop(_env)
	active = false
	session += 1
	ContextActionService:UnbindAction(ACTION)
	if buttonConnection then
		buttonConnection:Disconnect()
		buttonConnection = nil
	end
	if punchButton then
		punchButton.Visible = false
		punchButton = nil
	end
	stopTrack()
	punchTrack = nil
	trackCharacter = nil
end

return GrandBully
