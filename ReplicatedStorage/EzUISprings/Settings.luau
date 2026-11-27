--[[
	All the settings in here are just for defaults, so if you don't set any params for your UISpringObject, they will inherit these values.
	
	// PRINT_UPDATE
	// Prints the new SpringParams whenever you change spring params for an active UISpring. Good for debugging.
	// Default: false
	
	// PART_CONTAINER
	// Just a place to hold the SpringParts, if set to nil then the module will automatically create it's own under workspace.
	// Default: nil
	
	// SIZEFACTOR
	// Determines how big to scale the parts compared to your screen (1 being your whole screen), not recommended to change.
	// Default: 1
	
	// SPRINGINTENSITY
	// Determines how intense the 3DSpringEffect() is.
	// Default: 1
	
	// MOUSEINTENSITY
	// Determines how intense the 3DMouseEffect() is.
	// Default: 1
	
	// POSITIONOFFSET
	// Determines the default positional offset of the spring part, not recommended to change.
	// Default: Vector3(0,0,0)
	
	// ROTATIONOFFSET
	// Determines the default rotation offset of the spring part, not recommended to change.
	// Default: Vector3(0,0,0)
	
	// USECAMERAFOCUS
	// Determines whether or not 3DSpringEffect() uses your camera's focus instead of your camera's cframe to determine how much it will shove the spring.
	// Default: false
	
	// SHOWDEBUG
	// Makes the part semi-transparent to see what it's doing easier, not recommended to change.
	// Default: false
	
	// MOUSECAP
	// Sets a maximum X and Y delta each frame for 3DMouseEffect(), could have some trouble with fpsunlockers but oh well.
	// Default: Vector2(50,50)
	
	//RESETONSPAWN
	// Does what you think it does, determines whether or not the object should be cleared on respawn.
	// Default: true
]]

local Settings = {
	PRINT_UPDATE = false;
	DEFAULT_PART_CONTAINER = nil;
	
	-- // SpringParams
	DEFAULT_SIZEFACTOR = 1;
	DEFAULT_SPRINGINTENSITY = 1;
	DEFAULT_MOUSEINTENSITY = 1;
	DEFAULT_POSITIONOFFSET = Vector3.new();
	DEFAULT_ROTATIONOFFSET = Vector3.new();
	DEFAULT_USECAMERAFOCUS = false;
	DEFAULT_SHOWDEBUG = false;
	DEFAULT_MOUSECAP = Vector2.new(50,50);
	DEFAULT_RESET_ON_SPAWN = true;
	
	-- // SpringParams2D
	DEFAULT_2DMOUSEINTENSITY = 1;
	DEFAULT_2DCAMERAINTENSITY = 1;
}

return Settings
