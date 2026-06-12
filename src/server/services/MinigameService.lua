--!strict
-- MinigameService: runs the Personal Trainer quiz. The server owns the questions and grades the
-- answers; correct answers pay followers via FollowerService. DialogService starts a quiz via
-- StartQuiz after the trainer dialog's Train choice; the unlock guard inside stays as defense in
-- depth. See doc/002_implementation_plan.md (1.6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local MinigameService = {}

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

-- Starts a quiz session. Called by DialogService when the player picks Train; the unlock
-- check repeats here so no other path can start an ungated session.
function MinigameService:StartQuiz(player: Player)
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
	trainerQuestion = Net.Event("TrainerQuestion")
	trainerAnswer = Net.Event("TrainerAnswer")
	trainerResult = Net.Event("TrainerResult")
end

function MinigameService:Start()
	trainerAnswer.OnServerEvent:Connect(onTrainerAnswer)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return MinigameService
