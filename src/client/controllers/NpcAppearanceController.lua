--!strict
-- NpcAppearanceController: renders this player's *own* version of the NPCs they have customized.
-- Customization is per-player, but the world NPC is one shared server model, so for each NPC this
-- player has a saved outfit (NpcOutfitSync) we: build a local cosmetic rig from that outfit, hide the
-- shared server rig *locally* (LocalTransparencyModifier -- other players still see it), make the
-- cosmetic rig follow the server rig's pivot each frame, and mirror its animation via the "LoopAnim"
-- attribute the server Agent broadcasts. Players who haven't customized an NPC just see the shared
-- default rig, untouched. The cosmetic rigs are client-only (never replicated).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local OutfitBuilder = require(ReplicatedStorage.Shared.Util.OutfitBuilder)
local GymFriendsCfg = require(ReplicatedStorage.Shared.Config.GymFriends)

type OutfitData = Types.OutfitData

local NpcAppearanceController = {}

local npcOutfitSync: RemoteEvent

type Skin = {
	serverModel: Model,
	rig: Model,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	currentAnim: string?,
	animConn: RBXScriptConnection,
}

local nameById: { [string]: string } = {} -- def.Id -> world model name (def.Name)
local skins: { [string]: Skin } = {} -- by npcId; only NPCs this player has customized
local container: Folder

local function hideLocally(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			-- local write to a server instance: persists since it never changes server-side
			(d :: Decal).Transparency = 1
		end
	end
end

-- Make a freshly built rig a static puppet: root anchored (so PivotTo places it cleanly and it never
-- falls), other limbs unanchored + massless so the Animator can still pose them, nothing collides.
local function prepareRig(rig: Model)
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			if d.Name == "HumanoidRootPart" then
				d.Anchored = true
			else
				d.Anchored = false
				d.Massless = true
			end
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false -- don't let the state machine fight the anchored puppet
	end
end

local function ensureAnimator(rig: Model): Animator
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "cosmetic rig has no Humanoid")
	local existing = humanoid:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

-- Plays `animId` (looped) on the cosmetic rig, mirroring the server rig's current loop. "" / nil
-- stops everything. Tracks are cached per animId.
local function applyLoop(skin: Skin, animId: string?)
	if animId == "" then
		animId = nil
	end
	if skin.currentAnim == animId then
		return
	end
	if skin.currentAnim and skin.tracks[skin.currentAnim] then
		skin.tracks[skin.currentAnim]:Stop()
	end
	skin.currentAnim = animId
	if not animId then
		return
	end
	local track = skin.tracks[animId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local loaded = skin.animator:LoadAnimation(anim)
		loaded.Looped = true
		loaded.Priority = Enum.AnimationPriority.Action
		skin.tracks[animId] = loaded
		track = loaded
	end
	track:Play()
end

-- Builds (or rebuilds) the cosmetic rig for one customized NPC. Yields on WaitForChild + rig build,
-- so call in its own thread.
local function buildSkin(npcId: string, outfit: OutfitData)
	local modelName = nameById[npcId]
	if not modelName then
		return
	end
	local folder = Workspace:WaitForChild("GymFriends", 30) :: Folder?
	if not folder then
		return
	end
	local serverModel = folder:WaitForChild(modelName, 30) :: Model?
	if not serverModel then
		return
	end

	local existing = skins[npcId]
	if existing then
		existing.animConn:Disconnect()
		existing.rig:Destroy()
		skins[npcId] = nil
	end

	local rig = OutfitBuilder.buildModel(outfit)
	rig.Name = modelName
	prepareRig(rig)
	local animator = ensureAnimator(rig)
	rig:PivotTo(serverModel:GetPivot())
	rig.Parent = container
	hideLocally(serverModel)

	local skin: Skin
	skin = {
		serverModel = serverModel,
		rig = rig,
		animator = animator,
		tracks = {},
		currentAnim = nil,
		animConn = serverModel:GetAttributeChangedSignal("LoopAnim"):Connect(function()
			applyLoop(skin, serverModel:GetAttribute("LoopAnim") :: string?)
		end),
	}
	skins[npcId] = skin
	applyLoop(skin, serverModel:GetAttribute("LoopAnim") :: string?)
end

local function onSync(outfits: unknown)
	if type(outfits) ~= "table" then
		return
	end
	for npcId, outfit in outfits :: { [string]: OutfitData } do
		if not skins[npcId] then
			task.spawn(buildSkin, npcId, outfit)
		end
	end
end

function NpcAppearanceController:Init()
	npcOutfitSync = Net.Event("NpcOutfitSync")
	for _, def in GymFriendsCfg.Friends do
		nameById[def.Id] = def.Name
	end
	container = Instance.new("Folder")
	container.Name = "LocalNpcSkins"
	container.Parent = Workspace
end

function NpcAppearanceController:Start()
	npcOutfitSync.OnClientEvent:Connect(onSync)
	-- Keep each cosmetic rig glued to its (hidden) server rig.
	RunService.RenderStepped:Connect(function()
		for _, skin in skins do
			if skin.serverModel.Parent and skin.rig.Parent then
				skin.rig:PivotTo(skin.serverModel:GetPivot())
			end
		end
	end)
end

return NpcAppearanceController
