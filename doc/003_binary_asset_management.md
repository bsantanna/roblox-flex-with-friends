# Binary Asset Management

How Flex-with-Friends manages 3D meshes (and other binary assets) the way a professional Roblox
studio does, while keeping **code + data as the source of truth in git**. Companion to
[002_implementation_plan.md](002_implementation_plan.md); the day-to-day quick reference is
[`assets/PIPELINE.md`](../assets/PIPELINE.md).

## The problem

A Roblox game is two different things in one `.rbxl`: **code** (Luau — text, diffs, merges) and the
**3D world** (terrain, meshes, instances — a binary blob that does *not* diff or merge). Committing
the place file to git means binary conflicts, lost work, and no review. Every professional workflow
separates the two and gives each the right tooling.

This project already authors code on disk and syncs it with Rojo (the code pillar is solved). This
document covers the **binary pillar**: how mesh geometry gets in and stays version-controlled.

## Principles

1. **No binary blobs in the place.** Geometry is **uploaded to Roblox and referenced by asset id**;
   the `.rbxl` is a build artifact, never committed.
2. **Source of truth in git.** The editable mesh source (a **GLB**, or an **OBJ** + its `.mtl` and
   textures) lives in git via **Git LFS**; the placement/registry lives in text (`manifest.json`,
   `asset-ids.json`).
3. **Reproducible & automated.** Uploads run through one command against the Open Cloud API; the
   result (asset id) is committed, so a fresh checkout renders the same world.
4. **Data-driven runtime.** A service reads the registry and instantiates meshes at runtime — no
   hand-placed instances saved in a binary.

## Source formats: GLB and OBJ

The Open Cloud Assets API accepts `glb`/`gltf`/`fbx` for Models but **not `obj`**. Two source formats
are supported here, both ending up as a GLB on the wire:

- **GLB** (binary glTF) — the preferred format and what gets uploaded. It is **self-contained** (mesh
  + textures + materials in one file), the **standard output of AI mesh generators and DCC tools**,
  an open spec, and **natively accepted by Open Cloud**. Uploaded as-is.
- **OBJ** (Wavefront) — geometry `.obj` + materials `.mtl` + separate texture images. Common DCC/AI
  output, but **not a valid Open Cloud upload format and not self-contained**, so `make assets-upload`
  **converts it to a self-contained GLB** ([obj2gltf](https://github.com/CesiumGS/obj2gltf), npm)
  before upload. The OBJ remains the editable source in git; the GLB is a throwaway upload artifact.

Meshes are generated out-of-band (a separate model/session) and dropped into
`assets/source/<Id>/` as `<Id>.glb`, or `<Id>.obj` (+ `.mtl` + textures).

## The pipeline

```
generate GLB ──▶ assets/source/<Id>/<Id>.glb        (Git LFS)
   — or —
generate OBJ ──▶ assets/source/<Id>/<Id>.obj (+ .mtl + textures)   (Git LFS)
                 register entry in assets/manifest.json (kind:"mesh", placement)
                          │
   make assets-upload ────┤  .obj? ──▶ obj2gltf ──▶ temp GLB   (npm; discarded after upload)
   (Open Cloud, via curl) │  POST /assets/v1/assets   (assetType Model, MIME model/gltf-binary)
                          │  poll  /assets/v1/operations/{id} ──▶ response.assetId
                          ▼
                 assets/asset-ids.json   (generated: id → assetId, committed)
                          │
   MeshSceneryService ────┘  reads manifest + asset-ids at runtime
                             InsertService:LoadAsset(assetId) ──▶ scale + pivot to zone+offset
```

### Components

| Piece | Role |
|---|---|
| `assets/source/<Id>/<Id>.glb` (or `<Id>.obj` + `.mtl` + textures) | Editable mesh source, **Git LFS** (`.gitattributes`; the `.mtl` is plain text, not LFS). |
| `assets/manifest.json` | Hand-authored registry; mapped to `ReplicatedStorage.Shared.SceneryManifest` and read at runtime. Mesh entries: `kind:"mesh"`, `source`, `zone`, `offset`, `rotationY`, `scale`, optional `color` (flat rgb tint for geometry-only meshes), `displayName`, `description`. |
| `assets/asset-ids.json` | **Generated** `id → assetId`; mapped to `SceneryAssetIds`. Written by the uploader so the hand-authored manifest is never machine-reformatted. |
| `tools/upload-assets.luau` (`make assets-upload`) | Uploads pending meshes to Open Cloud via `curl` (rbxcloud's CLI is FBX-only), polls the operation, records ids. `.obj` sources are converted to a temp GLB with `obj2gltf` (npm) first. Inert without `ROBLOX_API_KEY` / `ROBLOX_CREATOR_ID` / `ROBLOX_CREATOR_TYPE`. |
| `MeshSceneryService` | Loads `kind:"mesh"` entries with a known asset id; skips pending ones so the build never breaks. |

### Upload mechanics (Open Cloud Assets API)

- A `.obj` source is converted to a temp GLB first (`npx --yes obj2gltf -i in.obj -o out.glb`); the
  upload is always a GLB. This is the only step that needs **Node/npm** on `PATH`.
- `POST https://apis.roblox.com/assets/v1/assets` — multipart: a JSON `request`
  (`assetType:"Model"`, `displayName`, `description`, `creationContext.creator.{userId|groupId}`)
  plus `fileContent` (the GLB, MIME `model/gltf-binary`). Header `x-api-key`.
- Returns `{ "path": "operations/{id}" }`; poll `GET /assets/v1/operations/{id}` until
  `done:true`, then read `response.assetId`.
- The API key needs the **`asset:write`** scope and the creator (user/group) must own the place.

## Contract for the mesh-generating session

Produce a **Roblox-ready GLB or OBJ** and register it (see `assets/PIPELINE.md` for the canonical
version):

- Y-up, Z-forward; **1 unit = 1 stud**; **origin at the base center**; textures embedded in the GLB,
  or (for OBJ) referenced by the `.mtl` with the image files committed alongside.
- Save to `assets/source/<Id>/<Id>.glb`, or `<Id>.obj` (+ `.mtl` + textures), under LFS; add a
  `kind:"mesh"` entry to `manifest.json` with `source` pointing at that file.
- Do **not** put the asset id in the manifest — `make assets-upload` records it in `asset-ids.json`.

## Place in the studio workflow

This is the git-native variant of the standard studio mesh pipeline (external DCC → upload → asset
id → reference). The alternative — building the world in **Team Create** and committing the binary
place — is rejected here: it makes the `.rbxl` the source of truth and fights git. Keeping
code + data authoritative is the right call for this project and what makes it reproducible and
reviewable.

## Tech-debt review (phases 0–1, re: this workflow)

**Found and fixed:**

- `assets/README.md` documented the **deprecated** flow (`.rbxmx` Save-to-File, `generate_procedural_model`
  prompts, and the now-false claim that the runtime never reads the manifest). Rewritten.
- The `Workspace.Scenery` → `assets/scenery` Rojo mapping (and the empty dir) was **vestigial** —
  GLB→assetId→runtime-load saves no `.rbxmx`. Removed; the services create the folder themselves.
- The uploader/manifest were **FBX-based**; switched to **GLB** via the Open Cloud API directly,
  since rbxcloud's CLI is FBX-only.
- `process.spawn` (the uploader's only subprocess call) **does not exist in Lune 0.10.4** — it's
  `process.exec`. The original was never hit (the no-op path exits first); fixed when the first live
  upload exercised it.

**Known, deferred (tracked here):**

- `SceneryService`'s primitive placements are **hardcoded**, not manifest-driven — the manifest is
  now the **mesh registry only** (the legacy procedural entries were removed). *Future:* if it's
  worth unifying, make `SceneryService` read `kind:"procedural"` manifest entries so primitive and
  mesh placement share one source.
- `make assets-upload`'s Open Cloud request/response parsing is **verified** — a live upload of 8
  OBJ-sourced meshes returned asset ids via the `operations/{id}` poll → `response.assetId` path.
- The CD key (`ROBLOX_API_KEY`, `universe-places:write`) and the asset key (`asset:write`) are the
  same env name; use one key with both scopes, or split the names if you prefer separate keys.
- Uploads are **manual** (`make assets-upload`), by design. Revisit CI-driven upload only if asset
  churn makes it worth the added key exposure and per-merge asset versions.
- **OBJ→GLB conversion** shells out to `obj2gltf` via `npx` (Node), the one non-Rokit/non-curl tool
  in the upload path. **Verified** on 8 real OBJs (convert → upload → asset id). Prefer authoring GLB
  directly when the tool can emit it (no conversion, no Node). If OBJ churn grows, consider pinning
  `obj2gltf` (`npm i -g`, or a committed `package.json`).

## Verification status

`make ci` (incl. Lune tests + build) is green. The full upload path is **verified end-to-end**: a
live `make assets-upload` converted 8 OBJ sources to GLB and uploaded them to Open Cloud, recording
their asset ids in `asset-ids.json`. What remains visual-only is in-world **placement** (scale,
vertical seating, facing) — confirm in a running place and tune the manifest `scale`/`offset.y`/
`rotationY` as needed.
