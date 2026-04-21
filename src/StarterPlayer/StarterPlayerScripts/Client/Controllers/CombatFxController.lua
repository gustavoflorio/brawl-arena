--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local localPlayer = Players.LocalPlayer

local HIT_SEQ_ATTR = Constants.CharacterAttributes.HitSeq
local ELIM_SEQ_ATTR = Constants.CharacterAttributes.EliminationSeq
local PUNCH_DURATION = 0.7

local CombatFxController = {}
CombatFxController._punchAnimation = nil :: Animation?
CombatFxController._activeTrack = nil :: AnimationTrack?

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

function CombatFxController:_getAnimation(): Animation
	if self._punchAnimation then
		return self._punchAnimation
	end
	local anim = Instance.new("Animation")
	anim.Name = "BrawlPunchAnimation"
	anim.AnimationId = Constants.Assets.PunchAnimationId
	self._punchAnimation = anim
	return anim
end

function CombatFxController:PlayLocalPunch()
	local character = localPlayer.Character
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end
	local animator = getAnimator(humanoid)
	if self._activeTrack then
		if self._activeTrack.IsPlaying then
			self._activeTrack:Stop(0)
		end
		self._activeTrack = nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(self:_getAnimation())
	end)
	if not ok or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	self._activeTrack = track
	track:Play(0.05)
	task.delay(PUNCH_DURATION, function()
		if self._activeTrack == track then
			self._activeTrack = nil
		end
	end)
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

local function bindPlayer(player: Player)
	local function onCharacter(character: Model)
		bindHitListener(character)
		if player == localPlayer then
			bindEliminationListener(character)
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
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)

	-- preload
	pcall(function()
		self:_getAnimation()
	end)
end

return CombatFxController
