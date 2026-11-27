--[[
	VendingMachineUI (ModuleScript, StarterPlayerScripts.BaldiClient.VendingMachineUI)

	Activating a vending machine's ProximityPrompt attempts the purchase on the
	server right away. This shows ToastGui.VendingToastLabel confirming the
	purchase or explaining why it failed.
]]

local VendingMachineUI = {}

function VendingMachineUI.init(ctx)
	local fx = ctx.controllers.UiFx
	local sounds = ctx.controllers.SoundController
	local self = {}

	local toast = fx.gui("ToastGui"):WaitForChild("VendingToastLabel")
	local stroke = toast.TextStrokeTransparency
	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1

	local toastThread = nil
	ctx.remotes.BuyResult.OnClientEvent:Connect(function(success, message)
		if toastThread then
			task.cancel(toastThread)
			toastThread = nil
		end
		toast.Text = message
		toast.TextColor3 = success and Color3.fromRGB(120, 235, 120) or Color3.fromRGB(255, 90, 80)
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = stroke
		fx.pop(toast)
		sounds.play(success and "buy" or "error")
		toastThread = task.delay(2, function()
			fx.tween(toast, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			toastThread = nil
		end)
	end)

	return self
end

return VendingMachineUI
