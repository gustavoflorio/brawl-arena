--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local CameraController = {}
CameraController._connection = nil :: RBXScriptConnection?
CameraController._currentState = Constants.PlayerState.InLobby

local CAMERA_DISTANCE = 40
local CAMERA_HEIGHT = 6

local function getRoot(): BasePart?
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

local function restoreDefaultCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = nil
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function CameraController:_enterArenaCamera()
	if self._connection then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	self._connection = RunService.RenderStepped:Connect(function()
		local root = getRoot()
		if not root then
			return
		end
		local targetPos = Vector3.new(root.Position.X, root.Position.Y + CAMERA_HEIGHT * 0.25, 0)
		local camPos = Vector3.new(root.Position.X, root.Position.Y + CAMERA_HEIGHT, CAMERA_DISTANCE)
		camera.CFrame = CFrame.new(camPos, targetPos)
	end)
end

function CameraController:_exitArenaCamera()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	restoreDefaultCamera()
end

function CameraController:_applyState(state: string)
	if state == self._currentState then
		return
	end
	self._currentState = state
	if state == Constants.PlayerState.InArena then
		self:_enterArenaCamera()
	else
		self:_exitArenaCamera()
	end
end

function CameraController:Init(_controllers: { [string]: any }) end

function CameraController:Start()
	restoreDefaultCamera()

	player.CharacterAdded:Connect(function()
		task.defer(function()
			if self._currentState == Constants.PlayerState.InArena then
				-- character novo após cair: servidor vai publicar InLobby, mas garantimos reset.
				self:_exitArenaCamera()
				self._currentState = Constants.PlayerState.InLobby
			else
				restoreDefaultCamera()
			end
		end)
	end)

	local remote = Remotes.GetStateRemote()
	if not remote then
		warn("[CameraController] BrawlState remote não encontrado.")
		return
	end
	remote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
			self:_applyState(snapshot.state)
		end
	end)
end

return CameraController
