# 3D asset pipeline (GLB/OBJ → Open Cloud → in-game)

> Quick reference for adding a mesh. The full rationale, schema, and tech-debt notes live in
> [`doc/003_binary_asset_management.md`](../doc/003_binary_asset_management.md).

Studio-grade mesh pipeline: source files live in git (LFS), geometry is uploaded to Roblox via
Open Cloud and referenced by **asset ID** (never a binary blob committed to the place), and the game
loads it at runtime. `assets/manifest.json` is the hand-authored spec (placement, source, names);
`make assets-upload` writes the resulting ids into the generated `assets/asset-ids.json`
(`id → assetId`) so the spec file is never machine-rewritten; `MeshSceneryService` merges the two
and renders them.

**Source formats.** The Open Cloud Assets API accepts `glb`/`gltf`/`fbx` for Models but **not
`obj`**. So a `.glb` source is uploaded as-is, and a `.obj` source is **converted to a self-contained
GLB** ([obj2gltf](https://github.com/CesiumGS/obj2gltf), npm) by `make assets-upload` before upload —
the OBJ stays the editable source in git, the GLB is a throwaway upload artifact.

This complements the code-built primitives in `SceneryService` (those need no upload). A mesh
*supersedes* a primitive: when you ship a mesh for an id that `SceneryService` also builds, remove
that id from `SceneryService` so the world isn't doubled up.

## Layout

```
assets/source/<AssetId>/
  <AssetId>.glb       a GLB source (textured, self-contained) + upload artifact (Git LFS)
   — or —
  <AssetId>.obj       a Wavefront OBJ source, converted to GLB at upload (Git LFS)
  <AssetId>.mtl       its material file (plain text, normal git — not LFS)
  textures/*          OBJ texture maps, or GLB textures if not embedded (Git LFS)
```

`<AssetId>` is the manifest `id` (PascalCase, e.g. `House`, `Airplane`). Pick the format that matches
your tool's output:

- **GLB** — self-contained (mesh + textures + materials in one binary), the standard output of most
  AI mesh tools, natively accepted by Open Cloud. Uploaded as-is.
- **OBJ** — geometry `.obj` + materials `.mtl` + separate texture images. **Not** accepted by Open
  Cloud, so `make assets-upload` converts it to a GLB first (`obj2gltf`). Keep the `.obj`, `.mtl`,
  and textures together so the conversion resolves them.

## Authoring contract (for whoever generates the mesh, incl. another model/session)

Produce a **Roblox-ready** mesh (GLB or OBJ):

- **Up axis Y, forward Z**; **1 unit = 1 stud** (apply scale/transforms before export).
- **Origin at the model's base center** (so placement `offset` puts its feet on the ground).
- **Textures embedded** in the GLB, or — for OBJ — referenced by the `.mtl` with the image files
  committed alongside (under the asset dir or `textures/`).
- Reasonable tri budget; one logical object per asset.

Then register/lock the entry in `assets/manifest.json` (point `source` at the `.glb` or the `.obj`):

```jsonc
{
  "id": "House",
  "kind": "mesh",                       // "mesh" = uploaded mesh (this pipeline)
  "source": "source/House/House.glb",   // or "source/House/House.obj" — relative to assets/
  "zone": "Home",                       // resolves origin from Config.Zones
  "offset": [30, 0, -26],               // studs from the zone origin
  "rotationY": 0,
  "scale": 1,
  "color": [222, 205, 170],             // optional flat rgb tint for a geometry-only mesh
  "displayName": "Influencer Mansion",
  "description": "Home lobby exterior."
}
```

`color` is optional — set it for meshes with **no embedded material/texture** (e.g. OBJ exports
without an `.mtl`); `MeshSceneryService` tints every part of the loaded model with it. Omit it for
textured GLBs so their materials show through.

The asset id is **not** in the manifest — `make assets-upload` records it in `assets/asset-ids.json`.
Commit the source (`.glb`, or `.obj` + `.mtl` + textures); binaries go to LFS automatically via
`.gitattributes`.

## Uploading

```sh
export ROBLOX_API_KEY=...          # Open Cloud key with asset:write
export ROBLOX_CREATOR_ID=...       # your user id, or the group id
export ROBLOX_CREATOR_TYPE=user    # or "group"
make assets-upload                 # uploads new + changed mesh entries (skips unchanged)
make assets-upload ARGS=--force    # re-upload every mesh entry regardless of change
```

`make assets-upload` reads the manifest and uploads each **new or changed** mesh directly to the
**Open Cloud Assets API** (via `curl` — rbxcloud's CLI is FBX-only), polls the operation to
completion, and records the result. Change detection uses `assets/.upload-state.json`
(`id → {hash, assetId}`): an entry uploads when it has no recorded state, when its source file's
sha256 differs from the recorded one, or under `--force`; unchanged entries are skipped. A **new**
asset is **created** (`POST /assets/v1/assets`, `assetType:"Model"`, MIME `model/gltf-binary`); a
**changed** asset that already has an id is **updated in place** (`PATCH /assets/v1/assets/{assetId}`)
so its id — the one the game references — stays stable. The returned ids land in
`assets/asset-ids.json`; commit both that and `.upload-state.json`.

A `.obj` source is **converted to a temporary GLB** with `npx --yes obj2gltf` first (so the upload is
always a self-contained GLB); the temp file is discarded after upload. This needs **Node/npm** on
`PATH` — `npx` fetches `obj2gltf` on first use (or `npm i -g obj2gltf` to pin it). GLB sources upload
with no conversion and no Node requirement.

Without the env vars it does nothing destructive — it reports the pending uploads and how to
configure, then exits.

## Runtime

`MeshSceneryService` reads `SceneryManifest` + `SceneryAssetIds` (Rojo maps `manifest.json` and
`asset-ids.json` into the tree) and, for each `kind:"mesh"` entry whose `id` has an uploaded asset,
`InsertService:LoadAsset`s it, scales it (`scale`), and pivots it to `Config.Zones[zone] + offset`
rotated by `rotationY`. Entries with no uploaded id are skipped, so the build never breaks on a
pending asset.

## First-checkout / contributor setup

```sh
git lfs install        # once per machine
git lfs pull           # fetch the binary sources
```

Uploading an OBJ source additionally needs **Node/npm** (for `obj2gltf`); GLB-only uploads don't.
