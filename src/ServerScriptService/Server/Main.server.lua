--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

-- Bloquear spawn de character automático. PlayerDataService controla
-- o spawn via player:LoadCharacter() após o profile estar carregado.
Players.CharacterAutoLoads = false

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Move speed e jump altos (2x default) pra arena ficar mais ágil.
StarterPlayer.CharacterWalkSpeed = Constants.PlayerMovement.WalkSpeed
StarterPlayer.CharacterJumpHeight = Constants.PlayerMovement.JumpHeight
StarterPlayer.CharacterJumpPower = Constants.PlayerMovement.JumpPower

-- Collision groups: durante dodge, character fica no grupo "Dodging" que
-- não colide com "Players", permitindo atravessar outros players.
local GROUP_PLAYERS = Constants.CollisionGroups.Players
local GROUP_DODGING = Constants.CollisionGroups.PlayersDodging
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP_PLAYERS)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP_DODGING)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP_DODGING, GROUP_PLAYERS, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_DODGING, GROUP_DODGING, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_PLAYERS, GROUP_PLAYERS, true)
end)

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(Constants.Remotes.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.Remotes.Folder
		folder.Parent = ReplicatedStorage
	end

	local remoteNames = {
		Constants.Remotes.Request,
		Constants.Remotes.State,
		Constants.Remotes.Events,
		Constants.Remotes.Arena,
	}
	for _, remoteName in ipairs(remoteNames) do
		if not folder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
		end
	end

	-- BrawlShop é RemoteFunction (request/response): UI precisa de ack
	-- síncrona pra exibir resultado da compra/equip. Outros remotes são
	-- fire-and-forget (state push, events).
	if not folder:FindFirstChild(Constants.Remotes.Shop) then
		local shopRemote = Instance.new("RemoteFunction")
		shopRemote.Name = Constants.Remotes.Shop
		shopRemote.Parent = folder
	end
end

ensureRemotes()

local ServiceLoader = require(script.Parent:WaitForChild("ServiceLoader"))

ServiceLoader:Init()
ServiceLoader:Start()

print("[BrawlArena] Server bootstrap concluído")
