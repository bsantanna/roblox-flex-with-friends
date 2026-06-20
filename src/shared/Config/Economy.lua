--!strict
-- Follower-economy tunables: travel, photos, invites (PhotoService, FriendInviteService, travel).

local Economy = {}

Economy.Travel = {
	CarbonFootprintLoss = 20, -- followers lost when traveling back Home
	MinigameWindow = 5, -- seconds the player has to board the plane at the Airport
}

Economy.Photo = {
	BaseReward = 25, -- followers per photo
	CoopBonus = 40, -- extra followers per participant when >= 2 players pose together
	CoopRange = 20, -- max studs between participants
	FacingDot = 0, -- min dot of look vectors to count as posing together (>= 0: same-ish way)
	Cooldown = 3, -- seconds between captures per player
}

Economy.Invite = {
	Bonus = 75, -- followers granted to both the inviter and the invited friend (once per friend)
}

return Economy
