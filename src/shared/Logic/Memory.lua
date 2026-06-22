--!strict
-- Memory: pure logic for the Nurse's recognition-memory minigame — per-round target/grid
-- generation, input grading, and round/reward progression. No Roblox globals, so it runs (and is
-- tested) under Lune; the caller injects the random source so tests can be deterministic.

local Memory = {}

export type RandomInt = (min: number, max: number) -> number

export type Round = {
	grid: { string }, -- gridSize distinct emojis to show face-up, shuffled
	targetIndices: { number }, -- which grid cells (1-based) hold the flashed targets, ascending
}

-- Fisher-Yates: returns a shuffled copy, leaving the input untouched.
local function shuffled<T>(randomInt: RandomInt, items: { T }): { T }
	local copy = table.clone(items)
	for i = #copy, 2, -1 do
		local j = randomInt(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Builds one round: a grid of `gridSize` distinct emojis (drawn from `emojis`, which must hold at
-- least that many) and `targetCount` of those cells chosen as the flashed targets. The caller
-- flashes grid[i] for each i in targetIndices, then shows the whole grid for recall.
function Memory.buildRound(randomInt: RandomInt, emojis: { string }, targetCount: number, gridSize: number): Round
	local grid = shuffled(randomInt, emojis)
	for i = #grid, gridSize + 1, -1 do
		grid[i] = nil
	end

	local cells = table.create(gridSize)
	for i = 1, gridSize do
		cells[i] = i
	end
	cells = shuffled(randomInt, cells)

	local targetIndices = table.create(targetCount)
	for i = 1, targetCount do
		targetIndices[i] = cells[i]
	end
	table.sort(targetIndices)

	return { grid = grid, targetIndices = targetIndices }
end

-- Targets to memorize in the given round: starts at startTargets, grows by one per round.
function Memory.targetCount(startTargets: number, round: number): number
	return startTargets + round - 1
end

-- Followers paid for clearing the given round.
function Memory.roundReward(baseReward: number, rewardPerRound: number, round: number): number
	return baseReward + (round - 1) * rewardPerRound
end

-- Grades a selection against the targets: true only if the selected cells are exactly the target
-- cells (order-independent, no duplicates, same count).
function Memory.grade(targetIndices: { number }, selectedIndices: { number }): boolean
	if #targetIndices ~= #selectedIndices then
		return false
	end
	local target: { [number]: boolean } = {}
	for _, idx in targetIndices do
		target[idx] = true
	end
	local seen: { [number]: boolean } = {}
	for _, idx in selectedIndices do
		if not target[idx] or seen[idx] then
			return false
		end
		seen[idx] = true
	end
	return true
end

return Memory
