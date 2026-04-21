--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Rank = require(sharedFolder:WaitForChild("Rank"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RankUpController = {}
RankUpController._banner = nil :: Frame?
RankUpController._title = nil :: TextLabel?
RankUpController._subtitle = nil :: TextLabel?

function RankUpController:Init(_controllers: { [string]: any }) end

function RankUpController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlRankUp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.55)
	banner.Size = UDim2.new(0, 520, 0, 120)
	banner.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0.55, 0)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = ""
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextTransparency = 1
	title.Parent = banner

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -24, 0.4, 0)
	subtitle.Position = UDim2.new(0, 12, 0.55, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = ""
	subtitle.TextColor3 = Color3.fromRGB(220, 220, 240)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextTransparency = 1
	subtitle.Parent = banner

	self._banner = banner
	self._title = title
	self._subtitle = subtitle

	local remote = Remotes.GetEventsRemote()
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or event.type ~= Constants.EventTypes.RankUp then
			return
		end
		local payload = event.payload
		if typeof(payload) ~= "table" or payload.userId ~= player.UserId then
			return
		end
		if not self._banner or not self._title or not self._subtitle then
			return
		end
		local promoted = payload.promoted == true
		local newRank = payload.newRank
		local previousRank = payload.previousRank
		if typeof(newRank) ~= "table" or typeof(previousRank) ~= "table" then
			return
		end
		local newName, newColor = Rank.format(newRank)
		self._title.Text = promoted and ("PROMOÇÃO: " .. newName) or ("DEMOÇÃO: " .. newName)
		self._title.TextColor3 = newColor
		self._subtitle.Text = promoted
			and string.format("Você subiu de %s pra %s", previousRank.name, newName)
			or string.format("Você caiu de %s pra %s", previousRank.name, newName)

		self._banner.BackgroundTransparency = 0.1
		self._title.TextTransparency = 0
		self._subtitle.TextTransparency = 0
		task.delay(2.5, function()
			if not self._banner then
				return
			end
			local fade = TweenInfo.new(0.4)
			TweenService:Create(self._banner, fade, { BackgroundTransparency = 1 }):Play()
			if self._title then
				TweenService:Create(self._title, fade, { TextTransparency = 1 }):Play()
			end
			if self._subtitle then
				TweenService:Create(self._subtitle, fade, { TextTransparency = 1 }):Play()
			end
		end)
	end)
end

return RankUpController
