--!strict
-- Sanity spec: proves the harness runs. Replaced by real Logic specs in the next step.

local framework = require("./framework")
local test = framework.test
local expect = framework.expect

test("harness runs", function()
	expect(1 + 1).toEqual(2)
end)
