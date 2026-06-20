--!strict
-- Runners (treadmills). Three gym friends with Intro/Friend dialog trees.

local Defs = require(script.Parent.Defs)

return {
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
} :: { Defs.FriendDef }
