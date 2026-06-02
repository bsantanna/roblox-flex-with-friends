--!strict
-- Pure offline-decay math, free of Roblox globals so it is unit-testable under Lune.

local Decay = {}

-- Followers lost for being away: prorated per day and capped. Returns 0 when disabled, for a
-- brand-new profile (lastSeen <= 0), or when no time has elapsed.
function Decay.compute(enabled: boolean, perDay: number, maxLoss: number, lastSeen: number, now: number): number
	if not enabled or lastSeen <= 0 then
		return 0
	end
	local elapsed = now - lastSeen
	if elapsed <= 0 then
		return 0
	end
	return math.min(maxLoss, math.floor((elapsed / 86400) * perDay))
end

return Decay
