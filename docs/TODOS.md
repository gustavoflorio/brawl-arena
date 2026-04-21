# TODOS — Brawl Arena

Itens deferidos explicitamente de V1. Cada um tem contexto pra evitar "esqueci por quê".

---

## V1.1 — pós-ship de V1, após retention validar o loop

### UPSET announcement
- **What**: Quando low-rank derruba high-rank (diff ≥ 1 tier major), broadcast announcement centralizado "UPSET! Pedro (Bronze) derrubou Lucas (Gold) +150 XP".
- **Why**: Amplifica o David-vs-Golias mechanic (P4) em layer social. O bonus XP já incentiva a ação; o announcement dá o momento público.
- **Pros**: Viralização natural ("cara, acabei de quebrar um Gold!"), social brag.
- **Cons**: Feature derivativa do rank system, não veio da frase do Pedro ("subi pro nível X, peguei rank tal"). ~3 dias de código.
- **Context**: Cortado durante spec review (Issue #6). Move here se V1 validar retention e flat-reward insight (P13) confirmar que diff-rank kills são o motor de progresso.
- **Depends on**: Rank system funcionando em produção com tier diversity.

### Tutorial interativo
- **What**: Tutorial guiado pro primeiro match (ex: arrow apontando pro pad, prompts "Clica M1 pra socar").
- **Why**: V1 usa só placa 3D + tooltip estático. Se onboarding D0 for ruim (retention D1 baixo mas D7 dos sobreviventes for alto), sinaliza que tutorial ajudaria.
- **Pros**: Pode elevar retention D1 em 5-10pp pra jogadores novos.
- **Cons**: Tutorial bem feito é ~1 semana de trabalho (UX, triggers, skip button, não romper o flow).
- **Context**: Open Question #6 do design doc. Decisão final depende de dados de D1 retention + session analytics.

### Rank decay por inatividade
- **What**: Se player não joga por N dias, rank cai gradativamente.
- **Why**: Previne rank squatting — player alcança Gold I, para de jogar, volta 1 mês depois ainda Gold I mas sem skill atualizada.
- **Pros**: Mantém rank = skill real. Força engajamento recorrente.
- **Cons**: Pune players casuais (que era o Pedro target). Pode prejudicar retention mais que proteger.
- **Context**: Open Question #4 do design doc. V1 sem decay — adicionar só se abuso observado.
- **Depends on**: Observar padrão real de squatting post-ship.

### Cosméticos gameplay-neutral (skins, trails)
- **What**: Skins de character, trails ao andar, effects de soco (pó, faíscas).
- **Why**: Segunda fonte de monetização (Robux), além do donate. Também layer de identidade visual que pode aumentar sessão length.
- **Pros**: Revenue stream com zero gameplay impact (alinha com P3 free-player).
- **Cons**: Asset pipeline grande (modelos, texturas, UI de seleção, inventory system). ~2-3 semanas.
- **Context**: P7 explicitamente cortou cosméticos de V1 em favor de donate button. Mover pra V1.1 só se donate rate provar monetization viable + retention sustentar.

---

## V2 — próxima grande iteração após validação de wedge

### Bots de preenchimento do lobby (empty-server mitigation)
- **What**: Quando arena tem < 4 players humanos, spawna NPCs com IA simples (walk + punch aleatório). Bots rendem XP reduzido pra incentivar matches humanos.
- **Why**: Cold-start problem (P8) — servers pouco populados matam o loop. Config Roblox (P8 V1) mitiga na margem, bots mitigam de verdade.
- **Pros**: Elimina empty-server UX ruim. Também serve como tutorial implícito (player aprende com bots).
- **Cons**: IA de bots requer state machine + path finding. ~1 semana. Risco de bots roubar foco de polish humano.
- **Context**: P8 opção 1, deferida em V1. Move here se CCU médio sub-10 depois de 2 semanas.

### Cross-server teleport pra encher lobbies
- **What**: Quando player entra em server vazio, detecta via MessagingService e teleporta automaticamente pra server mais cheio do mesmo jogo.
- **Why**: Alternativa a bots — resolve empty-server via matchmaking, não via fake players.
- **Pros**: Mais elegante que bots. Garante experiência humana.
- **Cons**: Precisa MessagingService (cross-server pub/sub). Teleport tem UX cost (loading de novo).
- **Context**: P8 opção 2, deferida em V1. Escolha entre bots vs cross-server deve ser data-driven post-V1.

### CI/CD automatizado via Rojo Cloud API
- **What**: GitHub Actions workflow: on push to main → `rojo build` → upload via Roblox Open Cloud API → publica no place.
- **Why**: Hoje deploy é manual (Rojo build + Save to Roblox via Studio). Ship frequency cresce muito com CI.
- **Pros**: Ship 3x mais rápido. Rollback fácil. Canary/staging places possíveis.
- **Cons**: Setup inicial de 4-6h (Roblox API key config, Actions YAML, secrets management).
- **Context**: Distribution Plan do design doc mencionou como "alternativa futura". V1 fica com upload manual.
- **Depends on**: Ship frequency > 2/semana (se ship raro, overhead de CI não compensa).
