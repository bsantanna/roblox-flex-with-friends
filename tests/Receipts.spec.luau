--!strict
local framework = require("./framework")
local Receipts = require("../src/shared/Logic/Receipts")
local test = framework.test
local expect = framework.expect

test("a fresh purchaseId should be granted, a recorded one should not", function()
	local cache: { string } = {}
	expect(Receipts.shouldGrant(cache, "p1")).toBeTrue()

	Receipts.record(cache, "p1", 100)
	expect(Receipts.shouldGrant(cache, "p1")).toBeFalse()
	-- a different id is still grantable
	expect(Receipts.shouldGrant(cache, "p2")).toBeTrue()
end)

test("record evicts oldest ids first to stay within maxSize", function()
	local cache: { string } = {}
	Receipts.record(cache, "a", 2)
	Receipts.record(cache, "b", 2)
	Receipts.record(cache, "c", 2) -- evicts "a"

	expect(#cache).toEqual(2)
	expect(table.find(cache, "a") == nil).toBeTrue()
	expect(cache[1]).toEqual("b")
	expect(cache[2]).toEqual("c")
end)

test("isSaved reflects presence in the persisted cache", function()
	expect(Receipts.isSaved(nil, "p1")).toBeFalse()
	expect(Receipts.isSaved({}, "p1")).toBeFalse()
	expect(Receipts.isSaved({ "p1" }, "p1")).toBeTrue()
	expect(Receipts.isSaved({ "p0" }, "p1")).toBeFalse()
end)

test("grant-once flow: record after granting blocks a retry", function()
	local cache: { string } = {}
	local grants = 0
	-- first delivery
	if Receipts.shouldGrant(cache, "px") then
		grants += 1
		Receipts.record(cache, "px", 100)
	end
	-- retry for the same purchase (e.g. player rejoined before the save confirmed)
	if Receipts.shouldGrant(cache, "px") then
		grants += 1
		Receipts.record(cache, "px", 100)
	end
	expect(grants).toEqual(1)
end)
