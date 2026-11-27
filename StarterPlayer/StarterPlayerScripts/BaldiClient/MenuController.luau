--[[
	MenuController (ModuleScript, StarterPlayerScripts.BaldiClient.MenuController)

	Drives the hand-built StarterGui.MainMenuGui:
	  PlayFrame          title screen over the MENU_CAMERA shot. PLAY glides the
	                     camera into the 3D blackboard, then the UI chalkboard
	                     (ChalkboardBgFrame) takes over the same picture.
	  ModeChoosingFrame  Singleplayer / Multiplayer / Settings / Faculty / Shop;
	                     its items ease in from the screen sides every time.
	  FacultyFrame       one page per GameConfig.NPC_GUIDE character.
	  SettingsFrame      opens like a book: covers + blank pages first, then the
	                     settings, keybinds and records appear. "Next page"
	                     turns to Chat Revive's note (NoteLeft/RightPage).
	  ShopFrame          cosmetics: tabs, sections, cards from GameConfig.
	  CountdownFrame     "Get ready" 3-2-1 between Play and spawning.
	  WinFrame/LoseFrame the chalkboard drops in, then the report card shows.

	Moving between screens goes through UiFx.transition (the black wipe).
	Server announcements use ToastGui.AnnounceLabel.

	Also orchestrates the round lifecycle on the client: HUD, stamina,
	keystrokes, first-person camera.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MenuController = {}

-- report cards are paper, so everything on them is written in ink colours
local GRADE_COLORS = {
	["A+"] = Color3.fromRGB(20, 140, 40),
	["A"] = Color3.fromRGB(20, 140, 40),
	["B"] = Color3.fromRGB(175, 135, 0),
	["C"] = Color3.fromRGB(175, 135, 0),
	["D"] = Color3.fromRGB(210, 110, 20),
	["F"] = Color3.fromRGB(200, 25, 25),
}
local INK_DIM = Color3.fromRGB(95, 95, 105)
local INK_GREEN = Color3.fromRGB(20, 140, 40)
local INK_ORANGE = Color3.fromRGB(190, 105, 0)
local PAPER_BORDER = Color3.fromRGB(204, 102, 0)

-- screen-entry animations start as the black wipe clears
local WIPE_DELAY = 0.4

function MenuController.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local hud = ctx.controllers.HudController
	local stamina = ctx.controllers.StaminaController
	local input = ctx.controllers.InputHandler
	local keystrokes = ctx.controllers.KeystrokesController
	local cosmeticState = ctx.controllers.CosmeticState
	local CosmeticsLib = require(ReplicatedStorage:WaitForChild("BaldiShared"):WaitForChild("Cosmetics"))
	local self = { inRound = false }

	local gui = fx.gui("MainMenuGui")
	local playFrame = gui:WaitForChild("PlayFrame")
	local modeFrame = gui:WaitForChild("ModeChoosingFrame")
	local chalkBg = gui:WaitForChild("ChalkboardBgFrame")
	local facultyFrame = gui:WaitForChild("FacultyFrame")
	local settingsFrame = gui:WaitForChild("SettingsFrame")
	local shopFrame = gui:WaitForChild("ShopFrame")
	local countdownFrame = gui:WaitForChild("CountdownFrame")
	local winFrame = gui:WaitForChild("WinFrame")
	local loseFrame = gui:WaitForChild("LoseFrame")
	local announceLabel = fx.gui("ToastGui"):WaitForChild("AnnounceLabel")

	-- ---------- artwork showcase (GameConfig.ARTWORK_SHOWCASE) ----------
	-- Crossfades the chalkboard's ArtworkFrame through the configured art.
	-- Only advances while the chalkboard is on screen.
	do
		local showcase = ctx.config.ARTWORK_SHOWCASE
		local artFrame = chalkBg:FindFirstChild("ArtworkFrame")
		local artImage = artFrame and artFrame:FindFirstChild("ArtworkImageLabel")
		local artCredit = artFrame and artFrame:FindFirstChild("ArtworkCreatorTextLabel")
		local images = showcase and showcase.IMAGES or {}
		if showcase and showcase.ENABLED ~= false and artImage and #images > 0 then
			local TweenService = game:GetService("TweenService")
			local creditStroke = artCredit and artCredit:FindFirstChildWhichIsA("UIStroke")
			local half = TweenInfo.new((showcase.FADE or 0.6) / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

			local function setArt(entry)
				artImage.Image = entry.image
				if artCredit then
					local credit = entry.creator or ""
					artCredit.Text = credit
					artCredit.Visible = credit ~= ""
				end
			end

			local function fadeTo(alpha)
				local last = TweenService:Create(artImage, half, { ImageTransparency = alpha })
				last:Play()
				if artCredit then
					TweenService:Create(artCredit, half, { TextTransparency = alpha }):Play()
				end
				if creditStroke then
					TweenService:Create(creditStroke, half, { Transparency = alpha }):Play()
				end
				last.Completed:Wait()
			end

			task.spawn(function()
				local ids = {}
				for _, entry in ipairs(images) do
					table.insert(ids, entry.image)
				end
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync(ids)
				end)
			end)

			local index = showcase.SHUFFLE and math.random(#images) or 1
			setArt(images[index])
			if #images > 1 then
				task.spawn(function()
					while artImage.Parent do
						task.wait(showcase.INTERVAL or 6)
						if chalkBg.Visible and gui.Enabled then
							local nextIndex = index % #images + 1
							if showcase.SHUFFLE then
								repeat
									nextIndex = math.random(#images)
								until nextIndex ~= index
							end
							index = nextIndex
							fadeTo(1)
							setArt(images[index])
							fadeTo(0)
						end
					end
				end)
			end
		end
	end

	local currencyName = (ctx.config.CURRENCY and ctx.config.CURRENCY.NAME) or "Curriculums"

	local function formatTime(seconds)
		local minutes = math.floor(seconds / 60)
		return string.format("%d:%04.1f", minutes, seconds - minutes * 60)
	end

	local function setButtonText(button, text)
		local label = button:FindFirstChild("Label")
		if label then
			label.Text = text
		end
	end

	-- ===================== camera =====================

	local camCfg = ctx.config.MENU_CAMERA or {}
	local MENU_FOV = camCfg.FIELD_OF_VIEW or 60
	local partCache, nextSearch = {}, {}

	-- cheap lookup: the menu set lives in Workspace.Menu (streamed Persistent)
	local function findMenuPart(name)
		local cached = partCache[name]
		if cached and cached:IsDescendantOf(Workspace) then
			return cached
		end
		if os.clock() < (nextSearch[name] or 0) then
			return nil
		end
		nextSearch[name] = os.clock() + 1
		local menu = Workspace:FindFirstChild("Menu")
		partCache[name] = (menu and menu:FindFirstChild(name, true)) or Workspace:FindFirstChild(name, true)
		return partCache[name]
	end

	local function titleCFrame()
		local part = findMenuPart(camCfg.PART_NAME or "MENU_CAMERA")
		if part and part:IsA("BasePart") then
			return part.CFrame
		end
		return nil
	end

	-- Where the camera sits so the 3D blackboard (wood frame included) fills
	-- the screen, on the side the title shot looks at. Cached per viewport shape.
	local boardCache, boardCacheKey = nil, nil
	local function boardCFrame()
		local camera = Workspace.CurrentCamera
		local board = findMenuPart(camCfg.BOARD_NAME or "BlackBoard")
		if not camera or not board then
			return nil
		end
		local key = tostring(camera.ViewportSize)
		if boardCache and boardCacheKey == key then
			return boardCache
		end
		-- the writing surface: the board's thin, widest part
		local surface, bestArea = nil, 0
		local parts = board:IsA("BasePart") and { board } or board:GetDescendants()
		for _, p in ipairs(parts) do
			if p:IsA("BasePart") then
				local s = p.Size
				local thin = math.min(s.X, s.Y, s.Z)
				local area = (s.X * s.Y * s.Z) / math.max(thin, 0.001)
				if thin < 0.6 and area > bestArea then
					surface, bestArea = p, area
				end
			end
		end
		if not surface then
			return nil
		end
		local s, cf = surface.Size, surface.CFrame
		local normal, up, width, height
		if s.Z <= s.X and s.Z <= s.Y then
			normal, up, width, height = cf.LookVector, cf.UpVector, s.X, s.Y
		elseif s.X <= s.Y then
			normal, up, width, height = cf.RightVector, cf.UpVector, s.Z, s.Y
		else
			normal, up, width, height = cf.UpVector, cf.LookVector, s.X, s.Z
		end
		local from = titleCFrame()
		if from and (from.Position - surface.Position):Dot(normal) < 0 then
			normal = -normal
		end
		local tanV = math.tan(math.rad(MENU_FOV / 2))
		local tanH = tanV * camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1)
		-- +1 stud each way takes in the wood frame, like the UI chalkboard's border
		local distance = math.min(((width + 1) / 2) / tanH, ((height + 1) / 2) / tanV)
		local eye = surface.Position + normal * (distance + math.min(s.X, s.Y, s.Z) / 2)
		boardCache, boardCacheKey = CFrame.lookAt(eye, surface.Position, up), key
		return boardCache
	end

	local holdConn = nil
	local function stopHold()
		if holdConn then
			holdConn:Disconnect()
			holdConn = nil
		end
	end

	-- "title" = the MENU_CAMERA shot, "board" = parked on the blackboard,
	-- nil = hand the camera back to the game
	local function setCamera(mode)
		stopHold()
		local getCFrame = (mode == "title" and titleCFrame) or (mode == "board" and boardCFrame) or nil
		if getCFrame then
			holdConn = RunService.RenderStepped:Connect(function()
				local camera = Workspace.CurrentCamera
				local target = camera and getCFrame()
				if target then
					camera.CameraType = Enum.CameraType.Scriptable
					camera.FieldOfView = MENU_FOV
					camera.CFrame = target
				end
			end)
		else
			local camera = Workspace.CurrentCamera
			if camera then
				camera.CameraType = Enum.CameraType.Custom
				camera.FieldOfView = 70
			end
		end
	end

	-- glide from the title shot into the blackboard (yields until it lands)
	local function dollyToBoard()
		local camera = Workspace.CurrentCamera
		local target = boardCFrame()
		stopHold()
		if camera and target then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = MENU_FOV
			local tween = TweenService:Create(camera, TweenInfo.new(camCfg.DOLLY_SECONDS or 1.6,
				Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
			tween:Play()
			tween.Completed:Wait()
		end
	end

	local function firstPersonCamera(enabled)
		if not ctx.config.FIRST_PERSON then
			return
		end
		if enabled then
			-- shrink Min first so Min <= Max holds at every step
			ctx.player.CameraMinZoomDistance = 0.5
			ctx.player.CameraMaxZoomDistance = 0.5
		else
			ctx.player.CameraMaxZoomDistance = 16
			ctx.player.CameraMinZoomDistance = 6
		end
	end

	-- ===================== screens =====================

	local SCREENS = {
		play = { playFrame },
		mode = { chalkBg, modeFrame },
		faculty = { chalkBg, facultyFrame },
		settings = { settingsFrame },
		shop = { shopFrame },
		countdown = { countdownFrame },
		win = { winFrame },
		lose = { loseFrame },
	}
	local CAMERA_FOR = {
		play = "title",
		mode = "board",
		faculty = "board",
		settings = "board",
		shop = "board",
		countdown = "board",
	}
	local ALL_FRAMES = { playFrame, modeFrame, chalkBg, facultyFrame, settingsFrame, shopFrame, countdownFrame, winFrame, loseFrame }
	local current = nil

	local function setScreen(name)
		current = name
		local show = {}
		for _, frame in ipairs(SCREENS[name] or {}) do
			show[frame] = true
		end
		for _, frame in ipairs(ALL_FRAMES) do
			frame.Visible = show[frame] == true
		end
		setCamera(CAMERA_FOR[name])
	end

	-- the mode screen's items, top to bottom (captured before anything moves)
	local modeItems = {}
	for _, child in ipairs(modeFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(modeItems, child)
			fx.origin(child)
		end
	end
	table.sort(modeItems, function(a, b)
		return a.Position.Y.Scale + a.Position.Y.Offset / 1000 < b.Position.Y.Scale + b.Position.Y.Offset / 1000
	end)

	local openSettingsBook -- defined with the settings page

	local function playEntry(name, delay)
		if name == "mode" then
			fx.easeInFromSides(modeItems, 0.65, 0.05, delay)
		elseif name == "settings" and openSettingsBook then
			openSettingsBook(delay)
		end
	end

	-- black wipe -> swap screens while covered -> wipe out -> entry animation
	local function goTo(name)
		if current == name then
			return
		end
		local frames = SCREENS[name] or {}
		fx.transition(function()
			setScreen(name)
			playEntry(name, WIPE_DELAY)
		end, frames[#frames])
	end

	-- ignore menu clicks while a wipe is running or a round is on
	local function menuClick(handler)
		return function(...)
			if fx.isTransitioning() or self.inRound then
				return
			end
			handler(...)
		end
	end

	-- ===================== announce toast =====================

	announceLabel.TextTransparency = 1
	local announceStroke = announceLabel.TextStrokeTransparency
	announceLabel.TextStrokeTransparency = 1
	local announceThread = nil
	local function announce(text)
		if announceThread then
			task.cancel(announceThread)
			announceThread = nil
		end
		announceLabel.Text = text
		announceLabel.TextTransparency = 0
		announceLabel.TextStrokeTransparency = announceStroke
		sounds.play("nickel")
		announceThread = task.delay(4, function()
			fx.tween(announceLabel, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
			announceThread = nil
		end)
	end

	-- ===================== records / labels =====================

	local stats = nil -- latest StatsData payload from the server
	local bestTimeLabel = modeFrame:FindFirstChild("BestTimeLabel")
	local currencyLabel = modeFrame:FindFirstChild("CurriculumsLabel")

	local recordsPanel = settingsFrame:WaitForChild("RecordsPanel")
	local recordsText = recordsPanel:WaitForChild("RecordsText")
	local leaderboardText = recordsPanel:WaitForChild("LeaderboardText")

	local function refreshRecords()
		if not stats then
			recordsText.Text = "loading..."
			return
		end
		local lines = {
			"Wins: " .. (stats.wins or 0),
			"Best time: " .. (stats.bestTime and formatTime(stats.bestTime) or "--"),
			"Best grade: " .. (stats.bestGrade or "--"),
			"",
			"Recent escapes:",
		}
		if stats.recent and #stats.recent > 0 then
			for index, t in ipairs(stats.recent) do
				table.insert(lines, "  " .. index .. ")  " .. formatTime(t))
			end
		else
			table.insert(lines, "  none yet — go escape!")
		end
		recordsText.Text = table.concat(lines, "\n")

		if stats.leaderboard and #stats.leaderboard > 0 then
			local rows = {}
			for index, entry in ipairs(stats.leaderboard) do
				table.insert(rows, index .. ".  " .. tostring(entry.name) .. "  —  " .. formatTime(entry.time))
			end
			leaderboardText.Text = table.concat(rows, "\n")
		else
			leaderboardText.Text = "no times posted yet"
		end
	end

	-- ===================== settings book =====================

	local settingsPanel = settingsFrame:WaitForChild("SettingsPanel")
	local bookParts = {
		leftCover = settingsFrame:WaitForChild("BookLeftCover"),
		rightCover = settingsFrame:WaitForChild("BookRightCover"),
		frontCover = settingsFrame:WaitForChild("BookFrontCover"),
		sheet = settingsFrame:WaitForChild("BookFlipSheet"),
		leftPage = settingsPanel,
		rightPage = recordsPanel,
		sheetCount = 2,
	}

	local noteLeftPage = settingsFrame:WaitForChild("NoteLeftPage")
	local noteRightPage = settingsFrame:WaitForChild("NoteRightPage")
	local nextPageButton = recordsPanel:WaitForChild("NextPageButton")
	local prevPageButton = noteRightPage:WaitForChild("PrevPageButton")
	fx.setButtonColor(nextPageButton, "cyan")
	fx.setButtonColor(prevPageButton, "cyan")
	local turningPage = false

	openSettingsBook = function(delay)
		-- always reopen on the settings/records spread
		turningPage = false
		noteLeftPage.Visible = false
		noteRightPage.Visible = false
		recordsPanel.Visible = true
		fx.hideChildren(settingsPanel)
		fx.hideChildren(recordsPanel)
		local function isCurrent()
			return current == "settings"
		end
		bookParts.delay = delay
		bookParts.onOpened = function()
			if isCurrent() then
				fx.revealChildren(recordsPanel, 0.03, isCurrent)
				fx.revealChildren(settingsPanel, 0.04, isCurrent)
			end
		end
		fx.openBook(bookParts)
	end

	local function turnSettingsPage(forward)
		if turningPage then
			return
		end
		turningPage = true
		local spread1 = { left = settingsPanel, right = recordsPanel }
		local spread2 = { left = noteLeftPage, right = noteRightPage }
		local to = forward and spread2 or spread1
		fx.hideChildren(to.left)
		fx.hideChildren(to.right)
		local function isCurrent()
			return current == "settings"
		end
		fx.turnPage({
			sheet = bookParts.sheet,
			from = forward and spread1 or spread2,
			to = to,
			onLanded = function()
				turningPage = false
				if isCurrent() then
					fx.revealChildren(to.left, 0.04, isCurrent)
					fx.revealChildren(to.right, 0.03, isCurrent)
				end
			end,
		}, forward)
	end

	nextPageButton.Activated:Connect(menuClick(function()
		sounds.play("click")
		turnSettingsPage(true)
	end))
	prevPageButton.Activated:Connect(menuClick(function()
		sounds.play("click")
		turnSettingsPage(false)
	end))

	-- current client preferences: defaults until the first StatsData arrives
	local defaultSettings = ctx.config.DEFAULT_SETTINGS or {}
	local clientSettings = {
		stopwatch = defaultSettings.stopwatch ~= false,
		sfxVolume = tonumber(defaultSettings.sfxVolume) or 1,
	}

	local function applyClientSettings()
		sounds.setMasterVolume(clientSettings.sfxVolume)
		hud.setStopwatchEnabled(clientSettings.stopwatch)
	end
	local function saveClientSettings()
		ctx.remotes.SaveSettings:FireServer({
			stopwatch = clientSettings.stopwatch,
			sfxVolume = clientSettings.sfxVolume,
		})
	end
	applyClientSettings()

	-- stopwatch ON/OFF toggle
	local toggleButton = settingsPanel:WaitForChild("StopwatchRow"):WaitForChild("ToggleButton")
	local function setToggle(state)
		setButtonText(toggleButton, state and "ON" or "OFF")
		fx.setButtonColor(toggleButton, state and "green" or "red")
	end
	toggleButton.Activated:Connect(function()
		sounds.play("click")
		clientSettings.stopwatch = not clientSettings.stopwatch
		setToggle(clientSettings.stopwatch)
		applyClientSettings()
		saveClientSettings()
	end)

	-- SFX volume slider: Track (click/drag) > Fill + Handle, ValueLabel
	local slider = settingsPanel:WaitForChild("SfxRow"):WaitForChild("Slider")
	local track = slider:WaitForChild("Track")
	local fill = track:WaitForChild("Fill")
	local handle = track:WaitForChild("Handle")
	local valueLabel = slider:WaitForChild("ValueLabel")
	local function setSliderVisual(v)
		v = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		handle.Position = UDim2.fromScale(v, 0.5)
		valueLabel.Text = math.floor(v * 100 + 0.5) .. "%"
	end
	local dragging = false
	local function updateFromX(px)
		local v = math.clamp((px - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		clientSettings.sfxVolume = v
		setSliderVisual(v)
		sounds.setMasterVolume(v) -- live, so the player hears it while dragging
	end
	local function startDrag(dragInput)
		if dragInput.UserInputType == Enum.UserInputType.MouseButton1
			or dragInput.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(dragInput.Position.X)
		end
	end
	track.InputBegan:Connect(startDrag)
	handle.InputBegan:Connect(startDrag)
	UserInputService.InputChanged:Connect(function(moveInput)
		if dragging and (moveInput.UserInputType == Enum.UserInputType.MouseMovement
			or moveInput.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(moveInput.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(endInput)
		if dragging and (endInput.UserInputType == Enum.UserInputType.MouseButton1
			or endInput.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			saveClientSettings()
			sounds.play("click")
		end
	end)

	local function refreshSettingsControls()
		setToggle(clientSettings.stopwatch)
		setSliderVisual(clientSettings.sfxVolume)
	end
	refreshSettingsControls()

	-- keybinds: <Row>.KeyButton per action
	local capturing = nil
	local bindButtons = {}
	for rowName, action in pairs({ UseRow = "USE", SwapRow = "SWAP", SprintRow = "SPRINT", CancelRow = "CANCEL" }) do
		local row = settingsPanel:FindFirstChild(rowName)
		local keyButton = row and row:FindFirstChild("KeyButton")
		if keyButton then
			bindButtons[action] = keyButton
			keyButton.Activated:Connect(function()
				sounds.play("click")
				capturing = action
				for otherAction, button in pairs(bindButtons) do
					setButtonText(button, otherAction == capturing and "press a key..." or input.getKeyName(otherAction))
					fx.setButtonColor(button, otherAction == capturing and "green" or "cyan")
				end
			end)
		end
	end
	local function refreshBindButtons()
		for action, button in pairs(bindButtons) do
			setButtonText(button, capturing == action and "press a key..." or input.getKeyName(action))
			fx.setButtonColor(button, capturing == action and "green" or "cyan")
		end
	end
	UserInputService.InputBegan:Connect(function(keyInput, processed)
		if capturing and not settingsFrame.Visible then
			-- left the page mid-capture: never rebind from a gameplay keypress
			capturing = nil
			refreshBindButtons()
			return
		end
		if not capturing or processed or keyInput.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local action = capturing
		capturing = nil
		if keyInput.KeyCode ~= Enum.KeyCode.Escape then
			input.setBind(action, keyInput.KeyCode.Name)
			ctx.remotes.SaveBinds:FireServer(input.getBinds())
			sounds.play("buy")
		end
		refreshBindButtons()
	end)
	input.onBindsChanged(refreshBindButtons)
	refreshBindButtons()

	-- mobile: lay out the touch controls
	local editTouchRow = settingsPanel:FindFirstChild("EditTouchRow")
	if editTouchRow then
		editTouchRow.Visible = input.touchEnabled
		local editButton = editTouchRow:FindFirstChild("EditTouchButton")
		if editButton then
			editButton.Activated:Connect(function()
				sounds.play("click")
				local editor = require(script.Parent:WaitForChild("HudLayoutEditor"))
				editor.open(ctx, hud)
			end)
		end
	end

	settingsFrame:WaitForChild("BackButton").Activated:Connect(menuClick(function()
		sounds.play("click")
		capturing = nil
		fx.cancelBook()
		goTo("mode")
	end))

	-- ===================== shop =====================

	local shopTemplates = shopFrame:WaitForChild("Templates")
	local tabTemplate = shopTemplates:WaitForChild("TabTemplate")
	local sectionTemplate = shopTemplates:WaitForChild("SectionTemplate")
	local cardTemplate = shopTemplates:WaitForChild("CardTemplate")
	local tabBar = shopFrame:WaitForChild("TabBar")
	local pageScroll = shopFrame:WaitForChild("PageScroll")
	local balanceLabel = shopFrame:WaitForChild("BalanceLabel")
	local shopToast = shopFrame:WaitForChild("ToastLabel")
	shopToast.TextTransparency = 1

	local shopToastThread = nil
	local function flashShopToast(text, good)
		if shopToastThread then
			task.cancel(shopToastThread)
			shopToastThread = nil
		end
		shopToast.Text = text
		shopToast.TextColor3 = good and Color3.fromRGB(160, 235, 150) or Color3.fromRGB(255, 140, 130)
		shopToast.TextTransparency = 0
		shopToastThread = task.delay(2.2, function()
			fx.tween(shopToast, 0.5, { TextTransparency = 1 })
			shopToastThread = nil
		end)
	end

	-- clear the Studio previews; the shop is rebuilt from GameConfig
	for _, container in ipairs({ tabBar, pageScroll }) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local categories = (ctx.config.SHOP and ctx.config.SHOP.CATEGORIES) or {}
	local targetLabels = (ctx.config.SHOP and ctx.config.SHOP.TARGET_LABELS) or {}
	local activeCategory = categories[1] and categories[1].id or nil
	local tabButtons = {}
	local sectionsByCategory = {}
	local shopCards = {}

	local function targetLabel(target)
		local itemDef = ctx.config.ITEMS[target]
		return (itemDef and itemDef.displayName) or targetLabels[target] or target
	end

	local function buildShopCard(cosmetic, parent, order)
		local card = cardTemplate:Clone()
		card.Name = cosmetic.id
		card.LayoutOrder = order
		card.Visible = true
		local preview = card:FindFirstChild("Preview")
		local swatch = card:FindFirstChild("Swatch")
		local hasImage = type(cosmetic.image) == "string" and cosmetic.image ~= ""
		if preview then
			preview.Image = hasImage and cosmetic.image or ""
			preview.Visible = hasImage
		end
		if swatch then
			swatch.Visible = not hasImage
			if cosmetic.color then
				swatch.BackgroundColor3 = Color3.fromRGB(cosmetic.color[1], cosmetic.color[2], cosmetic.color[3])
			end
		end
		card.NameLabel.Text = cosmetic.displayName
		local priceLabel = card.PriceLabel
		local action = card.ActionButton
		local border = card:FindFirstChild("Border")
		local highlight = card:FindFirstChild("EquippedHighlight")
		local ring = highlight and highlight:FindFirstChild("EquippedRing")
		card.Parent = parent

		local function refresh()
			local owned = cosmeticState.isOwned(cosmetic.id)
			local equipped = cosmeticState.getEquippedId(cosmetic.target) == cosmetic.id
			if equipped then
				priceLabel.Text = "Equipped"
				priceLabel.TextColor3 = INK_GREEN
				setButtonText(action, "EQUIPPED")
				fx.setButtonColor(action, "cyan")
			elseif owned then
				priceLabel.Text = "Owned"
				priceLabel.TextColor3 = INK_DIM
				setButtonText(action, "EQUIP")
				fx.setButtonColor(action, "green")
			else
				priceLabel.Text = (cosmetic.price or 0) .. " " .. currencyName
				priceLabel.TextColor3 = INK_ORANGE
				setButtonText(action, "BUY")
				fx.setButtonColor(action, "green")
			end
			if border then
				border.Color = equipped and INK_GREEN or PAPER_BORDER
			end
			if ring then
				ring.Enabled = equipped
			end
		end

		action.Activated:Connect(function()
			if cosmeticState.getEquippedId(cosmetic.target) == cosmetic.id then
				return -- already wearing it
			end
			sounds.play("click")
			if cosmeticState.isOwned(cosmetic.id) then
				cosmeticState.requestEquip(cosmetic.id)
			else
				cosmeticState.requestBuy(cosmetic.id)
			end
		end)
		return { refresh = refresh }
	end

	for categoryIndex, category in ipairs(categories) do
		sectionsByCategory[category.id] = {}
		local order = 0
		for _, target in ipairs(category.targets or {}) do
			local skins = {}
			for _, cosmetic in ipairs(CosmeticsLib.all()) do
				if cosmetic.target == target then
					table.insert(skins, cosmetic)
				end
			end
			if #skins > 0 then
				order += 1
				local section = sectionTemplate:Clone()
				section.Name = "Section_" .. target
				section.LayoutOrder = categoryIndex * 100 + order
				section.Visible = category.id == activeCategory
				section.HeaderLabel.Text = targetLabel(target)
				section.Parent = pageScroll
				for skinIndex, cosmetic in ipairs(skins) do
					table.insert(shopCards, buildShopCard(cosmetic, section.Row, skinIndex))
				end
				table.insert(sectionsByCategory[category.id], section)
			end
		end
	end

	local function applyCategoryFilter()
		for categoryId, sections in pairs(sectionsByCategory) do
			for _, section in ipairs(sections) do
				section.Visible = categoryId == activeCategory
			end
		end
		for id, button in pairs(tabButtons) do
			fx.setButtonColor(button, id == activeCategory and "green" or "cyan")
		end
		pageScroll.CanvasPosition = Vector2.zero
	end

	for index, category in ipairs(categories) do
		local tab = tabTemplate:Clone()
		tab.Name = "Tab_" .. category.id
		tab.LayoutOrder = index
		tab.Visible = true
		setButtonText(tab, category.label)
		tab.Parent = tabBar
		tabButtons[category.id] = tab
		tab.Activated:Connect(function()
			sounds.play("click")
			activeCategory = category.id
			applyCategoryFilter()
		end)
	end
	applyCategoryFilter()

	local function refreshShop()
		if stats and stats.curriculums ~= nil then
			balanceLabel.Text = currencyName .. ": " .. stats.curriculums
		end
		for _, card in ipairs(shopCards) do
			card.refresh()
		end
	end
	refreshShop()

	shopFrame:WaitForChild("BackButton").Activated:Connect(menuClick(function()
		sounds.play("click")
		goTo("mode")
	end))

	ctx.remotes.CosmeticResult.OnClientEvent:Connect(function(ok, message)
		flashShopToast(tostring(message or ""), ok == true)
		sounds.play(ok and "buy" or "error")
	end)

	-- ===================== faculty =====================

	local facultyScroll = facultyFrame:WaitForChild("ScrollingFrame")
	local facultyTemplate = facultyScroll:WaitForChild("TemplateFrame")
	facultyTemplate.Visible = false
	local npcRigs = (function()
		local shared = ReplicatedStorage:FindFirstChild("BaldiShared")
		local assets = ReplicatedStorage:FindFirstChild("BaldiAssets") or (shared and shared:FindFirstChild("BaldiAssets"))
		return assets and assets:FindFirstChild("Npcs")
	end)()

	-- a live render of the character's rig for its photo (when no image is set)
	local function rigPhoto(photoFrame, npcName)
		local rig = npcRigs and npcRigs:FindFirstChild(npcName)
		if not rig or not rig:IsA("Model") then
			return
		end
		local model = rig:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("ModuleScript") then
				d:Destroy()
			end
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			model.PrimaryPart = root
		end
		model:PivotTo(CFrame.new())
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "RigViewport"
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.fromScale(1, 0.9)
		viewport.ZIndex = 2
		viewport.Ambient = Color3.fromRGB(190, 190, 190)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		model.Parent = viewport
		local boxCFrame, boxSize = model:GetBoundingBox()
		local distance = (boxSize.Y / 2 * 1.2) / math.tan(math.rad(camera.FieldOfView / 2))
		local look = boxCFrame.Position
		-- rigs face -Z after PivotTo(identity): stand in front of the face
		camera.CFrame = CFrame.lookAt(look + Vector3.new(0, boxSize.Y * 0.05, -distance), look)
		viewport.Parent = photoFrame
		local placeholder = photoFrame:FindFirstChildOfClass("ImageLabel")
		if placeholder then
			placeholder.ImageTransparency = 1
		end
	end

	local facultyPages = {}
	for index, entry in ipairs(ctx.config.NPC_GUIDE or {}) do
		local page = facultyTemplate:Clone()
		page.Name = "Page_" .. entry.name
		page.Visible = true
		local accent = entry.color and Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3]) or nil
		for _, d in ipairs(page:GetDescendants()) do
			if d.Name == "CharacterNameLabel" and d:IsA("TextLabel") then
				-- the photo caption is quoted, the big heading is plain
				d.Text = d.Parent.Name == "PhotoFrame" and ('"' .. entry.name .. '"') or entry.name
			elseif d.Name == "CharacterQuoteLabel" and d:IsA("TextLabel") then
				d.Text = '"' .. (entry.quote or entry.role or "") .. '"'
				if accent then
					d.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.35)
				end
			elseif d.Name == "CharacterDescriptionLabel" and d:IsA("TextLabel") then
				d.Text = entry.desc or ""
			end
		end
		local photo = page:FindFirstChild("PhotoFrame")
		if photo then
			local photoImage = photo:FindFirstChildOfClass("ImageLabel")
			if entry.image and entry.image ~= "" and photoImage then
				photoImage.Image = entry.image
			else
				rigPhoto(photo, entry.name)
			end
		end
		page.Parent = facultyScroll
		facultyPages[index] = page
	end

	-- one character per screen-height page. The template is laid out for a
	-- two-page-tall frame, so each page is two windows tall (its lower half
	-- is empty) and pages are stacked one window apart. The pages are pure
	-- scale of the canvas (DeviceUi leaves them alone, and the template's
	-- aspect constraint keeps them in shape on any screen ratio); only the
	-- canvas height is in pixels.
	local function layoutFaculty()
		local pageHeight = facultyScroll.AbsoluteSize.Y
		if pageHeight <= 0 then
			return
		end
		local count = math.max(1, #facultyPages)
		for index, page in ipairs(facultyPages) do
			page.Size = UDim2.fromScale(1, 2 / count)
			page.Position = UDim2.fromScale(0.5, (index - 1) / count)
		end
		facultyScroll.CanvasSize = UDim2.fromOffset(0, count * pageHeight)
	end
	facultyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	facultyScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutFaculty)
	layoutFaculty()

	local facultyBack = facultyFrame:FindFirstChild("BackButton")
	if facultyBack then
		facultyBack.Activated:Connect(menuClick(function()
			sounds.play("click")
			goTo("mode")
		end))
	end

	-- ===================== countdown =====================

	local countdownNumber = countdownFrame:WaitForChild("CountdownNumber")
	local countdownToken = 0

	-- ===================== end screens =====================

	local revealToken = 0
	-- drop the chalkboard in from above, then pop the rest of the screen in
	local function showEndScreen(name, frame, content, onRevealed)
		revealToken += 1
		local token = revealToken
		setScreen(name)
		for _, obj in ipairs(content) do
			obj.Visible = false
		end
		local board = frame:FindFirstChild("Chalkboard")
		task.spawn(function()
			if board then
				fx.dropIn(board, 0.8).Completed:Wait()
			end
			if token ~= revealToken or current ~= name then
				return
			end
			for index, obj in ipairs(content) do
				fx.pop(obj, (index - 1) * 0.12)
			end
			if onRevealed then
				task.wait(#content * 0.12 + 0.2)
				if token == revealToken and current == name then
					onRevealed()
				end
			end
		end)
	end

	-- win: the animated report card
	local winCard = winFrame:WaitForChild("ReportCard")
	local winTime = winCard:WaitForChild("TimeLabel")
	local winGrade = winCard:WaitForChild("GradeCircle"):WaitForChild("GradeLabel")
	local winList = winCard:WaitForChild("BreakdownList")
	local winTotal = winCard:WaitForChild("TotalLabel")
	local rowTemplate = winFrame:WaitForChild("Templates"):WaitForChild("BreakdownRowTemplate")
	local winTitle = winFrame:WaitForChild("TitleLabel")
	local winRetry = winFrame:WaitForChild("RetryButton")
	local winMenu = winFrame:WaitForChild("MenuButton")
	local winSkip = winFrame:WaitForChild("SkipButton")

	local breakdownRows = {}
	local function clearBreakdownRows()
		for _, child in ipairs(winList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy() -- includes the Studio preview rows
			end
		end
		breakdownRows = {}
	end
	local function addBreakdownRow(text)
		local row = rowTemplate:Clone()
		row.Name = "Row" .. (#breakdownRows + 1)
		row.LayoutOrder = #breakdownRows + 1
		row.NameLabel.Text = text
		row.AmountLabel.Text = "+0"
		row.Visible = true
		row.Parent = winList
		table.insert(breakdownRows, row)
		return row
	end

	local winToken = 0
	local function playWinSummary(elapsed, grade, breakdown, totalAward)
		winToken += 1
		local token = winToken
		local skip = false
		winRetry.Visible = false
		winMenu.Visible = false
		winSkip.Visible = true
		local skipConn = winSkip.Activated:Connect(function()
			skip = true
		end)

		local function finalize()
			winTime.Text = formatTime(elapsed)
			winGrade.Text = grade or ""
			winGrade.TextColor3 = GRADE_COLORS[grade] or GRADE_COLORS.F
			clearBreakdownRows()
			for _, item in ipairs(breakdown or {}) do
				addBreakdownRow(item.label).AmountLabel.Text = "+" .. item.amount
			end
			winTotal.Text = "Total: +" .. (totalAward or 0) .. " " .. currencyName
			winSkip.Visible = false
			skipConn:Disconnect()
			fx.pop(winRetry)
			fx.pop(winMenu, 0.08)
		end

		task.spawn(function()
			local function stale()
				return winToken ~= token
			end
			-- 1. count the stopwatch up to the escape time
			local duration = math.clamp(elapsed * 0.25, 0.8, 2)
			local t0 = os.clock()
			while true do
				if stale() then skipConn:Disconnect() return end
				if skip then finalize() return end
				local p = math.clamp((os.clock() - t0) / duration, 0, 1)
				winTime.Text = formatTime(elapsed * (1 - (1 - p) * (1 - p)))
				if p >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			winTime.Text = formatTime(elapsed)
			if stale() then skipConn:Disconnect() return end
			if skip then finalize() return end

			-- 2. the teacher circles the grade
			winGrade.Text = grade or ""
			winGrade.TextColor3 = GRADE_COLORS[grade] or GRADE_COLORS.F
			fx.pop(winGrade.Parent)
			sounds.play("click", 1.3)
			task.wait(0.25)

			-- 3. reveal and count each Curriculum source
			for _, item in ipairs(breakdown or {}) do
				if stale() then skipConn:Disconnect() return end
				if skip then finalize() return end
				local row = addBreakdownRow(item.label)
				local r0 = os.clock()
				while true do
					if stale() then skipConn:Disconnect() return end
					if skip then finalize() return end
					local p = math.clamp((os.clock() - r0) / 0.45, 0, 1)
					row.AmountLabel.Text = "+" .. math.floor(item.amount * p + 0.5)
					if p >= 1 then break end
					RunService.Heartbeat:Wait()
				end
				row.AmountLabel.Text = "+" .. item.amount
				sounds.play("nickel")
				task.wait(0.12)
			end
			if stale() then skipConn:Disconnect() return end
			if skip then finalize() return end

			-- 4. the total, then the buttons
			winTotal.Text = "Total: +" .. (totalAward or 0) .. " " .. currencyName
			sounds.play("buy")
			task.wait(0.2)
			if stale() then skipConn:Disconnect() return end
			winSkip.Visible = false
			skipConn:Disconnect()
			fx.pop(winRetry)
			fx.pop(winMenu, 0.08)
		end)
	end

	-- lose
	local loseCard = loseFrame:WaitForChild("ReportCard")
	local loseGrade = loseCard:WaitForChild("GradeCircle"):WaitForChild("GradeLabel")
	local loseDetail = loseCard:WaitForChild("DetailLabel")
	local loseSub = loseCard:WaitForChild("SubLabel")
	local loseTitle = loseFrame:WaitForChild("TitleLabel")
	local loseRetry = loseFrame:WaitForChild("RetryButton")
	local loseMenu = loseFrame:WaitForChild("MenuButton")

	-- ===================== round lifecycle =====================

	local function enterRound()
		self.inRound = true
		fx.transition(function()
			setScreen(nil) -- hides every menu screen, gives the camera back
			hud.show()
			stamina.setEnabled(true)
			firstPersonCamera(true)
			input.releaseMouse("Menu")
			if keystrokes then
				keystrokes.setActive(true)
			end
		end)
	end

	local function exitRound()
		self.inRound = false
		hud.hide()
		stamina.setEnabled(false)
		firstPersonCamera(false)
		input.captureMouse("Menu")
		if keystrokes then
			keystrokes.setActive(false)
		end
	end

	local lastModeId = "CLASSIC" -- so RETRY restarts the mode you just played

	local function requestStart(modeId)
		sounds.play("click")
		ctx.remotes.RequestStart:FireServer(modeId or "CLASSIC")
	end

	-- ===================== title + mode buttons =====================

	local playButton = playFrame:WaitForChild("PlayButton")
	local entering = false
	playButton.Activated:Connect(function()
		if entering or current ~= "play" then
			return
		end
		entering = true
		sounds.play("click")
		playFrame.Visible = false
		dollyToBoard()
		-- the 3D board now fills the screen: the UI chalkboard takes over
		setScreen("mode")
		fx.fadeIn(chalkBg, 0.25)
		playEntry("mode", 0.05)
		entering = false
	end)

	local function bindModeButton(name, handler)
		local button = modeFrame:FindFirstChild(name)
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(menuClick(handler))
		end
	end

	bindModeButton("SingleplayerButton", function()
		requestStart("CLASSIC")
	end)
	-- multiplayer switched off (GameConfig.MULTIPLAYER_ENABLED): dim the button
	local multiplayerOn = ctx.config.MULTIPLAYER_ENABLED ~= false
	do
		local button = modeFrame:FindFirstChild("MultiplayerButton")
		if button and not multiplayerOn then
			if button:IsA("ImageButton") then
				button.ImageColor3 = Color3.fromRGB(130, 130, 130)
			end
			for _, child in ipairs(button:GetDescendants()) do
				if child:IsA("TextLabel") then
					child.TextTransparency = 0.45
				elseif child:IsA("ImageLabel") then
					child.ImageColor3 = Color3.fromRGB(130, 130, 130)
				end
			end
		end
	end
	bindModeButton("MultiplayerButton", function()
		if not multiplayerOn then
			sounds.play("error")
			announce("Multiplayer is coming soon!")
			return
		end
		if RunService:IsStudio() then
			sounds.play("error")
			announce("Multiplayer only works in the published game.")
			return
		end
		sounds.play("click")
		announce("Taking you to the Hub to group up with friends...")
		ctx.remotes.GoToHub:FireServer()
	end)
	bindModeButton("SettingButton", function()
		sounds.play("click")
		ctx.remotes.StatsRequest:FireServer() -- fresh leaderboard for the records page
		refreshRecords()
		refreshBindButtons()
		refreshSettingsControls()
		goTo("settings")
	end)
	bindModeButton("FacultyButton", function()
		sounds.play("click")
		goTo("faculty")
	end)
	bindModeButton("ShopButton", function()
		sounds.play("click")
		ctx.remotes.StatsRequest:FireServer() -- fresh balance + owned set
		refreshShop()
		goTo("shop")
	end)

	winRetry.Activated:Connect(menuClick(function()
		requestStart(lastModeId)
	end))
	loseRetry.Activated:Connect(menuClick(function()
		requestStart(lastModeId)
	end))
	winMenu.Activated:Connect(menuClick(function()
		sounds.play("click")
		winToken += 1
		goTo("mode")
	end))
	loseMenu.Activated:Connect(menuClick(function()
		sounds.play("click")
		goTo("mode")
	end))

	-- ===================== server events =====================

	-- profile + leaderboard payloads drive the records page, shop and labels
	ctx.remotes.StatsData.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		stats = payload
		input.applyBinds(payload.binds)
		cosmeticState.apply(payload.cosmetics) -- repaints HUD + shop skins
		if type(payload.settings) == "table" then
			if payload.settings.stopwatch ~= nil then
				clientSettings.stopwatch = payload.settings.stopwatch == true
			end
			local vol = tonumber(payload.settings.sfxVolume)
			if vol then
				clientSettings.sfxVolume = math.clamp(vol, 0, 1)
			end
			applyClientSettings()
			refreshSettingsControls()
		end
		if payload.bestTime and bestTimeLabel then
			bestTimeLabel.Text = "Best time: " .. formatTime(payload.bestTime)
		end
		if payload.curriculums ~= nil and currencyLabel then
			currencyLabel.Text = currencyName .. ": " .. payload.curriculums
		end
		refreshRecords()
		refreshShop()
	end)

	ctx.remotes.RoundAnnounce.OnClientEvent:Connect(function(text)
		if type(text) == "string" then
			announce(text)
		end
	end)

	ctx.remotes.GameCountdown.OnClientEvent:Connect(function(seconds)
		countdownToken += 1
		local token = countdownToken
		countdownNumber.Text = tostring(seconds)
		task.spawn(goTo, "countdown")
		task.spawn(function()
			for remaining = seconds, 1, -1 do
				if token ~= countdownToken then
					return
				end
				countdownNumber.Text = tostring(remaining)
				fx.pop(countdownNumber)
				sounds.play("click", 1 + (seconds - remaining) * 0.15)
				task.wait(1)
			end
			if token == countdownToken then
				countdownNumber.Text = "GO!"
				fx.pop(countdownNumber)
			end
		end)
	end)

	ctx.remotes.GameStarted.OnClientEvent:Connect(function(notebooksTotal, modeId)
		countdownToken += 1
		if type(modeId) == "string" then
			lastModeId = modeId
		end
		hud.resetForRound(notebooksTotal or ctx.config.NOTEBOOK_SPAWN_COUNT)
		hud.startStopwatch()
		enterRound()
	end)

	ctx.remotes.PlayerWon.OnClientEvent:Connect(function(elapsed, best, grade, award, balance, breakdown)
		hud.stopStopwatch()
		exitRound()
		sounds.winJingle()
		if best and bestTimeLabel then
			bestTimeLabel.Text = "Best time: " .. formatTime(best)
		end
		if balance ~= nil and currencyLabel then
			currencyLabel.Text = currencyName .. ": " .. balance
		end
		-- reset the card before it drops in
		winToken += 1
		winTime.Text = "0:00.0"
		winGrade.Text = ""
		winTotal.Text = ""
		clearBreakdownRows()
		winRetry.Visible = false
		winMenu.Visible = false
		showEndScreen("win", winFrame, { winTitle, winCard }, function()
			playWinSummary(elapsed, grade, breakdown, award)
		end)
	end)

	ctx.remotes.PlayerLost.OnClientEvent:Connect(function(catcherName, cause, collected, total)
		hud.stopStopwatch()
		exitRound()
		sounds.play("caught")
		loseGrade.Text = "F" -- losing is always an F
		loseGrade.TextColor3 = GRADE_COLORS.F
		loseDetail.Text = "Caught by " .. tostring(catcherName)
		local subText = tostring(cause or "")
		if collected and total then
			subText = subText .. string.format("  (Notebooks: %d/%d)", collected, total)
		end
		loseSub.Text = subText
		showEndScreen("lose", loseFrame, { loseTitle, loseCard, loseRetry, loseMenu })
	end)

	ctx.remotes.RoundEnded.OnClientEvent:Connect(function()
		hud.stopStopwatch()
		-- safety net: the round collapsed while we thought we were in it (and
		-- no win/lose screen arrived): fall back to the menu
		if self.inRound then
			exitRound()
			goTo("mode")
		end
	end)

	-- Respawn safety net: a reset mid-run drops the player in the lobby; if no
	-- win/lose screen caught it, bring the menu back.
	ctx.player.CharacterAdded:Connect(function()
		task.wait(0.15) -- let any PlayerLost / RoundEnded for this death land first
		if not self.inRound and current == nil then
			exitRound()
			goTo("mode")
		end
	end)

	-- boot: the title screen over the MENU_CAMERA shot, HUD hidden
	exitRound()
	setScreen("play")

	return self
end

return MenuController
