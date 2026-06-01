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

## scenery/ — designed models (the main asset path)

`default.project.json` maps `assets/scenery/` → `Workspace.Scenery`. Each saved
model file becomes an instance:

- `assets/scenery/House.rbxmx` → `Workspace.Scenery.House`
- `.rbxmx` = XML (larger, somewhat diffable in git). `.rbxm` = binary (smaller).

### Workflow to add a model

1. Build it in Studio, or generate a ProceduralModel (Studio Assistant or the
   `generate_procedural_model` MCP tool). ProceduralModels are preferred: scripted
   primitives with editable attributes (size/color/proportions).
2. Position it at the right zone before saving (`Config.Zones`):
   Home `(0, 0, 0)`, Airport `(0, 0, 200)`, Beach `(0, 0, 400)`.
3. In Explorer: right-click the model → **Save to File…** → save into
   `assets/scenery/` as `<Name>.rbxmx`.
4. `make build` (or live `make serve`) now includes it. Commit the file.

Record each ProceduralModel's prompt + key attribute defaults in
`scenery/<Name>.md` so it can be regenerated/justified from source.

## Terrain

Roblox Terrain (voxels) does **not** round-trip through Rojo/files cleanly. Pick
one:

- **Parts/meshes instead of Terrain** — Rojo-mappable (use `scenery/`). Usually
  enough for stylized ground/islands.
- **Generate in code** at runtime (`workspace.Terrain:FillBlock/FillRegion`) from
  a service — reproducible from `src`.
- **Base place** — author terrain in a `.rbxl` and sync scripts into it; terrain
  then lives in the place file, not git.
