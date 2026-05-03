--!strict

-- ClassAccessoryDefs: shapes, cores, attachment points por classe pra construir
-- Accessories proceduralmente em runtime. Acaba com dependência de catalog
-- assets (ownership/trust issues do InsertService:LoadAsset com items de
-- creators terceiros) e copyright.
--
-- Estratégia: cada parte é um Part primitivo (Shape=Ball/Cylinder/Block) com
-- Color/Size/Attachment próprios. Roblox renderiza nativo, sem mesh import.
-- Forma carrega identidade da classe (luva ≠ wrap ≠ tutu); Highlight outline
-- carrega cor da classe (axis ortogonal — ver DESIGN.md surface decoupling).
--
-- Cores escolhidas pra serem **iconicamente legíveis** pela forma + cor base:
--   Boxer  → vermelho clássico de luva de boxe + trim dourado (AccentColor da classe)
--   Taekwon → branco-cru clássico de wrap martial arts
--   Ballerina → rosa pastel clássico de tutu
--
-- Attachment points são standard Roblox rig (R6 e R15 ambos suportam):
--   LeftGripAttachment / RightGripAttachment — nas mãos
--   WaistCenterAttachment — na cintura (Torso R6, LowerTorso R15)

type AccessoryPartDef = {
	-- Roblox Part.Shape — Ball, Cylinder, Block
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	-- CFrame offset relativo ao attachment point. Identity = collado no
	-- attachment; rotações ajustam orientação (ex.: tutu precisa girar
	-- pra cylinder ficar horizontal/disco-like).
	offset: CFrame,
}

type ClassAccessoryDef = {
	-- Nome do Accessory (vai pro Accessory.Name + identificação no character)
	name: string,
	-- Nome do Attachment standard no rig do char (Roblox Accessory weld
	-- automático bate por nome).
	attachmentName: string,
	-- Lista de Parts compondo a accessory. Primeira é o Handle (welded ao
	-- char via attachment); restantes são welded ao Handle.
	parts: { AccessoryPartDef },
}

-- Tokens locais pra cores reusáveis (nao confundir com DESIGN.md Class Colors,
-- que pintam o Highlight outline — outra surface).
local LEATHER_RED = Color3.fromRGB(165, 35, 35)
local GOLD_TRIM = Color3.fromRGB(220, 180, 90) -- mesmo do AccentColor do Boxer
local WRAP_CREAM = Color3.fromRGB(230, 220, 195)
local WRAP_STRIPE = Color3.fromRGB(95, 50, 180) -- mesmo do AccentColor do Taekwon
local TUTU_PINK = Color3.fromRGB(255, 200, 220)
local TUTU_RIBBON = Color3.fromRGB(140, 240, 220) -- mesmo do AccentColor da Ballerina

local Defs: { [string]: { ClassAccessoryDef } } = {
	-- ===== BOXER =====
	-- Luvas de boxe estilizadas: bola arredondada (fist) + cilindro fino na
	-- base (cuff) na cor accent da classe. Pareadas L+R.
	Boxer = {
		{
			name = "BoxerLeftGlove",
			attachmentName = "LeftGripAttachment",
			parts = {
				{
					-- Fist principal (bola elongada, scale Z um pouco maior pra
					-- parecer mais "punching" que esférico puro)
					shape = Enum.PartType.Ball,
					size = Vector3.new(1.5, 1.5, 1.7),
					color = LEATHER_RED,
					material = Enum.Material.SmoothPlastic,
					-- Centra na atttachment, leve avanço pra frente da mão
					offset = CFrame.new(0, 0, 0.4),
				},
				{
					-- Cuff dourado na base (anel atrás da bola)
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.4, 1.3, 1.3),
					color = GOLD_TRIM,
					material = Enum.Material.SmoothPlastic,
					-- Cylinder.Shape eixo é X — pra ficar como anel na direção
					-- do braço, alinha X com Z do attachment (rota 90° em Y).
					offset = CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.rad(90), 0),
				},
			},
		},
		{
			name = "BoxerRightGlove",
			attachmentName = "RightGripAttachment",
			parts = {
				{
					shape = Enum.PartType.Ball,
					size = Vector3.new(1.5, 1.5, 1.7),
					color = LEATHER_RED,
					material = Enum.Material.SmoothPlastic,
					offset = CFrame.new(0, 0, 0.4),
				},
				{
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.4, 1.3, 1.3),
					color = GOLD_TRIM,
					material = Enum.Material.SmoothPlastic,
					offset = CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.rad(90), 0),
				},
			},
		},
	},

	-- ===== TAEKWON =====
	-- Wraps (bandagens) nas mãos: cilindro fino enrolando o pulso, com listra
	-- violeta (AccentColor) pra dar identidade visual. Pareadas L+R.
	Taekwon = {
		{
			name = "TaekwonLeftWrap",
			attachmentName = "LeftGripAttachment",
			parts = {
				{
					-- Wrap principal: cilindro mais largo (Y/Z = diâmetro,
					-- X = comprimento ao longo do braço).
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(1.0, 1.3, 1.3),
					color = WRAP_CREAM,
					material = Enum.Material.Fabric,
					offset = CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.rad(90), 0),
				},
				{
					-- Listra accent — cilindro fino sobreposto, levemente maior
					-- diâmetro pra "envolver" sem z-fighting.
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.25, 1.35, 1.35),
					color = WRAP_STRIPE,
					material = Enum.Material.Fabric,
					offset = CFrame.new(0, 0, -0.55) * CFrame.Angles(0, math.rad(90), 0),
				},
			},
		},
		{
			name = "TaekwonRightWrap",
			attachmentName = "RightGripAttachment",
			parts = {
				{
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(1.0, 1.3, 1.3),
					color = WRAP_CREAM,
					material = Enum.Material.Fabric,
					offset = CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.rad(90), 0),
				},
				{
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.25, 1.35, 1.35),
					color = WRAP_STRIPE,
					material = Enum.Material.Fabric,
					offset = CFrame.new(0, 0, -0.55) * CFrame.Angles(0, math.rad(90), 0),
				},
			},
		},
	},

	-- ===== BALLERINA =====
	-- Tutu: disco achatado (cilindro deitado) na cintura, rosa pastel + ribbon
	-- aqua (AccentColor) na borda externa.
	Ballerina = {
		{
			name = "BallerinaTutu",
			attachmentName = "WaistCenterAttachment",
			parts = {
				{
					-- Disco principal — cilindro com eixo vertical (rota Z=90°
					-- bota X horizontal vira eixo vertical na orientação base).
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.6, 4.5, 4.5),
					color = TUTU_PINK,
					material = Enum.Material.Fabric,
					-- Rotaciona pra cylinder.X (axis) ficar na vertical (Y do mundo)
					offset = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
				},
				{
					-- Ribbon: cilindro mais fino externamente (anel maior raio)
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(0.7, 4.7, 4.7),
					color = TUTU_RIBBON,
					material = Enum.Material.Fabric,
					-- Mesma orientação, levemente abaixo + maior raio (reage
					-- como uma "borda" acentuada visualmente)
					offset = CFrame.new(0, -0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
				},
			},
		},
	},
}

return Defs
