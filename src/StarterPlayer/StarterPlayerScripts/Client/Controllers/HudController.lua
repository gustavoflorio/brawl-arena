--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Rank = require(sharedFolder:WaitForChild("Rank"))

local controllersFolder = script.Parent
local ArenaStockPanel = require(controllersFolder:WaitForChild("ArenaStockPanel"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FLAG_NAME = "NewArenaHudEnabled"

local TRANSITION_FADE_SECONDS = 0.15

local HudController = {}

-- Shared state
HudController._stockPanel = nil
HudController._currentState = nil :: string?
HudController._flagEnabled = true
HudController._controllers = nil :: { [string]: any }?

-- New HUD refs
HudController._lobbyProgressPanel = nil :: Frame?
-- Rank badge é TextButton: clicável, abre o StatsPanelController.
HudController._rankBadge = nil :: TextButton?
HudController._rankLabel = nil :: TextLabel?
HudController._rankAccent = nil :: Frame?
HudController._levelLabel = nil :: TextLabel?
HudController._xpBarFill = nil :: Frame?
HudController._xpText = nil :: TextLabel?
HudController._insetGui = nil :: ScreenGui?
HudController._fullGui = nil :: ScreenGui?

-- Legacy HUD refs (feature flag = false path)
HudController._legacyDamageLabel = nil :: TextLabel?
HudController._legacyStateLabel = nil :: TextLabel?
HudController._legacyLevelLabel = nil :: TextLabel?
HudController._legacyRankLabel = nil :: TextLabel?
HudController._legacyXpFill = nil :: Frame?
HudController._legacyXpText = nil :: TextLabel?

local function readFlag(): boolean
	local value = Workspace:GetAttribute(FLAG_NAME)
	if value == nil then
		return true
	end
	return value == true
end

-- ================= NEW HUD BUILD =================

local function buildNewHud(self)
	local insetGui = Instance.new("ScreenGui")
	insetGui.Name = "BrawlHud_Inset"
	insetGui.ResetOnSpawn = false
	insetGui.IgnoreGuiInset = false
	insetGui.Parent = playerGui
	self._insetGui = insetGui

	local fullGui = Instance.new("ScreenGui")
	fullGui.Name = "BrawlHud_Full"
	fullGui.ResetOnSpawn = false
	fullGui.IgnoreGuiInset = true
	fullGui.Parent = playerGui
	self._fullGui = fullGui

	-- Rank badge (top-left, inset-respecting). TextButton pra poder clicar
	-- e abrir o StatsPanel; Text vazio + AutoButtonColor false pra visual
	-- ficar idêntico a um Frame (cor não pisca no hover).
	local rankBadge = Instance.new("TextButton")
	rankBadge.Name = "RankBadge"
	rankBadge.AnchorPoint = Vector2.new(0, 0)
	rankBadge.Position = UDim2.new(0, 16, 0, 16)
	rankBadge.Size = UDim2.new(0, 140, 0, 36)
	rankBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	rankBadge.BackgroundTransparency = 0.25
	rankBadge.BorderSizePixel = 0
	rankBadge.Text = ""
	rankBadge.AutoButtonColor = false
	rankBadge.Visible = false
	rankBadge.Parent = insetGui

	rankBadge.MouseButton1Click:Connect(function()
		local controllers = self._controllers
		local statsPanel = controllers and controllers.StatsPanelController
		if statsPanel and type(statsPanel.Toggle) == "function" then
			statsPanel:Toggle()
		end
	end)

	local rankCorner = Instance.new("UICorner")
	rankCorner.CornerRadius = UDim.new(0, 10)
	rankCorner.Parent = rankBadge

	local rankAccent = Instance.new("Frame")
	rankAccent.Name = "Accent"
	rankAccent.Size = UDim2.new(0, 4, 1, -12)
	rankAccent.Position = UDim2.new(0, 8, 0, 6)
	rankAccent.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	rankAccent.BorderSizePixel = 0
	rankAccent.Parent = rankBadge
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 2)
	accentCorner.Parent = rankAccent

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.Size = UDim2.new(1, -24, 1, 0)
	rankLabel.Position = UDim2.new(0, 20, 0, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = "Unranked"
	rankLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	rankLabel.TextSize = 14
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Parent = rankBadge

	self._rankBadge = rankBadge
	self._rankLabel = rankLabel
	self._rankAccent = rankAccent

	-- Level/XP panel (top-right, colado no topo do safe viewport).
	-- Y=0 + IgnoreGuiInset=false no insetGui faz ficar logo abaixo da
	-- status bar do sistema no mobile, sem gap adicional.
	local progressPanel = Instance.new("Frame")
	progressPanel.Name = "LevelXpPanel"
	progressPanel.AnchorPoint = Vector2.new(1, 0)
	progressPanel.Position = UDim2.new(1, -16, 0, 0)
	progressPanel.Size = UDim2.new(0, 220, 0, 60)
	progressPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	progressPanel.BackgroundTransparency = 0.25
	progressPanel.BorderSizePixel = 0
	progressPanel.Visible = false
	progressPanel.Parent = insetGui

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 10)
	progressCorner.Parent = progressPanel

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(1, -16, 0, 20)
	levelLabel.Position = UDim2.new(0, 8, 0, 6)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.TextSize = 15
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = progressPanel

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Name = "XpBg"
	xpBarBg.Size = UDim2.new(1, -16, 0, 10)
	xpBarBg.Position = UDim2.new(0, 8, 0, 28)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
	xpBarBg.BorderSizePixel = 0
	xpBarBg.Parent = progressPanel

	local xpBgCorner = Instance.new("UICorner")
	xpBgCorner.CornerRadius = UDim.new(1, 0)
	xpBgCorner.Parent = xpBarBg

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Name = "XpFill"
	xpBarFill.Size = UDim2.new(0, 0, 1, 0)
	xpBarFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	xpBarFill.BorderSizePixel = 0
	xpBarFill.Parent = xpBarBg

	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(1, 0)
	xpFillCorner.Parent = xpBarFill

	local xpText = Instance.new("TextLabel")
	xpText.Name = "XpText"
	xpText.Size = UDim2.new(1, -16, 0, 12)
	xpText.Position = UDim2.new(0, 8, 0, 42)
	xpText.BackgroundTransparency = 1
	xpText.Text = "0 / 100 XP"
	xpText.TextColor3 = Color3.fromRGB(200, 200, 220)
	xpText.TextSize = 10
	xpText.Font = Enum.Font.Gotham
	xpText.TextXAlignment = Enum.TextXAlignment.Left
	xpText.Parent = progressPanel

	self._lobbyProgressPanel = progressPanel
	self._levelLabel = levelLabel
	self._xpBarFill = xpBarFill
	self._xpText = xpText

	-- Damage é mostrado pelo DamageLabelController (world-space BillboardGui acima do char).
	-- Sem painel bottom-center no novo HUD — evita redundância + overlap com stock panel.

	-- Stock panel (inside fullGui so it ignores inset — bottom needs no inset protection)
	self._stockPanel = ArenaStockPanel.new(fullGui)
end

-- ================= LEGACY HUD BUILD =================

local function buildLegacyHud(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	self._insetGui = gui -- store for cleanup; legacy keeps old style
	self._fullGui = nil

	local damagePanel = Instance.new("Frame")
	damagePanel.AnchorPoint = Vector2.new(0.5, 1)
	damagePanel.Size = UDim2.new(0, 260, 0, 110)
	damagePanel.Position = UDim2.new(0.5, 0, 0.98, 0)
	damagePanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	damagePanel.BackgroundTransparency = 0.25
	damagePanel.BorderSizePixel = 0
	damagePanel.Parent = gui
	local damageCorner = Instance.new("UICorner")
	damageCorner.CornerRadius = UDim.new(0, 12)
	damageCorner.Parent = damagePanel

	local damage = Instance.new("TextLabel")
	damage.Size = UDim2.new(1, 0, 0.65, 0)
	damage.BackgroundTransparency = 1
	damage.Text = "0%"
	damage.TextColor3 = Color3.fromRGB(255, 255, 255)
	damage.TextScaled = true
	damage.Font = Enum.Font.GothamBold
	damage.Parent = damagePanel

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Size = UDim2.new(1, 0, 0.3, 0)
	stateLabel.Position = UDim2.new(0, 0, 0.68, 0)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Text = "Lobby"
	stateLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	stateLabel.TextScaled = true
	stateLabel.Font = Enum.Font.Gotham
	stateLabel.Parent = damagePanel

	local progressPanel = Instance.new("Frame")
	progressPanel.AnchorPoint = Vector2.new(0, 0)
	progressPanel.Position = UDim2.new(0, 16, 0, 16)
	progressPanel.Size = UDim2.new(0, 260, 0, 70)
	progressPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	progressPanel.BackgroundTransparency = 0.3
	progressPanel.BorderSizePixel = 0
	progressPanel.Parent = gui
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 10)
	progressCorner.Parent = progressPanel

	local levelRow = Instance.new("Frame")
	levelRow.Size = UDim2.new(1, -16, 0, 22)
	levelRow.Position = UDim2.new(0, 8, 0, 6)
	levelRow.BackgroundTransparency = 1
	levelRow.Parent = progressPanel

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(0.5, 0, 1, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.TextScaled = true
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = levelRow

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Size = UDim2.new(0.5, 0, 1, 0)
	rankLabel.Position = UDim2.new(0.5, 0, 0, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = "Unranked"
	rankLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	rankLabel.TextScaled = true
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextXAlignment = Enum.TextXAlignment.Right
	rankLabel.Parent = levelRow

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Size = UDim2.new(1, -16, 0, 16)
	xpBarBg.Position = UDim2.new(0, 8, 0, 34)
	xpBarBg.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
	xpBarBg.BorderSizePixel = 0
	xpBarBg.Parent = progressPanel
	local xpBgCorner = Instance.new("UICorner")
	xpBgCorner.CornerRadius = UDim.new(1, 0)
	xpBgCorner.Parent = xpBarBg

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Size = UDim2.new(0, 0, 1, 0)
	xpBarFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	xpBarFill.BorderSizePixel = 0
	xpBarFill.Parent = xpBarBg
	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(1, 0)
	xpFillCorner.Parent = xpBarFill

	local xpText = Instance.new("TextLabel")
	xpText.Size = UDim2.new(1, -16, 0, 14)
	xpText.Position = UDim2.new(0, 8, 0, 52)
	xpText.BackgroundTransparency = 1
	xpText.Text = "0 / 100 XP"
	xpText.TextColor3 = Color3.fromRGB(200, 200, 220)
	xpText.TextScaled = true
	xpText.Font = Enum.Font.Gotham
	xpText.Parent = progressPanel

	self._legacyDamageLabel = damage
	self._legacyStateLabel = stateLabel
	self._legacyLevelLabel = levelLabel
	self._legacyRankLabel = rankLabel
	self._legacyXpFill = xpBarFill
	self._legacyXpText = xpText
end

-- ================= CONTEXT SWITCHING =================

local function fadePanel(panel: GuiObject?, targetTransparency: number, seconds: number)
	if not panel then
		return
	end
	local tween = TweenService:Create(panel, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = targetTransparency,
	})
	tween:Play()
end

function HudController:_enterLobbyLayout()
	-- Lobby: progressPanel (level/xp) + rankBadge. Arena stock escondido.
	if self._stockPanel then
		self._stockPanel:Hide()
	end
	if self._lobbyProgressPanel then
		self._lobbyProgressPanel.Visible = true
		self._lobbyProgressPanel.BackgroundTransparency = 1
		fadePanel(self._lobbyProgressPanel, 0.25, TRANSITION_FADE_SECONDS)
	end
	if self._rankBadge then
		self._rankBadge.Visible = true
		self._rankBadge.BackgroundTransparency = 1
		fadePanel(self._rankBadge, 0.25, TRANSITION_FADE_SECONDS)
	end
end

function HudController:_enterArenaLayout()
	-- Arena: apenas stock panel (avatares). Dano mostrado pelo DamageLabelController.
	if self._lobbyProgressPanel then
		self._lobbyProgressPanel.Visible = false
	end
	if self._rankBadge then
		self._rankBadge.Visible = false
	end
	if self._stockPanel then
		self._stockPanel:Show()
	end
end

function HudController:_transitionTo(newState: string)
	if self._currentState == newState then
		return
	end
	local previousState = self._currentState
	self._currentState = newState

	if previousState then
		-- Fade out previous first
		if previousState == "InArena" then
			-- Stock panel é escondido no _enterLobbyLayout. Nada pra fadear aqui.
		else
			fadePanel(self._lobbyProgressPanel, 1, TRANSITION_FADE_SECONDS)
			fadePanel(self._rankBadge, 1, TRANSITION_FADE_SECONDS)
		end
		task.delay(TRANSITION_FADE_SECONDS, function()
			if self._currentState ~= newState then
				return
			end
			if newState == "InArena" then
				self:_enterArenaLayout()
			else
				self:_enterLobbyLayout()
			end
		end)
	else
		-- First entry, no fade-out needed
		if newState == "InArena" then
			self:_enterArenaLayout()
		else
			self:_enterLobbyLayout()
		end
	end
end

-- ================= STATE UPDATE (NEW HUD) =================

function HudController:_applyStateSnapshot(snapshot: { [string]: any })
	local state = snapshot.state
	if typeof(state) == "string" then
		self:_transitionTo(state == "InArena" and "InArena" or "Lobby")
	end

	if self._levelLabel and typeof(snapshot.level) == "number" then
		self._levelLabel.Text = string.format("Level %d", snapshot.level)
	end

	if self._xpBarFill and self._xpText and typeof(snapshot.xp) == "number" and typeof(snapshot.xpForNextLevel) == "number" then
		local forNext = snapshot.xpForNextLevel
		local pct = forNext > 0 and math.clamp(snapshot.xp / forNext, 0, 1) or 0
		self._xpBarFill.Size = UDim2.new(pct, 0, 1, 0)
		self._xpText.Text = string.format("%d / %d XP", snapshot.xp, forNext)
	end

	if self._rankLabel and self._rankAccent and typeof(snapshot.rank) == "table" then
		local name, color = Rank.format(snapshot.rank)
		self._rankLabel.Text = name
		self._rankLabel.TextColor3 = color
		self._rankAccent.BackgroundColor3 = color
	end
end

-- ================= LEGACY STATE UPDATE =================

function HudController:_applyLegacyStateSnapshot(snapshot: { [string]: any })
	if self._legacyDamageLabel and typeof(snapshot.damagePercent) == "number" then
		self._legacyDamageLabel.Text = string.format("%d%%", math.floor(snapshot.damagePercent))
	end
	if self._legacyStateLabel and typeof(snapshot.state) == "string" then
		self._legacyStateLabel.Text = snapshot.state == "InArena" and "Arena" or "Lobby"
	end
	if self._legacyLevelLabel and typeof(snapshot.level) == "number" then
		self._legacyLevelLabel.Text = string.format("Level %d", snapshot.level)
	end
	if self._legacyXpFill and self._legacyXpText and typeof(snapshot.xp) == "number" and typeof(snapshot.xpForNextLevel) == "number" then
		local pct = snapshot.xpForNextLevel > 0 and math.clamp(snapshot.xp / snapshot.xpForNextLevel, 0, 1) or 0
		self._legacyXpFill.Size = UDim2.new(pct, 0, 1, 0)
		self._legacyXpText.Text = string.format("%d / %d XP", snapshot.xp, snapshot.xpForNextLevel)
	end
	if self._legacyRankLabel and typeof(snapshot.rank) == "table" then
		local name, color = Rank.format(snapshot.rank)
		self._legacyRankLabel.Text = name
		self._legacyRankLabel.TextColor3 = color
	end
end

-- ================= ARENA STATE UPDATE =================

function HudController:_applyArenaSnapshot(arenaSnapshot: { [string]: any })
	if not self._stockPanel then
		return
	end
	local players = arenaSnapshot.players
	if typeof(players) ~= "table" then
		return
	end
	self._stockPanel:Update(players, player.UserId)
end

-- ================= LIFECYCLE =================

function HudController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function HudController:Start()
	self._flagEnabled = readFlag()

	if self._flagEnabled then
		buildNewHud(self)
	else
		buildLegacyHud(self)
	end

	-- Watch flag changes (rebuild on toggle)
	Workspace:GetAttributeChangedSignal(FLAG_NAME):Connect(function()
		local newFlag = readFlag()
		if newFlag == self._flagEnabled then
			return
		end
		self._flagEnabled = newFlag
		if self._insetGui then
			self._insetGui:Destroy()
			self._insetGui = nil
		end
		if self._fullGui then
			self._fullGui:Destroy()
			self._fullGui = nil
		end
		self._stockPanel = nil
		self._currentState = nil
		if self._flagEnabled then
			buildNewHud(self)
		else
			buildLegacyHud(self)
		end
	end)

	local stateRemote = Remotes.GetStateRemote()
	if not stateRemote then
		warn("[HudController] BrawlState remote não encontrado.")
		return
	end
	stateRemote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		if self._flagEnabled then
			self:_applyStateSnapshot(snapshot)
		else
			self:_applyLegacyStateSnapshot(snapshot)
		end
	end)

	local arenaRemote = Remotes.GetArenaRemote()
	if arenaRemote then
		arenaRemote.OnClientEvent:Connect(function(arenaSnapshot)
			if typeof(arenaSnapshot) ~= "table" then
				return
			end
			if self._flagEnabled then
				self:_applyArenaSnapshot(arenaSnapshot)
			end
		end)
	else
		warn("[HudController] BrawlArenaState remote não encontrado.")
	end
end

return HudController
