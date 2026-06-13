**Plan for Gym NPC Group – Simple Looping Workout Behaviors**

### Goal
Create **5+ distinct NPCs** in the gym area of your experience. They perform continuous, realistic workout animations (no player interaction or mini-games). They should look like active gym-goers, loop their routines naturally, and enhance the immersive "influencer fitness" atmosphere. NPCs resemble generic avatars (or use random Roblox avatars for variety).

### High-Level Architecture
1. **NPC Spawner Script** (Server Script in ServerScriptService or inside the Gym folder)
   - One central script that creates and configures all NPCs on server start / when players join.
   - Store NPC data in a table (position, animations, cycle timings).

2. **NPC Model Template**
   - Use R15 rigs.
   - Either:
     - `Players:CreateHumanoidModelFromUserId(randomUserId)` for varied looks, or
     - Pre-built custom rigs in ReplicatedStorage that you clone.

3. **Animation System**
   - Pre-load Animation objects (in ReplicatedStorage).
   - Each NPC has a **cycle** of 1–3 animations with idle periods.
   - Use `Humanoid:LoadAnimation()` + `track:Play()` with proper `AnimationPriority`.

4. **Behavior Loop**
   - Simple `while true do` or `task.spawn` per NPC with `task.wait()` for timing.
   - No Pathfinding needed for static gym stations (they stay in place).

### Required Animations (Asset IDs)
You’ll need to upload or find these via Roblox Animation Editor / Toolbox:

- Push-ups
- Squats
- Bench Press / Dumbbell Lift
- Treadmill Run (looping run animation + slight bob)
- Cycling (bicycle motion)
- Optional: Jumping jacks, planks, burpees, drinking water (break animation)

**Tip**: Search Roblox Library for “gym animation pack” or create short ones yourself.

---

### Detailed Implementation Plan

#### 1. Folder Structure in Studio
```
Workspace
└── GymArea
    ├── NPCSpawner (Script)
    ├── Positions (Folder with Attachment/Part markers)
    └── ReplicatedStorage
        └── Animations (Folder)
            ├── PushUpAnim
            ├── SquatAnim
            ├── WeightLiftAnim
            ├── TreadmillRunAnim
            └── BikeAnim
```

#### 2. Central NPC Spawner Script (Server)
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ANIMATIONS = {
    PushUp = ReplicatedStorage.Animations.PushUpAnim,
    Squat = ReplicatedStorage.Animations.SquatAnim,
    WeightLift = ReplicatedStorage.Animations.WeightLiftAnim,
    Run = ReplicatedStorage.Animations.TreadmillRunAnim,
    Bike = ReplicatedStorage.Animations.BikeAnim,
}

local npcConfigs = {
    {
        name = "PushUpGuy",
        userId = 123456, -- or random
        position = Vector3.new(x1, y1, z1),
        activities = {"PushUp", "Squat"},
        cycleTime = 8, -- seconds per activity
    },
    {
        name = "WeightLifter",
        userId = 654321,
        position = Vector3.new(x2, y2, z2),
        activities = {"WeightLift"},
        cycleTime = 6,
    },
    {
        name = "TreadmillRunner",
        userId = 111222,
        position = Vector3.new(x3, y3, z3),
        activities = {"Run"},
        cycleTime = 12,
    },
    {
        name = "BikeGirl",
        userId = 333444,
        position = Vector3.new(x4, y4, z4),
        activities = {"Bike"},
        cycleTime = 10,
    },
    {
        name = "AllRounder",
        userId = 555666,
        position = Vector3.new(x5, y5, z5),
        activities = {"Squat", "PushUp", "WeightLift"},
        cycleTime = 7,
    },
    -- Add more as needed
}

local function createNPC(config)
    local model = Players:CreateHumanoidModelFromUserId(config.userId)
    model.Name = config.name
    model.Parent = workspace.GymArea
    
    local humanoid = model:WaitForChild("Humanoid")
    humanoid.AutomaticScalingEnabled = false -- Optional for consistency
    
    -- Move to position + face forward
    model:MoveTo(config.position)
    model:PivotTo(CFrame.new(config.position) * CFrame.Angles(0, math.rad(180), 0)) -- adjust rotation
    
    -- Start behavior loop
    task.spawn(function()
        while model.Parent do
            for _, activity in config.activities do
                local animObj = ANIMATIONS[activity]
                if animObj then
                    local track = humanoid:LoadAnimation(animObj)
                    track.Priority = Enum.AnimationPriority.Action
                    track:Play()
                    
                    task.wait(config.cycleTime)
                    track:Stop()
                end
            end
            task.wait(2) -- short break between cycles
        end
    end)
    
    return model
end

-- Spawn all NPCs
for _, cfg in npcConfigs do
    createNPC(cfg)
end
```

#### 3. Animation Loading Best Practices
- Put Animation instances in ReplicatedStorage with correct `AnimationId = "rbxassetid://YOUR_ID"`.
- For better performance, consider pre-loading tracks or using an Animator object.

#### 4. Enhancements (Add Later)
- **Random idle breaks**: Occasionally play a “drink water” or “wipe sweat” animation.
- **Sound effects**: Add looping gym sounds (grunts, treadmill noise) attached to each NPC.
- **Visual polish**:
  - Attach workout equipment (dumbbells, treadmill models) as welded parts.
  - Particle effects (sweat drops).
  - Simple name tags above heads (“Gym Bro”, “Fitness Influencer”).
- **Performance**: Limit to 8–12 NPCs max per server. Use `CollectionService` for easier management.
- **Variation**: Add slight random timing offsets so they don’t sync perfectly.

#### 5. Testing & Debugging Checklist
- Test on server start: All NPCs appear and animate.
- Animations loop smoothly without T-pose.
- NPCs don’t collide with each other (CollisionGroup).
- Mobile performance is acceptable.
- NPCs stay in place (no drifting).

---

**Next Steps for You / Coding Assistant**
1. Create the 5 Animation objects in ReplicatedStorage with real Asset IDs.
2. Place Position Parts in the gym and copy their `Position` values into the config table.
3. Paste and run the spawner script.
4. Iterate: Add more NPCs, vary cycle times, add equipment props.

This system is clean, scalable, and easy to extend (e.g., later add interaction with ProximityPrompts for mini-games). It reuses the same animation techniques from the Trainer NPC you already built.

Would you like me to expand any part (full script with more polish, equipment attachment code, random avatar pool, or CollectionService version)? Just tell your coding assistant to ask me for refinements.