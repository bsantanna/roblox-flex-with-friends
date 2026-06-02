--!strict
-- FollowerService: the single writer of Profile.Data.Followers. Other code asks it to
-- Award/Deduct; it clamps at >= 0, mirrors the value into leaderstats.Followers (the native
-- scoreboard), and fires the FollowerChanged remote for live HUD updates.
-- See references/architecture.md (Follower / reputation economy).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Net = require(ReplicatedStorage.Shared.Net)
local Followers = require(ReplicatedStorage.Shared.Logic.Followers)
local Decay = require(ReplicatedStorage.Shared.Logic.Decay)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)

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

	value = Followers.clamp(value)
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
		local loss = Decay.compute(decay.Enabled, decay.PerDay, decay.MaxLoss, profile.Data.LastSeen, os.time())
		if loss > 0 then
			FollowerService:Deduct(player, loss, "offline-decay")
		end
	end)
end

function FollowerService:Award(player: Player, amount: number, reason: string?)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	set(player, Followers.afterAward(profile.Data.Followers, amount))
	Analytics.event(player, "FollowerAward", amount, reason)
end

function FollowerService:Deduct(player: Player, amount: number, reason: string?)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	set(player, Followers.afterDeduct(profile.Data.Followers, amount))
	Analytics.event(player, "FollowerDeduct", amount, reason)
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
