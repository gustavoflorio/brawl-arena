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

function RankService:ComputeXPGain(puncherTier: number, targetTier: number): number
	local diff = math.max(0, targetTier - puncherTier)
	local multiplier = 1 + diff * Constants.XP.TierBonusPercent
	return math.ceil(Constants.XP.Base * multiplier)
end

function RankService:GetDivision(tierIdx: number): number
	if tierIdx <= 1 then
		return 0
	elseif tierIdx <= 4 then
		return 1
	elseif tierIdx <= 7 then
		return 2
	elseif tierIdx <= 10 then
		return 3
	elseif tierIdx <= 13 then
		return 4
	elseif tierIdx <= 16 then
		return 5
	end
	return 6
end

function RankService:ComputeRankPointsDeltas(puncherTier: number, targetTier: number): (number, number)
	local diff = self:GetDivision(targetTier) - self:GetDivision(puncherTier)
	local multiplier = 1 + diff * Constants.Rank.DivisionBonusPercent
	local killerGain = math.ceil(Constants.Rank.PointsPerKill * multiplier)
	local targetLoss = math.ceil(Constants.Rank.PointsLostPerDeath * multiplier)
	return killerGain, targetLoss
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

function RankService:ApplyKillDelta(player: Player, targetTier: number): RankDeltaResult?
	local brief = self:GetRankBrief(player)
	local gain, _ = self:ComputeRankPointsDeltas(brief.tier, targetTier)
	return self:ApplyPointsDelta(player, gain)
end

function RankService:ApplyDeathDelta(player: Player, puncherTier: number): RankDeltaResult?
	local brief = self:GetRankBrief(player)
	local _, loss = self:ComputeRankPointsDeltas(puncherTier, brief.tier)
	return self:ApplyPointsDelta(player, -loss)
end

return RankService
