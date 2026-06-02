--!strict
-- SceneryService: builds the visual scenery models in code from primitives — no Roblox AI / cloud.
-- Each model is parametric (assembled from blocks/cylinders/spheres), placed from Config.Zones plus
-- a per-model offset that mirrors assets/manifest.json (adjusted so nothing covers the spawn/roads).
-- This is the code implementation of the manifest's "buildable" assets; the manifest stays the
-- design spec, and AI-generated models can replace these later without changing placement. Models
-- live under Workspace.Scenery.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SceneryService = {}

local WALL = Color3.fromRGB(236, 228, 214)
local GLASS = Color3.fromRGB(174, 198, 207)
local ROOF = Color3.fromRGB(70, 70, 82)
local DARKWOOD = Color3.fromRGB(80, 55, 35)
local BLACK = Color3.fromRGB(24, 24, 28)
local TAXI = Color3.fromRGB(240, 200, 40)
local METAL = Color3.fromRGB(221, 227, 234)
local THATCH = Color3.fromRGB(169, 116, 79)
local WHITE = Color3.fromRGB(245, 245, 245)
local FROND = Color3.fromRGB(62, 142, 65)
local TRUNK = Color3.fromRGB(139, 90, 43)
local CUSHION = Color3.fromRGB(232, 213, 183)
local GOLD = Color3.fromRGB(212, 175, 55)

type PartOpts = { material: Enum.Material?, transparency: number?, shape: Enum.PartType? }

local function add(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	if o.shape then
		p.Shape = o.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A vertical cylinder (Cylinder's length is along local X, so rotate X->Y).
local function pillar(
	parent: Instance,
	base: CFrame,
	x: number,
	y: number,
	z: number,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
)
	add(
		parent,
		base * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, diameter, diameter),
		color,
		{
			shape = Enum.PartType.Cylinder,
			material = material,
		}
	)
end

local function buildHouse(model: Model, base: CFrame)
	local w, h, d = 44, 16, 32
	add(model, base * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), WALL) -- body
	add(model, base * CFrame.new(0, h + 0.5, 0), Vector3.new(w + 2, 1, d + 2), ROOF) -- flat roof
	add(
		model,
		base * CFrame.new(0, h * 0.45, d / 2),
		Vector3.new(w - 6, h - 4, 1),
		GLASS,
		{ material = Enum.Material.Glass, transparency = 0.35 }
	) -- glass front
	add(model, base * CFrame.new(0, 4, d / 2 + 0.1), Vector3.new(5, 8, 0.6), DARKWOOD) -- door
	-- second-floor balcony
	add(model, base * CFrame.new(0, h * 0.62, d / 2 + 2.5), Vector3.new(22, 0.6, 5), ROOF)
	add(model, base * CFrame.new(0, h * 0.62 + 1.2, d / 2 + 4.8), Vector3.new(22, 1.4, 0.3), WALL)
	-- side windows
	for _, sx in { -1, 1 } do
		for _, wz in { -8, 8 } do
			add(
				model,
				base * CFrame.new(sx * (w / 2 + 0.05), 9, wz),
				Vector3.new(0.5, 5, 6),
				GLASS,
				{ material = Enum.Material.Glass, transparency = 0.4 }
			)
		end
	end
end

local function buildCab(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 2, 0), Vector3.new(10, 3, 5), BLACK) -- body
	add(model, base * CFrame.new(-0.5, 4.2, 0), Vector3.new(6, 2.4, 4.6), BLACK) -- cabin
	add(
		model,
		base * CFrame.new(-0.5, 4.4, 0),
		Vector3.new(6.1, 1.5, 4.7),
		GLASS,
		{ material = Enum.Material.Glass, transparency = 0.45 }
	) -- windows
	add(model, base * CFrame.new(0, 5.9, 0), Vector3.new(2.4, 0.9, 1.2), TAXI) -- taxi sign
	for _, sx in { -3.4, 3.4 } do
		for _, sz in { -2.4, 2.4 } do
			add(model, base * CFrame.new(sx, 1, sz), Vector3.new(0.8, 2, 2), BLACK, { shape = Enum.PartType.Cylinder })
		end
	end
	add(model, base * CFrame.new(5.05, 2, -1.4), Vector3.new(0.4, 0.9, 0.9), TAXI, { shape = Enum.PartType.Ball }) -- headlight
	add(model, base * CFrame.new(5.05, 2, 1.4), Vector3.new(0.4, 0.9, 0.9), TAXI, { shape = Enum.PartType.Ball })
end

local function buildTerminal(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 7, 0), Vector3.new(60, 14, 20), METAL, { material = Enum.Material.Concrete })
	add(model, base * CFrame.new(0, 14.5, 0), Vector3.new(62, 1, 22), ROOF)
	add(
		model,
		base * CFrame.new(0, 6, 10.1),
		Vector3.new(56, 10, 1),
		GLASS,
		{ material = Enum.Material.Glass, transparency = 0.35 }
	)
	add(model, base * CFrame.new(0, 12, 10.4), Vector3.new(18, 2, 0.5), Color3.fromRGB(30, 111, 186)) -- departures sign band
	for _, sx in { -24, -12, 0, 12, 24 } do
		pillar(model, base, sx, 6, 10.6, 12, 1, METAL)
	end
end

local function buildBoardingGate(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 1.5, 0), Vector3.new(3, 3, 2), Color3.fromRGB(120, 120, 130)) -- podium
	pillar(model, base, -3, 3, 0, 6, 0.6, METAL) -- sign post
	add(model, base * CFrame.new(-3, 6, 0), Vector3.new(0.4, 3, 4), Color3.fromRGB(30, 111, 186)) -- gate sign
	add(model, base * CFrame.new(0, 3, 10), Vector3.new(4, 5, 16), Color3.fromRGB(150, 150, 160)) -- jet bridge
end

local function buildAirplane(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 6, 0), Vector3.new(40, 6, 6), WHITE, { shape = Enum.PartType.Cylinder }) -- fuselage
	add(model, base * CFrame.new(20, 6, 0), Vector3.new(6, 5.6, 5.6), WHITE, { shape = Enum.PartType.Ball }) -- nose
	add(model, base * CFrame.new(0, 6, 0), Vector3.new(40, 1, 0.2), GOLD) -- stripe
	add(model, base * CFrame.new(0, 6, 0), Vector3.new(8, 0.6, 34), WHITE) -- main wing
	add(model, base * CFrame.new(-17, 9, 0), Vector3.new(5, 6, 0.6), WHITE) -- tail fin
	add(model, base * CFrame.new(-15, 6, 0), Vector3.new(8, 0.5, 12), WHITE) -- tailplane
	for _, sz in { -10, 10 } do
		add(
			model,
			base * CFrame.new(2, 4.2, sz),
			Vector3.new(6, 2.2, 2.2),
			Color3.fromRGB(60, 60, 70),
			{ shape = Enum.PartType.Cylinder }
		) -- engine
	end
end

local function buildBeachCabana(model: Model, base: CFrame)
	for _, sx in { -8, 8 } do
		for _, sz in { -8, 8 } do
			pillar(model, base, sx, 3.5, sz, 7, 0.8, DARKWOOD, Enum.Material.Wood)
		end
	end
	add(model, base * CFrame.new(0, 7.4, 0), Vector3.new(20, 1.2, 20), THATCH, { material = Enum.Material.Grass })
	add(model, base * CFrame.new(0, 8.4, 0), Vector3.new(13, 1, 13), THATCH, { material = Enum.Material.Grass }) -- tiered peak
	add(model, base * CFrame.new(0, 1.6, -7), Vector3.new(12, 3, 2), DARKWOOD, { material = Enum.Material.Wood }) -- bar counter
	for _, sx in { -8.1, 8.1 } do
		add(
			model,
			base * CFrame.new(sx, 3.5, 0),
			Vector3.new(0.3, 6, 14),
			WHITE,
			{ material = Enum.Material.Fabric, transparency = 0.25 }
		) -- curtains
	end
end

local function buildPalmTree(model: Model, base: CFrame)
	pillar(model, base, 0, 8, 0, 16, 1.6, TRUNK, Enum.Material.Wood) -- trunk
	for i = 0, 5 do
		local a = math.rad(i * 60)
		add(
			model,
			base * CFrame.new(math.cos(a) * 3.5, 15.5, math.sin(a) * 3.5) * CFrame.Angles(math.rad(20), -a, 0),
			Vector3.new(7, 0.4, 2.2),
			FROND,
			{ material = Enum.Material.Grass }
		) -- fronds
	end
	for _, sx in { -0.8, 0.8 } do
		add(model, base * CFrame.new(sx, 15, 0), Vector3.new(1, 1, 1), TRUNK, { shape = Enum.PartType.Ball }) -- coconuts
	end
end

local function buildSunLounger(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 0.7, 0), Vector3.new(3, 0.4, 7), DARKWOOD, { material = Enum.Material.Wood }) -- frame
	add(
		model,
		base * CFrame.new(0, 0.95, 0.3),
		Vector3.new(2.6, 0.4, 6.4),
		CUSHION,
		{ material = Enum.Material.Fabric }
	) -- cushion
	add(
		model,
		base * CFrame.new(0, 1.6, -3) * CFrame.Angles(math.rad(-35), 0, 0),
		Vector3.new(2.6, 0.4, 3),
		CUSHION,
		{ material = Enum.Material.Fabric }
	) -- backrest
	for _, sx in { -1.3, 1.3 } do
		for _, sz in { -3, 3 } do
			add(
				model,
				base * CFrame.new(sx, 0.25, sz),
				Vector3.new(0.3, 0.5, 0.3),
				DARKWOOD,
				{ material = Enum.Material.Wood }
			) -- legs
		end
	end
	add(model, base * CFrame.new(2.6, 0.75, -2), Vector3.new(1.4, 1.5, 1.4), WHITE) -- side table
	add(
		model,
		base * CFrame.new(2.6, 1.7, -2),
		Vector3.new(0.6, 0.8, 0.6),
		Color3.fromRGB(230, 120, 90),
		{ shape = Enum.PartType.Cylinder }
	) -- drink
end

type Placement = { id: string, zone: string, offset: Vector3, rotationY: number, build: (Model, CFrame) -> () }

-- Offsets mirror assets/manifest.json, nudged so the House/Cab clear the Home spawn and crossroad.
local PLACEMENTS: { Placement } = {
	{ id = "House", zone = "Home", offset = Vector3.new(30, 0, -26), rotationY = 0, build = buildHouse },
	{ id = "Cab", zone = "Home", offset = Vector3.new(0, 0, 38), rotationY = 0, build = buildCab },
	{ id = "Terminal", zone = "Airport", offset = Vector3.new(0, 0, -20), rotationY = 0, build = buildTerminal },
	{ id = "BoardingGate", zone = "Airport", offset = Vector3.new(0, 0, 10), rotationY = 0, build = buildBoardingGate },
	{ id = "Airplane", zone = "Airport", offset = Vector3.new(18, 0, 30), rotationY = 90, build = buildAirplane },
	{ id = "BeachCabana", zone = "Beach", offset = Vector3.new(0, 0, 0), rotationY = 0, build = buildBeachCabana },
	{ id = "PalmTree", zone = "Beach", offset = Vector3.new(-22, 0, 12), rotationY = 0, build = buildPalmTree },
	{ id = "SunLounger", zone = "Beach", offset = Vector3.new(14, 0, 6), rotationY = -90, build = buildSunLounger },
}

function SceneryService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end

	for _, placement in PLACEMENTS do
		local origin = Config.Zones[placement.zone]
		local base = CFrame.new(origin + placement.offset) * CFrame.Angles(0, math.rad(placement.rotationY), 0)
		local model = Instance.new("Model")
		model.Name = placement.id
		placement.build(model, base)
		model.Parent = scenery
	end
end

return SceneryService
