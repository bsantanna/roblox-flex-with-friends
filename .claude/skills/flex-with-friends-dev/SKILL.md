---
name: flex-with-friends-dev
description: >-
  Architectural conventions, development lifecycle, and CI/Makefile workflow for the
  Flex-with-Friends Roblox game (Rojo + Wally + Luau). Use this whenever writing, structuring,
  reviewing, or debugging code in this repo — adding a server Service or client Controller,
  wiring RemoteEvents, persisting player data, awarding or deducting followers/reputation,
  unlocking places or NPCs, generating 3D models/environments/props, running the quality gates
  (make ci/fmt/lint/analyze/build), starting a new phase or goal, or deciding where a file belongs.
  Critically, use it for any work that places, moves, sizes, rotates, or arranges things in the 3D
  world — building roads/decks/ramps/structures, positioning props or spawns, generating models,
  laying out a scene — where correctness is spatial and must be verified by simulating in Roblox
  Studio (screen captures, camera framing, walking the character), never judged from the code alone.
  Apply it even when the user doesn't name it, e.g. "add a photo system", "implement the travel
  minigame", "why won't analyze pass", "add a new place", "persist this value", "run the checks",
  "generate a model for the lobby", "this asset/house looks rough — rebuild and repaint the mesh",
  "the road looks off", "this part is floating", "fix the placement", "why is the ramp clipping".
---

# Flex-with-Friends — engineering conventions

Flex-with-Friends is a multiplayer Roblox "influencer simulator". The codebase is authored on
disk in **Luau** and synced to Studio with **Rojo**; dependencies are managed by **Wally**; the
toolchain is pinned by **Rokit**. The source of truth is `src/` + `default.project.json` in git —
not the Studio place file.

But this is a **3D game**, and that changes what "correct" means. Two different things have to be
true, and they're verified in two different ways:

- **Logic correctness** — does the service award the right followers, persist the right data, gate
  the right unlock? You verify this by reading code, `make analyze`, and `execute_luau`.
- **Spatial correctness** — does the road actually rest on the terrain, do the guardrails line up,
  is the ramp walkable, does the view deck overlook the water instead of clipping a mountain, is
  anything floating, sunk, rotated, or overlapping? **Code cannot tell you this.** A CFrame, an
  offset, a size — they all type-check perfectly while producing geometry that's visibly wrong in
  3D. The only way to know is to *look*: open Studio, position the camera, and capture the scene.

So Studio is not just "where assets and runtime tests happen" — for anything you place in the
world, it is the instrument you verify with. **Never sign off on spatial work from code alone.**
See [Seeing the scene](#seeing-the-scene-spatial-verification) below.

This skill is the fast path. For depth, read the reference files when the task calls for it:

- `references/architecture.md` — full layout, the bootstrapper contract, data model, networking, place model.
- `references/lifecycle.md` — the phased plan, goal-driven verification, branching, how to runtime-verify.
- `references/makefile.md` — every `make` target, the pinned tools, and the analyze gotchas.
- `references/minigames.md` — the NPC-minigame framework + the recipe for adding one (read before
  building, extending, or debugging an NPC minigame — e.g. Simon Says).

The authoritative roadmap is `doc/002_implementation_plan.md`. When in doubt about *what* to build
next, read it; this skill is about *how* to build it.

## Golden rules

These are the conventions that keep the game correct and the diffs clean. Internalize the *why* —
they're not bureaucracy, they prevent specific failure modes.

1. **Server-authoritative.** Anything that changes followers, reputation, unlocks, or persisted
   data happens on the server. Never trust a client request — validate it. A client that can award
   its own followers is an exploit, not a feature.
2. **Single writer per resource.** Followers are written only by `FollowerService`; reputation only
   by `ReputationService`. Other code *asks* (`FollowerService:Award(player, amount, reason)` /
   `:Deduct(...)`), it never mutates the balance directly. One writer means one place to audit,
   clamp, replicate, and rate-limit.
3. **Tunables live in `Config`, not in logic.** Reward amounts, decay rates, unlock thresholds,
   place definitions go in `src/shared/Config`. If you're typing a magic number into a service,
   stop and put it in `Config`.
4. **Register every remote in `Net.lua`.** The full client↔server contract is greppable in one
   module, and every server-side handler validates its inputs. No ad-hoc `RemoteEvent` instances.
5. **Surgical, simple changes.** Match the surrounding style; touch only what the task needs; no
   speculative abstractions or config that wasn't asked for. This repo follows the guidelines in
   `.claude/CLAUDE.md` — read them once if you haven't. When a 200-line approach could be 50, write 50.
6. **Verify spatial work by looking, never by reasoning about the numbers.** Anything you place,
   move, size, or rotate in the 3D world is unverified until you've seen it in Studio. The math can
   be "obviously right" and the result still floats, clips, or faces the wrong way — offsets compound,
   CFrame rotations apply in an order you didn't expect, the terrain isn't where you assumed. Don't
   talk yourself into "this should be correct"; capture the scene and check. This is the rule people
   skip because reading code feels faster — and it's why placement bugs ship.
7. **One phase-step per commit, each independently verifiable.** Branch off `main` before
   committing (e.g. `phase-1-data-persistence`). Commit messages end with the project's
   `Co-Authored-By` trailer.

## Where code goes

```
src/shared/   -> ReplicatedStorage/Shared          Config/, Net.lua, Types.lua, Bootstrap.lua, Util/
src/server/   -> ServerScriptService/Server         init.server.lua + services/
src/client/   -> StarterPlayer/StarterPlayerScripts  init.client.lua + controllers/
ServerPackages/ -> ServerScriptService/ServerPackages (Wally server deps, e.g. ProfileStore)
```

A directory with `init.server.lua` becomes a server `Script`; with `init.client.lua` a
`LocalScript`; with `init.lua` a `ModuleScript`; otherwise a `Folder`. The mapping is in
`default.project.json` — if you add a new top-level area, update that file.

## The bootstrapper contract

`src/shared/Bootstrap.lua` is how every server Service and client Controller comes alive. Given a
folder of `ModuleScript`s it requires each one, calls `:Init()` on **all** of them, then `:Start()`
on **all** of them. The two-phase order is the contract that lets services depend on each other:

- **`Init()`** — wiring and state setup only. After Init runs for everyone, all services exist and
  are configured. Do *not* assume another service has started yet.
- **`Start()`** — runtime work: connect events, register remotes, spawn loops. By now every service
  is fully initialized, so cross-service calls are safe.

A module that needs neither can omit both; Bootstrap only calls methods that exist.

## Recipe: add a server Service

Services are the unit of server logic (FollowerService, DataService, PhotoService, …).

1. Create `src/server/services/<Name>Service.lua` (create the `services/` folder if it's the first one).
2. Use this shape:
   ```lua
   --!strict
   local <Name>Service = {}

   function <Name>Service:Init()
       -- wiring: cache references, build state, read Config
   end

   function <Name>Service:Start()
       -- runtime: connect remotes/events, start loops
   end

   return <Name>Service
   ```
3. It's wired automatically — `src/server/init.server.lua` boots everything under `services/`. No
   registration list to edit.
4. Route any follower/reputation/data change through the owning service (rule 2). Pull tunables
   from `Config` (rule 3).
5. If it talks to clients, add the event(s) to `Net.lua` and validate inputs server-side (rule 4).
6. Verify with `make analyze` (types) and a runtime check in Studio (see below), then `make ci`.

Client **Controllers** are identical but live in `src/client/controllers/` and are booted by
`init.client.lua`. Controllers own UI and input; they send requests to services and react to
server events — they never decide rewards.

**Building an NPC minigame** (a game a player starts by talking to an NPC, like Simon Says) is a
special case: there's a generic framework so each game shares one pre-game flow (walk → ready mark →
rules → confirm) and you only write the game-specific part as a plugin. Don't hand-roll it — read
`references/minigames.md` for the contract and the recipe.

## Development loop

```
1. Branch off main                          (phase-N-... or a task name)
2. Implement the smallest verifiable step   (one service / one feature slice)
3. make ci                                  -> fmt-check, lint, analyze, build all green
4. Verify in Studio                         (logic: does it run? spatial: does it look right? — see below)
5. Commit (one step, Co-Authored-By trailer)
6. Repeat for the next step
```

Define success as a checkable criterion before you start (the plan's **Verify** lines are written
this way). "Add validation" becomes "write the invalid-input case, make it pass". Strong criteria
let you loop without re-asking.

## Make targets (quick reference)

Run `make help` for the live list. The pinned tools live in `~/.rokit/bin`, which a fresh
non-interactive shell (e.g. an agent `Bash` call) usually does **not** have on `PATH` — so `make`,
`stylua`, `rojo`, `lune`, `rbxcloud` fail with *command not found*. Put it on `PATH` first, in the
same command (the `$HOME` form needs no `cd`, so it won't trip a permission prompt):

```sh
export PATH="$HOME/.rokit/bin:$PATH" && make ci
```

`make install` provisions the tools via Rokit. Full details and gotchas in `references/makefile.md`.

| Command | Use it when |
|---|---|
| `make install` | First checkout / after changing `rokit.toml` or `wally.toml`. |
| `make fmt` | Before committing — auto-format Luau (StyLua). |
| `make fmt-check` / `make lint` / `make analyze` | Individual gates while iterating. |
| `make build` | Produce `build.rbxl`. |
| `make ci` | The full gate (`fmt-check → lint → analyze → build`). Run before every commit/PR. |
| `make serve` | Live-sync to Studio during development (`rojo serve`). |
| `make clean` | Remove generated artifacts. |

## Verifying that logic actually runs

**Rojo only packages Luau — it does not compile it**, so `make build` passing does *not* prove your
scripts run or even parse at runtime. Two complementary checks:

- **`make analyze`** — static type-check via luau-lsp. Catches type errors and unknown globals.
- **Runtime check in Studio** — for logic that must execute (a bootstrapped service, a remote
  handler), confirm it in a running place. The lightweight way is the Roblox Studio MCP
  `execute_luau` tool: run the real logic (or a Play session) and assert the observed behavior,
  rather than trusting the build. `get_console_output` may return a stale snapshot — prefer having
  the executed code *return* its evidence. See `references/lifecycle.md` for the pattern used to
  verify the bootstrapper.

That covers *logic*. Anything that occupies space in the world also needs spatial verification:

## Seeing the scene: spatial verification

When you build or move geometry — roads, decks, ramps, guardrails, NPC spawns, props, a whole
island ring like `IslandService` — the question "is it right?" is a question about a 3D scene, and
you answer it by **looking at the scene**, not by re-reading the CFrame math. Treat this as a tight
visual loop, the same way you'd treat a failing test:

```
1. Run the placement (execute_luau: require the service, call its build fn)
2. Point the camera at what you changed, capture it (screen_capture)
3. Compare against the intent — alignment, scale, gaps, clipping, orientation
4. Adjust the tunable in Config (offsets/sizes live there, rule 3), re-run
5. Repeat until the picture matches the intent
```

The Studio MCP gives you everything this loop needs:

- **`screen_capture`** — the core instrument. It returns an actual image of the viewport, so you
  *see* the result instead of imagining it. One angle is never enough — geometry that floats or
  clips often hides behind other parts. Take at least: a **top-down** shot (judges layout,
  alignment, spacing, symmetry) and an **eye-level** shot (judges scale, sightlines, whether a
  human-sized player reads the space as intended). Add **close-ups at the seams** — where a ramp
  meets the road, a guardrail meets a deck, a slip-road merges — because that's where offset errors
  show up first.
- **Camera control** — set `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable` then
  its `.CFrame = CFrame.lookAt(eye, target)` via `execute_luau`, *then* `screen_capture`. Frame the
  exact thing you changed; don't capture whatever the camera happened to be showing.
- **`character_navigation`** — walk the player character through the space to check it from the
  player's point of view and to test that ramps are actually walkable, gaps aren't fall-throughs,
  and decks are reachable. Spatial correctness includes *traversability*, which a screenshot alone
  won't prove.
- **`inspect_instance` / `search_game_tree`** — read back the real positions and sizes as a
  numeric cross-check when a screenshot is ambiguous (e.g. confirm two parts share an edge). Use it
  to *confirm* what you see, not as a substitute for seeing.

If the studio isn't connected, `list_roblox_studios` / `set_active_studio` get you a session. Don't
report spatial work as done on the strength of the code — report it with the screenshot that shows
it's right.

## 3D assets

Default to **GenAI ProceduralModels** for any 3D asset (environments, props, characters, vehicles).
Generate them with the Studio Assistant or the MCP `generate_procedural_model` tool — the output is
a scripted, primitive-based model with **user-editable attributes** (size, color, proportions) you
can tune without regenerating. Prefer it because it keeps GenAI in the loop and is parametric rather
than an opaque binary blob. Reach for `generate_mesh` only when primitives can't express the shape,
`generate_material` for surfacing, and the Creator Store as a fallback. Record each model's prompt +
attribute defaults under `assets/` (code/place stays the source of truth; assets are referenced by
name/id). Detail in `references/architecture.md`.

Generation is *where spatial correctness bites hardest* — a model can come back the wrong scale,
mis-proportioned, or oriented oddly, and the attribute values won't tell you. After generating (and
after tuning attributes), capture it in Studio per [Seeing the scene](#seeing-the-scene-spatial-verification)
before considering it placed.

### Improving an AI-generated mesh asset: interpret → rebuild → repaint

Some assets arrive as **AI-generated OBJ meshes** under `assets/source/<Id>/<Id>.obj` (e.g. the
`Neighbor*` houses) — the output of an external mesh generator, uploaded to Roblox via the
`make assets-upload` pipeline (`assets/PIPELINE.md`). These are a trap to "paint": each is a single
welded shell, tens of thousands of tris, with no separable parts, no UVs, and a blank (all-white)
vertex-color layer. There are no clean faces to grab — what looks like a window is just a shadowed
recess — so assigning materials to the raw mesh by region/recess heuristics fights the geometry and
still looks mushy. (We tried; it doesn't get there.)

Treat the OBJ as a **reference to interpret and rebuild**, not a thing to fix:

1. **Interpret.** Load the OBJ in Blender as reference only. Measure its massing — bounding box plus a
   height/z-band histogram of the footprint exposes the floors, roof line, and chimney positions — and
   render clay views from several angles to read what it actually is and where its parts are. (It may
   not be what its name implies — `Neighbor01` turned out to be a house, not a person; *look* before
   you model.)
2. **Rebuild.** Model a clean, part-based copy of that massing, one object per logical part
   (foundation, walls, columns, roof, windows = frame + glass, door, chimneys, steps…). Follow the
   **blender-assembly** skill — connection map first, `size=2` cubes, bmesh for sloped/angled pieces
   like roof planes (never Euler-rotated boxes), verifying each part's bounds and overlaps as you go.
3. **Repaint.** Give each part its own single material in the chosen palette — no per-face guessing,
   because every part is already its own clean piece of geometry.
4. **Bake & export in place.** UV-unwrap, bake the per-part colors into one texture, consolidate to a
   single textured material, and export over the existing `<Id>.glb` / `<Id>.blend` /
   `<Id>_BaseColor.png` — Y-up, origin at the base center, and roughly the original's bounding box so
   the manifest's `scale` and placement still hold. Overwriting the `.glb` changes its hash, so
   `make assets-upload` re-uploads just that asset, PATCHing the existing id with no manifest edit.

This is the **standard pipeline for every `assets/source/*.obj`** (Neighbor houses, cars, props —
not a one-off), so don't re-derive the Blender code each time. The skill bundles the whole toolkit in
`scripts/blender_asset_helpers.py`: `import_reference`, `massing`, `new_collection`, `box`,
`make_beam`, `poly_roof`, `bounds`/`overlap`, `flat_material`, `paint`, `comic_lighting`,
`render_views`, and `finalize_and_export` (join → UV → bake → overwrite the `.glb`/`.blend`/`.png` in
place). Load it once per Blender session and reuse it across `execute_blender_code` calls — the import
is cached for the life of the process:

```python
import sys; sys.path.insert(0, "<this skill's dir>/scripts")  # base dir is printed when the skill loads
import blender_asset_helpers as bah
```

Its module docstring walks the full loop end to end. Lean on it; only drop to raw `bpy` for geometry
the helpers don't cover.

Why rebuild instead of paint: clean parts read correctly (crisp windows, trim, door) and the result
is ~100× lighter — a Neighbor house went from ~43k tris to ~330. And **every stage is a visual
checkpoint** — massing, then roof, then windows, then paint, then the final bake — rendered and
eyeballed, never signed off from the code. It's the [Seeing the scene](#seeing-the-scene-spatial-verification)
loop applied to modeling.

## Common gotcha: analyze fails on a dynamic `require`

luau-lsp can't resolve `require(someInstanceVariable)` and reports `Unknown require: unsupported
path`. That's expected for a generic loader, not a bug. The idiom (used in `Bootstrap.lua`) is to
cast: `(require :: any)(child)`. Use it only for genuinely dynamic requires; static requires should
stay statically typed so analyze can check them.
