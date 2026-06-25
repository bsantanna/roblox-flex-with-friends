--!strict
-- FlowerService: scatters small flower clusters across every grass area in the Home zone.
-- Flowers are primitive clusters (stem + ball head) placed deterministically from Config.Flower.
-- Flowers live under Workspace.Scenery.Flowerbeds.
--
-- Green areas covered by construction:
--   1. Green belt -- computed from Config.Terrain.Home's grid geometry (outside perimeter walkway,
--      inside shoreline ellipse, clearing ramps and the farm paddock).
--   2. Park square -- the one grid square left as grass (ParkCell).
--   3. House gardens -- up to four corners per house square (same corner scheme as ForestService).
--
-- No asset dependency: flowers are pure primitives, generated at boot.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Manifest = require(ReplicatedStorage.Shared.SceneryManifest) :: any

local Flowers = require(ReplicatedStorage.Shared.Config.Flower)

local FlowerService = {}

local function pickColor(rng: Random): Color3
	return Flowers.Palette[rng:NextInteger(1, #Flowers.Palette)]
end

local function makeCluster(
	parent: Instance,
	base: CFrame,
	x: number,
	z: number,
	scale: number,
	color: Color3,
	rng: Random
)
	local sh = rng:NextNumber(Flowers.MinStemHeight, Flowers.MaxStemHeight) * scale
	local cf = base * CFrame.new(x, sh / 2, z)

	local stemWidth = Flowers.StemWidth * scale
	local stem = Instance.new("Part")
	stem.Name = "FlowerStem"
	stem.Anchored = true
	stem.Size = Vector3.new(stemWidth, sh, stemWidth)
	stem.CFrame = cf
	stem.Color = Flowers.StemColor
	stem.Material = Enum.Material.SmoothPlastic
	stem.Parent = parent

	local ringSize = Flowers.BaseRingSize * scale
	local ring = Instance.new("Part")
	ring.Name = "FlowerRing"
	ring.Anchored = true
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(ringSize, 0.15, ringSize)
	ring.CFrame = base * CFrame.new(x, ringSize / 2, z)
	ring.Color = Color3.fromRGB(80, 50, 20)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Parent = parent

	for i = 1, Flowers.HeadsPerCluster do
		local headSize = Flowers.HeadSize * scale
		local offsetX = (i - (Flowers.HeadsPerCluster + 1) / 2) * (headSize * 0.35)
		local offsetZ = (i == 1 and -1 or 0) * (headSize * 0.25)
		local headY = sh + headSize / 2 + (headSize * 0.1)
		local head = Instance.new("Part")
		head.Name = "FlowerHead"
		head.Anchored = true
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(headSize, headSize, headSize)
		head.CFrame = base * CFrame.new(x + offsetX, headY, z + offsetZ)
		head.Color = color
		head.Material = Enum.Material.SmoothPlastic
		head.Parent = parent
	end
end

local function greenBeltSites(): { Vector2 }
	local F = Config.Forest
	local H = Config.Terrain.Home
	local R = H.Ring
	local rng = Random.new(Flowers.Seed + 1)
	local sites: { Vector2 } = {}

	local beltInner = H.PerimeterLine + H.RoadWidth / 2 + Config.Roads.CurbWidth + F.RoadMargin
	local ax, az = R.Plateau.Ax - F.ShoreMargin, R.Plateau.Az - F.ShoreMargin

	local rampDirs: { Vector2 } = {}
	for k = 0, R.Oval.Ramps - 1 do
		local th = (k / R.Oval.Ramps) * 2 * math.pi
		table.insert(rampDirs, Vector2.new(math.cos(th), math.sin(th)))
	end

	local farm = Config.Farm
	local farmMinX = farm.Center.X - farm.Size.X / 2
	local farmMaxX = farm.Center.X + farm.Size.X / 2
	local farmMinZ = farm.Center.Z - farm.Size.Y / 2
	local farmMaxZ = farm.Center.Z + farm.Size.Y / 2

	local densitySq = Flowers.Density ^ 2

	local x = -ax
	while x <= ax do
		local z = -az
		while z <= az do
			local px = x + rng:NextNumber(-Flowers.Density, Flowers.Density)
			local pz = z + rng:NextNumber(-Flowers.Density, Flowers.Density)
			local onIsland = (px / ax) ^ 2 + (pz / az) ^ 2 <= 1
			local inTown = math.max(math.abs(px), math.abs(pz)) < beltInner
			local nearRamp = false
			for _, dir in rampDirs do
				local along = px * dir.X + pz * dir.Y
				local across = math.abs(px * dir.Y - pz * dir.X)
				if along > 0 and across < F.RampClearance then
					nearRamp = true
					break
				end
			end
			local nearFarm = px >= farmMinX and px <= farmMaxX and pz >= farmMinZ and pz <= farmMaxZ
			if onIsland and not inTown and not nearRamp and not nearFarm then
				table.insert(sites, Vector2.new(px, pz))
			end
			z += densitySq
		end
		x += densitySq
	end

	return sites
end

local function parkSites(): { Vector2 }
	local H = Config.Terrain.Home
	local rng = Random.new(Flowers.Seed + 2)
	local sites: { Vector2 } = {}

	local park = H.ParkCell
	local reach = H.CellSize / 2 - 2
	local parkJitter = 1

	local x2 = -reach
	while x2 <= reach do
		local z2 = -reach
		while z2 <= reach do
			table.insert(
				sites,
				Vector2.new(
					park.X + x2 + rng:NextNumber(-parkJitter, parkJitter),
					park.Z + z2 + rng:NextNumber(-parkJitter, parkJitter)
				)
			)
			z2 += Flowers.ParkDensity
		end
		x2 += Flowers.ParkDensity
	end

	return sites
end

function FlowerService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end

	local flowerbeds = Instance.new("Model")
	flowerbeds.Name = "Flowerbeds"
	flowerbeds.Parent = scenery

	local origin = Config.Zones.Home
	local base = CFrame.new(origin.X, origin.Y, origin.Z)
	local H = Config.Terrain.Home

	local rng = Random.new(Flowers.Seed)

	for _, site in greenBeltSites() do
		local scale = rng:NextNumber(0.8, 1.2)
		local color = pickColor(rng)
		makeCluster(flowerbeds, base, site.X, site.Y, scale, color, rng)
	end

	for _, site in parkSites() do
		local scale = rng:NextNumber(0.9, 1.1)
		local color = pickColor(rng)
		makeCluster(flowerbeds, base, site.X, site.Y, scale, color, rng)
	end

	task.spawn(function()
		local scene = Workspace:WaitForChild("Scenery", 30)
		local count = 0
		for _, entry in Manifest.assets :: { any } do
			local off = entry.offset
			local onLattice = function(v: number): boolean
				return v == -H.Pitch or v == 0 or v == H.Pitch
			end
			local isHouseCell = entry.kind == "mesh"
				and not entry.scatter
				and entry.zone == "Home"
				and onLattice(off[1])
				and onLattice(off[3])
				and not (off[1] == 0 and off[3] == 0)
			if not isHouseCell then
				continue
			end
			local house = scene:WaitForChild(entry.id, 10)
			if not (house and house:IsA("Model")) then
				continue
			end
			local cf, size = house:GetBoundingBox()
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local gx = off[1] + sx * Flowers.GardenInset
					local gz = off[3] + sz * Flowers.GardenInset
					local headHalf = Flowers.HeadSize * 1.2
					local dx = math.max(math.abs(gx - cf.X) - size.X / 2, 0)
					local dz = math.max(math.abs(gz - cf.Z) - size.Z / 2, 0)
					if dx * dx + dz * dz >= headHalf * headHalf then
						local scale = rng:NextNumber(0.8, 1.3)
						local color = pickColor(rng)
						makeCluster(flowerbeds, base, gx, gz, scale, color, rng)
						count += 1
					end
				end
			end
		end
		print("[FlowerService] garden sites planted:", count)
	end)
end

return FlowerService
