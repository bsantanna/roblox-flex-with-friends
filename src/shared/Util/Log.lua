--!strict
-- Structured logging seam: consistent, greppable lines "[Scope] message | k=v k=v".
-- A thin wrapper over print/warn so call sites are uniform and routing can change in one place.

local Log = {}

local function format(scope: string, message: string, data: { [string]: any }?): string
	local line = `[{scope}] {message}`
	if data then
		local parts = {}
		for key, value in data do
			table.insert(parts, `{key}={value}`)
		end
		if #parts > 0 then
			table.sort(parts)
			line ..= " | " .. table.concat(parts, " ")
		end
	end
	return line
end

function Log.info(scope: string, message: string, data: { [string]: any }?)
	print(format(scope, message, data))
end

function Log.warn(scope: string, message: string, data: { [string]: any }?)
	warn(format(scope, message, data))
end

return Log
