--!strict

-- DevService: handler do BrawlDev RemoteFunction. Valida que o caller tá em
-- Constants.Dev.UserIds antes de aplicar qualquer mutação (grant coins etc).
-- Client UI também checa pra mostrar/esconder, mas a verdade é aqui.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

local ACTIONS = Constants.Dev.Actions

local DevService = {}
DevService._services = nil :: Services?

local function isDev(userId: number): boolean
	for _, id in ipairs(Constants.Dev.UserIds) do
		if id == userId then
			return true
		end
	end
	return false
end

function DevService:Init(services: Services)
	self._services = services
end

function DevService:_handleInvoke(player: Player, request: any): any
	if not isDev(player.UserId) then
		return { success = false, reason = "NotAuthorized" }
	end
	if typeof(request) ~= "table" then
		return { success = false, reason = "BadRequest" }
	end

	local action = request.action
	if action == ACTIONS.GrantCoins then
		local services = self._services :: Services
		local playerData = services.PlayerDataService
		if not playerData or not playerData:IsLoaded(player) then
			return { success = false, reason = "ProfileNotLoaded" }
		end
		local amount = tonumber(request.amount) or 0
		if amount <= 0 then
			return { success = false, reason = "BadAmount" }
		end
		local newBalance = playerData:AddCurrency(player, amount)
		print(string.format(
			"[DevService] GrantCoins: userId=%d amount=%d → newBalance=%d",
			player.UserId, amount, newBalance
		))
		return { success = true, newBalance = newBalance }
	end

	return { success = false, reason = "UnknownAction" }
end

function DevService:Start()
	local remote = Remotes.GetDevRemote()
	assert(remote, "BrawlDev RemoteFunction not found")

	remote.OnServerInvoke = function(player: Player, request: any): any
		local ok, result = pcall(function()
			return self:_handleInvoke(player, request)
		end)
		if not ok then
			warn("[DevService] Invoke failed:", result)
			return { success = false, reason = "InternalError" }
		end
		return result
	end
end

return DevService
