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

local DialogService = {}
local dialogLine: any
local dialogAdvance: any
local dialogChoose: any
local dialogEnd: any

-- All spawned NPC models: npcId -> { root: BasePart, model: Model }
local npcModels: { [string]: { root: BasePart, model: Model } } = {}
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
	dialogLine:FireClient(s.player, step.text, step.index, step.total, step.choices)
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
	}
	session = s
	bubble:show()
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
	local train = session.qualified and choiceIndex == 1
	endSession()
	if train and modelData then
		-- MinigameService hides this NPC's prompt for the session and restores it on any outcome.
		MinigameService:Request(player, npcId, modelData.model)
	end
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
	NpcPromptService.Register(npcId, prompt)
	npcModels[npcId] = { root = root, model = model }
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
