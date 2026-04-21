--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Rank = require(sharedFolder:WaitForChild("Rank"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudController = {}
HudController._damageLabel = nil :: TextLabel?
HudController._stateLabel = nil :: TextLabel?
HudController._levelLabel = nil :: TextLabel?
HudController._rankLabel = nil :: TextLabel?
HudController._xpBarFill = nil :: Frame?
HudController._xpText = nil :: TextLabel?

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local damagePanel = Instance.new("Frame")
	damagePanel.AnchorPoint = Vector2.new(0.5, 1)
	damagePanel.Size = UDim2.new(0, 260, 0, 110)
	damagePanel.Position = UDim2.new(0.5, 0, 0.98, 0)
	damagePanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	damagePanel.BackgroundTransparency = 0.25
	damagePanel.BorderSizePixel = 0
	damagePanel.Parent = gui

	local damageCorner = Instance.new("UICorner")
	damageCorner.CornerRadius = UDim.new(0, 12)
	damageCorner.Parent = damagePanel

	local damage = Instance.new("TextLabel")
	damage.Size = UDim2.new(1, 0, 0.65, 0)
	damage.BackgroundTransparency = 1
	damage.Text = "0%"
	damage.TextColor3 = Color3.fromRGB(255, 255, 255)
	damage.TextScaled = true
	damage.Font = Enum.Font.GothamBold
	damage.Parent = damagePanel

	local state = Instance.new("TextLabel")
	state.Size = UDim2.new(1, 0, 0.3, 0)
	state.Position = UDim2.new(0, 0, 0.68, 0)
	state.BackgroundTransparency = 1
	state.Text = "Lobby"
	state.TextColor3 = Color3.fromRGB(200, 200, 220)
	state.TextScaled = true
	state.Font = Enum.Font.Gotham
	state.Parent = damagePanel

	local progressPanel = Instance.new("Frame")
	progressPanel.AnchorPoint = Vector2.new(0, 0)
	progressPanel.Position = UDim2.new(0, 16, 0, 16)
	progressPanel.Size = UDim2.new(0, 260, 0, 70)
	progressPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	progressPanel.BackgroundTransparency = 0.3
	progressPanel.BorderSizePixel = 0
	progressPanel.Parent = gui

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 10)
	progressCorner.Parent = progressPanel

	local levelRow = Instance.new("Frame")
	levelRow.Size = UDim2.new(1, -16, 0, 22)
	levelRow.Position = UDim2.new(0, 8, 0, 6)
	levelRow.BackgroundTransparency = 1
	levelRow.Parent = progressPanel

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(0.5, 0, 1, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.TextScaled = true
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = levelRow

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Size = UDim2.new(0.5, 0, 1, 0)
	rankLabel.Position = UDim2.new(0.5, 0, 0, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = "Unranked"
	rankLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	rankLabel.TextScaled = true
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextXAlignment = Enum.TextXAlignment.Right
	rankLabel.Parent = levelRow

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.new(1, -16, 0, 16)
	xpBarBg.Position = UDim2.new(0, 8, 0, 34)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
	xpBarBg.BorderSizePixel = 0
	xpBarBg.Parent = progressPanel

	local xpBarBgCorner = Instance.new("UICorner")
	xpBarBgCorner.CornerRadius = UDim.new(1, 0)
	xpBarBgCorner.Parent = xpBarBg

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Size = UDim2.new(0, 0, 1, 0)
	xpBarFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	xpBarFill.BorderSizePixel = 0
	xpBarFill.Parent = xpBarBg

	local xpBarFillCorner = Instance.new("UICorner")
	xpBarFillCorner.CornerRadius = UDim.new(1, 0)
	xpBarFillCorner.Parent = xpBarFill

	local xpText = Instance.new("TextLabel")
	xpText.Size = UDim2.new(1, -16, 0, 14)
	xpText.Position = UDim2.new(0, 8, 0, 52)
	xpText.BackgroundTransparency = 1
	xpText.Text = "0 / 100 XP"
	xpText.TextColor3 = Color3.fromRGB(200, 200, 220)
	xpText.TextScaled = true
	xpText.Font = Enum.Font.Gotham
	xpText.Parent = progressPanel

	return damage, state, levelLabel, rankLabel, xpBarFill, xpText
end

function HudController:Init(_controllers: { [string]: any }) end

function HudController:Start()
	local damage, state, level, rank, xpFill, xpText = buildGui()
	self._damageLabel = damage
	self._stateLabel = state
	self._levelLabel = level
	self._rankLabel = rank
	self._xpBarFill = xpFill
	self._xpText = xpText

	local remote = Remotes.GetStateRemote()
	if not remote then
		warn("[HudController] BrawlState remote não encontrado.")
		return
	end
	remote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		if typeof(snapshot.damagePercent) == "number" and self._damageLabel then
			self._damageLabel.Text = string.format("%d%%", math.floor(snapshot.damagePercent))
		end
		if typeof(snapshot.state) == "string" and self._stateLabel then
			self._stateLabel.Text = snapshot.state == "InArena" and "Arena" or "Lobby"
		end
		if typeof(snapshot.level) == "number" and self._levelLabel then
			self._levelLabel.Text = string.format("Level %d", snapshot.level)
		end
		if typeof(snapshot.xp) == "number" and typeof(snapshot.xpForNextLevel) == "number" and self._xpBarFill and self._xpText then
			local pct = snapshot.xpForNextLevel > 0 and math.clamp(snapshot.xp / snapshot.xpForNextLevel, 0, 1) or 0
			self._xpBarFill.Size = UDim2.new(pct, 0, 1, 0)
			self._xpText.Text = string.format("%d / %d XP", snapshot.xp, snapshot.xpForNextLevel)
		end
		if typeof(snapshot.rank) == "table" and self._rankLabel then
			local name, color = Rank.format(snapshot.rank)
			self._rankLabel.Text = name
			self._rankLabel.TextColor3 = color
		end
	end)
end

return HudController
