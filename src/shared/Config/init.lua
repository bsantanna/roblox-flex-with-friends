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
	Airport = Vector3.new(0, 0, 560),
	Beach = Vector3.new(0, 0, 760),
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

-- Code-generated ground per zone (WorldService paints it at startup). Terrain voxels don't
-- round-trip through Rojo, so the *generating values* live here and the world stays reproducible
-- from src. Lots stay apart so zones don't become walkable-connected (which would bypass the travel
-- system): the Home neighborhood (streets at +/-155) sits on a grass island ringed by a water moat
-- and then a sheer ~100-stud rock mountain (Ring, below) that reaches out to ~+/-420 and walls the
-- town in. Airport (560 away) +/-60 clears the mountain. The rendered top of each slab sits at the
-- zone floor level (Y=0).
--
-- Home is a 3x3 neighborhood grid: nine CellSize squares on a Pitch (cell + road) lattice, so cell
-- centers sit at (i-1)*Pitch for i in {0,1,2} = {-Pitch, 0, Pitch}. The center square is the spawn
-- plaza; the eight surrounding squares hold one house each (one is left as a park, see ParkCell).
-- Roads run along the gaps between squares (lines at +/-RoadLine on both axes) and around the
-- outside (lines at +/-PerimeterLine), so the streets form a closed grid with no dead ends and cars
-- can drive a full loop. Each house gets a driveway to its facing inner road and the rest of its
-- square stays grass (the garden). Ring describes the island/moat/mountain and the elevated oval
-- highway that circles the town (built by WorldService terrain + IslandService parts).
Config.Terrain = {
	Thickness = 8, -- vertical depth of each painted ground slab
	Home = {
		Size = 310, -- grassy lot enclosing the grid + perimeter loop (+/-155) with a small margin
		Ground = Enum.Material.Grass,
		Sidewalk = Enum.Material.Concrete,
		Driveway = Enum.Material.Concrete,
		CellSize = 60, -- side of each square lot
		Pitch = 92, -- cell-center spacing (CellSize + the gap occupied by road + walkways)
		RoadLine = 46, -- |coord| of the two internal roads per axis (the gaps between squares)
		PerimeterLine = 138, -- |coord| of the outer loop road that closes the grid (no dead ends)
		RoadWidth = 24, -- two-lane asphalt down the middle of each gap (cars pass both ways)
		DrivewayWidth = 10, -- carway from a house to its facing road
		ParkCell = Vector3.new(0, 0, 92), -- the one perimeter square left as grass (no house)
		-- The island and its surroundings (concentric elliptical bands, semi-axes a=X, b=Z): a grass
		-- Plateau in a wide water lake, with an elevated Oval highway hugging the island and joined to
		-- the perimeter loop by ramps. Lake inner = Plateau, outer = Plateau + Moat.Width; Airport and
		-- Beach sit in the lake as their own islands. Sizes in studs.
		Ring = {
			Plateau = { Ax = 250, Az = 225 }, -- grass island bounding ellipse (contains the town)
			Moat = { Width = 2000, Depth = 45, Material = Enum.Material.Water }, -- ~2km lake (room for future islands)
			Oval = {
				Ax = 315, -- elevated highway ellipse (hugs the island, clearing the wide decks)
				Az = 290,
				Y = 20, -- elevation above ground
				Width = 24, -- two-lane road, matches the streets
				Thickness = 1,
				DeckOverlap = 16, -- studs each deck chord overlaps its neighbours so the curve has no gaps
				Segments = 72, -- chord segments approximating the ellipse
				PillarEvery = 6, -- a support pillar every Nth segment
				PillarDiameter = 6,
				Ramps = 8, -- ground-to-oval links: 4 sides + 4 corners
				WalkwayWidth = 30, -- wide wood-deck promenade flanking each side (room for buildings)
				GuardrailHeight = 9, -- taller than a player + jump apex, so nobody jumps off the deck
				GuardrailThickness = 0.5,
				ViewDeckEvery = 9, -- a panoramic view deck every Nth segment (9 -> one per 45 degrees)
				ViewDeckDepth = 16, -- how far each view deck juts out past the outer guardrail
			},
		},
	},
	Airport = {
		Size = 120, -- tarmac apron
		Ground = Enum.Material.Asphalt,
	},
	Beach = {
		Size = 120, -- sand, with ocean water painted just beyond the far (+Z) edge
		Ground = Enum.Material.Sand,
		Water = Enum.Material.Water,
		WaterDepth = 60,
	},
}

-- Ground road network (RoadService lays these parts over the grass). The lane geometry derives from
-- the grid lines in Config.Terrain.Home (RoadLine / PerimeterLine / RoadWidth); these are the visual
-- tunables: how thick the asphalt sits over the grass, how much each junction rounds its corners, and
-- the lane-marking / curb dimensions.
Config.Roads = {
	Thickness = 0.4, -- asphalt slab height above the grass surface (Y=0)
	Fillet = 4, -- extra radius at each junction so corners curve instead of meeting square
	LaneLineWidth = 0.7, -- width of the dashed centre line
	DashLength = 9, -- length of each centre-line dash
	DashGap = 9, -- gap between dashes
	CurbWidth = 8, -- concrete walkway flanking each road edge
	CurbHeight = 0.6, -- low enough to step/drive over, high enough to read as a curb
}

-- Ambient cars (TrafficService): decorative, server-driven traffic that random-walks the road network
-- (inner grid + perimeter loop + ramps + elevated ring), staying in lane and stopping for players.
Config.Traffic = {
	Cars = 16, -- cars roaming the whole network
	Speed = 26, -- cruising studs per second
	LaneOffset = 6, -- studs from the road centre into the right-hand lane
	StopDistance = 16, -- decelerate/stop for a player within this distance ahead, in-lane
	StuckSeconds = 30, -- if a car barely moves for this long, respawn it ahead on the road
	RespawnAhead = 24, -- studs to teleport a stuck car forward along its route (> StopDistance so it clears the blockage)
	BalloonSeconds = 10, -- how long the angry comic balloon shows over a respawned car
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

-- Offline follower decay applied on join. Off by default until balanced with real playtest data.
Config.Decay = {
	Enabled = false,
	PerDay = 10, -- followers lost per full day offline
	MaxLoss = 50, -- cap on a single return's loss
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
