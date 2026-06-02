--!strict
-- Pure referral logic, free of Roblox globals so it is unit-testable under Lune. The joiner claims
-- a one-time welcome bonus; the inviter is rewarded once per unique invited friend. Awards are
-- applied through callbacks so this stays free of FollowerService / Config / Instance dependencies.

local Referral = {}

export type Data = {
	ClaimedReferral: boolean,
	InvitedFriends: { number },
	Stats: { FriendsInvited: number },
}

-- Applies the dedupe to the profile data and calls the award callbacks when a side qualifies.
-- Returns (rewardedInviter, rewardedJoiner).
function Referral.apply(
	inviterData: Data?,
	joinerData: Data,
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

return Referral
