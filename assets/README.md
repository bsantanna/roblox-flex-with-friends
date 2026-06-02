# assets

3D content for the game. The built place comes **only** from `src/` +
`default.project.json`, so anything in the world is either built in code by a
service or referenced by asset id — never a binary blob committed here.

## How the world is produced (all at runtime, reproducible from `src`)

| Layer | Built by | Into | Source |
|---|---|---|---|
| **Functional geometry** — floors, spawn, ProximityPrompt anchors, terrain | `WorldService` | `Workspace.World` | `Config.Zones`, `Config.Terrain` |
| **Code-built scenery** — stylized primitive models (house, plane, cabana, …) | `SceneryService` | `Workspace.Scenery` | primitives in code |
| **Uploaded mesh scenery** — GLB meshes referenced by asset id | `MeshSceneryService` | `Workspace.Scenery` | Open Cloud asset ids |

The two scenery services coexist: `SceneryService` gives every spot a primitive
stand-in now; a **GLB mesh supersedes a primitive** when you ship one (remove
that id from `SceneryService` so it isn't doubled up).

## The mesh pipeline (GLB → Open Cloud → in-game)

This is the professional, git-native path for real art. Full details in
[`PIPELINE.md`](PIPELINE.md) and [`../doc/003_binary_asset_management.md`](../doc/003_binary_asset_management.md):

- `assets/source/<Id>/<Id>.glb` — the mesh source, stored in **Git LFS**.
- `make assets-upload` — uploads each pending GLB to the **Open Cloud Assets
  API** and records `id → assetId` in the generated `asset-ids.json`.
- `MeshSceneryService` loads those ids at runtime and places them per the manifest.

## manifest.json — the scenery registry

`manifest.json` is mapped into the tree (`ReplicatedStorage.Shared.SceneryManifest`)
and **read at runtime** by `MeshSceneryService`. It is the **mesh registry**: each
`kind:"mesh"` entry (`source`, `zone`, `offset`, `rotationY`, `scale`,
`displayName`, `description`) drives the GLB pipeline; the asset id lives in the
generated `asset-ids.json`, not here. Code-built primitive scenery is **not** in
the manifest — its placement lives in `SceneryService`.

## Terrain

Roblox Terrain (voxels) doesn't round-trip through Rojo, so it's **generated in
code** by `WorldService` from `Config.Terrain` (the reproducible-from-`src`
option). Don't hand-paint terrain into a place file.
