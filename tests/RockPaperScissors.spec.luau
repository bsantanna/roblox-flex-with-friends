--!strict
local framework = require("./framework")
local RPS = require("../src/shared/Logic/RockPaperScissors")
local test = framework.test
local expect = framework.expect

local CHOICES = { "Rock", "Paper", "Scissors" }

-- Always returns the same index, ignoring the requested range.
local function fixed(value: number): RPS.RandomInt
	return function(_min: number, _max: number)
		return value
	end
end

test("pick maps the random index to a choice", function()
	expect(RPS.pick(fixed(1), CHOICES)).toEqual("Rock")
	expect(RPS.pick(fixed(2), CHOICES)).toEqual("Paper")
	expect(RPS.pick(fixed(3), CHOICES)).toEqual("Scissors")
end)

test("resolve returns tie on equal choices", function()
	expect(RPS.resolve("Rock", "Rock")).toEqual("tie")
	expect(RPS.resolve("Paper", "Paper")).toEqual("tie")
	expect(RPS.resolve("Scissors", "Scissors")).toEqual("tie")
end)

test("resolve returns win when the player's choice beats the opponent", function()
	expect(RPS.resolve("Rock", "Scissors")).toEqual("win")
	expect(RPS.resolve("Scissors", "Paper")).toEqual("win")
	expect(RPS.resolve("Paper", "Rock")).toEqual("win")
end)

test("resolve returns lose when the player's choice is beaten", function()
	expect(RPS.resolve("Scissors", "Rock")).toEqual("lose")
	expect(RPS.resolve("Paper", "Scissors")).toEqual("lose")
	expect(RPS.resolve("Rock", "Paper")).toEqual("lose")
end)

test("matchWinner returns nil until a side reaches winsNeeded", function()
	expect(RPS.matchWinner(0, 0, 2)).toEqual(nil)
	expect(RPS.matchWinner(1, 1, 2)).toEqual(nil)
end)

test("matchWinner names the side that reached winsNeeded", function()
	expect(RPS.matchWinner(2, 0, 2)).toEqual("player")
	expect(RPS.matchWinner(1, 2, 2)).toEqual("opponent")
end)
