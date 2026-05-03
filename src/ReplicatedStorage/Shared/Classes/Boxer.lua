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
	-- Burnished gold (mid luminance ~0.65). Reads as "default/grounded/heavy".
	AccentColor = Color3.fromRGB(220, 180, 90),
	-- Boxing gloves nas mãos. Asset IDs Roblox catalog placeholder por 'Turesa
	-- (luvas pareadas L+R, Shoulder attachments). Swap por arte custom depois.
	AccessoryAssetIds = {
		107859381954122, -- [R6] Left Boxing Glove
		97239457897224,  -- [R6] Right Boxing Glove
	} :: { number },
}

return Boxer
