--[[
	DoorService (ModuleScript, ServerScriptService.BaldiGame.DoorService)

	Makes the schoolhouse's non-collidable, decal-animated doors block NPC line of
	SIGHT while closed and let it through while open — WITHOUT touching collision,
	so the navmesh still routes through every doorway and NPCs walk through freely.

	The one fact that makes this work: Roblox raycasts hit a part based on its
	CanQuery property, NOT CanCollide. A non-collidable door is still "seen" by the
	NPC sight rays (NpcBase:canSee / walkableLine) as long as CanQuery is true. So a
	door blocks sight exactly when CanQuery is on.

	This service keeps each tagged door's CanQuery in sync with an "Open" attribute:
		door:SetAttribute("Open", true)   -> CanQuery OFF -> rays pass   (open)
		door:SetAttribute("Open", false)  -> CanQuery ON  -> rays blocked (closed)

	SETUP (in Studio):
	  1. Tag the door PANEL — the moving/decal part that should hide the view when
	     shut (NOT the frame; the frame is a wall and should always block) — with
	     the CollectionService tag "BaldiDoor". A door made of several parts can be
	     a Model with the tag on the Model; every BasePart under it is synced.
	  2. In your open/close animation, set the door's "Open" attribute true/false.
	     That's all — the NPC sight system already respects CanQuery.

	Doors start CLOSED (blocking) until something sets Open = true.
]]

local CollectionService = game:GetService("CollectionService")

local DOOR_TAG = "BaldiDoor"

local DoorService = {}

-- Toggle CanQuery on the door instance and any BaseParts under it. CanCollide is
-- never touched, so pathfinding through the doorway is unaffected.
local function setQueryable(door, queryable)
	if door:IsA("BasePart") then
		door.CanQuery = queryable
	end
	for _, descendant in ipairs(door:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = queryable
		end
	end
end

-- Open => rays pass (not queryable). Closed (false/nil) => rays blocked (queryable).
local function sync(door)
	setQueryable(door, not door:GetAttribute("Open"))
end

local function track(door)
	sync(door) -- apply current state (defaults to closed/blocking)
	door:GetAttributeChangedSignal("Open"):Connect(function()
		sync(door)
	end)
end

function DoorService.init(ctx)
	for _, door in ipairs(CollectionService:GetTagged(DOOR_TAG)) do
		track(door)
	end
	CollectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(track)
	ctx.doors = DoorService
	return DoorService
end

return DoorService
