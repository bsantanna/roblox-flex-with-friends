--!strict
-- ReadyZone: a flat green disc on the floor marking where a player must stand for a minigame to
-- begin, plus a geometry test for entry. The server builds it and parents it to Workspace, so every
-- nearby player sees it (like the speech bubbles); the orchestrator polls only the playing player's
-- position against :contains(). Generic across NPC minigames.

local Players = game:GetService("Players")

local ReadyZone = {}
ReadyZone.__index = ReadyZone

-- Floor-probe bounds. The configured arena Y is only approximate — the real floor under it can be a
-- raised curb (sidewalk NPCs sit on a Y=0.6 curb), a building floor, or terrain. Probe from a little
-- above the requested center straight down, so the disc lands on whatever floor is actually there
-- without punching up to a ceiling or catching a tall prop overhead (which a probe from high up does).
local PROBE_UP = 4 -- start the probe this far above the requested center
local PROBE_DOWN = 10 -- ...and reach this far below it (stays under typical ceilings)
local LIFT = 0.05 -- seat the disc a hair above the floor so it never z-fights or sinks under the surface

export type ReadyZone = typeof(setmetatable(
	{} :: {
		part: Part,
		center: Vector3,
		radius: number,
	},
	ReadyZone
))

-- Finds the floor Y directly under `center`. Probes only collidable parts (so the disc, decals, and
-- decorative non-collidable bits are ignored) and skips player characters. Falls back to center.Y when
-- nothing is hit (e.g. the arena sits over a gap), which preserves the old behaviour.
local function floorYUnder(center: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local origin = center + Vector3.new(0, PROBE_UP, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -(PROBE_UP + PROBE_DOWN), 0), params)
	return if hit then hit.Position.Y else center.Y
end

-- Builds a glowing green disc of `radius` centred on `center`'s XZ, seated on the real floor beneath
-- it, anchored and non-interactive so it never blocks the player walking onto it.
function ReadyZone.create(center: Vector3, radius: number, color: Color3, height: number): ReadyZone
	local floorY = floorYUnder(center)
	local part = Instance.new("Part")
	part.Name = "MinigameReadyZone"
	part.Shape = Enum.PartType.Cylinder
	-- A Cylinder's circular faces are on its local X axis, so Size.X is the disc thickness and
	-- Size.Y/Z the diameter; rotating 90° about Z lays that thin axis along world Y (a floor disc).
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(Vector3.new(center.X, floorY + LIFT + height / 2, center.Z))
		* CFrame.Angles(0, 0, math.rad(90))
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
