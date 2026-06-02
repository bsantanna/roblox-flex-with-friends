--!strict
-- PhotoController: a shutter button that takes a real screen capture (CaptureService) and shows
-- it as a polaroid preview with Save/Share, while requesting the follower reward from the server.
-- The server (PhotoService) decides the reward; the capture is purely client-side visual feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CaptureService = game:GetService("CaptureService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage.Shared.Net)

local PhotoController = {}

local player = Players.LocalPlayer
local playerGui: PlayerGui

local requestPhotoCapture: RemoteEvent
local photoResult: RemoteEvent

local gui: ScreenGui
local flash: Frame
local resultLabel: TextLabel
local previewFrame: Frame
local previewImage: ImageLabel

local capturing = false
local lastCapture: string?

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

-- Hide all in-game UI (our own GUI included) and the Roblox core UI so the screenshot is the
-- framed scene only. Returns a function that restores exactly what was hidden.
local function hideInterfaceForCapture(): () -> ()
	local restores: { () -> () } = {}
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled then
			child.Enabled = false
			table.insert(restores, function()
				child.Enabled = true
			end)
		end
	end
	if pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end) then
		table.insert(restores, function()
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
			end)
		end)
	end
	return function()
		for _, restore in restores do
			restore()
		end
	end
end

local function takePhoto()
	if capturing then
		return
	end
	capturing = true

	-- Reward path stays server-authoritative and runs independently of the cosmetic capture.
	requestPhotoCapture:FireServer()

	local restore = hideInterfaceForCapture()
	-- Let the hidden UI render out before grabbing the frame.
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()

	CaptureService:CaptureScreenshot(function(contentId: string)
		restore()
		capturing = false
		lastCapture = contentId
		previewImage.Image = contentId
		previewFrame.Visible = true
	end)
end

function PhotoController:Init()
	requestPhotoCapture = Net.Event("RequestPhotoCapture")
	photoResult = Net.Event("PhotoResult")

	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	gui = Instance.new("ScreenGui")
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

	-- Polaroid preview of the captured shot, with Save / Share / close.
	previewFrame = Instance.new("Frame")
	previewFrame.Name = "Preview"
	previewFrame.AnchorPoint = Vector2.new(1, 0.5)
	previewFrame.Position = UDim2.new(1, -16, 0.5, 0)
	previewFrame.Size = UDim2.fromOffset(260, 200)
	previewFrame.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	previewFrame.Visible = false
	previewFrame.Parent = gui

	previewImage = Instance.new("ImageLabel")
	previewImage.AnchorPoint = Vector2.new(0.5, 0)
	previewImage.Position = UDim2.new(0.5, 0, 0, 10)
	previewImage.Size = UDim2.fromOffset(240, 135)
	previewImage.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	previewImage.ScaleType = Enum.ScaleType.Crop
	previewImage.Parent = previewFrame

	local saveButton = Instance.new("TextButton")
	saveButton.AnchorPoint = Vector2.new(0, 1)
	saveButton.Position = UDim2.new(0, 10, 1, -10)
	saveButton.Size = UDim2.fromOffset(115, 38)
	saveButton.BackgroundColor3 = Color3.fromRGB(80, 160, 120)
	saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	saveButton.Font = Enum.Font.GothamBold
	saveButton.TextScaled = true
	saveButton.Text = "Save"
	saveButton.Parent = previewFrame

	local shareButton = Instance.new("TextButton")
	shareButton.AnchorPoint = Vector2.new(1, 1)
	shareButton.Position = UDim2.new(1, -10, 1, -10)
	shareButton.Size = UDim2.fromOffset(115, 38)
	shareButton.BackgroundColor3 = Color3.fromRGB(90, 130, 200)
	shareButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	shareButton.Font = Enum.Font.GothamBold
	shareButton.TextScaled = true
	shareButton.Text = "Share"
	shareButton.Parent = previewFrame

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -4, 0, 4)
	closeButton.Size = UDim2.fromOffset(24, 24)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextScaled = true
	closeButton.Text = "X"
	closeButton.ZIndex = 2
	closeButton.Parent = previewFrame

	shutter.Activated:Connect(takePhoto)
	saveButton.Activated:Connect(function()
		if lastCapture then
			CaptureService:PromptSaveCapturesToGallery({ lastCapture }, function() end)
		end
	end)
	shareButton.Activated:Connect(function()
		if lastCapture then
			CaptureService:PromptShareCapture(lastCapture, "", function() end)
		end
	end)
	closeButton.Activated:Connect(function()
		previewFrame.Visible = false
	end)

	gui.Parent = playerGui
end

function PhotoController:Start()
	photoResult.OnClientEvent:Connect(onPhotoResult)
end

return PhotoController
