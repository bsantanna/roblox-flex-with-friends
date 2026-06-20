--!strict
-- PhoneMenuController: the cellphone HUD. A 📱 launcher button (bottom-right) summons a GTA-style
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

local AssetIds = require(ReplicatedStorage.Shared.SceneryAssetIds) :: { [string]: number }

local PhoneMenuController = {}

local player = Players.LocalPlayer

local PHONE = Config.UI.Phone
local SCREEN_TEAL = Color3.fromRGB(134, 226, 231)
local SCREEN_TEXT = Color3.fromRGB(28, 30, 46)
local NAV_GLYPHS = { Close = "✖", Left = "◀", Ok = "OK", Right = "▶" }

local launcher: TextButton
local phone: ImageLabel
local screenFrame: Frame
local emojiLabel: TextLabel
local titleLabel: TextLabel
local modal: Frame?
local gui: ScreenGui
local followerLabel: TextLabel?

local index = 1
local mode: "carousel" | "social" = "carousel"
local hasArt = false

local function renderCarousel()
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
	setMode("carousel")
end

local function close()
	phone.Visible = false
	launcher.Visible = true
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
	fl.Size = UDim2.fromScale(1, 0.12)
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
	flSub.Size = UDim2.fromScale(1, 0.06)
	flSub.BackgroundTransparency = 1
	flSub.Text = "Followers"
	flSub.TextScaled = true
	flSub.TextColor3 = Color3.fromRGB(255, 255, 255)
	flSub.TextTransparency = 0.3
	flSub.Font = Enum.Font.Gotham
	flSub.Parent = m

	-- Trophies grid: 3 columns x 3 rows of empty cells.
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "TrophiesGrid"
	gridFrame.LayoutOrder = 3
	gridFrame.Size = UDim2.fromScale(0.85, 0.52)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = m

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.CellSize = UDim2.fromOffset(52, 52)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.Parent = gridFrame

	-- 9 empty trophy slots.
	for _ = 1, 9 do
		local cell = Instance.new("Frame")
		cell.Name = "TrophySlot"
		cell.Size = UDim2.fromOffset(52, 52)
		cell.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
		cell.BackgroundTransparency = 0.3
		cell.BorderSizePixel = 0
		cell.Parent = gridFrame
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0, 6)
		cellCorner.Parent = cell
	end

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
	renderCarousel()
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

	-- Launcher: the 📱 button that summons the phone.
	launcher = Instance.new("TextButton")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(1, 1)
	launcher.Position = UDim2.new(1, -18, 1, -18)
	launcher.Size = UDim2.fromOffset(64, 64)
	launcher.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	launcher.BackgroundTransparency = 0.2
	launcher.Text = "📲"
	launcher.TextScaled = true
	launcher.Font = Enum.Font.GothamBold
	launcher.Parent = gui
	local launcherCorner = Instance.new("UICorner")
	launcherCorner.CornerRadius = UDim.new(0, 16)
	launcherCorner.Parent = launcher

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
