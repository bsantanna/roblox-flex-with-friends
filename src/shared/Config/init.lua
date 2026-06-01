--!strict
-- Tunable values for Flex-with-Friends. Magic numbers live here, not in services.
-- See doc/002_implementation_plan.md.

local Types = require(script.Parent.Types)

local Config = {}

-- DataStore name for player profiles. Bump the suffix to reset all saved data during dev.
Config.DataStoreName = "PlayerData_v1"

-- Default profile data. New keys added here are reconciled into existing profiles on load.
Config.ProfileTemplate = {
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
} :: Types.ProfileData

-- World zone origins. MVP keeps Home/Airport/Beach as zones in one place; "travel"
-- repositions the player between these origins (Airport is the transit waypoint where the
-- boarding minigame runs).
Config.Zones = {
	Home = Vector3.new(0, 0, 0),
	Airport = Vector3.new(0, 0, 200),
	Beach = Vector3.new(0, 0, 400),
} :: { [string]: Vector3 }

-- Travel destinations selectable from the Cab picker. A place is travelable only if it is in
-- the player's UnlockedPlaces. Arrival is the follower reward for arriving there.
Config.Places = {
	Home = { Zone = Config.Zones.Home, Arrival = 0 },
	Beach = { Zone = Config.Zones.Beach, Arrival = 50 },
} :: { [string]: { Zone: Vector3, Arrival: number } }

Config.Travel = {
	CarbonFootprintLoss = 20, -- followers lost when traveling back Home
	MinigameWindow = 5, -- seconds the player has to board the plane at the Airport
}

Config.Photo = {
	BaseReward = 25, -- followers per photo
	CoopBonus = 40, -- extra followers per participant when >= 2 players pose together
	CoopRange = 20, -- max studs between participants
	FacingDot = 0, -- min dot of look vectors to count as posing together (>= 0: same-ish way)
	Cooldown = 3, -- seconds between captures per player
}

-- Collectible NPCs. An NPC unlocks once the player reaches UnlockFollowers; the Personal Trainer
-- then offers a quiz minigame that pays RewardPerCorrect per correct answer.
type Question = { q: string, options: { string }, answer: number }
type NpcDef = {
	UnlockFollowers: number,
	SpawnOffset: Vector3, -- relative to the Home zone origin
	RewardPerCorrect: number,
	Questions: { Question },
}

Config.Invite = {
	Bonus = 75, -- followers granted to both the inviter and the invited friend (once per friend)
}

Config.Npc = {
	PersonalTrainer = {
		UnlockFollowers = 100,
		SpawnOffset = Vector3.new(-12, 0, 10),
		RewardPerCorrect = 30,
		Questions = {
			{
				q = "Which macronutrient mainly builds muscle?",
				options = { "Protein", "Sugar", "Trans fat" },
				answer = 1,
			},
			{
				q = "How many rest days a week are healthy?",
				options = { "Zero", "One to two", "Never rest" },
				answer = 2,
			},
			{
				q = "Which best supports heart health?",
				options = { "Smoking", "Regular cardio", "Skipping sleep" },
				answer = 2,
			},
		},
	},
} :: { [string]: NpcDef }

return Config
