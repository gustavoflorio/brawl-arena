--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudController = {}
HudController._damageLabel = nil :: TextLabel?
HudController._stateLabel = nil :: TextLabel?

local function buildGui(): (TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = UDim2.new(0, 260, 0, 110)
	frame.Position = UDim2.new(0.5, 0, 0.98, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local damage = Instance.new("TextLabel")
	damage.Size = UDim2.new(1, 0, 0.65, 0)
	damage.BackgroundTransparency = 1
	damage.Text = "0%"
	damage.TextColor3 = Color3.fromRGB(255, 255, 255)
	damage.TextScaled = true
	damage.Font = Enum.Font.GothamBold
	damage.Parent = frame

	local state = Instance.new("TextLabel")
	state.Size = UDim2.new(1, 0, 0.3, 0)
	state.Position = UDim2.new(0, 0, 0.68, 0)
	state.BackgroundTransparency = 1
	state.Text = "Lobby"
	state.TextColor3 = Color3.fromRGB(200, 200, 220)
	state.TextScaled = true
	state.Font = Enum.Font.Gotham
	state.Parent = frame

	return damage, state
end

function HudController:Init(_controllers: { [string]: any }) end

function HudController:Start()
	local damageLabel, stateLabel = buildGui()
	self._damageLabel = damageLabel
	self._stateLabel = stateLabel

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
			if snapshot.state == "InArena" then
				self._stateLabel.Text = "Arena"
			else
				self._stateLabel.Text = "Lobby"
			end
		end
	end)
end

return HudController
