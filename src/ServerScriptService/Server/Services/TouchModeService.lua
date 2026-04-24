--!strict

-- Força DynamicThumbstick em mobile. Sem isso, cai em Classic Thumbstick
-- (base circular cinza persistente no canto inferior esquerdo), mesmo
-- com StarterPlayer.DevTouchMovementMode no project.json — porque rojo
-- serve não atualiza props do StarterPlayer em runtime sem rebuild rbxlx.
--
-- DevTouchMovementMode é protected: local scripts dão "Insufficient
-- permissions". Precisa rodar no servidor.
--
-- Aplica em duas camadas: StarterPlayer (novos players) + cada Player
-- instance (existentes e PlayerAdded). Redundância proposital — uma
-- cobre casos onde a outra pode falhar.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local TouchModeService = {}

local function applyMode(player: Player)
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.DynamicThumbstick
end

function TouchModeService:Init(_services: { [string]: any })
	-- Aplica no StarterPlayer logo em Init pra novos players já nascerem
	-- com o modo correto (antes do PlayerModule do client criar TouchGui).
	pcall(function()
		StarterPlayer.DevTouchMovementMode = Enum.DevTouchMovementMode.DynamicThumbstick
	end)
end

function TouchModeService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		applyMode(player)
	end
	Players.PlayerAdded:Connect(applyMode)
end

return TouchModeService
