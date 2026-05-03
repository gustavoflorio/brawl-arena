--!strict

-- ClassAccessoryService: aplica acessórios diegéticos por classe (luvas pro Boxer,
-- wraps pro Taekwon, tutu pra Ballerina) no Character. Os prefabs são Accessory
-- instances criadas em Studio (vivem em Workspace.BrawlClassAccessories,
-- editáveis visualmente no editor) — service só clona e parenta.
--
-- Por que Workspace.Assets:
--   Convenção do projeto: TODOS os prefabs/assets do jogo vão em Workspace.Assets
--   (ver memory note do user). Workspace é o painel sempre aberto no Studio Explorer
--   onde o user vê tudo, e Assets agrupa pra não poluir o root do Workspace.
--   Custo: prefabs renderizam no mundo (anchored, longe da arena em Y=50).
--
-- Por que não InsertService:LoadAsset (catalog):
--   Roblox bloqueia LoadAsset de items de creators terceiros (trust policy)
--   + copyright (catalog items não têm licença pra reusar em outros experiences).
--
-- Lifecycle:
--   PlayerAdded → bind CharacterAdded → applyAccessories(char, equipped class)
--   ShopService:EquipClass → calls Reapply(player) → remove old + add new

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(sharedFolder:WaitForChild("Classes"))

local ASSETS_FOLDER_NAME = "Assets"
local PREFABS_FOLDER_NAME = "BrawlClassAccessories"

type Services = { [string]: any }

-- Tag interna nas Accessory instances criadas por este service. Usado pra
-- localizar e remover na hora do Reapply (não mexer em accessories naturais
-- do avatar do user).
local ACCESSORY_TAG = "BrawlClassAccessory"

local ClassAccessoryService = {}
ClassAccessoryService._services = nil :: Services?
ClassAccessoryService._characterConns = {} :: { [Player]: RBXScriptConnection }
ClassAccessoryService._prefabsFolder = nil :: Folder?

local function getPrefabsFolder(): Folder?
	-- Lazy lookup: se prefabs não tão lá ainda no Init, espera pacientemente.
	-- Em produção, prefabs vivem no place file (Studio editor save), não no Rojo.
	-- Convention: Workspace.Assets é a folder raiz pra TODOS os prefabs do jogo.
	local assets = Workspace:FindFirstChild(ASSETS_FOLDER_NAME)
	if not assets then
		return nil
	end
	return assets:FindFirstChild(PREFABS_FOLDER_NAME) :: Folder?
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

local function applyClassAccessories(character: Model, classId: string, prefabsFolder: Folder)
	local classFolder = prefabsFolder:FindFirstChild(classId)
	if not classFolder then
		-- Classe sem prefabs cadastrados — silently skip (válido, classes futuras
		-- podem não ter accessories no asset folder ainda).
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, prefab in ipairs(classFolder:GetChildren()) do
		if prefab:IsA("Accessory") then
			local clone = prefab:Clone()
			clone:SetAttribute(ACCESSORY_TAG, true)
			-- Prefabs em ReplicatedStorage podem estar Anchored (pra editar parados
			-- no Studio). No Character, weld só funciona com BasePart unanchored.
			for _, p in ipairs(clone:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = false
				end
			end
			humanoid:AddAccessory(clone)
		end
	end
end

function ClassAccessoryService:Init(services: Services)
	self._services = services
	self._prefabsFolder = getPrefabsFolder()
	if not self._prefabsFolder then
		warn(string.format(
			"[ClassAccessoryService] %s folder not found in Workspace.%s. " ..
			"Accessories won't be applied. Verifica que os prefabs foram salvos no place.",
			PREFABS_FOLDER_NAME, ASSETS_FOLDER_NAME
		))
	end
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
	local prefabsFolder = self._prefabsFolder
	if not prefabsFolder then
		return
	end
	-- Espera HumanoidRootPart pra garantir que rig tá pronto pra weld.
	character:WaitForChild("HumanoidRootPart", 5)
	local classId = self:_resolveEquippedClass(player)
	-- Cleanup defensivo: se char foi recém-spawnado mas tem accessory tagueada
	-- de spawn anterior (não deveria, mas defesa em profundidade), remove.
	removeClassAccessories(character)
	applyClassAccessories(character, classId, prefabsFolder)
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
	local prefabsFolder = self._prefabsFolder
	if not prefabsFolder then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local classId = self:_resolveEquippedClass(player)
	removeClassAccessories(character)
	applyClassAccessories(character, classId, prefabsFolder)
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
