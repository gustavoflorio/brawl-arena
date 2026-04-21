--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local MovementController = {}
MovementController._lockConnection = nil :: RBXScriptConnection?
MovementController._currentState = Constants.PlayerState.InLobby

local Z_LOCK = Constants.Arena.AxisLockValue
local ACTION_JUMP = "BrawlArenaJump"
local ACTION_BLOCK_BACKWARD = "BrawlArenaBlockBackward"

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return nil
end

function MovementController:_handleJump(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		local humanoid = getHumanoid()
		if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
	return Enum.ContextActionResult.Sink
end

function MovementController:_handleBlockBackward(_name: string, _state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

function MovementController:_enableArenaControls()
	if not self._lockConnection then
		self._lockConnection = RunService.Heartbeat:Connect(function()
			local root = getRoot()
			if not root then
				return
			end
			local pos = root.Position
			if math.abs(pos.Z - Z_LOCK) > 0.01 then
				local rotation = root.CFrame - pos
				root.CFrame = CFrame.new(pos.X, pos.Y, Z_LOCK) * rotation
			end
			local velocity = root.AssemblyLinearVelocity
			if math.abs(velocity.Z) > 0.01 then
				root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
			end
		end)
	end

	ContextActionService:BindAction(
		ACTION_JUMP,
		function(name, state, input)
			return self:_handleJump(name, state, input)
		end,
		false,
		Enum.KeyCode.W
	)
	ContextActionService:BindAction(
		ACTION_BLOCK_BACKWARD,
		function(name, state, input)
			return self:_handleBlockBackward(name, state, input)
		end,
		false,
		Enum.KeyCode.S
	)
end

function MovementController:_disableArenaControls()
	if self._lockConnection then
		self._lockConnection:Disconnect()
		self._lockConnection = nil
	end
	ContextActionService:UnbindAction(ACTION_JUMP)
	ContextActionService:UnbindAction(ACTION_BLOCK_BACKWARD)
end

function MovementController:_applyState(state: string)
	if state == self._currentState then
		return
	end
	self._currentState = state
	if state == Constants.PlayerState.InArena then
		self:_enableArenaControls()
	else
		self:_disableArenaControls()
	end
end

function MovementController:Init(_controllers: { [string]: any }) end

function MovementController:Start()
	local remote = Remotes.GetStateRemote()
	if not remote then
		warn("[MovementController] BrawlState remote não encontrado.")
		return
	end
	remote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
			self:_applyState(snapshot.state)
		end
	end)

end

return MovementController
