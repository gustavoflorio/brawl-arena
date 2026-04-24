--!strict

-- Força DynamicThumbstick em todo player que entra. Sem isso, a Roblox
-- cai em Thumbstick classic (base circular escura persistente no canto
-- inferior esquerdo), mesmo com StarterPlayer.DevTouchMovementMode
-- setado no project.json.
--
-- DevTouchMovementMode é protected: local scripts não conseguem settar
-- (erro "Insufficient permissions"). Precisa rodar no servidor.

local Players = game:GetService("Players")

local TouchModeService = {}

local function applyMode(player: Player)
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.DynamicThumbstick
end

function TouchModeService:Init(_services: { [string]: any }) end

function TouchModeService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		applyMode(player)
	end
	Players.PlayerAdded:Connect(applyMode)
end

return TouchModeService
