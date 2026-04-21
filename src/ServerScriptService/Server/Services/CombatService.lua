--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

local CombatService = {}
CombatService._services = nil :: Services?
CombatService._nextPunchAllowedAt = {} :: { [Player]: number }
CombatService._nextDodgeAllowedAt = {} :: { [Player]: number }
CombatService._requestWindow = {} :: { [Player]: { number } }

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

function CombatService:_findTargets(puncher: Player, origin: Vector3, facing: Vector3): { Player }
	local arenaService = (self._services :: Services).ArenaService
	local results: { Player } = {}

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local puncherCharacter = puncher.Character
	if puncherCharacter then
		overlapParams.FilterDescendantsInstances = { puncherCharacter }
	end

	local parts = Workspace:GetPartBoundsInRadius(origin, Constants.Combat.PunchRange, overlapParams)
	local seen: { [Player]: boolean } = {}
	for _, part in ipairs(parts) do
		local character = part:FindFirstAncestorOfClass("Model")
		if character then
			local targetPlayer = Players:GetPlayerFromCharacter(character)
			if
				targetPlayer
				and targetPlayer ~= puncher
				and not seen[targetPlayer]
				and arenaService:GetState(targetPlayer) == Constants.PlayerState.InArena
				and isAlive(targetPlayer)
				and not isInvincible(targetPlayer)
			then
				local targetRoot = character:FindFirstChild("HumanoidRootPart")
				if targetRoot and targetRoot:IsA("BasePart") then
					local delta = targetRoot.Position - origin
					if delta.X * facing.X >= -0.1 then
						seen[targetPlayer] = true
						table.insert(results, targetPlayer)
					end
				end
			end
		end
	end
	return results
end

function CombatService:_applyHit(puncher: Player, target: Player, facing: Vector3, damageMultiplier: number)
	local arenaService = (self._services :: Services).ArenaService
	local punchRoot = getCharacterRoot(puncher)
	local targetRoot = getCharacterRoot(target)
	if not punchRoot or not targetRoot then
		return
	end

	local damageAmount = Constants.Combat.PunchDamage * damageMultiplier
	arenaService:AddDamage(target, damageAmount)
	local damage = arenaService:GetDamage(target)

	local speed = Constants.Combat.KnockbackBase * (1 + (damage / 100) * Constants.Combat.KnockbackGrowth) * damageMultiplier
	local kbVelocity = facing * speed + Vector3.new(0, Constants.Combat.KnockbackVertical * damageMultiplier, 0)

	local targetCharacter = target.Character
	if targetCharacter then
		local attrHit = Constants.CharacterAttributes.HitSeq
		local currentHit = targetCharacter:GetAttribute(attrHit)
		local nextSeq = (typeof(currentHit) == "number" and currentHit or 0) + 1
		targetCharacter:SetAttribute(attrHit, nextSeq)

		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitterId, puncher.UserId)
		targetCharacter:SetAttribute(Constants.CharacterAttributes.LastHitTime, os.clock())

		-- Knockback via attribute pattern: client do target aplica velocity
		-- (Roblox physics ownership do character pertence ao owner client).
		local kbAttr = Constants.CharacterAttributes.KBVelocity
		local kbSeqAttr = Constants.CharacterAttributes.KBSeq
		targetCharacter:SetAttribute(kbAttr, kbVelocity)
		local currentKBSeq = targetCharacter:GetAttribute(kbSeqAttr)
		local nextKBSeq = (typeof(currentKBSeq) == "number" and currentKBSeq or 0) + 1
		targetCharacter:SetAttribute(kbSeqAttr, nextKBSeq)
	end

	arenaService:PublishState(target)
end

function CombatService:_handlePunch(puncher: Player, isHeavy: boolean)
	local arenaService = (self._services :: Services).ArenaService
	if arenaService:GetState(puncher) ~= Constants.PlayerState.InArena then
		return
	end

	if not self:_checkRateLimit(puncher) then
		return
	end

	local now = os.clock()
	local nextAllowed = self._nextPunchAllowedAt[puncher] or 0
	if now < nextAllowed then
		return
	end
	local cooldown = isHeavy and Constants.Combat.HeavyPunchCooldown or Constants.Combat.PunchCooldown
	self._nextPunchAllowedAt[puncher] = now + cooldown

	local root = getCharacterRoot(puncher)
	if not root then
		return
	end

	local multiplier = isHeavy and Constants.Combat.HeavyPunchMultiplier or 1
	local facing = resolveFacing(root)
	local targets = self:_findTargets(puncher, root.Position, facing)
	for _, target in ipairs(targets) do
		self:_applyHit(puncher, target, facing, multiplier)
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
	requestRemote.OnServerEvent:Connect(function(player: Player, action: any)
		if action == Constants.Actions.Punch then
			self:_handlePunch(player, false)
		elseif action == Constants.Actions.HeavyPunch then
			self:_handlePunch(player, true)
		elseif action == Constants.Actions.DodgeRoll then
			self:_handleDodgeRoll(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._nextPunchAllowedAt[player] = nil
		self._nextDodgeAllowedAt[player] = nil
		self._requestWindow[player] = nil
	end)
end

return CombatService
