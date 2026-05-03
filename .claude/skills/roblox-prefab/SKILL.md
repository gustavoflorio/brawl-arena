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

## Quality Tiers — choose realistically

Before building, declare which tier you're targeting. The user pissed off at v1/v2 builds was a tier mismatch — primitive composition was being asked to match catalog-quality, which it physically can't.

**Tier 1 — Primitive composition (Block/Ball/Cylinder + WeldConstraint)**
- Effort: minutes per accessory.
- Visual ceiling: looks like Lego. OK for prototypes, jam games, deliberately blocky aesthetic. **Will look amateur next to anything professional.**
- Limitations: no curved geometry, no UV-mapped textures, no PBR. Color is per-Part flat.
- Example: what we shipped as v1 + v2 of the Boxer/Taekwon/Ballerina prefabs. User feedback: "muito amador".

**Tier 2 — Catalog mesh reuse (clone MeshPart from `InsertService:LoadAsset`)**
- Effort: minutes per accessory + 1 catalog research session.
- Visual ceiling: identical to professional catalog items (uses their actual MeshId + TextureID).
- Pattern:
  1. Research catalog API (`https://catalog.roblox.com/v1/search/items/details`) for high-favorited items in your asset family. Filter by creator if you want trust safety: `CreatorName=Roblox` for Roblox-official only, otherwise prefer items ≥ 1k favorites + verified creator badge.
  2. In Studio (`execute_luau`, target=edit), `InsertService:LoadAsset(<id>)` to load the wrapper Accessory.
  3. Clone the loaded MeshPart, repurpose as your Accessory's Handle.
  4. Rename the Attachment if needed (e.g. catalog Front Accessory → rename Attachment to `LeftGripAttachment` for hand-mount).
- Once loaded into the place file (saved via Ctrl+S), the MeshPart is part of YOUR place file — runtime cloning works without further `LoadAsset` calls or trust checks.
- **Copyright caveat**: Roblox-official items (creatorName="Roblox") are safest. 3rd-party UGC technically belongs to the original creator; redistributing in a competing game is gray area and could DMCA-risk if the game grows. For brawl-arena, prefer Roblox-official meshes; if using 3rd-party, log the original asset URL as attribution.
- **Plugin context cannot set `MeshId` directly** — it's `NotAccessible`. The `InsertService:LoadAsset` route is the workaround; the loaded MeshPart already has MeshId baked in.

**Tier 3 — Procedural EditableMesh (RECOMMENDED for owned IP + pro quality)**
- Effort: 30-90 min per asset (write generator code in Lua).
- Visual ceiling: smooth curved 3D geometry com superellipsoid + multiple welded MeshParts. Better than primitives, slightly less polished than hand-modeled custom (no UV-mapped textures unless you also generate UVs + apply Texture).
- 100% owned IP — geometry written by you, no asset upload, zero copyright concerns.
- API caveats:
  - `EditableMesh:SetVertexColor` does NOT exist; use `AddColor` + `SetFaceColors` for per-vertex color, OR (simpler) one MeshPart per color region welded together.
  - `MeshPart.MeshId` is `NotAccessible` to plugin context — that's why we generate via `CreateMeshPartAsync`.
  - Multi-color path: build a separate `EditableMesh` per color region, call `CreateMeshPartAsync` for each, set `MeshPart.Color` on each, weld all under one Accessory.

#### Required helper library (copy into your build script)

These are battle-tested helpers that produce professional-quality mesh shapes. Use them verbatim — they handle the math correctly (signs, parametrization, capped ends).

```lua
local AssetService = game:GetService("AssetService")

-- Signed power: sign(x) * |x|^exp. Pra superellipsoid parametrization correta.
local function sp(angle, exp, useSin)
  local v = useSin and math.sin(angle) or math.cos(angle)
  if v == 0 then return 0 end
  local sign = (v >= 0) and 1 or -1
  return sign * (math.abs(v) ^ exp)
end

-- Superellipsoid: |x/a|^m + |y/b|^m + |z/c|^m = 1
--   m=n=2     → sphere/ellipsoid (round)
--   m=n=2.5   → fist-like rounded shape (good pro look)
--   m=n=4     → rounded cube
--   m=n=large → cube
-- Y é eixo polar vertical. knuckleBulge empurra +Z extra na metade superior front
-- (cria ressalto frontal estilo "nós dos dedos").
local function buildSuperellipsoid(latSeg, lonSeg, a, b, c, m, n, knuckleBulge)
  local em = AssetService:CreateEditableMesh()
  local verts = {}
  for lat = 0, latSeg do
    verts[lat] = {}
    local u = -math.pi/2 + (lat / latSeg) * math.pi
    for lon = 0, lonSeg do
      local v = -math.pi + (lon / lonSeg) * math.pi * 2
      local x = a * sp(u, 2/m, false) * sp(v, 2/n, false)
      local y = b * sp(u, 2/m, true)
      local z = c * sp(u, 2/m, false) * sp(v, 2/n, true)
      if knuckleBulge and y > 0 and z > 0 then
        z = z + knuckleBulge * (y / b) * (z / c)
      end
      verts[lat][lon] = em:AddVertex(Vector3.new(x, y, z))
    end
  end
  for lat = 0, latSeg - 1 do
    for lon = 0, lonSeg - 1 do
      local va, vb = verts[lat][lon], verts[lat][lon + 1]
      local vc, vd = verts[lat + 1][lon], verts[lat + 1][lon + 1]
      em:AddTriangle(va, vb, vc)
      em:AddTriangle(vb, vd, vc)
    end
  end
  return em
end

-- Capped cylinder around Y axis. yBottom..yTop, segments lateral count.
local function buildCappedCylinder(yBottom, yTop, radius, segments)
  local em = AssetService:CreateEditableMesh()
  local bottom, top = {}, {}
  for s = 0, segments - 1 do
    local phi = (s / segments) * math.pi * 2
    local x, z = radius * math.cos(phi), radius * math.sin(phi)
    bottom[s + 1] = em:AddVertex(Vector3.new(x, yBottom, z))
    top[s + 1]    = em:AddVertex(Vector3.new(x, yTop, z))
  end
  for s = 0, segments - 1 do
    local b1, b2 = bottom[s + 1], bottom[((s + 1) % segments) + 1]
    local t1, t2 = top[s + 1], top[((s + 1) % segments) + 1]
    em:AddTriangle(b1, t1, b2); em:AddTriangle(b2, t1, t2)
  end
  local cb = em:AddVertex(Vector3.new(0, yBottom, 0))
  local ct = em:AddVertex(Vector3.new(0, yTop, 0))
  for s = 0, segments - 1 do
    local b1, b2 = bottom[s + 1], bottom[((s + 1) % segments) + 1]
    local t1, t2 = top[s + 1], top[((s + 1) % segments) + 1]
    em:AddTriangle(cb, b2, b1); em:AddTriangle(ct, t1, t2)
  end
  return em
end

-- Box (rectangular prism, 8 verts + 12 tris). Pra lacing strips, details pequenos.
local function buildBox(sx, sy, sz)
  local em = AssetService:CreateEditableMesh()
  local hx, hy, hz = sx/2, sy/2, sz/2
  local v = {
    em:AddVertex(Vector3.new(-hx, -hy, -hz)), em:AddVertex(Vector3.new(hx, -hy, -hz)),
    em:AddVertex(Vector3.new(hx, -hy, hz)),   em:AddVertex(Vector3.new(-hx, -hy, hz)),
    em:AddVertex(Vector3.new(-hx, hy, -hz)),  em:AddVertex(Vector3.new(hx, hy, -hz)),
    em:AddVertex(Vector3.new(hx, hy, hz)),    em:AddVertex(Vector3.new(-hx, hy, hz)),
  }
  local function quad(a,b,c,d) em:AddTriangle(v[a], v[b], v[c]); em:AddTriangle(v[a], v[c], v[d]) end
  quad(1,2,3,4); quad(5,8,7,6); quad(1,5,6,2); quad(4,3,7,8); quad(1,4,8,5); quad(2,6,7,3)
  return em
end

local function configurePart(p)
  p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
  p.Massless = true; p.Anchored = true
end

-- Builds an Accessory with Handle = first mesh, decoratives welded with offset.
-- layout = { { mp = MeshPart, name = string, cf = CFrame relative to Handle } }
local function buildAccessoryFromMeshes(name, attachmentName, handleMP, layout, mirror)
  local accessory = Instance.new("Accessory")
  accessory.Name = name
  local handle = handleMP:Clone()
  handle.Name = "Handle"
  configurePart(handle)
  handle.CFrame = CFrame.new()
  handle.Parent = accessory
  local att = Instance.new("Attachment")
  att.Name = attachmentName
  if mirror then att.CFrame = CFrame.Angles(0, math.rad(180), 0) end
  att.Parent = handle
  for _, item in ipairs(layout) do
    local clone = item.mp:Clone()
    clone.Name = item.name
    configurePart(clone)
    clone.CFrame = handle.CFrame * item.cf
    clone.Parent = accessory
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle; weld.Part1 = clone; weld.Parent = handle
  end
  return accessory
end

-- Move accessory inteiro (handle + welded decoratives) preservando offsets
local function moveAccessory(accessory, newHandlePos)
  local handle = accessory:FindFirstChild("Handle")
  local delta = newHandlePos - handle.Position
  for _, p in ipairs(accessory:GetDescendants()) do
    if p:IsA("BasePart") then p.Position = p.Position + delta end
  end
end
```

#### Boxing glove recipe (proven v5 — produces actual leather-looking glove with cuff + lacing)

```lua
local LEATHER_RED  = Color3.fromRGB(155, 30, 30)
local CUFF_WHITE   = Color3.fromRGB(240, 235, 220)
local CUFF_TRIM    = Color3.fromRGB(220, 175, 80)
local LACE_BLACK   = Color3.fromRGB(15, 15, 15)

-- 1) Fist: superellipsoid m=n=2.5 (rounded cube), elongated +Z (depth 0.85),
--    squashed Y (height 0.55), knuckle bulge 0.18. 16 lat × 24 lon = ~432 verts.
local fistEm = buildSuperellipsoid(16, 24, 0.65, 0.55, 0.85, 2.5, 2.5, 0.18)
local fistMP = AssetService:CreateMeshPartAsync(Content.fromObject(fistEm))
fistMP.Color = LEATHER_RED
fistMP.Material = Enum.Material.SmoothPlastic
fistMP.Reflectance = 0.07

-- 2) Thumb: pequeno ellipsoid (10x14, m=n=2 = round)
local thumbEm = buildSuperellipsoid(10, 14, 0.25, 0.28, 0.32, 2, 2, 0)
local thumbMP = AssetService:CreateMeshPartAsync(Content.fromObject(thumbEm))
thumbMP.Color = LEATHER_RED
thumbMP.Material = Enum.Material.SmoothPlastic
thumbMP.Reflectance = 0.07

-- 3) Cuff: cilindro longo (yBottom=-0.55..yTop=0.05, 0.6 stud altura), 24 seg
local cuffMP = AssetService:CreateMeshPartAsync(
  Content.fromObject(buildCappedCylinder(-0.55, 0.05, 0.5, 24)))
cuffMP.Color = CUFF_WHITE; cuffMP.Material = Enum.Material.Fabric

-- 4) Trim: anel fino dourado (-0.05..0.05, ligeiramente maior raio que cuff)
local trimMP = AssetService:CreateMeshPartAsync(
  Content.fromObject(buildCappedCylinder(-0.05, 0.05, 0.55, 24)))
trimMP.Color = CUFF_TRIM; trimMP.Material = Enum.Material.SmoothPlastic
trimMP.Reflectance = 0.20

-- 5) Lacing: 1 vertical + 3 horizontal cross stripes, fabric preto fino
local laceVertMP = AssetService:CreateMeshPartAsync(Content.fromObject(buildBox(0.07, 0.45, 0.05)))
laceVertMP.Color = LACE_BLACK; laceVertMP.Material = Enum.Material.Fabric
local laceHorizMP = AssetService:CreateMeshPartAsync(Content.fromObject(buildBox(0.32, 0.05, 0.05)))
laceHorizMP.Color = LACE_BLACK; laceHorizMP.Material = Enum.Material.Fabric

-- 6) Assemble: Fist é Handle. Thumb pra lateral, Cuff abaixo, Trim entre.
--    Lacing na frente do cuff (Z=+0.5).
local function gloveLayout(mirror)
  local thumbX = mirror and -0.45 or 0.45
  return {
    { mp = thumbMP,     name = "Thumb",    cf = CFrame.new(thumbX, -0.1, 0.25) },
    { mp = cuffMP,      name = "Cuff",     cf = CFrame.new(0, -0.85, 0) },
    { mp = trimMP,      name = "Trim",     cf = CFrame.new(0, -0.40, 0) },
    { mp = laceVertMP,  name = "LaceVert", cf = CFrame.new(0, -0.85, 0.50) },
    { mp = laceHorizMP, name = "LaceTop",  cf = CFrame.new(0, -0.65, 0.50) },
    { mp = laceHorizMP, name = "LaceMid",  cf = CFrame.new(0, -0.85, 0.50) },
    { mp = laceHorizMP, name = "LaceBot",  cf = CFrame.new(0, -1.05, 0.50) },
  }
end

local lglove = buildAccessoryFromMeshes("BoxerLeftGlove", "LeftGripAttachment", fistMP, gloveLayout(false), false)
local rglove = buildAccessoryFromMeshes("BoxerRightGlove", "RightGripAttachment", fistMP, gloveLayout(true), true)
-- Cleanup mesh templates (não precisam ficar fora dos accessories)
fistMP:Destroy(); thumbMP:Destroy(); cuffMP:Destroy(); trimMP:Destroy()
laceVertMP:Destroy(); laceHorizMP:Destroy()
```

**Tuning knobs** (ajusta visualmente, sem quebrar a estrutura):

| Param | v5 default | Range | Effect |
|---|---|---|---|
| superellipsoid `m`/`n` | 2.5 | 2 (sphere) → 4 (rounded cube) | Higher = mais cubóide |
| `knuckleBulge` | 0.18 | 0 → 0.3 | Saliência frontal dos nós |
| fist `(a,b,c)` | (0.65, 0.55, 0.85) | scale to taste | width / height / depth |
| `Reflectance` | 0.07 (fist), 0.20 (trim) | 0 → 0.5 | "Brilho de couro" |
| latSeg/lonSeg | 16/24 | 8/12 → 24/36 | Smoothness vs poly count |
| `Material` (fist) | SmoothPlastic | Plastic, Slate, Glass, Metal | Surface look |

#### Other shape recipes

- **Bandage wrap (Taekwon-style)**: `buildCappedCylinder(-0.4, 0.4, 0.4, 16)` body + thin colored stripe via second cylinder slightly larger radius. Material=Fabric.
- **Tutu (Ballerina-style)**: `buildCappedCylinder(-0.05, 0.05, 2.0, 32)` flat wide disc. Add ribbon ring via second cylinder slightly below. Material=Fabric.
- **Helmet/hat**: superellipsoid m=n=3, c < a < b (taller than wide).
- **Sword hilt**: capped cylinder + box + capped cylinder (handle, guard, pommel) welded.

**Tier 4 — Custom uploaded meshes (Blender etc.)**
- Effort: hours-days (Blender modeling + texture painting + Roblox asset upload).
- Visual ceiling: anything you can model. Highest quality; fully owned IP. UV-mapped textures, normal maps, PBR.
- Workflow: outside this skill's scope (3D modeling tools required). After upload, plug new asset IDs into a Tier 2-style flow but with assets you legally own.

**Recommendation**: When user asks for "professional + clean IP", **go straight to Tier 3 procedural**. It's the sweet spot: real 3D geometry (not blocky), no asset upload (no Blender required), zero copyright issues. Don't promise primitive composition (Tier 1) can match catalog quality — it physically cannot. Tier 2 catalog reuse is fast but legal-gray for UGC; only safe with Roblox-official meshes (creatorName="Roblox").

## Phases

### Phase 1: Confirm scope + design + tier

Before building anything, lock in:
- **What asset(s)?** Accessory? Model? MeshPart? List the names (e.g., `BoxerLeftGlove`, `BoxerRightGlove`, `BallerinaTutu`).
- **Attachment points (Accessory only)?** `LeftGripAttachment` / `RightGripAttachment` for hands; `WaistCenterAttachment` / `WaistFrontAttachment` for waist; `HatAttachment` / `HairAttachment` for head. Both R6 and R15 expose these by name.
- **Visual goal?** Iconic shape (red boxing glove, white wrap, pink tutu) — discutir trade-off entre shape carrying class identity vs cor carrying class identity.
- **Project convention check**: read `DESIGN.md` if visual decisions overlap with existing color/spacing/motion tokens. Asset color shouldn't conflict with `player.p1`-`p4`, damage gradient, or class accent colors.

If unclear, ask the user; don't guess. Bad shape/color now means a rebuild later.

### Phase 2: Build via Studio MCP

Choose path based on declared tier (Phase 1).

#### Tier 2 path — clone catalog MeshPart (RECOMMENDED for "professional")

```lua
local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")

-- Catalog research: queried via curl beforehand. Pick high-favorite items
-- from trusted creators. Reference catalog accessories include:
--   id=4470966858  (White Bow Tutu, by ROBLOX, 209k favs)  → meshId 4470940229
--   id=17257872770 (Tulle Pink Tutu, 49k favs)             → meshId 17257666533
--   id=89718847680206 (Bandage Wrap Glove R6, 1k favs)     → meshId 81877682482776
--   id=7029093651 (Boxing Gloves, 380 favs, by hu2an UGC)  → meshId 7015205963
-- (Mesh+Texture IDs are referenceable from any place once loaded; they live
-- on Roblox CDN as public assets.)

local CATALOG_REFS = {
  Tutu        = 4470966858,
  WrapGlove   = 89718847680206,
  BoxingGlove = 7029093651,
}

-- Load originals into a study folder (one-time per place)
local study = Workspace.Assets:FindFirstChild("_CatalogStudy")
if not study then
  study = Instance.new("Folder")
  study.Name = "_CatalogStudy"
  study.Parent = Workspace.Assets
end

local function ensureLoaded(refName, assetId)
  local existing = study:FindFirstChild(refName)
  if existing then return existing end
  local model = InsertService:LoadAsset(assetId)
  model.Name = refName
  model.Parent = study
  return model
end

-- Clone the MeshPart from the loaded asset, repurpose as our Accessory's Handle
local function cloneCatalogToAccessory(refName, attachmentName, scale)
  local loadedModel = study:FindFirstChild(refName)
  local origAccessory = loadedModel and loadedModel:FindFirstChildWhichIsA("Accessory")
  local origHandle = origAccessory and origAccessory:FindFirstChild("Handle")
  if not origHandle or not origHandle:IsA("MeshPart") then
    warn("Catalog asset " .. refName .. " has no MeshPart Handle")
    return nil
  end

  local accessory = Instance.new("Accessory")
  accessory.Name = refName .. "_repurposed"

  local handle = origHandle:Clone()
  handle.Name = "Handle"
  handle.Anchored = true
  handle.CanCollide = false
  handle.CanQuery = false
  handle.CanTouch = false
  handle.Massless = true
  if scale then handle.Size = origHandle.Size * scale end
  -- Strip original attachments (will rename ours)
  for _, c in ipairs(handle:GetChildren()) do
    if c:IsA("Attachment") then c:Destroy() end
  end
  handle.Parent = accessory

  local att = Instance.new("Attachment")
  att.Name = attachmentName
  att.Parent = handle

  return accessory
end
```

Reposition the cloned MeshPart's Attachment offset visually in the editor — catalog accessories were made for specific body parts (e.g. Front Accessory mounted on torso), so when repurposing for a different attachment (LeftGripAttachment), you'll need to nudge offset/scale.

#### Tier 1 path — primitive composition (use only when quality bar is low)

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

**Showcase line (3D world position)**:

Prefabs também precisam de coordenadas 3D razoáveis. **NÃO deixe em (0,0,0)** — fica em cima do spawn pad e o user perde tempo procurando. **Convenção do projeto**: alinhar todos os prefabs em fila Y=50, Z=0, X variando a cada 4-5 studs, próximos aos prefabs já existentes da família (`BrawlClassAccessories`).

Antes de buildar, probe a posição dos prefabs existentes:

```lua
for _, accessory in ipairs(parentFolder:GetDescendants()) do
  if accessory:IsA("Accessory") then
    local h = accessory:FindFirstChild("Handle")
    if h then print(accessory:GetFullName(), h.Position) end
  end
end
```

Posiciona os novos numa continuação dessa linha. Mover toda a Accessory (Handle + decoratives) preserva offsets relativos via delta translation:

```lua
local function moveAccessory(accessory, newHandlePos)
  local handle = accessory:FindFirstChild("Handle")
  local delta = newHandlePos - handle.Position
  for _, p in ipairs(accessory:GetDescendants()) do
    if p:IsA("BasePart") then p.Position = p.Position + delta end
  end
end
```

**Test dummy também posiciona perto** dos prefabs (e.g. Z=5 à frente da showcase line) — não no (0, 5, 0).

### Phase 3: Visual validation via test dummies

Spawn 1+ R15 dummy in **`Workspace.Assets._TestRigs`** (NEVER at Workspace root — pollutes the user's Explorer view), equip the prefabs, ask user to look in Studio.

```lua
local Players = game:GetService("Players")

local function ensureTestRigsFolder(): Folder
  local assets = Workspace:FindFirstChild("Assets")
  assert(assets, "Workspace.Assets not found — build prefabs first")
  local testRigs = assets:FindFirstChild("_TestRigs")
  if not testRigs then
    testRigs = Instance.new("Folder")
    testRigs.Name = "_TestRigs"
    testRigs.Parent = assets
  end
  return testRigs
end

local function spawnDummy(name, position)
  local desc = Instance.new("HumanoidDescription")
  local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
  model.Name = name  -- prefix e.g. "BrawlAccessoryTestRig_<class>"
  model.Parent = ensureTestRigsFolder()  -- NEVER Workspace root
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
local testRigs = Workspace:FindFirstChild("Assets") and
  Workspace.Assets:FindFirstChild("_TestRigs")
if testRigs then
  for _, m in ipairs(testRigs:GetChildren()) do
    if m.Name:find("BrawlAccessoryTestRig") then m:Destroy() end
  end
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
- **DO NOT** spawn test dummies / scratch Models / debug Parts at `Workspace` root. They pollute the Explorer view and the user gets pissed. Test rigs go in `Workspace.Assets._TestRigs`; prefabs in `Workspace.Assets.<NomeDoAsset>`. **Anything created via MCP belongs inside `Workspace.Assets`** — no exceptions.
- **DO NOT** leave test dummies in the place after validation. They'd ship with the place file and clutter Workspace forever. Always cleanup before reporting DONE.
- **DO NOT** write `Attachment.CFrame = handleOffset` (without `:Inverse()`). The math is `Attachment.CFrame = handleOffset:Inverse()` so that after Roblox's weld inverts it during equip, the handle ends up at `bodyAtt * handleOffset`.
- **DO NOT** write `extra.CFrame = handleOffset:Inverse() * partOffset`. The correct formula is `extra.CFrame = handleOffset * partOffset`. Verified empirically last session — got the math wrong twice before locking it.
- **DO NOT** use `Cylinder` shape with rotated offsets unless absolutely necessary. The cylinder axis (X) gets twisted through bodyAttachment alignment + handle inverse + your rotation, and you'll spend 2+ iterations debugging visually. Prefer `Block` shape (rectangular, no axis confusion) for first-pass shapes.
- **DO NOT** ship prefabs with `Anchored=false`. Without anchoring, the user can't position them in the Studio editor — they fall on play, fly off on physics, or shift mid-edit. Anchored=true on the prefab; runtime clone unanchors before AddAccessory.
- **DO NOT** procedurally rebuild prefabs at runtime from a `Defs.lua` table. Tried that earlier this session — the user explicitly rejected it: "para podermos refinar depois" requires Studio editor visibility. Always: build once via MCP, store as Instances in the place file, clone at runtime.
- **DO NOT** declare a trigger phrase the user wouldn't actually type. "build prefab via Studio MCP" is dev jargon; "cria um acessório" / "novo prefab" / "build accessory" is real user language.
- **DO NOT** promise "professional quality" with primitive Parts (Tier 1). Catalog accessories use uploaded MeshParts with UV-textured 3D meshes; primitives top out at "blocky/low-poly" no matter how many Parts you stack. If the user wants pro look, go Tier 2 (catalog mesh reuse) or commission Tier 3.
- **DO NOT** try to set `MeshPart.MeshId` directly via plugin `execute_luau`. It's `NotAccessible` (capability blocked). Use `InsertService:LoadAsset(<id>)` to load the wrapper Accessory; the loaded MeshPart already has MeshId baked in. Clone that MeshPart into your own Accessory.
- **DO NOT** ship 3rd-party UGC meshes in production without thinking about copyright. Roblox-official items (`creatorName="Roblox"`) are safest. UGC creators technically own their meshes — gray area to redistribute via your experience. For brawl-arena: prefer ROBLOX-official meshes; if using UGC, attribute the original asset URL in code comments.
- **DO NOT** ship a prefab with a Part that has no `WeldConstraint` to Handle. When `Humanoid:AddAccessory` runs, only the Handle gets welded to the body's matching Attachment. Other Parts (siblings of Handle inside the Accessory, OR children of Handle) need their own `WeldConstraint(Part0=Handle, Part1=otherPart)` to follow the Handle to the character. Without it, the Part stays at the prefab's world position (e.g. Y=50 floating in the air where Workspace.Assets lives) — invisible at the player's character location, totally confusing for the user during playtest. **When the user adds a Part to the prefab manually in the Studio editor, proactively check whether it has a weld to Handle. If not, add one.**

## Editor refinement workflow (when user edits a prefab manually)

The user may edit a prefab visually in the Studio Explorer (Insert > Part, drag Position, change Color via Properties panel). Studio's default Insert > Part DOES NOT add welds — it just drops a free Part. After the user adds a Part manually:

1. **Probe the prefab** via `execute_luau` with `target=edit` to see the current tree.
2. **Check each newly-added Part** has a `WeldConstraint` connecting it to Handle. If missing, add one programmatically:
   ```lua
   local weld = Instance.new("WeldConstraint")
   weld.Part0 = handle
   weld.Part1 = newPart
   weld.Parent = handle  -- conventional: weld lives under Part0
   ```
3. **Verify the new Part is `Anchored = true`** in the prefab (so it stays put in editor). Runtime service will unanchor on clone.
4. **Restart playtest** to verify. Edit-mode changes don't propagate to a running Play session — Edit and Play are separate data models. Stop & restart playtest after editing.

If the new Part still doesn't appear in playtest after weld+anchor are correct:
- Ensure the user **saved the place** (Ctrl+S) at least once. `execute_luau` mutates the in-memory data model; without save, changes don't persist across Studio sessions but DO survive within the same Studio session including Play mode.
- Verify the Part's CFrame relative to Handle isn't some absurd offset (1000+ studs away). If offset is huge, the Part follows Handle but visually is far off-screen.

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
