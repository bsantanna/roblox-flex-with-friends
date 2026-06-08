# Contributing

Flex-with-Friends is authored in **Luau** on disk and synced to Studio with **Rojo**. The source of
truth is `src/` + `default.project.json` in git — not the `.rbxl`. See `doc/002_implementation_plan.md`
for the roadmap and `.claude/skills/flex-with-friends-dev` for the engineering conventions.

## Setup

```sh
make install   # provisions the pinned toolchain (Rokit) + deps (Wally)
git lfs install && git lfs pull   # fetch binary 3D sources (GLB/OBJ under assets/source)
```

The Rokit bin dir (`~/.rokit/bin`) must be on `PATH`. The 3D mesh pipeline (GLB/OBJ → Open Cloud →
in-game) is documented in `assets/PIPELINE.md` and `doc/003_binary_asset_management.md`; upload
meshes with `make assets-upload` (OBJ uploads also need Node for `obj2gltf`).

## Development loop

```sh
make serve     # live-sync src/ + assets into an open Studio place
# edit code...
make fmt       # format (StyLua)
make ci        # fmt-check -> lint -> typecheck -> test -> build (the full gate)
```

Run `make ci` green before every commit/PR. For logic that must actually execute (remotes, UI,
CaptureService, a bootstrapped service), also verify in a running Studio place — a green build does
not prove scripts run.

## Quality gates (`make ci`)

| Stage | Tool | What it checks |
|---|---|---|
| `fmt-check` | StyLua | formatting |
| `lint` | Selene | lint rules |
| `analyze` | luau-lsp | `--!strict` type-checking |
| `test` | Lune | headless unit tests (`tests/*.spec.luau`) — see `TESTING.md` |
| `build` | Rojo | produces `build.rbxl` |

GitHub Actions runs `make ci` on every PR (`.github/workflows/ci.yml`).

## Branching & commits

- Branch off `main` (e.g. `phase-2-places`); never commit straight to `main`.
- One verifiable step per commit. End commit messages with the project's `Co-Authored-By` trailer.
- Open a PR; CI must be green to merge.

## Conventions (the load-bearing ones)

- **Server-authoritative** for anything affecting followers/reputation/data — never trust the client.
- **Single writer per resource** (followers → `FollowerService`, etc.); others ask, never mutate.
- **Tunables in `src/shared/Config`**, never magic numbers in logic.
- **Every remote registered in `Net.lua`** and validated server-side.
- **Functional core / imperative shell** — pure logic in `src/shared/Logic/` (Roblox-free, unit-tested
  under Lune); services/controllers stay thin.

## Deployment (Open Cloud, manual)

There is **no automated deploy** — publishing to Roblox is done **manually** by the maintainer, so a
merge to `main` never changes what's live. To publish the built place yourself:

1. `make build` to produce `build.rbxl`.
2. Create an Open Cloud **API key** with `universe-places:write` scoped to the target place.
3. Publish with the pinned `rbxcloud`:

   ```sh
   rbxcloud experience publish --filename build.rbxl \
     --universe-id <UNIVERSE_ID> --place-id <PLACE_ID> \
     --version-type published --api-key <API_KEY>
   ```

Mesh assets are uploaded manually too, via `make assets-upload` (see `assets/PIPELINE.md`).
