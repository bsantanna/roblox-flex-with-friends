--!strict
-- FriendInviteService: when a player joins via a friend's game invite, both the inviter and the
-- invited friend get a one-time follower bonus. The invite prompt is sent client-side (carrying
-- the inviter's userId as launchData); on join the server reads that and grants the bonus, with
-- dedupe so the same friend is only rewarded once. See doc/002_implementation_plan.md (1.7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local FriendInviteService = {}

-- Pure referral core: decides and applies the dedupe to the profile data, calling the award
-- callbacks when a side qualifies. No Player/Config/Instance dependencies, so it is unit-testable.
-- The joiner claims their welcome bonus once ever; the inviter is rewarded once per unique friend.
function FriendInviteService._applyReferral(
	inviterData: Types.ProfileData?,
	joinerData: Types.ProfileData,
	joinerUserId: number,
	awardInviter: () -> (),
	awardJoiner: () -> ()
): (boolean, boolean)
	local rewardedJoiner = false
	if not joinerData.ClaimedReferral then
		joinerData.ClaimedReferral = true
		rewardedJoiner = true
		awardJoiner()
	end

	local rewardedInviter = false
	if inviterData and not table.find(inviterData.InvitedFriends, joinerUserId) then
		table.insert(inviterData.InvitedFriends, joinerUserId)
		inviterData.Stats.FriendsInvited += 1
		rewardedInviter = true
		awardInviter()
	end

	return rewardedInviter, rewardedJoiner
end

local function processReferral(joiner: Player, inviterUserId: number)
	if inviterUserId == joiner.UserId then
		return
	end

	local joinerProfile = DataService:GetProfile(joiner)
	if not joinerProfile then
		return
	end

	local inviter = Players:GetPlayerByUserId(inviterUserId)
	local inviterProfile = if inviter then DataService:GetProfile(inviter) else nil
	local inviterData = if inviterProfile then inviterProfile.Data else nil

	FriendInviteService._applyReferral(inviterData, joinerProfile.Data, joiner.UserId, function()
		if inviter then
			FollowerService:Award(inviter, Config.Invite.Bonus, "invited-friend")
		end
	end, function()
		FollowerService:Award(joiner, Config.Invite.Bonus, "invite-welcome")
	end)
end

function FriendInviteService:Start()
	DataService:OnProfileLoaded(function(joiner: Player, _profile)
		local ok, joinData = pcall(function()
			return joiner:GetJoinData()
		end)
		if not ok or typeof(joinData) ~= "table" then
			return
		end

		local inviterUserId = tonumber(joinData.LaunchData)
		if inviterUserId then
			processReferral(joiner, inviterUserId)
		end
	end)
end

return FriendInviteService
