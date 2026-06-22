# Quest 002 — "The Pilot's Forgotten Packages"

A cinematic, Zelda/GTA-style fetch quest given by a special airport NPC, the **Pilot**. This is the
game's **first quest** and the template for a reusable quest system. It is authored to this repo's
conventions — see `.claude/skills/flex-with-friends-dev` — **not** to the generic "QuestManager in
ReplicatedStorage / BindableEvents / DataStore" layout the first draft proposed. Where that draft
invented new infrastructure, this plan reuses what already exists.

> **Status:** design / not yet implemented. This document is the build plan; each phase below is one
> commit with a verifiable success criterion, branched off `main` (e.g. `quest-pilot-packages-A`).

---

## 1. Vision & tone (unchanged from the seed idea)

A **positive, uplifting rescue quest** about responsibility, punctuality, and helping others.

- Light, friendly dialogue — no villains, no real stress.
- The player is the hero by being **reliable and kind**.
- GTA-style open-world feel (phone fast-travel, glowing objective beacons, a countdown) but **safe,
  wholesome, and encouraging**. Failure is gentle: *"We'll get them next time — thanks for trying!"*
- Zelda-style **cinematic framing**: the camera takes over for the intro and the ending, panning to
  the Pilot while he speaks.
- Target audience: young players — bright colors, short encouraging lines, no pressure.

**Core loop (2-minute limit):**

1. Meet the stressed Pilot in the airport terminal → **cinematic intro** (camera pan + speech bubble).
2. Accept the quest.
3. Open the **phone** → fast-travel to the city.
4. Collect **4 glowing packages** (objective beacons) before the timer runs out.
5. Phone → fast-travel back to the airport.
6. Deliver to the Pilot → **cinematic ending** + reward.

### Locked design decisions

| Decision | Choice | Consequence |
|---|---|---|
| The "city" map | **Reuse the Home neighborhood** | No new zone/terrain/scenery to build. The existing 3×3 town (houses, roads, plaza) *is* the city. Packages are placed around it. |
| Reward | **Followers + a one-time Pilot trophy** | Uses `FollowerService:Award` and `TrophyService:AwardTrophy`. No new currency. (The dormant `Reputation` field stays unused — out of scope.) |
| Cinematics | **In v1** | A reusable client `CutsceneController` (Scriptable camera + tweens) is built up front, not deferred. |
| Repeatability | **One-time story quest** | Completion persists to the profile; the reward + trophy are granted once. Replays show a warm "thanks again" with no reward. |

---

## 2. What already exists (reuse, do not reinvent)

The first draft listed `QuestManager`, `PhoneController`, `WaypointManager`, `TimerService`,
`CutsceneController` as all-new modules. Most of that capability is already here:

| Need | Reuse this | Where |
|---|---|---|
| NPC standing in the world, dressed, with a "Talk" prompt | NPC spawn + outfit + `ProximityPrompt` build | `DialogService.lua` (`spawnNpc`/`applyOutfit`), `Config/Npc.lua` (`NpcOutfit`) |
| Dialog text visible to **all** nearby players | Server-side `SpeechBubble` (BillboardGui) | `src/shared/Util/SpeechBubble.lua` |
| On-screen choice buttons (Accept / Decline) | `DialogController`'s button row | `src/client/controllers/DialogController.lua` |
| NPC poses/animations (worried, happy) | `NpcActor.pose(animator, animId, seconds)` | `src/server/services/minigame/NpcActor.lua` |
| Server-authoritative session + timer + clean cancel | The `alive`-flag + `os.clock()` deadline + `task.wait(0.1)` poll pattern | `src/server/services/MinigameService.lua` |
| Awarding followers | `FollowerService:Award(player, amount, reason)` | `src/server/services/FollowerService.lua` |
| One-time completion badge | `TrophyService:AwardTrophy(player, id)` + trophy def | `src/server/services/TrophyService.lua`, mirrored in `PhoneMenuController` social modal |
| The phone UI (carousel + modal pattern) | `PhoneMenuController` | `src/client/controllers/PhoneMenuController.lua`, items in `Config/Ui.lua` |
| Player teleport between zones + screen fade | `PlaceService` teleport, `TravelController`'s `tweenFade` | `PlaceService.lua`, `TravelController.lua` |
| Persistence (auto-migrating profile) | `DataService` + ProfileStore `Reconcile()` | `DataService.lua`, profile in `Types.lua` + `Config/Player.lua` |
| Networking contract | Add named events to `Net.lua` | `src/shared/Net.lua` |
| Auto-wiring a new service/controller | `Bootstrap` (`:Init()` then `:Start()`) | `src/shared/Bootstrap.lua` |

### What is genuinely net-new

1. **Quest state machine** — no quest concept exists. New `QuestService` (server) + `QuestController` (client).
2. **Cinematic camera** — *nothing* takes over the workspace camera anywhere in `src/`. New `CutsceneController` (client).
3. **Objective beacons + timed collection** — no Beam/beacon/collectible/pickup system exists. New, built per the spatial-verification loop.
4. **Quest HUD** — no countdown timer or objective counter UI exists.
5. **Destination-aware fast travel** — `PlaceService` is a binary Home↔Airport toggle today; it needs a quest-driven teleport that does **not** charge the carbon-footprint follower loss.
6. **Persisted quest completion** — a new `CompletedQuests` profile field.

---

## 3. Where the code goes (repo conventions)

```
src/shared/
  Config/Quest.lua          NEW  Pilot def, timer, package positions, beacon visuals, rewards, camera keyframes
  Config/init.lua           edit Config.Quest = require(script.Quest)
  Net.lua                   edit register the quest remotes (see §6)
  Types.lua                 edit add CompletedQuests to ProfileData
  Config/Player.lua         edit add CompletedQuests = {} to ProfileTemplate
src/server/services/
  QuestService.lua          NEW  quest state machine, server timer, collection validation, rewards,
                                 Pilot spawn + dialog/cutscene orchestration (single writer of CompletedQuests)
  TrophyService.lua         edit add the Pilot completion trophy def
  PlaceService.lua          edit add a destination-aware TravelTo (no carbon loss) for quest travel
src/client/controllers/
  QuestController.lua        NEW  quest HUD (timer + 4/4 counter), objective beacons, collection input
  CutsceneController.lua     NEW  Scriptable-camera cutscene player (tween keyframes, restore camera)
  PhoneMenuController.lua    edit a "Quest" screen: Go to City / Return to Airport (gated on active quest)
```

`QuestService` and `CutsceneController`/`QuestController` are auto-wired by `Bootstrap` — no
registration list to edit. Tunables live in `Config/Quest.lua` (golden rule 3); the quest never holds
a magic number. Every remote is declared in `Net.lua` and validated server-side (golden rule 4).

**Pilot spawn note:** the NPC-model build (`CreateHumanoidModelFromUserId` → outfit → anchored root →
floor-align → `ProximityPrompt`) currently lives privately in `DialogService.spawnNpc`. The Pilot is
**not** a minigame host, so he doesn't belong in `Config.Npc` (whose `NpcDef` requires arena/minigame
fields and whose dialog auto-routes to `MinigameService`). Two acceptable paths — pick during Phase A:
- **(Recommended) Extract a shared helper** `Util/NpcModel.buildModel(spec)` that both `DialogService`
  and `QuestService` call. Justified DRY: two services now need the same build. Keep it a surgical
  extraction — same behavior, no feature creep.
- **Minimal:** `QuestService` carries its own ~40-line build copy. Faster, but duplicates logic.

---

## 4. The Pilot NPC

- **Zone:** `Airport` — stands inside the arrivals terminal like the other airport NPCs (floor `Y = 1.1`).
  Suggested post near the terminal approach, e.g. `Vector3.new(0, 1.1, 700)` facing the entrance
  (`SpawnYaw` toward −Z / the apron). **Exact post + facing verified in Studio**, not from the number.
- **Look:** pilot uniform via the existing `NpcOutfit` shape (`Hats` = a pilot/officer cap such as the
  White Star Line Officer Cap already used by the Postman; `Layered` = a uniform jacket). Filled in the
  Studio catalog pass like the other NPCs.
- **Special behavior:** he is a **quest-giver**, not a minigame host. His "Talk" prompt routes to
  `QuestService`, which decides the conversation based on quest state:
  - **Never accepted** → cinematic intro → Accept / Decline.
  - **Active, packages incomplete** → a short "any luck with those packages?" nudge.
  - **Active, all 4 collected (player returned)** → cinematic ending → reward.
  - **Already completed (one-time)** → warm "thanks again, hero" speech bubble, no reward.
- **Animations:** `NpcActor.pose(animator, animId, seconds)` for a *worried* loop during the intro and a
  *happy/cheer* during the ending. Use Roblox default emote IDs as placeholders (the pattern the whole
  roster uses), with the IDs in `Config.Quest` so they're swapped without touching logic.

---

## 5. Quest state machine (server: `QuestService`)

One **per-player** session (not the single global slot `MinigameService` uses — multiple players must
be able to quest at once). Mirror the MinigameService lifecycle *pattern*, don't extend the service.

```
idle ──accept──▶ collecting ──all 4 collected──▶ returning ──deliver to Pilot──▶ complete
                     │                                  │
                     └────────── timer expires ─────────┴──▶ failed ──▶ idle (retryable)
```

- **Session table** per player: `{ phase, alive, deadline, collected = {bool×4}, count }`.
- **Timer:** start `deadline = os.clock() + Config.Quest.TimeLimitSeconds` when the player arrives in the
  city (phase → `collecting`). A `task.spawn` poll loop (`while alive and os.clock() < deadline`)
  enforces expiry server-side. The client renders its own countdown from a single `QuestState` sync
  (start + duration); the **server is the sole authority** on whether time ran out.
- **Failure** (`failed`): gentle. Fire `QuestState(phase="failed")`, snap the player back to the airport
  via `PlaceService:TravelTo`, despawn beacons, reset to `idle`. The Pilot gives an understanding line.
- **Cleanup:** `alive=false` on disconnect / failure / completion; despawn anything spawned; tear down
  the poll loop — same discipline as `MinigameService.endSession`.
- **Single writer:** `QuestService` is the only writer of `CompletedQuests`; it asks `FollowerService`
  and `TrophyService` to grant rewards (golden rule 2).

### The 4 packages & beacons — **per-player, GTA-style**

Objective markers in GTA/Zelda are **personal** — only the questing player sees their objectives. That
also sidesteps concurrent-quester collisions in a shared world. So:

- **Visuals are client-side** (`QuestController`): at `collecting` start it renders 4 glowing beacons at
  `Config.Quest.PackagePositions` (4 `Vector3` around the Home town). Each beacon = a `Beam` between a
  ground and a sky `Attachment` + `ParticleEmitter` + `PointLight` + a Neon part, gently pulsing — built
  and **tuned by looking in Studio** (the spatial loop: top-down for placement, eye-level for scale,
  close-ups where a beacon meets the ground). Beacon tunables (height, color, particle rate) live in
  `Config.Quest`.
- **Collection is server-authoritative:** when the player nears a beacon, `QuestController` offers a
  prompt and fires `RequestCollectPackage(index)`. `QuestService` validates the player's *real* root
  position is within `CollectRadius` of `PackagePositions[index]`, the package isn't already collected,
  and the phase is `collecting`. Only then does it mark progress and reply `QuestState`
  (collected/total). A nice particle burst + sound + an encouraging line plays client-side.
- When `count == 4`, phase → `returning`; the phone's "Return to Airport" becomes active.

---

## 6. Networking (`Net.lua` additions)

Keep the surface small; one `QuestState` event carries most of the sync.

| Event | Dir | Payload | Purpose |
|---|---|---|---|
| `QuestState` | s→c | `(questId, phase, collected, total, deadline?)` | The one HUD/state sync — drives timer + counter + phone buttons |
| `QuestAccept` | c→s | `()` | Player accepted the offer (during the intro cutscene) |
| `QuestDecline` | c→s | `()` | Player declined |
| `RequestQuestTravel` | c→s | `(destination: string)` | Phone fast-travel ("City" / "Airport"); validated against quest state |
| `RequestCollectPackage` | c→s | `(index: number)` | Player triggered a beacon; server validates proximity |
| `CutscenePlay` | s→c | `(sequenceId: string)` | Take camera control and play a named cutscene |
| `CutsceneDone` | c→s | `()` | Cutscene finished (or skipped) — lets the server sequence dialog beats |

Collection feedback rides on `QuestState`. The Pilot's spoken lines reuse `SpeechBubble` (server-side,
all players see them); only the **interacting** player gets the Accept/Decline buttons and the camera.

---

## 7. Cinematics (`CutsceneController`, v1)

The only net-new *engine-interaction* risk in the quest, and the reason to verify by **looking**.

- On `CutscenePlay(sequenceId)`: set `camera.CameraType = Enum.CameraType.Scriptable`, then tween
  `camera.CFrame` through a sequence of `CFrame.lookAt(eye, target)` keyframes with `TweenService`.
  Restore `Enum.CameraType.Custom` when done and fire `CutsceneDone`.
- **Keyframes live in `Config.Quest`** as eye/target offsets relative to the Pilot's post (rule 3), so
  framing is tuned without editing the controller.
- **Server drives the beats** (`QuestService`): play intro cutscene → Pilot worried pose + speech-bubble
  lines timed to the camera → on the final beat show Accept/Decline. The ending mirrors it: pan to
  Pilot → happy pose → thank-you line → grant reward → restore camera.
- Coordinate with `TravelController`'s `tweenFade` for a clean fade on the fast-travel cuts.
- **Verification is visual, not numeric:** capture each cutscene beat in Studio (`screen_capture`),
  confirm the Pilot is framed, the pan reads smoothly, nothing clips. A CFrame that type-checks can
  still point at a wall — see the skill's "Seeing the scene."

Sample dialogue (keep lines short, warm):

> Intro: *"Oh no… my flight leaves in two minutes and I left four packages back in the city!"*
> *"I was so busy helping everyone this morning… could you be my hero and grab them?"*
> Ending: *"You made it just in time — thank you! The flight can leave on schedule. You're not just
> helpful, you're reliable and kind. That's what makes the world better!"*
> Fail (gentle): *"Ah, they slipped away this time — no worries. Thanks for trying, friend!"*

---

## 8. Fast travel & the phone

- **City = Home neighborhood.** "Go to City" teleports Airport → a spot in the Home town
  (`Config.Quest.CityDropOff`); "Return to Airport" teleports back to the terminal (the existing
  `dropOff("Airport")` location, beside the Pilot).
- **Mechanism:** add `PlaceService:TravelTo(player, zoneName)` — `PlaceService` stays the single owner of
  player location/teleport. `QuestService` calls it; it reuses the teleport + `setLocation` logic but
  **skips the carbon-footprint follower loss** (that's a cab penalty, not a quest action). `QuestService`
  starts the timer the moment the city teleport lands.
- **Phone screen:** add a `Quest` item to `Config.UI.Phone.Items` and a `showQuestModal()` in
  `PhoneMenuController` (modeled on the existing social modal): a timer readout, a 0/4 objective list, and
  the "Go to City" / "Return to Airport" buttons firing `RequestQuestTravel`. The item is **only shown
  while a quest is active** (same gating idiom as the cab item, which is hidden without its trophy).

---

## 9. Persistence & reward (one-time)

- **Profile field:** add `CompletedQuests: { [string]: true }` to `ProfileData` (`Types.lua`) and
  `CompletedQuests = {}` to `ProfileTemplate` (`Config/Player.lua`). ProfileStore `Reconcile()`
  backfills existing profiles automatically — no migration script.
- On delivery: `QuestService` sets `CompletedQuests["PilotPackages"] = true`, calls
  `FollowerService:Award(player, Config.Quest.Reward, "quest-pilot-packages")`, and
  `TrophyService:AwardTrophy(player, "pilot_delivery")` (add the trophy def + mirror it in the
  `PhoneMenuController` social-modal Airport tab).
- **Replays:** if `CompletedQuests["PilotPackages"]` is set, talking to the Pilot gives a warm
  "thanks again" speech bubble and offers no reward.

---

## 10. Build phases (one commit each, branch off `main`)

Each phase has a checkable **Verify**. Logic is verified with `make analyze` + a Studio runtime check
(`execute_luau`); anything placed in the world is verified by **looking** (`screen_capture`), never from
the math. Run `make ci` before every commit.

**Phase A — Pilot NPC + quest skeleton + persistence**
- Add `Config/Quest.lua` (Pilot def + tunables), wire it into `Config/init.lua`. Add `CompletedQuests`
  to `Types.lua` + `Player.lua`. Add the quest remotes to `Net.lua`. Create `QuestService` that spawns
  the Pilot (shared `NpcModel` helper) and runs the state machine through accept/decline (no travel yet).
- **Verify:** Pilot stands dressed in the terminal (Studio capture); talking offers Accept/Decline;
  accepting sets state and (stub) completion persists across rejoin (`execute_luau` reads the profile);
  `make analyze` clean.

**Phase B — Fast travel (phone)**
- Add `PlaceService:TravelTo` (no carbon loss). Add the phone Quest screen + `RequestQuestTravel`
  (gated on active quest). Start/stop the server timer on city arrival/return.
- **Verify:** with the quest active, phone → "Go to City" lands the player in the Home town and starts
  the timer; "Return to Airport" returns them to the Pilot; gating hides the screen when idle.

**Phase C — Packages, beacons & timed collection + HUD**
- `QuestController`: render 4 beacons at `Config.Quest.PackagePositions`, the collection prompt, the HUD
  (timer + 0/4). `QuestService`: validate `RequestCollectPackage` by real proximity; advance to
  `returning` at 4/4; enforce timer expiry → `failed`.
- **Verify (spatial):** Studio captures — beacons placed/scaled correctly around town (top-down +
  eye-level + a ground-seam close-up); walk the character to collect all 4 under the timer; let the
  timer expire to see the gentle fail + snap-back; confirm server rejects a spoofed collect from far away.

**Phase D — Cinematics**
- `CutsceneController` (Scriptable camera + tween keyframes). `QuestService` drives the intro and ending
  cutscenes, syncing Pilot poses (`NpcActor.pose`) and speech-bubble lines to camera beats; fades via
  `TravelController`.
- **Verify (visual):** capture each cutscene beat — Pilot framed, pan smooth, no clipping; intro ends on
  Accept/Decline; ending plays before the reward; camera restores to normal afterward.

**Phase E — Reward, trophy & completion/replay polish**
- Award followers + the `pilot_delivery` trophy on delivery; add the trophy to the social modal. Wire the
  one-time gate (replays = thanks-again, no reward) and the failure path end-to-end. Encouraging
  feedback toasts on each collection.
- **Verify:** full run grants followers **once** and shows the trophy in the phone's Airport tab; a second
  run gives the warm replay line and no reward; failure path is gentle and leaves the player idle/retryable.

---

## 11. Open items to confirm before Phase A

- **Unlock gate for the Pilot:** does the quest require a follower threshold / prerequisite trophy to
  appear (like the airport NPC chain, 600+), or is it available to everyone from the start? (Default
  assumption: available early — it's the intro quest.)
- **Exact Pilot outfit asset IDs** — chosen in the Studio catalog pass (placeholder: Postman's officer cap
  + a uniform jacket).
- **Package positions & beacon look** — starting `Vector3`s and visual tunables are placeholders until
  walked and captured in Studio.
- **Time limit** — 120s per the seed; confirm it's reachable across the Home town on foot once positions
  are set (tune in `Config.Quest`).
