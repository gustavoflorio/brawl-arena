--!strict

-- DevController: painel flutuante de ferramentas dev. Só monta a UI se o
-- LocalPlayer tá em Constants.Dev.UserIds. A whitelist real é server-side
-- (DevService valida antes de aplicar mutação) — esta checagem aqui é só
-- pra esconder a UI dos jogadores normais.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local ACTIONS = Constants.Dev.Actions

-- DESIGN.md tokens
local COLOR_BG_DEEP = Color3.fromRGB(13, 15, 26)
local COLOR_BG_ELEVATED = Color3.fromRGB(28, 32, 56)
local COLOR_TEXT_PRIMARY = Color3.fromRGB(230, 232, 240)
local COLOR_TEXT_PURE = Color3.fromRGB(255, 255, 255)
local COLOR_TEXT_MUTED = Color3.fromRGB(160, 165, 184)
local COLOR_SUCCESS = Color3.fromRGB(74, 219, 122)
local COLOR_ERROR = Color3.fromRGB(255, 71, 87)
-- Vermelho de "modo dev" — visualmente distinto do warning amarelo.
local COLOR_DEV_ACCENT = Color3.fromRGB(220, 60, 90)
local COLOR_OUTLINE = Color3.fromRGB(0, 0, 0)

local FONT_HEADING = Enum.Font.GothamBlack
local FONT_LABEL = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.Gotham

local DevController = {}
DevController._gui = nil :: ScreenGui?
DevController._statusLabel = nil :: TextLabel?
DevController._busy = false
DevController._otherControllers = nil :: { [string]: any }?

local function isDev(userId: number): boolean
	for _, id in ipairs(Constants.Dev.UserIds) do
		if id == userId then
			return true
		end
	end
	return false
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

function DevController:_setStatus(text: string, color: Color3?)
	if not self._statusLabel then
		return
	end
	self._statusLabel.Text = text
	self._statusLabel.TextColor3 = color or COLOR_TEXT_MUTED
end

function DevController:_invokeDev(request: any): any
	local remote = Remotes.GetDevRemote()
	if not remote then
		return { success = false, reason = "NoRemote" }
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(request)
	end)
	if not ok then
		warn("[DevController] InvokeServer failed:", result)
		return { success = false, reason = "InvokeFailed" }
	end
	return result
end

function DevController:_grantCoins(amount: number)
	if self._busy then
		return
	end
	self._busy = true
	self:_setStatus("granting...", COLOR_TEXT_MUTED)

	local result = self:_invokeDev({ action = ACTIONS.GrantCoins, amount = amount })
	self._busy = false

	if typeof(result) == "table" and result.success then
		self:_setStatus(string.format("+%d coins (balance %d)", amount, result.newBalance or 0), COLOR_SUCCESS)
		-- Refresh shop UI se tiver aberta — usuário vê balance update na hora.
		local controllers = self._otherControllers
		if controllers then
			local shop = controllers.ShopController
			if shop and typeof(shop._refreshIfOpen) == "function" then
				shop:_refreshIfOpen()
			end
		end
	else
		local reason = (typeof(result) == "table" and result.reason) or "UnknownError"
		self:_setStatus("failed: " .. tostring(reason), COLOR_ERROR)
	end
end

local function buildGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanelGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
	panel.Size = UDim2.fromOffset(220, 130)
	panel.BackgroundColor3 = COLOR_BG_ELEVATED
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 10)
	stroke(panel, COLOR_DEV_ACCENT, 2)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = FONT_HEADING
	title.Text = "DEV TOOLS"
	title.TextSize = 14
	title.TextColor3 = COLOR_DEV_ACCENT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local btn = Instance.new("TextButton")
	btn.Name = "GrantCoinsBtn"
	btn.Position = UDim2.new(0, 0, 0, 24)
	btn.Size = UDim2.new(1, 0, 0, 40)
	btn.BackgroundColor3 = COLOR_BG_DEEP
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = FONT_LABEL
	btn.Text = "+500 COINS"
	btn.TextSize = 18
	btn.TextColor3 = COLOR_TEXT_PURE
	btn.Parent = panel
	corner(btn, 8)
	stroke(btn, COLOR_DEV_ACCENT, 1)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 0, 1, 0)
	status.Size = UDim2.new(1, 0, 0, 32)
	status.BackgroundTransparency = 1
	status.Font = FONT_BODY
	status.Text = ""
	status.TextSize = 13
	status.TextColor3 = COLOR_TEXT_MUTED
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextWrapped = true
	status.Parent = panel

	gui.Parent = playerGui
	return gui
end

function DevController:Init(controllers: { [string]: any })
	self._otherControllers = controllers
end

function DevController:Start()
	if not isDev(localPlayer.UserId) then
		return
	end

	self._gui = buildGui()
	local panel = self._gui:FindFirstChild("Panel") :: Frame?
	if not panel then
		return
	end
	self._statusLabel = panel:FindFirstChild("Status") :: TextLabel?
	local btn = panel:FindFirstChild("GrantCoinsBtn") :: TextButton?
	if btn then
		btn.Activated:Connect(function()
			DevController:_grantCoins(500)
		end)
	end
end

return DevController
