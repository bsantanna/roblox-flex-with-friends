# Feature: City Flowers

**Status:** Discovery
**Created:** 2026-06-26

## Summary
Add flowers to all green areas in the city — the grass squares (houses' gardens), the ParkCell, and any other green/grass terrain the city uses. Flowers are small decorative primitive clusters placed procedurally across grass surfaces.

## Questions for User
- Flower placement: random scatter with density tunable in Config?
- Visual style: simple (sphere+cone primitive clusters), or more detailed?
- Variations: one flower type or multiple (different colors, sizes)?
- Should flowers appear in Airport/Beach grass too, or just the Home city area?
- Any specific placement rules (not on roads, not in driveways, not overlapping houses)?

# Lessons Learned

## FlowerService CFrame Drift Bug (2026-06-25)

### Problem
Heads were placed at the correct Y position (Y=5.2-7.3) according to debug prints, but the actual workspace showed them at Y=-6302 (deep underground). The code was correct — the animation loop was destroying the positions.

### Root Cause
The animation function used CFrame multiplication to rotate heads:
```lua
local headBottom = head.CFrame * CFrame.new(0, -headSize/2, 0)
head.CFrame = headBottom * angle
```

Multiplying rotated CFrames compounds errors with each heartbeat tick. The rotation was not anchored to a stable point — it used the head's *current* CFrame (which was already slightly rotated) to compute the next position, causing exponential drift.

Attempts to fix it:
1. **Computed bottom from position** → still drifted (Position itself was affected by prior rotation)
2. **Computed from stem base** → same problem (the angle was being compounded)
3. **Commented out animation entirely** → confirmed placement was correct

### Fix
Removed the animation entirely for now. The flower service now only places heads statically.

### Key Lessons

#### 1. Debug prints ≠ workspace reality
Console output showed heads at Y=5.2-7.3 (correct placement). Workspace query showed Y=-6302 (broken). These can differ when:
- An animation loop modifies the instance after creation
- The module is cached/old version running (Rojo sync issues)
- Console prints from a different source than the live module

**Rule:** Always query the actual workspace positions with `execute_luau` to confirm reality, not just debug prints.

#### 2. CFrame multiplication drift is silent and exponential
When you do `head.CFrame = (head.CFrame * offset) * rotation`, the head's CFrame from the *previous frame* includes the previous rotation. Multiplying again compounds it. This is not a Lua error — Luau LSP won't catch it. It's a math problem that only shows up after many iterations.

**Safe pattern:** If you need rotating a head around its bottom, store the bottom as a *fixed* Vector3 (not a CFrame) and recompute:
```lua
local bottom = stem.CFrame * CFrame.new(0, stemHeight, 0) -- FIXED, recomputed each frame
head.CFrame = bottom * rotation
```

But for now: **no animation is better than broken animation.**

#### 3. Rojo caching can cause stale code
The flower module was running an old version (no `base *` fix) even after patching the file. Rojo caches modules. Restarting Rojo (`make serve` in IDE) is required for live sync.

**Never kill Rojo.** User runs it in IDE. Agent must notify user to restart.

#### 4. Animation in a static scene is optional
The flowers don't *need* animation to be fun or visible. Simpler is better. If an animation is needed, it must be mathematically sound (rotate around a fixed pivot, not compound rotations).