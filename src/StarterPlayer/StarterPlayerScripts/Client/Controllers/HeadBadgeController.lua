--!strict

-- Badge world-space acima da cabeça do player: imagem do rank em cima e
-- "LVL N" embaixo, sem frame/background. Visível apenas no lobby.
-- Unranked não renderiza imagem (só o level text).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Rank = require(sharedFolder:WaitForChild("Rank"))

local LEVEL_ATTR = Constants.CharacterAttributes.Level
local RANK_NAME_ATTR = Constants.CharacterAttributes.RankName
local RANK_TIER_ATTR = Constants.CharacterAttributes.RankTier
local ARENA_ATTR = Constants.CharacterAttributes.ArenaActive

local BADGE_NAME = "BrawlHeadBadge"

local HeadBadgeController = {}

local function createBadge(character: Model): BillboardGui
	local hrp = character:WaitForChild("HumanoidRootPart", 5) :: Instance?

	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Size = UDim2.new(0, 60, 0, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Adornee = hrp
	gui.Enabled = false
	gui.Parent = character

	local icon = Instance.new("ImageLabel")
	icon.Name = "RankIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = gui

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.AnchorPoint = Vector2.new(0.5, 1)
	levelLabel.Position = UDim2.new(0.5, 0, 1, 0)
	levelLabel.Size = UDim2.new(1, 0, 0, 20)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "LVL 1"
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.TextSize = 16
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextStrokeTransparency = 0
	levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabel.Parent = gui

	return gui
end

local function refresh(character: Model, gui: BillboardGui)
	local icon = gui:FindFirstChild("RankIcon")
	local levelLabel = gui:FindFirstChild("Level")

	local level = character:GetAttribute(LEVEL_ATTR)
	local rankTier = character:GetAttribute(RANK_TIER_ATTR)
	local arenaActive = character:GetAttribute(ARENA_ATTR) == true

	local hasData = typeof(level) == "number" or typeof(rankTier) == "number"
	gui.Enabled = hasData and not arenaActive

	if icon and icon:IsA("ImageLabel") then
		local assetId: string? = nil
		if typeof(rankTier) == "number" then
			assetId = Rank.getIconAsset(rankTier)
		end
		if assetId and assetId ~= "" then
			icon.Image = assetId
			icon.Visible = true
		else
			icon.Image = ""
			icon.Visible = false
		end
	end

	if levelLabel and levelLabel:IsA("TextLabel") then
		local lv = typeof(level) == "number" and level or 1
		levelLabel.Text = string.format("LVL %d", lv)
	end
end

local function bindCharacter(character: Model)
	local existing = character:FindFirstChild(BADGE_NAME)
	if existing then
		existing:Destroy()
	end
	local gui = createBadge(character)
	refresh(character, gui)

	for _, attr in ipairs({ LEVEL_ATTR, RANK_NAME_ATTR, RANK_TIER_ATTR, ARENA_ATTR }) do
		character:GetAttributeChangedSignal(attr):Connect(function()
			refresh(character, gui)
		end)
	end
end

local function bindPlayer(player: Player)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		bindCharacter(character)
	end)
end

function HeadBadgeController:Init(_controllers: { [string]: any }) end

function HeadBadgeController:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
end

return HeadBadgeController
