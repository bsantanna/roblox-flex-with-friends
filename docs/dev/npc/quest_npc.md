# Building an NPC quest — patterns & reference implementation

How to build a quest given by an NPC in Flex-with-Friends, distilled from the first one,
**"The Pilot's Forgotten Packages"** (Quest 002). Read this before adding a new quest; it captures the
conventions, the reusable pieces, and the mistakes already paid for.

The Pilot quest is the canonical reference. Its files:

```
src/shared/Config/Quest.lua             all quest tunables (one quest per Config table today)
src/server/services/QuestService.lua    server state machine + reward + persistence (single writer)
src/client/controllers/QuestController.lua   player HUD, choice buttons, objective beacons
src/client/controllers/CutsceneController.lua  Scriptable-camera cinematics (reusable across quests)
src/shared/Util/NpcModel.lua            shared NPC build (the quest-giver reuses the roster's spawn)
```

Supporting edits the quest needed: `Config/init.lua`, `Net.lua`, `Types.lua`, `Config/Player.lua`,
`Config/Ui.lua`, `TrophyService.lua`, `PlaceService.lua`, `PhoneMenuController.lua`,
`TravelController.lua`. The design doc that drove it: `docs/dev/quests/002_pilot_missing_fligt.md`.

---

## 1. The shape of a quest

A quest is a **server-authoritative, per-player state machine** plus the client UI/world feedback that
renders it. It is *not* a minigame — don't extend `MinigameService` (it uses a single global slot
because one NPC body walks to one arena). A quest mirrors that service's lifecycle **pattern** while
keeping its own per-player sessions so many players can quest at once.

```
idle ──talk──▶ offer ──accept──▶ accepted ──(travel)──▶ collecting ──goal met──▶ returning
                 │                                            │
                 └── decline ──▶ idle                  timer expires ──▶ failed ──▶ idle (retryable)
   returning ──talk──▶ complete  (reward + one-time trophy, persisted once)
```

Adapt the middle (`collecting`/`returning`) to your quest's objective; the offer/accept/decline/replay
and complete/fail edges are the reusable skeleton.

### The golden rules, applied to quests

1. **Server-authoritative.** Every state change (accept, travel, collect, deliver, fail) happens on
   the server and validates its inputs. The client *requests*; it never decides progress or rewards.
2. **Single writer.** The quest service is the only writer of its persisted field
   (`Profile.Data.CompletedQuests`). It *asks* `FollowerService:Award` / `TrophyService:AwardTrophy`
   for rewards — it never touches `Followers`/`Trophies` directly.
3. **Tunables in `Config`.** Positions, timers, rewards, dialogue, beacon visuals, camera keyframes,
   pose emotes — all live in `Config.Quest`. No magic numbers in the service.
4. **Every remote in `Net.lua`**, validated server-side (type-check `unknown` args, verify the player
   owns a session and the phase allows the action, verify spatial proximity).
5. **Auto-wired.** A new `*Service.lua` under `src/server/services/` and `*Controller.lua` under
   `src/client/controllers/` are booted by `Bootstrap` (Init-all then Start-all) — no registration.

---

## 2. Reuse, don't reinvent

| Need | Reuse |
|---|---|
| Quest-giver NPC (dressed, anchored, floor-aligned, "Talk" prompt) | `Util/NpcModel.build(spec)` — returns `{ root, model, prompt }`; you wire `prompt.Triggered` |
| Dialogue all nearby players see | `Util/SpeechBubble.create(root)` → `:show()` / `:setText()` / `:hide()` (one-shot; recreate per beat) |
| NPC poses (worried/happy/…) | `NpcActor.pose(animator, animId, seconds)` — static; get the animator from the model's Humanoid |
| Followers / one-time trophy | `FollowerService:Award(player, n, reason)`, `TrophyService:AwardTrophy(player, npcId)` (+ a `TROPHY_DEFS` entry, mirrored in `PhoneMenuController`) |
| Persistence (auto-migrating) | add a field to `Types.ProfileData` + `Config/Player.lua` template — ProfileStore `Reconcile()` backfills, no migration, no DataStore bump |
| Fast travel without the cab penalty | `PlaceService:TravelTo(player, zone, position?)` — same teleport/`setLocation`, skips the carbon-footprint loss |
| Screen fade on cuts | `TravelController:TweenFade(t)` (0 = black, 1 = clear) |
| Phone screen for the quest | a gated item in `Config.UI.Phone.Items` + a modal in `PhoneMenuController` |

If the giver isn't a minigame host, **keep it out of `Config.Npc`** — that type requires arena/minigame
fields and `DialogService` auto-spawns every entry and routes its dialog to `MinigameService`. Spawn the
giver yourself in your quest service via `NpcModel.build`, and use **dedicated quest remotes** rather
than `DialogLine`/`DialogChoose` (those run through `DialogService`'s single *global* dialog session).

---

## 3. Reference skeleton (server)

`QuestService.lua`, trimmed to the reusable bones:

```lua
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local NpcModel = require(ReplicatedStorage.Shared.Util.NpcModel)
local SpeechBubble = require(ReplicatedStorage.Shared.Util.SpeechBubble)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local TrophyService = require(script.Parent.TrophyService)
local PlaceService = require(script.Parent.PlaceService)
local NpcActor = require(script.Parent.minigame.NpcActor)

local QuestService = {}
local Q = Config.Quest

type Session = { player: Player, phase: string, alive: boolean, deadline: number, count: number, ... }
local sessions: { [Player]: Session } = {}     -- PER-PLAYER, not a single global slot
local giverModel, giverRoot                     -- set when the NPC spawns

local questState, questAccept, questDecline, ... -- RemoteEvents, grabbed in :Init()

-- The one HUD/state sync. `phase` is a plain string so transient phases (idle/failed/complete/replay)
-- can be reported too. `deadline` is GetServerTimeNow()-based so the client can render the countdown
-- without trusting its own clock; the server's os.clock() deadline is the sole authority on expiry.
local function fireState(player, phase, count, deadline)
    questState:FireClient(player, Q.Id, phase, count, TOTAL, deadline)
end

local function clearSession(player)
    local s = sessions[player]; if s then s.alive = false end
    sessions[player] = nil
end

-- One-time completion: single writer of CompletedQuests; rewards granted immediately (a mid-cutscene
-- disconnect can't lose them), with a guard against double-deliver.
local function deliver(player)
    clearSession(player)
    local profile = DataService:GetProfile(player); if not profile then return end
    if profile.Data.CompletedQuests[Q.Id] then return end
    profile.Data.CompletedQuests[Q.Id] = true
    cutscenePlay:FireClient(player, "Ending")          -- presentation only
    FollowerService:Award(player, Q.Reward, "quest-...")
    TrophyService:AwardTrophy(player, Q.TrophyNpcId)
    fireState(player, "complete", TOTAL)
end

local function onTalk(player)
    local profile = DataService:GetProfile(player); if not profile then return end
    if profile.Data.CompletedQuests[Q.Id] then          -- one-time: warm replay, no reward
        task.spawn(speak, { Q.Lines.Replay }); fireState(player, "replay", 0); return
    end
    local s = sessions[player]
    if s then
        if s.phase == "returning" then deliver(player)
        elseif s.phase ~= "offer" then task.spawn(speak, { Q.Lines.Nudge }); fireState(player, s.phase, s.count) end
        return                                            -- offer in progress -> ignore re-trigger
    end
    sessions[player] = { player = player, phase = "offer", alive = true, ... }  -- start the offer
    cutscenePlay:FireClient(player, "Intro")
    task.spawn(function() ... speak(Q.Lines.Intro); fireState(player, "offer", 0) end)
end

-- Validate EVERY client request: type, session ownership, phase, and (for spatial actions) real proximity.
local function onCollect(player, index)
    if type(index) ~= "number" then return end
    local s = sessions[player]; if not s or s.phase ~= "collecting" then return end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not (root and root:IsA("BasePart")) then return end
    local target = Q.PackagePositions[index]
    local flat = Vector3.new(root.Position.X, target.Y, root.Position.Z)
    if (flat - target).Magnitude > Q.CollectRadius then return end   -- rejects spoofed far collects
    ...
end

function QuestService:Init()  -- grab every remote here (Net.Event), wiring only
    questState = Net.Event("QuestState"); questAccept = Net.Event("QuestAccept"); ...
end

function QuestService:Start()
    task.spawn(function()
        local r = NpcModel.build({ npcId = Q.Pilot.NpcId, zone = Q.Pilot.Zone,
            avatarUserId = Q.Pilot.AvatarUserId, spawnPosition = Q.Pilot.SpawnPosition,
            spawnYaw = Q.Pilot.SpawnYaw, outfit = Q.Pilot.Outfit, promptText = "Talk", promptDistance = 12 })
        giverModel, giverRoot = r.model, r.root
        if r.prompt then r.prompt.Triggered:Connect(onTalk) end
    end)
    questAccept.OnServerEvent:Connect(onAccept)          -- connect handlers, start loops
    requestCollect.OnServerEvent:Connect(onCollect)
    Players.PlayerRemoving:Connect(clearSession)         -- ALWAYS clean up on disconnect
end

return QuestService
```

### Timers: the server-authoritative pattern

Mirror `MinigameService`: an `alive` flag + an `os.clock()` deadline polled in a `task.spawn` loop.

```lua
local function startCollecting(s)
    s.phase = "collecting"
    s.deadline = os.clock() + Q.TimeLimitSeconds            -- server authority
    task.spawn(function()
        while s.alive and s.phase == "collecting" and os.clock() < s.deadline do task.wait(0.1) end
        if s.alive and s.phase == "collecting" then failQuest(s.player) end   -- timed out
    end)
    fireState(s.player, "collecting", s.count, Workspace:GetServerTimeNow() + Q.TimeLimitSeconds)
end
```

Send the client a `GetServerTimeNow()`-based **absolute end time** (synced clock) and let it render the
countdown locally. Never send "seconds left" and let the client decrement — and never trust the client's
clock for expiry. Re-check `s.alive` and `s.phase` after **every** yield (a disconnect during a
`task.wait` ends the session out from under you).

---

## 4. Reference skeleton (client)

Three controllers, each auto-wired:

- **`QuestController`** owns everything player-only: the Accept/Decline buttons (shown on
  `QuestState` phase `"offer"`), the HUD (countdown + objective counter), and the **objective beacons**.
  Beacons are **client-side and personal** (GTA-style — only the questing player sees their objectives,
  which also sidesteps concurrent-quester collisions). Build them under `Workspace` (client-only
  instances don't replicate). Collection is server-validated: each beacon carries a `ProximityPrompt`
  that fires `RequestCollectPackage(index)`; remove the beacon optimistically (the prompt only appears
  within `CollectRadius`, the same radius the server checks, so a legit collect can't be rejected).
  Track collected indices locally so re-entering the area doesn't respawn collected beacons.

- **`CutsceneController`** is **reusable across quests** and is the *only* code that touches
  `workspace.CurrentCamera`. On `CutscenePlay(sequenceId)` it sets `CameraType = Scriptable`, tweens
  through `Config.Quest.Cutscene[sequenceId]` keyframes (eye/target **offsets relative to the NPC's
  post**, read off the replicated giver model), then restores `Custom` and fires `CutsceneDone`. A quick
  `TravelController:TweenFade` hides the hard cut in/out. Keep keyframes in `Config` so framing is tuned
  without editing the controller.

- **`PhoneMenuController`** gets a gated quest item: add `{ ..., action = "Quest" }` to
  `Config.UI.Phone.Items`, gate it (`isItemHidden` → hidden unless the quest is active), and add a modal
  (mirror `showSocialModal`) with the timer/objective readout and the travel buttons firing
  `RequestQuestTravel`. Mirror `QuestState` into a module-level flag for the gating.

The client subscribes to **one** `QuestState` event and drives all of the above from its `phase`. Keep
the remote surface small: one state sync down, a few intent events up.

```
QuestState           s→c  (questId, phase, collected, total, deadline?)   -- the one HUD/state sync
QuestAccept/Decline  c→s  ()
RequestQuestTravel   c→s  (destination)        -- validated vs quest state; zero-cost travel
RequestCollect…      c→s  (index)              -- server validates real proximity
CutscenePlay         s→c  (sequenceId)
CutsceneDone         c→s  ()
```

---

## 5. Spatial verification — non-negotiable

A quest places things in the 3D world (the giver, beacons, fast-travel drop-offs, camera framing).
**Code cannot tell you if they're right** — a CFrame type-checks while clipping a wall. Verify by
*looking*, in a Studio Play session (the world geometry is **code-generated on Play** by
WorldService/TerminalService — it doesn't exist in Edit mode).

What this caught on the Pilot quest (every value was a guess that was *wrong*):

- The giver's `(0,700)` post **clipped the terminal bar**; the hall centre is furnished (bar + sushi +
  seating), NPCs line the walls at `x=±80`. Open floor for a central NPC is **by the gates ~`z690`** —
  with the gate + runway as a free cutscene backdrop (see the `Quest.Pilot` comments in `Config/Quest.lua`).
- Two of four package positions sat **under Forest trees**; the Home grid's internal **road crossings
  `(±72, ±72)`** are open, walkable, one per quadrant, ~100 studs from spawn (reachable in the timer).

The loop: drop bright marker parts at the exact `Config` coordinates via `execute_luau` in a Play
session → `screen_capture` an angled bird's-eye (layout) + an eye-level (scale/clipping) + the
**cutscene keyframe itself** (does the camera frame the NPC?) → `raycast`/`GetPartBoundsInBox` to
confirm the floor material and that nothing occupies the spot at standing height → adjust the `Config`
tunable, repeat. Take at least a top-down *and* an eye-level; one angle hides float/clip.

**Gotcha:** an already-open `build.rbxl` Studio session may be a *stale* build that predates your code.
Before runtime-verifying, confirm your code is present (e.g. check the `Remotes` folder for your events,
or `require(Config).Quest`); if stale, reload the place or `make serve` + connect Rojo, then Play.

---

## 6. Recipe — adding a new quest

1. **Write the design doc** under `docs/dev/quests/` first (vision, locked decisions, reuse map, build
   phases each with a checkable *Verify*). The Pilot's doc is the template.
2. **`Config/Quest.lua`** (or a sibling per quest): giver post/outfit, timer, objective positions,
   reward, trophy id, dialogue, pose emotes, beacon visuals, cutscene keyframes. Wire into `Config/init`.
3. **Persistence:** add your completion field to `Types.ProfileData` + `Config/Player.lua` template.
4. **`Net.lua`:** declare every quest remote.
5. **`QuestService`:** spawn the giver via `NpcModel.build`; run the per-player state machine; validate
   all inputs; be the single writer of completion; ask Follower/Trophy services for rewards.
6. **Client:** `QuestController` (HUD + choices + beacons) and reuse/extend `CutsceneController`; add the
   gated phone screen.
7. **Trophy:** add a `TROPHY_DEFS` entry server-side and mirror it in `PhoneMenuController`.
8. **Build one phase per commit**, branch off `main`, `make ci` (fmt-check, lint, analyze, build, tests)
   green before each commit.
9. **Studio spatial pass** at the end (or per phase for anything placed): verify the giver, beacons,
   drop-offs, and cutscene framing by looking — never sign off from the numbers.

---

## 7. Pitfalls checklist

- ☐ Per-player `sessions` map (not a single global slot) — the giver isn't a shared arena body.
- ☐ Re-check `session.alive` / `phase` after every yield; `clearSession` on `PlayerRemoving`.
- ☐ Validate every remote: type, session ownership, phase, **server-side proximity** for world actions.
- ☐ One-time reward is guarded against double-deliver and granted **before/independently of** the
  presentation cutscene (a disconnect mid-cutscene must not lose the reward).
- ☐ Timer authority is server `os.clock()`; client renders from a `GetServerTimeNow()` end time.
- ☐ Quest giver lives **outside** `Config.Npc`; dialogue uses **dedicated remotes**, not the global
  `DialogService` session.
- ☐ Beacons are client-side/personal under `Workspace`; track collected locally for re-entry.
- ☐ `CutsceneController` restores `CameraType = Custom` on **every** exit path. (Known gap to close:
  also restore if the player respawns mid-cutscene — currently only restored on normal completion.)
- ☐ New `ProfileData` field added to both the type and the template so `Reconcile()` backfills it.
- ☐ Spatial values Studio-verified; don't trust a stale `build.rbxl` session.
