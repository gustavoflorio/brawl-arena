--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

type StreakState = {
	count: number,
	lastKillTime: number,
}

local KillProcessor = {}
KillProcessor._services = nil :: Services?
KillProcessor._streaks = {} :: { [Player]: StreakState }

local function streakKind(count: number, delta: number): (string?, boolean)
	if count >= Constants.Streak.DominatingThreshold then
		return "Dominating", true
	end
	if count == 3 and delta <= Constants.Streak.TripleWindow then
		return "Triple", true
	end
	if count == 2 and delta <= Constants.Streak.DoubleWindow then
		return "Double", true
	end
	return nil, false
end

function KillProcessor:Init(services: Services)
	self._services = services
end

function KillProcessor:Start()
	Players.PlayerRemoving:Connect(function(player)
		self._streaks[player] = nil
	end)
end

function KillProcessor:ResetStreak(player: Player)
	self._streaks[player] = nil
end

function KillProcessor:_advanceStreak(puncher: Player): (string?, number)
	local now = os.clock()
	local state = self._streaks[puncher]
	if not state then
		state = { count = 0, lastKillTime = 0 }
		self._streaks[puncher] = state
	end
	local delta = now - state.lastKillTime
	if state.count == 0 or delta > Constants.Streak.TripleWindow then
		state.count = 1
	else
		state.count += 1
	end
	state.lastKillTime = now
	local kind = streakKind(state.count, delta)
	return kind, state.count
end

function KillProcessor:_broadcast(eventType: string, payload: { [string]: any })
	local remote = Remotes.GetEventsRemote()
	if not remote then
		return
	end
	remote:FireAllClients({ type = eventType, payload = payload })
end

function KillProcessor:_broadcastToPlayer(player: Player, eventType: string, payload: { [string]: any })
	local remote = Remotes.GetEventsRemote()
	if not remote then
		return
	end
	remote:FireClient(player, { type = eventType, payload = payload })
end

function KillProcessor:HandleKill(puncher: Player, target: Player)
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	local rankService = services.RankService
	local analytics = services.AnalyticsService
	local arenaService = services.ArenaService

	if not playerData:IsLoaded(puncher) or not playerData:IsLoaded(target) then
		return
	end

	local puncherBrief = rankService:GetRankBrief(puncher)
	local targetBrief = rankService:GetRankBrief(target)

	local bonus = rankService:ComputeXPBonus(puncherBrief.tier, targetBrief.tier)
	local totalXP = math.max(0, Constants.XP.Base + bonus)

	playerData:AddKill(puncher)
	playerData:AddDeath(target)

	-- Registra kill + XP no state da arena do puncher pro summary da
	-- sessão atual (state.killsSinceEnter, state.xpSinceEnter). Sem isso,
	-- profile.TotalKills e profile.XP sobem mas o summary ao cair mostra
	-- 'kills: 0, +0 XP' sempre.
	if arenaService and type(arenaService.RegisterKill) == "function" then
		arenaService:RegisterKill(puncher, totalXP)
	end

	local newLevel, _, leveledUp = playerData:AddXP(puncher, totalXP)
	local previousLevelPuncher = newLevel - (leveledUp and 1 or 0)

	local puncherRankDelta = rankService:ApplyKillDelta(puncher)
	local targetRankDelta = rankService:ApplyDeathDelta(target)

	self:_broadcast(Constants.EventTypes.KillFeed, {
		puncher = { name = puncher.Name, userId = puncher.UserId, rank = puncherBrief },
		target = { name = target.Name, userId = target.UserId, rank = targetBrief },
	})

	self:_broadcastToPlayer(puncher, Constants.EventTypes.XPGain, {
		puncherUserId = puncher.UserId,
		targetUserId = target.UserId,
		amount = totalXP,
	})

	local streak, streakCount = self:_advanceStreak(puncher)
	if streak then
		self:_broadcast(Constants.EventTypes.Streak, {
			userId = puncher.UserId,
			name = puncher.Name,
			kind = streak,
			count = streakCount,
		})
	end

	if leveledUp then
		self:_broadcast(Constants.EventTypes.LevelUp, {
			userId = puncher.UserId,
			previousLevel = previousLevelPuncher,
			newLevel = newLevel,
		})
	end

	if puncherRankDelta and puncherRankDelta.promoted then
		self:_broadcast(Constants.EventTypes.RankUp, {
			userId = puncher.UserId,
			previousRank = { name = puncherRankDelta.previousName, tier = puncherRankDelta.previousTier },
			newRank = { name = puncherRankDelta.newName, tier = puncherRankDelta.newTier },
			promoted = true,
		})
	end

	if targetRankDelta and targetRankDelta.demoted then
		self:_broadcastToPlayer(target, Constants.EventTypes.RankUp, {
			userId = target.UserId,
			previousRank = { name = targetRankDelta.previousName, tier = targetRankDelta.previousTier },
			newRank = { name = targetRankDelta.newName, tier = targetRankDelta.newTier },
			promoted = false,
		})
	end

	analytics:Log(Constants.Analytics.Events.Kill, {
		puncherUserId = puncher.UserId,
		targetUserId = target.UserId,
		puncherTier = puncherBrief.tier,
		targetTier = targetBrief.tier,
		xpAwarded = totalXP,
		streak = streak,
	})

	if leveledUp then
		analytics:Log(Constants.Analytics.Events.LevelUp, {
			userId = puncher.UserId,
			newLevel = newLevel,
		})
	end

	if puncherRankDelta and puncherRankDelta.promoted then
		analytics:Log(Constants.Analytics.Events.RankUp, {
			userId = puncher.UserId,
			newRank = puncherRankDelta.newName,
		})
	end

	local rankingService = services.RankingService
	if rankingService then
		rankingService:SubmitForPlayer(puncher)
	end

	-- Puncher ganhou XP/rank — republica o state pra HUD refletir imediatamente.
	-- Sem isso, o HUD do puncher só atualizaria no próximo trigger de
	-- PublishState (dano, ReturnToLobby, etc.), fazendo parecer que XP
	-- parou de somar.
	if arenaService then
		arenaService:PublishState(puncher)
	end
end

return KillProcessor
