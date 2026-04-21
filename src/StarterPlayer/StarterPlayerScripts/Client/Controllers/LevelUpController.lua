--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LevelUpController = {}
LevelUpController._label = nil :: TextLabel?

function LevelUpController:Init(_controllers: { [string]: any }) end

function LevelUpController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlLevelUp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.45)
	label.Size = UDim2.new(0, 600, 0, 80)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(80, 255, 120)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextTransparency = 1
	label.Parent = gui
	self._label = label

	local remote = Remotes.GetEventsRemote()
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or event.type ~= Constants.EventTypes.LevelUp then
			return
		end
		local payload = event.payload
		if typeof(payload) ~= "table" or payload.userId ~= player.UserId then
			return
		end
		if typeof(payload.newLevel) ~= "number" or not self._label then
			return
		end
		self._label.Text = string.format("LEVEL %d", payload.newLevel)
		self._label.TextTransparency = 0
		local anim = TweenService:Create(self._label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 700, 0, 100),
		})
		anim:Play()
		task.delay(1.0, function()
			if self._label then
				local fade = TweenService:Create(self._label, TweenInfo.new(0.4), {
					TextTransparency = 1,
				})
				fade:Play()
				fade.Completed:Wait()
				self._label.Size = UDim2.new(0, 600, 0, 80)
			end
		end)
	end)
end

return LevelUpController
