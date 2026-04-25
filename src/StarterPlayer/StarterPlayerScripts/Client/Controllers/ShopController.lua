--!strict

-- ShopController: monta ScreenGui da loja, escuta ProximityPrompts taggeados
-- como ShopKiosk, e faz transações de compra/equip via BrawlShop RemoteFunction.
--
-- Cria UI em runtime usando tokens do DESIGN.md (ver constantes COLORS/FONTS
-- no topo do arquivo). Motion contida em widgets (pulse, fade) — sem afetar tela.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Types = require(sharedFolder:WaitForChild("Types"))

type ClassCatalogEntry = Types.ClassCatalogEntry
type ShopCatalogPayload = Types.ShopCatalogPayload

-- DESIGN.md tokens (ver docs/DESIGN.md)
local COLOR_BG_DEEP = Color3.fromRGB(13, 15, 26)
local COLOR_BG_SURFACE = Color3.fromRGB(20, 24, 44)
local COLOR_BG_ELEVATED = Color3.fromRGB(28, 32, 56)
local COLOR_TEXT_PRIMARY = Color3.fromRGB(230, 232, 240)
local COLOR_TEXT_PURE = Color3.fromRGB(255, 255, 255)
local COLOR_TEXT_MUTED = Color3.fromRGB(160, 165, 184)
local COLOR_TEXT_DIM = Color3.fromRGB(120, 120, 140)
local COLOR_SUCCESS = Color3.fromRGB(74, 219, 122)
local COLOR_WARNING = Color3.fromRGB(255, 203, 43)
local COLOR_ERROR = Color3.fromRGB(255, 71, 87)
local COLOR_INFO = Color3.fromRGB(74, 158, 255)
local COLOR_OUTLINE = Color3.fromRGB(0, 0, 0)

local FONT_DISPLAY = Enum.Font.GothamBlack
local FONT_HEADING = Enum.Font.GothamBlack
local FONT_LABEL = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.Gotham

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local SHOP_TAG = Constants.Tags.ShopKiosk
local REASONS = Constants.Shop.BuyResultReasons
local ACTIONS = Constants.Shop.BuyActions

local ShopController = {}
ShopController._gui = nil :: ScreenGui?
ShopController._cardsContainer = nil :: Frame?
ShopController._balanceLabel = nil :: TextLabel?
ShopController._statusLabel = nil :: TextLabel?
ShopController._modalFrame = nil :: Frame?
ShopController._dimBackdrop = nil :: Frame?
ShopController._open = false
ShopController._busy = false
ShopController._cards = {} :: { [string]: any }
ShopController._promptConnections = {} :: { [Instance]: { RBXScriptConnection } }
ShopController._lastCatalog = nil :: ShopCatalogPayload?

-- ===== UI helpers =====

local function corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent: Instance, p: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, p)
	pad.PaddingBottom = UDim.new(0, p)
	pad.PaddingLeft = UDim.new(0, p)
	pad.PaddingRight = UDim.new(0, p)
	pad.Parent = parent
	return pad
end

-- ===== Card creation =====

local function createCard(entry: ClassCatalogEntry): Frame
	local card = Instance.new("Frame")
	card.Name = entry.id
	card.Size = UDim2.new(1, -16, 0, 132)
	card.BackgroundColor3 = COLOR_BG_ELEVATED
	card.BorderSizePixel = 0
	corner(card, 12)
	stroke(card, COLOR_OUTLINE, 2)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card

	-- Linha 1: nome + state badge
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 32)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundTransparency = 1
	header.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_DISPLAY
	nameLabel.Text = string.upper(entry.displayName)
	nameLabel.TextSize = 28
	nameLabel.TextColor3 = COLOR_TEXT_PURE
	nameLabel.TextStrokeColor3 = COLOR_OUTLINE
	nameLabel.TextStrokeTransparency = 0.6
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Parent = header

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, 0, 0.5, 0)
	badge.Size = UDim2.new(0, 110, 0, 26)
	badge.BackgroundColor3 = COLOR_BG_SURFACE
	badge.BorderSizePixel = 0
	badge.Font = FONT_LABEL
	badge.TextSize = 13
	badge.TextColor3 = COLOR_TEXT_DIM
	badge.Text = ""
	corner(badge, 6)
	badge.Parent = header

	-- Linha 2: descrição
	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.Position = UDim2.new(0, 0, 0, 38)
	desc.Size = UDim2.new(1, 0, 0, 36)
	desc.BackgroundTransparency = 1
	desc.Font = FONT_BODY
	desc.Text = entry.description
	desc.TextSize = 14
	desc.TextColor3 = COLOR_TEXT_MUTED
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Parent = card

	-- Linha 3: action button (right-aligned)
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionBtn"
	actionBtn.AnchorPoint = Vector2.new(1, 1)
	actionBtn.Position = UDim2.new(1, 0, 1, 0)
	actionBtn.Size = UDim2.new(0, 180, 0, 40)
	actionBtn.BackgroundColor3 = COLOR_BG_SURFACE
	actionBtn.BorderSizePixel = 0
	actionBtn.AutoButtonColor = false
	actionBtn.Font = FONT_LABEL
	actionBtn.Text = ""
	actionBtn.TextSize = 16
	actionBtn.TextColor3 = COLOR_TEXT_PRIMARY
	corner(actionBtn, 8)
	stroke(actionBtn, COLOR_OUTLINE, 1)
	actionBtn.Parent = card

	return card
end

local function setCardState(card: Frame, entry: ClassCatalogEntry, balance: number, busy: boolean)
	local header = card:FindFirstChild("Header")
	local badge = header and header:FindFirstChild("Badge") :: any
	local btn = card:FindFirstChild("ActionBtn") :: any
	if not badge or not btn or not badge:IsA("TextLabel") or not btn:IsA("TextButton") then
		return
	end

	if entry.equipped then
		badge.Text = "EQUIPPED"
		badge.TextColor3 = COLOR_SUCCESS
		badge.BackgroundColor3 = COLOR_BG_DEEP
		btn.Text = "EQUIPPED"
		btn.TextColor3 = COLOR_TEXT_DIM
		btn.BackgroundColor3 = COLOR_BG_DEEP
		btn.AutoButtonColor = false
		btn.Active = false
	elseif entry.owned then
		badge.Text = "OWNED"
		badge.TextColor3 = COLOR_INFO
		badge.BackgroundColor3 = COLOR_BG_DEEP
		btn.Text = "EQUIP"
		btn.TextColor3 = COLOR_TEXT_PURE
		btn.BackgroundColor3 = COLOR_INFO
		btn.AutoButtonColor = true
		btn.Active = not busy
	else
		badge.Text = "LOCKED"
		badge.TextColor3 = COLOR_TEXT_DIM
		badge.BackgroundColor3 = COLOR_BG_DEEP
		if balance >= entry.price then
			btn.Text = string.format("BUY  %d", entry.price)
			btn.TextColor3 = COLOR_TEXT_PURE
			btn.BackgroundColor3 = COLOR_WARNING
			btn.AutoButtonColor = true
			btn.Active = not busy
		else
			btn.Text = string.format("NEED %d MORE", entry.price - balance)
			btn.TextColor3 = COLOR_TEXT_DIM
			btn.BackgroundColor3 = COLOR_BG_DEEP
			btn.AutoButtonColor = false
			btn.Active = false
		end
	end
end

-- ===== Modal layout =====

local function buildGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	gui.Enabled = false

	-- Dim backdrop
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = gui

	-- Modal panel
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.Size = UDim2.new(0, 540, 0, 540)
	modal.BackgroundColor3 = COLOR_BG_SURFACE
	modal.BorderSizePixel = 0
	modal.Parent = gui
	corner(modal, 20)
	stroke(modal, COLOR_OUTLINE, 3)

	local aspect = Instance.new("UISizeConstraint")
	aspect.MaxSize = Vector2.new(560, 600)
	aspect.MinSize = Vector2.new(320, 360)
	aspect.Parent = modal

	padding(modal, 20)

	-- Header: title + balance + close
	local headerRow = Instance.new("Frame")
	headerRow.Name = "Header"
	headerRow.Size = UDim2.new(1, 0, 0, 44)
	headerRow.Position = UDim2.new(0, 0, 0, 0)
	headerRow.BackgroundTransparency = 1
	headerRow.Parent = modal

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.5, 0, 1, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = FONT_DISPLAY
	title.Text = "SHOP"
	title.TextSize = 36
	title.TextColor3 = COLOR_TEXT_PURE
	title.TextStrokeColor3 = COLOR_OUTLINE
	title.TextStrokeTransparency = 0.4
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = headerRow

	local balance = Instance.new("TextLabel")
	balance.Name = "Balance"
	balance.AnchorPoint = Vector2.new(1, 0.5)
	balance.Position = UDim2.new(1, -56, 0.5, 0)
	balance.Size = UDim2.new(0, 200, 0, 36)
	balance.BackgroundColor3 = COLOR_BG_DEEP
	balance.BorderSizePixel = 0
	balance.Font = FONT_LABEL
	balance.Text = "0  COINS"
	balance.TextSize = 18
	balance.TextColor3 = COLOR_WARNING
	balance.TextXAlignment = Enum.TextXAlignment.Center
	corner(balance, 6)
	stroke(balance, COLOR_OUTLINE, 1)
	balance.Parent = headerRow

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, 0, 0.5, 0)
	close.Size = UDim2.new(0, 44, 0, 44)
	close.BackgroundColor3 = COLOR_BG_DEEP
	close.BorderSizePixel = 0
	close.Font = FONT_HEADING
	close.Text = "X"
	close.TextSize = 20
	close.TextColor3 = COLOR_TEXT_PRIMARY
	corner(close, 8)
	stroke(close, COLOR_OUTLINE, 1)
	close.Parent = headerRow

	-- Status row (mensagens de erro/feedback)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 22)
	status.Position = UDim2.new(0, 0, 0, 50)
	status.BackgroundTransparency = 1
	status.Font = FONT_BODY
	status.Text = ""
	status.TextSize = 14
	status.TextColor3 = COLOR_TEXT_MUTED
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = modal

	-- Cards container (scrolling pra robustez se vier mais classes)
	local cards = Instance.new("ScrollingFrame")
	cards.Name = "Cards"
	cards.Size = UDim2.new(1, 0, 1, -82)
	cards.Position = UDim2.new(0, 0, 0, 76)
	cards.BackgroundTransparency = 1
	cards.BorderSizePixel = 0
	cards.CanvasSize = UDim2.new()
	cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cards.ScrollBarThickness = 4
	cards.ScrollBarImageColor3 = COLOR_TEXT_DIM
	cards.Parent = modal

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = cards

	gui.Parent = playerGui

	close.Activated:Connect(function()
		ShopController:Close()
	end)
	dim.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			ShopController:Close()
		end
	end)

	return gui
end

-- ===== Network =====

function ShopController:_invokeShop(request: any): any
	local remote = Remotes.GetShopRemote()
	if not remote then
		return { success = false, reason = REASONS.UnknownClass }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(request)
	end)
	if not ok then
		warn("[ShopController] InvokeServer failed:", result)
		return { success = false, reason = REASONS.UnknownClass }
	end
	return result
end

function ShopController:_fetchCatalog(): ShopCatalogPayload?
	local result = self:_invokeShop({ action = ACTIONS.GetCatalog })
	if typeof(result) == "table" and typeof(result.classes) == "table" then
		return result :: ShopCatalogPayload
	end
	return nil
end

-- ===== Render =====

function ShopController:_setStatus(text: string, color: Color3?)
	if not self._statusLabel then
		return
	end
	self._statusLabel.Text = text
	self._statusLabel.TextColor3 = color or COLOR_TEXT_MUTED
end

local REASON_MESSAGES: { [string]: string } = {
	[REASONS.AlreadyOwned] = "You already own this class.",
	[REASONS.InsufficientFunds] = "Not enough coins.",
	[REASONS.UnknownClass] = "Unknown class.",
	[REASONS.InTransaction] = "Wait for the previous transaction...",
	[REASONS.NotInLobby] = "Return to the lobby to use the shop.",
}

function ShopController:_render(catalog: ShopCatalogPayload)
	self._lastCatalog = catalog
	if self._balanceLabel then
		self._balanceLabel.Text = string.format("%d  COINS", catalog.balance)
	end
	if not self._cardsContainer then
		return
	end

	-- Cria/atualiza cards. Reutiliza cards existentes pelo Id (preserva Tween state).
	local seenIds: { [string]: boolean } = {}
	for layoutOrder, entry in ipairs(catalog.classes) do
		seenIds[entry.id] = true
		local card = self._cards[entry.id]
		if not card then
			card = createCard(entry)
			card.LayoutOrder = layoutOrder
			card.Parent = self._cardsContainer
			self._cards[entry.id] = card

			local btn = card:FindFirstChild("ActionBtn") :: TextButton
			btn.Activated:Connect(function()
				ShopController:_onCardAction(entry.id)
			end)
		else
			card.LayoutOrder = layoutOrder
		end
		setCardState(card, entry, catalog.balance, self._busy)
	end

	-- Cleanup: cards de classes que sumiram (não deveria acontecer, mas seguro).
	for id, card in pairs(self._cards) do
		if not seenIds[id] then
			card:Destroy()
			self._cards[id] = nil
		end
	end
end

function ShopController:_pulseCard(classId: string, color: Color3)
	local card = self._cards[classId]
	if not card then
		return
	end
	local original = card.BackgroundColor3
	local tween = TweenService:Create(
		card,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = color }
	)
	tween:Play()
	task.delay(0.18, function()
		if card and card.Parent then
			TweenService:Create(
				card,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundColor3 = original }
			):Play()
		end
	end)
end

function ShopController:_shakeCard(classId: string)
	local card = self._cards[classId]
	if not card then
		return
	end
	local origPos = card.Position
	local offsets = { 6, -8, 5, -3, 0 }
	for i, offset in ipairs(offsets) do
		task.delay((i - 1) * 0.04, function()
			if card and card.Parent then
				card.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset + offset, origPos.Y.Scale, origPos.Y.Offset)
			end
		end)
	end
	task.delay(#offsets * 0.04, function()
		if card and card.Parent then
			card.Position = origPos
		end
	end)
end

-- ===== Card actions =====

function ShopController:_onCardAction(classId: string)
	if self._busy or not self._lastCatalog then
		return
	end
	local entry: ClassCatalogEntry? = nil
	for _, e in ipairs(self._lastCatalog.classes) do
		if e.id == classId then
			entry = e
			break
		end
	end
	if not entry then
		return
	end
	if entry.equipped then
		return
	end

	self._busy = true
	self:_setStatus("...", COLOR_TEXT_MUTED)

	if entry.owned then
		local result = self:_invokeShop({ action = ACTIONS.Equip, classId = classId })
		self._busy = false
		if typeof(result) == "table" and result.success then
			self:_setStatus(string.format("Equipped %s.", entry.displayName), COLOR_SUCCESS)
			self:_pulseCard(classId, COLOR_INFO)
		else
			local reason = (typeof(result) == "table" and result.reason) or REASONS.UnknownClass
			self:_setStatus(REASON_MESSAGES[reason] or "Unknown error.", COLOR_ERROR)
			self:_shakeCard(classId)
		end
	else
		local result = self:_invokeShop({ action = ACTIONS.Buy, classId = classId })
		self._busy = false
		if typeof(result) == "table" and result.success then
			self:_setStatus(string.format("Purchased %s!", entry.displayName), COLOR_SUCCESS)
			self:_pulseCard(classId, COLOR_SUCCESS)
		else
			local reason = (typeof(result) == "table" and result.reason) or REASONS.UnknownClass
			self:_setStatus(REASON_MESSAGES[reason] or "Unknown error.", COLOR_ERROR)
			self:_shakeCard(classId)
		end
	end

	-- Refetch após qualquer ação pra refletir saldo, owned/equipped flags atualizados.
	local refreshed = self:_fetchCatalog()
	if refreshed then
		self:_render(refreshed)
	end
end

-- ===== Open / Close =====

function ShopController:Open()
	if self._open or not self._gui then
		return
	end
	self._open = true
	self._gui.Enabled = true
	self:_setStatus("", COLOR_TEXT_MUTED)

	-- Pop-in animation no modal
	if self._modalFrame then
		self._modalFrame.Size = UDim2.new(0, 480, 0, 480)
		TweenService:Create(
			self._modalFrame,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 540, 0, 540) }
		):Play()
	end

	local catalog = self:_fetchCatalog()
	if catalog then
		self:_render(catalog)
	else
		self:_setStatus("Failed to load shop.", COLOR_ERROR)
	end
end

function ShopController:Close()
	if not self._open or not self._gui then
		return
	end
	self._open = false
	self._gui.Enabled = false
end

function ShopController:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

-- ===== Kiosk binding =====

function ShopController:_bindPrompt(prompt: ProximityPrompt)
	if self._promptConnections[prompt] then
		return
	end
	local conn = prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer == localPlayer then
			ShopController:Open()
		end
	end)
	self._promptConnections[prompt] = { conn }
end

function ShopController:_unbindPrompt(prompt: Instance)
	local conns = self._promptConnections[prompt]
	if conns then
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		self._promptConnections[prompt] = nil
	end
end

-- ===== Lifecycle =====

function ShopController:Init(_controllers: { [string]: any }) end

function ShopController:Start()
	self._gui = buildGui()
	self._modalFrame = self._gui:FindFirstChild("Modal") :: Frame
	local headerRow = self._modalFrame and self._modalFrame:FindFirstChild("Header") :: Frame?
	self._balanceLabel = headerRow and headerRow:FindFirstChild("Balance") :: TextLabel?
	self._statusLabel = self._modalFrame and self._modalFrame:FindFirstChild("Status") :: TextLabel?
	self._cardsContainer = self._modalFrame and self._modalFrame:FindFirstChild("Cards") :: Frame?

	-- ESC pra fechar
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if self._open and input.KeyCode == Enum.KeyCode.Escape then
			self:Close()
		end
	end)

	-- Bind prompts existentes + future
	for _, inst in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
		if inst:IsA("ProximityPrompt") then
			self:_bindPrompt(inst)
		else
			-- Tag aplicada à Part: procura o ProximityPrompt filho.
			local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				self:_bindPrompt(prompt)
			end
		end
	end
	CollectionService:GetInstanceAddedSignal(SHOP_TAG):Connect(function(inst)
		if inst:IsA("ProximityPrompt") then
			self:_bindPrompt(inst)
		else
			local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				self:_bindPrompt(prompt)
			end
		end
	end)
	CollectionService:GetInstanceRemovedSignal(SHOP_TAG):Connect(function(inst)
		self:_unbindPrompt(inst)
	end)
end

return ShopController
