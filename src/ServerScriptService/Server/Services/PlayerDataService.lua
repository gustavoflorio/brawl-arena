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

local DEFAULT_CLASS_ID = "Boxer"

local PROFILE_TEMPLATE: Profile = {
	XP = 0,
	Level = 1,
	Rank = "Unranked",
	RankPoints = 0,
	HighestRank = "Unranked",
	SeriesKind = "none",
	SeriesProgress = 0,
	RankSchemaVersion = 0, -- migration bumps to 2 on load; novos profiles também passam por migração (no-op)
	TotalKills = 0,
	TotalDeaths = 0,
	DonationCount = 0,
	LastLoginTimestamp = 0,
	-- Classes/economy (ClassSchema v1)
	Currency = 0,
	UnlockedClasses = { [DEFAULT_CLASS_ID] = true },
	EquippedClass = DEFAULT_CLASS_ID,
	ClassSchemaVersion = 0, -- migration bumps to 1 on load
}

local CURRENT_RANK_SCHEMA = 2
local CURRENT_CLASS_SCHEMA = 1

local function migrateRankSchema(data)
	if (data.RankSchemaVersion or 0) >= CURRENT_RANK_SCHEMA then
		return
	end
	-- v0/v1 → v2: thresholds antigos eram variáveis (Bronze I=100, Bronze II=250, ..., Champion=10000).
	-- Novo schema usa 100 FP por tier uniforme + séries de promo/demote, então RankPoints antigos
	-- não traduzem. Reset everyone fair start.
	data.RankPoints = 0
	data.Rank = "Unranked"
	data.HighestRank = "Unranked"
	data.SeriesKind = "none"
	data.SeriesProgress = 0
	data.RankSchemaVersion = CURRENT_RANK_SCHEMA
end

local function migrateClassSchema(data)
	-- v0 → v1: garante currency, unlocked set com Boxer, e classe equipada válida.
	-- Profiles legados (pré-classes) caem aqui no primeiro load. Reconcile já
	-- preencheu defaults da template; esta migration corrige inconsistências.
	if (data.ClassSchemaVersion or 0) >= CURRENT_CLASS_SCHEMA then
		return
	end
	if typeof(data.Currency) ~= "number" then
		data.Currency = 0
	end
	if typeof(data.UnlockedClasses) ~= "table" then
		data.UnlockedClasses = {}
	end
	-- Boxer sempre desbloqueada — invariante do design (default free).
	data.UnlockedClasses[DEFAULT_CLASS_ID] = true
	if typeof(data.EquippedClass) ~= "string" or not data.UnlockedClasses[data.EquippedClass] then
		data.EquippedClass = DEFAULT_CLASS_ID
	end
	data.ClassSchemaVersion = CURRENT_CLASS_SCHEMA
end

local PlayerDataService = {}
PlayerDataService._services = nil :: Services?
PlayerDataService._store = nil :: any
PlayerDataService._profiles = {} :: { [Player]: any }
PlayerDataService._loadedSignals = {} :: { [Player]: { [(any) -> ()]: boolean } }

local function xpForLevelUp(level: number): number
	local exponent = Constants.XP.LevelCurveExponent + level * Constants.XP.LevelCurveExponentGrowth
	return math.floor(Constants.XP.LevelCurveMultiplier * (level ^ exponent))
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
	migrateRankSchema(profile.Data)
	migrateClassSchema(profile.Data)
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

	if leveledUp and data.Level ~= previousLevel then
		self:SyncOverheadAttributes(player)
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

function PlayerDataService:SetSeriesState(player: Player, kind: string, progress: number)
	local data = self:GetProfile(player)
	if not data then
		return
	end
	data.SeriesKind = kind
	data.SeriesProgress = math.clamp(progress, 0, 99)
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

function PlayerDataService:SyncOverheadAttributes(player: Player)
	-- Propaga Level e Rank como attributes no character. Attributes replicam
	-- automaticamente pra todos os clients, então o HeadBadgeController vê
	-- o dado de qualquer player sem round-trip via remote.
	local character = player.Character
	local data = self:GetProfile(player)
	if not character or not data then
		return
	end
	character:SetAttribute(Constants.CharacterAttributes.Level, data.Level)

	local services = self._services
	local rankService = services and services.RankService
	if rankService and type(rankService.GetRankBrief) == "function" then
		local brief = rankService:GetRankBrief(player)
		character:SetAttribute(Constants.CharacterAttributes.RankName, brief.name)
		character:SetAttribute(Constants.CharacterAttributes.RankTier, brief.tier)
	else
		character:SetAttribute(Constants.CharacterAttributes.RankName, data.Rank)
		character:SetAttribute(Constants.CharacterAttributes.RankTier, 1)
	end
end

function PlayerDataService:XPForNextLevel(player: Player): number
	local data = self:GetProfile(player)
	if not data then
		return 0
	end
	return xpForLevelUp(data.Level)
end

-- ===== Classes / Currency =====

function PlayerDataService:GetCurrency(player: Player): number
	local data = self:GetProfile(player)
	if not data then
		return 0
	end
	return data.Currency
end

function PlayerDataService:AddCurrency(player: Player, amount: number): number
	-- Soma signed. Negativo é aceito (compras), mas saldo nunca fica < 0.
	local data = self:GetProfile(player)
	if not data then
		return 0
	end
	data.Currency = math.max(0, data.Currency + amount)
	return data.Currency
end

function PlayerDataService:GetEquippedClass(player: Player): string
	local data = self:GetProfile(player)
	if not data then
		return DEFAULT_CLASS_ID
	end
	return data.EquippedClass
end

function PlayerDataService:IsClassUnlocked(player: Player, classId: string): boolean
	local data = self:GetProfile(player)
	if not data then
		return false
	end
	return data.UnlockedClasses[classId] == true
end

function PlayerDataService:UnlockClass(player: Player, classId: string): boolean
	local data = self:GetProfile(player)
	if not data then
		return false
	end
	if data.UnlockedClasses[classId] then
		return false
	end
	data.UnlockedClasses[classId] = true
	return true
end

function PlayerDataService:SetEquippedClass(player: Player, classId: string): boolean
	-- Caller é responsável por validar que classId existe no Classes registry.
	-- Aqui só checamos que o player desbloqueou — defesa em profundidade.
	local data = self:GetProfile(player)
	if not data then
		return false
	end
	if not data.UnlockedClasses[classId] then
		return false
	end
	data.EquippedClass = classId
	return true
end

function PlayerDataService:GetUnlockedClasses(player: Player): { [string]: boolean }
	local data = self:GetProfile(player)
	if not data then
		return {}
	end
	-- Retorna cópia rasa pra evitar mutação externa do profile.
	local copy: { [string]: boolean } = {}
	for k, v in pairs(data.UnlockedClasses) do
		copy[k] = v
	end
	return copy
end

return PlayerDataService
