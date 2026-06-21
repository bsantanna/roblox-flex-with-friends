# Gym friends

The gym friends (`Config.GymFriends`) are **ambient, customizable decor**: twelve NPCs (four workout
types × three people) who exercise at their stations on the gym's opened first floor and wander to
lounge groups on breaks. They have **no minigames**. Their point is atmosphere plus a light
personalization hook — the first time you meet one, you dress it.

## Behavior

`GymFriendService` spawns all twelve from the roster and runs each as a `GymFriend` agent
(`Shared.Logic.Routine`): exercise at the station for a jittered interval, walk to its fixed slot in
a lounge group, rest, repeat. Walking is anchored CFrame motion on a fixed Y plane, so friends never
fall through the floor; a `GymNpc` collision group keeps them from clipping into each other and a
`GymProp` group lets them pass through the equipment so straight-line walking never snags.

Positions and the placeholder workout animations are tuned by looking in Studio (`Config.GymFriends`
+ the per-workout roster modules `Runners`/`Cyclists`/`Lifters`/`Floor`).

## Meeting and customizing a friend

Talking to a friend (a `Talk` ProximityPrompt) does one of two things:

- **First meeting** — opens the "create your friend" editor (`NpcEditorController` fires from
  `OpenNpcEditor`): a live preview rig with a body-colour palette and Shirt / Pants / accessory-slot
  tabs, each backed by the Roblox catalog (`AvatarEditorService:SearchCatalog`). On **Save**, the
  chosen look goes to the server (`SaveNpcOutfit`).
- **After befriending** — runs a branching, choose-your-reply conversation
  (`Shared.Logic.DialogTree`): the friend greets you and you pick replies. Lines render in the shared
  server-side speech bubble; only the talking player gets the answer buttons.

## Outfit storage and rendering

- **`OutfitService`** is the single writer of `Profile.Data.Friends` — a per-player map of
  `npcId -> OutfitData`. A key being present means the player has befriended that NPC (which is what
  gates first-meet vs. friend dialog). On save it **validates every catalog id** against its expected
  `AssetType` (`GetBatchItemDetails`), stores the look, and awards `Config.GymFriends.BefriendReward`
  followers — once per friend. Other code asks here (`IsFriend` / `GetOutfit` / `SaveOutfit`); it
  never touches the map directly.
- Each player's outfit map replicates to **their own client only** (`NpcOutfitSync`).
- **Rendering is per-player and client-side.** Every friend spawns server-side with the shared
  default look (`Config.DefaultNpcOutfit`). For each friend a player has customized,
  `NpcAppearanceController` builds a local cosmetic rig from the saved outfit, hides the shared server
  rig *locally* (other players still see the default), and makes the cosmetic rig follow the server
  rig's pivot and mirror its animation. Players who never customized a friend just see the default.

## Relationship to the minigame NPCs

Gym friends and the minigame NPCs (`Config.Npc`) are independent systems — different config, different
service, different interaction. The catalog editor and per-player outfit storage described here apply
**only** to gym friends. The minigame NPCs have fixed, code-configured looks (see
[minigame_npcs.md](minigame_npcs.md)).
