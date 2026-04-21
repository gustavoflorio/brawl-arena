--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

type PlayerState = {
	state: string,
	damagePercent: number,
	lastPadTouch: number,
}

local ArenaService = {}
ArenaService._services = nil :: Services?
ArenaService._playerStates = {} :: { [Player]: PlayerState }
ArenaService._padConnection = nil :: RBXScriptConnection?
ArenaService._heartbeatConnection = nil :: RBXScriptConnection?

local TOUCH_DEBOUNCE = 0.5

local function resolveLobbyFolder(): Instance?
	return Workspace:FindFirstChild("Lobby")
end

local function resolveArenaFolder(): Instance?
	return Workspace:FindFirstChild("Arena")
end

local function getSpawnPad(): BasePart?
	local folder = resolveLobbyFolder()
	if not folder then
		return nil
	end
	local pad = folder:FindFirstChild("SpawnPad")
	if pad and pad:IsA("BasePart") then
		return pad
	end
	return nil
end

local function getLobbySpawn(): BasePart?
	local folder = resolveLobbyFolder()
	if not folder then
		return nil
	end
	local spawnPart = folder:FindFirstChild("LobbySpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end
	return nil
end

local function getArenaSpawn(): BasePart?
	local folder = resolveArenaFolder()
	if not folder then
		return nil
	end
	local spawnPart = folder:FindFirstChild("ArenaSpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end
	return nil
end

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

function ArenaService:_ensureState(player: Player): PlayerState
	local existing = self._playerStates[player]
	if existing then
		return existing
	end
	local newState: PlayerState = {
		state = Constants.PlayerState.InLobby,
		damagePercent = 0,
		lastPadTouch = 0,
	}
	self._playerStates[player] = newState
	return newState
end

function ArenaService:GetState(player: Player): string
	local state = self:_ensureState(player)
	return state.state
end

function ArenaService:GetDamage(player: Player): number
	local state = self:_ensureState(player)
	return state.damagePercent
end

function ArenaService:AddDamage(player: Player, amount: number)
	local state = self:_ensureState(player)
	state.damagePercent = state.damagePercent + amount
end

function ArenaService:ResetDamage(player: Player)
	local state = self:_ensureState(player)
	state.damagePercent = 0
end

function ArenaService:PublishState(player: Player)
	local remote = Remotes.GetStateRemote()
	if not remote then
		return
	end
	local state = self:_ensureState(player)
	remote:FireClient(player, {
		state = state.state,
		damagePercent = state.damagePercent,
	})
end

function ArenaService:TeleportToArena(player: Player)
	local spawnPart = getArenaSpawn()
	local root = getCharacterRoot(player)
	if not spawnPart or not root then
		return
	end
	root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	local state = self:_ensureState(player)
	state.state = Constants.PlayerState.InArena
	state.damagePercent = 0
	self:PublishState(player)
end

function ArenaService:ReturnToLobby(player: Player, reason: string?)
	local spawnPart = getLobbySpawn()
	local root = getCharacterRoot(player)
	if spawnPart and root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local state = self:_ensureState(player)
	local wasInArena = state.state == Constants.PlayerState.InArena
	state.state = Constants.PlayerState.InLobby
	state.damagePercent = 0
	state.lastPadTouch = os.clock()

	if wasInArena and reason == "OutOfBounds" then
		local character = player.Character
		if character then
			local attr = Constants.CharacterAttributes.EliminationSeq
			local current = character:GetAttribute(attr)
			local nextSeq = (typeof(current) == "number" and current or 0) + 1
			character:SetAttribute(attr, nextSeq)
		end
	end

	self:PublishState(player)
end

function ArenaService:_handlePadTouch(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local state = self:_ensureState(player)
	local now = os.clock()
	if now - state.lastPadTouch < TOUCH_DEBOUNCE then
		return
	end
	state.lastPadTouch = now
	if state.state == Constants.PlayerState.InArena then
		return
	end
	self:TeleportToArena(player)
end

function ArenaService:_bindSpawnPad()
	local pad = getSpawnPad()
	if not pad then
		warn("[ArenaService] SpawnPad não encontrado em Workspace.Lobby. Loop de bind irá tentar quando existir.")
		return
	end
	if self._padConnection then
		self._padConnection:Disconnect()
	end
	self._padConnection = pad.Touched:Connect(function(hit)
		self:_handlePadTouch(hit)
	end)
end

function ArenaService:_watchOutOfBounds()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
	end
	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		for player, state in pairs(self._playerStates) do
			if state.state == Constants.PlayerState.InArena then
				local root = getCharacterRoot(player)
				if root and root.Position.Y < Constants.Arena.YKillThreshold then
					self:ReturnToLobby(player, "OutOfBounds")
				end
			end
		end
	end)
end

function ArenaService:_onPlayerAdded(player: Player)
	self:_ensureState(player)
	player.CharacterAdded:Connect(function()
		local state = self:_ensureState(player)
		state.state = Constants.PlayerState.InLobby
		state.damagePercent = 0
		state.lastPadTouch = os.clock()
		task.defer(function()
			self:PublishState(player)
		end)
	end)
	player.CharacterRemoving:Connect(function() end)
end

function ArenaService:Init(services: Services)
	self._services = services
end

function ArenaService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._playerStates[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end

	self:_bindSpawnPad()

	local lobby = resolveLobbyFolder()
	if lobby then
		lobby.ChildAdded:Connect(function(child)
			if child.Name == "SpawnPad" then
				task.wait(0.1)
				self:_bindSpawnPad()
			end
		end)
	end

	self:_watchOutOfBounds()
end

return ArenaService
