--!strict

-- STUB: implementação completa na Lane B (WS3).
-- Propósito: log de eventos (kill, level up, rank up, donate, session start/end).
-- V1: GameAnalytics SDK (se drop-in simples) ou DataStore manual ou print-only.

type Services = { [string]: any }

local AnalyticsService = {}
AnalyticsService._services = nil :: Services?
AnalyticsService._enabled = false

function AnalyticsService:Init(services: Services)
	self._services = services
end

function AnalyticsService:Start()
	-- TODO (WS3): sanity-check HttpService, inicializar GameAnalytics SDK
end

function AnalyticsService:Log(eventName: string, payload: { [string]: any }?)
	if not self._enabled then
		return
	end
	-- TODO (WS3): forward pro SDK ou DataStore
end

return AnalyticsService
