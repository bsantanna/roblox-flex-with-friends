# Contributing

Flex-with-Friends is authored in **Luau** on disk and synced to Studio with **Rojo**. The source of
truth is `src/` + `default.project.json` in git — not the `.rbxl`. See `doc/002_implementation_plan.md`
for the roadmap and `.claude/skills/flex-with-friends-dev` for the engineering conventions.

## Setup

```sh
make install   # provisions the pinned toolchain (Rokit) + deps (Wally)
```

The Rokit bin dir (`~/.rokit/bin`) must be on `PATH`.

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

## Deployment (Open Cloud, staging)

`.github/workflows/cd.yml` publishes `build.rbxl` to a **staging** universe on merge to `main`.
It is **inert until configured**. To enable it:

1. Create the staging universe/place in Roblox.
2. Create an Open Cloud **API key** with `universe-places:write` scoped to that place.
3. In the repo: add secret `ROBLOX_API_KEY`, and variables `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID`.

Until all three exist the deploy job runs, detects the missing config, and skips with a notice.
