--!strict
-- GymService: builds the gym equipment on the CentralBuilding's opened first floor. Each station is
-- a parametric assembly of primitives (no Roblox AI / mesh upload), the same approach SceneryService
-- uses for the beach props. Station positions/orientations are the tunables and live in
-- Config.Gym.Stations (the Phase-2 NPC spawner reads the same table to post a gym-goer at each one);
-- equipment geometry constants stay local here. Models live under Workspace.Gym.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GymService = {}

local FRAME = Color3.fromRGB(45, 48, 55) -- dark powder-coated metal
local BELT = Color3.fromRGB(25, 25, 28) -- treadmill belt / tyres / weight plates
local ACCENT = Color3.fromRGB(214, 69, 60) -- red cushions / seats
local STEEL = Color3.fromRGB(150, 156, 162) -- chrome bars and handles
local SCREEN = Color3.fromRGB(40, 120, 160) -- console screens
local MAT = Color3.fromRGB(58, 130, 200) -- exercise mats
local GLASS = Color3.fromRGB(184, 210, 224) -- mirror glass
local WHITE = Color3.fromRGB(238, 240, 242) -- water cooler body
local FLOOR = Color3.fromRGB(32, 34, 44) -- #20222C painted studio floor for the gym hall

type PartOpts = {
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
	reflectance: number?,
}

local function add(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	if o.shape then
		p.Shape = o.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A cylinder whose round axis lies along world X at the base orientation (Cylinder's length is its
-- local X). Used for wheels, barbells, weight plates: pass diameter for Y/Z, thickness for X.
local CYL: PartOpts = { shape = Enum.PartType.Cylinder, material = Enum.Material.Metal }

-- Treadmill: a raised running belt with side rails, a console panel at the front (-Z) and handlebars.
local function buildTreadmill(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 0.55, 0.5), Vector3.new(2.6, 0.5, 6), BELT) -- belt deck
	for _, sx in { -1.45, 1.45 } do
		add(model, base * CFrame.new(sx, 0.7, 0.5), Vector3.new(0.3, 0.5, 6), FRAME) -- side rails
	end
	add(model, base * CFrame.new(0, 2.3, -2.6), Vector3.new(2.8, 3.6, 0.4), FRAME) -- console upright
	add(model, base * CFrame.new(0, 3.0, -2.4), Vector3.new(1.7, 1.2, 0.15), SCREEN, { material = Enum.Material.Neon }) -- screen
	for _, sx in { -1.2, 1.2 } do
		add(
			model,
			base * CFrame.new(sx, 1.6, -1.9),
			Vector3.new(0.2, 2.4, 0.2),
			STEEL,
			{ material = Enum.Material.Metal }
		) -- handle posts
	end
	add(model, base * CFrame.new(0, 2.7, -1.9), Vector3.new(2.6, 0.2, 0.2), STEEL, { material = Enum.Material.Metal }) -- crossbar
end

-- Exercise bike: a side flywheel, a saddle on a post, handlebars at the front (-Z) and a foot frame.
local function buildExerciseBike(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 0.2, 0), Vector3.new(1.4, 0.4, 3.6), FRAME) -- floor stabiliser
	add(model, base * CFrame.new(0, 1.3, -1.0), Vector3.new(0.45, 2.4, 2.4), BELT, CYL) -- flywheel disc (axis along X)
	add(model, base * CFrame.new(0, 1.9, 0.8), Vector3.new(0.35, 2.6, 0.35), FRAME) -- saddle post
	add(model, base * CFrame.new(0, 3.0, 0.9), Vector3.new(1.0, 0.3, 1.6), ACCENT) -- saddle
	add(model, base * CFrame.new(0, 2.1, -0.55), Vector3.new(0.35, 3.2, 0.35), FRAME) -- handle column
	add(
		model,
		base * CFrame.new(0, 3.6, -0.55),
		Vector3.new(1.7, 0.22, 0.22),
		STEEL,
		{ material = Enum.Material.Metal }
	) -- handlebar
end

-- Weight bench: a padded bench with A-frame legs, two uprights and a loaded barbell at the head (-Z).
local function buildWeightBench(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 1.7, 0), Vector3.new(1.5, 0.4, 5), ACCENT) -- pad
	for _, sz in { -1.9, 1.9 } do
		add(model, base * CFrame.new(0, 0.85, sz), Vector3.new(1.4, 1.5, 0.4), FRAME) -- A-frame legs
	end
	for _, sx in { -1.05, 1.05 } do
		add(model, base * CFrame.new(sx, 2.6, -2.2), Vector3.new(0.35, 2.4, 0.35), FRAME) -- barbell uprights
	end
	add(model, base * CFrame.new(0, 3.7, -2.2), Vector3.new(5, 0.25, 0.25), STEEL, CYL) -- barbell
	for _, sx in { -2, 2 } do
		add(model, base * CFrame.new(sx, 3.7, -2.2), Vector3.new(0.5, 1.3, 1.3), BELT, CYL) -- weight plates
	end
end

-- Dumbbell rack: a two-tier frame holding rows of dumbbells (a chrome handle with two dark weights).
local function buildDumbbellRack(model: Model, base: CFrame)
	for _, sx in { -2.9, 2.9 } do
		add(model, base * CFrame.new(sx, 1.1, 0), Vector3.new(0.3, 2.2, 1.4), FRAME) -- side frames
	end
	for _, ty in { { 0.9, 0.45 }, { 1.7, 0 } } do
		add(model, base * CFrame.new(0, ty[1], ty[2]), Vector3.new(6, 0.25, 1.2), FRAME) -- a tray
		for _, dx in { -2, 0, 2 } do
			local d = base * CFrame.new(dx, ty[1] + 0.3, ty[2])
			add(model, d, Vector3.new(1.5, 0.22, 0.22), STEEL, { material = Enum.Material.Metal }) -- handle
			for _, hx in { -0.85, 0.85 } do
				add(model, d * CFrame.new(hx, 0, 0), Vector3.new(0.25, 0.75, 0.75), BELT, CYL) -- end weights
			end
		end
	end
end

-- Exercise mat: a thin floor pad (where the push-up / squat NPCs work out).
local function buildMat(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 0.1, 0), Vector3.new(4, 0.2, 6), MAT)
end

-- Mirror wall: a framed reflective panel along a wall.
local function buildMirrorWall(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 5, 0), Vector3.new(20, 9, 0.5), FRAME) -- backing / frame
	add(
		model,
		base * CFrame.new(0, 5, 0.3),
		Vector3.new(19, 8.4, 0.1),
		GLASS,
		{ reflectance = 0.45, material = Enum.Material.Glass }
	) -- mirror
end

-- Water cooler: a body with a blue bottle on top.
local function buildWaterCooler(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 1.5, 0), Vector3.new(1.4, 3, 1.4), WHITE) -- body
	add(
		model,
		base * CFrame.new(0, 3.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(1.5, 1, 1),
		Color3.fromRGB(120, 185, 220),
		{ shape = Enum.PartType.Cylinder, transparency = 0.35 }
	) -- bottle
end

local BUILDERS: { [string]: (Model, CFrame) -> () } = {
	Treadmill = buildTreadmill,
	ExerciseBike = buildExerciseBike,
	WeightBench = buildWeightBench,
	DumbbellRack = buildDumbbellRack,
	Mat = buildMat,
	MirrorWall = buildMirrorWall,
	WaterCooler = buildWaterCooler,
}

function GymService:Start()
	local gym = Workspace:FindFirstChild("Gym")
	if not gym then
		gym = Instance.new("Folder")
		gym.Name = "Gym"
		gym.Parent = Workspace
	end

	-- Paint the hall floor: a thin slab laid flush over the CentralBuilding's first-floor mesh surface
	-- (top y=23.02), sized to the gym-hall floor footprint measured in Studio. CanCollide off so players
	-- still stand on the mesh floor beneath; it only recolours what they see.
	local floor = add(gym, CFrame.new(-27.7, 22.89, -89.2), Vector3.new(62.3, 0.3, 102.9), FLOOR)
	floor.Name = "GymFloor"
	floor.CanCollide = false

	for i, station in Config.Gym.Stations do
		local builder = BUILDERS[station.Kind]
		if not builder then
			warn("GymService: no builder for station kind " .. station.Kind)
			continue
		end
		local base = CFrame.new(station.Position) * CFrame.Angles(0, math.rad(station.Yaw), 0)
		local model = Instance.new("Model")
		model.Name = station.Kind .. i
		builder(model, base)
		model.Parent = gym
	end
end

return GymService
