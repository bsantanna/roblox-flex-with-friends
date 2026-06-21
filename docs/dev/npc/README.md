# NPCs

Flex-with-Friends has **two separate NPC populations**, built and maintained independently. This
folder documents what each one *is* and how it behaves in the game; the engineering contract for
*building* a minigame lives in the `flex-with-friends-dev` skill's `references/minigames.md`.

| Population | Config | Spawned by | Interaction | Customizable look? |
|---|---|---|---|---|
| **Minigame NPCs** | `Config.Npc` | `DialogService` | Talk → a minigame (Rock-Paper-Scissors, Simon Says, Quick Draw) for follower + trophy rewards | No — fixed, profession-matched outfit configured in code |
| **Gym friends** | `Config.GymFriends` | `GymFriendService` | Talk → first meeting opens the "create your friend" editor; afterwards a branching chat. No minigames | Yes — per-player, via the in-game catalog editor |

Keep the two crisp: a minigame NPC is a *game host* with a fixed identity; a gym friend is *ambient
decor* the player personalizes. Don't add minigames to gym friends and don't make minigame NPCs
player-editable.

## Documents

- **[minigame_npcs.md](minigame_npcs.md)** — the canonical reference for the minigame NPCs: the
  roster, unlock rules (followers + trophy gates), reward formulas, the trophy catalog, and each
  NPC's profession outfit + pose config. **Update its roster table whenever `Config.Npc` changes.**
- **[gym_friends.md](gym_friends.md)** — the customizable gym friends: the editor, per-player outfit
  storage, and how a player's custom look is rendered.

## Where the code lives

```
src/shared/Config/Npc.lua            minigame NPC roster + framework tunables
src/shared/Config/GymFriends/        gym friend roster + AI/dialog tunables
src/server/services/DialogService    spawns minigame NPCs, runs their dialog, hands off to a minigame
src/server/services/MinigameService  generic pre-game flow + plugin registry (see the skill reference)
src/server/services/minigame/games/  one plugin per minigame (RockPaperScissors, SimonSays, QuickDraw)
src/server/services/NpcService       records NPC unlocks (follower + trophy gates)
src/server/services/TrophyService    awards + persists once-per-account trophies
src/server/services/GymFriendService spawns gym friends, runs their routine + branching dialog
src/server/services/OutfitService    single writer of per-player gym-friend outfits
src/client/controllers/              dialog, minigame, and NPC-appearance/editor UI
```
