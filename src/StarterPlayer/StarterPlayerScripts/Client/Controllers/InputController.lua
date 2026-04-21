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
	print(string.format("[InputController] _firePunch isHeavy=%s state=%s", tostring(isHeavy), self._currentState))
	if self._currentState ~= Constants.PlayerState.InArena then
		print("[InputController] bail: not in arena")
		return
	end
	if self:_isBusy() then
		print("[InputController] bail: busy (dodging)")
		return
	end
	local remote = Remotes.GetRequestRemote()
	if remote then
		local action = isHeavy and Constants.Actions.HeavyPunch or Constants.Actions.Punch
		print("[InputController] firing action:", action)
		remote:FireServer(action)
	else
		warn("[InputController] BrawlRequest remote não encontrado ao firar punch")
	end
	local controllers = self._controllers
	local fxController = controllers and controllers.CombatFxController
	if fxController and type(fxController.PlayLocalPunch) == "function" then
		fxController:PlayLocalPunch(isHeavy)
	end
end

function InputController:Start()
	print("[InputController] Start — conectando UserInputService.InputBegan")

	local stateRemote = Remotes.GetStateRemote()
	if stateRemote then
		stateRemote.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" and typeof(snapshot.state) == "string" then
				if snapshot.state ~= self._currentState then
					print("[InputController] state snapshot:", snapshot.state)
				end
				self._currentState = snapshot.state
			end
		end)
	else
		warn("[InputController] BrawlState remote não encontrado ao conectar")
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- Gate apenas por estado InArena (não por processed flag).
		-- processed=true acontece pra M2 quando camera module marca,
		-- mas queremos firar heavy punch mesmo assim.
		if self._currentState ~= Constants.PlayerState.InArena then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if processed then
				return -- M1 em UI (botão de donate por exemplo), deixa passar
			end
			print("[InputController] M1 detectado")
			self:_firePunch(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			print("[InputController] M2 detectado (processed=" .. tostring(processed) .. ")")
			self:_firePunch(true)
		end
	end)
end

return InputController
