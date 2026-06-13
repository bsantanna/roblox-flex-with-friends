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
-- system): the Home neighborhood (streets out to +/-228) sits on a grass island ringed by a water moat
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
		Size = 540, -- grassy lot enclosing the grid + perimeter loop (+/-228) with a small margin
		Ground = Enum.Material.Grass,
		Sidewalk = Enum.Material.Concrete,
		Driveway = Enum.Material.Concrete,
		CellSize = 60, -- side of each square lot
		Pitch = 144, -- cell-center spacing (CellSize + the gap: road 24 + a 30-wide walkway each side)
		RoadLine = 72, -- |coord| of the two internal roads per axis (= Pitch/2, the gaps between squares)
		PerimeterLine = 216, -- |coord| of the outer loop road that closes the grid (= Pitch*1.5, no dead ends)
		RoadWidth = 24, -- two-lane asphalt down the middle of each gap (cars pass both ways)
		DrivewayWidth = 10, -- carway from a house to its facing road
		ParkCell = Vector3.new(0, 0, 144), -- the one perimeter square left as grass (no house); = (0, Pitch)
		-- The island and its surroundings (concentric elliptical bands, semi-axes a=X, b=Z): a grass
		-- Plateau in a wide water lake, with an elevated Oval highway hugging the island and joined to
		-- the perimeter loop by ramps. Lake inner = Plateau, outer = Plateau + Moat.Width; Airport and
		-- Beach sit in the lake as their own islands. Sizes in studs.
		Ring = {
			Plateau = { Ax = 391, Az = 352 }, -- grass island bounding ellipse (contains the town)
			Moat = { Width = 2000, Depth = 45, Material = Enum.Material.Water }, -- ~2km lake (room for future islands)
			Oval = {
				Ax = 456, -- elevated highway ellipse (hugs the island: Plateau + ~65, clearing the wide decks)
				Az = 417,
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
				GuardrailOverlap = 8, -- studs each rail panel overlaps its neighbours; like DeckOverlap, closes
				-- the miter slivers where straight panels offset outward on the curve would otherwise gap (fall-through)
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

-- Tree01 forest scattered over the Home island's grass (ForestService clones the uploaded mesh —
-- see assets/manifest.json's scatter entry). Layout is deterministic from Seed, and every site is
-- derived from the Terrain.Home grid, so trees keep off roads, walkways, driveways, houses, and the
-- highway ramps by construction.
Config.Forest = {
	Seed = 7,
	Spacing = 24, -- candidate-site pitch across the green belt
	Jitter = 8, -- random per-site offset, so the grid doesn't read as rows
	ScaleMin = 9, -- mesh is ~1.9 units tall -> trees ~17..25 studs
	ScaleMax = 13,
	RoadMargin = 4, -- extra grass between the walkway edge and the first belt tree
	ShoreMargin = 14, -- keep canopies off the waterline
	RampClearance = 26, -- half-width of the tree-free corridor under each ground-to-highway ramp
	ParkSpacing = 16, -- denser grove on the park square
	ParkInset = 12, -- keeps park sites (incl. their smaller jitter) inside the square's grass
	GardenInset = 23, -- house-garden corner trees: outside the house, clear of the driveway
}

-- Ground road network (RoadService lays these parts over the grass). The lane geometry derives from
-- the grid lines in Config.Terrain.Home (RoadLine / PerimeterLine / RoadWidth); these are the visual
-- tunables: how thick the asphalt sits over the grass, how much each junction rounds its corners, and
-- the lane-marking / curb dimensions.
Config.Roads = {
	Thickness = 0.4, -- asphalt slab height above the grass surface (Y=0)
	Fillet = 10, -- extra radius at each junction so corners curve instead of meeting square; must exceed
	-- ~5 (RoadWidth 24, CurbWidth 30 -> corner tip at sqrt(2)*12) so the disc pokes past the walkway corner
	LaneLineWidth = 0.7, -- width of the dashed centre line
	DashLength = 9, -- length of each centre-line dash
	DashGap = 9, -- gap between dashes
	CurbWidth = 30, -- wide concrete walkway flanking each road edge (room to walk + place buildings)
	CurbHeight = 0.6, -- low enough to step/drive over, high enough to read as a curb
}

-- Ambient cars (TrafficService): decorative, server-driven traffic that random-walks the road network
-- (inner grid + perimeter loop + ramps + elevated ring), staying in lane and stopping for players.
Config.Traffic = {
	Cars = 16, -- cars roaming the whole network
	Speed = 26, -- cruising studs per second
	LaneOffset = 6, -- studs from the road centre into the right-hand lane
	TurnIn = 18, -- studs before a junction where the in-lane curve starts, keeping the turn local so the body stays off walkways
	StopDistance = 16, -- decelerate/stop for a player within this distance ahead, in-lane
	StuckSeconds = 30, -- if a car barely moves for this long, respawn it ahead on the road
	RespawnAhead = 24, -- studs to teleport a stuck car forward along its route (> StopDistance so it clears the blockage)
	BalloonSeconds = 10, -- how long the angry comic balloon shows over a respawned car
}

-- Ambient air traffic (AirTrafficService): a fixed fleet of decorative planes flying a continuous
-- airport lifecycle over the city -- takeoff roll, climb-out, an oval cruise circling the town,
-- descent, landing, taxi and park -- then looping. The horizontal flight track is a single ellipse
-- (Oval) whose +Z extreme is tangent to the runway centre, so takeoff and landing both line up with the
-- runway heading (+X). With Planes staggered evenly across TotalCycle, exactly one plane begins its
-- takeoff every TotalCycle/Planes seconds. The runway runs along X, centred on Zones.Airport.
Config.AirTraffic = {
	Planes = 5, -- fleet size; staggered evenly -> a takeoff every TotalCycle/Planes (60s)
	TotalCycle = 300, -- seconds for one plane's full lifecycle (5 minutes)
	Runway = {
		Length = 500, -- studs along X, centred on Zones.Airport
		Width = 30,
		Y = 1, -- runway driving-surface height above the apron platform
		-- Foundation apron: a built-up concrete island in the lake under the runway + taxiways, so the
		-- runway doesn't float on open water. Sized to also hold the taxi U-turns and the parking spot;
		-- offset toward +Z (the parking side). Depth reaches below the water surface so it reads as solid.
		Apron = { Length = 580, Width = 100, OffsetZ = 20, Depth = 10 },
	},
	GroundY = 2.5, -- plane pivot (belly) height while taxiing / on the runway
	CruiseAltitude = 130, -- plane pivot height while cruising, above Zones.Airport.Y (clears the ring + tall builds)
	Oval = {
		Ax = 320, -- ellipse half-width along X (spans the city's width)
		Az = 280, -- ellipse half-depth along Z; its +Z extreme touches the runway centreline (Az = airport gap)
		Laps = 5, -- cruise laps over the city between climb-out and descent
	},
	Bank = 16, -- degrees of roll banking into the oval (right) turn
	ClimbPitch = 12, -- degrees nose-up through the climb
	DescentPitch = 7, -- degrees nose-down through the descent
	Park = Vector3.new(150, 0, 46), -- parking-apron spot, offset from Zones.Airport
	-- Phase durations (seconds); these sum to TotalCycle. Cruise is the bulk.
	Phases = {
		TakeoffRoll = 7,
		Climb = 18,
		Cruise = 210,
		Descent = 22,
		LandingRoll = 9,
		TaxiPark = 13,
		ParkHold = 13,
		TaxiThreshold = 8,
	},
}

Config.Photo = {
	BaseReward = 25, -- followers per photo
	CoopBonus = 40, -- extra followers per participant when >= 2 players pose together
	CoopRange = 20, -- max studs between participants
	FacingDot = 0, -- min dot of look vectors to count as posing together (>= 0: same-ish way)
	Cooldown = 3, -- seconds between captures per player
}

-- Collectible NPCs. The NPC stands in the world for everyone; reaching UnlockFollowers records
-- the unlock (persisted) and lets the dialog's branch line offer training — a Simon Says
-- pose-memory minigame (SimonSays below). Dialog lines show in a speech bubble over the NPC
-- (visible to all nearby players); {threshold} in a line is replaced with UnlockFollowers.
type SimonSaysDef = {
	StartLength: number, -- arrows in round 1's sequence
	MaxRounds: number, -- the game is cleared after this many rounds
	ShowStepSeconds: number, -- how long each arrow shows (and each pose plays)
	ShowGapSeconds: number, -- blank gap between shown arrows
	RoundDelaySeconds: number, -- pause between a cleared round and the next show phase
	InputTimeoutSeconds: number, -- server-side deadline for a round's whole input phase
	BaseReward: number, -- followers for clearing round 1
	RewardPerRound: number, -- extra followers per round beyond the first
	Arrows: { string }, -- input directions, each a key of Poses
	Poses: { [string]: string }, -- arrow -> animation asset id played on NPC and player
	MoveSeconds: number, -- seconds for the trainer to walk between its post and the arena
	WalkAnimation: string, -- animation asset id played on the NPC while it walks
}
type NpcDialog = {
	Lines: { string }, -- plain lines, advanced with Next
	QualifiedLine: string, -- branch line when the player has the unlock
	GateLine: string, -- branch line when the player does not
	QualifiedChoices: { string }, -- choice 1 starts training, choice 2 leaves
	GateChoices: { string }, -- choice 1 leaves
	TimeoutSeconds: number, -- idle time before the server closes the session
}
type NpcDef = {
	UnlockFollowers: number,
	SpawnPosition: Vector3, -- world position of the floor point the NPC stands on (its post)
	SpawnYaw: number, -- facing, degrees around Y (0 looks -Z/north); also the arena facing
	AvatarUserId: number, -- avatar copied for the NPC model (red-box fallback on failure)
	ArenaPosition: Vector3, -- floor point the trainer walks to for the minigame, then returns from
	Dialog: NpcDialog,
	SimonSays: SimonSaysDef,
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
		SpawnPosition = Vector3.new(-10, 23, -32), -- CentralBuilding first floor, beside the spiral stair
		SpawnYaw = 180, -- face south, toward the entrance forecourt where players approach
		AvatarUserId = 1, -- Roblox's own avatar as the stand-in trainer look
		ArenaPosition = Vector3.new(-10, 23, -50), -- open floor north of the post, in clear view from it
		Dialog = {
			Lines = {
				"Hey, welcome to my gym!",
				"I coach influencers who take their fitness seriously.",
			},
			QualifiedLine = "You've got the following — ready to sweat?",
			GateLine = "Come back when you have {threshold} followers and we'll train.",
			QualifiedChoices = { "Train", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		SimonSays = {
			StartLength = 3,
			MaxRounds = 5,
			ShowStepSeconds = 0.6,
			ShowGapSeconds = 0.25,
			RoundDelaySeconds = 1.2,
			InputTimeoutSeconds = 10,
			BaseReward = 30,
			RewardPerRound = 10,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				-- Roblox default emote animations as stand-in poses; swap for custom
				-- squat/pull-up/jump/yoga uploads later by editing only these ids.
				Left = "rbxassetid://507770239", -- wave
				Up = "rbxassetid://507770677", -- cheer
				Right = "rbxassetid://507770453", -- point
				Down = "rbxassetid://507771019", -- dance
			},
			MoveSeconds = 1.5,
			WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		},
	},
} :: { [string]: NpcDef }

-- Dev cheat console (DevConsoleController): typing Sequence on the keyboard toggles a console
-- that can set the follower count. The server accepts SetFollowers only in Studio.
Config.DevConsole = {
	Sequence = { "Up", "Up", "Down", "Down", "Left", "Right", "Left", "Right", "B", "A" },
	MaxFollowers = 1000000, -- server-side clamp on a cheated value
}

-- The cellphone HUD (PhoneMenuController): a GTA-style phone summoned from a corner button. The
-- phone art is the uploaded Phone01 image; the on-screen buttons (close / left / ok / right) are
-- baked into that art, so the controller overlays invisible click zones on them. Every rect below
-- is { x, y, width, height } in *scale* coordinates relative to the phone image (0..1), measured
-- from the cropped Phone01.png (485x624). Tune these if the art changes.
Config.UI = {
	Phone = {
		Asset = "Phone01", -- key into ReplicatedStorage.Shared.SceneryAssetIds
		AspectRatio = 485 / 624, -- width / height of the cropped art
		HeightScale = 0.46, -- phone height as a fraction of the viewport height
		-- Invisible click zones over the art's baked-in buttons.
		Zones = {
			Close = { 0.666, 0.05, 0.198, 0.152 },
			Left = { 0.10, 0.78, 0.21, 0.15 },
			Ok = { 0.38, 0.75, 0.23, 0.18 },
			Right = { 0.70, 0.78, 0.21, 0.15 },
		},
		-- The teal screen area where carousel content / the social view render.
		Screen = { 0.25, 0.28, 0.58, 0.34 },
		-- Carousel functionalities, in order. `action` is matched in PhoneMenuController.
		Items = {
			{ emoji = "📷", label = "Take Photo", action = "Photo" },
			{ emoji = "👥", label = "Invite Friends", action = "Invite" },
			{ emoji = "🚕", label = "Call a Cab", action = "Cab" },
			{ emoji = "📲", label = "Social Media", action = "Social" },
		},
	},
}

return Config
