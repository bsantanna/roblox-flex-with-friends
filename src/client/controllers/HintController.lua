--!strict
-- HintController: the core-loop onboarding banner. A first-time player (0 lifetime photos) is guided
-- to open the phone and take their first photo -- the first follower reward -- with no external help.
-- The step + hint text come from the pure Logic/Tutorial state machine; this controller only feeds it
-- observed progress (the PhoneOpened client signal and the server-set PhotosTaken attribute) and
-- renders the result. Once the player takes a photo (PhotosTaken >= 1) the banner hides for good, so
-- returning players never see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tutorial = require(ReplicatedStorage.Shared.Logic.Tutorial)

local HintController = {}

local player = Players.LocalPlayer
local label: TextLabel

local function refresh()
	-- PhotosTaken is set by the server on profile load; until it arrives we can't tell a new player
	-- from a returning one, so keep the banner hidden to avoid flashing it at veterans.
	local photos = player:GetAttribute("PhotosTaken")
	if photos == nil then
		label.Visible = false
		return
	end

	local hint = Tutorial.hint(Tutorial.step({
		phoneOpened = player:GetAttribute("PhoneOpened") == true,
		photosTaken = tonumber(photos) or 0,
	}))

	if hint then
		label.Text = hint
		label.Visible = true
	else
		label.Visible = false
	end
end

function HintController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Onboarding"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.IgnoreGuiInset = true

	label = Instance.new("TextLabel")
	label.Name = "Hint"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -90)
	label.Size = UDim2.fromOffset(460, 46)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = label

	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

function HintController:Start()
	player:GetAttributeChangedSignal("PhotosTaken"):Connect(refresh)
	player:GetAttributeChangedSignal("PhoneOpened"):Connect(refresh)
	refresh()
end

return HintController
