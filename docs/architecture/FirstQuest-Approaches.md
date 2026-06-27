# FirstQuest Architecture — Three Approaches

## Context

Adding a second quest NPC "Tim" who lost his lunch box at the airport. The existing QuestService/QuestController are already ~80% quest-agnostic — they reference Config.Quest for every tunable, with no hardcoded Pilot logic.

## The Three Approaches

### Approach A: Full Clone (Duplicate Everything)

Duplicate QuestService, QuestController, and add a new Net remote set for FirstQuest.

- **New files:** QuestServiceTim.lua, QuestControllerTim.lua (~800+ lines each)
- **Changes:** Config/Quest.lua (Tim config), Net.lua (new remotes)
- **Estimated LOC:** ~1,800 new lines
- **Pros:** Zero risk to Pilot; fully isolated
- **Cons:** Massive code duplication; bug fixes only apply to one; hard to maintain; 3rd quest doubles again

### Approach B: Extracted Framework

Extract shared quest logic into a QuestFramework module. Both quests use it via Config dispatch.

- **New files:** QuestFramework.lua, QuestRegistry.lua, QuestTemplate.lua (~400 lines)
- **Changes:** Refactor QuestService, QuestController, CutsceneController, Net.lua, Config/init.lua
- **Estimated LOC:** ~400 new, ~300 refactored
- **Pros:** Elegant; 3rd quest costs 60 LOC; true reuse
- **Cons:** Refactoring risk to working code; requires touching QuestService (900+ lines); 3rd quest not yet needed

### Approach C: Config-Only Addition (Recommended)

The existing QuestService/QuestController already accept any quest via Config dispatch. Add Tim's config entries and a small gate check.

- **New files:** None
- **Changes:** Config/Quest.lua (Tim config), QuestService.lua (2 lines for gate), Types.lua (Kindness trophy), TrophyService.lua (TROPHY_DEFS), PhoneMenuController.lua (remove unused Quest item)
- **Estimated LOC:** ~150 new/changed
- **Pros:** Minimal risk; zero duplication; works immediately; Pilot untouched
- **Cons:** Slightly less "clean" if we end up with many quests later (but 2 quests doesn't justify extraction)

## Detailed Comparison

| Concern | A (Clone) | B (Framework) | C (Config-only) |
|---------|-----------|---------------|-----------------|
| Files changed | 5 | 7 | 5 |
| New LOC | ~1,800 | ~400 | ~150 |
| Risk to Pilot | Zero | Medium | Very Low |
| 3rd quest cost | +1,800 | +60 | +60 |
| Time | 2h | 3d | 30min |

## My Recommendation: Approach C

The code is already designed for multiple quests. Config/Quest.lua is the **only** file that needs quest-specific data (NPC, positions, dialogue, cutscene, reward). QuestService already:
- Iterates `Config.Quest.PackagePositions` for beacons (works for 1 or 4)
- Uses `Config.Quest.TimeLimitSeconds` for the timer
- Uses `Config.Quest.Lines` for dialogue
- Uses `Config.Quest.Cutscene` for keyframes

The only change needed in QuestService is a **trophy gate check** in `onTalk` (new hard gate: must have `taxi_driver_mobility`). Everything else is identical.

### Files to Change

1. **`src/shared/Config/Quest.lua`** — Add `Quest.FirstQuest` block (NPC, box pos, dialogue, cutscene, reward, trophy)
2. **`src/server/services/QuestService.lua`** — Add trophy gate check in `onTalk` (`taxi_driver_mobility`)
3. **`src/server/services/TrophyService.lua`** — Add `FirstQuest = { Id = "kindness", Name = "Kindness", Emoji = "⭐" }`
4. **`src/shared/Types.lua`** — No changes (CompletedQuests already exists; questId="FirstQuest" just needs string entry)
5. **`src/client/controllers/PhoneMenuController.lua`** — Remove unused Quest item from carousel
6. **`docs/dev/quests/003_firstquest_tim.md`** — Design doc (per recipe)

### Key Design Decisions

- **Tim's spawn:** Near Postman at `Vector3.new(55, 0, -45)` in Home zone (central plaza, open ground)
- **Hard gate:** RequiredTrophies check in QuestService.onTalk before creating session
- **Box location:** Single collectible at airport (airport spawn/terminal area)
- **Timer:** 90 seconds (single collectible = shorter than Pilot's 120s)
- **Reward:** 200 followers + Kindness trophy (⭐)
- **Cutscene:** Intro + Ending with GTA-style cinematic (same pattern as Pilot)
- **Phone item:** Remove — Quest item in phone menu is unused (it was only for Pilot's fast-travel, but the quest uses PlaceService:TravelTo which doesn't need a phone button)

## Next Steps

1. User approves Approach C
2. Create design doc
3. Implement Phase 1: Config entries
4. Implement Phase 2: Gate + reward
5. Implement Phase 3: Cutscene
6. Studio spatial verification
7. Commit