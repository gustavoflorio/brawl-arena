--!strict

-- Painel de stats do player: rank + progresso FP, série ativa, highest rank,
-- level/XP e combat stats (kills/deaths/KD). Exposto como Toggle() e acionado
-- pelo rank badge do HudController (via controllers[StatsPanelController]:Toggle).
-- Dados vêm do state snapshot (campo `stats`) — o cache é atualizado a cada
-- snapshot, então abrir o painel mostra sempre o estado mais recente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Rank = require(sharedFolder:WaitForChild("Rank"))

local ResponsiveLayout = require(script.Parent:WaitForChild("ResponsiveLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Tokens do DESIGN.md
local BG_DEEP = Color3.fromRGB(13, 15, 26)
local BG_SURFACE = Color3.fromRGB(20, 24, 44)
local BG_ELEVATED = Color3.fromRGB(28, 32, 56)
local TEXT_PRIMARY = Color3.fromRGB(230, 232, 240)
local TEXT_PURE = Color3.fromRGB(255, 255, 255)
local TEXT_MUTED = Color3.fromRGB(160, 165, 184)
local TEXT_DIM = Color3.fromRGB(120, 120, 140)
local SUCCESS = Color3.fromRGB(74, 219, 122)
local INFO = Color3.fromRGB(74, 158, 255)
local WARNING = Color3.fromRGB(255, 203, 43)
local ERROR = Color3.fromRGB(255, 71, 87)
local FP_GOLD = Color3.fromRGB(255, 220, 120)

local POINTS_PER_TIER = Constants.Rank.PointsPerTier
local CHAMPION_TIER_IDX = #Constants.Rank.Tiers

-- Responsive layout: composição "fixed geometry" em resolução desktop,
-- escalada via UIScale pra caber no safe viewport (sem reflow estrutural).
-- Padrão da skill roblox-ui-creator — ver Controllers/ResponsiveLayout.lua.
local MODAL_DESIGN_WIDTH = 760
local MODAL_DESIGN_HEIGHT = 720
local MODAL_POP_START_WIDTH = 600
local MODAL_POP_START_HEIGHT = 580

type Snapshot = {
	level: number?,
	xp: number?,
	xpForNextLevel: number?,
	rank: { name: string, tier: number }?,
	stats: {
		kills: number?,
		deaths: number?,
		rankPoints: number?,
		highestRank: string?,
		seriesKind: string?,
		seriesProgress: number?,
	}?,
	state: string?,
}

local StatsPanelController = {}
StatsPanelController._latestSnapshot = {} :: Snapshot
StatsPanelController._isOpen = false

-- Refs
StatsPanelController._modalGui = nil :: ScreenGui?
StatsPanelController._modalRoot = nil :: Frame?
StatsPanelController._modalOverlay = nil :: Frame?
StatsPanelController._rankIcon = nil :: ImageLabel?
StatsPanelController._rankName = nil :: TextLabel?
StatsPanelController._rankPointsText = nil :: TextLabel?
StatsPanelController._rankBar = nil :: Frame?
StatsPanelController._rankBarFill = nil :: Frame?
StatsPanelController._rankProgressText = nil :: TextLabel?
StatsPanelController._seriesRow = nil :: Frame?
StatsPanelController._seriesText = nil :: TextLabel?
StatsPanelController._seriesDots = nil :: { Frame }?
StatsPanelController._levelLabel = nil :: TextLabel?
StatsPanelController._xpBarFill = nil :: Frame?
StatsPanelController._xpText = nil :: TextLabel?
StatsPanelController._killsValue = nil :: TextLabel?
StatsPanelController._deathsValue = nil :: TextLabel?
StatsPanelController._kdValue = nil :: TextLabel?
StatsPanelController._inputConn = nil :: RBXScriptConnection?
StatsPanelController._panelScale = nil :: UIScale?
StatsPanelController._viewportConn = nil :: RBXScriptConnection?
StatsPanelController._cameraChangedConn = nil :: RBXScriptConnection?

-- Helpers -----------------------------------------------------------------

local function roundedCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function newText(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextColor3 = TEXT_PRIMARY
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function computeTierProgress(rankPoints: number, tierIdx: number): (number, number, number)
	-- Retorna (pointsInTier, pointsToNextTier, pctFilled[0..1]).
	-- Champion é terminal: progresso é aberto (sempre 100%).
	if tierIdx >= CHAMPION_TIER_IDX then
		return rankPoints, rankPoints, 1
	end
	local threshold = Constants.Rank.Tiers[tierIdx].threshold
	local pointsInTier = math.max(0, rankPoints - threshold)
	local pct = math.clamp(pointsInTier / POINTS_PER_TIER, 0, 1)
	return pointsInTier, POINTS_PER_TIER, pct
end

local function nextTierName(tierIdx: number): string?
	local next = Constants.Rank.Tiers[tierIdx + 1]
	return next and next.name or nil
end

-- Build -------------------------------------------------------------------

local function buildStatCard(parent: Instance, title: string, xOffset: number, width: number, accent: Color3): (Frame, TextLabel)
	local card = Instance.new("Frame")
	card.Name = "Card_" .. title
	card.Position = UDim2.new(0, xOffset, 0, 0)
	card.Size = UDim2.new(0, width, 1, 0)
	card.BackgroundColor3 = BG_ELEVATED
	card.BorderSizePixel = 0
	card.ZIndex = 13
	card.Parent = parent
	roundedCorner(card, 10)

	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Position = UDim2.new(0, 0, 1, -3)
	accentBar.Size = UDim2.new(1, 0, 0, 3)
	accentBar.BackgroundColor3 = accent
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 14
	accentBar.Parent = card

	local titleLabel = newText(card, "Title")
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 1, -36)
	titleLabel.Size = UDim2.new(1, -12, 0, 26)
	titleLabel.Text = title
	titleLabel.TextColor3 = TEXT_MUTED
	titleLabel.TextSize = 24
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 14

	local value = newText(card, "Value")
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.new(0.5, 0, 0.4, 0)
	value.Size = UDim2.new(1, -12, 0, 84)
	value.Text = "0"
	value.TextColor3 = TEXT_PURE
	value.TextSize = 68
	value.Font = Enum.Font.GothamBlack
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.ZIndex = 14

	return card, value
end

local function buildModal(gui: ScreenGui)
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = gui

	-- Botão invisível full-screen pra capturar click-out
	local overlayClick = Instance.new("TextButton")
	overlayClick.Size = UDim2.fromScale(1, 1)
	overlayClick.BackgroundTransparency = 1
	overlayClick.Text = ""
	overlayClick.AutoButtonColor = false
	overlayClick.ZIndex = 10
	overlayClick.Parent = overlay

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Position é reatribuído via _applyResponsiveLayout() baseado no safe
	-- viewport atual — centraliza no espaço visível (não na tela física).
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, MODAL_DESIGN_WIDTH, 0, MODAL_DESIGN_HEIGHT)
	panel.BackgroundColor3 = BG_DEEP
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = overlay
	roundedCorner(panel, 20)
	stroke(panel, Color3.fromRGB(0, 0, 0), 3, 0)

	-- UIScale pro fit-to-viewport: geometria fixa em design coords, escala
	-- inteira via ResponsiveLayout. Tween de Size no pop-in continua valendo
	-- (UIScale é multiplicativo, não atrapalha animação).
	StatsPanelController._panelScale = ResponsiveLayout.EnsureUiScale(panel, "ResponsiveScale")

	-- Impede que clicks no panel "vazem" pro overlayClick. Parent no próprio
	-- overlay depois do overlayClick garante que ele fique por cima em Z.
	local panelBlocker = Instance.new("TextButton")
	panelBlocker.Size = UDim2.fromScale(1, 1)
	panelBlocker.BackgroundTransparency = 1
	panelBlocker.Text = ""
	panelBlocker.AutoButtonColor = false
	panelBlocker.ZIndex = 11
	panelBlocker.Parent = panel

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 60)
	header.Position = UDim2.new(0, 16, 0, 16)
	header.BackgroundTransparency = 1
	header.ZIndex = 12
	header.Parent = panel

	local title = newText(header, "Title")
	title.Size = UDim2.fromScale(1, 1)
	title.Text = "PLAYER STATS"
	title.TextColor3 = TEXT_PURE
	title.TextSize = 48
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 12

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, 0, 0.5, 0)
	close.Size = UDim2.new(0, 56, 0, 56)
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.Text = "X"
	close.TextColor3 = TEXT_PRIMARY
	close.TextSize = 44
	close.Font = Enum.Font.GothamBold
	close.AutoButtonColor = true
	close.ZIndex = 12
	close.Parent = header

	-- Rank section
	local rankSection = Instance.new("Frame")
	rankSection.Name = "RankSection"
	rankSection.Position = UDim2.new(0, 24, 0, 92)
	rankSection.Size = UDim2.new(1, -48, 0, 160)
	rankSection.BackgroundColor3 = BG_SURFACE
	rankSection.BorderSizePixel = 0
	rankSection.ZIndex = 12
	rankSection.Parent = panel
	roundedCorner(rankSection, 16)

	local rankIcon = Instance.new("ImageLabel")
	rankIcon.Name = "RankIcon"
	rankIcon.AnchorPoint = Vector2.new(0, 0.5)
	rankIcon.Position = UDim2.new(0, 20, 0.5, 0)
	rankIcon.Size = UDim2.new(0, 140, 0, 140)
	rankIcon.BackgroundTransparency = 1
	rankIcon.ScaleType = Enum.ScaleType.Fit
	rankIcon.ZIndex = 13
	rankIcon.Parent = rankSection

	-- Fallback text quando Unranked (sem ícone)
	local rankIconFallback = newText(rankSection, "IconFallback")
	rankIconFallback.AnchorPoint = Vector2.new(0, 0.5)
	rankIconFallback.Position = UDim2.new(0, 20, 0.5, 0)
	rankIconFallback.Size = UDim2.new(0, 140, 0, 140)
	rankIconFallback.Text = "—"
	rankIconFallback.TextColor3 = TEXT_DIM
	rankIconFallback.TextSize = 72
	rankIconFallback.Font = Enum.Font.GothamBlack
	rankIconFallback.TextXAlignment = Enum.TextXAlignment.Center
	rankIconFallback.ZIndex = 13
	rankIconFallback.Visible = false

	local rankName = newText(rankSection, "RankName")
	rankName.Position = UDim2.new(0, 176, 0, 18)
	rankName.Size = UDim2.new(1, -460, 0, 60)
	rankName.Text = "Unranked"
	rankName.TextColor3 = TEXT_PURE
	rankName.TextSize = 52
	rankName.Font = Enum.Font.GothamBlack
	rankName.ZIndex = 13

	local rankPointsText = newText(rankSection, "FPText")
	rankPointsText.AnchorPoint = Vector2.new(1, 0)
	rankPointsText.Position = UDim2.new(1, -20, 0, 22)
	rankPointsText.Size = UDim2.new(0, 260, 0, 54)
	rankPointsText.Text = "0 FP"
	rankPointsText.TextColor3 = FP_GOLD
	rankPointsText.TextSize = 44
	rankPointsText.Font = Enum.Font.GothamBold
	rankPointsText.TextXAlignment = Enum.TextXAlignment.Right
	rankPointsText.ZIndex = 13

	local rankBar = Instance.new("Frame")
	rankBar.Name = "Bar"
	rankBar.Position = UDim2.new(0, 176, 0, 90)
	rankBar.Size = UDim2.new(1, -196, 0, 20)
	rankBar.BackgroundColor3 = BG_ELEVATED
	rankBar.BorderSizePixel = 0
	rankBar.ZIndex = 13
	rankBar.Parent = rankSection
	roundedCorner(rankBar, 10)

	local rankBarFill = Instance.new("Frame")
	rankBarFill.Name = "Fill"
	rankBarFill.Size = UDim2.fromScale(0, 1)
	rankBarFill.BackgroundColor3 = FP_GOLD
	rankBarFill.BorderSizePixel = 0
	rankBarFill.ZIndex = 14
	rankBarFill.Parent = rankBar
	roundedCorner(rankBarFill, 10)

	local rankProgressText = newText(rankSection, "Progress")
	rankProgressText.Position = UDim2.new(0, 176, 0, 118)
	rankProgressText.Size = UDim2.new(1, -196, 0, 36)
	rankProgressText.Text = "0 / 100 → Bronze I"
	rankProgressText.TextColor3 = TEXT_MUTED
	rankProgressText.TextSize = 28
	rankProgressText.Font = Enum.Font.Gotham
	rankProgressText.ZIndex = 13

	-- Level section (logo após rank pra aproximar as duas barras de progresso)
	local levelSection = Instance.new("Frame")
	levelSection.Name = "LevelSection"
	levelSection.Position = UDim2.new(0, 24, 0, 268)
	levelSection.Size = UDim2.new(1, -48, 0, 116)
	levelSection.BackgroundColor3 = BG_SURFACE
	levelSection.BorderSizePixel = 0
	levelSection.ZIndex = 12
	levelSection.Parent = panel
	roundedCorner(levelSection, 16)

	local levelLabel = newText(levelSection, "Level")
	levelLabel.Position = UDim2.new(0, 20, 0, 14)
	levelLabel.Size = UDim2.new(0, 300, 0, 48)
	levelLabel.Text = "Level 1"
	levelLabel.TextColor3 = TEXT_PURE
	levelLabel.TextSize = 38
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.ZIndex = 13

	local xpText = newText(levelSection, "XpText")
	xpText.AnchorPoint = Vector2.new(1, 0)
	xpText.Position = UDim2.new(1, -20, 0, 18)
	xpText.Size = UDim2.new(0, 320, 0, 42)
	xpText.Text = "0 / 100 XP"
	xpText.TextColor3 = TEXT_MUTED
	xpText.TextSize = 30
	xpText.Font = Enum.Font.GothamBold
	xpText.TextXAlignment = Enum.TextXAlignment.Right
	xpText.ZIndex = 13

	local xpBar = Instance.new("Frame")
	xpBar.Name = "XpBar"
	xpBar.Position = UDim2.new(0, 20, 0, 72)
	xpBar.Size = UDim2.new(1, -40, 0, 26)
	xpBar.BackgroundColor3 = BG_ELEVATED
	xpBar.BorderSizePixel = 0
	xpBar.ZIndex = 13
	xpBar.Parent = levelSection
	roundedCorner(xpBar, 13)

	-- Series row (conditional) — posicionada depois do level, acima dos stats
	local seriesRow = Instance.new("Frame")
	seriesRow.Name = "SeriesRow"
	seriesRow.Position = UDim2.new(0, 24, 0, 400)
	seriesRow.Size = UDim2.new(1, -48, 0, 70)
	seriesRow.BackgroundColor3 = BG_ELEVATED
	seriesRow.BorderSizePixel = 0
	seriesRow.Visible = false
	seriesRow.ZIndex = 12
	seriesRow.Parent = panel
	roundedCorner(seriesRow, 12)

	local seriesLabel = newText(seriesRow, "Label")
	seriesLabel.Position = UDim2.new(0, 20, 0, 0)
	seriesLabel.Size = UDim2.new(1, -180, 1, 0)
	seriesLabel.Text = "PROMOTION SERIES"
	seriesLabel.TextColor3 = SUCCESS
	seriesLabel.TextSize = 30
	seriesLabel.Font = Enum.Font.GothamBold
	seriesLabel.ZIndex = 13

	local dotsContainer = Instance.new("Frame")
	dotsContainer.Name = "Dots"
	dotsContainer.AnchorPoint = Vector2.new(1, 0.5)
	dotsContainer.Position = UDim2.new(1, -20, 0.5, 0)
	dotsContainer.Size = UDim2.new(0, 120, 0, 28)
	dotsContainer.BackgroundTransparency = 1
	dotsContainer.ZIndex = 13
	dotsContainer.Parent = seriesRow

	local dotsList = Instance.new("UIListLayout")
	dotsList.FillDirection = Enum.FillDirection.Horizontal
	dotsList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dotsList.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsList.Padding = UDim.new(0, 10)
	dotsList.Parent = dotsContainer

	local dots: { Frame } = {}
	for i = 1, Constants.Rank.SeriesLength do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.fromOffset(28, 28)
		dot.BackgroundColor3 = BG_SURFACE
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i
		dot.ZIndex = 14
		dot.Parent = dotsContainer
		roundedCorner(dot, 14)
		stroke(dot, TEXT_DIM, 1, 0)
		table.insert(dots, dot)
	end

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Name = "Fill"
	xpBarFill.Size = UDim2.fromScale(0, 1)
	xpBarFill.BackgroundColor3 = SUCCESS
	xpBarFill.BorderSizePixel = 0
	xpBarFill.ZIndex = 14
	xpBarFill.Parent = xpBar
	roundedCorner(xpBarFill, 9)

	-- Combat stats cards
	local statsRow = Instance.new("Frame")
	statsRow.Name = "StatsRow"
	statsRow.Position = UDim2.new(0, 24, 0, 486)
	statsRow.Size = UDim2.new(1, -48, 0, 170)
	statsRow.BackgroundTransparency = 1
	statsRow.ZIndex = 12
	statsRow.Parent = panel

	local totalW = MODAL_DESIGN_WIDTH - 48 -- panel width - padding
	local gap = 16
	local cardW = math.floor((totalW - gap * 2) / 3)

	local _, killsValue = buildStatCard(statsRow, "KILLS", 0, cardW, SUCCESS)
	local _, deathsValue = buildStatCard(statsRow, "DEATHS", cardW + gap, cardW, ERROR)
	local _, kdValue = buildStatCard(statsRow, "K/D", (cardW + gap) * 2, cardW, INFO)

	-- Footer hint
	local footer = newText(panel, "Footer")
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -20)
	footer.Size = UDim2.new(1, -48, 0, 28)
	footer.Text = "Press ESC or click outside to close"
	footer.TextColor3 = TEXT_DIM
	footer.TextSize = 22
	footer.Font = Enum.Font.Gotham
	footer.TextXAlignment = Enum.TextXAlignment.Center
	footer.ZIndex = 12

	StatsPanelController._modalRoot = panel
	StatsPanelController._modalOverlay = overlay
	StatsPanelController._rankIcon = rankIcon
	StatsPanelController._rankName = rankName
	StatsPanelController._rankPointsText = rankPointsText
	StatsPanelController._rankBar = rankBar
	StatsPanelController._rankBarFill = rankBarFill
	StatsPanelController._rankProgressText = rankProgressText
	StatsPanelController._seriesRow = seriesRow
	StatsPanelController._seriesText = seriesLabel
	StatsPanelController._seriesDots = dots
	StatsPanelController._levelLabel = levelLabel
	StatsPanelController._xpBarFill = xpBarFill
	StatsPanelController._xpText = xpText
	StatsPanelController._killsValue = killsValue
	StatsPanelController._deathsValue = deathsValue
	StatsPanelController._kdValue = kdValue

	close.MouseButton1Click:Connect(function()
		StatsPanelController:Close()
	end)
	overlayClick.MouseButton1Click:Connect(function()
		StatsPanelController:Close()
	end)

	-- Helper pra refs Unranked (usa fallback text)
	StatsPanelController._setRankIconAsset = function(asset: string?)
		if asset then
			rankIcon.Image = asset
			rankIcon.Visible = true
			rankIconFallback.Visible = false
		else
			rankIcon.Visible = false
			rankIconFallback.Visible = true
		end
	end
end

-- Render ------------------------------------------------------------------

function StatsPanelController:_render()
	local snap = self._latestSnapshot
	if not snap or not self._modalRoot then
		return
	end

	local rank = snap.rank
	local stats = snap.stats or {}
	local rankPoints = stats.rankPoints or 0
	local tierIdx = (rank and rank.tier) or 1
	local rankName, rankColor = Rank.format(rank)

	-- Rank section
	if self._rankName then
		self._rankName.Text = rankName
		self._rankName.TextColor3 = rankColor
	end
	if self._setRankIconAsset then
		self._setRankIconAsset(Rank.getIconAsset(tierIdx))
	end

	local pointsInTier, pointsToNext, pct = computeTierProgress(rankPoints, tierIdx)
	if self._rankPointsText then
		-- FP mostrado é o progresso dentro do tier (0-100), não o absoluto.
		-- Ex: Bronze I com 187 abs = "87 FP" (87 pontos dentro de Bronze I).
		-- Champion é terminal — mostra absoluto (sem next tier pra referenciar).
		self._rankPointsText.Text = string.format("%d FP", pointsInTier)
	end
	if self._rankBarFill then
		self._rankBarFill.Size = UDim2.fromScale(pct, 1)
	end
	if self._rankProgressText then
		if tierIdx >= CHAMPION_TIER_IDX then
			self._rankProgressText.Text = string.format("%d FP · max tier", rankPoints)
		else
			local nextName = nextTierName(tierIdx) or "Next tier"
			self._rankProgressText.Text = string.format("%d / %d → %s", pointsInTier, pointsToNext, nextName)
		end
	end

	-- Series
	local seriesKind = stats.seriesKind
	local seriesProgress = stats.seriesProgress or 0
	if self._seriesRow and self._seriesDots and self._seriesText then
		local isActive = seriesKind == "promo" or seriesKind == "demote"
		self._seriesRow.Visible = isActive
		if isActive then
			local isPromo = seriesKind == "promo"
			self._seriesText.Text = isPromo and "PROMOTION SERIES" or "DEMOTION SERIES"
			self._seriesText.TextColor3 = isPromo and SUCCESS or ERROR
			local fillColor = isPromo and SUCCESS or ERROR
			for i, dot in ipairs(self._seriesDots) do
				local filled = i <= seriesProgress
				dot.BackgroundColor3 = filled and fillColor or BG_SURFACE
			end
		end
	end

	-- Level / XP
	if self._levelLabel and typeof(snap.level) == "number" then
		self._levelLabel.Text = string.format("Level %d", snap.level)
	end
	if self._xpBarFill and self._xpText and typeof(snap.xp) == "number" and typeof(snap.xpForNextLevel) == "number" then
		local forNext = snap.xpForNextLevel
		local xpPct = forNext > 0 and math.clamp(snap.xp / forNext, 0, 1) or 0
		self._xpBarFill.Size = UDim2.fromScale(xpPct, 1)
		self._xpText.Text = string.format("%d / %d XP", snap.xp, forNext)
	end

	-- Combat stats
	local kills = stats.kills or 0
	local deaths = stats.deaths or 0
	if self._killsValue then
		self._killsValue.Text = tostring(kills)
	end
	if self._deathsValue then
		self._deathsValue.Text = tostring(deaths)
	end
	if self._kdValue then
		-- K/D clássico: se deaths=0, mostra o número de kills (evita div/0 e
		-- reflete o sentimento de "inédito"/"perfeito"). Senão, 2 casas decimais.
		local kdText: string
		if deaths == 0 then
			kdText = kills == 0 and "0.00" or string.format("%d.00", kills)
		else
			kdText = string.format("%.2f", kills / deaths)
		end
		self._kdValue.Text = kdText
	end
end

-- Lifecycle ---------------------------------------------------------------

function StatsPanelController:_applyResponsiveLayout()
	local metrics = ResponsiveLayout.GetViewportMetrics()

	-- Modal: GetViewportFitScale garante que o panel cabe em 94% da largura
	-- safe e no default dinâmico de altura (0.86 em phoneLandscape, 0.9 em
	-- shortHeight, 0.94 normal) — previne corte de bottom em phones landscape
	-- onde inset da status bar come mais altura. min 0.35, max 1.
	if self._panelScale then
		local panelScale = ResponsiveLayout.GetViewportFitScale(
			metrics,
			MODAL_DESIGN_WIDTH,
			MODAL_DESIGN_HEIGHT,
			0.94,
			nil,
			0.35,
			1
		)
		self._panelScale.Scale = panelScale
	end

	if self._modalRoot then
		-- Posiciona no centro do safe viewport (respeita inset top/bottom).
		self._modalRoot.Position = ResponsiveLayout.GetSafeCenterPosition(metrics)
	end
end

function StatsPanelController:Open()
	if self._isOpen or not self._modalOverlay or not self._modalRoot then
		return
	end
	self._isOpen = true
	self:_render()
	-- Reaplica layout antes de abrir: se o viewport mudou enquanto o painel
	-- estava fechado (rotate de device), scale/position tá stale.
	self:_applyResponsiveLayout()
	self._modalOverlay.Visible = true
	self._modalOverlay.BackgroundTransparency = 1
	TweenService:Create(
		self._modalOverlay,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.45 }
	):Play()
	-- Pop-in do painel (DESIGN.md: Back easing em pop-ins, ~200ms).
	-- Tween em design coords — UIScale aplica o fit-to-viewport por fora.
	self._modalRoot.Size = UDim2.new(0, MODAL_POP_START_WIDTH, 0, MODAL_POP_START_HEIGHT)
	TweenService:Create(
		self._modalRoot,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, MODAL_DESIGN_WIDTH, 0, MODAL_DESIGN_HEIGHT) }
	):Play()
end

function StatsPanelController:Close()
	if not self._isOpen or not self._modalOverlay then
		return
	end
	self._isOpen = false
	local overlay = self._modalOverlay
	TweenService:Create(
		overlay,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	task.delay(0.12, function()
		if not self._isOpen and overlay then
			overlay.Visible = false
		end
	end)
end

function StatsPanelController:Toggle()
	if self._isOpen then
		self:Close()
	else
		self:Open()
	end
end

function StatsPanelController:Init(_controllers: { [string]: any }) end

function StatsPanelController:Start()
	local modalGui = Instance.new("ScreenGui")
	modalGui.Name = "BrawlStatsPanel"
	modalGui.ResetOnSpawn = false
	modalGui.IgnoreGuiInset = true
	-- Sibling: filhos sempre acima dos pais na render order, independente do
	-- valor absoluto de ZIndex. Previne que cards (Z default) fiquem atras do
	-- panelBlocker (Z 11) em places com ZIndexBehavior=Global.
	modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	modalGui.DisplayOrder = 50
	modalGui.Parent = playerGui
	self._modalGui = modalGui

	buildModal(modalGui)

	-- Aplica scale inicial + reaplica em resize (rotate de device, join mid-game
	-- em outro aspect ratio, etc.). Camera pode ser recriada em alguns casos —
	-- reanexar via CurrentCameraChanged pra não perder a conexão.
	self:_applyResponsiveLayout()

	local function attachCameraWatcher()
		if self._viewportConn then
			self._viewportConn:Disconnect()
			self._viewportConn = nil
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		self._viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_applyResponsiveLayout()
		end)
	end

	attachCameraWatcher()
	self._cameraChangedConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		attachCameraWatcher()
		self:_applyResponsiveLayout()
	end)

	-- ESC fecha o painel
	self._inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and self._isOpen then
			self:Close()
		end
	end)

	local stateRemote = Remotes.GetStateRemote()
	if not stateRemote then
		warn("[StatsPanelController] BrawlState remote não encontrado.")
		return
	end
	stateRemote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		-- Faz merge raso: state snapshots parciais (ex: só damagePercent em arena)
		-- não podem apagar level/xp/rank/stats que já temos em cache.
		local cache = self._latestSnapshot
		for key, value in pairs(snapshot) do
			cache[key] = value
		end
		-- Se saiu pro arena com painel aberto, fecha (gameplay não pode ser
		-- interrompido por overlay modal).
		if typeof(snapshot.state) == "string" and snapshot.state == Constants.PlayerState.InArena and self._isOpen then
			self:Close()
		end
		if self._isOpen then
			self:_render()
		end
	end)
end

return StatsPanelController
