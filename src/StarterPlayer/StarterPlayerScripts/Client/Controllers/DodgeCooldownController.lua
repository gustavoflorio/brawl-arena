--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))

local function isMobileDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COOLDOWN_TOTAL = Constants.Combat.DodgeRollCooldown

local READY_COLOR = Color3.fromRGB(80, 200, 120)
local COOLDOWN_COLOR = Color3.fromRGB(70, 70, 85)

local DodgeCooldownController = {}
DodgeCooldownController._controllers = nil :: { [string]: any }?
DodgeCooldownController._gui = nil :: ScreenGui?
DodgeCooldownController._frame = nil :: Frame?
DodgeCooldownController._overlay = nil :: Frame?
DodgeCooldownController._timeLabel = nil :: TextLabel?
DodgeCooldownController._keyLabel = nil :: TextLabel?
DodgeCooldownController._currentStateReady = nil :: boolean?

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlDodgeCooldown"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -16, 1, -140)
	frame.Size = UDim2.new(0, 72, 0, 72)
	frame.BackgroundColor3 = READY_COLOR
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(30, 30, 40)
	border.Thickness = 2
	border.Parent = frame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.AnchorPoint = Vector2.new(0.5, 0)
	keyLabel.Position = UDim2.new(0.5, 0, 0, 6)
	keyLabel.Size = UDim2.new(0, 40, 0, 28)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = "S"
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyLabel.TextSize = 24
	keyLabel.Font = Enum.Font.GothamBlack
	keyLabel.TextStrokeTransparency = 0.5
	keyLabel.Parent = frame

	local dodgeLabel = Instance.new("TextLabel")
	dodgeLabel.Name = "Label"
	dodgeLabel.AnchorPoint = Vector2.new(0.5, 0)
	dodgeLabel.Position = UDim2.new(0.5, 0, 0, 34)
	dodgeLabel.Size = UDim2.new(1, -8, 0, 14)
	dodgeLabel.BackgroundTransparency = 1
	dodgeLabel.Text = "DODGE"
	dodgeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	dodgeLabel.TextSize = 10
	dodgeLabel.Font = Enum.Font.GothamBold
	dodgeLabel.Parent = frame

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.AnchorPoint = Vector2.new(0.5, 1)
	timeLabel.Position = UDim2.new(0.5, 0, 1, -6)
	timeLabel.Size = UDim2.new(1, -8, 0, 16)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "READY"
	timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timeLabel.TextSize = 12
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.Parent = frame

	-- Overlay escuro que drena de baixo pra cima conforme cooldown passa.
	-- Começa em 100% da altura (full dark), vai pra 0 quando ready.
	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.new(0, 0, 1, 0)
	overlay.Size = UDim2.new(1, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	overlay.BackgroundTransparency = 0.2
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 2
	overlay.Parent = frame

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 10)
	overlayCorner.Parent = overlay

	return gui, frame, overlay, timeLabel, keyLabel
end

function DodgeCooldownController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function DodgeCooldownController:_applyReady()
	if self._currentStateReady == true then
		return
	end
	self._currentStateReady = true
	if self._frame then
		self._frame.BackgroundColor3 = READY_COLOR
	end
	if self._overlay then
		self._overlay.Size = UDim2.new(1, 0, 0, 0)
	end
	if self._timeLabel then
		self._timeLabel.Text = "READY"
	end
end

function DodgeCooldownController:_applyCooldown(remaining: number)
	if self._currentStateReady ~= false then
		self._currentStateReady = false
		if self._frame then
			self._frame.BackgroundColor3 = COOLDOWN_COLOR
		end
	end
	if self._overlay then
		local pct = math.clamp(remaining / COOLDOWN_TOTAL, 0, 1)
		self._overlay.Size = UDim2.new(1, 0, pct, 0)
	end
	if self._timeLabel then
		self._timeLabel.Text = string.format("%.1fs", remaining)
	end
end

function DodgeCooldownController:Start()
	-- Em mobile o cooldown é mostrado no D-Pad Down pelo MobileControlsController.
	-- Evita HUD duplicada + o "S" key label não faz sentido sem teclado.
	if isMobileDevice() then
		return
	end

	local gui, frame, overlay, timeLabel, keyLabel = buildGui()
	self._gui = gui
	self._frame = frame
	self._overlay = overlay
	self._timeLabel = timeLabel
	self._keyLabel = keyLabel

	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) ~= "table" then
				return
			end
			local state = snapshot.state
			if typeof(state) ~= "string" then
				return
			end
			gui.Enabled = state == Constants.PlayerState.InArena
		end)
	end

	RunService.Heartbeat:Connect(function()
		local controllers = self._controllers
		local movement = controllers and controllers.MovementController
		if not movement or type(movement.GetDodgeCooldownRemaining) ~= "function" then
			return
		end
		local remaining = movement:GetDodgeCooldownRemaining()
		if remaining <= 0 then
			self:_applyReady()
		else
			self:_applyCooldown(remaining)
		end
	end)
end

return DodgeCooldownController
