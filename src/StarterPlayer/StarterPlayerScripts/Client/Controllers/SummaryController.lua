--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SummaryController = {}
SummaryController._panel = nil :: Frame?
SummaryController._kills = nil :: TextLabel?
SummaryController._time = nil :: TextLabel?
SummaryController._xp = nil :: TextLabel?
SummaryController._levelLine = nil :: TextLabel?
SummaryController._lastSummaryKey = ""

local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	if mins > 0 then
		return string.format("%dm %02ds", mins, secs)
	end
	return string.format("%ds", secs)
end

function SummaryController:Init(_controllers: { [string]: any }) end

function SummaryController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlSummary"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.08, 0)
	panel.Size = UDim2.new(0, 440, 0, 140)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.new(0, 8, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = "FIM DA VIDA"
	title.TextColor3 = Color3.fromRGB(255, 200, 80)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextTransparency = 1
	title.Parent = panel

	local stats = Instance.new("Frame")
	stats.Size = UDim2.new(1, -16, 0, 70)
	stats.Position = UDim2.new(0, 8, 0, 38)
	stats.BackgroundTransparency = 1
	stats.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.Parent = stats

	local function makeStat(label: string, color: Color3): TextLabel
		local stat = Instance.new("TextLabel")
		stat.Size = UDim2.new(0.3, 0, 1, 0)
		stat.BackgroundTransparency = 1
		stat.Text = label
		stat.TextColor3 = color
		stat.TextScaled = true
		stat.Font = Enum.Font.GothamBold
		stat.TextTransparency = 1
		stat.Parent = stats
		return stat
	end

	local killsLabel = makeStat("0\nkills", Color3.fromRGB(255, 255, 255))
	local timeLabel = makeStat("0s\nvivo", Color3.fromRGB(200, 200, 220))
	local xpLabel = makeStat("+0\nXP", Color3.fromRGB(120, 220, 120))

	local levelLine = Instance.new("TextLabel")
	levelLine.Size = UDim2.new(1, -16, 0, 24)
	levelLine.Position = UDim2.new(0, 8, 0, 110)
	levelLine.BackgroundTransparency = 1
	levelLine.Text = ""
	levelLine.TextColor3 = Color3.fromRGB(80, 255, 120)
	levelLine.TextScaled = true
	levelLine.Font = Enum.Font.GothamBold
	levelLine.TextTransparency = 1
	levelLine.Parent = panel

	self._panel = panel
	self._kills = killsLabel
	self._time = timeLabel
	self._xp = xpLabel
	self._levelLine = levelLine

	local function show(summary: { [string]: any })
		local kills = summary.kills or 0
		local timeAlive = summary.timeAliveSeconds or 0
		local xp = summary.xpGained or 0
		local leveled = summary.leveledUp == true
		local newLevel = summary.newLevel

		local key = string.format("%d|%d|%d|%s", kills, timeAlive, xp, tostring(newLevel))
		if key == self._lastSummaryKey then
			return
		end
		self._lastSummaryKey = key

		if self._kills then
			self._kills.Text = string.format("%d\nkills", kills)
		end
		if self._time then
			self._time.Text = string.format("%s\nvivo", formatTime(timeAlive))
		end
		if self._xp then
			self._xp.Text = string.format("+%d\nXP", xp)
		end
		if self._levelLine then
			if leveled and typeof(newLevel) == "number" then
				self._levelLine.Text = string.format("⬆ LEVEL UP! Agora Level %d", newLevel)
			else
				self._levelLine.Text = ""
			end
		end

		local fadeIn = TweenInfo.new(0.25)
		TweenService:Create(panel, fadeIn, { BackgroundTransparency = 0.15 }):Play()
		TweenService:Create(title, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(killsLabel, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(timeLabel, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(xpLabel, fadeIn, { TextTransparency = 0 }):Play()
		if self._levelLine and self._levelLine.Text ~= "" then
			TweenService:Create(self._levelLine, fadeIn, { TextTransparency = 0 }):Play()
		end

		task.delay(4.5, function()
			if self._lastSummaryKey ~= key then
				return
			end
			local fadeOut = TweenInfo.new(0.5)
			TweenService:Create(panel, fadeOut, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(title, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(killsLabel, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(timeLabel, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(xpLabel, fadeOut, { TextTransparency = 1 }):Play()
			if self._levelLine then
				TweenService:Create(self._levelLine, fadeOut, { TextTransparency = 1 }):Play()
			end
		end)
	end

	local remote = Remotes.GetStateRemote()
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		local summary = snapshot.summary
		if typeof(summary) == "table" then
			show(summary)
		end
	end)
end

return SummaryController
