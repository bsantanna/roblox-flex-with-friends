--!strict
local framework = require("./framework")
local Routine = require("../src/shared/Logic/Routine")
local test = framework.test
local expect = framework.expect

local CFG: Routine.Config = {
	exercise = { min = 240, max = 360 },
	rest = { min = 200, max = 300 },
}

-- rng stubs that always return a band edge, so durations are deterministic in tests.
local function rngMin(min: number, _max: number): number
	return min
end
local function rngMax(_min: number, max: number): number
	return max
end

test("the first spell is exercising, drawn from the exercise band", function()
	local state, duration = Routine.first(CFG, rngMin)
	expect(state).toEqual("exercise")
	expect(duration).toEqual(240)
end)

test("exercise is followed by a break", function()
	local state = Routine.next("exercise", CFG, rngMin)
	expect(state).toEqual("break")
end)

test("a break is followed by exercise", function()
	local state = Routine.next("break", CFG, rngMin)
	expect(state).toEqual("exercise")
end)

test("each spell's duration is drawn from that state's band", function()
	local _, restDuration = Routine.next("exercise", CFG, rngMax)
	expect(restDuration).toEqual(300)
	local _, exerciseDuration = Routine.next("break", CFG, rngMin)
	expect(exerciseDuration).toEqual(240)
end)
