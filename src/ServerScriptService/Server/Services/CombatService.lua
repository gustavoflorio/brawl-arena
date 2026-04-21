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
CombatService._lastPunch = {} :: { [Player]: number }

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
			then
				local targetRoot = getCharacterRoot(targetPlayer)
				if targetRoot then
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

function CombatService:_applyHit(puncher: Player, target: Player, facing: Vector3)
	local arenaService = (self._services :: Services).ArenaService
	local punchRoot = getCharacterRoot(puncher)
	local targetRoot = getCharacterRoot(target)
	if not punchRoot or not targetRoot then
		return
	end

	arenaService:AddDamage(target, Constants.Combat.PunchDamage)
	local damage = arenaService:GetDamage(target)

	local speed = Constants.Combat.KnockbackBase * (1 + (damage / 100) * Constants.Combat.KnockbackGrowth)
	targetRoot.AssemblyLinearVelocity = facing * speed + Vector3.new(0, Constants.Combat.KnockbackVertical, 0)

	local targetCharacter = target.Character
	if targetCharacter then
		local attr = Constants.CharacterAttributes.HitSeq
		local current = targetCharacter:GetAttribute(attr)
		local nextSeq = (typeof(current) == "number" and current or 0) + 1
		targetCharacter:SetAttribute(attr, nextSeq)
	end

	arenaService:PublishState(target)
end

function CombatService:_handlePunch(puncher: Player)
	local arenaService = (self._services :: Services).ArenaService
	if arenaService:GetState(puncher) ~= Constants.PlayerState.InArena then
		return
	end

	local now = os.clock()
	local lastPunch = self._lastPunch[puncher] or 0
	if now - lastPunch < Constants.Combat.PunchCooldown then
		return
	end
	self._lastPunch[puncher] = now

	local root = getCharacterRoot(puncher)
	if not root then
		return
	end

	local facing = resolveFacing(root)
	local targets = self:_findTargets(puncher, root.Position, facing)
	for _, target in ipairs(targets) do
		self:_applyHit(puncher, target, facing)
	end
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
			self:_handlePunch(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._lastPunch[player] = nil
	end)
end

return CombatService
