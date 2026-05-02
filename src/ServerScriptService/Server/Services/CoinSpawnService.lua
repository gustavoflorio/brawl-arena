--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

-- CoinSpawnService: spawn de uma moeda na arena por vez. Player que toca
-- ganha +1 currency e a moeda é destruída; 5s depois uma nova spawna em
-- posição random na faixa da arena. Loop de rotação roda server-side
-- (single coin = bandwidth desprezível) pra todos verem a mesma anim.

type Services = { [string]: any }

local COIN_RESPAWN_DELAY = 5
local COIN_INITIAL_DELAY = 2

-- Faixa de spawn dentro do bounding box da arena (X 60-140, Y 4.5-33, Z 0).
-- Escolhe X random no range, daí raycast Y- pra achar a superfície mais alta
-- (chão ou plataforma) e ancora a moeda em cima — variação vem das plataformas
-- em alturas diferentes, mas moeda sempre fica no solo (não flutua).
local SPAWN_X_MIN = 68
local SPAWN_X_MAX = 132
local SPAWN_Z = 0
local RAY_FROM_Y = 50 -- acima do top da arena (Y_MAX=33)
local RAY_DISTANCE = 100 -- cobre até abaixo do chão
local COIN_GROUND_OFFSET = 3.5 -- metade do diâmetro (4) + 1.5 de margem visível
local MAX_SPAWN_ATTEMPTS = 8

local ROTATION_SPEED = math.rad(180) -- 180°/sec, "moeda flipando" classico
local TEXTURE_ID = "rbxassetid://79708762867617"
local COIN_COLOR = Color3.fromRGB(255, 200, 30)

local function getPlayerFromHit(hit: BasePart): Player?
	-- hit pode ser parte do char direto OU acessorio (criança da Character
	-- model). FindFirstAncestorOfClass acha o Model do char em qualquer caso.
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function buildCoin(pos: Vector3): BasePart
	local coin = Instance.new("Part")
	coin.Name = "ArenaCoin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.3, 4, 4)
	coin.Material = Enum.Material.SmoothPlastic
	coin.Color = COIN_COLOR
	coin.Anchored = true
	coin.CanCollide = false
	-- CFrame inicial é so a posição; rotation é aplicada/atualizada no Heartbeat.
	coin.CFrame = CFrame.new(pos)

	local front = Instance.new("Decal")
	front.Name = "FaceFront"
	front.Texture = TEXTURE_ID
	front.Face = Enum.NormalId.Right
	front.Parent = coin

	local back = Instance.new("Decal")
	back.Name = "FaceBack"
	back.Texture = TEXTURE_ID
	back.Face = Enum.NormalId.Left
	back.Parent = coin

	return coin
end

local CoinSpawnService = {}
CoinSpawnService._services = nil :: Services?
CoinSpawnService._currentCoin = nil :: BasePart?
CoinSpawnService._rotationConn = nil :: RBXScriptConnection?
CoinSpawnService._rotationAngle = 0

function CoinSpawnService:Init(services: Services)
	self._services = services
end

local function findGroundedSpawn(): Vector3?
	-- Raycast Y- pra achar a superfície mais alta naquele X. Filtra chars de
	-- jogador (senão pode bater num player na plataforma e spawnar em cima
	-- dele). Tenta múltiplos Xs porque pode cair em vão entre plataformas.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	for _ = 1, MAX_SPAWN_ATTEMPTS do
		local x = math.random() * (SPAWN_X_MAX - SPAWN_X_MIN) + SPAWN_X_MIN
		local origin = Vector3.new(x, RAY_FROM_Y, SPAWN_Z)
		local result = Workspace:Raycast(origin, Vector3.new(0, -RAY_DISTANCE, 0), params)
		if result then
			return Vector3.new(x, result.Position.Y + COIN_GROUND_OFFSET, SPAWN_Z)
		end
	end
	return nil
end

function CoinSpawnService:_spawnCoin()
	if self._currentCoin and self._currentCoin.Parent then
		return -- ja tem moeda viva
	end

	local pos = findGroundedSpawn()
	if not pos then
		-- Fallback: nenhum raycast bateu (arena vazia? geometria quebrada?).
		-- Spawna no centro a Y=9 pra garantir que jogadores ainda peguem moeda.
		warn("[CoinSpawnService] nenhuma superfície encontrada, usando fallback")
		pos = Vector3.new((SPAWN_X_MIN + SPAWN_X_MAX) / 2, 9, SPAWN_Z)
	end
	local coin = buildCoin(pos)

	local touchedConn: RBXScriptConnection?
	touchedConn = coin.Touched:Connect(function(hit)
		if not coin.Parent then
			return -- já coletada
		end
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end
		if self._currentCoin ~= coin then
			return
		end
		if touchedConn then
			touchedConn:Disconnect()
			touchedConn = nil
		end
		self:_collectCoin(player, coin)
	end)

	self._currentCoin = coin
	coin.Parent = Workspace
end

function CoinSpawnService:_collectCoin(player: Player, coin: BasePart)
	local services = self._services :: Services
	local playerData = services.PlayerDataService
	local arenaService = services.ArenaService

	local newBalance = 0
	if playerData and playerData.AddCurrency then
		newBalance = playerData:AddCurrency(player, 1)
	end

	-- Push novo saldo via PublishState (HUD lê snapshot.currency).
	if arenaService and arenaService.PublishState then
		arenaService:PublishState(player)
	end

	-- Evento CoinGain pro popup flutuante "+1 coin" (FloatingGainController
	-- ouve via BrawlEvents).
	local eventsRemote = Remotes.GetEventsRemote()
	if eventsRemote then
		eventsRemote:FireClient(player, {
			type = Constants.EventTypes.CoinGain,
			payload = { userId = player.UserId, amount = 1, balance = newBalance },
		})
	end

	coin:Destroy()
	if self._currentCoin == coin then
		self._currentCoin = nil
	end

	task.delay(COIN_RESPAWN_DELAY, function()
		self:_spawnCoin()
	end)
end

function CoinSpawnService:Start()
	-- Rotação: gira a moeda atual em torno do eixo Y mundial. Cylinder axis
	-- horizontal sweep no plano XZ — produz efeito "flipping coin" Mario-style
	-- (face visível, edge-on, face do outro lado, edge-on, repeat).
	self._rotationConn = RunService.Heartbeat:Connect(function(dt)
		local coin = self._currentCoin
		if coin and coin.Parent then
			self._rotationAngle = (self._rotationAngle + ROTATION_SPEED * dt) % (math.pi * 2)
			coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, self._rotationAngle, 0)
		end
	end)

	-- Spawn inicial com delay pra dar tempo de outros services subirem.
	task.delay(COIN_INITIAL_DELAY, function()
		self:_spawnCoin()
	end)
end

return CoinSpawnService
