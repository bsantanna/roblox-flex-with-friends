--!strict
local framework = require("./framework")
local KeySequence = require("../src/shared/Logic/KeySequence")
local test = framework.test
local expect = framework.expect

local KONAMI = { "Up", "Up", "Down", "Down", "Left", "Right", "Left", "Right", "B", "A" }

local function feed(keys: { string }): (boolean, { string })
	local matched = false
	local history: { string } = {}
	for _, key in keys do
		matched, history = KeySequence.push(history, key, KONAMI)
	end
	return matched, history
end

test("matches the full sequence", function()
	local matched = feed(KONAMI)
	expect(matched).toBeTrue()
end)

test("does not match a partial or wrong-order sequence", function()
	expect((feed({ "Up", "Up", "Down" }))).toBeFalse()
	expect((feed({ "Up", "Up", "Down", "Down", "Right", "Left", "Right", "Left", "B", "A" }))).toBeFalse()
end)

test("matches when the sequence follows unrelated keys", function()
	local keys = { "W", "A", "S", "D" }
	for _, key in KONAMI do
		table.insert(keys, key)
	end
	expect((feed(keys))).toBeTrue()
end)

test("recovers after a mistake mid-sequence", function()
	local keys = { "Up", "Up", "Down", "X" }
	for _, key in KONAMI do
		table.insert(keys, key)
	end
	expect((feed(keys))).toBeTrue()
end)

test("trims the window and does not mutate the input history", function()
	local history = { "Up" }
	local _, newHistory = KeySequence.push(history, "Down", KONAMI)
	expect(#history).toEqual(1)
	expect(#newHistory).toEqual(2)

	local _, window = feed({ "X", "Y" })
	local matched, full = KeySequence.push(window, "Z", KONAMI)
	expect(matched).toBeFalse()
	expect(#full <= #KONAMI).toBeTrue()
end)
