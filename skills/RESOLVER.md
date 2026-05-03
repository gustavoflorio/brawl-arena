# Skills RESOLVER

Maps user trigger phrases → skill `SKILL.md` paths. Loaded into Claude's context when the matching phrase appears in a user turn.

Format: each row maps one (or more, slash-separated) trigger to a skill path.

| Trigger | Skill |
|---|---|
| `"skillify this"` / `"skillify"` / `"is this a skill?"` / `"create a new skill"` / `"make this proper"` | `.claude/skills/skillify/SKILL.md` |
| `"cria um asset"` / `"cria um prefab"` / `"cria um acessório"` / `"cria uma luva"` / `"cria um tutu"` / `"novo prefab roblox"` / `"build accessory in studio"` / `"cria asset no studio"` / `"asset roblox custom"` | `.claude/skills/roblox-prefab/SKILL.md` |

## How it's used

`trigger.test.ts` in each skill directory asserts every phrase in `triggers[]` of its `SKILL.md` frontmatter has a row here pointing to that skill's path. Catches the regression where someone adds a trigger but forgets to wire it.

## Conventions

- Phrases in quotes (`"..."` or `` `...` ``) on the same row as the skill path.
- Multiple phrases per row: separate by ` / `.
- One skill per path; multiple skills can't claim the same trigger phrase.
