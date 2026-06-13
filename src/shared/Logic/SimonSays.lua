--!strict
-- SimonSays: pure logic for the Personal Trainer pose-memory minigame — sequence generation,
-- input grading, and round/reward progression. No Roblox globals, so it runs (and is tested)
-- under Lune; the caller injects the random source so tests can be deterministic.

local SimonSays = {}

export type RandomInt = (min: number, max: number) -> number
export type Grade = "wrong" | "correct" | "complete"

-- The arrow sequence for one round: `length` picks from `arrows`.
function SimonSays.generate(randomInt: RandomInt, arrows: { string }, length: number): { string }
	local sequence = table.create(length)
	for i = 1, length do
		sequence[i] = arrows[randomInt(1, #arrows)]
	end
	return sequence
end

-- Arrows in the given round's sequence: starts at startLength, grows by one per round.
function SimonSays.sequenceLength(startLength: number, round: number): number
	return startLength + round - 1
end

-- Followers paid for clearing the given round.
function SimonSays.roundReward(baseReward: number, rewardPerRound: number, round: number): number
	return baseReward + (round - 1) * rewardPerRound
end

-- Grades one input against the expected arrow at inputIndex: "wrong" ends the game,
-- "correct" awaits the next input, "complete" means the round's last arrow matched.
function SimonSays.grade(sequence: { string }, inputIndex: number, arrow: string): Grade
	if sequence[inputIndex] ~= arrow then
		return "wrong"
	end
	return if inputIndex == #sequence then "complete" else "correct"
end

return SimonSays
