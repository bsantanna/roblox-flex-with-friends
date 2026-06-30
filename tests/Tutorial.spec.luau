--!strict
local framework = require("./framework")
local Tutorial = require("../src/shared/Logic/Tutorial")
local test = framework.test
local expect = framework.expect

test("a brand-new player is told to open the phone", function()
	local step = Tutorial.step({ phoneOpened = false, photosTaken = 0 })
	expect(step).toEqual("open_phone")
	expect(Tutorial.hint(step) ~= nil).toBeTrue()
end)

test("after opening the phone the next step is taking a photo", function()
	local step = Tutorial.step({ phoneOpened = true, photosTaken = 0 })
	expect(step).toEqual("take_photo")
	expect(Tutorial.hint(step) ~= nil).toBeTrue()
end)

test("a player who has ever taken a photo is done (no hint)", function()
	expect(Tutorial.step({ phoneOpened = false, photosTaken = 1 })).toEqual("done")
	expect(Tutorial.step({ phoneOpened = true, photosTaken = 5 })).toEqual("done")
	expect(Tutorial.hint("done")).toEqual(nil)
end)
