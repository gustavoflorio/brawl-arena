--!strict

-- Controles mobile dedicados, ativos desde o spawn (lobby + arena).
-- Substitui 100% do sistema default do Roblox:
--   * GuiService.TouchControlsEnabled = false → esconde thumbstick/jump
--   * PlayerModule:GetControls():Disable() → desliga input default
--   * hideTouchGuiBackgrounds → belt-and-suspenders em qualquer visual residual
--
-- Lobby: zona de toque invisível fullscreen, arrasta esquerda/direita pra
-- mover. Zero UI visível.
--
-- Arena: D-Pad (esq/dir/cima/baixo) + A/B à direita. Up = jump (inclui
-- double), Down = dodge, A = soco leve, B = soco pesado.
--
-- Ativado só em dispositivos touch sem teclado (phones/tablets puros).
-- Em hybrid laptops com touch+teclado, deixamos o default funcionar.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local DODGE_READY_COLOR = Color3.fromRGB(80, 200, 120)
local DODGE_COOLDOWN_BG_COLOR = Color3.fromRGB(28, 32, 56)
local DODGE_COOLDOWN_TOTAL = Constants.Combat.DodgeRollCooldown

local MobileControlsController = {}
MobileControlsController._controllers = nil :: { [string]: any }?
MobileControlsController._enabled = false
MobileControlsController._gui = nil :: ScreenGui?
MobileControlsController._currentState = Constants.PlayerState.InLobby
MobileControlsController._moveConn = nil :: RBXScriptConnection?
MobileControlsController._dodgeVisConn = nil :: RBXScriptConnection?
MobileControlsController._downButton = nil :: TextButton?
MobileControlsController._downOverlay = nil :: Frame?
MobileControlsController._holdLeft = false
MobileControlsController._holdRight = false
MobileControlsController._controls = nil :: any?
MobileControlsController._controlsDisabled = false
MobileControlsController._characterConn = nil :: RBXScriptConnection?
MobileControlsController._lobbyGui = nil :: ScreenGui?
MobileControlsController._lobbyMoveConn = nil :: RBXScriptConnection?
MobileControlsController._lobbyHoldX = 0

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

function MobileControlsController:_destroyGui()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
	self._holdLeft = false
	self._holdRight = false
	self._downButton = nil
	self._downOverlay = nil
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

function MobileControlsController:_enableDefaultControls()
	if not self._controlsDisabled then
		return
	end
	local controls = self._controls
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
	self._controlsDisabled = false
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

function MobileControlsController:_stopDodgeVisDriver()
	if self._dodgeVisConn then
		self._dodgeVisConn:Disconnect()
		self._dodgeVisConn = nil
	end
end

function MobileControlsController:_stopMovementDriver()
	if self._moveConn then
		self._moveConn:Disconnect()
		self._moveConn = nil
	end
	local humanoid = getHumanoid()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end
end

-- Lobby: touch zone invisível fullscreen + Heartbeat driver que lê
-- posição do dedo relativa ao X center da tela pra decidir direção.
-- Zero visual — nada escuro aparece no canto.
function MobileControlsController:_buildLobbyGui()
	if self._lobbyGui then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlLobbyTouchMove"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1
	gui.Parent = playerGui
	self._lobbyGui = gui

	local zone = Instance.new("TextButton")
	zone.Name = "TouchZone"
	zone.Size = UDim2.new(1, 0, 1, 0)
	zone.BackgroundTransparency = 1
	zone.Text = ""
	zone.AutoButtonColor = false
	zone.Active = true
	zone.Modal = false
	zone.Parent = gui

	local activeInput: InputObject? = nil
	local startX = 0

	zone.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not activeInput then
			activeInput = input
			startX = input.Position.X
			self._lobbyHoldX = 0
		end
	end)

	zone.InputChanged:Connect(function(input)
		if input == activeInput and input.UserInputType == Enum.UserInputType.Touch then
			local dx = input.Position.X - startX
			local threshold = 12
			if dx < -threshold then
				self._lobbyHoldX = -1
			elseif dx > threshold then
				self._lobbyHoldX = 1
			else
				self._lobbyHoldX = 0
			end
		end
	end)

	zone.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
			self._lobbyHoldX = 0
		end
	end)

	self._lobbyMoveConn = RunService.Heartbeat:Connect(function()
		local humanoid = getHumanoid()
		if not humanoid then
			return
		end
		humanoid:Move(Vector3.new(self._lobbyHoldX, 0, 0), false)
	end)
end

function MobileControlsController:_destroyLobbyGui()
	if self._lobbyMoveConn then
		self._lobbyMoveConn:Disconnect()
		self._lobbyMoveConn = nil
	end
	if self._lobbyGui then
		self._lobbyGui:Destroy()
		self._lobbyGui = nil
	end
	self._lobbyHoldX = 0
	local humanoid = getHumanoid()
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end
end

function MobileControlsController:_enterArena()
	self:_destroyLobbyGui()
	self:_buildGui()
	self:_startMovementDriver()
	self:_startDodgeVisDriver()
end

function MobileControlsController:_exitArena()
	self:_stopDodgeVisDriver()
	self:_stopMovementDriver()
	self:_destroyGui()
	self:_buildLobbyGui()
end

function MobileControlsController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

-- Patch defensivo: apaga visuals do thumbstick default do Roblox (Frame
-- backgrounds + ImageLabels da base/nub). Mantém JumpButton visível e
-- touch ainda funciona (ImageTransparency só afeta render, não hit test).
local function isThumbstickElement(instance: Instance): boolean
	local name = instance.Name:lower()
	-- Classic: ThumbstickFrame, OuterImage, CenterImage, NubFrame
	-- Dynamic: DynamicThumbstickFrame, ThumbstickRing, ThumbstickArrow, NubFrame
	return name:find("thumb") ~= nil
		or name:find("nub") ~= nil
		or name == "outerimage"
		or name == "centerimage"
end

local function hideTouchGuiBackgrounds(playerGui: PlayerGui)
	local function killVisual(instance: Instance)
		if instance:IsA("Frame") then
			instance.BackgroundTransparency = 1
		elseif instance:IsA("ImageLabel") and isThumbstickElement(instance) then
			instance.ImageTransparency = 1
			instance.BackgroundTransparency = 1
		end
	end

	local function patch(gui: Instance)
		for _, descendant in ipairs(gui:GetDescendants()) do
			killVisual(descendant)
		end
		gui.DescendantAdded:Connect(killVisual)
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == "TouchGui" then
			patch(child)
		end
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			patch(child)
		end
	end)
end

function MobileControlsController:Start()
	if not isMobileDevice() then
		return
	end
	self._enabled = true

	-- Nuke total dos controles default do Roblox em mobile, desde o Start.
	-- GuiService.TouchControlsEnabled=false é o golden bullet pra esconder
	-- o visual (thumbstick base + jump button). controls:Disable() mata
	-- o input handling default. hideTouchGuiBackgrounds é belt-and-suspenders
	-- caso algum visual teimoso continue. Com isso lobby fica sem retângulo.
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	self:_disableDefaultControls()
	hideTouchGuiBackgrounds(player:WaitForChild("PlayerGui"))

	-- Lobby usa zona de toque invisível fullscreen pra mover: toca +
	-- arrasta esquerda/direita. Sem visual.
	self:_buildLobbyGui()

	-- Respawns re-criam o character e o PlayerModule.controls pode
	-- re-enable default controls + TouchControlsEnabled. Re-aplica
	-- defensivamente a cada respawn.
	self._characterConn = player.CharacterAdded:Connect(function()
		task.defer(function()
			if not self._enabled then
				return
			end
			pcall(function()
				GuiService.TouchControlsEnabled = false
			end)
			self:_disableDefaultControls()
		end)
	end)

	local remote = Remotes.GetStateRemote()
	if not remote then
		warn("[MobileControlsController] BrawlState remote não encontrado.")
		return
	end
	remote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		local state = snapshot.state
		if typeof(state) ~= "string" then
			return
		end
		if state == self._currentState then
			return
		end
		self._currentState = state
		if state == Constants.PlayerState.InArena then
			self:_enterArena()
		else
			self:_exitArena()
		end
	end)
end

return MobileControlsController
