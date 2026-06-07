--!strict
-- IslandService: builds the elevated structures of the Home island ring (the terrain plateau, water
-- moat and mountain are painted by WorldService). It lays an elevated two-lane "high line" highway
-- that loops around the town over the moat (Config.Terrain.Home.Ring.Oval): a central road with a
-- dashed lane line, a wood-deck walkway down each side, a glass guardrail taller than a player on
-- the outer edges (so nobody falls/jumps off), diagonal wood bracing for a High-Line look, support
-- pillars into the water, panoramic view decks every 45 degrees, and ramps joining the ground
-- perimeter loop up to the deck. Everything is anchored, decorative geometry under Workspace.Scenery.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local IslandService = {}

local ROAD = Color3.fromRGB(58, 60, 66)
local PILLAR = Color3.fromRGB(176, 178, 184)
local DECK = Color3.fromRGB(156, 116, 76) -- wood planking
local RAIL = Color3.fromRGB(120, 86, 58) -- darker wood for handrails and braces
local GLASS = Color3.fromRGB(214, 228, 236) -- light, frosted-glass tint
local GLASS_MATERIAL = Enum.Material.SmoothPlastic -- resembles glass but far lighter to render than Glass
local GLASS_TRANSPARENCY = 0.65
local LINE = Color3.fromRGB(245, 245, 245)

local function addPart(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A glass-like panel: SmoothPlastic + transparency reads as glass but is far cheaper to render than
-- the Glass material across the deck's many panels.
local function addGlass(parent: Instance, name: string, cframe: CFrame, size: Vector3): Part
	return addPart(parent, name, cframe, size, GLASS, GLASS_MATERIAL, GLASS_TRANSPARENCY)
end

-- Point on the ellipse (a=X, b=Z semi-axes) at parameter angle t.
local function ovalPoint(a: number, b: number, t: number): Vector3
	return Vector3.new(a * math.cos(t), 0, b * math.sin(t))
end

-- A guardrail panel along one deck edge: a see-through glass wall (taller than a player + jump),
-- a wood handrail on top, and one diagonal wood brace (alternating slope -> a zigzag High-Line look).
-- `seg` is the segment CFrame (local Z = travel direction, local X = lateral, +X outward), `lateral`
-- the edge offset, `length` the segment length, `diag` the brace slope sign.
local function guardrail(parent: Instance, seg: CFrame, lateral: number, length: number, O: any, diag: number)
	addGlass(
		parent,
		"Guardrail",
		seg * CFrame.new(lateral, O.GuardrailHeight / 2, 0),
		Vector3.new(O.GuardrailThickness, O.GuardrailHeight, length + 1)
	)
	addPart(
		parent,
		"Handrail",
		seg * CFrame.new(lateral, O.GuardrailHeight, 0),
		Vector3.new(1.1, 0.4, length + 1),
		RAIL,
		Enum.Material.Wood
	)
	local a = math.atan2(O.GuardrailHeight, length)
	addPart(
		parent,
		"Brace",
		seg * CFrame.new(lateral, O.GuardrailHeight / 2, 0) * CFrame.Angles(diag * -a, 0, 0),
		Vector3.new(0.4, 0.4, math.sqrt(length * length + O.GuardrailHeight * O.GuardrailHeight)),
		RAIL,
		Enum.Material.Wood
	)
end

-- A panoramic view deck jutting outward (+X) from the deck edge, railed on its three open sides.
local function buildViewDeck(parent: Instance, seg: CFrame, length: number, O: any, edge: number)
	local depth, w, far = O.ViewDeckDepth, length + 4, edge + O.ViewDeckDepth
	addPart(
		parent,
		"ViewDeck",
		seg * CFrame.new(edge + depth / 2, 0, 0),
		Vector3.new(depth, O.Thickness, w),
		DECK,
		Enum.Material.WoodPlanks
	)
	addGlass(
		parent,
		"Guardrail",
		seg * CFrame.new(far, O.GuardrailHeight / 2, 0),
		Vector3.new(O.GuardrailThickness, O.GuardrailHeight, w)
	)
	for _, sz in { -1, 1 } do
		addGlass(
			parent,
			"Guardrail",
			seg * CFrame.new(edge + depth / 2, O.GuardrailHeight / 2, sz * w / 2),
			Vector3.new(depth, O.GuardrailHeight, O.GuardrailThickness)
		)
	end
	addPart(
		parent,
		"Handrail",
		seg * CFrame.new(far, O.GuardrailHeight, 0),
		Vector3.new(1.1, 0.4, w),
		RAIL,
		Enum.Material.Wood
	)
end

-- A segment whose inner edge a ramp merges onto: the inner guardrail must open there so cars can
-- drive off the ramp onto the highway. Ramp k lands at the vertex starting segment k*ratio, so the
-- gap straddles that vertex -> open the landing segment and the one before it.
local function isRampGap(i: number, O: any): boolean
	local ratio = O.Segments / O.Ramps
	local m = i % ratio
	return m == 0 or m == ratio - 1
end

-- The high-line deck: per chord segment, a road + dashed lane line + wood walkways + edge guardrails,
-- with view decks replacing the outer guardrail every ViewDeckEvery segments, and periodic pillars.
local function buildOval(parent: Instance, origin: Vector3, O: any)
	local segs = O.Segments
	local roadHalf = O.Width / 2
	local walkCenter = roadHalf + O.WalkwayWidth / 2
	local edge = roadHalf + O.WalkwayWidth -- outer guardrail line
	for i = 0, segs - 1 do
		local p0 = ovalPoint(O.Ax, O.Az, (i / segs) * 2 * math.pi)
		local p1 = ovalPoint(O.Ax, O.Az, ((i + 1) / segs) * 2 * math.pi)
		local d = p1 - p0
		local length = d.Magnitude
		local seg = CFrame.new(origin + (p0 + p1) / 2 + Vector3.new(0, O.Y, 0))
			* CFrame.Angles(0, math.atan2(d.X, d.Z), 0)
		local diag = if i % 2 == 0 then 1 else -1

		-- Road, then a dashed centre line on alternate segments.
		addPart(parent, "OvalRoad", seg, Vector3.new(O.Width, O.Thickness, length + 1), ROAD, Enum.Material.Asphalt)
		if i % 2 == 0 then
			addPart(
				parent,
				"LaneLine",
				seg * CFrame.new(0, O.Thickness / 2 + 0.06, 0),
				Vector3.new(0.6, 0.12, length * 0.5),
				LINE,
				Enum.Material.SmoothPlastic
			)
		end

		-- Wood-deck walkways on both sides; the inner one opens where a ramp merges (like the inner
		-- guardrail) so it doesn't cut across the driveable landing.
		for _, sx in { -1, 1 } do
			if sx == -1 and isRampGap(i, O) then
				continue
			end
			addPart(
				parent,
				"Walkway",
				seg * CFrame.new(sx * walkCenter, 0, 0),
				Vector3.new(O.WalkwayWidth, O.Thickness, length + 1),
				DECK,
				Enum.Material.WoodPlanks
			)
		end

		-- Inner guardrail except where a ramp merges on (there it must open); outer guardrail unless
		-- this is a view-deck segment.
		if not isRampGap(i, O) then
			guardrail(parent, seg, -edge, length, O, diag)
		end
		if i % O.ViewDeckEvery == 0 then
			buildViewDeck(parent, seg, length, O, edge)
		else
			guardrail(parent, seg, edge, length, O, diag)
		end

		if i % O.PillarEvery == 0 then
			-- Vertical cylinder from the water surface (Y=0) up to the deck (Cylinder's length is
			-- along local X, so rotate X->Y).
			local base = origin + p0
			addPart(
				parent,
				"Pillar",
				CFrame.new(base.X, origin.Y + O.Y / 2, base.Z) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(O.Y, O.PillarDiameter, O.PillarDiameter),
				PILLAR,
				Enum.Material.Concrete,
				0,
				Enum.PartType.Cylinder
			)
		end
	end
end

-- Ramps linking the ground perimeter loop up to the deck: one per 45 degrees (4 sides + 4 corners),
-- each with a glass guardrail down both sides.
local function buildRamps(parent: Instance, origin: Vector3, O: any, perimeterEdge: number, width: number)
	local count = O.Ramps
	for k = 0, count - 1 do
		local th = (k / count) * 2 * math.pi
		local c, s = math.cos(th), math.sin(th)
		-- Exit point where the ray hits the square perimeter, at ground level.
		local rEdge = perimeterEdge / math.max(math.abs(c), math.abs(s))
		local p0 = origin + Vector3.new(rEdge * c, 0, rEdge * s)
		-- Road-centre landing point on the oval ellipse in the same direction, at deck height.
		local rOval = 1 / math.sqrt((c / O.Ax) ^ 2 + (s / O.Az) ^ 2)
		local pLand = origin + Vector3.new(rOval * c, O.Y, rOval * s)
		-- The sloped ramp climbs only to pTop -- one landing-radius short of the road centre but already
		-- at deck height -- and a flat landing carries the rest of the turn onto the highway. Because the
		-- slope ends exactly where the flat landing begins (both at O.Y), the surfaces meet flush: the
		-- old design ran the slope to the centre and dropped a flat disc on top of the still-rising ramp,
		-- leaving a ledge a car couldn't climb.
		local landingRadius = width / 2 + 6
		local inward = Vector3.new(c, 0, s) * landingRadius
		local pTop = pLand - inward
		local rampLen = (pTop - p0).Magnitude
		-- lookAt puts the local -Z (and so the length axis) along the slope from p0 to pTop.
		local rampCF = CFrame.lookAt((p0 + pTop) / 2, pTop)
		addPart(parent, "Ramp", rampCF, Vector3.new(width, O.Thickness, rampLen), ROAD, Enum.Material.Asphalt)
		-- Flat landing, flush with the oval road (same Y + thickness): a radial connector the width of
		-- the ramp from pTop to the road centre, plus a disc that rounds the turn onto the curving road.
		addPart(
			parent,
			"RampLanding",
			CFrame.lookAt((pTop + pLand) / 2, pLand),
			Vector3.new(width, O.Thickness, landingRadius),
			ROAD,
			Enum.Material.Asphalt
		)
		addPart(
			parent,
			"RampMerge",
			CFrame.new(pLand) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(O.Thickness, 2 * landingRadius, 2 * landingRadius),
			ROAD,
			Enum.Material.Asphalt,
			nil,
			Enum.PartType.Cylinder
		)
		-- Glass guardrails down the sloped ramp's sides.
		for _, sx in { -1, 1 } do
			addGlass(
				parent,
				"Guardrail",
				rampCF * CFrame.new(sx * width / 2, O.GuardrailHeight / 2, 0),
				Vector3.new(O.GuardrailThickness, O.GuardrailHeight, rampLen)
			)
		end
		-- Tie each ramp side rail to the oval's inner rail (which resumes just past the 2-segment gap)
		-- so the barrier funnels into the ramp with no open sliver or doubled pane. Approximate the
		-- inner rail's gap-edge point by stepping `edge` inward along the radial at the boundary vertex.
		local function innerEdge(ti: number): Vector3
			local cp = origin + ovalPoint(O.Ax, O.Az, (ti / O.Segments) * 2 * math.pi)
			local radial = Vector3.new(cp.X - origin.X, 0, cp.Z - origin.Z).Unit
			return Vector3.new(cp.X, origin.Y + O.Y, cp.Z) - radial * (width / 2 + O.WalkwayWidth)
		end
		local i0 = k * (O.Segments / O.Ramps)
		local edgePlus, edgeMinus = innerEdge(i0 + 1), innerEdge(i0 - 1)
		for _, sx in { -1, 1 } do
			local railEnd = (rampCF * CFrame.new(sx * width / 2, 0, -rampLen / 2)).Position
			local ovalEdge = if (edgePlus - railEnd).Magnitude < (edgeMinus - railEnd).Magnitude
				then edgePlus
				else edgeMinus
			local d = ovalEdge - railEnd
			if d.Magnitude > 0.5 then
				local mid = (railEnd + ovalEdge) / 2 + Vector3.new(0, O.GuardrailHeight / 2, 0)
				addGlass(
					parent,
					"Guardrail",
					CFrame.lookAt(mid, mid + d.Unit),
					Vector3.new(O.GuardrailThickness, O.GuardrailHeight, d.Magnitude)
				)
			end
		end
	end
end

function IslandService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end

	local ring = Instance.new("Model")
	ring.Name = "HomeRing"
	ring.Parent = scenery

	local H = Config.Terrain.Home
	local origin = Config.Zones.Home
	local O = H.Ring.Oval
	-- Ground exits sit at the outer edge of the perimeter loop road.
	local perimeterEdge = H.PerimeterLine + H.RoadWidth / 2

	buildOval(ring, origin, O)
	buildRamps(ring, origin, O, perimeterEdge, O.Width)
end

return IslandService
