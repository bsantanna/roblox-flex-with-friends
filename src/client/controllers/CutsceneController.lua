--!strict
-- CutsceneController: takes over the workspace camera for the quest's cinematic beats. This is the only
-- code in src/ that manipulates the workspace camera -- its framing must be verified by looking in
-- Studio, never trusted from the offset math (a CFrame that type-checks can still point at a wall).
--
-- "Intro" is a simple keyframe pan over the fretting Pilot (Config.Quest.Cutscene.Intro).
--
-- "Ending" is a staged, PERSONAL cinematic: its actors (a throwaway plane + a Pilot clone) are
-- client-local, so only the questing player sees it and the shared world is undisturbed. Beats:
--   1. Farewell -- frame the real Pilot, who waves + speaks (posed server-side in QuestService).
--   2. Taxi     -- cut (on a fade) to the runway, where the plane he "boarded" rolls forward.
--   3. Takeoff  -- the plane accelerates and climbs away along the runway, out over the lake.
--   4. Cockpit  -- a tight close-up of the smiling (Happy-posed) Pilot clone under a GTA
--                  "MISSION COMPLETE!" banner showing the reward.
-- The Pilot is inside the glass terminal and can't reach the plane, so his boarding is implied by the
-- fade between beats 1 and 2. A respawn mid-cutscene aborts cleanly (the camera is always restored);
-- both paths fire CutsceneDone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local TravelController = require(script.Parent.TravelController)

local CutsceneController = {}

local Q = Config.Quest
local FADE_SECONDS = 0.4
local HOLD_SECONDS = 0.6 -- pause on the final Intro beat before restoring control

local PLANE_BODY = Color3.fromRGB(245, 245, 245)
local PLANE_STRIPE = Color3.fromRGB(212, 175, 55)
local PLANE_ENGINE = Color3.fromRGB(60, 60, 70)

local player = Players.LocalPlayer

local cutscenePlay: RemoteEvent
local cutsceneDone: RemoteEvent
local playing = false

-- Mission Complete UI (built once in Init): cinematic letterbox bars + the centred banner.
local letterboxTop: Frame
local letterboxBottom: Frame
local banner: CanvasGroup
local bannerTitle: TextLabel
local bannerSubtitle: TextLabel
local bannerReward: TextLabel

-- The Pilot model is server-spawned and replicated, so the client can read his post + clone him. Returns
-- nil if he isn't present yet (then we skip the cinematic gracefully).
local function pilotModel(): Model?
	local world = Workspace:FindFirstChild("World")
	local airport = world and world:FindFirstChild("Airport")
	local pilot = airport and airport:FindFirstChild(Q.Pilot.NpcId)
	return (pilot and pilot:IsA("Model")) and pilot or nil
end

local function pilotPosition(model: Model?): Vector3?
	if not model then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return root and root.Position or nil
end

-- Plays an emote on a (client-local) model's Animator for `seconds`; no-op without an Animator.
local function poseEmote(model: Model, animationId: string, seconds: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play()
	task.delay(seconds, function()
		track:Stop()
	end)
end

local function tweenCamera(camera: Camera, eye: Vector3, target: Vector3, seconds: number)
	local goal = CFrame.lookAt(eye, target)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(camera, info, { CFrame = goal })
	tween:Play()
	tween.Completed:Wait()
end

-- Glides an anchored model from its current pivot to `goal` over `seconds`, frame by frame.
local function glide(model: Model, goal: CFrame, seconds: number)
	local start = model:GetPivot()
	local t0 = os.clock()
	while true do
		local a = math.min(1, (os.clock() - t0) / seconds)
		model:PivotTo(start:Lerp(goal, a))
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function planePart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- A compact throwaway airliner (~34 studs), nose = local -Z so CFrame.lookAt(pos, pos + heading) faces
-- it forward. The invisible Root pivot sits at the belly. Deliberately independent of AirTrafficService.
local function buildPlane(): Model
	local m = Instance.new("Model")
	m.Name = "QuestCutscenePlane"
	local root = planePart(m, Vector3.new(1, 1, 1), CFrame.new(0, 3, 0), PLANE_BODY)
	root.Transparency = 1
	m.PrimaryPart = root
	planePart(
		m,
		Vector3.new(34, 5, 5),
		CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(90), 0),
		PLANE_BODY,
		Enum.PartType.Cylinder
	)
	planePart(m, Vector3.new(5, 4.6, 4.6), CFrame.new(0, 5, -17), PLANE_BODY, Enum.PartType.Ball)
	planePart(m, Vector3.new(30, 0.5, 7), CFrame.new(0, 5, 0), PLANE_BODY)
	planePart(m, Vector3.new(0.5, 5, 4), CFrame.new(0, 8, 15), PLANE_BODY)
	planePart(m, Vector3.new(10, 0.4, 6), CFrame.new(0, 5, 13), PLANE_BODY)
	planePart(m, Vector3.new(0.2, 0.9, 34), CFrame.new(0, 5, 0), PLANE_STRIPE)
	for _, sx in { -8, 8 } do
		planePart(
			m,
			Vector3.new(5, 2, 2),
			CFrame.new(sx, 3.6, 0) * CFrame.Angles(0, math.rad(90), 0),
			PLANE_ENGINE,
			Enum.PartType.Cylinder
		)
	end
	return m
end

-- Orient the plane (nose local -Z) along a horizontal heading, pitched up by pitchDeg.
local function planePose(pos: Vector3, heading: Vector3, pitchDeg: number): CFrame
	local flat = Vector3.new(heading.X, 0, heading.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(1, 0, 0)
	return CFrame.lookAt(pos, pos + flat) * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

local function setLetterbox(visible: boolean)
	letterboxTop.Visible = visible
	letterboxBottom.Visible = visible
end

local function showBanner(reward: number)
	local M = Q.MissionComplete
	bannerTitle.Text = M.Title
	bannerSubtitle.Text = M.Subtitle
	bannerReward.Text = if reward > 0 then `+{reward}{M.RewardSuffix}` else M.ReplayLine
	banner.Visible = true
	banner.GroupTransparency = 1
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
end

local function hideBanner()
	banner.Visible = false
end

-- "Intro": the original two-beat keyframe pan over the Pilot.
local function playKeyframes(sequenceId: string)
	local keyframes = (Q.Cutscene :: any)[sequenceId]
	local base = pilotPosition(pilotModel())
	if not keyframes or #keyframes == 0 or not base then
		cutsceneDone:FireServer()
		return
	end
	playing = true

	local camera = Workspace.CurrentCamera
	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(base + keyframes[1].eye, base + keyframes[1].target)
	TravelController:TweenFade(1)

	for i = 2, #keyframes do
		local kf = keyframes[i]
		tweenCamera(camera, base + kf.eye, base + kf.target, Q.Cutscene.TweenSeconds)
	end
	task.wait(HOLD_SECONDS)

	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	camera.CameraType = Enum.CameraType.Custom
	TravelController:TweenFade(1)

	playing = false
	cutsceneDone:FireServer()
end

-- "Ending": the staged personal cinematic (see the file header). The Farewell is framed on the Pilot's
-- post; the plane beats are framed on the runway centre (Config.Zones.Airport).
local function playEnding(reward: number)
	local real = pilotModel()
	local pilotBase = pilotPosition(real)
	if not pilotBase or not real then
		cutsceneDone:FireServer()
		return
	end
	playing = true

	local E = Q.Cutscene.Ending
	local runwayBase = Config.Zones.Airport
	local camera = Workspace.CurrentCamera
	local plane: Model? = nil
	local clone: Model? = nil
	local aborted = false

	local respawnConn = player.CharacterAdded:Connect(function()
		aborted = true
	end)

	local function teardown()
		camera.CameraType = Enum.CameraType.Custom
		if plane then
			plane:Destroy()
		end
		if clone then
			clone:Destroy()
		end
		hideBanner()
		setLetterbox(false)
	end

	local function finish()
		respawnConn:Disconnect()
		teardown()
		TravelController:TweenFade(1)
		playing = false
		cutsceneDone:FireServer()
	end

	-- BEAT 1: Farewell -- frame the real Pilot (posed Happy + speaking server-side) waving from his post.
	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	camera.CameraType = Enum.CameraType.Scriptable
	setLetterbox(true)
	camera.CFrame = CFrame.lookAt(pilotBase + E.Farewell.Cam.eye, pilotBase + E.Farewell.Cam.target)
	TravelController:TweenFade(1)
	task.wait(E.Farewell.Seconds)
	if aborted then
		return finish()
	end

	-- Cut (under a fade) to the runway: he has boarded; the plane sits at the threshold facing +X.
	local P = E.Plane
	local startPos = runwayBase + P.Start
	local taxiPos = runwayBase + P.TaxiTo
	local rollPos = runwayBase + P.RollTo
	local climbPos = runwayBase + P.ClimbTo
	local heading = rollPos - startPos

	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	local newPlane = buildPlane()
	newPlane:PivotTo(planePose(startPos, heading, 0))
	newPlane.Parent = Workspace
	plane = newPlane
	camera.CFrame = CFrame.lookAt(runwayBase + E.Taxi.Cam.eye, runwayBase + E.Taxi.Cam.target)
	TravelController:TweenFade(1)

	-- BEAT 2: Taxi -- a slow roll up the runway.
	glide(newPlane, planePose(taxiPos, heading, 0), E.Taxi.Seconds)
	if aborted then
		return finish()
	end

	-- BEAT 3: Takeoff -- accelerate to the rotate point, then climb away. Camera tracks.
	task.spawn(
		tweenCamera,
		camera,
		runwayBase + E.Takeoff.Cam.eye,
		runwayBase + E.Takeoff.Cam.target,
		E.Takeoff.Seconds
	)
	glide(newPlane, planePose(rollPos, heading, 0), E.Takeoff.Seconds * 0.45)
	glide(newPlane, planePose(climbPos, heading, -E.ClimbPitch), E.Takeoff.Seconds * 0.55)
	if aborted then
		return finish()
	end

	-- BEAT 4: Cockpit -- close-up of the smiling Pilot (a clone posed high over the runway, sky behind)
	-- under the Mission Complete banner.
	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	newPlane:Destroy()
	plane = nil
	local spot = runwayBase + E.Cockpit.PilotSpot
	local camEye = runwayBase + E.Cockpit.Cam.eye
	local pilotClone = real:Clone()
	clone = pilotClone
	pilotClone:PivotTo(CFrame.lookAt(spot, Vector3.new(camEye.X, spot.Y, camEye.Z)))
	pilotClone.Parent = Workspace
	poseEmote(pilotClone, Q.Pose.Happy, E.Cockpit.Seconds + 1)
	camera.CFrame = CFrame.lookAt(camEye, runwayBase + E.Cockpit.Cam.target)
	TravelController:TweenFade(1)
	showBanner(reward)
	task.wait(E.Cockpit.Seconds)

	TravelController:TweenFade(0)
	task.wait(FADE_SECONDS)
	finish()
end

function CutsceneController:Init()
	cutscenePlay = Net.Event("CutscenePlay")
	cutsceneDone = Net.Event("CutsceneDone")

	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestCutscene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20

	letterboxTop = Instance.new("Frame")
	letterboxTop.Name = "LetterboxTop"
	letterboxTop.Size = UDim2.fromScale(1, 0.12)
	letterboxTop.BackgroundColor3 = Color3.new(0, 0, 0)
	letterboxTop.BorderSizePixel = 0
	letterboxTop.Visible = false
	letterboxTop.Parent = gui

	letterboxBottom = Instance.new("Frame")
	letterboxBottom.Name = "LetterboxBottom"
	letterboxBottom.AnchorPoint = Vector2.new(0, 1)
	letterboxBottom.Position = UDim2.fromScale(0, 1)
	letterboxBottom.Size = UDim2.fromScale(1, 0.12)
	letterboxBottom.BackgroundColor3 = Color3.new(0, 0, 0)
	letterboxBottom.BorderSizePixel = 0
	letterboxBottom.Visible = false
	letterboxBottom.Parent = gui

	banner = Instance.new("CanvasGroup")
	banner.Name = "MissionComplete"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.5)
	banner.Size = UDim2.fromScale(0.8, 0.3)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.Parent = gui

	local bannerLayout = Instance.new("UIListLayout")
	bannerLayout.FillDirection = Enum.FillDirection.Vertical
	bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bannerLayout.Padding = UDim.new(0, 8)
	bannerLayout.Parent = banner

	bannerTitle = Instance.new("TextLabel")
	bannerTitle.Size = UDim2.fromScale(1, 0.45)
	bannerTitle.BackgroundTransparency = 1
	bannerTitle.Text = ""
	bannerTitle.TextScaled = true
	bannerTitle.TextColor3 = Color3.fromRGB(255, 215, 90)
	bannerTitle.Font = Enum.Font.GothamBlack
	bannerTitle.Parent = banner
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = Color3.fromRGB(20, 20, 20)
	titleStroke.Parent = bannerTitle

	bannerSubtitle = Instance.new("TextLabel")
	bannerSubtitle.Size = UDim2.fromScale(0.9, 0.22)
	bannerSubtitle.BackgroundTransparency = 1
	bannerSubtitle.Text = ""
	bannerSubtitle.TextScaled = true
	bannerSubtitle.TextColor3 = Color3.fromRGB(245, 245, 245)
	bannerSubtitle.Font = Enum.Font.GothamMedium
	bannerSubtitle.Parent = banner

	bannerReward = Instance.new("TextLabel")
	bannerReward.Size = UDim2.fromScale(0.9, 0.24)
	bannerReward.BackgroundTransparency = 1
	bannerReward.Text = ""
	bannerReward.TextScaled = true
	bannerReward.TextColor3 = Color3.fromRGB(150, 230, 150)
	bannerReward.Font = Enum.Font.GothamBold
	bannerReward.Parent = banner

	gui.Parent = player:WaitForChild("PlayerGui")
end

function CutsceneController:Start()
	cutscenePlay.OnClientEvent:Connect(function(sequenceId: string, reward: number?)
		if playing then
			return
		end
		if sequenceId == "Ending" then
			task.spawn(playEnding, reward or 0)
		else
			task.spawn(playKeyframes, sequenceId)
		end
	end)
end

return CutsceneController
