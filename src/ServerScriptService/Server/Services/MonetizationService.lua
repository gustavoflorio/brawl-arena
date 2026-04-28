--!strict

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

type Services = { [string]: any }

local MonetizationService = {}
MonetizationService._services = nil :: Services?
MonetizationService._purchaseStore = nil :: DataStore?

function MonetizationService:Init(services: Services)
	self._services = services
end

function MonetizationService:_bindKioskPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt.Triggered:Connect(function(player)
		self:PromptDonate(player)
	end)
end

function MonetizationService:Start()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Constants.DataStore.PurchaseDataStoreName)
	end)
	if ok then
		self._purchaseStore = store
	else
		warn("[MonetizationService] Não foi possível obter DataStore de purchases.")
	end

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end

	local kioskTag = Constants.Tags.DonateKiosk
	for _, prompt in ipairs(CollectionService:GetTagged(kioskTag)) do
		self:_bindKioskPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal(kioskTag):Connect(function(inst)
		self:_bindKioskPrompt(inst)
	end)
end

function MonetizationService:PromptDonate(player: Player)
	if Constants.Donate.ProductId <= 0 then
		warn("[MonetizationService] ProductId não configurado. Defina Constants.Donate.ProductId com o id do DevProduct.")
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, Constants.Donate.ProductId)
	end)
	if not ok then
		warn("[MonetizationService] PromptProductPurchase falhou:", err)
	end
end

function MonetizationService:_processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	local analytics = services.AnalyticsService

	print(string.format(
		"[MonetizationService] ProcessReceipt fired: productId=%s playerId=%s purchaseId=%s",
		tostring(receiptInfo.ProductId),
		tostring(receiptInfo.PlayerId),
		tostring(receiptInfo.PurchaseId)
	))

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		warn("[MonetizationService] player not found for receipt — NotProcessedYet")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not self._purchaseStore then
		warn("[MonetizationService] _purchaseStore is nil — NotProcessedYet")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = "purchase_" .. receiptInfo.PurchaseId

	local alreadyGranted
	local okGet, errGet = pcall(function()
		alreadyGranted = self._purchaseStore:GetAsync(key)
	end)
	if not okGet then
		warn("[MonetizationService] GetAsync falhou:", errGet)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if alreadyGranted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if receiptInfo.ProductId == Constants.Donate.ProductId then
		if not playerData:IsLoaded(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		playerData:IncrementDonation(player)
		if analytics then
			analytics:Log(Constants.Analytics.Events.Donate, {
				userId = player.UserId,
				productId = receiptInfo.ProductId,
				purchaseId = receiptInfo.PurchaseId,
			})
		end
	elseif receiptInfo.ProductId == Constants.Shop.CoinPack.ProductId then
		if not playerData:IsLoaded(player) then
			warn("[MonetizationService] CoinPack: profile not loaded — NotProcessedYet")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local newBalance = playerData:AddCurrency(player, Constants.Shop.CoinPack.Amount)
		print(string.format(
			"[MonetizationService] CoinPack credited: +%d → newBalance=%d",
			Constants.Shop.CoinPack.Amount,
			newBalance
		))
		-- Push novo saldo via PublishState (HUD lê snapshot.currency). Mesmo
		-- padrão do CoinSpawnService — sem isto a coin badge fica stale até o
		-- próximo state push (kill/death/enter arena).
		local arenaService = services.ArenaService
		if arenaService and arenaService.PublishState then
			arenaService:PublishState(player)
		end
		if analytics then
			analytics:Log(Constants.Analytics.Events.CoinPackPurchased, {
				userId = player.UserId,
				productId = receiptInfo.ProductId,
				purchaseId = receiptInfo.PurchaseId,
				amount = Constants.Shop.CoinPack.Amount,
				newBalance = newBalance,
			})
		end
	else
		warn("[MonetizationService] ProductId desconhecido:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local okSet, errSet = pcall(function()
		self._purchaseStore:SetAsync(key, {
			userId = player.UserId,
			productId = receiptInfo.ProductId,
			grantedAt = os.time(),
		})
	end)
	if not okSet then
		warn("[MonetizationService] SetAsync falhou:", errSet)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
