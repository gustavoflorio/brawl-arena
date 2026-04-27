--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Ballerina: identidade = mobility. Por ora frame data (damage/range/timings) é
-- clonada de Constants.Combat.Moves — só os AnimationIds são proprios. A
-- diferenciação real (thrusts, hitboxes, recovery por golpe) entra em PR
-- futura. Manter as chaves Jab1/Jab2/Jab3/Heavy é obrigatório porque o cliente
-- usa string.sub(moveKey, 4) pra extrair o comboIndex (InputController.lua) e
-- o servidor reconstrói "Jab" .. comboIndex (CombatService.lua).

local function deepClone<T>(t: T): T
	local copy: { [any]: any } = {}
	for k, v in pairs(t :: any) do
		if typeof(v) == "table" then
			copy[k] = deepClone(v)
		else
			copy[k] = v
		end
	end
	return copy :: any
end

local Moves = deepClone(Constants.Combat.Moves)
Moves.Jab1.AnimationId = "rbxassetid://121219969575849"  -- Jette 1
Moves.Jab2.AnimationId = "rbxassetid://131729594416095"  -- Jette 2
Moves.Jab3.AnimationId = "rbxassetid://117200019361388"  -- Arabesque
Moves.Heavy.AnimationId = "rbxassetid://109321388916076" -- Pirouette

local Ballerina = {
	Id = "Ballerina",
	DisplayName = "Ballerina",
	Description = "Pure mobility. Reposition, dance, escape.",
	IconAssetId = "",
	Price = 500,
	IsDefault = false,
	Moves = Moves,
}

return Ballerina
