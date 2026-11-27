--[[
	ModifierClient (ModuleScript, StarterPlayerScripts.BaldiClient.ModifierClient)

	Runs every in-run visual / input effect of the Modifiers system. Reacts to
	workspace.ActiveModifiers (JSON stacks, set by the server's ModifierService)
	being set or cleared, and makes sure everything a modifier changed is put
	back when it clears. Effects only run while the local player is IN that
	run (LocalPlayer attribute InModifiedRun), never on the menu.

	Feature modules: every ModuleScript in BaldiClient/Modifiers named after a
	modifier id (ModifierConfig.ORDER) is that modifier's client behaviour. A
	feature returns a table with any of:
	  init(env)                 once, when this controller starts
	  start(env, count)         the modifier became active
	  stop(env)                 it cleared: restore EVERYTHING it changed
	  step(env, dt)             every frame while active (RenderStepped)
	  camera(env, cframe, dt) -> cframe
	                            camera pass while active: transform the camera
	                            CFrame and return it. Runs once per frame at
	                            RenderPriority.Camera + 1 in ascending
	                            CAMERA_ORDER (shake 10, then mirror 20). The
	                            untouched CFrame is put back at the start of the
	                            next frame so the camera scripts never read a
	                            transformed camera.
	  CAMERA_ORDER = number     (optional, default 50)
	env = { ctx, player, playerGui, camera (current at call time), id, def,
	        config (ModifierConfig), assets (ModifierAssets), count, core = self }

	Public (for other controllers):
	  has(id), count(id), stacks(), isActive()
	  Changed:Connect(fn(stacks|nil))   fired after every start/clear
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local ModifierConfig = require(shared:WaitForChild("ModifierConfig"))
local ModifierAssets = require(shared:WaitForChild("ModifierAssets"))

local ModifierClient = {}

local CAMERA_BIND = "TmodModifierCamera"
local RESTORE_BIND = "TmodModifierCameraRestore"

function ModifierClient.init(ctx)
	local self = {}
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local changedEvent = Instance.new("BindableEvent")
	self.Changed = changedEvent.Event

	local current = nil -- stacks { [id] = count }
	local running = {} -- [id] = true while started

	-- ---------- feature modules ----------

	local features = {}
	local envs = {}
	local folder = script.Parent:FindFirstChild("Modifiers")
	for _, id in ipairs(ModifierConfig.ORDER) do
		local moduleScript = folder and folder:FindFirstChild(id)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, result = pcall(require, moduleScript)
			if ok and type(result) == "table" then
				features[id] = result
				envs[id] = setmetatable({
					ctx = ctx,
					player = player,
					playerGui = playerGui,
					id = id,
					def = ModifierConfig.LIST[id],
					config = ModifierConfig,
					assets = ModifierAssets,
					count = 0,
					core = self,
				}, {
					-- env.camera is always the live CurrentCamera
					__index = function(_, key)
						if key == "camera" then
							return workspace.CurrentCamera
						end
						return nil
					end,
				})
			else
				warn("[Tmod] Client modifier " .. id .. " failed to load: " .. tostring(result))
			end
		end
	end

	local function call(id, fnName, ...)
		local feature = features[id]
		local fn = feature and feature[fnName]
		if type(fn) ~= "function" then
			return nil
		end
		local ok, result = pcall(fn, envs[id], ...)
		if not ok then
			warn("[Tmod] Client modifier " .. id .. "." .. fnName .. " failed: " .. tostring(result))
			return nil
		end
		return result
	end

	-- ---------- queries ----------

	function self.isActive()
		return current ~= nil
	end

	function self.has(id)
		return current ~= nil and (current[id] or 0) > 0
	end

	function self.count(id)
		return (current and current[id]) or 0
	end

	function self.stacks()
		return current
	end

	-- ---------- per-frame passes ----------

	local cameraOrder = {} -- ids with a camera(), sorted by CAMERA_ORDER
	local savedCFrame = nil
	local bound = false

	local function rebuildCameraOrder()
		cameraOrder = {}
		for id in pairs(running) do
			if type(features[id].camera) == "function" then
				table.insert(cameraOrder, id)
			end
		end
		table.sort(cameraOrder, function(a, b)
			local oa = features[a].CAMERA_ORDER or 50
			local ob = features[b].CAMERA_ORDER or 50
			if oa == ob then
				return a < b
			end
			return oa < ob
		end)
	end

	local function cameraPass(dt)
		local camera = workspace.CurrentCamera
		if not camera or #cameraOrder == 0 then
			return
		end
		local original = camera.CFrame
		local cf = original
		for _, id in ipairs(cameraOrder) do
			local result = call(id, "camera", cf, dt)
			if typeof(result) == "CFrame" then
				cf = result
			end
		end
		if cf ~= original then
			savedCFrame = original
			camera.CFrame = cf
		end
	end

	local function restorePass()
		local camera = workspace.CurrentCamera
		if savedCFrame and camera then
			camera.CFrame = savedCFrame
		end
		savedCFrame = nil
	end

	local stepConnection = nil

	local function bind()
		if bound then
			return
		end
		bound = true
		RunService:BindToRenderStep(RESTORE_BIND, Enum.RenderPriority.First.Value, restorePass)
		RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, cameraPass)
		stepConnection = RunService.RenderStepped:Connect(function(dt)
			for id in pairs(running) do
				if features[id].step then
					call(id, "step", dt)
				end
			end
		end)
	end

	local function unbind()
		if not bound then
			return
		end
		bound = false
		pcall(function()
			RunService:UnbindFromRenderStep(CAMERA_BIND)
			RunService:UnbindFromRenderStep(RESTORE_BIND)
		end)
		if stepConnection then
			stepConnection:Disconnect()
			stepConnection = nil
		end
		restorePass()
	end

	-- ---------- start / clear ----------

	local function stopAll()
		for id in pairs(running) do
			call(id, "stop")
			envs[id].count = 0
		end
		running = {}
		cameraOrder = {}
		unbind()
	end

	local function apply(stacks)
		stopAll()
		current = stacks
		if stacks then
			for _, id in ipairs(ModifierConfig.ORDER) do
				local count = stacks[id]
				if count and count > 0 and features[id] then
					envs[id].count = count
					running[id] = true
					call(id, "start", count)
				end
			end
			rebuildCameraOrder()
			if next(running) then
				bind()
			end
		end
		changedEvent:Fire(current)
	end

	local function readAttribute()
		if player:GetAttribute("InModifiedRun") ~= true then
			return nil
		end
		local raw = workspace:GetAttribute("ActiveModifiers")
		if type(raw) ~= "string" or raw == "" then
			return nil
		end
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or type(decoded) ~= "table" then
			return nil
		end
		local stacks = {}
		for id, count in pairs(decoded) do
			if ModifierConfig.LIST[id] and type(count) == "number" and count > 0 then
				stacks[id] = count
			end
		end
		return next(stacks) and stacks or nil
	end

	for id in pairs(features) do
		call(id, "init")
	end

	-- only restart features when the effective stacks actually change
	local lastRaw = nil
	local function refresh()
		local stacks = readAttribute()
		local raw = stacks and HttpService:JSONEncode(stacks) or nil
		if raw == lastRaw then
			return
		end
		lastRaw = raw
		apply(stacks)
	end

	workspace:GetAttributeChangedSignal("ActiveModifiers"):Connect(refresh)
	player:GetAttributeChangedSignal("InModifiedRun"):Connect(refresh)
	task.defer(refresh) -- joined mid-run

	return self
end

return ModifierClient
