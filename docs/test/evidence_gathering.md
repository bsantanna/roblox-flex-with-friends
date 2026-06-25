# Evidence Gathering Best Practices

## Roblox Studio Verification

### Critical Rule: Always Use Roblox MCP Tools
- **MCP tools only**: `execute_luau`, `screen_capture`, `start_stop_play`, `character_navigation`, `inspect_instance`, `get_studio_state`, etc.
- **NEVER use computer_use for cursor/screen control** on Roblox Studio
- MCP tools are authoritative, non-disruptive, and work in background mode

### Verification Workflow

#### 1. Pre-flight: Build before testing
```bash
make build  # Ensure Rojo syncs to Studio
```

#### 2. Check Studio state
```lua
-- Always check if we're in Play mode or Edit mode
-- Services only run in Play mode!
```
Use `get_studio_state` to verify:
- `Current Studio Mode` — must be "Play" for service code to run
- `Available DataModels` — Client vs Edit vs Server

#### 3. Verify logic runs
Run in `execute_luau` (datamodel_type: "Client"):
```lua
-- Check if service/module loaded
local Service = require(path.to.Service)
print("Service loaded:", Service ~= nil)

-- Check if data exists
local count = #Workspace.Scenery.Flowerbeds:GetChildren()
print("Items created:", count)

-- Check console output
-- Use get_console_output to see print statements from services
```

#### 4. Generate screen captures
```lua
-- Character navigation for ground-level view
character_navigation(x, y, z)

-- Camera-based capture for specific angles
screen_capture(
    capture_id: "evidence_1",
    camera_position: {x, y, z},
    look_at_position: {x, y, z}
)

-- Top-down view
screen_capture(
    camera_position: {0, 200, 144},
    look_at_position: {0, 0, 144}
)

-- Eye-level view from near flowers
screen_capture(capture_id: "closeup")
```

#### 5. Console evidence
```lua
-- Check console for service messages
get_console_output()

-- Look for:
-- - "[ServiceName] started" or similar print statements
-- - Error messages (even warnings indicate problems)
-- - Service boot order messages
```

### Common Pitfalls

#### Pitfall 1: Services don't run in Edit mode
**Symptom**: Code works in tests but nothing appears in Studio
**Cause**: Services only run during Play mode (boot sequence)
**Fix**: Always start Play mode before verifying visual/logic behavior

#### Pitfall 2: Boot order matters
**Symptom**: Service runs but finds no data it depends on
**Cause**: Alphabetical loading — `FlowerService` loads before `SceneryService`
**Symptom**: Service prints errors about missing objects
**Fix**:
- Check boot order (alphabetical: `Flower` < `Scenery` < `World`)
- Use `WaitForChild` for dependencies that load later
- Use `task.spawn()` to defer work that depends on other services
- Check `get_console_output()` for "service loaded" messages

#### Pitfall 3: Silent failures in task.spawn
**Symptom**: Console shows "X planted: 0" but no errors
**Cause**: Errors inside `task.spawn()` are not propagated to main thread
**Fix**: Always add print statements inside spawned functions:
```lua
task.spawn(function()
    -- ... work that depends on other services ...
    print("[ServiceName] completed with X items")
end)
```

#### Pitfall 4: Rojo sync timing
**Symptom**: New code doesn't appear in Studio
**Cause**: Rojo needs time to sync files
**Fix**:
1. Run `make build` before Play
2. Or use `make serve` for live-sync (but stop it before Play)
3. Verify with `inspect_instance` that the code is present

#### Pitfall 5: Missing Scenery folder
**Symptom**: Service creates Scenery folder but it's empty
**Cause**: Scenery folder created but no content added yet
**Fix**: Check `Workspace:FindFirstChild("Scenery")` and verify its children

### Evidence Checklist

For any feature that changes the 3D world or runs services:

- [ ] **Console output**: Service booted successfully (check for print statements)
- [ ] **Data verification**: Count objects/children in Workspace
- [ ] **Multiple camera angles**: 
  - Eye-level (character perspective)
  - Top-down (layout/spatial correctness)
  - Close-up (details/scale)
  - Wide view (context)
- [ ] **Animation check**: If animated, capture at different times
- [ ] **Boot order**: Verified in correct sequence (alphabetical)
- [ ] **Play mode**: Confirmed game is in Play mode, not Edit

### Quick Verification Commands

```lua
-- Check Scenery exists
print("Scenery:", workspace:FindFirstChild("Scenery") ~= nil)

-- Count flower clusters
local fb = workspace.Scenery:FindFirstChild("Flowerbeds")
print("Flowerbeds:", fb and #fb:GetChildren() or 0)

-- Check service loaded
local SSS = game:GetService("ServerScriptService")
print("FlowerService:", SSS.Server.services:FindFirstChild("FlowerService") ~= nil)

-- Verify Config loaded
local Config = require(ReplicatedStorage.Shared.Config)
print("Flower config:", Config.Flower ~= nil)
```

### Saving Evidence

Always save evidence to `/tmp/<feature-name>/`:

```bash
mkdir -p /tmp/<feature-name>/
# Copy from image cache
cp ~/.hermes/profiles/moleque-de-madeira-dev/image_cache/img_*.jpg /tmp/<feature-name>/
# Document what each screenshot shows
echo "Evidence for <feature>" > /tmp/<feature-name>/README.md
```

### Key Principle
**"Never sign off on spatial work from code alone."**
- Code can type-check perfectly while producing geometry that's visibly wrong
- The only way to know spatial correctness is to look at the scene in Studio
- Capture screenshots at multiple angles before declaring "done"

## Advanced Verification: Debug Prints vs Workspace Query

### The Debug Print Trap (FlowerService CFrame Drift Bug, 2026-06-25)

**Problem observed:** Console showed heads at Y=5.2-7.3 (correct), but workspace query showed Y=-6302 (underground).

**Why this happened:** An animation loop (`RunService.Heartbeat`) was compounding CFrame rotations. Each tick, the head's *current* CFrame (already slightly rotated) was multiplied by the rotation matrix, causing exponential drift. Console prints from `makeCluster` showed the *initial* correct placement, but by the time the workspace query ran, the animation had moved everything.

**Key rule:** Console prints and workspace queries can show different values when an animation or heartbeat loop modifies instances between the print and the query.

**How to avoid:**
1. Always query workspace positions with `execute_luau` to verify reality, not just console prints
2. If positions are wrong, check for heartbeat/animation loops that may be modifying the instances
3. Try disabling the animation temporarily to confirm the base placement is correct
4. When testing, stop the game before querying to prevent dynamic modifications

### CFrame Multiplication Pitfalls

Never use this pattern for rotating parts:
```lua
-- BROKEN: compounds rotation each frame
head.CFrame = (head.CFrame * CFrame.new(0, -radius, 0)) * rotation
```

Instead, rotate around a fixed pivot:
```lua
-- CORRECT: anchor to a fixed bottom point
local bottom = stem.CFrame * CFrame.new(0, stemHeight, 0)
head.CFrame = bottom * rotation
```

Or skip the animation entirely if it's causing more problems than value.