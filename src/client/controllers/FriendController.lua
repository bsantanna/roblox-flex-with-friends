--!strict
-- FriendController: an "Invite Friends" button that opens the Roblox game-invite prompt, carrying
-- the inviter's userId as launchData so the server can grant the invite bonus when the friend joins.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local FriendController = {}

local player = Players.LocalPlayer

local statusLabel: TextLabel
local statusToken = 0

-- The invite prompt can't be sent from Studio (only the published experience), and both calls
-- can fail silently — so always give the player feedback instead of a dead button.
local UNAVAILABLE = "Invites aren't available here — try the published game"

local function showStatus(text: string)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = text
	statusLabel.Visible = true
	task.delay(2.5, function()
		if token == statusToken then
			statusLabel.Visible = false
		end
	end)
end

local function promptInvite()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok or not canInvite then
		showStatus(UNAVAILABLE)
		return
	end

	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = tostring(player.UserId)
	local sent = pcall(function()
		SocialService:PromptGameInvite(player, options)
	end)
	showStatus(if sent then "Opening invites…" else UNAVAILABLE)
end

function FriendController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Friends"
	gui.ResetOnSpawn = false

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -16, 0, 16)
	button.Size = UDim2.fromOffset(160, 44)
	button.BackgroundColor3 = Color3.fromRGB(90, 70, 200)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = "Invite Friends"
	button.Parent = gui

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.Position = UDim2.new(1, -16, 0, 68)
	statusLabel.Size = UDim2.fromOffset(300, 32)
	statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	statusLabel.BackgroundTransparency = 0.2
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Visible = false
	statusLabel.Parent = gui

	button.Activated:Connect(promptInvite)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return FriendController
