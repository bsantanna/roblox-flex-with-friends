--!strict
local framework = require("./framework")
local Referral = require("../src/shared/Logic/Referral")
local test = framework.test
local expect = framework.expect

local function data(claimed: boolean): Referral.Data
	return { ClaimedReferral = claimed, InvitedFriends = {}, Stats = { FriendsInvited = 0 } }
end

test("joiner claims the welcome bonus exactly once", function()
	local joiner = data(false)
	local joinerAwards = 0
	local awardJoiner = function()
		joinerAwards += 1
	end

	local _, rewardedJoiner = Referral.apply(nil, joiner, 5, function() end, awardJoiner)
	expect(rewardedJoiner).toBeTrue()
	expect(joiner.ClaimedReferral).toBeTrue()
	expect(joinerAwards).toEqual(1)

	local _, rewardedAgain = Referral.apply(nil, joiner, 5, function() end, awardJoiner)
	expect(rewardedAgain).toBeFalse()
	expect(joinerAwards).toEqual(1)
end)

test("inviter is rewarded once per unique friend", function()
	local inviter = data(true)
	local inviterAwards = 0
	local awardInviter = function()
		inviterAwards += 1
	end

	local rewarded1 = Referral.apply(inviter, data(false), 7, awardInviter, function() end)
	expect(rewarded1).toBeTrue()
	expect(inviterAwards).toEqual(1)
	expect(inviter.Stats.FriendsInvited).toEqual(1)

	-- same friend userId joining again (fresh joiner profile): inviter not rewarded twice
	local rewarded2 = Referral.apply(inviter, data(false), 7, awardInviter, function() end)
	expect(rewarded2).toBeFalse()
	expect(inviterAwards).toEqual(1)
end)
