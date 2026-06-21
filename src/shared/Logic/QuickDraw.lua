--!strict
-- QuickDraw: pure logic for the Forest sage's reaction-duel minigame. After a random suspense delay
-- the NPC "draws"; the player must react within a window. No Roblox globals, so it runs (and is
-- tested) under Lune; the caller injects the random source so tests can be deterministic.

local QuickDraw = {}

export type Outcome = "win" | "slow"

-- The suspense before the DRAW signal: interpolates [minDelay, maxDelay] by t01 (a value in [0, 1)).
-- The caller supplies t01 (e.g. Random:NextNumber()), keeping this deterministic for tests.
function QuickDraw.signalDelay(t01: number, minDelay: number, maxDelay: number): number
	return minDelay + t01 * (maxDelay - minDelay)
end

-- Judges a reaction: pressing within `window` seconds of the DRAW signal wins the round, else "slow".
-- (A press *before* the signal is a false start — the server detects that by game phase, not here.)
function QuickDraw.judge(elapsed: number, window: number): Outcome
	return if elapsed <= window then "win" else "slow"
end

return QuickDraw
