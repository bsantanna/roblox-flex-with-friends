--!strict
local framework = require("./framework")
local Decay = require("../src/shared/Logic/Decay")
local test = framework.test
local expect = framework.expect

local DAY = 86400

test("decays nothing when disabled or for a brand-new profile", function()
	expect(Decay.compute(false, 10, 50, 1, 1 + DAY * 5)).toEqual(0)
	expect(Decay.compute(true, 10, 50, 0, DAY * 5)).toEqual(0)
end)

test("decays nothing when no time has elapsed", function()
	expect(Decay.compute(true, 10, 50, 1000, 1000)).toEqual(0)
end)

test("prorates per day and caps at maxLoss", function()
	expect(Decay.compute(true, 10, 50, 1, 1 + DAY * 3)).toEqual(30)
	expect(Decay.compute(true, 10, 50, 1, 1 + DAY * 100)).toEqual(50)
end)
