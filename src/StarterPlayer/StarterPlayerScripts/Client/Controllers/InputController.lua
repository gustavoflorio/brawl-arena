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

function InputController:_firePunch(isHeavy: boolean)
	local remote = Remotes.GetRequestRemote()
	if remote then
		local action = isHeavy and Constants.Actions.HeavyPunch or Constants.Actions.Punch
		remote:FireServer(action)
	end
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch(isHeavy)
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
		if self._currentState ~= Constants.PlayerState.InArena then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_firePunch(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_firePunch(true)
		end
	end)
end

return InputController
