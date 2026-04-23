--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer

type BufferedPunch = { isHeavy: boolean, at: number }

local InputController = {}
InputController._controllers = nil :: { [string]: any }?
InputController._currentState = Constants.PlayerState.InLobby
InputController._bufferedPunch = nil :: BufferedPunch?
InputController._bufferFlushConn = nil :: RBXScriptConnection?

function InputController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

local function getLocalCharacter(): Model?
	return localPlayer.Character
end

local function isHitStopped(): boolean
	local character = getLocalCharacter()
	if not character then
		return false
	end
	local until_ = character:GetAttribute(Constants.CharacterAttributes.HitStopUntil)
	if typeof(until_) ~= "number" then
		return false
	end
	return os.clock() < until_
end

function InputController:_isBusy(): boolean
	local controllers = self._controllers
	local movementController = controllers and controllers.MovementController
	if movementController and type(movementController.IsDodging) == "function" then
		if movementController:IsDodging() then
			return true
		end
	end
	-- Hitstop bloqueia punch + dodge do próprio player. Sem isso, target
	-- tomaria hit e imediatamente daria dodge roll escapando combos via
	-- i-frame — comportamento errado pra fighter.
	if isHitStopped() then
		return true
	end
	return false
end

function InputController:FirePunch(isHeavy: boolean)
	self:_firePunch(isHeavy)
end

function InputController:_firePunch(isHeavy: boolean)
	if self._currentState ~= Constants.PlayerState.InArena then
		return
	end
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	local punching = fxController and type(fxController.IsPunching) == "function" and fxController:IsPunching()

	if self:_isBusy() or punching then
		-- Tenta buffer: se está prestes a terminar, armazena pra consumir
		-- no próximo frame free. Evita drop de inputs dados 100-150ms antes
		-- do fim da animação.
		self._bufferedPunch = { isHeavy = isHeavy, at = os.clock() }
		return
	end

	local remote = Remotes.GetRequestRemote()
	if remote then
		local action = isHeavy and Constants.Actions.HeavyPunch or Constants.Actions.Punch
		remote:FireServer(action)
	end
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch(isHeavy)
	end
	local movementController = controllers and controllers.MovementController
	if movementController and type(movementController.StartPunchLock) == "function" then
		local lockDuration = isHeavy and Constants.Combat.HeavyPunchStartupLockSeconds
			or Constants.Combat.PunchStartupLockSeconds
		movementController:StartPunchLock(lockDuration)
	end
end

function InputController:_tryFlushBuffer()
	local buffered = self._bufferedPunch
	if not buffered then
		return
	end
	-- Buffer expira se ficou na fila mais que InputBufferWindow. Mesmo
	-- princípio de fighting games: input muito antigo não deve disparar.
	if os.clock() - buffered.at > Constants.Combat.InputBufferWindow then
		self._bufferedPunch = nil
		return
	end
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	local punching = fxController and type(fxController.IsPunching) == "function" and fxController:IsPunching()
	if punching or self:_isBusy() then
		return
	end
	self._bufferedPunch = nil
	self:_firePunch(buffered.isHeavy)
end

function InputController:Start()
	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
				if snapshot.state ~= self._currentState then
					-- Transition Arena↔Lobby deve descartar buffer. Sem isso,
					-- player que apertou M1 enquanto morria poderia socar
					-- no primeiro frame da próxima arena.
					self._bufferedPunch = nil
				end
				self._currentState = snapshot.state
			end
		end)
	end

	-- Tick loop para consumir buffer quando janela abrir. Check barato
	-- (só flag + timestamp), roda sempre que há input pendente.
	self._bufferFlushConn = RunService.Heartbeat:Connect(function()
		if self._bufferedPunch then
			self:_tryFlushBuffer()
		end
	end)

	-- M2 é consumido pelo default camera rotation script (processed=true),
	-- mas queremos firar heavy punch mesmo assim — por isso não checamos
	-- processed pra MouseButton2. M1 respeita processed pra não firar
	-- punch quando clicando em UI (ex: donate button).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if self._currentState ~= Constants.PlayerState.InArena then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if processed then
				return
			end
			self:_firePunch(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_firePunch(true)
		end
	end)
end

return InputController
