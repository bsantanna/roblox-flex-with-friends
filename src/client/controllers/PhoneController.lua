--!strict
-- PhoneController: the Home phone. Pressing it opens a small menu; "Call a Cab" hands off to
-- TravelController's destination picker (the cab is no longer a standalone world prompt). Room to
-- add Order Food / Services later (idea doc).

local Players = game:GetService("Players")

local InteractionController = require(script.Parent.InteractionController)
local TravelController = require(script.Parent.TravelController)

local PhoneController = {}

local player = Players.LocalPlayer

local menuFrame: Frame

function PhoneController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Phone"
	gui.ResetOnSpawn = false

	menuFrame = Instance.new("Frame")
	menuFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	menuFrame.Position = UDim2.fromScale(0.5, 0.5)
	menuFrame.Size = UDim2.fromOffset(260, 200)
	menuFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	menuFrame.Visible = false
	menuFrame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = "Phone"
	title.Parent = menuFrame

	local callCab = Instance.new("TextButton")
	callCab.AnchorPoint = Vector2.new(0.5, 0)
	callCab.Position = UDim2.new(0.5, 0, 0, 56)
	callCab.Size = UDim2.fromOffset(228, 44)
	callCab.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	callCab.TextColor3 = Color3.fromRGB(255, 255, 255)
	callCab.Font = Enum.Font.GothamBold
	callCab.TextScaled = true
	callCab.Text = "Call a Cab"
	callCab.Parent = menuFrame

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.fromOffset(228, 40)
	close.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.Text = "Close"
	close.Parent = menuFrame

	callCab.Activated:Connect(function()
		menuFrame.Visible = false
		TravelController:OpenPicker()
	end)
	close.Activated:Connect(function()
		menuFrame.Visible = false
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function PhoneController:Start()
	InteractionController:OnInteract("Phone", function()
		menuFrame.Visible = true
	end)
end

return PhoneController
