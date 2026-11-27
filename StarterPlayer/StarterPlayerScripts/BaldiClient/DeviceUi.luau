--[[
	DeviceUi (ModuleScript, StarterPlayerScripts.BaldiClient.DeviceUi)

	Makes the hand-built screens fit every device: phones, tablets, laptops,
	4K monitors and TVs, and lets a gamepad drive the menus.

	Sizing. The UI was built at REFERENCE (1691 x 1121, 1x). On any other
	screen the factor is min(width / 1691, height / 1121), clamped to
	MIN_SCALE..MAX_SCALE and recomputed when the window resizes:
	  - a pixel-sized element (an offset-only Size: menu buttons, HUD
	    counters, shop cards, keystrokes) gets a "DeviceScale" UIScale, so it
	    and everything inside it scale together
	  - an element mixing scale with big pixel parts (a full-width shop
	    section 268px tall, a label 177px from the top) has just its pixel
	    parts scaled
	  - fixed-size text outside those groups has its TextSize scaled
	  - pixel-valued modifiers outside those groups (UIStroke thickness,
	    UITextSizeConstraint limits, UIShadow blur, 9-slice SliceScale) are
	    scaled too, since scale-built screens (the HUD, the main menu) have
	    no UIScale to do it
	The design values are kept as attributes (DesignSize, DesignPosition,
	DesignTextSize, DesignThickness, DesignMinTextSize, DesignMaxTextSize,
	DesignBlurRadius, DesignSliceScale), so clones of a template are never
	scaled twice.
	Left alone: on-screen touch controls (TOUCH_CONTROLS: they keep their
	finger-sized design), anything with a KeepPixelSize attribute, Roblox's
	own screens, and the voiceline subtitles (HyperText sizes those itself).

	Previewing: set a number attribute "ForceDeviceScale" on your PlayerGui
	during a playtest (0.35 is about a phone, 0.7 a tablet) to see the
	screens at that size; clear it to go back to the real screen.

	Gamepad. While a menu or minigame has the cursor free (InputHandler's
	captureMouse), a button is kept selected so the D-pad and A work: the
	top screen's first button is picked whenever nothing usable is selected.
	Back in gameplay the selection is cleared so A jumps again.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local DeviceUi = {}

local REFERENCE = Vector2.new(1691, 1121) -- the screen size the UI was built at
local MIN_SCALE = 0.3
local MAX_SCALE = 2
local BIG_OFFSET = 40 -- pixel parts at least this big get scaled on mixed elements
local SELECT_EVERY = 0.25 -- seconds between gamepad selection checks

-- containers of on-screen touch controls: their buttons keep the design size
local TOUCH_CONTROLS = { MobileControls = true, Proxies = true, MobileTaps = true }
-- screens this never touches
local SKIP_SCREENS = { VoicelineGui = true, LoadingGui = true }

local function hasOffset(udim2)
	return udim2.X.Offset ~= 0 or udim2.Y.Offset ~= 0
end

local function hasBigOffset(udim2)
	return math.abs(udim2.X.Offset) >= BIG_OFFSET or math.abs(udim2.Y.Offset) >= BIG_OFFSET
end

local function scaleOffsets(udim2, factor)
	return UDim2.new(udim2.X.Scale, math.floor(udim2.X.Offset * factor + 0.5),
		udim2.Y.Scale, math.floor(udim2.Y.Offset * factor + 0.5))
end

-- the design value of a property, remembered on first sight (and carried by clones)
local function design(object, attribute, current)
	local value = object:GetAttribute(attribute)
	if value == nil then
		object:SetAttribute(attribute, current)
		value = current
	end
	return value
end

function DeviceUi.init(ctx)
	local fx = ctx.controllers.UiFx
	local player = ctx.player
	local playerGui = player:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	local self = {}

	-- plain tables (an Instance can drop out of a weak table while it's still
	-- on screen); entries leave when their instance is destroyed
	local deviceScales = {} -- UIScales this made
	local mixed = {} -- elements with scaled pixel parts
	local placed = {} -- pixel groups whose pixel position scales
	local texts = {} -- fixed-size text it scales
	local modifiers = {} -- pixel-valued strokes, text-size limits, shadows and 9-slices outside pixel groups

	local function track(set, object)
		if set[object] then
			return
		end
		set[object] = true
		object.Destroying:Once(function()
			set[object] = nil
		end)
	end

	local function computeFactor()
		local forced = playerGui:GetAttribute("ForceDeviceScale")
		if typeof(forced) == "number" and forced > 0 then
			return forced -- previewing another device size
		end
		local viewport = camera.ViewportSize
		if viewport.X < 2 or viewport.Y < 2 then
			return 1
		end
		return math.clamp(math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y), MIN_SCALE, MAX_SCALE)
	end
	local factor = computeFactor()

	function self.factor()
		return factor
	end

	-- ---------- applying ----------

	local function applyMixed(object)
		local size = scaleOffsets(design(object, "DesignSize", object.Size), factor)
		local position = scaleOffsets(design(object, "DesignPosition", object.Position), factor)
		object.Size = size
		object.Position = position
		if fx and fx.rebase then
			fx.rebase(object, position, size)
		end
	end

	-- a pixel group: its UIScale handles the size, only the position moves here
	local function applyPlacement(object)
		local position = scaleOffsets(design(object, "DesignPosition", object.Position), factor)
		object.Position = position
		if fx and fx.rebase then
			fx.rebase(object, position, nil)
		end
	end

	local function applyText(object)
		object.TextSize = math.max(8, math.floor(design(object, "DesignTextSize", object.TextSize) * factor + 0.5))
	end

	-- scale-built screens have no UIScale, so their pixel-valued modifiers scale here
	local function isModifier(object)
		return object:IsA("UIStroke") or object:IsA("UITextSizeConstraint") or object.ClassName == "UIShadow"
	end

	local function applyModifier(object)
		if object:IsA("UIStroke") then
			local thickness = design(object, "DesignThickness", object.Thickness)
			-- never thinner than 1px unless it was designed thinner
			object.Thickness = math.max(math.min(thickness, 1), thickness * factor)
		elseif object:IsA("UITextSizeConstraint") then
			-- Roblox caps both limits at 100
			local minSize = math.clamp(math.floor(design(object, "DesignMinTextSize", object.MinTextSize) * factor + 0.5), 1, 100)
			local maxSize = math.clamp(math.floor(design(object, "DesignMaxTextSize", object.MaxTextSize) * factor + 0.5), minSize, 100)
			object.MinTextSize = minSize
			object.MaxTextSize = maxSize
		elseif object.ClassName == "UIShadow" then
			local blur = design(object, "DesignBlurRadius", object.BlurRadius)
			object.BlurRadius = UDim.new(blur.Scale, blur.Offset * factor)
		elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
			object.SliceScale = design(object, "DesignSliceScale", object.SliceScale) * factor
		end
	end

	local function applyAll()
		for scale in pairs(deviceScales) do
			if scale.Parent then
				scale.Scale = factor
			end
		end
		for object in pairs(mixed) do
			if object.Parent then
				applyMixed(object)
			end
		end
		for object in pairs(placed) do
			if object.Parent then
				applyPlacement(object)
			end
		end
		for object in pairs(texts) do
			if object.Parent then
				applyText(object)
			end
		end
		for object in pairs(modifiers) do
			if object.Parent then
				applyModifier(object)
			end
		end
	end

	-- ---------- finding what to scale ----------

	local function insideHandled(object, screen)
		-- under a pixel group (it scales with it) or a touch-control container
		local node = object.Parent
		while node and node ~= screen do
			if TOUCH_CONTROLS[node.Name] or node:GetAttribute("KeepPixelSize") then
				return true
			end
			if node:FindFirstChild("DeviceScale") and deviceScales[node:FindFirstChild("DeviceScale")] then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local function visit(object, screen)
		if isModifier(object) then
			if not insideHandled(object, screen) then
				track(modifiers, object)
				applyModifier(object)
			end
			return
		end
		if not object:IsA("GuiObject") then
			return
		end
		if TOUCH_CONTROLS[object.Name] or object:GetAttribute("KeepPixelSize") or insideHandled(object, screen) then
			return
		end
		local size = object:GetAttribute("DesignSize") or object.Size
		if size.X.Scale == 0 and size.Y.Scale == 0 and hasOffset(size) then
			-- a pixel-built group: one UIScale scales it and everything inside
			local scale = object:FindFirstChild("DeviceScale")
			if not (scale and scale:IsA("UIScale")) then
				scale = Instance.new("UIScale")
				scale.Name = "DeviceScale"
				scale.Parent = object
			end
			scale.Scale = factor
			track(deviceScales, scale)
			if hasBigOffset(object:GetAttribute("DesignPosition") or object.Position) then
				track(placed, object) -- its pixel position moves with the screen too
				applyPlacement(object)
			end
			return
		end
		local position = object:GetAttribute("DesignPosition") or object.Position
		if (hasOffset(size) or hasOffset(position)) and (hasBigOffset(size) or hasBigOffset(position)) then
			track(mixed, object)
			applyMixed(object)
		end
		if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and not object.TextScaled then
			track(texts, object)
			applyText(object)
		end
		if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and object.ScaleType == Enum.ScaleType.Slice then
			track(modifiers, object)
			applyModifier(object)
		end
	end

	local function adopt(screen)
		if not screen:IsA("ScreenGui") or SKIP_SCREENS[screen.Name] or screen:GetAttribute("NoDeviceScale") then
			return
		end
		if not StarterGui:FindFirstChild(screen.Name) then
			return -- Roblox's own screens (touch thumbstick, chat...) aren't ours
		end
		-- top-down so a pixel group claims its contents before they're visited
		local queue = { screen }
		while #queue > 0 do
			local node = table.remove(queue, 1)
			if node ~= screen then
				visit(node, screen)
			end
			if node == screen or not (node:FindFirstChild("DeviceScale") and deviceScales[node:FindFirstChild("DeviceScale")]) then
				for _, child in ipairs(node:GetChildren()) do
					table.insert(queue, child)
				end
			end
		end
		-- things added later (cloned cards, notebook icons...)
		screen.DescendantAdded:Connect(function(object)
			task.defer(function()
				if object.Parent then
					visit(object, screen)
				end
			end)
		end)
	end

	for _, screen in ipairs(playerGui:GetChildren()) do
		adopt(screen)
	end
	playerGui.ChildAdded:Connect(adopt)

	local function refresh()
		local newFactor = computeFactor()
		if math.abs(newFactor - factor) > 0.001 then
			factor = newFactor
			applyAll()
		end
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	playerGui:GetAttributeChangedSignal("ForceDeviceScale"):Connect(refresh)

	-- ---------- gamepad menu navigation ----------

	local input = ctx.controllers.InputHandler

	local function usable(button)
		if not (button and button:IsA("GuiButton") and button.Selectable) then
			return false
		end
		if button.AbsoluteSize.X < 2 or button.AbsoluteSize.Y < 2 then
			return false
		end
		local node = button
		while node and node ~= playerGui do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			if node:IsA("LayerCollector") and not node.Enabled then
				return false
			end
			node = node.Parent
		end
		return node == playerGui
	end

	-- the first button (top to bottom, left to right) of the highest screen showing any
	local function firstButton()
		local best, bestOrder = nil, -math.huge
		for _, screen in ipairs(playerGui:GetChildren()) do
			if screen:IsA("ScreenGui") and screen.Enabled and screen.DisplayOrder >= bestOrder then
				local pick, pickY, pickX = nil, math.huge, math.huge
				for _, object in ipairs(screen:GetDescendants()) do
					if object:IsA("GuiButton") and usable(object) then
						local at = object.AbsolutePosition
						if at.Y < pickY - 2 or (math.abs(at.Y - pickY) <= 2 and at.X < pickX) then
							pick, pickY, pickX = object, at.Y, at.X
						end
					end
				end
				if pick then
					best, bestOrder = pick, screen.DisplayOrder
				end
			end
		end
		return best
	end

	local function usingGamepad()
		local last = UserInputService:GetLastInputType()
		return last.Name:find("Gamepad") ~= nil
	end

	task.spawn(function()
		while true do
			task.wait(SELECT_EVERY)
			if usingGamepad() then
				local menuOpen = input and input.isCursorFree and input.isCursorFree()
				if menuOpen then
					if not usable(GuiService.SelectedObject) then
						GuiService.SelectedObject = firstButton()
					end
				elseif GuiService.SelectedObject then
					GuiService.SelectedObject = nil -- gameplay: A jumps again
				end
			end
		end
	end)

	return self
end

return DeviceUi
