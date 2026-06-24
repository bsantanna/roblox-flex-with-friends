--!strict
-- HeliTrafficService: a single decorative helicopter shuttling between a helipad on the central
-- building's rooftop and a helipad on the airport's west apron. It lifts off the rooftop, cruises to
-- the airport, descends and holds, then flies back and lands on the rooftop -- one full round trip
-- every Config.HeliTraffic.TotalCycle (5 minutes). Same engine as AirTrafficService: an anchored
-- primitive model under Workspace.Scenery, no physics and no remotes, driven by a pure evaluate(elapsed)
-- mapping the wrapping clock to a pivot CFrame across phases that are C0-continuous so the wrap is
-- seamless. The two Hold phases yaw the helicopter 180 degrees in place so it always departs nose-first.
-- The main and tail rotors spin continuously off a separate clock; because PivotTo moves the model
-- rigidly, each rotor blade's CFrame is re-set relative to the body every frame.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HeliTrafficService = {}

type Blade = { part: Part, offset: number }

local BODY = Color3.fromRGB(245, 245, 245)
local TRIM = Color3.fromRGB(212, 175, 55)
local GLASS = Color3.fromRGB(60, 70, 90)
local METAL = Color3.fromRGB(60, 60, 70)
local CONCRETE = Color3.fromRGB(70, 72, 78)
local MARK = Color3.fromRGB(236, 214, 96)

-- Rotor hubs in the model's local frame (relative to the Root pivot at the skid bottom).
local MAIN_HUB = CFrame.new(0, 6.6, 0)
local TAIL_HUB = CFrame.new(0.9, 5.4, 11.3)

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

-- A light civilian helicopter (~17-stud body) built nose = local -Z so CFrame.lookAt(pos, pos + heading)
-- faces it forward (same convention as the planes). The invisible Root pivot sits at the skid bottom, so
-- PivotTo places it on its skids. Returns the model plus the rotor blades whose CFrames the loop spins.
local function makeHelicopter(): (Model, { Blade }, { Blade })
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local root = addPart(m, "Root", Vector3.new(1, 1, 1), CFrame.new(0, 0, 0), BODY, Enum.Material.SmoothPlastic)
	root.Transparency = 1

	-- Skids: two tubes along Z, joined to the body by short uprights.
	for _, sx in { -2.3, 2.3 } do
		addPart(
			m,
			"Skid",
			Vector3.new(0.5, 9, 0.5),
			CFrame.new(sx, 0.25, 0) * CFrame.Angles(math.rad(90), 0, 0),
			METAL,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		for _, sz in { -2.5, 2.5 } do
			addPart(m, "Strut", Vector3.new(0.4, 2, 0.4), CFrame.new(sx, 1.3, sz), METAL, Enum.Material.Metal)
		end
	end

	-- Cabin: a body block, a rounded nose, a dark windscreen and a gold belly stripe.
	addPart(m, "Cabin", Vector3.new(5, 4.6, 9), CFrame.new(0, 3.4, 0), BODY, Enum.Material.SmoothPlastic)
	addPart(
		m,
		"Nose",
		Vector3.new(5, 4.4, 4),
		CFrame.new(0, 3.2, -5.2),
		BODY,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	addPart(m, "Windscreen", Vector3.new(4.2, 2.6, 3), CFrame.new(0, 3.7, -4), GLASS, Enum.Material.Glass)
	addPart(m, "Stripe", Vector3.new(5.1, 1, 9), CFrame.new(0, 2.2, 0), TRIM, Enum.Material.SmoothPlastic)

	-- Tail boom, fin and horizontal stabiliser.
	addPart(m, "Boom", Vector3.new(1.4, 1.4, 8), CFrame.new(0, 4.2, 7.5), BODY, Enum.Material.SmoothPlastic)
	addPart(m, "TailFin", Vector3.new(0.5, 3, 2), CFrame.new(0, 5.4, 11), BODY, Enum.Material.SmoothPlastic)
	addPart(m, "Tailplane", Vector3.new(4, 0.4, 1.6), CFrame.new(0, 4.4, 10.5), BODY, Enum.Material.SmoothPlastic)

	-- Rotor masts/hubs (static); the blades themselves are spun by the loop.
	addPart(
		m,
		"Mast",
		Vector3.new(0.6, 1.6, 0.6),
		CFrame.new(0, 5.9, 0),
		METAL,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	addPart(
		m,
		"MainHub",
		Vector3.new(0.5, 1.6, 1.6),
		MAIN_HUB * CFrame.Angles(0, 0, math.rad(90)),
		METAL,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	local mainBlades: { Blade } = {}
	for _, off in { 0, math.pi / 2 } do
		local b = addPart(m, "MainBlade", Vector3.new(17, 0.25, 1.1), MAIN_HUB, METAL, Enum.Material.Metal)
		table.insert(mainBlades, { part = b, offset = off })
	end
	local tailBlades: { Blade } = {}
	for _, off in { 0, math.pi / 2 } do
		local b = addPart(m, "TailBlade", Vector3.new(0.25, 4, 0.7), TAIL_HUB, METAL, Enum.Material.Metal)
		table.insert(tailBlades, { part = b, offset = off })
	end

	m.PrimaryPart = root
	return m, mainBlades, tailBlades
end

-- A helipad: a gold rim cylinder with a darker landing disc on top and a painted "H". `topY` is the
-- world height of the landing surface (where the skids rest); the disc is built just below it.
local function buildPad(parent: Instance, center: Vector3, topY: number)
	local P = Config.HeliTraffic.Pad
	local rimY = topY - P.Thickness / 2
	addPart(
		parent,
		"PadRim",
		Vector3.new(P.Thickness, P.Radius * 2, P.Radius * 2),
		CFrame.new(center.X, rimY, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		MARK,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	addPart(
		parent,
		"PadDisc",
		Vector3.new(P.Thickness, (P.Radius - 1.5) * 2, (P.Radius - 1.5) * 2),
		CFrame.new(center.X, rimY + 0.05, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		CONCRETE,
		Enum.Material.Concrete,
		Enum.PartType.Cylinder
	)
	-- The "H": two uprights and a crossbar, painted on the disc top.
	local markY = topY + 0.06
	for _, mx in { -3, 3 } do
		addPart(
			parent,
			"Mark",
			Vector3.new(1.4, 0.1, 11),
			CFrame.new(center.X + mx, markY, center.Z),
			MARK,
			Enum.Material.SmoothPlastic
		)
	end
	addPart(
		parent,
		"Mark",
		Vector3.new(7.4, 0.1, 1.4),
		CFrame.new(center.X, markY, center.Z),
		MARK,
		Enum.Material.SmoothPlastic
	)
end

-- Geometry, derived from Config once in :Start() and read by evaluate().
local rooftopXZ, airportXZ = Vector3.zero, Vector3.zero
local rooftopLandY, airportLandY, cruiseY = 0, 0, 0
local angToAirport = 0 -- yaw (radians) of the rooftop -> airport heading
local fwdPitch = 0
local durs: { number } = {}
local bound: { number } = {}

local PHASE_ORDER = {
	"RooftopLift",
	"ToAirport",
	"AirportDescend",
	"AirportHold",
	"AirportLift",
	"ToRooftop",
	"RooftopDescend",
	"RooftopHold",
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function dirFromYaw(a: number): Vector3
	return Vector3.new(math.sin(a), 0, math.cos(a))
end

-- Nose is local -Z; orient so -Z faces `heading` (horizontal), then pitch about local X (positive =
-- nose-up, matching AirTrafficService).
local function orient(pos: Vector3, heading: Vector3, pitchDeg: number): CFrame
	local flat = Vector3.new(heading.X, 0, heading.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(1, 0, 0)
	return CFrame.lookAt(pos, pos + flat) * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

-- Map the wrapping clock to the helicopter's body pivot CFrame. The two cruise legs reverse heading,
-- and the two Hold phases yaw 180 degrees in place to bridge them, so the pose at elapsed=0 and
-- elapsed=TotalCycle is the same (hovering on the rooftop pad, nose toward the airport).
local function evaluate(elapsed: number): CFrame
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

	local toAirport = dirFromYaw(angToAirport)
	local toRooftop = dirFromYaw(angToAirport + math.pi)

	if phase == "RooftopLift" then
		local y = lerp(rooftopLandY, cruiseY, smooth(lt))
		return orient(Vector3.new(rooftopXZ.X, y, rooftopXZ.Z), toAirport, 0)
	elseif phase == "ToAirport" then
		local pos = rooftopXZ:Lerp(airportXZ, smooth(lt))
		return orient(Vector3.new(pos.X, cruiseY, pos.Z), toAirport, -fwdPitch * math.sin(lt * math.pi))
	elseif phase == "AirportDescend" then
		local y = lerp(cruiseY, airportLandY, smooth(lt))
		return orient(Vector3.new(airportXZ.X, y, airportXZ.Z), toAirport, 0)
	elseif phase == "AirportHold" then
		-- Sit on the airport pad, yawing from the arrival heading round to face home.
		return orient(
			Vector3.new(airportXZ.X, airportLandY, airportXZ.Z),
			dirFromYaw(angToAirport + math.pi * smooth(lt)),
			0
		)
	elseif phase == "AirportLift" then
		local y = lerp(airportLandY, cruiseY, smooth(lt))
		return orient(Vector3.new(airportXZ.X, y, airportXZ.Z), toRooftop, 0)
	elseif phase == "ToRooftop" then
		local pos = airportXZ:Lerp(rooftopXZ, smooth(lt))
		return orient(Vector3.new(pos.X, cruiseY, pos.Z), toRooftop, -fwdPitch * math.sin(lt * math.pi))
	elseif phase == "RooftopDescend" then
		local y = lerp(cruiseY, rooftopLandY, smooth(lt))
		return orient(Vector3.new(rooftopXZ.X, y, rooftopXZ.Z), toRooftop, 0)
	else -- RooftopHold: yaw from the arrival heading round to face the airport again (back to start).
		return orient(
			Vector3.new(rooftopXZ.X, rooftopLandY, rooftopXZ.Z),
			dirFromYaw(angToAirport + math.pi + math.pi * smooth(lt)),
			0
		)
	end
end

function HeliTrafficService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "HeliTraffic"
	folder.Parent = scenery

	local H = Config.HeliTraffic
	local airport = Config.Zones.Airport
	local rooftop = H.RooftopPad
	local airPad = airport + H.AirportPad
	rooftopXZ = Vector3.new(rooftop.X, 0, rooftop.Z)
	airportXZ = Vector3.new(airPad.X, 0, airPad.Z)
	rooftopLandY = rooftop.Y
	airportLandY = airPad.Y + H.Pad.Thickness
	cruiseY = H.CruiseAltitude
	angToAirport = math.atan2(airportXZ.X - rooftopXZ.X, airportXZ.Z - rooftopXZ.Z)
	fwdPitch = 6

	local P = H.Phases
	durs = {
		P.RooftopLift,
		P.ToAirport,
		P.AirportDescend,
		P.AirportHold,
		P.AirportLift,
		P.ToRooftop,
		P.RooftopDescend,
		P.RooftopHold,
	}
	local acc = 0
	for i = 1, #durs do
		acc += durs[i]
		bound[i] = acc
	end

	buildPad(folder, rooftop, rooftopLandY)
	buildPad(folder, airPad, airportLandY)

	local model, mainBlades, tailBlades = makeHelicopter()
	model.Parent = folder

	local elapsed = 0
	local rotor = 0
	model:PivotTo(evaluate(elapsed))
	RunService.Heartbeat:Connect(function(dt)
		elapsed = (elapsed + dt) % H.TotalCycle
		local body = evaluate(elapsed)
		model:PivotTo(body)
		-- Spin the rotors relative to the (rigidly moved) body; the tail rotor turns faster.
		rotor = (rotor + dt * math.rad(H.RotorSpeed)) % (2 * math.pi)
		for _, b in mainBlades do
			b.part.CFrame = body * MAIN_HUB * CFrame.Angles(0, rotor + b.offset, 0)
		end
		for _, b in tailBlades do
			b.part.CFrame = body * TAIL_HUB * CFrame.Angles(rotor * 2.4 + b.offset, 0, 0)
		end
	end)
end

return HeliTrafficService
