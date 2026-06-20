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
local EMOJI = { Left = "⬅️", Up = "⬆️", Down = "⬇️", Right = "➡️" } -- shown in round/end feedback
local KEY_ARROWS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Right] = "Right",
}

local BUTTON_IDLE = Color3.fromRGB(60, 120, 200)
local BUTTON_LIT = Color3.fromRGB(255, 220, 80)
local HIGHLIGHT_SECONDS = 2.5 -- matches Config ShowStepSeconds so the arrow stays lit for the whole show

local trainerShowStepNumber: RemoteEvent
local trainerShowStep: RemoteEvent
local trainerInputPhase: RemoteEvent
local trainerPoseInput: RemoteEvent
local trainerRoundResult: RemoteEvent
local trainerRoundFeedback: RemoteEvent
local trainerGameOver: RemoteEvent

local gameFrame: Frame
local roundLabel: TextLabel
local statusLabel: TextLabel
local arrowButtons: { [string]: TextButton } = {}

-- Big centered overlay for the current step number.
local stepOverlayGui: ScreenGui
local stepOverlayLabel: TextLabel
local stepOverlayVisible: TextLabel -- gates the overlay (ScreenGui.Visible is untyped in luau-lsp)

-- Centered panel that recaps a round/game with the move sequence as emojis.
local feedbackFrame: Frame
local feedbackTitle: TextLabel
local feedbackCaption: TextLabel
local feedbackSequence: TextLabel
local feedbackSubtitle: TextLabel

local inputEnabled = false

-- Renders an arrow-name sequence as a spaced emoji string (e.g. "⬆️   ⬅️   ➡️").
local function emojiSequence(sequence: { string }): string
	local parts = table.create(#sequence)
	for index, arrow in sequence do
		parts[index] = EMOJI[arrow] or "?"
	end
	return table.concat(parts, "   ")
end

local function hideFeedback()
	feedbackFrame.Visible = false
end

-- Between-round success: congratulate and show the order the player just nailed.
local function showRoundFeedback(sequence: { string })
	feedbackTitle.Text = "🎉 Congratulations, you made it!"
	feedbackTitle.TextColor3 = Color3.fromRGB(120, 240, 140)
	feedbackCaption.Text = "Your moves:"
	feedbackSequence.Text = emojiSequence(sequence)
	feedbackSubtitle.Text = "Get ready for the next round!"
	feedbackFrame.Visible = true
end

-- Game over: encouraging recap for both winning and losing, always showing the correct order.
local function showEndFeedback(cleared: boolean, totalReward: number, sequence: { string })
	if cleared then
		feedbackTitle.Text = "🎉 You made it!"
		feedbackTitle.TextColor3 = Color3.fromRGB(120, 240, 140)
		feedbackCaption.Text = "Your moves:"
		feedbackSubtitle.Text = `⭐ Training complete! +{totalReward} followers!`
	else
		feedbackTitle.Text = "😅 Oops, that wasn't correct!"
		feedbackTitle.TextColor3 = Color3.fromRGB(255, 170, 90)
		feedbackCaption.Text = "The correct order was:"
		feedbackSubtitle.Text = `💪 Nice try! You earned +{totalReward} followers — come back and beat it!`
	end
	feedbackSequence.Text = emojiSequence(sequence)
	feedbackFrame.Visible = true
	task.delay(5, hideFeedback)
end

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
	-- Hide the overlay; it will be shown per-step by onTrainerShowStepNumber.
	stepOverlayVisible.Visible = false

	roundLabel.Text = `Round {round} / {maxRounds}`
	statusLabel.Text = "Watch the trainer..."
	flashArrow(arrow)
end

local function onTrainerShowStepNumber(stepNumber: number, _round: number, _maxRounds: number)
	hideFeedback() -- the next round is starting; clear the between-round recap
	stepOverlayLabel.Text = tostring(stepNumber)
	stepOverlayVisible.Visible = true
end

local function onTrainerRoundFeedback(sequence: { string })
	showRoundFeedback(sequence)
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

local function onTrainerGameOver(totalReward: number, roundsCompleted: number, cleared: boolean, sequence: { string })
	inputEnabled = false
	statusLabel.Text = if cleared
		then `Training complete! +{totalReward} followers`
		else `Session over — {roundsCompleted} rounds, +{totalReward} followers`
	stepOverlayVisible.Visible = false
	showEndFeedback(cleared, totalReward, sequence)
	task.delay(2.5, function()
		gameFrame.Visible = false
	end)
end

function SimonSaysController:Init()
	trainerShowStepNumber = Net.Event("TrainerShowStepNumber")
	trainerShowStep = Net.Event("TrainerShowStep")
	trainerInputPhase = Net.Event("TrainerInputPhase")
	trainerPoseInput = Net.Event("TrainerPoseInput")
	trainerRoundResult = Net.Event("TrainerRoundResult")
	trainerRoundFeedback = Net.Event("TrainerRoundFeedback")
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

	-- Big centered step-number overlay (fullscreen, appears during show phase).
	stepOverlayGui = Instance.new("ScreenGui")
	stepOverlayGui.Name = "SimonSaysStepOverlay"
	stepOverlayGui.ResetOnSpawn = false

	stepOverlayLabel = Instance.new("TextLabel")
	stepOverlayLabel.Size = UDim2.fromScale(1, 1)
	stepOverlayLabel.BackgroundTransparency = 1
	stepOverlayLabel.Text = ""
	stepOverlayLabel.TextColor3 = Color3.fromRGB(255, 230, 60)
	stepOverlayLabel.Font = Enum.Font.GothamBlack
	stepOverlayLabel.TextScaled = true
	stepOverlayLabel.ZIndex = 10
	stepOverlayLabel.TextXAlignment = Enum.TextXAlignment.Center
	stepOverlayLabel.TextYAlignment = Enum.TextYAlignment.Center
	stepOverlayLabel.Parent = stepOverlayGui

	-- Invisible label that gates the overlay's visibility (ScreenGui.Visible is untyped in luau-lsp).
	stepOverlayVisible = Instance.new("TextLabel")
	stepOverlayVisible.Text = ""
	stepOverlayVisible.Visible = false
	stepOverlayVisible.Parent = stepOverlayGui

	-- Centered feedback panel: between-round congrats and the encouraging game-over recap,
	-- both showing the move sequence as emojis. Parented under `gui` so it shares its PlayerGui.
	feedbackFrame = Instance.new("Frame")
	feedbackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	feedbackFrame.Position = UDim2.fromScale(0.5, 0.4)
	feedbackFrame.Size = UDim2.fromOffset(460, 240)
	feedbackFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	feedbackFrame.BackgroundTransparency = 0.05
	feedbackFrame.Visible = false
	feedbackFrame.ZIndex = 20
	feedbackFrame.Parent = gui

	local feedbackCorner = Instance.new("UICorner")
	feedbackCorner.CornerRadius = UDim.new(0, 16)
	feedbackCorner.Parent = feedbackFrame

	local feedbackLayout = Instance.new("UIListLayout")
	feedbackLayout.FillDirection = Enum.FillDirection.Vertical
	feedbackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	feedbackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	feedbackLayout.Padding = UDim.new(0, 10)
	feedbackLayout.Parent = feedbackFrame

	feedbackTitle = Instance.new("TextLabel")
	feedbackTitle.LayoutOrder = 1
	feedbackTitle.Size = UDim2.fromOffset(420, 48)
	feedbackTitle.BackgroundTransparency = 1
	feedbackTitle.Font = Enum.Font.GothamBold
	feedbackTitle.TextScaled = true
	feedbackTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	feedbackTitle.ZIndex = 21
	feedbackTitle.Text = ""
	feedbackTitle.Parent = feedbackFrame

	feedbackCaption = Instance.new("TextLabel")
	feedbackCaption.LayoutOrder = 2
	feedbackCaption.Size = UDim2.fromOffset(420, 24)
	feedbackCaption.BackgroundTransparency = 1
	feedbackCaption.Font = Enum.Font.Gotham
	feedbackCaption.TextScaled = true
	feedbackCaption.TextColor3 = Color3.fromRGB(190, 190, 200)
	feedbackCaption.ZIndex = 21
	feedbackCaption.Text = ""
	feedbackCaption.Parent = feedbackFrame

	feedbackSequence = Instance.new("TextLabel")
	feedbackSequence.LayoutOrder = 3
	feedbackSequence.Size = UDim2.fromOffset(420, 64)
	feedbackSequence.BackgroundTransparency = 1
	feedbackSequence.Font = Enum.Font.GothamBlack
	feedbackSequence.TextScaled = true
	feedbackSequence.TextColor3 = Color3.fromRGB(255, 255, 255)
	feedbackSequence.ZIndex = 21
	feedbackSequence.Text = ""
	feedbackSequence.Parent = feedbackFrame

	feedbackSubtitle = Instance.new("TextLabel")
	feedbackSubtitle.LayoutOrder = 4
	feedbackSubtitle.Size = UDim2.fromOffset(420, 48)
	feedbackSubtitle.BackgroundTransparency = 1
	feedbackSubtitle.Font = Enum.Font.Gotham
	feedbackSubtitle.TextScaled = true
	feedbackSubtitle.TextWrapped = true
	feedbackSubtitle.TextColor3 = Color3.fromRGB(220, 220, 140)
	feedbackSubtitle.ZIndex = 21
	feedbackSubtitle.Text = ""
	feedbackSubtitle.Parent = feedbackFrame

	gui.Parent = player:WaitForChild("PlayerGui")
end

function SimonSaysController:Start()
	trainerShowStepNumber.OnClientEvent:Connect(onTrainerShowStepNumber)
	trainerShowStep.OnClientEvent:Connect(onTrainerShowStep)
	trainerInputPhase.OnClientEvent:Connect(onTrainerInputPhase)
	trainerRoundResult.OnClientEvent:Connect(onTrainerRoundResult)
	trainerRoundFeedback.OnClientEvent:Connect(onTrainerRoundFeedback)
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
