--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Ballerina: identidade = mobility (vai ganhar dashes/twirls com i-frames e
-- reposicionamento em PR futura). Por enquanto compartilha moveset com
-- Boxer — placeholder até diferenciação real.

local Ballerina = {
	Id = "Ballerina",
	DisplayName = "Ballerina",
	Description = "Pure mobility. Reposition, dance, escape.",
	IconAssetId = "",
	Price = 500,
	IsDefault = false,
	Moves = Constants.Combat.Moves,
}

return Ballerina
