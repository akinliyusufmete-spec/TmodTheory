--[[
	VoicelineController (ModuleScript, StarterPlayerScripts.BaldiClient.VoicelineController)

	Shows what characters say (Voiceline remote, from VoicelineService) as a
	subtitle in StarterGui.VoicelineGui, drawn with HyperText
	(ReplicatedStorage.Packages.HyperText). Each character's look comes from
	CharacterConfig: the TextColor -> TextAltColor gradient, the outline
	colour and their TextEffect markups. Font, text size, outline width and
	fade-out are shared, in CharacterConfig.Settings.

	  VoicelineGui
	    Subtitle            (hidden until a line plays)
	      SpeakerLabel      the character's name, in their colours
	      Container         HyperText draws each line's letters in here
	Restyle and resize these freely; keep the names. Text is Settings.TextScale
	of Container's height, shrunk when a long line would spill out of it.
	During a round Subtitle sits where you put it; outside one (the lose
	screen shows the catcher's line) it moves to its MenuAnchor /
	MenuPosition / MenuSize attributes, clear of the screen's buttons.

	A line only shows if you're within Settings.HearDistance of the speaker,
	unless it's aimed at you (you're the one being chased, caught, grabbed).
	Lines queue: the next waits for the current one to finish appearing and
	cuts its hold short. A line's voice clip (Sound) plays at the speaker; its
	Animation plays through NpcAnimatorClient. With Settings.Enabled = false
	incoming lines are ignored and the subtitle never shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("BaldiShared")
local CharacterConfig = require(shared:WaitForChild("CharacterConfig"))
local SoundLoader = require(shared:WaitForChild("SoundLoader"))

local VoicelineController = {}

local QUEUE_LIMIT = 3
local MIN_HOLD = 0.6 -- a queued line still lets the current one sit this long
local MIN_TEXT_SIZE = 12
local MAX_TEXT_SIZE = 100 -- HyperText's limit
local FIT_ATTEMPTS = 5
local DEFAULT_FONT = "rbxasset://fonts/families/Kalam.json"
-- markups that `false` switches off (the rest take false as their value)
local SWITCH_OFF = { anim = true, clearAnim = true, soundId = true }

-- "Get back <shake=true>HERE</shake>!" -> "Get back HERE!"
local function withoutTags(text)
	return (string.gsub(text, "<[^<>]*>", ""))
end

function VoicelineController.init(ctx)
	local fx = ctx.controllers.UiFx
	local npcAnimator = ctx.controllers.NpcAnimatorClient
	local player = Players.LocalPlayer
	local settings = CharacterConfig.Settings

	local gui = fx.gui("VoicelineGui")
	local subtitle = gui:WaitForChild("Subtitle")
	local speaker = subtitle:WaitForChild("SpeakerLabel")
	local container = subtitle:WaitForChild("Container")
	local speakerOutline = speaker:FindFirstChildOfClass("UIStroke")
	subtitle.Visible = false

	local hudGui = fx.gui("GameplayMenuGui")
	local roundLayout = { subtitle.AnchorPoint, subtitle.Position, subtitle.Size }
	local menuLayout = {
		subtitle:GetAttribute("MenuAnchor") or Vector2.new(0.5, 0.5),
		subtitle:GetAttribute("MenuPosition") or UDim2.new(0.5, 0, 0.19, 0),
		subtitle:GetAttribute("MenuSize") or UDim2.new(0.6, 0, 0.1, 0),
	}
	local function placeSubtitle()
		local layout = (hudGui and hudGui.Enabled) and roundLayout or menuLayout
		subtitle.AnchorPoint, subtitle.Position, subtitle.Size = layout[1], layout[2], layout[3]
	end
	if hudGui then
		-- a catch line arrives just before the HUD hides: follow it to the lose screen
		hudGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if subtitle.Visible then
				placeSubtitle()
			end
		end)
	end

	local HyperText, HyperTextConfig = nil, nil
	local loaded, loadError = pcall(function()
		local module = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("HyperText")
		HyperText = require(module)
		HyperTextConfig = require(module:WaitForChild("Config"))
	end)
	if not loaded then
		HyperText = nil
		warn("[Voicelines] HyperText (ReplicatedStorage.Packages.HyperText) didn't load; lines show as plain text: " .. tostring(loadError))
	end

	-- one TextEffect entry onto a HyperText markups table: name = value, or name = { value, attribute = ... }
	local function applyEffect(markups, name, spec)
		local defaults = HyperTextConfig.DEFAULT_MARKUPS[name]
		if not defaults or not markups[name] then
			warn(("[Voicelines] TextEffect: %q isn't a HyperText markup"):format(tostring(name)))
			return
		end
		local value, attributes = spec, nil
		if type(spec) == "table" then
			value, attributes = spec[1], spec
		end
		if value == false and SWITCH_OFF[name] then
			value = HyperText.DELETE
		end

		local markup, defaultEntry = markups[name], defaults
		if defaults.stack then -- shiny / fog / emitImg / bgImg: adds a layer
			markup = HyperText.insertStackEntry(markups[name], #markups[name].stack + 1)
			defaultEntry = defaults._entryDefaultValues
		end
		if value ~= nil then
			markup.value = value
		end
		if attributes then
			-- some attributes belong to one value (anim "slide" has dir/offset/rot, "grow" has startScale...)
			local valueKey = (value ~= nil and value ~= HyperText.DELETE) and value or defaultEntry.value
			local perValue = type(valueKey) == "string" and defaultEntry.valueAttributes[valueKey]
			for key, attrValue in pairs(attributes) do
				if type(key) == "string" then
					if perValue and perValue[key] ~= nil then
						markup.valueAttributes[valueKey] = markup.valueAttributes[valueKey] or {}
						markup.valueAttributes[valueKey][key] = attrValue
					else
						markup.attributes[key] = attrValue
					end
				end
			end
		end
	end

	local function buildMarkups(character)
		local markups = HyperText.newMarkups()
		markups.font.value = settings.Font or DEFAULT_FONT
		markups.weight.value = settings.FontWeight or Enum.FontWeight.Bold
		markups.horizontalAlignment.value = Enum.HorizontalAlignment.Center
		markups.verticalAlignment.value = Enum.VerticalAlignment.Center
		markups.scaleDimension.value = "Y" -- text follows the box's height if it resizes
		markups.color.value = Color3.new(1, 1, 1) -- the gradient carries the colour
		markups.gradient.value = true
		markups.gradient.attributes.colors = { character.TextColor, character.TextAltColor }
		markups.gradient.attributes.rot = 90 -- TextColor on top, TextAltColor at the bottom
		markups.gradient.attributes.individual = true -- per letter
		markups.stroke.value = true
		markups.stroke.attributes.color = character.TextOutlineColor
		markups.stroke.attributes.thickness = settings.OutlineThickness or 0.08
		markups.clearTransDur.value = settings.FadeOut or 0.3
		for name, spec in pairs(character.TextEffect or {}) do
			if name ~= "size" then
				applyEffect(markups, name, spec)
			end
		end
		return markups
	end

	-- the biggest text size (up to `wanted`) at which the whole line fits the box
	local function fitSize(object, text, wanted)
		local box = container.AbsoluteSize
		local size = wanted
		for _ = 1, FIT_ATTEMPTS do
			local sizing = HyperText.newMarkups()
			sizing.size.value = size
			object:UpdateDefaultMarkups(sizing)
			object:Render(text, true, true, true) -- lay out only, to measure
			local bounds = object:GetConstructionSize()
			if not bounds or (bounds.X <= box.X and bounds.Y <= box.Y) then
				break
			end
			local smaller = math.max(MIN_TEXT_SIZE, math.floor(size * math.min(box.X / bounds.X, box.Y / bounds.Y)))
			if smaller >= size then
				smaller = size - 2
			end
			if smaller < MIN_TEXT_SIZE then
				break
			end
			size = smaller
		end
		return size
	end

	-- plain TextLabel for when HyperText can't draw a line
	local plainLabel = nil
	local function showPlain(character, text)
		if not plainLabel then
			plainLabel = Instance.new("TextLabel")
			plainLabel.Name = "PlainText"
			plainLabel.BackgroundTransparency = 1
			plainLabel.Size = UDim2.fromScale(1, 1)
			plainLabel.FontFace = Font.new(settings.Font or DEFAULT_FONT, settings.FontWeight or Enum.FontWeight.Bold)
			plainLabel.TextScaled = true
			plainLabel.TextWrapped = true
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = 54
			cap.Parent = plainLabel
			Instance.new("UIStroke").Parent = plainLabel
			plainLabel.Parent = container
		end
		plainLabel.Text = withoutTags(text)
		plainLabel.TextColor3 = character.TextColor
		plainLabel.TextTransparency = 0
		plainLabel:FindFirstChildOfClass("UIStroke").Color = character.TextOutlineColor
		plainLabel:FindFirstChildOfClass("UIStroke").Transparency = 0
		plainLabel.Visible = true
	end

	local current = nil -- the HyperText object drawing the current line

	local function clear()
		if current then
			current:Destroy()
			current = nil
		end
		if plainLabel then
			plainLabel.Visible = false
		end
		speaker.TextTransparency = 0
		if speakerOutline then
			speakerOutline.Transparency = 0
		end
	end

	local function style(character)
		speaker.Text = character.DisplayName
		speaker.TextColor3 = character.TextColor
		if speakerOutline then
			speakerOutline.Color = character.TextOutlineColor
		end
	end

	local function fadeOut()
		local duration = settings.FadeOut or 0.3
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(speaker, info, { TextTransparency = 1 }):Play()
		if speakerOutline then
			TweenService:Create(speakerOutline, info, { Transparency = 1 }):Play()
		end
		if plainLabel and plainLabel.Visible then
			TweenService:Create(plainLabel, info, { TextTransparency = 1 }):Play()
			TweenService:Create(plainLabel:FindFirstChildOfClass("UIStroke"), info, { Transparency = 1 }):Play()
		end
		if current then
			current:Clear() -- HyperText fades the letters over clearTransDur
		else
			task.wait(duration)
		end
	end

	local function holdTime(text)
		local plain = withoutTags(text)
		local letters = utf8.len(plain) or #plain
		return math.min((settings.HoldBase or 1.4) + letters * (settings.HoldPerLetter or 0.045), settings.HoldMax or 5)
	end

	-- draws one line; yields until every letter is out
	local function reveal(entry)
		local character = CharacterConfig.get(entry.name)
		clear()
		style(character)
		placeSubtitle()
		subtitle.Visible = true
		fx.pop(speaker)
		RunService.Heartbeat:Wait() -- let the box take its size before measuring

		if HyperText and container.AbsoluteSize.X > 0 and container.AbsoluteSize.Y > 0 then
			local effect = character.TextEffect or {}
			local wanted = tonumber(effect.size)
				or math.floor(container.AbsoluteSize.Y * (settings.TextScale or 0.42))
			wanted = math.clamp(wanted, MIN_TEXT_SIZE, MAX_TEXT_SIZE)

			local made, object = pcall(HyperText.new, container, buildMarkups(character))
			if made then
				current = object
				local ok, err = pcall(function()
					fitSize(object, entry.text, wanted)
					object:Render(entry.text, true)
				end)
				if ok and container:FindFirstChild("HyperTextContent") then
					return
				end
				warn("[Voicelines] HyperText couldn't draw " .. entry.name .. "'s line: " .. tostring(err or "nothing rendered"))
			else
				warn("[Voicelines] HyperText setup failed for " .. entry.name .. ": " .. tostring(object))
			end
			clear()
		end
		showPlain(character, entry.text)
	end

	local queue = {}
	local busy = false

	local function pump()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			while #queue > 0 do
				local entry = table.remove(queue, 1)
				reveal(entry)
				local hold = holdTime(entry.text)
				local shownAt = os.clock()
				while os.clock() - shownAt < hold do
					if #queue > 0 and os.clock() - shownAt > MIN_HOLD then
						break -- someone else is talking: move along
					end
					task.wait(0.05)
				end
				fadeOut()
				clear()
			end
			subtitle.Visible = false
			busy = false
		end)
	end

	ctx.remotes.Voiceline.OnClientEvent:Connect(function(name, text, position, model, soundId, animationName, targetId)
		if settings.Enabled == false then
			return -- voicelines are switched off
		end
		if type(name) ~= "string" or type(text) ~= "string" or text == "" then
			return
		end
		local aimedAtMe = targetId == player.UserId

		-- where the speaker is (the model can be streamed out: fall back to the sent position)
		local root = model and model.Parent and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		local from = root and root.Position or position
		local character = player.Character
		local myRoot = character and character:FindFirstChild("HumanoidRootPart")
		local inEarshot = myRoot ~= nil and typeof(from) == "Vector3"
			and (myRoot.Position - from).Magnitude <= (settings.HearDistance or 70)
		if not (inEarshot or aimedAtMe) then
			return
		end

		if soundId then
			-- at the speaker when nearby; straight to you when it's aimed at you from afar
			SoundLoader.playAt(inEarshot and (root or from) or nil, {
				Id = soundId,
				Volume = 1,
				RollOffMaxDistance = (settings.HearDistance or 70) + 20,
			})
		end
		if animationName and model and npcAnimator and npcAnimator.playOneShot then
			npcAnimator.playOneShot(model, animationName)
		end

		local entry = { name = name, text = text }
		if aimedAtMe then
			table.insert(queue, 1, entry) -- your line jumps the queue
		else
			table.insert(queue, entry)
		end
		while #queue > QUEUE_LIMIT do
			table.remove(queue)
		end
		pump()
	end)

	return {}
end

return VoicelineController
