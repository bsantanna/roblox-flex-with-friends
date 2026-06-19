--!strict
-- SimonSaysController: the Simon Says (Personal Trainer) gameplay UI — the game-specific half that
-- the generic MinigameController pre-game shell hands off to. The server owns the game (it fires one
-- TrainerShowStep per arrow, then TrainerInputPhase when it accepts inputs); this controller lights
-- the arrow buttons during the show, then lets the player answer with the same buttons or the
-- keyboard arrow keys. New minigames add their own controller alongside this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local SimonSaysController = {}

local player = Players.LocalPlayer

local ARROWS = { "Left", "Up", "Down", "Right" } -- on-screen button order
local GLYPHS = { Left = "◀", Up = "▲", Down = "▼", Right = "▶" }
local KEY_ARROWS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Right] = "Right",
}

local BUTTON_IDLE = Color3.fromRGB(60, 120, 200)
local BUTTON_LIT = Color3.fromRGB(255, 220, 80)
local HIGHLIGHT_SECONDS = 0.4

local trainerShowStep: RemoteEvent
local trainerInputPhase: RemoteEvent
local trainerPoseInput: RemoteEvent
local trainerRoundResult: RemoteEvent
local trainerGameOver: RemoteEvent

local gameFrame: Frame
local roundLabel: TextLabel
local statusLabel: TextLabel
local arrowButtons: { [string]: TextButton } = {}

local inputEnabled = false

-- Lights an arrow button briefly (show phase and input echo share the same flash).
local function flashArrow(arrow: string)
	local button = arrowButtons[arrow]
	if not button then
		return
	end
	button.BackgroundColor3 = BUTTON_LIT
	task.delay(HIGHLIGHT_SECONDS, function()
		button.BackgroundColor3 = BUTTON_IDLE
	end)
end

local function sendArrow(arrow: string)
	if not inputEnabled then
		return
	end
	flashArrow(arrow)
	trainerPoseInput:FireServer(arrow)
end

local function onTrainerShowStep(arrow: string, round: number, maxRounds: number)
	gameFrame.Visible = true
	inputEnabled = false
	roundLabel.Text = `Round {round} / {maxRounds}`
	statusLabel.Text = "Watch the trainer..."
	flashArrow(arrow)
end

local function onTrainerInputPhase(_timeoutSeconds: number)
	inputEnabled = true
	statusLabel.Text = "Your turn — repeat the moves!"
end

local function onTrainerRoundResult(correct: boolean, reward: number)
	if not correct then
		inputEnabled = false
		statusLabel.Text = "Wrong move!"
	elseif reward > 0 then
		inputEnabled = false
		statusLabel.Text = `Round cleared! +{reward} followers`
	else
		statusLabel.Text = "Nice!"
	end
end

local function onTrainerGameOver(totalReward: number, roundsCompleted: number, cleared: boolean)
	inputEnabled = false
	statusLabel.Text = if cleared
		then `Training complete! +{totalReward} followers`
		else `Session over — {roundsCompleted} rounds, +{totalReward} followers`
	task.delay(2.5, function()
		gameFrame.Visible = false
	end)
end

function SimonSaysController:Init()
	trainerShowStep = Net.Event("TrainerShowStep")
	trainerInputPhase = Net.Event("TrainerInputPhase")
	trainerPoseInput = Net.Event("TrainerPoseInput")
	trainerRoundResult = Net.Event("TrainerRoundResult")
	trainerGameOver = Net.Event("TrainerGameOver")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SimonSays"
	gui.ResetOnSpawn = false

	gameFrame = Instance.new("Frame")
	gameFrame.AnchorPoint = Vector2.new(0.5, 1)
	gameFrame.Position = UDim2.fromScale(0.5, 0.92)
	gameFrame.Size = UDim2.fromOffset(340, 180)
	gameFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	gameFrame.Visible = false
	gameFrame.Parent = gui

	roundLabel = Instance.new("TextLabel")
	roundLabel.Size = UDim2.new(1, -16, 0, 28)
	roundLabel.Position = UDim2.fromOffset(8, 8)
	roundLabel.BackgroundTransparency = 1
	roundLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	roundLabel.Font = Enum.Font.GothamBold
	roundLabel.TextScaled = true
	roundLabel.Text = ""
	roundLabel.Parent = gameFrame

	local arrowRow = Instance.new("Frame")
	arrowRow.AnchorPoint = Vector2.new(0.5, 0)
	arrowRow.Position = UDim2.new(0.5, 0, 0, 44)
	arrowRow.Size = UDim2.fromOffset(296, 64)
	arrowRow.BackgroundTransparency = 1
	arrowRow.Parent = gameFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = arrowRow

	for order, arrow in ARROWS do
		local button = Instance.new("TextButton")
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(64, 64)
		button.BackgroundColor3 = BUTTON_IDLE
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = GLYPHS[arrow]
		button.Parent = arrowRow
		button.Activated:Connect(function()
			sendArrow(arrow)
		end)
		arrowButtons[arrow] = button
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
	statusLabel.Size = UDim2.new(1, -16, 0, 28)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(220, 220, 120)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Parent = gameFrame

	gui.Parent = player:WaitForChild("PlayerGui")
end

function SimonSaysController:Start()
	trainerShowStep.OnClientEvent:Connect(onTrainerShowStep)
	trainerInputPhase.OnClientEvent:Connect(onTrainerInputPhase)
	trainerRoundResult.OnClientEvent:Connect(onTrainerRoundResult)
	trainerGameOver.OnClientEvent:Connect(onTrainerGameOver)

	-- The arrow keys double as Roblox's default movement, so they arrive with gameProcessed=true;
	-- guarding on a focused TextBox (not gameProcessed) is what lets the player answer with the
	-- keyboard. sendArrow no-ops unless the input phase is open.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local arrow = KEY_ARROWS[input.KeyCode]
		if arrow then
			sendArrow(arrow)
		end
	end)
end

return SimonSaysController
