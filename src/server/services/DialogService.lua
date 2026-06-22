--!strict
-- DialogService: spawns every NPC defined in Config.Npc, one per zone folder under World.<Zone>.
-- Each NPC runs its own Zelda-like dialog flow. Lines render in a server-side speech bubble so every
-- nearby player sees the conversation; only the interacting player gets the on-screen choices. Picking
-- the training choice hands off to MinigameService:Request with the correct npcId.
-- The flow is pure logic in Shared.Logic.Dialog; the bubble is Shared.Util.SpeechBubble.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Dialog = require(ReplicatedStorage.Shared.Logic.Dialog)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local SpeechBubble = require(ReplicatedStorage.Shared.Util.SpeechBubble)
local DataService = require(script.Parent.DataService)
local MinigameService = require(script.Parent.MinigameService)
local NpcPromptService = require(script.Parent.NpcPromptService)
local NpcActor = require(script.Parent.minigame.NpcActor)

local DialogService = {}
local dialogLine: any
local dialogAdvance: any
local dialogChoose: any
local dialogEnd: any

-- All spawned NPC models: npcId -> { root: BasePart, model: Model }
local npcModels: { [string]: { root: BasePart, model: Model } } = {}
-- All spawned NPC actors (for chore patrol): npcId -> NpcActor
local npcActors: { [string]: NpcActor.NpcActor? } = {}
-- Dialog sessions: one at a time. If a new NPC is talked to, the old session ends.
type Session = {
	player: Player,
	npcId: string,
	def: Dialog.Def,
	qualified: boolean,
	index: number,
	choices: { string }?,
	bubble: any,
	timeout: any?,
	train: boolean, -- true if the dialog choice leads to a minigame
	model: Model?, -- the NPC model (needed for chore resume)
}
local session: Session? = nil

local function endSession()
	if not session then
		return
	end
	local s = session
	session = nil

	if s.timeout and coroutine.status(s.timeout) == "suspended" then
		task.cancel(s.timeout)
	end

	s.bubble:hide()

	if s.player.Parent then
		dialogEnd:FireClient(s.player)
	end

	-- Resume chore or citizen walk when dialog ends without leading to a minigame
	-- (minigame service manages chore/citizen walk pause/resume on its own).
	local walkActor = npcActors[s.npcId]
	if not s.train and walkActor then
		if Config.Npc[s.npcId]["CitizenWalk"] then
			NpcActor.resumeCitizenWalk(walkActor)
		else
			NpcActor.resumeChore(walkActor)
		end
	end
end

local function armTimeout(s: Session)
	if s.timeout and coroutine.status(s.timeout) == "suspended" then
		task.cancel(s.timeout)
	end
	s.timeout = task.delay(Config.Npc[s.npcId].Dialog.TimeoutSeconds, endSession)
end

local function sendStep(s: Session)
	local step = Dialog.step(s.def, s.qualified, s.index)
	if not step then
		endSession()
		return
	end
	s.choices = step.choices
	s.bubble:setText(step.text)
	dialogLine:FireClient(s.player, step.text, step.index, step.total, step.choices, s.npcId)
	armTimeout(s)
end

local function onPromptTriggered(player: Player, npcId: string)
	if session or not npcModels[npcId] then
		return
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local npcDef = Config.Npc[npcId]
	local d = npcDef.Dialog
	local threshold = tostring(npcDef.UnlockFollowers)
	local lines = table.create(#d.Lines)
	for i, line in d.Lines do
		lines[i] = (line:gsub("{threshold}", threshold))
	end
	local def: Dialog.Def = {
		lines = lines,
		qualifiedLine = (d.QualifiedLine:gsub("{threshold}", threshold)),
		gateLine = (d.GateLine:gsub("{threshold}", threshold)),
		qualifiedChoices = d.QualifiedChoices,
		gateChoices = d.GateChoices,
	}

	local modelData = npcModels[npcId]
	local bubble = SpeechBubble.create(modelData.root)
	local s: Session = {
		player = player,
		npcId = npcId,
		def = def,
		qualified = table.find(profile.Data.UnlockedNpcs, npcId) ~= nil,
		index = 1,
		bubble = bubble,
		train = false,
		model = modelData.model,
	}
	session = s
	bubble:show()

	-- Pause chore or citizen walk so the NPC doesn't wander during dialog.
	local actor = npcActors[npcId]
	if actor then
		if Config.Npc[npcId]["Chore"] then
			NpcActor.pauseChore(actor)
		elseif Config.Npc[npcId]["CitizenWalk"] then
			NpcActor.pauseCitizenWalk(actor)
		end
	end

	sendStep(s)
end

local function onDialogAdvance(player: Player)
	if not session or session.player ~= player or session.choices ~= nil then
		return
	end
	session.index += 1
	sendStep(session)
end

local function onDialogChoose(player: Player, choiceIndex: unknown)
	if not session or session.player ~= player or session.choices == nil then
		return
	end
	if type(choiceIndex) ~= "number" or choiceIndex % 1 ~= 0 or choiceIndex < 1 or choiceIndex > #session.choices then
		return
	end

	local npcId = session.npcId
	local modelData = npcModels[npcId]
	local choreActor = npcActors[npcId]
	local citizenActor = npcActors[npcId]
	local train = session.qualified and choiceIndex == 1
	session.train = train
	endSession()
	if train and modelData then
		-- MinigameService hides this NPC's prompt for the session and restores it on any outcome.
		MinigameService:Request(player, npcId, modelData.model, choreActor, citizenActor)
	end
end

-- Dresses an NPC in its fixed profession outfit (Config.Npc.<npcId>.Outfit). The model must already
-- be parented into the DataModel (ApplyDescription needs that). Rigid headwear goes through the
-- HatAccessory string property; layered clothing (shirt/pants/jacket) through SetAccessories with
-- includeRigidAccessories=false so the hats are preserved. Yields, so spawnNpc runs off the boot thread.
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

-- Spawns one NPC from Config.Npc.<npcId> in its World.<Zone> folder.
local function spawnNpc(npcId: string, def: any)
	local zoneName = def.Zone
	local worldFolder = Workspace:WaitForChild("World", 30)
	local zoneFolder = worldFolder:WaitForChild(zoneName, 30)
	assert(zoneFolder, string.format("DialogService: zone %s not found under World/", zoneName))

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromUserId(def.AvatarUserId)
	end)
	local model: Model
	if ok and result then
		model = result
	else
		Log.warn(
			"DialogService",
			"avatar fetch failed; using fallback body",
			{ npcId = npcId, userId = def.AvatarUserId }
		)
		model = makeFallbackBody()
	end
	model.Name = npcId

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	assert(root, string.format("DialogService: %s model has no BasePart", npcId))

	root.Anchored = true

	model:PivotTo(CFrame.new(def.SpawnPosition) * CFrame.Angles(0, math.rad(def.SpawnYaw), 0))
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottom = boundsCFrame.Position.Y - boundsSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, def.SpawnPosition.Y - bottom, 0))

	-- Ensure the NPC has an Animator for the minigame walk/pose animations.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = npcId
	prompt.ActionText = "Talk"
	prompt.ObjectText = npcId
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Triggered:Connect(function(player: Player)
		onPromptTriggered(player, npcId)
	end)
	prompt.Parent = root
	model.Parent = zoneFolder
	-- Dress the NPC in its profession outfit once it's in the DataModel (ApplyDescription requires it).
	if def.Outfit then
		applyOutfit(model, def.Outfit)
	end
	NpcPromptService.Register(npcId, prompt)
	npcModels[npcId] = { root = root, model = model }

	-- Start chore patrol for NPCs that have one; store the actor for chore pause/resume.
	local defChore = def["Chore"]
	if defChore then
		local actor = NpcActor.new(model, def.MoveSeconds, def.WalkAnimation)
		NpcActor.startChorePatrol(actor, defChore.HomePosition, defChore.Waypoints)
		npcActors[npcId] = actor
	end

	-- Start citizen walk for NPCs that patrol the town sidewalks (no chore/minigame).
	local defCitizen = def["CitizenWalk"]
	if defCitizen then
		local actor = NpcActor.new(model, def.MoveSeconds, def.WalkAnimation)
		NpcActor.startCitizenWalk(
			actor,
			defCitizen.Waypoints,
			defCitizen.WalkSpeed,
			defCitizen.PauseMin,
			defCitizen.PauseMax
		)
		-- Store the actor so dialog/minigame can pause the walk (otherwise the NPC walks away
		-- mid-conversation). The chore branch above stores its actor the same way.
		npcActors[npcId] = actor
	end
end

function DialogService:Init()
	dialogLine = Net.Event("DialogLine")
	dialogAdvance = Net.Event("DialogAdvance")
	dialogChoose = Net.Event("DialogChoose")
	dialogEnd = Net.Event("DialogEnd")
end

function DialogService:Start()
	-- Spawn all NPCs from Config.Npc, one per zone.
	for npcId, def in Config.Npc do
		task.spawn(spawnNpc, npcId, def)
	end

	dialogAdvance.OnServerEvent:Connect(onDialogAdvance)
	dialogChoose.OnServerEvent:Connect(onDialogChoose)
	Players.PlayerRemoving:Connect(function(player: Player)
		if session and session.player == player then
			endSession()
		end
	end)
end

return DialogService
