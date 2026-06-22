--!strict
-- MemoryController: the recognition-memory (Nurse) gameplay UI — the game-specific half that the
-- generic MinigameController pre-game shell hands off to. The server flashes a set of target emojis
-- (MemoryShowTargets), then reveals a 4x4 grid (MemoryRecallPhase). This controller shows the targets,
-- then lets the player toggle-select grid cells and Submit; the server grades and pays. New minigames
-- add their own controller alongside this one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local MemoryController = {}

local player = Players.LocalPlayer

local GRID_COLUMNS = 4
local CELL_SIZE = 72
local CELL_PAD = 8

local CELL_IDLE = Color3.fromRGB(60, 70, 90)
local CELL_SELECTED = Color3.fromRGB(255, 200, 70)
local SUBMIT_READY = Color3.fromRGB(80, 180, 110)
local SUBMIT_IDLE = Color3.fromRGB(70, 75, 85)

local memoryShowTargets: RemoteEvent
local memoryRecallPhase: RemoteEvent
local memorySubmit: RemoteEvent
local memoryRoundResult: RemoteEvent
local memoryGameOver: RemoteEvent

-- Target panel: flashed emojis to memorize.
local targetFrame: Frame
local targetRoundLabel: TextLabel
local targetRow: Frame

-- Recall panel: the 4x4 grid + submit.
local gridFrame: Frame
local gridRoundLabel: TextLabel
local statusLabel: TextLabel
local submitButton: TextButton
local cellButtons: { TextButton } = {}

local inputEnabled = false
local targetCount = 0
local selected: { [number]: boolean } = {}
local selectedCount = 0

local function clearTargetRow()
	for _, child in targetRow:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function refreshSubmit()
	local ready = inputEnabled and selectedCount == targetCount
	submitButton.BackgroundColor3 = if ready then SUBMIT_READY else SUBMIT_IDLE
	submitButton.AutoButtonColor = ready
end

local function clearSelection()
	selected = {}
	selectedCount = 0
	for _, button in cellButtons do
		button.BackgroundColor3 = CELL_IDLE
	end
	refreshSubmit()
end

local function toggleCell(index: number)
	if not inputEnabled then
		return
	end
	if selected[index] then
		selected[index] = nil
		selectedCount -= 1
		cellButtons[index].BackgroundColor3 = CELL_IDLE
	elseif selectedCount < targetCount then
		selected[index] = true
		selectedCount += 1
		cellButtons[index].BackgroundColor3 = CELL_SELECTED
	end
	refreshSubmit()
end

local function onSubmitPressed()
	if not inputEnabled or selectedCount ~= targetCount then
		return
	end
	inputEnabled = false
	refreshSubmit()
	local indices = table.create(targetCount)
	for index in selected do
		table.insert(indices, index)
	end
	statusLabel.Text = "Checking..."
	memorySubmit:FireServer(indices)
end

local function onShowTargets(targets: { string }, round: number, maxRounds: number)
	targetCount = #targets
	inputEnabled = false
	gridFrame.Visible = false

	targetRoundLabel.Text = `Round {round} / {maxRounds} — memorize these!`
	clearTargetRow()
	for order, emoji in targets do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.fromOffset(64, 64)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = emoji
		label.Parent = targetRow
	end
	targetFrame.Visible = true
end

local function onRecallPhase(grid: { string }, _timeoutSeconds: number, round: number, maxRounds: number)
	targetFrame.Visible = false
	gridRoundLabel.Text = `Round {round} / {maxRounds}`
	statusLabel.Text = "Tap the items you saw, then Submit"
	for index, button in cellButtons do
		button.Text = grid[index] or ""
	end
	clearSelection()
	inputEnabled = true
	refreshSubmit()
	gridFrame.Visible = true
end

local function onRoundResult(correct: boolean, reward: number)
	inputEnabled = false
	refreshSubmit()
	if not correct then
		statusLabel.Text = "Not quite!"
	elseif reward > 0 then
		statusLabel.Text = `Round cleared! +{reward} followers`
	else
		statusLabel.Text = "Nice!"
	end
end

local function onGameOver(totalReward: number, roundsCompleted: number, cleared: boolean)
	inputEnabled = false
	targetFrame.Visible = false
	statusLabel.Text = if cleared
		then `🧠 Memory complete! +{totalReward} followers`
		else `Session over — {roundsCompleted} rounds, +{totalReward} followers`
	task.delay(2.5, function()
		gridFrame.Visible = false
	end)
end

function MemoryController:Init()
	memoryShowTargets = Net.Event("MemoryShowTargets")
	memoryRecallPhase = Net.Event("MemoryRecallPhase")
	memorySubmit = Net.Event("MemorySubmit")
	memoryRoundResult = Net.Event("MemoryRoundResult")
	memoryGameOver = Net.Event("MemoryGameOver")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Memory"
	gui.ResetOnSpawn = false

	-- Target panel (flashed emojis to memorize).
	targetFrame = Instance.new("Frame")
	targetFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	targetFrame.Position = UDim2.fromScale(0.5, 0.4)
	targetFrame.Size = UDim2.fromOffset(460, 160)
	targetFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	targetFrame.BackgroundTransparency = 0.05
	targetFrame.Visible = false
	targetFrame.Parent = gui

	local targetCorner = Instance.new("UICorner")
	targetCorner.CornerRadius = UDim.new(0, 16)
	targetCorner.Parent = targetFrame

	targetRoundLabel = Instance.new("TextLabel")
	targetRoundLabel.Size = UDim2.new(1, -16, 0, 36)
	targetRoundLabel.Position = UDim2.fromOffset(8, 8)
	targetRoundLabel.BackgroundTransparency = 1
	targetRoundLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	targetRoundLabel.Font = Enum.Font.GothamBold
	targetRoundLabel.TextScaled = true
	targetRoundLabel.Text = ""
	targetRoundLabel.Parent = targetFrame

	targetRow = Instance.new("Frame")
	targetRow.AnchorPoint = Vector2.new(0.5, 1)
	targetRow.Position = UDim2.new(0.5, 0, 1, -16)
	targetRow.Size = UDim2.new(1, -24, 0, 80)
	targetRow.BackgroundTransparency = 1
	targetRow.Parent = targetFrame

	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	targetLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	targetLayout.Padding = UDim.new(0, 10)
	targetLayout.Parent = targetRow

	-- Recall panel (the 4x4 grid + submit).
	gridFrame = Instance.new("Frame")
	gridFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gridFrame.Position = UDim2.fromScale(0.5, 0.45)
	gridFrame.Size = UDim2.fromOffset(380, 470)
	gridFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	gridFrame.Visible = false
	gridFrame.Parent = gui

	local gridCorner = Instance.new("UICorner")
	gridCorner.CornerRadius = UDim.new(0, 16)
	gridCorner.Parent = gridFrame

	gridRoundLabel = Instance.new("TextLabel")
	gridRoundLabel.Size = UDim2.new(1, -16, 0, 28)
	gridRoundLabel.Position = UDim2.fromOffset(8, 8)
	gridRoundLabel.BackgroundTransparency = 1
	gridRoundLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	gridRoundLabel.Font = Enum.Font.GothamBold
	gridRoundLabel.TextScaled = true
	gridRoundLabel.Text = ""
	gridRoundLabel.Parent = gridFrame

	local gridHolder = Instance.new("Frame")
	gridHolder.AnchorPoint = Vector2.new(0.5, 0)
	gridHolder.Position = UDim2.new(0.5, 0, 0, 44)
	gridHolder.Size = UDim2.fromOffset(
		GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_PAD,
		GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_PAD
	)
	gridHolder.BackgroundTransparency = 1
	gridHolder.Parent = gridFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	gridLayout.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
	gridLayout.FillDirectionMaxCells = GRID_COLUMNS
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridHolder

	for index = 1, GRID_COLUMNS * GRID_COLUMNS do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.BackgroundColor3 = CELL_IDLE
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = ""
		button.Parent = gridHolder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button

		button.Activated:Connect(function()
			toggleCell(index)
		end)
		cellButtons[index] = button
	end

	submitButton = Instance.new("TextButton")
	submitButton.AnchorPoint = Vector2.new(0.5, 1)
	submitButton.Position = UDim2.new(0.5, 0, 1, -44)
	submitButton.Size = UDim2.fromOffset(220, 44)
	submitButton.BackgroundColor3 = SUBMIT_IDLE
	submitButton.AutoButtonColor = false
	submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	submitButton.Font = Enum.Font.GothamBold
	submitButton.TextScaled = true
	submitButton.Text = "Submit"
	submitButton.Parent = gridFrame

	local submitCorner = Instance.new("UICorner")
	submitCorner.CornerRadius = UDim.new(0, 10)
	submitCorner.Parent = submitButton

	submitButton.Activated:Connect(onSubmitPressed)

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
	statusLabel.Size = UDim2.new(1, -16, 0, 26)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(220, 220, 120)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Parent = gridFrame

	gui.Parent = player:WaitForChild("PlayerGui")
end

function MemoryController:Start()
	memoryShowTargets.OnClientEvent:Connect(onShowTargets)
	memoryRecallPhase.OnClientEvent:Connect(onRecallPhase)
	memoryRoundResult.OnClientEvent:Connect(onRoundResult)
	memoryGameOver.OnClientEvent:Connect(onGameOver)
end

return MemoryController
