--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Classes = require(sharedFolder:WaitForChild("Classes"))

local localPlayer = Players.LocalPlayer

type BufferedPunch = { isHeavy: boolean, at: number, flushableSince: number? }

local InputController = {}
InputController._controllers = nil :: { [string]: any }?
InputController._currentState = Constants.PlayerState.InLobby
InputController._bufferedPunch = nil :: BufferedPunch?
InputController._tickConn = nil :: RBXScriptConnection?

-- Combo state: espelha o lado servidor (ver CombatService._activeSwings).
-- Cliente decide proativamente qual move está firando pra poder trocar a anim
-- instantaneamente (antes do server ack). Server valida e pode dropar.
-- Encadeamento dirigido por Move.Next da classe equipada — chaves arbitrárias
-- (Jab1/Jab2... ou Jet1/Jet2/Arabesque...) só importam pra cadeia, não pro
-- protocolo. IASA: durante o cancel window (últimos N seg do swing), input
-- direto cancela o recovery e dispara o próximo move. Inputs durante o
-- committed phase (startup+active) são bufferizados e flushados ao abrir
-- o cancel window — anim do current corta no momento, anim do next entra.
InputController._activeMoveKey = nil :: string?
InputController._swingEndsAt = 0
InputController._cancelOpensAt = 0
InputController._lastMoveKey = nil :: string?
InputController._comboWindowEndsAt = 0

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

function InputController:_isCommitted(now: number): boolean
	-- Committed = startup + active + parte inicial do recovery (até cancelOpensAt).
	-- Durante esse intervalo, input não dispara móve novo: vira buffer.
	return self._activeMoveKey ~= nil and now < self._cancelOpensAt
end

function InputController:_getEquippedClass()
	local controllers = self._controllers
	local shop = controllers and controllers.ShopController
	local classId
	if shop and type(shop.GetEquippedClassId) == "function" then
		classId = shop:GetEquippedClassId()
	else
		classId = Classes.GetDefaultId()
	end
	return Classes.GetClass(classId) or Classes.GetDefault()
end

function InputController:_resolveNextMove(isHeavy: boolean, now: number): string?
	-- Decide qual move iniciar. Retorna moveKey ou nil se precisa bufferizar.
	-- Regra: committed phase = buffer (anim do startup/active deve rodar
	-- inteira). Cancel window aberto = dispara imediatamente, cancelando
	-- o recovery do current.
	if self:_isCommitted(now) then
		return nil
	end
	local class = self:_getEquippedClass()
	local moves = class.Moves
	if isHeavy then
		local key = class.HeavyKey
		if key and moves[key] then
			return key
		end
		return nil
	end
	-- Player livre: se combo window ainda válido, walka chain via Next. Senão
	-- reseta pro starter da classe (Jab1 / Jet1 / etc.).
	if self._lastMoveKey and now < self._comboWindowEndsAt then
		local lastMove = moves[self._lastMoveKey]
		if lastMove and lastMove.Next and moves[lastMove.Next] then
			return lastMove.Next
		end
	end
	return class.ComboStarter
end

function InputController:FirePunch(isHeavy: boolean)
	self:_firePunch(isHeavy)
end

function InputController:_firePunch(isHeavy: boolean)
	if self._currentState ~= Constants.PlayerState.InArena then
		return
	end
	if self:_isBusy() then
		-- Dodge/hitstop: buffer pra respeitar input lenience de 150ms.
		self._bufferedPunch = { isHeavy = isHeavy, at = os.clock() }
		return
	end

	local now = os.clock()
	local moveKey = self:_resolveNextMove(isHeavy, now)
	if not moveKey then
		self._bufferedPunch = { isHeavy = isHeavy, at = now }
		return
	end

	local move = self:_getEquippedClass().Moves[moveKey]
	if not move then
		return
	end

	local remote = Remotes.GetRequestRemote()
	if remote then
		-- clientTime: workspace:GetServerTimeNow() é sincronizado entre cliente
		-- e servidor. Server usa esse valor pra rewind a posição dos alvos na
		-- hora de resolver a hitbox (B1, lag compensation). Não enviamos qual
		-- move foi disparado — server resolve pelo lastCombo dele.
		local clientTime = Workspace:GetServerTimeNow()
		if isHeavy then
			remote:FireServer(Constants.Actions.HeavyPunch, { clientTime = clientTime })
		else
			remote:FireServer(Constants.Actions.Punch, { clientTime = clientTime })
		end
	end

	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch(moveKey)
	end
	local movementController = controllers and controllers.MovementController
	if movementController and type(movementController.StartPunchSwing) == "function" then
		-- Lunge drive dura Startup+Active (char avança durante o windup e o
		-- momento do hit). Lock total cobre o swing inteiro (recovery incluso)
		-- pra travar movimento e facing até a anim terminar.
		local lungeDuration = move.Startup + move.Active
		local totalDuration = lungeDuration + move.Recovery
		movementController:StartPunchSwing(move.LungeSpeed or 0, lungeDuration, totalDuration)
	end

	-- Atualiza estado local pra próximo firePunch/tick.
	local activeEndsAt = now + move.Startup + move.Active
	local swingEndsAt = activeEndsAt + move.Recovery
	self._activeMoveKey = moveKey
	self._swingEndsAt = swingEndsAt
	-- IASA: cancel abre nos últimos CancelPct do recovery (proporcional).
	-- Espelha o lado servidor.
	self._cancelOpensAt = activeEndsAt + move.Recovery * (1 - Constants.Combat.CancelPct)
	self._comboWindowEndsAt = swingEndsAt + move.ComboWindow
	if isHeavy then
		-- Heavy reseta combo chain: próximo M1 começa do starter da classe.
		self._lastMoveKey = nil
	else
		self._lastMoveKey = moveKey
	end
	-- Disparo direto consome qualquer buffer pendente (player já viu o input
	-- ser atendido — buffer antigo viraria input fantasma).
	self._bufferedPunch = nil
end

function InputController:_tryFlushBuffer(now: number)
	local buffered = self._bufferedPunch
	if not buffered then
		return
	end
	-- Buffer sobrevive durante o committed phase (startup+active e parte do
	-- recovery). Quando cancelOpensAt é atingido, vira elegível pra flush e
	-- InputBufferWindow começa a contar — flushableSince marca esse momento.
	-- Resultado: input antigo cancela current no abrir do cancel window;
	-- input que ficou pendurado por mais que InputBufferWindow após isso é
	-- descartado pra evitar ghost input.
	local committed = self:_isCommitted(now)
	if not committed then
		if buffered.flushableSince == nil then
			buffered.flushableSince = now
		end
		if now - buffered.flushableSince > Constants.Combat.InputBufferWindow then
			self._bufferedPunch = nil
			return
		end
	end
	if self:_isBusy() then
		return
	end
	-- Tenta resolver um moveKey agora que passou tempo.
	local moveKey = self:_resolveNextMove(buffered.isHeavy, now)
	if not moveKey then
		return
	end
	self._bufferedPunch = nil
	self:_firePunch(buffered.isHeavy)
end

function InputController:_tickState(now: number)
	-- Fim do swing local: libera inputs subsequentes (bufferizados flush já
	-- no próximo tick). Server faz o mesmo com seu próprio clock; mínima
	-- desincronia é ok porque o server é a autoridade final.
	if self._activeMoveKey and now >= self._swingEndsAt then
		self._activeMoveKey = nil
	end
	-- Combo window expirou: reseta lastMoveKey (próximo M1 começa do starter).
	if self._lastMoveKey and self._activeMoveKey == nil and now >= self._comboWindowEndsAt then
		self._lastMoveKey = nil
	end
end

function InputController:_resetComboState()
	self._activeMoveKey = nil
	self._swingEndsAt = 0
	self._cancelOpensAt = 0
	self._lastMoveKey = nil
	self._comboWindowEndsAt = 0
	self._bufferedPunch = nil
end

function InputController:Start()
	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
				if snapshot.state ~= self._currentState then
					-- Transition Arena↔Lobby descarta buffer + combo state. Sem isso,
					-- player que apertou M1 enquanto morria poderia socar no primeiro
					-- frame da próxima arena, ou continuar combo em outro personagem.
					self:_resetComboState()
				end
				self._currentState = snapshot.state
			end
		end)
	end

	-- Tick loop: roda swing state expiry + buffer flush. Heartbeat ~60Hz é
	-- barato (<1ms/frame); custo negligível mesmo com 50+ players no server.
	self._tickConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		self:_tickState(now)
		if self._bufferedPunch then
			self:_tryFlushBuffer(now)
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
