--[[
	SeeMoon (ModuleScript, StarterPlayerScripts.BaldiClient.Modifiers.SeeMoon)

	Client half of the See Moon modifier: the whole world is mirrored left to
	right. Pure camera pass, no assets.

	A mirror flips only the view's X axis: the camera keeps its position, its
	look direction and its up, and only the RightVector is negated. In
	CFrame.fromMatrix(pos, vX, vY, vZ) terms vZ is the BACK vector
	(-LookVector), so:
	    CFrame.fromMatrix(cf.Position, -cf.RightVector, cf.UpVector, cf.ZVector)
	That basis is left-handed (determinant -1).

	CHECK IN STUDIO: Roblox documents CFrames as rotations, and a left-handed
	camera basis is unsupported territory. It may render mirrored as
	intended, may render with inside-out faces (flipped triangle winding /
	culling), or the engine may re-orthonormalize it so nothing visible
	changes. If it doesn't look right, this file is the only place to change.

	Runs after the Fire Drill shake (CAMERA_ORDER 10) so the shake is mirrored
	too. ModifierClient puts the untouched CFrame back at the start of every
	frame, so the camera scripts and movement input still read the real
	camera: pressing D moves you to the real right, which on the mirrored
	screen looks like left, and mouse-look turns appear reversed the same
	way. Nothing to restore on stop.
]]

local SeeMoon = {}

SeeMoon.CAMERA_ORDER = 20

function SeeMoon.camera(_env, cf)
	return CFrame.fromMatrix(cf.Position, -cf.RightVector, cf.UpVector, cf.ZVector)
end

return SeeMoon
