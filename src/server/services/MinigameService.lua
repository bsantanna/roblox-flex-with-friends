--!strict
-- MinigameService: runs the Personal Trainer pose-memory minigame (Simon Says). The server owns
-- the clock and the sequence: the show phase fires one TrainerShowStep per arrow while posing the
-- NPC (visible to everyone), then the input phase grades each TrainerPoseInput, posing the
-- player's character on correct moves. Cleared rounds pay followers via FollowerService; the
-- first mistake or an input timeout ends the game with no penalty. DialogService starts a game
-- via StartGame after the trainer dialog's Train choice; the unlock guard inside stays as defense
-- in depth. Sequence/grading/reward math is pure logic in Shared.Logic.SimonSays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SimonSays = require(ReplicatedStorage.Shared.Logic.SimonSays)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local MinigameService = {}

local trainerShowStep: RemoteEvent
local trainerInputPhase: RemoteEvent
local trainerPoseInput: RemoteEvent
local trainerRoundResult: RemoteEvent
local trainerGameOver: RemoteEvent

local rng = Random.new()

type Session = {
	phase: "show" | "input",
	round: number,
	sequence: { string },
	inputIndex: number, -- next expected position in sequence
	totalReward: number,
	model: Model?, -- the trainer model, walked to the arena and back
	npcAnimator: Animator?,
	deadline: number, -- os.clock() cutoff for the current input phase
}
-- One game at a time: the trainer is a single shared model that physically walks to the arena.
local sessions: { [Player]: Session } = {}

-- One reusable Animation instance per asset id; tracks are loaded per play.
local animations: { [string]: Animation } = {}

local function getAnimation(animationId: string): Animation
	local cached = animations[animationId]
	if cached then
		return cached
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	animations[animationId] = animation
	return animation
end

-- Plays the arrow's pose on an Animator for `seconds`; skips silently when the rig has no
-- Animator (e.g. the NPC's red-box fallback body).
local function playPose(animator: Animator?, arrow: string, seconds: number)
	if not animator then
		return
	end
	local animationId = Config.Npc.PersonalTrainer.SimonSays.Poses[arrow]
	if not animationId then
		return
	end
	local track = animator:LoadAnimation(getAnimation(animationId))
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	task.delay(seconds, function()
		track:Stop()
	end)
end

local function getPlayerAnimator(player: Player): Animator?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return humanoid:FindFirstChildOfClass("Animator")
end

local function getNpcAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

local TURN_SECONDS = 0.3 -- time to pivot to the final facing after arriving

-- A bumped generation supersedes any in-flight walk, so the latest destination always wins (e.g.
-- a return-home triggered while still walking to the arena). One looped walk track at a time.
local moveGen = 0
local walkTrack: AnimationTrack? = nil

local function stopWalk()
	if walkTrack then
		walkTrack:Stop()
		walkTrack = nil
	end
end

-- Glides the anchored trainer (the root is anchored; PivotTo carries the jointed limbs) from its
-- current spot to targetFeet on the same flat floor, facing the direction of travel with a walk
-- animation, then turns to finalYaw. The model's pivot Y is preserved (floor is level).
local function walkTrainer(model: Model, animator: Animator?, targetFeet: Vector3, finalYaw: number)
	moveGen += 1
	local myGen = moveGen
	stopWalk()

	local def = Config.Npc.PersonalTrainer.SimonSays
	local startCF = model:GetPivot()
	local startPos = startCF.Position
	local endPos = Vector3.new(targetFeet.X, startPos.Y, targetFeet.Z)
	local moveDir = endPos - startPos
	local moving = moveDir.Magnitude > 0.5
	local travelRot = if moving then CFrame.lookAt(Vector3.zero, moveDir).Rotation else startCF.Rotation
	local finalRot = CFrame.Angles(0, math.rad(finalYaw), 0)

	if animator and moving then
		local track = animator:LoadAnimation(getAnimation(def.WalkAnimation))
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement
		track:Play()
		walkTrack = track
	end

	local t = 0
	while t < def.MoveSeconds do
		local dt = task.wait()
		if myGen ~= moveGen then
			return
		end
		t = math.min(t + dt, def.MoveSeconds)
		model:PivotTo(CFrame.new(startPos:Lerp(endPos, t / def.MoveSeconds)) * travelRot)
	end
	stopWalk()

	-- Turn in place to the final facing (no-op when already aligned, e.g. walking home).
	t = 0
	while t < TURN_SECONDS do
		local dt = task.wait()
		if myGen ~= moveGen then
			return
		end
		t = math.min(t + dt, TURN_SECONDS)
		model:PivotTo(CFrame.new(endPos) * travelRot:Lerp(finalRot, t / TURN_SECONDS))
	end
	if myGen == moveGen then
		model:PivotTo(CFrame.new(endPos) * finalRot)
	end
end

-- Sends the trainer back to its post (also used on disconnect); skipped for the fallback body.
local function returnTrainerHome(session: Session)
	local model = session.model
	if model then
		local def = Config.Npc.PersonalTrainer
		task.spawn(walkTrainer, model, session.npcAnimator, def.SpawnPosition, def.SpawnYaw)
	end
end

local function endGame(player: Player, roundsCompleted: number, cleared: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if player.Parent then
		trainerGameOver:FireClient(player, session.totalReward, roundsCompleted, cleared)
	end
	returnTrainerHome(session)
end

-- The show phase: fires one step per arrow to the player while the NPC poses along, then opens
-- the input phase with a server-side deadline. Runs in its own thread (it sleeps); every step
-- re-checks the session so a disconnect mid-show stops it.
local function runShowPhase(player: Player, session: Session)
	local def = Config.Npc.PersonalTrainer.SimonSays
	if session.round > 1 then
		task.wait(def.RoundDelaySeconds)
	end

	for _, arrow in session.sequence do
		if sessions[player] ~= session then
			return
		end
		trainerShowStep:FireClient(player, arrow, session.round, def.MaxRounds)
		playPose(session.npcAnimator, arrow, def.ShowStepSeconds)
		task.wait(def.ShowStepSeconds + def.ShowGapSeconds)
	end

	if sessions[player] ~= session then
		return
	end
	session.phase = "input"
	session.deadline = os.clock() + def.InputTimeoutSeconds
	trainerInputPhase:FireClient(player, def.InputTimeoutSeconds)

	-- Round-scoped timeout watcher: a later round refreshes the deadline, so a stale watcher
	-- (deadline check fails) does nothing.
	local deadline = session.deadline
	task.delay(def.InputTimeoutSeconds + 0.5, function()
		if sessions[player] == session and session.phase == "input" and session.deadline == deadline then
			endGame(player, session.round - 1, false)
		end
	end)
end

local function startRound(player: Player, session: Session)
	local def = Config.Npc.PersonalTrainer.SimonSays
	session.phase = "show"
	session.inputIndex = 1
	session.sequence = SimonSays.generate(function(min: number, max: number)
		return rng:NextInteger(min, max)
	end, def.Arrows, SimonSays.sequenceLength(def.StartLength, session.round))
	task.spawn(runShowPhase, player, session)
end

-- Starts a game. Called by DialogService when the player picks Train; the unlock check repeats
-- here so no other path can start an ungated session. The trainer walks to the arena, runs the
-- rounds there, then returns. `model` is the trainer (nil-safe; the fallback body just won't
-- animate or walk). Only one game runs at a time — the trainer is a single shared model.
function MinigameService:StartGame(player: Player, model: Model?)
	local profile = DataService:GetProfile(player)
	if not profile or next(sessions) ~= nil then
		return
	end
	if not table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") then
		return
	end

	local def = Config.Npc.PersonalTrainer
	local session: Session = {
		phase = "show",
		round = 1,
		sequence = {},
		inputIndex = 1,
		totalReward = 0,
		model = model,
		npcAnimator = if model then getNpcAnimator(model) else nil,
		deadline = 0,
	}
	sessions[player] = session

	task.spawn(function()
		if model then
			walkTrainer(model, session.npcAnimator, def.ArenaPosition, def.SpawnYaw)
		end
		if sessions[player] ~= session then
			return -- player left during the walk; returnTrainerHome already took over
		end
		startRound(player, session)
	end)
end

local function onTrainerPoseInput(player: Player, arrow: unknown)
	local session = sessions[player]
	if not session or session.phase ~= "input" then
		return
	end
	local def = Config.Npc.PersonalTrainer.SimonSays
	if type(arrow) ~= "string" or not table.find(def.Arrows, arrow) then
		return
	end
	if os.clock() > session.deadline then
		endGame(player, session.round - 1, false)
		return
	end

	local grade = SimonSays.grade(session.sequence, session.inputIndex, arrow)
	if grade == "wrong" then
		trainerRoundResult:FireClient(player, false, 0)
		endGame(player, session.round - 1, false)
		return
	end

	playPose(getPlayerAnimator(player), arrow, def.ShowStepSeconds)

	if grade == "correct" then
		session.inputIndex += 1
		trainerRoundResult:FireClient(player, true, 0)
		return
	end

	-- Round cleared.
	local reward = SimonSays.roundReward(def.BaseReward, def.RewardPerRound, session.round)
	session.totalReward += reward
	FollowerService:Award(player, reward, "trainer-pose")
	trainerRoundResult:FireClient(player, true, reward)

	if session.round >= def.MaxRounds then
		endGame(player, session.round, true)
	else
		session.round += 1
		startRound(player, session)
	end
end

function MinigameService:Init()
	trainerShowStep = Net.Event("TrainerShowStep")
	trainerInputPhase = Net.Event("TrainerInputPhase")
	trainerPoseInput = Net.Event("TrainerPoseInput")
	trainerRoundResult = Net.Event("TrainerRoundResult")
	trainerGameOver = Net.Event("TrainerGameOver")
end

function MinigameService:Start()
	trainerPoseInput.OnServerEvent:Connect(onTrainerPoseInput)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			sessions[player] = nil
			returnTrainerHome(session)
		end
	end)
end

return MinigameService
