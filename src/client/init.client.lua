--!strict
-- Client entry point. Boots every ModuleScript under `controllers/` via the
-- shared bootstrapper. Controllers are added in Phase 1. See doc/002_implementation_plan.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bootstrap = require(Shared:WaitForChild("Bootstrap"))

Bootstrap.run(script:FindFirstChild("controllers"))

print("[Client] booted")
