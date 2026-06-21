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
**after** the NPC is parented into its zone. Current looks: Postman (officer cap), Cowboy (cowboy
hat), Trainer (sweatband + tank top), Farmer (straw hat + denim overalls).

## Poses

Pose/throw/arrow animations are configured per NPC in its game subtable (`SimonSays.Poses`,
`RockPaperScissors.Poses`).

> **Placeholders:** the poses are Roblox **default** emote animation ids — they load for every player.
> Truly profession/game-specific poses (squat, lift, draw…) must be **uploaded** to the place/group
> owner's account, because the engine only plays animation assets the place owner owns (or Roblox
> defaults); arbitrary catalog animation ids fail to load for other players. Once uploaded, swapping
> is a one-line id change per pose in `Config.Npc`.

---

**Procedural note for agents:** This file is the canonical reference for the minigame NPCs. **Always
update the Roster table** when adding, modifying, or removing an entry in `Config.Npc` — include the
npcId, minigame, zone, unlock requirement (followers and/or required trophies), max reward, and trophy
id. When you add a trophy, update both `TrophyService` and the `PhoneMenuController` mirror, and the
Trophies section here. This keeps the docs in sync with the source of truth without parsing module
code.
