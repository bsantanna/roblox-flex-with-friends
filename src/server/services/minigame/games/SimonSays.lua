--!strict
-- SimonSays: a reusable Simon Says pose-memory minigame factory.
-- Call SimonSays.create(npcId) to get a game plugin for any NPC that wants the Simon Says game.
-- The framework handles pre-game (walk-out, ready-zone, instructions, Start); the plugin owns the play.
-- Shared.Logic.SimonSays provides sequence generation, grading, and reward math.
-- The plugin reads from Config.Npc.<npcId>.SimonSays for game-specific values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SimonSaysLogic = require(ReplicatedStorage.Shared.Logic.SimonSays)
local NpcActor = require(script.Parent.Parent.NpcActor)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)
local TrophyService = require(servicesFolder.TrophyService)

local rng = Random.new()

local SimonSaysModule = {}

function SimonSaysModule.create(npcId: string)
	local SimonSaysGame = {}
	SimonSaysGame.Id = npcId .. "Says"
	SimonSaysGame.NpcId = npcId

	-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
	-- Shared across all SimonSays instances since MinigameService only runs one game at a time.
	local current: any? = nil

	local function def()
		return Config.Npc[npcId].SimonSays
	end

	local function endGame(session: any, roundsCompleted: number, cleared: boolean)
		if current ~= session then
			return
		end
		if cleared then
			TrophyService:AwardTrophy(session.player, session.npcId)
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
		st.sequence = SimonSaysLogic.generate(function(min: number, max: number)
			return rng:NextInteger(min, max)
		end, d.Arrows, SimonSaysLogic.sequenceLength(d.StartLength, st.round))

		task.spawn(function()
			local st2 = session.state
			if st2.round > 1 then
				task.wait(d.RoundDelaySeconds)
			end
			for index, arrow in st2.sequence do
				if not session.alive or current ~= session then
					return
				end
				-- Show the step number before the arrow.
				Net.Event("TrainerShowStepNumber"):FireClient(session.player, index, st2.round, d.MaxRounds)
				task.wait(d.StepLeadSeconds)
				-- Light the arrow and pose the NPC.
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

			-- Round-scoped timeout watcher
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

		local grade = SimonSaysLogic.grade(st.sequence, st.inputIndex, arrow)
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
		local reward = SimonSaysLogic.roundReward(d.BaseReward, d.RewardPerRound, st.round)
		st.totalReward += reward
		FollowerService:Award(player, reward, npcId:lower() .. "-pose")
		Net.Event("TrainerRoundResult"):FireClient(player, true, reward)

		if st.round >= d.MaxRounds then
			endGame(session, st.round, true)
		else
			st.round += 1
			startRound(session)
		end
	end

	function SimonSaysGame:begin(session: any)
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

	function SimonSaysGame:abort(session: any)
		if current == session then
			current = nil
		end
	end

	function SimonSaysGame:Init()
		-- Nothing to pre-bind; remotes are shared (Net.Event returns cached singleton).
	end

	function SimonSaysGame:Start()
		Net.Event("TrainerPoseInput").OnServerEvent:Connect(onPoseInput)
	end

	return SimonSaysGame
end

return SimonSaysModule
