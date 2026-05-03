--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Classes = require(sharedFolder:WaitForChild("Classes"))
local Profiling = require(sharedFolder:WaitForChild("Profiling"))

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
	-- Trap moves: quando TrapDuration > 0, o move funciona como
	-- "captura + DoT" em vez de hit instantâneo. Target leva hitstop pelo
	-- TrapDuration inteiro (não pode mover/atacar/dodgear), Damage é
	-- distribuído entre TrapTicks ao longo do trap, e knockback é skipado
	-- (KnockbackMult ignorado). Ex: 64 palmas — Damage=20, Tick=8 ticks de
	-- 2.5 dmg cada, target preso pela duração toda.
	TrapDuration: number?,
	TrapTicks: number?,
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
	cancelOpensAt: number, -- IASA: cancel-into-next permitido a partir desse tempo
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

type ActiveTrap = {
	trapId: string,
	victim: Player,
	endsAt: number,
}

local CombatService = {}
CombatService._services = nil :: Services?
CombatService._activeSwings = {} :: { [Player]: ActiveSwing }
CombatService._lastCombo = {} :: { [Player]: LastCombo }
CombatService._nextDodgeAllowedAt = {} :: { [Player]: number }
CombatService._requestWindow = {} :: { [Player]: { number } }
CombatService._snapshots = {} :: { [Player]: { Snapshot } }
CombatService._pendingDI = {} :: { [Player]: PendingDI }
-- Active traps (Palmas etc): tracked por puncher pra que tick callbacks pendentes
-- possam ser cancelados quando o puncher é interrompido (e.g., levou um hit no
-- meio do canalize). Cada tick captura trapId no closure e checa contra o atual
-- — mismatch = trap foi cancelada, return.
CombatService._activeTraps = {} :: { [Player]: ActiveTrap }
-- Pendência de cancelamento de swing colhida durante _tickSwings. Set durante
-- a iteração e processado no fim. Permite mutual hits (A e B socam ao mesmo
-- frame) — sem isso, _cancelTargetSwing limparia _activeSwings[target] mid-
-- iteration, e o swing do target era pulado pelo pairs() antes de processar.
CombatService._pendingSwingCancels = nil :: { [Player]: boolean }?
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
	-- InvincibleUntil é setado por ArenaService:TeleportToArena com
	-- Workspace:GetServerTimeNow(). Comparar com os.clock() (server-local
	-- CPU time) gera mismatch enorme — server uptime longo deixa o "until"
	-- na casa dos milhares enquanto os.clock() está em dezenas, retornando
	-- TRUE perpetuamente e bloqueando todos os hits no _findTargets.
	return Workspace:GetServerTimeNow() < until_
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

function CombatService:_getClassFor(player: Player): any
	-- Resolve classe equipada do player. Fallback pra classe default se o
	-- profile ainda não carregou ou se a classe equipada some do registry
	-- (defesa em profundidade — não deveria acontecer com a migration certa).
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	if playerData and playerData.GetEquippedClass then
		local classId = playerData:GetEquippedClass(player)
		local classDef = Classes.GetClass(classId)
		if classDef then
			return classDef
		end
	end
	return Classes.GetDefault()
end

function CombatService:_getMovesFor(player: Player): { [string]: any }
	return self:_getClassFor(player).Moves
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

local function firePulse(eventType: string, character: Model, payload: { [string]: any }?)
	-- Combat events vão por RemoteEvent unificado em vez de seq bumps em
	-- attributes. RemoteEvent dispara imediato (sem batching de ~100ms da
	-- replication queue de attributes), então hits/anims/KB respondem mais
	-- rápido client-side. FireAllClients porque Hit precisa propagar VFX/sound
	-- pra todos os clientes; outros events (HitStop, KB, Elim) são filtrados
	-- client-side por character == localPlayer.Character.
	local remote = Remotes.GetCombatPulseRemote()
	if not remote then
		return
	end
	remote:FireAllClients(eventType, character, payload or {})
end

local function applyHitStop(character: Model, duration: number)
	-- HitStopUntil é lido pelo InputController (bloqueia input) e
	-- pelo CombatFxController (pausa anim + walkspeed). Se hit múltiplo
	-- chegar durante hitstop ativo, preserva o maior deadline.
	-- Usa Workspace:GetServerTimeNow() (sincronizado server↔client) em vez de
	-- os.clock() — este último tem referência por-VM, e o cliente computaria
	-- `remaining = until - os.clock()` contra clock dessincronizado, gerando
	-- valores enormes (dezenas de segundos) e congelando o char até rejoin.
	local current = character:GetAttribute(Constants.CharacterAttributes.HitStopUntil)
	local target = Workspace:GetServerTimeNow() + duration
	if typeof(current) == "number" and current > target then
		target = current
	end
	character:SetAttribute(Constants.CharacterAttributes.HitStopUntil, target)
	firePulse(Constants.CombatPulseTypes.HitStop, character, { until_ = target })
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

function CombatService:_applyTrapHit(puncher: Player, target: Player, move: MoveData)
	-- Trap hit: target preso pela duração do trap, sem knockback. Damage
	-- distribuído entre N ticks ao longo do trap. Cada tick bumpa HitSeq pra
	-- gerar SFX/VFX de palma landing rítmica. HitStop é setado UMA VEZ com
	-- duração total = TrapDuration; ticks só agregam damage.
	-- Cancelable: trapId é registrado em _activeTraps[puncher] e cada tick
	-- valida contra o atual antes de fazer dano. Se o puncher levar hit no
	-- meio do canalize, _cancelTrap zera _activeTraps[puncher] → ticks
	-- pendentes encontram mismatch e abortam, victim é liberado cedo.
	local arenaService = (self._services :: Services).ArenaService
	local targetCharacter = target.Character
	local puncherCharacter = puncher.Character
	if not targetCharacter then
		return
	end

	local trapDuration = move.TrapDuration :: number
	local ticks = move.TrapTicks or 8
	local damagePerTick = move.Damage / ticks
	local interval = trapDuration / ticks

	local trapId = HttpService:GenerateGUID(false)
	self._activeTraps[puncher] = {
		trapId = trapId,
		victim = target,
		endsAt = Workspace:GetServerTimeNow() + trapDuration,
	}

	-- HitKind agora viaja na payload do Hit pulse (cada tick); LastHitterId/Time
	-- ficam em attribute pra kill attribution server-side.
	targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitterId, puncher.UserId)
	targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitTime, os.clock())
	applyHitStop(targetCharacter, trapDuration)

	for i = 1, ticks do
		task.delay((i - 1) * interval, function()
			-- Trap cancelada (puncher tomou hit) → trapId não bate mais.
			local trap = self._activeTraps[puncher]
			if not trap or trap.trapId ~= trapId then
				return
			end
			if target.Character ~= targetCharacter or not targetCharacter.Parent then
				return
			end
			local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			arenaService:AddDamage(target, damagePerTick)
			firePulse(Constants.CombatPulseTypes.Hit, targetCharacter, {
				hitKind = move.HitKind,
				damagePercent = arenaService:GetDamage(target),
			})
			arenaService:PublishState(target)
		end)
	end

	-- Cleanup do registry após o trap terminar naturalmente. Margem de 0.05s
	-- pra garantir que o último tick rodou antes do clear. Idempotente: se o
	-- puncher já iniciou outra trap, trapId mudou e este clear é skipado.
	task.delay(trapDuration + 0.05, function()
		local trap = self._activeTraps[puncher]
		if trap and trap.trapId == trapId then
			self._activeTraps[puncher] = nil
		end
	end)

	-- Puncher leva hitstop curto (confirmação visual de hit), não a duração
	-- inteira do trap — senão o puncher também ficaria parado 4s.
	if puncherCharacter then
		applyHitStop(puncherCharacter, math.min(0.15, move.HitstopBase * move.HitstopAttackerRatio))
	end
end

function CombatService:_cancelTrap(puncher: Player)
	-- Cancela trap ativo do puncher (callbacks pendentes vão bater mismatch
	-- de trapId e abortar) e libera o victim do hitstop cedo. Sem o release,
	-- victim ficaria preso pelo TrapDuration inteiro (ex: 3.5s nas Palmas)
	-- mesmo após o puncher ser interrompido — UX ruim.
	local trap = self._activeTraps[puncher]
	if not trap then
		return
	end
	self._activeTraps[puncher] = nil
	local victim = trap.victim
	if not victim then
		return
	end
	local victimChar = victim.Character
	if not victimChar then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local current = victimChar:GetAttribute(Constants.CharacterAttributes.HitStopUntil)
	if typeof(current) == "number" and current > now then
		-- HitStopUntil ainda é state (lido por InputController.isHitStopped),
		-- mas o sinal de "release agora" vai por pulso explícito —
		-- HitStopRelease dispara EndHitStopLock no cliente sem precisar de
		-- listener no attribute.
		victimChar:SetAttribute(Constants.CharacterAttributes.HitStopUntil, now)
		firePulse(Constants.CombatPulseTypes.HitStopRelease, victimChar, {})
	end
end

function CombatService:_cancelTargetSwing(target: Player)
	-- Target tomou hit: cancela qualquer ataque/trap em andamento. Sem isso,
	-- shaolin canalizando Palmas mantém o trap ativo após levar knockback,
	-- e qualquer combo no recovery continua até o final.
	-- Trap cancel é imediato (sem concern de iteração — _activeTraps é
	-- iterado em loop separado). Já o swing/lastCombo clear é DEFERIDO
	-- durante _tickSwings: limpar _activeSwings[target] no meio do for-pairs
	-- faz o swing do target ser pulado antes de processar mutual hits no
	-- mesmo frame (A↔B socam juntos → só um conecta).
	self:_cancelTrap(target)
	if self._pendingSwingCancels then
		self._pendingSwingCancels[target] = true
	else
		self._activeSwings[target] = nil
		self._lastCombo[target] = nil
	end
end

function CombatService:_applyHit(puncher: Player, target: Player, facing: Vector3, move: MoveData)
	local arenaService = (self._services :: Services).ArenaService
	local punchRoot = getCharacterRoot(puncher)
	local targetRoot = getCharacterRoot(target)
	if not punchRoot or not targetRoot then
		return
	end

	-- "Tomou hit = para de atacar": cancela swing/trap ativos do target ANTES
	-- de aplicar damage/knockback. HitSeq replica e o cliente do target faz
	-- o mirror visual (stop animation, end lunge, clear combo).
	self:_cancelTargetSwing(target)

	-- Trap moves (Palmas etc) tem fluxo separado: prendem o target pela
	-- duração inteira em vez de aplicar hit instantâneo + knockback.
	if move.TrapDuration and move.TrapDuration > 0 then
		self:_applyTrapHit(puncher, target, move)
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
		-- LastHitterId/Time são server-state pra kill attribution; ficam como
		-- attribute. HitKind e damage% vão direto na payload do pulso (sem
		-- precisar de attribute pro cliente ler — recebe no evento).
		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitterId, puncher.UserId)
		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitTime, os.clock())
		firePulse(Constants.CombatPulseTypes.Hit, targetCharacter, {
			hitKind = move.HitKind,
			damagePercent = damagePercent,
		})

		applyHitStop(targetCharacter, targetHitStop)

		-- Knockback aplicado APÓS o hitstop do target terminar. Sem o delay,
		-- client do target aplica AssemblyLinearVelocity enquanto anim está
		-- congelada → char voa em pose de soco. Smash congela posições
		-- durante hitlag; no Roblox simulamos atrasando a velocity.
		-- DI é lida APENAS no momento da aplicação (depois do hitstop), dando
		-- ao cliente do target a janela inteira pra mandar updates de input.
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
			firePulse(Constants.CombatPulseTypes.Knockback, current, {
				velocity = finalKB,
			})
		end)
	end

	if puncherCharacter then
		applyHitStop(puncherCharacter, puncherHitStop)
	end

	arenaService:PublishState(target)
end

function CombatService:_resolveRequestedMove(player: Player, isHeavy: boolean): string?
	-- Encadeamento dirigido por Move.Next: o cliente só sinaliza "punch" ou
	-- "heavy"; o servidor walka a chain a partir do lastCombo pra decidir
	-- qual move é o próximo. IASA: durante o cancel window (últimos N
	-- segundos do recovery, definido por Constants.Combat.CancelWindow), o
	-- próximo move é aceito e substitui o swing atual. Startup+Active
	-- continuam committed pra preservar integridade do hit.
	local active = self._activeSwings[player]
	local now = os.clock()
	if active and now < active.cancelOpensAt then
		return nil
	end

	local class = self:_getClassFor(player)
	local moves = class.Moves

	if isHeavy then
		local key = class.HeavyKey
		if not key or not moves[key] then
			return nil
		end
		return key
	end

	local last = self._lastCombo[player]
	if last == nil or now >= last.windowEndsAt then
		-- Combo zerado: começa pelo starter da classe.
		local key = class.ComboStarter
		if not key or not moves[key] then
			return nil
		end
		return key
	end

	-- Continua chain: lastMove.Next aponta o próximo. nil = chain acabou.
	local lastMove = moves[last.moveKey]
	if not lastMove then
		return nil
	end
	local nextKey = lastMove.Next
	if not nextKey or not moves[nextKey] then
		return nil
	end
	return nextKey
end

function CombatService:_startSwing(player: Player, moveKey: string, clientTime: number?)
	local moves = self:_getMovesFor(player)
	local move = moves[moveKey] :: MoveData
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

	local activeEndsAt = now + move.Startup + move.Active
	local recoveryEndsAt = activeEndsAt + move.Recovery
	-- IASA: cancel abre nos últimos CancelPct do recovery (proporcional ao
	-- tamanho do move). Active phase é sempre committed pra preservar o hit
	-- — a janela é aplicada só dentro do Recovery.
	local cancelOpensAt = activeEndsAt + move.Recovery * (1 - Constants.Combat.CancelPct)

	self._activeSwings[player] = {
		moveKey = moveKey,
		move = move,
		swingId = HttpService:GenerateGUID(false),
		startedAt = now,
		activeStartsAt = now + move.Startup,
		activeEndsAt = activeEndsAt,
		recoveryEndsAt = recoveryEndsAt,
		comboWindowEndsAt = recoveryEndsAt + move.ComboWindow,
		cancelOpensAt = cancelOpensAt,
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

	-- Pending swing cancels: coletados durante a iteração via _cancelTargetSwing
	-- (chamado de _applyHit). Aplicados DEPOIS do for-pairs pra que mutual hits
	-- no mesmo frame ambos processem antes de qualquer swing ser removido.
	local pendingCancels: { [Player]: boolean } = {}
	self._pendingSwingCancels = pendingCancels

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
				-- Active → Recovery: arma lastCombo já aqui (não no fim do
				-- recovery). Sem isso, cancel via IASA encontra lastCombo=nil
				-- e zera o chain — Jet2 viraria Jet1 quando cancelando Jet1.
				self._lastCombo[player] = {
					moveKey = swing.moveKey,
					windowEndsAt = swing.comboWindowEndsAt,
				}
			end
		end

		-- Recovery → Done: limpa active swing. lastCombo já foi setado na
		-- transição active→recovery, então persiste após o swing acabar.
		if swing.phase == "recovery" and now >= swing.recoveryEndsAt then
			self._activeSwings[player] = nil
		end
	end

	-- GC do lastCombo expirado.
	for player, combo in pairs(self._lastCombo) do
		if now > combo.windowEndsAt then
			self._lastCombo[player] = nil
		end
	end

	-- Aplica os cancels de swing colhidos durante o tick. Tem que ser DEPOIS
	-- do for-pairs principal — limpar _activeSwings durante a iteração faria
	-- swings de targets de hits ainda-não-processados sumirem antes de poderem
	-- responder com seus próprios hits (mutual hits viravam single-hit).
	for player in pairs(pendingCancels) do
		self._activeSwings[player] = nil
		self._lastCombo[player] = nil
	end
	self._pendingSwingCancels = nil

	-- GC de traps cuja puncher saiu da arena ou morreu — libera victim.
	for puncher, _ in pairs(self._activeTraps) do
		if arenaService:GetState(puncher) ~= Constants.PlayerState.InArena or not isAlive(puncher) then
			self:_cancelTrap(puncher)
		end
	end
end

function CombatService:_handlePunchRequest(player: Player, isHeavy: boolean, clientTime: number?)
	local arenaService = (self._services :: Services).ArenaService
	if arenaService:GetState(player) ~= Constants.PlayerState.InArena then
		return
	end
	-- Profiling: input latency = serverNow - clientTime. Mede o RTT efetivo
	-- entre o player apertar M1 e o servidor processar a request.
	if clientTime and Profiling.IsEnabled("InputLatency") then
		local delta_ms = (Workspace:GetServerTimeNow() - clientTime) * 1000
		Profiling.Log("InputLatency", {
			action = if isHeavy then "HeavyPunch" else "Punch",
			player = player.Name,
			delta_ms = math.floor(delta_ms + 0.5),
		})
	end
	if not self:_checkRateLimit(player) then
		return
	end
	local resolved = self:_resolveRequestedMove(player, isHeavy)
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

local function setDescendantCollisionGroup(character: Model, bodyGroup: string)
	-- Hitbox volumétrico (PlayerHitbox part) tem ciclo de grupo separado:
	-- durante dodge entra junto no grupo PlayersDodging (passa por tudo);
	-- fora do dodge volta pro próprio grupo PlayerHitbox (que bloca outros
	-- player-hitboxes mas não interage com body parts/terreno).
	local hitboxName = Constants.PlayerHitbox.PartName
	local dodgingGroup = Constants.CollisionGroups.PlayersDodging
	local hitboxGroup = Constants.CollisionGroups.PlayerHitbox
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Name == hitboxName then
				descendant.CollisionGroup = if bodyGroup == dodgingGroup then dodgingGroup else hitboxGroup
			else
				descendant.CollisionGroup = bodyGroup
			end
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
	-- InvincibleUntil precisa estar na MESMA referência de tempo que ArenaService
	-- usa (Workspace:GetServerTimeNow). Misturar os.clock() aqui faria isInvincible
	-- ler um attribute potencialmente setado em duas escalas diferentes — o que
	-- vence é o math.max, e os.clock() perderia sempre, anulando os i-frames
	-- do dodge na prática.
	local serverNow = Workspace:GetServerTimeNow()
	local invulnUntil = serverNow + Constants.Combat.DodgeRollDurationSeconds
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
			-- Cliente só sinaliza "M1 apertado" — chain é resolvida server-side
			-- a partir do _lastCombo. Sem comboIndex no payload: a fonte de
			-- verdade do progresso do combo é o servidor.
			local clientTime: number? = nil
			if typeof(payload) == "table" and typeof(payload.clientTime) == "number" then
				clientTime = payload.clientTime
			end
			self:_handlePunchRequest(player, false, clientTime)
		elseif action == Constants.Actions.HeavyPunch then
			local clientTime: number? = nil
			if typeof(payload) == "table" and typeof(payload.clientTime) == "number" then
				clientTime = payload.clientTime
			end
			self:_handlePunchRequest(player, true, clientTime)
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
		self._activeTraps[player] = nil
	end)
end

return CombatService
