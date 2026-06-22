--!strict
-- TicTacToeController: the HomeBuilder tic-tac-toe gameplay UI — the game-specific half the generic
-- MinigameController pre-game shell hands off to. The server owns the game: it fires TttGameStart with
-- a fresh board, TttUpdate after each move (yourTurn flags whose turn it is), TttGameResult when a game
-- ends, and TttGameOver for the match. This controller draws the 3x3 board, sends the tapped cell, and
-- recaps the match. New minigames add their own controller alongside this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local TicTacToeController = {}

local player = Players.LocalPlayer

local DEFAULT_NAME = "Builder"
local CELL_SIZE = 80
local CELL_PAD = 6

local CELL_IDLE = Color3.fromRGB(45, 50, 64)
local MARK_COLOR: { [string]: Color3 } = {
	X = Color3.fromRGB(90, 170, 255), -- player
	O = Color3.fromRGB(255, 170, 90), -- NPC
}

local tttGameStart: RemoteEvent
local tttMove: RemoteEvent
local tttUpdate: RemoteEvent
local tttGameResult: RemoteEvent
local tttGameOver: RemoteEvent

local gameFrame: Frame
local scoreLabel: TextLabel
local statusLabel: TextLabel
local cellButtons: { TextButton } = {}

-- Centered panel that recaps the match outcome.
local feedbackFrame: Frame
local feedbackTitle: TextLabel
local feedbackScore: TextLabel
local feedbackSubtitle: TextLabel

local inputEnabled = false
local npcName = DEFAULT_NAME

local function setScore(playerWins: number, opponentWins: number)
	scoreLabel.Text = `You {playerWins}  —  {opponentWins} {npcName}`
end

local function renderBoard(board: { string })
	for index, button in cellButtons do
		local mark = board[index] or ""
		button.Text = mark
		button.TextColor3 = MARK_COLOR[mark] or Color3.fromRGB(255, 255, 255)
	end
end

local function hideFeedback()
	feedbackFrame.Visible = false
end

local function sendMove(cell: number)
	if not inputEnabled or cellButtons[cell].Text ~= "" then
		return
	end
	inputEnabled = false
	tttMove:FireServer(cell)
end

local function onGameStart(board: { string }, gameNumber: number, playerWins: number, opponentWins: number)
	hideFeedback()
	gameFrame.Visible = true
	renderBoard(board)
	setScore(playerWins, opponentWins)
	statusLabel.Text = `Game {gameNumber} — your turn (you're X)!`
	inputEnabled = true
end

local function onUpdate(board: { string }, yourTurn: boolean)
	renderBoard(board)
	inputEnabled = yourTurn
	statusLabel.Text = if yourTurn then "Your turn!" else `{npcName} is thinking...`
end

local function onGameResult(board: { string }, result: string, playerWins: number, opponentWins: number)
	inputEnabled = false
	renderBoard(board)
	setScore(playerWins, opponentWins)
	if result == "win" then
		statusLabel.Text = "Three in a row — you win this one!"
	elseif result == "lose" then
		statusLabel.Text = `{npcName} got three in a row!`
	else
		statusLabel.Text = "It's a draw — play it again!"
	end
end

local function onGameOver(
	won: boolean,
	playerWins: number,
	opponentWins: number,
	totalReward: number,
	incomingNpcId: string
)
	inputEnabled = false
	npcName = incomingNpcId or DEFAULT_NAME
	if won then
		feedbackTitle.Text = "\u{1F3C6} You won the match!"
		feedbackTitle.TextColor3 = Color3.fromRGB(120, 240, 140)
		feedbackSubtitle.Text = `\u{2B50} +{totalReward} followers and the {npcName} trophy!`
	else
		feedbackTitle.Text = `\u{1F605} {npcName} got you!`
		feedbackTitle.TextColor3 = Color3.fromRGB(255, 170, 90)
		feedbackSubtitle.Text = if totalReward > 0
			then `\u{1F3D7}\u{FE0F} +{totalReward} followers — come back for a rematch!`
			else `\u{1F3D7}\u{FE0F} Better luck next time — come build again!`
	end
	feedbackScore.Text = `You {playerWins}  —  {opponentWins} {npcName}`
	feedbackFrame.Visible = true
	task.delay(5, hideFeedback)
	task.delay(2.5, function()
		gameFrame.Visible = false
	end)
end

function TicTacToeController:Init()
	tttGameStart = Net.Event("TttGameStart")
	tttMove = Net.Event("TttMove")
	tttUpdate = Net.Event("TttUpdate")
	tttGameResult = Net.Event("TttGameResult")
	tttGameOver = Net.Event("TttGameOver")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TicTacToe"
	gui.ResetOnSpawn = false

	gameFrame = Instance.new("Frame")
	gameFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameFrame.Position = UDim2.fromScale(0.5, 0.45)
	gameFrame.Size = UDim2.fromOffset(300, 372)
	gameFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	gameFrame.Visible = false
	gameFrame.Parent = gui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 16)
	frameCorner.Parent = gameFrame

	scoreLabel = Instance.new("TextLabel")
	scoreLabel.Size = UDim2.new(1, -16, 0, 28)
	scoreLabel.Position = UDim2.fromOffset(8, 8)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	scoreLabel.Font = Enum.Font.GothamBold
	scoreLabel.TextScaled = true
	scoreLabel.Text = `You 0  —  0 {DEFAULT_NAME}`
	scoreLabel.Parent = gameFrame

	local gridHolder = Instance.new("Frame")
	gridHolder.AnchorPoint = Vector2.new(0.5, 0)
	gridHolder.Position = UDim2.new(0.5, 0, 0, 44)
	gridHolder.Size = UDim2.fromOffset(3 * CELL_SIZE + 2 * CELL_PAD, 3 * CELL_SIZE + 2 * CELL_PAD)
	gridHolder.BackgroundTransparency = 1
	gridHolder.Parent = gameFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	gridLayout.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
	gridLayout.FillDirectionMaxCells = 3
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridHolder

	for index = 1, 9 do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.BackgroundColor3 = CELL_IDLE
		button.AutoButtonColor = true
		button.Font = Enum.Font.GothamBlack
		button.TextScaled = true
		button.Text = ""
		button.Parent = gridHolder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button

		button.Activated:Connect(function()
			sendMove(index)
		end)
		cellButtons[index] = button
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

	-- Centered match-over recap (mirrors the RPS feedback panel).
	feedbackFrame = Instance.new("Frame")
	feedbackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	feedbackFrame.Position = UDim2.fromScale(0.5, 0.2)
	feedbackFrame.Size = UDim2.fromOffset(460, 220)
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
	feedbackLayout.Padding = UDim.new(0, 12)
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

	feedbackScore = Instance.new("TextLabel")
	feedbackScore.LayoutOrder = 2
	feedbackScore.Size = UDim2.fromOffset(420, 40)
	feedbackScore.BackgroundTransparency = 1
	feedbackScore.Font = Enum.Font.GothamBlack
	feedbackScore.TextScaled = true
	feedbackScore.TextColor3 = Color3.fromRGB(255, 255, 255)
	feedbackScore.ZIndex = 21
	feedbackScore.Text = ""
	feedbackScore.Parent = feedbackFrame

	feedbackSubtitle = Instance.new("TextLabel")
	feedbackSubtitle.LayoutOrder = 3
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

function TicTacToeController:Start()
	tttGameStart.OnClientEvent:Connect(onGameStart)
	tttUpdate.OnClientEvent:Connect(onUpdate)
	tttGameResult.OnClientEvent:Connect(onGameResult)
	tttGameOver.OnClientEvent:Connect(onGameOver)
end

return TicTacToeController
