--!strict
-- Test entry point: auto-discovers every tests/*.spec.luau, runs them, exits non-zero on failure.
-- Run with `make test` (or `lune run tests/run.luau`).

local fs = require("@lune/fs")
local process = require("@lune/process")
local framework = require("./framework")

for _, entry in fs.readDir("tests") do
	if string.match(entry, "%.spec%.luau$") then
		require("./" .. string.gsub(entry, "%.luau$", ""))
	end
end

local failed = framework.run()
process.exit(if failed > 0 then 1 else 0)
