---
name: flex-with-friends-dev
description: >-
  Architectural conventions, development lifecycle, and CI/Makefile workflow for the
  Flex-with-Friends Roblox game (Rojo + Wally + Luau). Use this whenever writing, structuring,
  reviewing, or debugging code in this repo — adding a server Service or client Controller,
  wiring RemoteEvents, persisting player data, awarding or deducting followers/reputation,
  unlocking places or NPCs, generating 3D models/environments/props, running the quality gates
  (make ci/fmt/lint/analyze/build), starting a new phase or goal, or deciding where a file belongs.
  Apply it even when the user doesn't name it, e.g. "add a photo system", "implement the travel
  minigame", "why won't analyze pass", "add a new place", "persist this value", "run the checks",
  "generate a model for the lobby".
---

# Flex-with-Friends — engineering conventions

Flex-with-Friends is a multiplayer Roblox "influencer simulator". The codebase is authored on
disk in **Luau** and synced to Studio with **Rojo**; dependencies are managed by **Wally**; the
toolchain is pinned by **Rokit**. Studio is used for assets and runtime testing, not as the source
of truth — the source of truth is `src/` + `default.project.json` in git.

This skill is the fast path. For depth, read the reference files when the task calls for it:

- `references/architecture.md` — full layout, the bootstrapper contract, data model, networking, place model.
- `references/lifecycle.md` — the phased plan, goal-driven verification, branching, how to runtime-verify.
- `references/makefile.md` — every `make` target, the pinned tools, and the analyze gotchas.

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
6. **One phase-step per commit, each independently verifiable.** Branch off `main` before
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

## Development loop

```
1. Branch off main                          (phase-N-... or a task name)
2. Implement the smallest verifiable step   (one service / one feature slice)
3. make ci                                  -> fmt-check, lint, analyze, build all green
4. Runtime-verify in Studio                 (see below — a green build does NOT prove it runs)
5. Commit (one step, Co-Authored-By trailer)
6. Repeat for the next step
```

Define success as a checkable criterion before you start (the plan's **Verify** lines are written
this way). "Add validation" becomes "write the invalid-input case, make it pass". Strong criteria
let you loop without re-asking.

## Make targets (quick reference)

Run `make help` for the live list. Tools must be on `PATH` (`make install` provisions them via
Rokit). Full details and gotchas in `references/makefile.md`.

| Command | Use it when |
|---|---|
| `make install` | First checkout / after changing `rokit.toml` or `wally.toml`. |
| `make fmt` | Before committing — auto-format Luau (StyLua). |
| `make fmt-check` / `make lint` / `make analyze` | Individual gates while iterating. |
| `make build` | Produce `build.rbxl`. |
| `make ci` | The full gate (`fmt-check → lint → analyze → build`). Run before every commit/PR. |
| `make serve` | Live-sync to Studio during development (`rojo serve`). |
| `make clean` | Remove generated artifacts. |

## Verifying that code actually runs

**Rojo only packages Luau — it does not compile it**, so `make build` passing does *not* prove your
scripts run or even parse at runtime. Two complementary checks:

- **`make analyze`** — static type-check via luau-lsp. Catches type errors and unknown globals.
- **Runtime check in Studio** — for logic that must execute (a bootstrapped service, a remote
  handler), confirm it in a running place. The lightweight way is the Roblox Studio MCP
  `execute_luau` tool: run the real logic (or a Play session) and assert the observed behavior,
  rather than trusting the build. `get_console_output` may return a stale snapshot — prefer having
  the executed code *return* its evidence. See `references/lifecycle.md` for the pattern used to
  verify the bootstrapper.

## 3D assets

Default to **GenAI ProceduralModels** for any 3D asset (environments, props, characters, vehicles).
Generate them with the Studio Assistant or the MCP `generate_procedural_model` tool — the output is
a scripted, primitive-based model with **user-editable attributes** (size, color, proportions) you
can tune without regenerating. Prefer it because it keeps GenAI in the loop and is parametric rather
than an opaque binary blob. Reach for `generate_mesh` only when primitives can't express the shape,
`generate_material` for surfacing, and the Creator Store as a fallback. Record each model's prompt +
attribute defaults under `assets/` (code/place stays the source of truth; assets are referenced by
name/id). Detail in `references/architecture.md`.

## Common gotcha: analyze fails on a dynamic `require`

luau-lsp can't resolve `require(someInstanceVariable)` and reports `Unknown require: unsupported
path`. That's expected for a generic loader, not a bug. The idiom (used in `Bootstrap.lua`) is to
cast: `(require :: any)(child)`. Use it only for genuinely dynamic requires; static requires should
stay statically typed so analyze can check them.
