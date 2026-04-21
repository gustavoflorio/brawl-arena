# Brawl Arena

Jogo Roblox estilo brawl 2D (side-scroller) inspirado em Smash Bros. Código-fonte gerenciado via Rojo.

## Gameplay

- Cada soco acumula **% de dano** no alvo.
- Quanto maior a %, maior o knockback — eventualmente o jogador é arremessado pra fora da arena.
- Ao cair fora da plataforma (Y abaixo do kill threshold), o jogador volta ao lobby com a % zerada.
- Sem partidas formais: entre e saia da arena a qualquer momento pisando no pad do lobby.

## Como jogar

| Ação | Lobby | Arena |
| --- | --- | --- |
| Mover lateral | `A`/`D` | `A`/`D` |
| Pular | `Espaço` | `W` ou `Espaço` |
| Frente/trás | `W`/`S` (padrão Roblox) | bloqueado (side-scroller) — `S` reservado, sem ação |
| Socar (botão A) | — | `M1` — direção do soco = para onde o player está olhando |
| Botão B | — | `M2` (reservado, ainda sem ação) |
| Entrar na arena | Pisar no `SpawnPad` (pad neon laranja) | — |
| Sair da arena | — | Cair pra fora da `Platform` |

> **Mobile**: o plano é ter dois botões on-screen, `A` e `B`, mapeados respectivamente para `M1` e `M2`. Por enquanto só o `M1` (soco) está implementado.

**Câmera e movimento:**
- No **lobby**, câmera e movimento são livres em 3D (padrão Roblox).
- Na **arena**, a câmera vira lateral fixa (side-scroller), o eixo Z fica travado e `W`/`S` são remapeados (pulo/fast-fall).

## Estrutura do código

```
src/
├── ReplicatedStorage/Shared/
│   ├── Constants.lua           # Actions, tuning de combate e arena, estados
│   └── Net/Remotes.lua         # Getters de BrawlRequest / BrawlState
├── ServerScriptService/Server/
│   ├── Main.server.lua         # Cria remotes + chama ServiceLoader
│   ├── ServiceLoader.lua       # Load order dos services
│   └── Services/
│       ├── ArenaService.lua    # Estado por jogador, teleporte, out-of-bounds
│       └── CombatService.lua   # Punch request, hit overlap, knockback
└── StarterPlayer/StarterPlayerScripts/Client/
    ├── Main.client.lua             # Bootstrap dos controllers
    └── Controllers/
        ├── CameraController.lua    # Câmera lateral fixa (side-scroller) — só na arena
        ├── MovementController.lua  # Trava eixo Z + W pulo / S bloqueado na arena
        ├── CombatFxController.lua  # Animação local de soco + sons de hit/eliminação
        ├── InputController.lua     # M1 → BrawlRequest (Punch) + animação local
        └── HudController.lua       # Mostra % de dano e estado atual
```

## Animação e áudio

Assets reaproveitados do `pet_tycoon_roblox` (Strength Brawl), configurados em `Constants.Assets`:

| FX | Asset | Origem |
| --- | --- | --- |
| Animação de soco | `rbxassetid://105919524623967` | Animator do `Humanoid` do puncher (local) |
| Som de hit | `rbxassetid://139697578472716` | `Sound` parented no `HumanoidRootPart` do alvo |
| Som de eliminação | `rbxassetid://76627054450785` | `Sound` parented na `CurrentCamera` do local player |

Padrão de propagação (mesmo do pet_tycoon): server incrementa atributos no Character (`BrawlHitSeq`, `BrawlEliminationSeq`). Clients escutam via `GetAttributeChangedSignal` e tocam o FX — isso replica automaticamente entre os jogadores sem precisar de RemoteEvents dedicados.

## Arquitetura

Padrão adaptado do `pet_tycoon_roblox`:

- Services/controllers seguem o contrato `Init(deps) → Start()`.
- Server é a **fonte única de verdade** para estado e dano. Client envia requests (`BrawlRequest`), server publica snapshots (`BrawlState`).
- Todos os módulos usam `--!strict`.

Objetos do mundo (`Workspace.Lobby`, `Workspace.Arena`) ficam no arquivo de place (não versionados no Rojo) — os nomes esperados pelo código são:

- `Workspace.Lobby.LobbySpawn` (SpawnLocation)
- `Workspace.Lobby.SpawnPad` (Part com `Touched`)
- `Workspace.Lobby.LobbyFloor` (Part, chão do lobby)
- `Workspace.Arena.ArenaSpawn` (Part marker para CFrame do teleporte)
- `Workspace.Arena.Platform` (Part, plataforma de combate)

## Uso rápido

Com o [Rojo](https://rojo.space/) instalado:

```bash
# Servir live no Studio via plugin Rojo
rojo serve default.project.json

# Compilar para arquivo de place
rojo build default.project.json -o build.rbxlx
```

No Roblox Studio, abra o plugin Rojo e conecte na porta padrão (`34872`).

## Tuning

Todos os valores de combate estão em `src/ReplicatedStorage/Shared/Constants.lua`:

| Chave | Padrão | Descrição |
| --- | --- | --- |
| `Combat.PunchRange` | `5` | Raio (studs) do hit de soco |
| `Combat.PunchDamage` | `10` | % adicionados por soco |
| `Combat.PunchCooldown` | `0.4` | Segundos entre socos do mesmo jogador |
| `Combat.KnockbackBase` | `40` | Velocidade base do empurrão |
| `Combat.KnockbackGrowth` | `1.5` | Multiplicador por 100% de dano |
| `Combat.KnockbackVertical` | `35` | Componente vertical do knockback |
| `Arena.YKillThreshold` | `-50` | Y abaixo disso = volta pro lobby |

## Repositório

https://github.com/gustavoflorio/brawl-arena
