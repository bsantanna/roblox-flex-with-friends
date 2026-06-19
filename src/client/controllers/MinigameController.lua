--!strict
-- MinigameController: the generic pre-game UI shell shared by every NPC minigame. The server drives
-- the flow: MinigameAwaitReady asks the player to step onto the green ready-zone in front of the
-- NPC; MinigameInstructions shows the rules with a Start button (the NPC also says them in a speech
-- bubble); MinigameConfirmStart tells the server to begin; MinigameAborted dismisses this UI if the
-- player took too long. The game-specific UI (e.g. SimonSaysController's arrows) takes over from
-- there. Also toasts NPC unlocks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local MinigameController = {}

local player = Players.LocalPlayer

local awaitReady: RemoteEvent
local instructionsEvent: RemoteEvent
local confirmStart: RemoteEvent
local aborted: RemoteEvent
local unlockNpc: RemoteEvent

local readyBanner: TextLabel
local instructionPanel: Frame
local instructionLabel: TextLabel
local toast: TextLabel

local function hidePregame()
	readyBanner.Visible = false
	instructionPanel.Visible = false
end

local function onAwaitReady()
	instructionPanel.Visible = false
	readyBanner.Visible = true
end

local function onInstructions(instructions: string)
	readyBanner.Visible = false
	instructionLabel.Text = instructions
	instructionPanel.Visible = true
end

local function onConfirm()
	hidePregame()
	confirmStart:FireServer()
end

local function onUnlockNpc(npcId: string)
	toast.Text = `Unlocked: {npcId}`
	toast.Visible = true
	task.delay(3, function()
		toast.Visible = false
	end)
end

function MinigameController:Init()
	awaitReady = Net.Event("MinigameAwaitReady")
	instructionsEvent = Net.Event("MinigameInstructions")
	confirmStart = Net.Event("MinigameConfirmStart")
	aborted = Net.Event("MinigameAborted")
	unlockNpc = Net.Event("UnlockNpc")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Minigame"
	gui.ResetOnSpawn = false

	-- "Head to the green circle" banner near the top.
	readyBanner = Instance.new("TextLabel")
	readyBanner.AnchorPoint = Vector2.new(0.5, 0)
	readyBanner.Position = UDim2.fromScale(0.5, 0.22)
	readyBanner.Size = UDim2.fromOffset(420, 40)
	readyBanner.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	readyBanner.TextColor3 = Color3.fromRGB(255, 255, 255)
	readyBanner.Font = Enum.Font.GothamBold
	readyBanner.TextScaled = true
	readyBanner.Text = "Step onto the green circle to begin!"
	readyBanner.Visible = false
	readyBanner.Parent = gui
	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 8)
	bannerCorner.Parent = readyBanner

	-- Instructions panel with a Start button, centred.
	instructionPanel = Instance.new("Frame")
	instructionPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	instructionPanel.Position = UDim2.fromScale(0.5, 0.4)
	instructionPanel.Size = UDim2.fromOffset(420, 220)
	instructionPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	instructionPanel.Visible = false
	instructionPanel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = instructionPanel

	instructionLabel = Instance.new("TextLabel")
	instructionLabel.AnchorPoint = Vector2.new(0.5, 0)
	instructionLabel.Position = UDim2.new(0.5, 0, 0, 16)
	instructionLabel.Size = UDim2.new(1, -32, 1, -84)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	instructionLabel.Font = Enum.Font.Gotham
	instructionLabel.TextWrapped = true
	instructionLabel.TextScaled = true
	instructionLabel.Text = ""
	instructionLabel.Parent = instructionPanel

	local startButton = Instance.new("TextButton")
	startButton.AnchorPoint = Vector2.new(0.5, 1)
	startButton.Position = UDim2.new(0.5, 0, 1, -16)
	startButton.Size = UDim2.fromOffset(180, 48)
	startButton.BackgroundColor3 = Color3.fromRGB(60, 180, 90)
	startButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	startButton.Font = Enum.Font.GothamBold
	startButton.TextScaled = true
	startButton.Text = "Start"
	startButton.Parent = instructionPanel
	local startCorner = Instance.new("UICorner")
	startCorner.CornerRadius = UDim.new(0, 8)
	startCorner.Parent = startButton
	startButton.Activated:Connect(onConfirm)

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
	awaitReady.OnClientEvent:Connect(onAwaitReady)
	instructionsEvent.OnClientEvent:Connect(onInstructions)
	aborted.OnClientEvent:Connect(hidePregame)
	unlockNpc.OnClientEvent:Connect(onUnlockNpc)
end

return MinigameController
