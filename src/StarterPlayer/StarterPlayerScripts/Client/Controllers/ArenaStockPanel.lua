--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MAX_CARDS = 4
local PLACEHOLDER_IMAGE = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local TIER_TOKENS = {
	Bronze = Color3.fromRGB(205, 182, 122),
	Silver = Color3.fromRGB(192, 192, 192),
	Gold = Color3.fromRGB(255, 200, 71),
	Platinum = Color3.fromRGB(185, 242, 255),
	Diamond = Color3.fromRGB(181, 236, 255),
}

local LOCAL_BORDER = Color3.fromRGB(255, 200, 60)

type ArenaPlayerSnapshot = {
	userId: number,
	displayName: string,
	damagePercent: number,
	level: number,
	rank: { name: string, tier: number },
}

type Card = {
	frame: Frame,
	avatarFrame: Frame,
	avatarImage: ImageLabel,
	nameLabel: TextLabel,
	damageLabel: TextLabel,
	levelLabel: TextLabel,
	rankBadge: Frame,
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

local function truncateName(name: string, maxChars: number): string
	if #name <= maxChars then
		return name
	end
	return string.sub(name, 1, maxChars - 1) .. "…"
end

local function damageTierColor(pct: number): Color3
	if pct < 50 then
		return Color3.fromRGB(255, 255, 255)
	elseif pct < 100 then
		return Color3.fromRGB(255, 200, 60)
	elseif pct < 150 then
		return Color3.fromRGB(255, 120, 40)
	end
	return Color3.fromRGB(255, 60, 60)
end

local function rankTierColor(rank: { name: string, tier: number }): Color3
	local name = rank.name
	if string.find(name, "Bronze") then
		return TIER_TOKENS.Bronze
	elseif string.find(name, "Silver") then
		return TIER_TOKENS.Silver
	elseif string.find(name, "Gold") then
		return TIER_TOKENS.Gold
	elseif string.find(name, "Platinum") then
		return TIER_TOKENS.Platinum
	elseif string.find(name, "Diamond") or string.find(name, "Champion") then
		return TIER_TOKENS.Diamond
	end
	return Color3.fromRGB(150, 150, 150)
end

function ArenaStockPanel:_createCard(container: Frame, index: number): Card
	local card = Instance.new("Frame")
	card.Name = "Card" .. tostring(index)
	card.Size = UDim2.new(0, 90, 0, 88)
	card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = LOCAL_BORDER
	stroke.Enabled = false
	stroke.Parent = card

	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "AvatarFrame"
	avatarFrame.Size = UDim2.new(0, 40, 0, 40)
	avatarFrame.Position = UDim2.new(0, 6, 0, 6)
	avatarFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
	avatarFrame.BorderSizePixel = 0
	avatarFrame.Parent = card

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatarFrame

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.new(1, 0, 1, 0)
	avatar.BackgroundTransparency = 1
	avatar.Image = PLACEHOLDER_IMAGE
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = avatarFrame

	local avatarImgCorner = Instance.new("UICorner")
	avatarImgCorner.CornerRadius = UDim.new(1, 0)
	avatarImgCorner.Parent = avatar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -52, 0, 16)
	nameLabel.Position = UDim2.new(0, 50, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "—"
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	nameLabel.TextScaled = false
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "Damage"
	damageLabel.Size = UDim2.new(1, -52, 0, 26)
	damageLabel.Position = UDim2.new(0, 50, 0, 22)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = "0%"
	damageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	damageLabel.TextScaled = false
	damageLabel.TextSize = 24
	damageLabel.Font = Enum.Font.GothamBlack
	damageLabel.TextXAlignment = Enum.TextXAlignment.Left
	damageLabel.Parent = card

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(0, 36, 0, 14)
	levelLabel.Position = UDim2.new(0, 6, 1, -18)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv 1"
	levelLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	levelLabel.TextSize = 11
	levelLabel.Font = Enum.Font.Gotham
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = card

	local rankBadge = Instance.new("Frame")
	rankBadge.Name = "RankBadge"
	rankBadge.Size = UDim2.new(0, 40, 0, 14)
	rankBadge.Position = UDim2.new(1, -46, 1, -18)
	rankBadge.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	rankBadge.BorderSizePixel = 0
	rankBadge.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = rankBadge

	return {
		frame = card,
		avatarFrame = avatarFrame,
		avatarImage = avatar,
		nameLabel = nameLabel,
		damageLabel = damageLabel,
		levelLabel = levelLabel,
		rankBadge = rankBadge,
		localStroke = stroke,
		userId = nil,
		shattering = false,
	}
end

function ArenaStockPanel:_build(parent: ScreenGui)
	local container = Instance.new("Frame")
	container.Name = "ArenaStockPanel"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 0.98, 0)
	container.Size = UDim2.new(0, 384, 0, 88)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(800, 88)
	sizeConstraint.Parent = container

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
		for attempt = 1, 3 do
			local ok, content, isReady = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
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
	Players.PlayerRemoving:Connect(function(player)
		self._avatarCache[player.UserId] = nil
		self._avatarPending[player.UserId] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_loadAvatar(player.UserId)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_loadAvatar(player.UserId)
	end)
end

function ArenaStockPanel:_applyCardData(card: Card, snap: ArenaPlayerSnapshot, isLocal: boolean)
	card.userId = snap.userId
	card.nameLabel.Text = truncateName(snap.displayName, 12)
	card.damageLabel.Text = string.format("%d%%", math.floor(snap.damagePercent))
	card.damageLabel.TextColor3 = damageTierColor(snap.damagePercent)
	card.levelLabel.Text = string.format("Lv %d", snap.level)
	card.rankBadge.BackgroundColor3 = rankTierColor(snap.rank)
	card.localStroke.Enabled = isLocal

	-- Reset visual state (may have been affected by KO animation)
	card.frame.BackgroundTransparency = 0.25
	card.avatarImage.ImageTransparency = 0
	card.avatarFrame.Visible = true
	card.nameLabel.TextTransparency = 0
	card.damageLabel.TextTransparency = 0
	card.levelLabel.TextTransparency = 0

	if self._avatarCache[snap.userId] then
		card.avatarImage.Image = self._avatarCache[snap.userId]
	else
		card.avatarImage.Image = PLACEHOLDER_IMAGE
		self:_loadAvatar(snap.userId)
	end
end

function ArenaStockPanel:_triggerKOShatter(card: Card)
	if not card.frame.Parent then
		return
	end
	-- Simulate shatter: 8 small fragments burst from avatar center
	local avatarFrame = card.avatarFrame
	local absPos = avatarFrame.AbsolutePosition
	local absSize = avatarFrame.AbsoluteSize
	local centerX = absPos.X + absSize.X * 0.5
	local centerY = absPos.Y + absSize.Y * 0.5

	-- Hide the original avatar immediately at start of shatter
	avatarFrame.Visible = false

	local fragmentsHost = card.frame.Parent:FindFirstChild("_Fragments") :: ScreenGui?
	if not fragmentsHost then
		-- Use the ScreenGui that contains the stock panel
		local screenGui = card.frame:FindFirstAncestorOfClass("ScreenGui")
		fragmentsHost = screenGui
	end

	for i = 1, 8 do
		local frag = Instance.new("Frame")
		frag.Size = UDim2.new(0, 10, 0, 10)
		frag.AnchorPoint = Vector2.new(0.5, 0.5)
		frag.Position = UDim2.new(0, centerX, 0, centerY)
		frag.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		frag.BorderSizePixel = 0
		frag.ZIndex = 10
		frag.Parent = fragmentsHost
		local fragCorner = Instance.new("UICorner")
		fragCorner.CornerRadius = UDim.new(0, 2)
		fragCorner.Parent = frag

		local angle = (i - 1) * (math.pi * 2 / 8) + math.random() * 0.3
		local distance = 60 + math.random(0, 30)
		local targetX = centerX + math.cos(angle) * distance
		local targetY = centerY + math.sin(angle) * distance

		local tween = TweenService:Create(frag, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, targetX, 0, targetY),
			BackgroundTransparency = 1,
			Rotation = 180 + math.random(-90, 90),
		})
		tween:Play()
		task.delay(0.85, function()
			if frag.Parent then
				frag:Destroy()
			end
		end)
	end

	-- Card fade-out after shatter
	task.delay(0.4, function()
		if not card.frame.Parent then
			card.shattering = false
			return
		end
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(card.frame, fadeInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card.nameLabel, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(card.damageLabel, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(card.levelLabel, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(card.rankBadge, fadeInfo, { BackgroundTransparency = 1 }):Play()
		task.delay(0.45, function()
			if card.frame.Parent then
				card.frame.Visible = false
				card.userId = nil
				-- Reset transparencies for next render
				card.frame.BackgroundTransparency = 0.25
				card.rankBadge.BackgroundTransparency = 0
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

	-- Phase 1: detect eliminations and trigger shatter (mark card as shattering)
	for _, card in ipairs(self._cards) do
		if card.userId and not newIds[card.userId] and card.frame.Visible and not card.shattering then
			card.shattering = true
			self:_triggerKOShatter(card)
		end
	end

	-- Phase 2: identify continuing cards (same userId persists) vs available cards
	local continuingByUserId = {} :: { [number]: Card }
	local availableCards = {} :: { Card }
	for _, card in ipairs(self._cards) do
		if card.shattering then
			-- Skip — owned by shatter animation
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

	-- Phase 4: any remaining available cards (not used) get hidden
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
