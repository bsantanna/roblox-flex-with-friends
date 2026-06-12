--!strict
-- MinigameController: drives the Personal Trainer quiz UI. The quiz starts server-side (the
-- trainer dialog's Train choice); the server sends each question and grades answers. Also
-- toasts NPC unlocks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local MinigameController = {}

local player = Players.LocalPlayer

local trainerQuestion: RemoteEvent
local trainerAnswer: RemoteEvent
local trainerResult: RemoteEvent
local unlockNpc: RemoteEvent

local quizFrame: Frame
local questionLabel: TextLabel
local optionsList: Frame
local feedbackLabel: TextLabel
local toast: TextLabel

local function clearOptions()
	for _, child in optionsList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function onTrainerQuestion(index: number, total: number, question: string, options: { string })
	quizFrame.Visible = true
	feedbackLabel.Text = ""
	questionLabel.Text = `({index}/{total}) {question}`
	clearOptions()
	for optionIndex, optionText in options do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -16, 0, 36)
		button.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = optionText
		button.Parent = optionsList
		button.Activated:Connect(function()
			clearOptions()
			trainerAnswer:FireServer(optionIndex)
		end)
	end
end

local function onTrainerResult(correct: boolean, reward: number, finished: boolean, score: number, message: string?)
	if message then
		feedbackLabel.Text = message
		quizFrame.Visible = false
		return
	end

	feedbackLabel.Text = if correct then `Correct! +{reward}` else "Not quite"

	if finished then
		questionLabel.Text = `Session complete - score {score}`
		clearOptions()
		task.delay(2.5, function()
			quizFrame.Visible = false
		end)
	end
end

local function onUnlockNpc(npcId: string)
	toast.Text = `Unlocked: {npcId}`
	toast.Visible = true
	task.delay(3, function()
		toast.Visible = false
	end)
end

function MinigameController:Init()
	trainerQuestion = Net.Event("TrainerQuestion")
	trainerAnswer = Net.Event("TrainerAnswer")
	trainerResult = Net.Event("TrainerResult")
	unlockNpc = Net.Event("UnlockNpc")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Minigame"
	gui.ResetOnSpawn = false

	quizFrame = Instance.new("Frame")
	quizFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	quizFrame.Position = UDim2.fromScale(0.5, 0.5)
	quizFrame.Size = UDim2.fromOffset(360, 300)
	quizFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	quizFrame.Visible = false
	quizFrame.Parent = gui

	questionLabel = Instance.new("TextLabel")
	questionLabel.Size = UDim2.new(1, -16, 0, 80)
	questionLabel.Position = UDim2.fromOffset(8, 8)
	questionLabel.BackgroundTransparency = 1
	questionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	questionLabel.Font = Enum.Font.GothamBold
	questionLabel.TextScaled = true
	questionLabel.TextWrapped = true
	questionLabel.Text = ""
	questionLabel.Parent = quizFrame

	optionsList = Instance.new("Frame")
	optionsList.Position = UDim2.fromOffset(8, 96)
	optionsList.Size = UDim2.new(1, -16, 1, -140)
	optionsList.BackgroundTransparency = 1
	optionsList.Parent = quizFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = optionsList

	feedbackLabel = Instance.new("TextLabel")
	feedbackLabel.AnchorPoint = Vector2.new(0.5, 1)
	feedbackLabel.Position = UDim2.new(0.5, 0, 1, -8)
	feedbackLabel.Size = UDim2.new(1, -16, 0, 28)
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.TextColor3 = Color3.fromRGB(220, 220, 120)
	feedbackLabel.Font = Enum.Font.Gotham
	feedbackLabel.TextScaled = true
	feedbackLabel.Text = ""
	feedbackLabel.Parent = quizFrame

	toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.fromScale(0.5, 0.15)
	toast.Size = UDim2.fromOffset(320, 36)
	toast.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.Font = Enum.Font.GothamBold
	toast.TextScaled = true
	toast.Text = ""
	toast.Visible = false
	toast.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

function MinigameController:Start()
	trainerQuestion.OnClientEvent:Connect(onTrainerQuestion)
	trainerResult.OnClientEvent:Connect(onTrainerResult)
	unlockNpc.OnClientEvent:Connect(onUnlockNpc)
end

return MinigameController
