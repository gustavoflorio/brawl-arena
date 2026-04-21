--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(Constants.Remotes.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.Remotes.Folder
		folder.Parent = ReplicatedStorage
	end

	for _, remoteName in ipairs({ Constants.Remotes.Request, Constants.Remotes.State }) do
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
