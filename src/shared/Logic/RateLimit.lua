--!strict
-- Pure token-bucket rate limiter, free of Roblox globals so it's Lune-testable. The caller holds
-- the bucket state per (player, remote) and a monotonic clock; `consume` refills based on elapsed
-- time, then spends one token if available. burst caps the bucket (max instantaneous calls);
-- ratePerSec is the sustained refill. Used by Util/Throttle to gate client->server remotes.

local RateLimit = {}

export type Bucket = { tokens: number, updated: number }

-- Refill the bucket for the elapsed time (capped at burst), then try to spend one token.
-- Returns (allowed, newBucket). Pass nil on the first call for a full bucket.
function RateLimit.consume(bucket: Bucket?, now: number, ratePerSec: number, burst: number): (boolean, Bucket)
	local tokens = if bucket then bucket.tokens else burst
	local updated = if bucket then bucket.updated else now

	local elapsed = math.max(0, now - updated)
	tokens = math.min(burst, tokens + elapsed * ratePerSec)

	local allowed = tokens >= 1
	if allowed then
		tokens -= 1
	end

	return allowed, { tokens = tokens, updated = now }
end

return RateLimit
