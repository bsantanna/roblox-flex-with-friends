--!strict
-- NpcEditorController: the first-meeting "create your friend" editor. When the server fires
-- OpenNpcEditor (the player talked to an NPC they haven't met), this opens a panel with a live preview
-- rig and tabs to dress the friend: a body-colour palette plus Shirt / Pants / accessory-slot tabs,
-- each backed by the Roblox catalog (AvatarEditorService:SearchCatalog). Picking an item rebuilds the
-- preview. Save sends the chosen look to the server (SaveNpcOutfit), which validates every id against
-- the catalog, befriends the NPC, and has it greet the player; Cancel just closes (no friend made).
-- The NPC then renders in the player's chosen look via NpcAppearanceController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local OutfitBuilder = require(ReplicatedStorage.Shared.Util.OutfitBuilder)

type OutfitData = Types.OutfitData

local NpcEditorController = {}

local player = Players.LocalPlayer

local openNpcEditor: RemoteEvent
local saveNpcOutfit: RemoteEvent

local root: Frame -- the dimmer + panel, shown only while editing
local viewport: ViewportFrame
local previewWorld: WorldModel -- holds the preview rig so accessory welds form (a bare ViewportFrame won't)
local tabRow: ScrollingFrame
local grid: ScrollingFrame
local previewRig: Model?
local previewGen = 0 -- guards async rig rebuilds: a stale build (older gen) is discarded
local previewYaw = math.pi -- the friend faces the camera by default; drag the preview to spin it

local currentNpcId: string?
local selectedColor: number = Config.DefaultNpcOutfit.BodyColor
local selectedShirt = 0
local selectedPants = 0
local selectedAccessories: { [number]: number } = {} -- AccessoryType value -> chosen asset id

type Tab = {
	label: string,
	kind: string, -- "color" | "clothing" | "accessory"
	category: Enum.AvatarAssetType?,
	field: string?, -- "Shirt" | "Pants" for clothing tabs
	accType: number?, -- Enum.AccessoryType value for accessory tabs
}
local tabs: { Tab } = {}
local activeTab = 1
local catalogCache: { [number]: { { Id: number, Name: string } } } = {} -- AvatarAssetType value -> items

-- A grid item plus a predicate for whether it is the current selection (for highlighting).
type GridEntry = { stroke: UIStroke, isSelected: () -> boolean }
local gridEntries: { GridEntry }
local tabButtons: { [number]: TextButton } = {} -- tab index -> its button (active tab gets a lighter bg)

-- Tab backgrounds: the active tab is a lighter slate so it reads clearly without touching the text.
local TAB_BG = Color3.fromRGB(55, 60, 72)
local TAB_BG_ACTIVE = Color3.fromRGB(120, 130, 152)

local function highlightTab(button: TextButton, on: boolean)
	button.BackgroundColor3 = if on then TAB_BG_ACTIVE else TAB_BG
end

local function unpackColor(packed: number): Color3
	return Color3.fromRGB(
		bit32.band(bit32.rshift(packed, 16), 0xFF),
		bit32.band(bit32.rshift(packed, 8), 0xFF),
		bit32.band(packed, 0xFF)
	)
end

local function highlight(stroke: UIStroke, on: boolean)
	stroke.Thickness = if on then 4 else 1
	stroke.Color = if on then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(0, 0, 0)
end

local function refreshGridHighlights()
	for _, entry in gridEntries do
		highlight(entry.stroke, entry.isSelected())
	end
end

local function currentOutfit(): OutfitData
	local accessories = {}
	for accType, id in selectedAccessories do
		table.insert(accessories, { AssetId = id, Type = accType })
	end
	return { BodyColor = selectedColor, Shirt = selectedShirt, Pants = selectedPants, Accessories = accessories }
end

-- Instant recolour of the existing rig (cheap -- no rebuild), used for body-colour changes.
local function recolorPreview()
	if not previewRig then
		return
	end
	local c = unpackColor(selectedColor)
	for _, d in previewRig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = c
		end
	end
end

-- Orients the preview rig to the current drag yaw (origin-pivot, so it just spins in place).
local function applyPreviewOrientation()
	if previewRig then
		previewRig:PivotTo(CFrame.Angles(0, previewYaw, 0))
	end
end

-- Rebuilds the preview rig from the current selection (clothing/accessories need a full rebuild --
-- CreateHumanoidModelFromDescription yields, so guard against an out-of-date build replacing a newer one).
local function rebuildPreview()
	previewGen += 1
	local gen = previewGen
	local outfit = currentOutfit()
	task.spawn(function()
		local ok, rig = pcall(function()
			return OutfitBuilder.buildModel(outfit)
		end)
		if not (ok and rig) or gen ~= previewGen then
			if ok and rig then
				rig:Destroy()
			end
			return
		end
		-- Anchor only the root: a ViewportFrame runs no physics, so the limbs hold their pose via their
		-- Motor6Ds and accessories stay welded to the head. (Anchoring every part freezes an accessory
		-- at its pre-weld position, leaving it floating above the head.)
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.Anchored = true
		end
		rig:PivotTo(CFrame.Angles(0, previewYaw, 0))
		if previewRig then
			previewRig:Destroy()
		end
		previewRig = rig
		rig.Parent = previewWorld
	end)
end

-- Builds the catalog items for a category once (cached). Yields on SearchCatalog.
local function loadCatalog(category: Enum.AvatarAssetType): { { Id: number, Name: string } }
	local cached = catalogCache[category.Value]
	if cached then
		return cached
	end
	local items: { { Id: number, Name: string } } = {}
	pcall(function()
		local params = CatalogSearchParams.new()
		params.AssetTypes = { category }
		params.SortType = Enum.CatalogSortType.MostFavorited
		for _, item in AvatarEditorService:SearchCatalog(params):GetCurrentPage() do
			table.insert(items, { Id = (item :: any).Id, Name = (item :: any).Name })
		end
	end)
	catalogCache[category.Value] = items
	return items
end

local function clearGrid()
	gridEntries = {}
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

-- A clickable grid cell with a selection outline. `image` is a thumbnail (catalog item) or nil (a
-- text label, e.g. the "None" cell or a colour swatch whose colour is set by the caller).
local function makeCell(image: string?, isSelected: () -> boolean, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(80, 80)
	button.BackgroundColor3 = Color3.fromRGB(225, 230, 238)
	button.Text = ""
	button.AutoButtonColor = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Parent = button

	if image then
		local thumb = Instance.new("ImageLabel")
		thumb.Size = UDim2.fromScale(1, 1)
		thumb.BackgroundTransparency = 1
		thumb.Image = image
		thumb.Parent = button
	end

	button.Activated:Connect(onClick)
	button.Parent = grid
	table.insert(gridEntries, { stroke = stroke, isSelected = isSelected })
	highlight(stroke, isSelected())
	return button
end

local function buildColorGrid()
	for _, color in Config.OutfitEditor.BodyColors do
		local cell = makeCell(nil, function()
			return selectedColor == color
		end, function()
			selectedColor = color
			recolorPreview()
			refreshGridHighlights()
		end)
		cell.BackgroundColor3 = unpackColor(color)
	end
end

local function buildCatalogGrid(tab: Tab)
	local category = tab.category :: Enum.AvatarAssetType

	-- A "None" cell that clears this slot.
	makeCell(nil, function()
		if tab.kind == "clothing" then
			return (if tab.field == "Shirt" then selectedShirt else selectedPants) == 0
		end
		return selectedAccessories[tab.accType :: number] == nil
	end, function()
		if tab.kind == "clothing" then
			if tab.field == "Shirt" then
				selectedShirt = 0
			else
				selectedPants = 0
			end
		else
			selectedAccessories[tab.accType :: number] = nil
		end
		rebuildPreview()
		refreshGridHighlights()
	end).Text =
		"None"

	local loadingForTab = activeTab
	task.spawn(function()
		local items = loadCatalog(category)
		if activeTab ~= loadingForTab then
			return -- the player switched tabs while we were fetching
		end
		for _, item in items do
			local id = item.Id
			makeCell(string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", id), function()
				if tab.kind == "clothing" then
					return (if tab.field == "Shirt" then selectedShirt else selectedPants) == id
				end
				return selectedAccessories[tab.accType :: number] == id
			end, function()
				if tab.kind == "clothing" then
					-- Toggle off if re-picking the equipped item.
					local equipped = if tab.field == "Shirt" then selectedShirt else selectedPants
					local value = if equipped == id then 0 else id
					if tab.field == "Shirt" then
						selectedShirt = value
					else
						selectedPants = value
					end
				else
					local slot = tab.accType :: number
					if selectedAccessories[slot] == id then
						selectedAccessories[slot] = nil -- toggle off
					else
						selectedAccessories[slot] = id
					end
				end
				rebuildPreview()
				refreshGridHighlights()
			end)
		end
	end)
end

local function selectTab(index: number)
	activeTab = index
	for i, button in tabButtons do
		highlightTab(button, i == index)
	end
	clearGrid()
	local tab = tabs[index]
	if tab.kind == "color" then
		buildColorGrid()
	else
		buildCatalogGrid(tab)
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
	saveNpcOutfit:FireServer(npcId, currentOutfit())
	close()
end

-- Resets the selection to the default look and opens the editor for `npcId`.
local function onOpen(npcId: string)
	currentNpcId = npcId
	selectedColor = Config.DefaultNpcOutfit.BodyColor
	selectedShirt = 0
	selectedPants = 0
	selectedAccessories = {}
	previewYaw = math.pi
	rebuildPreview()
	selectTab(1)
	root.Visible = true
end

local function buildTabs()
	table.insert(tabs, { label = "Color", kind = "color" })
	for _, slot in Config.OutfitEditor.ClothingSlots do
		table.insert(tabs, { label = slot.Label, kind = "clothing", category = slot.Category, field = slot.Field })
	end
	for _, slot in Config.OutfitEditor.AccessorySlots do
		table.insert(
			tabs,
			{ label = slot.Label, kind = "accessory", category = slot.Category, accType = slot.Type.Value }
		)
	end

	for index, tab in tabs do
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(78, 28)
		button.BackgroundColor3 = TAB_BG
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 14
		button.Text = tab.label
		button.Parent = tabRow

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		tabButtons[index] = button

		button.Activated:Connect(function()
			selectTab(index)
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
	panel.Size = UDim2.fromOffset(700, 540)
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

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 32)
	title.BackgroundTransparency = 1
	title.Text = "Create your friend!"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = panel

	-- Left column: live preview over the Cancel / Save buttons.
	local left = Instance.new("Frame")
	left.Position = UDim2.fromOffset(0, 42)
	left.Size = UDim2.new(0.42, -7, 1, -42)
	left.BackgroundTransparency = 1
	left.Parent = panel

	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 1, -52)
	viewport.BackgroundColor3 = Color3.fromRGB(225, 230, 238)
	viewport.Parent = left
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 8)
	vpCorner.Parent = viewport
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.4, 7), Vector3.new(0, 0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	previewWorld = Instance.new("WorldModel")
	previewWorld.Parent = viewport

	-- Drag the preview left/right to spin the friend around so any side can be inspected.
	local dragging = false
	local lastX = 0
	viewport.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			lastX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			previewYaw -= (input.Position.X - lastX) * 0.01
			lastX = input.Position.X
			applyPreviewOrientation()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	local buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0, 1)
	buttonRow.Position = UDim2.fromScale(0, 1)
	buttonRow.Size = UDim2.new(1, 0, 0, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = left
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.Parent = buttonRow

	local function makeButton(text: string, color: Color3, onClick: () -> ())
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(120, 38)
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
	end
	makeButton("Cancel", Color3.fromRGB(90, 94, 104), close)
	makeButton("Save", Color3.fromRGB(60, 160, 90), onSave)

	-- Right column: tab strip over the item grid.
	local right = Instance.new("Frame")
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, 0, 0, 42)
	right.Size = UDim2.new(0.58, -7, 1, -42)
	right.BackgroundTransparency = 1
	right.Parent = panel

	tabRow = Instance.new("ScrollingFrame")
	tabRow.Size = UDim2.new(1, 0, 0, 30)
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.ScrollBarThickness = 4
	tabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabRow.CanvasSize = UDim2.new()
	tabRow.Parent = right
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(0, 40)
	grid.Size = UDim2.new(1, 0, 1, -40)
	grid.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = right
	local gridCorner = Instance.new("UICorner")
	gridCorner.CornerRadius = UDim.new(0, 8)
	gridCorner.Parent = grid
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(80, 80)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 8)
	gridPad.PaddingBottom = UDim.new(0, 8)
	gridPad.Parent = grid

	buildTabs()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function NpcEditorController:Start()
	openNpcEditor.OnClientEvent:Connect(onOpen)
end

return NpcEditorController
