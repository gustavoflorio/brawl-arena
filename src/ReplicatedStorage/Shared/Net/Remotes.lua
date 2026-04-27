--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local Remotes = {}

local function resolveRemotesFolder(): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Constants.Remotes.Folder)
	if folder then
		return folder
	end
	return ReplicatedStorage:WaitForChild(Constants.Remotes.Folder, 5)
end

local function getRemote(name: string): RemoteEvent?
	local folder = resolveRemotesFolder()
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	local awaited = folder:WaitForChild(name, 5)
	if awaited and awaited:IsA("RemoteEvent") then
		return awaited
	end
	return nil
end

local function getRemoteFunction(name: string): RemoteFunction?
	local folder = resolveRemotesFolder()
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end
	local awaited = folder:WaitForChild(name, 5)
	if awaited and awaited:IsA("RemoteFunction") then
		return awaited
	end
	return nil
end

function Remotes.GetRequestRemote(): RemoteEvent?
	return getRemote(Constants.Remotes.Request)
end

function Remotes.GetStateRemote(): RemoteEvent?
	return getRemote(Constants.Remotes.State)
end

function Remotes.GetEventsRemote(): RemoteEvent?
	return getRemote(Constants.Remotes.Events)
end

function Remotes.GetArenaRemote(): RemoteEvent?
	return getRemote(Constants.Remotes.Arena)
end

function Remotes.GetShopRemote(): RemoteFunction?
	return getRemoteFunction(Constants.Remotes.Shop)
end

function Remotes.GetDevRemote(): RemoteFunction?
	return getRemoteFunction(Constants.Remotes.Dev)
end

return Remotes
