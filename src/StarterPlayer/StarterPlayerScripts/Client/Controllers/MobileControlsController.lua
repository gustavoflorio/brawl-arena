--!strict

-- Controles mobile dedicados, ativos desde o spawn (lobby + arena).
-- Substitui o thumbstick + jump button padrão do Roblox por um D-Pad
-- (esq/dir/cima/baixo) + A/B à direita. Up do D-Pad = jump (inclui
-- double jump), Down = dodge, A = soco leve, B = soco pesado.
--
-- Desabilita o default PlayerModule logo no Start pra não deixar o
-- thumbstick padrão aparecendo como retângulo escuro no bottom-left.
--
-- Ativado só em dispositivos touch sem teclado (phones/tablets puros).
-- Em hybrid laptops com touch+teclado, deixamos o default funcionar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))

local player = Players.LocalPlayer

local DODGE_READY_COLOR = Color3.fromRGB(80, 200, 120)
local DODGE_COOLDOWN_BG_COLOR = Color3.fromRGB(28, 32, 56)
local DODGE_COOLDOWN_TOTAL = Constants.Combat.DodgeRollCooldown

local MobileControlsController = {}
MobileControlsController._controllers = nil :: { [string]: any }?
MobileControlsController._enabled = false
MobileControlsController._gui = nil :: ScreenGui?
MobileControlsController._moveConn = nil :: RBXScriptConnection?
MobileControlsController._dodgeVisConn = nil :: RBXScriptConnection?
MobileControlsController._downButton = nil :: TextButton?
MobileControlsController._downOverlay = nil :: Frame?
MobileControlsController._holdLeft = false
MobileControlsController._holdRight = false
MobileControlsController._controls = nil :: any?
MobileControlsController._controlsDisabled = false
MobileControlsController._characterConn = nil :: RBXScriptConnection?

local function isMobileDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getControls(): any?
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return nil
	end
	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript then
		return nil
	end
	local ok, playerModule = pcall(require, playerModuleScript)
	if not ok or not playerModule then
		return nil
	end
	local okControls, controls = pcall(function()
		return playerModule:GetControls()
	end)
	if not okControls then
		return nil
	end
	return controls
end

local IDLE_TRANSPARENCY = 0.55
local PRESSED_TRANSPARENCY = 0.2

local function setButtonPressed(btn: TextButton, pressed: boolean)
	btn.BackgroundTransparency = pressed and PRESSED_TRANSPARENCY or IDLE_TRANSPARENCY
end

function MobileControlsController:_bindHold(btn: TextButton, onChange: (boolean) -> ())
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setButtonPressed(btn, true)
			onChange(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setButtonPressed(btn, false)
			onChange(false)
		end
	end)
end

function MobileControlsController:_bindTap(btn: TextButton, onTap: () -> ())
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setButtonPressed(btn, true)
			onTap()
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setButtonPressed(btn, false)
		end
	end)
end

function MobileControlsController:_requestJump()
	local mc = self._controllers and self._controllers.MovementController
	if mc and type(mc.TryJump) == "function" then
		mc:TryJump()
	end
end

function MobileControlsController:_requestDodge()
	local mc = self._controllers and self._controllers.MovementController
	if mc and type(mc.TryDodge) == "function" then
		mc:TryDodge()
	end
end

function MobileControlsController:_requestPunch(isHeavy: boolean)
	local ic = self._controllers and self._controllers.InputController
	if ic and type(ic.FirePunch) == "function" then
		ic:FirePunch(isHeavy)
	end
end

local function makeDirButton(parent: Instance, name: string, text: string, anchor: Vector2, pos: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = anchor
	btn.Position = pos
	btn.Size = UDim2.new(0, 70, 0, 70)
	btn.BackgroundColor3 = Color3.fromRGB(28, 32, 56)
	btn.BackgroundTransparency = IDLE_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(230, 232, 240)
	btn.TextSize = 28
	btn.TextTransparency = 0.1
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = false
	btn.Active = true
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.5
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	return btn
end

local function makeActionButton(parent: Instance, name: string, label: string, color: Color3, anchor: Vector2, pos: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = anchor
	btn.Position = pos
	btn.Size = UDim2.new(0, 80, 0, 80)
	btn.BackgroundColor3 = color
	btn.BackgroundTransparency = IDLE_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.Text = label
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 30
	btn.TextTransparency = 0.05
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = false
	btn.Active = true
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2.5
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	return btn
end

function MobileControlsController:_buildGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlMobileControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = playerGui
	self._gui = gui

	-- D-Pad container (bottom-left, colado no canto)
	local pad = Instance.new("Frame")
	pad.Name = "DPad"
	pad.AnchorPoint = Vector2.new(0, 1)
	pad.Position = UDim2.new(0, 14, 1, -14)
	pad.Size = UDim2.new(0, 220, 0, 220)
	pad.BackgroundTransparency = 1
	pad.Parent = gui

	local up = makeDirButton(pad, "Up", "▲", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0))
	local down = makeDirButton(pad, "Down", "", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0))
	local left = makeDirButton(pad, "Left", "◀", Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0))
	local right = makeDirButton(pad, "Right", "▶", Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0))

	-- Down button = indicador de dodge ready. Bg verde quando pronto, overlay
	-- escuro drenando de baixo pra cima durante o cooldown. Mirror da lógica
	-- do DodgeCooldownController (desktop keeps o shell separado).
	local cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
	cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
	cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
	cooldownOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	cooldownOverlay.BackgroundTransparency = 0.2
	cooldownOverlay.BorderSizePixel = 0
	cooldownOverlay.ZIndex = 2
	cooldownOverlay.Parent = down

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 12)
	overlayCorner.Parent = cooldownOverlay

	-- Glyph ▼ como child com ZIndex > overlay, pra seta sempre ser visível
	-- mesmo quando o overlay cobre o botão.
	local downGlyph = Instance.new("TextLabel")
	downGlyph.Name = "Glyph"
	downGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	downGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
	downGlyph.Size = UDim2.new(1, 0, 1, 0)
	downGlyph.BackgroundTransparency = 1
	downGlyph.Text = "▼"
	downGlyph.TextColor3 = Color3.fromRGB(255, 255, 255)
	downGlyph.TextSize = 28
	downGlyph.TextTransparency = 0.05
	downGlyph.Font = Enum.Font.GothamBold
	downGlyph.TextStrokeTransparency = 0.4
	downGlyph.ZIndex = 3
	downGlyph.Parent = down

	self._downButton = down
	self._downOverlay = cooldownOverlay

	self:_bindHold(left, function(pressed)
		self._holdLeft = pressed
	end)
	self:_bindHold(right, function(pressed)
		self._holdRight = pressed
	end)
	self:_bindTap(up, function()
		self:_requestJump()
	end)
	self:_bindTap(down, function()
		self:_requestDodge()
	end)

	-- Action buttons container (bottom-right, colado no canto)
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.AnchorPoint = Vector2.new(1, 1)
	actions.Position = UDim2.new(1, -14, 1, -14)
	actions.Size = UDim2.new(0, 190, 0, 170)
	actions.BackgroundTransparency = 1
	actions.Parent = gui

	local a = makeActionButton(
		actions,
		"A",
		"A",
		Color3.fromRGB(74, 158, 255),
		Vector2.new(0, 1),
		UDim2.new(0, 0, 1, 0)
	)
	local b = makeActionButton(
		actions,
		"B",
		"B",
		Color3.fromRGB(255, 140, 66),
		Vector2.new(1, 0),
		UDim2.new(1, 0, 0, 0)
	)

	self:_bindTap(a, function()
		self:_requestPunch(false)
	end)
	self:_bindTap(b, function()
		self:_requestPunch(true)
	end)
end

function MobileControlsController:_disableDefaultControls()
	if self._controlsDisabled then
		return
	end
	local controls = self._controls or getControls()
	if not controls then
		return
	end
	self._controls = controls
	local ok = pcall(function()
		controls:Disable()
	end)
	if ok then
		self._controlsDisabled = true
	end
end

function MobileControlsController:_startMovementDriver()
	if self._moveConn then
		return
	end
	self._moveConn = RunService.Heartbeat:Connect(function()
		local humanoid = getHumanoid()
		if not humanoid then
			return
		end
		local x = 0
		if self._holdLeft then
			x -= 1
		end
		if self._holdRight then
			x += 1
		end
		-- relativeToCamera=false: world-space. A câmera da arena é fixa
		-- no eixo X, então world-space bate direto com a direção visual.
		humanoid:Move(Vector3.new(x, 0, 0), false)
	end)
end

function MobileControlsController:_startDodgeVisDriver()
	if self._dodgeVisConn then
		return
	end
	self._dodgeVisConn = RunService.Heartbeat:Connect(function()
		local btn = self._downButton
		local overlay = self._downOverlay
		if not btn or not overlay then
			return
		end
		local mc = self._controllers and self._controllers.MovementController
		if not mc or type(mc.GetDodgeCooldownRemaining) ~= "function" then
			return
		end
		local remaining = mc:GetDodgeCooldownRemaining()
		if remaining <= 0 then
			btn.BackgroundColor3 = DODGE_READY_COLOR
			overlay.Size = UDim2.new(1, 0, 0, 0)
		else
			btn.BackgroundColor3 = DODGE_COOLDOWN_BG_COLOR
			local pct = math.clamp(remaining / DODGE_COOLDOWN_TOTAL, 0, 1)
			overlay.Size = UDim2.new(1, 0, pct, 0)
		end
	end)
end

function MobileControlsController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function MobileControlsController:Start()
	if not isMobileDevice() then
		return
	end
	self._enabled = true

	-- D-Pad ativo desde o spawn em mobile (lobby + arena). Sem isso, o
	-- thumbstick default do Roblox aparece como retângulo escuro no canto
	-- inferior esquerdo do lobby.
	self:_disableDefaultControls()
	self:_buildGui()
	self:_startMovementDriver()
	self:_startDodgeVisDriver()

	-- Respawns re-criam o character e o PlayerModule.controls pode re-enable
	-- os default controls. Re-disable defensivamente a cada respawn.
	self._characterConn = player.CharacterAdded:Connect(function()
		task.defer(function()
			if self._enabled then
				self:_disableDefaultControls()
			end
		end)
	end)
end

return MobileControlsController
