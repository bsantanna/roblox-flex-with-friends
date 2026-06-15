--!strict
-- FarmService: builds the FARM on the Home island's north-east green belt -- a procedural white
-- post-and-rail fence (primitives, like the gym equipment in GymService) enclosing a grassy paddock,
-- then populates it with farm animals that gently wander inside the rails. The pen footprint and the
-- fence/animal tunables live in Config.Farm, so the area is reproducible from src.
--
-- Animals are assembled in code from uploaded Blender part meshes (Config.Farm.Animals.Species ->
-- SceneryAssetIds): a body root plus N legs, all anchored, animated kinematically -- the legs swing
-- fore/aft for a walk cycle and the body bobs, driven each Heartbeat from the wander state. No physics
-- and no animation assets: every pose is computed, so it is deterministic and reproducible. Until a
-- species' meshes are uploaded the populate step skips that kind (a pending asset never breaks boot,
-- the same contract MeshSceneryService/ForestService use). The pen sits on grass clear of the
-- perimeter road, the ring highway, and the shoreline, and encloses a few belt trees -- those are
-- obstacles so animals keep off the trunks. Everything lives under Workspace.Farm.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage.Shared.Config)
local AssetIds = require(ReplicatedStorage.Shared.SceneryAssetIds) :: { [string]: number }

local FarmService = {}

local FENCE = Config.Farm.Fence
local ANIM = Config.Farm.Animals

-- Pen bounds (Home-relative world coords; the grass surface is flat at Y=0).
local center = Config.Farm.Center
local minX = center.X - Config.Farm.Size.X / 2
local maxX = center.X + Config.Farm.Size.X / 2
local minZ = center.Z - Config.Farm.Size.Y / 2
local maxZ = center.Z + Config.Farm.Size.Y / 2

-- ===== Fence =====================================================================================

local function makePart(farm: Instance, cframe: CFrame, size: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = FENCE.Color
	p.Material = FENCE.Material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = farm
	return p
end

-- One side of the fence between a..b. `axis` is the side's long axis ("X" varies X at the fixed Z,
-- "Z" varies Z at the fixed X): posts at PostSpacing intervals plus a long rail board at each height.
local function buildRun(farm: Instance, axis: string, fixed: number, a: number, b: number)
	local len = b - a
	local n = math.max(1, math.floor(len / FENCE.PostSpacing + 0.5))
	for i = 0, n do
		local t = a + len * (i / n)
		local pos = if axis == "X"
			then Vector3.new(t, FENCE.PostSize.Y / 2, fixed)
			else Vector3.new(fixed, FENCE.PostSize.Y / 2, t)
		makePart(farm, CFrame.new(pos), FENCE.PostSize)
	end
	local mid = (a + b) / 2
	for _, h in FENCE.RailHeights do
		local pos = if axis == "X" then Vector3.new(mid, h, fixed) else Vector3.new(fixed, h, mid)
		local size = if axis == "X"
			then Vector3.new(len, FENCE.RailBoardHeight, FENCE.RailThickness)
			else Vector3.new(FENCE.RailThickness, FENCE.RailBoardHeight, len)
		makePart(farm, CFrame.new(pos), size)
	end
end

-- The four sides; the town-facing west side (x = minX) leaves a centred gate gap.
local function buildFence(farm: Instance)
	buildRun(farm, "X", minZ, minX, maxX) -- north
	buildRun(farm, "X", maxZ, minX, maxX) -- south
	buildRun(farm, "Z", maxX, minZ, maxZ) -- east
	local gateCentre = (minZ + maxZ) / 2
	buildRun(farm, "Z", minX, minZ, gateCentre - FENCE.GateWidth / 2)
	buildRun(farm, "Z", minX, gateCentre + FENCE.GateWidth / 2, maxZ)
end

-- ===== Animals ===================================================================================

type Leg = { part: MeshPart, hip: CFrame, phase: number }
type Animal = {
	root: MeshPart,
	legs: { Leg },
	legHalfHeight: number,
	species: any,
	x: number,
	z: number,
	y: number, -- body-centre height with feet on the grass
	yaw: number,
	radius: number,
	walking: boolean,
	tx: number,
	tz: number,
	pauseUntil: number,
	gait: number, -- accumulating gait phase
	swing: number, -- eased 0..1 walk amount, for smooth start/stop
}

local rng = Random.new(ANIM.Seed)
local trees: { Vector2 } = {} -- pasture-tree trunks inside the pen, treated as obstacles
local animals: { Animal } = {}
local meshCache: { [string]: MeshPart } = {} -- idKey -> template MeshPart (cloned per instance)

-- Load a single-mesh asset once and keep an anchored template MeshPart to clone. Returns nil if the
-- asset isn't uploaded yet or never loads (the briefly-unloadable window other services retry over).
local function loadMesh(idKey: string): MeshPart?
	if meshCache[idKey] then
		return meshCache[idKey]
	end
	local assetId = AssetIds[idKey]
	if not assetId then
		return nil
	end
	local ATTEMPTS, BACKOFF = 20, 3
	for attempt = 1, ATTEMPTS do
		local ok, container = pcall(function(): Instance
			return InsertService:LoadAsset(assetId)
		end)
		if ok and container then
			local mp = container:FindFirstChildWhichIsA("MeshPart", true)
			if mp then
				mp.Parent = nil
				mp.Anchored = true
				meshCache[idKey] = mp
				container:Destroy()
				return mp
			end
			container:Destroy()
		end
		if attempt < ATTEMPTS then
			task.wait(BACKOFF)
		end
	end
	return nil
end

local function snapshotTrees()
	table.clear(trees)
	local scenery = Workspace:FindFirstChild("Scenery")
	local forest = scenery and scenery:FindFirstChild("Forest")
	if not forest then
		return
	end
	for _, t in forest:GetChildren() do
		if t:IsA("Model") then
			local p = t:GetPivot().Position
			if p.X >= minX and p.X <= maxX and p.Z >= minZ and p.Z <= maxZ then
				table.insert(trees, Vector2.new(p.X, p.Z))
			end
		end
	end
end

local function clearOfTrees(x: number, z: number, radius: number): boolean
	local need = ANIM.TreeClearance + radius
	local at = Vector2.new(x, z)
	for _, trunk in trees do
		if (at - trunk).Magnitude < need then
			return false
		end
	end
	return true
end

-- A random point inside the rails (minus the edge/obstacle margins); falls back to any in-bounds
-- point if the pen is too crowded to find a clear one, so a busy pasture never deadlocks.
local function pickPoint(radius: number): (number, number)
	local loX, hiX = minX + ANIM.EdgeMargin + radius, maxX - ANIM.EdgeMargin - radius
	local loZ, hiZ = minZ + ANIM.EdgeMargin + radius, maxZ - ANIM.EdgeMargin - radius
	for _ = 1, 30 do
		local x, z = rng:NextNumber(loX, hiX), rng:NextNumber(loZ, hiZ)
		if clearOfTrees(x, z, radius) then
			return x, z
		end
	end
	return rng:NextNumber(loX, hiX), rng:NextNumber(loZ, hiZ)
end

local function lerpAngle(from: number, to: number, t: number): number
	local d = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + d * t
end

-- Leg layout for `count` legs: hip offsets (forward X, side ±Z) and gait phase, so a diagonal pair
-- swings together. Front legs use HipForwardFront, back legs HipForwardBack; a 2-legged animal puts
-- both legs at the front offset.
local function legLayout(species: any): { { fx: number, side: number, phase: number } }
	local layout = {}
	if species.Legs >= 4 then
		layout = {
			{ fx = species.HipForwardFront, side = 1, phase = 0 },
			{ fx = species.HipForwardFront, side = -1, phase = math.pi },
			{ fx = species.HipForwardBack, side = 1, phase = math.pi },
			{ fx = species.HipForwardBack, side = -1, phase = 0 },
		}
	else
		layout = {
			{ fx = species.HipForwardFront, side = 1, phase = 0 },
			{ fx = species.HipForwardFront, side = -1, phase = math.pi },
		}
	end
	return layout
end

-- Build one animal: a body root mesh plus its legs, scaled/coloured, seated with feet on the grass.
local function buildAnimal(farm: Instance, species: any): boolean
	local bodyTemplate = loadMesh(species.Body)
	local legTemplate = loadMesh(species.Leg)
	if not (bodyTemplate and legTemplate) then
		return false
	end
	local scale = species.Scale
	local model = Instance.new("Model")

	local root = bodyTemplate:Clone()
	root.Size = bodyTemplate.Size * scale
	root.Color = species.BodyColor
	root.Material = species.Material
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root

	local legHalfHeight = (legTemplate.Size.Y * scale) / 2
	local legs: { Leg } = {}
	for _, slot in legLayout(species) do
		local leg = legTemplate:Clone()
		leg.Size = legTemplate.Size * scale
		leg.Color = species.LegColor
		leg.Material = species.Material
		leg.Anchored = true
		leg.Parent = model
		local hip = CFrame.new(slot.fx * scale, -species.HipDown * scale, slot.side * species.HipSide * scale)
		table.insert(legs, { part = leg, hip = hip, phase = slot.phase })
	end

	local extents = root.Size
	local radius = math.max(extents.X, extents.Z) / 2
	local x, z = pickPoint(radius)
	local y = (species.HipDown + legTemplate.Size.Y) * scale -- body-centre height: feet at grass (Y=0)
	local tx, tz = pickPoint(radius)
	model.Parent = farm
	table.insert(animals, {
		root = root,
		legs = legs,
		legHalfHeight = legHalfHeight,
		species = species,
		x = x,
		z = z,
		y = y,
		yaw = rng:NextNumber(0, 2 * math.pi),
		radius = radius,
		walking = false,
		tx = tx,
		tz = tz,
		pauseUntil = os.clock() + rng:NextNumber(0, ANIM.PauseMax),
		gait = rng:NextNumber(0, 2 * math.pi),
		swing = 0,
	})
	return true
end

-- Advance every animal one frame: walk toward the target (turning the body's forward, +X, to face
-- travel), idle a random pause, then pick the next target. Legs swing while walking (eased in/out)
-- and the body bobs; all poses are set kinematically on the anchored parts.
local function step(dt: number)
	local now = os.clock()
	for _, a in animals do
		local sp = a.species
		if a.walking then
			local dx, dz = a.tx - a.x, a.tz - a.z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < 0.5 then
				a.walking = false
				a.pauseUntil = now + rng:NextNumber(ANIM.PauseMin, ANIM.PauseMax)
			else
				local move = math.min(ANIM.WanderSpeed * dt, dist)
				a.x += (dx / dist) * move
				a.z += (dz / dist) * move
				a.yaw = lerpAngle(a.yaw, math.atan2(-dz, dx), math.min(ANIM.TurnSpeed * dt, 1))
				a.gait += dt * sp.WalkFreq * 2 * math.pi
			end
		elseif now >= a.pauseUntil then
			a.tx, a.tz = pickPoint(a.radius)
			a.walking = true
		end

		-- ease the leg swing in/out so starts and stops aren't abrupt
		a.swing += ((a.walking and 1 or 0) - a.swing) * math.min(dt * 6, 1)
		local bob = math.sin(now * sp.BobFreq * 2 * math.pi) * sp.BobAmplitude * (0.4 + 0.6 * a.swing)
		local rootCf = CFrame.new(a.x, a.y + bob, a.z) * CFrame.Angles(0, a.yaw, 0)
		a.root.CFrame = rootCf
		for _, leg in a.legs do
			local angle = math.sin(a.gait + leg.phase) * sp.WalkSwing * a.swing
			leg.part.CFrame = rootCf * leg.hip * CFrame.Angles(0, 0, angle) * CFrame.new(0, -a.legHalfHeight, 0)
		end
	end
end

-- Build the roster, then start the wander/animation loop -- in its own task so it can wait for the
-- async forest to settle (trees become obstacles) and for the animal meshes to load.
local function populate(farm: Instance)
	task.spawn(function()
		local scenery = Workspace:WaitForChild("Scenery", 30)
		local forest = scenery and scenery:WaitForChild("Forest", 30)
		if forest then
			local last = -1
			while #forest:GetChildren() ~= last do
				last = #forest:GetChildren()
				task.wait(2)
			end
		end
		snapshotTrees()

		local any = false
		for _, entry in ANIM.Roster do
			local species = ANIM.Species[entry.Kind]
			if not species then
				continue -- this animal isn't modelled yet
			end
			for _ = 1, entry.Count do
				if buildAnimal(farm, species) then
					any = true
				end
			end
		end
		if any then
			RunService.Heartbeat:Connect(step)
		end
	end)
end

function FarmService:Start()
	local farm = Workspace:FindFirstChild("Farm")
	if not farm then
		local folder = Instance.new("Folder")
		folder.Name = "Farm"
		folder.Parent = Workspace
		farm = folder
	end
	buildFence(farm)
	populate(farm)
end

return FarmService
