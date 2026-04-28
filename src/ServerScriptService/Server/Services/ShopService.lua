--!strict

-- ShopService: handle de compra e equip de classes. Servidor é fonte única
-- de verdade — cliente nunca decide se a transação ocorreu, só dispara
-- request via BrawlShop RemoteFunction. ProfileService garante single-server
-- ownership do profile, então race condition cross-server é impossível.
-- Single-flight por player previne dupla cobrança em duplo-clique.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Classes = require(sharedFolder:WaitForChild("Classes"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Types = require(sharedFolder:WaitForChild("Types"))

type Services = { [string]: any }
type ClassCatalogEntry = Types.ClassCatalogEntry
type ShopCatalogPayload = Types.ShopCatalogPayload
type ShopBuyResult = Types.ShopBuyResult
type ShopEquipResult = Types.ShopEquipResult

local REASONS = Constants.Shop.BuyResultReasons
local ACTIONS = Constants.Shop.BuyActions

local ShopService = {}
ShopService._services = nil :: Services?
ShopService._inFlight = {} :: { [Player]: boolean }

function ShopService:Init(services: Services)
	self._services = services
end

local function failure(reason: string): ShopBuyResult
	return { success = false, reason = reason }
end

function ShopService:_isInLobby(player: Player): boolean
	local services = self._services :: Services
	local arena = services.ArenaService
	if not arena then
		-- Defesa: se ArenaService ainda não inicializou, presume lobby
		-- (player nem entrou em match ainda).
		return true
	end
	return arena:GetState(player) == Constants.PlayerState.InLobby
end

function ShopService:GetCatalogFor(player: Player): ShopCatalogPayload
	local services = self._services :: Services
	local playerData = services.PlayerDataService

	local balance = 0
	local equippedId = Classes.GetDefaultId()
	local unlocked: { [string]: boolean } = {}

	if playerData and playerData:IsLoaded(player) then
		balance = playerData:GetCurrency(player)
		equippedId = playerData:GetEquippedClass(player)
		unlocked = playerData:GetUnlockedClasses(player)
	else
		unlocked[Classes.GetDefaultId()] = true
	end

	local entries: { ClassCatalogEntry } = {}
	for _, def in ipairs(Classes.GetCatalog()) do
		table.insert(entries, {
			id = def.Id,
			displayName = def.DisplayName,
			description = def.Description,
			iconAssetId = def.IconAssetId,
			price = def.Price,
			owned = unlocked[def.Id] == true,
			equipped = def.Id == equippedId,
		})
	end

	return {
		balance = balance,
		classes = entries,
	}
end

function ShopService:BuyClass(player: Player, classId: string): ShopBuyResult
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	local analytics = services.AnalyticsService

	if not playerData or not playerData:IsLoaded(player) then
		return failure(REASONS.UnknownClass)
	end

	-- Single-flight lock por player (anti double-click). Liberado via defer
	-- antes de qualquer return.
	if self._inFlight[player] then
		return failure(REASONS.InTransaction)
	end
	self._inFlight[player] = true
	local function release()
		self._inFlight[player] = nil
	end

	if not self:_isInLobby(player) then
		release()
		return failure(REASONS.NotInLobby)
	end

	local classDef = Classes.GetClass(classId)
	if not classDef then
		release()
		return failure(REASONS.UnknownClass)
	end

	if playerData:IsClassUnlocked(player, classId) then
		release()
		return failure(REASONS.AlreadyOwned)
	end

	local balance = playerData:GetCurrency(player)
	if balance < classDef.Price then
		release()
		return failure(REASONS.InsufficientFunds)
	end

	-- Transação. AddCurrency com signed negativo deduz; UnlockClass adiciona
	-- ao set. Ambos mutam profile.Data direto (ProfileService persiste no
	-- release/autosave). Ordem: primeiro deduz, depois unlock — se algo der
	-- errado entre as duas linhas (não deveria, são ops síncronas), o player
	-- perde a moeda mas não recebe a classe; preferimos isso a o reverso.
	local newBalance = playerData:AddCurrency(player, -classDef.Price)
	playerData:UnlockClass(player, classId)

	-- Push novo saldo via PublishState (HUD lê snapshot.currency). Mesmo
	-- padrão do CoinSpawnService — sem isto a coin badge fica stale até o
	-- próximo state push (kill/death/enter arena).
	local arenaService = services.ArenaService
	if arenaService and arenaService.PublishState then
		arenaService:PublishState(player)
	end

	if analytics and analytics.Log then
		analytics:Log(Constants.Analytics.Events.ClassPurchased, {
			userId = player.UserId,
			classId = classId,
			price = classDef.Price,
			newBalance = newBalance,
		})
	end

	release()
	return {
		success = true,
		newBalance = newBalance,
	}
end

function ShopService:EquipClass(player: Player, classId: string): ShopEquipResult
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	local analytics = services.AnalyticsService

	if not playerData or not playerData:IsLoaded(player) then
		return { success = false, reason = REASONS.UnknownClass }
	end

	if not self:_isInLobby(player) then
		return { success = false, reason = REASONS.NotInLobby }
	end

	if not Classes.Has(classId) then
		return { success = false, reason = REASONS.UnknownClass }
	end

	if not playerData:IsClassUnlocked(player, classId) then
		return { success = false, reason = REASONS.AlreadyOwned }
	end

	local ok = playerData:SetEquippedClass(player, classId)
	if not ok then
		return { success = false, reason = REASONS.UnknownClass }
	end

	if analytics and analytics.Log then
		analytics:Log(Constants.Analytics.Events.ClassEquipped, {
			userId = player.UserId,
			classId = classId,
		})
	end

	return { success = true }
end

function ShopService:_handleInvoke(player: Player, request: any): any
	-- request: { action: string, classId: string? }
	if typeof(request) ~= "table" then
		return failure(REASONS.UnknownClass)
	end
	local action = request.action
	if action == ACTIONS.GetCatalog then
		return self:GetCatalogFor(player)
	elseif action == ACTIONS.Buy then
		local classId = request.classId
		if typeof(classId) ~= "string" then
			return failure(REASONS.UnknownClass)
		end
		return self:BuyClass(player, classId)
	elseif action == ACTIONS.Equip then
		local classId = request.classId
		if typeof(classId) ~= "string" then
			return failure(REASONS.UnknownClass)
		end
		return self:EquipClass(player, classId)
	end
	return failure(REASONS.UnknownClass)
end

function ShopService:Start()
	local remote = Remotes.GetShopRemote()
	assert(remote, "BrawlShop RemoteFunction not found — Main.server.lua should have created it")

	remote.OnServerInvoke = function(player: Player, request: any): any
		local ok, result = pcall(function()
			return self:_handleInvoke(player, request)
		end)
		if not ok then
			warn("[ShopService] Invoke failed:", result)
			return failure(REASONS.UnknownClass)
		end
		return result
	end

	-- Limpa lock quando player sai (defesa contra leak de memory + estado
	-- preso caso transação fique pendurada por algum motivo bizarro).
	Players.PlayerRemoving:Connect(function(player)
		self._inFlight[player] = nil
	end)
end

return ShopService
