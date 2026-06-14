--!strict
-- Gym-friend roster and AI/dialog tunables (Config.GymFriends). Twelve NPCs, four workout types x
-- three people, each with a name, gender, a home station on the opened first floor, and two
-- branching dialog trees: Intro (first meeting -- they introduce themselves; befriending them on
-- close awards BefriendReward followers) and Friend (they already know you). They all spawn with the
-- shared "default lego block" look (Config.DefaultNpcOutfit); a player who customizes one sees their
-- own version, rendered client-side. GymFriendService spawns them, runs the exercise/break routine
-- (Shared.Logic.Routine) with natural Humanoid walking, and runs the conversations
-- (Shared.Logic.DialogTree). Positions and the placeholder animation ids are tuned by looking in
-- Studio and swapped for real workout uploads later (doc 002).

local DialogTree = require(script.Parent.Parent.Logic.DialogTree)

export type FriendDef = {
	Id: string, -- stable id; the persisted "befriended" key (ProfileData.Friends)
	Name: string, -- display name (ProximityPrompt + name tag)
	Gender: "male" | "female",
	Type: "Runner" | "Cyclist" | "Lifter" | "Floor", -- selects the workout animation
	Station: Vector3, -- where they stand to exercise (a gym equipment spot, floor surface y=23)
	Yaw: number, -- facing while exercising (0 looks -Z), matched to the equipment
	Intro: DialogTree.Tree, -- first meeting
	Friend: DialogTree.Tree, -- once befriended
}

local GymFriends = {}

GymFriends.BefriendReward = 40 -- followers granted the first time you chat with each friend (once each)
GymFriends.Exercise = { min = 240, max = 360 } -- seconds exercising before a break (~5 min, jittered)
GymFriends.Rest = { min = 240, max = 360 } -- seconds on break before exercising again (~5 min, jittered)
GymFriends.WalkSpeed = 9 -- studs/sec; a relaxed gym wander (default 16 looks like sprinting)
GymFriends.CollisionGroup = "GymNpc" -- friends don't collide with each other; equipment is "GymProp"
GymFriends.EquipmentGroup = "GymProp" -- the gym equipment group friends pass through (no MoveTo snags)
GymFriends.PromptDistance = 12 -- studs the Talk prompt is reachable from
GymFriends.DialogTimeout = 30 -- seconds of inactivity before a conversation closes itself

-- Placeholder workout animations: confirmed-loadable Roblox defaults/emotes (already used by the
-- trainer) standing in for real push-up/cycling/lifting uploads -- swap the ids when those exist.
GymFriends.Animations = {
	Walk = "rbxassetid://913402848", -- default R15 walk (between station and lounge)
	Break = "rbxassetid://507770239", -- wave emote -- friendly idle while resting
	Runner = "rbxassetid://913376220", -- default R15 run, in place on the treadmill
	Cyclist = "rbxassetid://507771019", -- dance emote (stand-in for pedalling)
	Lifter = "rbxassetid://507770677", -- cheer emote (stand-in for lifting)
	Floor = "rbxassetid://507770453", -- point emote (stand-in for floor work)
}

export type LoungeGroup = {
	center: Vector3, -- the spot the group gathers around; each member takes a distinct slot in a ring
	members: { string }, -- friend Ids assigned to this group (a fixed slot each, so they never overlap)
}

-- Break groups: where friends gather to rest and chat, in five distinct corners of the gym. Each
-- friend has a fixed group (and a fixed slot within it -- GymFriendService rings the members around
-- the centre facing inward), so a break reads as a little huddle of friends, not one pile, and two
-- friends never claim the same spot. Every centre sits at Z <= -57 -- well clear of the stairwell
-- hole (Z in [-37.5, -19.1]) -- so the straight walk from a station never crosses the shaft and no
-- one falls. Tuned by looking in Studio. Groups of three and two as requested.
GymFriends.LoungeGroups = {
	{ center = Vector3.new(-22, 23, -57), members = { "maya", "lucas", "bianca" } },
	{ center = Vector3.new(-46, 23, -78), members = { "priya", "diego" } },
	{ center = Vector3.new(-9, 23, -78), members = { "marcus", "hana" } },
	{ center = Vector3.new(-22, 23, -103), members = { "theo", "sofia", "noah" } },
	{ center = Vector3.new(-46, 23, -120), members = { "aisha", "sam" } },
} :: { LoungeGroup }

-- Two-answer Intro/Friend trees per NPC: the greeting offers the player two friendly answers, each
-- leading to a warm reply that closes the chat. Personality lives in the wording.
GymFriends.Friends = {
	-- ===== Runners (treadmills) =====
	{
		Id = "maya",
		Name = "Maya",
		Gender = "female",
		Type = "Runner",
		Station = Vector3.new(-50, 23, -59),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Oh hey! I'm Maya — I basically live on this treadmill. You new around here?",
					choices = {
						{ label = "Yeah, just joined!", next = "new" },
						{ label = "Love your energy!", next = "energy" },
					},
				},
				new = {
					text = "Welcome to the crew! Stick with me and we'll run a marathon by summer. Friends?",
					choices = { { label = "Friends! 🙌", next = nil } },
				},
				energy = {
					text = "Ha! Runner's high is real. So good to meet a fellow gym soul.",
					choices = { { label = "Likewise! 😄", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "There's my favourite training buddy! Did you stretch today, or are we both lying?",
					choices = {
						{ label = "Totally stretched. 😇", next = "stretch" },
						{ label = "...define 'stretch'.", next = "lazy" },
					},
				},
				stretch = {
					text = "Look at you being responsible! Proud of you. Go crush it.",
					choices = { { label = "You too! 💪", next = nil } },
				},
				lazy = {
					text = "Hahaha at least you're honest. Okay, ten seconds of toe-touches, with me — go!",
					choices = { { label = "Okay okay! 😅", next = nil } },
				},
			},
		},
	},
	{
		Id = "theo",
		Name = "Theo",
		Gender = "male",
		Type = "Runner",
		Station = Vector3.new(-5, 23, -59),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hey there. Theo. I just zone out to podcasts up here. What gets you moving?",
					choices = {
						{ label = "Music, all the way.", next = "music" },
						{ label = "Honestly? Snacks after.", next = "snacks" },
					},
				},
				music = {
					text = "A person of taste. We'll trade playlists sometime. Good to meet you, friend.",
					choices = { { label = "For sure! 🎧", next = nil } },
				},
				snacks = {
					text = "Hahaha finally, someone honest. Earn the smoothie, I always say. Let's be friends.",
					choices = { { label = "Deal! 🥤", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "Ayy, look who's back. New episode dropped — wanna hear the wild part?",
					choices = {
						{ label = "Go on, spoil it.", next = "spoil" },
						{ label = "No spoilers! 🙉", next = "nospoil" },
					},
				},
				spoil = {
					text = "...okay I won't, you'll thank me. Run now, gossip later. Pace yourself!",
					choices = { { label = "Haha later! 👋", next = nil } },
				},
				nospoil = {
					text = "Respect. Sealed lips. Now go get those steps in, champ.",
					choices = { { label = "On it! 🏃", next = nil } },
				},
			},
		},
	},
	{
		Id = "priya",
		Name = "Priya",
		Gender = "female",
		Type = "Runner",
		Station = Vector3.new(-28, 23, -71),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hi! Priya. I'm chasing a new personal best today — wish me luck? I'm friendly, promise!",
					choices = {
						{ label = "You've got this!", next = "gotit" },
						{ label = "What's your record?", next = "record" },
					},
				},
				gotit = {
					text = "Aw, that means a lot from a new face. Consider us officially friends!",
					choices = { { label = "Officially! 🤝", next = nil } },
				},
				record = {
					text = "Faster than yesterday — that's the only record that counts. Nice to meet you!",
					choices = { { label = "Love that. 🙂", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "Hey hey! Guess who shaved four seconds off? Me. I'm telling everyone, especially you.",
					choices = {
						{ label = "Incredible! 🎉", next = "yay" },
						{ label = "Race me sometime?", next = "race" },
					},
				},
				yay = {
					text = "Right?! Okay your turn — go beat your own time. I believe in you!",
					choices = { { label = "Challenge accepted!", next = nil } },
				},
				race = {
					text = "Oh it's ON. Loser buys protein shakes. Friendly stakes only, of course. 😏",
					choices = { { label = "You're on! 🏁", next = nil } },
				},
			},
		},
	},
	-- ===== Cyclists (bikes) =====
	{
		Id = "lucas",
		Name = "Lucas",
		Gender = "male",
		Type = "Cyclist",
		Station = Vector3.new(-50, 23, -47),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "WOO! Hey! Lucas here — spin class is my whole personality. You feeling the energy?!",
					choices = {
						{ label = "Let's GO! 🔥", next = "go" },
						{ label = "Easy, it's morning! 😅", next = "easy" },
					},
				},
				go = {
					text = "THAT'S what I'm talking about! New friend, new energy. Love it here!",
					choices = { { label = "Same! 🙌", next = nil } },
				},
				easy = {
					text = "Hahaha fair, fair — I'll bring you a coffee first next time, friend!",
					choices = { { label = "Deal! ☕", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "MY FRIEND! Back for more punishment? I mean... fun. It's fun. Climb's in five!",
					choices = {
						{ label = "Bring the climb! ⛰️", next = "climb" },
						{ label = "Five minutes of peace first?", next = "peace" },
					},
				},
				climb = {
					text = "YES! Legs of steel, that's us. Save some energy to celebrate after!",
					choices = { { label = "Always! 🎉", next = nil } },
				},
				peace = {
					text = "Hah, you've earned it. Catch your breath — I'll be right here being loud.",
					choices = { { label = "Never change. 😂", next = nil } },
				},
			},
		},
	},
	{
		Id = "sofia",
		Name = "Sofia",
		Gender = "female",
		Type = "Cyclist",
		Station = Vector3.new(-5, 23, -47),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hello. I'm Sofia — I cycle to clear my head. It's quieter up here. You seem kind.",
					choices = {
						{ label = "That's so calming.", next = "calm" },
						{ label = "Mind if I join the quiet?", next = "join" },
					},
				},
				calm = {
					text = "It really is. I think we'll get along just fine. New friend, gentle pace.",
					choices = { { label = "Gentle pace. 🌿", next = nil } },
				},
				join = {
					text = "Please do. Good company is rare. Consider yourself a friend of mine.",
					choices = { { label = "Honoured. 🙂", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "Oh, it's you — my favourite calm in the chaos. How's your heart today, friend?",
					choices = {
						{ label = "Lighter, seeing you.", next = "light" },
						{ label = "Bit heavy, honestly.", next = "heavy" },
					},
				},
				light = {
					text = "That's the nicest thing I'll hear all day. Ride easy with me a while.",
					choices = { { label = "Always. 🌸", next = nil } },
				},
				heavy = {
					text = "Then we pedal slow and breathe. No rush here. I've got you.",
					choices = { { label = "Thank you. 💛", next = nil } },
				},
			},
		},
	},
	{
		Id = "marcus",
		Name = "Marcus",
		Gender = "male",
		Type = "Cyclist",
		Station = Vector3.new(-28, 23, -83),
		Yaw = 180,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hey! Marcus. Did you know this bike has a flywheel that— sorry, I nerd out. Hi!",
					choices = {
						{ label = "Tell me everything!", next = "everything" },
						{ label = "Ha, you really love bikes.", next = "love" },
					},
				},
				everything = {
					text = "Oh we are going to be GREAT friends. I've got so many facts for you.",
					choices = { { label = "Can't wait! 🚲", next = nil } },
				},
				love = {
					text = "Guilty! Two wheels, one happy guy. Lovely to meet a patient new friend.",
					choices = { { label = "Likewise! 😄", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "My friend returns! I upgraded my pedals. PEDALS. Do you want to hear about it?",
					choices = {
						{ label = "Obviously yes.", next = "yes" },
						{ label = "Maybe after the workout? 😅", next = "after" },
					},
				},
				yes = {
					text = "You're the best. Clipless, carbon, chef's kiss. Okay, go ride, I'll save the rest.",
					choices = { { label = "Haha later! 👋", next = nil } },
				},
				after = {
					text = "Fair, fair. I'll prepare slides. Kidding. Mostly. Enjoy the ride, friend!",
					choices = { { label = "You too! 🚴", next = nil } },
				},
			},
		},
	},
	-- ===== Lifters (benches + dumbbells) =====
	{
		Id = "bianca",
		Name = "Bianca",
		Gender = "female",
		Type = "Lifter",
		Station = Vector3.new(-50, 23, -95),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hey, you! Bianca. I'm the one who'll cheer way too loud when you hit a PR. Hi!",
					choices = {
						{ label = "I could use a hype woman!", next = "hype" },
						{ label = "Those are big weights! 😳", next = "weights" },
					},
				},
				hype = {
					text = "Then you found her! Spot you, hype you, befriend you — full package. Deal?",
					choices = { { label = "Deal! 🙌", next = nil } },
				},
				weights = {
					text = "Started with the tiny ones too, promise. You'll get there. New friend, new gains!",
					choices = { { label = "Thanks, Bianca! 💪", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "THERE they are! My favourite lifter. Tell me you slept and ate. Tell me!",
					choices = {
						{ label = "Eight hours, big breakfast.", next = "good" },
						{ label = "...coffee counts, right?", next = "coffee" },
					},
				},
				good = {
					text = "THAT'S my friend! Recovery is a flex. Now go move something heavy.",
					choices = { { label = "Yes coach! 🏋️", next = nil } },
				},
				coffee = {
					text = "Coffee is not a food group, you menace. Love you. Eat a banana. Then lift.",
					choices = { { label = "Fine, fine! 🍌", next = nil } },
				},
			},
		},
	},
	{
		Id = "diego",
		Name = "Diego",
		Gender = "male",
		Type = "Lifter",
		Station = Vector3.new(-28, 23, -95),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Oh, hello. I'm Diego. I look scary but I promise I'm a big softie. Need a spot?",
					choices = {
						{ label = "Maybe later, thanks!", next = "later" },
						{ label = "A gentle giant, huh?", next = "gentle" },
					},
				},
				later = {
					text = "Anytime. I'm always around. Nice to meet you, friend — truly.",
					choices = { { label = "You too, Diego. 🙂", next = nil } },
				},
				gentle = {
					text = "Heh. My plants would agree. Glad to have a new friend in here.",
					choices = { { label = "Same! 🌱", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "My friend. Good to see your face. The bench is warm if you want it.",
					choices = {
						{ label = "How are the plants?", next = "plants" },
						{ label = "Spot me today?", next = "spot" },
					},
				},
				plants = {
					text = "Thriving. New little fern named after you, actually. Don't make it weird. Heh.",
					choices = { { label = "Honoured! 🌿", next = nil } },
				},
				spot = {
					text = "Always. I've got you — never let a friend lift alone. Go on, set up.",
					choices = { { label = "Thanks, big guy. 💪", next = nil } },
				},
			},
		},
	},
	{
		Id = "hana",
		Name = "Hana",
		Gender = "female",
		Type = "Lifter",
		Station = Vector3.new(-5, 23, -95),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hi. Hana. I lift heavy and talk straight, but I'm warmer than I look. You good?",
					choices = {
						{ label = "Teach me sometime?", next = "teach" },
						{ label = "Straight talk, I respect it.", next = "respect" },
					},
				},
				teach = {
					text = "Form first, ego never. Show up and I'll show you. New friend, fair warning: I'm strict.",
					choices = { { label = "I'll show up! 🫡", next = nil } },
				},
				respect = {
					text = "Good. We'll get along. No nonsense, lots of heart. Welcome, friend.",
					choices = { { label = "Glad to know you. 🙂", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "You're back. Good. Warm up properly this time — I saw you skip it last week.",
					choices = {
						{ label = "Caught me. I'll warm up.", next = "warm" },
						{ label = "You watch THAT closely? 😅", next = "watch" },
					},
				},
				warm = {
					text = "Smart. Friends keep friends injury-free. Now — let's see that deadlift.",
					choices = { { label = "Watching the form! 🏋️", next = nil } },
				},
				watch = {
					text = "I watch the people I care about. That's you now. Deal with it. Warm up.",
					choices = { { label = "Okay, okay! 😄", next = nil } },
				},
			},
		},
	},
	-- ===== Floor (mats: yoga / calisthenics) =====
	{
		Id = "noah",
		Name = "Noah",
		Gender = "male",
		Type = "Floor",
		Station = Vector3.new(-39, 23, -131),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hey, peaceful soul. I'm Noah — yoga, calisthenics, lots of breathing. Welcome in.",
					choices = {
						{ label = "I could use some calm.", next = "calm" },
						{ label = "Teach me a pose?", next = "pose" },
					},
				},
				calm = {
					text = "You're in the right corner. Breathe with me sometime. Glad we met, friend.",
					choices = { { label = "Me too. 🧘", next = nil } },
				},
				pose = {
					text = "We'll start with 'comfortable'. Revolutionary, I know. Happy to have a new friend.",
					choices = { { label = "Ha! Thanks Noah. 🙏", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "Ah, my friend. Your shoulders are at your ears again. Drop them. Breathe. Better?",
					choices = {
						{ label = "Whoa — much better.", next = "better" },
						{ label = "How did you even notice?", next = "notice" },
					},
				},
				better = {
					text = "See? Free of charge. Roll out a mat, let's loosen up together.",
					choices = { { label = "Let's flow. 🧘", next = nil } },
				},
				notice = {
					text = "I notice my friends. That's the whole practice, really. Now — exhale.",
					choices = { { label = "Exhaling... 😌", next = nil } },
				},
			},
		},
	},
	{
		Id = "aisha",
		Name = "Aisha",
		Gender = "female",
		Type = "Floor",
		Station = Vector3.new(-16, 23, -119),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hi hi! I'm Aisha — pilates and good vibes only. You have a lovely gym aura, you know!",
					choices = {
						{ label = "Good vibes back at you!", next = "vibes" },
						{ label = "My... aura? 😄", next = "aura" },
					},
				},
				vibes = {
					text = "Yes! Instant friends, I can tell. This corner just got brighter.",
					choices = { { label = "Aww! ✨", next = nil } },
				},
				aura = {
					text = "Mhm! Very 'about to crush a workout'. I read these things. Welcome, friend!",
					choices = { { label = "Haha thank you! 😊", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "There's my sunshine! Okay be honest — water today, or just vibes and hope?",
					choices = {
						{ label = "Hydrated and proud!", next = "hydrated" },
						{ label = "...vibes and hope. 😬", next = "vibes" },
					},
				},
				hydrated = {
					text = "That's the spirit! Glowing AND functional. Roll out next to me, friend.",
					choices = { { label = "Coming! 🧘‍♀️", next = nil } },
				},
				vibes = {
					text = "Hahaha go drink water, you gorgeous disaster. Then come stretch with me!",
					choices = { { label = "On my way! 💧", next = nil } },
				},
			},
		},
	},
	{
		Id = "sam",
		Name = "Sam",
		Gender = "male",
		Type = "Floor",
		Station = Vector3.new(-5, 23, -131),
		Yaw = 0,
		Intro = {
			start = "hi",
			nodes = {
				hi = {
					text = "Hey! Sam. Currently on push-up number... I lost count. Talk to me, save me. Hi!",
					choices = {
						{ label = "Rescuing you now. 😄", next = "rescue" },
						{ label = "Push-ups are evil.", next = "evil" },
					},
				},
				rescue = {
					text = "My hero! See, instant friends. The floor is ours, welcome to the struggle.",
					choices = { { label = "Glad to join! 😂", next = nil } },
				},
				evil = {
					text = "FINALLY someone gets it. We'll suffer together — that's friendship, right?",
					choices = { { label = "The truest kind! 🤝", next = nil } },
				},
			},
		},
		Friend = {
			start = "hey",
			nodes = {
				hey = {
					text = "My partner in suffering returns! I invented a new excuse to skip core. Wanna hear?",
					choices = {
						{ label = "Absolutely I do.", next = "hear" },
						{ label = "No excuses — plank with me!", next = "plank" },
					},
				},
				hear = {
					text = "'My arms are still tired from existing.' ...Okay even I don't buy it. Floor time!",
					choices = { { label = "Hahaha let's go! 😆", next = nil } },
				},
				plank = {
					text = "Ugh, a friend who holds me accountable. The worst. The best. Fine — together!",
					choices = { { label = "Together! 💪", next = nil } },
				},
			},
		},
	},
} :: { FriendDef }

return GymFriends
