--!strict
-- AirTrafficService: a fixed fleet of decorative planes flying a continuous airport lifecycle over the
-- city -- takeoff roll, climb-out, an oval cruise circling the town, descent, landing, taxi and park --
-- then looping. The horizontal flight track is a single ellipse (Config.AirTraffic.Oval) whose +Z extreme
-- is tangent to the runway centreline, so takeoff and landing both line up with the runway heading (+X).
-- Each plane carries one wrapping clock (`elapsed`); a pure evaluate(elapsed) maps it to a pivot CFrame
-- (position + heading + bank/pitch), and the whole cycle is C0-continuous so the wrap is seamless. The
-- fleet is staggered evenly across TotalCycle, so one plane begins its takeoff every TotalCycle/Planes
-- seconds. Planes are anchored primitive models under Workspace.Scenery -- no physics, no remotes; their
-- positions replicate automatically to every client, exactly like the cars in TrafficService.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AirTrafficService = {}

type Plane = { model: Model, elapsed: number }

local BODY = Color3.fromRGB(245, 245, 245)
local STRIPE = Color3.fromRGB(212, 175, 55)
local ENGINE = Color3.fromRGB(60, 60, 70)
local ASPHALT = Color3.fromRGB(48, 50, 56)
local CONCRETE = Color3.fromRGB(151, 153, 159)
local PAINT = Color3.fromRGB(238, 238, 238)

local function addPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A simple airliner (~40 studs long) built nose = local -Z so CFrame.lookAt(pos, pos + heading) faces it
-- forward (the same convention as the cars). The invisible Root pivot sits at the belly, so PivotTo places
-- the plane on its wheels. Cylinders' length is along local X, so a fuselage/engine along Z rotates X->Z.
local function makePlane(): Model
	local m = Instance.new("Model")
	m.Name = "Plane"
	local root = addPart(m, "Root", Vector3.new(1, 1, 1), CFrame.new(0, 3, 0), BODY, Enum.Material.SmoothPlastic)
	root.Transparency = 1
	addPart(
		m,
		"Fuselage",
		Vector3.new(40, 6, 6),
		CFrame.new(0, 6, 0) * CFrame.Angles(0, math.rad(90), 0),
		BODY,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	addPart(
		m,
		"Nose",
		Vector3.new(6, 5.6, 5.6),
		CFrame.new(0, 6, -20),
		BODY,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	addPart(m, "Stripe", Vector3.new(0.2, 1, 40), CFrame.new(0, 6, 0), STRIPE, Enum.Material.SmoothPlastic)
	addPart(m, "Wing", Vector3.new(34, 0.6, 8), CFrame.new(0, 6, 0), BODY, Enum.Material.SmoothPlastic)
	addPart(m, "TailFin", Vector3.new(0.6, 6, 5), CFrame.new(0, 9, 17), BODY, Enum.Material.SmoothPlastic)
	addPart(m, "Tailplane", Vector3.new(12, 0.5, 8), CFrame.new(0, 6, 15), BODY, Enum.Material.SmoothPlastic)
	for _, sx in { -10, 10 } do
		addPart(
			m,
			"Engine",
			Vector3.new(6, 2.2, 2.2),
			CFrame.new(sx, 4.2, 0) * CFrame.Angles(0, math.rad(90), 0),
			ENGINE,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
	end
	m.PrimaryPart = root
	return m
end

-- The runway: a dark asphalt strip along X centred on the airport, with painted edge lines, a dashed
-- centreline and a row of threshold bars at each end so it reads as a runway over the lighter apron.
local function buildRunway(parent: Instance, airport: Vector3)
	local R = Config.AirTraffic.Runway
	local half = R.Length / 2
	local topY = airport.Y + R.Y
	local markY = topY + 0.35
	-- Foundation apron first (the runway + markings sit on top of it).
	local AP = R.Apron
	addPart(
		parent,
		"Apron",
		Vector3.new(AP.Length, AP.Depth, AP.Width),
		CFrame.new(airport.X, topY - 0.3 - AP.Depth / 2, airport.Z + AP.OffsetZ),
		CONCRETE,
		Enum.Material.Concrete
	)
	addPart(
		parent,
		"Runway",
		Vector3.new(R.Length, 0.6, R.Width),
		CFrame.new(airport.X, topY, airport.Z),
		ASPHALT,
		Enum.Material.Asphalt
	)
	for _, sz in { -1, 1 } do
		addPart(
			parent,
			"EdgeLine",
			Vector3.new(R.Length, 0.1, 0.8),
			CFrame.new(airport.X, markY, airport.Z + sz * (R.Width / 2 - 1.5)),
			PAINT,
			Enum.Material.SmoothPlastic
		)
	end
	local dash, gap = 16, 14
	local x = -half + 30
	while x < half - 30 do
		addPart(
			parent,
			"CentreDash",
			Vector3.new(dash, 0.1, 0.8),
			CFrame.new(airport.X + x + dash / 2, markY, airport.Z),
			PAINT,
			Enum.Material.SmoothPlastic
		)
		x += dash + gap
	end
	for _, ex in { -1, 1 } do
		for i = -3, 3 do
			addPart(
				parent,
				"Threshold",
				Vector3.new(6, 0.1, 2),
				CFrame.new(airport.X + ex * (half - 12), markY, airport.Z + i * 3.2),
				PAINT,
				Enum.Material.SmoothPlastic
			)
		end
	end
end

-- Geometry, derived from Config once in :Start() and read by evaluate().
local airport = Vector3.zero
local groundY, cruiseY = 0, 0
local thresholdX, rolloutX = 0, 0
local ovalAx, ovalAz, ovalCenterZ, laps = 0, 0, 0, 0
local parkPt, parkHeading = Vector3.zero, Vector3.zero
local tpP0, tpC0, tpC1, tpP1 = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero
local ttP0, ttC0, ttC1, ttP1 = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero
local durs: { number } = {}
local bound: { number } = {}
local planes: { Plane } = {}

local PHASE_ORDER =
	{ "TakeoffRoll", "Climb", "Cruise", "Descent", "LandingRoll", "TaxiPark", "ParkHold", "TaxiThreshold" }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Nose is local -Z; orient so -Z faces `heading` (horizontal), then pitch about local X and roll (bank)
-- about local Z.
local function orient(pos: Vector3, heading: Vector3, pitchDeg: number, rollDeg: number): CFrame
	local flat = Vector3.new(heading.X, 0, heading.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(1, 0, 0)
	return CFrame.lookAt(pos, pos + flat) * CFrame.Angles(math.rad(pitchDeg), 0, math.rad(rollDeg))
end

-- The oval flight track: an ellipse centred at (airport.X, ovalCenterZ) so its +Z extreme (theta=0) sits on
-- the runway centreline and its -Z extreme (theta=pi) is over the city. theta increases -> a right turn.
local function ovalPos(theta: number, y: number): Vector3
	return Vector3.new(airport.X + ovalAx * math.sin(theta), y, ovalCenterZ + ovalAz * math.cos(theta))
end
local function ovalHeading(theta: number): Vector3
	return Vector3.new(ovalAx * math.cos(theta), 0, -ovalAz * math.sin(theta))
end

local function bezier(p0: Vector3, c0: Vector3, c1: Vector3, p1: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + c0 * (3 * u * u * t) + c1 * (3 * u * t * t) + p1 * (t * t * t)
end
local function bezierDir(p0: Vector3, c0: Vector3, c1: Vector3, p1: Vector3, t: number): Vector3
	local u = 1 - t
	return (c0 - p0) * (3 * u * u) + (c1 - c0) * (6 * u * t) + (p1 - c1) * (3 * t * t)
end

-- Map a plane's wrapping clock to its pivot CFrame. Phase boundaries are C0-continuous in position and
-- heading (takeoff/touchdown share the oval's tangent point; the taxi beziers join park-heading to +X),
-- so a plane at elapsed=0 and elapsed=TotalCycle is the same stationary pose at the threshold.
local function evaluate(elapsed: number): CFrame
	local A = Config.AirTraffic
	local idx = #PHASE_ORDER
	for i = 1, #PHASE_ORDER do
		if elapsed < bound[i] then
			idx = i
			break
		end
	end
	local startT = if idx == 1 then 0 else bound[idx - 1]
	local dur = durs[idx]
	local lt = if dur > 0 then (elapsed - startT) / dur else 0
	local phase = PHASE_ORDER[idx]

	if phase == "TakeoffRoll" then
		-- Accelerate from the threshold to the rotate point (the oval tangent at X=0), heading +X.
		local x = lerp(thresholdX, 0, lt * lt)
		return orient(Vector3.new(airport.X + x, groundY, airport.Z), Vector3.new(1, 0, 0), 0, 0)
	elseif phase == "Climb" then
		-- Climb a half-loop of the oval (theta 0->pi), rotating nose-up at liftoff and banking into the turn.
		local theta = lt * math.pi
		local y = lerp(groundY, cruiseY, smooth(lt))
		return orient(ovalPos(theta, y), ovalHeading(theta), A.ClimbPitch * (1 - smooth(lt)), -A.Bank * smooth(lt))
	elseif phase == "Cruise" then
		-- Circle the city at cruise altitude for Laps full loops, holding the bank.
		local theta = math.pi + lt * (laps * 2 * math.pi)
		return orient(ovalPos(theta, cruiseY), ovalHeading(theta), 0, -A.Bank)
	elseif phase == "Descent" then
		-- Descend the final half-loop (theta -> a multiple of 2*pi), levelling the bank and flaring at touchdown.
		local theta = (math.pi + laps * 2 * math.pi) + lt * math.pi
		local y = lerp(cruiseY, groundY, smooth(lt))
		return orient(
			ovalPos(theta, y),
			ovalHeading(theta),
			-A.DescentPitch * math.sin(lt * math.pi),
			-A.Bank * (1 - smooth(lt))
		)
	elseif phase == "LandingRoll" then
		-- Touch down at the tangent point and decelerate down the runway, heading +X.
		local x = lerp(0, rolloutX, 1 - (1 - lt) * (1 - lt))
		return orient(Vector3.new(airport.X + x, groundY, airport.Z), Vector3.new(1, 0, 0), 0, 0)
	elseif phase == "TaxiPark" then
		return orient(bezier(tpP0, tpC0, tpC1, tpP1, lt), bezierDir(tpP0, tpC0, tpC1, tpP1, lt), 0, 0)
	elseif phase == "ParkHold" then
		return orient(parkPt, parkHeading, 0, 0)
	else -- TaxiThreshold
		return orient(bezier(ttP0, ttC0, ttC1, ttP1, lt), bezierDir(ttP0, ttC0, ttC1, ttP1, lt), 0, 0)
	end
end

function AirTrafficService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "AirTraffic"
	folder.Parent = scenery

	local A = Config.AirTraffic
	airport = Config.Zones.Airport
	groundY = airport.Y + A.GroundY
	cruiseY = airport.Y + A.CruiseAltitude
	local half = A.Runway.Length / 2
	thresholdX = -half * 0.92 -- takeoff start, near the -X end
	rolloutX = half * 0.88 -- landing rollout end, near the +X end
	ovalAx = A.Oval.Ax
	ovalAz = A.Oval.Az
	ovalCenterZ = airport.Z - ovalAz -- so the oval's +Z extreme lands on the runway centreline
	laps = A.Oval.Laps

	-- Ground taxi: the plane exits the +X runway end, U-turns onto the apron facing -X (TaxiPark), holds,
	-- then taxis back and lines up at the threshold facing +X (TaxiThreshold). Cubic beziers whose end
	-- tangents match the runway/park headings keep the whole ground path smooth and the wrap seamless.
	local fwd = Vector3.new(1, 0, 0)
	local rolloutPt = Vector3.new(airport.X + rolloutX, groundY, airport.Z)
	local thresholdPt = Vector3.new(airport.X + thresholdX, groundY, airport.Z)
	parkPt = Vector3.new(airport.X + A.Park.X, groundY, airport.Z + A.Park.Z)
	parkHeading = Vector3.new(-1, 0, 0)
	tpP0, tpC0, tpC1, tpP1 = rolloutPt, rolloutPt + fwd * 45, parkPt - parkHeading * 45, parkPt
	ttP0, ttC0, ttC1, ttP1 = parkPt, parkPt + parkHeading * 90, thresholdPt - fwd * 45, thresholdPt

	-- Read phase durations in PHASE_ORDER (static field access, so analyze can type-check it) and build the
	-- cumulative end-time boundaries evaluate() buckets `elapsed` into.
	local P = A.Phases
	durs = { P.TakeoffRoll, P.Climb, P.Cruise, P.Descent, P.LandingRoll, P.TaxiPark, P.ParkHold, P.TaxiThreshold }
	local acc = 0
	for i = 1, #durs do
		acc += durs[i]
		bound[i] = acc
	end

	buildRunway(folder, airport)

	for n = 1, A.Planes do
		local plane: Plane = { model = makePlane(), elapsed = (n - 1) * (A.TotalCycle / A.Planes) }
		plane.model.Parent = folder
		plane.model:PivotTo(evaluate(plane.elapsed))
		table.insert(planes, plane)
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, plane in planes do
			plane.elapsed = (plane.elapsed + dt) % A.TotalCycle
			plane.model:PivotTo(evaluate(plane.elapsed))
		end
	end)
end

return AirTrafficService
