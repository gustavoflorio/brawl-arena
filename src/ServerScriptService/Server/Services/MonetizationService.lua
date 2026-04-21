--!strict

-- STUB: implementação completa na Lane B (WS4).
-- Propósito: MarketplaceService.ProcessReceipt com idempotency via PurchaseId.

type Services = { [string]: any }

local MonetizationService = {}
MonetizationService._services = nil :: Services?

function MonetizationService:Init(services: Services)
	self._services = services
end

function MonetizationService:Start()
	-- TODO (WS4): conectar MarketplaceService.ProcessReceipt
end

return MonetizationService
