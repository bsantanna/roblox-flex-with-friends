--!strict
local framework = require("./framework")
local Memory = require("../src/shared/Logic/Memory")
local test = framework.test
local expect = framework.expect

local EMOJIS = { "A", "B", "C", "D", "E", "F", "G", "H" }

-- Always returns the low end of the range; makes buildRound deterministic without hand-tracing.
local alwaysMin: Memory.RandomInt = function(min: number, _max: number)
	return min
end

test("targetCount grows by one per round", function()
	expect(Memory.targetCount(4, 1)).toEqual(4)
	expect(Memory.targetCount(4, 2)).toEqual(5)
	expect(Memory.targetCount(4, 3)).toEqual(6)
end)

test("roundReward adds rewardPerRound for each round beyond the first", function()
	expect(Memory.roundReward(50, 25, 1)).toEqual(50)
	expect(Memory.roundReward(50, 25, 2)).toEqual(75)
	expect(Memory.roundReward(50, 25, 3)).toEqual(100)
end)

test("buildRound trims the grid to gridSize", function()
	local round = Memory.buildRound(alwaysMin, EMOJIS, 2, 4)
	expect(#round.grid).toEqual(4)
end)

test("buildRound picks targetCount distinct in-range cells, ascending", function()
	local round = Memory.buildRound(alwaysMin, EMOJIS, 3, 6)
	expect(#round.targetIndices).toEqual(3)
	local prev = 0
	local ok = true
	for _, idx in round.targetIndices do
		if idx <= prev or idx < 1 or idx > 6 then
			ok = false
		end
		prev = idx
	end
	expect(ok).toBeTrue()
end)

test("buildRound keeps grid emojis distinct", function()
	local round = Memory.buildRound(alwaysMin, EMOJIS, 2, 5)
	local seen: { [string]: boolean } = {}
	local distinct = true
	for _, emoji in round.grid do
		if seen[emoji] then
			distinct = false
		end
		seen[emoji] = true
	end
	expect(distinct).toBeTrue()
end)

test("grade accepts the exact target set regardless of order", function()
	expect(Memory.grade({ 2, 5, 9 }, { 9, 2, 5 })).toBeTrue()
end)

test("grade rejects a wrong cell", function()
	expect(Memory.grade({ 2, 5, 9 }, { 2, 5, 8 })).toBeFalse()
end)

test("grade rejects the wrong count", function()
	expect(Memory.grade({ 2, 5, 9 }, { 2, 5 })).toBeFalse()
end)

test("grade rejects duplicate selections", function()
	expect(Memory.grade({ 2, 5, 9 }, { 2, 5, 5 })).toBeFalse()
end)
