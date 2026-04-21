--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

type Services = { [string]: any }

local AnalyticsService = {}
AnalyticsService._services = nil :: Services?
AnalyticsService._enabled = false
AnalyticsService._store = nil :: DataStore?
AnalyticsService._buffer = {} :: { { [string]: any } }
AnalyticsService._flushConnection = nil :: thread?

local FLUSH_INTERVAL = 30
local MAX_BUFFER_SIZE = 100

local function utcTimestamp(): string
	return os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
end

function AnalyticsService:Init(services: Services)
	self._services = services
end

function AnalyticsService:_tryInitDataStore()
	if RunService:IsStudio() then
		self._enabled = true
		return
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("BrawlArenaAnalytics_v1")
	end)
	if ok then
		self._store = store
		self._enabled = true
	end
end

function AnalyticsService:Start()
	self:_tryInitDataStore()

	self._flushConnection = task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			self:_flush()
		end
	end) :: any

	game:BindToClose(function()
		self:_flush()
	end)
end

function AnalyticsService:Log(eventName: string, payload: { [string]: any }?)
	if not self._enabled then
		return
	end
	local record = {
		ts = utcTimestamp(),
		event = eventName,
		payload = payload or {},
	}
	if RunService:IsStudio() then
		print(string.format("[Analytics] %s %s", eventName, HttpService:JSONEncode(record.payload)))
	end
	table.insert(self._buffer, record)
	if #self._buffer >= MAX_BUFFER_SIZE then
		self:_flush()
	end
end

function AnalyticsService:_flush()
	if not self._enabled or not self._store or #self._buffer == 0 then
		return
	end
	local buffer = self._buffer
	self._buffer = {}
	local key = string.format("events_%s_%d", os.date("!%Y%m%d") :: string, math.random(1, 1e9))
	local ok, err = pcall(function()
		self._store:SetAsync(key, buffer)
	end)
	if not ok then
		warn("[AnalyticsService] Flush falhou:", err)
		for _, event in ipairs(buffer) do
			table.insert(self._buffer, event)
		end
	end
end

return AnalyticsService
