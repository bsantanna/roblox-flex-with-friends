--!strict
local framework = require("./framework")
local Followers = require("../src/shared/Logic/Followers")
local test = framework.test
local expect = framework.expect

test("clamp floors and never goes below zero", function()
	expect(Followers.clamp(-5)).toEqual(0)
	expect(Followers.clamp(3.9)).toEqual(3)
end)

test("award adds and ignores negative amounts", function()
	expect(Followers.afterAward(100, 50)).toEqual(150)
	expect(Followers.afterAward(100, -50)).toEqual(100)
end)

test("deduct subtracts but never below zero", function()
	expect(Followers.afterDeduct(100, 40)).toEqual(60)
	expect(Followers.afterDeduct(30, 100)).toEqual(0)
end)
