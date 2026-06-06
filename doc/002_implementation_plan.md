# Flex-with-Friends — Implementation Plan

Execution plan for building the game described in [001_initial_idea.md](001_initial_idea.md).
Designed to be run step-by-step with the goal skill: each step has a **Build** task and a
verifiable **Verify** success criterion.

## Locked Decisions

| Decision | Choice |
|---|---|
| Code workflow | **Rojo + git** — Luau in `src/`, synced to Studio. Studio MCP used only for asset/model generation. |
| MVP scope | **Core loop + 1 NPC** (Personal Trainer + one minigame). **Co-op included in MVP.** |
| Assets | **GenAI ProceduralModels first** (Studio Assistant / MCP `generate_procedural_model`), then `generate_mesh` / `generate_material`, then free Creator Store. Grey-box only as temporary placeholder. |
| Co-op | **In MVP**: co-op photos + friend-invite follower bonus. |

## Guiding Principles (from CLAUDE.md)

- Server-authoritative for anything that affects followers/reputation/data. Never trust the client.
- Simplicity first: no framework (Knit/Flamework) unless a concrete need appears. Roll a thin bootstrapper.
- Surgical, incremental commits — one phase step per commit, each independently verifiable.

---

## Architecture

### Tech stack

- **Rojo 7.5.1** — filesystem ↔ Studio sync and `.rbxl` builds.
- **Wally 0.3.2** — package manager. Dependencies kept minimal:
  - **ProfileStore** (DataStore session-locking + safe profiles). Justified: hand-rolled DataStore code loses player data.
  - A small networking helper is **not** added up front — a hand-written `Net` wrapper over `RemoteEvent`/`RemoteFunction` is enough until profiling says otherwise.
  - Exact package versions are pinned in Phase 0 (verify latest at install time).
- **Luau** with `--!strict` on new modules where practical.
- Dev tooling (pinned in `rokit.toml`): `stylua` (format), `selene` (lint), `luau-lsp` (typecheck).
- **Lune** — headless Luau runtime for unit tests (`make test`, part of `make ci`). Pure domain
  logic lives in `src/shared/Logic/` (Roblox-free) so it runs under Lune with no Studio.
- **rbxcloud** — Open Cloud publishing for CD (staging deploy on merge to `main`; see `CONTRIBUTING.md`).

### Repository layout

```
default.project.json        # Rojo project: maps src/ to Roblox services
wally.toml                  # package manifest
src/
  shared/                   # -> ReplicatedStorage/Shared   (run on client + server)
    Config/                 # tunables: follower rewards, decay rates, unlock thresholds, place defs
    Net.lua                 # thin RemoteEvent/RemoteFunction registry
    Types.lua               # shared type defs (Profile, PlaceId, NpcId, ...)
    Util/
  server/                   # -> ServerScriptService/Server
    init.server.lua         # bootstrapper: requires + :Init()/:Start() each service
    services/
      DataService.lua       # ProfileStore wrapper: load/save/release profile
      FollowerService.lua   # authoritative follower balance, earn/lose, leaderstats
      ReputationService.lua # reputation score (used by events later)
      PlaceService.lua      # zone/destination teleport + unlock gating
      PhotoService.lua      # validates photo captures, co-op detection, awards followers
      NpcService.lua        # NPC unlock state + spawning
      MinigameService.lua   # minigame session lifecycle + reward payout
  client/                   # -> StarterPlayer/StarterPlayerScripts/Client
    init.client.lua         # bootstrapper: requires + :Init()/:Start() each controller
    controllers/
      HudController.lua         # follower count + reputation HUD
      PhotoController.lua       # photo-mode camera/UI, capture input
      InteractionController.lua # ProximityPrompts for phone/computer/cab/NPC
      MinigameController.lua    # minigame UI
      TravelController.lua      # destination picker UI
    ui/                     # UI component modules
assets/                     # ProceduralModel specs (prompts + attribute defaults) and asset notes; the generated instances live in the .rbxl
```

`init.server.lua` / `init.client.lua` are a ~20-line loop that `require`s each module,
calls `:Init()` on all, then `:Start()` on all. No DI container, no framework.

### Core data model (player Profile)

```
Profile.Data = {
  Followers      = 0,        -- the scoreboard number
  Reputation     = 50,       -- 0..100, affects follower swings at places
  UnlockedPlaces = { "Home", "Airport" },
  UnlockedNpcs   = {},       -- e.g. { "PersonalTrainer" }
  Stats          = { PhotosTaken = 0, TripsTaken = 0, FriendsInvited = 0 },
  LastSeen       = 0,        -- os.time(), for offline decay
  CompanionNpc   = nil,      -- NPC currently traveling with the player
}
```

`FollowerService` is the single writer of `Followers`; everything else asks it to
`Award(player, amount, reason)` / `Deduct(...)`. `leaderstats` mirrors `Followers` for the
native Roblox scoreboard ("real scoreboard with number of followers").

### Networking contract (defined in `Net.lua`)

Server→client and client→server events are registered by name in one place so the contract is
greppable. MVP events: `FollowerChanged`, `RequestPhotoCapture`, `PhotoResult`, `RequestTravel`,
`TravelComplete`, `StartMinigame`, `MinigameInput`, `MinigameResult`, `InviteFriend`,
`UnlockNpc`.

### Place / travel model (MVP)

True cross-`.rbxl` `TeleportService` open worlds are deferred to Phase 2. In the MVP, **Home**,
**Airport**, and **Beach** are three zones in the *same* place; "travel" repositions the player
(with a fade) and runs the airport minigame in between. This keeps the loop fully testable in one
Studio play session before introducing multi-place complexity.

---

## Phase 0 — Scaffolding & toolchain — ✅ COMPLETE (2026-06-01)

Goal: a buildable, Studio-syncable empty project committed to git.

1. Add `~/.rokit/bin` to PATH (or `rokit install`); confirm `rojo`, `wally` resolve.
   → **Verify:** `rojo --version` and `wally --version` succeed. ✅ Rojo 7.5.1, wally 0.3.2.
2. `wally init`; add ProfileStore; `wally install`.
   → **Verify:** dependency installed, no errors. ✅ See correction below.
3. Write `default.project.json` mapping `src/shared|server|client` to the services above.
   → **Verify:** `rojo build -o build.rbxl` succeeds and produces a non-empty file. ✅ 27 KB; built `.rbxlx` confirmed correct service placement (Server→ServerScriptService, Client→StarterPlayerScripts, Shared→ReplicatedStorage, ServerPackages→ServerScriptService).
4. Create `src/{shared,server,client}` with bootstrappers that print a boot line.
   → **Verify:** bootstrapper runs at runtime. ✅ See verification-method note below.
5. Commit on a feature branch.
   → **Verify:** `git status` clean except intended files; `.gitignore` excludes wally outputs, `build.rbxl`, `*.rbxl.lock`. ✅ Branch `phase-0-scaffolding`.

**What was built:** `default.project.json`, `wally.toml` + `wally.lock`, `src/shared/Bootstrap.lua`
(shared Init-then-Start loader), `src/server/init.server.lua`, `src/client/init.client.lua`,
updated `.gitignore`.

**Corrections discovered during execution (plan premises that were wrong):**
- **ProfileStore is not published to Wally by loleris** under an obvious name; only unofficial
  community re-uploads exist. The official package is **`lm-loleris/profilestore`** (server realm,
  pinned `1.0.3`). Because it is a *server-realm* package it lives under `[server-dependencies]`
  and installs to **`ServerPackages/`**, not `Packages/`. No `Packages/` (shared realm) dir exists
  yet — the `ReplicatedStorage/Packages` mapping is therefore **deferred to Phase 1** (added when
  the first shared dependency appears), to avoid mapping a non-existent path.
- **`wally.lock` is committed** (with a `!wally.lock` negation in `.gitignore`, since the repo's
  existing `*.lock` rule would otherwise ignore it) for reproducible installs.

**Verification method note:** Rojo only *packages* Luau — it does not compile it, so a green build
does not prove the scripts run. The bootstrapper was verified at runtime via the Studio MCP
(`execute_luau`): loading the real `Bootstrap` source proved `require` succeeds, the nil-container
path (Phase 0 reality) runs clean, and ordering across modules is `A-init; B-init; A-start; B-start`
— i.e. **all `:Init()` complete before any `:Start()`**, the core contract. The entry scripts are
trivial `WaitForChild` + `Bootstrap.run` + `print` wrappers. (Live Rojo-plugin Play-test was not
scripted because connecting the plugin requires a manual click in Studio; the MCP runtime check is
the automated equivalent.)

---

## Phase 1 — MVP vertical slice

Definition of done: a player spawns at Home, travels (Airport minigame → Beach), takes a photo
(solo or co-op) to gain followers, unlocks + trains with the Personal Trainer NPC for followers,
invites a friend for a bonus, and **all of it persists across rejoins**.

### 1.1 Data persistence
- **Build:** `DataService` wraps ProfileStore; loads profile on join, releases on leave, provides `GetProfile(player)`; defines the schema above with reconciliation for new keys.
  - **Verify:** Join, mutate a field via command bar, rejoin → value persists. Two sessions don't double-load (session lock holds).

### 1.2 Follower economy + scoreboard
- **Build:** `FollowerService.Award/Deduct(player, amount, reason)`, clamps ≥ 0, fires `FollowerChanged`, mirrors to `leaderstats.Followers`. `HudController` shows live count.
  - **Verify:** Awarding 100 updates HUD and native leaderboard instantly; value survives rejoin.

### 1.3 Home lobby
- **Build:** Generate a simple Home interior as ProceduralModels (`generate_procedural_model`), falling back to Creator Store; set as spawn; place ProximityPrompts for Phone, Computer, Cab (Cab opens the travel picker).
  - **Verify:** Player spawns in Home; prompts appear and fire their client events.

### 1.4 Travel: Airport minigame → Beach
- **Build:** `TravelController` destination picker (only unlocked places selectable). `PlaceService.RequestTravel` validates unlock + cost, fades, runs the Airport minigame (simple "reach the gate before time" or tap-sequence), then moves player to Beach and awards arrival followers. Returning Home applies the carbon-footprint follower loss from `Config`.
  - **Verify:** Travel Home→Beach succeeds only for unlocked place; minigame completes; arrival awards followers; return-home deducts the configured amount; `Stats.TripsTaken` increments and persists.

### 1.5 Photo system (solo + co-op)
- **Build:** `PhotoController` enters photo mode (camera + shutter UI); `RequestPhotoCapture` sent to server. `PhotoService` validates and awards base followers; if ≥2 players are within range + facing, awards the co-op bonus to all participants. Per-cooldown to prevent spam.
  - **Verify:** Solo photo awards base; two players nearby each get the co-op bonus; cooldown blocks spam; `Stats.PhotosTaken` persists. (Server-authoritative — client cannot self-award.)

### 1.6 Personal Trainer NPC + minigame
- **Build:** `NpcService` tracks `UnlockedNpcs`; trainer unlocks at the `Config` follower threshold and spawns in Home. Interacting starts a `MinigameService` session — one educational-question/quick-time trainer minigame; correct answers pay followers via `FollowerService`.
  - **Verify:** Trainer appears only after threshold; minigame runs server-validated; reward credited and persisted; unlock state survives rejoin.

### 1.7 Co-op: friend invite bonus
- **Build:** `InviteFriend` triggers the Roblox friend-invite prompt; when an invited friend joins the same server (detected via `TeleportData`/join source), both get the configured follower bonus once per friend. `Stats.FriendsInvited` tracks it.
  - **Verify:** Simulated invited-join grants the bonus to both, is not repeatable for the same friend, and persists.

### 1.8 Offline follower decay (minimal)
- **Build:** On join, `FollowerService` applies a small decay based on `os.time() - LastSeen` (capped), reflecting "lose followers from not playing". Tunable in `Config`, off by default until balanced.
  - **Verify:** With decay enabled, a backdated `LastSeen` reduces followers within the configured cap on join.

**MVP gate:** Phase 1 reviewed (3 code-reviewer passes: simplicity/DRY, correctness/exploits, conventions) and playable end-to-end in one server with two test clients.

### Post-Phase-1: professional-workflow hardening — ✅ (2026-06-02)

Adapted the workflow toward Roblox-studio practice for long-term maintainability (the architecture
was kept as-is — a thin bootstrapper over a framework is a deliberate, valid choice; no Knit/
Flamework/typed-networking added):

- **Automated tests** — headless **Lune** harness (`tests/`, `make test`, in `make ci` + GitHub
  Actions). Phase 1 pure logic extracted to `src/shared/Logic/` (`Followers`, `Decay`, `Referral`)
  and unit-tested (functional core / imperative shell).
- **CD** — `cd.yml` publishes to a **staging** Open Cloud universe on merge to `main` via
  `rbxcloud` (inert until the owner sets `ROBLOX_API_KEY` + `ROBLOX_UNIVERSE_ID`/`PLACE_ID`).
- **Observability** — `Util/Log` (structured logs) + `Util/Analytics` (AnalyticsService wrapper);
  the follower economy and NPC unlocks emit funnel events.
- **Scenery as code** — while the GenAI `generate_procedural_model` backend was unavailable,
  scenery moved to code-built primitive models (`SceneryService`), driven by `assets/manifest.json`;
  AI models can replace them later without changing placement.
- **Docs** — `CONTRIBUTING.md`, `TESTING.md`, and ADRs under `docs/adr/`.

---

## Phase 2 — Breadth: places & real travel

- Convert destinations to **separate places** with `TeleportService` (public open-world servers, no chat) + reserved co-op sessions for parties.
- Implement the full place list incrementally with **unlock-by-follower-count** gating: Beachside Riviera, Paradise Island, Infinite Pool High-Rise, Music Festival, Nightclub High-Rise, Mediterranean Cliff, Alpine Holiday, Formula Race Paddock, Euro City.
- Per-place follower behavior driven by reputation (good rep → faster gain).
- Computer flight-booking UI; Cab→Airport flow; per-place ambient follower trickle by time spent.
- **Verify per place:** locked until threshold; teleport in/out works; arrival/behavior rewards fire; persists.

## Phase 3 — NPC roster & minigames

- Add remaining collectible NPCs: Butler, Hairdresser, PR Agent, Rich Friend (M), Rich Friend (F).
- Each unlocks a distinct minigame; build a small reusable minigame framework (session, timer, scoring, payout) so new minigames are data-driven.
- Companion system: bring an NPC on trips; **party mode** when friends + NPCs travel together (funny interactions).
- **Verify:** each NPC unlock gated; each minigame server-validated and rewarding; companion travels and persists.

## Phase 4 — Systems depth

- **Phone services:** order food/services (timed buffs, small follower/reputation effects).
- **Computer feed & news:** player feed, news websites, decisions that nudge reputation.
- **Events / moral dilemmas:** server-driven prompts adjusting `Reputation`; reputation modulates follower swings.
- Educational-question bank for minigames (data-driven, expandable).
- **Verify:** reputation changes flow into follower behavior; events fire and persist outcomes.

## Phase 5 — Monetization & VIP

- Robux developer products / game passes: **VIP** (exclusive places, aura buffers), **philanthropy** purchase that raises followers.
- VIP gating in `PlaceService`; aura/buff system.
- **Verify:** purchases grant entitlements server-side; entitlements persist; receipts handled idempotently (`ProcessReceipt`).

## Phase 6 — Polish, balance, hardening

- Anti-exploit pass (all rewards server-authoritative; rate limits; remote validation).
- Economy balancing of `Config` thresholds/rewards/decay.
- Analytics events for the funnel (travel, photos, unlocks, purchases).
- Performance: streaming for open-world places, asset budgets.
- Onboarding/tutorial for the core loop.

---

## Cross-cutting conventions

- Every reward/penalty routes through `FollowerService` / `ReputationService` (single writers).
- Every new remote is registered in `Net.lua` and validated server-side.
- New tunable numbers live in `src/shared/Config` — never hard-coded in services.
- One phase-step per commit, each independently verifiable per its Verify line.
- **Functional core / imperative shell:** pure domain logic goes in `src/shared/Logic/`
  (no Roblox globals) and is unit-tested under Lune; services/controllers stay thin shells.
- **Verify-as-test:** when a plan **Verify** line covers pure logic, add a Lune spec for it; reserve
  manual Studio checks for what genuinely needs a running place (UI, remotes, CaptureService).
- Player-affecting events emit through the observability seam (`Util/Log`, `Util/Analytics`).
- `make ci` (fmt-check → lint → typecheck → **test** → build) is the gate; GitHub Actions runs it on
  every PR, and merges to `main` publish to a staging universe via Open Cloud (`cd.yml`).

## Open questions / assumptions to revisit

- **Multi-place vs single-place** is a real fork at Phase 2 — confirm reserved-server party model before building it.
- **Educational-question theme/source** (Phase 3/4) — needs a content decision (topics, age range).
- **Decay aggressiveness** (1.8) — left off-by-default until playtested; tune with real data.
- **Asset pipeline** — superseded by [003_binary_asset_management.md](003_binary_asset_management.md). Current state: stylized scenery is **code-built primitives** (`SceneryService`, no upload), and real art is a **GLB/OBJ → Open Cloud → asset-id → runtime-load** pipeline (`MeshSceneryService`, sources in Git LFS; OBJ is converted to GLB at upload). The GenAI `generate_procedural_model` path is unused while its backend is unavailable. No binary instances are committed to the `.rbxl`.
