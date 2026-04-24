--!strict

-- Gera o PunchingBag no lobby programaticamente (sem precisar de asset no Studio).
-- Bag é alvo kinestésico: swing físico via HingeConstraint, sem HP/damage/knockback.
-- CombatService detecta hits via atributo LobbyTarget=true e aplica impulso + HitSeq.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

type Services = { [string]: any }

local LOBBY_TARGET_ATTR = "LobbyTarget"
local BAG_NAME = "PunchingBag"
local LOBBY_FOLDER_NAME = "Lobby"
local LOBBY_SPAWN_NAME = "LobbySpawn"

-- Offset relativo ao LobbySpawn: 12 studs à frente (eixo X) do spawn.
-- Z locka em 0 pra ficar no plano 2D do side-scroller.
local BAG_OFFSET = Vector3.new(12, 4, 0)
local BAG_HEIGHT = 6
local BAG_RADIUS = 1.2
local CHAIN_HEIGHT = 3

-- DESIGN.md tokens (mantenho aqui pra não acoplar com Theme ainda).
local COLOR_BAG = Color3.fromRGB(20, 24, 44)      -- bg.surface
local COLOR_BAG_RIM = Color3.fromRGB(255, 107, 53) -- player.p1 (accent neon)
local COLOR_CHAIN = Color3.fromRGB(120, 120, 140)  -- text.dim

local LobbyTrainingService = {}
LobbyTrainingService._services = nil :: Services?
LobbyTrainingService._bag = nil :: Model?
LobbyTrainingService._spawnWatch = nil :: RBXScriptConnection?

local function resolveLobbyFolder(): Instance?
	return Workspace:FindFirstChild(LOBBY_FOLDER_NAME)
end

local function resolveLobbySpawn(lobby: Instance): BasePart?
	local spawn = lobby:FindFirstChild(LOBBY_SPAWN_NAME)
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

local function buildBag(anchorPos: Vector3): Model
	-- Anchor invisível acima (âncora do Hinge).
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Anchored = true
	anchor.CastShadow = false
	anchor.Position = anchorPos + Vector3.new(0, CHAIN_HEIGHT + BAG_HEIGHT / 2, 0)

	-- Corrente (puramente visual, fina).
	local chain = Instance.new("Part")
	chain.Name = "Chain"
	chain.Shape = Enum.PartType.Cylinder
	chain.Size = Vector3.new(CHAIN_HEIGHT, 0.15, 0.15)
	chain.Color = COLOR_CHAIN
	chain.Material = Enum.Material.Metal
	chain.CanCollide = false
	chain.CanQuery = false
	chain.CanTouch = false
	chain.Anchored = true
	chain.CastShadow = false
	-- Cilindro é orientado no eixo X por default. Rotaciono 90° em Z pra ficar vertical.
	chain.CFrame = CFrame.new(anchorPos + Vector3.new(0, BAG_HEIGHT / 2 + CHAIN_HEIGHT / 2, 0))
		* CFrame.Angles(0, 0, math.pi / 2)

	-- Bag (alvo do soco).
	local bag = Instance.new("Part")
	bag.Name = "Bag"
	bag.Shape = Enum.PartType.Cylinder
	bag.Size = Vector3.new(BAG_HEIGHT, BAG_RADIUS * 2, BAG_RADIUS * 2)
	bag.Color = COLOR_BAG
	bag.Material = Enum.Material.SmoothPlastic
	bag.CanCollide = false -- phantom pra player não empurrar andando
	bag.CanQuery = true
	bag.CanTouch = false
	bag.CastShadow = true
	bag.CFrame = CFrame.new(anchorPos) * CFrame.Angles(0, 0, math.pi / 2)
	bag.CustomPhysicalProperties = PhysicalProperties.new(
		2.5, -- Density (leve pra balançar bem)
		0.3, -- Friction
		0.2, -- Elasticity
		1,   -- FrictionWeight
		1    -- ElasticityWeight
	)
	bag:SetAttribute(LOBBY_TARGET_ATTR, true)

	-- Rim neon (acento visual minimalista do DESIGN.md).
	-- SelectionBox dá contorno sutil que combina com a direção arcade neon sem
	-- poluir com part extra ou particle.
	local rim = Instance.new("SelectionBox")
	rim.Name = "Rim"
	rim.Adornee = bag
	rim.LineThickness = 0.05
	rim.Color3 = COLOR_BAG_RIM
	rim.Transparency = 0.35
	rim.SurfaceColor3 = COLOR_BAG_RIM
	rim.SurfaceTransparency = 0.9
	rim.Parent = bag

	-- Attachments pro Hinge.
	local attachAnchor = Instance.new("Attachment")
	attachAnchor.Name = "HingeAnchor"
	attachAnchor.Parent = anchor

	local attachBag = Instance.new("Attachment")
	attachBag.Name = "HingeBag"
	-- Ponto de suspensão fica no topo do bag (em local space). Bag foi rotacionado
	-- no CFrame acima pra ficar vertical, então seu eixo "longo" é Y em world mas
	-- X em local (Cylinder nativo é X). O topo local = +X/2.
	attachBag.CFrame = CFrame.new(BAG_HEIGHT / 2, 0, 0)
	attachBag.Parent = bag

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Hinge"
	hinge.Attachment0 = attachAnchor
	hinge.Attachment1 = attachBag
	-- Axis default é o X do Attachment. Com anchor sem rotação, isso é o X mundial.
	-- Pro bag swingar no plano X-Y (gameplane 2D), preciso do eixo de rotação = Z.
	hinge.Enabled = true
	-- Aplico axis via orientação do attachment anchor: rotaciono 90° em Y pra alinhar X→Z.
	attachAnchor.CFrame = CFrame.Angles(0, math.pi / 2, 0)
	hinge.LimitsEnabled = true
	hinge.UpperAngle = 60
	hinge.LowerAngle = -60
	hinge.Restitution = 0.1 -- amortecimento natural
	hinge.AngularResponsiveness = 50

	local model = Instance.new("Model")
	model.Name = BAG_NAME
	anchor.Parent = model
	chain.Parent = model
	bag.Parent = model
	hinge.Parent = model
	model.PrimaryPart = bag

	return model
end

function LobbyTrainingService:_ensureBag()
	local lobby = resolveLobbyFolder()
	if not lobby then
		return
	end
	if lobby:FindFirstChild(BAG_NAME) then
		return
	end
	local spawn = resolveLobbySpawn(lobby)
	if not spawn then
		return
	end

	local anchorPos = spawn.Position + BAG_OFFSET
	-- Z lock no 0 pra ficar no plano 2D (AxisLockValue do Constants.Arena).
	anchorPos = Vector3.new(anchorPos.X, anchorPos.Y, 0)

	local bag = buildBag(anchorPos)
	bag.Parent = lobby
	self._bag = bag
end

function LobbyTrainingService:Init(services: Services)
	self._services = services
end

function LobbyTrainingService:Start()
	-- Tenta gerar imediatamente. Se lobby folder ou spawn ainda não existem,
	-- agenda retry via ChildAdded (mesma pattern do ArenaService).
	self:_ensureBag()

	local lobby = resolveLobbyFolder()
	if not lobby then
		-- Workspace.Lobby não existe ainda: escuta até aparecer.
		local conn: RBXScriptConnection
		conn = Workspace.ChildAdded:Connect(function(child)
			if child.Name == LOBBY_FOLDER_NAME then
				conn:Disconnect()
				-- Após folder existir, ainda espera LobbySpawn.
				if resolveLobbySpawn(child) then
					self:_ensureBag()
				else
					local spawnConn: RBXScriptConnection
					spawnConn = child.ChildAdded:Connect(function(subchild)
						if subchild.Name == LOBBY_SPAWN_NAME and subchild:IsA("BasePart") then
							spawnConn:Disconnect()
							self:_ensureBag()
						end
					end)
				end
			end
		end)
		return
	end

	if not resolveLobbySpawn(lobby) then
		local conn: RBXScriptConnection
		conn = lobby.ChildAdded:Connect(function(child)
			if child.Name == LOBBY_SPAWN_NAME and child:IsA("BasePart") then
				conn:Disconnect()
				self:_ensureBag()
			end
		end)
	end
end

-- Chamado pelo CombatService quando o hitbox de um soco encosta na bag.
-- Aplica impulso proporcional ao move e replica o hit via attribute (cliente
-- toca som + FX no seu próprio clock).
function LobbyTrainingService:RegisterHit(bag: BasePart, puncher: Player, move: any)
	if not bag or not bag.Parent then
		return
	end
	local puncherChar = puncher.Character
	if not puncherChar then
		return
	end
	local puncherRoot = puncherChar:FindFirstChild("HumanoidRootPart")
	if not puncherRoot or not puncherRoot:IsA("BasePart") then
		return
	end

	-- Direção: do puncher pro bag, só no eixo X (2D side-scroller).
	local dx = bag.Position.X - puncherRoot.Position.X
	local signX = dx >= 0 and 1 or -1

	-- Magnitude: escala com KnockbackMult do move. Bag é leve (density 2.5);
	-- multiplicador base 220 dá swing visível em jab (~0.55x = 121) e fortíssimo
	-- em heavy (~1.5x = 330) — parecido com leve/pesado do arena feel.
	local baseImpulse = 220
	local magnitude = baseImpulse * (move.KnockbackMult or 1)

	-- Horizontal + leve component vertical pra vender o "uppercut" feeling.
	local impulse = Vector3.new(signX * magnitude, magnitude * 0.15, 0)
	bag:ApplyImpulse(impulse)

	-- Bump HitSeq pra client tocar som + VFX localmente.
	local current = bag:GetAttribute("BrawlHitSeq")
	local nextVal = (typeof(current) == "number" and current or 0) + 1
	bag:SetAttribute("BrawlHitSeq", nextVal)
	bag:SetAttribute("BrawlLastHitterId", puncher.UserId)
	bag:SetAttribute("BrawlHitKind", move.HitKind or "Light")
end

return LobbyTrainingService
