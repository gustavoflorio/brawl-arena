--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

type MoveData = {
	AnimationId: string,
	Damage: number,
	Range: number,
	BackOffset: number,
	Height: number,
	Depth: number,
	CloseRadius: number,
	Startup: number,
	Active: number,
	Recovery: number,
	ComboWindow: number,
	HitstopBase: number,
	HitstopScale: number,
	HitstopMax: number,
	HitstopAttackerRatio: number,
	KnockbackMult: number,
	LungeSpeed: number,
	HitKind: string,
	Next: string?,
	IsHeavy: boolean,
}

type ActiveSwing = {
	moveKey: string,
	move: MoveData,
	swingId: string,
	startedAt: number,
	activeStartsAt: number,
	activeEndsAt: number,
	recoveryEndsAt: number,
	comboWindowEndsAt: number,
	rewindTime: number, -- timestamp (workspace:GetServerTimeNow()) usado pra lag comp
	hitTargets: { [Player]: boolean },
	phase: string, -- "startup" | "active" | "recovery"
	facing: Vector3?,
}

type LastCombo = {
	moveKey: string,
	windowEndsAt: number,
}

type Snapshot = {
	time: number,
	position: Vector3,
	velocity: Vector3,
}

type PendingDI = {
	inputX: number,
	setAt: number,
	requestCount: number,
	windowStartAt: number,
}

local CombatService = {}
CombatService._services = nil :: Services?
CombatService._activeSwings = {} :: { [Player]: ActiveSwing }
CombatService._lastCombo = {} :: { [Player]: LastCombo }
CombatService._nextDodgeAllowedAt = {} :: { [Player]: number }
CombatService._requestWindow = {} :: { [Player]: { number } }
CombatService._snapshots = {} :: { [Player]: { Snapshot } }
CombatService._pendingDI = {} :: { [Player]: PendingDI }
CombatService._heartbeatConn = nil :: RBXScriptConnection?

local function getCharacterRoot(player: Player): BasePart?
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

local function isAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	return humanoid.Health > 0
end

local function isInvincible(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local until_ = character:GetAttribute(Constants.CharacterAttributes.InvincibleUntil)
	if typeof(until_) ~= "number" then
		return false
	end
	return os.clock() < until_
end

local function resolveFacing(root: BasePart): Vector3
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

function CombatService:_checkRateLimit(player: Player): boolean
	local window = self._requestWindow[player]
	if not window then
		window = {}
		self._requestWindow[player] = window
	end
	local now = os.clock()
	local cutoff = now - Constants.Combat.RateLimitWindow
	local compact: { number } = {}
	for _, timestamp in ipairs(window) do
		if timestamp >= cutoff then
			table.insert(compact, timestamp)
		end
	end
	if #compact >= Constants.Combat.RateLimitMaxRequests then
		self._requestWindow[player] = compact
		return false
	end
	table.insert(compact, now)
	self._requestWindow[player] = compact
	return true
end

-- ===== Lag compensation =====

function CombatService:_captureSnapshots()
	-- Roda em Heartbeat. Guarda um snapshot de posição/velocity por player em
	-- arena. Ring buffer de ~0.5s (30 entries @ 60Hz). GC por time cutoff.
	local arenaService = (self._services :: Services).ArenaService
	local now = Workspace:GetServerTimeNow()
	local cutoff = now - Constants.LagComp.SnapshotHistorySeconds

	for _, player in ipairs(Players:GetPlayers()) do
		if arenaService:GetState(player) ~= Constants.PlayerState.InArena then
			if self._snapshots[player] then
				self._snapshots[player] = nil
			end
			continue
		end
		local root = getCharacterRoot(player)
		if not root then
			continue
		end
		local history = self._snapshots[player]
		if not history then
			history = {}
			self._snapshots[player] = history
		end
		table.insert(history, {
			time = now,
			position = root.Position,
			velocity = root.AssemblyLinearVelocity,
		})
		while history[1] and history[1].time < cutoff do
			table.remove(history, 1)
		end
	end
end

function CombatService:_getSnapshotPosition(player: Player, atTime: number): Vector3?
	-- Retorna a posição do player no snapshot mais recente <= atTime.
	-- Linear reverse walk; com history de ~30 entries, custo negligível.
	local history = self._snapshots[player]
	if not history or #history == 0 then
		return nil
	end
	for i = #history, 1, -1 do
		if history[i].time <= atTime then
			return history[i].position
		end
	end
	return history[1].position
end

local function pointInHitbox(point: Vector3, origin: Vector3, facing: Vector3, move: MoveData): boolean
	-- Close-range sphere: independente de facing (protege contra chars grudados).
	local delta = point - origin
	if delta.Magnitude <= move.CloseRadius then
		return true
	end
	-- Directional box: retângulo axis-aligned XY com depth limitada em Z.
	local back = move.BackOffset
	local totalLength = move.Range + back
	local centerOffset = (move.Range - back) / 2
	local boxCenter = origin + Vector3.new(facing.X * centerOffset, 0, 0)
	local localPoint = point - boxCenter
	return math.abs(localPoint.X) <= totalLength / 2
		and math.abs(localPoint.Y) <= move.Height / 2
		and math.abs(localPoint.Z) <= move.Depth / 2
end

function CombatService:_findTargets(
	puncher: Player,
	origin: Vector3,
	facing: Vector3,
	move: MoveData,
	rewindTime: number
): { Player }
	-- Manual point-in-hitbox com lag compensation: pra cada player elegível,
	-- testa a posição dele NO TEMPO DO CLIENTE (snapshot rewind). Sem fallback
	-- de OverlapParams: no side-scroller 2D com <10 players, manual é mais
	-- barato e determinístico pro rewind.
	local arenaService = (self._services :: Services).ArenaService
	local results: { Player } = {}

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == puncher then
			continue
		end
		if arenaService:GetState(targetPlayer) ~= Constants.PlayerState.InArena then
			continue
		end
		if not isAlive(targetPlayer) then
			continue
		end
		if isInvincible(targetPlayer) then
			continue
		end
		local targetPos = self:_getSnapshotPosition(targetPlayer, rewindTime)
		if not targetPos then
			-- Fallback pra posição atual se snapshots não chegaram ainda
			-- (player que acabou de spawnar, snapshot ring está vazio).
			local root = getCharacterRoot(targetPlayer)
			if not root then
				continue
			end
			targetPos = root.Position
		end
		if pointInHitbox(targetPos, origin, facing, move) then
			table.insert(results, targetPlayer)
		end
	end

	return results
end

local function bumpSeqAttribute(character: Model, attrName: string)
	local current = character:GetAttribute(attrName)
	local nextVal = (typeof(current) == "number" and current or 0) + 1
	character:SetAttribute(attrName, nextVal)
end

local function applyHitStop(character: Model, duration: number)
	-- HitStopUntil é lido pelo InputController (bloqueia input) e
	-- pelo CombatFxController (pausa anim + walkspeed). Se hit múltiplo
	-- chegar durante hitstop ativo, preserva o maior deadline.
	local current = character:GetAttribute(Constants.CharacterAttributes.HitStopUntil)
	local target = os.clock() + duration
	if typeof(current) == "number" and current > target then
		target = current
	end
	character:SetAttribute(Constants.CharacterAttributes.HitStopUntil, target)
	bumpSeqAttribute(character, Constants.CharacterAttributes.HitStopSeq)
end

function CombatService:_applyDI(kbVelocity: Vector3, inputX: number): Vector3
	-- B2: rotaciona o knockback no plano XY baseado no input horizontal do
	-- alvo durante o hitstop. Smash-style: oposto ao KB → deflete pra cima
	-- (ganha altura, evita blastzone horizontal); mesma direção → deflete
	-- pra baixo (skims o chão, recupera ground bem). Escala linear com |inputX|.
	if math.abs(inputX) < 0.1 then
		return kbVelocity
	end
	local kbX = kbVelocity.X
	if math.abs(kbX) < 0.1 then
		-- knockback puramente vertical: DI horizontal não faz sentido.
		return kbVelocity
	end
	local inputMag = math.clamp(math.abs(inputX), 0, 1)
	local sameDirection = (kbX > 0 and inputX > 0) or (kbX < 0 and inputX < 0)
	local angleDeg
	if sameDirection then
		angleDeg = Constants.DI.MaxAngleSameDeg * inputMag
	else
		angleDeg = Constants.DI.MaxAngleOppositeDeg * inputMag
	end
	local angle = math.rad(angleDeg)
	-- KB pra esquerda inverte o sentido da rotação pra manter a semântica
	-- "deflete pra cima" consistente (sem isso, oposto lateralmente ia invertido).
	if kbX < 0 then
		angle = -angle
	end
	local cosA = math.cos(angle)
	local sinA = math.sin(angle)
	return Vector3.new(
		kbVelocity.X * cosA - kbVelocity.Y * sinA,
		kbVelocity.X * sinA + kbVelocity.Y * cosA,
		0
	)
end

function CombatService:_applyHit(puncher: Player, target: Player, facing: Vector3, move: MoveData)
	local arenaService = (self._services :: Services).ArenaService
	local punchRoot = getCharacterRoot(puncher)
	local targetRoot = getCharacterRoot(target)
	if not punchRoot or not targetRoot then
		return
	end

	arenaService:AddDamage(target, move.Damage)
	local damagePercent = arenaService:GetDamage(target)

	-- Knockback: fórmula padrão (base * (1 + dmg% * growth)) modulada pelo
	-- multiplicador do move. Jab1 empurra pouco (0.55x); jab3/heavy finalizam (1.35-1.5x).
	local speed = Constants.Combat.KnockbackBase * (1 + (damagePercent / 100) * Constants.Combat.KnockbackGrowth)
		* move.KnockbackMult
	local kbVelocity = facing * speed + Vector3.new(0, Constants.Combat.KnockbackVertical, 0)

	-- S1: hitstop escalado por damage% acumulado do alvo. Light em alvo fresco
	-- ≈ 100ms (acima do limiar perceptual de impacto); heavy em alvo perto do
	-- KO ≈ 300-400ms (sensação de peso crescendo conforme % sobe).
	local targetHitStop = math.clamp(
		move.HitstopBase + damagePercent * move.HitstopScale,
		move.HitstopBase,
		move.HitstopMax
	)
	local puncherHitStop = targetHitStop * move.HitstopAttackerRatio

	local targetCharacter = target.Character
	local puncherCharacter = puncher.Character

	if targetCharacter then
		-- HitKind antes de incrementar HitSeq: client lê kind atomicamente
		-- junto com o trigger (mesmo frame).
		targetCharacter:SetAttribute(Constants.CharacterAttributes.HitKind, move.HitKind)
		bumpSeqAttribute(targetCharacter, Constants.CharacterAttributes.HitSeq)
		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitterId, puncher.UserId)
		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitTime, os.clock())

		applyHitStop(targetCharacter, targetHitStop)

		-- Knockback aplicado APÓS o hitstop do target terminar. Sem o delay,
		-- client do target aplica AssemblyLinearVelocity enquanto anim está
		-- congelada → char voa em pose de soco. Smash congela posições
		-- durante hitlag; no Roblox simulamos atrasando a velocity.
		-- DI é lida APENAS no momento da aplicação (depois do hitstop), dando
		-- ao cliente do target a janela inteira pra mandar updates de input.
		local kbAttr = Constants.CharacterAttributes.KBVelocity
		local kbSeqAttr = Constants.CharacterAttributes.KBSeq
		task.delay(targetHitStop, function()
			local current = target.Character
			if current ~= targetCharacter or not current.Parent then
				return
			end
			local finalKB = kbVelocity
			local diEntry = self._pendingDI[target]
			if diEntry and os.clock() - diEntry.setAt < Constants.DI.FreshnessSeconds then
				finalKB = self:_applyDI(kbVelocity, diEntry.inputX)
			end
			current:SetAttribute(kbAttr, finalKB)
			bumpSeqAttribute(current, kbSeqAttr)
		end)
	end

	if puncherCharacter then
		applyHitStop(puncherCharacter, puncherHitStop)
	end

	arenaService:PublishState(target)
end

function CombatService:_resolveRequestedMove(player: Player, requestedKey: string): string?
	-- Combo sem cancel: durante swing, NENHUM novo move é aceito. Cliente
	-- buferiza. Jab2/Jab3 só encadeiam DEPOIS do swing anterior completar
	-- (lastCombo set pelo _tickSwings). Isso preserva integridade visual
	-- da animação inteira — jab1 sempre roda até o fim antes do jab2.
	local active = self._activeSwings[player]
	local last = self._lastCombo[player]
	local now = os.clock()
	local moves = Constants.Combat.Moves

	if not moves[requestedKey] then
		return nil
	end

	-- Qualquer swing em andamento bloqueia (sem IASA).
	if active then
		return nil
	end

	if requestedKey == "Heavy" then
		return "Heavy"
	elseif requestedKey == "Jab1" then
		return "Jab1"
	elseif requestedKey == "Jab2" then
		if last ~= nil and last.moveKey == "Jab1" and now < last.windowEndsAt then
			return "Jab2"
		end
		return nil
	elseif requestedKey == "Jab3" then
		if last ~= nil and last.moveKey == "Jab2" and now < last.windowEndsAt then
			return "Jab3"
		end
		return nil
	end

	return nil
end

function CombatService:_startSwing(player: Player, moveKey: string, clientTime: number?)
	local move = Constants.Combat.Moves[moveKey] :: MoveData
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()

	-- Resolve rewindTime pra lag compensation. Cliente manda o tempo em que
	-- ele *viu* o swing disparar; clampamos contra abuso (>250ms = rejeitado
	-- pro presente). Se cliente não mandou, usa now (sem compensação).
	local rewindTime = serverNow
	if clientTime then
		local maxRewind = Constants.LagComp.MaxRewindSeconds
		rewindTime = math.clamp(clientTime, serverNow - maxRewind, serverNow)
	end

	self._activeSwings[player] = {
		moveKey = moveKey,
		move = move,
		swingId = HttpService:GenerateGUID(false),
		startedAt = now,
		activeStartsAt = now + move.Startup,
		activeEndsAt = now + move.Startup + move.Active,
		recoveryEndsAt = now + move.Startup + move.Active + move.Recovery,
		comboWindowEndsAt = now + move.Startup + move.Active + move.Recovery + move.ComboWindow,
		rewindTime = rewindTime,
		hitTargets = {},
		phase = "startup",
		facing = nil,
	}
	-- Ao iniciar novo swing, limpa lastCombo (evita double-accept no próximo tick).
	self._lastCombo[player] = nil
end

function CombatService:_tickSwings()
	local now = os.clock()
	local arenaService = (self._services :: Services).ArenaService

	for player, swing in pairs(self._activeSwings) do
		-- Player saiu de arena ou morreu: aborta swing.
		if arenaService:GetState(player) ~= Constants.PlayerState.InArena then
			self._activeSwings[player] = nil
			continue
		end

		-- Startup → Active: resolve facing no momento em que hitbox acorda.
		-- Permite player virar durante o windup (mesmo princípio Smash).
		if swing.phase == "startup" and now >= swing.activeStartsAt then
			local root = getCharacterRoot(player)
			if root then
				swing.facing = resolveFacing(root)
			end
			swing.phase = "active"
		end

		-- Active: testa hitbox a cada tick. Dedup por swingId (hitTargets):
		-- um alvo só leva hit uma vez no swing, mesmo com hitbox viva por
		-- múltiplos frames (A1). Usa lag comp rewindTime salvo no swing.
		if swing.phase == "active" then
			local root = getCharacterRoot(player)
			if root and swing.facing then
				local targets = self:_findTargets(player, root.Position, swing.facing, swing.move, swing.rewindTime)
				for _, target in ipairs(targets) do
					if not swing.hitTargets[target] then
						swing.hitTargets[target] = true
						self:_applyHit(player, target, swing.facing, swing.move)
					end
				end
			end
			if now >= swing.activeEndsAt then
				swing.phase = "recovery"
			end
		end

		-- Recovery → Done: arma lastCombo pra validar próximo jab do chain.
		if swing.phase == "recovery" and now >= swing.recoveryEndsAt then
			self._lastCombo[player] = {
				moveKey = swing.moveKey,
				windowEndsAt = swing.comboWindowEndsAt,
			}
			self._activeSwings[player] = nil
		end
	end

	-- GC do lastCombo expirado.
	for player, combo in pairs(self._lastCombo) do
		if now > combo.windowEndsAt then
			self._lastCombo[player] = nil
		end
	end
end

function CombatService:_handlePunchRequest(player: Player, requestedMoveKey: string, clientTime: number?)
	local arenaService = (self._services :: Services).ArenaService
	if arenaService:GetState(player) ~= Constants.PlayerState.InArena then
		return
	end
	if not self:_checkRateLimit(player) then
		return
	end
	local resolved = self:_resolveRequestedMove(player, requestedMoveKey)
	if not resolved then
		return
	end
	self:_startSwing(player, resolved, clientTime)
end

function CombatService:_handleDIRequest(player: Player, inputX: number)
	-- Rate limit dedicado pro DI (4 updates/s). Cliente reenvia se input
	-- muda durante hitstop, mas spam é bloqueado.
	local now = os.clock()
	local entry = self._pendingDI[player]
	if not entry then
		entry = { inputX = 0, setAt = 0, requestCount = 0, windowStartAt = now }
		self._pendingDI[player] = entry
	end
	if now - entry.windowStartAt > 1.0 then
		entry.requestCount = 0
		entry.windowStartAt = now
	end
	if entry.requestCount >= Constants.DI.RateLimitMaxRequests then
		return
	end
	entry.requestCount += 1
	entry.inputX = math.clamp(inputX, -1, 1)
	entry.setAt = now
end

local function setDescendantCollisionGroup(character: Model, groupName: string)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

function CombatService:_handleDodgeRoll(player: Player)
	local arenaService = (self._services :: Services).ArenaService
	if arenaService:GetState(player) ~= Constants.PlayerState.InArena then
		return
	end

	local now = os.clock()
	local nextAllowed = self._nextDodgeAllowedAt[player] or 0
	if now < nextAllowed then
		return
	end
	self._nextDodgeAllowedAt[player] = now + Constants.Combat.DodgeRollCooldown

	local character = player.Character
	if not character then
		return
	end
	local invulnUntil = now + Constants.Combat.DodgeRollDurationSeconds
	local current = character:GetAttribute(Constants.CharacterAttributes.InvincibleUntil)
	if typeof(current) ~= "number" then
		current = 0
	end
	character:SetAttribute(Constants.CharacterAttributes.InvincibleUntil, math.max(current, invulnUntil))

	-- Atravessa outros players durante o dodge: troca collision group e
	-- restaura ao fim. Captura referência do character pra não restaurar
	-- em um respawn se player morrer durante o dodge.
	setDescendantCollisionGroup(character, Constants.CollisionGroups.PlayersDodging)
	task.delay(Constants.Combat.DodgeRollDurationSeconds, function()
		if player.Character == character and character.Parent then
			setDescendantCollisionGroup(character, Constants.CollisionGroups.Players)
		end
	end)
end

function CombatService:Init(services: Services)
	self._services = services
end

function CombatService:Start()
	local requestRemote = Remotes.GetRequestRemote()
	if not requestRemote then
		warn("[CombatService] BrawlRequest remote não encontrado.")
		return
	end
	requestRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
		if action == Constants.Actions.Punch then
			local comboIndex = 1
			local clientTime: number? = nil
			if typeof(payload) == "table" then
				if typeof(payload.comboIndex) == "number" then
					comboIndex = math.clamp(math.floor(payload.comboIndex), 1, 3)
				end
				if typeof(payload.clientTime) == "number" then
					clientTime = payload.clientTime
				end
			end
			local moveKey = "Jab" .. tostring(comboIndex)
			self:_handlePunchRequest(player, moveKey, clientTime)
		elseif action == Constants.Actions.HeavyPunch then
			local clientTime: number? = nil
			if typeof(payload) == "table" and typeof(payload.clientTime) == "number" then
				clientTime = payload.clientTime
			end
			self:_handlePunchRequest(player, "Heavy", clientTime)
		elseif action == Constants.Actions.DodgeRoll then
			self:_handleDodgeRoll(player)
		elseif action == Constants.Actions.DI then
			if typeof(payload) == "table" and typeof(payload.inputX) == "number" then
				self:_handleDIRequest(player, payload.inputX)
			end
		end
	end)

	-- Single global tick loop: captura snapshots de posição primeiro (pra
	-- que o tick lhe use valores do frame atual) e roda o ticker de swings
	-- depois. Heartbeat ~60Hz; custo combinado <1ms/frame com <20 players.
	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_captureSnapshots()
		self:_tickSwings()
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._activeSwings[player] = nil
		self._lastCombo[player] = nil
		self._nextDodgeAllowedAt[player] = nil
		self._requestWindow[player] = nil
		self._snapshots[player] = nil
		self._pendingDI[player] = nil
	end)
end

return CombatService
