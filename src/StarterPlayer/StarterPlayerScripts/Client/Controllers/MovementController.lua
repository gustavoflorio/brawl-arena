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
MovementController._dodgeCooldownUntil = 0
MovementController._savedWalkSpeed = 16
MovementController._punchSwingUntil = 0
MovementController._punchSwingSavedWalkSpeed = 16
MovementController._punchSwingActive = false
MovementController._punchLungeConnection = nil :: RBXScriptConnection?
MovementController._punchLungeAttachment = nil :: Attachment?
MovementController._punchLungeConstraint = nil :: LinearVelocity?
MovementController._hitStopUntil = 0
MovementController._hitStopSavedWalkSpeed = 16
MovementController._hitStopActive = false

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

function MovementController:IsDodging(): boolean
	return os.clock() < self._dodgeUntil
end

function MovementController:GetDodgeCooldownRemaining(): number
	local remaining = self._dodgeCooldownUntil - os.clock()
	if remaining < 0 then
		return 0
	end
	return remaining
end

function MovementController:IsDodgeReady(): boolean
	return os.clock() >= self._dodgeCooldownUntil
end

function MovementController:IsPunchSwinging(): boolean
	return os.clock() < self._punchSwingUntil
end

function MovementController:IsHitStopped(): boolean
	return os.clock() < self._hitStopUntil
end

function MovementController:StartHitStopLock(duration: number)
	-- Mesma pattern do PunchSwing: salva walkspeed, zera, restaura no fim.
	-- Hits consecutivos só extendem o deadline (maior dos dois vale).
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	local now = os.clock()
	local until_ = now + duration
	if self._hitStopActive then
		self._hitStopUntil = math.max(self._hitStopUntil, until_)
		return
	end
	-- Se o punch swing já zerou walkspeed, não precisamos salvar de novo
	-- (senão salvaríamos 0 e restauraríamos 0 ao final do hitstop).
	local baseSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or Constants.PlayerMovement.WalkSpeed
	self._hitStopSavedWalkSpeed = baseSpeed
	self._hitStopUntil = until_
	self._hitStopActive = true
	humanoid.WalkSpeed = 0
	task.delay(duration, function()
		if os.clock() >= self._hitStopUntil - 0.01 and self._hitStopActive then
			local h = getHumanoid()
			if h and h.Parent and not self._punchSwingActive then
				h.WalkSpeed = self._hitStopSavedWalkSpeed
			end
			self._hitStopActive = false
			self._hitStopUntil = 0
		end
	end)
end

function MovementController:_endPunchLunge()
	if self._punchLungeConnection then
		self._punchLungeConnection:Disconnect()
		self._punchLungeConnection = nil
	end
	if self._punchLungeConstraint then
		self._punchLungeConstraint:Destroy()
		self._punchLungeConstraint = nil
	end
	if self._punchLungeAttachment then
		self._punchLungeAttachment:Destroy()
		self._punchLungeAttachment = nil
	end
end

local function isLungeBlockedByOtherPlayer(root: BasePart, facing: Vector3, blockRadius: number): boolean
	-- Checa se há outro player à frente (na direção do facing) dentro do
	-- blockRadius no plano XY. Serve pra impedir que o lunge atravesse
	-- oponentes — LinearVelocity com MaxForce=huge ignora colisões de physics,
	-- então validamos manualmente.
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player then
			continue
		end
		local char = other.Character
		if not char then
			continue
		end
		local otherRoot = char:FindFirstChild("HumanoidRootPart")
		if not otherRoot or not otherRoot:IsA("BasePart") then
			continue
		end
		local delta = otherRoot.Position - root.Position
		-- Ignora se o outro player está atrás do atacante no eixo do facing.
		if delta.X * facing.X <= 0 then
			continue
		end
		-- Distância 2D (X + Y) — Y pra evitar parar em player que tá em
		-- platform muito acima/abaixo.
		local dist2d = Vector2.new(delta.X, delta.Y).Magnitude
		if dist2d < blockRadius then
			return true
		end
	end
	return false
end

function MovementController:_startPunchLunge(facing: Vector3, lungeSpeed: number, lungeDuration: number)
	-- Lunge via LinearVelocity constraint (physics-engine puro), NÃO via
	-- Humanoid:Move ou AssemblyLinearVelocity direto. Motivo: o PlayerModule
	-- default chama humanoid:Move(inputDir) a cada RenderStepped — tanto
	-- Heartbeat quanto Stepped perdem essa corrida, e com WalkSpeed=0 o
	-- Humanoid ainda aplica damping cancelando velocity manual. LinearVelocity
	-- com MaxForce=huge é aplicado pela physics engine independente do
	-- Humanoid, sobrepujando qualquer force contrária e input do player.
	-- Line mode restringe só o eixo X do facing; Y/Z livres pra gravidade/jump.
	-- Pausa durante hitstop: LineVelocity=0 (constraint continua ativo mas não
	-- empurra), retoma ao fim do hitstop.
	self:_endPunchLunge()
	if lungeSpeed <= 0 or lungeDuration <= 0 then
		return
	end
	local root = getRoot()
	if not root then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "BrawlLungeAttachment"
	attachment.Parent = root

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "BrawlLungeVelocity"
	linearVel.Attachment0 = attachment
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVel.LineDirection = Vector3.new(facing.X, 0, 0)
	linearVel.LineVelocity = lungeSpeed
	linearVel.MaxForce = math.huge
	linearVel.Parent = root

	self._punchLungeAttachment = attachment
	self._punchLungeConstraint = linearVel

	local lungeUntil = os.clock() + lungeDuration

	self._punchLungeConnection = RunService.Heartbeat:Connect(function()
		if not root.Parent or not self._punchLungeConstraint then
			self:_endPunchLunge()
			return
		end
		if os.clock() >= lungeUntil then
			-- Fim do lunge: constraint removido, char para no resto do swing.
			self:_endPunchLunge()
			return
		end
		-- Block check: outro player à frente dentro do blockRadius aborta o
		-- lunge pra evitar atravessar o oponente. Hit ainda conecta (server
		-- resolve via hitbox no seu próprio clock).
		if isLungeBlockedByOtherPlayer(root, facing, Constants.Combat.LungeBlockRadius) then
			self:_endPunchLunge()
			-- Zera velocity horizontal pra char parar instantaneamente no
			-- ponto de contato (senão deslizaria mais alguns frames por inércia).
			local currentVel = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, currentVel.Y, 0)
			return
		end
		if self:IsHitStopped() then
			-- Pausa: constraint segue parented mas sem empurrar.
			self._punchLungeConstraint.LineVelocity = 0
		else
			self._punchLungeConstraint.LineVelocity = lungeSpeed
		end
	end)
end

function MovementController:StartPunchSwing(lungeSpeed: number, lungeDuration: number, totalDuration: number)
	-- Lock total durante o swing: WalkSpeed=0 (player não anda inputando A/D)
	-- e AutoRotate=false (char não vira pelo mouse mid-anim, preserva facing
	-- do commit do M1). Lunge drive roda em paralelo aplicando velocity pra
	-- frente durante Startup+Active (lungeDuration).
	local humanoid = getHumanoid()
	local root = getRoot()
	if not humanoid or not root then
		return
	end
	local now = os.clock()
	local until_ = now + totalDuration

	if self._punchSwingActive then
		-- Cliente não emite swings sobrepostos (buffer garante isso), mas por
		-- segurança: extende o deadline e reinicia o lunge drive.
		self._punchSwingUntil = math.max(self._punchSwingUntil, until_)
	else
		self._punchSwingSavedWalkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or Constants.PlayerMovement.WalkSpeed
		self._punchSwingUntil = until_
		self._punchSwingActive = true
		humanoid.WalkSpeed = 0
		-- AutoRotate é false globalmente durante arena (lockConnection).
		-- Facing já está snappped em ±X, não precisa ser resalvo aqui.
	end

	local facing = resolveFacingVector(root, humanoid)
	self:_startPunchLunge(facing, lungeSpeed, lungeDuration)

	task.delay(totalDuration, function()
		-- Só restaura se ainda estamos no mesmo swing window (sem extensão).
		if os.clock() >= self._punchSwingUntil - 0.01 and self._punchSwingActive then
			local h = getHumanoid()
			if h and h.Parent and not self._hitStopActive then
				h.WalkSpeed = self._punchSwingSavedWalkSpeed
			end
			self._punchSwingActive = false
			self._punchSwingUntil = 0
			self:_endPunchLunge()
		end
	end)
end

function MovementController:TryJump()
	-- Entry point para controles mobile custom (D-Pad up). Mantém a mesma
	-- lógica de single/double jump do keybind W sem depender de InputObject.
	self:_handleJump("MobileJump", Enum.UserInputState.Begin, (nil :: any) :: InputObject)
end

function MovementController:TryDodge()
	self:_handleDodge("MobileDodge", Enum.UserInputState.Begin, (nil :: any) :: InputObject)
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
	local speed = self._savedWalkSpeed * Constants.Combat.DodgeRollVelocityMultiplier
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
		-- AutoRotate mantém-se false durante arena (gerenciado por lockConnection).
	end
end

function MovementController:_handleDodge(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if self:IsDodging() or not self:IsDodgeReady() then
		return Enum.ContextActionResult.Sink
	end
	local humanoid = getHumanoid()
	local root = getRoot()
	if not humanoid or not root then
		return Enum.ContextActionResult.Sink
	end

	self._dodgeCooldownUntil = os.clock() + Constants.Combat.DodgeRollCooldown

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
	self._savedWalkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or Constants.PlayerMovement.WalkSpeed
	humanoid.WalkSpeed = 0
	-- AutoRotate já é false globalmente durante arena (lockConnection gerencia).

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
			-- Z axis lock: prende char ao plano Z=0 (side-scroller 2D).
			if math.abs(pos.Z - Z_LOCK) > 0.01 then
				local rotation = root.CFrame - pos
				root.CFrame = CFrame.new(pos.X, pos.Y, Z_LOCK) * rotation
			end
			local velocity = root.AssemblyLinearVelocity
			if math.abs(velocity.Z) > 0.01 then
				root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
			end

			-- Facing lock: força yaw do char em ±90° (LookVector = ±X exato).
			-- Roblox 3D permite rotação livre no eixo Y; AutoRotate default faria
			-- char virar pro cursor (pra -Z em side-scroller → costas pra tela).
			-- Aqui desligamos AutoRotate e snap manual. Direção escolhida por
			-- MoveDirection.X (input A/D); sem input ou durante commit (swing/
			-- dodge/hitstop), preserva lado atual — player não pode girar o char
			-- no meio da anim de soco mudando o input.
			local humanoid = getHumanoid()
			if humanoid then
				if humanoid.AutoRotate then
					humanoid.AutoRotate = false
				end
				local look = root.CFrame.LookVector
				local md = humanoid.MoveDirection
				local facingLocked = self._punchSwingActive
					or self:IsDodging()
					or self:IsHitStopped()
				local targetX: number
				if not facingLocked and md.X > 0.1 then
					targetX = 1
				elseif not facingLocked and md.X < -0.1 then
					targetX = -1
				elseif look.X >= 0 then
					targetX = 1
				else
					targetX = -1
				end
				-- Re-snap só se CFrame diverged (evita overwrite desnecessário
				-- toda frame, que poderia interferir com physics na rotação).
				if look.X * targetX < 0.99 or math.abs(look.Y) > 0.05 or math.abs(look.Z) > 0.05 then
					root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(targetX, 0, 0))
				end
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
	self:_endPunchLunge()
	self:_endDodgeDrive(getHumanoid())
	self._dodgeUntil = 0
	self._punchSwingActive = false
	self._punchSwingUntil = 0
	self._hitStopActive = false
	self._hitStopUntil = 0
	-- Restaura AutoRotate ao sair da arena (no lobby, controle livre).
	local h = getHumanoid()
	if h then
		h.AutoRotate = true
	end
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
