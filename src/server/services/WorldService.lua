--!strict
-- WorldService: constructs the static world in code so the place is reproducible from src
-- (Rojo doesn't manage Workspace; make build produces an empty Workspace). Phase 1 builds the
-- Home zone: a floor, a SpawnLocation, and the Phone / Computer / Cab interaction anchors, each
-- carrying a named ProximityPrompt. Grey-box geometry for now; visual ProceduralModels can
-- replace these parts later without changing the interaction contract (the prompt names).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldService = {}

-- Interaction anchors: name -> { offset from zone origin, prompt action/object text }.
local HOME_INTERACTIONS = {
	{ name = "Phone", offset = Vector3.new(-15, 2, -15), action = "Use", object = "Phone" },
	{ name = "Computer", offset = Vector3.new(15, 2, -15), action = "Use", object = "Computer" },
	{ name = "Cab", offset = Vector3.new(0, 2, 25), action = "Travel", object = "Cab" },
}

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = color
	part.Parent = parent
	return part
end

local function addPrompt(part: BasePart, name: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part
end

local ZONE_FLOOR_COLOR = {
	Home = Color3.fromRGB(120, 120, 130),
	Airport = Color3.fromRGB(90, 110, 140),
	Beach = Color3.fromRGB(220, 200, 150),
}

local Terrain = Workspace.Terrain

-- Paint a flat ground slab whose top sits at origin.Y, centered on origin's X/Z.
local function fillSlab(origin: Vector3, sizeX: number, sizeZ: number, material: Enum.Material)
	local t = Config.Terrain.Thickness
	Terrain:FillBlock(CFrame.new(origin.X, origin.Y - t / 2, origin.Z), Vector3.new(sizeX, t, sizeZ), material)
end

-- Landscaping ground per zone (Config.Terrain). Complements the greybox floors; buildings/props
-- are layered on top later. Roads/water overwrite the ground voxels where they overlap.
local function paintTerrain()
	local T = Config.Terrain

	local home = Config.Zones.Home
	fillSlab(home, T.Home.Size, T.Home.Size, T.Home.Ground)
	fillSlab(home, T.Home.Size, T.Home.RoadWidth, T.Home.Road) -- crossroad along X
	fillSlab(home, T.Home.RoadWidth, T.Home.Size, T.Home.Road) -- crossroad along Z

	local airport = Config.Zones.Airport
	fillSlab(airport, T.Airport.Size, T.Airport.Size, T.Airport.Ground)

	local beach = Config.Zones.Beach
	fillSlab(beach, T.Beach.Size, T.Beach.Size, T.Beach.Ground)
	local waterCenter = beach + Vector3.new(0, 0, T.Beach.Size / 2 + T.Beach.WaterDepth / 2)
	fillSlab(waterCenter, T.Beach.Size, T.Beach.WaterDepth, T.Beach.Water)
end

function WorldService:Start()
	paintTerrain()

	local world = Instance.new("Folder")
	world.Name = "World"

	-- A floor per zone so players have ground when travel teleports them.
	for zoneName, zoneOrigin in Config.Zones do
		local zone = Instance.new("Model")
		zone.Name = zoneName
		zone.Parent = world
		local color = ZONE_FLOOR_COLOR[zoneName] or Color3.fromRGB(120, 120, 130)
		makePart("Floor", Vector3.new(80, 1, 80), zoneOrigin + Vector3.new(0, -0.5, 0), color, zone)
	end

	local home = world:FindFirstChild("Home") :: Model
	local origin = Config.Zones.Home

	-- Spawn players in Home.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HomeSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = origin + Vector3.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Color = Color3.fromRGB(80, 160, 120)
	spawn.Parent = home

	-- Interaction anchors with named ProximityPrompts.
	local interactions = Instance.new("Folder")
	interactions.Name = "Interactions"
	interactions.Parent = home
	for _, def in HOME_INTERACTIONS do
		local part =
			makePart(def.name, Vector3.new(3, 4, 3), origin + def.offset, Color3.fromRGB(200, 170, 90), interactions)
		addPrompt(part, def.name, def.action, def.object)
	end

	world.Parent = Workspace
end

return WorldService
