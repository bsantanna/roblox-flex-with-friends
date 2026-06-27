--!strict
-- QuestController: the interacting player's side of the Pilot quest. It listens to the single
-- QuestState sync and drives all player-only UI/world feedback:
--   * the Accept/Decline choice when the quest is offered,
--   * the quest HUD (countdown timer + objective counter) while collecting/returning,
--   * the 4 objective beacons in the city -- client-side and personal (GTA-style), so only the
--     questing player sees their objectives. Collection is server-authoritative: a beacon's prompt
--     fires RequestCollectPackage and the server validates real proximity before advancing.
-- Tunables (positions, beacon look, collect radius) come from Config.Quest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local QuestController = {}

local player = Players.LocalPlayer
local Q = Config.Quest

-- The active quest's config + derived collectible positions, set from each QuestState sync (the server
-- threads the questId). Defaults to the Pilot quest until the first sync arrives.
local activeQ: any = Q
local activePositions: { Vector3 } = Q.PackagePositions
local total = #Q.PackagePositions -- objective count; the server sends the authoritative value each sync

local function getQuestConfig(questId: string): any
	if questId == Q.Id then
		return Q
	end
	return Q.FirstQuest
end

-- A quest's collectible world positions: an explicit list (Pilot's packages) or the single CollectPosition.
local function questPositions(qc: any): { Vector3 }
	if qc.PackagePositions then
		return qc.PackagePositions
	end
	if qc.CollectPosition then
		return { qc.CollectPosition }
	end
	return {}
end

local questState: RemoteEvent
local questAccept: RemoteEvent
local questDecline: RemoteEvent
local requestCollect: RemoteEvent

local buttonRow: Frame
local hudFrame: Frame
local timerLabel: TextLabel
local objLabel: TextLabel
local toastLabel: TextLabel
local toastToken = 0
local prevCount = 0

-- Beacon + collection state. collectedLocal mirrors which packages this client has already grabbed so
-- re-entering the city doesn't respawn collected beacons; the server count stays authoritative.
local beacons: { [number]: Model } = {}
local collectedLocal: { [number]: boolean } = {}

local questPhase = "idle"
local questCount = 0
local questDeadline: number? = nil

-- Accept / Decline choice ----------------------------------------------------------------------

local function clearButtons()
	for _, child in buttonRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

-- Matches DialogController's button look so the quest choice reads as part of the same dialog UI.
local function addButton(label: string, onActivated: () -> ())
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(140, 40)
	button.BackgroundColor3 = Color3.fromRGB(55, 60, 72)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = label
	button.Parent = buttonRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 98, 116)
	stroke.Thickness = 1
	stroke.Parent = button

	button.Activated:Connect(function()
		clearButtons()
		buttonRow.Visible = false
		onActivated()
	end)
end

local function showOffer()
	buttonRow.Visible = true
	clearButtons()
	addButton("Accept", function()
		questAccept:FireServer()
	end)
	addButton("Decline", function()
		questDecline:FireServer()
	end)
end

local function hideOffer()
	clearButtons()
	buttonRow.Visible = false
end

-- Objective beacons ----------------------------------------------------------------------------

local function removeBeacon(index: number)
	local model = beacons[index]
	if model then
		model:Destroy()
		beacons[index] = nil
	end
end

local function clearBeacons()
	for index in beacons do
		removeBeacon(index)
	end
end

-- A little pickup flourish: burst the particles, hide the part, then destroy after the burst clears.
local function collectFeedback(model: Model)
	local part = model.PrimaryPart
	if part then
		local emitter = part:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter:Emit(24)
		end
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = false
		end
		part.Transparency = 1
	end
	task.delay(0.5, function()
		model:Destroy()
	end)
end

local function makeBeacon(index: number, ground: Vector3): Model
	local B = activeQ.Beacon
	local model = Instance.new("Model")
	model.Name = `QuestBeacon{index}`

	local part = Instance.new("Part")
	part.Name = "Pickup"
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = B.Color
	part.Size = B.PartSize
	part.Position = ground + Vector3.new(0, B.PartHeight, 0)
	part.Parent = model
	model.PrimaryPart = part

	local light = Instance.new("PointLight")
	light.Color = B.Color
	light.Range = B.LightRange
	light.Brightness = B.LightBrightness
	light.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(B.Color)
	emitter.Rate = B.ParticleRate
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new(0.6)
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.Parent = part

	-- A beam from the ground point up to the sky so the objective reads from across the town.
	local groundAtt = Instance.new("Attachment")
	groundAtt.Position = Vector3.new(0, -B.PartHeight, 0)
	groundAtt.Parent = part
	local skyAtt = Instance.new("Attachment")
	skyAtt.Position = Vector3.new(0, B.BeamHeight, 0)
	skyAtt.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment0 = groundAtt
	beam.Attachment1 = skyAtt
	beam.Width0 = B.BeamWidth
	beam.Width1 = B.BeamWidth * 0.3
	beam.Color = ColorSequence.new(B.Color)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	prompt.ObjectText = activeQ.CollectableName or "Package"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = activeQ.CollectRadius
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		if collectedLocal[index] then
			return
		end
		-- Optimistic local removal; the server validates proximity before it counts.
		collectedLocal[index] = true
		local m = beacons[index]
		beacons[index] = nil
		if m then
			collectFeedback(m)
		end
		requestCollect:FireServer(index)
	end)

	model.Parent = Workspace
	return model
end

-- Spawns beacons for packages this client hasn't collected yet (idempotent: skips existing ones).
local function spawnBeacons()
	for index, ground in activePositions do
		if not collectedLocal[index] and not beacons[index] then
			beacons[index] = makeBeacon(index, ground)
		end
	end
end

local function resetCollected()
	for i = 1, #activePositions do
		collectedLocal[i] = false
	end
end

-- HUD ------------------------------------------------------------------------------------------

local function setHud(visible: boolean)
	hudFrame.Visible = visible
end

local function updateObjective()
	objLabel.Text = `{activeQ.ObjectiveIcon or "📦"} {questCount}/{total}`
end

-- A brief encouraging toast (auto-hides). Latest call wins via the token.
local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(2.2, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

-- State sync -----------------------------------------------------------------------------------

local function onQuestState(questId: string, phase: string, count: number, serverTotal: number, deadline: number?)
	activeQ = getQuestConfig(questId)
	activePositions = questPositions(activeQ)
	total = serverTotal
	questPhase = phase
	questCount = count
	questDeadline = deadline

	if phase == "offer" then
		showOffer()
	else
		hideOffer()
	end

	-- A collectible was just confirmed (count climbed) -> an encouraging toast.
	if (phase == "collecting" or phase == "returning") and count > prevCount then
		showToast(activeQ.CollectToasts[math.min(count, #activeQ.CollectToasts)])
	end
	prevCount = count

	if phase == "offer" then
		if count == 0 then
			resetCollected()
		end
		clearBeacons()
		setHud(false)
	elseif phase == "collecting" then
		spawnBeacons()
		updateObjective()
		setHud(true)
	elseif phase == "returning" then
		clearBeacons()
		updateObjective()
		setHud(true)
	else
		-- idle / failed / complete / replay: tear everything down.
		resetCollected()
		clearBeacons()
		setHud(false)
	end
end

-- Per-frame beacon animation + countdown render.
local function onHeartbeat(dt: number)
	local now = Workspace:GetServerTimeNow()
	for _, model in beacons do
		local part = model.PrimaryPart
		if part then
			part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(activeQ.Beacon.SpinSpeed) * dt, 0)
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				light.Brightness = activeQ.Beacon.LightBrightness * (0.65 + 0.35 * math.sin(now * 4))
			end
		end
	end

	if hudFrame.Visible then
		if questPhase == "collecting" and questDeadline then
			local remaining = math.max(0, math.floor((questDeadline :: number) - now))
			timerLabel.Text = `⏱ {remaining}s`
		elseif questPhase == "returning" then
			timerLabel.Text = activeQ.ReturnLabel or "Deliver it back!"
		end
	end
end

function QuestController:Init()
	questState = Net.Event("QuestState")
	questAccept = Net.Event("QuestAccept")
	questDecline = Net.Event("QuestDecline")
	requestCollect = Net.Event("RequestCollectPackage")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Quest"
	gui.ResetOnSpawn = false

	buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -140) -- above the Photo shutter, like DialogController
	buttonRow.Size = UDim2.fromOffset(440, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Visible = false
	buttonRow.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttonRow

	-- The quest HUD: a top-centre panel with the countdown and objective counter.
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "QuestHud"
	hudFrame.AnchorPoint = Vector2.new(0.5, 0)
	hudFrame.Position = UDim2.new(0.5, 0, 0, 12)
	hudFrame.Size = UDim2.fromOffset(220, 64)
	hudFrame.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
	hudFrame.BackgroundTransparency = 0.2
	hudFrame.BorderSizePixel = 0
	hudFrame.Visible = false
	hudFrame.Parent = gui

	local hudCorner = Instance.new("UICorner")
	hudCorner.CornerRadius = UDim.new(0, 10)
	hudCorner.Parent = hudFrame

	timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.fromScale(1, 0.5)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = ""
	timerLabel.TextScaled = true
	timerLabel.TextColor3 = Color3.fromRGB(255, 210, 120)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = hudFrame

	objLabel = Instance.new("TextLabel")
	objLabel.Position = UDim2.fromScale(0, 0.5)
	objLabel.Size = UDim2.fromScale(1, 0.5)
	objLabel.BackgroundTransparency = 1
	objLabel.Text = ""
	objLabel.TextScaled = true
	objLabel.TextColor3 = Color3.fromRGB(220, 230, 220)
	objLabel.Font = Enum.Font.GothamBold
	objLabel.Parent = hudFrame

	-- Encouraging collection toast, just under the HUD.
	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "QuestToast"
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0, 84)
	toastLabel.Size = UDim2.fromOffset(360, 40)
	toastLabel.BackgroundColor3 = Color3.fromRGB(40, 55, 30)
	toastLabel.BackgroundTransparency = 0.2
	toastLabel.Text = ""
	toastLabel.TextScaled = true
	toastLabel.TextColor3 = Color3.fromRGB(235, 245, 220)
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.Visible = false
	toastLabel.Parent = gui

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 10)
	toastCorner.Parent = toastLabel

	gui.Parent = player:WaitForChild("PlayerGui")
end

function QuestController:Start()
	questState.OnClientEvent:Connect(onQuestState)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return QuestController
