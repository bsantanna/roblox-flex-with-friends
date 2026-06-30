--!strict
-- PhotoService: server-authoritative photo captures. A capture awards base followers; if two or
-- more players are posing together (within range and facing a similar way) every participant gets
-- the co-op bonus. A per-player cooldown blocks spam. The client never decides the reward.
-- See doc/002_implementation_plan.md (1.5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local MonetizationService = require(script.Parent.MonetizationService)

local PhotoService = {}

-- VIP's "aura buff": photo follower rewards are multiplied for VIP players.
local function vipAdjusted(player: Player, amount: number): number
	if MonetizationService:IsVip(player) then
		return amount * Config.Monetization.Vip.PhotoMultiplier
	end
	return amount
end

local requestPhotoCapture: RemoteEvent
local photoResult: RemoteEvent

local lastCaptureAt: { [Player]: number } = {}

-- Pure co-op predicate: is `other` posing together with the capturer? Within CoopRange and
-- facing a similar direction (look-vector dot >= FacingDot). Exposed for unit testing.
function PhotoService.isCoopParticipant(
	capturerPos: Vector3,
	capturerLook: Vector3,
	otherPos: Vector3,
	otherLook: Vector3
): boolean
	local inRange = (otherPos - capturerPos).Magnitude <= Config.Photo.CoopRange
	local facing = capturerLook:Dot(otherLook) >= Config.Photo.FacingDot
	return inRange and facing
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Players (excluding the capturer) posing together with the capturer.
local function findCoParticipants(capturer: Player): { Player }
	local capturerRoot = getRoot(capturer)
	if not capturerRoot then
		return {}
	end

	local result = {}
	for _, other in Players:GetPlayers() do
		if other ~= capturer then
			local otherRoot = getRoot(other)
			if
				otherRoot
				and PhotoService.isCoopParticipant(
					capturerRoot.Position,
					capturerRoot.CFrame.LookVector,
					otherRoot.Position,
					otherRoot.CFrame.LookVector
				)
			then
				table.insert(result, other)
			end
		end
	end
	return result
end

local function onRequestPhotoCapture(capturer: Player)
	local profile = DataService:GetProfile(capturer)
	if not profile then
		return
	end

	local now = os.clock()
	if now - (lastCaptureAt[capturer] or -math.huge) < Config.Photo.Cooldown then
		photoResult:FireClient(capturer, false, 0, false, "Slow down!")
		return
	end
	lastCaptureAt[capturer] = now

	local coParticipants = findCoParticipants(capturer)
	local isCoop = #coParticipants >= 1

	-- Capturer always gets the base reward; co-op adds the bonus to everyone posing. VIP players
	-- earn a multiplied reward (the VIP aura buff), applied per participant.
	local capturerReward =
		vipAdjusted(capturer, Config.Photo.BaseReward + (if isCoop then Config.Photo.CoopBonus else 0))
	FollowerService:Award(capturer, capturerReward, "photo")
	profile.Data.Stats.PhotosTaken += 1
	capturer:SetAttribute("PhotosTaken", profile.Data.Stats.PhotosTaken)

	if isCoop then
		for _, participant in coParticipants do
			FollowerService:Award(participant, vipAdjusted(participant, Config.Photo.CoopBonus), "photo-coop")
		end
	end

	Analytics.event(capturer, "PhotoTaken", capturerReward, if isCoop then "coop" else "solo")
	photoResult:FireClient(capturer, true, capturerReward, isCoop, nil)
end

function PhotoService:Init()
	requestPhotoCapture = Net.Event("RequestPhotoCapture")
	photoResult = Net.Event("PhotoResult")
end

function PhotoService:Start()
	-- Surface lifetime photo count so the client onboarding (HintController) knows whether the
	-- player is new (0 photos) and can stop the tutorial after their first capture.
	DataService:OnProfileLoaded(function(player: Player, profile)
		player:SetAttribute("PhotosTaken", profile.Data.Stats.PhotosTaken)
	end)

	requestPhotoCapture.OnServerEvent:Connect(onRequestPhotoCapture)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCaptureAt[player] = nil
	end)
end

return PhotoService
