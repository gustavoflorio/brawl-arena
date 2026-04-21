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

local MAX_ENTRIES = 3
local ENTRY_LIFETIME = 5.0
local ENTRY_HEIGHT = 36

local KillFeedController = {}
KillFeedController._container = nil :: Frame?
KillFeedController._entries = {} :: { Frame }

local function buildContainer(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlKillFeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -16, 0, 16)
	container.Size = UDim2.new(0, 320, 0, (ENTRY_HEIGHT + 4) * MAX_ENTRIES)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	return container
end

local function buildEntry(payload: { [string]: any }): Frame?
	local puncher = payload.puncher
	local target = payload.target
	if typeof(puncher) ~= "table" or typeof(target) ~= "table" then
		return nil
	end

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local puncherLabel = Instance.new("TextLabel")
	puncherLabel.AnchorPoint = Vector2.new(0, 0.5)
	puncherLabel.Position = UDim2.new(0, 0, 0.5, 0)
	puncherLabel.Size = UDim2.new(0.4, 0, 0.85, 0)
	puncherLabel.BackgroundTransparency = 1
	puncherLabel.Text = puncher.name
	local _, puncherColor = Rank.format(puncher.rank)
	puncherLabel.TextColor3 = puncherColor
	puncherLabel.TextScaled = true
	puncherLabel.TextXAlignment = Enum.TextXAlignment.Left
	puncherLabel.Font = Enum.Font.GothamBold
	puncherLabel.Parent = frame

	local hitIcon = Instance.new("TextLabel")
	hitIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	hitIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	hitIcon.Size = UDim2.new(0.12, 0, 0.85, 0)
	hitIcon.BackgroundTransparency = 1
	hitIcon.Text = "💥"
	hitIcon.TextScaled = true
	hitIcon.Font = Enum.Font.GothamBold
	hitIcon.Parent = frame

	local targetLabel = Instance.new("TextLabel")
	targetLabel.AnchorPoint = Vector2.new(1, 0.5)
	targetLabel.Position = UDim2.new(1, 0, 0.5, 0)
	targetLabel.Size = UDim2.new(0.4, 0, 0.85, 0)
	targetLabel.BackgroundTransparency = 1
	targetLabel.Text = target.name
	local _, targetColor = Rank.format(target.rank)
	targetLabel.TextColor3 = targetColor
	targetLabel.TextScaled = true
	targetLabel.TextXAlignment = Enum.TextXAlignment.Right
	targetLabel.Font = Enum.Font.GothamBold
	targetLabel.Parent = frame

	return frame
end

function KillFeedController:_pushEntry(frame: Frame)
	if not self._container then
		return
	end
	frame.Parent = self._container
	frame.LayoutOrder = -os.clock() * 1000 // 1
	table.insert(self._entries, frame)
	while #self._entries > MAX_ENTRIES do
		local oldest = table.remove(self._entries, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(ENTRY_LIFETIME, function()
		if frame and frame.Parent then
			local tween = TweenService:Create(frame, TweenInfo.new(0.4), {
				BackgroundTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				if frame then
					frame:Destroy()
				end
			end)
			for idx, entry in ipairs(self._entries) do
				if entry == frame then
					table.remove(self._entries, idx)
					break
				end
			end
		end
	end)
end

function KillFeedController:Init(_controllers: { [string]: any }) end

function KillFeedController:Start()
	self._container = buildContainer()

	local remote = Remotes.GetEventsRemote()
	if not remote then
		warn("[KillFeedController] BrawlEvents remote não encontrado.")
		return
	end
	remote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or event.type ~= Constants.EventTypes.KillFeed then
			return
		end
		local frame = buildEntry(event.payload)
		if frame then
			self:_pushEntry(frame)
		end
	end)
end

return KillFeedController
