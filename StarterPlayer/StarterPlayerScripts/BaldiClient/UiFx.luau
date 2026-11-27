--[[
	UiFx (ModuleScript, StarterPlayerScripts.BaldiClient.UiFx)

	Shared UI plumbing + animations for the hand-built StarterGui screens.

	  gui(name)            the PlayerGui copy of a StarterGui ScreenGui
	  setButtonColor(b, c) swap a glossy button plate: "green" | "cyan" | "red"
	  transition(work, preloadRoot?)
	                       black wipe in from the right (linear), run `work`
	                       while the screen is covered (waiting for images under
	                       preloadRoot to load), then wipe out to the left at the
	                       same speed. Serialized: overlapping calls queue.
	  flashbang()          screen goes fully white for a beat, then fades out
	  slideIn(obj, from)   obj eases in from off-screen ("bottom"/"top"/"left"/"right")
	  easeInFromSides(list) each item eases in from the nearest screen side, staggered
	  dropIn(obj)          obj drops in from above with a bounce; returns the tween
	  pop(obj, delay)      obj scales up from small with a little overshoot
	  openBook(parts)      covers + blank pages open like a book, then onOpened()

	Original positions/sizes are captured the first time an object animates, so
	an interrupted animation never leaves it drifted.
]]

local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local UiFx = {}

local WIPE_SECONDS = 0.3
local MAX_PRELOAD_SECONDS = 1.5

UiFx.BUTTON = {
	green = "rbxassetid://97733941449709",
	cyan = "rbxassetid://137658229766739",
	red = "rbxassetid://89182990213313",
}

function UiFx.init(ctx)
	local self = {}
	local playerGui = ctx.player:WaitForChild("PlayerGui")

	local originPos = setmetatable({}, { __mode = "k" })
	local originSize = setmetatable({}, { __mode = "k" })

	function self.gui(name)
		return playerGui:WaitForChild(name)
	end

	function self.setButtonColor(button, color)
		if button and button:IsA("ImageButton") then
			button.Image = UiFx.BUTTON[color] or button.Image
		end
	end

	function self.tween(instance, seconds, props, style, direction, delay)
		local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out, 0, false, delay or 0), props)
		tween:Play()
		return tween
	end
	local tween = self.tween

	function self.origin(obj)
		if originPos[obj] == nil then
			originPos[obj] = obj.Position
		end
		return originPos[obj]
	end

	function self.originSize(obj)
		if originSize[obj] == nil then
			originSize[obj] = obj.Size
		end
		return originSize[obj]
	end

	-- DeviceUi resized something for the screen: animations return there now
	function self.rebase(obj, position, size)
		if position and originPos[obj] ~= nil then
			originPos[obj] = position
		end
		if size and originSize[obj] ~= nil then
			originSize[obj] = size
		end
	end

	-- ===================== black wipe =====================

	local wipe = self.gui("TransitionGui"):WaitForChild("Wipe")
	wipe.Position = UDim2.fromScale(1, 0)
	local busy = false

	local function preload(root)
		if not root then
			return
		end
		local list = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" and not d.IsLoaded then
				table.insert(list, d)
			end
		end
		if #list == 0 then
			return
		end
		local done = false
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(list)
			end)
			done = true
		end)
		local deadline = os.clock() + MAX_PRELOAD_SECONDS
		while not done and os.clock() < deadline do
			task.wait()
		end
	end

	function self.isTransitioning()
		return busy
	end

	function self.transition(work, preloadRoot)
		while busy do
			task.wait()
		end
		busy = true
		wipe.Position = UDim2.fromScale(1, 0)
		tween(wipe, WIPE_SECONDS, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Linear).Completed:Wait()
		local ok, err = pcall(work)
		if not ok then
			warn("[UiFx] transition work failed: " .. tostring(err))
		end
		preload(preloadRoot)
		task.wait(0.06)
		tween(wipe, WIPE_SECONDS, { Position = UDim2.fromScale(-1, 0) }, Enum.EasingStyle.Linear).Completed:Wait()
		wipe.Position = UDim2.fromScale(1, 0)
		busy = false
	end

	-- ===================== flashbang =====================

	local flash = self.gui("FlashGui"):WaitForChild("Flash")
	flash.BackgroundTransparency = 1
	local flashToken = 0

	function self.flashbang()
		flashToken += 1
		local token = flashToken
		flash.BackgroundTransparency = 0
		task.delay(0.12, function()
			if token == flashToken then
				tween(flash, 0.65, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)
	end

	-- ===================== movement =====================

	local OFFSETS = {
		bottom = UDim2.fromScale(0, 1.25),
		top = UDim2.fromScale(0, -1.25),
		left = UDim2.fromScale(-1.1, 0),
		right = UDim2.fromScale(1.1, 0),
	}

	function self.slideIn(obj, from, seconds, delay)
		local home = self.origin(obj)
		obj.Position = home + (OFFSETS[from] or OFFSETS.bottom)
		return tween(obj, seconds or 0.5, { Position = home }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
	end

	-- items left of centre come from the left edge, the rest from the right
	function self.easeInFromSides(items, seconds, stagger, baseDelay)
		local camera = workspace.CurrentCamera
		local width = camera and camera.ViewportSize.X or 1920
		for index, obj in ipairs(items) do
			local home = self.origin(obj)
			local centreX = home.X.Scale + home.X.Offset / width
			local side = centreX < 0.5 and OFFSETS.left or OFFSETS.right
			obj.Position = home + side
			tween(obj, seconds or 0.65, { Position = home }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out,
				(baseDelay or 0) + (index - 1) * (stagger or 0.06))
		end
	end

	function self.dropIn(obj, seconds)
		local home = self.origin(obj)
		obj.Position = home - UDim2.fromScale(0, 1.05)
		return tween(obj, seconds or 0.8, { Position = home }, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	end

	function self.pop(obj, delay)
		-- a pixel group already sized for the screen (DeviceUi's DeviceScale)
		-- pops through that same UIScale and settles back at the screen size;
		-- an object can only have one UIScale doing the work
		local scale = obj:FindFirstChild("DeviceScale")
		local rest = 1
		if scale and scale:IsA("UIScale") then
			local device = ctx.controllers.DeviceUi
			rest = device and device.factor() or 1
		else
			scale = obj:FindFirstChild("FxScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "FxScale"
				scale.Parent = obj
			end
		end
		scale.Scale = 0.35 * rest
		if delay and delay > 0 then
			-- stay hidden until it's this item's turn
			obj.Visible = false
			task.delay(delay, function()
				obj.Visible = true
				tween(scale, 0.38, { Scale = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end)
			return nil
		end
		obj.Visible = true
		return tween(scale, 0.38, { Scale = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- quick side-to-side jolt for a miss / wrong answer (always ends at home)
	function self.shake(obj, magnitude)
		local home = self.origin(obj)
		magnitude = magnitude or 8
		task.spawn(function()
			for i = 1, 4 do
				obj.Position = home + UDim2.fromOffset(i % 2 == 0 and magnitude or -magnitude, 0)
				task.wait(0.04)
			end
			obj.Position = home
		end)
	end

	-- fade a frame (and its plain Frame children, e.g. a wood border) in from clear
	function self.fadeIn(root, seconds)
		local targets = { root }
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(targets, child)
			end
		end
		for _, obj in ipairs(targets) do
			local goal = obj:GetAttribute("FxBackground")
			if goal == nil then
				goal = obj.BackgroundTransparency
				obj:SetAttribute("FxBackground", goal)
			end
			obj.BackgroundTransparency = 1
			tween(obj, seconds or 0.25, { BackgroundTransparency = goal })
		end
	end

	-- ===================== the settings book =====================
	-- parts = { leftCover, rightCover, frontCover, sheet, leftPage, rightPage,
	--           sheetCount?, onOpened() }
	-- Pages are expected to be scale-positioned, either side of the spine.

	local bookToken = 0

	function self.cancelBook()
		bookToken += 1
	end

	function self.openBook(parts)
		bookToken += 1
		local token = bookToken
		local leftCover, frontCover, sheet = parts.leftCover, parts.frontCover, parts.sheet
		local leftPage, rightPage = parts.leftPage, parts.rightPage
		local coverSize = self.originSize(leftCover)
		local frontSize = self.originSize(frontCover)
		local pageSize = self.originSize(rightPage)
		local closedCover = UDim2.new(0, 0, coverSize.Y.Scale, coverSize.Y.Offset)
		local flatPage = UDim2.new(0, 0, pageSize.Y.Scale, pageSize.Y.Offset)

		-- spine-side page edges, from the pages' own layout
		local rightPos, leftPos = self.origin(rightPage), self.origin(leftPage)
		local rightEdge = rightPos.X.Scale - pageSize.X.Scale * rightPage.AnchorPoint.X
		local leftEdge = leftPos.X.Scale + pageSize.X.Scale * (1 - leftPage.AnchorPoint.X)
		local pageY = rightPos.Y

		-- closed: only the right half of the book, front cover on top
		leftCover.Size = closedCover
		leftPage.Visible = false
		sheet.Visible = false
		frontCover.ClipsDescendants = true
		frontCover.Size = frontSize
		frontCover.Visible = true

		local function step(t)
			t.Completed:Wait()
			return token == bookToken
		end

		task.spawn(function()
			task.wait(parts.delay or 0.08)
			if token ~= bookToken then
				return
			end
			-- the front cover swings up toward you...
			if not step(tween(frontCover, 0.28, { Size = UDim2.new(0, 0, frontSize.Y.Scale, frontSize.Y.Offset) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)) then
				return
			end
			frontCover.Visible = false
			-- ...and lands on the left
			if not step(tween(leftCover, 0.28, { Size = coverSize }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)) then
				return
			end
			-- a few blank pages flip across
			for index = 1, parts.sheetCount or 2 do
				sheet.AnchorPoint = Vector2.new(0, 0.5)
				sheet.Position = UDim2.new(rightEdge, 0, pageY.Scale, pageY.Offset)
				sheet.Size = pageSize
				sheet.Visible = true
				if not step(tween(sheet, 0.17, { Size = flatPage }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)) then
					return
				end
				sheet.AnchorPoint = Vector2.new(1, 0.5)
				sheet.Position = UDim2.new(leftEdge, 0, pageY.Scale, pageY.Offset)
				if not step(tween(sheet, 0.17, { Size = pageSize }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)) then
					return
				end
				if index == 1 then
					leftPage.Visible = true -- the first page to land becomes the left page
				end
			end
			sheet.Visible = false
			if parts.onOpened then
				parts.onOpened()
			end
		end)
	end

	-- Turn one leaf of an open book. parts = { sheet, from = { left, right },
	-- to = { left, right }, onLanded() }. Forward flips right-to-left, backward
	-- left-to-right; the page under the leaf swaps first, the far page on landing.
	function self.turnPage(parts, forward)
		bookToken += 1
		local token = bookToken
		local sheet, from, to = parts.sheet, parts.from, parts.to
		local pageSize = self.originSize(from.right)
		local flatPage = UDim2.new(0, 0, pageSize.Y.Scale, pageSize.Y.Offset)
		local rightPos, leftPos = self.origin(from.right), self.origin(from.left)
		local rightEdge = rightPos.X.Scale - pageSize.X.Scale * from.right.AnchorPoint.X
		local leftEdge = leftPos.X.Scale + pageSize.X.Scale * (1 - from.left.AnchorPoint.X)
		local pageY = rightPos.Y
		local startAnchor, startX = Vector2.new(0, 0.5), rightEdge
		local endAnchor, endX = Vector2.new(1, 0.5), leftEdge
		local under, underTo, far, farTo = from.right, to.right, from.left, to.left
		if not forward then
			startAnchor, startX, endAnchor, endX = endAnchor, endX, startAnchor, startX
			under, underTo, far, farTo = far, farTo, under, underTo
		end

		sheet.AnchorPoint = startAnchor
		sheet.Position = UDim2.new(startX, 0, pageY.Scale, pageY.Offset)
		sheet.Size = pageSize
		sheet.Visible = true
		under.Visible = false
		underTo.Visible = true

		task.spawn(function()
			local t = tween(sheet, 0.17, { Size = flatPage }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			t.Completed:Wait()
			if token ~= bookToken then
				return
			end
			sheet.AnchorPoint = endAnchor
			sheet.Position = UDim2.new(endX, 0, pageY.Scale, pageY.Offset)
			t = tween(sheet, 0.17, { Size = pageSize }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			t.Completed:Wait()
			if token ~= bookToken then
				return
			end
			far.Visible = false
			farTo.Visible = true
			sheet.Visible = false
			if parts.onLanded then
				parts.onLanded()
			end
		end)
	end

	-- Show each GuiObject child of `root` one after another (the "writing
	-- appears on the blank page" step). Hidden first by hideChildren().
	function self.hideChildren(root)
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("FxKeepVisible") ~= true then
				if child:GetAttribute("FxWasVisible") == nil then
					child:SetAttribute("FxWasVisible", child.Visible)
				end
				child.Visible = false
			end
		end
	end

	function self.revealChildren(root, stagger, isCurrent)
		local children = {}
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("FxWasVisible") ~= nil then
				table.insert(children, child)
			end
		end
		table.sort(children, function(a, b)
			if a.LayoutOrder ~= b.LayoutOrder then
				return a.LayoutOrder < b.LayoutOrder
			end
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end)
		task.spawn(function()
			for _, child in ipairs(children) do
				if isCurrent and not isCurrent() then
					break
				end
				child.Visible = child:GetAttribute("FxWasVisible") == true
				child:SetAttribute("FxWasVisible", nil)
				task.wait(stagger or 0.04)
			end
			-- anything skipped by an early exit still gets its visibility back
			for _, child in ipairs(children) do
				if child:GetAttribute("FxWasVisible") ~= nil then
					child.Visible = child:GetAttribute("FxWasVisible") == true
					child:SetAttribute("FxWasVisible", nil)
				end
			end
		end)
	end

	return self
end

return UiFx
