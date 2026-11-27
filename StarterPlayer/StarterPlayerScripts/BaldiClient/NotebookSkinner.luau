--[[
	NotebookSkinner (ModuleScript, StarterPlayerScripts.BaldiClient.NotebookSkinner)

	Applies the local player's equipped NOTEBOOK cosmetic to the notebooks in
	the world. The server tags every spawned notebook "BaldiNotebook" and tints
	it by its TYPE color (red/blue/green/purple) via ImageColor3 — we only swap
	the ImageLabel's *image*, never its color, so the "which minigame" cue is
	preserved and the skin art reads in the type color.

	Skinning is client-side and per-player: each player sees their own notebook
	skin on the same shared notebooks. Placeholder notebooks (plain parts, no
	ImageLabel) simply have nothing to skin, which is fine.

	The original image is remembered on each label (BaldiBaseImage attribute) so
	un-equipping a skin restores the stock look.

	It also runs the notebooks' spin/bob locally (the server only places them):
	BobPhase offsets each one, BobSpeed > 1 is Guy's too-fast wobble.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local NotebookSkinner = {}

local TAG = "BaldiNotebook"

function NotebookSkinner.init(ctx)
	local cosmetics = ctx.controllers.CosmeticState
	local tracked = {} -- [notebook] = { connections }
	local bobbing = {} -- [notebook] = { base = CFrame, phase = number, speed = number }

	local function skinLabel(label)
		if not label:IsA("ImageLabel") then
			return
		end
		-- remember the model's stock image once, so we can restore it
		if label:GetAttribute("BaldiBaseImage") == nil then
			label:SetAttribute("BaldiBaseImage", label.Image)
		end
		local skinImage = cosmetics and cosmetics.getImage("NOTEBOOK")
		label.Image = (skinImage and skinImage ~= "" and skinImage)
			or label:GetAttribute("BaldiBaseImage")
	end

	local function skinNotebook(notebook)
		for _, descendant in ipairs(notebook:GetDescendants()) do
			skinLabel(descendant)
		end
	end

	local function track(notebook)
		if tracked[notebook] then
			return
		end
		-- late-replicating ImageLabels still get skinned
		tracked[notebook] = { notebook.DescendantAdded:Connect(skinLabel) }
		skinNotebook(notebook)
		if notebook:IsA("PVInstance") then
			bobbing[notebook] = {
				base = notebook:GetPivot(), -- the server never moves it after placing
				phase = tonumber(notebook:GetAttribute("BobPhase")) or math.random() * math.pi * 2,
				speed = tonumber(notebook:GetAttribute("BobSpeed")) or 1,
			}
		end
	end

	local function untrack(notebook)
		local conns = tracked[notebook]
		if conns then
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			tracked[notebook] = nil
		end
		bobbing[notebook] = nil
	end

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for notebook, info in pairs(bobbing) do
			if notebook.Parent then
				local t = now * info.speed
				local yaw = CFrame.Angles(0, t * 1.6 + info.phase, 0)
				local bob = Vector3.new(0, math.sin(t * 2 + info.phase) * 0.2, 0)
				notebook:PivotTo(info.base * yaw + bob)
			else
				bobbing[notebook] = nil
			end
		end
	end)

	for _, notebook in ipairs(CollectionService:GetTagged(TAG)) do
		track(notebook)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

	-- re-skin every live notebook when the player equips a different one
	if cosmetics then
		cosmetics.onChanged(function()
			for notebook in pairs(tracked) do
				skinNotebook(notebook)
			end
		end)
	end

	return {}
end

return NotebookSkinner
