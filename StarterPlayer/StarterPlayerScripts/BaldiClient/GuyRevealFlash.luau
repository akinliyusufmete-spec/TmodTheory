--[[
	GuyRevealFlash (ModuleScript, StarterPlayerScripts.BaldiClient.GuyRevealFlash)

	Guy has no body in the world. When the server fires GuyReveal at you (his
	fake notebook, or the chance roll when you FAIL a notebook) he HAUNTS YOUR
	SCREEN:

	  * StarterGui.Guy (the purple "FATAL ERROR" window) slams in after a
	    flashbang. Another copy of the window pops in every WINDOW_ADD_INTERVAL
	    seconds, up to MAX_WINDOWS at once, each blocking a different part of
	    your view.
	  * Every window SNAPS (no tween, no easing) to a new screen spot every
	    MOVE_INTERVAL seconds and jumps on top of the others.
	  * His face flips between FACE_STARE (Guy1) and FACE_LAUGH (Guy2) every
	    FACE_SWAP seconds. Nothing is ever rotated.
	  * Aggressive glitching on the window background and the text:
	      - tinted purple / magenta / cyan copies offset behind and over them
	      - horizontal "tear" slices of the background shoved sideways
	      - the originals jitter every frame, flash purple, and the text
	        scrambles into garbage characters for a frame or two
	  * A slight purple shade covers the whole screen while he is there.

	After HAUNT_SECONDS he flickers out. A round ending, winning, losing or
	dying clears him instantly.
]]

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GLITCH_TINTS = {
	Color3.fromRGB(190, 90, 255),
	Color3.fromRGB(230, 70, 220),
	Color3.fromRGB(140, 70, 255),
	Color3.fromRGB(255, 110, 230),
	Color3.fromRGB(255, 60, 170),
	Color3.fromRGB(120, 200, 255),
}
local SHADE_COLOR = Color3.fromRGB(110, 40, 160)
local SHADE_TRANSPARENCY = 0.72 -- 1 = invisible; lower = darker purple
local GLYPHS = { "#", "%", "@", "!", "?", "/", "\\", "|", "<", ">", "_", "0", "1", "&", "$", "*", "=" }
local MAX_CLONES = 40 -- glitch copies alive at once (all windows together)

-- layer order inside each window (ZIndexBehavior = Sibling)
local Z_BG_COPY = 2 -- tinted copies peeking out behind the background
local Z_BG = 3
local Z_BG_OVER = 4 -- see-through copies doubling the background
local Z_FACE = 5
local Z_TEXT_COPY = 6
local Z_TEXT = 7

-- decorations that should not be copied onto glitch copies
local DECOR = { UIStroke = true, UIGradient = true, UIShadow = true }

local function zeroRotation(root)
	if root:IsA("GuiObject") then
		root.Rotation = 0
	end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.Rotation = 0
		end
	end
end

-- removes child GUI objects (other glitch tears) and decorations from a copy
local function stripDecor(c)
	for _, child in c:GetChildren() do
		if child:IsA("GuiObject") or DECOR[child.ClassName] then
			child:Destroy()
		end
	end
end

local function signed(min, max)
	local v = math.random(min, max)
	return math.random() < 0.5 and -v or v
end

local function scramble(s)
	return (string.gsub(s, "%S", function()
		if math.random() < 0.35 then
			return GLYPHS[math.random(1, #GLYPHS)]
		end
		return nil
	end))
end

local GuyRevealFlash = {}

function GuyRevealFlash.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local cfg = ctx.config.NPC.GUY or {}
	local self = {}

	local HAUNT_SECONDS = cfg.HAUNT_SECONDS or 8
	local FACE_SWAP = cfg.FACE_SWAP or 0.15
	local MOVE_INTERVAL = cfg.MOVE_INTERVAL or 1.5
	local MAX_WINDOWS = cfg.MAX_WINDOWS or 3
	local WINDOW_ADD_INTERVAL = cfg.WINDOW_ADD_INTERVAL or 1.5
	local FACE_STARE = cfg.FACE_STARE or "rbxassetid://105812793677447"
	local FACE_LAUGH = cfg.FACE_LAUGH or "rbxassetid://134737818710462"

	-- The screen is "GuyUI" in StarterGui; also accept the older name "Guy".
	local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("GuyUI") or playerGui:FindFirstChild("Guy")
	while not gui do
		playerGui.ChildAdded:Wait()
		gui = playerGui:FindFirstChild("GuyUI") or playerGui:FindFirstChild("Guy")
	end
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 11
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local mainFrame = gui:WaitForChild("MainFrame")
	local background = mainFrame:WaitForChild("WindowBackgroundImage")
	local face = mainFrame:WaitForChild("GuyFace")
	local text = mainFrame:WaitForChild("TextLabel")

	background.ZIndex = Z_BG
	face.ZIndex = Z_FACE
	text.ZIndex = Z_TEXT
	face.Image = FACE_STARE
	zeroRotation(mainFrame)

	local home = {
		framePos = mainFrame.Position,
		frameAnchor = mainFrame.AnchorPoint,
		frameZ = mainFrame.ZIndex,
		bgPos = background.Position,
		bgSize = background.Size,
		bgColor = background.ImageColor3,
		facePos = face.Position,
		faceSize = face.Size,
		textPos = text.Position,
		textSize = text.Size,
		textString = text.Text,
		textColor = text.TextColor3,
	}
	-- only scramble plain ASCII text (rich text tags / UTF-8 would break)
	local canScramble = not text.RichText and not string.find(home.textString, "[\128-\255]")

	-- clean copy of the window used for the extra windows
	local template = mainFrame:Clone()
	template.Name = "GuyWindowCopy"
	template.AnchorPoint = Vector2.new(0.5, 0.5)

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ FACE_STARE, FACE_LAUGH, background.Image })
		end)
	end)

	-- full-screen purple shade, under every window
	local shade = Instance.new("Frame")
	shade.Name = "PurpleShade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = SHADE_COLOR
	shade.BackgroundTransparency = 1
	shade.Active = false
	shade.ZIndex = 0
	shade.Parent = gui

	local token = 0
	local loop = nil
	local shadeTween = nil
	local kickUntil = 0
	local windows = {} -- active window records
	local live = {} -- glitch copy root -> { obj, prop, start, born, life }
	local liveCount = 0
	local topZ = home.frameZ

	local function makeWindow(frame)
		return {
			frame = frame,
			bg = frame:FindFirstChild("WindowBackgroundImage"),
			face = frame:FindFirstChild("GuyFace"),
			text = frame:FindFirstChild("TextLabel"),
			laughing = false,
			spot = nil,
			nextFace = 0,
			nextMove = 0,
		}
	end
	local primary = makeWindow(mainFrame)

	------------------------------------------------------------ face / restore
	local function setFace(w, laughing)
		w.laughing = laughing
		local f = w.face
		if not f then
			return
		end
		f.Rotation = 0
		if laughing then
			f.Image = FACE_LAUGH
			f.Size = home.faceSize + UDim2.fromOffset(16, 16)
			f.Position = home.facePos + UDim2.fromOffset(math.random(-3, 3), math.random(-3, 3))
		else
			f.Image = FACE_STARE
			f.Size = home.faceSize
			f.Position = home.facePos
		end
	end

	local function restoreWindow(w)
		w.frame.Visible = true
		w.frame.Rotation = 0
		if w.bg then
			w.bg.Position = home.bgPos
			w.bg.Size = home.bgSize
			w.bg.ImageColor3 = home.bgColor
			w.bg.Rotation = 0
		end
		if w.text then
			w.text.Position = home.textPos
			w.text.Text = home.textString
			w.text.TextColor3 = home.textColor
			w.text.Rotation = 0
		end
		setFace(w, false)
	end

	------------------------------------------------------------ glitch copies
	local function track(root, obj, prop, start)
		live[root] = {
			obj = obj,
			prop = prop,
			start = start,
			born = os.clock(),
			life = 0.06 + math.random() * 0.1,
		}
		liveCount += 1
	end

	local function dropCopy(c)
		if live[c] then
			live[c] = nil
			liveCount -= 1
		end
		c:Destroy()
	end

	-- one tinted, offset copy of `source` that blinks out within a fraction of a second
	local function spawnCopy(w, source, z, minOff, maxOff, isImage, homePos, homeSize, horizontal, startMin, startMax)
		if liveCount >= MAX_CLONES or not source then
			return
		end
		local c = source:Clone()
		c.Name = "GlitchCopy"
		stripDecor(c)
		c.Rotation = 0
		c.ZIndex = z
		c.BackgroundTransparency = 1
		local dx, dy
		if horizontal then
			-- smeared sideways, stretched wide
			dx = signed(minOff * 2, maxOff * 3)
			dy = signed(0, 2)
			c.Size = homeSize + UDim2.fromOffset(math.random(10, 40), 0)
		else
			dx = signed(minOff, maxOff)
			dy = signed(minOff, maxOff)
			if isImage then
				c.Size = homeSize + UDim2.fromOffset(math.random(-10, 24), math.random(-6, 6))
			end
		end
		c.Position = homePos + UDim2.fromOffset(dx, dy)
		local tint = GLITCH_TINTS[math.random(1, #GLITCH_TINTS)]
		local start = startMin + math.random() * (startMax - startMin)
		local prop
		if isImage then
			c.ImageColor3 = tint
			c.ImageTransparency = start
			prop = "ImageTransparency"
		else
			c.TextColor3 = tint
			c.TextTransparency = start
			c.TextStrokeTransparency = 1
			prop = "TextTransparency"
		end
		track(c, c, prop, start)
		c.Parent = w.frame
	end

	-- a horizontal strip of the background, shoved sideways (lives inside the background)
	local function spawnTear(w)
		local bg = w.bg
		if liveCount >= MAX_CLONES or not bg then
			return
		end
		local f = 0.05 + math.random() * 0.17 -- strip height, fraction of the background
		local y0 = math.random() * (1 - f)
		local slice = Instance.new("Frame")
		slice.Name = "GlitchTear"
		slice.BackgroundTransparency = 1
		slice.BorderSizePixel = 0
		slice.ClipsDescendants = true
		slice.ZIndex = 1
		slice.AnchorPoint = Vector2.zero
		slice.Position = UDim2.new(0, signed(15, 60), y0, 0)
		slice.Size = UDim2.fromScale(1, f)

		local inner = bg:Clone()
		inner.Name = "TearImage"
		stripDecor(inner)
		inner.Rotation = 0
		inner.AnchorPoint = Vector2.zero
		inner.Position = UDim2.fromScale(0, -y0 / f)
		inner.Size = UDim2.fromScale(1, 1 / f)
		inner.ZIndex = 1
		inner.BackgroundTransparency = 1
		if math.random() < 0.6 then
			inner.ImageColor3 = GLITCH_TINTS[math.random(1, #GLITCH_TINTS)]
		else
			inner.ImageColor3 = home.bgColor
		end
		local start = math.random() * 0.25
		inner.ImageTransparency = start
		inner.Parent = slice

		track(slice, inner, "ImageTransparency", start)
		slice.Parent = bg
	end

	local function glitchBurst(w, count)
		for _ = 1, count do
			local r = math.random()
			if r < 0.3 then
				spawnTear(w)
			elseif r < 0.45 then
				spawnCopy(w, w.bg, Z_BG_OVER, 8, 30, true, home.bgPos, home.bgSize, false, 0.35, 0.65)
			elseif r < 0.6 then
				spawnCopy(w, w.bg, Z_BG_COPY, 8, 30, true, home.bgPos, home.bgSize, false, 0.05, 0.4)
			elseif r < 0.85 then
				spawnCopy(w, w.text, Z_TEXT_COPY, 6, 20, false, home.textPos, home.textSize, false, 0.05, 0.4)
			else
				spawnCopy(w, w.text, Z_TEXT_COPY, 6, 20, false, home.textPos, home.textSize, true, 0.05, 0.4)
			end
		end
	end

	-- the originals themselves: purple flashes and scrambled text
	local function glitchOriginals(w)
		if w.bg then
			if math.random() < 0.25 then
				w.bg.ImageColor3 = GLITCH_TINTS[math.random(1, #GLITCH_TINTS)]
			else
				w.bg.ImageColor3 = home.bgColor
			end
		end
		if w.text then
			if canScramble and math.random() < 0.3 then
				w.text.Text = scramble(home.textString)
			else
				w.text.Text = home.textString
			end
			if math.random() < 0.2 then
				w.text.TextColor3 = GLITCH_TINTS[math.random(1, #GLITCH_TINTS)]
			else
				w.text.TextColor3 = home.textColor
			end
		end
	end

	-- every frame: the background and text shudder, the window sometimes shakes
	local function jitter(w)
		if w.bg then
			if math.random() < 0.5 then
				w.bg.Position = home.bgPos + UDim2.fromOffset(signed(1, 4), signed(0, 3))
			else
				w.bg.Position = home.bgPos
			end
		end
		if w.text then
			local r = math.random()
			if r < 0.1 then
				w.text.Position = home.textPos + UDim2.fromOffset(signed(8, 16), signed(0, 4))
			elseif r < 0.6 then
				w.text.Position = home.textPos + UDim2.fromOffset(signed(1, 3), signed(0, 2))
			else
				w.text.Position = home.textPos
			end
		end
		if w.spot then
			if math.random() < 0.08 then
				w.frame.Position = w.spot + UDim2.fromOffset(signed(4, 12), signed(3, 8))
			else
				w.frame.Position = w.spot
			end
		end
	end

	------------------------------------------------------------ windows
	local function pickSpot()
		local best, bestScore = nil, -1
		for _ = 1, 8 do
			local x = 0.22 + math.random() * 0.56
			local y = 0.22 + math.random() * 0.56
			local score = math.huge
			for _, o in ipairs(windows) do
				if o.spot then
					local dx, dy = x - o.spot.X.Scale, y - o.spot.Y.Scale
					score = math.min(score, dx * dx + dy * dy)
				end
			end
			if score > bestScore then
				best, bestScore = UDim2.fromScale(x, y), score
			end
			if bestScore >= 0.06 then
				break
			end
		end
		return best
	end

	-- instant jump to a new spot (no tween), on top of the other windows
	local function snap(w, now)
		w.spot = pickSpot()
		w.frame.Position = w.spot
		topZ += 1
		w.frame.ZIndex = topZ
		w.nextMove = now + MOVE_INTERVAL + math.random() * 0.5
		kickUntil = now + 0.15
		glitchBurst(w, 5)
	end

	local function addWindow(now)
		local frame = template:Clone()
		frame.Name = "GuyWindowCopy"
		frame.Visible = true
		local w = makeWindow(frame)
		table.insert(windows, w)
		setFace(w, math.random() < 0.5)
		w.nextFace = now + FACE_SWAP * (0.5 + math.random())
		frame.Parent = gui
		snap(w, now)
	end

	------------------------------------------------------------ lifecycle
	local function clear()
		token += 1
		if loop then
			loop:Disconnect()
			loop = nil
		end
		if shadeTween then
			shadeTween:Cancel()
			shadeTween = nil
		end
		for c in pairs(live) do
			c:Destroy()
		end
		table.clear(live)
		liveCount = 0
		for _, w in ipairs(windows) do
			if w ~= primary then
				w.frame:Destroy()
			end
		end
		table.clear(windows)
		restoreWindow(primary)
		mainFrame.Position = home.framePos
		mainFrame.AnchorPoint = home.frameAnchor
		mainFrame.ZIndex = home.frameZ
		primary.spot = nil
		topZ = home.frameZ
		kickUntil = 0
		gui.Enabled = false
		shade.BackgroundTransparency = 1
	end

	local function finish(myToken)
		if myToken ~= token then
			return
		end
		if loop then
			loop:Disconnect()
			loop = nil
		end
		for c in pairs(live) do
			c:Destroy()
		end
		table.clear(live)
		liveCount = 0
		for _, w in ipairs(windows) do
			restoreWindow(w)
			if w.spot then
				w.frame.Position = w.spot
			end
		end
		shadeTween = TweenService:Create(
			shade,
			TweenInfo.new(0.4, Enum.EasingStyle.Linear),
			{ BackgroundTransparency = 1 }
		)
		shadeTween:Play()
		task.spawn(function()
			for _ = 1, 7 do
				if myToken ~= token then
					return
				end
				for _, w in ipairs(windows) do
					w.frame.Visible = not w.frame.Visible
				end
				task.wait(0.06)
			end
			if myToken == token then
				clear()
			end
		end)
	end

	local function haunt()
		clear()
		local myToken = token
		local startedAt = os.clock()
		local nextGlitch = startedAt
		local nextWindow = startedAt + WINDOW_ADD_INTERVAL

		mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		table.insert(windows, primary)
		setFace(primary, false)
		primary.nextFace = startedAt + FACE_SWAP
		snap(primary, startedAt)
		fx.flashbang()
		sounds.play("caught", 1.4)
		gui.Enabled = true

		loop = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local t = now - startedAt

			local fadeIn = math.min(1, t / 0.3)
			local alpha = 1 - (1 - SHADE_TRANSPARENCY) * fadeIn
			alpha += math.sin(t * 6) * 0.04 * fadeIn
			if now < kickUntil then
				alpha -= 0.15 * ((kickUntil - now) / 0.15)
			end
			shade.BackgroundTransparency = math.clamp(alpha, 0, 1)

			if #windows < MAX_WINDOWS and now >= nextWindow then
				nextWindow = now + WINDOW_ADD_INTERVAL
				addWindow(now)
			end

			if now >= nextGlitch then
				nextGlitch = now + 0.03 + math.random() * 0.03
				if math.random() < 0.1 then
					kickUntil = math.max(kickUntil, now + 0.1)
				end
				for _, w in ipairs(windows) do
					glitchBurst(w, math.random(2, 5))
					glitchOriginals(w)
				end
			end

			for _, w in ipairs(windows) do
				if now >= w.nextFace then
					w.nextFace = now + FACE_SWAP
					setFace(w, not w.laughing)
				end
				if now >= w.nextMove then
					snap(w, now)
				end
				jitter(w)
			end

			for c, info in pairs(live) do
				local p = (now - info.born) / info.life
				if p >= 1 or not c.Parent then
					dropCopy(c)
				else
					local v = info.start + (1 - info.start) * p
					if math.random() < 0.15 then
						v = 1
					end
					info.obj[info.prop] = v
				end
			end
		end)

		task.delay(HAUNT_SECONDS, finish, myToken)
	end

	ctx.remotes.GuyReveal.OnClientEvent:Connect(haunt)

	for _, name in ipairs({ "RoundEnded", "PlayerLost", "PlayerWon" }) do
		local remote = ctx.remotes[name]
		if remote then
			remote.OnClientEvent:Connect(clear)
		end
	end

	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				if humanoid.Health <= 0 then
					clear()
				end
			end)
		end
	end
	if ctx.player.Character then
		task.spawn(watchCharacter, ctx.player.Character)
	end
	ctx.player.CharacterAdded:Connect(watchCharacter)

	self.clear = clear
	return self
end

return GuyRevealFlash
