--!strict
-- Uploads new or changed mesh assets to Roblox via the Open Cloud Assets API. Run with
-- `make assets-upload` (ARGS=--force re-uploads every mesh entry). See doc/003_binary_asset_management.md
-- and assets/PIPELINE.md.
--
-- Change detection: assets/.upload-state.json records, per asset id, the sha256 of the source file
-- that was last uploaded plus the resulting assetId. An entry is (re)uploaded when it is new (no
-- state), when its source file hash differs from the recorded one, or when --force is passed.
-- Unchanged entries are skipped, so a single edited source no longer requires re-uploading everything.
--
--   * new asset (no recorded assetId)   -> POST   /assets             (create, gets a fresh id)
--   * changed asset (has an assetId)     -> PATCH  /assets/{assetId}   (update in place, id unchanged)
--
-- The API accepts glb/gltf/fbx for Models but NOT obj, so an .obj source is converted to a
-- self-contained GLB with obj2gltf (npm; `npx --yes` fetches it on first use) before upload.
-- rbxcloud's CLI only exposes model-fbx, so GLB is uploaded by calling the API directly with curl.
-- Reads ROBLOX_API_KEY (asset:write), ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE (user|group) from env;
-- without them it lists what is pending and exits without uploading.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local task = require("@lune/task")

local MANIFEST = "assets/manifest.json"
local IDS = "assets/asset-ids.json"
local STATE = "assets/.upload-state.json" -- id -> { hash, assetId }; change-detection state, commit it
local API = "https://apis.roblox.com/assets/v1"

local force = table.find(process.args, "--force") ~= nil

local manifest = serde.decode("json", fs.readFile(MANIFEST))
local ids = serde.decode("json", fs.readFile(IDS))

-- .upload-state.json may not exist yet (first run on a fresh checkout); treat a missing/unreadable
-- file as empty state rather than erroring.
local state = {}
do
	local ok, raw = pcall(fs.readFile, STATE)
	if ok then
		state = serde.decode("json", raw)
	end
end

-- sha256 of the source file's bytes; this is what change detection compares against the recorded hash.
local function sourceHash(path: string): string
	local ok, contents = pcall(fs.readFile, path)
	if not ok then
		error(`source file not found: {path} (referenced by the manifest)`)
	end
	return serde.hash("sha256", contents)
end

-- Collect entries that need uploading, tagging each with its current hash and the reason.
local pending = {}
for _, entry in manifest.assets do
	if entry.kind ~= "mesh" and entry.kind ~= "image" then
		continue
	end
	local hash = sourceHash("assets/" .. entry.source)
	local recorded = state[entry.id]
	local reason = if recorded == nil then "new" elseif recorded.hash ~= hash then "changed" else "forced"
	if force or recorded == nil or recorded.hash ~= hash then
		table.insert(pending, { entry = entry, hash = hash, reason = reason })
	end
end

if #pending == 0 then
	print("No assets new or changed since last upload.")
	process.exit(0)
end

local apiKey = process.env.ROBLOX_API_KEY
local creatorId = process.env.ROBLOX_CREATOR_ID
local creatorType = process.env.ROBLOX_CREATOR_TYPE
if not (apiKey and creatorId and creatorType) then
	print(`{#pending} asset(s) pending upload:`)
	for _, p in pending do
		print(`  - {p.entry.id}  ({p.reason})  {p.entry.source}`)
	end
	print("\nSet ROBLOX_API_KEY, ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE to upload. See assets/PIPELINE.md.")
	process.exit(0)
end

-- curl returning decoded JSON; raw output is surfaced on failure for debuggability.
local function curlJson(args: { string }): any
	local result = process.exec("curl", args)
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
	local result = process.exec("npx", { "--yes", "obj2gltf", "-i", objPath, "-o", out })
	if not result.ok then
		error(`obj2gltf failed for {objPath} (code {result.code}):\n{result.stderr}`)
	end
	return out
end

-- Poll the long-running operation until it reports the asset id (or give up after ~60s).
local function awaitAssetId(operationId: string): string?
	for _ = 1, 30 do
		task.wait(2)
		local op = curlJson({ "-s", `{API}/operations/{operationId}`, "-H", `x-api-key: {apiKey}` })
		if op.done then
			local response = op.response or {}
			local assetId = response.assetId
			if not assetId and response.path then
				assetId = string.match(response.path, "assets/(%d+)")
			end
			return assetId
		end
	end
	return nil
end

local creatorKey = if creatorType == "group" then "groupId" else "userId"
local requestPath = (process.env.TMPDIR or "/tmp") .. "/fwf-asset-request.json"

for _, p in pending do
	local entry = p.entry
	local source = "assets/" .. entry.source
	-- A changed asset already has an id (from state, or the legacy asset-ids.json); update it in
	-- place so the id stays stable. A genuinely new asset is created.
	local existingId = (state[entry.id] and state[entry.id].assetId) or ids[entry.id]
	local mode = if existingId then "update" else "create"
	print(`{if mode == "update" then "Updating" else "Creating"} {entry.id} <- {entry.source} ({p.reason}) ...`)

	-- .obj is not a valid Open Cloud upload format; convert it to a GLB and upload that instead.
	local uploadPath = source
	local tempGlb: string? = nil
	if string.match(source, "%.obj$") then
		uploadPath = objToGlb(entry.id, source)
		tempGlb = uploadPath
	end

	-- The `request` part is JSON; pass it via a temp file so commas/quotes never confuse curl -F.
	local requestBody, method, url
	if mode == "update" then
		requestBody = { assetId = existingId }
		method = "PATCH"
		url = `{API}/assets/{existingId}`
	else
		requestBody = {
			-- Open Cloud asset type per source kind: a 3D mesh is a Model, a 2D UI image is a Decal.
			-- NOTE for image assets: Open Cloud returns the *Decal* id, but `ImageLabel.Image` can
			-- only render the Decal's underlying *texture* id (they differ). After creating or
			-- re-uploading an image, resolve the texture id and store THAT in asset-ids.json -- e.g.
			-- InsertService:LoadAsset(<decalId>) in Studio, then read the inner Decal.Texture.
			assetType = if entry.kind == "image" then "Decal" else "Model",
			displayName = entry.displayName or entry.id,
			description = entry.description or entry.id,
			creationContext = { creator = { [creatorKey] = tonumber(creatorId) or creatorId } },
		}
		method = "POST"
		url = `{API}/assets`
	end
	fs.writeFile(requestPath, serde.encode("json", requestBody))

	local created = curlJson({
		"-s",
		"-X",
		method,
		url,
		"-H",
		`x-api-key: {apiKey}`,
		"-F",
		`request=<{requestPath};type=application/json`,
		"-F",
		`fileContent=@{uploadPath};type={if entry.kind == "image" then "image/png" else "model/gltf-binary"}`,
	})

	local operationId = created.operationId
	if not operationId and created.path then
		operationId = string.match(created.path, "operations/(.+)")
	end
	if not operationId then
		error(`{entry.id}: no operation id in response:\n{serde.encode("json", created, true)}`)
	end

	local assetId = awaitAssetId(operationId)
	if not assetId then
		error(`{entry.id}: upload did not finish (or no assetId returned)`)
	end

	ids[entry.id] = tonumber(assetId) or assetId
	state[entry.id] = { hash = p.hash, assetId = ids[entry.id] }
	print(`  -> {entry.id} = {ids[entry.id]}`)

	if tempGlb then
		pcall(fs.removeFile, tempGlb)
	end
end

pcall(fs.removeFile, requestPath)
fs.writeFile(IDS, serde.encode("json", ids, true) .. "\n")
fs.writeFile(STATE, serde.encode("json", state, true) .. "\n")
print(`\nWrote {IDS} and {STATE}. Commit them (and the manifest/source).`)
