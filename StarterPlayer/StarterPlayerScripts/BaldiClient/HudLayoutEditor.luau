--[[
	HudLayoutEditor (ModuleScript, StarterPlayerScripts.BaldiClient.HudLayoutEditor)

	The "Edit Touch Controls" overlay (mobile) — StarterGui.HudEditorGui.
	Opened from Settings, it lets a player lay out the RUN / USE / SWAP buttons:
	  - drag a proxy anywhere to reposition it,
	  - tap one to select it (its SelectionRing lights), then - / + to resize,
	  - SAVE persists the layout (and applies it live), RESET returns to the
	    defaults, CANCEL discards changes.

	Not a controller (no .init): MenuController calls HudLayoutEditor.open(ctx, hud).
]]

local UserInputService = game:GetService("UserInputService")

local HudLayoutEditor = {}

local PROXY_NAMES = { sprint = "RunProxy", use = "UseProxy", swap = "SwapProxy" }
local ORDER = { "sprint", "use", "swap" }

local session = nil -- the open editor's state; nil when closed
local wired = false

function HudLayoutEditor.open(ctx, hud)
	if session then
		return
	end
	-- nothing to edit if the HUD has no mobile buttons (non-touch session)
	if not hud or not hud.mobileButtons or not hud.getHudLayout then
		return
	end
	local playerGui = ctx.player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("HudEditorGui")
	local proxyFolder = gui:WaitForChild("Proxies")
	local toolbar = gui:WaitForChild("Toolbar")
	local mobileCfg = ctx.config.MOBILE_HUD or {}
	local defaults = mobileCfg.DEFAULTS or {}
	local baseSize = hud.mobileBaseSize or mobileCfg.BASE_SIZE or {}
	local minScale = mobileCfg.MIN_SCALE or 0.6
	local maxScale = mobileCfg.MAX_SCALE or 1.7

	local proxies = {}
	for key, name in pairs(PROXY_NAMES) do
		proxies[key] = proxyFolder:WaitForChild(name)
	end

	-- working copy of the layout (the live one, else the defaults)
	session = { layout = {}, selected = "use", dragging = nil }
	local current = hud.getHudLayout()
	for _, key in ipairs(ORDER) do
		local e = current[key] or defaults[key] or { x = 0.5, y = 0.7, scale = 1 }
		session.layout[key] = { x = e.x, y = e.y, scale = e.scale or 1 }
	end

	local function place(key)
		local entry = session.layout[key]
		local px = (baseSize[key] or 90) * entry.scale
		proxies[key].Size = UDim2.fromOffset(px, px)
		proxies[key].Position = UDim2.fromScale(entry.x, entry.y)
	end
	local function refreshSelection()
		for key, proxy in pairs(proxies) do
			local ring = proxy:FindFirstChild("SelectionRing")
			if ring then
				ring.Enabled = key == session.selected
			end
		end
	end
	for _, key in ipairs(ORDER) do
		place(key)
	end
	refreshSelection()
	gui.Enabled = true

	local function close()
		gui.Enabled = false
		if session then
			for _, conn in ipairs(session.conns) do
				conn:Disconnect()
			end
		end
		session = nil
	end

	-- one global move/end pair drives whichever proxy is being dragged
	session.conns = {
		UserInputService.InputChanged:Connect(function(move)
			if not session or not session.dragging then
				return
			end
			if move.UserInputType ~= Enum.UserInputType.MouseMovement and move.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local abs = gui.AbsoluteSize
			if abs.X <= 0 or abs.Y <= 0 then
				return
			end
			local key = session.dragging
			session.layout[key].x = math.clamp((move.Position.X - gui.AbsolutePosition.X) / abs.X, 0.06, 0.94)
			session.layout[key].y = math.clamp((move.Position.Y - gui.AbsolutePosition.Y) / abs.Y, 0.10, 0.95)
			place(key)
		end),
		UserInputService.InputEnded:Connect(function(ended)
			if session and (ended.UserInputType == Enum.UserInputType.MouseButton1 or ended.UserInputType == Enum.UserInputType.Touch) then
				session.dragging = nil
			end
		end),
	}

	-- buttons persist between openings: wire them once, against `session`
	if not wired then
		wired = true
		for key, proxy in pairs(proxies) do
			proxy.InputBegan:Connect(function(press)
				if session and (press.UserInputType == Enum.UserInputType.MouseButton1 or press.UserInputType == Enum.UserInputType.Touch) then
					session.selected = key
					session.dragging = key
					for otherKey, other in pairs(proxies) do
						local ring = other:FindFirstChild("SelectionRing")
						if ring then
							ring.Enabled = otherKey == key
						end
					end
				end
			end)
		end
		local function resize(delta)
			if not session then
				return
			end
			local entry = session.layout[session.selected]
			entry.scale = math.clamp(entry.scale + delta, minScale, maxScale)
			local px = (baseSize[session.selected] or 90) * entry.scale
			proxies[session.selected].Size = UDim2.fromOffset(px, px)
		end
		toolbar:WaitForChild("MinusButton").Activated:Connect(function()
			resize(-0.1)
		end)
		toolbar:WaitForChild("PlusButton").Activated:Connect(function()
			resize(0.1)
		end)
		toolbar:WaitForChild("ResetButton").Activated:Connect(function()
			if not session then
				return
			end
			for _, key in ipairs(ORDER) do
				local d = defaults[key] or { x = 0.5, y = 0.7, scale = 1 }
				session.layout[key] = { x = d.x, y = d.y, scale = d.scale or 1 }
				local entry = session.layout[key]
				local px = (baseSize[key] or 90) * entry.scale
				proxies[key].Size = UDim2.fromOffset(px, px)
				proxies[key].Position = UDim2.fromScale(entry.x, entry.y)
			end
		end)
		toolbar:WaitForChild("CancelButton").Activated:Connect(function()
			HudLayoutEditor._close()
		end)
		toolbar:WaitForChild("SaveButton").Activated:Connect(function()
			if not session then
				return
			end
			if HudLayoutEditor._hud and HudLayoutEditor._hud.applyHudLayout then
				HudLayoutEditor._hud.applyHudLayout(session.layout)
			end
			ctx.remotes.SaveHudLayout:FireServer(session.layout)
			HudLayoutEditor._close()
		end)
	end
	HudLayoutEditor._hud = hud
	HudLayoutEditor._close = close
end

return HudLayoutEditor
