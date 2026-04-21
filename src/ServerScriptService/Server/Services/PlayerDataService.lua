--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Types = require(sharedFolder:WaitForChild("Types"))

local modulesFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Modules")
local ProfileService = require(modulesFolder:WaitForChild("ProfileService"))

type Services = { [string]: any }
type Profile = Types.Profile

local PROFILE_TEMPLATE: Profile = {
	XP = 0,
	Level = 1,
	Rank = "Unranked",
	RankPoints = 0,
	HighestRank = "Unranked",
	TotalKills = 0,
	TotalDeaths = 0,
	TotalTimeAlive = 0,
	DonationCount = 0,
	LastLoginTimestamp = 0,
}

local PlayerDataService = {}
PlayerDataService._services = nil :: Services?
PlayerDataService._store = nil :: any
PlayerDataService._profiles = {} :: { [Player]: any }
PlayerDataService._loadedSignals = {} :: { [Player]: { [(any) -> ()]: boolean } }

local function xpForLevelUp(level: number): number
	return math.floor(Constants.XP.LevelCurveMultiplier * (level ^ Constants.XP.LevelCurveExponent))
end

function PlayerDataService:Init(services: Services)
	self._services = services

	local storeName = Constants.DataStore.ProfileStoreName
	if RunService:IsStudio() then
		storeName = storeName .. "_Studio"
	end
	self._store = ProfileService.GetProfileStore(storeName, PROFILE_TEMPLATE)
end

function PlayerDataService:_notifyLoaded(player: Player)
	local listeners = self._loadedSignals[player]
	if not listeners then
		return
	end
	self._loadedSignals[player] = nil
	for callback in pairs(listeners) do
		task.spawn(callback, player)
	end
end

function PlayerDataService:OnProfileLoaded(player: Player, callback: (Player) -> ())
	if self._profiles[player] then
		task.spawn(callback, player)
		return
	end
	local listeners = self._loadedSignals[player]
	if not listeners then
		listeners = {}
		self._loadedSignals[player] = listeners
	end
	listeners[callback] = true
end

function PlayerDataService:_loadProfile(player: Player)
	local profileKey = "Player_" .. player.UserId
	local profile = self._store:LoadProfileAsync(profileKey)

	if not profile then
		player:Kick("Não foi possível carregar seu perfil. Tente entrar novamente em alguns minutos.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile:ListenToRelease(function()
		self._profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Seu perfil foi liberado em outro servidor.")
		end
	end)

	if player.Parent ~= Players then
		profile:Release()
		return
	end

	profile.Data.LastLoginTimestamp = os.time()
	self._profiles[player] = profile
	self:_notifyLoaded(player)

	player:LoadCharacter()
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			self:_loadProfile(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local profile = self._profiles[player]
		if profile then
			profile:Release()
		end
		self._loadedSignals[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

function PlayerDataService:GetProfile(player: Player): Profile?
	local wrapper = self._profiles[player]
	if wrapper then
		return wrapper.Data
	end
	return nil
end

function PlayerDataService:IsLoaded(player: Player): boolean
	return self._profiles[player] ~= nil
end

function PlayerDataService:AddXP(player: Player, amount: number): (number, number, boolean)
	local data = self:GetProfile(player)
	if not data or amount <= 0 then
		return 0, 0, false
	end

	data.XP += amount
	local leveledUp = false
	local previousLevel = data.Level
	while data.XP >= xpForLevelUp(data.Level) do
		data.XP -= xpForLevelUp(data.Level)
		data.Level += 1
		leveledUp = true
	end

	return data.Level, data.XP, leveledUp and data.Level ~= previousLevel
end

function PlayerDataService:AddKill(player: Player)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.TotalKills += 1
end

function PlayerDataService:AddDeath(player: Player)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.TotalDeaths += 1
end

function PlayerDataService:AddTimeAlive(player: Player, seconds: number)
	local data = self:GetProfile(player)
	if not data or seconds <= 0 then
		return
	end
	data.TotalTimeAlive += seconds
end

function PlayerDataService:IncrementDonation(player: Player)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.DonationCount += 1
end

function PlayerDataService:SetRankPoints(player: Player, points: number)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.RankPoints = math.max(0, points)
end

function PlayerDataService:SetRankName(player: Player, rankName: string)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.Rank = rankName
	local highestIdx = -1
	local newIdx = -1
	for idx, tier in ipairs(Constants.Rank.Tiers) do
		if tier.name == data.HighestRank then
			highestIdx = idx
		end
		if tier.name == rankName then
			newIdx = idx
		end
	end
	if newIdx > highestIdx then
		data.HighestRank = rankName
	end
end

function PlayerDataService:XPForNextLevel(player: Player): number
	local data = self:GetProfile(player)
	if not data then
		return 0
	end
	return xpForLevelUp(data.Level)
end

return PlayerDataService
