--!strict
-- TravelController: opens the Cab destination picker, drives the Airport boarding-minigame UI,
-- and shows travel status with a screen fade. It only sends requests; PlaceService decides the
-- outcome. The picker lists the player's unlocked places (replicated via attributes) that are
-- real travel destinations, excluding the current one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local InteractionController = require(script.Parent.InteractionController)

local TravelController = {}

local player = Players.LocalPlayer

local requestTravel: RemoteEvent
local travelComplete: RemoteEvent
local startMinigame: RemoteEvent
local minigameInput: RemoteEvent

local pickerFrame: Frame
local pickerList: Frame
local minigameFrame: Frame
local boardButton: TextButton
local countdownLabel: TextLabel
local statusLabel: TextLabel
local fade: Frame

local minigameToken = 0

local function makeButton(text: string, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -16, 0, 40)
	button.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.Parent = parent
	return button
end

local function setPickerVisible(visible: boolean)
	pickerFrame.Visible = visible
end

local function openPicker()
	for _, child in pickerList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local current = player:GetAttribute("CurrentPlace")
	local unlocked = string.split(player:GetAttribute("UnlockedPlaces") :: string or "", ",")
	for _, placeId in unlocked do
		if Config.Places[placeId] and placeId ~= current then
			local button = makeButton(placeId, pickerList)
			button.Activated:Connect(function()
				setPickerVisible(false)
				requestTravel:FireServer(placeId)
			end)
		end
	end

	setPickerVisible(true)
end

local function tweenFade(transparency: number)
	TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = transparency }):Play()
end

local function onStartMinigame(_kind: string, duration: number)
	minigameToken += 1
	local token = minigameToken
	minigameFrame.Visible = true

	task.spawn(function()
		local remaining = duration
		while remaining > 0 and token == minigameToken and minigameFrame.Visible do
			countdownLabel.Text = `Board in {string.format("%.1f", remaining)}s`
			task.wait(0.1)
			remaining -= 0.1
		end
		if token == minigameToken then
			minigameFrame.Visible = false
		end
	end)
end

local function onTravelComplete(success: boolean, reason: string?, placeId: string?)
	minigameToken += 1 -- stop any running countdown
	minigameFrame.Visible = false

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
	startMinigame = Net.Event("StartMinigame")
	minigameInput = Net.Event("MinigameInput")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Travel"
	gui.ResetOnSpawn = false

	fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 10
	fade.Parent = gui

	-- Destination picker.
	pickerFrame = Instance.new("Frame")
	pickerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	pickerFrame.Position = UDim2.fromScale(0.5, 0.5)
	pickerFrame.Size = UDim2.fromOffset(280, 320)
	pickerFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	pickerFrame.Visible = false
	pickerFrame.Parent = gui

	local pickerTitle = Instance.new("TextLabel")
	pickerTitle.Size = UDim2.new(1, 0, 0, 40)
	pickerTitle.BackgroundTransparency = 1
	pickerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	pickerTitle.Font = Enum.Font.GothamBold
	pickerTitle.TextScaled = true
	pickerTitle.Text = "Where to?"
	pickerTitle.Parent = pickerFrame

	pickerList = Instance.new("Frame")
	pickerList.Position = UDim2.fromOffset(8, 48)
	pickerList.Size = UDim2.new(1, -16, 1, -56)
	pickerList.BackgroundTransparency = 1
	pickerList.Parent = pickerFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = pickerList

	-- Boarding minigame.
	minigameFrame = Instance.new("Frame")
	minigameFrame.AnchorPoint = Vector2.new(0.5, 1)
	minigameFrame.Position = UDim2.fromScale(0.5, 0.9)
	minigameFrame.Size = UDim2.fromOffset(280, 120)
	minigameFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	minigameFrame.Visible = false
	minigameFrame.Parent = gui

	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Size = UDim2.new(1, 0, 0, 40)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	countdownLabel.Font = Enum.Font.Gotham
	countdownLabel.TextScaled = true
	countdownLabel.Text = ""
	countdownLabel.Parent = minigameFrame

	boardButton = makeButton("Board the plane!", minigameFrame)
	boardButton.Position = UDim2.fromOffset(8, 56)
	boardButton.AnchorPoint = Vector2.new(0, 0)

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
	InteractionController:OnInteract("Cab", openPicker)

	boardButton.Activated:Connect(function()
		minigameFrame.Visible = false
		minigameInput:FireServer()
	end)

	startMinigame.OnClientEvent:Connect(onStartMinigame)
	travelComplete.OnClientEvent:Connect(onTravelComplete)
end

return TravelController
