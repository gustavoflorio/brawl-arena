--!strict

local ServiceLoader = {}

type Services = { [string]: any }

local services: Services = {}
local loadOrder = {
	"PlayerDataService",
	"AnalyticsService",
	"RankService",
	"RankingService",
	"MonetizationService",
	"KillProcessor",
	"ArenaService",
	"CombatService",
	"TouchModeService",
}

function ServiceLoader:Init()
	local servicesFolder = script.Parent:WaitForChild("Services")

	for _, serviceName in ipairs(loadOrder) do
		local moduleScript = servicesFolder:FindFirstChild(serviceName)
		assert(
			moduleScript and moduleScript:IsA("ModuleScript"),
			string.format("Missing service module: %s", serviceName)
		)
		services[serviceName] = require(moduleScript)
	end

	for _, serviceName in ipairs(loadOrder) do
		local service = services[serviceName]
		if type(service.Init) == "function" then
			service:Init(services)
		end
	end
end

function ServiceLoader:Start()
	for _, serviceName in ipairs(loadOrder) do
		local service = services[serviceName]
		if type(service.Start) == "function" then
			service:Start()
		end
	end
end

function ServiceLoader:GetServices(): Services
	return services
end

return ServiceLoader
