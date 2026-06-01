--!strict
-- FollowerService: the single writer of Profile.Data.Followers. Other code asks it to
-- Award/Deduct; it clamps at >= 0, mirrors the value into leaderstats.Followers (the native
-- scoreboard), and fires the FollowerChanged remote for live HUD updates.
-- See references/architecture.md (Follower / reputation economy).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Net = require(ReplicatedStorage.Shared.Net)

local FollowerService = {}

local followerChanged: RemoteEvent
local changedCallbacks: { (Player, number) -> () } = {}

local function getLeaderstatValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end
	local value = leaderstats:FindFirstChild("Followers")
	return if value and value:IsA("IntValue") then value else nil
end

-- Writes the clamped balance to the profile, the leaderstat, and the client.
local function set(player: Player, value: number)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	value = math.max(0, math.floor(value))
	profile.Data.Followers = value

	local stat = getLeaderstatValue(player)
	if stat then
		stat.Value = value
	end

	followerChanged:FireClient(player, value)

	for _, callback in changedCallbacks do
		task.spawn(callback, player, value)
	end
end

function FollowerService:Init()
	followerChanged = Net.Event("FollowerChanged")
end

-- Pure offline-decay amount: followers lost for being away, prorated per day and capped. Returns
-- 0 when disabled, for a brand-new profile (LastSeen 0), or no elapsed time. Exposed for testing.
function FollowerService.computeOfflineDecay(
	enabled: boolean,
	perDay: number,
	maxLoss: number,
	lastSeen: number,
	now: number
): number
	if not enabled or lastSeen <= 0 then
		return 0
	end
	local elapsed = now - lastSeen
	if elapsed <= 0 then
		return 0
	end
	return math.min(maxLoss, math.floor((elapsed / 86400) * perDay))
end

function FollowerService:Start()
	-- Build the native scoreboard entry as each profile loads, seeded from saved data.
	DataService:OnProfileLoaded(function(player: Player, profile)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"

		local followers = Instance.new("IntValue")
		followers.Name = "Followers"
		followers.Value = profile.Data.Followers
		followers.Parent = leaderstats

		leaderstats.Parent = player

		local decay = Config.Decay
		local loss = FollowerService.computeOfflineDecay(
			decay.Enabled,
			decay.PerDay,
			decay.MaxLoss,
			profile.Data.LastSeen,
			os.time()
		)
		if loss > 0 then
			FollowerService:Deduct(player, loss, "offline-decay")
		end
	end)
end

function FollowerService:Award(player: Player, amount: number, _reason: string?)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	set(player, profile.Data.Followers + math.max(0, amount))
end

function FollowerService:Deduct(player: Player, amount: number, _reason: string?)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	set(player, profile.Data.Followers - math.max(0, amount))
end

function FollowerService:Get(player: Player): number
	local profile = DataService:GetProfile(player)
	return if profile then profile.Data.Followers else 0
end

-- Register a callback run with (player, newFollowerValue) whenever a balance changes.
function FollowerService:OnChanged(callback: (Player, number) -> ())
	table.insert(changedCallbacks, callback)
end

return FollowerService
