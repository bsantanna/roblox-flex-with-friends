--!strict
-- PhoneMenuController: the cellphone HUD. A 📱 launcher button (top-right) summons a GTA-style
-- phone — the uploaded Phone01 art with a carousel of functionalities on its screen. The art's
-- close / left / ok / right buttons are baked into the image, so invisible TextButtons are overlaid
-- on them (rects from Config.UI.Phone.Zones, measured from the art). Selecting a carousel item runs
-- its action: Take Photo, Invite Friends, and Social Media. Navigation: the on-screen buttons, or
-- ←/→ to cycle, Enter to select, Esc to close. Before Phone01 is uploaded the art is absent, so
-- the shell falls back to a plain frame with visible button glyphs — the carousel still works for
-- testing.
--
-- The Social Modal (opened via "Social" item) features a tabbed trophy gallery:
-- "City" tab shows trophies from town NPCs; "Airport" tab shows airport NPC trophies.
-- Each tab has a large 2-card carousel with arrow navigation and dot indicators;
--
-- Trophy zones are mapped in TROPHY_ZONE (mirrors Config.Npc zone assignments).

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

-- Trophy carousel state: current page index per tab.
local currentIndex_City: number = 1
local currentIndex_Airport: number = 1

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
	-- Airport-terminal NPCs.
	["athlete_speed"] = { Id = "athlete_speed", Name = "Speed", Emoji = "\u{1F3C3}" },
	["chef_secret_sauce"] = { Id = "chef_secret_sauce", Name = "Secret Sauce", Emoji = "\u{1F9C5}" },
	["singer_confidence"] = { Id = "singer_confidence", Name = "Confidence", Emoji = "\u{1F3A4}" },
	["violinist_refinement"] = { Id = "violinist_refinement", Name = "Refinement", Emoji = "\u{1F3BB}" },
	["dj_grooves"] = { Id = "dj_grooves", Name = "Grooves", Emoji = "\u{1F3A7}" },
	["ballerina_swiftness"] = { Id = "ballerina_swiftness", Name = "Swiftness", Emoji = "\u{1FA70}" },
	["pianist_talent"] = { Id = "pianist_talent", Name = "Talent", Emoji = "\u{1F3B9}" },
	["archeologist_relic"] = { Id = "archeologist_relic", Name = "Relic", Emoji = "\u{1F9B4}" },
	-- Quest 002 completion trophy.
	["pilot_delivery"] = { Id = "pilot_delivery", Name = "Delivery Hero", Emoji = "\u{2708}" },
}

-- Trophy zone mapping: trophyId -> zone name. Each trophy belongs to exactly one zone. Town NPCs
-- (Config.Npc Zone = "Home"/"Farm") map to "City"; the airport-terminal NPCs (Zone = "Airport") map
-- to "Airport", populating that tab.
local TROPHY_ZONE: { [string]: string } = {
	["personal_trainer_strength"] = "City",
	["farmer_farmhand"] = "City",
	["cowboy_roundup"] = "City",
	["postman_swiftpost"] = "City",
	["sage_quickdraw"] = "City",
	["taxi_driver_mobility"] = "City",
	["policeman_protection"] = "City",
	["firefighter_bravery"] = "City",
	["gardener_caretaking"] = "City",
	["home_builder_nicehome"] = "City",
	["nurse_healthy"] = "City",
	["truck_driver_heavyduty"] = "City",
	["athlete_speed"] = "Airport",
	["chef_secret_sauce"] = "Airport",
	["singer_confidence"] = "Airport",
	["violinist_refinement"] = "Airport",
	["dj_grooves"] = "Airport",
	["ballerina_swiftness"] = "Airport",
	["pianist_talent"] = "Airport",
	["archeologist_relic"] = "Airport",
	["pilot_delivery"] = "Airport",
}

-- Tab bar labels and colors. Config-driven in the future.
-- Text color always white for readability; active state signaled by BG + border.
local TABS: { [string]: { label: string, activeColor: Color3, inactiveColor: Color3 } } = {
	City = { label = "City", activeColor = Color3.fromRGB(80, 180, 80), inactiveColor = Color3.fromRGB(60, 62, 75) },
	Airport = {
		label = "Airport",
		activeColor = Color3.fromRGB(80, 160, 200),
		inactiveColor = Color3.fromRGB(60, 62, 75),
	},
}

local index = 1
local mode: "carousel" | "social" = "carousel"
local hasArt = false

-- Pilot-quest phase, mirrored from the QuestState sync. While a quest is active the Call a Cab item is
-- revealed for everyone (and the ride is free, waived server-side) so the player can travel to the city
-- to run the errand and fly back themselves -- there's no dedicated quest-travel screen.
local questPhase = "idle"

-- A quest is "active" between accepting and finishing.
local function questActive(): boolean
	return questPhase == "collecting" or questPhase == "returning"
end

-- Whether a carousel item is currently hidden: Cab is gated behind the Mobility trophy, but always
-- available while a quest is active so the player can travel to run the errand.
local function isItemHidden(action: string): boolean
	if action == "Cab" then
		return not (earnedTrophies["taxi_driver_mobility"] or questActive())
	end
	return false
end

local function renderCarousel(step: number?)
	-- Skip hidden items, stepping in the direction of travel (default forward) so left/right navigation
	-- past a hidden item stays symmetric.
	local dir = step or 1
	local start = index
	while isItemHidden(PHONE.Items[index].action) do
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
	local carousel = m == "carousel"
	emojiLabel.Visible = carousel
	titleLabel.Visible = carousel
	if carousel then
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

-- Build a single large trophy card.
local function buildTrophyCard(parent: Frame, trophyId: string)
	local def = TROPHY_DEFS[trophyId]
	if not def then
		return
	end

	-- Card frame: large rounded card with gold tint.
	local card = Instance.new("Frame")
	card.Name = "TrophyCard_" .. trophyId
	card.Size = UDim2.fromOffset(220, 180)
	card.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	card.BackgroundTransparency = 0.75
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = card

	-- Subtle gold border.
	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(255, 215, 0)
	border.Thickness = 2
	border.Transparency = 0.5
	border.Parent = card

	-- Emoji: large, centered in the upper portion of the card (TextScaled fills the box).
	local emoji = Instance.new("TextLabel")
	emoji.Name = "TrophyEmoji"
	emoji.Size = UDim2.fromOffset(110, 110)
	emoji.AnchorPoint = Vector2.new(0.5, 0.5)
	emoji.Position = UDim2.fromScale(0.5, 0.38)
	emoji.BackgroundTransparency = 1
	emoji.Text = def.Emoji
	emoji.TextScaled = true
	emoji.TextColor3 = Color3.fromRGB(255, 255, 255)
	emoji.Font = Enum.Font.GothamBold
	emoji.TextXAlignment = Enum.TextXAlignment.Center
	emoji.TextYAlignment = Enum.TextYAlignment.Center
	emoji.Parent = card

	-- Trophy name: centered below the emoji.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TrophyName"
	nameLabel.Size = UDim2.fromOffset(200, 36)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.fromScale(0.5, 0.7)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.TextSize = 24
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextWrapped = true
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Parent = card

	return card
end

-- Render earned trophies in the grid (2 per page) and update dots/arrows.
local function renderCarousels(gridFrame: Frame, dotsFrame: Frame, container: Frame, zone: string)
	-- Clear existing trophies.
	for _, child in gridFrame:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("UICorner") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	-- Collect earned trophies for this zone.
	local trophyIds: { [number]: string } = {}
	for trophyId, _ in earnedTrophies do
		if TROPHY_ZONE[trophyId] == zone then
			table.insert(trophyIds, trophyId)
		end
	end

	local totalCards = #trophyIds
	local totalPages = math.max(math.ceil(totalCards / 2), 1)
	local currentPage = zone == "City" and currentIndex_City or currentIndex_Airport

	-- Clamp to valid range.
	if currentPage < 1 then
		currentPage = 1
	end
	if currentPage > totalPages then
		currentPage = totalPages
	end

	-- Index range for the current page (up to 2 cards). endIdx is an index, not a count -- the
	-- previous code used the count as the loop bound, so every page past the first rendered nothing.
	local startIdx = (currentPage - 1) * 2 + 1
	local endIdx = math.min(startIdx + 1, totalCards)
	local visibleCount = endIdx - startIdx + 1

	-- Adjust grid size based on how many cards this page shows.
	if visibleCount <= 1 then
		gridFrame.Size = UDim2.fromOffset(240, 200)
	else
		gridFrame.Size = UDim2.fromOffset(500, 200)
	end

	if totalCards == 0 then
		-- Empty zone: show a placeholder instead of a bare frame.
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyState"
		empty.Text = "No trophies yet"
		empty.TextColor3 = Color3.fromRGB(160, 162, 176)
		empty.TextSize = 20
		empty.Font = Enum.Font.Gotham
		empty.BackgroundTransparency = 1
		empty.Parent = gridFrame
	end

	-- Only show the current page's cards.
	for i = startIdx, endIdx do
		if trophyIds[i] then
			buildTrophyCard(gridFrame, trophyIds[i])
		end
	end

	-- Update dot indicators.
	for _, child in dotsFrame:GetChildren() do
		child:Destroy()
	end

	for i = 1, totalPages do
		local dot = Instance.new("TextLabel")
		dot.Name = "Dot_" .. i
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundTransparency = 1
		dot.Text = (i == currentPage) and "\u{25CF}" or "\u{25CB}"
		dot.TextColor3 = (i == currentPage) and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(120, 122, 136)
		dot.TextSize = 14
		dot.Font = Enum.Font.GothamBold
		dot.TextXAlignment = Enum.TextXAlignment.Center
		dot.TextYAlignment = Enum.TextYAlignment.Center
		dot.Parent = dotsFrame
	end

	-- Arrow visibility.
	local leftArrow = container:FindFirstChild("CarouselLeft", true) :: TextButton?
	local rightArrow = container:FindFirstChild("CarouselRight", true) :: TextButton?
	if leftArrow then
		leftArrow.Visible = currentPage > 1
	end
	if rightArrow then
		rightArrow.Visible = currentPage < totalPages
	end
end

-- Re-render a zone's carousel by walking modal -> carousel -> container -> grid/dots. Centralizing
-- this walk keeps every caller (navigation, tab switch, live trophy award) in sync and is the single
-- place the TrophyContainer hierarchy is traversed. The grid is nested under TrophyRow, so the lookup
-- is recursive; the dots sit directly under the container.
local function rerenderZone(zone: string)
	if modal == nil then
		return
	end
	local carousel =
		modal:FindFirstChild(zone == "City" and "TrophyCarousel_City" or "TrophyCarousel_Airport") :: Frame?
	if not carousel then
		return
	end
	local container = carousel:FindFirstChild("TrophyContainer") :: Frame?
	if not container then
		return
	end
	local grid = container:FindFirstChild("TrophyGrid", true) :: Frame?
	local dots = container:FindFirstChild("TrophyDots") :: Frame?
	if grid and dots then
		renderCarousels(grid, dots, container, zone)
	end
end

-- Navigate the carousel (step direction ±1 page = ±2 trophies).
local function navigateCarousel(zone: string, dir: number)
	local indexRef = zone == "City" and currentIndex_City or currentIndex_Airport
	local trophyIds: { [number]: string } = {}
	for trophyId, _ in earnedTrophies do
		if TROPHY_ZONE[trophyId] == zone then
			table.insert(trophyIds, trophyId)
		end
	end
	local totalPages = math.max(math.ceil(math.max(#trophyIds, 0) / 2), 1)
	local newIndex = indexRef + dir
	if newIndex >= 1 and newIndex <= totalPages then
		if zone == "City" then
			currentIndex_City = newIndex
		else
			currentIndex_Airport = newIndex
		end
		rerenderZone(zone)
	end
end

-- Build the trophy carousel UI: a centered row of ◀ grid ▶, with page dots below.
local function buildCarousels(carouselFrame: Frame, zone: string)
	-- Container: vertical stack of the arrow/card row and the dots beneath it.
	local container = Instance.new("Frame")
	container.Name = "TrophyContainer"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = carouselFrame

	local vLayout = Instance.new("UIListLayout")
	vLayout.FillDirection = Enum.FillDirection.Vertical
	vLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	vLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	vLayout.SortOrder = Enum.SortOrder.LayoutOrder
	vLayout.Padding = UDim.new(0, 12)
	vLayout.Parent = container

	-- Row: ◀ arrow | grid | ▶ arrow, laid horizontally and centered. Width auto-fits the grid so the
	-- arrows always flank it as the page size toggles between 1 and 2 cards.
	local row = Instance.new("Frame")
	row.Name = "TrophyRow"
	row.Size = UDim2.fromOffset(0, 200)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.LayoutOrder = 1
	row.Parent = container

	local hLayout = Instance.new("UIListLayout")
	hLayout.FillDirection = Enum.FillDirection.Horizontal
	hLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hLayout.Padding = UDim.new(0, 12)
	hLayout.Parent = row

	-- Left arrow.
	local leftArrow = Instance.new("TextButton")
	leftArrow.Name = "CarouselLeft"
	leftArrow.Size = UDim2.fromOffset(40, 200)
	leftArrow.BackgroundColor3 = Color3.fromRGB(50, 52, 68)
	leftArrow.BackgroundTransparency = 0.5
	leftArrow.Text = "\u{25C0}"
	leftArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	leftArrow.TextScaled = true
	leftArrow.Font = Enum.Font.GothamBold
	leftArrow.BorderSizePixel = 0
	leftArrow.LayoutOrder = 1
	leftArrow.Parent = row
	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = leftArrow
	leftArrow.Activated:Connect(function()
		navigateCarousel(zone, -1)
	end)

	-- Trophy grid: up to 2 cards per page.
	local trophyGrid = Instance.new("Frame")
	trophyGrid.Name = "TrophyGrid"
	trophyGrid.Size = UDim2.fromOffset(500, 200)
	trophyGrid.BackgroundTransparency = 1
	trophyGrid.LayoutOrder = 2
	trophyGrid.Parent = row

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	gridLayout.CellSize = UDim2.fromOffset(220, 180)
	gridLayout.CellPadding = UDim2.fromOffset(20, 10)
	gridLayout.Parent = trophyGrid

	-- Right arrow.
	local rightArrow = Instance.new("TextButton")
	rightArrow.Name = "CarouselRight"
	rightArrow.Size = UDim2.fromOffset(40, 200)
	rightArrow.BackgroundColor3 = Color3.fromRGB(50, 52, 68)
	rightArrow.BackgroundTransparency = 0.5
	rightArrow.Text = "\u{25B6}"
	rightArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	rightArrow.TextScaled = true
	rightArrow.Font = Enum.Font.GothamBold
	rightArrow.BorderSizePixel = 0
	rightArrow.LayoutOrder = 3
	rightArrow.Parent = row
	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 8)
	rightCorner.Parent = rightArrow
	rightArrow.Activated:Connect(function()
		navigateCarousel(zone, 1)
	end)

	-- Dots indicator, centered below the row. Auto-sizes so all page dots fit.
	local dotsFrame = Instance.new("Frame")
	dotsFrame.Name = "TrophyDots"
	dotsFrame.Size = UDim2.fromOffset(0, 20)
	dotsFrame.AutomaticSize = Enum.AutomaticSize.X
	dotsFrame.BackgroundTransparency = 1
	dotsFrame.LayoutOrder = 2
	dotsFrame.Parent = container

	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dotsLayout.Padding = UDim.new(0, 4)
	dotsLayout.Parent = dotsFrame

	-- Render initial state.
	renderCarousels(trophyGrid, dotsFrame, container, zone)
end

local function onTrophyEarned(trophies: { [string]: true })
	earnedTrophies = trophies

	-- If the social modal is open, refresh both zones (each rerenderZone no-ops if modal is nil; only
	-- the visible carousel is shown, so refreshing the hidden one is harmless and keeps it in sync).
	rerenderZone("City")
	rerenderZone("Airport")

	-- Re-render the carousel so a newly earned Mobility trophy reveals "Call a Cab" live.
	if mode == "carousel" and phone.Visible then
		renderCarousel()
	end
end

local function updateFollowerLabel(followerCount: number)
	if followerLabel ~= nil then
		followerLabel.Text = tostring(followerCount)
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
	m.Size = UDim2.fromScale(0.9, 0.65)
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

	-- Vertical list layout for followers, tab bar, grid, close button.
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 12)
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
	fl.Size = UDim2.fromOffset(160, 24)
	fl.BackgroundTransparency = 1
	fl.Text = `❤ {followersValue}`
	fl.TextScaled = true
	fl.TextColor3 = Color3.fromRGB(255, 255, 255)
	fl.Font = Enum.Font.GothamBold
	fl.Parent = m
	followerLabel = fl

	-- Trophy carousel for City (visible by default).
	local cityCarousel = Instance.new("Frame")
	cityCarousel.Name = "TrophyCarousel_City"
	cityCarousel.LayoutOrder = 2
	cityCarousel.Size = UDim2.fromScale(0.95, 0.55)
	cityCarousel.BackgroundTransparency = 1
	cityCarousel.Visible = true
	cityCarousel.Parent = m

	buildCarousels(cityCarousel, "City")

	-- Trophy carousel for Airport (hidden initially).
	local airportCarousel = Instance.new("Frame")
	airportCarousel.Name = "TrophyCarousel_Airport"
	airportCarousel.LayoutOrder = 2
	airportCarousel.Size = UDim2.fromScale(0.95, 0.55)
	airportCarousel.BackgroundTransparency = 1
	airportCarousel.Visible = false
	airportCarousel.Parent = m

	buildCarousels(airportCarousel, "Airport")

	-- Tab bar: horizontal button row with City/Airport tabs.
	-- Placed after carousels so switchTab closure can reference them.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TrophyTabBar"
	tabBar.LayoutOrder = 3
	tabBar.Size = UDim2.fromOffset(280, 34)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = m

	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
	tabBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabBarLayout.Padding = UDim.new(0, 8)
	tabBarLayout.Parent = tabBar

	-- City tab button.
	local cityTab = Instance.new("TextButton")
	cityTab.Name = "Tab_City"
	cityTab.Size = UDim2.fromScale(0.5, 1)
	cityTab.BackgroundColor3 = TABS.City.activeColor
	cityTab.Text = TABS.City.label
	cityTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	cityTab.Font = Enum.Font.GothamBold
	cityTab.TextScaled = true
	cityTab.BorderSizePixel = 0
	cityTab.LayoutOrder = 1
	cityTab.Parent = tabBar
	local cityTabCorner = Instance.new("UICorner")
	cityTabCorner.CornerRadius = UDim.new(0, 6)
	cityTabCorner.Parent = cityTab
	local cityTabStroke = Instance.new("UIStroke")
	cityTabStroke.Color = TABS.City.activeColor
	cityTabStroke.Thickness = 1
	cityTabStroke.Parent = cityTab

	-- Airport tab button.
	local airportTab = Instance.new("TextButton")
	airportTab.Name = "Tab_Airport"
	airportTab.Size = UDim2.fromScale(0.5, 1)
	airportTab.BackgroundColor3 = TABS.Airport.inactiveColor
	airportTab.Text = TABS.Airport.label
	airportTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	airportTab.Font = Enum.Font.Gotham
	airportTab.TextScaled = true
	airportTab.BorderSizePixel = 0
	airportTab.LayoutOrder = 2
	airportTab.Parent = tabBar
	local airportTabCorner = Instance.new("UICorner")
	airportTabCorner.CornerRadius = UDim.new(0, 6)
	airportTabCorner.Parent = airportTab

	-- Active tab is local to each modal: the modal is always rebuilt with City visible/active, so a
	-- module-level value would survive a close/reopen and desync from the rebuilt UI — making a tab
	-- unresponsive (switchTab early-returns when the clicked tab already equals activeTab).
	local activeTab = "City"

	-- Tab switch callback (captures cityCarousel/airportCarousel by closure).
	local function switchTab(newTab: string)
		if newTab == activeTab then
			return
		end
		activeTab = newTab

		-- Update visual style.
		if newTab == "City" then
			cityTab.BackgroundColor3 = TABS.City.activeColor
			cityTab.TextColor3 = Color3.fromRGB(255, 255, 255)
			cityTab.Font = Enum.Font.GothamBold
			cityTabStroke.Color = TABS.City.activeColor
			airportTab.BackgroundColor3 = TABS.Airport.inactiveColor
			airportTab.TextColor3 = Color3.fromRGB(255, 255, 255)
			airportTab.Font = Enum.Font.Gotham
		else
			airportTab.BackgroundColor3 = TABS.Airport.activeColor
			airportTab.TextColor3 = Color3.fromRGB(255, 255, 255)
			airportTab.Font = Enum.Font.GothamBold
			cityTab.BackgroundColor3 = TABS.City.inactiveColor
			cityTab.TextColor3 = Color3.fromRGB(255, 255, 255)
			cityTab.Font = Enum.Font.Gotham
		end

		-- Swap carousel visibility and reset index.
		cityCarousel.Visible = newTab == "City"
		airportCarousel.Visible = newTab == "Airport"
		if newTab == "City" then
			currentIndex_City = 1
		else
			currentIndex_Airport = 1
		end
		-- Re-render the now-visible carousel.
		rerenderZone(newTab)
	end

	cityTab.Activated:Connect(function()
		switchTab("City")
	end)

	airportTab.Activated:Connect(function()
		switchTab("Airport")
	end)

	-- Carousels are rendered inside buildCarousels().
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

-- A modal view is a leaf: any nav (left/right/ok) backs out to the carousel; only close exits.
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
		TravelController:OpenCabConfirm()
	end
end

-- Mirror the quest phase so the carousel reveals/hides Call a Cab as the quest activates/finishes.
local function onQuestState(_questId: string, phase: string)
	questPhase = phase
	if mode == "carousel" and phone.Visible then
		renderCarousel()
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

	-- Pilot quest: mirror the phase so Call a Cab is revealed (and free) while a quest is active.
	Net.Event("QuestState").OnClientEvent:Connect(onQuestState)

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
