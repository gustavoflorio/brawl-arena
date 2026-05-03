---
name: roblox-prefab
version: 1.0.0
description: |
  Use this skill whenever the user wants to create, build, refine, or position Roblox prefab assets in the place file — Accessories (gloves, hats, tutus, weapons), Models (props, NPCs, structures), MeshParts, ParticleEmitters, or any Instance tree meant to be cloned at runtime onto Characters/world. Triggers on phrases like "cria um asset", "cria um prefab", "cria uma luva/tutu/wraps", "cria um acessório", "novo prefab roblox", "build accessory in studio". Builds via Roblox Studio MCP `execute_luau` (no InsertService, no catalog purchase, no third-party copyright). Establishes prefabs in `Workspace.Assets.<NomeDoAsset>` (project convention) and wires runtime consumer code that clones from there.
triggers:
  - "cria um asset"
  - "cria um prefab"
  - "cria um acessório"
  - "cria uma luva"
  - "cria um tutu"
  - "novo prefab roblox"
  - "build accessory in studio"
  - "cria asset no studio"
  - "asset roblox custom"
tools:
  - mcp__robloxstudio-mcp__execute_luau
  - mcp__robloxstudio-mcp__get_services
  - mcp__robloxstudio-mcp__get_project_structure
  - mcp__robloxstudio-mcp__batch_render_objects
mutating: true
---

# roblox-prefab — Build Roblox prefab assets via Studio MCP

## Contract

This skill GUARANTEES:

1. Prefabs land in `Workspace.Assets.<NomeDoAsset>`. Never `ReplicatedStorage`, never `ServerStorage`, never the root of `Workspace`. The user can't see those reliably in their Studio Explorer; this convention is locked. (See `feedback_assets_in_workspace_assets.md`.)
2. Prefabs are built via `mcp__robloxstudio-mcp__execute_luau` with `target=edit`. No `InsertService:LoadAsset` of catalog items (Roblox blocks third-party assets via trust policy + copyright issues). No procedural-only solutions — the user wants visual editability in the Studio editor.
3. Each Accessory has a Handle Part with a child Attachment whose name matches the body's same-named Attachment (`LeftGripAttachment`, `RightGripAttachment`, `WaistCenterAttachment`, etc.). Decorative Parts are `WeldConstraint`-attached to the Handle. All Parts are `Anchored=true` in the prefab so the user can edit them parado in the editor.
4. Runtime consumer code in `src/` clones the prefab, **unanchors all BasePart descendants** before `Humanoid:AddAccessory(clone)` (welds need unanchored parts to mount). Original prefab in `Workspace.Assets` stays intact across clones.
5. Test workflow: spawn an R15 dummy (or 3 dummies for multi-class) at known coordinates, equip the prefabs via `Humanoid:AddAccessory`, ask the user to validate visually, then **clean up dummies before save** (don't leave test rigs in the place).
6. The `Workspace.Assets` folder is created on demand if missing; subdirectories per asset family (e.g. `BrawlClassAccessories/Boxer/`) keep things organized.
7. The user's saved place persists prefabs across sessions. The skill never relies on Rojo to mount these assets (Rojo only syncs `src/`).

## Phases

### Phase 1: Confirm scope + design

Before building anything, lock in:
- **What asset(s)?** Accessory? Model? MeshPart? List the names (e.g., `BoxerLeftGlove`, `BoxerRightGlove`, `BallerinaTutu`).
- **Attachment points (Accessory only)?** `LeftGripAttachment` / `RightGripAttachment` for hands; `WaistCenterAttachment` / `WaistFrontAttachment` for waist; `HatAttachment` / `HairAttachment` for head. Both R6 and R15 expose these by name.
- **Visual goal?** Iconic shape (red boxing glove, white wrap, pink tutu) — discutir trade-off entre shape carrying class identity vs cor carrying class identity.
- **Project convention check**: read `DESIGN.md` if visual decisions overlap with existing color/spacing/motion tokens. Asset color shouldn't conflict with `player.p1`-`p4`, damage gradient, or class accent colors.

If unclear, ask the user; don't guess. Bad shape/color now means a rebuild later.

### Phase 2: Build via Studio MCP

Use a single `execute_luau` call with `target=edit` to construct everything atomically — partial state in `Workspace.Assets` is messier than re-running.

**Skeleton:**

```lua
local Workspace = game:GetService("Workspace")

local assets = Workspace:FindFirstChild("Assets")
if not assets then
  assets = Instance.new("Folder")
  assets.Name = "Assets"
  assets.Parent = Workspace
end

-- Cleanup any prior copy of this asset family
local existing = assets:FindFirstChild("<NomeDoAsset>")
if existing then existing:Destroy() end

local root = Instance.new("Folder")
root.Name = "<NomeDoAsset>"
root.Parent = assets
```

**Accessory builder helper** (reuse this — caught a CFrame math bug last session, locked the math here):

```lua
-- handleOffset: where the handle sits relative to bodyAttachment.WorldCFrame.
--   Identity = handle exactly at body attachment point.
--   CFrame.new(0,0,0.4) = handle 0.4 studs in +Z direction of the attachment.
-- Math derivation:
--   We want handle.WorldCFrame == bodyAtt.WorldCFrame * handleOffset.
--   Roblox sets handle.WorldCFrame = bodyAtt.WorldCFrame * Attachment.CFrame:Inverse().
--   So Attachment.CFrame must equal handleOffset:Inverse().
--
-- decoratives offset: where each extra part sits relative to bodyAttachment.WorldCFrame.
-- Math: at build time, handle.CFrame = identity. WeldConstraint preserves
--   relativeCFrame = handle.CFrame:Inverse() * extra.CFrame at weld time.
--   We want: extra.WorldCFrame = bodyAtt.WorldCFrame * partOffset
--   Solving: relativeCFrame = handleOffset * partOffset
--   Therefore (at build): extra.CFrame = identity * (handleOffset * partOffset)
--                                       = handleOffset * partOffset
--
-- COMMON BUG: writing handleOffset:Inverse() * partOffset → wrong (math derived
-- from confusing world-vs-local frames). The correct multiplication is
-- handleOffset * partOffset. Verified empirically last session.

local function buildAccessory(parent, name, attachmentName, handleProps, handleOffset, decoratives)
  local accessory = Instance.new("Accessory")
  accessory.Name = name
  accessory.Parent = parent

  local handle = Instance.new("Part")
  handle.Name = "Handle"
  handle.Shape = handleProps.shape or Enum.PartType.Block
  handle.Size = handleProps.size
  handle.Color = handleProps.color
  handle.Material = handleProps.material or Enum.Material.SmoothPlastic
  handle.CanCollide = false
  handle.CanQuery = false
  handle.CanTouch = false
  handle.Massless = true
  handle.TopSurface = Enum.SurfaceType.Smooth
  handle.BottomSurface = Enum.SurfaceType.Smooth
  handle.Anchored = true
  handle.CFrame = CFrame.new()
  handle.Parent = accessory

  local att = Instance.new("Attachment")
  att.Name = attachmentName
  att.CFrame = handleOffset:Inverse()
  att.Parent = handle

  for _, dec in ipairs(decoratives or {}) do
    local extra = Instance.new("Part")
    extra.Name = dec.props.name
    extra.Shape = dec.props.shape or Enum.PartType.Block
    extra.Size = dec.props.size
    extra.Color = dec.props.color
    extra.Material = dec.props.material or Enum.Material.SmoothPlastic
    extra.CanCollide = false
    extra.CanQuery = false
    extra.CanTouch = false
    extra.Massless = true
    extra.Anchored = true
    extra.CFrame = handleOffset * dec.offset  -- <-- multiplication, NOT inverse
    extra.Parent = accessory

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle
    weld.Part1 = extra
    weld.Parent = handle
  end

  return accessory
end
```

**Shape choices** (start simple, iterate visually):
- `Enum.PartType.Ball` — sphere. Use for fists, beads, eyes.
- `Enum.PartType.Block` — rectangular. Default — works for most things, no axis confusion.
- `Enum.PartType.Cylinder` — cylinder along X axis. Powerful but rotation math is painful (cylinder axis ≠ world axis after attachment alignment). **Prefer Block when in doubt.** Last session burned 2 iterations on cylinder rotation for a tutu — Block (4.5, 0.4, 4.5) gave a cleaner flat disc with zero CFrame.Angles.

**Color choices**:
- Pull from `DESIGN.md` tokens when relevant (`class.boxer`, `class.taekwon`, `class.ballerina`, etc.).
- Iconic shapes: red boxing glove (165,35,35), white wrap (230,220,195), pink tutu (255,200,220).
- Don't make accessory color same as class accent — let outline carry the class color (surface decoupling rule, see DESIGN.md).

### Phase 3: Visual validation via test dummies

Spawn 1+ R15 dummy in `Workspace`, equip the prefabs, ask user to look in Studio.

```lua
local Players = game:GetService("Players")

local function spawnDummy(name, position)
  local desc = Instance.new("HumanoidDescription")
  local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
  model.Name = name  -- prefix e.g. "BrawlAccessoryTestRig_<class>"
  model.Parent = Workspace
  model:PivotTo(CFrame.new(position))
  for _, p in ipairs(model:GetDescendants()) do
    if p:IsA("BasePart") then p.Anchored = true end
  end
  return model
end

local function equipFromAssetFolder(dummy, assetFolderName)
  local folder = assets:FindFirstChild(assetFolderName)
  if not folder then return end
  local hum = dummy:FindFirstChildOfClass("Humanoid")
  for _, acc in ipairs(folder:GetChildren()) do
    if acc:IsA("Accessory") then
      local clone = acc:Clone()
      -- Unanchor all BasePart descendants before AddAccessory (welds need unanchored)
      for _, p in ipairs(clone:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
      end
      hum:AddAccessory(clone)
    end
  end
  -- Re-anchor whole dummy to keep it parado for editing
  for _, p in ipairs(dummy:GetDescendants()) do
    if p:IsA("BasePart") then p.Anchored = true end
  end
end
```

After build + equip, **ask the user to screenshot or describe what they see**. Don't guess if it looks right — the user has eyes on the actual editor.

If positions/sizes/colors are off:
- Iterate via another `execute_luau` run that destroys+rebuilds the prefab (idempotent).
- Don't try to surgically `set_property` individual parts — destroying and rebuilding is faster and avoids stale-state bugs.

### Phase 4: Cleanup + persist

Once user confirms "ok como v0" or similar, **destroy all test dummies**:

```lua
for _, m in ipairs(Workspace:GetChildren()) do
  if m.Name:find("BrawlAccessoryTestRig") then m:Destroy() end
end
```

Tell the user to **save the place** (Ctrl+S in Studio) so prefabs persist beyond the session. `execute_luau` modifies the in-memory data model; without save, changes are lost on Studio close.

### Phase 5: Wire runtime consumer in `src/`

Most prefabs need a server service that clones them onto Characters/world.

**Runtime lookup pattern:**

```lua
local Workspace = game:GetService("Workspace")
local ASSETS_FOLDER_NAME = "Assets"
local PREFABS_FOLDER_NAME = "<NomeDoAsset>"

local function getPrefabsFolder(): Folder?
  local assets = Workspace:FindFirstChild(ASSETS_FOLDER_NAME)
  if not assets then return nil end
  return assets:FindFirstChild(PREFABS_FOLDER_NAME) :: Folder?
end
```

**Apply pattern (Accessory case):**

```lua
local function applyAccessories(character: Model, classId: string, prefabsFolder: Folder)
  local classFolder = prefabsFolder:FindFirstChild(classId)
  if not classFolder then return end
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if not humanoid then return end
  for _, prefab in ipairs(classFolder:GetChildren()) do
    if prefab:IsA("Accessory") then
      local clone = prefab:Clone()
      clone:SetAttribute("BrawlClassAccessory", true)  -- tag for cleanup tracking
      for _, p in ipairs(clone:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
      end
      humanoid:AddAccessory(clone)
    end
  end
end
```

**Service skeleton:**
- Hook `Players.PlayerAdded` → `Player.CharacterAdded` → `applyAccessories`.
- Tag clones with an attribute so `Reapply()` can remove them later (when class swap, etc.) without touching natural avatar accessories.
- Degrade gracefully if `Workspace.Assets.<NomeDoAsset>` is missing (warn + skip, don't throw — the place file might not have prefabs in some dev branches).

Reference: `src/ServerScriptService/Server/Services/ClassAccessoryService.lua` is the canonical example (commit `0661028`+).

### Phase 6: Commit + push

Per the project's auto-commit-and-push rule (`feedback_auto_commit_push.md`), after the runtime consumer is wired:

1. `rojo build default.project.json -o /tmp/check.rbxlx` to verify Lua compiles.
2. `git add` only the touched `src/` files (the prefabs themselves live in the place file, not in `src/` — Studio save is the user's responsibility, not Rojo's).
3. Commit with a body describing what asset was added and where it lives.
4. `git pull --rebase origin main` then `git push origin main`.

## Anti-Patterns

- **DO NOT** create assets via `InsertService:LoadAsset` of catalog items. Roblox blocks third-party items via trust policy (`Asset is not trusted` error at runtime). Even if it worked, copyright-wise the catalog license doesn't grant reuse rights to the experience owner.
- **DO NOT** put prefabs in `ReplicatedStorage` or `ServerStorage`. The user has reported repeatedly they can't see those reliably in their Studio Explorer. Always `Workspace.Assets.<NomeDoAsset>`. (Recurring memory note: `feedback_assets_in_workspace_assets.md`.)
- **DO NOT** leave test dummies in the place after validation. They'd ship with the place file and clutter Workspace forever. Always cleanup before reporting DONE.
- **DO NOT** write `Attachment.CFrame = handleOffset` (without `:Inverse()`). The math is `Attachment.CFrame = handleOffset:Inverse()` so that after Roblox's weld inverts it during equip, the handle ends up at `bodyAtt * handleOffset`.
- **DO NOT** write `extra.CFrame = handleOffset:Inverse() * partOffset`. The correct formula is `extra.CFrame = handleOffset * partOffset`. Verified empirically last session — got the math wrong twice before locking it.
- **DO NOT** use `Cylinder` shape with rotated offsets unless absolutely necessary. The cylinder axis (X) gets twisted through bodyAttachment alignment + handle inverse + your rotation, and you'll spend 2+ iterations debugging visually. Prefer `Block` shape (rectangular, no axis confusion) for first-pass shapes.
- **DO NOT** ship prefabs with `Anchored=false`. Without anchoring, the user can't position them in the Studio editor — they fall on play, fly off on physics, or shift mid-edit. Anchored=true on the prefab; runtime clone unanchors before AddAccessory.
- **DO NOT** procedurally rebuild prefabs at runtime from a `Defs.lua` table. Tried that earlier this session — the user explicitly rejected it: "para podermos refinar depois" requires Studio editor visibility. Always: build once via MCP, store as Instances in the place file, clone at runtime.
- **DO NOT** declare a trigger phrase the user wouldn't actually type. "build prefab via Studio MCP" is dev jargon; "cria um acessório" / "novo prefab" / "build accessory" is real user language.

## Output Format

A roblox-prefab run produces, in order:

1. **Scope confirmation** — list of assets to build, attachment points, color/shape choices. 1-3 sentences.
2. **MCP build call** — single `execute_luau` invocation creating Workspace.Assets folder + prefabs + test dummies + equip-on-dummies. Logs final state to console.
3. **Visual validation prompt** — ask user to look in Studio (specific tab/folder), screenshot if helpful.
4. **Iteration cycle** (if needed) — additional `execute_luau` calls destroying+rebuilding affected prefabs based on user feedback.
5. **Cleanup confirmation** — destroy test dummies, ask user to Ctrl+S the place.
6. **Runtime wiring** — `Edit`/`Write` on `src/` files (consumer service) + ServiceLoader/controllerOrder hookup as needed.
7. **Build + commit** — rojo build verification, git add+commit+push.
8. **Final summary** — list of prefabs created, runtime files modified, commit hash.

Example final summary:

```
[roblox-prefab] Built 5 Accessory prefabs in Workspace.Assets.BrawlClassAccessories
  - Boxer/{LeftGlove,RightGlove}: red sphere + gold cuff @ LeftGripAttachment / RightGripAttachment
  - Taekwon/{LeftWrap,RightWrap}: cream block + violet stripe @ LeftGripAttachment / RightGripAttachment
  - Ballerina/Tutu: pink wide block + aqua ribbon @ WaistCenterAttachment
[roblox-prefab] Test dummies cleaned up. User confirmed visual ok.
[roblox-prefab] Runtime: src/ServerScriptService/Server/Services/ClassAccessoryService.lua wired (clone + unanchor + AddAccessory)
[roblox-prefab] Commit: ef35180 — pushed to origin/main
[roblox-prefab] Action required from user: Ctrl+S in Studio to persist prefabs.
```
