--!strict
-- DevConsoleController: Studio-only cheat console. Typing the Config.DevConsole.Sequence on the
-- keyboard (the Konami code) toggles a small panel that force-sets the follower count via the
-- SetFollowers remote — which the server also only honors in Studio. Outside Studio this whole
-- controller is a no-op.
--
-- The same Konami sequence also toggles a debug panel with a "Grant All Trophies" button that
-- unlocks every trophy (and so the Cab phone option) via the GrantAllTrophies remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local KeySequence = require(ReplicatedStorage.Shared.Logic.KeySequence)
local Net = require(ReplicatedStorage.Shared.Net)

local DevConsoleController = {}

local player = Players.LocalPlayer

local setFollowers: RemoteEvent
local grantTrophies: RemoteEvent
local panel: Frame
local debugPanel: Frame

function DevConsoleController:Init()
	if not RunService:IsStudio() then
		return
	end

	setFollowers = Net.Event("SetFollowers")
	grantTrophies = Net.Event("GrantAllTrophies")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevConsole"
	gui.ResetOnSpawn = false

	-- Main panel: follower setter.
	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.06)
	panel.Size = UDim2.fromOffset(260, 110)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	panel.Visible = false
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 24)
	title.Position = UDim2.fromOffset(8, 8)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(120, 220, 120)
	title.Font = Enum.Font.Code
	title.TextScaled = true
	title.Text = "Dev console — set followers"
	title.Parent = panel

	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, -16, 0, 30)
	input.Position = UDim2.fromOffset(8, 38)
	input.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	input.TextColor3 = Color3.fromRGB(255, 255, 255)
	input.Font = Enum.Font.Code
	input.TextScaled = true
	input.ClearTextOnFocus = false
	input.Text = ""
	input.PlaceholderText = "follower count"
	input.Parent = panel

	local apply = Instance.new("TextButton")
	apply.Size = UDim2.new(1, -16, 0, 28)
	apply.Position = UDim2.fromOffset(8, 74)
	apply.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	apply.TextColor3 = Color3.fromRGB(255, 255, 255)
	apply.Font = Enum.Font.GothamBold
	apply.TextScaled = true
	apply.Text = "Set"
	apply.Parent = panel
	apply.Activated:Connect(function()
		local value = tonumber(input.Text)
		if value then
			setFollowers:FireServer(value)
		end
	end)

	-- Debug panel: trophy grant. Sits just below the 110px-tall main panel.
	debugPanel = Instance.new("Frame")
	debugPanel.AnchorPoint = Vector2.new(0.5, 0)
	debugPanel.Position = UDim2.new(0.5, 0, 0.06, 120)
	debugPanel.Size = UDim2.fromOffset(260, 60)
	debugPanel.BackgroundColor3 = Color3.fromRGB(30, 20, 40)
	debugPanel.Visible = false
	debugPanel.Parent = gui

	local debugTitle = Instance.new("TextLabel")
	debugTitle.Size = UDim2.new(1, 0, 0, 24)
	debugTitle.BackgroundTransparency = 1
	debugTitle.TextColor3 = Color3.fromRGB(200, 120, 220)
	debugTitle.Font = Enum.Font.Code
	debugTitle.TextScaled = true
	debugTitle.Text = "Debug mode"
	debugTitle.Parent = debugPanel

	local grantBtn = Instance.new("TextButton")
	grantBtn.Size = UDim2.new(1, -16, 0, 28)
	grantBtn.Position = UDim2.fromOffset(8, 32)
	grantBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 180)
	grantBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	grantBtn.Font = Enum.Font.GothamBold
	grantBtn.TextScaled = true
	grantBtn.Text = "Grant All Trophies"
	grantBtn.Parent = debugPanel
	grantBtn.Activated:Connect(function()
		grantTrophies:FireServer()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function DevConsoleController:Start()
	if not RunService:IsStudio() then
		return
	end

	local history: { string } = {}
	local panelVisible = false

	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		-- Don't filter on gameProcessed: the default character controls sink the arrow keys
		-- (and A/B), which would eat most of the sequence. Only ignore typing into a TextBox.
		if UserInputService:GetFocusedTextBox() ~= nil or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		local keyName = input.KeyCode.Name

		-- Full Konami (↑↑↓↓←→←→BA): toggles dev console + debug panels together.
		local matched
		matched, history = KeySequence.push(history, keyName, Config.DevConsole.Sequence)
		if matched then
			panelVisible = not panelVisible
			panel.Visible = panelVisible
			debugPanel.Visible = panelVisible
		end
	end)
end

return DevConsoleController
