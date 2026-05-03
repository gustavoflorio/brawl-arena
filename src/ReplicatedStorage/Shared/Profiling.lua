--!strict

-- Profiling diagnóstico pra rastrear desync entre cliente e servidor. Usado
-- temporariamente durante testing pra identificar gargalos de replicação.
-- Constants.Profiling.Enabled = false desliga tudo (no-op).
--
-- Fluxo de uso típico (state replication):
--   server: Profiling.StampSeq(char, "BrawlHitSeq") antes do SetAttribute
--           do seq bump.
--   client: Profiling.LogSeqArrival(char, "BrawlHitSeq", seq, "Hit") no
--           listener — printa delta_ms = serverTime_chegada - serverTime_bump.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Profiling = {}

local _constants
local function config()
	-- Lazy-require Constants pra evitar problemas de ordem de require em
	-- ambientes que carregam Profiling antes de Constants estar pronto.
	if not _constants then
		local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
		_constants = require(sharedFolder:WaitForChild("Constants"))
	end
	return _constants.Profiling
end

function Profiling.IsEnabled(category: string?): boolean
	local c = config()
	if not c or not c.Enabled then
		return false
	end
	if category and c[category] == false then
		return false
	end
	return true
end

function Profiling.Log(category: string, fields: { [string]: any })
	if not Profiling.IsEnabled(category) then
		return
	end
	-- Sort keys pra output determinístico (facilita grep/diff).
	local keys: { string } = {}
	for k in pairs(fields) do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local parts: { string } = {}
	for _, k in ipairs(keys) do
		table.insert(parts, k .. "=" .. tostring(fields[k]))
	end
	print("[PROFILE " .. category .. "] " .. table.concat(parts, " "))
end

-- Server-side helper: stampa timestamp de servidor antes de um seq bump.
-- Cliente lê o stamp no listener e computa o delta de replicação.
function Profiling.StampSeq(character: Instance, seqAttr: string)
	if not Profiling.IsEnabled("StateReplication") then
		return
	end
	character:SetAttribute(seqAttr .. "Stamp", Workspace:GetServerTimeNow())
end

-- Client-side helper: lê o stamp anexado pelo servidor e printa o delta.
function Profiling.LogSeqArrival(character: Instance, seqAttr: string, seq: number, eventName: string?)
	if not Profiling.IsEnabled("StateReplication") then
		return
	end
	local stamp = character:GetAttribute(seqAttr .. "Stamp")
	if typeof(stamp) ~= "number" then
		return
	end
	local delta_ms = (Workspace:GetServerTimeNow() - stamp) * 1000
	Profiling.Log("StateReplication", {
		event = eventName or seqAttr,
		char = character.Name,
		seq = seq,
		delta_ms = math.floor(delta_ms + 0.5),
	})
end

return Profiling
