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

-- Subtract `cutters` from `main` and swap the result in for it. The cutters are consumed; on CSG
-- failure the original part stays (pavement intact, just not rounded/trimmed).
local function carve(main: Part, cutters: { Part }, name: string, color: Color3, parent: Instance)
	local ok, result = pcall(function()
		return main:SubtractAsync(cutters :: any)
	end)
	for _, c in cutters do
		c:Destroy()
	end
	if ok and result then
		result.Name = name
		result.UsePartColor = true
		result.Color = color
		result.Anchored = true
		result.Parent = parent
		main:Destroy()
	end
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
	local walkOff = W / 2 + R.CurbWidth / 2 -- centre offset of the flanking walkway from the road centre

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

		-- Concrete walkways flanking the road, also stopping clear of the junction discs.
		local curbLen = len - clear
		if curbLen > 0 then
			for _, s in { -1, 1 } do
				local pos = if alongX
					then Vector3.new(mid.X, R.CurbHeight / 2, mid.Z + s * walkOff)
					else Vector3.new(mid.X + s * walkOff, R.CurbHeight / 2, mid.Z)
				local size = if alongX
					then Vector3.new(curbLen, R.CurbHeight, R.CurbWidth)
					else Vector3.new(R.CurbWidth, R.CurbHeight, curbLen)
				addPart(model, "Curb", CFrame.new(pos), size, CURB, Enum.Material.Concrete)
			end
		end
	end

	-- A flat asphalt disc at each crossing rounds the corners (Cylinder length is local X, rotate
	-- X->Y so it lies flat); then a walkway square in each corner where two arms meet, bridging the
	-- flanking walkways (which stop short of the disc) so the pavement wraps the junction with no grass
	-- gap. Only place a corner where both perpendicular arms exist, so none strands on the grass.
	for _, n in nodes do
		local disc = addPart(
			model,
			"Junction",
			CFrame.new(n.X, th / 2, n.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(th, junctionDiameter, junctionDiameter),
			ASPHALT,
			Enum.Material.Asphalt,
			true,
			Enum.PartType.Cylinder
		)
		local x, z = n.X - origin.X, n.Z - origin.Z

		-- On sides with no outgoing arm (the perimeter's outward sides) trim the disc flush with the
		-- road edge, so its extra radius rounds the walkway corners without bulging into the grass.
		local trimDepth = R.Fillet + 1
		local trims = {}
		local dirs = {
			{ arm = x < T.PerimeterLine, off = Vector3.new(1, 0, 0) },
			{ arm = x > -T.PerimeterLine, off = Vector3.new(-1, 0, 0) },
			{ arm = z < T.PerimeterLine, off = Vector3.new(0, 0, 1) },
			{ arm = z > -T.PerimeterLine, off = Vector3.new(0, 0, -1) },
		}
		for _, d in dirs do
			if not d.arm then
				local center = Vector3.new(n.X, th / 2, n.Z) + d.off * (W / 2 + trimDepth / 2)
				local size = if d.off.X ~= 0
					then Vector3.new(trimDepth, th + 0.2, junctionDiameter + 2)
					else Vector3.new(junctionDiameter + 2, th + 0.2, trimDepth)
				table.insert(
					trims,
					addPart(model, "JunctionTrim", CFrame.new(center), size, ASPHALT, Enum.Material.Asphalt, false)
				)
			end
		end
		if #trims > 0 then
			carve(disc, trims, "Junction", ASPHALT, model)
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local armX = if sx > 0 then x < T.PerimeterLine else x > -T.PerimeterLine
				local armZ = if sz > 0 then z < T.PerimeterLine else z > -T.PerimeterLine
				if armX and armZ then
					local corner = addPart(
						model,
						"Curb",
						CFrame.new(n.X + sx * walkOff, R.CurbHeight / 2, n.Z + sz * walkOff),
						Vector3.new(R.CurbWidth, R.CurbHeight, R.CurbWidth),
						CURB,
						Enum.Material.Concrete
					)
					-- Carve the corner's inside edge back to the junction disc's arc, so the walkway
					-- border wraps the crossing as a curve instead of a sharp right angle.
					local cutter = addPart(
						model,
						"CornerCutter",
						CFrame.new(n.X, R.CurbHeight / 2, n.Z) * CFrame.Angles(0, 0, math.rad(90)),
						Vector3.new(R.CurbHeight + 0.2, junctionDiameter, junctionDiameter),
						CURB,
						Enum.Material.Concrete,
						false,
						Enum.PartType.Cylinder
					)
					carve(corner, { cutter }, "Curb", CURB, model)
				end
			end
		end
	end
end

return RoadService
