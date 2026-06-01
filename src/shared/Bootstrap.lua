--!strict
-- Shared bootstrapper: given a Folder of ModuleScripts, requires each module,
-- then calls :Init() on all of them followed by :Start() on all of them.
-- Used by the server and client entry points so wiring (Init) is complete
-- before any runtime work (Start) begins. See doc/002_implementation_plan.md.

local Bootstrap = {}

function Bootstrap.run(container: Instance?)
	local modules = {}

	if container then
		for _, child in container:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(modules, require(child))
			end
		end
	end

	for _, module in modules do
		if type(module.Init) == "function" then
			module:Init()
		end
	end

	for _, module in modules do
		if type(module.Start) == "function" then
			module:Start()
		end
	end
end

return Bootstrap
