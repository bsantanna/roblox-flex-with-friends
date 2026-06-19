--!strict
-- ReadyZone: a flat green disc on the floor marking where a player must stand for a minigame to
-- begin, plus a geometry test for entry. The server builds it and parents it to Workspace, so every
-- nearby player sees it (like the speech bubbles); the orchestrator polls only the playing player's
-- position against :contains(). Generic across NPC minigames.

local ReadyZone = {}
ReadyZone.__index = ReadyZone

export type ReadyZone = typeof(setmetatable(
	{} :: {
		part: Part,
		center: Vector3,
		radius: number,
	},
	ReadyZone
))

-- Builds a glowing green disc of `radius` centred on `center` (its underside on center.Y),
-- anchored and non-interactive so it never blocks the player walking onto it.
function ReadyZone.create(center: Vector3, radius: number, color: Color3, height: number): ReadyZone
	local part = Instance.new("Part")
	part.Name = "MinigameReadyZone"
	part.Shape = Enum.PartType.Cylinder
	-- A Cylinder's circular faces are on its local X axis, so Size.X is the disc thickness and
	-- Size.Y/Z the diameter; rotating 90° about Z lays that thin axis along world Y (a floor disc).
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.35
	part.Parent = workspace
	return setmetatable({ part = part, center = center, radius = radius }, ReadyZone)
end

-- True when `position` is within the disc on the XZ plane (height is ignored).
function ReadyZone.contains(self: ReadyZone, position: Vector3): boolean
	local flat = Vector3.new(position.X - self.center.X, 0, position.Z - self.center.Z)
	return flat.Magnitude <= self.radius
end

function ReadyZone.destroy(self: ReadyZone)
	self.part:Destroy()
end

return ReadyZone
