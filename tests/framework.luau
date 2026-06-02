--!strict
-- Minimal Lune test harness: register cases with `test`, assert with `expect`, run with `run`.
-- Kept tiny and dependency-free; specs require this and the pure Logic modules under src/shared.

local Framework = {}

type Case = { name: string, fn: () -> () }
local cases: { Case } = {}

function Framework.test(name: string, fn: () -> ())
	table.insert(cases, { name = name, fn = fn })
end

type Expectation = {
	toEqual: (expected: any) -> (),
	toBeTrue: () -> (),
	toBeFalse: () -> (),
}

function Framework.expect(value: any): Expectation
	return {
		toEqual = function(expected: any)
			if value ~= expected then
				error(`expected {tostring(expected)}, got {tostring(value)}`, 2)
			end
		end,
		toBeTrue = function()
			if value ~= true then
				error(`expected true, got {tostring(value)}`, 2)
			end
		end,
		toBeFalse = function()
			if value ~= false then
				error(`expected false, got {tostring(value)}`, 2)
			end
		end,
	}
end

function Framework.run(): number
	local failed = 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			print(`  PASS  {case.name}`)
		else
			failed += 1
			print(`  FAIL  {case.name}`)
			print(`        {err}`)
		end
	end
	print(`\n{#cases - failed}/{#cases} passed`)
	return failed
end

return Framework
