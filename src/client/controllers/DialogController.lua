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

local buttonRow: Frame

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
	button.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = label
	button.Parent = buttonRow
	button.Activated:Connect(function()
		-- One shot per step: the server answers with the next line or DialogEnd.
		clearButtons()
		onActivated()
	end)
end

local function onDialogLine(_text: string, _index: number, _total: number, choices: { string }?)
	buttonRow.Visible = true
	clearButtons()
	if choices then
		for choiceIndex, label in choices do
			addButton(label, function()
				dialogChoose:FireServer(choiceIndex)
			end)
		end
	else
		addButton("Next \u{25B8}", function()
			dialogAdvance:FireServer()
		end)
	end
end

local function onDialogEnd()
	clearButtons()
	buttonRow.Visible = false
end

function DialogController:Init()
	dialogLine = Net.Event("DialogLine")
	dialogAdvance = Net.Event("DialogAdvance")
	dialogChoose = Net.Event("DialogChoose")
	dialogEnd = Net.Event("DialogEnd")

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

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DialogController:Start()
	dialogLine.OnClientEvent:Connect(onDialogLine)
	dialogEnd.OnClientEvent:Connect(onDialogEnd)
end

return DialogController
