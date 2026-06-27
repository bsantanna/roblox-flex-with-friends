--!strict
-- QuestService: the server-authoritative state machine for all active quests.
-- Each quest is configured in Config.Quest (see Quest.lua); the service spawns each quest-giver NPC
-- via the shared Util.NpcModel, validates every remote, and runs a PER-PLAYER session through the
-- lifecycle:
--
--   idle --talk--> offer --accept--> accepting --(travel)--> collecting --goal met--> returning
--                    |                                               |
--                    decline-> idle                          timer expires -> failed -> idle
--   returning --talk--> complete (reward + one-time trophy, persisted)
--
-- Multi-quest: a questNpcs registry maps each quest's NpcId to its spawned model. onTalk resolves
-- the quest from the NPC lookup, checks any RequiredTrophies gate, then runs the same
-- offer/accept/collect/return flow for whichever quest the player is talking to.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local NpcModel = require(ReplicatedStorage.Shared.Util.NpcModel)
local SpeechBubble = require(ReplicatedStorage.Shared.Util.SpeechBubble)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local TrophyService = require(script.Parent.TrophyService)
local PlaceService = require(script.Parent.PlaceService)
local NpcPromptService = require(script.Parent.NpcPromptService)
local NpcActor = require(script.Parent.minigame.NpcActor)

local QuestService = {}

type Phase = "offer" | "collecting" | "returning"
type Session = {
	player: Player,
	questId: string,
	phase: Phase,
	alive: boolean,
	deadline: number,
	collected: { boolean },
	count: number,
}

local Q = Config.Quest

local questState: RemoteEvent
local questAccept: RemoteEvent
local questDecline: RemoteEvent
local requestCollect: RemoteEvent
local cutscenePlay: RemoteEvent

local sessions: { [Player]: Session } = {}
-- NPC registry: npcId -> { model, root, animator }
local questNpcs: { [string]: { model: Model, root: BasePart, animator: Animator? } } = {}

-- Reverse lookup: NpcId -> questId.
local npcToQuestId: { [string]: string } = {}

local PilotQuestId = Q.Id -- "PilotPackages"

-- Forward declarations for functions defined later that startCollecting needs.
local failQuest: (Player) -> ()
local clientDeadline: (Session) -> number
local startCollecting: (Session) -> ()

-- --- Helpers ---

local function getQ(questId: string): any
	if questId == PilotQuestId then
		return Q
	end
	return Q.FirstQuest
end

local function questNpcAnimator(npcId: string): Animator?
	local n = questNpcs[npcId]
	return n and n.animator
end

local function totalCollectibles(questId: string): number
	local q = getQ(questId)
	if q.TotalCollectibles then
		return q.TotalCollectibles
	end
	local pos = q.PackagePositions
	return pos and #pos or 0
end

local function getCollectPosition(questId: string): Vector3?
	local q = getQ(questId)
	if q.CollectPosition then
		return q.CollectPosition
	end
	local pos = q.PackagePositions
	return pos and pos[1] or nil
end

local function collectRadius(questId: string): number
	local q = getQ(questId)
	return q.CollectRadius or 14
end

local function lineHold(q: any): number
	return q.LineHoldSeconds or 4
end

local function fireState(player: Player, questId: string, phase: string, count: number, deadline: number?)
	questState:FireClient(player, questId, phase, count, totalCollectibles(questId), deadline)
end

local function speak(questId: string, lines: { string })
	local cfg = getQ(questId)
	local npcId = cfg.NpcId
	local n = questNpcs[npcId]
	if not n or not n.root then
		return
	end
	local bubble = SpeechBubble.create(n.root)
	bubble:show()
	for _, line in lines do
		bubble:setText(line)
		task.wait(lineHold(cfg))
	end
	bubble:hide()
end

local function clearSession(player: Player)
	local s = sessions[player]
	if s then
		s.alive = false
	end
	sessions[player] = nil
	player:SetAttribute("QuestActive", false)
end

local function deliver(player: Player, questId: string)
	clearSession(player)

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	local cfg = getQ(questId)
	local firstTime = not profile.Data.CompletedQuests[questId]
	if firstTime then
		profile.Data.CompletedQuests[questId] = true
		FollowerService:Award(player, cfg.Reward, "quest-" .. questId:lower())
		TrophyService:AwardTrophy(player, cfg.TrophyNpcId)
	end

	local npcId = cfg.NpcId
	NpcPromptService:Hide(npcId)
	cutscenePlay:FireClient(player, questId, "Ending", if firstTime then cfg.Reward else 0)
	task.spawn(function()
		NpcActor.pose(questNpcAnimator(npcId), cfg.Pose.Happy, 6)
		speak(questId, { cfg.Lines.Returned, cfg.Lines.Ending })
		NpcPromptService:Show(npcId)
	end)

	fireState(player, questId, "complete", totalCollectibles(questId))
end

local function handleTalk(player: Player, questId: string)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local session = sessions[player]
	if session then
		if session.phase == "returning" then
			deliver(player, questId)
		elseif session.phase ~= "offer" then
			local cfg = getQ(questId)
			task.spawn(function()
				speak(questId, { cfg.Lines.Nudge })
			end)
			fireState(player, questId, session.phase, session.count)
		end
		return
	end

	-- Check RequiredTrophies gate.
	local cfg = getQ(questId)
	if cfg.RequiredTrophies then
		for _, trophyId in cfg.RequiredTrophies do
			if not profile.Data.Trophies[trophyId] then
				local npcId = cfg.NpcId
				NpcPromptService:Hide(npcId)
				task.spawn(function()
					speak(questId, { "You need to unlock more skills before I can help with this!" })
				end)
				NpcPromptService:Show(npcId)
				return
			end
		end
	end

	-- Fresh offer.
	local replaying = profile.Data.CompletedQuests[questId] == true
	local introLines = if replaying then { cfg.Lines.Replay, cfg.Lines.Intro[2] } else cfg.Lines.Intro

	local s: Session = {
		player = player,
		questId = questId,
		phase = "offer",
		alive = true,
		deadline = 0,
		collected = table.create(totalCollectibles(questId), false),
		count = 0,
	}
	sessions[player] = s
	local npcId = cfg.NpcId
	NpcPromptService:Hide(npcId)
	cutscenePlay:FireClient(player, questId, "Intro")
	task.spawn(function()
		NpcActor.pose(questNpcAnimator(npcId), cfg.Pose.Worried, lineHold(cfg) * #introLines)
		speak(questId, introLines)
		if sessions[player] == s and s.phase == "offer" then
			fireState(player, questId, "offer", 0)
		end
	end)
end

function startCollecting(session: Session)
	session.phase = "collecting"
	local cfg = getQ(session.questId)
	session.deadline = os.clock() + cfg.TimeLimitSeconds
	session.player:SetAttribute("QuestActive", true)
	task.spawn(function()
		while session.alive and session.phase == "collecting" and os.clock() < session.deadline do
			task.wait(0.1)
		end
		if session.alive and session.phase == "collecting" then
			failQuest(session.player)
		end
	end)
	fireState(session.player, session.questId, "collecting", session.count, clientDeadline(session))
end

local function onAccept(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "offer" then
		return
	end
	local cfg = getQ(s.questId)
	local npcId = cfg.NpcId
	NpcPromptService:Show(npcId)
	NpcActor.pose(questNpcAnimator(npcId), cfg.Pose.Happy, 3)
	task.spawn(function()
		speak(s.questId, { cfg.Lines.Accepted })
	end)
	startCollecting(s)
end

local function onDecline(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "offer" then
		return
	end
	clearSession(player)
	local cfg = getQ(s.questId)
	NpcPromptService:Show(cfg.NpcId)
	task.spawn(function()
		speak(s.questId, { cfg.Lines.Declined })
	end)
	fireState(player, s.questId, "idle", 0)
end

function clientDeadline(session: Session): number
	return Workspace:GetServerTimeNow() + math.max(0, session.deadline - os.clock())
end

function failQuest(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "collecting" then
		return
	end
	clearSession(player)
	PlaceService:TravelTo(player, "Airport")
	local cfg = getQ(s.questId)
	task.spawn(function()
		speak(s.questId, { cfg.Lines.Fail })
	end)
	fireState(player, s.questId, "failed", 0)
end

local function onCollect(player: Player, index: unknown)
	if type(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local s = sessions[player]
	if not s or s.phase ~= "collecting" then
		return
	end
	local total = totalCollectibles(s.questId)
	if index < 1 or index > total or s.collected[index] then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local target = getCollectPosition(s.questId)
	if not target then
		return
	end
	local flat = Vector3.new((root :: BasePart).Position.X, target.Y, (root :: BasePart).Position.Z)
	if (flat - target).Magnitude > collectRadius(s.questId) then
		return
	end

	s.collected[index] = true
	s.count += 1
	if s.count >= total then
		s.phase = "returning"
		fireState(player, s.questId, "returning", s.count)
	else
		fireState(player, s.questId, "collecting", s.count, clientDeadline(s))
	end
end

-- Spawn all quest NPCs and wire their Talk prompts.
local function spawnQuestNpcs()
	-- Pilot.
	task.spawn(function()
		local result = NpcModel.build({
			npcId = Q.Pilot.NpcId,
			zone = Q.Pilot.Zone,
			avatarUserId = Q.Pilot.AvatarUserId,
			spawnPosition = Q.Pilot.SpawnPosition,
			spawnYaw = Q.Pilot.SpawnYaw,
			outfit = Q.Pilot.Outfit,
			promptText = "Talk",
			promptDistance = 12,
		})
		if result.model and result.root then
			local hum = result.model:FindFirstChildOfClass("Humanoid")
			questNpcs[Q.Pilot.NpcId] = {
				model = result.model,
				root = result.root,
				animator = hum and hum:FindFirstChildOfClass("Animator"),
			}
			npcToQuestId[Q.Pilot.NpcId] = PilotQuestId
			if result.prompt then
				NpcPromptService.Register(Q.Pilot.NpcId, result.prompt)
				result.prompt.Triggered:Connect(function(player)
					handleTalk(player, PilotQuestId)
				end)
			end
		end
	end)

	-- FirstQuest (Tim).
	task.spawn(function()
		local result = NpcModel.build({
			npcId = Q.FirstQuest.NpcId,
			zone = Q.FirstQuest.Zone,
			avatarUserId = Q.FirstQuest.AvatarUserId,
			spawnPosition = Q.FirstQuest.SpawnPosition,
			spawnYaw = Q.FirstQuest.SpawnYaw,
			outfit = Q.FirstQuest.Outfit,
			promptText = "Talk",
			promptDistance = 12,
		})
		if result.model and result.root then
			local hum = result.model:FindFirstChildOfClass("Humanoid")
			questNpcs[Q.FirstQuest.NpcId] = {
				model = result.model,
				root = result.root,
				animator = hum and hum:FindFirstChildOfClass("Animator"),
			}
			npcToQuestId[Q.FirstQuest.NpcId] = "FirstQuest"
			if result.prompt then
				NpcPromptService.Register(Q.FirstQuest.NpcId, result.prompt)
				result.prompt.Triggered:Connect(function(player)
					handleTalk(player, "FirstQuest")
				end)
			end
		end
	end)
end

function QuestService:Init()
	questState = Net.Event("QuestState")
	questAccept = Net.Event("QuestAccept")
	questDecline = Net.Event("QuestDecline")
	requestCollect = Net.Event("RequestCollectPackage")
	cutscenePlay = Net.Event("CutscenePlay")
end

function QuestService:Start()
	spawnQuestNpcs()

	questAccept.OnServerEvent:Connect(onAccept)
	questDecline.OnServerEvent:Connect(onDecline)
	requestCollect.OnServerEvent:Connect(onCollect)

	Players.PlayerRemoving:Connect(clearSession)
end

return QuestService
