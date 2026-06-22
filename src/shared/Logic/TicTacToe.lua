--!strict
-- TicTacToe: pure logic for the HomeBuilder's tic-tac-toe minigame — win detection, the NPC's move
-- selection, and best-of-N match resolution. No Roblox globals, so it runs (and is tested) under
-- Lune; the caller injects the random source so tests can be deterministic. The board is a 9-cell
-- array indexed 1..9 (row-major); a cell is "" (empty) or a mark string ("X"/"O").

local TicTacToe = {}

export type RandomInt = (min: number, max: number) -> number
export type Winner = "player" | "opponent"

-- The eight winning lines (row-major indices).
local LINES = {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8, 9 },
	{ 1, 4, 7 },
	{ 2, 5, 8 },
	{ 3, 6, 9 },
	{ 1, 5, 9 },
	{ 3, 5, 7 },
}

-- The mark occupying a completed line, or nil if no line is complete.
function TicTacToe.winner(board: { string }): string?
	for _, line in LINES do
		local a = board[line[1]]
		if a ~= "" and a == board[line[2]] and a == board[line[3]] then
			return a
		end
	end
	return nil
end

-- True when every cell is taken (a draw once winner() is nil).
function TicTacToe.isFull(board: { string }): boolean
	for cell = 1, 9 do
		if board[cell] == "" then
			return false
		end
	end
	return true
end

-- The cell that completes a line for `mark` right now, or nil if there is none.
local function winningCell(board: { string }, mark: string): number?
	for cell = 1, 9 do
		if board[cell] == "" then
			board[cell] = mark
			local found = TicTacToe.winner(board) == mark
			board[cell] = ""
			if found then
				return cell
			end
		end
	end
	return nil
end

-- The NPC's move (medium tactical): take a winning cell if one exists, else block the player's
-- winning cell, else a uniform random open cell. Assumes at least one open cell.
function TicTacToe.aiMove(randomInt: RandomInt, board: { string }, aiMark: string, playerMark: string): number
	local take = winningCell(board, aiMark)
	if take then
		return take
	end
	local block = winningCell(board, playerMark)
	if block then
		return block
	end
	local open = {}
	for cell = 1, 9 do
		if board[cell] == "" then
			table.insert(open, cell)
		end
	end
	return open[randomInt(1, #open)]
end

-- The match winner once a side reaches winsNeeded, else nil (play another game).
function TicTacToe.matchWinner(playerWins: number, opponentWins: number, winsNeeded: number): Winner?
	if playerWins >= winsNeeded then
		return "player"
	end
	if opponentWins >= winsNeeded then
		return "opponent"
	end
	return nil
end

return TicTacToe
