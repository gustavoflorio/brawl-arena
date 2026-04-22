--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local NEAR = Constants.DonateKiosk.FadeNearDistance
local FAR = Constants.DonateKiosk.FadeFarDistance
local localPlayer = Players.LocalPlayer

local DonateKioskController = {}
DonateKioskController._connection = nil :: RBXScriptConnection?

local function getLocalRoot(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getKioskAndLabel(): (BasePart?, TextLabel?)
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil, nil
	end
	local kiosk = lobby:FindFirstChild("DonateKiosk")
	if not kiosk or not kiosk:IsA("BasePart") then
		return nil, nil
	end
	local billboard = kiosk:FindFirstChild("Label")
	if not billboard or not billboard:IsA("BillboardGui") then
		return kiosk, nil
	end
	local text = billboard:FindFirstChild("Text")
	if text and text:IsA("TextLabel") then
		return kiosk, text
	end
	return kiosk, nil
end

function DonateKioskController:Init(_controllers: { [string]: any }) end

function DonateKioskController:Start()
	self._connection = RunService.Heartbeat:Connect(function()
		local root = getLocalRoot()
		local kiosk, text = getKioskAndLabel()
		if not root or not kiosk or not text then
			return
		end
		local dist = (root.Position - kiosk.Position).Magnitude
		local alpha: number
		if dist <= NEAR then
			alpha = 0
		elseif dist >= FAR then
			alpha = 1
		else
			alpha = (dist - NEAR) / (FAR - NEAR)
		end
		text.TextTransparency = alpha
		text.TextStrokeTransparency = alpha
	end)
end

return DonateKioskController
