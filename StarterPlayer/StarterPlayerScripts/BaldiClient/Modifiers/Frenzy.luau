--[[
	Frenzy (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.Frenzy)

	Client half of the Frenzy modifier: the wide-angle "everything is too
	fast" camera. The speed itself is server-side (ModSpeedMult, applied by
	StaminaController).

	  start  sets LocalPlayer attribute ModFov = def.FOV (so other code can
	         tell the run wants a different base FOV) and tweens the camera's
	         FieldOfView to it
	  step   keeps it there: if anything else resets the FOV (MenuController
	         writes 70 when it hands the camera back to the game) it is put
	         back. No other gameplay controller tweens the FOV, so the rule is
	         simply "def.FOV every frame", with two exceptions: while our own
	         start tween runs, and while the camera is Scriptable (a menu /
	         cutscene shot owns the camera and its FOV then)
	  stop   clears ModFov and restores the FOV from before start (70 if the
	         camera was in a scripted shot at the time)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Frenzy = {}

local DEFAULT_FOV = 70 -- the game's normal FOV (MenuController uses it too)
local TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local active = false
local previousFov = DEFAULT_FOV
local tween = nil
local tweenCamera = nil

local function cancelTween()
	if tween then
		tween:Cancel()
		tween = nil
	end
	tweenCamera = nil
end

local function cameraIsOurs(camera)
	return camera ~= nil and camera.CameraType ~= Enum.CameraType.Scriptable
end

function Frenzy.start(env)
	cancelTween()
	active = true
	local fov = env.def.FOV or DEFAULT_FOV
	Players.LocalPlayer:SetAttribute("ModFov", fov)

	local camera = workspace.CurrentCamera
	if cameraIsOurs(camera) then
		previousFov = camera.FieldOfView
		tweenCamera = camera
		local myTween = TweenService:Create(camera, TWEEN, { FieldOfView = fov })
		tween = myTween
		myTween.Completed:Connect(function()
			-- Completed also fires on Cancel (maybe deferred): only clear
			-- the state if it still belongs to this tween
			if tween == myTween then
				tween = nil
				tweenCamera = nil
			end
		end)
		myTween:Play()
	else
		previousFov = DEFAULT_FOV
	end
end

function Frenzy.step(env, _dt)
	if not active then
		return
	end
	local camera = workspace.CurrentCamera
	if not cameraIsOurs(camera) then
		return
	end
	if tween and tweenCamera == camera then
		return -- our own ease-in is still running
	end
	local fov = env.def.FOV or DEFAULT_FOV
	if math.abs(camera.FieldOfView - fov) > 0.01 then
		camera.FieldOfView = fov
	end
end

function Frenzy.stop(_env)
	cancelTween()
	if not active then
		return
	end
	active = false
	Players.LocalPlayer:SetAttribute("ModFov", nil)
	local camera = workspace.CurrentCamera
	if cameraIsOurs(camera) then
		camera.FieldOfView = previousFov
	end
	previousFov = DEFAULT_FOV
end

return Frenzy
