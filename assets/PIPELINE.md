# 3D asset pipeline (GLB → Open Cloud → in-game)

> Quick reference for adding a mesh. The full rationale, schema, and tech-debt notes live in
> [`doc/003_binary_asset_management.md`](../doc/003_binary_asset_management.md).

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
  <AssetId>.glb       textured GLB, the source + upload artifact (Git LFS)
  textures/*          only if textures aren't embedded in the GLB (Git LFS)
```

`<AssetId>` is the manifest `id` (PascalCase, e.g. `House`, `Airplane`). **GLB** is the format: it's
self-contained (mesh + textures + materials in one binary), the standard output of most AI mesh
tools, and natively accepted by the Open Cloud Assets API.

## Authoring contract (for whoever generates the mesh, incl. another model/session)

Produce a **Roblox-ready GLB**:

- **Up axis Y, forward Z**; **1 unit = 1 stud** (apply scale/transforms before export).
- **Origin at the model's base center** (so placement `offset` puts its feet on the ground).
- **Textures embedded** in the GLB (or placed under `textures/`).
- Reasonable tri budget; one logical object per asset.

Then register/lock the entry in `assets/manifest.json`:

```jsonc
{
  "id": "House",
  "kind": "mesh",                       // "mesh" = uploaded GLB (this pipeline)
  "source": "source/House/House.glb",   // relative to assets/
  "zone": "Home",                       // resolves origin from Config.Zones
  "offset": [30, 0, -26],               // studs from the zone origin
  "rotationY": 0,
  "scale": 1,
  "displayName": "Influencer Mansion",
  "description": "Home lobby exterior."
}
```

The asset id is **not** in the manifest — `make assets-upload` records it in `assets/asset-ids.json`.
Commit the `.glb` (it goes to LFS automatically via `.gitattributes`).

## Uploading

```sh
export ROBLOX_API_KEY=...          # Open Cloud key with asset:write
export ROBLOX_CREATOR_ID=...       # your user id, or the group id
export ROBLOX_CREATOR_TYPE=user    # or "group"
make assets-upload                 # uploads mesh entries with no recorded asset id
make assets-upload ARGS=--force    # re-upload all mesh entries (new asset versions)
```

`make assets-upload` reads the manifest and uploads each pending GLB directly to the **Open Cloud
Assets API** (`POST /assets/v1/assets`, `assetType:"Model"`, MIME `model/gltf-binary`, via `curl` —
rbxcloud's CLI is FBX-only), polls the operation to completion, writes the returned ids into
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
