--!strict
-- RockPaperScissorsController: the Cowboy Rock-Paper-Scissors gameplay UI — the game-specific half
-- the generic MinigameController pre-game shell hands off to. The server owns the game: it fires
-- RpsPickPhase when it accepts a hand, then RpsReveal once it has thrown (the opponent's hand is
-- already decided server-side; the reel here is pure flair that lands on it). This controller shows
-- the three hand buttons, spins the opponent reel like a wheel of fortune, and recaps each round and
-- the match. New minigames add their own controller alongside this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local RockPaperScissorsController = {}

local player = Players.LocalPlayer

local ORDER = { "Rock", "Paper", "Scissors" } -- on-screen button order
local EMOJI = { Rock = "\u{270A}", Paper = "\u{270B}", Scissors = "\u{270C}\u{FE0F}" }
local KEY_CHOICE: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Rock",
	[Enum.KeyCode.Two] = "Paper",
	[Enum.KeyCode.Three] = "Scissors",
}

local BUTTON_IDLE = Color3.fromRGB(60, 120, 200)
local BUTTON_PICKED = Color3.fromRGB(60, 200, 90)
local REEL_STEP = 0.08 -- seconds between reel flips while spinning

local rpsPickPhase: RemoteEvent
local rpsPlayerChoice: RemoteEvent
local rpsReveal: RemoteEvent
local rpsGameOver: RemoteEvent

local gameFrame: Frame
local scoreLabel: TextLabel
local statusLabel: TextLabel
local reelLabel: TextLabel
local choiceButtons: { [string]: TextButton } = {}

-- Centered panel that recaps the match outcome.
local feedbackFrame: Frame
local feedbackTitle: TextLabel
local feedbackScore: TextLabel
local feedbackSubtitle: TextLabel

local inputEnabled = false
local reelToken: {}? = nil -- identity token so a new round/reveal cancels an in-flight spin

local orderKey: string? = nil -- npcId received from the server, used for opponent name in UI

local function setScore(playerWins: number, opponentWins: number)
	local name = orderKey or "Cowboy"
	scoreLabel.Text = `You {playerWins}  —  {opponentWins} {name}`
end

local function resetButtons()
	for _, button in choiceButtons do
		button.BackgroundColor3 = BUTTON_IDLE
	end
end

local function hideFeedback()
	feedbackFrame.Visible = false
end

local function sendChoice(choice: string)
	if not inputEnabled then
		return
	end
	inputEnabled = false
	resetButtons()
	local button = choiceButtons[choice]
	if button then
		button.BackgroundColor3 = BUTTON_PICKED
	end
	statusLabel.Text = `You threw {EMOJI[choice]} — {orderKey or "Cowboy"} is throwing...`
	rpsPlayerChoice:FireServer(choice)
end

local function onPickPhase(_choices: { string }, _timeoutSeconds: number, npcId: string)
	orderKey = npcId
	hideFeedback()
	gameFrame.Visible = true
	inputEnabled = true
	reelToken = nil -- stop any leftover spin
	resetButtons()
	reelLabel.Text = "\u{2753}" -- question mark while waiting for the throw
	statusLabel.Text = "Pick your hand!"
end

-- Spins the reel through the emojis for `seconds`, then lands on `finalChoice` and runs `onLand`.
local function spinReel(finalChoice: string, seconds: number, onLand: () -> ())
	local token = {}
	reelToken = token
	task.spawn(function()
		local elapsed = 0
		local index = 1
		while reelToken == token and elapsed < seconds do
			reelLabel.Text = EMOJI[ORDER[index]]
			index = (index % #ORDER) + 1
			task.wait(REEL_STEP)
			elapsed += REEL_STEP
		end
		if reelToken == token then
			reelLabel.Text = EMOJI[finalChoice] or "\u{2753}"
			onLand()
		end
	end)
end

local function onReveal(
	_playerChoice: string,
	opponentChoice: string,
	outcome: string,
	reelSeconds: number,
	playerWins: number,
	opponentWins: number,
	roundReward: number
)
	inputEnabled = false
	local name = orderKey or "Cowboy"
	statusLabel.Text = `${name} is throwing...`
	spinReel(opponentChoice, reelSeconds, function()
		setScore(playerWins, opponentWins)
		if outcome == "win" then
			statusLabel.Text = `You win the round! +{roundReward} followers`
		elseif outcome == "lose" then
			statusLabel.Text = `${name} wins the round!`
		else
			statusLabel.Text = "Tie — throw again!"
		end
	end)
end

local function onGameOver(won: boolean, playerWins: number, opponentWins: number, totalReward: number, npcId: string)
	inputEnabled = false
	reelToken = nil
	local name = npcId or "Cowboy"
	if won then
		feedbackTitle.Text = "\u{1F3C6} You won the match!"
		feedbackTitle.TextColor3 = Color3.fromRGB(120, 240, 140)
		feedbackSubtitle.Text = `\u{2B50} +{totalReward} followers and the {name} trophy!`
	else
		feedbackTitle.Text = `\u{1F605} {name} got you!`
		feedbackTitle.TextColor3 = Color3.fromRGB(255, 170, 90)
		feedbackSubtitle.Text = if totalReward > 0
			then `\u{1F920} +{totalReward} followers — catch {name} on the route!`
			else `\u{1F920} Better luck next time, {name}!`
	end
	feedbackScore.Text = `You {playerWins}  —  {opponentWins} {name}`
	feedbackFrame.Visible = true
	task.delay(5, hideFeedback)
	task.delay(2.5, function()
		gameFrame.Visible = false
	end)
end

function RockPaperScissorsController:Init()
	rpsPickPhase = Net.Event("RpsPickPhase")
	rpsPlayerChoice = Net.Event("RpsPlayerChoice")
	rpsReveal = Net.Event("RpsReveal")
	rpsGameOver = Net.Event("RpsGameOver")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RockPaperScissors"
	gui.ResetOnSpawn = false

	gameFrame = Instance.new("Frame")
	gameFrame.AnchorPoint = Vector2.new(0.5, 1)
	gameFrame.Position = UDim2.fromScale(0.5, 0.92)
	gameFrame.Size = UDim2.fromOffset(340, 230)
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
	scoreLabel.Text = "You 0  —  0 ?"
	scoreLabel.Parent = gameFrame

	-- The opponent reel: a big emoji that spins like a wheel of fortune and lands on the throw.
	reelLabel = Instance.new("TextLabel")
	reelLabel.AnchorPoint = Vector2.new(0.5, 0)
	reelLabel.Position = UDim2.new(0.5, 0, 0, 40)
	reelLabel.Size = UDim2.fromOffset(80, 80)
	reelLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	reelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	reelLabel.Font = Enum.Font.GothamBlack
	reelLabel.TextScaled = true
	reelLabel.Text = "\u{2753}"
	reelLabel.Parent = gameFrame

	local reelCorner = Instance.new("UICorner")
	reelCorner.CornerRadius = UDim.new(0, 12)
	reelCorner.Parent = reelLabel

	local choiceRow = Instance.new("Frame")
	choiceRow.AnchorPoint = Vector2.new(0.5, 0)
	choiceRow.Position = UDim2.new(0.5, 0, 0, 128)
	choiceRow.Size = UDim2.fromOffset(296, 64)
	choiceRow.BackgroundTransparency = 1
	choiceRow.Parent = gameFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = choiceRow

	for order, choice in ORDER do
		local button = Instance.new("TextButton")
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(64, 64)
		button.BackgroundColor3 = BUTTON_IDLE
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = EMOJI[choice]
		button.Parent = choiceRow
		button.Activated:Connect(function()
			sendChoice(choice)
		end)
		choiceButtons[choice] = button
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

	-- Centered match-over recap (mirrors the Simon Says feedback panel).
	feedbackFrame = Instance.new("Frame")
	feedbackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	feedbackFrame.Position = UDim2.fromScale(0.5, 0.4)
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

function RockPaperScissorsController:Start()
	rpsPickPhase.OnClientEvent:Connect(onPickPhase)
	rpsReveal.OnClientEvent:Connect(onReveal)
	rpsGameOver.OnClientEvent:Connect(onGameOver)

	-- 1/2/3 double as a keyboard shortcut for Rock/Paper/Scissors; sendChoice no-ops unless the
	-- pick phase is open. Ignore keys typed into a focused TextBox.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local choice = KEY_CHOICE[input.KeyCode]
		if choice then
			sendChoice(choice)
		end
	end)
end

return RockPaperScissorsController
