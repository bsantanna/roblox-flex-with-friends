--!strict
-- DialogService: spawns the always-present Personal Trainer NPC and runs its Zelda-like dialog.
-- The NPC's lines render in a server-side speech bubble (a BillboardGui in Workspace), so every
-- nearby player sees the conversation; only the interacting player gets the on-screen choices
-- (DialogLine/DialogAdvance/DialogChoose/DialogEnd). Picking Train hands off to
-- MinigameService:StartGame. The flow itself is pure logic in Shared.Logic.Dialog; the bubble is
-- the shared Shared.Util.SpeechBubble (the gym friends use the same one).

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

local DialogService = {}

local dialogLine: RemoteEvent
local dialogAdvance: RemoteEvent
local dialogChoose: RemoteEvent
local dialogEnd: RemoteEvent

local npcRoot: BasePart? = nil
local npcModel: Model? = nil -- the trainer model, handed to MinigameService to pose and walk it

-- One session at a time: the bubble is a single shared world object. A trigger while busy is
-- ignored — bystanders watch the running conversation instead (and can talk right after).
type Session = {
	player: Player,
	def: Dialog.Def, -- with {threshold} already substituted
	qualified: boolean,
	index: number,
	choices: { string }?, -- the branch line's choices once reached; nil while lines advance
	bubble: SpeechBubble.SpeechBubble,
	timeout: thread?,
}
local session: Session? = nil

-- Ends the running session: cancels the timeout, fades the bubble away, dismisses the
-- interacting player's choice UI. Safe to call from the timeout thread itself.
local function endSession()
	local s = session
	if not s then
		return
	end
	session = nil

	if s.timeout and coroutine.status(s.timeout) == "suspended" then
		task.cancel(s.timeout)
	end

	s.bubble:hide()

	if s.player.Parent then
		dialogEnd:FireClient(s.player)
	end
end

-- (Re-)arms the idle timeout; a session the player abandons mid-line closes itself.
local function armTimeout(s: Session)
	if s.timeout and coroutine.status(s.timeout) == "suspended" then
		task.cancel(s.timeout)
	end
	s.timeout = task.delay(Config.Npc.PersonalTrainer.Dialog.TimeoutSeconds, endSession)
end

-- Shows the session's current step in the bubble and sends it (with any choices) to the player.
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

local function onPromptTriggered(player: Player)
	if session or not npcRoot then
		return
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local npcDef = Config.Npc.PersonalTrainer
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

	local bubble = SpeechBubble.create(npcRoot)
	local s: Session = {
		player = player,
		def = def,
		qualified = table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") ~= nil,
		index = 1,
		bubble = bubble,
	}
	session = s
	bubble:show()
	sendStep(s)
end

local function onDialogAdvance(player: Player)
	local s = session
	if not s or s.player ~= player or s.choices ~= nil then
		return
	end
	s.index += 1
	sendStep(s)
end

local function onDialogChoose(player: Player, choiceIndex: unknown)
	local s = session
	if not s or s.player ~= player or s.choices == nil then
		return
	end
	if type(choiceIndex) ~= "number" or choiceIndex % 1 ~= 0 or choiceIndex < 1 or choiceIndex > #s.choices then
		return
	end

	local train = s.qualified and choiceIndex == 1
	endSession()
	if train then
		MinigameService:StartGame(player, npcModel)
	end
end

-- The red-box stand-in used until (or instead of) the avatar copy.
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

-- Builds the trainer (avatar copy of Config AvatarUserId, red box on failure), seats its feet on
-- SpawnPosition, and wires the Talk prompt. Runs in its own thread: the avatar fetch is a web
-- call and World/Home may not exist yet at Start.
local function spawnTrainer()
	local def = Config.Npc.PersonalTrainer
	local home = Workspace:WaitForChild("World"):WaitForChild("Home")

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromUserId(def.AvatarUserId)
	end)
	local model: Model
	if ok and result then
		model = result
	else
		Log.warn("DialogService", "avatar fetch failed; using fallback body", { userId = def.AvatarUserId })
		model = makeFallbackBody()
	end
	model.Name = "PersonalTrainer"

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	assert(root, "DialogService: trainer model has no BasePart")

	-- Anchor only the root: the Motor6D joints hold the limbs to it. Anchoring every part
	-- detaches the head/accessories when the Humanoid applies avatar scaling at parent time.
	root.Anchored = true

	-- Seat the model: pivot (with facing) to the spawn point, then lift so the bounding-box
	-- bottom sits on it.
	model:PivotTo(CFrame.new(def.SpawnPosition) * CFrame.Angles(0, math.rad(def.SpawnYaw), 0))
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottom = boundsCFrame.Position.Y - boundsSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, def.SpawnPosition.Y - bottom, 0))

	-- The minigame poses and walks the trainer through its Animator (Animator:LoadAnimation needs
	-- one; CreateHumanoidModelFromUserId does not guarantee it). Ensure it exists here; the
	-- fallback body has no Humanoid, so the minigame just skips animation.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Trainer"
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Personal Trainer"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Triggered:Connect(onPromptTriggered)
	prompt.Parent = root

	model.Parent = home
	npcRoot = root
	npcModel = model
end

function DialogService:Init()
	dialogLine = Net.Event("DialogLine")
	dialogAdvance = Net.Event("DialogAdvance")
	dialogChoose = Net.Event("DialogChoose")
	dialogEnd = Net.Event("DialogEnd")
end

function DialogService:Start()
	task.spawn(spawnTrainer)

	dialogAdvance.OnServerEvent:Connect(onDialogAdvance)
	dialogChoose.OnServerEvent:Connect(onDialogChoose)
	Players.PlayerRemoving:Connect(function(player: Player)
		if session and session.player == player then
			endSession()
		end
	end)
end

return DialogService
