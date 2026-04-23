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
CameraController._camPos = Vector3.zero
CameraController._lookPos = Vector3.zero
CameraController._lookAheadX = 0
CameraController._anchorX = 0

local CAMERA_DISTANCE = 40
local CAMERA_HEIGHT = 6
local FOLLOW_RATE = 8 -- exponential damping; maior = mais responsivo, menor = mais laggy
local LOOK_AHEAD_FACTOR = 0.25 -- studs de offset por unit/s de velocidade horizontal
local LOOK_AHEAD_MAX = 7 -- cap pra não desorientar
local LOOK_AHEAD_RATE = 3 -- damping próprio do offset; menor = transição de direção mais suave
local DEADZONE_X = 4 -- studs; player pode se mexer ±4 sem puxar a câmera

local function damp(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function dampV(current: Vector3, target: Vector3, rate: number, dt: number): Vector3
	return current:Lerp(target, 1 - math.exp(-rate * dt))
end

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

	-- Snap inicial pra não lerpar do (0,0,0) no primeiro frame.
	local root = getRoot()
	if root then
		local rootPos = root.Position
		self._camPos = Vector3.new(rootPos.X, rootPos.Y + CAMERA_HEIGHT, CAMERA_DISTANCE)
		self._lookPos = Vector3.new(rootPos.X, rootPos.Y + CAMERA_HEIGHT * 0.25, 0)
		self._anchorX = rootPos.X
	end
	self._lookAheadX = 0

	camera.CameraType = Enum.CameraType.Scriptable
	self._connection = RunService.RenderStepped:Connect(function(dt)
		local r = getRoot()
		if not r then
			return
		end
		local rootPos = r.Position

		-- Deadzone X: anchor só se move quando o player sai dos ±DEADZONE_X.
		-- Pulinhos pequenos pros lados não puxam a câmera; só movimento real.
		local distFromAnchor = rootPos.X - self._anchorX
		if distFromAnchor > DEADZONE_X then
			self._anchorX = rootPos.X - DEADZONE_X
		elseif distFromAnchor < -DEADZONE_X then
			self._anchorX = rootPos.X + DEADZONE_X
		end

		local velX = r.AssemblyLinearVelocity.X
		local desiredLookAhead = math.clamp(velX * LOOK_AHEAD_FACTOR, -LOOK_AHEAD_MAX, LOOK_AHEAD_MAX)
		self._lookAheadX = damp(self._lookAheadX, desiredLookAhead, LOOK_AHEAD_RATE, dt)

		local focusX = self._anchorX + self._lookAheadX
		local desiredCamPos = Vector3.new(focusX, rootPos.Y + CAMERA_HEIGHT, CAMERA_DISTANCE)
		local desiredLookPos = Vector3.new(focusX, rootPos.Y + CAMERA_HEIGHT * 0.25, 0)

		self._camPos = dampV(self._camPos, desiredCamPos, FOLLOW_RATE, dt)
		self._lookPos = dampV(self._lookPos, desiredLookPos, FOLLOW_RATE, dt)

		camera.CFrame = CFrame.new(self._camPos, self._lookPos)
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
