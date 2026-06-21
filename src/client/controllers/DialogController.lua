--!strict
-- DialogController: the interacting player's side of an NPC dialog. The NPC's lines render in a
-- server-side bubble over the NPC (visible to everyone nearby); this controller shows only the
-- bottom-screen buttons — Next while plain lines advance, the branch choices at the end — and
-- reports the pick to DialogService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local DialogController = {}

local player = Players.LocalPlayer

local dialogLine: RemoteEvent
local dialogAdvance: RemoteEvent
local dialogChoose: RemoteEvent
local dialogEnd: RemoteEvent

-- Gym-friend conversations reuse this same button row, with their own remotes (branching trees).
local friendDialogLine: RemoteEvent
local friendDialogChoose: RemoteEvent
local friendDialogEnd: RemoteEvent

local buttonRow: Frame
local npcNameLabel: TextLabel -- displays the NPC name at the top of the dialog UI

local function updateNpcName(npcId: string)
	-- Map npcId to a display name
	local displayName: string
	if npcId == "Postman" then
		displayName = "Postman"
	elseif npcId == "Cowboy" then
		displayName = "Cowboy"
	elseif npcId == "PersonalTrainer" then
		displayName = "Trainer"
	elseif npcId == "Farmer" then
		displayName = "Farmer"
	else
		displayName = npcId
	end
	if npcNameLabel then
		npcNameLabel.Text = displayName
	end
end

local function clearButtons()
	for _, child in buttonRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function addButton(label: string, onActivated: () -> ())
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(140, 40)
	-- Same dark slate look as the "Create your friend!" editor, instead of the old flat blue.
	button.BackgroundColor3 = Color3.fromRGB(55, 60, 72)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = label
	button.Parent = buttonRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	-- Inset the label so it doesn't hug the rounded border.
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
		-- One shot per step: the server answers with the next line or DialogEnd.
		clearButtons()
		onActivated()
	end)
end

local function onDialogLine(_text: string, _index: number, _total: number, choices: { string }?, npcId: string?)
	if npcId then
		updateNpcName(npcId)
	end
	npcNameLabel.Text = npcId or ""
	buttonRow.Visible = true
	clearButtons()
	if choices then
		for choiceIndex, label in choices do
			addButton(label, function()
				dialogChoose:FireServer(choiceIndex)
			end)
		end
	else
		addButton("Next \u{27A1}\u{FE0F}", function()
			dialogAdvance:FireServer()
		end)
	end
end

local function onDialogEnd()
	clearButtons()
	buttonRow.Visible = false
	if npcNameLabel then
		npcNameLabel.Text = ""
	end
end

-- Gym-friend lines always carry the player's answer choices (a branching tree, no plain "Next");
-- render them with the same buttons and report the pick on the friend remote.
local function onFriendLine(_text: string, choices: { string })
	buttonRow.Visible = true
	clearButtons()
	for choiceIndex, label in choices do
		addButton(label, function()
			friendDialogChoose:FireServer(choiceIndex)
		end)
	end
end

function DialogController:Init()
	dialogLine = Net.Event("DialogLine")
	dialogAdvance = Net.Event("DialogAdvance")
	dialogChoose = Net.Event("DialogChoose")
	dialogEnd = Net.Event("DialogEnd")
	friendDialogLine = Net.Event("FriendDialogLine")
	friendDialogChoose = Net.Event("FriendDialogChoose")
	friendDialogEnd = Net.Event("FriendDialogEnd")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Dialog"
	gui.ResetOnSpawn = false

	buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	-- sits above the Photo shutter button so the two never overlap
	buttonRow.Position = UDim2.new(0.5, 0, 1, -140)
	buttonRow.Size = UDim2.fromOffset(440, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Visible = false
	buttonRow.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttonRow

	-- NPC name label shown above the button row
	npcNameLabel = Instance.new("TextLabel")
	npcNameLabel.AnchorPoint = Vector2.new(0.5, 0)
	npcNameLabel.Position = UDim2.new(0.5, 0, 1, -148)
	npcNameLabel.Size = UDim2.fromOffset(300, 24)
	npcNameLabel.BackgroundTransparency = 1
	npcNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	npcNameLabel.Font = Enum.Font.GothamBold
	npcNameLabel.TextScaled = true
	npcNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	npcNameLabel.Text = ""
	npcNameLabel.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DialogController:Start()
	dialogLine.OnClientEvent:Connect(onDialogLine)
	dialogEnd.OnClientEvent:Connect(onDialogEnd)
	friendDialogLine.OnClientEvent:Connect(onFriendLine)
	friendDialogEnd.OnClientEvent:Connect(onDialogEnd)
end

return DialogController
