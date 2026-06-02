# 3D asset pipeline (Blender → Open Cloud → in-game)

Studio-grade mesh pipeline: source files live in git (LFS), geometry is uploaded to Roblox via
Open Cloud and referenced by **asset ID** (never a binary blob committed to the place), and the game
loads it at runtime. `assets/manifest.json` is the hand-authored spec (placement, source, names);
`make assets-upload` writes the resulting ids into the generated `assets/asset-ids.json`
(`id → assetId`) so the spec file is never machine-rewritten; `MeshSceneryService` merges the two
and renders them.

This complements the code-built primitives in `SceneryService` (those need no upload). A mesh
*supersedes* a primitive: when you ship a mesh for an id that `SceneryService` also builds, remove
that id from `SceneryService` so the world isn't doubled up.

## Layout

```
assets/source/<AssetId>/
  <AssetId>.blend     editable source              (Git LFS)
  <AssetId>.fbx       textured export, the upload artifact (Git LFS)
  textures/*          only if textures aren't embedded in the FBX (Git LFS)
```

`<AssetId>` is the manifest `id` (PascalCase, e.g. `House`, `Airplane`).

## Authoring contract (for whoever builds the mesh, incl. a Blender/Claude session)

Export a **Roblox-ready FBX**:

- **Up axis Y, forward Z**; **1 Blender unit = 1 stud** (apply scale before export).
- **Origin at the model's base center** (so placement `offset` puts its feet on the ground).
- **Textures embedded** in the FBX (or placed under `textures/` and referenced).
- Reasonable tri budget; one logical object per asset.

Then register/lock the entry in `assets/manifest.json`:

```jsonc
{
  "id": "House",
  "kind": "mesh",                       // "mesh" = uploaded FBX (this pipeline)
  "source": "source/House/House.fbx",   // relative to assets/
  "zone": "Home",                       // resolves origin from Config.Zones
  "offset": [30, 0, -26],               // studs from the zone origin
  "rotationY": 0,
  "scale": 1,
  "displayName": "Influencer Mansion",
  "description": "Home lobby exterior."
}
```

The asset id is **not** in the manifest — `make assets-upload` records it in `assets/asset-ids.json`.
Commit the `.blend` + `.fbx` (they go to LFS automatically via `.gitattributes`).

## Uploading

```sh
export RBXCLOUD_API_KEY=...        # Open Cloud key with asset:write
export ROBLOX_CREATOR_ID=...       # your user id, or the group id
export ROBLOX_CREATOR_TYPE=user    # or "group"
make assets-upload                 # uploads mesh entries whose assetId is still null
make assets-upload ARGS=--force    # re-upload all mesh entries (new asset versions)
```

`make assets-upload` reads the manifest, uploads each pending FBX via `rbxcloud assets create
--asset-type model-fbx`, polls the operation to completion, writes the returned ids into
`assets/asset-ids.json`, and prints a summary. Commit that file.

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
