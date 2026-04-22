--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local TAG = Constants.Tags.JumpThroughPlatform
local localPlayer = Players.LocalPlayer

local JumpThroughController = {}
JumpThroughController._connection = nil :: RBXScriptConnection?
JumpThroughController._tagged = {} :: { BasePart }
JumpThroughController._passThroughActive = false

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

local function getLocalHumanoid(): Humanoid?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function JumpThroughController:_refreshCache()
	self._tagged = {}
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			table.insert(self._tagged, inst)
		end
	end
end

function JumpThroughController:_setPassThrough(passThrough: boolean)
	if passThrough == self._passThroughActive then
		return
	end
	self._passThroughActive = passThrough
	for _, part in ipairs(self._tagged) do
		if part.Parent then
			part.CanCollide = not passThrough
		end
	end
end

function JumpThroughController:Init(_controllers: { [string]: any }) end

function JumpThroughController:Start()
	self:_refreshCache()

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			table.insert(self._tagged, inst)
			inst.CanCollide = not self._passThroughActive
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		for idx, part in ipairs(self._tagged) do
			if part == inst then
				table.remove(self._tagged, idx)
				break
			end
		end
	end)

	self._connection = RunService.Heartbeat:Connect(function()
		local root = getLocalRoot()
		local humanoid = getLocalHumanoid()
		if not root or not humanoid then
			self:_setPassThrough(false)
			return
		end
		local yVel = root.AssemblyLinearVelocity.Y
		local inAir = humanoid.FloorMaterial == Enum.Material.Air
		local ascending = inAir and yVel > 0.5
		self:_setPassThrough(ascending)
	end)
end

return JumpThroughController
