--!strict
-- Pure follower-balance math, free of Roblox globals so it is unit-testable under Lune.
-- FollowerService is the only writer; it routes its arithmetic through here.

local Followers = {}

-- The stored balance is always a non-negative integer.
function Followers.clamp(value: number): number
	return math.max(0, math.floor(value))
end

-- Awards only add; a negative amount is ignored. Result is clamped.
function Followers.afterAward(current: number, amount: number): number
	return Followers.clamp(current + math.max(0, amount))
end

-- Deducts only subtract; a negative amount is ignored. Result never goes below zero.
function Followers.afterDeduct(current: number, amount: number): number
	return Followers.clamp(current - math.max(0, amount))
end

return Followers
