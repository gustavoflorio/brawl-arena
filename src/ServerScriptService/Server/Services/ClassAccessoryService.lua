--!strict

-- ClassAccessoryService: aplica acessórios diegéticos por classe (luvas pro Boxer,
-- wraps pro Taekwon, tutu pra Ballerina) construídos proceduralmente de Parts
-- primitivos. Server-side: Accessory parented ao Character replica nativamente
-- pra todos os clients — single source of truth.
--
-- Arquitetura: shapes/cores definidas em ServerScriptService/Modules/
-- ClassAccessoryDefs.lua. Service só consome a tabela e instancia. Sem
-- InsertService:LoadAsset (issues de copyright + trust policy do Roblox com
-- assets de creators terceiros).
--
-- Lifecycle:
--   PlayerAdded → bind CharacterAdded → applyAccessories(char, equipped class)
--   ShopService:EquipClass → calls Reapply(player) → remove old + add new

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(sharedFolder:WaitForChild("Classes"))

local modulesFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Modules")
local ClassAccessoryDefs = require(modulesFolder:WaitForChild("ClassAccessoryDefs"))

type Services = { [string]: any }

-- Tag interna nas Accessory instances criadas por este service. Usado pra
-- localizar e remover na hora do Reapply (não mexer em accessories naturais
-- do avatar do user).
local ACCESSORY_TAG = "BrawlClassAccessory"

local ClassAccessoryService = {}
ClassAccessoryService._services = nil :: Services?
ClassAccessoryService._characterConns = {} :: { [Player]: RBXScriptConnection }

local function buildPart(partDef: any, isHandle: boolean): BasePart
	local part = Instance.new("Part")
	part.Shape = partDef.shape
	part.Size = partDef.size
	part.Color = partDef.color
	part.Material = partDef.material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Name = if isHandle then "Handle" else "AccessoryPart"
	return part
end

local function buildAccessory(def: any): Accessory
	-- Primeira part da def é o "Handle" (pivot welded ao char via Attachment).
	-- Restantes são parts decorativas welded ao Handle.
	local accessory = Instance.new("Accessory")
	accessory.Name = def.name
	accessory:SetAttribute(ACCESSORY_TAG, true)

	local handlePartDef = def.parts[1]
	local handle = buildPart(handlePartDef, true)
	handle.Parent = accessory

	-- Attachment no Handle com nome casado ao attachment do char rig
	-- (Roblox auto-weld por nome quando Humanoid:AddAccessory é chamado).
	local attachment = Instance.new("Attachment")
	attachment.Name = def.attachmentName
	-- offset do handle = identity (Handle's Attachment.CFrame é o offset que
	-- o weld vai aplicar relativo ao body part attachment).
	attachment.CFrame = handlePartDef.offset
	attachment.Parent = handle

	-- Decorative parts: welded ao Handle. Cada um tem offset relativo ao
	-- attachment do char, que internamente é Handle.position * weld * partOffset.
	-- Pra simplificar, transformamos: partOffset relativo ao attachment é
	-- handle.CFrame * (handlePartDef.offset)^-1 * partDef.offset. Mas como
	-- o Handle vai ser welded com attachment.CFrame igual ao handlePartDef.offset,
	-- e a Handle.Position começa origin (0,0,0), o weld interno de outras parts
	-- pode usar diretamente partDef.offset como CFrame relativo ao attachment.
	-- Resultado: a outra part welded com WeldConstraint ao Handle, com Part0=
	-- handle, Part1=otherPart, offset = otherDef.offset relativo a handlePartDef.offset.
	for i = 2, #def.parts do
		local partDef = def.parts[i]
		local extraPart = buildPart(partDef, false)
		-- CFrame relativo: queremos extraPart no attachment com partDef.offset.
		-- Handle vai ficar no attachment com handlePartDef.offset.
		-- Então extraPart relativo ao Handle = (handlePartDef.offset)^-1 * partDef.offset.
		extraPart.CFrame = handle.CFrame * (handlePartDef.offset:Inverse() * partDef.offset)
		extraPart.Parent = accessory

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = extraPart
		weld.Parent = handle
	end

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
	local defsList = ClassAccessoryDefs[classId]
	if not defsList then
		-- Classe sem accessories definidas — silently skip (válido).
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, def in ipairs(defsList) do
		local ok, accessoryOrErr = pcall(function()
			return buildAccessory(def)
		end)
		if not ok then
			warn(string.format("[ClassAccessoryService] buildAccessory failed for %s/%s: %s",
				classId, def.name, tostring(accessoryOrErr)))
			continue
		end
		local accessory = accessoryOrErr :: Accessory
		-- Humanoid:AddAccessory faz o weld nas attachment points por nome
		-- (Handle.Attachment.Name == bodyPart.Attachment.Name → auto-weld).
		humanoid:AddAccessory(accessory)
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
