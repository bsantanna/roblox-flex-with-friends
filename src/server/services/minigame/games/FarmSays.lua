--!strict
-- FarmSays: the Farmer's Simon Says minigame plugin. Same framework as SimonSays.lua — this module
-- owns the play for the Farmer NPC. The framework calls begin()/abort() and provides session.actor
-- (NPC posing) and session.finish() (game over -> NPC walks home).
--
-- Game logic is shared in Shared.Logic.SimonSays. This module reads from Config.Npc.Farmer.SimonSays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SimonSays = require(ReplicatedStorage.Shared.Logic.SimonSays)
local NpcActor = require(script.Parent.Parent.NpcActor)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)

local FarmSaysGame = {}
FarmSaysGame.Id = "FarmSays"
FarmSaysGame.NpcId = "Farmer"

-- The session currently being played; set in begin, cleared on game over/abort.
local current: any = nil

local function def()
	return Config.Npc.Farmer.SimonSays
end

local function endGame(session: any, roundsCompleted: number, cleared: boolean)
	if current ~= session then
		return
	end
	current = nil
	if session.player.Parent then
		Net.Event("TrainerGameOver"):FireClient(session.player, session.state.totalReward, roundsCompleted, cleared)
	end
	session.finish()
end

local function startRound(session: any)
	local d = def()
	local st = session.state
	st.phase = "show"
	st.inputIndex = 1
	st.sequence = SimonSays.generate(function(min: number, max: number)
		return math.random(min, max)
	end, d.Arrows, SimonSays.sequenceLength(d.StartLength, st.round))

	task.spawn(function()
		local st2 = session.state
		if st2.round > 1 then
			task.wait(d.RoundDelaySeconds)
		end
		for _, arrow in st2.sequence do
			if not session.alive or current ~= session then
				return
			end
			Net.Event("TrainerShowStep"):FireClient(session.player, arrow, st2.round, d.MaxRounds)
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
		Net.Event("TrainerInputPhase"):FireClient(session.player, d.InputTimeoutSeconds)

		local deadline = st2.deadline
		task.delay(d.InputTimeoutSeconds + 0.5, function()
			if current == session and st2.phase == "input" and st2.deadline == deadline then
				endGame(session, st2.round - 1, false)
			end
		end)
	end)
end

local function onPoseInput(player: Player, arrow: unknown)
	local session = current
	if not session or session.player ~= player or not session.alive then
		return
	end
	local st = session.state
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
		Net.Event("TrainerRoundResult"):FireClient(player, false, 0)
		endGame(session, st.round - 1, false)
		return
	end

	NpcActor.posePlayer(player, d.Poses[arrow], d.ShowStepSeconds)

	if grade == "correct" then
		st.inputIndex += 1
		Net.Event("TrainerRoundResult"):FireClient(player, true, 0)
		return
	end

	-- Round cleared.
	local reward = SimonSays.roundReward(d.BaseReward, d.RewardPerRound, st.round)
	st.totalReward += reward
	FollowerService:Award(player, reward, "farm-says")
	Net.Event("TrainerRoundResult"):FireClient(player, true, reward)

	if st.round >= d.MaxRounds then
		endGame(session, st.round, true)
	else
		st.round += 1
		startRound(session)
	end
end

function FarmSaysGame:begin(session: any)
	current = session
	session.state = {
		phase = "show",
		round = 1,
		sequence = {},
		inputIndex = 1,
		totalReward = 0,
		deadline = 0,
	}
	startRound(session)
end

function FarmSaysGame:abort(session: any)
	if current == session then
		current = nil
	end
end

function FarmSaysGame:Init()
	-- Nothing to pre-bind; remotes accessed via Net.Event inline.
end

function FarmSaysGame:Start()
	Net.Event("TrainerPoseInput").OnServerEvent:Connect(onPoseInput)
end

return FarmSaysGame
