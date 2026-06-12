--!strict
local framework = require("./framework")
local SimonSays = require("../src/shared/Logic/SimonSays")
local test = framework.test
local expect = framework.expect

local ARROWS = { "Left", "Up", "Right", "Down" }

-- Returns each value from `values` in order, ignoring the requested range.
local function fixedRandom(values: { number }): SimonSays.RandomInt
	local i = 0
	return function(_min: number, _max: number)
		i += 1
		return values[i]
	end
end

test("generate returns the requested length", function()
	local sequence = SimonSays.generate(fixedRandom({ 1, 2, 3 }), ARROWS, 3)
	expect(#sequence).toEqual(3)
end)

test("generate maps random picks to arrows in order", function()
	local sequence = SimonSays.generate(fixedRandom({ 4, 1, 2 }), ARROWS, 3)
	expect(sequence[1]).toEqual("Down")
	expect(sequence[2]).toEqual("Left")
	expect(sequence[3]).toEqual("Up")
end)

test("sequenceLength grows by one per round", function()
	expect(SimonSays.sequenceLength(3, 1)).toEqual(3)
	expect(SimonSays.sequenceLength(3, 2)).toEqual(4)
	expect(SimonSays.sequenceLength(3, 5)).toEqual(7)
end)

test("roundReward scales with the round number", function()
	expect(SimonSays.roundReward(30, 10, 1)).toEqual(30)
	expect(SimonSays.roundReward(30, 10, 2)).toEqual(40)
	expect(SimonSays.roundReward(30, 10, 5)).toEqual(70)
end)

test("grade returns wrong on a mismatch", function()
	expect(SimonSays.grade({ "Left", "Up" }, 1, "Up")).toEqual("wrong")
end)

test("grade returns correct for a matching non-final input", function()
	expect(SimonSays.grade({ "Left", "Up" }, 1, "Left")).toEqual("correct")
end)

test("grade returns complete for the final matching input", function()
	expect(SimonSays.grade({ "Left", "Up" }, 2, "Up")).toEqual("complete")
end)

test("grade returns wrong past the end of the sequence", function()
	expect(SimonSays.grade({ "Left" }, 2, "Left")).toEqual("wrong")
end)
