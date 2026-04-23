--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local DAMAGE_ATTR = Constants.CharacterAttributes.DamagePercent
local ARENA_ATTR = Constants.CharacterAttributes.ArenaActive

local DamageLabelController = {}

local function pickColor(damage: number): Color3
	local t = math.clamp(damage / 150, 0, 1)
	local r = math.clamp(t * 255, 120, 255)
	local g = math.clamp(255 * (1 - t), 40, 255)
	return Color3.fromRGB(r, g, 60)
end

local function createLabel(character: Model): BillboardGui
	-- Adornee no HRP (estável mesmo durante flip do double jump e roll do dodge);
	-- usar Head fazia o label seguir a part rotacionada pela animation, virando junto.
	local hrp = character:WaitForChild("HumanoidRootPart", 5) :: Instance?
	local gui = Instance.new("BillboardGui")
	gui.Name = "BrawlDamageLabel"
	gui.Size = UDim2.new(0, 90, 0, 32)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = hrp
	gui.Enabled = false
	gui.Parent = character

	local label = Instance.new("TextLabel")
	label.Name = "DamageText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "0%"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	return gui
end

local function refresh(character: Model, gui: BillboardGui)
	local label = gui:FindFirstChild("DamageText")
	if not label or not label:IsA("TextLabel") then
		return
	end
	local damageAttr = character:GetAttribute(DAMAGE_ATTR)
	local arenaAttr = character:GetAttribute(ARENA_ATTR)
	local active = arenaAttr == true
	local damage = typeof(damageAttr) == "number" and damageAttr or 0
	gui.Enabled = active
	label.Text = string.format("%d%%", math.floor(damage))
	label.TextColor3 = pickColor(damage)
end

local function bindCharacter(character: Model)
	local existing = character:FindFirstChild("BrawlDamageLabel")
	if existing then
		existing:Destroy()
	end
	local gui = createLabel(character)
	refresh(character, gui)

	character:GetAttributeChangedSignal(DAMAGE_ATTR):Connect(function()
		refresh(character, gui)
	end)
	character:GetAttributeChangedSignal(ARENA_ATTR):Connect(function()
		refresh(character, gui)
	end)
end

local function bindPlayer(player: Player)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		bindCharacter(character)
	end)
end

function DamageLabelController:Init(_controllers: { [string]: any }) end

function DamageLabelController:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerAdded:Connect(bindPlayer)
end

return DamageLabelController
