--!strict

-- ClassAccessoryService: aplica acessórios diegéticos por classe (luvas pro Boxer,
-- wraps pro Taekwon, tutu pra Ballerina) no Character. Server-side: Accessory
-- parented ao Character replica nativamente pra todos os clients (single source
-- of truth — diferente do Highlight outline, que é client-side per viewer).
--
-- Lifecycle:
--   PlayerAdded → bind CharacterAdded → applyAccessories(char, equipped class)
--   ShopService:EquipClass → calls Reapply(player) → remove old + add new
--
-- Resilience:
--   InsertService:LoadAsset wrap em pcall — IDs inválidos / catalog removido
--   degradam graciosamente (warn no console, char fica sem accessory).

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(sharedFolder:WaitForChild("Classes"))

type Services = { [string]: any }

-- Tag interna nas Accessory instances criadas por este service. Usado pra
-- localizar e remover na hora do Reapply (não mexer em accessories naturais
-- do avatar do user).
local ACCESSORY_TAG = "BrawlClassAccessory"

local ClassAccessoryService = {}
ClassAccessoryService._services = nil :: Services?
ClassAccessoryService._characterConns = {} :: { [Player]: RBXScriptConnection }

local function loadAccessoryAsset(assetId: number): Accessory?
	-- LoadAsset retorna Model contendo o Accessory. Wrap em pcall: ID inválido
	-- ou catalog removido throwa, queremos degradar gracioso.
	local ok, modelOrErr = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		warn(string.format("[ClassAccessoryService] LoadAsset failed for id=%d: %s", assetId, tostring(modelOrErr)))
		return nil
	end
	local model = modelOrErr :: Model
	local accessory = model:FindFirstChildWhichIsA("Accessory")
	if not accessory then
		warn(string.format("[ClassAccessoryService] Asset %d has no Accessory child; ignoring", assetId))
		model:Destroy()
		return nil
	end
	-- Re-parent o Accessory pra fora do Model wrapper antes de destruir o wrapper.
	accessory.Parent = nil
	model:Destroy()
	accessory:SetAttribute(ACCESSORY_TAG, true)
	return accessory
end

local function removeClassAccessories(character: Model)
	-- Remove só accessories taggeadas pelo service. Não toca em hat/hair/etc
	-- naturais do avatar do user.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child:GetAttribute(ACCESSORY_TAG) == true then
			child:Destroy()
		end
	end
end

local function applyClassAccessories(character: Model, classId: string)
	local classDef = Classes.GetClass(classId)
	if not classDef then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, assetId in ipairs(classDef.AccessoryAssetIds) do
		if assetId == 0 then
			continue
		end
		local accessory = loadAccessoryAsset(assetId)
		if accessory then
			-- Humanoid:AddAccessory faz o weld nas attachment points definidas
			-- pela accessory (HatAttachment, RightGripAttachment, etc.).
			humanoid:AddAccessory(accessory)
		end
	end
end

function ClassAccessoryService:Init(services: Services)
	self._services = services
end

function ClassAccessoryService:_resolveEquippedClass(player: Player): string
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	if playerData and playerData.GetEquippedClass then
		return playerData:GetEquippedClass(player)
	end
	return Classes.GetDefaultId()
end

function ClassAccessoryService:_onCharacterAdded(player: Player, character: Model)
	-- Espera HumanoidRootPart pra garantir que rig tá pronto pra weld.
	character:WaitForChild("HumanoidRootPart", 5)
	local classId = self:_resolveEquippedClass(player)
	-- Cleanup defensivo: se char foi recém-spawnado mas tem accessory tagueada
	-- de spawn anterior (não deveria, mas defesa em profundidade), remove.
	removeClassAccessories(character)
	applyClassAccessories(character, classId)
end

function ClassAccessoryService:_bindPlayer(player: Player)
	-- Disconnect old binding se já existe (player rejoin no mesmo server, raro
	-- mas possível com Players:LoadCharacter após erro).
	local existing = self._characterConns[player]
	if existing then
		existing:Disconnect()
	end
	if player.Character then
		task.spawn(function()
			self:_onCharacterAdded(player, player.Character :: Model)
		end)
	end
	self._characterConns[player] = player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(player, character)
	end)
end

function ClassAccessoryService:Reapply(player: Player)
	-- Chamado pelo ShopService após SetEquippedClass: remove accessories da classe
	-- antiga e aplica da nova. Sem respawn — player vê troca instantânea no lobby.
	local character = player.Character
	if not character then
		return
	end
	local classId = self:_resolveEquippedClass(player)
	removeClassAccessories(character)
	applyClassAccessories(character, classId)
end

function ClassAccessoryService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local conn = self._characterConns[player]
		if conn then
			conn:Disconnect()
			self._characterConns[player] = nil
		end
	end)
end

return ClassAccessoryService
