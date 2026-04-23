--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MAX_CARDS = 4
local CARD_WIDTH = 60
local CARD_HEIGHT = 82
local AVATAR_SIZE = 44
local CARD_GAP = 8
local PLACEHOLDER_IMAGE = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local LOCAL_BORDER = Color3.fromRGB(255, 200, 60)
local RING_COLOR = Color3.fromRGB(255, 255, 255)

local RANK_TIER_COLORS = {
	Unranked = Color3.fromRGB(120, 120, 130),
	Bronze = Color3.fromRGB(205, 127, 50),
	Silver = Color3.fromRGB(200, 200, 210),
	Gold = Color3.fromRGB(255, 200, 71),
	Platinum = Color3.fromRGB(185, 242, 255),
	Diamond = Color3.fromRGB(140, 220, 255),
	Champion = Color3.fromRGB(255, 90, 90),
}

local RANK_ICON_IDS = {
	Bronze = "rbxassetid://95221352287862",
	Silver = "rbxassetid://87829525424272",
	Gold = "rbxassetid://90669385414264",
	Platinum = "rbxassetid://128268020488699",
	Diamond = "rbxassetid://78191016954660",
	Champion = "rbxassetid://83852817358288",
}

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
	damageLabel: TextLabel,
	levelLabel: TextLabel,
	rankLogo: ImageLabel,
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

local function rankTierColor(rankName: string): Color3
	if string.find(rankName, "Bronze") then
		return RANK_TIER_COLORS.Bronze
	elseif string.find(rankName, "Silver") then
		return RANK_TIER_COLORS.Silver
	elseif string.find(rankName, "Gold") then
		return RANK_TIER_COLORS.Gold
	elseif string.find(rankName, "Platinum") then
		return RANK_TIER_COLORS.Platinum
	elseif string.find(rankName, "Diamond") then
		return RANK_TIER_COLORS.Diamond
	elseif string.find(rankName, "Champion") then
		return RANK_TIER_COLORS.Champion
	end
	return RANK_TIER_COLORS.Unranked
end

local function rankIconId(rankName: string): string?
	if string.find(rankName, "Bronze") then
		return RANK_ICON_IDS.Bronze
	elseif string.find(rankName, "Silver") then
		return RANK_ICON_IDS.Silver
	elseif string.find(rankName, "Gold") then
		return RANK_ICON_IDS.Gold
	elseif string.find(rankName, "Platinum") then
		return RANK_ICON_IDS.Platinum
	elseif string.find(rankName, "Diamond") then
		return RANK_ICON_IDS.Diamond
	elseif string.find(rankName, "Champion") then
		return RANK_ICON_IDS.Champion
	end
	return nil
end

function ArenaStockPanel:_createCard(container: Frame, index: number): Card
	-- Root card is transparent — visual elements are the avatar circle + text below.
	local card = Instance.new("Frame")
	card.Name = "Card" .. tostring(index)
	card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = container

	-- Avatar circle (white ring)
	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "Avatar"
	avatarFrame.AnchorPoint = Vector2.new(0.5, 0)
	avatarFrame.Position = UDim2.new(0.5, 0, 0, 0)
	avatarFrame.Size = UDim2.new(0, AVATAR_SIZE, 0, AVATAR_SIZE)
	avatarFrame.BackgroundColor3 = RING_COLOR
	avatarFrame.BorderSizePixel = 0
	avatarFrame.Parent = card

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatarFrame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = LOCAL_BORDER
	stroke.Enabled = false
	stroke.Parent = avatarFrame

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "AvatarImage"
	avatar.Size = UDim2.new(1, -4, 1, -4)
	avatar.Position = UDim2.new(0, 2, 0, 2)
	avatar.BackgroundTransparency = 1
	avatar.Image = PLACEHOLDER_IMAGE
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = avatarFrame

	local avatarImgCorner = Instance.new("UICorner")
	avatarImgCorner.CornerRadius = UDim.new(1, 0)
	avatarImgCorner.Parent = avatar

	-- Damage text — big, tier-colored
	local damageLabel = Instance.new("TextLabel")
	damageLabel.Name = "Damage"
	damageLabel.AnchorPoint = Vector2.new(0.5, 0)
	damageLabel.Position = UDim2.new(0.5, 0, 0, AVATAR_SIZE + 4)
	damageLabel.Size = UDim2.new(1, 0, 0, 16)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Text = "0%"
	damageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	damageLabel.TextStrokeTransparency = 0.5
	damageLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	damageLabel.TextSize = 15
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.Parent = card

	-- Meta row — Lv + rank chip
	local metaRow = Instance.new("Frame")
	metaRow.Name = "Meta"
	metaRow.AnchorPoint = Vector2.new(0.5, 0)
	metaRow.Position = UDim2.new(0.5, 0, 0, AVATAR_SIZE + 22)
	metaRow.Size = UDim2.new(1, 0, 0, 14)
	metaRow.BackgroundTransparency = 1
	metaRow.Parent = card

	local metaLayout = Instance.new("UIListLayout")
	metaLayout.FillDirection = Enum.FillDirection.Horizontal
	metaLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	metaLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	metaLayout.SortOrder = Enum.SortOrder.LayoutOrder
	metaLayout.Padding = UDim.new(0, 4)
	metaLayout.Parent = metaRow

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.LayoutOrder = 1
	levelLabel.Size = UDim2.new(0, 28, 1, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv 1"
	levelLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	levelLabel.TextStrokeTransparency = 0.6
	levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabel.TextSize = 10
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.Parent = metaRow

	local rankLogo = Instance.new("ImageLabel")
	rankLogo.Name = "RankLogo"
	rankLogo.LayoutOrder = 2
	rankLogo.Size = UDim2.new(0, 16, 0, 14)
	rankLogo.BackgroundTransparency = 1
	rankLogo.Image = PLACEHOLDER_IMAGE
	rankLogo.ImageColor3 = RANK_TIER_COLORS.Unranked
	rankLogo.ScaleType = Enum.ScaleType.Fit
	rankLogo.Parent = metaRow

	return {
		frame = card,
		avatarImage = avatar,
		localStroke = stroke,
		damageLabel = damageLabel,
		levelLabel = levelLabel,
		rankLogo = rankLogo,
		userId = nil,
		shattering = false,
	}
end

function ArenaStockPanel:_build(parent: ScreenGui)
	local container = Instance.new("Frame")
	container.Name = "ArenaStockPanel"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 0.98, 0)
	local totalWidth = CARD_WIDTH * MAX_CARDS + CARD_GAP * (MAX_CARDS - 1)
	container.Size = UDim2.new(0, totalWidth, 0, CARD_HEIGHT)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
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

	-- Reset visual state (shatter may have faded)
	card.frame.Visible = true
	card.avatarImage.ImageTransparency = 0
	card.damageLabel.TextTransparency = 0
	card.levelLabel.TextTransparency = 0
	card.rankLogo.ImageTransparency = 0

	-- Damage
	local pct = math.floor(snap.damagePercent)
	card.damageLabel.Text = string.format("%d%%", pct)
	card.damageLabel.TextColor3 = damageTierColor(pct)

	-- Level
	card.levelLabel.Text = string.format("Lv%d", snap.level)

	local rankName = snap.rank and snap.rank.name or "Unranked"
	local iconId = rankIconId(rankName)
	if iconId then
		card.rankLogo.Image = iconId
		card.rankLogo.ImageColor3 = Color3.fromRGB(255, 255, 255)
	else
		card.rankLogo.Image = PLACEHOLDER_IMAGE
		card.rankLogo.ImageColor3 = RANK_TIER_COLORS.Unranked
	end

	-- Avatar
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

	-- Fragmentos são parented ao card (não ao ScreenGui) e usam card-local coords.
	-- Garante que shatter sempre acompanha a posição do card mesmo se layout mudar
	-- durante a animação. Avatar center in card-local = (CARD_WIDTH/2, AVATAR_SIZE/2).
	local centerX = CARD_WIDTH * 0.5
	local centerY = AVATAR_SIZE * 0.5

	for i = 1, 8 do
		local frag = Instance.new("Frame")
		frag.Size = UDim2.new(0, 9, 0, 9)
		frag.AnchorPoint = Vector2.new(0.5, 0.5)
		frag.Position = UDim2.new(0, centerX, 0, centerY)
		frag.BackgroundColor3 = LOCAL_BORDER
		frag.BorderSizePixel = 0
		frag.ZIndex = 10
		frag.Parent = card.frame
		local fragCorner = Instance.new("UICorner")
		fragCorner.CornerRadius = UDim.new(0, 2)
		fragCorner.Parent = frag

		local angle = (i - 1) * (math.pi * 2 / 8) + math.random() * 0.3
		local distance = 55 + math.random(0, 25)
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

	card.avatarImage.ImageTransparency = 1
	task.delay(0.4, function()
		if not card.frame.Parent then
			card.shattering = false
			return
		end
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(card.damageLabel, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(card.levelLabel, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(card.rankLogo, fadeInfo, { ImageTransparency = 1 }):Play()
		task.delay(0.45, function()
			if card.frame.Parent then
				card.frame.Visible = false
				card.userId = nil
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

	-- Phase 1: trigger shatter for cards whose player disappeared
	for _, card in ipairs(self._cards) do
		if card.userId and not newIds[card.userId] and card.frame.Visible and not card.shattering then
			card.shattering = true
			self:_triggerKOShatter(card)
		end
	end

	-- Phase 2: split cards into continuing vs available
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

	-- Phase 3: apply snapshots to cards
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
		end
	end

	-- Phase 4: hide leftover cards
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
