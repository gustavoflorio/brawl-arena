--!strict

-- ClassOutlineController: Highlight outline cor-coded por classe em arena.
-- Client-side per viewer (cada client computa state machine local lendo Character
-- attributes que já replicam server→clients). Visibilidade arena-only.
--
-- State machine (5 estados):
--   Spawn / invul:    pulsa em transparency baixa pelo InvincibleUntil window.
--   Normal combat:    transparency baseline alto (sutil); LocalPlayer dimmer.
--   Heavy / signature (LOCAL only): snap pra mais visível no momento do heavy,
--                                   ease back pra baseline. Cross-client signature
--                                   snap deferido pra PR futura (cosmético).
--   Hit / hitstun:    Highlight.Enabled=false (hit FX owns o pixel).
--   KO:               pulsa transparency 0.7→0.0 over ~400ms, fade com body.
--
-- Phase offset: pulsos derivam de UserId%N — round start não strobeia 4 chars
-- sincronizados.
--
-- Per-Player conn table: dispara cleanup explícito em CharacterAdded pra evitar
-- closures capturando Highlight destruído (state machine é mais sensível a leak
-- que BillboardGui fire-and-forget do HeadBadge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(sharedFolder:WaitForChild("Constants"))
local Classes = require(sharedFolder:WaitForChild("Classes"))
local Remotes = require(sharedFolder:WaitForChild("Net"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer

local CLASS_ID_ATTR = Constants.CharacterAttributes.ClassId
local ARENA_ACTIVE_ATTR = Constants.CharacterAttributes.ArenaActive
local INVUL_ATTR = Constants.CharacterAttributes.InvincibleUntil
local HITSTOP_UNTIL_ATTR = Constants.CharacterAttributes.HitStopUntil

local HIGHLIGHT_NAME = "BrawlClassOutline"
local OUTLINE_THICKNESS = 4

-- Transparency targets por estado. Quanto maior, mais sutil; 1.0 = invisível.
-- Calibração v2 (2026-05-02): primeiro tuning ficou subdimensionado em arena
-- com 4 chars + hit FX competindo — outlines sumiam. Subimos visibilidade
-- baseline + spawn peak. LocalPlayer offset: +0.20 (próprio char ainda dimmer
-- que remotes pra reduzir self-clutter, mas visível).
local TRANS_SPAWN_PEAK = 0.0
local TRANS_NORMAL_REMOTE = 0.35
local TRANS_NORMAL_LOCAL = 0.55
local TRANS_HEAVY_PEAK = 0.10
local TRANS_KO_PEAK = 0.0

local SPAWN_PULSE_HZ = 1.5
local SPAWN_FADEOUT_DURATION = 0.5
local HEAVY_HOLD_DURATION = 0.25
local HEAVY_EASE_DURATION = 0.20
local KO_PULSE_DURATION = 0.40

type CharacterBinding = {
	character: Model,
	highlight: Highlight,
	conns: { RBXScriptConnection },
	heartbeatConn: RBXScriptConnection?,
	heavyExpiresAt: number,
	koActiveUntil: number,
	phaseOffset: number,
	isLocal: boolean,
}

local ClassOutlineController = {}
ClassOutlineController._controllers = nil :: { [string]: any }?
ClassOutlineController._bindings = {} :: { [Player]: CharacterBinding }

local function resolveAccentColor(character: Model): Color3
	local classId = character:GetAttribute(CLASS_ID_ATTR)
	if typeof(classId) ~= "string" then
		classId = Classes.GetDefaultId()
	end
	local classDef = Classes.GetClass(classId :: string) or Classes.GetDefault()
	return classDef.AccentColor or Color3.fromRGB(255, 255, 255)
end

local function isInArena(character: Model): boolean
	return character:GetAttribute(ARENA_ACTIVE_ATTR) == true
end

local function isInInvul(character: Model): boolean
	-- InvincibleUntil é setado pelo servidor com Workspace:GetServerTimeNow()
	-- (clock sincronizado). Comparar com os.clock() local geraria mismatch
	-- enorme (mesma armadilha do HitStopUntil — ver InputController).
	local until_ = character:GetAttribute(INVUL_ATTR)
	if typeof(until_) ~= "number" then
		return false
	end
	return until_ > Workspace:GetServerTimeNow()
end

local function isInHitstop(character: Model): boolean
	local until_ = character:GetAttribute(HITSTOP_UNTIL_ATTR)
	if typeof(until_) ~= "number" then
		return false
	end
	return until_ > Workspace:GetServerTimeNow()
end

local function disconnectAll(binding: CharacterBinding)
	for _, conn in ipairs(binding.conns) do
		conn:Disconnect()
	end
	binding.conns = {}
	if binding.heartbeatConn then
		binding.heartbeatConn:Disconnect()
		binding.heartbeatConn = nil
	end
end

local function destroyBinding(binding: CharacterBinding)
	disconnectAll(binding)
	if binding.highlight.Parent then
		binding.highlight:Destroy()
	end
end

local function applyState(binding: CharacterBinding)
	-- evaluateState() inline: lê attributes + clocks transientes (heavy/ko) pra
	-- escolher transparency target. Highlight.Enabled gateado por arena+hitstop.
	local character = binding.character
	local highlight = binding.highlight

	highlight.OutlineColor = resolveAccentColor(character)

	if not isInArena(character) then
		highlight.Enabled = false
		return
	end

	if isInHitstop(character) then
		-- Hit FX owns pixel. Disable outline pelo window inteiro.
		highlight.Enabled = false
		return
	end

	highlight.Enabled = true
	local now = os.clock()
	local baselineTrans = if binding.isLocal then TRANS_NORMAL_LOCAL else TRANS_NORMAL_REMOTE

	-- KO pulse: dura ~400ms da elim seq. Sobrepõe-se a tudo (exceto hitstop, já
	-- tratado acima — KO normalmente fora do hitstop window).
	if now < binding.koActiveUntil then
		local progress = 1 - (binding.koActiveUntil - now) / KO_PULSE_DURATION
		progress = math.clamp(progress, 0, 1)
		-- Easing Back-style: dispara pra peak rápido, easeout
		local pulse = 1 - (1 - progress) * (1 - progress)
		highlight.OutlineTransparency = TRANS_KO_PEAK + (baselineTrans - TRANS_KO_PEAK) * pulse
		return
	end

	-- Heavy/signature snap (LOCAL only): hold 250ms em peak, ease 200ms back.
	if binding.isLocal and now < binding.heavyExpiresAt then
		local remaining = binding.heavyExpiresAt - now
		if remaining > HEAVY_EASE_DURATION then
			-- Hold phase
			highlight.OutlineTransparency = TRANS_HEAVY_PEAK
		else
			-- Ease phase: lerp peak → baseline
			local easeProgress = 1 - remaining / HEAVY_EASE_DURATION
			highlight.OutlineTransparency = TRANS_HEAVY_PEAK + (baselineTrans - TRANS_HEAVY_PEAK) * easeProgress
		end
		return
	end

	-- Spawn invul: pulse cosseno em ~1.5Hz pelo window. Phase offset por player
	-- evita 4-player strobe sincronizado.
	if isInInvul(character) then
		local phase = (now + binding.phaseOffset) * SPAWN_PULSE_HZ * math.pi * 2
		local pulse = (math.cos(phase) + 1) * 0.5 -- 0..1
		highlight.OutlineTransparency = TRANS_SPAWN_PEAK + (baselineTrans - TRANS_SPAWN_PEAK) * pulse
		return
	end

	-- Normal combat: baseline.
	highlight.OutlineTransparency = baselineTrans
end

local function ensureHeartbeat(binding: CharacterBinding)
	-- Heartbeat só roda quando há estado transiente (heavy ou KO ativos, ou
	-- spawn invul). Em normal combat estático não há nada pra animar e o
	-- Heartbeat fica disconnected pra economizar tick budget.
	if binding.heartbeatConn then
		return
	end
	binding.heartbeatConn = RunService.Heartbeat:Connect(function()
		applyState(binding)
		local now = os.clock()
		local stillTransient = now < binding.heavyExpiresAt
			or now < binding.koActiveUntil
			or isInInvul(binding.character)
		if not stillTransient then
			-- Done with transients — disconnect Heartbeat. Próximo evento (hit,
			-- KO, novo heavy) reativa.
			if binding.heartbeatConn then
				binding.heartbeatConn:Disconnect()
				binding.heartbeatConn = nil
			end
			-- Settle final: garante baseline aplicado (caso último frame caiu
			-- exatamente na borda da invul window).
			applyState(binding)
		end
	end)
end

function ClassOutlineController:_bindCharacter(player: Player, character: Model)
	-- Cleanup binding antigo (respawn) — disconnect explícito, nada de fire-and-forget.
	local existing = self._bindings[player]
	if existing then
		destroyBinding(existing)
		self._bindings[player] = nil
	end

	character:WaitForChild("HumanoidRootPart", 5)
	if not character:IsDescendantOf(workspace) then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1 -- starts invisible até primeiro applyState
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = character
	highlight.Parent = character

	local binding: CharacterBinding = {
		character = character,
		highlight = highlight,
		conns = {},
		heartbeatConn = nil,
		heavyExpiresAt = 0,
		koActiveUntil = 0,
		-- Phase offset: 0..1 segundos espalhados pelos UserIds dos players.
		-- 8 = max esperado de players por server; granularidade fina suficiente.
		phaseOffset = (player.UserId % 8) / 8,
		isLocal = player == localPlayer,
	}

	-- Attribute listeners: cada um (re)avalia state e potencialmente reativa Heartbeat.
	local function onChange()
		applyState(binding)
		if isInInvul(character) or os.clock() < binding.heavyExpiresAt or os.clock() < binding.koActiveUntil then
			ensureHeartbeat(binding)
		end
	end

	for _, attr in ipairs({ CLASS_ID_ATTR, ARENA_ACTIVE_ATTR, INVUL_ATTR, HITSTOP_UNTIL_ATTR }) do
		table.insert(binding.conns, character:GetAttributeChangedSignal(attr):Connect(onChange))
	end

	-- KO pulse trigger vem via Constants.CombatPulseTypes.Elimination remote
	-- (subscrito em Start). Antes era ELIM_SEQ attribute change; agora unificado
	-- com o resto dos pulsos de combat pra responder mais rápido.

	self._bindings[player] = binding
	applyState(binding)
	-- Se entrou já em invul ou ArenaActive recente, pode precisar de Heartbeat.
	if isInInvul(character) then
		ensureHeartbeat(binding)
	end
end

function ClassOutlineController:_bindPlayer(player: Player)
	if player.Character then
		task.spawn(function()
			self:_bindCharacter(player, player.Character :: Model)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		local binding = self._bindings[player]
		if binding then
			destroyBinding(binding)
			self._bindings[player] = nil
		end
	end)
end

-- API pública: chamada pelo InputController quando heavy/signature move começa
-- (LOCAL player only). Triggera o snap de transparency.
function ClassOutlineController:NotifyLocalSignatureMove()
	local binding = self._bindings[localPlayer]
	if not binding or not binding.isLocal then
		return
	end
	binding.heavyExpiresAt = os.clock() + HEAVY_HOLD_DURATION + HEAVY_EASE_DURATION
	ensureHeartbeat(binding)
end

function ClassOutlineController:Init(controllers: { [string]: any })
	self._controllers = controllers
end

function ClassOutlineController:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local binding = self._bindings[player]
		if binding then
			destroyBinding(binding)
			self._bindings[player] = nil
		end
	end)

	-- Combat pulse: escuta só Elimination pra disparar KO pulse no outline.
	-- Outros eventos (Hit/HitStop/KB) são tratados em CombatFxController.
	local pulseRemote = Remotes.GetCombatPulseRemote()
	if pulseRemote then
		pulseRemote.OnClientEvent:Connect(function(eventType: any, character: any, _payload: any)
			if eventType ~= Constants.CombatPulseTypes.Elimination then
				return
			end
			if typeof(character) ~= "Instance" or not character:IsA("Model") then
				return
			end
			for _, binding in pairs(self._bindings) do
				if binding.character == character then
					binding.koActiveUntil = os.clock() + KO_PULSE_DURATION
					ensureHeartbeat(binding)
					break
				end
			end
		end)
	end
end

return ClassOutlineController
