--!strict
-- TravelController: opens the "Call a Cab" confirmation and shows travel status with a screen fade.
-- The cab is a binary shuttle, so there is no destination picker: it reads the player's CurrentPlace
-- (replicated as an attribute) to phrase the prompt -- from Home it offers the Airport, from anywhere
-- else it offers Home -- and only sends the request. PlaceService decides and performs the move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)

local TravelController = {}

local player = Players.LocalPlayer

local requestTravel: RemoteEvent
local travelComplete: RemoteEvent

local confirmFrame: Frame
local promptLabel: TextLabel
local statusLabel: TextLabel
local fade: Frame

local function makeButton(text: string, color: Color3, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -12, 0, 44)
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.Parent = parent
	return button
end

local function setConfirmVisible(visible: boolean)
	confirmFrame.Visible = visible
end

-- Opened by the phone ("Call a Cab"). The destination is wherever the player is not: Home -> Airport,
-- otherwise -> Home. The server re-derives this authoritatively; the label is just for the player.
function TravelController:OpenCabConfirm()
	local current = player:GetAttribute("CurrentPlace")
	local goingToAirport = current == "Home"
	promptLabel.Text = if goingToAirport then "Take a cab to the Airport?" else "Take a cab back Home?"
	setConfirmVisible(true)
end

local function tweenFade(transparency: number)
	TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = transparency }):Play()
end

local function onTravelComplete(success: boolean, reason: string?, placeId: string?)
	if success then
		statusLabel.Text = `Arrived at {placeId}`
		tweenFade(0)
		task.wait(0.3)
		tweenFade(1)
	else
		statusLabel.Text = reason or "Travel failed"
	end

	statusLabel.Visible = true
	task.delay(2, function()
		statusLabel.Visible = false
	end)
end

function TravelController:Init()
	requestTravel = Net.Event("RequestTravel")
	travelComplete = Net.Event("TravelComplete")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Travel"
	gui.ResetOnSpawn = false

	fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 10
	fade.Parent = gui

	-- Cab confirmation dialog.
	confirmFrame = Instance.new("Frame")
	confirmFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmFrame.Position = UDim2.fromScale(0.5, 0.5)
	confirmFrame.Size = UDim2.fromOffset(320, 160)
	confirmFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	confirmFrame.Visible = false
	confirmFrame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = "🚕 Call a Cab"
	title.Parent = confirmFrame

	promptLabel = Instance.new("TextLabel")
	promptLabel.Position = UDim2.fromOffset(12, 48)
	promptLabel.Size = UDim2.new(1, -24, 0, 44)
	promptLabel.BackgroundTransparency = 1
	promptLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	promptLabel.Font = Enum.Font.Gotham
	promptLabel.TextScaled = true
	promptLabel.TextWrapped = true
	promptLabel.Text = ""
	promptLabel.Parent = confirmFrame

	local buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -12)
	buttonRow.Size = UDim2.new(1, -24, 0, 44)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = confirmFrame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 16)
	rowLayout.Parent = buttonRow

	local yesButton = makeButton("Yes", Color3.fromRGB(60, 160, 90), buttonRow)
	local noButton = makeButton("No", Color3.fromRGB(120, 60, 60), buttonRow)

	yesButton.Activated:Connect(function()
		setConfirmVisible(false)
		requestTravel:FireServer()
	end)
	noButton.Activated:Connect(function()
		setConfirmVisible(false)
	end)

	-- Status message.
	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5, 0)
	statusLabel.Position = UDim2.fromScale(0.5, 0.08)
	statusLabel.Size = UDim2.fromOffset(320, 36)
	statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	statusLabel.BackgroundTransparency = 0.2
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Visible = false
	statusLabel.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

function TravelController:Start()
	travelComplete.OnClientEvent:Connect(onTravelComplete)
end

return TravelController
