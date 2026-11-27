--[[
	KeystrokesController (ModuleScript, StarterPlayerScripts.BaldiClient.KeystrokesController)

	Shows the player's keystrokes during a run (StarterGui.KeystrokeGui) —
	computers only (needs a keyboard + mouse). Each key box lights up and dips
	while its key is held:
	  KeyStrokeForward / Backward / Left / Right   W S A D (and the arrow keys)
	  KeyStrokeSpecial1                            your USE key
	  KeyStrokeSpecial2                            your SWAP key
	  KeyStrokeSprint                              your SPRINT key
	The Special / Sprint labels follow the player's rebinds.

	The whole panel rides on an EzUISprings 2D spring
	(ReplicatedStorage.EzUISprings), so it sways as you turn, strafe and jump
	and gets a small kick on every press. The library's 2D camera effect reads
	raw world-space camera movement, which would fling the panel on teleports
	and ignores turning, so it is handed a proxy "camera" whose CFrame we drive
	from the real camera's turn + camera-relative movement, clamped per frame.
	(The library's 3D SurfaceGui mode doesn't render in this place.)
	MenuController calls setActive(true/false) as rounds start and end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KeystrokesController = {}

local PRESSED_BG = Color3.fromRGB(0, 255, 255)
local PRESSED_TEXT = Color3.fromRGB(15, 20, 25)

-- sway tuning (proxy-camera units; the library multiplies by 5 into pixels)
local TURN_SWAY = 90      -- per radian of turn
local MOVE_SWAY = 4       -- per stud of strafe / vertical movement
local MAX_STEP = 4        -- clamp per frame, so snaps can't fling the panel
local TELEPORT_STUDS = 4  -- camera jumps bigger than this in one frame are ignored
local PRESS_KICK = Vector3.new(0, 30, 0) -- ~5px dip per key press

-- short, readable names for long KeyCodes
local SHORT = {
	LeftShift = "Shift", RightShift = "Shift", LeftControl = "Ctrl", RightControl = "Ctrl",
	LeftAlt = "Alt", RightAlt = "Alt", Space = "Space", Return = "Enter", Backspace = "Bksp",
	CapsLock = "Caps", Tab = "Tab",
}

function KeystrokesController.init(ctx)
	local fx = ctx.controllers.UiFx
	local input = ctx.controllers.InputHandler
	local self = { active = false }

	local isComputer = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
	local gui = fx.gui("KeystrokeGui")
	gui.Enabled = false
	local main = gui:WaitForChild("MainFrame")

	local EzUISprings = nil
	pcall(function()
		EzUISprings = require(ReplicatedStorage:WaitForChild("EzUISprings", 5))
	end)

	-- box name -> { frame, label, idle colours }
	local boxes = {}
	local function box(name)
		if boxes[name] then
			return boxes[name]
		end
		local frame = main:FindFirstChild(name)
		if not frame then
			return nil
		end
		local label = frame:FindFirstChildWhichIsA("TextLabel")
		local scale = frame:FindFirstChild("KeyScale") or Instance.new("UIScale")
		scale.Name = "KeyScale"
		scale.Parent = frame
		local entry = {
			frame = frame,
			label = label,
			scale = scale,
			bg = frame.BackgroundColor3,
			bgT = frame.BackgroundTransparency,
			text = label and label.TextColor3,
			held = 0,
		}
		boxes[name] = entry
		return entry
	end

	local function shortName(keyName)
		return SHORT[keyName] or keyName
	end

	local function refreshLabels()
		for name, action in pairs({ KeyStrokeSpecial1 = "USE", KeyStrokeSpecial2 = "SWAP", KeyStrokeSprint = "SPRINT" }) do
			local entry = box(name)
			if entry and entry.label then
				entry.label.Text = shortName(input.getKeyName(action))
			end
		end
	end
	refreshLabels()
	input.onBindsChanged(refreshLabels)

	local MOVE_KEYS = {
		[Enum.KeyCode.W] = "KeyStrokeForward", [Enum.KeyCode.Up] = "KeyStrokeForward",
		[Enum.KeyCode.S] = "KeyStrokeBackward", [Enum.KeyCode.Down] = "KeyStrokeBackward",
		[Enum.KeyCode.A] = "KeyStrokeLeft", [Enum.KeyCode.Left] = "KeyStrokeLeft",
		[Enum.KeyCode.D] = "KeyStrokeRight", [Enum.KeyCode.Right] = "KeyStrokeRight",
	}

	-- which box a key lights (movement keys first, then the rebindable actions)
	local function boxFor(keyCode)
		if MOVE_KEYS[keyCode] then
			return MOVE_KEYS[keyCode]
		end
		local name = keyCode.Name
		if name == input.getKeyName("USE") then
			return "KeyStrokeSpecial1"
		elseif name == input.getKeyName("SWAP") then
			return "KeyStrokeSpecial2"
		elseif name == input.getKeyName("SPRINT") or (input.getKeyName("SPRINT") == "LeftShift" and name == "RightShift") then
			return "KeyStrokeSprint"
		end
		return nil
	end

	local spring = nil
	local proxyCamera = { CFrame = CFrame.new() }
	local SWAY_BIND = "KeystrokeSway"

	local function lookAngles(cf)
		local look = cf.LookVector
		return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
	end

	local function startSway()
		local camera = workspace.CurrentCamera
		local lastCF = camera.CFrame
		local lastYaw, lastPitch = lookAngles(lastCF)
		local virtual = Vector3.zero
		proxyCamera.CFrame = CFrame.new(virtual)
		RunService:BindToRenderStep(SWAY_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			local cf = workspace.CurrentCamera.CFrame
			local yaw, pitch = lookAngles(cf)
			local dYaw = (yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
			local dPitch = pitch - lastPitch
			local moved = cf.Position - lastCF.Position
			local localMove = moved.Magnitude <= TELEPORT_STUDS and cf:VectorToObjectSpace(moved) or Vector3.zero
			lastCF, lastYaw, lastPitch = cf, yaw, pitch

			-- the panel lags behind: turn/strafe right -> it drifts left, look/jump up -> it dips
			local step = Vector3.new(dYaw * TURN_SWAY - localMove.X * MOVE_SWAY, dPitch * TURN_SWAY + localMove.Y * MOVE_SWAY, 0)
			if step.Magnitude > MAX_STEP then
				step = step.Unit * MAX_STEP
			end
			virtual += step
			proxyCamera.CFrame = CFrame.new(virtual)
		end)
	end

	local function stopSway()
		pcall(function()
			RunService:UnbindFromRenderStep(SWAY_BIND)
		end)
	end

	local function setPressed(entry, pressed)
		if pressed then
			fx.tween(entry.frame, 0.06, { BackgroundColor3 = PRESSED_BG, BackgroundTransparency = math.min(entry.bgT, 0.25) })
			if entry.label then
				fx.tween(entry.label, 0.06, { TextColor3 = PRESSED_TEXT })
			end
			fx.tween(entry.scale, 0.06, { Scale = 0.88 })
			if spring then
				spring:Shove(PRESS_KICK)
			end
		else
			fx.tween(entry.frame, 0.15, { BackgroundColor3 = entry.bg, BackgroundTransparency = entry.bgT })
			if entry.label then
				fx.tween(entry.label, 0.15, { TextColor3 = entry.text })
			end
			fx.tween(entry.scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end

	UserInputService.InputBegan:Connect(function(key)
		if not self.active or key.UserInputType ~= Enum.UserInputType.Keyboard or UserInputService:GetFocusedTextBox() then
			return
		end
		local entry = box(boxFor(key.KeyCode) or "")
		if entry then
			entry.held += 1
			if entry.held == 1 then
				setPressed(entry, true)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(key)
		if key.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local entry = box(boxFor(key.KeyCode) or "")
		if entry and entry.held > 0 then
			entry.held -= 1
			if entry.held == 0 then
				setPressed(entry, false)
			end
		end
	end)

	local function releaseAll()
		for _, entry in pairs(boxes) do
			entry.held = 0
			entry.frame.BackgroundColor3 = entry.bg
			entry.frame.BackgroundTransparency = entry.bgT
			entry.scale.Scale = 1
			if entry.label then
				entry.label.TextColor3 = entry.text
			end
		end
	end

	-- on during a run, off in menus; never on touch-only devices
	function self.setActive(active)
		active = active and isComputer
		if active == self.active then
			return
		end
		self.active = active
		releaseAll()
		if active then
			gui.Enabled = true
			if EzUISprings then
				startSway()
				local ok, result = pcall(function()
					local params = EzUISprings.newSpringParams2D({ CameraIntensity = 1, Camera = proxyCamera })
					local object = EzUISprings.new2D(main, params)
					object:Apply2DSpringEffect()
					return object
				end)
				if ok then
					spring = result
				else
					stopSway()
					warn("[Keystrokes] EzUISprings failed, showing the panel without sway: " .. tostring(result))
				end
			end
		else
			stopSway()
			if spring then
				pcall(function()
					spring:Destroy() -- puts MainFrame back at its designed Position
				end)
				spring = nil
			end
			gui.Enabled = false
		end
	end

	return self
end

return KeystrokesController
