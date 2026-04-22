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
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	if fxController and type(fxController.IsPunching) == "function" and fxController:IsPunching() then
		return
	end
	local remote = Remotes.GetRequestRemote()
	if remote then
		local action = isHeavy and Constants.Actions.HeavyPunch or Constants.Actions.Punch
		remote:FireServer(action)
	end
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch(isHeavy)
	end
	local movementController = controllers and controllers.MovementController
	if movementController and type(movementController.StartPunchLock) == "function" then
		local lockDuration = isHeavy and Constants.Combat.HeavyPunchStartupLockSeconds
			or Constants.Combat.PunchStartupLockSeconds
		movementController:StartPunchLock(lockDuration)
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

	-- M2 é consumido pelo default camera rotation script (processed=true),
	-- mas queremos firar heavy punch mesmo assim — por isso não checamos
	-- processed pra MouseButton2. M1 respeita processed pra não firar
	-- punch quando clicando em UI (ex: donate button).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if self._currentState ~= Constants.PlayerState.InArena then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if processed then
				return
			end
			self:_firePunch(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_firePunch(true)
		end
	end)
end

return InputController
