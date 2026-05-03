--!strict

-- Render-side smoothing pra chars remotos (não-LocalPlayer). Roblox replica
-- CFrame de chars de outros players a ~30Hz e tem interpolação built-in,
-- mas em redes irregulares ainda dá pra ver micro-stutters. Este controller
-- amostra a posição replicada a cada Heartbeat (post-physics, post-replication)
-- e re-renderiza no RenderStepped contra uma janela atrasada (~50ms),
-- lerpando entre samples bracketing pra um movimento contínuo.
--
-- Trade-off: oponente aparece ~50ms no passado (somado ao lag de rede já
-- existente). Em fighting games esse delay é aceitável — quem dá o input
-- continua sendo autoritativo via lag comp server-side.
--
-- Smoothing aplica SÓ posição. Rotação fica como veio (lockConnection no
-- dono do char já trata facing X discreto; lerpar rotação geraria interp
-- estranho na hora do char virar).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- 50ms de janela: precisa ser >= intervalo entre samples replicados (~33ms
-- em 30Hz) pra ter dois samples bracketing na hora de lerpar. Mais alto =
-- mais smoothing mas mais lag visual.
local RENDER_DELAY = 0.05
-- Histórico de samples mantido por char. 0.5s cobre spikes de rede até 500ms.
local HISTORY_SECONDS = 0.5

type Sample = { time: number, position: Vector3 }
type CharData = { samples: { Sample } }

local RemoteCharSmoother = {}
RemoteCharSmoother._chars = {} :: { [Model]: CharData }
RemoteCharSmoother._sampleConn = nil :: RBXScriptConnection?
RemoteCharSmoother._renderConn = nil :: RBXScriptConnection?

local localPlayer = Players.LocalPlayer

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function RemoteCharSmoother:Init(_controllers: any)
end

function RemoteCharSmoother:Start()
	-- Heartbeat: amostra posição replicada de cada char remoto. Heartbeat
	-- roda DEPOIS do physics step (e da replicação aplicada nele), então
	-- root.Position aqui é o valor que o servidor mandou nesse frame.
	self._sampleConn = RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, player in ipairs(Players:GetPlayers()) do
			if player == localPlayer then
				continue
			end
			local char = player.Character
			if not char or not char.Parent then
				continue
			end
			local root = getRoot(char)
			if not root then
				continue
			end
			local data = self._chars[char]
			if not data then
				data = { samples = {} }
				self._chars[char] = data
			end
			table.insert(data.samples, {
				time = now,
				position = root.Position,
			})
			-- Trim histórico antigo.
			local cutoff = now - HISTORY_SECONDS
			while data.samples[1] and data.samples[1].time < cutoff do
				table.remove(data.samples, 1)
			end
		end
		-- Cleanup de chars que sumiram (player saiu, respawn etc).
		for char in pairs(self._chars) do
			if not char.Parent then
				self._chars[char] = nil
			end
		end
	end)

	-- RenderStepped: roda antes do render do frame. Sobrescreve root.CFrame
	-- pra posição interpolada do passado. Override é efêmero — próximo
	-- physics step replica o valor do dono do char e sobrescreve de volta,
	-- então não dá pra desincronizar permanentemente.
	self._renderConn = RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local renderTime = now - RENDER_DELAY
		for char, data in pairs(self._chars) do
			local root = getRoot(char)
			if not root then
				continue
			end
			local samples = data.samples
			if #samples < 2 then
				continue
			end

			-- Acha bracket (before, after) tal que before.time <= renderTime < after.time.
			local before: Sample? = nil
			local after: Sample? = nil
			for i = #samples - 1, 1, -1 do
				if samples[i].time <= renderTime then
					before = samples[i]
					after = samples[i + 1]
					break
				end
			end
			-- renderTime mais antigo que o oldest sample: usa os dois mais antigos.
			if not before then
				before = samples[1]
				after = samples[2]
			end
			if not before or not after then
				continue
			end

			local span = after.time - before.time
			local alpha = if span > 0 then math.clamp((renderTime - before.time) / span, 0, 1) else 0
			local lerpedPos = before.position:Lerp(after.position, alpha)

			-- Mantém rotação atual (driven por lockConnection do dono replicado).
			local rotOnly = root.CFrame - root.CFrame.Position
			root.CFrame = CFrame.new(lerpedPos) * rotOnly
		end
	end)
end

return RemoteCharSmoother
