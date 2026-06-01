# assets

3D content that ships in the built place. `make build` produces `build.rbxl`
**only** from `src/` + `default.project.json`, so anything you want in the
world must be reachable from this folder (or built at runtime by a service).

## Division of labor

- **Functional geometry** (spawn, collision floors, ProximityPrompt anchors) is
  built in code by `WorldService` into `Workspace.World`, positioned from
  `Config.Zones`. It's parametric and gameplay-critical.
- **Visual art** (house, plane, airport terminal, beach props) lives here as
  saved model files and is mapped into `Workspace.Scenery` by Rojo. The two
  folders never collide.

## manifest.json — the asset spec (single source of prompts + attributes)

`manifest.json` is the structured spec for every designed model: its
generation `prompt`, `attributes` defaults, target `zone`, and `offset` from the
zone origin. It is an **authoring-time** spec — the game runtime never reads it.
It replaces the old per-model `scenery/<Name>.md` notes; record new models here.

Each entry's fields:

| Field | Meaning |
|---|---|
| `id` | Model name → `Workspace.Scenery.<id>`, saved as `scenery/<id>.rbxmx`. |
| `zone` | `Home` / `Airport` / `Beach`; resolves the origin (mirrors `Config.Zones`). |
| `category` | `structure` / `prop` / `vehicle` / `character`. |
| `status` | `buildable` (build it now) or `planned` (Phase 2+ stub, prompt only). |
| `prompt` | Natural-language input for `generate_procedural_model`. |
| `attributes` | Desired editable-attribute defaults to apply after generation. |
| `offset`, `rotationY` | Placement relative to the zone origin. |
| `justification` | Why it exists / what it ties to in code. |

## scenery/ — designed models (the main asset path)

`default.project.json` maps `assets/scenery/` → `Workspace.Scenery`. Each saved
model file becomes an instance:

- `assets/scenery/House.rbxmx` → `Workspace.Scenery.House`
- `.rbxmx` = XML (larger, somewhat diffable in git). `.rbxm` = binary (smaller).

### Driver: turning a manifest entry into a committed model

For each `buildable` entry in `manifest.json` (`planned` entries are skipped
until their phase):

1. Generate the model with the `generate_procedural_model` MCP tool (or Studio
   Assistant), passing the entry's `prompt`. ProceduralModels are preferred:
   scripted primitives with editable attributes (size/color/proportions).
2. Apply the entry's `attributes` and name the model `<id>`.
3. Position it at `Config.Zones[zone] + offset`, rotated by `rotationY`
   (Home `(0,0,0)`, Airport `(0,0,200)`, Beach `(0,0,400)`).
4. In Explorer: right-click the model → **Save to File…** → save into
   `assets/scenery/` as `<id>.rbxmx`.
5. `make build` (or live `make serve`) now includes it. Commit the file.

The `prop`/`vehicle`/`character` offsets in `Home` overlay the existing
`WorldService` ProximityPrompt anchors (and the Personal Trainer spawn), so the
visual art lands on top of the functional greybox without changing the
interaction contract.

## Terrain

Roblox Terrain (voxels) does **not** round-trip through Rojo/files cleanly. Pick
one:

- **Parts/meshes instead of Terrain** — Rojo-mappable (use `scenery/`). Usually
  enough for stylized ground/islands.
- **Generate in code** at runtime (`workspace.Terrain:FillBlock/FillRegion`) from
  a service — reproducible from `src`.
- **Base place** — author terrain in a `.rbxl` and sync scripts into it; terrain
  then lives in the place file, not git.
