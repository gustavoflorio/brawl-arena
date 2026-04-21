--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BrawlArenaLoading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
background.BorderSizePixel = 0
background.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.new(0, 600, 0, 100)
title.BackgroundTransparency = 1
title.Text = "BRAWL ARENA"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBlack
title.Parent = background

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.55)
subtitle.Size = UDim2.new(0, 400, 0, 40)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Carregando perfil..."
subtitle.TextColor3 = Color3.fromRGB(200, 200, 220)
subtitle.TextScaled = true
subtitle.Font = Enum.Font.Gotham
subtitle.Parent = background

local spinner = Instance.new("Frame")
spinner.AnchorPoint = Vector2.new(0.5, 0.5)
spinner.Position = UDim2.fromScale(0.5, 0.7)
spinner.Size = UDim2.new(0, 60, 0, 6)
spinner.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
spinner.BorderSizePixel = 0
spinner.Parent = background

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = spinner

task.spawn(function()
	local phase = 0
	while spinner.Parent do
		phase += 0.08
		local t = (math.sin(phase) + 1) * 0.5
		spinner.Size = UDim2.new(0, 40 + t * 80, 0, 6)
		task.wait(0.03)
	end
end)

local function hideLoading()
	if not gui.Parent then
		return
	end
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(background, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(spinner, fadeInfo, { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		gui:Destroy()
	end)
end

if player.Character then
	hideLoading()
else
	local connection
	connection = player.CharacterAdded:Connect(function()
		if connection then
			connection:Disconnect()
		end
		hideLoading()
	end)
end
