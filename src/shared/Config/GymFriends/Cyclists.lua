--!strict
-- Cyclists (bikes). Three gym friends with Intro/Friend dialog trees.
--
-- A bike's flywheel juts toward the saddle, so a friend standing on the bike's centre clips the
-- wheel. Their station sits ~2.5 studs behind the saddle (the bikes face +Z, saddle on the -Z
-- side) so they stand just behind their bike facing it (Yaw 180) -- clear of the wheel. Bike
-- centres are at Z = -47 / -83 (see Config.Gym.Stations); these are offset to -49.5 / -85.5.

local Defs = require(script.Parent.Defs)

return {
	{
		Id = "lucas",
		Name = "Lucas",
		Gender = "male",
		Type = "Cyclist",
		Station = Vector3.new(-50, 23, -49.5),
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
		Station = Vector3.new(-5, 23, -49.5),
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
		Station = Vector3.new(-28, 23, -85.5),
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
} :: { Defs.FriendDef }
