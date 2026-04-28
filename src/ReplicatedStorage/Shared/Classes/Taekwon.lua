--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Taekwon: identidade = burst (chutes longos, dano alto). Combo de 2 hits —
-- Sweep abre, Palmas (64 palmas estilo Hokuto) finaliza. Heavy: Dragon Flying
-- Kick. Frame data calibrado pra duração de cada anim:
--   Sweep      = 1.00s (chute baixo, hit no swipe)
--   Palmas     = 4.00s (flurry — hit no golpe final, "killing blow" depois
--                       da windup visual de 64 palmas)
--   DragonKick = 1.05s (leap + impact, lunge alto pra cobrir distância)

local baseMoves = Constants.Combat.Moves

local Sweep = table.clone(baseMoves.Jab1)
Sweep.AnimationId = "rbxassetid://82787593146425"
Sweep.Next = "Palmas"
Sweep.Startup = 0.25
Sweep.Active = 0.30
Sweep.Recovery = 0.45
Sweep.LungeSpeed = 25

-- Palmas: 4s de "captura + DoT". Hit landa cedo (Active 0.20-0.50), engaja o
-- trap que prende o target pelos 3.5s seguintes. Damage de 20 distribuído em
-- 8 ticks (2.5/tick) ao longo do trap. Puncher commita o swing inteiro (4s);
-- target fica trancado pela duração do trap. Sem knockback — trap é o payoff.
local Palmas = table.clone(baseMoves.Jab3)
Palmas.AnimationId = "rbxassetid://101710755494114"
Palmas.Next = nil
Palmas.Startup = 0.20
Palmas.Active = 0.30
Palmas.Recovery = 3.50
Palmas.LungeSpeed = 7
Palmas.Damage = 20
Palmas.TrapDuration = 3.50
Palmas.TrapTicks = 8
Palmas.KnockbackMult = 0

-- DragonKick: leap + impact. Lunge alto pra dive forward. Active curto, hit
-- no momento do impacto (heavy padrão Smash-like).
local DragonKick = table.clone(baseMoves.Heavy)
DragonKick.AnimationId = "rbxassetid://98299028937621"
DragonKick.Next = nil
DragonKick.Startup = 0.35
DragonKick.Active = 0.20
DragonKick.Recovery = 0.50
DragonKick.LungeSpeed = 60

local Taekwon = {
	Id = "Taekwon",
	DisplayName = "Taekwon",
	Description = "High burst. Long kicks, surgical punishment.",
	IconAssetId = "121198361774472",
	Price = 500,
	IsDefault = false,
	Moves = {
		Sweep = Sweep,
		Palmas = Palmas,
		DragonKick = DragonKick,
	},
	ComboStarter = "Sweep",
	HeavyKey = "DragonKick",
}

return Taekwon
