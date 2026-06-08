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
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrafficService = {}

type Graph = { pos: { Vector3 }, adj: { { number } } }
type Car = {
	model: Model,
	n0: number,
	n1: number,
	n2: number,
	n3: number,
	t: number,
	seg: number,
	speed: number,
	laned: Vector3, -- last lane position (for car-to-car spacing)
	fwd: Vector3, -- last horizontal heading
	stuck: number, -- seconds the car has been roughly stationary (stuck detection)
	checkPos: Vector3, -- reference position the stuck timer measures movement against
	balloon: BillboardGui?, -- the active "angry" comic balloon, if one is showing
}

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
local STOP_GAP = 9 -- fully stop if a car ahead is closer than this (about a car length)
local FOLLOW_GAP = 22 -- start easing off within this gap, down to STOP_GAP -> smooth car-following
local STUCK_MOVE = 2 -- studs; the car must shift at least this much or the stuck timer keeps counting
local BALLOON_FADE = 0.45 -- fade-in / fade-out seconds for the comic balloon
local BUBBLE_BG = Color3.fromRGB(255, 255, 255)
local BUBBLE_INK = Color3.fromRGB(24, 24, 28)

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

-- Centripetal Catmull-Rom through p1->p2 (p0,p3 are the neighbour nodes). The centripetal (alpha=0.5)
-- parametrisation keeps the curve tight at sharp turns; a uniform Catmull-Rom overshoots there and
-- would swing the cars wide off their lane onto the walkways. Returns position and a finite-diff tangent.
local function spline(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, lt: number): (Vector3, Vector3)
	local t1 = math.max((p1 - p0).Magnitude, 1e-2) ^ 0.5
	local t2 = t1 + math.max((p2 - p1).Magnitude, 1e-2) ^ 0.5
	local t3 = t2 + math.max((p3 - p2).Magnitude, 1e-2) ^ 0.5
	local function eval(t: number): Vector3
		local a1 = p0:Lerp(p1, t / t1)
		local a2 = p1:Lerp(p2, (t - t1) / (t2 - t1))
		local a3 = p2:Lerp(p3, (t - t2) / (t3 - t2))
		local b1 = a1:Lerp(a2, t / t2)
		local b2 = a2:Lerp(a3, (t - t1) / (t3 - t1))
		return b1:Lerp(b2, (t - t1) / (t2 - t1))
	end
	local g = t1 + lt * (t2 - t1)
	local e = (t2 - t1) * 0.01
	return eval(g), eval(g + e) - eval(g - e)
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

-- A comic speech balloon (rounded white bubble + downward tail + the angry emoji), built fully
-- transparent so it can be faded in. Returns the gui plus the {inst, prop} list of things to tween.
local function makeBalloon(): (BillboardGui, { { inst: Instance, prop: string } })
	local gui = Instance.new("BillboardGui")
	gui.Name = "StuckBalloon"
	gui.Size = UDim2.fromOffset(130, 130)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	gui.AlwaysOnTop = true -- render over the car/world so it stays clearly readable
	gui.LightInfluence = 0 -- not dimmed by lighting
	gui.MaxDistance = 240

	-- Tail: a rotated square poking out the bottom; the bubble (higher ZIndex) covers its top, so
	-- only the downward point shows -- a comic speech-bubble pointer aimed at the car.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.78)
	tail.Size = UDim2.fromScale(0.26, 0.26)
	tail.Rotation = 45
	tail.BackgroundColor3 = BUBBLE_BG
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	tail.Parent = gui
	local tstroke = Instance.new("UIStroke")
	tstroke.Thickness = 3
	tstroke.Color = BUBBLE_INK
	tstroke.Transparency = 1
	tstroke.Parent = tail

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.Position = UDim2.fromScale(0.5, 0)
	bubble.Size = UDim2.fromScale(1, 0.8)
	bubble.BackgroundColor3 = BUBBLE_BG
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.32, 0)
	corner.Parent = bubble
	local bstroke = Instance.new("UIStroke")
	bstroke.Thickness = 3
	bstroke.Color = BUBBLE_INK
	bstroke.Transparency = 1
	bstroke.Parent = bubble

	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.AnchorPoint = Vector2.new(0.5, 0.5)
	emoji.Position = UDim2.fromScale(0.5, 0.4)
	emoji.Size = UDim2.fromScale(0.74, 0.74)
	emoji.BackgroundTransparency = 1
	emoji.FontFace = Font.fromEnum(Enum.Font.GothamBold) -- modern font; the Instance.new default skips the emoji glyph
	emoji.Text = "🤬"
	emoji.TextScaled = true -- fill the bubble so it reads at distance
	emoji.TextColor3 = BUBBLE_INK
	emoji.TextTransparency = 1
	emoji.ZIndex = 3 -- BillboardGui ZIndex is Global; must beat the bubble (2) or it renders behind it
	emoji.Parent = bubble

	local fades: { { inst: Instance, prop: string } } = {
		{ inst = bubble, prop = "BackgroundTransparency" },
		{ inst = bstroke, prop = "Transparency" },
		{ inst = tail, prop = "BackgroundTransparency" },
		{ inst = tstroke, prop = "Transparency" },
		{ inst = emoji, prop = "TextTransparency" },
	}
	return gui, fades
end

local TWEEN_IN = TweenInfo.new(BALLOON_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(BALLOON_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Pop an angry comic balloon over the car: fade in, hold for BalloonSeconds, fade out, clean up.
local function showBalloon(car: Car)
	if car.balloon then
		return
	end
	local root = car.model.PrimaryPart
	if not root then
		return
	end
	local gui, fades = makeBalloon()
	gui.Adornee = root
	gui.Parent = root
	car.balloon = gui

	for _, f in fades do
		local goal: { [string]: any } = { [f.prop] = 0 }
		TweenService:Create(f.inst, TWEEN_IN, goal):Play()
	end

	task.delay(Config.Traffic.BalloonSeconds - BALLOON_FADE, function()
		if gui.Parent == nil then
			return
		end
		for _, f in fades do
			local goal: { [string]: any } = { [f.prop] = 1 }
			TweenService:Create(f.inst, TWEEN_OUT, goal):Play()
		end
		task.delay(BALLOON_FADE, function()
			gui:Destroy()
			if car.balloon == gui then
				car.balloon = nil
			end
		end)
	end)
end

-- Teleport a stuck car forward along its current route so it clears whatever blocked it (a player
-- in the lane, a gridlocked queue) and drives on -- advancing its spline parameter keeps it exactly
-- in-lane, rolling over graph nodes as needed.
local function respawnAhead(car: Car)
	car.t += Config.Traffic.RespawnAhead / car.seg
	while car.t >= 1 do
		car.t -= 1
		advance(car)
	end
	car.speed = Config.Traffic.Speed
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
			laned = graph.pos[n1],
			fwd = (graph.pos[n2] - graph.pos[n1]).Unit,
			stuck = 0,
			checkPos = graph.pos[n1],
			balloon = nil,
		}
		car.model.Parent = folder
		table.insert(cars, car)
	end

	RunService.Heartbeat:Connect(function(dt)
		local lane = Config.Traffic.LaneOffset
		for _, car in cars do
			-- Car-following: ease toward the speed that keeps a gap to the nearest car ahead in this
			-- lane (proportional, not a hard stop, so loops keep flowing instead of gridlocking); stop
			-- dead only for a player. Uses last frame's positions.
			local lead = math.huge
			for _, other in cars do
				if other ~= car then
					local to = other.laned - car.laned
					local ahead = to:Dot(car.fwd)
					if ahead > 0 and ahead < lead and (to - car.fwd * ahead).Magnitude < 4 then
						lead = ahead
					end
				end
			end
			local target
			if playerAhead(car.laned, car.fwd) then
				target = 0
			elseif lead < FOLLOW_GAP then
				target = Config.Traffic.Speed * math.clamp((lead - STOP_GAP) / (FOLLOW_GAP - STOP_GAP), 0, 1)
			else
				target = Config.Traffic.Speed
			end
			local a = if target > car.speed then ACCEL else -DECEL
			car.speed = math.clamp(car.speed + a * dt, 0, Config.Traffic.Speed)

			car.t += (car.speed * dt) / car.seg
			while car.t >= 1 do
				car.t -= 1
				advance(car)
			end

			local pos, tan = spline(graph.pos[car.n0], graph.pos[car.n1], graph.pos[car.n2], graph.pos[car.n3], car.t)
			if tan.Magnitude < 1e-3 then
				tan = graph.pos[car.n2] - graph.pos[car.n1]
			end
			tan = tan.Unit
			local flat = Vector3.new(tan.X, 0, tan.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else tan
			local right = Vector3.new(tan.Z, 0, -tan.X)
			right = if right.Magnitude > 1e-3 then right.Unit else Vector3.zero
			local laned = pos + right * lane
			car.laned = laned
			car.fwd = flat
			car.model:PivotTo(CFrame.lookAt(laned, laned + tan))

			-- Stuck detection: if the car has barely moved for StuckSeconds (a player blocking the lane,
			-- a gridlocked queue), pop an angry comic balloon and teleport it ahead on the road. The
			-- teleport lands next frame, far from checkPos, which resets the timer cleanly.
			if (laned - car.checkPos).Magnitude > STUCK_MOVE then
				car.checkPos = laned
				car.stuck = 0
			else
				car.stuck += dt
				if car.stuck >= Config.Traffic.StuckSeconds then
					showBalloon(car)
					respawnAhead(car)
					car.stuck = 0
					car.checkPos = laned
				end
			end
		end
	end)
end

return TrafficService
