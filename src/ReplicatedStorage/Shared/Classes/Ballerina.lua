--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Ballerina: identidade = mobility. Frame data parte de Constants.Combat.Moves
-- (table.clone shallow — campos só escalares) e sobrescreve Startup/Active/
-- Recovery pra casar com a duração real das anims (Jet1 1.3s, Jet2 1.3s,
-- Arabesque 0.8s, Spin 2.0s). Sem isso, swing acaba em ~0.3s mas anim continua
-- por 1s+ e o combo trava porque o buffer de input expira antes do fim visual.
-- Split usado: ~25% startup, ~15% active, ~60% recovery (padrão fighting game).
-- ComboWindow e LungeSpeed mantidos herdados do Boxer por enquanto (tuning
-- separado). Chaves arbitrárias: protocolo é dirigido por ComboStarter +
-- Move.Next, cada classe nomeia seus moves como quiser.

local baseMoves = Constants.Combat.Moves

-- Jet1/Jet2: anim natural 1.30s, mas o feel de Boxer rápido pede aceleração.
-- Tocando 1.6x acelera o visual; timings divididos pelo mesmo fator mantêm
-- gameplay sincronizado (swing acaba quando anim acaba).
local jetSpeed = 1.6

local Jet1 = table.clone(baseMoves.Jab1)
Jet1.AnimationId = "rbxassetid://121219969575849"
Jet1.Next = "Jet2"
Jet1.AnimSpeed = jetSpeed
Jet1.Startup = 0.40 / jetSpeed
Jet1.Active = 0.40 / jetSpeed
Jet1.Recovery = 0.50 / jetSpeed
Jet1.LungeSpeed = 50

local Jet2 = table.clone(baseMoves.Jab2)
Jet2.AnimationId = "rbxassetid://131729594416095"
Jet2.Next = "Arabesque"
Jet2.AnimSpeed = jetSpeed
Jet2.Startup = 0.40 / jetSpeed
Jet2.Active = 0.40 / jetSpeed
Jet2.Recovery = 0.50 / jetSpeed
Jet2.LungeSpeed = 50

local Arabesque = table.clone(baseMoves.Jab3)
Arabesque.AnimationId = "rbxassetid://117200019361388"
Arabesque.Next = nil
Arabesque.Startup = 0.20
Arabesque.Active = 0.40
Arabesque.Recovery = 0.20
Arabesque.LungeSpeed = 15

local Spin = table.clone(baseMoves.Heavy)
Spin.AnimationId = "rbxassetid://109321388916076"
Spin.Next = nil
Spin.Startup = 0.50
Spin.Active = 1.00
Spin.Recovery = 0.50
-- Hitbox simétrico: Range igual pros dois lados (sem offset de facing).
-- pointInHitbox usa BackOffset pra dimensão "atrás" — quando BackOffset == Range,
-- a box vira axis-aligned simétrica sobre o origin.
Spin.BackOffset = 8
Spin.LungeSpeed = 15

local Ballerina = {
	Id = "Ballerina",
	DisplayName = "Ballerina",
	Description = "Pure mobility. Reposition, dance, escape.",
	IconAssetId = "74087510553468",
	Price = 500,
	IsDefault = false,
	Moves = {
		Jet1 = Jet1,
		Jet2 = Jet2,
		Arabesque = Arabesque,
		Spin = Spin,
	},
	ComboStarter = "Jet1",
	HeavyKey = "Spin",
}

return Ballerina
