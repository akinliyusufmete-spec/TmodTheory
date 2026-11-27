local VERSION_NUMBER = 1.21
--[[
	// EzUISprings Created By: (@Haystees)
		 ,----.     ,--.  ,--.                        ,--.
		'   ,  |    |  '--'  | ,--,--.,--. ,--.,---.,-'  '-. ,---.  ,---.  ,---.
		|  |   /    |  .--.  |' ,-.  | \  '  /(  .-''-.  .-'| .-. :| .-. :(  .-'
		'  '--'|    |  |  |  |\ '-'  |  \   ' .-'  `) |  |  \   --.\   --..-'  `)
		 `----'     `--'  `--' `--`--'.-'  /  `----'  `--'   `----' `----'`----' 
		                              `---'
	
	// Remade after 7-ish months to fit my standards.
	
	// Bug Fixes (That i'm aware of):
	
	--V 1.2
	// Mouse3DInfluence no longer has janky SpringInfluence based on look Camera LookVector.
	// Fixed disconnect not working sometimes when trying to do it too quickly.
	
	--Hotfix V 1.21
	// Reset on spawn not working for some goddamn reason
	// Mispelled spring in the shove function
	
	// Usage Guide:
	I have changed it a bit since the last version, so it's not quite the same as it is on the devforum post.
	UISpringObjects use custom paramaters to determine how to display and behave, which can be easily modified at any time.
		
		-> Quick Set Up Example:
			local EzUISpring = require(...) -- Path to wherever you stored the module
			local Frame = (...) -- Your gui object

			local SpringParams = EzUISpring.newSpringParams() -- The spring params that you are going to give your UISpringObject, not neccessary if you are not going to put in anything.
			
			local UISpringObject = EzUISpring.new(Frame, SpringParams) -- Creating your object

			UISpringObject:Apply3DSpringEffect() -- Applying the "Spring" effect, which will react to camera movement

			task.delay(5, function ()
				SpringParams.SpringIntensity = 4
				SpringParams.BaseRotationOffset = Vector3.new(5,0,0)
				
				UISpringObject:UpdateSpringParams(SpringParams) -- Updating the spring params after 5 seconds to make it a bit more springy and tilt to the right
			end)
			
			task.delay(7, function ()
				UISpringObject:Destroy() -- get rid of it!
			end)
	
	
	// Base Functions:
		-> EZUISprings:ClearAll()
			Made just for quick cleanup, does what you think it does.
		
		-> EzUISprings.newSpringParams({[string]: any}?): SpringParams
			Creates a new SpringParams table that you can use, you can set the values by giving it a table with the right keys and values, i.e {SizeFactor = .7};
			Or you can simply just change values by using the dot operator, i.e SpringParams.SizeFactor = 2
		
		-> EzUISprings.newSpringParams2D({[string]: any}?): SpringParams2D
			<!!!> NOT TO BE CONFUSED WITH SpringParams (the 3D version).
			Does the same thing though, just with differing constructors.
		
		-> EzUISprings.new(GuiObject: GuiObject, SpringParams: SpringParams?): UISpringObject
			Creates a new 3D UISpring object with a given GuiObject, SpringParams are optional.
			
		-> EzUISprings.new2D(GuiObject: GuiObject, SpringParams: SpringParams2D?): UISpringObject2D
			Creates a new 2D UISpring object with a given GuiObject, SpringParams2D are optional.
			
	// UISpringObject Functions:
		-> UISpringObject:Shove(Vector: Vector3)
			Force shoves the springs with whatever given vector you supply.
			
		-> UISpringObject:Apply3DSpringEffect(SurfaceGuiProperties: {[string]: any}?)
			Applies the spring effect to the SpringPart.
			You can pass through SurfaceGuiProperties here if you want to change it.
			
		-> UISpringObject:Apply3DMouseEffect()
			Applies the mouse effect to the SpringPart. Only works in third person, or with an unlocked mouse.
			You can pass through SurfaceGuiProperties here if you want to change it.
			
		-> UISpringObject:Destroy(ReturnToParent: boolean)
			Destroys the UISpringObject, if ReturnToParent is true, then it will try to set the original GuiObject's parent back to whatever it was beforehand.
			
	// UISpringObject2D Functions:
		-> UISpringObject2D:Shove(Vector: Vector3)
		-> UISpringObject2D:Apply2DSpringEffect()
		-> UISpringObject2D:Apply2DMousEffect()
		-> UISpringObject2D:Destroy()
]]

local Spring = require(script.Spring)
local Settings = require(script.Settings)
local InstanceFunctions = require(script.InstanceFunctions)

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = PlayerService.LocalPlayer
local PlayerGui = Player.PlayerGui
local DefaultCamera = workspace.CurrentCamera
local Mouse = Player:GetMouse()

local EzUISprings = {}
local UISpringObject = {}
local UISpringObject2D = {}
UISpringObject2D.__index = UISpringObject2D
UISpringObject.__index = UISpringObject

export type SpringParams = {
	SizeFactor: number;
	SpringIntensity: number;
	MouseIntensity: number;
	UseCameraFocus: boolean;
	ShowDebug: boolean;
	MouseCap: Vector2;
	BasePositionOffset: Vector3;
	BaseRotationOffset: Vector3;
	Camera: Camera?;
	ResetOnSpawn: boolean?;
};

export type SpringParams2D = {
	MouseIntensity: number;
	CameraIntensity: number;
	Camera: Camera?;
}

function EzUISprings:ClearAll()
	local SurfaceGuiContainer = PlayerGui:FindFirstChild("EzUISprings")
	local PartContainer = Settings.DEFAULT_PART_CONTAINER or workspace:FindFirstChild("EzUISprings")
	
	if SurfaceGuiContainer then
		for _, Instance in SurfaceGuiContainer:GetChildren() do
			Instance:Destroy()
		end
	end
	
	if PartContainer then
		for _, Instance in PartContainer:GetChildren() do
			Instance:Destroy()
		end
	end
end

function EzUISprings.newSpringParams(SpringParams: SpringParams?): SpringParams
	SpringParams = SpringParams or {}
	
	return {
		SizeFactor = SpringParams.SizeFactor or Settings.DEFAULT_SIZEFACTOR;
		SpringIntensity = SpringParams.SpringIntensity or Settings.DEFAULT_SPRINGINTENSITY;
		MouseIntensity = SpringParams.MouseIntensity or Settings.DEFAULT_MOUSEINTENSITY;
		UseCameraFocus = SpringParams.UseCameraFocus or Settings.DEFAULT_USECAMERAFOCUS;
		ShowDebug = SpringParams.ShowDebug or Settings.DEFAULT_SHOWDEBUG;
		BasePositionOffset = SpringParams.BasePositionOffset or Settings.DEFAULT_POSITIONOFFSET;
		BaseRotationOffset = SpringParams.BaseRotationOffset or Settings.DEFAULT_ROTATIONOFFSET;
		MouseCap = SpringParams.MouseCap or Settings.DEFAULT_MOUSECAP;
		Camera = SpringParams.Camera or DefaultCamera;
		ResetOnSpawn = SpringParams.ResetOnSpawn == nil and SpringParams.DEFAULT_RESET_ON_SPAWN or SpringParams.ResetOnSpawn; -- stupid work around checking for nil because (false and true) = true, sighhhh
	} :: SpringParams
end

function EzUISprings.newSpringParams2D(SpringParams2D: SpringParams2D?): SpringParams2D
	SpringParams2D = SpringParams2D or {}
	return {
		CameraIntensity = SpringParams2D.CameraIntensity or Settings.DEFAULT_2DCAMERAINTENSITY;
		MouseIntensity = SpringParams2D.MouseIntensity or Settings.DEFAULT_2DMOUSEINTENSITY;
		Camera = SpringParams2D.Camera or DefaultCamera;
	} :: SpringParams2D
end

function EzUISprings.new(GuiObject: GuiObject, SpringParams: SpringParams?)
	assert(GuiObject:IsA("GuiObject"), `Expected GuiObject; got '{GuiObject.ClassName}'.`)
	
	local SurfaceGuiContainer = PlayerGui:FindFirstChild("EzUISprings")
	local NoResetSurfaceGuiContainer = PlayerGui:FindFirstChild("EzUISpringsNoReset")
	if not SurfaceGuiContainer then
		SurfaceGuiContainer = InstanceFunctions:Populate(Instance.new("SurfaceGui"), {
			Name = "EzUISprings";
			Parent = PlayerGui;
			ResetOnSpawn = true;
		})
	end
	
	if not NoResetSurfaceGuiContainer then
		NoResetSurfaceGuiContainer = InstanceFunctions:Populate(Instance.new("SurfaceGui"), {
			Name = "EzUISpringsNoReset";
			Parent = PlayerGui;
			ResetOnSpawn = false;
		})
	end
	
	local PartContainer = Settings.DEFAULT_PART_CONTAINER or workspace:FindFirstChild("EzUISprings")
	if not PartContainer then
		PartContainer = InstanceFunctions:Populate(Instance.new("Folder"), {
			Name = "EzUISprings";
			Parent = workspace;
		})
	end
	
	local self = setmetatable({
		SpringParams = EzUISprings.newSpringParams(SpringParams)	
	}, UISpringObject)

	self.GuiObject = GuiObject
	self.OriginalParent = GuiObject.Parent
	self.AbsoluteX = self.GuiObject.AbsoluteSize.X
	self.AbsoluteY = self.GuiObject.AbsoluteSize.Y
	self.OriginalPosition = self.GuiObject.Position
	self.OriginalSize = GuiObject.Size
	
	self.EffectSpring = Spring.create()
	self.MouseSpring = Spring.create()
	
	self.SpringPart = InstanceFunctions:Populate(Instance.new("Part"), {
		Name = "Part3DSurface";
		Transparency = 1;
		Anchored = true;
		CanQuery = false;
		CanCollide = false;
		CanTouch = false;
		Parent = PartContainer;
		Color = Color3.new(1, 0, 0);
	})
	
	self.SurfaceGui = InstanceFunctions:Populate(Instance.new("SurfaceGui"), {
		Face = Enum.NormalId.Front;
		LightInfluence = 0;
		Brightness = 2;
		Name = "EzUISpringsSurfaceGui";
		Adornee = self.SpringPart;
		AlwaysOnTop = true;
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize;
		Parent = self.SpringParams.ResetOnSpawn and SurfaceGuiContainer or NoResetSurfaceGuiContainer;
	})
	
	self.GuiObject.Parent = self.SurfaceGui
	
	self._DestroySignalFired = false
	self.Connections = {
		DestroyedConnection = script.Destroying:Connect(function ()
			if not self.SurfaceGui.Parent then
				self._DestroySignalFired = true
				self:Destroy()
			end
		end);
		
		UpdateConnection = RunService.RenderStepped:Connect(function (DeltaTime)
			local Camera = self.SpringParams.Camera
			
			self.EffectSpring:update(DeltaTime)
			self.MouseSpring:update(DeltaTime)

			local ViewSizeX, ViewSizeY = Camera.ViewportSize.X, Camera.ViewportSize.Y
			self.SurfaceGui.CanvasSize = Vector2.new(ViewSizeX, ViewSizeY)
			local CurrentLookVector = Camera.CFrame.LookVector
			local SpringPos = self.EffectSpring.Position * CurrentLookVector
			local Height = math.tan(math.rad(Camera.FieldOfView/2))* 2
			local Width = (ViewSizeX/ViewSizeY) * Height
			self.SpringPart.Size = Vector3.new(Width, Height, 0.1)/(1/(self.SpringParams.SizeFactor - 0.05))
			
			local LookAtCFrame = CFrame.lookAt((Camera.CFrame + (Camera.CFrame.LookVector)).Position, Camera.CFrame.Position)
			local BaseRotationCFrame = CFrame.Angles(math.rad(self.SpringParams.BaseRotationOffset.Y), math.rad(self.SpringParams.BaseRotationOffset.X), math.rad(self.SpringParams.BaseRotationOffset.Z))
			local BasePositionCFrame = CFrame.new(self.SpringParams.BasePositionOffset)
			local EffectSpringCFrame = CFrame.Angles(math.rad(self.EffectSpring.Y * self.SpringParams.SpringIntensity), math.rad(self.EffectSpring.X * self.SpringParams.SpringIntensity), math.rad(self.EffectSpring.Z * self.SpringParams.SpringIntensity))
			local MouseSpringCFrame = CFrame.Angles(math.rad(self.MouseSpring.Y * self.SpringParams.MouseIntensity), math.rad(self.MouseSpring.X * self.SpringParams.MouseIntensity), math.rad(self.MouseSpring.Z * self.SpringParams.MouseIntensity))
			
			self.SpringPart.CFrame = LookAtCFrame * BasePositionCFrame * BaseRotationCFrame * EffectSpringCFrame * MouseSpringCFrame
			
			if self.SpringParams.ShowDebug then
				self.SpringPart.Transparency = .7
			else
				self.SpringPart.Transparency = 1
			end
		end)
	}
	
	return self
end

function EzUISprings.new2D(GuiObject: GuiObject, SpringParams2D: SpringParams2D?)
	assert(GuiObject:IsA("GuiObject"), `Expected GuiObject; got '{GuiObject.ClassName}'.`)
	
	local self = setmetatable({
		SpringParams2D = EzUISprings.newSpringParams2D(SpringParams2D)	
	}, UISpringObject2D)
	
	self.GuiObject = GuiObject
	self.OriginalPosition = GuiObject.Position
	
	self.EffectSpring = Spring.create()
	self.MouseSpring = Spring.create()
	
	self.Connections = {
		UpdateConnection = RunService.RenderStepped:Connect(function (DeltaTime: number)
			self.EffectSpring:update(DeltaTime)
			self.MouseSpring:update(DeltaTime)
			
			local CameraSpringPosition = (Vector2.new(self.EffectSpring.Position.X, self.EffectSpring.Position.Y))
			local MouseSpringPosition = (Vector2.new(self.MouseSpring.Position.X, self.MouseSpring.Position.Y)/15)
		
			local CameraSpringOffset = UDim2.fromOffset(CameraSpringPosition.X, CameraSpringPosition.Y)
			local MouseSpringOffset = UDim2.fromOffset(MouseSpringPosition.X, MouseSpringPosition.Y)
		
			self.GuiObject.Position = self.OriginalPosition + CameraSpringOffset + MouseSpringOffset
		end);
	}
	
	return self
end

function UISpringObject:Shove(Vector: Vector3)
	self.EffectSpring:shove(Vector)
	self.MouseSpring:shove(Vector)
end

function UISpringObject:UpdateSpringParams(SpringParams: SpringParams?)
	local DoPrintUpdate = Settings.PRINT_UPDATE
	
	if DoPrintUpdate then
		print("Updated active spring with new SpringParams: ", SpringParams)
	end
	
	self.SpringParams = EzUISprings.newSpringParams(SpringParams)
end

function UISpringObject:Apply3DSpringEffect(SurfaceGuiProperties: {any}?)
	SurfaceGuiProperties = SurfaceGuiProperties or {}
	InstanceFunctions:Populate(self.SurfaceGui, SurfaceGuiProperties)
	
	local Camera = self.SpringParams.Camera
	self.LastCameraCFrame = Camera.Focus * CFrame.new(Camera.Focus.LookVector)
	self.Connections.EffectConnection = RunService.RenderStepped:Connect(function ()
		local Camera = self.SpringParams.Camera
		
		local LookNormalized
		local Difference
		
		if self.SpringParams.UseCameraFocus then
			LookNormalized = Camera.Focus * CFrame.new(Camera.Focus.LookVector)
			Difference = LookNormalized.Position - self.LastCameraCFrame.Position
		else
			LookNormalized = Camera.CFrame * CFrame.new(Camera.CFrame.LookVector)
			Difference = LookNormalized.Position - self.LastCameraCFrame.Position
		end
		
		self.EffectSpring:shove(Difference)
		self.LastCameraCFrame = LookNormalized
	end)
	
	return self.Connections.EffectConnection
end

function UISpringObject:Apply3DMouseEffect(SurfaceGuiProperties: {any}?): RBXScriptConnection
	SurfaceGuiProperties = SurfaceGuiProperties or {}
	InstanceFunctions:Populate(self.SurfaceGui, SurfaceGuiProperties)	
	
	self.LastMouseLocation = UserInputService:GetMouseLocation() or Vector2.new(0,0)
	self.Connections.MouseConnection = RunService.RenderStepped:Connect(function ()
		local NewLocation = UserInputService:GetMouseLocation()
		
		local Delta = NewLocation - self.LastMouseLocation
		
		self.LastMouseLocation = NewLocation
		self.MouseSpring:shove(Vector3.new(math.clamp(Delta.X, -self.SpringParams.MouseCap.X, self.SpringParams.MouseCap.X), math.clamp(-Delta.Y, -self.SpringParams.MouseCap.Y, self.SpringParams.MouseCap.Y), 0)/5)
	end)
	
	return self.Connections.MouseConnection
end

function UISpringObject:Destroy(ReturnToParent: boolean?)
	ReturnToParent = ReturnToParent or false
	
	for _, Connection: RBXScriptConnection in self.Connections do
		Connection:Disconnect()
	end
	
	if ReturnToParent then
		if self.OriginalParent then
			self.GuiObject.Parent = self.OriginalParent
		end
	end
	
	if not self._DestroySignalFired then
		self.SurfaceGui:Destroy()
	end

	self.SpringPart:Destroy()

	self = nil
end

function UISpringObject2D:Shove(Vector: Vector3)
	self.EffectSpring:shove(Vector)
	self.MouseSpring:shove(Vector)	
end

function UISpringObject2D:Apply2DSpringEffect(): RBXScriptConnection
	local PreviousCameraCFrame: CFrame = self.SpringParams2D.Camera.CFrame 
	self.Connections.EffectConnection = RunService.RenderStepped:Connect(function (DeltaTime: number)
		local Camera: Camera = self.SpringParams2D.Camera
		local NewCFrame: CFrame = Camera.CFrame
		local MovementDelta = NewCFrame.Position - PreviousCameraCFrame.Position
		
		PreviousCameraCFrame = NewCFrame
		self.EffectSpring:shove(MovementDelta * 5 * self.SpringParams2D.CameraIntensity)
	end)
	
	return self.Connections.EffectConnection
end

function UISpringObject2D:Apply2DMouseEffect(): RBXScriptConnection
	local LastMousePosition = UserInputService:GetMouseLocation()
	self.Connections.MouseConnection = RunService.RenderStepped:Connect(function (DeltaTime: number)
		local NewMousePosition = UserInputService:GetMouseLocation()
		local MouseDelta = NewMousePosition - LastMousePosition
		LastMousePosition = NewMousePosition

		self.MouseSpring:shove(Vector3.new(MouseDelta.X, MouseDelta.Y, 0) * self.SpringParams2D.MouseIntensity)
	end)
	
	return self.Connections.MouseConnection
end

function UISpringObject2D:Destroy()
	for _, Connection: RBXScriptConnection in self.Connections do
		Connection:Disconnect()
	end
	
	self.GuiObject.Position = self.OriginalPosition
	self = nil
end

return EzUISprings