--!strict

-- Handler server-side de hits em LobbyTargets (punching bag, sandbag futuros).
-- O asset em si é criado no Studio/DevSandbox: Part com atributo LobbyTarget=true
-- em Workspace.Lobby (qualquer profundidade). CombatService chama RegisterHit
-- quando o hitbox de um soco conecta.

type Services = { [string]: any }

local LobbyTrainingService = {}
LobbyTrainingService._services = nil :: Services?

function LobbyTrainingService:Init(services: Services)
	self._services = services
end

function LobbyTrainingService:Start() end

-- Aplica impulso no alvo e bump HitSeq pra cliente tocar som/FX localmente.
-- Sem HP, sem damage%, sem knockback no puncher — feedback puramente kinestésico.
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

	-- Direção horizontal: do puncher pro bag (2D side-scroller usa X).
	local dx = bag.Position.X - puncherRoot.Position.X
	local signX = dx >= 0 and 1 or -1

	-- Magnitude escala com KnockbackMult do move. Jab (~0.55x) = swing leve;
	-- Heavy (~1.5x) = swing forte. Component vertical leve vende "uppercut".
	local baseImpulse = 220
	local magnitude = baseImpulse * (move.KnockbackMult or 1)
	local impulse = Vector3.new(signX * magnitude, magnitude * 0.15, 0)
	bag:ApplyImpulse(impulse)

	-- BrawlHitSeq bump: cliente ouve attribute change e toca PunchHitSound.
	local current = bag:GetAttribute("BrawlHitSeq")
	local nextVal = (typeof(current) == "number" and current or 0) + 1
	bag:SetAttribute("BrawlHitSeq", nextVal)
	bag:SetAttribute("BrawlLastHitterId", puncher.UserId)
	bag:SetAttribute("BrawlHitKind", move.HitKind or "Light")
end

return LobbyTrainingService
