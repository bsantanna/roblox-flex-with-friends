--!strict
-- Uploads pending mesh assets to Roblox via the Open Cloud Assets API and records the returned
-- asset ids in assets/asset-ids.json. Run with `make assets-upload` (ARGS=--force re-uploads all).
-- See doc/003_binary_asset_management.md and assets/PIPELINE.md.
--
-- The API accepts glb/gltf/fbx for Models but NOT obj, so an .obj source is converted to a
-- self-contained GLB with obj2gltf (npm; `npx --yes` fetches it on first use) before upload.
--
-- rbxcloud's CLI only exposes model-fbx, so GLB is uploaded by calling the API directly with curl:
--   POST https://apis.roblox.com/assets/v1/assets  (multipart: request JSON + fileContent glb)
--   GET  https://apis.roblox.com/assets/v1/operations/{id}  (poll until done -> response.assetId)
-- Reads ROBLOX_API_KEY (asset:write), ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE (user|group) from env;
-- without them it lists what is pending and exits without uploading.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local task = require("@lune/task")

local MANIFEST = "assets/manifest.json"
local IDS = "assets/asset-ids.json"
local API = "https://apis.roblox.com/assets/v1"

local force = table.find(process.args, "--force") ~= nil

local manifest = serde.decode("json", fs.readFile(MANIFEST))
local ids = serde.decode("json", fs.readFile(IDS))

local pending = {}
for _, entry in manifest.assets do
	if entry.kind == "mesh" and (force or not ids[entry.id]) then
		table.insert(pending, entry)
	end
end

if #pending == 0 then
	print("No mesh assets pending upload.")
	process.exit(0)
end

local apiKey = process.env.ROBLOX_API_KEY
local creatorId = process.env.ROBLOX_CREATOR_ID
local creatorType = process.env.ROBLOX_CREATOR_TYPE
if not (apiKey and creatorId and creatorType) then
	print(`{#pending} mesh asset(s) pending upload:`)
	for _, entry in pending do
		print(`  - {entry.id}  ({entry.source})`)
	end
	print("\nSet ROBLOX_API_KEY, ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE to upload. See assets/PIPELINE.md.")
	process.exit(0)
end

-- curl returning decoded JSON; raw output is surfaced on failure for debuggability.
local function curlJson(args: { string }): any
	local result = process.spawn("curl", args)
	if not result.ok then
		error(`curl failed (code {result.code}):\n{result.stderr}`)
	end
	local ok, decoded = pcall(serde.decode, "json" :: "json", result.stdout)
	if not ok then
		error(`non-JSON response from Open Cloud:\n{result.stdout}`)
	end
	return decoded
end

-- Open Cloud rejects OBJ, so convert an .obj (+.mtl + textures) to a self-contained GLB via
-- obj2gltf before upload. Returns the temp GLB path (caller removes it after uploading).
local function objToGlb(id: string, objPath: string): string
	local out = (process.env.TMPDIR or "/tmp") .. "/fwf-glb-" .. id .. ".glb"
	print(`  converting OBJ -> GLB ({objPath})`)
	local result = process.spawn("npx", { "--yes", "obj2gltf", "-i", objPath, "-o", out })
	if not result.ok then
		error(`obj2gltf failed for {objPath} (code {result.code}):\n{result.stderr}`)
	end
	return out
end

local creatorKey = if creatorType == "group" then "groupId" else "userId"
local requestPath = (process.env.TMPDIR or "/tmp") .. "/fwf-asset-request.json"

for _, entry in pending do
	local source = "assets/" .. entry.source
	print(`Uploading {entry.id} <- {source} ...`)

	-- .obj is not a valid Open Cloud upload format; convert it to a GLB and upload that instead.
	local uploadPath = source
	local tempGlb: string? = nil
	if string.match(source, "%.obj$") then
		uploadPath = objToGlb(entry.id, source)
		tempGlb = uploadPath
	end

	-- The `request` part is JSON; pass it via a temp file so commas/quotes never confuse curl -F.
	fs.writeFile(
		requestPath,
		serde.encode("json", {
			assetType = "Model",
			displayName = entry.displayName or entry.id,
			description = entry.description or entry.id,
			creationContext = { creator = { [creatorKey] = tonumber(creatorId) or creatorId } },
		})
	)

	local created = curlJson({
		"-s",
		"-X",
		"POST",
		`{API}/assets`,
		"-H",
		`x-api-key: {apiKey}`,
		"-F",
		`request=<{requestPath};type=application/json`,
		"-F",
		`fileContent=@{uploadPath};type=model/gltf-binary`,
	})

	local operationId = created.operationId
	if not operationId and created.path then
		operationId = string.match(created.path, "operations/(.+)")
	end
	if not operationId then
		error(`{entry.id}: no operation id in response:\n{serde.encode("json", created, true)}`)
	end

	local assetId
	for _ = 1, 30 do
		task.wait(2)
		local op = curlJson({ "-s", `{API}/operations/{operationId}`, "-H", `x-api-key: {apiKey}` })
		if op.done then
			local response = op.response or {}
			assetId = response.assetId
			if not assetId and response.path then
				assetId = string.match(response.path, "assets/(%d+)")
			end
			break
		end
	end
	if not assetId then
		error(`{entry.id}: upload did not finish (or no assetId returned)`)
	end

	ids[entry.id] = tonumber(assetId) or assetId
	print(`  -> {entry.id} = {ids[entry.id]}`)

	if tempGlb then
		pcall(fs.removeFile, tempGlb)
	end
end

pcall(fs.removeFile, requestPath)
fs.writeFile(IDS, serde.encode("json", ids, true) .. "\n")
print(`\nWrote {IDS}. Commit it (and the manifest/source).`)
