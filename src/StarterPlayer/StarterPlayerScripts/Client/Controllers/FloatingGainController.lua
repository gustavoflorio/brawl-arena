--!strict

-- Pops de ganho flutuantes estilo pet tycoon: ao derrubar um player, XP e FP
-- ganhos aparecem como labels que pulam na tela, flutuam pra cima e fadem.
-- Elementos independentes (uma coluna pra XP, uma pra FP) empilham quando
-- múltiplos ganhos disparam em sequência (ex: double/triple kill).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local ResponsiveLayout = require(script.Parent:WaitForChild("ResponsiveLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cores alinhadas ao DESIGN.md: XP usa semantic.success (verde), FP usa um
-- amber/gold alinhado com o sentimento competitivo do rank (mesma paleta do
-- NEUTRAL_COLOR em RankUpController pra coerência visual de rank feedback).
-- Coin reusa o tom dourado da moeda (RGB 255, 200, 30) pra o popup bater
-- visualmente com o objeto que foi pego.
local XP_COLOR = Color3.fromRGB(74, 219, 122)
local FP_COLOR = Color3.fromRGB(255, 220, 120)
local COIN_COLOR = Color3.fromRGB(255, 200, 30)

local POP_DURATION = 0.22
local FLOAT_DURATION = 1.0
local FADE_HOLD = 0.25
local FLOAT_DISTANCE = 70
local STACK_OFFSET = 42

-- Responsive scaling: design coords pra 1280x720; em viewports menores
-- (mobile) reduz pra manter proporção visual com o resto da HUD. min 0.55
-- evita ficar ilegível em phone portrait extremo, max 1 evita upscala em
-- monitor grande. Padrão da skill roblox-ui-creator.
local DESIGN_REFERENCE_WIDTH = 1280
local DESIGN_REFERENCE_HEIGHT = 720
local SCALE_MIN = 0.55
local SCALE_MAX = 1

type GainKind = "XP" | "FP" | "Coin"

type ColumnState = {
	frame: Frame,
	activeCount: number,
}

local FloatingGainController = {}
FloatingGainController._columns = {} :: { [GainKind]: ColumnState }
FloatingGainController._panelScale = nil :: UIScale?
FloatingGainController._viewportConn = nil :: RBXScriptConnection?
FloatingGainController._cameraChangedConn = nil :: RBXScriptConnection?

function FloatingGainController:Init(_controllers: { [string]: any }) end

function FloatingGainController:_applyResponsiveLayout()
	if not self._panelScale then
		return
	end
	local metrics = ResponsiveLayout.GetViewportMetrics()
	-- ReferenceScale: scale = min(viewport.X / 1280, viewport.Y / 720), clamped.
	-- Não usa GetViewportFitScale porque o popup é pequeno relativo ao viewport
	-- (fit-scale daria scale absurdamente grande). Queremos escala proporcional
	-- ao tamanho relativo da tela, não preencher bounds.
	local scale = ResponsiveLayout.GetReferenceScale(
		metrics,
		DESIGN_REFERENCE_WIDTH,
		DESIGN_REFERENCE_HEIGHT,
		1,
		1,
		SCALE_MIN,
		SCALE_MAX
	)
	self._panelScale.Scale = scale
end

local function buildColumn(parent: Instance, position: UDim2): ColumnState
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = UDim2.fromOffset(260, 60)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return { frame = frame, activeCount = 0 }
end

local function buildLabel(column: ColumnState, text: string, color: Color3, startYOffset: number): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, startYOffset)
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextTransparency = 1
	label.Parent = column.frame
	return label
end

function FloatingGainController:_spawnPop(kind: GainKind, amount: number)
	local column = self._columns[kind]
	if not column then
		return
	end

	local color: Color3
	local prefix: string
	if kind == "XP" then
		color = XP_COLOR
		prefix = "+%d XP"
	elseif kind == "FP" then
		color = FP_COLOR
		prefix = "+%d FP"
	else
		color = COIN_COLOR
		prefix = "+%d Coin"
	end
	local text = string.format(prefix, amount)

	local stackIdx = column.activeCount
	column.activeCount += 1

	-- Entradas mais recentes nascem mais baixas pra "empurrar" visualmente as
	-- anteriores; enquanto flutuam, as anteriores já estão mais pra cima.
	local startY = stackIdx * STACK_OFFSET
	local label = buildLabel(column, text, color, startY)

	local popIn = TweenService:Create(
		label,
		TweenInfo.new(POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(240, 56),
			TextTransparency = 0,
			TextStrokeTransparency = 0,
		}
	)
	popIn:Play()

	task.delay(POP_DURATION + FADE_HOLD, function()
		if not label.Parent then
			return
		end
		local floatOut = TweenService:Create(
			label,
			TweenInfo.new(FLOAT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(0.5, 0, 0.5, startY - FLOAT_DISTANCE),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}
		)
		floatOut:Play()
		floatOut.Completed:Connect(function()
			label:Destroy()
			column.activeCount = math.max(0, column.activeCount - 1)
		end)
	end)
end

function FloatingGainController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrawlFloatingGains"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Container fullscreen pra hospedar o UIScale responsivo. UIScale precisa
	-- de pai GuiObject (ScreenGui não conta como GuiObject). Não consome input
	-- — Active=false, BackgroundTransparency=1.
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Active = false
	container.Parent = gui

	self._panelScale = ResponsiveLayout.EnsureUiScale(container, "ResponsiveScale")

	-- Três colunas verticais empilhadas no lado direito da tela: XP em cima,
	-- FP no meio, Coin embaixo. Longe do centro pra não obstruir gameplay, mas
	-- na foveal do jogador (entre damage label central-bottom e a borda direita).
	-- Posições em scale: o UIScale do container reduz o size dos labels mas
	-- preserva os anchors em % da tela — pop sempre nasce no mesmo lugar visual.
	self._columns.XP = buildColumn(container, UDim2.fromScale(0.80, 0.42))
	self._columns.FP = buildColumn(container, UDim2.fromScale(0.80, 0.52))
	self._columns.Coin = buildColumn(container, UDim2.fromScale(0.80, 0.62))

	-- Aplica scale inicial + watchers de viewport (rotate de device, mid-game
	-- em outro aspect ratio, camera recriada).
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

	local remote = Remotes.GetEventsRemote()
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" then
			return
		end
		local payload = event.payload
		if typeof(payload) ~= "table" then
			return
		end
		if event.type == Constants.EventTypes.XPGain then
			if payload.puncherUserId ~= player.UserId then
				return
			end
			local amount = payload.amount
			if typeof(amount) == "number" and amount > 0 then
				self:_spawnPop("XP", amount)
			end
		elseif event.type == Constants.EventTypes.FPGain then
			if payload.userId ~= player.UserId then
				return
			end
			local amount = payload.amount
			if typeof(amount) == "number" and amount > 0 then
				self:_spawnPop("FP", amount)
			end
		elseif event.type == Constants.EventTypes.CoinGain then
			if payload.userId ~= player.UserId then
				return
			end
			local amount = payload.amount
			if typeof(amount) == "number" and amount > 0 then
				self:_spawnPop("Coin", amount)
			end
		end
	end)
end

return FloatingGainController
