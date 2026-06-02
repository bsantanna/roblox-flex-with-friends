--!strict
-- FriendInviteService: when a player joins via a friend's game invite, both the inviter and the
-- invited friend get a one-time follower bonus. The invite prompt is sent client-side (carrying
-- the inviter's userId as launchData); on join the server reads that and grants the bonus, with
-- dedupe so the same friend is only rewarded once. See doc/002_implementation_plan.md (1.7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local Referral = require(ReplicatedStorage.Shared.Logic.Referral)

local FriendInviteService = {}

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

	-- ProfileData is a structural superset of Referral.Data; cast at the pure-core boundary.
	Referral.apply(inviterData :: any, joinerProfile.Data :: any, joiner.UserId, function()
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
