**Yes, Roblox supports powerful tools for this**, but there is **no single built-in "default character creation dialog"** that you can just show to the player for customizing gym friends/NPCs out of the box.

### Current NPC Roster (Minigame NPCs)

Every new NPC added to `Config.Npc` must be reflected here. Update this table when an NPC is created, modified, or removed.

| NPC | Minigame | Zone | Unlock Requirement | Reward (max) | Trophy (id) |
|-----|----------|------|--------------------|--------------|-------------|
| Postman | Rock Paper Scissors | Home (central plaza) | None | 160 (2×40 + 80 bonus) | 📦 Swift Post (`postman_swiftpost`) |
| Cowboy (Cole) | Rock Paper Scissors | Farm (paddock) | None | 160 (2×40 + 80 bonus) | 🐄 Cowboy (`cowboy_roundup`) |
| PersonalTrainer | Simon Says (pose-memory) | Home (CentralBuilding) | 100 followers | 225 (50+75+100) | 💪 Strength (`personal_trainer_strength`) |
| Farmer | Simon Says (pose-memory) | Farm (west fence) | 200 followers | 225 (50+75+100) | 🥛 Fresh Milk (`farmer_farmhand`) |

**Reward notes:**
- **Simon Says:** `BaseReward + (round-1) * RewardPerRound` per round, grows from StartLength→StartLength+MaxRounds-1 arrows. Max total = sum across all rounds.
- **Rock Paper Scissors:** `BaseReward` per round win + `MatchBonus` for winning the match (best-of-N).
- **Trophies** are once-per-account (idempotent). Stored in `Profile.Data.Trophies` via `TrophyService:AwardTrophy(player, npcId)`.

### Unlocks

NPCs are gated by follower count in their `Config.Npc.<npcId>.UnlockFollowers` field. The dialog service checks this gate and shows either the `QualifiedLine` (has followers) or `GateLine` (has not yet). A player must reach the threshold before the NPC's minigame dialog branch opens.

### What Roblox Provides Natively
- **`HumanoidDescription`** + **`Humanoid:ApplyDescription()`** — This is the core system. A `HumanoidDescription` object stores **everything** about an avatar’s look (body colors, scales, accessories, clothing, animations, etc.). You can create, modify, save, and apply these to any Humanoid (player or NPC).
- **`AvatarEditorService`** — Allows you to build a full in-game avatar editor. It can show catalog items, inventory, try-on previews, save outfits, etc. You still need to build the GUI yourself, but the backend (fetching items, permissions, saving) is handled by Roblox.
- **`Players:CreateHumanoidModelFromUserId()`** or `Players:GetHumanoidDescriptionFromUserId()` — Great for starting from real Roblox avatars.

### Recommended Approach for Your Gym Friends
1. **Build a simple customization UI** (ScreenGui with tabs for Body, Clothing, Accessories, Colors, etc.).
2. Let the player preview changes on a **dummy NPC model** in a viewport or separate area.
3. When the player is happy, save the `HumanoidDescription` (or its serialized properties) to that specific NPC.
4. On NPC spawn, load and apply the saved description.

This is very common in Roblox games (roleplay, dress-up, simulator experiences).

### Storage Options per NPC
- **DataStores** (recommended for persistence across sessions/servers): Store the full `HumanoidDescription` JSON or key properties per NPC ID.
- **Attributes** on the NPC model (simple values only).
- **Value objects** inside the NPC (for quick access).
- For temporary/testing: Just store in a ModuleScript table.

### High-Level Implementation Plan
**1. NPC Data Structure**
```lua
-- In a ModuleScript or DataStore wrapper
local GymNPCs = {
    ["PushUpGuy"] = {
        Name = "PushUpGuy",
        BaseUserId = 123456, -- fallback look
        HumanoidDescriptionData = nil, -- will store JSON or full description
    },
    -- ... other NPCs
}
```

**2. Customization Flow (LocalScript + RemoteEvents)**
- Player clicks “Customize Gym Friend” → ProximityPrompt on NPC or gym menu.
- Server clones a base rig + applies current description for preview.
- Open custom GUI (you build it with Frames, ImageButtons for catalog items, sliders for colors/scales).
- Use `AvatarEditorService:GetInventory()` / `SearchCatalog()` to populate real items the player owns.
- Preview changes live on the dummy.
- On “Save”: Send description to server → validate + save to DataStore + re-apply to the real NPC.

**3. Applying to NPC (Server Script)**
```lua
local function applyLookToNPC(npcModel, humanoidDescription)
    local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:ApplyDescription(humanoidDescription)  -- or ApplyDescriptionAsync
    end
end
```

**4. Saving the Look**
- Convert `HumanoidDescription` to JSON with `:GetNonDefaultProperties()` or manual serialization.
- Store in DataStore keyed by NPC name + player UserId (if per-player customization) or globally.

### Pros & Limitations
- **Fully feasible** and used in many popular games.
- You control the UI style to match your “Superstar Life” influencer theme.
- Players can make their gym friends look like real influencers or friends.
- **Limitation**: Full AvatarEditorService requires player permission prompts (`PromptAllowInventoryReadAccess`). For simpler NPC-only customization, you can skip it and just use manual sliders + your own asset list.

**Plugins that can help during development**:
- Avatar Creator / RigEdit Lite (for quickly making base NPCs in Studio).
- Load Character plugins.

Would you like a more detailed code skeleton (GUI structure + saving/loading `HumanoidDescription` + DataStore example) that you can pass to your coding assistant? Or focus on a minimal version without the full catalog (just colors, basic clothing, and a few accessories)?
---

**Procedural note for agents:** This file is the canonical reference for all minigame NPCs. **Always update the Current NPC Roster table above** when adding, modifying, or removing an NPC from `Config.Npc`. Include the npcId, minigame type, zone, unlock follower threshold, reward calculation (or max reward), and trophy id. This keeps documentation in sync with the source of truth without requiring agents to parse module code.
