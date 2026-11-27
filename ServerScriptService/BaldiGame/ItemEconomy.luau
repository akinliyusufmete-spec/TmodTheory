--[[
	ItemEconomy (ModuleScript, ServerScriptService.BaldiGame.ItemEconomy)

	Server-authoritative inventory + currency:
	  - Two item slots per player; slot 1 is the active slot.
	  - Nickels: currency, picked up by walking over them (or a prompt when
	    PICKUP_PROMPT.NICKELS_WALKOVER = false), dropped by ChatRevive where a
	    player was caught, spent at vending machines.
	  - World pickups: a ProximityPrompt on each item (key / gamepad button /
	    tap or click the prompt, or click the item via a ClickDetector —
	    GameConfig.PICKUP_PROMPT). Collects if a slot is free, otherwise the
	    client gets a PickupFailed ("Inventory full").
	  - UseItem: validates slot 1 and applies the effect —
	      ZESTY -> StaminaRestore to the client (instant stamina reset)
	      BSODA -> server-stepped projectile that knocks back + stuns NPCs
	  - Vending: ProximityPrompt opens the client popup; BuyItem validates
	    nickel count and a free slot before granting.

	Your models (all optional, placeholders otherwise):
	  ReplicatedStorage/BaldiAssets/Items/Nickel
	  ReplicatedStorage/BaldiAssets/Items/BSODA            (world pickup)
	  ReplicatedStorage/BaldiAssets/Items/ZESTY            (world pickup)
	  GameConfig.BSODA_PROJECTILE.SPRAY_IMAGE  (flying spray: a tinted BillboardGui, no model)
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AssetResolver = require(script.Parent.AssetResolver)
local SoundLoader = require(game:GetService("ReplicatedStorage"):WaitForChild("BaldiShared"):WaitForChild("SoundLoader"))

local ItemEconomy = {}

function ItemEconomy.init(ctx)
	local self = {}
	local config = ctx.config
	local states = {} -- [player] = { nickels = n, slots = {id?, id?} }
	local fullFlashCooldown = {} -- [player] = next allowed "Inventory full" flash

	-- every purchasable/spawnable item id, for the ItemSpawner pads
	local itemIds = {}
	for itemId in pairs(config.ITEMS) do
		table.insert(itemIds, itemId)
	end
	table.sort(itemIds) -- deterministic order; math.random picks from it

	-- ===================== player state =====================

	local function getState(player)
		local state = states[player]
		if not state then
			state = { nickels = 0, slots = {} }
			states[player] = state
		end
		return state
	end

	local function syncInventory(player)
		local state = getState(player)
		ctx.remotes.InventoryChanged:FireClient(player, state.slots[1], state.slots[2])
	end

	local function syncNickels(player)
		ctx.remotes.NickelChanged:FireClient(player, getState(player).nickels)
	end

	function self.addNickels(player, amount)
		local state = getState(player)
		state.nickels = state.nickels + amount
		syncNickels(player)
	end

	function self.getNickels(player)
		return getState(player).nickels
	end

	local function freeSlot(state)
		if state.slots[1] == nil then
			return 1
		end
		if state.slots[2] == nil then
			return 2
		end
		return nil
	end

	local function giveItem(player, itemId)
		local state = getState(player)
		local slot = freeSlot(state)
		if not slot then
			return false
		end
		state.slots[slot] = itemId
		syncInventory(player)
		return true
	end

	-- Take a specific item from either slot (slot 1 first). Used by systems
	-- that consume items outside the normal slot-1 "use" flow, like Silver's
	-- scissors escape. Returns true if the item was found and removed.
	function self.consumeItem(player, itemId)
		local state = getState(player)
		if state.slots[1] == itemId then
			state.slots[1] = state.slots[2]
			state.slots[2] = nil
		elseif state.slots[2] == itemId then
			state.slots[2] = nil
		else
			return false
		end
		syncInventory(player)
		return true
	end

	function self.syncAll(player)
		syncInventory(player)
		syncNickels(player)
	end

	function self.forget(player)
		states[player] = nil
		fullFlashCooldown[player] = nil
	end

	-- Wipe a player's inventory + nickels for a fresh run. Called when a player
	-- enters a round so items/coins never carry over from a previous round (or
	-- a death + retry). The persistent currency (Curriculums) lives in profiles,
	-- not here, so it's untouched.
	function self.resetPlayer(player)
		states[player] = { nickels = 0, slots = {} }
		syncInventory(player)
		syncNickels(player)
	end

	-- ===================== world pickups =====================

	local function makePickupPart(name, color, size)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end

	local promptCfg = config.PICKUP_PROMPT or {}

	-- one entry point for prompt, click and walk-over collection
	local function tryCollect(player, pickup)
		if not pickup.Parent or pickup:GetAttribute("Collected") then
			return
		end
		if not (ctx.manager and ctx.manager.isRoundActive() and ctx.manager.isParticipant(player)) then
			return
		end
		if pickup:GetAttribute("IsNickel") then
			pickup:SetAttribute("Collected", true)
			pickup:Destroy()
			self.addNickels(player, 1)
			return
		end
		local itemId = pickup:GetAttribute("ItemId")
		if not itemId then
			return
		end
		if giveItem(player, itemId) then
			pickup:SetAttribute("Collected", true)
			pickup:Destroy()
		elseif (fullFlashCooldown[player] or 0) <= os.clock() then
			fullFlashCooldown[player] = os.clock() + 1.5
			ctx.remotes.PickupFailed:FireClient(player, "Inventory full")
		end
	end

	local function keyCode(name, fallback)
		local ok, code = pcall(function()
			return Enum.KeyCode[name]
		end)
		return ok and code or fallback
	end

	-- ProximityPrompt (+ optional ClickDetector) on a pickup model or part
	local function attachPickupPrompt(pickup, objectText)
		local promptParent = pickup:IsA("BasePart") and pickup
			or pickup.PrimaryPart
			or pickup:FindFirstChildWhichIsA("BasePart", true)
		if not promptParent then
			return
		end
		local distance = promptCfg.DISTANCE or 8
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PickupPrompt"
		prompt.ActionText = promptCfg.ACTION_TEXT or "Pick up"
		prompt.ObjectText = objectText
		prompt.HoldDuration = promptCfg.HOLD or 0
		prompt.MaxActivationDistance = distance
		prompt.KeyboardKeyCode = keyCode(promptCfg.KEY or "E", Enum.KeyCode.E)
		prompt.GamepadKeyCode = keyCode(promptCfg.GAMEPAD_KEY or "ButtonX", Enum.KeyCode.ButtonX)
		prompt.ClickablePrompt = true
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent
		prompt.Triggered:Connect(function(player)
			tryCollect(player, pickup)
		end)
		if promptCfg.CLICKABLE ~= false then
			local click = Instance.new("ClickDetector")
			click.Name = "PickupClick"
			click.MaxActivationDistance = distance
			click.Parent = promptParent
			click.MouseClick:Connect(function(player)
				tryCollect(player, pickup)
			end)
		end
	end

	function self.spawnNickel(position)
		local template = AssetResolver.itemTemplate("Nickel")
		local coin
		if template then
			coin = AssetResolver.preparePropClone(template)
			coin:PivotTo(CFrame.new(position + Vector3.new(0, 0.7, 0)))
		else
			coin = makePickupPart("Nickel", Color3.fromRGB(255, 210, 70), Vector3.new(0.25, 1.4, 1.4))
			coin.Shape = Enum.PartType.Cylinder
			coin.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
			local sparkle = Instance.new("PointLight")
			sparkle.Color = Color3.fromRGB(255, 220, 90)
			sparkle.Range = 5
			sparkle.Parent = coin
		end
		coin:SetAttribute("IsNickel", true)
		if promptCfg.NICKELS_WALKOVER == false then
			attachPickupPrompt(coin, "Nickel")
		end
		coin.Parent = ctx.map.pickupsFolder
	end

	function self.spawnItemPickup(itemId, position)
		local def = config.ITEMS[itemId]
		if not def then
			return
		end
		local template = AssetResolver.itemTemplate(itemId)
		local pickup
		if template then
			pickup = AssetResolver.preparePropClone(template)
			pickup:PivotTo(CFrame.new(position + Vector3.new(0, 0.7, 0)))
		else
			local color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
			if itemId == "BSODA" then
				pickup = makePickupPart("Pickup_BSODA", color, Vector3.new(2, 1.1, 1.1))
				pickup.Shape = Enum.PartType.Cylinder
				pickup.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
			else
				pickup = makePickupPart("Pickup_" .. itemId, color, Vector3.new(1.6, 0.5, 2.2))
				pickup.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0))
			end
		end
		pickup:SetAttribute("ItemId", itemId)
		attachPickupPrompt(pickup, def.displayName or itemId)
		pickup.Parent = ctx.map.pickupsFolder
	end

	-- ===================== alarm clock distraction =====================

	local distraction = nil -- { position, expiresAt }
	local alarmClock = nil -- the placed ringing prop

	-- ChatRevive polls this: a ringing alarm overrides his usual hunting.
	function self.getDistraction()
		if distraction and os.clock() < distraction.expiresAt then
			return distraction
		end
		return nil
	end

	local function stopAlarm()
		distraction = nil
		if alarmClock then
			alarmClock:Destroy()
			alarmClock = nil
		end
	end

	local function placeAlarm(position)
		stopAlarm()
		local ringSeconds = config.ALARM_CLOCK.RING_SECONDS

		local template = AssetResolver.itemTemplate("ALARM")
		local clock
		if template then
			clock = AssetResolver.preparePropClone(template)
			clock:PivotTo(CFrame.new(position + Vector3.new(0, 0.7, 0)))
		else
			clock = makePickupPart("AlarmClock", Color3.fromRGB(255, 150, 50), Vector3.new(1.2, 1.2, 0.8))
			clock.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0))
			local blink = Instance.new("PointLight")
			blink.Color = Color3.fromRGB(255, 160, 60)
			blink.Range = 8
			blink.Brightness = 2
			blink.Parent = clock
		end

		local soundParent = clock:IsA("BasePart") and clock
			or clock.PrimaryPart
			or clock:FindFirstChildWhichIsA("BasePart", true)
		if soundParent then
			local ring = SoundLoader.attach(soundParent, "AlarmRing", {
				Asset = "alarm",
				Fallback = "rbxasset://sounds/electronicpingshort.wav",
				FallbackSpeed = 1.1,
				Looped = true,
				Volume = 1,
				RollOffMaxDistance = 150,
			})
			pcall(function()
				ring:Play()
			end)
		end

		-- not a pickup: parent with the other transient props
		clock.Parent = ctx.map.projectilesFolder
		alarmClock = clock
		distraction = { position = position, expiresAt = os.clock() + ringSeconds }

		task.delay(ringSeconds, function()
			if alarmClock == clock then
				stopAlarm()
			end
		end)
	end

	function self.clearPickups()
		stopAlarm()
		ctx.map.pickupsFolder:ClearAllChildren()
	end

	function self.onRoundStart()
		self.clearPickups()
		-- shuffle a copy so each round's starter coins land in different spots
		local spots = {}
		for _, position in ipairs(ctx.map.nickelSpawns) do
			table.insert(spots, position)
		end
		for i = #spots, 2, -1 do
			local j = math.random(i)
			spots[i], spots[j] = spots[j], spots[i]
		end
		for index = 1, math.min(config.NICKELS_AT_ROUND_START, #spots) do
			self.spawnNickel(spots[index])
		end
		if config.WORLD_ITEMS_AT_ROUND_START then
			for itemId, position in pairs(ctx.map.itemSpawns) do
				self.spawnItemPickup(itemId, position)
			end
		end
		-- seed every ItemSpawner pad with a random item right away
		if #itemIds > 0 then
			for _, position in ipairs(ctx.map.itemSpawners or {}) do
				self.spawnItemPickup(itemIds[math.random(#itemIds)], position)
			end
		end
	end

	-- nickel walk-over scan (more reliable than Touched). Items are NOT
	-- collected here any more — they use the pickup prompt above.
	task.spawn(function()
		while true do
			task.wait(0.1)
			if ctx.manager and ctx.manager.isRoundActive() then
				local pickups = ctx.map.pickupsFolder:GetChildren()
				if #pickups > 0 then
					for _, player in ipairs(Players:GetPlayers()) do
						if ctx.manager.isParticipant(player) then
							local character = player.Character
							local hrp = character and character:FindFirstChild("HumanoidRootPart")
							if hrp then
								for _, pickup in ipairs(pickups) do
									if pickup.Parent
										and pickup:GetAttribute("IsNickel")
										and promptCfg.NICKELS_WALKOVER ~= false
										and (pickup:GetPivot().Position - hrp.Position).Magnitude < config.PICKUP_RADIUS then
										tryCollect(player, pickup)
									end
								end
							end
						end
					end
				end
			end
		end
	end)

	-- ===================== item spawner pads =====================
	-- Parts named "ItemSpawner" in the map (ctx.map.itemSpawners) restock
	-- themselves with a random item from GameConfig.ITEMS every INTERVAL
	-- seconds during a round — but only when nothing is already sitting
	-- there, so unclaimed items don't pile up.
	local function spawnerOccupied(position)
		for _, pickup in ipairs(ctx.map.pickupsFolder:GetChildren()) do
			if pickup.Parent and (pickup:GetPivot().Position - position).Magnitude < 4 then
				return true
			end
		end
		return false
	end

	task.spawn(function()
		while true do
			local spawnerCfg = config.ITEM_SPAWNER
			task.wait((spawnerCfg and spawnerCfg.INTERVAL) or 20)
			if spawnerCfg and spawnerCfg.ENABLED ~= false
				and ctx.manager and ctx.manager.isRoundActive()
				and #itemIds > 0 then
				for _, position in ipairs(ctx.map.itemSpawners or {}) do
					if not spawnerOccupied(position) then
						self.spawnItemPickup(itemIds[math.random(#itemIds)], position)
					end
				end
			end
		end
	end)

	-- ===================== BSODA projectile =====================

	-- The flying spray: an invisible anchored part carrying a BillboardGui of
	-- GameConfig.BSODA_PROJECTILE.SPRAY_IMAGE (white art). tint is the shooter's
	-- equipped BSODA skin's sprayColor (nil = classic blue).
	local function makeProjectileVisual(tint, cfg)
		local part = Instance.new("Part")
		part.Name = "BsodaSpray"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1

		local size = cfg.SPRAY_SIZE or 4.5
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Spray"
		billboard.Size = UDim2.fromScale(size, size)
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = false
		billboard.Adornee = part
		billboard.Parent = part

		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = cfg.SPRAY_IMAGE or ""
		image.ImageColor3 = tint or Color3.fromRGB(70, 150, 255)
		image.Parent = billboard
		return part
	end

	local function fireBsoda(player, direction)
		-- the spray only travels along X/Z: it can't be aimed up or down
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 0.01 then
			return
		end
		direction = direction.Unit
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local cfg = config.BSODA_PROJECTILE

		-- the shooter's equipped BSODA skin recolors their spray (sprayColor, else color)
		local profiles = ctx.profiles
		local tint = nil
		if profiles and profiles.getEquippedSprayColor then
			tint = profiles.getEquippedSprayColor(player, "BSODA")
		elseif profiles and profiles.getEquippedColor then
			tint = profiles.getEquippedColor(player, "BSODA")
		end
		local blast = makeProjectileVisual(tint, cfg)
		-- fixed flight height: position.Y never changes while it travels
		local position = hrp.Position + direction * 2.5 + Vector3.new(0, cfg.SPRAY_HEIGHT or 0.5, 0)
		blast:PivotTo(CFrame.new(position, position + direction))
		blast.Parent = ctx.map.projectilesFolder

		-- exclude the shooter so the blast doesn't pop on their own body
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = { ctx.map.npcFolder, ctx.map.notebooksFolder, ctx.map.pickupsFolder, ctx.map.projectilesFolder }
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer.Character then
				table.insert(excluded, otherPlayer.Character)
			end
		end
		params.FilterDescendantsInstances = excluded

		-- Walls don't stop the spray (per the wiki it travels through them); it
		-- latches onto the FIRST character in its path within HIT_RADIUS, then
		-- shoves that character along until they hit a wall or it lifespans out.
		task.spawn(function()
			local traveled = 0
			local hitNpc = nil
			while traveled < cfg.RANGE and blast.Parent do
				local dt = task.wait()
				local step = direction * cfg.SPEED * dt
				position = position + step
				traveled = traveled + step.Magnitude
				blast:PivotTo(CFrame.new(position, position + direction))
				for _, npc in pairs(ctx.npcs) do
					if npc.base and npc.base.model.Parent and not npc.base.parked then
						local toNpc = npc.base.root.Position - position
						if Vector3.new(toNpc.X, 0, toNpc.Z).Magnitude < cfg.HIT_RADIUS
							and math.abs(toNpc.Y) < (cfg.HIT_HEIGHT or 6) then
							hitNpc = npc
							break
						end
					end
				end
				if hitNpc then
					break
				end
			end

			if hitNpc then
				SoundLoader.playAt(hitNpc.base.root, {
					Fallback = "rbxasset://sounds/splat.mp3",
					Volume = 1,
				})

				-- keep the spray clinging to the caught character while it pushes
				local pushing = true
				task.spawn(function()
					while pushing and blast.Parent and hitNpc.base.root.Parent do
						local rootPos = hitNpc.base.root.Position
						local tail = Vector3.new(rootPos.X, position.Y, rootPos.Z) - direction * 1.6
						blast:PivotTo(CFrame.new(tail, tail + direction))
						task.wait()
					end
				end)
				-- params excludes every character + transient folder, so the
				-- wall-stop ray only trips on real geometry
				hitNpc.base:pushBy(direction, cfg.PUSH_SPEED or 26, cfg.PUSH_LIFETIME or 30, params)
				pushing = false
			end

			if blast.Parent then
				blast:Destroy()
			end
		end)
	end

	-- ===================== remote handlers =====================

	ctx.remotes.UseItem.OnServerEvent:Connect(function(player, direction)
		if not ctx.manager or not ctx.manager.isRoundActive() or not ctx.manager.isParticipant(player) then
			return
		end
		local state = getState(player)
		local itemId = state.slots[1]
		if not itemId then
			return
		end

		if itemId == "ZESTY" then
			-- consume, then let the client reset its stamina state
			state.slots[1] = state.slots[2]
			state.slots[2] = nil
			syncInventory(player)
			ctx.remotes.StaminaRestore:FireClient(player)
		elseif itemId == "ALARM" then
			-- drop a ringing clock at your feet; ChatRevive investigates it
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				return
			end
			state.slots[1] = state.slots[2]
			state.slots[2] = nil
			syncInventory(player)
			placeAlarm(hrp.Position + Vector3.new(0, -1.5, 0))
		elseif itemId == "SCISSORS" then
			-- only useful mid-grab (the minigame fires SilverEscape); don't
			-- waste the item on an empty snip
			ctx.remotes.PickupFailed:FireClient(player, "Scissors only work while grabbed!")
		elseif itemId == "BSODA" then
			-- validate the client-supplied aim direction
			if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 or direction ~= direction then
				return
			end
			local flat = Vector3.new(direction.X, 0, direction.Z) -- X/Z only: the spray can't be shot up or down
			if flat.Magnitude < 0.01 then
				return
			end
			state.slots[1] = state.slots[2]
			state.slots[2] = nil
			syncInventory(player)
			fireBsoda(player, flat.Unit)
		end
	end)

	ctx.remotes.SwapSlots.OnServerEvent:Connect(function(player)
		local state = getState(player)
		state.slots[1], state.slots[2] = state.slots[2], state.slots[1]
		syncInventory(player)
	end)

	-- ===================== vending machines =====================

	local function tryBuy(player, machine)
		local def = config.ITEMS[machine.itemId]
		if not def then return end
		local state = getState(player)
		if state.nickels < def.cost then
			ctx.remotes.BuyResult:FireClient(player, false,
				"Need " .. def.cost .. " Nickel" .. (def.cost == 1 and "" or "s")
					.. " (have " .. state.nickels .. ")")
			return
		end
		if not freeSlot(state) then
			ctx.remotes.BuyResult:FireClient(player, false, "Inventory full!")
			return
		end
		state.nickels = state.nickels - def.cost
		giveItem(player, machine.itemId)
		syncNickels(player)
		ctx.remotes.BuyResult:FireClient(player, true, def.displayName .. " bought!")
	end

	for _, machine in ipairs(ctx.map.vendingMachines) do
		machine.prompt.Triggered:Connect(function(player)
			if not ctx.manager or not ctx.manager.isRoundActive()
				or not ctx.manager.isParticipant(player) then
				return
			end
			tryBuy(player, machine)
		end)
	end

	ctx.economy = self
	return self
end

return ItemEconomy
