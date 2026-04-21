--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local InputController = {}
InputController._controllers = nil :: { [string]: any }?
InputController._currentState = Constants.PlayerState.InLobby

function InputController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function InputController:_firePunch()
	local remote = Remotes.GetRequestRemote()
	if remote then
		remote:FireServer(Constants.Actions.Punch)
	end
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch()
	end
end

function InputController:Start()
	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
				self._currentState = snapshot.state
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self._currentState == Constants.PlayerState.InArena then
				self:_firePunch()
			end
		end
	end)
end

return InputController
