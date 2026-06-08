--!strict
-- TrafficService: ambient, server-driven cars that roam the road network -- the inner street grid,
-- the perimeter loop, the ramps and the elevated oval ring -- picking a random turn at every junction,
-- so they wander into and out of town and up and down the ring. Each car follows a Catmull-Rom spline
-- through the graph nodes (smooth in-lane curves, no physics, so it never jams or flips), offset into
-- the right-hand lane, and decelerates to a stop when a player is in its path. Cars are simple
-- primitive models under Workspace.Scenery; the graph derives from the same Config the roads are built
-- from, so the cars sit on the roads.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrafficService = {}

type Graph = { pos: { Vector3 }, adj: { { number } } }
type Car = { model: Model, n0: number, n1: number, n2: number, n3: number, t: number, seg: number, speed: number }

local CAR_COLORS = {
	Color3.fromRGB(196, 64, 64),
	Color3.fromRGB(64, 96, 196),
	Color3.fromRGB(220, 200, 90),
	Color3.fromRGB(70, 160, 100),
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(40, 40, 48),
}

local ACCEL = 26 -- studs/s^2 speeding up
local DECEL = 70 -- studs/s^2 braking

local function addPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A simple car (~10 x 4.4 studs) whose pivot (an invisible root) sits at wheel-contact, -Z = forward.
local function makeCar(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Car"
	local root = addPart(m, "Root", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), color)
	root.Transparency = 1
	addPart(m, "Body", Vector3.new(4.4, 1.8, 10), CFrame.new(0, 1.8, 0), color)
	addPart(m, "Cabin", Vector3.new(3.8, 1.5, 4.8), CFrame.new(0, 3.2, 0.6), color)
	for _, wx in { -2.1, 2.1 } do
		for _, wz in { -3, 3 } do
			addPart(
				m,
				"Wheel",
				Vector3.new(1, 2, 2),
				CFrame.new(wx, 1, wz) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(28, 28, 32),
				Enum.PartType.Cylinder
			)
		end
	end
	m.PrimaryPart = root
	return m
end

-- The road graph: node positions + adjacency. Ground roads sit at the grid lines (RoadLine /
-- PerimeterLine); each ramp adds a base + top node linking a perimeter junction up to a ring node.
local function buildGraph(origin: Vector3, T: any, O: any): Graph
	local pos: { Vector3 } = {}
	local adj: { { number } } = {}
	local byKey: { [string]: number } = {}
	local function node(p: Vector3): number
		local key = string.format("%.0f_%.0f_%.0f", p.X, p.Y, p.Z)
		local existing = byKey[key]
		if existing then
			return existing
		end
		table.insert(pos, p)
		local idx = #pos
		byKey[key] = idx
		adj[idx] = {}
		return idx
	end
	local function link(a: number, b: number)
		if a == b then
			return
		end
		table.insert(adj[a], b)
		table.insert(adj[b], a)
	end

	local groundY = Config.Roads.Thickness
	local deckY = origin.Y + O.Y + O.Thickness / 2
	local PL, RL = T.PerimeterLine, T.RoadLine
	-- Perimeter lines carry an extra junction at 0 where the axis ramps meet; inner lines do not.
	local perimSeq = { -PL, -RL, 0, RL, PL }
	local innerSeq = { -PL, -RL, RL, PL }
	local function gnode(x: number, z: number): number
		return node(origin + Vector3.new(x, groundY, z))
	end
	local xLines = { { -PL, perimSeq }, { -RL, innerSeq }, { RL, innerSeq }, { PL, perimSeq } }
	for _, line in xLines do
		local prev: number? = nil
		for _, z in line[2] :: { number } do
			local n = gnode(line[1] :: number, z)
			if prev then
				link(prev, n)
			end
			prev = n
		end
	end
	local zLines = { { -PL, perimSeq }, { -RL, innerSeq }, { RL, innerSeq }, { PL, perimSeq } }
	for _, line in zLines do
		local prev: number? = nil
		for _, x in line[2] :: { number } do
			local n = gnode(x, line[1] :: number)
			if prev then
				link(prev, n)
			end
			prev = n
		end
	end

	-- Oval ring: a smooth chain of nodes around the ellipse; ramps land on every (ringSteps/Ramps)th.
	local ringSteps = O.Ramps * 6
	local ring: { number } = {}
	for j = 0, ringSteps - 1 do
		local a = (j / ringSteps) * 2 * math.pi
		ring[j + 1] = node(origin + Vector3.new(O.Ax * math.cos(a), deckY, O.Az * math.sin(a)))
	end
	for j = 1, ringSteps do
		link(ring[j], ring[(j % ringSteps) + 1])
	end

	-- Ramps: perimeter junction -> base -> top -> ring node.
	local innerInset = O.Width / 2 + O.WalkwayWidth
	for k = 0, O.Ramps - 1 do
		local th = (k / O.Ramps) * 2 * math.pi
		local c, s = math.cos(th), math.sin(th)
		local m = math.max(math.abs(c), math.abs(s))
		local jNode = node(origin + Vector3.new(c * (PL / m), groundY, s * (PL / m)))
		local rEdge = (PL + T.RoadWidth / 2) / m
		local baseNode = node(origin + Vector3.new(rEdge * c, groundY, rEdge * s))
		local rOval = 1 / math.sqrt((c / O.Ax) ^ 2 + (s / O.Az) ^ 2)
		local pLand = origin + Vector3.new(rOval * c, deckY, rOval * s)
		local topNode = node(pLand - Vector3.new(c, 0, s) * innerInset)
		local ovalNode = ring[k * 6 + 1] -- the ring node at this ramp's angle
		link(jNode, baseNode)
		link(baseNode, topNode)
		link(topNode, ovalNode)
	end

	return { pos = pos, adj = adj }
end

-- A random neighbour of `n`, avoiding the node we came from unless it's the only option.
local function pickNext(graph: Graph, n: number, came: number): number
	local opts = {}
	for _, nb in graph.adj[n] do
		if nb ~= came then
			table.insert(opts, nb)
		end
	end
	if #opts == 0 then
		return came
	end
	return opts[math.random(#opts)]
end

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - 3 * p2 + p3 - p0) * t3)
end

local function catmullTangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	return 0.5 * ((p2 - p0) + (2 * p0 - 5 * p1 + 4 * p2 - p3) * (2 * t) + (3 * p1 - 3 * p2 + p3 - p0) * (3 * t2))
end

local cars: { Car } = {}
local graph: Graph

local function advance(car: Car)
	car.n0, car.n1, car.n2 = car.n1, car.n2, car.n3
	car.n3 = pickNext(graph, car.n2, car.n1)
	car.seg = math.max(1, (graph.pos[car.n2] - graph.pos[car.n1]).Magnitude)
end

-- Is a player within StopDistance ahead of `pos` along `fwd`, roughly in this lane?
local function playerAhead(pos: Vector3, fwd: Vector3): boolean
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local to = (hrp :: BasePart).Position - pos
			local ahead = to:Dot(fwd)
			if ahead > 0 and ahead < Config.Traffic.StopDistance then
				if (to - fwd * ahead).Magnitude < 5 then
					return true
				end
			end
		end
	end
	return false
end

function TrafficService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = scenery

	local origin = Config.Zones.Home
	graph = buildGraph(origin, Config.Terrain.Home, Config.Terrain.Home.Ring.Oval)

	for n = 1, Config.Traffic.Cars do
		local n1 = math.random(#graph.pos)
		local n2 = graph.adj[n1][math.random(#graph.adj[n1])]
		local car: Car = {
			model = makeCar(CAR_COLORS[(n % #CAR_COLORS) + 1]),
			n0 = pickNext(graph, n1, n2),
			n1 = n1,
			n2 = n2,
			n3 = pickNext(graph, n2, n1),
			t = math.random(),
			seg = math.max(1, (graph.pos[n2] - graph.pos[n1]).Magnitude),
			speed = Config.Traffic.Speed,
		}
		car.model.Parent = folder
		table.insert(cars, car)
	end

	RunService.Heartbeat:Connect(function(dt)
		local lane = Config.Traffic.LaneOffset
		for _, car in cars do
			local p0, p1, p2, p3 = graph.pos[car.n0], graph.pos[car.n1], graph.pos[car.n2], graph.pos[car.n3]
			local pos = catmull(p0, p1, p2, p3, car.t)
			local tan = catmullTangent(p0, p1, p2, p3, car.t)
			if tan.Magnitude < 1e-3 then
				tan = p2 - p1
			end
			tan = tan.Unit
			local flat = Vector3.new(tan.X, 0, tan.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else tan
			local right = Vector3.new(tan.Z, 0, -tan.X)
			right = if right.Magnitude > 1e-3 then right.Unit else Vector3.zero
			local laned = pos + right * lane

			local target = if playerAhead(laned, flat) then 0 else Config.Traffic.Speed
			local a = if target > car.speed then ACCEL else -DECEL
			car.speed = math.clamp(car.speed + a * dt, 0, Config.Traffic.Speed)

			car.t += (car.speed * dt) / car.seg
			while car.t >= 1 do
				car.t -= 1
				advance(car)
			end
			car.model:PivotTo(CFrame.lookAt(laned, laned + tan))
		end
	end)
end

return TrafficService
