--!strict
-- NpcModel: the shared spawn path for a standing, dressed NPC. Used by DialogService (the roster) and
-- QuestService (the Pilot). It fetches the avatar (or a red fallback body), names the model,
-- anchors + floor-aligns it on its zone floor, ensures a Humanoid Animator for poses, optionally
-- creates a "Talk" ProximityPrompt, parents it under Workspace.World.<zone>, and dresses it. The
-- caller wires the prompt's Triggered and any background movement (chore patrol / citizen walk).
-- Extracted from DialogService.spawnNpc so the Pilot reuses the exact same build.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Util.Log)

local NpcModel = {}

export type BuildSpec = {
	npcId: string,
	zone: string,
	avatarUserId: number,
	spawnPosition: Vector3,
	spawnYaw: number,
	outfit: any?, -- NpcOutfit: { Hats: {number}, Layered: {{AssetId: number, Type: Enum.AccessoryType}} }
	promptText: string?, -- ProximityPrompt ActionText; nil = no prompt
	promptDistance: number?, -- MaxActivationDistance (default 12)
}

export type BuildResult = {
	root: BasePart,
	model: Model,
	prompt: ProximityPrompt?,
}

-- Dresses an NPC in its fixed outfit. The model must already be parented into the DataModel
-- (ApplyDescription needs that). Rigid headwear goes through the HatAccessory string property; layered
-- clothing (shirt/pants/jacket) through SetAccessories with includeRigidAccessories=false so the hats
-- are preserved. Yields, so callers run this off the boot thread.
local function applyOutfit(model: Model, outfit: any)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local desc = humanoid:GetAppliedDescription()

	local hatIds = {}
	for _, id in outfit.Hats do
		table.insert(hatIds, tostring(id))
	end
	desc.HatAccessory = table.concat(hatIds, ",")

	local layered = {}
	for i, item in outfit.Layered do
		table.insert(layered, { Order = i, AssetId = item.AssetId, AccessoryType = item.Type, IsLayered = true })
	end
	desc:SetAccessories(layered, false)

	humanoid:ApplyDescriptionAsync(desc)
end

local function makeFallbackBody(): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 5, 2)
	body.Anchored = true
	body.Color = Color3.fromRGB(200, 90, 90)
	body.Parent = model
	model.PrimaryPart = body
	return model
end

-- Builds an NPC model from `spec` and returns its handles. The prompt is nil when spec.promptText is.
function NpcModel.build(spec: BuildSpec): BuildResult
	local worldFolder = Workspace:WaitForChild("World", 30)
	local zoneFolder = worldFolder:WaitForChild(spec.zone, 30)
	assert(zoneFolder, string.format("NpcModel: zone %s not found under World/", spec.zone))

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromUserId(spec.avatarUserId)
	end)
	local model: Model
	if ok and result then
		model = result
	else
		Log.warn("NpcModel", "avatar fetch failed; using fallback body", {
			npcId = spec.npcId,
			userId = spec.avatarUserId,
		})
		model = makeFallbackBody()
	end
	model.Name = spec.npcId

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	assert(root, string.format("NpcModel: %s model has no BasePart", spec.npcId))
	root.Anchored = true

	model:PivotTo(CFrame.new(spec.spawnPosition) * CFrame.Angles(0, math.rad(spec.spawnYaw), 0))
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottom = boundsCFrame.Position.Y - boundsSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, spec.spawnPosition.Y - bottom, 0))

	-- Ensure the NPC has an Animator for walk/pose animations.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local prompt: ProximityPrompt? = nil
	if spec.promptText then
		local p = Instance.new("ProximityPrompt")
		p.Name = spec.npcId
		p.ActionText = spec.promptText
		p.ObjectText = spec.npcId
		p.HoldDuration = 0
		p.RequiresLineOfSight = false
		p.MaxActivationDistance = spec.promptDistance or 12
		p.Parent = root
		prompt = p
	end

	model.Parent = zoneFolder
	-- Dress once it's in the DataModel (ApplyDescription requires it).
	if spec.outfit then
		applyOutfit(model, spec.outfit)
	end

	return { root = root, model = model, prompt = prompt }
end

return NpcModel
