# Minigame NPCs

The minigame NPCs (`Config.Npc`) are *game hosts*: each stands in the world, and talking to it can
start a minigame that pays out followers and a once-per-account trophy. This file is the **canonical
roster and reward reference** — keep it in sync with `Config.Npc` (see the procedural note at the
bottom).

For *how the minigame framework works* (the pre-game flow, the plugin contract, how to add one), read
the `flex-with-friends-dev` skill's `references/minigames.md`. This file is about *what exists and
what it pays*, not how to build it.

## Roster

Update this table when an NPC is created, modified, or removed.

| NPC | Minigame | Zone | Unlock | Reward (max) | Trophy (id) |
|-----|----------|------|--------|--------------|-------------|
| Postman | Rock-Paper-Scissors | Home (central plaza) | None | 160 (2×40 + 80 bonus) | 📦 Swift Post (`postman_swiftpost`) |
| Cowboy (Cole) | Rock-Paper-Scissors | Farm (paddock) | None | 160 (2×40 + 80 bonus) | 🐄 Cowboy (`cowboy_roundup`) |
| PersonalTrainer | Simon Says (pose-memory) | Home (CentralBuilding) | 100 followers | 225 (50+75+100) | 💪 Strength (`personal_trainer_strength`) |
| Farmer | Simon Says (pose-memory) | Farm (west fence) | 200 followers | 225 (50+75+100) | 🥛 Fresh Milk (`farmer_farmhand`) |
| Sage | Quick Draw (reaction) | Home (forest clearing) | 250 followers **and** `farmer_farmhand` | 220 (3×45 + 85 bonus) | ⚡ Fast Hands (`sage_quickdraw`) |
| TaxiDriver | Rock-Paper-Scissors | Home (NE ramp foot) | 300 followers **and** `personal_trainer_strength` | 160 (2×40 + 80 bonus) | 🚕 Mobility (`taxi_driver_mobility`) |
| Policeman | Quick Draw (reaction) | Home (by Neighbor02, NE) | 350 followers **and** `sage_quickdraw` | 220 (3×45 + 85 bonus) | 👮 Protection (`policeman_protection`) |
| Firefighter | Simon Says (pose-memory) | Home (by Neighbor01, NW) | 300 followers **and** `personal_trainer_strength` | 225 (50+75+100) | 🚒 Bravery (`firefighter_bravery`) |
| Gardener | Simon Says (pose-memory) | Home (NW green quarter) | 450 followers **and** `policeman_protection` | 225 (50+75+100) | 🌱 Caretaking (`gardener_caretaking`) |
| HomeBuilder | Tic-Tac-Toe | Home (by Neighbor03, W) | 300 followers **and** `personal_trainer_strength` | 160 (2×40 + 80 bonus) | 🏠 Nice Home (`home_builder_nicehome`) |
| Nurse | Memory (recognition) | Home (by Neighbor04, E) | 550 followers **and** `gardener_caretaking` | 225 (50+75+100) | 🩺 Healthy (`nurse_healthy`) |
| TruckDriver | Quick Draw (reaction) | Home (SW ramp foot) | 450 followers **and** `taxi_driver_mobility` | 220 (3×45 + 85 bonus) | 🚚 Heavy Duty (`truck_driver_heavyduty`) |
| Athlete | Simon Says (pose-memory) | Airport (terminal hall) | 600 followers **and** `personal_trainer_strength` | 225 (50+75+100) | 🏃 Speed (`athlete_speed`) |
| Chef | Memory (recognition) | Airport (terminal hall) | 700 followers **and** `sage_quickdraw` | 225 (50+75+100) | 🧅 Secret Sauce (`chef_secret_sauce`) |
| Singer | Rock-Paper-Scissors | Airport (terminal hall) | 800 followers **and** `firefighter_bravery` | 160 (2×40 + 80 bonus) | 🎤 Confidence (`singer_confidence`) |
| Violinist | Tic-Tac-Toe | Airport (terminal hall) | 900 followers **and** `home_builder_nicehome` | 160 (2×40 + 80 bonus) | 🎻 Refinement (`violinist_refinement`) |
| DJ | Memory (recognition) | Airport (terminal hall) | 1000 followers **and** `policeman_protection` | 225 (50+75+100) | 🎧 Grooves (`dj_grooves`) |
| Ballerina | Simon Says (pose-memory) | Airport (terminal hall) | 1100 followers **and** `truck_driver_heavyduty` | 225 (50+75+100) | 🩰 Swiftness (`ballerina_swiftness`) |
| Pianist | Memory (recognition) | Airport (terminal hall) | 1200 followers **and** `gardener_caretaking` | 225 (50+75+100) | 🎹 Talent (`pianist_talent`) |
| Archeologist | Tic-Tac-Toe | Airport (terminal hall) | 1300 followers **and** `nurse_healthy` | 160 (2×40 + 80 bonus) | 🦴 Relic (`archeologist_relic`) |

The Airport NPCs form a second collectible chain, each gating on a city NPC's trophy plus a rising
follower threshold (600→1300), so they unlock after the town is cleared. They stand stationary inside
the arrivals terminal and their trophies populate the Social Modal's **Airport** tab.

## Unlocks

An NPC's minigame branch opens only once the player **unlocks** it; the unlock is recorded in
`Profile.Data.UnlockedNpcs` (persisted, append-only — once earned it stays). `NpcService` evaluates
the gate on profile load, on every follower change, and on every trophy award.

A gate has two parts, both configured on the `Config.Npc.<npcId>` entry:

- **`UnlockFollowers`** — a follower threshold (`0` means no follower gate).
- **`RequiredTrophies`** *(optional)* — a list of trophy ids the player must already own. Because
  trophies are *earned by completing other NPCs' minigames*, this chains NPCs together: e.g. the
  Forest sage requires the Farmer's `farmer_farmhand` before it opens.

`DialogService` shows the `QualifiedLine` + training choice when both parts are satisfied, otherwise
the `GateLine`. `MinigameService:Request` re-checks the unlock as defense in depth.

## Rewards

- **Rock-Paper-Scissors** — `BaseReward` per round won + `MatchBonus` for taking the match
  (best-of-`2*WinsNeeded-1`). Max = `(WinsNeeded × BaseReward) + MatchBonus`.
- **Simon Says** — `BaseReward + (round-1) × RewardPerRound` per round cleared, over `MaxRounds`
  rounds (the sequence grows from `StartLength` arrows). Max = the sum across all rounds.
- **Tic-Tac-Toe** — `BaseReward` per game won + `MatchBonus` for taking the match (best-of-`2*WinsNeeded-1`,
  drawn games replay). The player is `PlayerMark` and moves first; the server plays the NPC (`NpcMark`)
  with a medium tactical strategy (take the win, else block, else random). A `MoveTimeoutSeconds` lapse
  forfeits the match. Max = `(WinsNeeded × BaseReward) + MatchBonus`.
- **Memory** — `BaseReward + (round-1) × RewardPerRound` per round cleared, over `Rounds` rounds (the
  count of emojis to memorize grows from `StartTargets`, shown for `ShowSeconds` before a `GridSize`-cell
  recall grid). Player selects the cells, then Submits; a wrong set or a `SelectTimeoutSeconds` timeout
  ends the game (rewards already earned are kept). Max = the sum across all rounds.
- **Quick Draw** — `BaseReward` per draw won (react within `ReactWindowSeconds` of the DRAW signal) +
  `MatchBonus` for winning every draw. One miss (too slow or a false start) ends the duel; rewards for
  draws already won are kept. Max = `(Rounds × BaseReward) + MatchBonus`. The press is timed on the
  **server** clock against the signal, so it can't be spoofed.

All follower awards route through `FollowerService:Award` (the single writer); tunables live in each
NPC's game subtable in `Config.Npc`.

## Trophies

A trophy is a once-per-account collectible, defined by an npcId and awarded when its minigame is fully
cleared (Simon Says) or the match is won (Rock-Paper-Scissors). Trophies persist in
`Profile.Data.Trophies` and gate the trophy-locked NPCs above.

- **Server**: `TrophyService` owns the definitions and the idempotent `AwardTrophy(player, npcId)`.
  It fires `TrophyEarned` (the full set, for the Social Modal grid) and `TrophyUnlocked` (a one-shot
  toast) to the client.
- **Client**: `PhoneMenuController` mirrors the definitions to render the grid + toast — **the two
  lists must stay identical** (same id / name / emoji per trophy).

## Looks

Each minigame NPC's model is built from `AvatarUserId` (`Players:CreateHumanoidModelFromUserId`,
currently the Roblox avatar `1`), with a red-box fallback if the fetch fails. On top of that base,
`DialogService` dresses it in a fixed, **code-configured** profession outfit from
`Config.Npc.<npcId>.Outfit` — applied on spawn, **not** player-editable (that's the gym friends, a
separate system).

An `Outfit` has two parts, both real Marketplace asset ids:

- **`Hats`** — rigid headwear ids, applied through `HumanoidDescription.HatAccessory` (the string
  property — rigid accessories are dropped by `SetAccessories`).
- **`Layered`** — layered clothing (`{ AssetId, Type = Enum.AccessoryType.* }`), applied through
  `HumanoidDescription:SetAccessories(list, false)` (`false` keeps the hats).

Because `ApplyDescriptionAsync` requires the model to be in the DataModel, the outfit is applied
**after** the NPC is parented into its zone. Every minigame NPC now wears a full profession look —
a hat plus matching layered top and/or trousers — so the body reads as the job, not just the hat:
e.g. Policeman (navy jacket + trousers), Nurse (medical scrubs), Cowboy/TruckDriver (plaid flannel +
jeans), Firefighter (turnout pants), Gardener/HomeBuilder (denim overalls), Trainer (tank top),
Farmer (overalls), Sage (robe). The `Layered` asset ids are real catalog layered clothing
(AssetTypeId 64–72), so they render for every player without the place owning them.

The eight Airport NPCs also wear full profession looks (Studio-verified Marketplace asset ids):
Athlete (sweatband + tank top + joggers), Chef (toque + white coat), Singer (cap + gold tuxedo),
Violinist (black pinstripe tuxedo), DJ (headphones + varsity jacket), Ballerina (tank top + tulle
tutu), Pianist (navy tuxedo), Archeologist (pith helmet + flannel + jeans). As with the town NPCs,
the `Hats` are rigid type-8 accessories and every `Layered` piece is real catalog layered clothing
(AssetTypeId 64–72), so they render for every player without the place owning them.

## Poses

Pose/throw/arrow animations are configured per NPC in its game subtable (`SimonSays.Poses`,
`RockPaperScissors.Poses`).

> **Placeholders:** the poses are Roblox **default** emote animation ids — they load for every player.
> Truly profession/game-specific poses (squat, lift, draw…) must be **uploaded** to the place/group
> owner's account, because the engine only plays animation assets the place owner owns (or Roblox
> defaults); arbitrary catalog animation ids fail to load for other players. Once uploaded, swapping
> is a one-line id change per pose in `Config.Npc`.

## Farm chore patrol

The Farmer and Cowboy NPCs walk around their zone doing chore animations when not in a minigame.
Each chore point has a position (where the NPC glides to), an animation id, and a delay (how long
the chore plays). The chore cycle loops: the NPC visits each point in order, then returns home and
repeats.

When a player talks to the NPC and starts a minigame, the chore patrol pauses (the NPC stays where
it is) and the NPC walks to the arena. After the minigame ends, the NPC walks home and the chore
patrol resumes automatically.

**Chore config** lives in `Config.Npc.<npcId>.Chore` with `HomePosition` and an ordered
`Waypoints` array. Animations use Roblox default emote IDs as placeholders — upload profession-specific
animations and replace the IDs.

---

**Procedural note for agents:** This file is the canonical reference for the minigame NPCs. **Always
update the Roster table** when adding, modifying, or removing an entry in `Config.Npc` — include the
npcId, minigame, zone, unlock requirement (followers and/or required trophies), max reward, and trophy
id. When you add a trophy, update both `TrophyService` and the `PhoneMenuController` mirror, and the
Trophies section here. This keeps the docs in sync with the source of truth without parsing module
code.
