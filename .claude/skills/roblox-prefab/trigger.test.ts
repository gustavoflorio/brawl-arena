/**
 * Trigger eval (item #7) for roblox-prefab.
 *
 * Asserts every trigger declared in this skill's frontmatter has a matching
 * routing entry in the workspace's RESOLVER.md pointing to this skill.
 *
 * Catches the regression where someone moves/renames the skill, adds a new
 * trigger, or changes the path without updating RESOLVER.
 *
 * Run: npx tsx --test .claude/skills/roblox-prefab/trigger.test.ts
 *
 * Note: this Roblox/Luau project doesn't ship a Node toolchain. The test is
 * here for parity with the skillify scaffold pattern and runs in environments
 * that have Node + tsx available (CI, dev's machine with the gstack tooling).
 */

import { test } from 'node:test';
import assert from 'node:assert';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const SKILL_DIR = __dirname;
const SKILL_NAME = 'roblox-prefab';
const WORKSPACE = join(SKILL_DIR, '..', '..', '..');
const RESOLVER_PATH = join(WORKSPACE, 'skills', 'RESOLVER.md');
const SKILL_REF = `.claude/skills/${SKILL_NAME}/SKILL.md`;

function parseTriggers(skillMdPath: string): string[] {
  const content = readFileSync(skillMdPath, 'utf-8');
  const fm = content.match(/^---\n([\s\S]*?)\n---/);
  assert.ok(fm, 'SKILL.md must have YAML frontmatter');
  const lines = fm[1].split('\n');
  const triggers: string[] = [];
  let inTriggers = false;
  for (const line of lines) {
    if (/^triggers:\s*$/.test(line)) { inTriggers = true; continue; }
    if (inTriggers) {
      if (/^\s+-\s/.test(line)) {
        triggers.push(line.replace(/^\s+-\s+/, '').trim().replace(/^["']|["']$/g, ''));
      } else if (/^\S/.test(line)) {
        break;
      }
    }
  }
  return triggers;
}

test(`roblox-prefab: every declared trigger has a routing entry in RESOLVER.md`, () => {
  assert.ok(existsSync(RESOLVER_PATH), `RESOLVER.md not found at ${RESOLVER_PATH}`);

  const triggers = parseTriggers(join(SKILL_DIR, 'SKILL.md'));
  assert.ok(triggers.length >= 3, `expected ≥3 triggers, got ${triggers.length}`);

  const resolverContent = readFileSync(RESOLVER_PATH, 'utf-8');

  // Each trigger phrase must appear on the same line as a reference to the
  // skill path. Allow grouping multiple triggers per row using slashes
  // (e.g. "cria um asset" / "cria um prefab").
  const escapedRef = SKILL_REF.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const missing = triggers.filter((trigger) => {
    const escapedTrigger = trigger.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp(`["\`]?${escapedTrigger}["\`]?[^\\n]*${escapedRef}`);
    return !re.test(resolverContent);
  });

  assert.deepStrictEqual(
    missing,
    [],
    `Triggers declared in SKILL.md frontmatter but not routed to ${SKILL_REF} in RESOLVER.md:\n${missing.map((t) => `  - "${t}"`).join('\n')}\n\nFix: add entries to RESOLVER.md routing each missing trigger to ${SKILL_REF}.`,
  );
});

test(`roblox-prefab: RESOLVER entries for this skill all reference the correct path`, () => {
  const resolverContent = readFileSync(RESOLVER_PATH, 'utf-8');
  const lines = resolverContent.split('\n').filter((l) => /roblox-prefab/i.test(l) && /SKILL\.md/.test(l));
  assert.ok(lines.length > 0, 'no RESOLVER entries reference this skill');
  for (const line of lines) {
    assert.ok(
      line.includes(SKILL_REF),
      `RESOLVER line mentions "roblox-prefab" but path is wrong: ${line.trim()}\nexpected to contain: ${SKILL_REF}`,
    );
  }
});
