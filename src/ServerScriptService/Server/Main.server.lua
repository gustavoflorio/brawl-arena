--!strict

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
	}
	for _, remoteName in ipairs(remoteNames) do
		if not folder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
		end
	end
end

ensureRemotes()

local ServiceLoader = require(script.Parent:WaitForChild("ServiceLoader"))

ServiceLoader:Init()
ServiceLoader:Start()

print("[BrawlArena] Server bootstrap concluído")
