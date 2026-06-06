--!strict
-- WorldService: constructs the static world in code so the place is reproducible from src
-- (Rojo doesn't manage Workspace; make build produces an empty Workspace). Phase 1 builds the
-- Home zone: a floor, a SpawnLocation, and the Phone / Computer interaction anchors, each
-- carrying a named ProximityPrompt. Grey-box geometry for now; visual ProceduralModels can
-- replace these parts later without changing the interaction contract (the prompt names).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldService = {}

-- Interaction anchors: name -> { offset from zone origin, prompt action/object text }. Placed in
-- the central plaza, just clear of the spawn, so they're reachable the moment the player lands.
local HOME_INTERACTIONS = {
	{ name = "Phone", offset = Vector3.new(-12, 2, 8), action = "Use", object = "Phone" },
	{ name = "Computer", offset = Vector3.new(12, 2, 8), action = "Use", object = "Computer" },
}

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = color
	part.Parent = parent
	return part
end

local function addPrompt(part: BasePart, name: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part
end

local ZONE_FLOOR_COLOR = {
	Home = Color3.fromRGB(120, 120, 130),
	Airport = Color3.fromRGB(90, 110, 140),
	Beach = Color3.fromRGB(220, 200, 150),
}

local Terrain = Workspace.Terrain

-- Smooth terrain renders its surface ~2 studs above the filled voxel top, so a block filled to
-- top=origin.Y would leave parts placed at origin.Y buried. Lower the fill by this skin so the
-- visible/collidable surface lands on origin.Y (the ground level everything else assumes).
local SURFACE_SKIN = 2

-- Paint a flat ground slab whose rendered surface sits at origin.Y, centered on origin's X/Z.
local function fillSlab(origin: Vector3, sizeX: number, sizeZ: number, material: Enum.Material)
	local t = Config.Terrain.Thickness
	local top = origin.Y - SURFACE_SKIN
	Terrain:FillBlock(CFrame.new(origin.X, top - t / 2, origin.Z), Vector3.new(sizeX, t, sizeZ), material)
end

-- Paint an elliptical band by sweeping overlapping rotated boxes around the ellipse (a=X, b=Z
-- semi-axes of the band's mid-line). `radialLen` is each box's thickness across the band (use a bit
-- more than the band width so neighbours overlap and there are no gaps; overshoot is overwritten by
-- later fills). The band's rendered surface sits at `surfaceTop`, filled `height` studs downward.
local RING_STEPS = 90
local function fillEllipseRing(
	center: Vector3,
	a: number,
	b: number,
	radialLen: number,
	surfaceTop: number,
	height: number,
	material: Enum.Material
)
	local fillTop = surfaceTop - SURFACE_SKIN
	local tangential = (2 * math.pi * math.max(a, b)) / RING_STEPS + 24 -- arc chord + overlap
	for i = 0, RING_STEPS - 1 do
		local t = (i / RING_STEPS) * 2 * math.pi
		local cx, cz = a * math.cos(t), b * math.sin(t)
		local ang = math.atan2(cz, cx)
		local cf = CFrame.new(center.X + cx, fillTop - height / 2, center.Z + cz) * CFrame.Angles(0, -ang, 0)
		Terrain:FillBlock(cf, Vector3.new(radialLen, height, tangential), material)
	end
end

-- Landscaping ground per zone (Config.Terrain). Complements the greybox floors; buildings/props
-- are layered on top later. Roads/water overwrite the ground voxels where they overlap.
local function paintTerrain()
	local T = Config.Terrain

	local home = Config.Zones.Home
	local H = T.Home
	local R = H.Ring
	-- The grass island (plateau), then the street grid on top, then the surrounding moat and
	-- mountain. Order matters: each layer overwrites grass where it overlaps.
	-- 1) Grass plateau, sized to the plateau ellipse's bounding box (the moat carves it elliptical).
	fillSlab(home, 2 * R.Plateau.Ax, 2 * R.Plateau.Az, H.Ground)
	-- 2) Street grid: an asphalt strip down each gap between squares (lines at +/-RoadLine) plus the
	-- outer loop (lines at +/-PerimeterLine). Each strip spans the full grid so they meet at every
	-- crossing -> a closed loop with no dead ends.
	local span = 2 * H.PerimeterLine + H.RoadWidth -- reaches corner to corner of the perimeter loop
	for _, g in { -H.PerimeterLine, -H.RoadLine, H.RoadLine, H.PerimeterLine } do
		fillSlab(home + Vector3.new(g, 0, 0), H.RoadWidth, span, H.Road) -- roads along Z
		fillSlab(home + Vector3.new(0, 0, g), span, H.RoadWidth, H.Road) -- roads along X
	end
	-- 3) Water moat: an elliptical ring just outside the plateau (surface at ground level).
	local moatAx, moatAz = R.Plateau.Ax + R.Moat.Width, R.Plateau.Az + R.Moat.Width
	fillEllipseRing(
		home,
		(R.Plateau.Ax + moatAx) / 2,
		(R.Plateau.Az + moatAz) / 2,
		R.Moat.Width + 40,
		0,
		R.Moat.Depth,
		R.Moat.Material
	)
	-- 4) Mountain: a sheer rock ring outside the moat, rising Mountain.Height studs (vertical = unclimbable).
	local mtnAx, mtnAz = moatAx + R.Mountain.Width, moatAz + R.Mountain.Width
	fillEllipseRing(
		home,
		(moatAx + mtnAx) / 2,
		(moatAz + mtnAz) / 2,
		R.Mountain.Width + 40,
		R.Mountain.Height,
		R.Mountain.Height,
		R.Mountain.Material
	)

	local airport = Config.Zones.Airport
	fillSlab(airport, T.Airport.Size, T.Airport.Size, T.Airport.Ground)

	local beach = Config.Zones.Beach
	fillSlab(beach, T.Beach.Size, T.Beach.Size, T.Beach.Ground)
	local waterCenter = beach + Vector3.new(0, 0, T.Beach.Size / 2 + T.Beach.WaterDepth / 2)
	fillSlab(waterCenter, T.Beach.Size, T.Beach.WaterDepth, T.Beach.Water)
end

-- The grid's hardscape: concrete walkways flanking every road (inner gaps + the perimeter loop),
-- the central plaza floor, and a driveway from each house to the road it faces. Squares are by center
-- (cx, cz) in {-Pitch, 0, Pitch}: (0,0) is the plaza, ParkCell stays grass, the other seven hold a
-- house (the meshes in assets/manifest.json plus the primitive home in SceneryService).
local PAVING = Color3.fromRGB(200, 200, 205)

local function buildHomeGrid(home: Model, origin: Vector3)
	local T = Config.Terrain.Home
	local span = 2 * T.PerimeterLine + T.RoadWidth

	-- Walkways: a thin concrete strip on each side of every road (inner gaps + the perimeter loop).
	local walkOffset = T.RoadWidth / 2 + T.WalkwayWidth / 2
	for _, g in { -T.PerimeterLine, -T.RoadLine, T.RoadLine, T.PerimeterLine } do
		for _, side in { -1, 1 } do
			local w = makePart(
				"Walkway",
				Vector3.new(T.WalkwayWidth, 0.3, span),
				origin + Vector3.new(g + side * walkOffset, 0.15, 0),
				PAVING,
				home
			)
			w.Material = T.Sidewalk
			local h = makePart(
				"Walkway",
				Vector3.new(span, 0.3, T.WalkwayWidth),
				origin + Vector3.new(0, 0.15, g + side * walkOffset),
				PAVING,
				home
			)
			h.Material = T.Sidewalk
		end
	end

	-- Plaza floor over the center square.
	local plaza =
		makePart("Plaza", Vector3.new(T.CellSize, 0.3, T.CellSize), origin + Vector3.new(0, 0.16, 0), PAVING, home)
	plaza.Material = T.Sidewalk

	-- One driveway per house square, running from the house out to its facing road. A square faces
	-- along Z toward the plaza unless it is a side-column square (cz == 0), which faces along X.
	local cells = { -T.Pitch, 0, T.Pitch }
	for _, cx in cells do
		for _, cz in cells do
			local isCenter = cx == 0 and cz == 0
			local isPark = cx == T.ParkCell.X and cz == T.ParkCell.Z
			if isCenter or isPark then
				continue
			end
			local drive
			if cz ~= 0 then
				local dir = if cz < 0 then 1 else -1 -- toward the plaza along Z
				drive = makePart(
					"Driveway",
					Vector3.new(T.DrivewayWidth, 0.3, T.CellSize / 2),
					origin + Vector3.new(cx, 0.12, cz + dir * T.CellSize / 4),
					PAVING,
					home
				)
			else
				local dir = if cx < 0 then 1 else -1 -- toward the plaza along X
				drive = makePart(
					"Driveway",
					Vector3.new(T.CellSize / 2, 0.3, T.DrivewayWidth),
					origin + Vector3.new(cx + dir * T.CellSize / 4, 0.12, cz),
					PAVING,
					home
				)
			end
			drive.Material = T.Driveway
		end
	end
end

function WorldService:Start()
	paintTerrain()

	local world = Instance.new("Folder")
	world.Name = "World"

	-- A safety floor per zone: full lot size, tucked just under the terrain surface (Y=0) so it
	-- never shows but still catches a fall if terrain isn't ready when a player spawns/teleports.
	for zoneName, zoneOrigin in Config.Zones do
		local zone = Instance.new("Model")
		zone.Name = zoneName
		zone.Parent = world
		local color = ZONE_FLOOR_COLOR[zoneName] or Color3.fromRGB(120, 120, 130)
		local zoneSize = (Config.Terrain[zoneName] and Config.Terrain[zoneName].Size) or 120
		local floor =
			makePart("Floor", Vector3.new(zoneSize, 1, zoneSize), zoneOrigin + Vector3.new(0, -1, 0), color, zone)
		floor.Transparency = 1
	end

	local home = world:FindFirstChild("Home") :: Model
	local origin = Config.Zones.Home

	-- Spawn players in Home.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HomeSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = origin + Vector3.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Color = Color3.fromRGB(80, 160, 120)
	spawn.Parent = home

	-- Interaction anchors with named ProximityPrompts.
	local interactions = Instance.new("Folder")
	interactions.Name = "Interactions"
	interactions.Parent = home
	for _, def in HOME_INTERACTIONS do
		local part =
			makePart(def.name, Vector3.new(3, 4, 3), origin + def.offset, Color3.fromRGB(200, 170, 90), interactions)
		addPrompt(part, def.name, def.action, def.object)
	end

	buildHomeGrid(home, origin)

	world.Parent = Workspace
end

return WorldService
