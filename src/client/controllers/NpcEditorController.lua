--!strict
-- NpcEditorController: the first-meeting "create your friend" editor. When the server fires
-- OpenNpcEditor (the player talked to an NPC they haven't met), this opens a panel with a live
-- preview rig and the body-colour palette (Config.OutfitEditor -- a placeholder for the full Roblox
-- catalog later). Save sends the chosen look to the server (SaveNpcOutfit), which validates it,
-- befriends the NPC, and has it greet the player; Cancel just closes (no friend made). The NPC then
-- renders in the player's chosen look via NpcAppearanceController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local OutfitBuilder = require(ReplicatedStorage.Shared.Util.OutfitBuilder)

local NpcEditorController = {}

local player = Players.LocalPlayer

local openNpcEditor: RemoteEvent
local saveNpcOutfit: RemoteEvent

local root: Frame -- the dimmer + panel, shown only while editing
local previewRig: Model
local swatchStrokes: { [TextButton]: UIStroke } = {}
local swatchColor: { [TextButton]: number } = {}

local currentNpcId: string?
local selectedColor: number = Config.DefaultNpcOutfit.BodyColor

local function unpackColor(packed: number): Color3
	return Color3.fromRGB(
		bit32.band(bit32.rshift(packed, 16), 0xFF),
		bit32.band(bit32.rshift(packed, 8), 0xFF),
		bit32.band(packed, 0xFF)
	)
end

local function recolorPreview(color: number)
	local c = unpackColor(color)
	for _, d in previewRig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = c
		end
	end
end

local function selectColor(button: TextButton)
	selectedColor = swatchColor[button]
	recolorPreview(selectedColor)
	for other, stroke in swatchStrokes do
		stroke.Thickness = if other == button then 4 else 1
		stroke.Color = if other == button then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(0, 0, 0)
	end
end

local function close()
	currentNpcId = nil
	root.Visible = false
end

local function onSave()
	local npcId = currentNpcId
	if not npcId then
		return
	end
	saveNpcOutfit:FireServer(npcId, { BodyColor = selectedColor, Shirt = 0, Pants = 0, Accessories = {} })
	close()
end

local function onOpen(npcId: string)
	currentNpcId = npcId
	selectedColor = Config.DefaultNpcOutfit.BodyColor
	recolorPreview(selectedColor)
	for button, stroke in swatchStrokes do
		stroke.Thickness = if swatchColor[button] == selectedColor then 4 else 1
		stroke.Color = if swatchColor[button] == selectedColor
			then Color3.fromRGB(255, 255, 255)
			else Color3.fromRGB(0, 0, 0)
	end
	root.Visible = true
end

local function buildPreview(parent: GuiObject)
	local viewport = Instance.new("ViewportFrame")
	viewport.LayoutOrder = 2
	viewport.Size = UDim2.fromScale(1, 0.55)
	viewport.BackgroundColor3 = Color3.fromRGB(225, 230, 238)
	viewport.Parent = parent

	local rigOk, rig = pcall(function()
		return OutfitBuilder.buildModel(Config.DefaultNpcOutfit)
	end)
	if rigOk and rig then
		previewRig = rig
		for _, d in previewRig:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		previewRig:PivotTo(CFrame.new(0, 0, 0))
		previewRig.Parent = viewport
	else
		previewRig = Instance.new("Model")
		previewRig.Parent = viewport
	end

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.4, 7), Vector3.new(0, 0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function buildSwatches(parent: GuiObject)
	local grid = Instance.new("Frame")
	grid.LayoutOrder = 3
	grid.Size = UDim2.fromScale(1, 0.28)
	grid.BackgroundTransparency = 1
	grid.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(40, 40)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = grid

	for _, color in Config.OutfitEditor.BodyColors do
		local button = Instance.new("TextButton")
		button.Text = ""
		button.BackgroundColor3 = unpackColor(color)
		button.Parent = grid

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Parent = button

		swatchStrokes[button] = stroke
		swatchColor[button] = color
		button.Activated:Connect(function()
			selectColor(button)
		end)
	end
end

function NpcEditorController:Init()
	openNpcEditor = Net.Event("OpenNpcEditor")
	saveNpcOutfit = Net.Event("SaveNpcOutfit")

	local gui = Instance.new("ScreenGui")
	gui.Name = "NpcEditor"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10

	root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	root.BackgroundTransparency = 0.4
	root.Visible = false
	root.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 480)
	panel.BackgroundColor3 = Color3.fromRGB(35, 38, 46)
	panel.Parent = root

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.Parent = panel

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 34)
	title.BackgroundTransparency = 1
	title.Text = "Create your friend!"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = panel

	buildPreview(panel)
	buildSwatches(panel)

	local buttonRow = Instance.new("Frame")
	buttonRow.LayoutOrder = 4
	buttonRow.Size = UDim2.new(1, 0, 0, 44)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 16)
	rowLayout.Parent = buttonRow

	local function makeButton(text: string, color: Color3, onClick: () -> ()): TextButton
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(150, 40)
		button.BackgroundColor3 = color
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = text
		button.Parent = buttonRow
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		button.Activated:Connect(onClick)
		return button
	end

	makeButton("Cancel", Color3.fromRGB(90, 94, 104), close)
	makeButton("Save", Color3.fromRGB(60, 160, 90), onSave)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function NpcEditorController:Start()
	openNpcEditor.OnClientEvent:Connect(onOpen)
end

return NpcEditorController
