--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local ACTION_LIGHT_PUNCH = "BrawlLightPunch"
local ACTION_HEAVY_PUNCH = "BrawlHeavyPunch"

local InputController = {}
InputController._controllers = nil :: { [string]: any }?
InputController._currentState = Constants.PlayerState.InLobby

function InputController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function InputController:_isBusy(): boolean
	local controllers = self._controllers
	local movementController = controllers and controllers.MovementController
	if movementController and type(movementController.IsDodging) == "function" then
		if movementController:IsDodging() then
			return true
		end
	end
	return false
end

function InputController:_firePunch(isHeavy: boolean)
	if self._currentState ~= Constants.PlayerState.InArena then
		return
	end
	if self:_isBusy() then
		return
	end
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

function InputController:_handleLightPunch(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		self:_firePunch(false)
	end
	return Enum.ContextActionResult.Sink
end

function InputController:_handleHeavyPunch(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		self:_firePunch(true)
	end
	return Enum.ContextActionResult.Sink
end

function InputController:Start()
	ContextActionService:BindAction(
		ACTION_LIGHT_PUNCH,
		function(name, state, input)
			return self:_handleLightPunch(name, state, input)
		end,
		false,
		Enum.UserInputType.MouseButton1
	)
	ContextActionService:BindAction(
		ACTION_HEAVY_PUNCH,
		function(name, state, input)
			return self:_handleHeavyPunch(name, state, input)
		end,
		false,
		Enum.UserInputType.MouseButton2
	)

	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
				self._currentState = snapshot.state
			end
		end)
	end
end

return InputController
