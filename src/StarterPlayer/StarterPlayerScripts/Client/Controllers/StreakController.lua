--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STREAK_LABELS: { [string]: string } = {
	Double = "DOUBLE KILL",
	Triple = "TRIPLE KILL",
	Dominating = "DOMINATING",
}

local STREAK_COLORS: { [string]: Color3 } = {
	Double = Color3.fromRGB(255, 220, 80),
	Triple = Color3.fromRGB(255, 130, 60),
	Dominating = Color3.fromRGB(255, 60, 60),
}

local StreakController = {}
StreakController._label = nil :: TextLabel?

function StreakController:Init(_controllers: { [string]: any }) end

function StreakController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlStreak"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.new(0, 600, 0, 100)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
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
		if typeof(event) ~= "table" or event.type ~= Constants.EventTypes.Streak then
			return
		end
		local payload = event.payload
		if typeof(payload) ~= "table" or typeof(payload.userId) ~= "number" then
			return
		end
		if payload.userId ~= player.UserId then
			return
		end
		local kind = payload.kind
		local text = STREAK_LABELS[kind]
		if not text or not self._label then
			return
		end
		self._label.Text = text
		self._label.TextColor3 = STREAK_COLORS[kind] or Color3.fromRGB(255, 255, 255)
		self._label.TextTransparency = 0
		self._label.Size = UDim2.new(0, 400, 0, 80)
		local grow = TweenService:Create(self._label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 700, 0, 120),
		})
		grow:Play()
		task.delay(1.5, function()
			if self._label and self._label.Text == text then
				local fade = TweenService:Create(self._label, TweenInfo.new(0.5), {
					TextTransparency = 1,
				})
				fade:Play()
			end
		end)
	end)
end

return StreakController
