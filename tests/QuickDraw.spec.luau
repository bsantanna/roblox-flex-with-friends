--!strict
local framework = require("./framework")
local QuickDraw = require("../src/shared/Logic/QuickDraw")
local test = framework.test
local expect = framework.expect

test("signalDelay returns minDelay at t01 = 0", function()
	expect(QuickDraw.signalDelay(0, 1.5, 3.5)).toEqual(1.5)
end)

test("signalDelay interpolates between min and max", function()
	expect(QuickDraw.signalDelay(0.5, 1.5, 3.5)).toEqual(2.5)
end)

test("signalDelay approaches maxDelay as t01 nears 1", function()
	expect(QuickDraw.signalDelay(0.75, 2, 6)).toEqual(5)
end)

test("judge wins when the reaction is within the window", function()
	expect(QuickDraw.judge(0.4, 0.8)).toEqual("win")
end)

test("judge wins exactly on the window boundary", function()
	expect(QuickDraw.judge(0.8, 0.8)).toEqual("win")
end)

test("judge is slow past the window", function()
	expect(QuickDraw.judge(0.9, 0.8)).toEqual("slow")
end)
