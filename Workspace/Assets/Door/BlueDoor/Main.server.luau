--Made By: Virtecc
--Blue Door
--6/8/2018
--Goes Great With Textured Brick Walls From The Game


function click()
script.Parent.ClickDetector.MaxActivationDistance = 0
script.Parent.Open:Play()
script.Parent.CanCollide = false
script.Parent.TextureBackClosed.Transparency = 1
script.Parent.TextureBackOpen.Transparency = 0
script.Parent.TextureFrontClosed.Transparency = 1
script.Parent.TextureFrontOpen.Transparency = 0
wait(4)
script.Parent.ClickDetector.MaxActivationDistance = 10
script.Parent.CanCollide = true
script.Parent.Close:Play()
script.Parent.TextureBackClosed.Transparency = 0
script.Parent.TextureBackOpen.Transparency = 1
script.Parent.TextureFrontClosed.Transparency= 0
script.Parent.TextureFrontOpen.Transparency = 1
end

script.Parent.ClickDetector.MouseClick:Connect(click)