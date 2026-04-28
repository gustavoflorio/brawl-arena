--!strict

-- ShopController: monta ScreenGui da loja, escuta ProximityPrompts taggeados
-- como ShopKiosk, e faz transações de compra/equip via BrawlShop RemoteFunction.
--
-- Cria UI em runtime usando tokens do DESIGN.md (ver constantes COLORS/FONTS
-- no topo do arquivo). Motion contida em widgets (pulse, fade) — sem afetar tela.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Classes = require(sharedFolder:WaitForChild("Classes"))

local ResponsiveLayout = require(script.Parent:WaitForChild("ResponsiveLayout"))

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

local CARD_WIDTH = 240
local CARD_HEIGHT = 400
local CARD_HERO_HEIGHT = 200

-- Responsive layout: composição "fixed geometry" em resolução de design,
-- escalada via UIScale pra caber no safe viewport (sem reflow estrutural).
-- Padrão da skill roblox-ui-creator — ver Controllers/ResponsiveLayout.lua.
-- Width 880 cabe 3 cards de 240 + paddings sem precisar scroll horizontal.
local MODAL_DESIGN_WIDTH = 880
local MODAL_DESIGN_HEIGHT = 620
local MODAL_POP_START_WIDTH = 810
local MODAL_POP_START_HEIGHT = 570

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
ShopController._panelScale = nil :: UIScale?
ShopController._viewportConn = nil :: RBXScriptConnection?
ShopController._cameraChangedConn = nil :: RBXScriptConnection?

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
	card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	card.BackgroundColor3 = COLOR_BG_ELEVATED
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	corner(card, 14)
	stroke(card, COLOR_OUTLINE, 2)

	-- Hero: imagem da classe (full-bleed topo). Quando iconAssetId vazio, mostra
	-- placeholder com a inicial em fonte chunky. Pronto pro user upar assets sem
	-- mexer no layout.
	--
	-- Trick pros corners arredondados: hero tem UICorner 14 (igual ao card) e
	-- altura HERO + 14, estendendo 14px abaixo da divisa visível. O Content
	-- abaixo é opaco (BG_ELEVATED) e cobre essa extensão, escondendo os corners
	-- arredondados de baixo. Resultado: hero curva certo no topo, transição
	-- limpa pra content (sem borda quebrada).
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.Size = UDim2.new(1, 0, 0, CARD_HERO_HEIGHT + 14)
	hero.Position = UDim2.new(0, 0, 0, 0)
	hero.BackgroundColor3 = COLOR_BG_DEEP
	hero.BorderSizePixel = 0
	hero.ClipsDescendants = true
	hero.Parent = card
	corner(hero, 14)

	-- HeroImage: mesma altura estendida do hero (HERO + 14) com UICorner 14, pra
	-- top corners curvarem junto com card e bottom corners ficarem cobertos pelo
	-- content. UICorner no hero não recorta ImageLabel filho — precisa do próprio.
	local heroImage = Instance.new("ImageLabel")
	heroImage.Name = "HeroImage"
	heroImage.Size = UDim2.new(1, 0, 0, CARD_HERO_HEIGHT + 14)
	heroImage.Position = UDim2.new(0, 0, 0, 0)
	heroImage.BackgroundTransparency = 1
	heroImage.BorderSizePixel = 0
	heroImage.ScaleType = Enum.ScaleType.Crop
	heroImage.Image = (entry.iconAssetId ~= "" and ("rbxassetid://" .. entry.iconAssetId)) or ""
	heroImage.Visible = entry.iconAssetId ~= ""
	heroImage.Parent = hero
	corner(heroImage, 14)

	local placeholder = Instance.new("TextLabel")
	placeholder.Name = "Placeholder"
	placeholder.Size = UDim2.new(1, 0, 0, CARD_HERO_HEIGHT)
	placeholder.Position = UDim2.new(0, 0, 0, 0)
	placeholder.BackgroundTransparency = 1
	placeholder.Font = FONT_DISPLAY
	placeholder.Text = string.upper(string.sub(entry.displayName, 1, 1))
	placeholder.TextSize = 110
	placeholder.TextColor3 = COLOR_TEXT_DIM
	placeholder.TextStrokeColor3 = COLOR_OUTLINE
	placeholder.TextStrokeTransparency = 0.4
	placeholder.Visible = entry.iconAssetId == ""
	placeholder.Parent = hero

	-- Content area abaixo do hero. UICorner 14 (igual ao card) faz os corners
	-- de baixo seguirem a curvatura. Os corners de cima curvam pra dentro mas
	-- ficam exatamente sobre os corners de baixo do hero (mesma posição/raio),
	-- então a transição hero↔content fica visualmente alinhada com a curva.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, -CARD_HERO_HEIGHT)
	content.Position = UDim2.new(0, 0, 0, CARD_HERO_HEIGHT)
	content.BackgroundColor3 = COLOR_BG_ELEVATED
	content.BackgroundTransparency = 0
	content.BorderSizePixel = 0
	content.Parent = card
	corner(content, 14)

	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingTop = UDim.new(0, 14)
	contentPad.PaddingBottom = UDim.new(0, 14)
	contentPad.PaddingLeft = UDim.new(0, 14)
	contentPad.PaddingRight = UDim.new(0, 14)
	contentPad.Parent = content

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 40)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_DISPLAY
	nameLabel.Text = string.upper(entry.displayName)
	nameLabel.TextSize = 36
	nameLabel.TextColor3 = COLOR_TEXT_PURE
	nameLabel.TextStrokeColor3 = COLOR_OUTLINE
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.Parent = content

	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.Position = UDim2.new(0, 0, 0, 46)
	desc.Size = UDim2.new(1, 0, 0, 60)
	desc.BackgroundTransparency = 1
	desc.Font = FONT_BODY
	desc.Text = entry.description
	desc.TextSize = 18
	desc.TextColor3 = COLOR_TEXT_MUTED
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Parent = content

	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionBtn"
	actionBtn.AnchorPoint = Vector2.new(0, 1)
	actionBtn.Position = UDim2.new(0, 0, 1, 0)
	actionBtn.Size = UDim2.new(1, 0, 0, 56)
	actionBtn.BackgroundColor3 = COLOR_BG_SURFACE
	actionBtn.BorderSizePixel = 0
	actionBtn.AutoButtonColor = false
	actionBtn.Font = FONT_LABEL
	actionBtn.Text = ""
	actionBtn.TextSize = 22
	actionBtn.TextColor3 = COLOR_TEXT_PRIMARY
	corner(actionBtn, 10)
	stroke(actionBtn, COLOR_OUTLINE, 1)
	actionBtn.Parent = content

	return card
end

local function setCardState(card: Frame, entry: ClassCatalogEntry, balance: number, busy: boolean)
	local content = card:FindFirstChild("Content")
	local btn = content and content:FindFirstChild("ActionBtn") :: any
	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	if not btn or not btn:IsA("TextButton") or not cardStroke then
		return
	end

	if entry.equipped then
		btn.Text = "EQUIPPED"
		btn.TextColor3 = COLOR_SUCCESS
		btn.BackgroundColor3 = COLOR_BG_DEEP
		btn.AutoButtonColor = false
		btn.Active = false
		cardStroke.Color = COLOR_SUCCESS
		cardStroke.Thickness = 3
	elseif entry.owned then
		btn.Text = "EQUIP"
		btn.TextColor3 = COLOR_TEXT_PURE
		btn.BackgroundColor3 = COLOR_INFO
		btn.AutoButtonColor = true
		btn.Active = not busy
		cardStroke.Color = COLOR_OUTLINE
		cardStroke.Thickness = 2
	else
		if balance >= entry.price then
			btn.Text = string.format("BUY  %d", entry.price)
			btn.TextColor3 = COLOR_TEXT_PURE
			btn.BackgroundColor3 = COLOR_WARNING
			btn.AutoButtonColor = true
			btn.Active = not busy
		else
			-- Saldo insuficiente: botão fica clicável e dispara o coin pack
			-- prompt no _onCardAction (UI nativa do Roblox pra DevProduct).
			btn.Text = string.format("%d COINS", entry.price)
			btn.TextColor3 = COLOR_WARNING
			btn.BackgroundColor3 = COLOR_BG_DEEP
			btn.AutoButtonColor = true
			btn.Active = not busy
		end
		cardStroke.Color = COLOR_OUTLINE
		cardStroke.Thickness = 2
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

	-- Modal panel — geometria fixa em design coords, escalada via UIScale.
	-- Position é reatribuída em _applyResponsiveLayout() pra centralizar no
	-- safe viewport (ignora gui inset, mas respeita-o pra centro).
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.new(0, MODAL_DESIGN_WIDTH, 0, MODAL_DESIGN_HEIGHT)
	modal.BackgroundColor3 = COLOR_BG_SURFACE
	modal.BorderSizePixel = 0
	-- Active = true faz o modal sinkar input. Sem isso, cliques na área do modal
	-- também disparam dim.InputBegan (Frame irmão atrás), fechando a UI mesmo
	-- quando o user clica dentro dela.
	modal.Active = true
	modal.Parent = gui
	corner(modal, 20)
	stroke(modal, COLOR_OUTLINE, 3)

	-- UIScale do fit-to-viewport. Pop-in agora usa tween de Size em design coords
	-- (UIScale aplica o fit por fora — não há briga). Mesmo padrão do StatsPanel.
	ShopController._panelScale = ResponsiveLayout.EnsureUiScale(modal, "ResponsiveScale")

	padding(modal, 20)

	-- Header: title + balance + close
	local headerRow = Instance.new("Frame")
	headerRow.Name = "Header"
	headerRow.Size = UDim2.new(1, 0, 0, 60)
	headerRow.Position = UDim2.new(0, 0, 0, 0)
	headerRow.BackgroundTransparency = 1
	headerRow.Parent = modal

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.55, 0, 1, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = FONT_HEADING
	title.Text = "CHANGE CLASS"
	title.TextSize = 32
	title.TextColor3 = COLOR_TEXT_PURE
	title.TextStrokeColor3 = COLOR_OUTLINE
	title.TextStrokeTransparency = 0.3
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = headerRow

	local balance = Instance.new("TextLabel")
	balance.Name = "Balance"
	balance.AnchorPoint = Vector2.new(1, 0.5)
	balance.Position = UDim2.new(1, -68, 0.5, 0)
	balance.Size = UDim2.new(0, 240, 0, 48)
	balance.BackgroundColor3 = COLOR_BG_DEEP
	balance.BorderSizePixel = 0
	balance.Font = FONT_LABEL
	balance.Text = "0  COINS"
	balance.TextSize = 24
	balance.TextColor3 = COLOR_WARNING
	balance.TextXAlignment = Enum.TextXAlignment.Center
	corner(balance, 8)
	stroke(balance, COLOR_OUTLINE, 1)
	balance.Parent = headerRow

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, 0, 0.5, 0)
	close.Size = UDim2.new(0, 56, 0, 56)
	close.BackgroundColor3 = COLOR_BG_DEEP
	close.BorderSizePixel = 0
	close.Font = FONT_HEADING
	close.Text = "X"
	close.TextSize = 28
	close.TextColor3 = COLOR_TEXT_PRIMARY
	corner(close, 10)
	stroke(close, COLOR_OUTLINE, 1)
	close.Parent = headerRow

	-- Status row (mensagens de erro/feedback)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 28)
	status.Position = UDim2.new(0, 0, 0, 68)
	status.BackgroundTransparency = 1
	status.Font = FONT_BODY
	status.Text = ""
	status.TextSize = 18
	status.TextColor3 = COLOR_TEXT_MUTED
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = modal

	-- Cards container: scroll horizontal pra acomodar N classes futuras
	local cards = Instance.new("ScrollingFrame")
	cards.Name = "Cards"
	cards.Size = UDim2.new(1, 0, 1, -112)
	cards.Position = UDim2.new(0, 0, 0, 112)
	cards.BackgroundTransparency = 1
	cards.BorderSizePixel = 0
	cards.CanvasSize = UDim2.new()
	cards.AutomaticCanvasSize = Enum.AutomaticSize.X
	cards.ScrollingDirection = Enum.ScrollingDirection.X
	cards.ScrollBarThickness = 6
	cards.ScrollBarImageColor3 = COLOR_TEXT_DIM
	cards.ClipsDescendants = true
	cards.Parent = modal

	-- Padding interno pra strokes (especialmente o equipped 3px) não baterem
	-- na borda do scroll, e pra reservar espaço da scrollbar abaixo dos cards.
	local cardsPad = Instance.new("UIPadding")
	cardsPad.PaddingTop = UDim.new(0, 6)
	cardsPad.PaddingBottom = UDim.new(0, 18)
	cardsPad.PaddingLeft = UDim.new(0, 6)
	cardsPad.PaddingRight = UDim.new(0, 6)
	cardsPad.Parent = cards

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 16)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = cards

	gui.Parent = playerGui

	close.Activated:Connect(function()
		ShopController:Close()
	end)
	-- Backdrop close: cliques fora do modal fecham. Em vez de depender de
	-- Active/sinking (que falha quando frames descendentes do modal não
	-- propagam o sink), checamos explicitamente se o ponto do clique está
	-- dentro do bounding box do modal. Se sim, ignora; senão, fecha.
	dim.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if ShopController._modalFrame then
			local pos = input.Position
			local modalPos = ShopController._modalFrame.AbsolutePosition
			local modalSize = ShopController._modalFrame.AbsoluteSize
			if pos.X >= modalPos.X and pos.X <= modalPos.X + modalSize.X
				and pos.Y >= modalPos.Y and pos.Y <= modalPos.Y + modalSize.Y
			then
				return
			end
		end
		ShopController:Close()
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
		local catalog = result :: ShopCatalogPayload
		-- Cache no _lastCatalog mesmo fora do flow do shop UI — outros
		-- controllers (CombatFxController) leem equippedClassId via
		-- GetEquippedClassId() pra montar lookup das anims por classe.
		self._lastCatalog = catalog
		return catalog
	end
	return nil
end

function ShopController:GetEquippedClassId(): string
	-- Fonte de verdade do equipped class no client. Lê do catalog cached;
	-- se ainda nao fetchou (race condition no boot), cai pro default.
	local catalog = self._lastCatalog
	if catalog then
		for _, entry in ipairs(catalog.classes) do
			if entry.equipped then
				return entry.id
			end
		end
	end
	return Classes.GetDefaultId()
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

			local content = card:FindFirstChild("Content") :: Frame
			local btn = content:FindFirstChild("ActionBtn") :: TextButton
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

	-- Saldo insuficiente: dispara o prompt nativo do Roblox pro coin pack
	-- (DevProduct configurado em Constants.Shop.CoinPack). ProcessReceipt no
	-- server credita 500 coins; o catalog é refetchado quando o prompt fecha.
	if not entry.owned and self._lastCatalog.balance < entry.price then
		self:_setStatus("", COLOR_TEXT_MUTED)
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, Constants.Shop.CoinPack.ProductId)
		end)
		if not ok then
			warn("[ShopController] PromptProductPurchase failed:", err)
			self:_setStatus("Could not open purchase prompt.", COLOR_ERROR)
		end
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

-- Refetch externo: outros controllers (ex: DevController após grant coins)
-- chamam isto pra forçar refresh quando o shop tá visível.
function ShopController:_refreshIfOpen()
	if not self._open then
		return
	end
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

	-- Reaplica responsive layout antes de abrir: se o viewport mudou enquanto
	-- o painel estava fechado (rotate de device), scale/position estaria stale.
	self:_applyResponsiveLayout()

	-- Pop-in: tween de Size em design coords. UIScale (responsivo) aplica o
	-- fit-to-viewport por fora, então o tween termina sempre no design size
	-- correto independente do device.
	if self._modalFrame then
		self._modalFrame.Size = UDim2.new(0, MODAL_POP_START_WIDTH, 0, MODAL_POP_START_HEIGHT)
		TweenService:Create(
			self._modalFrame,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, MODAL_DESIGN_WIDTH, 0, MODAL_DESIGN_HEIGHT) }
		):Play()
	end

	local catalog = self:_fetchCatalog()
	if catalog then
		self:_render(catalog)
	else
		self:_setStatus("Failed to load shop.", COLOR_ERROR)
	end
end

function ShopController:_applyResponsiveLayout()
	local metrics = ResponsiveLayout.GetViewportMetrics()

	-- GetViewportFitScale garante que o modal cabe em 94% da largura safe e
	-- no default dinâmico de altura (0.86 phoneLandscape, 0.9 shortHeight,
	-- 0.94 normal) — previne corte de bottom em phones landscape onde inset
	-- da status bar come mais altura. min 0.35, max 1 (não upscala em telão).
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

	if self._modalFrame then
		-- Centraliza no safe viewport (respeita inset top/bottom).
		self._modalFrame.Position = ResponsiveLayout.GetSafeCenterPosition(metrics)
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
	-- Fetch inicial do catalog (assincrono): popula _lastCatalog mesmo sem o
	-- user abrir o shop. Outros controllers leem equippedClassId via
	-- GetEquippedClassId() — sem esse fetch o lookup cairia sempre no default.
	task.spawn(function()
		self:_fetchCatalog()
	end)

	self._gui = buildGui()
	self._modalFrame = self._gui:FindFirstChild("Modal") :: Frame
	local headerRow = self._modalFrame and self._modalFrame:FindFirstChild("Header") :: Frame?
	self._balanceLabel = headerRow and headerRow:FindFirstChild("Balance") :: TextLabel?
	self._statusLabel = self._modalFrame and self._modalFrame:FindFirstChild("Status") :: TextLabel?
	self._cardsContainer = self._modalFrame and self._modalFrame:FindFirstChild("Cards") :: Frame?

	-- Aplica scale inicial + reaplica em resize (rotate de device, join mid-game
	-- em outro aspect ratio, etc.). Camera pode ser recriada — reanexa via
	-- CurrentCameraChanged pra não perder a conexão.
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

	-- Refetch catalog quando o prompt do coin pack fecha com sucesso.
	-- ProcessReceipt no server pode terminar antes ou depois do prompt fechar
	-- (timing variável especialmente em Studio), então fazemos polling: até 5
	-- tentativas com delay crescente, parando assim que detectamos balance up.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= localPlayer.UserId then return end
		if productId ~= Constants.Shop.CoinPack.ProductId then return end
		if not isPurchased or not self._open then return end
		local previousBalance = self._lastCatalog and self._lastCatalog.balance or 0
		for attempt = 1, 5 do
			task.wait(attempt == 1 and 0.3 or 0.6)
			if not self._open then return end
			local refreshed = self:_fetchCatalog()
			if refreshed then
				self:_render(refreshed)
				if refreshed.balance > previousBalance then
					self:_setStatus(string.format("+%d coins added!", Constants.Shop.CoinPack.Amount), COLOR_SUCCESS)
					return
				end
			end
		end
		self:_setStatus("Coins not credited yet — try refreshing.", COLOR_WARNING)
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
