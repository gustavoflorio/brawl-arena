--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

type Services = { [string]: any }

type Entry = {
	userId: number,
	name: string,
	score: number,
}

local RankingService = {}
RankingService._services = nil :: Services?
RankingService._stores = {} :: { [string]: OrderedDataStore }
RankingService._cachedEntries = {} :: { [string]: { Entry } }
RankingService._nameCache = {} :: { [number]: string }
RankingService._dirtyModes = {} :: { [string]: boolean }
RankingService._refreshThread = nil :: thread?

local function resolveBoardDisplay(mode: string): BasePart?
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local hub = lobby:FindFirstChild("RankingBoards")
	if not hub then
		return nil
	end
	local board = hub:FindFirstChild("Board" .. mode)
	if not board then
		return nil
	end
	local display = board:FindFirstChild("Display")
	if display and display:IsA("BasePart") then
		return display
	end
	return nil
end

local function formatScore(mode: string, score: number): string
	local display = Constants.Ranking.ModeDisplay[mode]
	local suffix = display and display.scoreSuffix or ""
	if mode == Constants.Ranking.Modes.TimeAlive then
		local seconds = score
		local hours = math.floor(seconds / 3600)
		local mins = math.floor((seconds % 3600) / 60)
		local secs = seconds % 60
		if hours > 0 then
			return string.format("%dh %02dm", hours, mins)
		elseif mins > 0 then
			return string.format("%dm %02ds", mins, secs)
		end
		return string.format("%ds", secs)
	end
	return string.format("%d%s", score, suffix)
end

function RankingService:Init(services: Services)
	self._services = services
	for _, mode in pairs(Constants.Ranking.Modes) do
		local storeName = Constants.DataStore.RankingStorePrefix .. mode
		if RunService:IsStudio() then
			storeName = storeName .. "_Studio"
		end
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName)
		end)
		if ok and store then
			self._stores[mode] = store
		end
		self._cachedEntries[mode] = {}
	end
end

function RankingService:SubmitScore(player: Player, mode: string, score: number)
	if score < Constants.Ranking.MinScoreToSubmit then
		return
	end
	local store = self._stores[mode]
	if not store then
		return
	end
	self._nameCache[player.UserId] = player.Name
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(player.UserId, score)
		end)
		if not ok then
			warn(string.format("[RankingService] SetAsync %s failed: %s", mode, tostring(err)))
			return
		end
		self._dirtyModes[mode] = true
	end)
end

function RankingService:_fetchTop(mode: string): { Entry }
	local store = self._stores[mode]
	if not store then
		return {}
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Constants.Ranking.TopN)
	end)
	if not ok or not pages then
		return {}
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or not page then
		return {}
	end
	local entries: { Entry } = {}
	for _, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			local name = self._nameCache[userId]
			if not name then
				local okName, fetched = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				name = okName and fetched or ("User" .. userId)
				self._nameCache[userId] = name
			end
			table.insert(entries, {
				userId = userId,
				name = name,
				score = item.value,
			})
		end
	end
	return entries
end

function RankingService:_renderBoard(mode: string, entries: { Entry })
	local display = resolveBoardDisplay(mode)
	if not display then
		return
	end

	local gui = display:FindFirstChildOfClass("SurfaceGui")
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "BoardSurface"
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(500, 750)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.PixelsPerStud = 50
		gui.Parent = display
	end

	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end

	local displayConfig = Constants.Ranking.ModeDisplay[mode]
	local accent = displayConfig and displayConfig.accent or Color3.fromRGB(200, 200, 200)
	local title = displayConfig and displayConfig.title or mode

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	background.BorderSizePixel = 0
	background.Parent = gui

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 80)
	header.Position = UDim2.new(0, 0, 0, 10)
	header.BackgroundColor3 = accent
	header.BackgroundTransparency = 0.1
	header.BorderSizePixel = 0
	header.Text = title
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.TextScaled = true
	header.Font = Enum.Font.GothamBlack
	header.Parent = background

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -20, 1, -110)
	list.Position = UDim2.new(0, 10, 0, 100)
	list.BackgroundTransparency = 1
	list.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	if #entries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 50)
		empty.BackgroundTransparency = 1
		empty.Text = "No records yet..."
		empty.TextColor3 = Color3.fromRGB(160, 160, 180)
		empty.TextScaled = true
		empty.Font = Enum.Font.Gotham
		empty.Parent = list
	end

	for idx, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = idx % 2 == 0 and Color3.fromRGB(28, 28, 40) or Color3.fromRGB(40, 40, 55)
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		row.Parent = list

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 60, 1, 0)
		rankLabel.Position = UDim2.new(0, 10, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = string.format("#%d", idx)
		rankLabel.TextColor3 = idx <= 3 and accent or Color3.fromRGB(200, 200, 220)
		rankLabel.TextScaled = true
		rankLabel.Font = Enum.Font.GothamBlack
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -230, 1, 0)
		nameLabel.Position = UDim2.new(0, 80, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local scoreLabel = Instance.new("TextLabel")
		scoreLabel.Size = UDim2.new(0, 140, 1, 0)
		scoreLabel.Position = UDim2.new(1, -150, 0, 0)
		scoreLabel.BackgroundTransparency = 1
		scoreLabel.Text = formatScore(mode, entry.score)
		scoreLabel.TextColor3 = accent
		scoreLabel.TextScaled = true
		scoreLabel.Font = Enum.Font.GothamBold
		scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
		scoreLabel.Parent = row
	end

	local footer = Instance.new("TextLabel")
	footer.Size = UDim2.new(1, -20, 0, 20)
	footer.Position = UDim2.new(0, 10, 1, -28)
	footer.BackgroundTransparency = 1
	footer.Text = string.format("Updated: %s", os.date("!%H:%M UTC") :: string)
	footer.TextColor3 = Color3.fromRGB(120, 120, 140)
	footer.TextScaled = true
	footer.Font = Enum.Font.Gotham
	footer.TextXAlignment = Enum.TextXAlignment.Right
	footer.Parent = background
end

function RankingService:RefreshAll()
	for _, mode in pairs(Constants.Ranking.Modes) do
		local entries = self:_fetchTop(mode)
		self._cachedEntries[mode] = entries
		self:_renderBoard(mode, entries)
		self._dirtyModes[mode] = nil
	end
end

function RankingService:RefreshDirty()
	local anyDirty = false
	for mode in pairs(self._dirtyModes) do
		anyDirty = true
		local entries = self:_fetchTop(mode)
		self._cachedEntries[mode] = entries
		self:_renderBoard(mode, entries)
		self._dirtyModes[mode] = nil
	end
	return anyDirty
end

function RankingService:Start()
	task.defer(function()
		self:RefreshAll()
	end)

	self._refreshThread = task.spawn(function()
		while true do
			task.wait(Constants.Ranking.RefreshIntervalSeconds)
			self:RefreshDirty()
		end
	end) :: any

	Players.PlayerRemoving:Connect(function(player)
		self._nameCache[player.UserId] = nil
	end)
end

function RankingService:SubmitForPlayer(player: Player)
	local services = self._services :: Services?
	if not services or not services.PlayerDataService then
		return
	end
	local profile = services.PlayerDataService:GetProfile(player)
	if not profile then
		return
	end
	self:SubmitScore(player, Constants.Ranking.Modes.Level, profile.Level)
	self:SubmitScore(player, Constants.Ranking.Modes.Kills, profile.TotalKills)
	self:SubmitScore(player, Constants.Ranking.Modes.TimeAlive, math.floor(profile.TotalTimeAlive))
end

return RankingService
