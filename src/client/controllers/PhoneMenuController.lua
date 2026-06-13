--!strict
-- PhoneMenuController: the cellphone HUD. A 📱 launcher button (bottom-right) summons a GTA-style
-- phone — the uploaded Phone01 art with a carousel of functionalities on its screen. The art's
-- close / left / ok / right buttons are baked into the image, so invisible TextButtons are overlaid
-- on them (rects from Config.UI.Phone.Zones, measured from the art). Selecting a carousel item runs
-- its action: Take Photo and Call a Cab hand off to PhotoController / TravelController, Invite Friends
-- to FriendController, and Social Media opens an in-phone view of the live follower count plus a
-- placeholder feed (real feed is Phase 4). Followers used to live in HudController (now removed);
-- they show here only. Navigation: the on-screen buttons, or ←/→ to cycle, Enter to select, Esc to
-- close. Before Phone01 is uploaded the art is absent, so the shell falls back to a plain frame with
-- visible button glyphs — the carousel still works for testing.

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
local NAV_GLYPHS = { Close = "✖", Left = "◀", Ok = "OK", Right = "▶" }

local launcher: TextButton
local phone: ImageLabel
local emojiLabel: TextLabel
local titleLabel: TextLabel
local socialFrame: Frame
local followerLabel: TextLabel

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
	socialFrame.Visible = social
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

-- The social view is a leaf: any nav (left/right/ok) backs out to the carousel; only close exits.
local function cycle(delta: number)
	if mode == "social" then
		setMode("carousel")
		return
	end
	index = (index - 1 + delta) % #PHONE.Items + 1
	renderCarousel()
end

local function activate()
	if mode == "social" then
		setMode("carousel")
		return
	end
	local action = PHONE.Items[index].action
	if action == "Photo" then
		close()
		PhotoController:Capture()
	elseif action == "Invite" then
		FriendController:PromptInvite()
	elseif action == "Cab" then
		close()
		TravelController:OpenPicker()
	elseif action == "Social" then
		setMode("social")
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

	local gui = Instance.new("ScreenGui")
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
	launcher.Text = "📱"
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
	local screenFrame = Instance.new("Frame")
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

	-- Social Media view: live follower count + a placeholder feed (Phase 4 builds the real one).
	socialFrame = Instance.new("Frame")
	socialFrame.Name = "Social"
	socialFrame.Size = UDim2.fromScale(1, 1)
	socialFrame.BackgroundTransparency = 1
	socialFrame.Visible = false
	socialFrame.Parent = screenFrame
	local socialLayout = Instance.new("UIListLayout")
	socialLayout.FillDirection = Enum.FillDirection.Vertical
	socialLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	socialLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	-- Order by LayoutOrder (count, feed, caption); the default SortOrder.Name would sort alphabetically.
	socialLayout.SortOrder = Enum.SortOrder.LayoutOrder
	socialLayout.Padding = UDim.new(0.04, 0)
	socialLayout.Parent = socialFrame

	followerLabel = Instance.new("TextLabel")
	followerLabel.Name = "Followers"
	followerLabel.LayoutOrder = 1
	followerLabel.Size = UDim2.fromScale(0.9, 0.34)
	followerLabel.BackgroundTransparency = 1
	followerLabel.Text = "❤ 0"
	followerLabel.TextScaled = true
	followerLabel.TextColor3 = SCREEN_TEXT
	followerLabel.Font = Enum.Font.GothamBold
	followerLabel.Parent = socialFrame

	local feedRow = Instance.new("Frame")
	feedRow.Name = "FeedRow"
	feedRow.LayoutOrder = 2
	feedRow.Size = UDim2.fromScale(0.9, 0.3)
	feedRow.BackgroundTransparency = 1
	feedRow.Parent = socialFrame
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.FillDirection = Enum.FillDirection.Horizontal
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	feedLayout.Padding = UDim.new(0.06, 0)
	feedLayout.Parent = feedRow
	for i = 1, 2 do
		local cell = Instance.new("TextLabel")
		cell.Name = `Cell{i}`
		cell.Size = UDim2.fromScale(0.42, 1)
		cell.BackgroundColor3 = Color3.fromRGB(36, 38, 52)
		cell.Text = "▶"
		cell.TextScaled = true
		cell.TextColor3 = Color3.fromRGB(235, 235, 240)
		cell.Font = Enum.Font.GothamBold
		cell.Parent = feedRow
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0.12, 0)
		cellCorner.Parent = cell
	end

	local feedCaption = Instance.new("TextLabel")
	feedCaption.Name = "Caption"
	feedCaption.LayoutOrder = 3
	feedCaption.Size = UDim2.fromScale(0.95, 0.18)
	feedCaption.BackgroundTransparency = 1
	feedCaption.Text = "Feed — coming soon"
	feedCaption.TextScaled = true
	feedCaption.TextColor3 = SCREEN_TEXT
	feedCaption.Font = Enum.Font.Gotham
	feedCaption.Parent = socialFrame

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
	-- Followers: seed from the replicated leaderstat, then track the FollowerChanged remote (same
	-- source the removed HudController used).
	local leaderstats = player:WaitForChild("leaderstats")
	local followers = leaderstats:WaitForChild("Followers") :: IntValue
	local function renderFollowers(count: number)
		followerLabel.Text = `❤ {count}`
	end
	renderFollowers(followers.Value)
	Net.Event("FollowerChanged").OnClientEvent:Connect(renderFollowers)

	-- Keyboard shortcuts while the phone is open. Arrow keys also drive movement (they arrive with
	-- gameProcessed=true), so guard only on a focused TextBox — matching MinigameController.
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
			close()
		end
	end)
end

return PhoneMenuController
