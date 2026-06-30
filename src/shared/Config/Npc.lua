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
type MemoryDef = {
	Rounds: number, -- rounds to clear; clearing all awards the bonus reward + trophy
	StartTargets: number, -- emojis to memorize in round 1 (grows by one per round)
	GridSize: number, -- cells shown for recall (16 = a 4x4 grid)
	ShowSeconds: number, -- how long the target emojis flash before the grid appears
	SelectTimeoutSeconds: number, -- server-side deadline for the player to submit a selection
	RoundDelaySeconds: number, -- pause between a cleared round and the next show phase
	BaseReward: number, -- followers for clearing round 1
	RewardPerRound: number, -- extra followers per round beyond the first
	Emojis: { string }, -- object-emoji pool to draw the grid from (>= GridSize distinct)
}
type TicTacToeDef = {
	WinsNeeded: number, -- first to this many game wins takes the match (draws replay the game)
	MoveTimeoutSeconds: number, -- server-side deadline for the player to make a move
	RevealSeconds: number, -- pause showing a finished game before the next
	RoundDelaySeconds: number, -- pause before a new game's board appears
	NpcMoveDelaySeconds: number, -- pause before the NPC plays its reply (so the player sees their move land)
	BaseReward: number, -- followers for each game the player wins
	MatchBonus: number, -- extra followers for winning the match
	PlayerMark: string, -- the player's symbol
	NpcMark: string, -- the NPC's symbol
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
	Memory: MemoryDef?, -- present iff this NPC hosts the recognition-memory minigame
	TicTacToe: TicTacToeDef?, -- present iff this NPC hosts the tic-tac-toe minigame
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
		Outfit = { -- cowboy look: cowboy hat + plaid flannel shirt and western jeans
			Hats = { 10473499273 }, -- Cowboy Hat
			Layered = {
				{ AssetId = 111812538083330, Type = Enum.AccessoryType.Shirt }, -- Light Brown Flannel Plaid Shirt
				{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
			},
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

	Rancher = {
		Zone = "Farm",
		UnlockFollowers = 250,
		RequiredTrophies = { "cowboy_roundup" }, -- beat Cole the Cowboy first, then challenge the Rancher
		SpawnPosition = Vector3.new(330, 0, -150), -- clear pasture grass east of the Cowboy (Studio-verified)
		SpawnYaw = 90, -- face west, toward players approaching from town
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- rancher look: cowboy hat + flannel and western jeans (same proven asset ids as the Cowboy)
			Hats = { 10473499273 }, -- Cowboy Hat
			Layered = {
				{ AssetId = 111812538083330, Type = Enum.AccessoryType.Shirt }, -- Light Brown Flannel Plaid Shirt
				{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
			},
		},
		ArenaPosition = Vector3.new(318, 0, -150), -- a short walk west to clear pasture for the duel (Studio-verified)
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Welcome to the ranch! Reckon you can beat me at Rock, Paper, Scissors?\n  Pick yer hand — best two outta three wins. Step on the mark when yer ready!",
		Dialog = {
			Lines = {
				"Howdy! I'm Hank, I run the horses out here on the back forty.",
				"Cole tells me you've got a sharp hand at Roshambo. Care to prove it?",
			},
			QualifiedLine = "Let's settle it the ranch way — Rock, Paper, Scissors, best two outta three!",
			GateLine = "Earn {threshold} followers and beat Cole the Cowboy first, then come challenge me.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Will do" },
			TimeoutSeconds = 30,
		},
		RockPaperScissors = {
			WinsNeeded = 2,
			InputTimeoutSeconds = 15,
			ReelSeconds = 2,
			RevealSeconds = 1.5,
			RoundDelaySeconds = 1,
			BaseReward = 50,
			MatchBonus = 100,
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
	},
	Postman = {
		Zone = "Home",
		UnlockFollowers = 0, -- no follower gate: anyone can challenge the postman
		SpawnPosition = Vector3.new(40, 0, -40), -- central plaza area, near the town green
		SpawnYaw = 180, -- face south, toward the approach from the spawn plaza
		AvatarUserId = 1, -- Roblox's own avatar as the base; dressed by Outfit below
		Outfit = { -- postal look: officer cap + white shirt and navy trousers (summer postal uniform)
			Hats = { 13383061629 }, -- White Star Line Officer Cap
			Layered = {
				{ AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt }, -- White Tank Top
				{ AssetId = 140048946599540, Type = Enum.AccessoryType.Pants }, -- navy uniform pants
			},
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
		Outfit = { -- cabbie look: newsboy cap + casual tee and jeans
			Hats = { 78174478860906 }, -- Black Shelby Vintage Cap
			Layered = {
				{ AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt }, -- White Tank Top
				{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
			},
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
		Outfit = { -- police look: police hat + navy uniform jacket and trousers
			Hats = { 15752686682 }, -- Police Hat
			Layered = {
				{ AssetId = 90301601233454, Type = Enum.AccessoryType.Jacket }, -- police uniform jacket
				{ AssetId = 140048946599540, Type = Enum.AccessoryType.Pants }, -- police uniform pants
			},
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
		Outfit = { -- firefighter look: fire helmet + firefighter turnout pants
			Hats = { 96463686997847 }, -- Firefighter Helmet
			Layered = {
				{ AssetId = 9773731232, Type = Enum.AccessoryType.Pants }, -- Firefighter Pants
			},
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
		Outfit = { -- gardener look: straw hat + flannel shirt under denim overalls
			Hats = { 18358376553 }, -- Straw Hat (reuses the verified Farmer straw hat)
			Layered = {
				{ AssetId = 111812538083330, Type = Enum.AccessoryType.Shirt }, -- Light Brown Flannel Plaid Shirt
				{ AssetId = 127189956586914, Type = Enum.AccessoryType.Pants }, -- Classic Blue Denim Overalls
			},
		},
		SpawnPosition = Vector3.new(-20, 0, 150), -- park SW corner, surrounded by flower clusters
		SpawnYaw = 180, -- face south toward the plaza
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(0, 0, 144), -- park center among the flowers
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
		-- Gardener patrols the park area among flower clusters.
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-20, 0, 150), -- SW corner of park (spawn / post)
				Vector3.new(20, 0, 150), -- SE edge (walks east among flowers)
				Vector3.new(20, 0, 130), -- NE corner
				Vector3.new(-20, 0, 130), -- NW corner
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
		Outfit = { -- builder look: hard hat + denim work overalls
			Hats = { 84987146959152 }, -- Construction Hard Hat
			Layered = {
				{ AssetId = 127189956586914, Type = Enum.AccessoryType.Pants }, -- Classic Blue Denim Overalls
			},
		},
		SpawnPosition = Vector3.new(-100, 0, 0), -- plaza-side sidewalk east of Neighbor03 (W square)
		SpawnYaw = 90, -- face east, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-86, 0, 0), -- a step toward the plaza, clear sidewalk
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Tic-Tac-Toe, builder style! You're X, I'm O — tap a square to lay your mark. Get"
			.. " three in a row before I do. Best two out of three takes it. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Howdy! I build the homes around this neighborhood.",
				"Every house starts with a solid plan — three beams in a row. Fancy a game?",
			},
			QualifiedLine = "You've got the strength — up for a round of Tic-Tac-Toe?",
			GateLine = "Come back with the trainer's badge and {threshold} followers, and we'll build together.",
			QualifiedChoices = { "Let's play", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		TicTacToe = {
			WinsNeeded = 2, -- best two out of three (draws replay the game)
			MoveTimeoutSeconds = 20,
			RevealSeconds = 2,
			RoundDelaySeconds = 1.5,
			NpcMoveDelaySeconds = 0.6,
			BaseReward = 40, -- per game won
			MatchBonus = 80, -- 2 x 40 + 80 = 160 max, matching the other best-of-three NPCs
			PlayerMark = "X",
			NpcMark = "O",
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
		Outfit = { -- nurse look: nurse cap + medical scrubs top and trousers
			Hats = { 10770260 }, -- Nurse Hat
			Layered = {
				{ AssetId = 80960012829759, Type = Enum.AccessoryType.Jacket }, -- Medical Nurse Outfit Vet
				{ AssetId = 13896827744, Type = Enum.AccessoryType.Pants }, -- Medical Scrubs Hospital Pants
			},
		},
		SpawnPosition = Vector3.new(100, 0, 0), -- plaza-side sidewalk west of Neighbor04 (E square)
		SpawnYaw = 270, -- face west, toward the plaza approach
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(86, 0, 0), -- a step toward the plaza, clear sidewalk
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Memory check! I'll flash a few items — memorize them. Then a grid appears: tap the"
			.. " ones you saw and hit Submit. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Hello! I'm the neighborhood nurse.",
				"A sharp mind keeps you healthy — let's test your memory with a quick game.",
			},
			QualifiedLine = "You've earned your care — fancy a memory test? Watch the items, then pick them out!",
			GateLine = "Come back with the gardener's badge and {threshold} followers, and we'll play.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		Memory = {
			Rounds = 3,
			StartTargets = 4, -- 4 -> 5 -> 6 items to memorize across the rounds
			GridSize = 16, -- 4x4 recall grid
			ShowSeconds = 4, -- the items flash for 4 seconds
			SelectTimeoutSeconds = 20,
			RoundDelaySeconds = 1.5,
			BaseReward = 50,
			RewardPerRound = 25, -- 50 + 75 + 100 = 225 max, matching the Simon Says clear
			Emojis = {
				"\u{1F34E}", -- apple
				"\u{26BD}", -- soccer ball
				"\u{1F3B8}", -- guitar
				"\u{1F511}", -- key
				"\u{1F388}", -- balloon
				"\u{1F355}", -- pizza
				"\u{1F6B2}", -- bicycle
				"\u{1F4DA}", -- books
				"\u{1F3B2}", -- die
				"\u{2602}\u{FE0F}", -- umbrella
				"\u{1F514}", -- bell
				"\u{1F344}", -- mushroom
				"\u{1F9E9}", -- puzzle piece
				"\u{1FA81}", -- kite
				"\u{1F941}", -- drum
				"\u{1F9F8}", -- teddy bear
				"\u{1F369}", -- doughnut
				"\u{1F381}", -- gift
				"\u{1F455}", -- t-shirt
				"\u{1F3A9}", -- top hat
				"\u{1F4A1}", -- light bulb
				"\u{1F33B}", -- sunflower
				"\u{1F4F7}", -- camera
				"\u{1F570}\u{FE0F}", -- clock
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
		Outfit = { -- trucker look: trucker cap + plaid flannel shirt and jeans
			Hats = { 12356137971 }, -- Vintage Label Trucker Cap
			Layered = {
				{ AssetId = 127156100983108, Type = Enum.AccessoryType.Shirt }, -- Red & Black Long Sleeve Plaid Flannel Shirt
				{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
			},
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
	-- Airport-terminal professions. The second collectible chain: each gates on a city NPC's trophy
	-- (RequiredTrophies) plus a rising follower threshold (600..1300), so they unlock after the town is
	-- cleared. All stand stationary inside the arrivals terminal (Zone "Airport", floor Y=1.1) and walk
	-- out to their arena for the minigame -- no CitizenWalk. Positions are starting values verified/tuned
	-- in Studio; outfits are filled in the Studio catalog pass. Their trophies populate the Social
	-- Modal's Airport tab (PhoneMenuController.TROPHY_ZONE).
	Athlete = {
		Zone = "Airport",
		UnlockFollowers = 600,
		RequiredTrophies = { "personal_trainer_strength" }, -- the gym trainer's Strength
		Outfit = { -- athletic look: sweatband + tank top and joggers
			Hats = { 12871624213 }, -- Red Bandana Headband
			Layered = {
				{ AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt }, -- White Tank Top
				{ AssetId = 9183094140, Type = Enum.AccessoryType.Pants }, -- White Jogger Pants
			},
		},
		SpawnPosition = Vector3.new(80, 1.1, 743), -- right wall, terminal floor
		SpawnYaw = 270, -- face west, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(64, 1.1, 743), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Simon Says, athlete style! Watch the moves I make, then repeat them in order with"
			.. " the on-screen buttons or the arrow keys. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Hey! I'm a pro athlete, always in training.",
				"Footwork drills sharpen the mind too — want to copy my moves?",
			},
			QualifiedLine = "You've got the strength — ready to run the drill? Watch and repeat!",
			GateLine = "Come back with the trainer's Strength and {threshold} followers, and we'll train.",
			QualifiedChoices = { "Let's go!", "Maybe later" },
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
		CitizenWalk = {
			Waypoints = {
				Vector3.new(80, 1.1, 727), -- spawn / post (Z 719-727 corridor)
				Vector3.new(64, 1.1, 727), -- in to inner wall
				Vector3.new(80, 1.1, 719), -- along right wall
				Vector3.new(64, 1.1, 719), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Chef = {
		Zone = "Airport",
		UnlockFollowers = 700,
		RequiredTrophies = { "sage_quickdraw" }, -- the Forest sage's Fast Hands
		Outfit = { -- chef look: toque + white double-breasted coat
			Hats = { 1374258 }, -- Chef Hat
			Layered = { { AssetId = 11332013358, Type = Enum.AccessoryType.Jacket } }, -- Chef Coat In White
		},
		SpawnPosition = Vector3.new(-80, 1.1, 677), -- left wall, terminal floor
		SpawnYaw = 90, -- face east, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-64, 1.1, 677), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Memory kitchen! I'll flash a few items — memorize them. Then a grid appears: tap the"
			.. " ones you saw and hit Submit. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Welcome! I'm a chef — I run the terminal's kitchen.",
				"A great cook never forgets a recipe. Want to test your memory?",
			},
			QualifiedLine = "You've got fast hands — fancy a memory game? Watch the ingredients, then pick them out!",
			GateLine = "Come back with the sage's Fast Hands and {threshold} followers, and we'll cook.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		Memory = {
			Rounds = 3,
			StartTargets = 4,
			GridSize = 16,
			ShowSeconds = 4,
			SelectTimeoutSeconds = 20,
			RoundDelaySeconds = 1.5,
			BaseReward = 50,
			RewardPerRound = 25,
			Emojis = {
				"\u{1F34E}", -- apple
				"\u{26BD}", -- soccer ball
				"\u{1F3B8}", -- guitar
				"\u{1F511}", -- key
				"\u{1F388}", -- balloon
				"\u{1F355}", -- pizza
				"\u{1F6B2}", -- bicycle
				"\u{1F4DA}", -- books
				"\u{1F3B2}", -- die
				"\u{2602}\u{FE0F}", -- umbrella
				"\u{1F514}", -- bell
				"\u{1F344}", -- mushroom
				"\u{1F9E9}", -- puzzle piece
				"\u{1FA81}", -- kite
				"\u{1F941}", -- drum
				"\u{1F9F8}", -- teddy bear
				"\u{1F369}", -- doughnut
				"\u{1F381}", -- gift
				"\u{1F455}", -- t-shirt
				"\u{1F3A9}", -- top hat
				"\u{1F4A1}", -- light bulb
				"\u{1F33B}", -- sunflower
				"\u{1F4F7}", -- camera
				"\u{1F570}\u{FE0F}", -- clock
			},
		},
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-80, 1.1, 687), -- spawn / post (Z 679-687 corridor)
				Vector3.new(-64, 1.1, 687), -- in to inner wall
				Vector3.new(-80, 1.1, 679), -- along left wall
				Vector3.new(-64, 1.1, 679), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Singer = {
		Zone = "Airport",
		UnlockFollowers = 800,
		RequiredTrophies = { "firefighter_bravery" }, -- the firefighter's Bravery
		Outfit = { -- pop-star look: stylish cap + flashy gold tuxedo jacket
			Hats = { 78174478860906 }, -- Black Shelby Vintage Cap
			Layered = { { AssetId = 13073595441, Type = Enum.AccessoryType.Jacket } }, -- Golden Tuxedo Suit
		},
		SpawnPosition = Vector3.new(-80, 1.1, 699), -- left wall, terminal floor
		SpawnYaw = 90, -- face east, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-64, 1.1, 699), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Rock, Paper, Scissors, star style! Pick your hand, I'll throw mine. Best two out of"
			.. " three takes it. Step on the mark when you're ready!",
		Dialog = {
			Lines = {
				"Hello, darling! I'm a singer touring the world.",
				"A little stage game keeps the nerves away — Rock, Paper, Scissors?",
			},
			QualifiedLine = "You've got the bravery — fancy a quick game of Rock, Paper, Scissors? Best two out of three!",
			GateLine = "Come back with the firefighter's Bravery and {threshold} followers, and we'll play.",
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
		CitizenWalk = {
			Waypoints = {
				Vector3.new(32, 1.1, 711), -- spawn / post (Z 703-711 corridor)
				Vector3.new(16, 1.1, 711), -- in to center
				Vector3.new(32, 1.1, 703), -- along center-right
				Vector3.new(16, 1.1, 703), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Violinist = {
		Zone = "Airport",
		UnlockFollowers = 900,
		RequiredTrophies = { "home_builder_nicehome" }, -- the home builder's Nice Home
		Outfit = { -- formal musician look: black pinstripe tuxedo jacket
			Hats = {},
			Layered = { { AssetId = 9039269740, Type = Enum.AccessoryType.Jacket } }, -- Pinstripe Tuxedo Jacket Suit - Black
		},
		SpawnPosition = Vector3.new(80, 1.1, 721), -- right wall, terminal floor
		SpawnYaw = 270, -- face west, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(64, 1.1, 721), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Tic-Tac-Toe, with finesse! You're X, I'm O — tap a square to lay your mark. Get three"
			.. " in a row before I do. Best two out of three takes it. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Ah, a listener! I'm a violinist between performances.",
				"Precision and patience — the same skills win a game of Tic-Tac-Toe.",
			},
			QualifiedLine = "You've a builder's eye for structure — up for a round of Tic-Tac-Toe?",
			GateLine = "Return with the builder's Nice Home badge and {threshold} followers, and we'll play.",
			QualifiedChoices = { "Let's play", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		TicTacToe = {
			WinsNeeded = 2,
			MoveTimeoutSeconds = 20,
			RevealSeconds = 2,
			RoundDelaySeconds = 1.5,
			NpcMoveDelaySeconds = 0.6,
			BaseReward = 40,
			MatchBonus = 80,
			PlayerMark = "X",
			NpcMark = "O",
		},
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-80, 1.1, 711), -- spawn / post (Z 711-719 corridor)
				Vector3.new(-64, 1.1, 711), -- in to inner wall
				Vector3.new(-80, 1.1, 719), -- along left wall
				Vector3.new(-64, 1.1, 719), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	DJ = {
		Zone = "Airport",
		UnlockFollowers = 1000,
		RequiredTrophies = { "policeman_protection" }, -- the policeman's Protection
		Outfit = { -- DJ look: headphones + varsity jacket
			Hats = { 12196484286 }, -- Star Headphones Accessory
			Layered = { { AssetId = 16380310710, Type = Enum.AccessoryType.Jacket } }, -- Black Sport Oversized Varsity Jacket
		},
		SpawnPosition = Vector3.new(-80, 1.1, 721), -- left wall, terminal floor
		SpawnYaw = 90, -- face east, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-64, 1.1, 721), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Memory mix! I'll flash a few items — memorize them. Then a grid appears: tap the ones"
			.. " you saw and hit Submit. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Yo! I'm the airport DJ — I keep the terminal grooving.",
				"A good memory makes a great set. Think you can keep up?",
			},
			QualifiedLine = "You've earned your stripes — fancy a memory game? Watch the tracks, then pick them out!",
			GateLine = "Come back with the policeman's Protection and {threshold} followers, and we'll spin.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		Memory = {
			Rounds = 3,
			StartTargets = 4,
			GridSize = 16,
			ShowSeconds = 4,
			SelectTimeoutSeconds = 20,
			RoundDelaySeconds = 1.5,
			BaseReward = 50,
			RewardPerRound = 25,
			Emojis = {
				"\u{1F34E}", -- apple
				"\u{26BD}", -- soccer ball
				"\u{1F3B8}", -- guitar
				"\u{1F511}", -- key
				"\u{1F388}", -- balloon
				"\u{1F355}", -- pizza
				"\u{1F6B2}", -- bicycle
				"\u{1F4DA}", -- books
				"\u{1F3B2}", -- die
				"\u{2602}\u{FE0F}", -- umbrella
				"\u{1F514}", -- bell
				"\u{1F344}", -- mushroom
				"\u{1F9E9}", -- puzzle piece
				"\u{1FA81}", -- kite
				"\u{1F941}", -- drum
				"\u{1F9F8}", -- teddy bear
				"\u{1F369}", -- doughnut
				"\u{1F381}", -- gift
				"\u{1F455}", -- t-shirt
				"\u{1F3A9}", -- top hat
				"\u{1F4A1}", -- light bulb
				"\u{1F33B}", -- sunflower
				"\u{1F4F7}", -- camera
				"\u{1F570}\u{FE0F}", -- clock
			},
		},
		CitizenWalk = {
			Waypoints = {
				Vector3.new(-32, 1.1, 703), -- spawn / post (Z 695-703 corridor)
				Vector3.new(-16, 1.1, 703), -- in to center
				Vector3.new(-32, 1.1, 695), -- along center-left
				Vector3.new(-16, 1.1, 695), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Ballerina = {
		Zone = "Airport",
		UnlockFollowers = 1100,
		RequiredTrophies = { "truck_driver_heavyduty" }, -- the truck driver's Heavy Duty
		Outfit = { -- ballet look: leotard top + tutu skirt
			Hats = {},
			Layered = {
				{ AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt }, -- White Tank Top (leotard top)
				{ AssetId = 14453904448, Type = Enum.AccessoryType.DressSkirt }, -- Ballerina dress (tutu)
			},
		},
		SpawnPosition = Vector3.new(80, 1.1, 677), -- right wall, terminal floor
		SpawnYaw = 270, -- face west, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(64, 1.1, 677), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Simon Says, en pointe! Watch the steps I make, then repeat them in order with the"
			.. " on-screen buttons or the arrow keys. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Bonjour! I'm a ballerina with the touring company.",
				"Choreography is memory in motion — want to follow my steps?",
			},
			QualifiedLine = "You've kept pace with the truckers — ready to follow my steps? Watch and repeat!",
			GateLine = "Return with the trucker's Heavy Duty badge and {threshold} followers, and we'll dance.",
			QualifiedChoices = { "Let's dance!", "Maybe later" },
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
		CitizenWalk = {
			Waypoints = {
				Vector3.new(80, 1.1, 695), -- spawn / post (Z 687-695 corridor)
				Vector3.new(64, 1.1, 695), -- in to inner wall
				Vector3.new(80, 1.1, 687), -- along right wall
				Vector3.new(64, 1.1, 687), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Pianist = {
		Zone = "Airport",
		UnlockFollowers = 1200,
		RequiredTrophies = { "gardener_caretaking" }, -- the gardener's Caretaking
		Outfit = { -- formal musician look: navy tuxedo jacket
			Hats = {},
			Layered = { { AssetId = 9039602336, Type = Enum.AccessoryType.Jacket } }, -- Tuxedo Jacket Suit - Navy
		},
		SpawnPosition = Vector3.new(80, 1.1, 699), -- right wall, terminal floor
		SpawnYaw = 270, -- face west, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(64, 1.1, 699), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Memory recital! I'll flash a few items — memorize them. Then a grid appears: tap the"
			.. " ones you saw and hit Submit. Clear every round to bank followers. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Good day. I'm a concert pianist passing through.",
				"Every melody is a memory — let's see how sharp yours is.",
			},
			QualifiedLine = "You've a gardener's care — fancy a memory game? Watch the notes, then pick them out!",
			GateLine = "Come back with the gardener's Caretaking and {threshold} followers, and we'll play.",
			QualifiedChoices = { "Let's play!", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		Memory = {
			Rounds = 3,
			StartTargets = 4,
			GridSize = 16,
			ShowSeconds = 4,
			SelectTimeoutSeconds = 20,
			RoundDelaySeconds = 1.5,
			BaseReward = 50,
			RewardPerRound = 25,
			Emojis = {
				"\u{1F34E}", -- apple
				"\u{26BD}", -- soccer ball
				"\u{1F3B8}", -- guitar
				"\u{1F511}", -- key
				"\u{1F388}", -- balloon
				"\u{1F355}", -- pizza
				"\u{1F6B2}", -- bicycle
				"\u{1F4DA}", -- books
				"\u{1F3B2}", -- die
				"\u{2602}\u{FE0F}", -- umbrella
				"\u{1F514}", -- bell
				"\u{1F344}", -- mushroom
				"\u{1F9E9}", -- puzzle piece
				"\u{1FA81}", -- kite
				"\u{1F941}", -- drum
				"\u{1F9F8}", -- teddy bear
				"\u{1F369}", -- doughnut
				"\u{1F381}", -- gift
				"\u{1F455}", -- t-shirt
				"\u{1F3A9}", -- top hat
				"\u{1F4A1}", -- light bulb
				"\u{1F33B}", -- sunflower
				"\u{1F4F7}", -- camera
				"\u{1F570}\u{FE0F}", -- clock
			},
		},
		CitizenWalk = {
			Waypoints = {
				Vector3.new(8, 1.1, 735), -- spawn / post (Z 727-735 corridor)
				Vector3.new(-8, 1.1, 735), -- across center
				Vector3.new(8, 1.1, 727), -- along center-right
				Vector3.new(-8, 1.1, 727), -- towards center
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
	Archeologist = {
		Zone = "Airport",
		UnlockFollowers = 1300,
		RequiredTrophies = { "nurse_healthy" }, -- the nurse's Healthy
		Outfit = { -- explorer look: pith helmet + flannel shirt and jeans
			Hats = { 10705097 }, -- Tan Pith Helmet
			Layered = {
				{ AssetId = 111812538083330, Type = Enum.AccessoryType.Shirt }, -- Light Brown Flannel Plaid Shirt
				{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
			},
		},
		SpawnPosition = Vector3.new(-80, 1.1, 743), -- left wall, terminal floor
		SpawnYaw = 90, -- face east, into the hall
		AvatarUserId = 1,
		ArenaPosition = Vector3.new(-64, 1.1, 743), -- a few steps toward the hall centre
		MoveSeconds = 2,
		WalkAnimation = "rbxassetid://913402848", -- Roblox default R15 walk
		Instructions = "Tic-Tac-Toe, dig-site style! You're X, I'm O — tap a square to lay your mark. Get"
			.. " three in a row before I do. Best two out of three takes it. Step on the mark and hit Start!",
		Dialog = {
			Lines = {
				"Greetings! I'm an archeologist, fresh off a dig.",
				"Strategy is everything in the field — and on the grid.",
			},
			QualifiedLine = "You've got a healer's patience — care for a game of Tic-Tac-Toe?",
			GateLine = "Come back with the nurse's Healthy badge and {threshold} followers, and we'll match wits.",
			QualifiedChoices = { "Let's play", "Maybe later" },
			GateChoices = { "Got it" },
			TimeoutSeconds = 30,
		},
		TicTacToe = {
			WinsNeeded = 2,
			MoveTimeoutSeconds = 20,
			RevealSeconds = 2,
			RoundDelaySeconds = 1.5,
			NpcMoveDelaySeconds = 0.6,
			BaseReward = 40,
			MatchBonus = 80,
			PlayerMark = "X",
			NpcMark = "O",
		},
		CitizenWalk = {
			Waypoints = {
				Vector3.new(32, 1.1, 743), -- spawn / post (Z 735-743 corridor)
				Vector3.new(16, 1.1, 743), -- in to center
				Vector3.new(32, 1.1, 735), -- along center-right
				Vector3.new(16, 1.1, 735), -- towards hall centre
			},
			WalkSpeed = 3,
			PauseMin = 2,
			PauseMax = 6,
		},
	},
} :: { [string]: NpcDef }

return Npc
