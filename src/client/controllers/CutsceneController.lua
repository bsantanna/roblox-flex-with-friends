--!strict
-- CutsceneController: takes over the workspace camera for the quest's cinematic beats. On CutscenePlay
-- it makes the camera Scriptable and tweens it through Config.Quest.Cutscene[sequenceId] keyframes
-- (eye/target offsets relative to the Pilot's post), then restores the player camera and fires
-- CutsceneDone. A quick fade (reused from TravelController) hides the hard cut in and out. This is the
-- only code in src/ that manipulates the workspace camera -- its framing must be verified by looking in
-- Studio, never trusted from the offset math (a CFrame that type-checks can still point at a wall).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local TravelController = require(script.Parent.TravelController)

local CutsceneController = {}

local Q = Config.Quest
local FADE_SECONDS = 0.4
local HOLD_SECONDS = 0.6 -- pause on the final beat before restoring control

local cutscenePlay: RemoteEvent
local cutsceneDone: RemoteEvent
local playing = false

-- The Pilot model is server-spawned and replicated, so the client can read his post to anchor the
-- camera offsets. Returns nil if he isn't present yet (then we skip the cinematic gracefully).
local function pilotPosition(): Vector3?
	local world = Workspace:FindFirstChild("World")
	local airport = world and world:FindFirstChild("Airport")
	local pilot = airport and airport:FindFirstChild(Q.Pilot.NpcId)
	if pilot and pilot:IsA("Model") then
		local root = pilot.PrimaryPart or pilot:FindFirstChildWhichIsA("BasePart")
		if root then
			return root.Position
		end
	end
	return nil
end

local function play(sequenceId: string)
	if playing then
		return
	end
	local keyframes = (Q.Cutscene :: any)[sequenceId]
	local base = pilotPosition()
	if not keyframes or #keyframes == 0 or not base then
		-- Nothing to frame -> tell the server we're done so its beats can proceed regardless.
		cutsceneDone:FireServer()
		return
	end
	playing = true

	local camera = Workspace.CurrentCamera

	TravelController:TweenFade(0) -- to black
	task.wait(FADE_SECONDS)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(base + keyframes[1].eye, base + keyframes[1].target)
	TravelController:TweenFade(1) -- fade in onto the cinematic camera

	for i = 2, #keyframes do
		local kf = keyframes[i]
		local goal = CFrame.lookAt(base + kf.eye, base + kf.target)
		local info = TweenInfo.new(Q.Cutscene.TweenSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local tween = TweenService:Create(camera, info, { CFrame = goal })
		tween:Play()
		tween.Completed:Wait()
	end
	task.wait(HOLD_SECONDS)

	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	camera.CameraType = Enum.CameraType.Custom
	TravelController:TweenFade(1)

	playing = false
	cutsceneDone:FireServer()
end

function CutsceneController:Init()
	cutscenePlay = Net.Event("CutscenePlay")
	cutsceneDone = Net.Event("CutsceneDone")
end

function CutsceneController:Start()
	cutscenePlay.OnClientEvent:Connect(function(sequenceId: string)
		task.spawn(play, sequenceId)
	end)
end

return CutsceneController
