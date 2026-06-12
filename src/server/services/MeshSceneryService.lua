--!strict
-- MeshSceneryService: loads uploaded GLB meshes (the assets/PIPELINE.md track) and places them in
-- the world. It reads the scenery manifest (Rojo maps assets/manifest.json into the tree) for
-- placement and the generated assets/asset-ids.json (id -> assetId, written by `make assets-upload`)
-- for the uploaded asset. For each `kind:"mesh"` entry with a known assetId it
-- InsertService:LoadAssets the model, scales and pivots it to Config.Zones[zone] + offset. Entries
-- without an uploaded assetId are skipped, so a pending asset never breaks the build. Primitive
-- scenery stays in SceneryService; a mesh supersedes a primitive by removing that id from it.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage.Shared.Config)
local Manifest = require(ReplicatedStorage.Shared.SceneryManifest) :: any
local AssetIds = require(ReplicatedStorage.Shared.SceneryAssetIds) :: { [string]: number }

local MeshSceneryService = {}

local function place(scenery: Folder, entry: any, assetId: number)
	local origin = Config.Zones[entry.zone :: string]
	if not origin then
		warn(`[MeshSceneryService] {entry.id}: unknown zone {tostring(entry.zone)}`)
		return
	end

	-- An asset is briefly unloadable in the first ~tens of seconds of a fresh server (it has to
	-- become available to InsertService), so retry over a generous window before giving up. place()
	-- is run per-entry in its own task (see Start), so these waits don't block boot or each other.
	local ATTEMPTS, BACKOFF = 20, 3
	local container: Instance? = nil
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function(): Instance
			return InsertService:LoadAsset(assetId)
		end)
		if ok and result then
			container = result
			break
		end
		if attempt < ATTEMPTS then
			task.wait(BACKOFF)
		else
			warn(
				`[MeshSceneryService] {entry.id}: LoadAsset {assetId} failed after {attempt} tries: {tostring(result)}`
			)
		end
	end
	if not container then
		return
	end

	-- LoadAsset returns a Model containing the imported instances; use it as the placed model.
	local model = container :: Model
	model.Name = entry.id

	-- Uploaded meshes arrive unanchored. Anchor them, or a house that loads before WorldService
	-- finishes painting the terrain free-falls and is destroyed at FallenPartsDestroyHeight.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	local scale = tonumber(entry.scale)
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end

	-- Optional flat tint for geometry-only meshes (no embedded material); manifest holds the rgb.
	local color = entry.color
	if color then
		local c = Color3.fromRGB(color[1], color[2], color[3])
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = c
			end
		end
	end

	local offset = entry.offset
	local cframe = CFrame.new(origin + Vector3.new(offset[1], offset[2], offset[3]))
		* CFrame.Angles(0, math.rad(tonumber(entry.rotationY) or 0), 0)
	model:PivotTo(cframe)

	-- Seat the model on the terrain below it: an uploaded mesh's origin relative to its geometry
	-- varies (and shifts under :ScaleTo), so trusting offset.y alone can bury or float a house.
	-- WorldService may still be painting the terrain when the first assets load in, so retry until
	-- the ray finds ground; skipping the seat would leave the model buried or floating.
	local cf, size = model:GetBoundingBox()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { Workspace.Terrain }
	local hit: RaycastResult? = nil
	for _ = 1, 30 do
		hit =
			Workspace:Raycast(cf.Position + Vector3.new(0, size.Y, 0), Vector3.new(0, -2 * size.Y - 100, 0), rayParams)
		if hit then
			break
		end
		task.wait(1)
	end
	if hit then
		model:PivotTo(model:GetPivot() + Vector3.new(0, hit.Position.Y - (cf.Y - size.Y / 2), 0))
	end

	model.Parent = scenery
end

local function getSceneryFolder(): Folder
	local existing = Workspace:FindFirstChild("Scenery")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = Workspace
	return folder
end

function MeshSceneryService:Start()
	local scenery = getSceneryFolder()

	-- Place each mesh in its own task so the boot isn't blocked by LoadAsset retries and a slow asset
	-- never holds up the others; each pops in as soon as it becomes loadable. Stagger the starts so 8
	-- simultaneous LoadAsset calls don't rate-limit each other at boot.
	-- scatter:true entries are uploaded through the same pipeline but placed in bulk by their
	-- owning service (e.g. ForestService), not pinned here one at a time.
	local index = 0
	for _, entry in Manifest.assets :: { any } do
		local assetId = AssetIds[entry.id]
		if entry.kind == "mesh" and assetId and not entry.scatter then
			index += 1
			local startDelay = index * 0.5
			task.spawn(function()
				task.wait(startDelay)
				place(scenery, entry, assetId)
			end)
		end
	end
end

return MeshSceneryService
