--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MAX_CARDS = 4
local CARD_SIZE = 56 -- px, white circle
local CARD_GAP = 8
local RING_INSET = 2 -- white ring thickness visible around avatar
local PLACEHOLDER_IMAGE = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local LOCAL_BORDER = Color3.fromRGB(255, 200, 60)
local RING_COLOR = Color3.fromRGB(255, 255, 255)

type ArenaPlayerSnapshot = {
	userId: number,
	displayName: string,
	damagePercent: number,
	level: number,
	rank: { name: string, tier: number },
}

type Card = {
	frame: Frame,
	avatarImage: ImageLabel,
	localStroke: UIStroke,
	userId: number?,
	shattering: boolean?,
}

local ArenaStockPanel = {}
ArenaStockPanel.__index = ArenaStockPanel

function ArenaStockPanel.new(parent: ScreenGui)
	local self = setmetatable({}, ArenaStockPanel) :: any
	self._avatarCache = {} :: { [number]: string }
	self._avatarPending = {} :: { [number]: boolean }
	self._currentUserIds = {} :: { [number]: boolean }
	self._cards = {} :: { Card }
	self:_build(parent)
	self:_bindPlayerCleanup()
	return self
end

function ArenaStockPanel:_createCard(container: Frame, index: number): Card
	-- The entire card is a white circle. Avatar fills most of it.
	local card = Instance.new("Frame")
	card.Name = "Card" .. tostring(index)
	card.Size = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	card.BackgroundColor3 = RING_COLOR
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- full circle
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = LOCAL_BORDER
	stroke.Enabled = false
	stroke.Parent = card

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.new(1, -RING_INSET * 2, 1, -RING_INSET * 2)
	avatar.Position = UDim2.new(0, RING_INSET, 0, RING_INSET)
	avatar.BackgroundTransparency = 1
	avatar.Image = PLACEHOLDER_IMAGE
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = card

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	return {
		frame = card,
		avatarImage = avatar,
		localStroke = stroke,
		userId = nil,
		shattering = false,
	}
end

function ArenaStockPanel:_build(parent: ScreenGui)
	local container = Instance.new("Frame")
	container.Name = "ArenaStockPanel"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 0.96, 0)
	local totalWidth = CARD_SIZE * MAX_CARDS + CARD_GAP * (MAX_CARDS - 1)
	container.Size = UDim2.new(0, totalWidth, 0, CARD_SIZE)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = container

	self._container = container

	for i = 1, MAX_CARDS do
		local card = self:_createCard(container, i)
		card.frame.LayoutOrder = i
		table.insert(self._cards, card)
	end
end

function ArenaStockPanel:_loadAvatar(userId: number)
	if self._avatarCache[userId] or self._avatarPending[userId] then
		return
	end
	self._avatarPending[userId] = true
	task.spawn(function()
		for _ = 1, 3 do
			local ok, content, isReady = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size60x60)
			end)
			if ok and isReady and typeof(content) == "string" and content ~= "" then
				self._avatarCache[userId] = content
				for _, card in ipairs(self._cards) do
					if card.userId == userId then
						card.avatarImage.Image = content
					end
				end
				self._avatarPending[userId] = nil
				return
			end
			task.wait(1)
		end
		self._avatarPending[userId] = nil
	end)
end

function ArenaStockPanel:PreloadAvatar(userId: number)
	self:_loadAvatar(userId)
end

function ArenaStockPanel:_bindPlayerCleanup()
	Players.PlayerRemoving:Connect(function(plr)
		self._avatarCache[plr.UserId] = nil
		self._avatarPending[plr.UserId] = nil
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		self:_loadAvatar(plr.UserId)
	end
	Players.PlayerAdded:Connect(function(plr)
		self:_loadAvatar(plr.UserId)
	end)
end

function ArenaStockPanel:_applyCardData(card: Card, snap: ArenaPlayerSnapshot, isLocal: boolean)
	card.userId = snap.userId
	card.localStroke.Enabled = isLocal

	-- Reset visual state (may have been faded by KO animation)
	card.frame.BackgroundTransparency = 0
	card.avatarImage.ImageTransparency = 0

	if self._avatarCache[snap.userId] then
		card.avatarImage.Image = self._avatarCache[snap.userId]
	else
		card.avatarImage.Image = PLACEHOLDER_IMAGE
		self:_loadAvatar(snap.userId)
	end
end

function ArenaStockPanel:_triggerKOShatter(card: Card)
	if not card.frame.Parent then
		card.shattering = false
		return
	end

	-- Shatter: burst 8 fragments from card center, fade avatar + card
	local cardAbsPos = card.frame.AbsolutePosition
	local cardAbsSize = card.frame.AbsoluteSize
	local centerX = cardAbsPos.X + cardAbsSize.X * 0.5
	local centerY = cardAbsPos.Y + cardAbsSize.Y * 0.5

	local screenGui = card.frame:FindFirstAncestorOfClass("ScreenGui")

	for i = 1, 8 do
		local frag = Instance.new("Frame")
		frag.Size = UDim2.new(0, 10, 0, 10)
		frag.AnchorPoint = Vector2.new(0.5, 0.5)
		frag.Position = UDim2.new(0, centerX, 0, centerY)
		frag.BackgroundColor3 = LOCAL_BORDER
		frag.BorderSizePixel = 0
		frag.ZIndex = 10
		frag.Parent = screenGui
		local fragCorner = Instance.new("UICorner")
		fragCorner.CornerRadius = UDim.new(0, 2)
		fragCorner.Parent = frag

		local angle = (i - 1) * (math.pi * 2 / 8) + math.random() * 0.3
		local distance = 60 + math.random(0, 30)
		local targetX = centerX + math.cos(angle) * distance
		local targetY = centerY + math.sin(angle) * distance

		TweenService:Create(frag, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, targetX, 0, targetY),
			BackgroundTransparency = 1,
			Rotation = 180 + math.random(-90, 90),
		}):Play()
		task.delay(0.85, function()
			if frag.Parent then
				frag:Destroy()
			end
		end)
	end

	-- Hide avatar immediately while shatter plays, fade card after
	card.avatarImage.ImageTransparency = 1
	task.delay(0.4, function()
		if not card.frame.Parent then
			card.shattering = false
			return
		end
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(card.frame, fadeInfo, { BackgroundTransparency = 1 }):Play()
		task.delay(0.45, function()
			if card.frame.Parent then
				card.frame.Visible = false
				card.userId = nil
				card.frame.BackgroundTransparency = 0
				card.avatarImage.ImageTransparency = 0
			end
			card.shattering = false
		end)
	end)
end

function ArenaStockPanel:Update(players: { ArenaPlayerSnapshot }, localUserId: number)
	local newIds = {} :: { [number]: boolean }
	for _, snap in ipairs(players) do
		newIds[snap.userId] = true
	end

	-- Phase 1: trigger shatter for cards whose player disappeared (KO)
	for _, card in ipairs(self._cards) do
		if card.userId and not newIds[card.userId] and card.frame.Visible and not card.shattering then
			card.shattering = true
			self:_triggerKOShatter(card)
		end
	end

	-- Phase 2: identify continuing vs available cards
	local continuingByUserId = {} :: { [number]: Card }
	local availableCards = {} :: { Card }
	for _, card in ipairs(self._cards) do
		if card.shattering then
			-- owned by shatter animation
		elseif card.userId and newIds[card.userId] then
			continuingByUserId[card.userId] = card
		else
			table.insert(availableCards, card)
		end
	end

	-- Phase 3: apply snapshots — continuing players stay on their card, new players take next available
	local count = math.min(#players, MAX_CARDS)
	for i = 1, count do
		local snap = players[i]
		local isLocal = snap.userId == localUserId
		local card = continuingByUserId[snap.userId]
		if not card then
			card = table.remove(availableCards, 1)
		end
		if card then
			self:_applyCardData(card, snap, isLocal)
			card.frame.Visible = true
		end
	end

	-- Phase 4: hide remaining unused cards
	for _, card in ipairs(availableCards) do
		card.frame.Visible = false
		card.userId = nil
	end

	self._currentUserIds = newIds
end

function ArenaStockPanel:Show()
	if self._container then
		self._container.Visible = true
	end
end

function ArenaStockPanel:Hide()
	if self._container then
		self._container.Visible = false
	end
end

function ArenaStockPanel:Clear()
	for _, card in ipairs(self._cards) do
		card.frame.Visible = false
		card.userId = nil
	end
	self._currentUserIds = {}
end

return ArenaStockPanel
