--!strict
-- GymFriendService: spawns the gym-friend NPCs (Config.GymFriends -- 12 of them, 4 workout types x
-- 3 people) on the opened first floor and runs their lives. Each is a GymFriend agent that exercises
-- at its station and wanders to the lounge on breaks (natural Humanoid walking; a "GymNpc" collision
-- group keeps them from clipping into each other and a "GymProp" group lets them pass through the
-- equipment so straight-line walking never snags). Talking to one runs a branching, choose-your-reply
-- conversation (Shared.Logic.DialogTree): the first chat introduces them and befriends them (awards
-- Config.GymFriends.BefriendReward followers, persisted once each); after that they greet you as a
-- friend. Lines render in the shared server-side SpeechBubble; the player gets the answer buttons
-- (FriendDialogLine/FriendDialogChoose/FriendDialogEnd).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DialogTree = require(ReplicatedStorage.Shared.Logic.DialogTree)
local SpeechBubble = require(ReplicatedStorage.Shared.Util.SpeechBubble)
local OutfitBuilder = require(ReplicatedStorage.Shared.Util.OutfitBuilder)
local GymFriendsCfg = require(ReplicatedStorage.Shared.Config.GymFriends)
local DataService = require(script.Parent.DataService)
local OutfitService = require(script.Parent.OutfitService)
local GymFriend = require(script.Parent.Parent.agents.GymFriend)

type FriendDef = GymFriendsCfg.FriendDef
type GymFriendObj = GymFriend.GymFriend

local GymFriendService = {}

local friendDialogLine: RemoteEvent
local friendDialogChoose: RemoteEvent
local friendDialogEnd: RemoteEvent

type FriendSession = {
	player: Player,
	def: FriendDef,
	tree: DialogTree.Tree,
	nodeId: string,
	isIntro: boolean, -- befriend on a completed first meeting
	agent: GymFriendObj,
	bubble: SpeechBubble.SpeechBubble,
	timeout: thread?,
}

local sessions: { [string]: FriendSession } = {} -- keyed by def.Id: one conversation per NPC
local playerSession: { [Player]: FriendSession } = {} -- a player is in at most one conversation
local endSession: (FriendSession, boolean) -> ()

local BREAK_RADIUS = 3.5 -- studs from the group centre each resting friend stands (a chat-sized ring)

-- A friend's break placement: its fixed slot in its lounge group (members rung evenly around the
-- centre, facing inward) and the centre it turns to face. Falls back to resting at its own station
-- if the def isn't in any group (shouldn't happen -- every friend is assigned).
local function computeBreak(def: FriendDef): (Vector3, Vector3)
	for _, group in GymFriendsCfg.LoungeGroups do
		local index = table.find(group.members, def.Id)
		if index then
			local count = #group.members
			local angle = (2 * math.pi) * (index - 1) / count
			local offset = Vector3.new(math.cos(angle) * BREAK_RADIUS, 0, math.sin(angle) * BREAK_RADIUS)
			return group.center + offset, group.center
		end
	end
	return def.Station, def.Station
end

-- The red-box stand-in used when an avatar copy fails (no Humanoid -> the agent teleports instead of
-- walking, and skips animation).
local function makeFallbackBody(): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(2, 5, 2)
	body.Color = Color3.fromRGB(200, 90, 90)
	body.Parent = model
	model.PrimaryPart = body
	return model
end

local function clearSession(session: FriendSession)
	sessions[session.def.Id] = nil
	if playerSession[session.player] == session then
		playerSession[session.player] = nil
	end
	if session.timeout and coroutine.status(session.timeout) == "suspended" then
		task.cancel(session.timeout)
	end
end

-- Ends a conversation: drops the session, fades the bubble, frees the agent, dismisses the player's
-- buttons, and (only on a *completed* first meeting) befriends + rewards.
function endSession(session: FriendSession, completed: boolean)
	clearSession(session)
	session.bubble:hide()
	session.agent:resume()
	if session.player.Parent then
		friendDialogEnd:FireClient(session.player)
	end
	if completed and session.isIntro then
		OutfitService:Befriend(session.player, session.def.Id)
	end
end

local function armTimeout(session: FriendSession)
	if session.timeout and coroutine.status(session.timeout) == "suspended" then
		task.cancel(session.timeout)
	end
	session.timeout = task.delay(GymFriendsCfg.DialogTimeout, function()
		if sessions[session.def.Id] == session then
			endSession(session, false)
		end
	end)
end

-- Shows the current node in the bubble and sends its answer choices to the player.
local function sendNode(session: FriendSession)
	local node = DialogTree.node(session.tree, session.nodeId)
	if not node then
		endSession(session, false)
		return
	end
	session.bubble:setText(node.text)
	friendDialogLine:FireClient(session.player, node.text, DialogTree.labels(node))
	armTimeout(session)
end

local function onTalk(player: Player, def: FriendDef, agent: GymFriendObj)
	if sessions[def.Id] or playerSession[player] then
		return -- this friend is busy, or the player is already chatting with someone
	end
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local isFriend = profile.Data.Friends[def.Id] ~= nil
	local tree = if isFriend then def.Friend else def.Intro

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	agent:interrupt(if hrp and hrp:IsA("BasePart") then hrp.Position else nil)

	local session: FriendSession = {
		player = player,
		def = def,
		tree = tree,
		nodeId = tree.start,
		isIntro = not isFriend,
		agent = agent,
		bubble = SpeechBubble.create(agent.root),
	}
	sessions[def.Id] = session
	playerSession[player] = session
	session.bubble:show()
	sendNode(session)
end

local function onChoose(player: Player, choiceIndex: unknown)
	local session = playerSession[player]
	if not session or type(choiceIndex) ~= "number" then
		return
	end
	local ok, nextId = DialogTree.choose(session.tree, session.nodeId, choiceIndex)
	if not ok then
		return
	end
	if nextId then
		session.nodeId = nextId
		sendNode(session)
	else
		endSession(session, true)
	end
end

-- Builds one friend (avatar copy or red-box fallback), seats it at its station, wires the Talk
-- prompt, and starts its routine. The avatar fetch yields, so this runs in its own thread.
local function spawnFriend(def: FriendDef, parent: Folder)
	-- Every friend starts as the shared "default lego block" look (Config.DefaultNpcOutfit); a player
	-- who customizes them sees their own version, rendered client-side (per-player rendering).
	local ok, result = pcall(function()
		return OutfitBuilder.buildModel(Config.DefaultNpcOutfit)
	end)
	local model: Model = if ok and result then result else makeFallbackBody()
	model.Name = def.Name

	-- Seat feet on the station, facing Yaw (left unanchored, so it stands and walks via physics).
	model:PivotTo(CFrame.new(def.Station) * CFrame.Angles(0, math.rad(def.Yaw), 0))
	local boundsCF, boundsSize = model:GetBoundingBox()
	local bottom = boundsCF.Position.Y - boundsSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, def.Station.Y - bottom, 0))

	model.Parent = parent
	local breakSpot, breakCenter = computeBreak(def)
	local agent = GymFriend.new(model, def, breakSpot, breakCenter)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Talk"
	prompt.ObjectText = def.Name
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = GymFriendsCfg.PromptDistance
	prompt.Parent = agent.root
	prompt.Triggered:Connect(function(player: Player)
		onTalk(player, def, agent)
	end)

	agent:start()
end

local function registerGroups()
	local function ensure(name: string)
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	ensure(GymFriendsCfg.CollisionGroup)
	ensure(GymFriendsCfg.EquipmentGroup)
	-- Friends never collide with each other, and pass through the gym equipment (so straight-line
	-- MoveTo never snags); they still collide with the floor and players (the Default group).
	PhysicsService:CollisionGroupSetCollidable(GymFriendsCfg.CollisionGroup, GymFriendsCfg.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(GymFriendsCfg.CollisionGroup, GymFriendsCfg.EquipmentGroup, false)
end

-- Tags the gym equipment so friends pass through it. Yields on WaitForChild, so run off the boot thread.
local function tagEquipment()
	local gym = Workspace:WaitForChild("Gym")
	local function tag(inst: Instance)
		if inst:IsA("BasePart") then
			inst.CollisionGroup = GymFriendsCfg.EquipmentGroup
		end
	end
	for _, descendant in gym:GetDescendants() do
		tag(descendant)
	end
	gym.DescendantAdded:Connect(tag)
end

function GymFriendService:Init()
	friendDialogLine = Net.Event("FriendDialogLine")
	friendDialogChoose = Net.Event("FriendDialogChoose")
	friendDialogEnd = Net.Event("FriendDialogEnd")
end

function GymFriendService:Start()
	registerGroups()

	friendDialogChoose.OnServerEvent:Connect(onChoose)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = playerSession[player]
		if session then
			endSession(session, false)
		end
	end)

	-- Equipment tagging + the avatar fetches yield; running them off the boot thread lets Start
	-- return so the other services (incl. GymService, which builds Workspace.Gym) get to start.
	task.spawn(function()
		tagEquipment()

		local folder = Instance.new("Folder")
		folder.Name = "GymFriends"
		folder.Parent = Workspace

		for _, def in GymFriendsCfg.Friends do
			task.spawn(spawnFriend, def, folder)
		end
	end)
end

return GymFriendService
