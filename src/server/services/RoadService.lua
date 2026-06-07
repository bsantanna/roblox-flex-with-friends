--!strict
-- RoadService: lays the Home neighbourhood's ground road network as parts over the grass terrain.
-- The network is the 3x3 grid's gaps (Config.Terrain.Home.RoadLine) plus the outer perimeter loop
-- (PerimeterLine), on both axes. WorldService paints the grass/plaza/driveways; IslandService builds
-- the elevated ring and the ramps that join it to this loop.
--
-- Built from a small graph: nodes are the line crossings, edges the straight segments between
-- consecutive crossings. Each edge gets an asphalt ribbon, a dashed centre line and flanking curbs;
-- each node gets a flat asphalt disc whose radius overshoots the road so the four corners read as
-- curves rather than hard right angles. The grid is axis-aligned, so no rotation is needed.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local RoadService = {}

local ASPHALT = Color3.fromRGB(58, 60, 66)
local LINE = Color3.fromRGB(245, 245, 245)
local CURB = Color3.fromRGB(200, 200, 205)

local function addPart(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.CanCollide = canCollide ~= false
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The grid crossings (nodes) and the straight segments joining consecutive crossings on each line
-- (edges). Lines sit at +/-RoadLine (inner gaps) and +/-PerimeterLine (outer loop) on both axes.
local function buildGraph(origin: Vector3, T: any): ({ Vector3 }, { { Vector3 } })
	local lines = { -T.PerimeterLine, -T.RoadLine, T.RoadLine, T.PerimeterLine }
	local nodes = {}
	for _, x in lines do
		for _, z in lines do
			table.insert(nodes, origin + Vector3.new(x, 0, z))
		end
	end
	local edges = {}
	for _, c in lines do
		for i = 1, #lines - 1 do
			local a, b = lines[i], lines[i + 1]
			table.insert(edges, { origin + Vector3.new(a, 0, c), origin + Vector3.new(b, 0, c) }) -- along X
			table.insert(edges, { origin + Vector3.new(c, 0, a), origin + Vector3.new(c, 0, b) }) -- along Z
		end
	end
	return nodes, edges
end

function RoadService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end
	local model = Instance.new("Model")
	model.Name = "HomeRoads"
	model.Parent = scenery

	local T = Config.Terrain.Home
	local R = Config.Roads
	local origin = Config.Zones.Home
	local W = T.RoadWidth
	local th = R.Thickness
	local junctionDiameter = W + 2 * R.Fillet
	local clear = junctionDiameter -- markings/curbs stop this short of an edge's ends (the junction discs)

	local nodes, edges = buildGraph(origin, T)

	for _, e in edges do
		local p0, p1 = e[1], e[2]
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude
		local alongX = math.abs(p1.X - p0.X) > 0.5

		local roadSize = if alongX then Vector3.new(len, th, W) else Vector3.new(W, th, len)
		addPart(model, "Road", CFrame.new(mid.X, th / 2, mid.Z), roadSize, ASPHALT, Enum.Material.Asphalt)

		-- Dashed centre line, stopping clear of the junction discs at each end.
		local span = len - clear
		if span > 0 then
			local step = R.DashLength + R.DashGap
			local count = math.max(1, math.floor(span / step))
			local used = count * step - R.DashGap
			local start = -used / 2 + R.DashLength / 2
			for k = 0, count - 1 do
				local o = start + k * step
				local pos = if alongX
					then Vector3.new(mid.X + o, th + 0.02, mid.Z)
					else Vector3.new(mid.X, th + 0.02, mid.Z + o)
				local size = if alongX
					then Vector3.new(R.DashLength, 0.06, R.LaneLineWidth)
					else Vector3.new(R.LaneLineWidth, 0.06, R.DashLength)
				addPart(model, "LaneLine", CFrame.new(pos), size, LINE, Enum.Material.SmoothPlastic, false)
			end
		end

		-- Concrete curbs flanking the road, also stopping clear of the junction discs.
		local curbLen = len - clear
		if curbLen > 0 then
			local off = W / 2 + R.CurbWidth / 2
			for _, s in { -1, 1 } do
				local pos = if alongX
					then Vector3.new(mid.X, R.CurbHeight / 2, mid.Z + s * off)
					else Vector3.new(mid.X + s * off, R.CurbHeight / 2, mid.Z)
				local size = if alongX
					then Vector3.new(curbLen, R.CurbHeight, R.CurbWidth)
					else Vector3.new(R.CurbWidth, R.CurbHeight, curbLen)
				addPart(model, "Curb", CFrame.new(pos), size, CURB, Enum.Material.Concrete)
			end
		end
	end

	-- A flat asphalt disc at each crossing rounds the corners (Cylinder length is local X, rotate
	-- X->Y so it lies flat).
	for _, n in nodes do
		addPart(
			model,
			"Junction",
			CFrame.new(n.X, th / 2, n.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(th, junctionDiameter, junctionDiameter),
			ASPHALT,
			Enum.Material.Asphalt,
			true,
			Enum.PartType.Cylinder
		)
	end
end

return RoadService
