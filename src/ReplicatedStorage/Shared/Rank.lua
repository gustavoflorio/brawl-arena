--!strict

local Rank = {}

local UNRANKED = Color3.fromRGB(150, 150, 150)
local BRONZE = Color3.fromRGB(170, 100, 50)
local SILVER = Color3.fromRGB(180, 180, 200)
local GOLD = Color3.fromRGB(240, 200, 60)
local PLATINUM = Color3.fromRGB(120, 220, 200)
local DIAMOND = Color3.fromRGB(100, 200, 255)
local CHAMPION = Color3.fromRGB(255, 80, 80)

function Rank.getColor(tier: number): Color3
	if tier <= 1 then
		return UNRANKED
	elseif tier <= 4 then
		return BRONZE
	elseif tier <= 7 then
		return SILVER
	elseif tier <= 10 then
		return GOLD
	elseif tier <= 13 then
		return PLATINUM
	elseif tier <= 16 then
		return DIAMOND
	end
	return CHAMPION
end

function Rank.format(brief: { name: string, tier: number }?): (string, Color3)
	if not brief then
		return "Unranked", UNRANKED
	end
	return brief.name, Rank.getColor(brief.tier)
end

-- Ícones do rank por divisão. Mesmos asset IDs usados no ranking board
-- (RankingService.RANK_ICON_IDS) — single source quando possível.
-- Unranked é explicitamente nil — caller deve esconder o ImageLabel nesse caso.
local RANK_ICONS = {
	Bronze = "rbxassetid://95221352287862",
	Silver = "rbxassetid://87829525424272",
	Gold = "rbxassetid://90669385414264",
	Platinum = "rbxassetid://128268020488699",
	Diamond = "rbxassetid://78191016954660",
	Champion = "rbxassetid://83852817358288",
}

function Rank.getIconAsset(tier: number): string?
	if tier <= 1 then
		return nil
	elseif tier <= 4 then
		return RANK_ICONS.Bronze
	elseif tier <= 7 then
		return RANK_ICONS.Silver
	elseif tier <= 10 then
		return RANK_ICONS.Gold
	elseif tier <= 13 then
		return RANK_ICONS.Platinum
	elseif tier <= 16 then
		return RANK_ICONS.Diamond
	end
	return RANK_ICONS.Champion
end

return Rank
