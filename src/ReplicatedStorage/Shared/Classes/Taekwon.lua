--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Taekwon: identidade = burst (vai ganhar chutes longos, mais dano por hit
-- mas com gaps maiores entre golpes em PR futura). Por enquanto compartilha
-- moveset com Boxer — placeholder até diferenciação real.

local Taekwon = {
	Id = "Taekwon",
	DisplayName = "Taekwon",
	Description = "High burst. Long kicks, surgical punishment.",
	IconAssetId = "",
	Price = 500,
	IsDefault = false,
	Moves = Constants.Combat.Moves,
}

return Taekwon
