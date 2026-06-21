--!strict
-- PhoneMenuController: the cellphone HUD. A 📱 launcher button (top-right) summons a GTA-style
-- phone — the uploaded Phone01 art with a carousel of functionalities on its screen. The art's
-- close / left / ok / right buttons are baked into the image, so invisible TextButtons are overlaid
-- on them (rects from Config.UI.Phone.Zones, measured from the art). Selecting a carousel item runs
-- its action: Take Photo, Invite Friends, and Social Media. Navigation: the on-screen buttons, or
-- ←/→ to cycle, Enter to select, Esc to close. Before Phone01 is uploaded the art is absent, so
-- the shell falls back to a plain frame with visible button glyphs — the carousel still works for
-- testing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PhotoController = require(script.Parent.PhotoController)
local FriendController = require(script.Parent.FriendController)
local TravelController = require(script.Parent.TravelController)

local AssetIds = require(ReplicatedStorage.Shared.SceneryAssetIds) :: { [string]: number }

local PhoneMenuController = {}

local player = Players.LocalPlayer

local PHONE = Config.UI.Phone
local SCREEN_TEAL = Color3.fromRGB(134, 226, 231)
local SCREEN_TEXT = Color3.fromRGB(28, 30, 46)
local NAV_GLYPHS = { Close = "\u{2716}", Left = "\u{25C0}", Ok = "OK", Right = "\u{25B6}" }

local launcher: TextButton
local launcherLabel: TextLabel? = nil
local phone: ImageLabel
local screenFrame: Frame
local emojiLabel: TextLabel
local titleLabel: TextLabel
local modal: Frame?
local gui: ScreenGui
local followerLabel: TextLabel?

-- Trophy state: trophyId -> true. Populated on join and on TrophyEarned events.
local earnedTrophies: { [string]: true } = {}

-- Trophy definitions mirrored from server TrophyService.
local TROPHY_DEFS: { [string]: { Id: string, Name: string, Emoji: string } } = {
	["personal_trainer_strength"] = { Id = "personal_trainer_strength", Name = "Strength", Emoji = "\u{1F4AA}" },
	["farmer_farmhand"] = { Id = "farmer_farmhand", Name = "Fresh Milk", Emoji = "\u{1F95B}" },
	["cowboy_roundup"] = { Id = "cowboy_roundup", Name = "Cowboy", Emoji = "\u{1F404}" },
	["postman_swiftpost"] = { Id = "postman_swiftpost", Name = "Swift Post", Emoji = "\u{1F4E6}" },
	["sage_quickdraw"] = { Id = "sage_quickdraw", Name = "Fast Hands", Emoji = "\u{26A1}" },
	["taxi_driver_mobility"] = { Id = "taxi_driver_mobility", Name = "Mobility", Emoji = "\u{1F695}" },
	["policeman_protection"] = { Id = "policeman_protection", Name = "Protection", Emoji = "\u{1F46E}" },
	["firefighter_bravery"] = { Id = "firefighter_bravery", Name = "Bravery", Emoji = "\u{1F692}" },
	["gardener_caretaking"] = { Id = "gardener_caretaking", Name = "Caretaking", Emoji = "\u{1F331}" },
	["home_builder_nicehome"] = { Id = "home_builder_nicehome", Name = "Nice Home", Emoji = "\u{1F3E0}" },
	["nurse_healthy"] = { Id = "nurse_healthy", Name = "Healthy", Emoji = "\u{1FA7A}" },
	["truck_driver_heavyduty"] = { Id = "truck_driver_heavyduty", Name = "Heavy Duty", Emoji = "\u{1F69A}" },
}

local index = 1
local mode: "carousel" | "social" = "carousel"
local hasArt = false

local function renderCarousel(step: number?)
	-- Skip "Call a Cab" if the player hasn't earned the Mobility trophy. Step in the direction
	-- of travel (default forward) so left/right navigation past the hidden item stays symmetric.
	local dir = step or 1
	local start = index
	while PHONE.Items[index].action == "Cab" and not earnedTrophies["taxi_driver_mobility"] do
		index = (index - 1 + dir) % #PHONE.Items + 1
		if index == start then
			break
		end
	end

	local item = PHONE.Items[index]
	emojiLabel.Text = item.emoji
	titleLabel.Text = item.label
end

local function setMode(m: "carousel" | "social")
	mode = m
	local social = m == "social"
	emojiLabel.Visible = not social
	titleLabel.Visible = not social
	if not social then
		renderCarousel()
	end
end

local function open()
	phone.Visible = true
	launcher.Visible = false
	assert(launcherLabel).Visible = false
	setMode("carousel")
end

local function close()
	phone.Visible = false
	launcher.Visible = true
	assert(launcherLabel).Visible = true
end

local function populateTrophies(gridFrame: Frame)
	-- Clear any existing cells.
	for _, child in gridFrame:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("UICorner") or child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local slotIndex = 1
	local maxSlots = 12

	-- Place each earned trophy in order.
	for trophyId, _ in earnedTrophies do
		if slotIndex > maxSlots then
			break
		end
		local def = TROPHY_DEFS[trophyId]
		if not def then
			continue
		end

		local cell = Instance.new("Frame")
		cell.Name = "TrophySlot"
		cell.Size = UDim2.fromOffset(180, 140)
		cell.BackgroundColor3 = Color3.fromRGB(40, 55, 30)
		cell.BackgroundTransparency = 0.25
		cell.BorderSizePixel = 0
		cell.Parent = gridFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = cell

		-- Emoji label (large, centered, ~65% height from top).
		local emoji = Instance.new("TextLabel")
		emoji.Name = "TrophyEmoji"
		emoji.Size = UDim2.fromScale(1, 0.65)
		emoji.Position = UDim2.fromOffset(0, 2)
		emoji.BackgroundTransparency = 1
		emoji.Text = def.Emoji
		emoji.TextSize = 120
		emoji.TextColor3 = Color3.fromRGB(255, 255, 255)
		emoji.Font = Enum.Font.GothamBold
		emoji.TextXAlignment = Enum.TextXAlignment.Center
		emoji.TextYAlignment = Enum.TextYAlignment.Center
		emoji.Parent = cell

		-- Name label below emoji (90% width, 25% height, positioned from top).
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "TrophyName"
		nameLabel.Size = UDim2.fromScale(0.9, 0.25)
		nameLabel.Position = UDim2.fromScale(0.05, 0.68)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = def.Name
		nameLabel.TextSize = 32
		nameLabel.TextColor3 = Color3.fromRGB(180, 220, 160)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.Parent = cell

		slotIndex += 1
	end

	-- Fill remaining slots with empty placeholders.
	for _ = slotIndex, maxSlots do
		local cell = Instance.new("Frame")
		cell.Name = "TrophySlot"
		cell.Size = UDim2.fromOffset(180, 140)
		cell.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
		cell.BackgroundTransparency = 0.3
		cell.BorderSizePixel = 0
		cell.Parent = gridFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = cell
	end
end

local function onTrophyEarned(trophies: { [string]: true })
	earnedTrophies = trophies

	-- If the social modal is open, re-populate the grid immediately.
	if modal ~= nil then
		local gridFrame = modal:FindFirstChild("TrophiesGrid") :: Frame?
		if gridFrame then
			populateTrophies(gridFrame)
		end
	end

	-- Re-render the carousel so a newly earned Mobility trophy reveals "Call a Cab" live.
	if mode == "carousel" and phone.Visible then
		renderCarousel()
	end
end

local function updateFollowerLabel(count: number)
	if followerLabel ~= nil then
		followerLabel.Text = `❤ {count}`
	end
end

local function showSocialModal()
	if modal ~= nil then
		modal:Destroy()
		modal = nil
	end
	followerLabel = nil

	local m = Instance.new("Frame")
	m.Name = "SocialModal"
	m.Size = UDim2.fromScale(0.9, 0.85)
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = UDim2.fromScale(0.5, 0.5)
	m.BackgroundColor3 = Color3.fromRGB(36, 38, 52)
	m.BackgroundTransparency = 0.15
	m.BorderSizePixel = 0
	m.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = m

	-- Padding so content doesn't touch the modal edge.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = m

	-- Vertical list layout for followers, trophies, close button.
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 16)
	listLayout.Parent = m

	-- Read current follower count from leaderstat.
	local followersValue = 0
	local ok, leaderstats = pcall(function()
		return player:FindFirstChild("leaderstats")
	end)
	if ok and leaderstats then
		local followers = leaderstats:FindFirstChild("Followers")
		if followers then
			followersValue = followers.Value
		end
	end

	-- Followers header: ❤ count.
	local fl = Instance.new("TextLabel")
	fl.Name = "Followers"
	fl.LayoutOrder = 1
	fl.Size = UDim2.fromOffset(200, 30)
	fl.BackgroundTransparency = 1
	fl.Text = `❤ {followersValue}`
	fl.TextScaled = true
	fl.TextColor3 = Color3.fromRGB(255, 255, 255)
	fl.Font = Enum.Font.GothamBold
	fl.Parent = m
	followerLabel = fl

	-- "Followers" subtitle label.
	local flSub = Instance.new("TextLabel")
	flSub.Name = "FollowersSub"
	flSub.LayoutOrder = 2
	flSub.Size = UDim2.fromOffset(200, 20)
	flSub.BackgroundTransparency = 1
	flSub.Text = "Followers"
	flSub.TextScaled = true
	flSub.TextColor3 = Color3.fromRGB(255, 255, 255)
	flSub.TextTransparency = 0.3
	flSub.Font = Enum.Font.Gotham
	flSub.Parent = m

	-- Trophies grid: 3 columns x 4 rows of empty cells.
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "TrophiesGrid"
	gridFrame.LayoutOrder = 3
	gridFrame.Size = UDim2.fromScale(0.85, 0.62)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = m

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.CellSize = UDim2.fromOffset(180, 140)
	gridLayout.CellPadding = UDim2.fromOffset(12, 12)
	gridLayout.Parent = gridFrame

	-- 12 empty trophy slots — will be overwritten by populateTrophies.
	for _ = 1, 12 do
		local cell = Instance.new("Frame")
		cell.Name = "TrophySlot"
		cell.Size = UDim2.fromOffset(180, 140)
		cell.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
		cell.BackgroundTransparency = 0.3
		cell.BorderSizePixel = 0
		cell.Parent = gridFrame
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0, 12)
		cellCorner.Parent = cell
	end

	populateTrophies(gridFrame)

	-- Bottom-centered Close button, matching DialogController's button style.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.LayoutOrder = 4
	closeBtn.Size = UDim2.fromOffset(140, 40)
	closeBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 72)
	closeBtn.Text = "Close"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextScaled = true
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = m

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = closeBtn

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingTop = UDim.new(0, 8)
	btnPadding.PaddingBottom = UDim.new(0, 8)
	btnPadding.PaddingLeft = UDim.new(0, 14)
	btnPadding.PaddingRight = UDim.new(0, 14)
	btnPadding.Parent = closeBtn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(90, 98, 116)
	btnStroke.Thickness = 1
	btnStroke.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		m:Destroy()
		modal = nil
		followerLabel = nil
		setMode("carousel")
	end)

	modal = m
	setMode("social")
end

local function closeModal()
	if modal ~= nil then
		modal:Destroy()
		modal = nil
	end
	setMode("carousel")
end

-- The social view is a leaf: any nav (left/right/ok) backs out to the carousel; only close exits.
local function cycle(delta: number)
	if mode == "social" then
		closeModal()
		return
	end
	index = (index - 1 + delta) % #PHONE.Items + 1
	renderCarousel(delta)
end

local function activate()
	if mode == "social" then
		closeModal()
		return
	end
	local action = PHONE.Items[index].action
	if action == "Photo" then
		close()
		PhotoController:Capture()
	elseif action == "Invite" then
		FriendController:PromptInvite()
	elseif action == "Social" then
		showSocialModal()
	elseif action == "Cab" then
		close()
		TravelController:OpenPicker()
	end
end

-- Invisible click zone over one of the art's baked-in buttons; carries a visible glyph only as the
-- no-art fallback.
local function makeZone(name: string, zone: { number }, onClick: () -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromScale(zone[1], zone[2])
	button.Size = UDim2.fromScale(zone[3], zone[4])
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = NAV_GLYPHS[name]
	button.TextScaled = true
	button.TextColor3 = SCREEN_TEXT
	button.TextTransparency = if hasArt then 1 else 0
	button.Font = Enum.Font.GothamBold
	button.Parent = phone
	button.Activated:Connect(onClick)
end

function PhoneMenuController:Init()
	local phoneAssetId = AssetIds[PHONE.Asset]
	hasArt = phoneAssetId ~= nil

	gui = Instance.new("ScreenGui")
	gui.Name = "Cellphone"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	-- Launcher: the 📱 button that summons the phone.
	launcher = Instance.new("TextButton")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(1, 0)
	launcher.Position = UDim2.new(1, -20, 0.02, 0)
	launcher.Size = UDim2.fromOffset(56, 56)
	launcher.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	launcher.BackgroundTransparency = 0.2
	launcher.Text = "📲"
	launcher.TextScaled = true
	launcher.Font = Enum.Font.GothamBold
	launcher.Parent = gui
	local launcherCorner = Instance.new("UICorner")
	launcherCorner.CornerRadius = UDim.new(0, 14)
	launcherCorner.Parent = launcher

	-- Label below the launcher icon.
	local lbl = Instance.new("TextLabel")
	lbl.Name = "LauncherLabel"
	lbl.Size = UDim2.fromOffset(56, 20)
	lbl.Position = UDim2.new(1, -75, 0.12, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "Phone"
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = gui
	launcherLabel = lbl

	-- The phone shell: the art, height-locked to the viewport with a fixed aspect ratio.
	phone = Instance.new("ImageLabel")
	phone.Name = "Phone"
	phone.AnchorPoint = Vector2.new(1, 1)
	phone.Position = UDim2.new(1, -14, 1, -14)
	phone.Size = UDim2.fromScale(0, PHONE.HeightScale)
	phone.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	phone.BackgroundTransparency = if hasArt then 1 else 0.05
	phone.Image = if hasArt then `rbxassetid://{phoneAssetId}` else ""
	phone.Visible = false
	phone.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = PHONE.AspectRatio
	aspect.DominantAxis = Enum.DominantAxis.Height
	-- ScaleWithParentSize (not the default FitWithinMaxSize): the height drives, the width follows
	-- the aspect. With FitWithinMaxSize the width-0 Size would be read as a max of 0 and collapse.
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.Parent = phone

	-- Screen content sits over the art's teal screen.
	screenFrame = Instance.new("Frame")
	screenFrame.Name = "Screen"
	screenFrame.Position = UDim2.fromScale(PHONE.Screen[1], PHONE.Screen[2])
	screenFrame.Size = UDim2.fromScale(PHONE.Screen[3], PHONE.Screen[4])
	screenFrame.BackgroundColor3 = SCREEN_TEAL
	screenFrame.BackgroundTransparency = if hasArt then 1 else 0
	screenFrame.Parent = phone

	emojiLabel = Instance.new("TextLabel")
	emojiLabel.Name = "Emoji"
	emojiLabel.Size = UDim2.fromScale(1, 0.62)
	emojiLabel.BackgroundTransparency = 1
	emojiLabel.Text = ""
	emojiLabel.TextScaled = true
	emojiLabel.Font = Enum.Font.GothamBold
	emojiLabel.Parent = screenFrame

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromScale(0, 0.62)
	titleLabel.Size = UDim2.fromScale(1, 0.34)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = ""
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = SCREEN_TEXT
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = screenFrame

	-- Invisible hit zones over the art's baked-in buttons.
	makeZone("Close", PHONE.Zones.Close, close)
	makeZone("Left", PHONE.Zones.Left, function()
		cycle(-1)
	end)
	makeZone("Ok", PHONE.Zones.Ok, activate)
	makeZone("Right", PHONE.Zones.Right, function()
		cycle(1)
	end)

	launcher.Activated:Connect(open)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function PhoneMenuController:Start()
	-- Followers: seed from the replicated leaderstat, then track FollowerChanged.
	local leaderstats = player:WaitForChild("leaderstats")
	local followers = leaderstats:WaitForChild("Followers") :: IntValue
	updateFollowerLabel(followers.Value)
	Net.Event("FollowerChanged").OnClientEvent:Connect(updateFollowerLabel)

	-- Trophies: listen for initial seed and new awards from the server.
	Net.Event("TrophyEarned").OnClientEvent:Connect(onTrophyEarned)

	-- Keyboard shortcuts while the phone is open.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not phone.Visible or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Left then
			cycle(-1)
		elseif key == Enum.KeyCode.Right then
			cycle(1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			activate()
		elseif key == Enum.KeyCode.Escape then
			if modal ~= nil then
				closeModal()
			else
				close()
			end
		end
	end)
end

return PhoneMenuController
