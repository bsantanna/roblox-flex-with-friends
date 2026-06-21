--!strict
-- NPC-minigame framework defaults (MinigameService) and the collectible-NPC roster (NpcService,
-- DialogService). Each NPC stands in the world; reaching UnlockFollowers records the unlock and lets
-- the dialog branch into a Simon Says pose-memory minigame.

local Npc = {}

-- Generic NPC-minigame framework tunables (MinigameService). Before any minigame plays, the NPC
-- walks to its arena and runs a shared pre-game flow: a green ready-zone the player must step into,
-- then the NPC explains the rules and waits for a Start confirmation. Per-NPC/per-game values
-- (arena, motion, instructions, rewards) live under Config.Npc; these are the cross-game defaults.
Npc.Minigame = {
	ReadyTimeoutSeconds = 30, -- abort (NPC walks home) if the player never reaches the ready-zone
	ConfirmTimeoutSeconds = 30, -- abort if the player never confirms the instructions
	ReadyZone = {
		Radius = 4, -- entry-detection + visual radius, studs
		Offset = 6, -- studs in front of the NPC (along its facing) where the disc sits
		Height = 0.1, -- disc thickness above the floor
		Color = Color3.fromRGB(80, 230, 110), -- bright green
	},
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
	StepLeadSeconds: number, -- pause after showing step number before the arrow lights up
	RoundDelaySeconds: number, -- pause between a cleared round and the next show phase
	InputTimeoutSeconds: number, -- server-side deadline for a round's whole input phase
	BaseReward: number, -- followers for clearing round 1
	RewardPerRound: number, -- extra followers per round beyond the first
	Arrows: { string }, -- input directions, each a key of Poses
	Poses: { [string]: string }, -- arrow -> animation asset id played on NPC and player
}
type RockPaperScissorsDef = {
	WinsNeeded: number, -- first to this many round wins takes the match (ties replay)
	InputTimeoutSeconds: number, -- server-side deadline for the player to pick a hand
	ReelSeconds: number, -- how long the client reel spins before locking on the opponent's hand
	RevealSeconds: number, -- pause showing the result before the next round
	RoundDelaySeconds: number, -- pause before a round's pick phase opens
	BaseReward: number, -- followers for each round the player wins
	MatchBonus: number, -- extra followers for winning the match
	Choices: { string }, -- canonical move keys (each a key of Emoji/Poses)
	Emoji: { [string]: string }, -- move -> emoji shown to the player
	Poses: { [string]: string }, -- move -> animation asset id played on the NPC at reveal
}
type QuickDrawDef = {
	Rounds: number, -- draws to win in a row; clearing all awards the bonus + trophy
	MinDelaySeconds: number, -- shortest suspense before the DRAW signal
	MaxDelaySeconds: number, -- longest suspense before the DRAW signal
	ReactWindowSeconds: number, -- press within this many seconds of DRAW to win the round (server-timed)
	RevealSeconds: number, -- pause showing a round's result before the next
	RoundDelaySeconds: number, -- pause before a round's countdown begins
	BaseReward: number, -- followers for each draw the player wins
	MatchBonus: number, -- extra followers for winning every draw
	DrawPose: string, -- animation asset id played on the NPC at the DRAW signal
}
-- Sidewalk/citizen walk config for NPCs that patrol the town (not doing chores).
type CitizenWalkDef = {
	Waypoints: { Vector3 }, -- ordered sidewalk waypoints the NPC visits in random order
	WalkSpeed: number, -- studs per second (3 is a casual pace)
	PauseMin: number, -- min seconds to pause at each waypoint
	PauseMax: number, -- max seconds to pause at each waypoint
}
type NpcDialog = {
	Lines: { string }, -- plain lines, advanced with Next
	QualifiedLine: string, -- branch line when the player has the unlock
	GateLine: string, -- branch line when the player does not
	QualifiedChoices: { string }, -- choice 1 starts training, choice 2 leaves
	GateChoices: { string }, -- choice 1 leaves
	TimeoutSeconds: number, -- idle time before the server closes the session
}
-- Fixed, code-configured profession outfit applied to the NPC on spawn (DialogService). The base
-- model comes from AvatarUserId; this dresses it. Rigid headwear goes through HumanoidDescription's
-- HatAccessory string property; layered clothing (shirts/pants/jackets) through SetAccessories. These
-- are real Marketplace asset ids; not player-editable (that's the gym friends, a separate system).
type NpcOutfit = {
	Hats: { number }, -- rigid headwear asset ids (HumanoidDescription.HatAccessory); {} for none
	Layered: { { AssetId: number, Type: Enum.AccessoryType } }, -- layered clothing; {} for none
}
type NpcDef = {
	Zone: string, -- which World.<Zone> folder the NPC is parented to
	UnlockFollowers: number,
	RequiredTrophies: { string }?, -- trophy ids the player must own to unlock (in addition to followers)
	Outfit: NpcOutfit?, -- profession look applied on spawn (omitted = bare AvatarUserId avatar)
	SpawnPosition: Vector3, -- world position of the floor point the NPC stands on (its post)
	SpawnYaw: number, -- facing, degrees around Y (0 looks -Z/north); also the arena facing
	AvatarUserId: number, -- avatar copied for the NPC model (red-box fallback on failure)
	ArenaPosition: Vector3, -- floor point the NPC walks to for its minigame, then returns from
	MoveSeconds: number, -- seconds for the NPC to walk between its post and the arena
	WalkAnimation: string, -- animation asset id played on the NPC while it walks
	Instructions: string, -- pre-game rules the NPC explains (speech bubble + client Start prompt)
	Dialog: NpcDialog,
	SimonSays: SimonSaysDef?, -- present iff this NPC hosts the Simon Says minigame
	RockPaperScissors: RockPaperScissorsDef?, -- present iff this NPC hosts the Rock-Paper-Scissors minigame
	QuickDraw: QuickDrawDef?, -- present iff this NPC hosts the Quick Draw reaction minigame
	Chore: {
		HomePosition: Vector3, -- spawn / idle position where the NPC wanders from
		Waypoints: { { position: Vector3, animationId: string, delaySeconds: number } }, -- ordered chore points
	}?, -- present iff this NPC does farm chore patrol
	CitizenWalk: CitizenWalkDef?, -- present iff this NPC patrols the town sidewalks
}

Npc.Npc = {
	PersonalTrainer = {
		Zone = "Home",
		UnlockFollowers = 100,
		SpawnPosition = Vector3.new(-10, 23, -32), -- CentralBuilding first floor, beside the spiral stair
		SpawnYaw = 180, -- face south, toward the entrance forecourt where players approach
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- gym look: sweatband + athletic tank top
			Hats = { 12871624213 }, -- Red Bandana Headband
			Layered = { { AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt } }, -- White Tank Top
		},
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
			StartLength = 1,
			MaxRounds = 3,
			ShowStepSeconds = 2.5,
			ShowGapSeconds = 0.6,
			StepLeadSeconds = 1.0,
			RoundDelaySeconds = 1.5,
			InputTimeoutSeconds = 20,
			BaseReward = 50,
			RewardPerRound = 25,
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
		-- PersonalTrainer patrols the gym area.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-10, 23, -32), -- spawn / post
				Vector3.new(-10, 23, -50), -- north walk
				Vector3.new(5, 23, -41), -- east walk
				Vector3.new(-25, 23, -41), -- west walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Farmer = {
		Zone = "Farm",
		UnlockFollowers = 200,
		SpawnPosition = Vector3.new(282, 0, -140), -- outside the west fence, near the gate
		SpawnYaw = 90, -- face east, toward the farm entrance
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- farmhand look: straw hat + denim overalls
			Hats = { 18358376553 }, -- Straw Hat
			Layered = { { AssetId = 127189956586914, Type = Enum.AccessoryType.Pants } }, -- Classic Blue Denim Overalls
		},
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
			StartLength = 1,
			MaxRounds = 3,
			ShowStepSeconds = 2.5,
			ShowGapSeconds = 0.6,
			StepLeadSeconds = 1.0,
			RoundDelaySeconds = 1.5,
			InputTimeoutSeconds = 20,
			BaseReward = 50,
			RewardPerRound = 25,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				Left = "rbxassetid://507770239",
				Up = "rbxassetid://507770677",
				Right = "rbxassetid://507770453",
				Down = "rbxassetid://507771019",
			},
		},
		-- Farm chore patrol: the Farmer wanders the paddock doing chores (wood-chopping, watering,
		-- feeding, fence-mending, harvesting). Animations use Roblox default emote IDs as placeholders;
		-- upload profession-specific animations and replace the IDs.
		Chore = {
			HomePosition = Vector3.new(282, 0, -140), -- spawn / idle position
			Waypoints = {
				{ position = Vector3.new(295, 0, -135), animationId = "rbxassetid://180734708", delaySeconds = 3 }, -- wood chop (axe swing)
				{ position = Vector3.new(310, 0, -145), animationId = "rbxassetid://507770239", delaySeconds = 2.5 }, -- watering (wave/can)
				{ position = Vector3.new(305, 0, -130), animationId = "rbxassetid://507770453", delaySeconds = 2 }, -- feeding (point/throw)
				{ position = Vector3.new(290, 0, -148), animationId = "rbxassetid://507770677", delaySeconds = 3 }, -- fence mend (cheer/lift)
				{ position = Vector3.new(315, 0, -132), animationId = "rbxassetid://180734708", delaySeconds = 2.5 }, -- harvest (chop)
			},
		},
	},
	Cowboy = {
		Zone = "Farm",
		UnlockFollowers = 0, -- no follower gate: anyone can challenge the cowboy
		SpawnPosition = Vector3.new(300, 0, -120), -- inside the paddock, on grass north-east of the Farmer
		SpawnYaw = 90, -- same facing as the Farmer (toward the pen approach)
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- cowboy look: a wide-brim cowboy hat
			Hats = { 10473499273 }, -- Cowboy Hat
			Layered = {},
		},
		ArenaPosition = Vector3.new(322, 0, -120), -- a short walk to clear pen floor for the duel
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Howdy, partner! It's a game o' chance — Rock, Paper, Scissors.\n  Pick yer hand, I'll throw mine. Best two outta three takes the pot. Step on the mark when yer ready!",
		Dialog = {
			Lines = {
				"Well howdy there, partner!",
				"Name's Cole — I wrangle cattle by day an' play Roshambo by night.",
			},
			QualifiedLine = "Fancy a friendly game o' Rock, Paper, Scissors? Best two outta three!",
			GateLine = "Mosey on over anytime fer a game, partner.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Howdy" },
			TimeoutSeconds = 30,
		},
		RockPaperScissors = {
			WinsNeeded = 2,
			InputTimeoutSeconds = 15,
			ReelSeconds = 2,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1,
			BaseReward = 40,
			MatchBonus = 80,
			Choices = { "Rock", "Paper", "Scissors" },
			Emoji = {
				Rock = "\u{270A}", -- raised fist
				Paper = "\u{270B}", -- raised hand
				Scissors = "\u{270C}\u{FE0F}", -- victory hand
			},
			Poses = {
				-- Roblox default emotes as stand-in throws; swap for custom uploads later.
				Rock = "rbxassetid://507770677", -- cheer (fist up)
				Paper = "rbxassetid://507770239", -- wave (open hand)
				Scissors = "rbxassetid://507770453", -- point
			},
		},
		-- Farm chore patrol: the Cowboy rides around the paddock doing ranch work (saddle, lasso,
		-- resting, repairs). Animations use Roblox default emote IDs as placeholders.
		Chore = {
			HomePosition = Vector3.new(300, 0, -120), -- spawn / idle position
			Waypoints = {
				{ position = Vector3.new(315, 0, -125), animationId = "rbxassetid://180734708", delaySeconds = 3 }, -- saddle tightening (axe swing)
				{ position = Vector3.new(325, 0, -130), animationId = "rbxassetid://507770453", delaySeconds = 2 }, -- lasso throw (point)
				{ position = Vector3.new(310, 0, -115), animationId = "rbxassetid://507770239", delaySeconds = 2.5 }, -- resting by fence (wave)
				{ position = Vector3.new(295, 0, -110), animationId = "rbxassetid://180734708", delaySeconds = 2.5 }, -- repairs (axe swing)
			},
		},
	},
	Postman = {
		Zone = "Home",
		UnlockFollowers = 0, -- no follower gate: anyone can challenge the postman
		SpawnPosition = Vector3.new(40, 0, -40), -- central plaza area, near the town green
		SpawnYaw = 180, -- face south, toward the approach from the spawn plaza
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- postal look: a peaked uniform officer cap
			Hats = { 13383061629 }, -- White Star Line Officer Cap
			Layered = {},
		},
		ArenaPosition = Vector3.new(60, 0, -40), -- a short walk north for the duel
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "G'day! I deliver the mail all across town. Bet ya can't beat me at Rock, Paper, Scissors!\n  Best two outta three. Step on the mark when yer ready!",
		Dialog = {
			Lines = {
				"G'day! I'm the town postman.",
				"I deliver mail all across the neighborhood — and I play a mean game o' Roshambo!",
			},
			QualifiedLine = "Fancy a quick game o' Rock, Paper, Scissors? Best two outta three!",
			GateLine = "Catch me anytime — I'm always on the route.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "G'day" },
			TimeoutSeconds = 30,
		},
		RockPaperScissors = {
			WinsNeeded = 2,
			InputTimeoutSeconds = 15,
			ReelSeconds = 2,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1,
			BaseReward = 40,
			MatchBonus = 80,
			Choices = { "Rock", "Paper", "Scissors" },
			Emoji = {
				Rock = "\u{270A}", -- raised fist
				Paper = "\u{270B}", -- raised hand
				Scissors = "\u{270C}\u{FE0F}", -- victory hand
			},
			Poses = {
				-- Roblox default emotes as stand-in throws; swap for custom uploads later.
				Rock = "rbxassetid://507770677", -- cheer (fist up)
				Paper = "rbxassetid://507770239", -- wave (open hand)
				Scissors = "rbxassetid://507770453", -- point
			},
		},
		-- Postman patrols the central plaza sidewalks.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(40, 0, -40), -- spawn / post
				Vector3.new(50, 0, -30), -- east walk
				Vector3.new(60, 0, -40), -- north walk
				Vector3.new(50, 0, -50), -- west walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Sage = {
		Zone = "Home", -- the forest is the Home island's green belt; the sage sits in a tree clearing
		UnlockFollowers = 250,
		RequiredTrophies = { "farmer_farmhand" }, -- must have earned the Farmer's Fresh Milk first
		SpawnPosition = Vector3.new(-116, 0, -276), -- grass clearing ringed by green-belt trees
		SpawnYaw = 180, -- face +Z, toward the walkway where players approach the grove
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- mystic look: a hood and flowing robe
			Hats = { 14760815405 }, -- Wizard Hood
			Layered = { { AssetId = 14133900767, Type = Enum.AccessoryType.Jacket } }, -- Long White Robes
		},
		ArenaPosition = Vector3.new(-116, 0, -266), -- a few steps toward the approach, still on grass
		MoveSeconds = 1.5,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Quick Draw! Watch me closely. The instant you see DRAW, strike — tap the button or"
			.. " hit Space. Hesitate and you lose the round. Win every draw to earn my favor. Step on the mark when you're ready!",
		Dialog = {
			Lines = {
				"Ah... a traveler ventures into my grove.",
				"I am the old sage of these woods, and I test the swiftness of those who seek me.",
			},
			QualifiedLine = "Your hand is proven and your fame precedes you. Care to test your reflexes?",
			GateLine = "Return when you carry the Farmer's Fresh Milk and have {threshold} followers — then we shall duel.",
			QualifiedChoices = { "Draw!", "Not now" },
			GateChoices = { "I will return" },
			TimeoutSeconds = 30,
		},
		QuickDraw = {
			Rounds = 3,
			MinDelaySeconds = 1.5,
			MaxDelaySeconds = 3.5,
			ReactWindowSeconds = 0.8, -- server-timed; generous enough to absorb typical network latency
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1.0,
			BaseReward = 45, -- per draw won
			MatchBonus = 85, -- all three draws -> 3*45 + 85 = 220 total
			DrawPose = "rbxassetid://507770453", -- point emote as the draw gesture (placeholder default)
		},
		-- Sage patrols the forest clearing area.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-116, 0, -276), -- spawn / post
				Vector3.new(-116, 0, -266), -- north walk
				Vector3.new(-126, 0, -276), -- west walk
				Vector3.new(-116, 0, -286), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 4, -- min seconds between waypoints
			PauseMax = 10, -- max seconds between waypoints
		},
	},
	-- Town-professions chain. Each gates on a previous NPC's trophy (RequiredTrophies) plus a rising
	-- follower threshold, so they unlock in order. Positions are starting values seated on the Home
	-- plateau (Y=0); verified/tuned in Studio. Profession headwear is filled in the Studio catalog pass.
	TaxiDriver = {
		Zone = "Home",
		UnlockFollowers = 300,
		RequiredTrophies = { "personal_trainer_strength" }, -- the gym trainer's Strength
		Outfit = { -- cabbie look: a flat newsboy cap
			Hats = { 78174478860906 }, -- Black Shelby Vintage Cap
			Layered = {},
		},
		SpawnPosition = Vector3.new(172, 0, -172), -- grass shoulder by the NE ramp, clear of the road
		SpawnYaw = 90, -- face the open grass toward town
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(160, 0, -172), -- a few steps along the grass
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Hop in! Quick game while the meter runs — Rock, Paper, Scissors.\n  Pick yer hand, best two outta three. Step on the mark when yer ready!",
		Dialog = {
			Lines = {
				"Need a lift? I'm the town cabbie.",
				"I know every street in this neighborhood — and I never lose a fare's bet.",
			},
			QualifiedLine = "Fancy a quick game o' Rock, Paper, Scissors while we wait? Best two outta three!",
			GateLine = "Come back with {threshold} followers and the trainer's badge, and we'll play for the ride.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		RockPaperScissors = {
			WinsNeeded = 2,
			InputTimeoutSeconds = 15,
			ReelSeconds = 2,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1,
			BaseReward = 40,
			MatchBonus = 80,
			Choices = { "Rock", "Paper", "Scissors" },
			Emoji = {
				Rock = "\u{270A}", -- raised fist
				Paper = "\u{270B}", -- raised hand
				Scissors = "\u{270C}\u{FE0F}", -- victory hand
			},
			Poses = {
				Rock = "rbxassetid://507770677", -- cheer (fist up)
				Paper = "rbxassetid://507770239", -- wave (open hand)
				Scissors = "rbxassetid://507770453", -- point
			},
		},
		-- TaxiDriver patrols the NE ramp area.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(172, 0, -172), -- spawn / post
				Vector3.new(160, 0, -160), -- along the ramp
				Vector3.new(150, 0, -172), -- east walk
				Vector3.new(160, 0, -184), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Policeman = {
		Zone = "Home",
		UnlockFollowers = 350,
		RequiredTrophies = { "sage_quickdraw" }, -- the Forest sage's Fast Hands
		Outfit = { -- police look: a peaked police hat
			Hats = { 15752686682 }, -- Police Hat
			Layered = {},
		},
		SpawnPosition = Vector3.new(144, 0, -110), -- plaza-side sidewalk south of Neighbor02 (NE square)
		SpawnYaw = 180, -- face south, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(144, 0, -96), -- a step toward the plaza, sidewalk before the road
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Quick Draw, citizen! Watch me closely. The instant you see DRAW, react — tap the button"
			.. " or hit Space. Hesitate and you lose the round. Win every draw to earn my respect. Step on the mark!",
		Dialog = {
			Lines = {
				"Afternoon. I keep the peace around this neighborhood.",
				"Fast reflexes keep a town safe — let's see if you've got them.",
			},
			QualifiedLine = "You've proven yourself. Care to test your reflexes against the law?",
			GateLine = "Return when you carry the sage's Fast Hands and have {threshold} followers.",
			QualifiedChoices = { "Draw!", "Not now" },
			GateChoices = { "Understood" },
			TimeoutSeconds = 30,
		},
		QuickDraw = {
			Rounds = 3,
			MinDelaySeconds = 1.5,
			MaxDelaySeconds = 3.5,
			ReactWindowSeconds = 0.8,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1.0,
			BaseReward = 45,
			MatchBonus = 85,
			DrawPose = "rbxassetid://507770453", -- point emote as the draw gesture (placeholder default)
		},
		-- Policeman patrols the plaza sidewalks.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(144, 0, -110), -- spawn / post
				Vector3.new(144, 0, -96), -- north walk
				Vector3.new(130, 0, -103), -- west walk
				Vector3.new(144, 0, -116), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Firefighter = {
		Zone = "Home",
		UnlockFollowers = 300,
		RequiredTrophies = { "personal_trainer_strength" }, -- the gym trainer's Strength
		Outfit = { -- firefighter look: a fire helmet
			Hats = { 96463686997847 }, -- Firefighter Helmet
			Layered = {},
		},
		SpawnPosition = Vector3.new(-144, 0, -110), -- plaza-side sidewalk south of Neighbor01 (NW square)
		SpawnYaw = 180, -- face south, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-144, 0, -96), -- a step toward the plaza, sidewalk before the road
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Drill time! Watch the moves I make, then repeat them in order with the on-screen buttons"
			.. " or the arrow keys. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Hey there! I'm the firefighter for this district.",
				"We train hard so we're ready for anything. Want to run the drill with me?",
			},
			QualifiedLine = "You've got the strength — ready to run the fire drill?",
			GateLine = "Come back with the trainer's badge and {threshold} followers, and we'll drill together.",
			QualifiedChoices = { "Run the drill", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		SimonSays = {
			StartLength = 1,
			MaxRounds = 3,
			ShowStepSeconds = 2.5,
			ShowGapSeconds = 0.6,
			StepLeadSeconds = 1.0,
			RoundDelaySeconds = 1.5,
			InputTimeoutSeconds = 20,
			BaseReward = 50,
			RewardPerRound = 25,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				Left = "rbxassetid://507770239",
				Up = "rbxassetid://507770677",
				Right = "rbxassetid://507770453",
				Down = "rbxassetid://507771019",
			},
		},
		-- Firefighter patrols the plaza sidewalks near Neighbor01.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-144, 0, -110), -- spawn / post
				Vector3.new(-144, 0, -96), -- north walk
				Vector3.new(-158, 0, -103), -- west walk
				Vector3.new(-144, 0, -116), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Gardener = {
		Zone = "Home",
		UnlockFollowers = 450,
		RequiredTrophies = { "policeman_protection" }, -- the policeman's Protection
		Outfit = { -- gardener look: a straw hat (reuses the verified Farmer straw hat)
			Hats = { 18358376553 }, -- Straw Hat
			Layered = {},
		},
		SpawnPosition = Vector3.new(-171, 0, -117), -- grass strip in the NW quarter, west of Neighbor01
		SpawnYaw = 180, -- face south toward the open sidewalk/plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-171, 0, -105), -- a few steps onto the open sidewalk
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Let's tend the garden! Watch the planting moves I make, then repeat them in order with"
			.. " the on-screen buttons or arrow keys. Clear every round to bank followers. Step on the mark!",
		Dialog = {
			Lines = {
				"Oh, hello! I keep the neighborhood green.",
				"A good garden takes patience and a steady rhythm — care to learn?",
			},
			QualifiedLine = "You've earned the town's trust — ready to tend the garden with me?",
			GateLine = "Come back with the policeman's badge and {threshold} followers, and we'll garden together.",
			QualifiedChoices = { "Let's garden", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		SimonSays = {
			StartLength = 1,
			MaxRounds = 3,
			ShowStepSeconds = 2.5,
			ShowGapSeconds = 0.6,
			StepLeadSeconds = 1.0,
			RoundDelaySeconds = 1.5,
			InputTimeoutSeconds = 20,
			BaseReward = 50,
			RewardPerRound = 25,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				Left = "rbxassetid://507770239",
				Up = "rbxassetid://507770677",
				Right = "rbxassetid://507770453",
				Down = "rbxassetid://507771019",
			},
		},
		-- Gardener patrols the NW area near Neighbor01.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-171, 0, -117), -- spawn / post
				Vector3.new(-171, 0, -105), -- north walk
				Vector3.new(-185, 0, -117), -- west walk
				Vector3.new(-171, 0, -129), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	HomeBuilder = {
		Zone = "Home",
		UnlockFollowers = 300,
		RequiredTrophies = { "personal_trainer_strength" }, -- the gym trainer's Strength
		Outfit = { -- builder look: a construction hard hat
			Hats = { 84987146959152 }, -- Construction Hard Hat
			Layered = {},
		},
		SpawnPosition = Vector3.new(-100, 0, 0), -- plaza-side sidewalk east of Neighbor03 (W square)
		SpawnYaw = 90, -- face east, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-86, 0, 0), -- a step toward the plaza, clear sidewalk
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Time to build! Watch the construction moves I make, then repeat them in order with the"
			.. " on-screen buttons or arrow keys. Clear every round to bank followers. Step on the mark!",
		Dialog = {
			Lines = {
				"Howdy! I build the homes around this neighborhood.",
				"Every house goes up step by step, in the right order. Think you can keep up?",
			},
			QualifiedLine = "You've got the strength — ready to raise a house with me?",
			GateLine = "Come back with the trainer's badge and {threshold} followers, and we'll build together.",
			QualifiedChoices = { "Let's build", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		SimonSays = {
			StartLength = 1,
			MaxRounds = 3,
			ShowStepSeconds = 2.5,
			ShowGapSeconds = 0.6,
			StepLeadSeconds = 1.0,
			RoundDelaySeconds = 1.5,
			InputTimeoutSeconds = 20,
			BaseReward = 50,
			RewardPerRound = 25,
			Arrows = { "Left", "Up", "Right", "Down" },
			Poses = {
				Left = "rbxassetid://507770239",
				Up = "rbxassetid://507770677",
				Right = "rbxassetid://507770453",
				Down = "rbxassetid://507771019",
			},
		},
		-- HomeBuilder patrols the W area near Neighbor03.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-100, 0, 0), -- spawn / post
				Vector3.new(-86, 0, 0), -- north walk
				Vector3.new(-114, 0, 14), -- east walk
				Vector3.new(-100, 0, 14), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	Nurse = {
		Zone = "Home",
		UnlockFollowers = 550,
		RequiredTrophies = { "gardener_caretaking" }, -- the gardener's Caretaking
		Outfit = { -- nurse look: a white nurse cap
			Hats = { 10770260 }, -- Nurse Hat
			Layered = {},
		},
		SpawnPosition = Vector3.new(100, 0, 0), -- plaza-side sidewalk west of Neighbor04 (E square)
		SpawnYaw = 270, -- face west, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(86, 0, 0), -- a step toward the plaza, clear sidewalk
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Health check! Quick game of Rock, Paper, Scissors to test your reflexes.\n  Pick yer hand, best two outta three. Step on the mark when you're ready!",
		Dialog = {
			Lines = {
				"Hello! I'm the neighborhood nurse.",
				"A sharp mind keeps you healthy — let's see how quick you are at a friendly game.",
			},
			QualifiedLine = "You've earned your care — fancy a game o' Rock, Paper, Scissors? Best two outta three!",
			GateLine = "Come back with the gardener's badge and {threshold} followers, and we'll play.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		RockPaperScissors = {
			WinsNeeded = 2,
			InputTimeoutSeconds = 15,
			ReelSeconds = 2,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1,
			BaseReward = 40,
			MatchBonus = 80,
			Choices = { "Rock", "Paper", "Scissors" },
			Emoji = {
				Rock = "\u{270A}", -- raised fist
				Paper = "\u{270B}", -- raised hand
				Scissors = "\u{270C}\u{FE0F}", -- victory hand
			},
			Poses = {
				Rock = "rbxassetid://507770677", -- cheer (fist up)
				Paper = "rbxassetid://507770239", -- wave (open hand)
				Scissors = "rbxassetid://507770453", -- point
			},
		},
		-- Nurse patrols the plaza sidewalks near Neighbor04.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(100, 0, 0), -- spawn / post
				Vector3.new(86, 0, 0), -- west walk
				Vector3.new(100, 0, -14), -- south walk
				Vector3.new(114, 0, 0), -- east walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
	TruckDriver = {
		Zone = "Home",
		UnlockFollowers = 450,
		RequiredTrophies = { "taxi_driver_mobility" }, -- the taxi driver's Mobility
		Outfit = { -- trucker look: a trucker cap
			Hats = { 12356137971 }, -- Vintage Label Trucker Cap
			Layered = {},
		},
		SpawnPosition = Vector3.new(-172, 0, 172), -- grass shoulder by the SW ramp, clear of the road
		SpawnYaw = 0, -- face the open grass toward the plaza
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-172, 0, 160), -- a few steps along the grass
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Quick Draw, partner! Watch me closely. The instant you see DRAW, react — tap the button"
			.. " or hit Space. Hesitate and you lose the round. Win every draw to earn my respect. Step on the mark!",
		Dialog = {
			Lines = {
				"Howdy! I haul the heavy loads in and out of town.",
				"Long-haul driving is all about reflexes on the road. Got fast hands?",
			},
			QualifiedLine = "You've kept up with the cabbie — care to test your reflexes against a trucker?",
			GateLine = "Come back with the cabbie's Mobility and {threshold} followers, and we'll duel.",
			QualifiedChoices = { "Draw!", "Not now" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		QuickDraw = {
			Rounds = 3,
			MinDelaySeconds = 1.5,
			MaxDelaySeconds = 3.5,
			ReactWindowSeconds = 0.8,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1.0,
			BaseReward = 45,
			MatchBonus = 85,
			DrawPose = "rbxassetid://507770453", -- point emote as the draw gesture (placeholder default)
		},
		-- TruckDriver patrols the SW ramp area.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-172, 0, 172), -- spawn / post
				Vector3.new(-172, 0, 160), -- north walk
				Vector3.new(-186, 0, 172), -- west walk
				Vector3.new(-172, 0, 186), -- south walk
			},
			WalkSpeed = 3, -- casual pace
			PauseMin = 3, -- min seconds between waypoints
			PauseMax = 8, -- max seconds between waypoints
		},
	},
} :: { [string]: NpcDef }

return Npc
