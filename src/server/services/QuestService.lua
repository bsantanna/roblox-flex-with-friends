--!strict
-- QuestService: the server-authoritative state machine for "The Pilot's Forgotten Packages"
-- (Quest 002) -- the game's first quest and the template for a quest system. It spawns the Pilot
-- quest-giver (via the shared Util.NpcModel build) and runs a PER-PLAYER session through the
-- lifecycle:
--
--   idle --talk--> offer --accept--> accepted --(phone: city)--> collecting --4/4--> returning
--                    |                                               |
--                    decline-> idle                          timer expires -> failed -> idle
--   returning --talk--> complete (reward + one-time trophy, persisted)
--
-- It mirrors MinigameService's lifecycle *pattern* (alive flag + os.clock deadline + clean cancel) but
-- keeps its own per-player sessions so many players can quest at once. QuestService is the single
-- writer of Profile.Data.CompletedQuests; it asks FollowerService/TrophyService to grant the reward.
-- Tunables live in Config.Quest; every remote is declared in Net.lua and validated here.
--
-- Phase A: spawn + offer/accept/decline/replay + delivery (reward & persistence). Fast travel, the
-- timed collection, and the cinematics are layered on in later phases.

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
	phase: Phase,
	alive: boolean,
	deadline: number, -- os.clock() expiry while collecting; 0 before the timer starts
	collected: { boolean },
	count: number,
}

local Q = Config.Quest
local TOTAL = #Q.PackagePositions

local questState: RemoteEvent
local questAccept: RemoteEvent
local questDecline: RemoteEvent
local requestCollect: RemoteEvent
local cutscenePlay: RemoteEvent

local sessions: { [Player]: Session } = {}
local pilotModel: Model? = nil
local pilotRoot: BasePart? = nil

-- Defined below (after the timer helpers) but called from onAccept above it: accepting the offer starts
-- the timed collection right away, so it needs a forward declaration here.
local startCollecting: (Session) -> ()

local function pilotAnimator(): Animator?
	local model = pilotModel
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

-- Sends the one HUD/state sync. `phase` is a plain string so transient phases (idle/failed/complete/
-- replay) that aren't session phases can be reported too. `deadline` (workspace:GetServerTimeNow()-
-- based absolute end time) drives the client countdown; nil when no timer is running.
local function fireState(player: Player, phase: string, count: number, deadline: number?)
	questState:FireClient(player, Q.Id, phase, count, TOTAL, deadline)
end

-- Speaks a sequence of lines in the Pilot's server-side bubble (all nearby players see them). Yields.
local function speak(lines: { string })
	local root = pilotRoot
	if not root then
		return
	end
	local bubble = SpeechBubble.create(root)
	bubble:show()
	for _, line in lines do
		bubble:setText(line)
		task.wait(Q.LineHoldSeconds)
	end
	bubble:hide()
end

local function clearSession(player: Player)
	local s = sessions[player]
	if s then
		s.alive = false
	end
	sessions[player] = nil
	-- The quest is over for this player: their cab rides cost followers again (PlaceService reads this).
	player:SetAttribute("QuestActive", false)
end

-- Delivery: the completion. Single writer of CompletedQuests; asks FollowerService and TrophyService
-- to grant the reward (golden rule 2). The reward + trophy are one-time (first completion only) -- the
-- quest is replayable for fun afterwards, but re-granting followers on every replay would be an
-- exploit. The ending cinematic plays every time.
local function deliver(player: Player)
	clearSession(player)

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	-- First completion only: persist + grant (the reward lands right away so a mid-cutscene disconnect
	-- can't lose it). Replays skip straight to the cinematic with no reward.
	local firstTime = not profile.Data.CompletedQuests[Q.Id]
	if firstTime then
		profile.Data.CompletedQuests[Q.Id] = true
		FollowerService:Award(player, Q.Reward, "quest-pilot-packages")
		TrophyService:AwardTrophy(player, Q.TrophyNpcId)
	end

	-- Cinematic ending: pan to the Pilot, happy pose + thank-you lines. Hide his Talk prompt for the
	-- duration so "Press E" doesn't float over the cutscene; restore it once the lines finish. The reward
	-- (only on the first completion) rides along to the Mission Complete banner.
	NpcPromptService:Hide(Q.Pilot.NpcId)
	cutscenePlay:FireClient(player, "Ending", if firstTime then Q.Reward else 0)
	task.spawn(function()
		NpcActor.pose(pilotAnimator(), Q.Pose.Happy, 6)
		speak({ Q.Lines.Returned, Q.Lines.Ending })
		NpcPromptService:Show(Q.Pilot.NpcId)
	end)

	fireState(player, "complete", TOTAL)
end

local function onTalk(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local session = sessions[player]
	if session then
		if session.phase == "returning" then
			deliver(player)
		elseif session.phase ~= "offer" then
			-- Active mid-quest -> a gentle nudge; resync the HUD/phone. (offer = intro in progress.)
			task.spawn(speak, { Q.Lines.Nudge })
			fireState(player, session.phase, session.count)
		end
		return
	end

	-- Fresh offer. A player who already finished it can replay (no reward the second time): greet them
	-- with the warm replay line, still asking for help, instead of the first-time intro.
	local replaying = profile.Data.CompletedQuests[Q.Id] == true
	local introLines = if replaying then { Q.Lines.Replay, Q.Lines.Intro[2] } else Q.Lines.Intro

	local s: Session = {
		player = player,
		phase = "offer",
		alive = true,
		deadline = 0,
		collected = table.create(TOTAL, false),
		count = 0,
	}
	sessions[player] = s
	-- Cinematic intro: the camera pans to the Pilot while he frets (worried pose) and explains, then
	-- the Accept/Decline choice appears once the lines have played and the camera has restored. Hide his
	-- Talk prompt while the cinematic + the choice are on screen so "Press E" doesn't float over them.
	NpcPromptService:Hide(Q.Pilot.NpcId)
	cutscenePlay:FireClient(player, "Intro")
	task.spawn(function()
		NpcActor.pose(pilotAnimator(), Q.Pose.Worried, Q.LineHoldSeconds * #introLines)
		speak(introLines)
		if sessions[player] == s and s.phase == "offer" then
			fireState(player, "offer", 0)
		end
	end)
end

local function onAccept(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "offer" then
		return
	end
	-- Choice resolved: the prompt returns, the Pilot cheers, and the timed collection starts right away.
	-- There's no separate "head to the city" step -- the timer is already running and the player uses
	-- their own phone (Call a Cab, free while questing) to fly over and grab the packages.
	NpcPromptService:Show(Q.Pilot.NpcId)
	NpcActor.pose(pilotAnimator(), Q.Pose.Happy, 3)
	task.spawn(speak, { Q.Lines.Accepted })
	startCollecting(s)
end

local function onDecline(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "offer" then
		return
	end
	clearSession(player)
	NpcPromptService:Show(Q.Pilot.NpcId)
	task.spawn(speak, { Q.Lines.Declined })
	fireState(player, "idle", 0)
end

-- Absolute end time the client counts down to: GetServerTimeNow() is synced client/server, so the
-- client can render the remaining time without trusting its own clock. The server's os.clock() deadline
-- stays the sole authority on expiry.
local function clientDeadline(session: Session): number
	return Workspace:GetServerTimeNow() + math.max(0, session.deadline - os.clock())
end

-- Gentle failure: snap the player back to the airport, drop the session, let the Pilot give an
-- understanding line. Only fires while collecting (the timer ran out).
local function failQuest(player: Player)
	local s = sessions[player]
	if not s or s.phase ~= "collecting" then
		return
	end
	clearSession(player)
	PlaceService:TravelTo(player, "Airport")
	task.spawn(speak, { Q.Lines.Fail })
	fireState(player, "failed", 0)
end

-- Begins the timed collection: starts the server-authoritative deadline + its poll loop and tells the
-- client the countdown end time. Called the moment the player accepts the offer; from here the player
-- uses their own phone to travel to the city and back.
function startCollecting(session: Session)
	session.phase = "collecting"
	session.deadline = os.clock() + Q.TimeLimitSeconds
	-- Flag the quest as active so the cab is free for these trips (PlaceService reads this attribute).
	session.player:SetAttribute("QuestActive", true)
	task.spawn(function()
		while session.alive and session.phase == "collecting" and os.clock() < session.deadline do
			task.wait(0.1)
		end
		if session.alive and session.phase == "collecting" then
			failQuest(session.player)
		end
	end)
	fireState(session.player, "collecting", session.count, clientDeadline(session))
end

-- Server-authoritative package collection: the client triggers a beacon, the server confirms the
-- player's real root position is within CollectRadius of that package, the package isn't already taken,
-- and the phase is collecting. Only then does progress advance. Rejects spoofed far-away collects.
local function onCollect(player: Player, index: unknown)
	if type(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local s = sessions[player]
	if not s or s.phase ~= "collecting" then
		return
	end
	if index < 1 or index > TOTAL or s.collected[index] then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local target = Q.PackagePositions[index]
	local flat = Vector3.new((root :: BasePart).Position.X, target.Y, (root :: BasePart).Position.Z)
	if (flat - target).Magnitude > Q.CollectRadius then
		return
	end

	s.collected[index] = true
	s.count += 1
	if s.count >= TOTAL then
		s.phase = "returning"
		fireState(player, "returning", s.count)
	else
		fireState(player, "collecting", s.count, clientDeadline(s))
	end
end

function QuestService:Init()
	questState = Net.Event("QuestState")
	questAccept = Net.Event("QuestAccept")
	questDecline = Net.Event("QuestDecline")
	requestCollect = Net.Event("RequestCollectPackage")
	cutscenePlay = Net.Event("CutscenePlay")
end

function QuestService:Start()
	-- Spawn the Pilot quest-giver in the arrivals terminal and wire his Talk prompt to the quest.
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
		pilotModel = result.model
		pilotRoot = result.root
		local prompt = result.prompt
		if prompt then
			NpcPromptService.Register(Q.Pilot.NpcId, prompt)
			prompt.Triggered:Connect(onTalk)
		end
	end)

	questAccept.OnServerEvent:Connect(onAccept)
	questDecline.OnServerEvent:Connect(onDecline)
	requestCollect.OnServerEvent:Connect(onCollect)

	Players.PlayerRemoving:Connect(clearSession)
end

return QuestService
