# Design System — Brawl Arena

Documento-fonte de verdade pras decisões visuais. Ler **antes** de tocar em UI, HUD, FX de tela, cores de partículas ou tipografia. Desvios precisam de aprovação explícita.

---

## Product Context

- **O que é:** jogo Roblox 2D side-scroller brawl, estilo Smash Bros. Ciclo rápido: entra arena → soca → é arremessado → volta ao lobby.
- **Para quem:** jogadores de Roblox que curtem PvP punchy, cadência alta, skill ceiling decente mas onboarding instantâneo.
- **Espaço:** fighting/brawler no Roblox. Concorrentes diretos: Combat Initiation, Ability Wars, Smash Legends-likes.
- **Project type:** jogo Roblox (Luau + Rojo). UI via ScreenGui/Frame, cores via `Color3.fromRGB`, fontes via `Enum.Font` — **não** usar Google Fonts, CSS ou hex strings diretamente no código.

---

## Aesthetic Direction

- **Direção:** Arcade Neon Brawl — dark + high-contrast + energético.
- **Decoration level:** intentional (glow em damage label, outlines chunky em UI crítica, scanlines sutis ~2% opacity no HUD).
- **Mood:** entre Brawlhalla (competitivo sério) e Smash clássico (arcade puro). Vende "soco parece bom" sem virar cafona.
- **Referência mental:** HUD de fighting game arcade dos anos 90-00 modernizado. Personalidade, não "tasteful gray webapp".

---

## Color

Roblox usa `Color3.fromRGB(r, g, b)`. Abaixo os valores RGB e um apelido pra usar em `ReplicatedStorage/Shared/Theme.lua` (sugestão — criar se não existir).

### Backgrounds

| Token | RGB | Uso |
| --- | --- | --- |
| `bg.deep` | `13, 15, 26` | Tela cheia, loading screen, summary overlay |
| `bg.surface` | `20, 24, 44` | Paineis principais (HUD, menus) |
| `bg.elevated` | `28, 32, 56` | Linhas de ranking, cards, itens de lista |
| `bg.arena` | `16, 16, 24` | Backdrop da própria arena (mantém o valor já em uso) |

### Neutrals

| Token | RGB | Uso |
| --- | --- | --- |
| `text.primary` | `230, 232, 240` | Texto principal em painéis |
| `text.pure` | `255, 255, 255` | Damage label, KO banners, emphasis absoluto |
| `text.muted` | `160, 165, 184` | Labels secundárias, footer, subtítulos |
| `text.dim` | `120, 120, 140` | Footer, hint text, disabled |

### Player Colors (4 distintas — crítico pra leitura em 4-player brawl)

| Token | RGB | Uso |
| --- | --- | --- |
| `player.p1` | `255, 107, 53` | Player 1 — orange |
| `player.p2` | `0, 217, 255` | Player 2 — cyan |
| `player.p3` | `255, 61, 165` | Player 3 — magenta |
| `player.p4` | `155, 255, 74` | Player 4 — lime |

Hit effects, kill feed markers, nameplates e accents devem usar essas cores conforme o player envolvido.

### Damage Escalation

Gradiente contínuo no `DamageLabelController` conforme % aumenta:

| Range | Cor RGB | Intenção |
| --- | --- | --- |
| 0-30% | `255, 255, 255` branco | Neutro, "ainda tá limpo" |
| 30-80% | `255, 217, 74` amarelo | "Tá ficando perigoso" |
| 80-130% | `255, 140, 66` laranja | "Zona de KO" |
| 130%+ | `255, 58, 58` vermelho | "Um toque e sai" |

Interpolar entre os pontos (não degraus visíveis).

### Semantic

| Token | RGB | Uso |
| --- | --- | --- |
| `semantic.success` | `74, 219, 122` | XP gained, level up, positive feedback |
| `semantic.warning` | `255, 203, 43` | Low HP warning, rank threshold close |
| `semantic.error` | `255, 71, 87` | Kills feed, elimination, negative feedback |
| `semantic.info` | `74, 158, 255` | Level display, neutral information |

### Streak Colors (manter valores atuais — já consistentes)

| Tipo | RGB |
| --- | --- |
| `Double` | `255, 220, 80` |
| `Dominating` | `255, 60, 60` |

---

## Typography

Roblox tem fonte limitada — usar `Enum.Font`. **Não usar fontes customizadas/imported** (overhead de asset, problemas em mobile). Para display/impact, Roblox oferece fontes chunky nativas.

| Role | Font | Uso |
| --- | --- | --- |
| Display | `Enum.Font.Sarpanch` | Damage label center-bottom, KO banner, match titles |
| Display alt | `Enum.Font.Bangers` | Streak labels ("DOUBLE KILL!"), big arcade moments |
| Headings | `Enum.Font.GothamBlack` | Section titles ("TOP KILLS"), level display |
| Labels/emphasis | `Enum.Font.GothamBold` | Nomes, stats, labels |
| Body | `Enum.Font.Gotham` | Texto corrido, subtítulos, footer |
| Numbers | `Enum.Font.GothamBold` | Stats numéricos, ranking positions (usa `TextScaled` ou tabular spacing quando possível) |

### Scale (TextSize)

| Role | Size | Contexto |
| --- | --- | --- |
| Damage label (mid) | 64 | HUD central, escalável via TextScaled |
| KO banner | 72 | Full-screen eliminação |
| Section title | 32 | Menu headers |
| Subsection | 20 | Card headers |
| Body | 16 | Texto corrido |
| Caption | 13 | Footer, hint |

Em mobile (aspect ratio diferente), usar `TextScaled = true` com `UITextSizeConstraint` pra não explodir.

---

## Spacing

- **Base unit:** 4px. Múltiplos: 4, 8, 12, 16, 24, 32, 48, 64.
- **Density:** compact na arena (HUD não pode obstruir gameplay), comfortable nos menus.
- **Padding padrão:**
  - Paineis: 16px
  - Cards: 12px
  - Botões: 12px horizontal / 8px vertical
  - Lista: 4-8px entre itens

---

## Layout

- **HUD na arena:** periférico compacto (damage %, streak, cooldowns nas bordas) + damage number central-bottom grande (padrão Smash Bros).
- **Lobby/menus:** grid-disciplined, painéis ancorados.
- **Max content width (menus):** 1280px (escala via `UIAspectRatioConstraint` em telas grandes).
- **Border radius (via `UICorner.CornerRadius`):**
  - sm: `UDim.new(0, 6)` — botões pequenos, tags
  - md: `UDim.new(0, 12)` — cards, painéis
  - lg: `UDim.new(0, 20)` — modais, containers grandes
  - pill: `UDim.new(1, 0)` — badges, rank indicators
- **Outlines:** `UIStroke` 2-3px `Color3.fromRGB(0, 0, 0)` ou `text.pure` em UI crítica (damage panel, streak widget) pra separar do gameplay.

---

## Motion

**REGRA CRÍTICA: zero motion da tela/câmera em hits.** Nada de screen shake, viewport zoom, camera bump, ou qualquer efeito que desloque/distorça a viewport quando um soco conecta. Isso atrapalha competitive play e foi decisão explícita do projeto.

Motion permitida é **contida em widgets individuais** — o próprio widget anima dentro do seu rect, sem afetar tela.

- **Approach:** intentional (contida em widgets, nunca global).
- **Easing:** `Enum.EasingStyle.Quad` padrão; `Enum.EasingStyle.Back` em pop-ins.
- **Duration:**
  - micro 80ms — feedback de click, highlight
  - short 200ms — widget enter/exit, damage label pulse
  - medium 350ms — streak pop-in, level up slide-in
  - long 600-800ms — summary overlay, rank up sequence

### Permitido

- Damage label fazendo pulse em si mesma (scale 1.0 → 1.15 → 1.0 no seu próprio rect) quando % sobe.
- Streak widget aparecendo com pop-in (scale + fade) no seu próprio container.
- Level up / rank up banner slidando do topo.
- Kill feed items fadein/fadeout na sua lista.
- Particle effects 3D no world (bater socos emite partículas — isso é world-space, não viewport motion).

### Proibido

- Screen shake em hit.
- Camera zoom/punch em hit.
- Blur/chromatic aberration na viewport em hit.
- Qualquer efeito que afete todo o ScreenGui ao conectar soco.

### Opcional (feature request futura)

- Animation intensity slider em settings (0-100%) aplicada a widget pulse amplitude — útil pra acessibilidade/preferência.

---

## Decoration

- **Scanlines sutis:** ~2% opacity overlay no HUD (opcional, toggle). Vende "arcade" sem virar ruído.
- **Glow em damage label:** `UIStroke` ou `TextStrokeTransparency` + cor semântica na stroke conforme range de damage.
- **Chunky outlines:** 2-3px black stroke em damage panel, streak widget, rank badge — garante leitura sobre qualquer background do world.
- **Sem:** gradientes decorativos em botões, blobs, corner decorations, stock-photo-style backgrounds, rounded-bubble aesthetics genéricas.

---

## Existing Code Alignment

A paleta atual do código já está 80% alinhada com esta proposta. Valores a **manter**:

- `Color3.fromRGB(16, 16, 24)` — mantido como `bg.arena`
- `Color3.fromRGB(20, 20, 30)` — próximo de `bg.surface` (valor novo `20, 24, 44` mais saturado, migrar gradualmente)
- `Color3.fromRGB(255, 100, 100)` kills accent — substituir por `semantic.error` (`255, 71, 87`) ou player color quando apropriado
- `Color3.fromRGB(80, 180, 255)` level accent — substituir por `semantic.info` (`74, 158, 255`)
- `Color3.fromRGB(120, 220, 120)` XP accent — substituir por `semantic.success` (`74, 219, 122`)
- Streak colors (`Double`, `Dominating`) — manter como estão.

Fontes atuais (Gotham / GothamBold / GothamBlack) ficam. Adicionar `Sarpanch` / `Bangers` pra damage/KO/streak display conforme esta spec.

**Sugestão de migração:** criar `src/ReplicatedStorage/Shared/Theme.lua` exportando todos os tokens acima como `Color3` constants + `Font` constants. Controllers passam a consumir dali em vez de hardcodar RGB. Ver Decisions Log pra tracking.

---

## Decisions Log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-04-21 | Design system inicial criado via `/design-consultation` | Formalizar a paleta dark + accents semânticos já presente no código, acrescentar player colors pra 4-player readability, adicionar display fonts chunky pra damage/KO. |
| 2026-04-21 | **Zero motion de tela/câmera em hits** | Decisão explícita do usuário. Motion agressiva de viewport atrapalha competitive play. Motion permanece permitida apenas contida em widgets individuais. |
