--!strict

-- STUB: implementação completa na Lane B (WS2).
-- Propósito: orquestra side-effects de um kill (XP, rank points, streak, analytics, BrawlEvents).

type Services = { [string]: any }

local KillProcessor = {}
KillProcessor._services = nil :: Services?

function KillProcessor:Init(services: Services)
	self._services = services
end

function KillProcessor:Start() end

function KillProcessor:HandleKill(puncher: Player, target: Player)
	-- TODO (WS2): calcular XP (base + MMR bonus), emitir ao PlayerDataService,
	-- apply rank points, detect streak, fire BrawlEvents broadcast, log analytics.
end

return KillProcessor
