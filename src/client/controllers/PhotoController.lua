--!strict
-- PhotoController: a shutter button that requests a photo capture and shows the result. The
-- server (PhotoService) decides the reward; this only sends the request and renders feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)

local PhotoController = {}

local player = Players.LocalPlayer

local requestPhotoCapture: RemoteEvent
local photoResult: RemoteEvent

local flash: Frame
local resultLabel: TextLabel

local function onPhotoResult(success: boolean, reward: number, coop: boolean, reason: string?)
	if success then
		TweenService:Create(flash, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()
		task.delay(0.15, function()
			TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end)
		resultLabel.Text = if coop then `Co-op photo! +{reward} followers` else `+{reward} followers`
	else
		resultLabel.Text = reason or "Could not take photo"
	end

	resultLabel.Visible = true
	task.delay(2, function()
		resultLabel.Visible = false
	end)
end

function PhotoController:Init()
	requestPhotoCapture = Net.Event("RequestPhotoCapture")
	photoResult = Net.Event("PhotoResult")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Photo"
	gui.ResetOnSpawn = false

	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20
	flash.Parent = gui

	local shutter = Instance.new("TextButton")
	shutter.AnchorPoint = Vector2.new(0.5, 1)
	shutter.Position = UDim2.new(0.5, 0, 1, -24)
	shutter.Size = UDim2.fromOffset(120, 48)
	shutter.BackgroundColor3 = Color3.fromRGB(230, 230, 235)
	shutter.TextColor3 = Color3.fromRGB(20, 20, 24)
	shutter.Font = Enum.Font.GothamBold
	shutter.TextScaled = true
	shutter.Text = "Photo"
	shutter.Parent = gui

	resultLabel = Instance.new("TextLabel")
	resultLabel.AnchorPoint = Vector2.new(0.5, 1)
	resultLabel.Position = UDim2.new(0.5, 0, 1, -80)
	resultLabel.Size = UDim2.fromOffset(320, 32)
	resultLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	resultLabel.BackgroundTransparency = 0.2
	resultLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextScaled = true
	resultLabel.Text = ""
	resultLabel.Visible = false
	resultLabel.Parent = gui

	shutter.Activated:Connect(function()
		requestPhotoCapture:FireServer()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function PhotoController:Start()
	photoResult.OnClientEvent:Connect(onPhotoResult)
end

return PhotoController
