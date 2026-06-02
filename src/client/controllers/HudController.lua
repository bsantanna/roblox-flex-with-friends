--!strict
-- HudController: shows the live follower count. Seeds from leaderstats.Followers (race-free,
-- replicated) and updates on the FollowerChanged remote fired by FollowerService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local HudController = {}

local label: TextLabel

local function render(count: number)
	label.Text = `Followers: {count}`
end

function HudController:Init()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false

	label = Instance.new("TextLabel")
	label.Name = "Followers"
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(16, 16)
	label.Size = UDim2.fromOffset(240, 44)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "Followers: 0"
	label.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController:Start()
	local player = Players.LocalPlayer

	-- Seed from the replicated leaderstat (present once FollowerService builds it).
	local leaderstats = player:WaitForChild("leaderstats")
	local followers = leaderstats:WaitForChild("Followers") :: IntValue
	render(followers.Value)

	Net.Event("FollowerChanged").OnClientEvent:Connect(function(count: number)
		render(count)
	end)
end

return HudController
