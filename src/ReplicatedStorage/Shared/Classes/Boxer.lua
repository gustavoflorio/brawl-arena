--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Boxer: classe default, gratuita. Identidade: pressão constante (vai ganhar
-- jabs rápidos com baixo recovery em PR futura). Por enquanto, moveset é
-- exatamente o moveset histórico do jogo (Jab1→Jab2→Jab3 + Heavy).

local Boxer = {
	Id = "Boxer",
	DisplayName = "Boxer",
	Description = "Constant pressure. Fast jabs, no mystery.",
	IconAssetId = "77777904772382",
	Price = 0,
	IsDefault = true,
	Moves = Constants.Combat.Moves,
	ComboStarter = "Jab1",
	HeavyKey = "Heavy",
}

return Boxer
