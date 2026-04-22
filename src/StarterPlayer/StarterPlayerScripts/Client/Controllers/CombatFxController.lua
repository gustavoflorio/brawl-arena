--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local localPlayer = Players.LocalPlayer

local HIT_SEQ_ATTR = Constants.CharacterAttributes.HitSeq
local ELIM_SEQ_ATTR = Constants.CharacterAttributes.EliminationSeq
local KB_SEQ_ATTR = Constants.CharacterAttributes.KBSeq
local KB_VEL_ATTR = Constants.CharacterAttributes.KBVelocity
local HIT_KIND_ATTR = Constants.CharacterAttributes.HitKind
local DAMAGE_PERCENT_ATTR = Constants.CharacterAttributes.DamagePercent
local HITSTOP_SEQ_ATTR = Constants.CharacterAttributes.HitStopSeq
local HITSTOP_UNTIL_ATTR = Constants.CharacterAttributes.HitStopUntil
local DOUBLE_JUMP_DURATION = 0.6
local VFX_IMPACT_DURATION = 0.6
-- Trail duration é proporcional ao damage% do target no momento do hit:
-- 100% dmg = VFX_TRAIL_BASE_DURATION. 200% = 2x. 50% = metade. Um minimo
-- curto (0.05s) garante que mesmo hits em alvos com 0% mostrem um flash.
local VFX_TRAIL_BASE_DURATION = 0.7
local VFX_TRAIL_MIN_DURATION = 0.05

local vfxFolder: Folder? = ReplicatedStorage:FindFirstChild("Punch VFX") :: Folder?

type TrackKind = "Punch" | "HeavyPunch" | "DodgeRoll" | "DoubleJump" | "Running"

local ANIM_SPECS: { { name: TrackKind, id: string } } = {
	{ name = "Punch", id = Constants.Assets.PunchAnimationId },
	{ name = "HeavyPunch", id = Constants.Assets.HeavyPunchAnimationId },
	{ name = "Running", id = Constants.Assets.RunAnimationId },
	{ name = "DodgeRoll", id = Constants.Assets.DodgeRollAnimationId },
	{ name = "DoubleJump", id = Constants.Assets.DoubleJumpAnimationId },
}

local CombatFxController = {}
CombatFxController._animCache = {} :: { [string]: Animation }
CombatFxController._tracks = {} :: { [TrackKind]: AnimationTrack? }
CombatFxController._runningPlaying = false
CombatFxController._controllers = nil :: { [string]: any }?

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
	local cached = self._animCache[name]
	if cached then
		return cached
	end
	local anim = Instance.new("Animation")
	anim.Name = "Brawl_" .. name
	anim.AnimationId = assetId
	self._animCache[name] = anim
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

function CombatFxController:IsPunching(): boolean
	for _, kind in ipairs({ "Punch", "HeavyPunch" }) do
		local track = self._tracks[kind]
		if track and track.IsPlaying then
			return true
		end
	end
	return false
end

function CombatFxController:PlayLocalPunch(isHeavy: boolean?)
	if self:IsPunching() then
		return
	end
	local kind: TrackKind = isHeavy and "HeavyPunch" or "Punch"
	local assetId = isHeavy and Constants.Assets.HeavyPunchAnimationId or Constants.Assets.PunchAnimationId
	local track = self:_loadTrack(kind, assetId, Enum.AnimationPriority.Action4, false)
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
	track:Play(0.05)
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
	self._runningPlaying = false
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

local function bindHitListener(character: Model)
	local lastSeen = character:GetAttribute(HIT_SEQ_ATTR)
	if typeof(lastSeen) ~= "number" then
		lastSeen = 0
	end
	character:GetAttributeChangedSignal(HIT_SEQ_ATTR):Connect(function()
		local seq = character:GetAttribute(HIT_SEQ_ATTR)
		if typeof(seq) ~= "number" or seq <= lastSeen then
			return
		end
		lastSeen = seq
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			playHitSoundAt(root)
		end
	end)
end

local function bindEliminationListener(character: Model)
	local lastSeen = character:GetAttribute(ELIM_SEQ_ATTR)
	if typeof(lastSeen) ~= "number" then
		lastSeen = 0
	end
	character:GetAttributeChangedSignal(ELIM_SEQ_ATTR):Connect(function()
		local seq = character:GetAttribute(ELIM_SEQ_ATTR)
		if typeof(seq) ~= "number" or seq <= lastSeen then
			return
		end
		lastSeen = seq
		playEliminationSound()
	end)
end

local function bindHitStopListener(character: Model, fxController: any)
	-- Só roda pro próprio character. Congela combat anims via AdjustSpeed(0)
	-- e delega walkspeed lock ao MovementController (mesma pattern do
	-- PunchLock). Sem isso, char faria animação normal + movia enquanto
	-- server achava que estava em hitstop → desincronia visual.
	local lastSeen = character:GetAttribute(HITSTOP_SEQ_ATTR)
	if typeof(lastSeen) ~= "number" then
		lastSeen = 0
	end
	character:GetAttributeChangedSignal(HITSTOP_SEQ_ATTR):Connect(function()
		local seq = character:GetAttribute(HITSTOP_SEQ_ATTR)
		if typeof(seq) ~= "number" or seq <= lastSeen then
			return
		end
		lastSeen = seq
		local until_ = character:GetAttribute(HITSTOP_UNTIL_ATTR)
		if typeof(until_) ~= "number" then
			return
		end
		local remaining = until_ - os.clock()
		if remaining <= 0 then
			return
		end

		-- Delega walkspeed ao MovementController (ele já sabe save/restore
		-- e coexistir com PunchLock ativo).
		local movementController = fxController._controllers and fxController._controllers.MovementController
		if movementController and type(movementController.StartHitStopLock) == "function" then
			movementController:StartHitStopLock(remaining)
		end

		-- Congela combat anim tracks em curso. Só track de punch/heavy:
		-- running/jump loopam normalmente (se target estava parado socando
		-- quando foi hit, a anim de punch freeza no meio).
		local pausedTracks: { { track: AnimationTrack, prevSpeed: number } } = {}
		for _, kind in ipairs({ "Punch", "HeavyPunch" }) do
			local track = fxController._tracks[kind]
			if track and track.IsPlaying then
				table.insert(pausedTracks, { track = track, prevSpeed = track.Speed })
				track:AdjustSpeed(0)
			end
		end
		if #pausedTracks == 0 then
			return
		end
		task.delay(remaining, function()
			for _, entry in ipairs(pausedTracks) do
				if entry.track.IsPlaying then
					entry.track:AdjustSpeed(entry.prevSpeed > 0 and entry.prevSpeed or 1)
				end
			end
		end)
	end)
end

local function bindKnockbackListener(character: Model)
	-- Só roda pro próprio character do local player — ele tem physics ownership
	-- e é o único que consegue aplicar velocity que replica corretamente.
	local lastSeen = character:GetAttribute(KB_SEQ_ATTR)
	if typeof(lastSeen) ~= "number" then
		lastSeen = 0
	end
	character:GetAttributeChangedSignal(KB_SEQ_ATTR):Connect(function()
		local seq = character:GetAttribute(KB_SEQ_ATTR)
		if typeof(seq) ~= "number" or seq <= lastSeen then
			return
		end
		lastSeen = seq
		local velocity = character:GetAttribute(KB_VEL_ATTR)
		if typeof(velocity) ~= "Vector3" then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity
	end)
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

-- Hit listener com VFX: extende o sound-only da versão anterior.
local function bindHitVFXListener(character: Model)
	local lastSeen = character:GetAttribute(HIT_SEQ_ATTR)
	if typeof(lastSeen) ~= "number" then
		lastSeen = 0
	end
	character:GetAttributeChangedSignal(HIT_SEQ_ATTR):Connect(function()
		local seq = character:GetAttribute(HIT_SEQ_ATTR)
		if typeof(seq) ~= "number" or seq <= lastSeen then
			return
		end
		lastSeen = seq
		local kind = character:GetAttribute(HIT_KIND_ATTR)
		local isHeavy = kind == "Heavy"
		local dmgAttr = character:GetAttribute(DAMAGE_PERCENT_ATTR)
		local damagePercent = typeof(dmgAttr) == "number" and dmgAttr or 0
		playImpactVFX(character)
		playTrailVFX(character, isHeavy, damagePercent)
	end)
end

local function bindPlayer(player: Player, fxController: any)
	local function onCharacter(character: Model)
		bindHitListener(character)
		bindHitVFXListener(character)
		if player == localPlayer then
			bindEliminationListener(character)
			bindKnockbackListener(character)
			bindHitStopListener(character, fxController)
			fxController:ResetCharacterTracks()
		end
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
	local preloadList: { Animation } = {}
	for _, spec in ipairs(ANIM_SPECS) do
		local anim = self:_getAnimation(spec.name, spec.id)
		table.insert(preloadList, anim)
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(preloadList)
		end)
		if not ok then
			warn("[CombatFxController] PreloadAsync falhou:", err)
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player, self)
	end
	Players.PlayerAdded:Connect(function(player)
		bindPlayer(player, self)
	end)
end

return CombatFxController
