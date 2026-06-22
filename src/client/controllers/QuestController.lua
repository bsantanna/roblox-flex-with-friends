--!strict
-- QuestController: the interacting player's side of the Pilot quest. It listens to the single
-- QuestState sync and drives the player-only UI. Phase A renders the Accept/Decline choice when the
-- server offers the quest (phase "offer") and reports the pick on QuestAccept/QuestDecline. The quest
-- HUD (timer + objective counter) and the objective beacons are layered on in later phases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local QuestController = {}

local player = Players.LocalPlayer

local questState: RemoteEvent
local questAccept: RemoteEvent
local questDecline: RemoteEvent

local buttonRow: Frame

local function clearButtons()
	for _, child in buttonRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

-- Matches DialogController's button look so the quest choice reads as part of the same dialog UI.
local function addButton(label: string, onActivated: () -> ())
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(140, 40)
	button.BackgroundColor3 = Color3.fromRGB(55, 60, 72)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = label
	button.Parent = buttonRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 98, 116)
	stroke.Thickness = 1
	stroke.Parent = button

	button.Activated:Connect(function()
		clearButtons()
		buttonRow.Visible = false
		onActivated()
	end)
end

local function showOffer()
	buttonRow.Visible = true
	clearButtons()
	addButton("Accept", function()
		questAccept:FireServer()
	end)
	addButton("Decline", function()
		questDecline:FireServer()
	end)
end

local function onQuestState(_questId: string, phase: string, _collected: number, _total: number, _deadline: number?)
	if phase == "offer" then
		showOffer()
	else
		clearButtons()
		buttonRow.Visible = false
	end
end

function QuestController:Init()
	questState = Net.Event("QuestState")
	questAccept = Net.Event("QuestAccept")
	questDecline = Net.Event("QuestDecline")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Quest"
	gui.ResetOnSpawn = false

	buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -140) -- above the Photo shutter, like DialogController
	buttonRow.Size = UDim2.fromOffset(440, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Visible = false
	buttonRow.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttonRow

	gui.Parent = player:WaitForChild("PlayerGui")
end

function QuestController:Start()
	questState.OnClientEvent:Connect(onQuestState)
end

return QuestController
