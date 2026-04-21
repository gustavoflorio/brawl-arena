--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local localPlayer = Players.LocalPlayer

local HIT_SEQ_ATTR = Constants.CharacterAttributes.HitSeq
local ELIM_SEQ_ATTR = Constants.CharacterAttributes.EliminationSeq
local KB_SEQ_ATTR = Constants.CharacterAttributes.KBSeq
local KB_VEL_ATTR = Constants.CharacterAttributes.KBVelocity
local PUNCH_DURATION = 0.7
local HEAVY_PUNCH_DURATION = 1.0
local DODGE_ROLL_DURATION = 1.0
local DOUBLE_JUMP_DURATION = 0.6

type TrackKind = "Punch" | "HeavyPunch" | "DodgeRoll" | "DoubleJump" | "Running"

local CombatFxController = {}
CombatFxController._animCache = {} :: { [string]: Animation }
CombatFxController._tracks = {} :: { [TrackKind]: AnimationTrack? }
CombatFxController._runningPlaying = false

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
	print(string.format(
		"[CombatFxController] _loadTrack %s OK — assetId=%s rig=%s length=%.3fs priority=%s looped=%s",
		kind,
		assetId,
		tostring(humanoid.RigType),
		track.Length,
		tostring(priority),
		tostring(looped)
	))
	return track
end

function CombatFxController:_stopTrack(kind: TrackKind)
	local track = self._tracks[kind]
	if track and track.IsPlaying then
		track:Stop(0.05)
	end
	self._tracks[kind] = nil
end

function CombatFxController:PlayLocalPunch(isHeavy: boolean?)
	print(string.format("[CombatFxController] PlayLocalPunch isHeavy=%s", tostring(isHeavy)))
	self:_stopTrack("Punch")
	self:_stopTrack("HeavyPunch")
	local kind: TrackKind = isHeavy and "HeavyPunch" or "Punch"
	local assetId = isHeavy and Constants.Assets.HeavyPunchAnimationId or Constants.Assets.PunchAnimationId
	local duration = isHeavy and HEAVY_PUNCH_DURATION or PUNCH_DURATION
	local track = self:_loadTrack(kind, assetId, Enum.AnimationPriority.Action4, false)
	if not track then
		return
	end
	self._tracks[kind] = track
	track:Play(0.05)
	task.delay(0.1, function()
		if self._tracks[kind] == track then
			print(string.format(
				"[CombatFxController] %s status pós-play: IsPlaying=%s TimePosition=%.3f Length=%.3f",
				kind,
				tostring(track.IsPlaying),
				track.TimePosition,
				track.Length
			))
		end
	end)
	task.delay(duration, function()
		if self._tracks[kind] == track then
			self._tracks[kind] = nil
		end
	end)
end

function CombatFxController:PlayDodgeRoll()
	self:_stopTrack("DodgeRoll")
	local track = self:_loadTrack("DodgeRoll", Constants.Assets.DodgeRollAnimationId, Enum.AnimationPriority.Action4, false)
	if not track then
		return
	end
	self._tracks["DodgeRoll"] = track
	track:Play(0.05)
	task.delay(DODGE_ROLL_DURATION, function()
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
	print("[CombatFxController] PlayRunning chamado")
	local existing = self._tracks["Running"]
	if not existing or not existing.IsPlaying then
		existing = self:_loadTrack("Running", Constants.Assets.RunAnimationId, Enum.AnimationPriority.Action3, true)
		self._tracks["Running"] = existing
	end
	if existing then
		existing:Play(0.1)
		self._runningPlaying = true
		print("[CombatFxController] Running track iniciada")
		task.delay(0.15, function()
			if existing and self._tracks["Running"] == existing then
				print(string.format(
					"[CombatFxController] Running status pós-play: IsPlaying=%s TimePosition=%.3f Speed=%.2f Length=%.3f",
					tostring(existing.IsPlaying),
					existing.TimePosition,
					existing.Speed,
					existing.Length
				))
			end
		end)
	else
		warn("[CombatFxController] PlayRunning falhou — track nil")
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

local function bindPlayer(player: Player, fxController: any)
	local function onCharacter(character: Model)
		bindHitListener(character)
		if player == localPlayer then
			bindEliminationListener(character)
			bindKnockbackListener(character)
			fxController:ResetCharacterTracks()
		end
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function CombatFxController:Init(_controllers: { [string]: any }) end

function CombatFxController:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player, self)
	end
	Players.PlayerAdded:Connect(function(player)
		bindPlayer(player, self)
	end)

	pcall(function()
		self:_getAnimation("Punch", Constants.Assets.PunchAnimationId)
		self:_getAnimation("HeavyPunch", Constants.Assets.HeavyPunchAnimationId)
		self:_getAnimation("Running", Constants.Assets.RunAnimationId)
		self:_getAnimation("DoubleJump", Constants.Assets.DoubleJumpAnimationId)
		self:_getAnimation("DodgeRoll", Constants.Assets.DodgeRollAnimationId)
	end)
end

return CombatFxController
