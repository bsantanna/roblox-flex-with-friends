# Architecture reference

Depth behind the conventions in `SKILL.md`. Read the section you need.

## Contents
- [Stack](#stack)
- [Repository layout](#repository-layout)
- [Rojo mapping rules](#rojo-mapping-rules)
- [Bootstrapper](#bootstrapper)
- [Services and Controllers](#services-and-controllers)
- [Player data model](#player-data-model)
- [Follower / reputation economy](#follower--reputation-economy)
- [Networking contract](#networking-contract)
- [Place / travel model](#place--travel-model)
- [Assets](#assets)

## Stack

- **Rojo** — filesystem ↔ Studio sync and `.rbxl` builds. Source of truth is `src/` + `default.project.json`.
- **Wally** — package manager. Dependencies are deliberately minimal. `ProfileStore`
  (`lm-loleris/profilestore`, **server realm** → `[server-dependencies]` → installs to
  `ServerPackages/`) handles DataStore session-locking. Don't hand-roll DataStore code.
- **Rokit** — pins every tool (`rokit.toml`): rojo, wally, StyLua, Selene, luau-lsp.
- **Luau**, `--!strict` on new modules where practical.

No game framework (Knit/Flamework). The hand-rolled `Bootstrap` is intentionally enough — add a
framework only if a concrete need appears, not preemptively.

## Repository layout

```
default.project.json        Rojo project: maps src/ to Roblox services
wally.toml / wally.lock      dependency manifest + lockfile (lockfile is committed)
src/
  shared/    -> ReplicatedStorage/Shared
    Config/                  tunables: follower rewards, decay, unlock thresholds, place defs
    Net.lua                  RemoteEvent/RemoteFunction registry (the network contract)
    Types.lua                shared type defs (Profile, PlaceId, NpcId, ...)
    Bootstrap.lua            Init-then-Start loader (already exists)
    Util/
  server/    -> ServerScriptService/Server
    init.server.lua          boots everything under services/
    services/                DataService, FollowerService, ReputationService, PlaceService,
                             PhotoService, NpcService, MinigameService, ...
  client/    -> StarterPlayer/StarterPlayerScripts/Client
    init.client.lua          boots everything under controllers/
    controllers/             HudController, PhotoController, InteractionController,
                             MinigameController, TravelController, ...
    ui/
ServerPackages/ -> ServerScriptService/ServerPackages   (Wally server deps; git-ignored)
```

`Config`, `Net.lua`, `Types.lua`, `services/`, `controllers/`, `ui/` are created as the relevant
phase needs them — they may not all exist yet. `Bootstrap.lua` and the two entry points do.

## Rojo mapping rules

- Directory with `init.server.lua` → server `Script` named after the directory.
- Directory with `init.client.lua` → `LocalScript`.
- Directory with `init.lua` → `ModuleScript`.
- Any other directory → `Folder`; `.lua`/`.luau` files in it → `ModuleScript`s.

If you add a new top-level source area (a shared `Packages/` once a *shared* Wally dep is added, a
new service realm, etc.), add the mapping to `default.project.json`. Only map paths that exist —
mapping a missing folder breaks `rojo build`.

## Bootstrapper

`src/shared/Bootstrap.lua` exposes `Bootstrap.run(container: Instance?)`. It requires every
`ModuleScript` child of `container`, then runs all `:Init()` methods, then all `:Start()` methods.
`init.server.lua` calls `Bootstrap.run(script:FindFirstChild("services"))`; `init.client.lua` uses
`controllers`. A nil/empty container is fine (Phase 0 reality).

Why two phases: **Init** is global wiring (after it, every module exists and is configured);
**Start** is runtime activation (cross-service calls are safe because everyone is initialized).
Putting event connections in Init risks firing handlers before another service is ready — that's
the bug the ordering prevents.

The loader uses `(require :: any)(child)` because the require path is a runtime Instance; see the
analyze gotcha in `SKILL.md`.

## Services and Controllers

Module contract (both server services and client controllers):

```lua
--!strict
local Service = {}

function Service:Init() end   -- optional: wiring/state
function Service:Start() end  -- optional: runtime

return Service
```

- **Services** (server) own game logic and authoritative state. They may require each other
  directly (`require(script.Parent.OtherService)`); rely on cross-service state only in `Start`.
- **Controllers** (client) own UI/input. They send requests through `Net` and react to server
  events. They never decide rewards or trust local state for authoritative outcomes.

Both are auto-discovered by the bootstrapper — there is no manual registration list.

## Player data model

`DataService` wraps ProfileStore: load profile on join, release on leave, expose
`GetProfile(player)`, reconcile new keys on schema changes. Shape:

```
Profile.Data = {
  Followers      = 0,        -- the scoreboard number
  Reputation     = 50,       -- 0..100, modulates follower swings at places
  UnlockedPlaces = { "Home", "Airport" },
  UnlockedNpcs   = {},
  Stats          = { PhotosTaken = 0, TripsTaken = 0, FriendsInvited = 0 },
  LastSeen       = 0,        -- os.time(), for offline decay
  CompanionNpc   = nil,
}
```

ProfileStore values must be plain tables (no Instances, no userdata like Vector3/Color3, no
functions, no mixed/gappy arrays). Serialize before storing.

## Follower / reputation economy

`FollowerService` is the **single writer** of `Followers`. API: `Award(player, amount, reason)` and
`Deduct(player, amount, reason)`, clamps at ≥ 0, fires the `FollowerChanged` remote, and mirrors the
value into `leaderstats.Followers` (the native Roblox scoreboard the game's pitch depends on).
`ReputationService` is the single writer of `Reputation` and is consumed by place/event logic.
Everything that grants or removes followers — photos, travel arrival, minigames, decay, invites,
philanthropy — calls these methods. Never write the balance from elsewhere.

## Networking contract

`src/shared/Net.lua` registers every `RemoteEvent`/`RemoteFunction` by name so the whole contract
is greppable in one file. Server handlers validate every payload (types, ranges, ownership,
cooldowns). MVP events include: `FollowerChanged`, `RequestPhotoCapture`, `PhotoResult`,
`RequestTravel`, `TravelComplete`, `StartMinigame`, `MinigameInput`, `MinigameResult`,
`InviteFriend`, `UnlockNpc`. Add new ones here, never as loose Instances.

## Place / travel model

MVP keeps **Home**, **Airport**, **Beach** as zones in one place; "travel" repositions the player
(with a fade) and runs the airport minigame between zones. True cross-place open worlds via
`TeleportService` (public servers, reserved party servers) are a later phase. Build the loop in one
place first, then introduce multi-place complexity. Place unlock gating is by follower count, read
from `Config`.

## Assets

**3D assets are GenAI ProceduralModels by default.** Generate them with the Studio Assistant or the
MCP `generate_procedural_model` tool. A ProceduralModel is a *scripted* model built from primitives
(blocks, spheres, cylinders, wedges) whose look is driven by **user-editable attributes** (size,
color, proportions) — so it's parametric, AI-(re)generatable, and tweakable after generation
*without* regenerating. That fits this repo's code-as-source-of-truth philosophy far better than an
opaque binary mesh, and keeps GenAI in the loop for iteration.

Order of preference for a new 3D asset:

1. **`generate_procedural_model`** — the default. Pass the user's own words; if specific tunables
   are wanted (head size, wheel count, palette), name them so they're exposed as attributes.
2. **`generate_mesh`** — only when primitives genuinely can't express the shape. Produces an
   AI-generated textured `MeshPart` (binary, not parametric).
3. **`generate_material`** — AI `MaterialVariant` (set `Material` + `MaterialVariant` on BaseParts)
   for surfacing.
4. **Creator Store** — free existing assets as a fallback.

Generated instances live in the `.rbxl` (binary, not cleanly diffable in git), so **code stays the
source of truth and references assets by name/id**. Record each ProceduralModel's prompt and
attribute defaults under `assets/` so a model can be regenerated or justified from source rather
than being an unexplained blob in the place file.

### Inherited AI-mesh assets (OBJ → Open Cloud)

Not every asset is a ProceduralModel. Some are **AI-generated OBJ meshes** committed under
`assets/source/<Id>/` and uploaded to Roblox via Open Cloud, then referenced by asset id — the
hand-authored spec is `assets/manifest.json`, `make assets-upload` records ids in
`assets/asset-ids.json` and re-uploads any source whose content hash changed (PATCHing an existing id
in place; state in `assets/.upload-state.json`). Full pipeline in `assets/PIPELINE.md` and
`doc/003_binary_asset_management.md`.

These raw OBJs are a single welded, untextured, ~40k-tri shell, so **painting the mesh fights the
geometry**. To make one look good, *interpret and rebuild it as clean part-based geometry, then
repaint and bake*, exporting over the existing `.glb` so the upload picks up the change. The full
workflow and rationale are in the skill's "3D assets" section (Improving an AI-generated mesh asset);
the modeling mechanics are the **blender-assembly** skill.
