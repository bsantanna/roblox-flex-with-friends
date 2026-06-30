--!strict
-- Per-player remote throttle: a thin server-side wrapper over the pure Logic/RateLimit token bucket.
-- Throttle.perPlayer(ratePerSec, burst) returns a gate(player) -> boolean; a remote handler calls it
-- first and ignores the request when it returns false. Buckets are kept per player and dropped when
-- the player leaves. Used to rate-limit client->server remotes (defense-in-depth against spam).

local Players = game:GetService("Players")

local RateLimit = require(script.Parent.Parent.Logic.RateLimit)

local Throttle = {}

-- Build an independent gate (one bucket set per call site). ratePerSec is the sustained allowance;
-- burst is the most calls tolerated back-to-back before throttling kicks in.
function Throttle.perPlayer(ratePerSec: number, burst: number): (Player) -> boolean
	local buckets: { [Player]: RateLimit.Bucket } = {}

	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)

	return function(player: Player): boolean
		local allowed, bucket = RateLimit.consume(buckets[player], os.clock(), ratePerSec, burst)
		buckets[player] = bucket
		return allowed
	end
end

return Throttle
