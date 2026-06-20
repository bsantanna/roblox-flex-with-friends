--!strict
-- Floor (mats: yoga / calisthenics). Three gym friends with Intro/Friend dialog trees.

local Defs = require(script.Parent.Defs)

return {
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
} :: { Defs.FriendDef }
