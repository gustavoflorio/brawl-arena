--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

type Services = { [string]: any }

type PlayerState = {
	state: string,
	damagePercent: number,
	lastPadTouch: number,
	arenaEnterTime: number,
	killsSinceEnter: number,
	xpSinceEnter: number,
	lastLevelSnapshot: number,
	lastRankPointsSnapshot: number,
}

local ArenaService = {}
ArenaService._services = nil :: Services?
ArenaService._playerStates = {} :: { [Player]: PlayerState }
ArenaService._padConnection = nil :: RBXScriptConnection?
ArenaService._heartbeatConnection = nil :: RBXScriptConnection?
ArenaService._broadcastConnection = nil :: RBXScriptConnection?
ArenaService._broadcastAccumulator = 0
ArenaService._heartbeatAccumulator = 0
ArenaService._lastBroadcastDamage = {} :: { [Player]: number }

local TOUCH_DEBOUNCE = 0.5
local BROADCAST_INTERVAL = 0.1 -- 10 Hz, fire on ≥1% damage change
local HEARTBEAT_INTERVAL = 0.5 -- heartbeat sync for late joiners

local function resolveLobbyFolder(): Instance?
	return Workspace:FindFirstChild("Lobby")
end

local function resolveArenaFolder(): Instance?
	return Workspace:FindFirstChild("Arena")
end

local function getSpawnPad(): BasePart?
	local folder = resolveLobbyFolder()
	if not folder then
		return nil
	end
	local pad = folder:FindFirstChild("SpawnPad")
	if pad and pad:IsA("BasePart") then
		return pad
	end
	return nil
end

local function getLobbySpawn(): BasePart?
	local folder = resolveLobbyFolder()
	if not folder then
		return nil
	end
	local spawnPart = folder:FindFirstChild("LobbySpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end
	return nil
end

local function getArenaSpawn(): BasePart?
	local folder = resolveArenaFolder()
	if not folder then
		return nil
	end
	local spawnPart = folder:FindFirstChild("ArenaSpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end
	return nil
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function ArenaService:_ensureState(player: Player): PlayerState
	local existing = self._playerStates[player]
	if existing then
		return existing
	end
	local newState: PlayerState = {
		state = Constants.PlayerState.InLobby,
		damagePercent = 0,
		lastPadTouch = 0,
		arenaEnterTime = 0,
		killsSinceEnter = 0,
		xpSinceEnter = 0,
		lastLevelSnapshot = 1,
		lastRankPointsSnapshot = 0,
	}
	self._playerStates[player] = newState
	return newState
end

function ArenaService:GetState(player: Player): string
	local state = self:_ensureState(player)
	return state.state
end

function ArenaService:GetDamage(player: Player): number
	local state = self:_ensureState(player)
	return state.damagePercent
end

function ArenaService:_syncDamageAttribute(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local state = self:_ensureState(player)
	character:SetAttribute(Constants.CharacterAttributes.DamagePercent, math.floor(state.damagePercent))
end

function ArenaService:AddDamage(player: Player, amount: number)
	local state = self:_ensureState(player)
	state.damagePercent = state.damagePercent + amount
	self:_syncDamageAttribute(player)
end

function ArenaService:ResetDamage(player: Player)
	local state = self:_ensureState(player)
	state.damagePercent = 0
	self:_syncDamageAttribute(player)
end

function ArenaService:RegisterKill(player: Player, xpGained: number)
	local state = self:_ensureState(player)
	state.killsSinceEnter += 1
	state.xpSinceEnter += xpGained
end

function ArenaService:PublishState(player: Player, summary: { [string]: any }?)
	local remote = Remotes.GetStateRemote()
	if not remote then
		return
	end
	local state = self:_ensureState(player)
	local services = self._services :: Services?
	local playerData = services and services.PlayerDataService
	local rankService = services and services.RankService

	local profile = playerData and playerData:GetProfile(player)
	local rank = if rankService and profile then rankService:GetRankBrief(player) else nil
	local xpForNext = if playerData and profile then playerData:XPForNextLevel(player) else 0

	local snapshot: { [string]: any } = {
		state = state.state,
		damagePercent = state.damagePercent,
	}
	if profile then
		snapshot.level = profile.Level
		snapshot.xp = profile.XP
		snapshot.xpForNextLevel = xpForNext
		snapshot.currency = profile.Currency
		-- Stats pro painel de Stats (StatsPanelController): player-owned scalars
		-- que não estão expostos nos atributos de character. Mantemos aqui porque
		-- o PublishState já dispara em todos os momentos relevantes (kill, death,
		-- level up, enter/leave arena), então o painel sempre tem dado fresco.
		snapshot.stats = {
			kills = profile.TotalKills,
			deaths = profile.TotalDeaths,
			rankPoints = profile.RankPoints,
			highestRank = profile.HighestRank,
			seriesKind = profile.SeriesKind,
			seriesProgress = profile.SeriesProgress,
		}
	end
	if rank then
		snapshot.rank = rank
	end
	if summary then
		snapshot.summary = summary
	end
	remote:FireClient(player, snapshot)
end

function ArenaService:TeleportToArena(player: Player)
	local spawnPart = getArenaSpawn()
	local root = getCharacterRoot(player)
	if not spawnPart or not root then
		return
	end
	root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	root.AssemblyLinearVelocity = Vector3.zero

	local character = player.Character
	if character then
		local now = os.clock()
		character:SetAttribute(Constants.CharacterAttributes.InvincibleUntil, now + Constants.Arena.InvincibilityDuration)
		character:SetAttribute(Constants.CharacterAttributes.LastHitterId, 0)
		character:SetAttribute(Constants.CharacterAttributes.LastHitTime, 0)
		character:SetAttribute(Constants.CharacterAttributes.DamagePercent, 0)
		character:SetAttribute(Constants.CharacterAttributes.ArenaActive, true)
	end

	local state = self:_ensureState(player)
	state.state = Constants.PlayerState.InArena
	state.damagePercent = 0
	state.arenaEnterTime = os.clock()
	state.killsSinceEnter = 0
	state.xpSinceEnter = 0

	local services = self._services :: Services?
	if services then
		local profile = services.PlayerDataService and services.PlayerDataService:GetProfile(player)
		state.lastLevelSnapshot = profile and profile.Level or 1
		state.lastRankPointsSnapshot = profile and profile.RankPoints or 0
		if services.AnalyticsService then
			services.AnalyticsService:Log(Constants.Analytics.Events.EnterArena, {
				userId = player.UserId,
			})
		end
	end

	self:PublishState(player)
	-- Immediate arena broadcast so new entrant sees populated panel on frame 1
	self:_broadcastArenaState(true)
end

function ArenaService:_resolveKillAttribution(target: Player): Player?
	local character = target.Character
	if not character then
		return nil
	end
	local lastHitterId = character:GetAttribute(Constants.CharacterAttributes.LastHitterId)
	local lastHitTime = character:GetAttribute(Constants.CharacterAttributes.LastHitTime)
	if typeof(lastHitterId) ~= "number" or lastHitterId <= 0 then
		return nil
	end
	if typeof(lastHitTime) ~= "number" or lastHitTime <= 0 then
		return nil
	end
	if os.clock() - lastHitTime > Constants.Arena.KillAttributionWindow then
		return nil
	end
	if lastHitterId == target.UserId then
		return nil
	end
	local puncher = Players:GetPlayerByUserId(lastHitterId)
	return puncher
end

function ArenaService:ReturnToLobby(player: Player, reason: string?)
	local services = self._services :: Services?
	local state = self:_ensureState(player)
	local wasInArena = state.state == Constants.PlayerState.InArena
	local arenaDuration = if state.arenaEnterTime > 0 then os.clock() - state.arenaEnterTime else 0

	local killer: Player? = nil
	if wasInArena and reason == "OutOfBounds" then
		killer = self:_resolveKillAttribution(player)
	end

	if wasInArena and services and services.RankingService then
		services.RankingService:SubmitForPlayer(player)
	end

	if killer and services and services.KillProcessor then
		services.KillProcessor:HandleKill(killer, player)
	end

	if services and services.KillProcessor then
		services.KillProcessor:ResetStreak(player)
	end

	local spawnPart = getLobbySpawn()
	local root = getCharacterRoot(player)
	if spawnPart and root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local character = player.Character
	if character then
		character:SetAttribute(Constants.CharacterAttributes.LastHitterId, 0)
		character:SetAttribute(Constants.CharacterAttributes.LastHitTime, 0)
		character:SetAttribute(Constants.CharacterAttributes.InvincibleUntil, 0)
		character:SetAttribute(Constants.CharacterAttributes.DamagePercent, 0)
		character:SetAttribute(Constants.CharacterAttributes.ArenaActive, false)
	end

	state.state = Constants.PlayerState.InLobby
	state.damagePercent = 0
	state.lastPadTouch = os.clock()

	if wasInArena and reason == "OutOfBounds" then
		if character then
			local current = character:GetAttribute(Constants.CharacterAttributes.EliminationSeq)
			local nextSeq = (typeof(current) == "number" and current or 0) + 1
			character:SetAttribute(Constants.CharacterAttributes.EliminationSeq, nextSeq)
		end
		if services and services.AnalyticsService then
			services.AnalyticsService:Log(Constants.Analytics.Events.ReturnToLobby, {
				userId = player.UserId,
				reason = reason,
				kills = state.killsSinceEnter,
				timeAlive = arenaDuration,
				xpGained = state.xpSinceEnter,
			})
		end
	end

	local profile = services and services.PlayerDataService and services.PlayerDataService:GetProfile(player)
	local rankDelta = profile and (profile.RankPoints - state.lastRankPointsSnapshot) or 0
	local summary: { [string]: any } = {
		kills = state.killsSinceEnter,
		timeAliveSeconds = math.floor(arenaDuration),
		xpGained = state.xpSinceEnter,
		leveledUp = profile and profile.Level > state.lastLevelSnapshot or false,
		newLevel = profile and profile.Level or nil,
		rankDelta = rankDelta,
	}

	self:PublishState(player, summary)
	-- Force arena broadcast so remaining players see the elimination immediately (trigger KO shatter)
	self:_broadcastArenaState(true)
end

function ArenaService:_handlePadTouch(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local services = self._services :: Services?
	if services and services.PlayerDataService and not services.PlayerDataService:IsLoaded(player) then
		return
	end

	local state = self:_ensureState(player)
	local now = os.clock()
	if now - state.lastPadTouch < TOUCH_DEBOUNCE then
		return
	end
	state.lastPadTouch = now
	if state.state == Constants.PlayerState.InArena then
		return
	end
	self:TeleportToArena(player)
end

function ArenaService:_bindSpawnPad()
	local pad = getSpawnPad()
	if not pad then
		warn("[ArenaService] SpawnPad não encontrado em Workspace.Lobby. Loop de bind irá tentar quando existir.")
		return
	end
	if self._padConnection then
		self._padConnection:Disconnect()
	end
	self._padConnection = pad.Touched:Connect(function(hit)
		self:_handlePadTouch(hit)
	end)
end

function ArenaService:_collectArenaSnapshot(): { [string]: any }
	local services = self._services :: Services?
	local playerData = services and services.PlayerDataService
	local rankService = services and services.RankService
	local players = {}
	for player, state in pairs(self._playerStates) do
		if state.state == Constants.PlayerState.InArena and player.Parent then
			local profile = playerData and playerData:GetProfile(player)
			local rank = if rankService and profile then rankService:GetRankBrief(player) else nil
			if not rank then
				rank = { name = "Unranked", tier = 1 }
			end
			local series = nil
			if profile and profile.SeriesKind and profile.SeriesKind ~= "none" then
				series = {
					kind = profile.SeriesKind,
					progress = profile.SeriesProgress or 0,
				}
			end
			table.insert(players, {
				userId = player.UserId,
				displayName = player.DisplayName,
				damagePercent = state.damagePercent,
				level = profile and profile.Level or 1,
				rank = rank,
				series = series,
			})
		end
	end
	return { players = players }
end

function ArenaService:_hasSignificantDamageChange(): boolean
	for player, state in pairs(self._playerStates) do
		if state.state == Constants.PlayerState.InArena then
			local last = self._lastBroadcastDamage[player] or -1
			if math.abs(state.damagePercent - last) >= 1 then
				return true
			end
		end
	end
	return false
end

function ArenaService:_broadcastArenaState(force: boolean?)
	local remote = Remotes.GetArenaRemote()
	if not remote then
		return
	end
	if not force and not self:_hasSignificantDamageChange() then
		return
	end
	local snapshot = self:_collectArenaSnapshot()
	-- Track last broadcast damage per player
	for player, state in pairs(self._playerStates) do
		if state.state == Constants.PlayerState.InArena then
			self._lastBroadcastDamage[player] = state.damagePercent
		end
	end
	-- Fire only to players currently in arena
	for player, state in pairs(self._playerStates) do
		if state.state == Constants.PlayerState.InArena and player.Parent then
			remote:FireClient(player, snapshot)
		end
	end
end

function ArenaService:_startBroadcastLoop()
	if self._broadcastConnection then
		self._broadcastConnection:Disconnect()
	end
	self._broadcastAccumulator = 0
	self._heartbeatAccumulator = 0
	self._broadcastConnection = RunService.Heartbeat:Connect(function(dt)
		self._broadcastAccumulator += dt
		self._heartbeatAccumulator += dt
		local didBroadcast = false
		if self._broadcastAccumulator >= BROADCAST_INTERVAL then
			self._broadcastAccumulator = 0
			self:_broadcastArenaState(false)
			didBroadcast = true
		end
		if self._heartbeatAccumulator >= HEARTBEAT_INTERVAL then
			self._heartbeatAccumulator = 0
			if not didBroadcast then
				self:_broadcastArenaState(true)
			end
		end
	end)
end

function ArenaService:_watchOutOfBounds()
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
	end
	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		for player, state in pairs(self._playerStates) do
			if state.state == Constants.PlayerState.InArena then
				local root = getCharacterRoot(player)
				if root and root.Position.Y < Constants.Arena.YKillThreshold then
					self:ReturnToLobby(player, "OutOfBounds")
				end
			end
		end
	end)
end

-- Passive XP drip removido: XP agora vem apenas de kills (via KillProcessor).

local function setCharacterCollisionGroup(character: Model, groupName: string)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

function ArenaService:_onPlayerAdded(player: Player)
	self:_ensureState(player)
	player.CharacterAdded:Connect(function(character)
		local state = self:_ensureState(player)
		state.state = Constants.PlayerState.InLobby
		state.damagePercent = 0
		state.lastPadTouch = os.clock()
		state.arenaEnterTime = 0
		state.killsSinceEnter = 0
		state.xpSinceEnter = 0

		character:SetAttribute(Constants.CharacterAttributes.LastHitterId, 0)
		character:SetAttribute(Constants.CharacterAttributes.LastHitTime, 0)
		character:SetAttribute(Constants.CharacterAttributes.InvincibleUntil, 0)

		-- Marca todos os BaseParts do character no grupo de colisão "Players"
		-- (default). Dodge vai trocar temporariamente pra "PlayersDodging".
		setCharacterCollisionGroup(character, Constants.CollisionGroups.Players)
		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				-- Novo part (ex: accessory): respeita o grupo atual.
				local isDodging = (descendant.CollisionGroup == Constants.CollisionGroups.PlayersDodging)
				if not isDodging then
					descendant.CollisionGroup = Constants.CollisionGroups.Players
				end
			end
		end)

		local services = self._services :: Services?
		if services and services.KillProcessor then
			services.KillProcessor:ResetStreak(player)
		end

		if services and services.PlayerDataService and type(services.PlayerDataService.SyncOverheadAttributes) == "function" then
			services.PlayerDataService:SyncOverheadAttributes(player)
		end

		task.defer(function()
			self:PublishState(player)
		end)
	end)
end

function ArenaService:Init(services: Services)
	self._services = services
end

function ArenaService:Start()
	local services = self._services :: Services?
	local playerData = services and services.PlayerDataService
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._playerStates[player] = nil
		self._lastBroadcastDamage[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
		if playerData and playerData:IsLoaded(player) then
			-- player entrou antes do loader; re-publish state
			task.defer(function()
				self:PublishState(player)
			end)
		end
	end

	if playerData then
		playerData.OnProfileLoaded = playerData.OnProfileLoaded or function() end
	end

	self:_bindSpawnPad()

	local lobby = resolveLobbyFolder()
	if lobby then
		lobby.ChildAdded:Connect(function(child)
			if child.Name == "SpawnPad" then
				task.wait(0.1)
				self:_bindSpawnPad()
			end
		end)
	end

	self:_watchOutOfBounds()
	self:_startBroadcastLoop()
end

return ArenaService
