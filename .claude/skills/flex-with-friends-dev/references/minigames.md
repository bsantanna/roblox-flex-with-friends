# NPC minigames

Read this when building, extending, or debugging an **NPC minigame** — a game a player starts by
talking to an NPC (the Personal Trainer's "Simon Says" is the first). There is a generic framework
so every minigame shares one pre-game flow and you only write the game-specific part. Don't re-derive
it; follow the recipe.

- [The shape of it](#the-shape-of-it) — what the framework owns vs. what a plugin owns
- [The lifecycle](#the-lifecycle) — the pre-game flow, step by step
- [File layout](#file-layout)
- [The plugin contract](#the-plugin-contract)
- [Session object](#session-object)
- [Config and Net conventions](#config-and-net-conventions)
- [Recipe: add an NPC minigame](#recipe-add-an-npc-minigame)
- [Verifying a minigame](#verifying-a-minigame)

## The shape of it

`MinigameService` (`src/server/services/MinigameService.lua`) is a **generic orchestrator**. It owns
the shared lifecycle every NPC minigame runs — walk the NPC out, make the player step onto a ready
mark, explain the rules and wait for a Start confirmation, then hand off to the game, then clean up.
It does **not** know any game's rules.

Each **minigame is a plugin** — a module under `minigame/games/` declaring which NPC hosts it and
implementing `begin`/`abort`. The plugin owns its gameplay loop, its own gameplay remotes, and its
own client UI controller. Adding a minigame is: drop a plugin file, add a client controller, add a
few Config values. The whole pre-game flow comes for free.

This split exists because the pre-game (walk → mark → rules → confirm) is identical for every game,
while the *gameplay* (arrows, rhythm, timing — whatever) is inherently game-specific. Keep that line
crisp: generic pre-game in the framework, game-specific play in the plugin.

## The lifecycle

`MinigameService:Request(player, npcId, model)` is the single entry point (DialogService calls it
after the NPC's "play" dialog choice). It runs, in its own thread:

```
1. validate          profile exists · no active session (one game at a time) · unlock gate
2. walk              NpcActor walks the NPC from its post to its ArenaPosition, facing the approach
3. ready-zone        ReadyZone shows a green disc in front of the NPC; fire MinigameAwaitReady
                     (client hint). Poll the player's root against the disc. ReadyTimeoutSeconds
                     to arrive, or the game aborts and the NPC walks home.
4. instructions      dismiss the disc · NPC speaks the rules in a speech bubble (all see) · fire
                     MinigameInstructions(text) so the player gets a Start button. ConfirmTimeoutSeconds
                     to confirm (MinigameConfirmStart), or it aborts.
5. play              game:begin(session) — the plugin runs its rounds, awards followers, fires its
                     own UI remotes
6. cleanup           the plugin calls session.finish() on game over (or a disconnect/timeout fires
                     game:abort) → the NPC walks home, the session slot clears
```

Every step re-checks `session.alive`, which the framework flips to `false` the instant a session
ends, so a disconnect mid-flow stops the thread. Only **one** game runs at a time — the NPC is a
single shared model that physically walks to the arena.

## File layout

```
src/server/services/MinigameService.lua        the generic orchestrator + plugin registry
src/server/services/minigame/                   a plain Folder — Bootstrap does NOT boot it
    NpcActor.lua                                 walk an NPC across a flat floor + play timed poses
    ReadyZone.lua                                the green floor disc + :contains() entry test
    games/<Name>.lua                             one minigame plugin (auto-registered by NpcId)
src/client/controllers/MinigameController.lua   generic pre-game shell (ready hint, instructions
                                                 panel + Start button, unlock toast)
src/client/controllers/<Name>Controller.lua     the game-specific gameplay UI
```

Bootstrap only boots **direct** `ModuleScript` children of `services/`, so `MinigameService` is a
booted service but everything under the `minigame/` Folder is not — `MinigameService` requires
`NpcActor`/`ReadyZone` statically and **dynamically requires** each `minigame/games/*` plugin, using
the `(require :: any)(child)` idiom (see the analyze gotcha in SKILL.md). It registers each plugin by
its `NpcId` and drives the plugins' own `Init`/`Start` itself (Bootstrap can't see them).

Client controllers *are* all booted (they're direct children of `controllers/`), so the per-game UI
controller needs no registration.

## The plugin contract

A plugin is a module shaped like a service, plus two framework hooks:

```lua
local MyGame = {}
MyGame.Id = "MyGame"          -- unique id
MyGame.NpcId = "SomeNpc"      -- which Config.Npc entry hosts it (unlock gate + tunables live there)

function MyGame:Init() end    -- cache this game's OWN gameplay remotes (Net.Event(...))
function MyGame:Start() end    -- connect this game's OWN input handlers

-- Framework hook: start play. Use session.actor to pose the NPC, NpcActor.posePlayer for the player,
-- FollowerService:Award for rewards, and the plugin's own remotes for UI. Store private state on
-- session.state. Call session.finish() when the game is over.
function MyGame:begin(session) end

-- Framework hook: stop play (player left / timed out). The framework already set session.alive=false
-- before calling this, so spawned loops bail on their own; just clear any plugin-local pointer here.
function MyGame:abort(session) end

return MyGame
```

Input arrives on a player-keyed remote, so a plugin typically keeps a module-local `current` session
pointer (set in `begin`, cleared in `abort`/on game over) to find the running game from a remote
handler. That is safe because only one game runs at a time and only this plugin owns its remotes.

Pure game math (sequence generation, grading, reward curves) belongs in `src/shared/Logic/` so it's
Lune-testable with no Roblox globals — `Shared.Logic.SimonSays` is the model to copy.

## Session object

The framework builds and owns the session; the plugin reads/writes the fields it needs. Type it
loosely in the plugin (a structural subset is fine):

| Field | Meaning |
|---|---|
| `player` | the playing player |
| `npcId`, `model` | the NPC id and its model (model is nil-safe: a fallback body just won't walk/pose) |
| `actor` | `NpcActor` bound to the model — `actor:poseNpc(animId, secs)`, walks |
| `game` | the plugin |
| `homePosition`, `homeYaw` | where the NPC walks back to on cleanup |
| `phase` | `"pregame"` / `"instructions"` / `"playing"` |
| `confirmed` | set true when the player presses Start |
| `alive` | framework-owned; `false` means the session has ended — loops check this to stop |
| `state` | **plugin-private** gameplay state (rounds, deadlines, …) |
| `finish()` | the plugin calls this on normal game over → NPC walks home, slot clears |

## Config and Net conventions

Per the golden rules, all tunables live in `Config` and all remotes are declared in `Net.lua`.

- **`Config.Minigame`** — cross-game pre-game tunables: `ReadyTimeoutSeconds`, `ConfirmTimeoutSeconds`,
  and `ReadyZone = { Radius, Offset, Height, Color }`. The disc center is computed generically as
  `ArenaPosition + facing * Offset`, where `facing = CFrame.Angles(0, rad(SpawnYaw), 0).LookVector` —
  i.e. `Offset` studs *in front of* the NPC, toward where the player approaches.
- **`Config.Npc[npcId]`** — per-NPC: `SpawnPosition`, `SpawnYaw` (also the arena facing),
  `ArenaPosition`, `MoveSeconds`, `WalkAnimation`, `Instructions` (the rules string), `Dialog`, and a
  game-specific subtable (e.g. `SimonSays = { … }`). `MoveSeconds`/`WalkAnimation` describe how the
  NPC moves, so they live at NPC level, not inside the game subtable.
- **Generic remotes** (already registered, reused by every game): `MinigameAwaitReady`,
  `MinigameInstructions`, `MinigameConfirmStart`, `MinigameAborted`.
- **Game-specific remotes** are owned by the plugin and its client controller — declare them in
  `Net.lua` too, namespaced to the game (the Simon Says plugin owns the `Trainer*` set). Validate
  every client→server payload server-side.

## Recipe: add an NPC minigame

1. **Pure logic first** (if any): put sequence/grading/reward math in `src/shared/Logic/<Name>.lua`
   with no Roblox globals, and a `tests/<Name>.spec.luau` Lune test.
2. **Config**: add the NPC under `Config.Npc` (with `SpawnPosition`, `SpawnYaw`, `ArenaPosition`,
   `MoveSeconds`, `WalkAnimation`, `Instructions`, `Dialog`, and your game subtable). Reuse the shared
   `Config.Minigame` pre-game values unless this game truly needs different ones.
3. **Net**: declare the game's gameplay remotes in `Net.lua`, namespaced to the game, with a comment
   on each payload's direction and shape.
4. **Plugin**: create `src/server/services/minigame/games/<Name>.lua` with the [contract](#the-plugin-contract)
   above — `Id`, `NpcId`, `Init`/`Start` (its remotes), `begin`/`abort`. Pose via `session.actor` and
   `NpcActor.posePlayer`; award via `FollowerService:Award`; end via `session.finish()`. It's
   auto-registered by `NpcId` — no list to edit.
5. **Client UI**: create `src/client/controllers/<Name>Controller.lua` for the gameplay UI, listening
   to the game's remotes. The generic pre-game shell (ready hint, instructions panel, Start) is
   already handled by `MinigameController` — don't duplicate it.
6. **Trigger**: from the NPC's dialog (DialogService) call `MinigameService:Request(player, npcId, model)`
   on the choice that starts the game. The unlock gate inside `Request` is defense in depth.
7. **Verify**: `make ci` green, then Studio (see below).

## Verifying a minigame

Two kinds of correctness, two kinds of check (this mirrors SKILL.md's split):

- **Logic** — the framework boots and registers the plugin, remotes exist, rounds/rewards behave.
  Confirm modules load and remotes are present with `execute_luau` (require the service, inspect
  `ReplicatedStorage.Remotes`). Pure logic is covered by the Lune test.
- **Spatial** — the **green ready-zone is geometry, so you must look at it.** The risky parts are the
  disc's orientation (a Cylinder is built `Size = (height, 2r, 2r)` then rotated `CFrame.Angles(0,0,90°)`
  to lie flat) and the offset *direction* (in front of the NPC, not behind/inside it). Capture it.

Studio gotchas specific to this flow:

- **ProfileStore doesn't load in a Studio session without API access / a published place**, so
  `MinigameService:Request`'s profile gate returns early and the full flow won't run end-to-end
  there. To verify the pre-game *spatially*, drive the real modules directly instead: `require` the
  live `NpcActor`/`ReadyZone`, build an actor for the NPC model, `actor:walkTo(ArenaPosition, SpawnYaw)`,
  compute the center and `ReadyZone.create(...)`. That exercises the exact placement code without the
  gate. (See `references/lifecycle.md` for the general execute_luau-returns-its-evidence pattern.)
- The gym floors are **enclosed**, so a top-down camera hits the ceiling. Frame from **inside** the
  room: an eye-level shot from the player's approach (looking at the NPC) shows the disc-is-flat,
  disc-is-in-front, size, and the player↔NPC spacing all at once.
- To see the instruction step, fire `MinigameInstructions` to the player and create the NPC speech
  bubble (`SpeechBubble.create(root)`), then capture — the bubble (all see) and the client Start panel
  should both show the rules.
