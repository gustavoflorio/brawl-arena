--!strict

-- STUB: implementação completa na Lane B (WS2).
-- Propósito: calcula tier a partir de rankPoints, XP bonus MMR, promotion/demotion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

type Services = { [string]: any }

local RankService = {}
RankService._services = nil :: Services?

function RankService:Init(services: Services)
	self._services = services
end

function RankService:Start() end

function RankService:GetTier(rankPoints: number): (number, string)
	local matchedIdx = 1
	local matchedName = Constants.Rank.Tiers[1].name
	for idx, tier in ipairs(Constants.Rank.Tiers) do
		if rankPoints >= tier.threshold then
			matchedIdx = idx
			matchedName = tier.name
		else
			break
		end
	end
	return matchedIdx, matchedName
end

function RankService:ComputeXPBonus(puncherTier: number, targetTier: number): number
	local diff = targetTier - puncherTier
	local bonus = diff * Constants.XP.MMRMultiplier
	return math.clamp(bonus, Constants.XP.BonusClampMin, Constants.XP.BonusClampMax)
end

return RankService
