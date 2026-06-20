--!strict
-- Tunable values for Flex-with-Friends. Magic numbers live here, not in services.
-- See doc/002_implementation_plan.md.

local Types = require(script.Parent.Types)

local Config = {}

-- DataStore name for player profiles. Bump the suffix to reset all saved data during dev.
-- v2: Friends changed from a { string } list of befriended ids to a { [id]: OutfitData } map.
Config.DataStoreName = "PlayerData_v2"

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
	Friends = {},
} :: Types.ProfileData

-- World zone origins. MVP keeps Home/Airport/Beach as zones in one place; "travel"
-- repositions the player between these origins (Airport is the transit waypoint where the
-- boarding minigame runs).
Config.Zones = {
	Home = Vector3.new(0, 0, 0),
	Airport = Vector3.new(0, 0, 560),
	Beach = Vector3.new(0, 0, 760),
	Farm = Vector3.new(320, 0, -140), -- zone origin; matches Config.Farm.Center
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

-- The farm: a fenced paddock on the Home island's north-east green belt (FarmService builds it). The
-- pen footprint was chosen in Studio to sit on grass, clear of the perimeter road, the elevated ring
-- highway/walkway, and the shoreline; it encloses a few of the belt's scattered trees as pasture
-- shade. Center is Home-relative (grass surface Y=0); Size is the X-by-Z interior. The white
-- post-and-rail fence is built from primitives (like the gym equipment). Animals are cloned from
-- ReplicatedStorage.Shared.FarmModels templates and gently wander inside the rails; until those
-- templates exist the populate step skips, so a pending model never breaks boot.
Config.Farm = {
	Center = Vector3.new(320, 0, -140),
	Size = Vector2.new(64, 64), -- interior X by Z; gate opens on the town-facing west side
	Fence = {
		PostSpacing = 8, -- studs between posts along each side
		PostSize = Vector3.new(0.6, 3.4, 0.6),
		RailHeights = { 1.1, 2.4 }, -- centre height of each horizontal rail above the grass
		RailThickness = 0.35, -- depth of a rail board (across the fence line)
		RailBoardHeight = 0.55, -- vertical height of a rail board
		Color = Color3.fromRGB(244, 244, 238), -- white wood
		Material = Enum.Material.WoodPlanks,
		GateWidth = 10, -- width of the opening left in the west side
		ClearanceRadius = 5, -- studs within which trees near the fence perimeter are removed
	},
	Animals = {
		Seed = 11, -- deterministic spawn points + wander, like the forest
		Roster = { -- Kind names a Species below; only built species spawn (others are skipped)
			{ Kind = "Cow", Count = 3 },
			{ Kind = "Sheep", Count = 3 },
			{ Kind = "Chicken", Count = 2 },
		},
		WanderSpeed = 4, -- studs/second while walking to a target
		TurnSpeed = 5, -- radians/second the animal yaws toward its heading
		PauseMin = 2, -- seconds idled between walks
		PauseMax = 6,
		EdgeMargin = 6, -- keep animals this far inside the rails
		TreeClearance = 5, -- keep spawn/target points this far from a pasture tree trunk
		TreeRadius = 2.2, -- trunk keep-out: an animal's centre stays TreeRadius + its body radius from a trunk
		Separation = 1.6, -- steering weight pushing an animal away from nearby trees/animals
		SeparationIterations = 3, -- hard push-out passes per frame that resolve any tree/animal overlap
		-- Each animal is assembled in code from uploaded part meshes (asset ids in SceneryAssetIds):
		-- a body root plus N legs, all anchored, animated kinematically (legs swing for the walk, a
		-- gentle body bob). Hip offsets are in template studs relative to the body part centre and were
		-- tuned in Studio; Scale multiplies the whole rig. Forward is +X, up +Y, side ±Z (the GLB import
		-- maps Blender X/Z/-Y to Roblox X/Y/Z).
		Species = {
			Cow = {
				Body = "CowBody",
				Leg = "CowLeg",
				Legs = 4,
				Scale = 1.1,
				BodyColor = Color3.fromRGB(255, 255, 255), -- white: the body mesh carries baked vertex colours (eyes, muzzle, spots)
				LegColor = Color3.fromRGB(250, 250, 250), -- legs carry their own white+hoof vertex colours
				Material = Enum.Material.SmoothPlastic,
				HipForwardFront = 0.9, -- +X offset of the front legs from the body centre
				HipForwardBack = -1.0, -- +X offset of the back legs
				HipSide = 0.72, -- ±Z offset of each leg pair
				HipDown = 1.2, -- -Y drop from the body centre to where the legs attach
				WalkSwing = 0.4, -- radians peak fore/aft leg swing while walking
				WalkFreq = 2.5, -- gait cycles per second at full walk speed
				BobAmplitude = 0.12, -- studs the body bobs vertically
				BobFreq = 2.2, -- bob cycles per second
			},
			Sheep = {
				Body = "SheepBody",
				Leg = "SheepLeg",
				Legs = 4,
				Scale = 0.8,
				BodyColor = Color3.fromRGB(255, 255, 255), -- vertex colours carry wool/face/eyes
				LegColor = Color3.fromRGB(92, 80, 70), -- dark tan legs
				Material = Enum.Material.SmoothPlastic,
				HipForwardFront = 0.7,
				HipForwardBack = -0.8,
				HipSide = 0.6,
				HipDown = 1.0,
				WalkSwing = 0.4,
				WalkFreq = 2.8,
				BobAmplitude = 0.07,
				BobFreq = 2.6,
			},
			Chicken = {
				Body = "ChickenBody",
				Leg = "ChickenLeg",
				Legs = 2,
				Scale = 1.0,
				BodyColor = Color3.fromRGB(255, 255, 255), -- vertex colours carry beak/comb/eyes
				LegColor = Color3.fromRGB(235, 150, 40), -- orange legs
				Material = Enum.Material.SmoothPlastic,
				HipForwardFront = -0.1, -- both legs sit just under the body centre
				HipForwardBack = -0.1,
				HipSide = 0.2,
				HipDown = 0.5,
				WalkSwing = 0.5,
				WalkFreq = 4.0,
				BobAmplitude = 0.05,
				BobFreq = 3.5,
			},
		},
	},
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
	Zone: string, -- which World.<Zone> folder the NPC is parented to
	UnlockFollowers: number,
	SpawnPosition: Vector3, -- world position of the floor point the NPC stands on (its post)
	SpawnYaw: number, -- facing, degrees around Y (0 looks -Z/north); also the arena facing
	AvatarUserId: number, -- avatar copied for the NPC model (red-box fallback on failure)
	ArenaPosition: Vector3, -- floor point the NPC walks to for its minigame, then returns from
	MoveSeconds: number, -- seconds for the NPC to walk between its post and the arena
	WalkAnimation: string, -- animation asset id played on the NPC while it walks
	Instructions: string, -- pre-game rules the NPC explains (speech bubble + client Start prompt)
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

-- Generic NPC-minigame framework tunables (MinigameService). Before any minigame plays, the NPC
-- walks to its arena and runs a shared pre-game flow: a green ready-zone the player must step into,
-- then the NPC explains the rules and waits for a Start confirmation. Per-NPC/per-game values
-- (arena, motion, instructions, rewards) live under Config.Npc; these are the cross-game defaults.
Config.Minigame = {
	ReadyTimeoutSeconds = 30, -- abort (NPC walks home) if the player never reaches the ready-zone
	ConfirmTimeoutSeconds = 30, -- abort if the player never confirms the instructions
	ReadyZone = {
		Radius = 4, -- entry-detection + visual radius, studs
		Offset = 6, -- studs in front of the NPC (along its facing) where the disc sits
		Height = 0.1, -- disc thickness above the floor
		Color = Color3.fromRGB(80, 230, 110), -- bright green
	},
}

Config.Npc = {
	PersonalTrainer = {
		Zone = "Home",
		UnlockFollowers = 100,
		SpawnPosition = Vector3.new(-10, 23, -32), -- CentralBuilding first floor, beside the spiral stair
		SpawnYaw = 180, -- face south, toward the entrance forecourt where players approach
		AvatarUserId = 1, -- Roblox's own avatar as the stand-in trainer look
		ArenaPosition = Vector3.new(-10, 23, -50), -- open floor north of the post, in clear view from it
		MoveSeconds = 1.5, -- seconds for the trainer to walk between its post and the arena
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Simon Says! Watch the moves I make, then repeat them in order with the on-screen"
			.. " buttons or the arrow keys. Clear every round to bank followers. Step on the mark and hit Start!",
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
		},
	},
	Farmer = {
		Zone = "Farm",
		UnlockFollowers = 200,
		SpawnPosition = Vector3.new(282, 0, -140), -- outside the west fence, near the gate
		SpawnYaw = 90, -- face east, toward the farm entrance
		AvatarUserId = 1, -- Roblox's own avatar as stand-in look
		ArenaPosition = Vector3.new(310, 0, -140), -- inside the pen, along the same Z axis
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Alright! We got work to do on this farm. I'll show the chore moves —\n  repeat them in order with the on-screen buttons. Clear every round to earn followers!",
		Dialog = {
			Lines = {
				"Howdy! I'm the farmer here.",
				"This farm's been a mess since I left it... I need a hand.",
			},
			QualifiedLine = "Help me do the farm chores? I'll show the moves!",
			GateLine = "I'm looking for folks with at least {threshold} followers to help me work this farm.",
			QualifiedChoices = { "Show me!", "Maybe later" },
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
			BaseReward = 35,
			RewardPerRound = 12,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				Left = "rbxassetid://507770239",
				Up = "rbxassetid://507770677",
				Right = "rbxassetid://507770453",
				Down = "rbxassetid://507771019",
			},
		},
	},
} :: { [string]: NpcDef }

-- Gym equipment on the CentralBuilding's opened first floor. GymService builds each station from
-- primitives (like SceneryService); the station is placed at an absolute world position on the
-- first-floor surface (y=23) facing Yaw degrees (0 looks -Z). Positions are tuned by looking in
-- Studio. The Phase-2 NPC spawner reads this same table to post a gym-goer at each station.
type GymStation = { Kind: string, Position: Vector3, Yaw: number }
Config.Gym = {
	Stations = {
		-- Cardio, nearest the spiral-stair entrance (stair occupies X[-33,-14], Z[-37,-19]); the two
		-- centre columns are left open here as the walk-in corridor. Treadmills/bikes face south
		-- (Yaw 180) so their consoles greet players coming up the stair.
		{ Kind = "ExerciseBike", Position = Vector3.new(-50, 23, -47), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-39, 23, -47), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-5, 23, -47), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-39, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-5, 23, -59), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-39, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-28, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-16, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-5, 23, -71), Yaw = 180 },
		{ Kind = "Treadmill", Position = Vector3.new(-50, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-39, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-28, 23, -83), Yaw = 180 },
		{ Kind = "ExerciseBike", Position = Vector3.new(-16, 23, -83), Yaw = 180 },
		{ Kind = "WaterCooler", Position = Vector3.new(-5, 23, -83), Yaw = 0 },
		-- Strength, mid hall.
		{ Kind = "WeightBench", Position = Vector3.new(-50, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-39, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-28, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-16, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-5, 23, -95), Yaw = 0 },
		{ Kind = "WeightBench", Position = Vector3.new(-50, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-39, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-28, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-16, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-5, 23, -107), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-50, 23, -119), Yaw = 0 },
		{ Kind = "DumbbellRack", Position = Vector3.new(-39, 23, -119), Yaw = 0 },
		-- Floor / stretching, north end.
		{ Kind = "Mat", Position = Vector3.new(-28, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-16, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-5, 23, -119), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-50, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-39, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-28, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-16, 23, -131), Yaw = 0 },
		{ Kind = "Mat", Position = Vector3.new(-5, 23, -131), Yaw = 0 },
		-- Water coolers framing the entrance on the two side pads.
		{ Kind = "WaterCooler", Position = Vector3.new(-48, 23, -28), Yaw = 0 },
		{ Kind = "WaterCooler", Position = Vector3.new(-6, 23, -28), Yaw = 0 },
		-- Mirror walls flush against the west wall, facing east into the hall (clear of the entrance).
		{ Kind = "MirrorWall", Position = Vector3.new(-56, 23, -75), Yaw = 90 },
		{ Kind = "MirrorWall", Position = Vector3.new(-56, 23, -110), Yaw = 90 },
	} :: { GymStation },
}

-- The gym friends (12 NPCs, 4 types x 3) and their AI/dialog tunables live in a submodule to keep
-- this file readable; GymFriendService spawns them and runs their branching dialog.
Config.GymFriends = require(script.GymFriends)

-- The "default lego block" look every customizable NPC wears the first time you meet it, before
-- you create their outfit: a neutral grey blocky avatar, no clothing or accessories. Stored as the
-- friend's OutfitData until the player customizes it. BefriendReward (Config.GymFriends) is awarded
-- once when the outfit is first saved.
Config.DefaultNpcOutfit = {
	BodyColor = 0xA3A3A3, -- neutral grey "unpainted block"
	Shirt = 0,
	Pants = 0,
	Accessories = {},
} :: Types.OutfitData

-- The first-meeting "create your friend" editor. The body-colour palette below is applied as the
-- single block colour; ClothingSlots and AccessorySlots drive the AvatarEditorService catalog tabs the
-- player browses to dress the friend. The server validates every saved value (BodyColor against this
-- list, and each clothing/accessory id against its slot's catalog category) so a tampered client can't
-- set an arbitrary look. Each accessory slot equips into one HumanoidDescription <Slot>Accessory.
type ClothingSlot = { Label: string, Category: Enum.AvatarAssetType, Field: string }
type AccessorySlot = { Label: string, Category: Enum.AvatarAssetType, Type: Enum.AccessoryType }
Config.OutfitEditor = {
	BodyColors = {
		0xA3A3A3, -- grey
		0xD9B38C, -- tan
		0xF2CDA0, -- light skin
		0x8C5A3B, -- brown
		0xE05A5A, -- red
		0xE0913B, -- orange
		0xE8D44D, -- yellow
		0x5AB85A, -- green
		0x4DA6E0, -- blue
		0x8C5AE0, -- purple
		0xE05AAE, -- pink
		0x2E2E2E, -- charcoal
	} :: { number },
	-- Classic clothing tabs: the catalog category to browse -> the OutfitData field it fills.
	ClothingSlots = {
		{ Label = "Shirt", Category = Enum.AvatarAssetType.Shirt, Field = "Shirt" },
		{ Label = "Pants", Category = Enum.AvatarAssetType.Pants, Field = "Pants" },
	} :: { ClothingSlot },
	-- Accessory tabs: the catalog category to browse -> the slot it equips into (one item per slot).
	AccessorySlots = {
		{ Label = "Hats", Category = Enum.AvatarAssetType.Hat, Type = Enum.AccessoryType.Hat },
		{ Label = "Hair", Category = Enum.AvatarAssetType.HairAccessory, Type = Enum.AccessoryType.Hair },
		{ Label = "Face", Category = Enum.AvatarAssetType.FaceAccessory, Type = Enum.AccessoryType.Face },
		{ Label = "Neck", Category = Enum.AvatarAssetType.NeckAccessory, Type = Enum.AccessoryType.Neck },
		{ Label = "Shoulder", Category = Enum.AvatarAssetType.ShoulderAccessory, Type = Enum.AccessoryType.Shoulder },
		{ Label = "Front", Category = Enum.AvatarAssetType.FrontAccessory, Type = Enum.AccessoryType.Front },
		{ Label = "Back", Category = Enum.AvatarAssetType.BackAccessory, Type = Enum.AccessoryType.Back },
		{ Label = "Waist", Category = Enum.AvatarAssetType.WaistAccessory, Type = Enum.AccessoryType.Waist },
	} :: { AccessorySlot },
}

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
