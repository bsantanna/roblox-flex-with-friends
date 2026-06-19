--!strict
-- SimonSays: the Personal Trainer pose-memory minigame, as a MinigameService plugin. The framework
-- handles the pre-game (walk-out, ready-zone, instructions, Start); this module owns the play. The
-- server drives the clock and the sequence: the show phase fires one TrainerShowStep per arrow while
-- posing the NPC (visible to all), then the input phase grades each TrainerPoseInput, posing the
-- player's character on correct moves. Cleared rounds pay followers; the first mistake or an input
-- timeout ends the round with no penalty. Sequence/grading/reward math is pure logic in
-- Shared.Logic.SimonSays. The framework calls begin()/abort() and provides session.actor (NPC
-- posing) and session.finish() (game over -> NPC walks home).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SimonSays = require(ReplicatedStorage.Shared.Logic.SimonSays)
local NpcActor = require(script.Parent.Parent.NpcActor)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)

local SimonSaysGame = {}
SimonSaysGame.Id = "SimonSays"
SimonSaysGame.NpcId = "PersonalTrainer"

-- Only the fields of MinigameService.Session this plugin touches (structurally compatible).
type Session = {
	player: Player,
	actor: NpcActor.NpcActor?,
	alive: boolean,
	state: any,
	finish: () -> (),
}

type State = {
	phase: "show" | "input",
	round: number,
	sequence: { string },
	inputIndex: number, -- next expected position in sequence
	totalReward: number,
	deadline: number, -- os.clock() cutoff for the current input phase
}

local trainerShowStep: RemoteEvent
local trainerInputPhase: RemoteEvent
local trainerPoseInput: RemoteEvent
local trainerRoundResult: RemoteEvent
local trainerGameOver: RemoteEvent

local rng = Random.new()

-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
-- Input arrives on a player-keyed remote, so this is how the handler finds the running game.
local current: Session? = nil

local function def()
	return Config.Npc.PersonalTrainer.SimonSays
end

local function endGame(session: Session, roundsCompleted: number, cleared: boolean)
	if current ~= session then
		return
	end
	current = nil
	if session.player.Parent then
		trainerGameOver:FireClient(session.player, session.state.totalReward, roundsCompleted, cleared)
	end
	session.finish() -- framework walks the NPC home and clears the session
end

local function startRound(session: Session)
	local d = def()
	local st: State = session.state
	st.phase = "show"
	st.inputIndex = 1
	st.sequence = SimonSays.generate(function(min: number, max: number)
		return rng:NextInteger(min, max)
	end, d.Arrows, SimonSays.sequenceLength(d.StartLength, st.round))

	-- Show phase: one step per arrow while the NPC poses along, then open input with a deadline.
	-- Re-checks the session every step so a disconnect/abort mid-show stops it.
	task.spawn(function()
		local st2: State = session.state
		if st2.round > 1 then
			task.wait(d.RoundDelaySeconds)
		end
		for _, arrow in st2.sequence do
			if not session.alive or current ~= session then
				return
			end
			trainerShowStep:FireClient(session.player, arrow, st2.round, d.MaxRounds)
			if session.actor then
				session.actor:poseNpc(d.Poses[arrow], d.ShowStepSeconds)
			end
			task.wait(d.ShowStepSeconds + d.ShowGapSeconds)
		end
		if not session.alive or current ~= session then
			return
		end
		st2.phase = "input"
		st2.deadline = os.clock() + d.InputTimeoutSeconds
		trainerInputPhase:FireClient(session.player, d.InputTimeoutSeconds)

		-- Round-scoped timeout watcher: a later round refreshes the deadline, so a stale watcher
		-- (deadline mismatch) does nothing.
		local deadline = st2.deadline
		task.delay(d.InputTimeoutSeconds + 0.5, function()
			if current == session and st2.phase == "input" and st2.deadline == deadline then
				endGame(session, st2.round - 1, false)
			end
		end)
	end)
end

local function onTrainerPoseInput(player: Player, arrow: unknown)
	local session = current
	if not session or session.player ~= player or not session.alive then
		return
	end
	local st: State = session.state
	if st.phase ~= "input" then
		return
	end
	local d = def()
	if type(arrow) ~= "string" or not table.find(d.Arrows, arrow) then
		return
	end
	if os.clock() > st.deadline then
		endGame(session, st.round - 1, false)
		return
	end

	local grade = SimonSays.grade(st.sequence, st.inputIndex, arrow)
	if grade == "wrong" then
		trainerRoundResult:FireClient(player, false, 0)
		endGame(session, st.round - 1, false)
		return
	end

	NpcActor.posePlayer(player, d.Poses[arrow], d.ShowStepSeconds)

	if grade == "correct" then
		st.inputIndex += 1
		trainerRoundResult:FireClient(player, true, 0)
		return
	end

	-- Round cleared.
	local reward = SimonSays.roundReward(d.BaseReward, d.RewardPerRound, st.round)
	st.totalReward += reward
	FollowerService:Award(player, reward, "trainer-pose")
	trainerRoundResult:FireClient(player, true, reward)

	if st.round >= d.MaxRounds then
		endGame(session, st.round, true)
	else
		st.round += 1
		startRound(session)
	end
end

-- Framework hook: start play for this session.
function SimonSaysGame:begin(session: Session)
	current = session
	session.state = {
		phase = "show",
		round = 1,
		sequence = {},
		inputIndex = 1,
		totalReward = 0,
		deadline = 0,
	} :: State
	startRound(session)
end

-- Framework hook: stop play (the player left or a timeout fired). The spawned loops also bail on
-- session.alive == false, which the framework sets before calling this.
function SimonSaysGame:abort(session: Session)
	if current == session then
		current = nil
	end
end

function SimonSaysGame:Init()
	trainerShowStep = Net.Event("TrainerShowStep")
	trainerInputPhase = Net.Event("TrainerInputPhase")
	trainerPoseInput = Net.Event("TrainerPoseInput")
	trainerRoundResult = Net.Event("TrainerRoundResult")
	trainerGameOver = Net.Event("TrainerGameOver")
end

function SimonSaysGame:Start()
	trainerPoseInput.OnServerEvent:Connect(onTrainerPoseInput)
end

return SimonSaysGame
