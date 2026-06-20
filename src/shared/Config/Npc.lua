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

Npc.Npc = {
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
	},
} :: { [string]: NpcDef }

return Npc
