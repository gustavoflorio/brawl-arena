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

local PROMO_COLOR = Color3.fromRGB(80, 220, 120)
local DEMOTE_COLOR = Color3.fromRGB(220, 80, 80)
local NEUTRAL_COLOR = Color3.fromRGB(255, 220, 120)

local RankUpController = {}
RankUpController._banner = nil :: Frame?
RankUpController._title = nil :: TextLabel?
RankUpController._subtitle = nil :: TextLabel?
RankUpController._activeKey = 0

function RankUpController:Init(_controllers: { [string]: any }) end

function RankUpController:_showBanner(titleText: string, titleColor: Color3, subtitleText: string, holdSeconds: number)
	if not self._banner or not self._title or not self._subtitle then
		return
	end
	local key = self._activeKey + 1
	self._activeKey = key

	self._title.Text = titleText
	self._title.TextColor3 = titleColor
	self._subtitle.Text = subtitleText

	self._banner.BackgroundTransparency = 0.1
	self._title.TextTransparency = 0
	self._subtitle.TextTransparency = 0

	task.delay(holdSeconds, function()
		if not self._banner or self._activeKey ~= key then
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
end

function RankUpController:_handleRankUp(payload: any)
	if typeof(payload) ~= "table" or payload.userId ~= player.UserId then
		return
	end
	local promoted = payload.promoted == true
	local newRank = payload.newRank
	local previousRank = payload.previousRank
	if typeof(newRank) ~= "table" or typeof(previousRank) ~= "table" then
		return
	end
	local newName, newColor = Rank.format(newRank)
	local titleText = promoted and ("PROMOTED: " .. newName) or ("DEMOTED: " .. newName)
	local subtitleText = promoted
		and string.format("You climbed from %s to %s", previousRank.name, newName)
		or string.format("You fell from %s to %s", previousRank.name, newName)
	self:_showBanner(titleText, newColor, subtitleText, 2.5)
end

function RankUpController:_handleSeriesEvent(payload: any)
	if typeof(payload) ~= "table" or payload.userId ~= player.UserId then
		return
	end
	local kind = payload.kind
	local currentTier = payload.currentTier or "?"
	local targetTier = payload.targetTier or "?"

	if kind == "promo_started" then
		self:_showBanner(
			"PROMOTION SERIES",
			PROMO_COLOR,
			string.format("Win 3 in a row to reach %s", targetTier),
			2.5
		)
	elseif kind == "demote_started" then
		self:_showBanner(
			"DEMOTION SERIES",
			DEMOTE_COLOR,
			string.format("Survive 3 deaths or fall to %s", targetTier),
			2.5
		)
	elseif kind == "promo_failed" then
		self:_showBanner(
			"PROMOTION FAILED",
			DEMOTE_COLOR,
			string.format("Stayed in %s", currentTier),
			2.0
		)
	elseif kind == "demote_broken" then
		self:_showBanner(
			"DEMOTION ESCAPED",
			PROMO_COLOR,
			string.format("Recovered in %s", currentTier),
			2.0
		)
	end
end

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
	title.TextColor3 = NEUTRAL_COLOR
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
		if typeof(event) ~= "table" then
			return
		end
		if event.type == Constants.EventTypes.RankUp then
			self:_handleRankUp(event.payload)
		elseif event.type == Constants.EventTypes.SeriesEvent then
			self:_handleSeriesEvent(event.payload)
		end
	end)
end

return RankUpController
