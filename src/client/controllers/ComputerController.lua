--!strict
-- ComputerController: the Home computer. Pressing it opens a placeholder panel; the real feed /
-- news / email role is Phase 4 (idea doc). For now it just shows "coming soon" so it responds.

local Players = game:GetService("Players")

local InteractionController = require(script.Parent.InteractionController)

local ComputerController = {}

local player = Players.LocalPlayer

local panel: Frame

function ComputerController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Computer"
	gui.ResetOnSpawn = false

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(280, 180)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	panel.Visible = false
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Text = "Computer"
	title.Parent = panel

	local message = Instance.new("TextLabel")
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.45)
	message.Size = UDim2.fromOffset(248, 48)
	message.BackgroundTransparency = 1
	message.TextColor3 = Color3.fromRGB(210, 210, 220)
	message.Font = Enum.Font.Gotham
	message.TextScaled = true
	message.Text = "Feed & News — coming soon"
	message.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.fromOffset(248, 40)
	close.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.Text = "Close"
	close.Parent = panel

	close.Activated:Connect(function()
		panel.Visible = false
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function ComputerController:Start()
	InteractionController:OnInteract("Computer", function()
		panel.Visible = true
	end)
end

return ComputerController
