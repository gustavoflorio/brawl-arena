--!strict

-- Aplica fade por distância em todos os BillboardGuis tagged com
-- BrawlFadingLabel. O Adornee do gui (ou Parent) é usado como
-- referência de posição. Todos TextLabels descendentes fadem em sync.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local TAG = Constants.Tags.FadingLabel
local NEAR = Constants.FadingLabel.NearDistance
local FAR = Constants.FadingLabel.FarDistance
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

local function resolveAdornee(gui: BillboardGui): BasePart?
	if gui.Adornee and gui.Adornee:IsA("BasePart") then
		return gui.Adornee
	end
	local parent = gui.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	return nil
end

local function applyFade(gui: BillboardGui, alpha: number)
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = alpha
			descendant.TextStrokeTransparency = alpha
		end
	end
end

function DonateKioskController:Init(_controllers: { [string]: any }) end

function DonateKioskController:Start()
	self._connection = RunService.Heartbeat:Connect(function()
		local root = getLocalRoot()
		if not root then
			return
		end
		local rootPos = root.Position
		for _, gui in ipairs(CollectionService:GetTagged(TAG)) do
			if gui:IsA("BillboardGui") then
				local adornee = resolveAdornee(gui)
				if adornee then
					local dist = (rootPos - adornee.Position).Magnitude
					local alpha: number
					if dist <= NEAR then
						alpha = 0
					elseif dist >= FAR then
						alpha = 1
					else
						alpha = (dist - NEAR) / (FAR - NEAR)
					end
					applyFade(gui, alpha)
				end
			end
		end
	end)
end

return DonateKioskController
