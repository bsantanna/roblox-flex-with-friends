--!strict
local framework = require("./framework")
local RateLimit = require("../src/shared/Logic/RateLimit")
local test = framework.test
local expect = framework.expect

test("first call starts from a full bucket and is allowed", function()
	local allowed, bucket = RateLimit.consume(nil, 0, 1, 3)
	expect(allowed).toBeTrue()
	expect(bucket.tokens).toEqual(2) -- 3 burst - 1 spent
end)

test("a burst is allowed up to the cap, then blocked", function()
	local now = 0
	local bucket = nil
	local results: { boolean } = {}
	for _ = 1, 4 do
		local allowed
		allowed, bucket = RateLimit.consume(bucket, now, 1, 3)
		table.insert(results, allowed)
	end
	-- 3 tokens available instantly, 4th blocked (no time elapsed to refill)
	expect(results[1]).toBeTrue()
	expect(results[2]).toBeTrue()
	expect(results[3]).toBeTrue()
	expect(results[4]).toBeFalse()
end)

test("tokens refill over elapsed time at ratePerSec", function()
	-- drain the bucket
	local _, bucket = RateLimit.consume(nil, 0, 2, 1) -- burst 1, now empty
	local blocked, b2 = RateLimit.consume(bucket, 0, 2, 1)
	expect(blocked).toBeFalse()

	-- 0.5s later at 2/sec => 1 token refilled => allowed again
	local allowed = RateLimit.consume(b2, 0.5, 2, 1)
	expect(allowed).toBeTrue()
end)

test("refill never exceeds burst", function()
	local _, bucket = RateLimit.consume(nil, 0, 100, 2) -- spend 1 of 2
	-- a long time passes; tokens cap at burst, not unbounded
	local _, b2 = RateLimit.consume(bucket, 1000, 100, 2)
	expect(b2.tokens).toEqual(1) -- capped at 2, minus the 1 just spent
end)
