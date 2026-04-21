# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

**Brawl Arena** — Roblox side-scroller 2D brawl inspirado em Smash Bros. Jogo de arena rápido, ciclo competitivo. Luau (`--!strict`) com Rojo.

## Build & Dev

```bash
rojo serve default.project.json
rojo build default.project.json -o build.rbxlx
```

## Architecture

- Server (`src/ServerScriptService/Server/`) é fonte única de verdade. `ServiceLoader.lua` carrega services em ordem explícita.
- Services seguem contrato `Init(deps) → Start()`.
- Dois RemoteEvents: `BrawlRequest` (client→server) e `BrawlState` (server→client).
- Atributos no Character (`BrawlHitSeq`, `BrawlEliminationSeq`) propagam FX cliente-a-cliente.
- Lobby e Arena coexistem no mesmo place, em regiões diferentes do Workspace.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke context-save
- Code quality, health check → invoke health
