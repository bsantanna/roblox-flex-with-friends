--!strict
local framework = require("./framework")
local Dialog = require("../src/shared/Logic/Dialog")
local test = framework.test
local expect = framework.expect

local DEF: Dialog.Def = {
	lines = { "Hey!", "I coach champions." },
	qualifiedLine = "Ready to train?",
	gateLine = "Come back with 100 followers.",
	qualifiedChoices = { "Train", "Maybe later" },
	gateChoices = { "Got it" },
}

test("counts every plain line plus the branch line", function()
	expect(Dialog.total(DEF)).toEqual(3)
end)

test("plain lines advance in order without choices", function()
	local step1 = Dialog.step(DEF, true, 1)
	assert(step1, "step 1 expected")
	expect(step1.text).toEqual("Hey!")
	expect(step1.index).toEqual(1)
	expect(step1.total).toEqual(3)
	expect(step1.choices == nil).toBeTrue()

	local step2 = Dialog.step(DEF, false, 2)
	assert(step2, "step 2 expected")
	expect(step2.text).toEqual("I coach champions.")
	expect(step2.choices == nil).toBeTrue()
end)

test("branch line offers the qualified text and choices when qualified", function()
	local step = Dialog.step(DEF, true, 3)
	assert(step, "branch step expected")
	expect(step.text).toEqual("Ready to train?")
	assert(step.choices, "choices expected")
	expect(#step.choices).toEqual(2)
	expect(step.choices[1]).toEqual("Train")
end)

test("branch line offers the gate text and choices when not qualified", function()
	local step = Dialog.step(DEF, false, 3)
	assert(step, "branch step expected")
	expect(step.text).toEqual("Come back with 100 followers.")
	assert(step.choices, "choices expected")
	expect(#step.choices).toEqual(1)
	expect(step.choices[1]).toEqual("Got it")
end)

test("returns nil outside the dialog", function()
	expect(Dialog.step(DEF, true, 0) == nil).toBeTrue()
	expect(Dialog.step(DEF, true, 4) == nil).toBeTrue()
end)
