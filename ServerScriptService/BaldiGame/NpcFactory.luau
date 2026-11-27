--[[
	NpcFactory (ModuleScript, ServerScriptService.BaldiGame.NpcFactory)

	Produces the character models the AIs drive.

	If you made a rig (ReplicatedStorage/BaldiAssets/Npcs/<Name>, any rig
	type, must contain a Humanoid + HumanoidRootPart, optional Animations
	folder) it is cloned and prepared. Otherwise a simple placeholder rig
	is built in code so the game runs before your characters exist.
]]

local AssetResolver = require(script.Parent.AssetResolver)

local NpcFactory = {}

-- Body parts the humanoid actually stands and collides with. Anything else in a
-- custom rig (accessory handles, hair, chains, props) is decoration.
local CORE_PARTS = {
	HumanoidRootPart = true,
	Torso = true, Head = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	UpperTorso = true, LowerTorso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

-- Decoration should never weigh the rig down, snag on doorways, or eat
-- physics/raycast time (the Chain rig alone carries 130+ chain links).
local function slimDecoration(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanTouch = false
			if not (part.Parent == model and CORE_PARTS[part.Name]) then
				part.CanCollide = false
				part.CanQuery = false
				part.Massless = true
			end
		end
	end
end

-- Hand-made mesh rigs can't stand as R6: R6 standing relies on parts named
-- "Left Leg" / "Right Leg", so they sink or hang in Freefall. Such a rig is
-- switched to R15 standing, whose HipHeight (bottom of the root -> floor) is
-- measured from the rig's rest pose, so its feet land on the floor. Only the
-- root collides afterwards (limbs swinging through a door frame would snag).
-- An invisible root also gets a standard character's size and height:
-- pathfinding can't route from a point more than ~4 studs off the floor, and
-- an oversized root snags on door frames. The joints on it are shifted to
-- match, so nothing visible moves. Set your own HipHeight on an R15 rig to
-- skip all of this.
local FITTED_ROOT_SIZE = Vector3.new(2, 2, 1)
local FITTED_ROOT_HEIGHT = 3 -- root centre above the floor

local function fitCustomRig(model, humanoid, root)
	if model:FindFirstChild("Left Leg") and model:FindFirstChild("Right Leg") then
		return -- a standard R6 body stands fine
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight > 0 then
		return
	end
	local lowest = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root and part.Transparency < 1 then
			local cf, half = part.CFrame, part.Size / 2
			local reach = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			lowest = math.min(lowest, cf.Position.Y - reach)
		end
	end
	if lowest == math.huge then
		return
	end
	if root.Transparency >= 0.99 then
		local drop = (root.Position.Y - lowest) - FITTED_ROOT_HEIGHT
		local shift = CFrame.new(root.CFrame:VectorToObjectSpace(Vector3.new(0, drop, 0)))
		for _, joint in ipairs(model:GetDescendants()) do
			if joint:IsA("JointInstance") then
				if joint.Part0 == root then
					joint.C0 = shift * joint.C0
				elseif joint.Part1 == root then
					joint.C1 = shift * joint.C1
				end
			end
		end
		root.Size = FITTED_ROOT_SIZE
		root.CFrame = root.CFrame - Vector3.new(0, drop, 0)
	end
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = math.max(0, (root.Position.Y - root.Size.Y / 2) - lowest)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = part == root
		end
	end
	model:SetAttribute("BaldiFittedRig", true)
end

-- ===================== placeholder rig =====================

local function makeBodyPart(name, size, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = transparency or 0
	return part
end

local function joinParts(part0, part1, offset, jointName)
	-- Position part1 relative to part0, then join with a Motor6D named per
	-- the standard R6 convention so humanoid physics behaves normally.
	part1.CFrame = part0.CFrame * offset
	local motor = Instance.new("Motor6D")
	motor.Name = jointName or "Weld"
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = offset
	motor.Parent = part0
	return motor
end

local function buildPlaceholderRig(spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model:SetAttribute("BaldiPlaceholderRig", true)

	local hrp = makeBodyPart("HumanoidRootPart", Vector3.new(2, 2, 1), spec.bodyColor, 1)
	hrp.CanCollide = false
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.Parent = model

	local torso = makeBodyPart("Torso", Vector3.new(2, 2, 1), spec.bodyColor, spec.transparency)
	torso.Parent = model
	joinParts(hrp, torso, CFrame.new(0, 0, 0), "RootJoint")

	local head = makeBodyPart("Head", Vector3.new(1.4, 1.4, 1.4), spec.headColor, spec.transparency)
	head.Shape = Enum.PartType.Ball
	head.Parent = model
	joinParts(torso, head, CFrame.new(0, 1.7, 0), "Neck")

	local leftLeg = makeBodyPart("Left Leg", Vector3.new(1, 2, 1), spec.bodyColor, spec.transparency)
	leftLeg.Parent = model
	joinParts(torso, leftLeg, CFrame.new(-0.5, -2, 0), "Left Hip")
	local rightLeg = makeBodyPart("Right Leg", Vector3.new(1, 2, 1), spec.bodyColor, spec.transparency)
	rightLeg.Parent = model
	joinParts(torso, rightLeg, CFrame.new(0.5, -2, 0), "Right Hip")

	local leftArm = makeBodyPart("Left Arm", Vector3.new(1, 2, 1), spec.bodyColor, spec.transparency)
	leftArm.CanCollide = false
	leftArm.Parent = model
	joinParts(torso, leftArm, CFrame.new(-1.5, 0, 0), "Left Shoulder")
	local rightArm = makeBodyPart("Right Arm", Vector3.new(1, 2, 1), spec.bodyColor, spec.transparency)
	rightArm.CanCollide = false
	rightArm.Parent = model
	joinParts(torso, rightArm, CFrame.new(1.5, 0, 0), "Right Shoulder")

	-- simple face so the head has a "front"
	local face = makeBodyPart("FaceMark", Vector3.new(0.5, 0.3, 0.2), Color3.new(0, 0, 0), spec.transparency)
	face.CanCollide = false
	face.CanQuery = false
	face.Parent = model
	joinParts(head, face, CFrame.new(0, 0.15, -0.65))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model

	if spec.glowColor then
		local glow = Instance.new("PointLight")
		glow.Color = spec.glowColor
		glow.Range = 9
		glow.Brightness = 1.2
		glow.Parent = torso
	end

	model.PrimaryPart = hrp
	return model
end

-- ===================== shared preparation =====================

local function addNameTag(model, spec)
	-- only when the rig doesn't already carry its own name display
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			return
		end
	end
	local target = model:FindFirstChild("Head") or model.PrimaryPart
	if not target then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 130, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Parent = target
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.Cartoon
	tag.TextScaled = true
	tag.TextColor3 = spec.tagColor or Color3.new(1, 1, 1)
	tag.TextStrokeTransparency = 0.2
	tag.Text = spec.name
	tag.Parent = billboard
end

-- spec = { name, bodyColor, headColor, transparency?, glowColor?, tagColor? }
-- (the color fields style the placeholder only; your rig is used as-is)
function NpcFactory.create(spec, parent)
	local template = AssetResolver.npcTemplate(spec.name)
	local model
	if template then
		model = template:Clone()
		model.Name = spec.name
		for _, descendant in ipairs(model:GetDescendants()) do
			-- never run scripts that came bundled with an imported asset, and
			-- drop the Animation Editor's saves (they'd replicate to every client)
			if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
				descendant:Destroy()
			elseif descendant.Name == "AnimSaves" and descendant.Parent == model then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = false
			end
		end
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
		slimDecoration(model)
		fitCustomRig(model, model:FindFirstChildOfClass("Humanoid"), model.PrimaryPart)
	else
		model = buildPlaceholderRig(spec)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.WalkSpeed = 0
	-- a usable jump lets pathfinding clear small thresholds/lips and lets the
	-- NPC hop free when it wedges on geometry (see NpcBase:unstickNudge)
	pcall(function()
		humanoid.UseJumpPower = true
	end)
	humanoid.JumpPower = 35
	pcall(function()
		humanoid.JumpHeight = 5
	end)
	humanoid.MaxHealth = 100000
	humanoid.Health = humanoid.MaxHealth
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = true
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayName = spec.name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	addNameTag(model, spec)

	-- stream each character to clients whole (body, joints and Animator
	-- together), never part by part: the client animator needs the full rig
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	-- keep NPCs out of the player collision group
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "BaldiNpc"
		end
	end

	model.Parent = parent

	-- BSODA knockback should shove, not ragdoll
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	return model
end

return NpcFactory
