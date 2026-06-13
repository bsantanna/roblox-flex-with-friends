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

local DARKWOOD = Color3.fromRGB(80, 55, 35)
local THATCH = Color3.fromRGB(169, 116, 79)
local WHITE = Color3.fromRGB(245, 245, 245)
local FROND = Color3.fromRGB(62, 142, 65)
local TRUNK = Color3.fromRGB(139, 90, 43)
local CUSHION = Color3.fromRGB(232, 213, 183)

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

type Placement = {
	id: string,
	zone: string,
	offset: Vector3,
	rotationY: number,
	scale: number?,
	build: (Model, CFrame) -> (),
}

-- The player's home is the CentralBuilding mesh on the plaza (assets/manifest.json); the
-- north-center square of the neighborhood grid is a free lot.
local PLACEMENTS: { Placement } = {
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
		if placement.scale then
			model:ScaleTo(placement.scale)
			-- ScaleTo grows about the pivot, dropping the base below the floor; reseat it to Y=origin.Y.
			local cf, size = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(0, origin.Y - (cf.Y - size.Y / 2), 0))
		end
		model.Parent = scenery
	end
end

return SceneryService
