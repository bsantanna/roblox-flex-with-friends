--!strict
-- TrafficService: ambient, server-driven cars that cruise the road loops (the elevated oval ring and
-- the ground perimeter loop). Decorative only -- each car moves by CFrame along a precomputed closed
-- loop every Heartbeat, with no physics, so it never jams, flips, or fights the player. Cars are
-- simple primitive models under Workspace.Scenery. Loop geometry derives from the same Config values
-- that RoadService/IslandService build the roads from, so the cars sit in the lanes.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrafficService = {}

type Loop = { points: { Vector3 }, cum: { number }, length: number }
type Car = { model: Model, loop: Loop, dist: number }

local CAR_COLORS = {
	Color3.fromRGB(196, 64, 64),
	Color3.fromRGB(64, 96, 196),
	Color3.fromRGB(220, 200, 90),
	Color3.fromRGB(70, 160, 100),
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(40, 40, 48),
}

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

-- A simple car whose pivot (an invisible root) sits at the wheel-contact point, local -Z = forward.
local function makeCar(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Car"
	local root = addPart(m, "Root", Vector3.new(0.4, 0.4, 0.4), CFrame.new(), color)
	root.Transparency = 1
	addPart(m, "Body", Vector3.new(3, 1.2, 6.5), CFrame.new(0, 1.1, 0), color)
	addPart(m, "Cabin", Vector3.new(2.6, 1.1, 3), CFrame.new(0, 2.1, 0.4), color)
	for _, wx in { -1.45, 1.45 } do
		for _, wz in { -2, 2 } do
			addPart(
				m,
				"Wheel",
				Vector3.new(0.7, 1.3, 1.3),
				CFrame.new(wx, 0.6, wz) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(28, 28, 32),
				Enum.PartType.Cylinder
			)
		end
	end
	m.PrimaryPart = root
	return m
end

local function makeLoop(points: { Vector3 }): Loop
	local cum = table.create(#points + 1)
	cum[1] = 0
	local total = 0
	for i = 1, #points do
		local nxt = points[(i % #points) + 1]
		total += (nxt - points[i]).Magnitude
		cum[i + 1] = total
	end
	return { points = points, cum = cum, length = total }
end

-- Position + unit tangent at distance d along the loop (wraps).
local function sampleLoop(loop: Loop, d: number): (Vector3, Vector3)
	local pts, cum = loop.points, loop.cum
	d = d % loop.length
	local i = 1
	while i < #pts and cum[i + 1] <= d do
		i += 1
	end
	local a = pts[i]
	local b = pts[(i % #pts) + 1]
	local segLen = (b - a).Magnitude
	local t = if segLen > 1e-4 then (d - cum[i]) / segLen else 0
	return a:Lerp(b, t), (b - a).Unit
end

-- The elevated ring, sampled and nudged outward into the right-hand cruising lane.
local function ovalLoop(origin: Vector3, O: any): Loop
	local n = 96
	local y = origin.Y + O.Y + O.Thickness / 2
	local pts = table.create(n)
	for j = 0, n - 1 do
		local ang = (j / n) * 2 * math.pi
		local px, pz = O.Ax * math.cos(ang), O.Az * math.sin(ang)
		local r = math.sqrt(px * px + pz * pz)
		local k = 1 + Config.Traffic.LaneOffset / r
		pts[j + 1] = origin + Vector3.new(px * k, y, pz * k)
	end
	return makeLoop(pts)
end

-- The ground perimeter loop: a rounded square just outside the loop road's centre line (right lane),
-- with corners small enough to stay on the asphalt / junction discs.
local function perimeterLoop(origin: Vector3, T: any): Loop
	local half = T.PerimeterLine + Config.Traffic.LaneOffset
	local cr = 8
	local h = half - cr
	local y = Config.Roads.Thickness + 0.05
	local centers = { Vector3.new(h, 0, h), Vector3.new(-h, 0, h), Vector3.new(-h, 0, -h), Vector3.new(h, 0, -h) }
	local steps = 6
	local pts = {}
	for ci, ctr in centers do
		local a0 = (ci - 1) * (math.pi / 2)
		for s = 0, steps do
			local ang = a0 + (s / steps) * (math.pi / 2)
			pts[#pts + 1] = origin + ctr + Vector3.new(cr * math.cos(ang), y, cr * math.sin(ang))
		end
	end
	return makeLoop(pts)
end

local cars: { Car } = {}

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
	local O = Config.Terrain.Home.Ring.Oval
	local T = Config.Terrain.Home

	local function populate(loop: Loop, count: number)
		for n = 0, count - 1 do
			local model = makeCar(CAR_COLORS[(n % #CAR_COLORS) + 1])
			model.Parent = folder
			local dist = (n / count) * loop.length
			local pos, tan = sampleLoop(loop, dist)
			model:PivotTo(CFrame.lookAt(pos, pos + tan))
			table.insert(cars, { model = model, loop = loop, dist = dist })
		end
	end

	populate(ovalLoop(origin, O), Config.Traffic.OvalCars)
	populate(perimeterLoop(origin, T), Config.Traffic.PerimeterCars)

	RunService.Heartbeat:Connect(function(dt)
		local step = Config.Traffic.Speed * dt
		for _, car in cars do
			car.dist = (car.dist + step) % car.loop.length
			local pos, tan = sampleLoop(car.loop, car.dist)
			car.model:PivotTo(CFrame.lookAt(pos, pos + tan))
		end
	end)
end

return TrafficService
