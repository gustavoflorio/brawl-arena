--!strict

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

function RankService:GetRankBrief(player: Player): { name: string, tier: number }
	local playerData = (self._services :: Services).PlayerDataService
	local profile = playerData:GetProfile(player)
	if not profile then
		return { name = "Unranked", tier = 1 }
	end
	local tier, name = self:GetTier(profile.RankPoints)
	return { name = name, tier = tier }
end

type RankDeltaResult = {
	previousTier: number,
	newTier: number,
	previousName: string,
	newName: string,
	promoted: boolean,
	demoted: boolean,
}

function RankService:ApplyPointsDelta(player: Player, delta: number): RankDeltaResult?
	local playerData = (self._services :: Services).PlayerDataService
	local profile = playerData:GetProfile(player)
	if not profile then
		return nil
	end

	local previousTier, previousName = self:GetTier(profile.RankPoints)
	local newPoints = math.max(0, profile.RankPoints + delta)
	playerData:SetRankPoints(player, newPoints)

	local newTier, newName = self:GetTier(newPoints)
	playerData:SetRankName(player, newName)

	return {
		previousTier = previousTier,
		newTier = newTier,
		previousName = previousName,
		newName = newName,
		promoted = newTier > previousTier,
		demoted = newTier < previousTier,
	}
end

function RankService:ApplyKillDelta(player: Player): RankDeltaResult?
	return self:ApplyPointsDelta(player, Constants.Rank.PointsPerKill)
end

function RankService:ApplyDeathDelta(player: Player): RankDeltaResult?
	return self:ApplyPointsDelta(player, -Constants.Rank.PointsLostPerDeath)
end

return RankService
