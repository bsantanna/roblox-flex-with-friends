--!strict
-- MinigameService: runs the Personal Trainer quiz. The server owns the questions and grades the
-- answers; correct answers pay followers via FollowerService. A player must have unlocked the
-- trainer to start. See doc/002_implementation_plan.md (1.6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local MinigameService = {}

local requestTrainer: RemoteEvent
local trainerQuestion: RemoteEvent
local trainerAnswer: RemoteEvent
local trainerResult: RemoteEvent

type Session = { index: number, score: number }
local sessions: { [Player]: Session } = {}

local function sendQuestion(player: Player)
	local session = sessions[player]
	local questions = Config.Npc.PersonalTrainer.Questions
	local question = questions[session.index]
	trainerQuestion:FireClient(player, session.index, #questions, question.q, question.options)
end

local function onRequestTrainer(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile or sessions[player] then
		return
	end

	if not table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") then
		trainerResult:FireClient(player, false, 0, true, 0, "Trainer not unlocked yet")
		return
	end

	sessions[player] = { index = 1, score = 0 }
	sendQuestion(player)
end

local function onTrainerAnswer(player: Player, optionIndex: unknown)
	local session = sessions[player]
	if not session or type(optionIndex) ~= "number" then
		return
	end

	local def = Config.Npc.PersonalTrainer
	local question = def.Questions[session.index]
	local correct = optionIndex == question.answer

	local reward = 0
	if correct then
		reward = def.RewardPerCorrect
		FollowerService:Award(player, reward, "trainer-quiz")
		session.score += 1
	end

	session.index += 1
	local finished = session.index > #def.Questions
	trainerResult:FireClient(player, correct, reward, finished, session.score, nil)

	if finished then
		sessions[player] = nil
	else
		sendQuestion(player)
	end
end

function MinigameService:Init()
	requestTrainer = Net.Event("RequestTrainer")
	trainerQuestion = Net.Event("TrainerQuestion")
	trainerAnswer = Net.Event("TrainerAnswer")
	trainerResult = Net.Event("TrainerResult")
end

function MinigameService:Start()
	requestTrainer.OnServerEvent:Connect(onRequestTrainer)
	trainerAnswer.OnServerEvent:Connect(onTrainerAnswer)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return MinigameService
