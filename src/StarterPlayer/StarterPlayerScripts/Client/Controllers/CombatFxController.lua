--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Classes = require(sharedFolder:WaitForChild("Classes"))

local localPlayer = Players.LocalPlayer

-- HitStopUntil ainda é attribute (lido por _playHitReactionOn pra freezar
-- a anim de impacto no frame 0 enquanto hitstop ativo). Demais sinais de
-- combat (HitSeq, KBSeq etc.) viraram pulsos via CombatPulse remote.
local HITSTOP_UNTIL_ATTR = Constants.CharacterAttributes.HitStopUntil
local DOUBLE_JUMP_DURATION = 0.6
local VFX_IMPACT_DURATION = 0.6
-- Trail duration é proporcional ao damage% do target no momento do hit:
-- 100% dmg = VFX_TRAIL_BASE_DURATION. 200% = 2x. 50% = metade. Um minimo
-- curto (0.05s) garante que mesmo hits em alvos com 0% mostrem um flash.
local VFX_TRAIL_BASE_DURATION = 0.7
local VFX_TRAIL_MIN_DURATION = 0.05

local vfxFolder: Folder? = ReplicatedStorage:FindFirstChild("Punch VFX") :: Folder?

-- TrackKind é só string: chaves de combat são class-defined (cada classe nomeia
-- seus moves como quiser — Jab1/Jet1/etc). Tracks não-combat (Running/DodgeRoll
-- /DoubleJump/HitReaction1-N) são globais.
type TrackKind = string

-- COMBAT_TRACKS = união dos move keys de TODAS as classes registradas. Computado
-- uma vez no module load. Iterado em cancel/IsPunching/hitstop pra encontrar
-- qual track de combat está tocando, sem assumir nomenclatura fixa.
local COMBAT_TRACKS: { TrackKind } = {}
do
	local seen: { [string]: boolean } = {}
	for _, classDef in ipairs(Classes.GetCatalog()) do
		for kind in pairs(classDef.Moves) do
			if not seen[kind] then
				seen[kind] = true
				table.insert(COMBAT_TRACKS, kind)
			end
		end
	end
end

local HIT_REACTION_IDS: { string } = Constants.Assets.HitReactionAnimationIds

-- Combat anim specs sao montados em runtime (Start) iterando Classes.GetCatalog()
-- — cada classe pode ter AnimationIds proprios pros 4 combat moves. Os outros
-- (Running/DodgeRoll/DoubleJump/HitReaction) sao globais por enquanto.
local NON_COMBAT_ANIM_SPECS: { { name: string, id: string } } = {
	{ name = "Running", id = Constants.Assets.RunAnimationId },
	{ name = "DodgeRoll", id = Constants.Assets.DodgeRollAnimationId },
	{ name = "DoubleJump", id = Constants.Assets.DoubleJumpAnimationId },
	{ name = "HitReaction1", id = HIT_REACTION_IDS[1] },
	{ name = "HitReaction2", id = HIT_REACTION_IDS[2] },
}

local CombatFxController = {}
CombatFxController._animCache = {} :: { [string]: Animation }
CombatFxController._tracks = {} :: { [TrackKind]: AnimationTrack? }
CombatFxController._runningPlaying = false
CombatFxController._controllers = nil :: { [string]: any }?
-- Hit reaction: tracks são pré-loadados UMA VEZ por character (array de N
-- variantes) e reutilizados. Chamar LoadAnimation/Destroy a cada hit causa
-- corrupção do Animator em combos rápidos — char para de animar por completo.
CombatFxController._hitReactionTracks = {} :: { [Model]: { AnimationTrack } }

local function getHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") then
		return humanoid
	end
	return nil
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end
	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

function CombatFxController:_getAnimation(name: string, assetId: string): Animation
	-- Cache por assetId pra evitar criar Animation duplicado pro mesmo asset
	-- (várias classes podem reusar o mesmo AnimationId).
	local cached = self._animCache[assetId]
	if cached then
		return cached
	end
	local anim = Instance.new("Animation")
	anim.Name = "Brawl_" .. name
	anim.AnimationId = assetId
	self._animCache[assetId] = anim
	return anim
end

function CombatFxController:_loadTrack(kind: TrackKind, assetId: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local character = localPlayer.Character
	local humanoid = getHumanoid(character)
	if not humanoid then
		warn(string.format("[CombatFxController] _loadTrack %s: humanoid ausente", kind))
		return nil
	end
	local animator = getAnimator(humanoid)
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(self:_getAnimation(kind, assetId))
	end)
	if not ok then
		warn(string.format("[CombatFxController] _loadTrack %s FALHOU: %s", kind, tostring(trackOrErr)))
		return nil
	end
	if not trackOrErr then
		warn(string.format("[CombatFxController] _loadTrack %s retornou nil", kind))
		return nil
	end
	local track = trackOrErr :: AnimationTrack
	track.Priority = priority
	track.Looped = looped
	return track
end

function CombatFxController:_stopTrack(kind: TrackKind)
	local track = self._tracks[kind]
	if track and track.IsPlaying then
		track:Stop(0.05)
	end
	self._tracks[kind] = nil
end

local function stopDefaultTracks(animator: Animator, keepTrack: AnimationTrack?)
	-- Stop anims default (Core/Movement/Idle priorities) pra que minha custom
	-- (Action3/Action4) não sofra blend competing.
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		if t ~= keepTrack then
			local p = t.Priority
			if p == Enum.AnimationPriority.Core
				or p == Enum.AnimationPriority.Idle
				or p == Enum.AnimationPriority.Movement
			then
				t:Stop(0.1)
			end
		end
	end
end

function CombatFxController:_resolveCombatMove(kind: TrackKind): { AnimationId: string }?
	-- Olha o Moves table da classe equipada (consulta ShopController) em vez
	-- de Constants.Combat.Moves direto — assim Ballerina toca anims dela e
	-- nao do Boxer. Fallback: classe default se ShopController ainda nao
	-- fetchou ou se a classe equipada sumiu do registry.
	local controllers = self._controllers
	local shop = controllers and controllers.ShopController
	local classId
	if shop and type(shop.GetEquippedClassId) == "function" then
		classId = shop:GetEquippedClassId()
	else
		classId = Classes.GetDefaultId()
	end
	local classDef = Classes.GetClass(classId) or Classes.GetDefault()
	local move = classDef.Moves[kind]
	if not move then
		return nil
	end
	return move
end

function CombatFxController:IsPunching(): boolean
	for _, kind in ipairs(COMBAT_TRACKS) do
		local track = self._tracks[kind]
		if track and track.IsPlaying then
			return true
		end
	end
	return false
end

function CombatFxController:PlayLocalPunch(moveKey: string?)
	-- moveKey é uma chave de move da classe equipada (Jab1/Jet1/Spin/etc).
	-- InputController sempre passa um valor; só retornamos se vier nil.
	if not moveKey then
		return
	end
	local kind: TrackKind = moveKey
	local move = self:_resolveCombatMove(kind)
	if not move then
		return
	end

	-- Cancel: para qualquer punch anim em execução antes de tocar a próxima.
	-- Sem isso, jab2 entraria em blend com jab1 e faria ambos tocando juntos.
	-- Fade out curto (0.03s) pra não estancar visualmente — é o que dá o
	-- "crunch" visual do combo.
	for _, otherKind in ipairs(COMBAT_TRACKS) do
		if otherKind ~= kind then
			local existing = self._tracks[otherKind]
			if existing and existing.IsPlaying then
				existing:Stop(0.03)
				self._tracks[otherKind] = nil
			end
		end
	end

	local track = self:_loadTrack(kind, move.AnimationId, Enum.AnimationPriority.Action4, false)
	if not track then
		return
	end
	local character = localPlayer.Character
	local humanoid = getHumanoid(character)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		stopDefaultTracks(animator :: Animator, track)
	end
	self._tracks[kind] = track
	track.Stopped:Connect(function()
		if self._tracks[kind] == track then
			self._tracks[kind] = nil
		end
	end)
	-- AnimSpeed permite acelerar/desacelerar a anim por move (default 1).
	-- Quem define AnimSpeed deve escalar Startup/Active/Recovery na mesma
	-- proporção pra manter gameplay em sync com a anim visual.
	track:Play(0.05, 1, (move :: any).AnimSpeed or 1)
end

function CombatFxController:PlayDodgeRoll()
	self:_stopTrack("DodgeRoll")
	local track = self:_loadTrack("DodgeRoll", Constants.Assets.DodgeRollAnimationId, Enum.AnimationPriority.Action4, false)
	if not track then
		return
	end
	self._tracks["DodgeRoll"] = track
	track:Play(0.05)
	track:AdjustSpeed(Constants.Combat.DodgeRollAnimSpeedMultiplier)
	task.delay(Constants.Combat.DodgeRollDurationSeconds, function()
		if self._tracks["DodgeRoll"] == track then
			self._tracks["DodgeRoll"] = nil
		end
	end)
end

function CombatFxController:PlayDoubleJump()
	self:_stopTrack("DoubleJump")
	local track = self:_loadTrack("DoubleJump", Constants.Assets.DoubleJumpAnimationId, Enum.AnimationPriority.Action3, false)
	if not track then
		return
	end
	self._tracks["DoubleJump"] = track
	track:Play(0.05)
	task.delay(DOUBLE_JUMP_DURATION, function()
		if self._tracks["DoubleJump"] == track then
			self._tracks["DoubleJump"] = nil
		end
	end)
end

function CombatFxController:PlayRunning()
	if self._runningPlaying then
		return
	end
	local existing = self._tracks["Running"]
	if not existing or not existing.IsPlaying then
		existing = self:_loadTrack("Running", Constants.Assets.RunAnimationId, Enum.AnimationPriority.Action3, true)
		self._tracks["Running"] = existing
	end
	if existing then
		local character = localPlayer.Character
		local humanoid = getHumanoid(character)
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			stopDefaultTracks(animator :: Animator, existing)
		end
		existing:Play(0.1)
		self._runningPlaying = true
	end
end

function CombatFxController:StopRunning()
	if not self._runningPlaying then
		return
	end
	local existing = self._tracks["Running"]
	if existing and existing.IsPlaying then
		existing:Stop(0.15)
	end
	self._runningPlaying = false
end

function CombatFxController:ResetCharacterTracks()
	for kind in pairs(self._tracks) do
		self._tracks[kind] = nil
	end
	-- Limpa refs a tracks de hit reaction de char anterior (respawn).
	-- Tracks são donos do Animator antigo → vão embora com o char destroyed.
	for char in pairs(self._hitReactionTracks) do
		self._hitReactionTracks[char] = nil
	end
	self._runningPlaying = false
end

function CombatFxController:_prepareHitReactionTracks(character: Model)
	-- Pré-carrega AnimationTrack pra cada variante de hit reaction UMA VEZ
	-- no Animator do char. Reutilizadas a cada hit via :Play() em vez de
	-- LoadAnimation/Destroy. Resolve corrupção do Animator em combos rápidos
	-- (onde múltiplas LoadAnimation consecutivas quebravam o state e
	-- travavam todas as anims do char).
	if #HIT_REACTION_IDS == 0 then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- Animator ainda não existe no char; tenta de novo quando adicionado.
		local conn: RBXScriptConnection? = nil
		conn = humanoid.ChildAdded:Connect(function(child)
			if child:IsA("Animator") then
				if conn then
					conn:Disconnect()
				end
				self:_prepareHitReactionTracks(character)
			end
		end)
		return
	end

	local tracks: { AnimationTrack } = {}
	for i, id in ipairs(HIT_REACTION_IDS) do
		local kind: TrackKind = ("HitReaction" .. tostring(i)) :: any
		local anim = self:_getAnimation(kind, id)
		local ok, result = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and result then
			local track = result :: AnimationTrack
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			table.insert(tracks, track)
		end
	end
	if #tracks > 0 then
		self._hitReactionTracks[character] = tracks
	end
end

function CombatFxController:_cancelLocalSwingOnHit()
	-- "Tomou hit = para de atacar": stop combat tracks (em vez do pause-resume
	-- do hitstop listener — pause-resume faz sentido pro PUNCHER que está em
	-- hitlag, não pro target que deveria ter sido interrompido). Termina lunge
	-- e walkspeed via MovementController, e limpa combo state no Input.
	for _, kind in ipairs(COMBAT_TRACKS) do
		local track = self._tracks[kind]
		if track then
			if track.IsPlaying then
				track:Stop(0.05)
			end
			self._tracks[kind] = nil
		end
	end
	local controllers = self._controllers
	if not controllers then
		return
	end
	local mc = controllers.MovementController
	if mc and type(mc.CancelPunchSwing) == "function" then
		mc:CancelPunchSwing()
	end
	local ic = controllers.InputController
	if ic and type(ic.CancelCombo) == "function" then
		ic:CancelCombo()
	end
end

function CombatFxController:_playHitReactionOn(character: Model)
	-- Usa tracks pré-carregados em _prepareHitReactionTracks. A cada hit,
	-- para as que estão tocando e dispara uma variante aleatória do zero.
	-- Durante hitstop, a anim fica congelada no frame 0 (pose de impacto);
	-- quando hitstop acaba, continua com speed normal — gera o efeito de
	-- "impacto congelado → sacudo pós-hit" típico de fighting games.
	local tracks = self._hitReactionTracks[character]
	if not tracks or #tracks == 0 then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Para variante que estiver tocando (combo consecutivo sobrescreve).
	for _, t in ipairs(tracks) do
		if t.IsPlaying then
			t:Stop(0.05)
		end
	end

	local track = tracks[math.random(1, #tracks)]
	track.TimePosition = 0
	track:Play(0.05)

	-- Hitstop freeze: se o char está em hitstop (set pelo server no mesmo
	-- instante do HitSeq bump), pausa a anim e agenda retomada ao fim do
	-- hitstop. HITSTOP_UNTIL_ATTR é replicado via attribute em server time
	-- (Workspace:GetServerTimeNow), portanto comparamos contra a mesma
	-- referência aqui — os.clock() seria por-VM e geraria remaining enorme.
	local hitstopUntil = character:GetAttribute(HITSTOP_UNTIL_ATTR)
	if typeof(hitstopUntil) == "number" then
		local remaining = hitstopUntil - Workspace:GetServerTimeNow()
		if remaining > 0 then
			track:AdjustSpeed(0)
			task.delay(remaining, function()
				-- Só retoma se a mesma track ainda está tocando (se outro hit
				-- chegou antes, essa track já foi stopada).
				if track and track.IsPlaying then
					track:AdjustSpeed(1)
				end
			end)
		end
	end
end

local function playHitSoundAt(root: BasePart)
	local cfg = Constants.Assets.PunchHitSound
	local sound = Instance.new("Sound")
	sound.Name = "BrawlPunchHit"
	sound.SoundId = cfg.Id
	sound.Volume = cfg.Volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = cfg.RollOffMinDistance
	sound.RollOffMaxDistance = cfg.RollOffMaxDistance
	sound.Parent = root
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(3, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end

local function playEliminationSound()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cfg = Constants.Assets.EliminationSound
	local sound = Instance.new("Sound")
	sound.Name = "BrawlElimination"
	sound.SoundId = cfg.Id
	sound.Volume = cfg.Volume
	sound.Parent = camera
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end

local function sendDIInput(character: Model)
	-- B2: envia input horizontal atual ao server. Chamada ao entrar em hitstop
	-- e sempre que MoveDirection mudar durante. Server usa o último valor
	-- quando vai aplicar knockback (após o fim do hitstop).
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local inputX = humanoid.MoveDirection.X
	local remote = Remotes.GetRequestRemote()
	if not remote then
		return
	end
	remote:FireServer(Constants.Actions.DI, { inputX = inputX })
end

-- ====== Punch VFX cloning ======

local function getHumanoidRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function cloneAttachmentFromTemplate(templateName: string, attachmentName: string): Attachment?
	if not vfxFolder then
		return nil
	end
	local template = vfxFolder:FindFirstChild(templateName)
	if not template then
		return nil
	end
	local attachment = template:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return attachment:Clone()
	end
	return nil
end

local function playImpactVFX(character: Model)
	local hrp = getHumanoidRoot(character)
	if not hrp then
		return
	end
	local att = cloneAttachmentFromTemplate("Hit impact", "Punch")
	if not att then
		return
	end
	att.Parent = hrp
	task.delay(VFX_IMPACT_DURATION, function()
		if att.Parent then
			att:Destroy()
		end
	end)
end

local function playTrailVFX(character: Model, isHeavy: boolean, damagePercent: number)
	local hrp = getHumanoidRoot(character)
	if not hrp then
		return
	end
	local attachmentName = isHeavy and "HeavyPunch" or "Punch"
	local att = cloneAttachmentFromTemplate("Hit trail", attachmentName)
	if not att then
		return
	end
	att.Parent = hrp
	local duration = math.max(VFX_TRAIL_MIN_DURATION, (damagePercent / 100) * VFX_TRAIL_BASE_DURATION)
	task.delay(duration, function()
		if att.Parent then
			att:Destroy()
		end
	end)
end

-- ===== Combat pulse handlers =====
--
-- Server emite RemoteEvent unificado (Hit/HitStop/HitStopRelease/Knockback/
-- Elimination) em vez de atributos seq + GetAttributeChangedSignal. Replication
-- de RemoteEvent é direta (sem batching), então VFX/sound/anim respondem mais
-- rápido client-side. Cada handler filtra por character == localPlayer.Character
-- quando o efeito é exclusivo do dono.

local function handleHitPulse(character: Model, payload: any, fxController: any)
	-- Hit dispara em TODOS os clientes pra cada char hitado: sound + VFX
	-- são visuais broadcast. Hit reaction + cancel swing são exclusivos
	-- do dono do char (anim local replica naturalmente via Animator).
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		playHitSoundAt(root)
	end
	local kind = typeof(payload) == "table" and payload.hitKind or nil
	local isHeavy = kind == "Heavy"
	local dmg = typeof(payload) == "table" and typeof(payload.damagePercent) == "number"
		and payload.damagePercent or 0
	playImpactVFX(character)
	playTrailVFX(character, isHeavy, dmg)
	if character == localPlayer.Character then
		fxController:_playHitReactionOn(character)
		fxController:_cancelLocalSwingOnHit()
	end
end

local function handleHitStopPulse(character: Model, payload: any, fxController: any)
	-- HitStop só matters pro dono do char: locka walkspeed + congela anim
	-- + abre janela de DI input. Outros clientes ignoram.
	if character ~= localPlayer.Character then
		return
	end
	local until_ = typeof(payload) == "table" and payload.until_ or nil
	if typeof(until_) ~= "number" then
		return
	end
	local remaining = until_ - Workspace:GetServerTimeNow()
	if remaining <= 0 then
		return
	end

	local mc = fxController._controllers and fxController._controllers.MovementController
	if mc and type(mc.StartHitStopLock) == "function" then
		mc:StartHitStopLock(remaining)
	end

	-- DI: snapshot inicial + monitor de mudanças durante o hitstop. Server
	-- usa o último valor recebido na hora de aplicar o KB.
	sendDIInput(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local diConn: RBXScriptConnection? = nil
	if humanoid then
		local lastSentX = humanoid.MoveDirection.X
		diConn = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
			if not humanoid.Parent then
				return
			end
			local currX = humanoid.MoveDirection.X
			if math.abs(currX - lastSentX) > 0.2 then
				lastSentX = currX
				sendDIInput(character)
			end
		end)
	end

	-- Pausa combat tracks em curso (jab/heavy). Running/jump loopam normalmente
	-- — se target estava parado socando, anim de soco freeza no meio.
	local pausedTracks: { { track: AnimationTrack, prevSpeed: number } } = {}
	for _, kind in ipairs(COMBAT_TRACKS) do
		local track = fxController._tracks[kind]
		if track and track.IsPlaying then
			table.insert(pausedTracks, { track = track, prevSpeed = track.Speed })
			track:AdjustSpeed(0)
		end
	end
	task.delay(remaining, function()
		if diConn then
			diConn:Disconnect()
		end
		for _, entry in ipairs(pausedTracks) do
			if entry.track.IsPlaying then
				entry.track:AdjustSpeed(entry.prevSpeed > 0 and entry.prevSpeed or 1)
			end
		end
	end)
end

local function handleHitStopReleasePulse(character: Model, _payload: any, fxController: any)
	-- Server liberou o hitstop cedo (e.g., trap cancelada — puncher foi
	-- interrompido e o victim sai do lockup imediato). Sem isso,
	-- MovementController seguraria walkspeed=0 até o deadline original.
	if character ~= localPlayer.Character then
		return
	end
	local mc = fxController._controllers and fxController._controllers.MovementController
	if mc and type(mc.EndHitStopLock) == "function" then
		mc:EndHitStopLock()
	end
end

-- Active KB constraint: lock-X via LinearVelocity (mesmo padrão do lunge).
-- Trocou PlatformStand porque PlatformStand desliga o HipHeight enforcement
-- do humanoid → assembly afundava no chão. LinearVelocity em Line mode
-- trava só X (Y livre pra gravity arc, Z trava em 0 pelo lockConnection),
-- humanoid mantém o resto do controle (HipHeight, anims, etc). MaxForce=huge
-- garante que walking input do player não consegue cancelar a velocity X.
type ActiveKB = { attachment: Attachment, velocity: LinearVelocity }
local _activeKB: ActiveKB? = nil

local function clearActiveKB()
	if not _activeKB then
		return
	end
	if _activeKB.velocity and _activeKB.velocity.Parent then
		_activeKB.velocity:Destroy()
	end
	if _activeKB.attachment and _activeKB.attachment.Parent then
		_activeKB.attachment:Destroy()
	end
	_activeKB = nil
end

local function handleKnockbackPulse(character: Model, payload: any, _fxController: any)
	-- KB só roda no dono do char — só ele tem physics ownership pra aplicar
	-- velocity que replica corretamente.
	if character ~= localPlayer.Character then
		return
	end
	local velocity = typeof(payload) == "table" and payload.velocity or nil
	if typeof(velocity) ~= "Vector3" then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local hitstunDuration = typeof(payload) == "table"
		and typeof(payload.hitstunDuration) == "number"
		and payload.hitstunDuration or 0

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Freefall pro initial impulse — sinaliza ao humanoid que char está
		-- em air, walking-force fica suprimida durante o jump arc.
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	-- Initial Y impulse (jump arc) + X (overrided pelo constraint logo abaixo,
	-- mas seta aqui pra garantir velocity inicial caso constraint demore 1 tick).
	root.AssemblyLinearVelocity = velocity

	-- Limpa qualquer KB constraint anterior (hit anterior ainda em hitstun
	-- → substituído pelo novo).
	clearActiveKB()

	if hitstunDuration <= 0 or math.abs(velocity.X) < 0.01 then
		return
	end

	-- LinearVelocity em Line mode: trava X durante hitstun, Y/Z livres.
	-- MaxForce=huge → walking input do humanoid não consegue cancelar
	-- (mesmo padrão que o lunge usa pra sobrepor o player module).
	local attachment = Instance.new("Attachment")
	attachment.Name = "BrawlKBStunAttachment"
	attachment.Parent = root

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "BrawlKBStunVelocity"
	linearVel.Attachment0 = attachment
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVel.LineDirection = Vector3.new(if velocity.X >= 0 then 1 else -1, 0, 0)
	linearVel.LineVelocity = math.abs(velocity.X)
	linearVel.MaxForce = math.huge
	linearVel.Parent = root

	local entry: ActiveKB = { attachment = attachment, velocity = linearVel }
	_activeKB = entry

	task.delay(hitstunDuration, function()
		-- Só destrói se ainda for o constraint atual (hit subsequente pode ter
		-- substituído via clearActiveKB no início do próximo handleKnockbackPulse).
		if _activeKB == entry then
			clearActiveKB()
		end
	end)
end

local function handleEliminationPulse(character: Model, _payload: any, _fxController: any)
	-- Elim sound só pro dono do char eliminado.
	if character ~= localPlayer.Character then
		return
	end
	playEliminationSound()
end

local function bindLocalCharacter(player: Player, fxController: any)
	-- Único bind agora: pré-carrega hit reaction tracks no Animator do local
	-- char (LoadAnimation em Animator remoto corrompe o engine — só o dono
	-- pode tocar). Anim replica naturalmente pros outros clients via Animator.
	if player ~= localPlayer then
		return
	end
	local function onCharacter(character: Model)
		fxController:ResetCharacterTracks()
		fxController:_prepareHitReactionTracks(character)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function CombatFxController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function CombatFxController:Start()
	-- ContentProvider:PreloadAsync é obrigatório: sem preload,
	-- Animator:LoadAnimation retorna tracks com length=0 silenciosamente
	-- e nenhuma animação toca.
	--
	-- Preload anima 4 combat moves de TODA classe (nao so a equipada) — o
	-- player pode trocar de classe a qualquer momento via shop, e sem preload
	-- a primeira execução do golpe novo nao tocaria.
	local preloadList: { Animation } = {}
	local seenAssets: { [string]: boolean } = {}
	local function pushUnique(name: string, id: string)
		if id == "" or seenAssets[id] then return end
		seenAssets[id] = true
		table.insert(preloadList, self:_getAnimation(name, id))
	end
	for _, spec in ipairs(NON_COMBAT_ANIM_SPECS) do
		pushUnique(spec.name, spec.id)
	end
	for _, classDef in ipairs(Classes.GetCatalog()) do
		for kind, move in pairs(classDef.Moves) do
			if move and typeof(move.AnimationId) == "string" then
				pushUnique(kind, move.AnimationId)
			end
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(preloadList)
		end)
		if not ok then
			warn("[CombatFxController] PreloadAsync falhou:", err)
		end
	end)

	-- Hit reaction tracks: pré-carregados no Animator do local char na hora
	-- que ele spawna. Não-locais não precisam — anim replica via Animator.
	for _, player in ipairs(Players:GetPlayers()) do
		bindLocalCharacter(player, self)
	end
	Players.PlayerAdded:Connect(function(player)
		bindLocalCharacter(player, self)
	end)

	-- Combat pulse: dispatcher único pra Hit/HitStop/HitStopRelease/Knockback/
	-- Elimination. Substitui os 6 attribute listeners anteriores. Filtragem
	-- por character == localPlayer.Character acontece dentro de cada handler.
	local pulseRemote = Remotes.GetCombatPulseRemote()
	if pulseRemote then
		pulseRemote.OnClientEvent:Connect(function(eventType: any, character: any, payload: any)
			if typeof(eventType) ~= "string" then
				return
			end
			if typeof(character) ~= "Instance" or not character:IsA("Model") or not character.Parent then
				return
			end
			if eventType == Constants.CombatPulseTypes.Hit then
				handleHitPulse(character, payload, self)
			elseif eventType == Constants.CombatPulseTypes.HitStop then
				handleHitStopPulse(character, payload, self)
			elseif eventType == Constants.CombatPulseTypes.HitStopRelease then
				handleHitStopReleasePulse(character, payload, self)
			elseif eventType == Constants.CombatPulseTypes.Knockback then
				handleKnockbackPulse(character, payload, self)
			elseif eventType == Constants.CombatPulseTypes.Elimination then
				handleEliminationPulse(character, payload, self)
			end
		end)
	else
		warn("[CombatFxController] CombatPulse remote não encontrado.")
	end
end

return CombatFxController
