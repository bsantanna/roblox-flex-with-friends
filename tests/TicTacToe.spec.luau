--!strict
local framework = require("./framework")
local TicTacToe = require("../src/shared/Logic/TicTacToe")
local test = framework.test
local expect = framework.expect

local E = "" -- empty cell

-- Always returns the low end of the range; makes the random branch deterministic.
local alwaysMin: TicTacToe.RandomInt = function(min: number, _max: number)
	return min
end

test("winner detects a row", function()
	expect(TicTacToe.winner({ "X", "X", "X", E, "O", E, "O", E, E })).toEqual("X")
end)

test("winner detects a column", function()
	expect(TicTacToe.winner({ "O", "X", E, "O", "X", E, "O", E, E })).toEqual("O")
end)

test("winner detects a diagonal", function()
	expect(TicTacToe.winner({ "X", "O", E, "O", "X", E, E, E, "X" })).toEqual("X")
end)

test("winner is nil with no completed line", function()
	expect(TicTacToe.winner({ "X", "O", "X", E, E, E, E, E, E })).toEqual(nil)
end)

test("isFull is false with an open cell and true when full", function()
	expect(TicTacToe.isFull({ "X", "O", "X", "X", "O", "O", "O", "X", E })).toBeFalse()
	expect(TicTacToe.isFull({ "X", "O", "X", "X", "O", "O", "O", "X", "X" })).toBeTrue()
end)

test("aiMove takes its own winning cell", function()
	-- O has cells 1 and 2; cell 3 completes the top row.
	expect(TicTacToe.aiMove(alwaysMin, { "O", "O", E, "X", "X", E, E, E, E }, "O", "X")).toEqual(3)
end)

test("aiMove blocks the player's winning cell when it can't win itself", function()
	-- X threatens the top row (1,2); O must block at 3.
	expect(TicTacToe.aiMove(alwaysMin, { "X", "X", E, "O", E, E, E, E, E }, "O", "X")).toEqual(3)
end)

test("aiMove prefers its own win over blocking", function()
	-- X threatens 1,2,_ but O threatens 4,5,_ — O should win at 6, not block at 3.
	expect(TicTacToe.aiMove(alwaysMin, { "X", "X", E, "O", "O", E, E, E, E }, "O", "X")).toEqual(6)
end)

test("aiMove returns an open cell otherwise", function()
	-- No immediate win/block; alwaysMin picks the first open cell (index 2).
	expect(TicTacToe.aiMove(alwaysMin, { "X", E, E, E, E, E, E, E, E }, "O", "X")).toEqual(2)
end)

test("matchWinner resolves once a side reaches winsNeeded", function()
	expect(TicTacToe.matchWinner(2, 0, 2)).toEqual("player")
	expect(TicTacToe.matchWinner(1, 2, 2)).toEqual("opponent")
	expect(TicTacToe.matchWinner(1, 1, 2)).toEqual(nil)
end)
