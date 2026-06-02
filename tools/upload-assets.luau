--!strict
-- Uploads pending mesh assets to Roblox via Open Cloud (rbxcloud) and records the returned asset
-- ids in assets/asset-ids.json. Run with `make assets-upload` (add ARGS=--force to re-upload all).
-- See assets/PIPELINE.md. Reads RBXCLOUD_API_KEY, ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE from env;
-- without them it reports what is pending and exits without uploading.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local task = require("@lune/task")

local MANIFEST = "assets/manifest.json"
local IDS = "assets/asset-ids.json"

local force = table.find(process.args, "--force") ~= nil

local manifest = serde.decode("json", fs.readFile(MANIFEST))
local ids = serde.decode("json", fs.readFile(IDS))

-- Mesh entries that still need an id (or all, with --force).
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

local apiKey = process.env.RBXCLOUD_API_KEY
local creatorId = process.env.ROBLOX_CREATOR_ID
local creatorType = process.env.ROBLOX_CREATOR_TYPE
if not (apiKey and creatorId and creatorType) then
	print(`{#pending} mesh asset(s) pending upload:`)
	for _, entry in pending do
		print(`  - {entry.id}  ({entry.source})`)
	end
	print("\nSet RBXCLOUD_API_KEY, ROBLOX_CREATOR_ID, ROBLOX_CREATOR_TYPE to upload. See assets/PIPELINE.md.")
	process.exit(0)
end

-- Run rbxcloud and decode its JSON stdout (raw output shown on failure for debuggability).
local function rbxcloud(args: { string }): any
	local result = process.spawn("rbxcloud", args)
	if not result.ok then
		error(`rbxcloud {args[2]} failed (code {result.code}):\n{result.stderr}\n{result.stdout}`)
	end
	local ok, decoded = pcall(serde.decode, "json" :: "json", result.stdout)
	if not ok then
		error(`could not parse rbxcloud output as JSON:\n{result.stdout}`)
	end
	return decoded
end

for _, entry in pending do
	local source = "assets/" .. entry.source
	print(`Uploading {entry.id} <- {source} ...`)

	local created = rbxcloud({
		"assets",
		"create",
		"--asset-type",
		"model-fbx",
		"--filepath",
		source,
		"--display-name",
		entry.displayName or entry.id,
		"--description",
		entry.description or entry.id,
		"--creator-id",
		creatorId,
		"--creator-type",
		creatorType,
		"--api-key",
		apiKey,
	})

	local operationId = created.operationId
	if not operationId and created.path then
		operationId = string.match(created.path, "operations/(.+)")
	end
	if not operationId then
		error(`{entry.id}: no operationId in create response:\n{serde.encode("json", created, true)}`)
	end

	-- Poll the operation until Roblox finishes processing the upload.
	local assetId
	for _ = 1, 30 do
		task.wait(2)
		local op = rbxcloud({ "assets", "get-operation", "--operation-id", operationId, "--api-key", apiKey })
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
end

fs.writeFile(IDS, serde.encode("json", ids, true) .. "\n")
print(`\nWrote {IDS}. Commit it (and the manifest/source).`)
