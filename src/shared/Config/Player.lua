--!strict
-- Player persistence + progression tunables (DataService, FollowerService decay).

local Types = require(script.Parent.Parent.Types)

local Player = {}

-- DataStore name for player profiles. Bump the suffix to reset all saved data during dev.
-- v2: Friends changed from a { string } list of befriended ids to a { [id]: OutfitData } map.
Player.DataStoreName = "PlayerData_v2"

-- Default profile data. New keys added here are reconciled into existing profiles on load.
Player.ProfileTemplate = {
	Followers = 0,
	Reputation = 50,
	UnlockedPlaces = { "Home", "Airport", "Beach" },
	UnlockedNpcs = {},
	Stats = {
		PhotosTaken = 0,
		TripsTaken = 0,
		FriendsInvited = 0,
	},
	LastSeen = 0,
	-- CompanionNpc defaults to nil (no companion).
	InvitedFriends = {},
	ClaimedReferral = false,
	Friends = {},
} :: Types.ProfileData

-- Offline follower decay applied on join. Off by default until balanced with real playtest data.
Player.Decay = {
	Enabled = false,
	PerDay = 10, -- followers lost per full day offline
	MaxLoss = 50, -- cap on a single return's loss
}

return Player
