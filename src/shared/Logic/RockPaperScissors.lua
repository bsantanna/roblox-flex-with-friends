--!strict
-- RockPaperScissors: pure logic for the Cowboy luck minigame — opponent move selection and
-- round/match resolution. No Roblox globals, so it runs (and is tested) under Lune; the caller
-- injects the random source so tests can be deterministic. Choice labels ("Rock"/"Paper"/
-- "Scissors") are canonical here; Config maps them to emojis for display.

local RockPaperScissors = {}

export type RandomInt = (min: number, max: number) -> number
export type Outcome = "win" | "lose" | "tie" -- from the player's point of view
export type Winner = "player" | "opponent"

-- What each choice beats.
local BEATS: { [string]: string } = {
	Rock = "Scissors",
	Scissors = "Paper",
	Paper = "Rock",
}

-- The opponent's move: a uniform pick from `choices`.
function RockPaperScissors.pick(randomInt: RandomInt, choices: { string }): string
	return choices[randomInt(1, #choices)]
end

-- Resolves one round from the player's point of view.
function RockPaperScissors.resolve(playerChoice: string, opponentChoice: string): Outcome
	if playerChoice == opponentChoice then
		return "tie"
	end
	return if BEATS[playerChoice] == opponentChoice then "win" else "lose"
end

-- The match winner once a side reaches winsNeeded, else nil (play another round).
function RockPaperScissors.matchWinner(playerWins: number, opponentWins: number, winsNeeded: number): Winner?
	if playerWins >= winsNeeded then
		return "player"
	end
	if opponentWins >= winsNeeded then
		return "opponent"
	end
	return nil
end

return RockPaperScissors
