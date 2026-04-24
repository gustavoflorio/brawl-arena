--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

type Services = { [string]: any }

local RankService = {}
RankService._services = nil :: Services?

local TIERS_COUNT = #Constants.Rank.Tiers
local CHAMPION_IDX = TIERS_COUNT
local UNRANKED_IDX = 1
local BRONZE_I_IDX = 2

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

function RankService:ComputeXPGain(puncherTier: number, targetTier: number): number
	local diff = math.max(0, targetTier - puncherTier)
	local multiplier = 1 + diff * Constants.XP.TierBonusPercent
	return math.ceil(Constants.XP.Base * multiplier)
end

local DIVISION_NAMES = { "Unranked", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion" }

function RankService:GetDivisionRates(tierIdx: number): { kill: number, death: number }
	local div = self:GetDivision(tierIdx)
	local name = DIVISION_NAMES[div + 1]
	return Constants.Rank.DivisionRates[name]
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

local function tierThreshold(tierIdx: number): number
	if tierIdx < 1 then
		return 0
	end
	if tierIdx > TIERS_COUNT then
		tierIdx = TIERS_COUNT
	end
	return Constants.Rank.Tiers[tierIdx].threshold
end

type RankDeltaResult = {
	previousTier: number,
	newTier: number,
	previousName: string,
	newName: string,
	previousPoints: number,
	newPoints: number,
	promoted: boolean,
	demoted: boolean,
	seriesKind: string,
	seriesProgress: number,
	seriesEvent: string?,
}

local function baseResult(prevTierIdx: number, prevTierName: string, prevPoints: number, profile: any): RankDeltaResult
	return {
		previousTier = prevTierIdx,
		newTier = prevTierIdx,
		previousName = prevTierName,
		newName = prevTierName,
		previousPoints = prevPoints,
		newPoints = prevPoints,
		promoted = false,
		demoted = false,
		seriesKind = profile.SeriesKind or "none",
		seriesProgress = profile.SeriesProgress or 0,
		seriesEvent = nil,
	}
end

local function syncOverhead(playerData: any, player: Player)
	if type(playerData.SyncOverheadAttributes) == "function" then
		playerData:SyncOverheadAttributes(player)
	end
end

function RankService:ApplyPointsDelta(player: Player, delta: number): RankDeltaResult?
	local playerData = (self._services :: Services).PlayerDataService
	local profile = playerData:GetProfile(player)
	if not profile then
		return nil
	end

	local previousPoints = profile.RankPoints
	local previousTier, previousName = self:GetTier(previousPoints)
	local newPoints = math.max(0, previousPoints + delta)
	playerData:SetRankPoints(player, newPoints)

	local newTier, newName = self:GetTier(newPoints)
	playerData:SetRankName(player, newName)
	syncOverhead(playerData, player)

	return {
		previousTier = previousTier,
		newTier = newTier,
		previousName = previousName,
		newName = newName,
		previousPoints = previousPoints,
		newPoints = newPoints,
		promoted = newTier > previousTier,
		demoted = newTier < previousTier,
		seriesKind = profile.SeriesKind or "none",
		seriesProgress = profile.SeriesProgress or 0,
		seriesEvent = nil,
	}
end

function RankService:ApplyKill(player: Player): RankDeltaResult?
	local playerData = (self._services :: Services).PlayerDataService
	local profile = playerData:GetProfile(player)
	if not profile then
		return nil
	end

	local prevAbsoluteFP = profile.RankPoints
	local prevTierIdx, prevTierName = self:GetTier(prevAbsoluteFP)
	local rates = self:GetDivisionRates(prevTierIdx)
	local result = baseResult(prevTierIdx, prevTierName, prevAbsoluteFP, profile)

	-- Em demote series: kill quebra → safety landing (25 FP no tier atual).
	if profile.SeriesKind == "demote" then
		local newPoints = tierThreshold(prevTierIdx) + Constants.Rank.DemoteFailLanding
		playerData:SetRankPoints(player, newPoints)
		playerData:SetSeriesState(player, "none", 0)
		playerData:SetRankName(player, prevTierName)
		syncOverhead(playerData, player)
		result.newPoints = newPoints
		result.seriesKind = "none"
		result.seriesProgress = 0
		result.seriesEvent = "demote_broken"
		return result
	end

	-- Em promo series: incrementa progresso. Se completar, promove.
	if profile.SeriesKind == "promo" then
		local newProgress = profile.SeriesProgress + 1
		if newProgress >= Constants.Rank.SeriesLength then
			-- Promote!
			local newTierIdx = math.min(prevTierIdx + 1, CHAMPION_IDX)
			local newName = Constants.Rank.Tiers[newTierIdx].name
			local newPoints = tierThreshold(newTierIdx)
			playerData:SetRankPoints(player, newPoints)
			playerData:SetRankName(player, newName)
			playerData:SetSeriesState(player, "none", 0)
			syncOverhead(playerData, player)
			result.newTier = newTierIdx
			result.newName = newName
			result.newPoints = newPoints
			result.promoted = true
			result.seriesKind = "none"
			result.seriesProgress = 0
			result.seriesEvent = "promoted"
		else
			playerData:SetSeriesState(player, "promo", newProgress)
			result.seriesProgress = newProgress
			result.seriesEvent = "promo_advanced"
		end
		return result
	end

	-- Sem série ativa: kill normal aplica taxa.
	local gainedFP = prevAbsoluteFP + rates.kill

	-- Champion: terminal, sem promo series, FP acumula livremente.
	if prevTierIdx >= CHAMPION_IDX then
		playerData:SetRankPoints(player, gainedFP)
		syncOverhead(playerData, player)
		result.newPoints = gainedFP
		return result
	end

	local nextThreshold = tierThreshold(prevTierIdx + 1)
	if gainedFP >= nextThreshold then
		-- Cruzou o limite do próximo tier.
		local nextTierIdx = prevTierIdx + 1
		local prevDivision = self:GetDivision(prevTierIdx)
		local nextDivision = self:GetDivision(nextTierIdx)
		-- Série de promoção só aplica em cruzamento de DIVISÃO (Bronze III →
		-- Silver I, Silver III → Gold I, etc). Transições intra-divisão
		-- (Bronze I → Bronze II) são auto-promote direto. Unranked → Bronze I
		-- também é auto-promote (divisão 0 → 1 mas é o onboarding).
		local isIntraDivision = nextDivision == prevDivision
		if prevTierIdx == UNRANKED_IDX or isIntraDivision then
			local newTierIdx = math.min(nextTierIdx, CHAMPION_IDX)
			local newName = Constants.Rank.Tiers[newTierIdx].name
			local newPoints = tierThreshold(newTierIdx)
			playerData:SetRankPoints(player, newPoints)
			playerData:SetRankName(player, newName)
			syncOverhead(playerData, player)
			result.newTier = newTierIdx
			result.newName = newName
			result.newPoints = newPoints
			result.promoted = true
			result.seriesEvent = "auto_promoted"
		else
			-- Entra em promo series. FP travado em (próximo threshold - 1) = 99 dentro do tier.
			local newPoints = nextThreshold - 1
			playerData:SetRankPoints(player, newPoints)
			playerData:SetSeriesState(player, "promo", 0)
			result.newPoints = newPoints
			result.seriesKind = "promo"
			result.seriesProgress = 0
			result.seriesEvent = "promo_started"
		end
	else
		playerData:SetRankPoints(player, gainedFP)
		result.newPoints = gainedFP
	end

	syncOverhead(playerData, player)
	return result
end

function RankService:ApplyDeath(player: Player): RankDeltaResult?
	local playerData = (self._services :: Services).PlayerDataService
	local profile = playerData:GetProfile(player)
	if not profile then
		return nil
	end

	local prevAbsoluteFP = profile.RankPoints
	local prevTierIdx, prevTierName = self:GetTier(prevAbsoluteFP)
	local rates = self:GetDivisionRates(prevTierIdx)
	local result = baseResult(prevTierIdx, prevTierName, prevAbsoluteFP, profile)

	-- Em promo series: morte quebra → fail landing (75 FP no tier atual).
	if profile.SeriesKind == "promo" then
		local newPoints = tierThreshold(prevTierIdx) + Constants.Rank.PromoFailLanding
		playerData:SetRankPoints(player, newPoints)
		playerData:SetSeriesState(player, "none", 0)
		playerData:SetRankName(player, prevTierName)
		syncOverhead(playerData, player)
		result.newPoints = newPoints
		result.seriesKind = "none"
		result.seriesProgress = 0
		result.seriesEvent = "promo_failed"
		return result
	end

	-- Em demote series: incrementa progresso. Se completar, demote.
	if profile.SeriesKind == "demote" then
		local newProgress = profile.SeriesProgress + 1
		if newProgress >= Constants.Rank.SeriesLength then
			-- Demote!
			local newTierIdx = math.max(prevTierIdx - 1, UNRANKED_IDX)
			local newName = Constants.Rank.Tiers[newTierIdx].name
			local newPoints = tierThreshold(newTierIdx) + Constants.Rank.DemoteSuccessLanding
			playerData:SetRankPoints(player, newPoints)
			playerData:SetRankName(player, newName)
			playerData:SetSeriesState(player, "none", 0)
			syncOverhead(playerData, player)
			result.newTier = newTierIdx
			result.newName = newName
			result.newPoints = newPoints
			result.demoted = true
			result.seriesKind = "none"
			result.seriesProgress = 0
			result.seriesEvent = "demoted"
		else
			playerData:SetSeriesState(player, "demote", newProgress)
			result.seriesProgress = newProgress
			result.seriesEvent = "demote_advanced"
		end
		return result
	end

	-- Sem série: morte normal aplica taxa.
	-- Bronze I e Unranked não demotam (floor).
	if prevTierIdx <= BRONZE_I_IDX then
		local floor = tierThreshold(prevTierIdx)
		local newFP = math.max(floor, prevAbsoluteFP - rates.death)
		playerData:SetRankPoints(player, newFP)
		syncOverhead(playerData, player)
		result.newPoints = newFP
		return result
	end

	local newFP = prevAbsoluteFP - rates.death
	local currentThreshold = tierThreshold(prevTierIdx)

	if newFP <= currentThreshold then
		-- Cruzou o piso do tier atual.
		local nextTierIdx = prevTierIdx - 1
		local prevDivision = self:GetDivision(prevTierIdx)
		local nextDivision = self:GetDivision(nextTierIdx)
		-- Série de demote só aplica em cruzamento de DIVISÃO (Silver I → Bronze III,
		-- Gold I → Silver III, etc). Intra-divisão (Bronze II → Bronze I)
		-- é auto-demote direto com landing de DemoteSuccessLanding FP no
		-- tier de baixo.
		local isIntraDivision = nextDivision == prevDivision
		if isIntraDivision then
			local newTierIdx = math.max(nextTierIdx, UNRANKED_IDX)
			local newName = Constants.Rank.Tiers[newTierIdx].name
			local newPoints = tierThreshold(newTierIdx) + Constants.Rank.DemoteSuccessLanding
			playerData:SetRankPoints(player, newPoints)
			playerData:SetRankName(player, newName)
			syncOverhead(playerData, player)
			result.newTier = newTierIdx
			result.newName = newName
			result.newPoints = newPoints
			result.demoted = true
			result.seriesEvent = "auto_demoted"
		else
			-- Entra em demote series. FP travado em 0 dentro do tier.
			playerData:SetRankPoints(player, currentThreshold)
			playerData:SetSeriesState(player, "demote", 0)
			result.newPoints = currentThreshold
			result.seriesKind = "demote"
			result.seriesProgress = 0
			result.seriesEvent = "demote_started"
		end
	else
		playerData:SetRankPoints(player, newFP)
		result.newPoints = newFP
	end

	syncOverhead(playerData, player)
	return result
end

return RankService
