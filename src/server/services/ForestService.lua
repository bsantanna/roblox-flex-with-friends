--!strict
-- ForestService: scatters the Tree01 mesh (assets/manifest.json scatter entry, uploaded via
-- `make assets-upload`) across the Home island's grass: the green belt between the perimeter
-- walkway and the shoreline, a denser grove on the park square, and the corners of each house
-- garden. Belt/park sites are derived from Config.Terrain.Home's grid geometry, so trees stay off
-- roads, walkways, driveways, and the highway-ramp corridors by construction; garden corners are
-- planted only where they clear the placed house's measured bounds (house sizes vary widely). The
-- layout is deterministic (Config.Forest.Seed), so every server grows the same forest.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage.Shared.Config)
local Manifest = require(ReplicatedStorage.Shared.SceneryManifest) :: any
local AssetIds = require(ReplicatedStorage.Shared.SceneryAssetIds) :: { [string]: number }

local ForestService = {}

local TREE_ID = "Tree01"

-- Tree sites as X/Z offsets from the Home origin (the grass surface is flat at Y=0).
local function treeSites(): { Vector2 }
	local F = Config.Forest
	local H = Config.Terrain.Home
	local R = H.Ring
	local rng = Random.new(F.Seed)
	local sites: { Vector2 } = {}

	-- Green belt: between the outer edge of the perimeter walkway and the shoreline ellipse,
	-- skipping a corridor under each of the eight ground-to-highway ramps (they cross the belt).
	local beltInner = H.PerimeterLine + H.RoadWidth / 2 + Config.Roads.CurbWidth + F.RoadMargin
	local ax, az = R.Plateau.Ax - F.ShoreMargin, R.Plateau.Az - F.ShoreMargin
	local rampDirs: { Vector2 } = {}
	for k = 0, R.Oval.Ramps - 1 do
		local th = (k / R.Oval.Ramps) * 2 * math.pi
		table.insert(rampDirs, Vector2.new(math.cos(th), math.sin(th)))
	end

	-- Farm zone: keep trees out of the fenced paddock (plus a clearance margin).
	local farm = Config.Farm
	local farmMinX = farm.Center.X - farm.Size.X / 2
	local farmMaxX = farm.Center.X + farm.Size.X / 2
	local farmMinZ = farm.Center.Z - farm.Size.Y / 2
	local farmMaxZ = farm.Center.Z + farm.Size.Y / 2

	local x = -ax
	while x <= ax do
		local z = -az
		while z <= az do
			local px = x + rng:NextNumber(-F.Jitter, F.Jitter)
			local pz = z + rng:NextNumber(-F.Jitter, F.Jitter)
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
			z += F.Spacing
		end
		x += F.Spacing
	end

	-- Park square: the one grid square left as grass gets a denser grove.
	local park = H.ParkCell
	local reach = H.CellSize / 2 - F.ParkInset
	local parkJitter = F.ParkInset / 2
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
			z2 += F.ParkSpacing
		end
		x2 += F.ParkSpacing
	end

	return sites
end

-- An asset is briefly unloadable on a fresh server (same window MeshSceneryService retries over).
local function loadTemplate(assetId: number): Model?
	local ATTEMPTS, BACKOFF = 20, 3
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function(): Instance
			return InsertService:LoadAsset(assetId)
		end)
		if ok and result then
			return result :: Model
		end
		if attempt < ATTEMPTS then
			task.wait(BACKOFF)
		else
			warn(`[ForestService] LoadAsset {assetId} failed after {attempt} tries: {tostring(result)}`)
		end
	end
	return nil
end

-- Clone the template into `forest` at the Home-relative X/Z site: random scale and facing from
-- `rng`, base seated on the grass (Y=0) — the mesh pivot isn't its base, and shifts under ScaleTo.
local function placeTree(forest: Model, template: Model, rng: Random, x: number, z: number)
	local F = Config.Forest
	local origin = Config.Zones.Home
	local tree = template:Clone()
	tree:ScaleTo(rng:NextNumber(F.ScaleMin, F.ScaleMax))
	tree:PivotTo(CFrame.new(origin + Vector3.new(x, 0, z)) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0))
	local cf, size = tree:GetBoundingBox()
	tree:PivotTo(tree:GetPivot() + Vector3.new(0, origin.Y - (cf.Y - size.Y / 2), 0))
	tree.Parent = forest
end

-- Garden corners: up to four trees per house square. House meshes vary widely in size (manifest
-- scale 14..32 — the biggest fill their whole square), so a corner is planted only if the tree's
-- canopy clears the house's *measured* bounding box once MeshSceneryService has placed it. Each
-- house loads asynchronously, so this waits per cell and quietly plants nothing on a timeout.
local function plantGardens(forest: Model, template: Model, scenery: Instance, doneWithTemplate: () -> ())
	local F = Config.Forest
	local H = Config.Terrain.Home
	local canopyHalf = template:GetExtentsSize().X / 2
	local pending = 0
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
		pending += 1
		task.spawn(function()
			local house = scenery:WaitForChild(entry.id, 150)
			if house and house:IsA("Model") then
				local cf, size = house:GetBoundingBox()
				local rng = Random.new(F.Seed + off[1] * 31 + off[3])
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local px = off[1] + sx * F.GardenInset
						local pz = off[3] + sz * F.GardenInset
						local reach = canopyHalf * F.ScaleMax
						local dx = math.max(math.abs(px - cf.X) - size.X / 2, 0)
						local dz = math.max(math.abs(pz - cf.Z) - size.Z / 2, 0)
						if dx * dx + dz * dz >= reach * reach then
							placeTree(forest, template, rng, px, pz)
						end
					end
				end
			end
			pending -= 1
			if pending == 0 then
				doneWithTemplate()
			end
		end)
	end
	if pending == 0 then
		doneWithTemplate()
	end
end

function ForestService:Start()
	-- Not uploaded yet (no recorded asset id): skip quietly so a pending asset never breaks boot.
	local assetId = AssetIds[TREE_ID]
	if not assetId then
		return
	end

	task.spawn(function()
		local template = loadTemplate(assetId)
		if not template then
			return
		end
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end

		local scenery = Workspace:FindFirstChild("Scenery")
		if not scenery then
			scenery = Instance.new("Folder")
			scenery.Name = "Scenery"
			scenery.Parent = Workspace
		end
		local forest = Instance.new("Model")
		forest.Name = "Forest"

		local rng = Random.new(Config.Forest.Seed + 1)
		for _, site in treeSites() do
			placeTree(forest, template, rng, site.X, site.Y)
		end
		forest.Parent = scenery

		plantGardens(forest, template, scenery, function()
			template:Destroy()
		end)
	end)
end

return ForestService
