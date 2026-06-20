--!strict
-- Lifters (benches + dumbbells). Three gym friends with Intro/Friend dialog trees.

local Defs = require(script.Parent.Defs)

return {
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
} :: { Defs.FriendDef }
