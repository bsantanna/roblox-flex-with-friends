# Quest 003: "Tim's Lost Lunch Box" (FirstQuest)

**Date:** 2026-06-27
**Status:** Implemented
**Quest ID:** `FirstQuest`

---

## Vision

A simple, warm first quest that introduces players to the quest system. Tim, a casual NPC in the central plaza, forgot his lunch box at the airport. The player must retrieve it as a single collectible. This quest gates on the taxi_driver_mobility trophy (earned from the TaxiDriver minigame), creating a natural progression: train → win cab game → help Tim.

**Reward:** 200 followers + Kindness trophy (⭐)

## Locked Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| Quest ID | `FirstQuest` | Simple, descriptive |
| NPC Name | Tim | Casual, friendly |
| NPC Location | Home zone, near Postman (`55, 0, -45`) | Central plaza, open ground |
| Collectible | 1 lunch box at Airport terminal (`0, 1.5, 690`) | Single objective = fast, clear |
| Timer | 90 seconds | Shorter than Pilot (120s) for a single collectible |
| Reward | 200 followers + Kindness (⭐) | Same scale as Pilot, star emoji for kindness |
| Hard gate | `RequiredTrophies = {"taxi_driver_mobility"}` | Mirrors the TaxiDriver chain pattern |
| Phone item | None (Quest item unused, left as-is) | Quest uses PlaceService:TravelTo, no phone button needed |
| Cutscene | Intro + Ending (Farewell) | GTA-style, reuses CutsceneController |
| Outfit | Casual (Shelby cap + blue tee + jeans) | Distinct from Pilot's uniform |

## State Machine

```
idle --[talk + mobility trophy]--> offer --[accept]--> collecting --[1/1 collect]--> returning
                                    |                                              |
                                    decline-> idle                         [talk]--> complete
                                                                           (reward + trophy)
```

Same structure as the Pilot quest, but:
- Single collectible instead of 4
- Shorter timer (90s vs 120s)
- Hard gate on taxi_driver_mobility trophy
- Simpler cutscene (2-beat Intro + 1-beat Ending Farewell)

## Files Modified

| File | Change |
|------|--------|
| `src/shared/Config/Quest.lua` | Added `Quest.FirstQuest` block |
| `src/server/services/QuestService.lua` | Multi-quest refactor: NPC registry, trophy gate, questId-aware state machine |
| `src/server/services/TrophyService.lua` | Added `FirstQuest` / Kindness trophy to TROPHY_DEFS |
| `src/client/controllers/PhoneMenuController.lua` | Added `kindness` trophy to TROPHY_DEFS + TROPHY_ZONE (City) |

## No Changes Required

- **QuestController.lua** — Already questId-aware (receives questId from QuestState event)
- **CutsceneController.lua** — Already sequenceId-driven (dispatches "Intro"/"Ending" from config)
- **Net.lua** — Already has all quest remotes (QuestState, QuestAccept, QuestDecline, RequestCollectPackage, CutscenePlay, CutsceneDone)
- **Types.lua** — `CompletedQuests: { [string]: true }` already supports any questId
- **Phone menu** — No "Quest" item exists; no cleanup needed

## Multi-Quest Refactor Details

QuestService was refactored from single-quest (Pilot-only) to multi-quest:

1. **NPC registry** (`questNpcs: { [string]: { model, root, animator } }`) — indexed by NpcId, not quest key
2. **Reverse lookup** (`npcToQuestId`) — maps NpcId → questId for onTalk
3. **`getQ(questId)` helper** — dispatches to `Q` (Pilot) or `Q.FirstQuest`
4. **Trophy gate** in `handleTalk` — checks `cfg.RequiredTrophies` against `profile.Data.Trophies`
5. **Config-driven collectibles** — supports both `PackagePositions` array and `CollectPosition` single vector
6. **All `speak`/`fireState` calls** thread questId through

The Pilot quest is unchanged in behavior; the refactor is transparent to it.

## Verification (make ci)

- `fmt-check`: PASS
- `selene`: 0 errors, 0 warnings
- `analyze`: 0 errors
- `tests`: 67/67 passed
- `build`: build.rbxl produced

## Next Steps

1. **Studio spatial verification** — Confirm Tim spawns in the central plaza, the lunch box beacon is visible at the Airport terminal, and the cutscene frames correctly
2. **Gameplay testing** — Verify the trophy gate blocks unqualified players, accepts qualified ones, and the 90s timer works
3. **Narrative polish** — Fine-tune dialogue lines, toast messages, cutscene keyframes in Studio