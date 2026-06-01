--!strict
-- FriendController: an "Invite Friends" button that opens the Roblox game-invite prompt, carrying
-- the inviter's userId as launchData so the server can grant the invite bonus when the friend joins.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local FriendController = {}

local player = Players.LocalPlayer

local function promptInvite()
	local canInvite = false
	pcall(function()
		canInvite = SocialService:CanSendGameInviteAsync(player)
	end)
	if not canInvite then
		return
	end

	local options = Instance.new("ExperienceInviteOptions")
	options.LaunchData = tostring(player.UserId)
	pcall(function()
		SocialService:PromptGameInvite(player, options)
	end)
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

	button.Activated:Connect(promptInvite)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return FriendController
