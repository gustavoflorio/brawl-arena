--!strict

local controllersFolder = script.Parent:WaitForChild("Controllers")

local controllerOrder = {
	"CameraController",
	"MovementController",
	"CombatFxController",
	"InputController",
	"HudController",
	"KillFeedController",
	"StreakController",
	"LevelUpController",
	"RankUpController",
	"SummaryController",
	"DamageLabelController",
}

local controllers: { [string]: any } = {}

for _, name in ipairs(controllerOrder) do
	local module = controllersFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			controllers[name] = result
		else
			warn(string.format("[Client] Falha ao carregar controller %s: %s", name, tostring(result)))
		end
	end
end

for _, name in ipairs(controllerOrder) do
	local controller = controllers[name]
	if controller and type(controller.Init) == "function" then
		local ok, err = pcall(function()
			controller:Init(controllers)
		end)
		if not ok then
			warn(string.format("[Client] Init falhou em %s: %s", name, tostring(err)))
		end
	end
end

for _, name in ipairs(controllerOrder) do
	local controller = controllers[name]
	if controller and type(controller.Start) == "function" then
		local ok, err = pcall(function()
			controller:Start()
		end)
		if not ok then
			warn(string.format("[Client] Start falhou em %s: %s", name, tostring(err)))
		end
	end
end

print("[BrawlArena] Client bootstrap concluído")
