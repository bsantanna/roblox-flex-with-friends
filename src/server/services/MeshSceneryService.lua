--!strict
-- MeshSceneryService: loads uploaded FBX meshes (the assets/PIPELINE.md track) and places them in
-- the world. It reads ReplicatedStorage.Shared.SceneryManifest (Rojo maps assets/manifest.json into
-- the tree) and, for each `kind:"mesh"` entry that has an `assetId`, InsertService:LoadAssets it,
-- scales and pivots it to Config.Zones[zone] + offset. Entries without an assetId (not yet uploaded)
-- are skipped, so a pending asset never breaks the build. Primitive scenery stays in SceneryService;
-- a mesh supersedes a primitive by removing that id from SceneryService.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage.Shared.Config)
local Manifest = require(ReplicatedStorage.Shared.SceneryManifest) :: any

local MeshSceneryService = {}

local function place(scenery: Folder, entry: any)
	local origin = Config.Zones[entry.zone :: string]
	if not origin then
		warn(`[MeshSceneryService] {entry.id}: unknown zone {tostring(entry.zone)}`)
		return
	end

	local ok, container = pcall(function(): Instance
		return InsertService:LoadAsset(tonumber(entry.assetId) :: number)
	end)
	if not ok or not container then
		warn(`[MeshSceneryService] {entry.id}: LoadAsset {tostring(entry.assetId)} failed: {tostring(container)}`)
		return
	end

	-- LoadAsset returns a Model containing the imported instances; use it as the placed model.
	local model = container :: Model
	model.Name = entry.id

	local scale = tonumber(entry.scale)
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end

	local offset = entry.offset
	local cframe = CFrame.new(origin + Vector3.new(offset[1], offset[2], offset[3]))
		* CFrame.Angles(0, math.rad(tonumber(entry.rotationY) or 0), 0)
	model:PivotTo(cframe)

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

	for _, entry in Manifest.assets :: { any } do
		if entry.kind == "mesh" and entry.assetId then
			place(scenery, entry)
		end
	end
end

return MeshSceneryService
