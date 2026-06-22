--!strict
-- QuickDrawController: the Forest sage's Quick Draw gameplay UI — the game-specific half the generic
-- MinigameController pre-game shell hands off to. The server owns the game: it fires QuickDrawCountdown
-- as a round opens (brace — do NOT press yet), then QuickDrawSignal the instant the sage draws (press
-- now!). The player strikes with the STRIKE button or the Spacebar; the server times the press against
-- its own clock and replies with QuickDrawResult. Pressing before the signal is a false start. New
-- minigames add their own controller alongside this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local QuickDrawController = {}

local player = Players.LocalPlayer

local BRACE_COLOR = Color3.fromRGB(40, 40, 50) -- waiting for the draw
local DRAW_COLOR = Color3.fromRGB(60, 200, 90) -- DRAW! strike now
local WIN_COLOR = Color3.fromRGB(60, 200, 90)
local LOSE_COLOR = Color3.fromRGB(210, 70, 70)

local quickDrawCountdown: RemoteEvent
local quickDrawSignal: RemoteEvent
local quickDrawPress: RemoteEvent
local quickDrawResult: RemoteEvent
local quickDrawGameOver: RemoteEvent

local gameFrame: Frame
local scoreLabel: TextLabel
local signalLabel: TextLabel
local statusLabel: TextLabel
local strikeButton: TextButton

local feedbackFrame: Frame
local feedbackTitle: TextLabel
local feedbackSubtitle: TextLabel

-- The player may strike once per round, any time it's armed (an early strike is a false start the
-- server punishes). Cleared the moment a strike is sent or the round resolves.
local armed = false

local function hideFeedback()
	feedbackFrame.Visible = false
end

local function strike()
	if not armed then
		return
	end
	armed = false
	statusLabel.Text = "You struck!"
	quickDrawPress:FireServer()
end

local function onCountdown(round: number, maxRounds: number)
	hideFeedback()
	gameFrame.Visible = true
	armed = true
	signalLabel.Text = "\u{2026}" -- ellipsis: wait for it
	signalLabel.BackgroundColor3 = BRACE_COLOR
	-- Be explicit that pressing now is a false start — wait for the DRAW flash.
	statusLabel.Text = `Round {round}/{maxRounds} — steady... DON'T draw yet!`
end

local function onSignal(_windowSeconds: number)
	signalLabel.Text = "DRAW!"
	signalLabel.BackgroundColor3 = DRAW_COLOR
	statusLabel.Text = "\u{26A1} STRIKE NOW!"
end

local function onResult(outcome: string, roundReward: number, roundsWon: number)
	armed = false
	-- Name the mistake so the player knows exactly what to fix next round.
	if outcome == "win" then
		signalLabel.Text = "\u{26A1}" -- lightning
		signalLabel.BackgroundColor3 = WIN_COLOR
		statusLabel.Text = `Hit! Lightning reflexes — +{roundReward} followers`
	elseif outcome == "falsestart" then
		signalLabel.Text = "\u{270B}" -- raised hand
		signalLabel.BackgroundColor3 = LOSE_COLOR
		statusLabel.Text = "Too soon! You drew before DRAW — wait for the green flash."
	else -- "slow"
		signalLabel.Text = "\u{1F40C}" -- snail
		signalLabel.BackgroundColor3 = LOSE_COLOR
		statusLabel.Text = "Too slow! Strike the instant you see DRAW."
	end
	scoreLabel.Text = `Draws won: {roundsWon}`
end

local function onGameOver(won: boolean, roundsWon: number, totalReward: number, npcId: string)
	armed = false
	local name = npcId or "opponent"
	if won then
		feedbackTitle.Text = `\u{1F3C6} You out-drew the {name}!`
		feedbackTitle.TextColor3 = Color3.fromRGB(120, 240, 140)
		feedbackSubtitle.Text = `\u{26A1} Every draw won — +{totalReward} followers and the trophy!`
	else
		feedbackTitle.Text = `\u{1F32B}\u{FE0F} The {name} was quicker...`
		feedbackTitle.TextColor3 = Color3.fromRGB(255, 170, 90)
		feedbackSubtitle.Text = if totalReward > 0
			then `\u{26A1} {roundsWon} draws won — +{totalReward} followers. Come back and sweep it!`
			else `Not a single draw — train your reflexes and return!`
	end
	feedbackFrame.Visible = true
	task.delay(5, hideFeedback)
	task.delay(2.5, function()
		gameFrame.Visible = false
	end)
end

function QuickDrawController:Init()
	quickDrawCountdown = Net.Event("QuickDrawCountdown")
	quickDrawSignal = Net.Event("QuickDrawSignal")
	quickDrawPress = Net.Event("QuickDrawPress")
	quickDrawResult = Net.Event("QuickDrawResult")
	quickDrawGameOver = Net.Event("QuickDrawGameOver")

	local gui = Instance.new("ScreenGui")
	gui.Name = "QuickDraw"
	gui.ResetOnSpawn = false

	gameFrame = Instance.new("Frame")
	gameFrame.AnchorPoint = Vector2.new(0.5, 1)
	gameFrame.Position = UDim2.fromScale(0.5, 0.92)
	gameFrame.Size = UDim2.fromOffset(340, 240)
	gameFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	gameFrame.Visible = false
	gameFrame.Parent = gui

	scoreLabel = Instance.new("TextLabel")
	scoreLabel.Size = UDim2.new(1, -16, 0, 28)
	scoreLabel.Position = UDim2.fromOffset(8, 8)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	scoreLabel.Font = Enum.Font.GothamBold
	scoreLabel.TextScaled = true
	scoreLabel.Text = "Draws won: 0"
	scoreLabel.Parent = gameFrame

	-- The signal panel: shows "..." while bracing and flips to "DRAW!" the instant the sage draws.
	signalLabel = Instance.new("TextLabel")
	signalLabel.AnchorPoint = Vector2.new(0.5, 0)
	signalLabel.Position = UDim2.new(0.5, 0, 0, 44)
	signalLabel.Size = UDim2.fromOffset(200, 80)
	signalLabel.BackgroundColor3 = BRACE_COLOR
	signalLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signalLabel.Font = Enum.Font.GothamBlack
	signalLabel.TextScaled = true
	signalLabel.Text = "\u{2026}"
	signalLabel.Parent = gameFrame

	local signalCorner = Instance.new("UICorner")
	signalCorner.CornerRadius = UDim.new(0, 12)
	signalCorner.Parent = signalLabel

	strikeButton = Instance.new("TextButton")
	strikeButton.AnchorPoint = Vector2.new(0.5, 0)
	strikeButton.Position = UDim2.new(0.5, 0, 0, 136)
	strikeButton.Size = UDim2.fromOffset(200, 48)
	strikeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	strikeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	strikeButton.Font = Enum.Font.GothamBold
	strikeButton.TextScaled = true
	strikeButton.Text = "STRIKE! (Space)"
	strikeButton.Parent = gameFrame

	local strikeCorner = Instance.new("UICorner")
	strikeCorner.CornerRadius = UDim.new(0, 10)
	strikeCorner.Parent = strikeButton

	strikeButton.Activated:Connect(strike)

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

	-- Centered duel-over recap (mirrors the other minigames' feedback panel).
	feedbackFrame = Instance.new("Frame")
	feedbackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	feedbackFrame.Position = UDim2.fromScale(0.5, 0.4)
	feedbackFrame.Size = UDim2.fromOffset(460, 200)
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
	feedbackLayout.Padding = UDim.new(0, 14)
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

	feedbackSubtitle = Instance.new("TextLabel")
	feedbackSubtitle.LayoutOrder = 2
	feedbackSubtitle.Size = UDim2.fromOffset(420, 56)
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

function QuickDrawController:Start()
	quickDrawCountdown.OnClientEvent:Connect(onCountdown)
	quickDrawSignal.OnClientEvent:Connect(onSignal)
	quickDrawResult.OnClientEvent:Connect(onResult)
	quickDrawGameOver.OnClientEvent:Connect(onGameOver)

	-- Spacebar doubles as the strike key; strike() no-ops unless a round is armed. Ignore the Space
	-- that's typed into a focused TextBox.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			strike()
		end
	end)
end

return QuickDrawController
