--!strict
-- Server entry point. Boots every ModuleScript under `services/` via the
-- shared bootstrapper. Services are added in Phase 1. See doc/002_implementation_plan.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bootstrap = require(Shared:WaitForChild("Bootstrap"))

Bootstrap.run(script:FindFirstChild("services"))

print("[Server] booted")
