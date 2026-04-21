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
MovementController._controllers = nil :: { [string]: any }?
MovementController._lockConnection = nil :: RBXScriptConnection?
MovementController._runAnimConnection = nil :: RBXScriptConnection?
MovementController._dodgeDriveConnection = nil :: RBXScriptConnection?
MovementController._currentState = Constants.PlayerState.InLobby
MovementController._hasDoubleJumped = false
MovementController._wasGrounded = true
MovementController._dodgeUntil = 0
MovementController._savedWalkSpeed = 16
MovementController._savedAutoRotate = true

local Z_LOCK = Constants.Arena.AxisLockValue
local ACTION_JUMP = "BrawlArenaJump"
local ACTION_DODGE = "BrawlArenaDodge"

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

function MovementController:_fxController(): any?
	local controllers = self._controllers
	return controllers and controllers.CombatFxController
end

function MovementController:IsDodging(): boolean
	return os.clock() < self._dodgeUntil
end

local function resolveFacingVector(root: BasePart, humanoid: Humanoid?): Vector3
	local moveDirection = humanoid and humanoid.MoveDirection or Vector3.zero
	if moveDirection.Magnitude > 0.1 then
		local x = moveDirection.X
		if x > 0.1 then
			return Vector3.new(1, 0, 0)
		elseif x < -0.1 then
			return Vector3.new(-1, 0, 0)
		end
	end
	local look = root.CFrame.LookVector
	if look.X > 0.1 then
		return Vector3.new(1, 0, 0)
	elseif look.X < -0.1 then
		return Vector3.new(-1, 0, 0)
	end
	local vel = root.AssemblyLinearVelocity
	if vel.X > 0.5 then
		return Vector3.new(1, 0, 0)
	elseif vel.X < -0.5 then
		return Vector3.new(-1, 0, 0)
	end
	return Vector3.new(1, 0, 0)
end

function MovementController:_handleJump(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if self:IsDodging() then
		return Enum.ContextActionResult.Sink
	end
	local humanoid = getHumanoid()
	if not humanoid then
		return Enum.ContextActionResult.Sink
	end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		self._hasDoubleJumped = false
	elseif not self._hasDoubleJumped then
		self._hasDoubleJumped = true
		local root = getRoot()
		if root then
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, Constants.Combat.DoubleJumpVelocity, 0)
		end
		local fx = self:_fxController()
		if fx and type(fx.PlayDoubleJump) == "function" then
			fx:PlayDoubleJump()
		end
	end
	return Enum.ContextActionResult.Sink
end

function MovementController:_startDodgeDrive(humanoid: Humanoid, root: BasePart, facing: Vector3)
	if self._dodgeDriveConnection then
		self._dodgeDriveConnection:Disconnect()
	end
	local speed = self._savedWalkSpeed
	self._dodgeDriveConnection = RunService.Heartbeat:Connect(function()
		if not self:IsDodging() or not root.Parent then
			return
		end
		local currentVel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(facing.X * speed, currentVel.Y, 0)
	end)
end

function MovementController:_endDodgeDrive(humanoid: Humanoid?)
	if self._dodgeDriveConnection then
		self._dodgeDriveConnection:Disconnect()
		self._dodgeDriveConnection = nil
	end
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = self._savedWalkSpeed
		humanoid.AutoRotate = self._savedAutoRotate
	end
end

function MovementController:_handleDodge(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if self:IsDodging() then
		return Enum.ContextActionResult.Sink
	end
	local humanoid = getHumanoid()
	local root = getRoot()
	if not humanoid or not root then
		return Enum.ContextActionResult.Sink
	end

	local remote = Remotes.GetRequestRemote()
	if remote then
		remote:FireServer(Constants.Actions.DodgeRoll)
	end
	local fx = self:_fxController()
	if fx and type(fx.PlayDodgeRoll) == "function" then
		fx:PlayDodgeRoll()
	end

	local duration = Constants.Combat.DodgeRollDurationSeconds
	self._dodgeUntil = os.clock() + duration
	self._savedWalkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
	self._savedAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	local facing = resolveFacingVector(root, humanoid)
	self:_startDodgeDrive(humanoid, root, facing)

	task.delay(duration, function()
		if os.clock() >= self._dodgeUntil - 0.01 then
			self:_endDodgeDrive(humanoid)
		end
	end)

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

	if not self._runAnimConnection then
		self._runAnimConnection = RunService.Heartbeat:Connect(function()
			local humanoid = getHumanoid()
			if not humanoid then
				return
			end
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			if grounded and not self._wasGrounded then
				self._hasDoubleJumped = false
			end
			self._wasGrounded = grounded

			local fx = self:_fxController()
			if not fx then
				return
			end
			local moving = humanoid.MoveDirection.Magnitude > 0.1 and grounded
			if moving then
				if type(fx.PlayRunning) == "function" then
					fx:PlayRunning()
				end
			else
				if type(fx.StopRunning) == "function" then
					fx:StopRunning()
				end
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
		ACTION_DODGE,
		function(name, state, input)
			return self:_handleDodge(name, state, input)
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
	if self._runAnimConnection then
		self._runAnimConnection:Disconnect()
		self._runAnimConnection = nil
	end
	self:_endDodgeDrive(getHumanoid())
	self._dodgeUntil = 0
	local fx = self:_fxController()
	if fx and type(fx.StopRunning) == "function" then
		fx:StopRunning()
	end
	self._hasDoubleJumped = false
	ContextActionService:UnbindAction(ACTION_JUMP)
	ContextActionService:UnbindAction(ACTION_DODGE)
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

function MovementController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

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

	player.CharacterAdded:Connect(function()
		self._hasDoubleJumped = false
		self._wasGrounded = true
		self._dodgeUntil = 0
		if self._dodgeDriveConnection then
			self._dodgeDriveConnection:Disconnect()
			self._dodgeDriveConnection = nil
		end
	end)
end

return MovementController
