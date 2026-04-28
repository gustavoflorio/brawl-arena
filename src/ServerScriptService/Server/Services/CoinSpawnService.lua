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
-- Inset de 15 studs nas pontas pra moeda nao spawnar grudada nas borda.
local SPAWN_X_MIN = 75
local SPAWN_X_MAX = 125
local SPAWN_Y = 9
local SPAWN_Z = 0

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

function CoinSpawnService:_spawnCoin()
	if self._currentCoin and self._currentCoin.Parent then
		return -- ja tem moeda viva
	end

	local x = math.random() * (SPAWN_X_MAX - SPAWN_X_MIN) + SPAWN_X_MIN
	local coin = buildCoin(Vector3.new(x, SPAWN_Y, SPAWN_Z))

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
