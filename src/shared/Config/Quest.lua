--!strict
-- Quest tunables for "The Pilot's Forgotten Packages" (Quest 002), the game's first quest. Every
-- magic number the quest needs lives here (golden rule 3): the Pilot quest-giver's post/outfit, the
-- timer, the package positions, the beacon visuals, the reward, the pose emotes, the fast-travel
-- drop-offs, and the cutscene camera keyframes. QuestService and the quest controllers read it all
-- from this module. See docs/dev/quests/002_pilot_missing_fligt.md.

local Quest = {}

-- Persisted completion key (Profile.Data.CompletedQuests[Id]); a one-time story quest.
Quest.Id = "PilotPackages"

-- The Pilot quest-giver. Stands in the arrivals terminal (Zone "Airport", floor Y=1.1) on open floor
-- by the gates -- clear of the central bar (behind) and the seating (ahead), facing the player arrival
-- point so the gate + runway sit behind him as the cutscene backdrop. Post + facing were Studio-verified
-- (the bar/seats occupy the hall centre; this spot reads cleanly). The outfit reuses verified catalog
-- ids (the Postman's White Star Line officer cap + a white tank + navy uniform pants).
Quest.Pilot = {
	NpcId = "Pilot",
	Zone = "Airport",
	AvatarUserId = 1, -- Roblox default avatar, dressed via Outfit (matches the whole roster)
	SpawnPosition = Vector3.new(0, 1.1, 690),
	SpawnYaw = 180, -- face +Z toward arriving players; the gate + runway frame the cutscene behind him
	Outfit = {
		Hats = { 13383061629 }, -- White Star Line Officer Cap
		Layered = {
			{ AssetId = 131452039626817, Type = Enum.AccessoryType.TShirt }, -- White Tank Top
			{ AssetId = 140048946599540, Type = Enum.AccessoryType.Pants }, -- navy uniform pants
		},
	},
}

-- The Pilot quest's config is the top-level Quest table (getQ returns it for PilotPackages), so its NPC
-- identity must be readable flat here -- the same shape FirstQuest uses. Mirror it from Quest.Pilot (single
-- source) so QuestService/CutsceneController can resolve the giver via cfg.NpcId / cfg.Zone for either quest.
Quest.NpcId = Quest.Pilot.NpcId
Quest.Zone = Quest.Pilot.Zone

-- The 2-minute collection window; starts when the player arrives in the city, enforced server-side.
Quest.TimeLimitSeconds = 120

-- Followers granted once on delivery (full-quest scale; minigames clear ~150-200). One-time only.
Quest.Reward = 200

-- Key into TrophyService's TROPHY_DEFS for the one-time completion trophy (pilot_delivery).
Quest.TrophyNpcId = "Pilot"

-- The 4 packages to collect, at the four internal road crossings of the Home grid -- open asphalt, one
-- per quadrant around the central plaza, ~100 studs from the spawn (well within the timer on foot). The
-- (+/-120, +/-120) house-square corners were rejected in Studio: two sat under Forest trees.
Quest.PackagePositions = {
	Vector3.new(72, 0, 72),
	Vector3.new(-72, 0, 72),
	Vector3.new(72, 0, -72),
	Vector3.new(-72, 0, -72),
}
Quest.CollectRadius = 14 -- studs; server validates the player's real root is within this of a package

-- Player-facing quest labels (QuestController reads the active quest's): the HUD objective icon, the
-- beacon prompt's object name, and the "return to the giver" HUD line shown once everything is collected.
Quest.ObjectiveIcon = "📦"
Quest.CollectableName = "Package"
Quest.ReturnLabel = "Deliver to the Pilot!"

-- Objective beacon visuals (client-rendered per QuestController): a neon pickup part at the package
-- position with a light + particles and a beam shooting skyward, gently pulsing. Tuned by looking in
-- Studio (top-down for placement, eye-level for scale, close-up at the ground seam).
Quest.Beacon = {
	Color = Color3.fromRGB(255, 210, 70), -- warm gold
	PartSize = Vector3.new(2, 2, 2),
	PartHeight = 3, -- centre height of the pickup part above the package position
	BeamHeight = 40, -- top attachment height for the skyward beam
	BeamWidth = 4,
	LightRange = 18,
	LightBrightness = 4,
	ParticleRate = 14,
	SpinSpeed = 60, -- degrees/sec the pickup part rotates
}

-- NPC pose emotes (Roblox default emote ids, placeholders like the rest of the roster), swapped here
-- without touching logic. "Worried" has no default emote; "point" reads as an anxious gesture.
Quest.Pose = {
	Worried = "rbxassetid://507770453", -- point (anxious gesturing during the intro)
	Happy = "rbxassetid://507770677", -- cheer (the grateful ending)
}

-- Dialogue (short, warm, encouraging for a young audience). Spoken via the server-side SpeechBubble so
-- all nearby players see the lines; only the interacting player gets the Accept/Decline choice.
Quest.Lines = {
	Intro = {
		"Oh no... my flight leaves in two minutes and I left four packages back in the city!",
		"I was so busy helping everyone this morning... could you be my hero and grab them?",
	},
	Accepted = "You're a lifesaver! Open your phone and fly to the city -- hurry back!",
	Declined = "No worries at all -- come find me if you change your mind!",
	Nudge = "Any luck with those packages? The city's just a phone tap away!",
	Returned = "You made it just in time -- thank you! The flight can leave on schedule.",
	Ending = "You're not just helpful, you're reliable and kind. That's what makes the world better!",
	Fail = "Ah, they slipped away this time -- no worries. Thanks for trying, friend!",
	Replay = "Thanks again, hero! Those packages made it home safe because of you.",
}
Quest.LineHoldSeconds = 4 -- how long each spoken line stays up

-- Encouraging toast shown on the player's screen as each package is collected, indexed by the running
-- count (1..4). Kept warm and short for the young audience.
Quest.CollectToasts = {
	"Nice find! 🎉",
	"Two down -- keep going!",
	"Almost there!",
	"That's all four -- back to the Pilot!",
}

-- Cutscene camera keyframes (CutsceneController). All eye/target/positions below are WORLD offsets
-- added to the Pilot's position (rule 3) so framing is tuned without editing the controller. The Pilot
-- faces +Z; the apron/runway sits behind him toward -Z, so the plane takes off out over it. Every
-- offset is a first pass -- a CFrame that type-checks can still point at a wall, so these are verified
-- and tuned visually in Studio.
Quest.Cutscene = {
	-- "Intro": a simple two-beat pan over the fretting Pilot.
	TweenSeconds = 2.5,
	Intro = {
		{ eye = Vector3.new(14, 6, 14), target = Vector3.new(0, 3, 0) },
		{ eye = Vector3.new(7, 4, 9), target = Vector3.new(0, 3, 0) },
	},
	-- "Ending": a staged, personal (client-local) cinematic. The Pilot waves, a Pilot clone boards a
	-- throwaway plane, the plane taxis and takes off out over the apron, then a tight "Mission Complete"
	-- cockpit close-up. Only the questing player sees the plane/clone; the real shared Pilot is hidden
	-- locally for the duration.
	Ending = {
		ClimbPitch = 14, -- degrees nose-up through the climb-out
		-- Farewell frames the waving Pilot, so its camera is offset from the PILOT's post. The Pilot
		-- stands inside the glass terminal; he can't walk out to the plane, so after he waves we cut (on a
		-- fade) to the plane already out on the runway -- the boarding is implied.
		Farewell = {
			Seconds = 3,
			Cam = { eye = Vector3.new(6, 4, 9), target = Vector3.new(0, 3, 0) },
		},
		-- The plane lives on the real runway, so its path + the taxi/takeoff/cockpit framing are offsets
		-- from the RUNWAY centre (Config.Zones.Airport). It takes off along +X out over the lake, the same
		-- heading as the ambient fleet. Studio-verified against the runway geometry.
		Plane = {
			Start = Vector3.new(-180, 2.5, 0), -- threshold, nose facing +X (toward RollTo)
			TaxiTo = Vector3.new(-120, 2.5, 0), -- end of the slow taxi roll
			RollTo = Vector3.new(60, 2.5, 0), -- rotate / lift-off point
			ClimbTo = Vector3.new(320, 110, 0), -- climb-away end, high over the lake
		},
		Taxi = {
			Seconds = 2.5,
			Cam = { eye = Vector3.new(-150, 14, 70), target = Vector3.new(-150, 4, 0) },
		},
		Takeoff = {
			Seconds = 5,
			Cam = { eye = Vector3.new(-40, 30, 90), target = Vector3.new(80, 25, 0) },
		},
		-- Cockpit: a tight close-up of the smiling Pilot clone, posed high over the runway against the sky.
		Cockpit = {
			Seconds = 3.5,
			PilotSpot = Vector3.new(320, 110, 0),
			Cam = { eye = Vector3.new(320, 111, 7), target = Vector3.new(320, 110.5, 0) },
		},
	},
}

-- GTA-style "Mission Complete" banner (CutsceneController), shown during the cockpit beat.
Quest.MissionComplete = {
	Title = "MISSION COMPLETE!",
	Subtitle = "Packages delivered safely.",
	-- First completion shows the reward; replays (reward 0) show the warm line instead.
	RewardSuffix = " Followers   ✈ Delivery Hero",
	ReplayLine = "Thanks for your help, hero!",
}

-- Quest 003 "Tim's Lost Lunch Box" (FirstQuest). Tim is in the central plaza near the Postman,
-- in the Home zone. He left his lunch box at the airport terminal and needs the player to
-- retrieve it. This quest has a hard gate: the player must already hold the taxi_driver_mobility
-- trophy (earned from the TaxiDriver minigame) before Tim will talk to them. Single box to collect
-- at the Airport terminal, shorter timer than the Pilot (90s vs 120s).
Quest.FirstQuest = {
	NpcId = "FirstQuest",
	Zone = "Home",
	AvatarUserId = 1, -- Roblox default avatar, dressed via Outfit
	SpawnPosition = Vector3.new(55, 0, -45), -- central plaza, NE of the Postman's post
	SpawnYaw = 180, -- face south toward player approach from the plaza
	Outfit = { -- casual look: blue tee + jeans
		Hats = { 78174478860906 }, -- Black Shelby Vintage Cap
		Layered = {
			{ AssetId = 140799784089779, Type = Enum.AccessoryType.Shirt }, -- Sky Blue T-Shirt
			{ AssetId = 113643430156923, Type = Enum.AccessoryType.Pants }, -- Western Jeans
		},
	},
	-- Hard gate: player must hold this trophy before Tim will talk.
	RequiredTrophies = { "taxi_driver_mobility" },
	-- The single lunch box to retrieve, at the Airport terminal arrivals area.
	-- The Airport zone origin is at (0, 0, 0) in world space; this is near the glass doors.
	CollectPosition = Vector3.new(0, 1.5, 690),
	CollectRadius = 14, -- studs
	BoxHeight = 3, -- centre height of the pickup part above the collect position
	TotalCollectibles = 1,
	ObjectiveIcon = "🥪",
	CollectableName = "Lunch Box",
	ReturnLabel = "Bring it back to Tim!",
	TimeLimitSeconds = 90,
	Reward = 200,
	TrophyNpcId = "FirstQuest",
	Beacon = {
		Color = Color3.fromRGB(255, 140, 40), -- bright orange (lunch box)
		PartSize = Vector3.new(2.5, 2.5, 2.5),
		PartHeight = 3,
		BeamHeight = 40,
		BeamWidth = 4,
		LightRange = 18,
		LightBrightness = 4,
		ParticleRate = 14,
		SpinSpeed = 60,
	},
	Pose = {
		Worried = "rbxassetid://507770453", -- point (anxious gesturing during the intro)
		Happy = "rbxassetid://507770677", -- cheer (the grateful ending)
	},
	Lines = {
		Intro = {
			"Uh oh... I left my lunch box at the airport!",
			"I was so excited to see everyone off, I completely forgot it on the bench!",
			"Could you be a hero and bring it back to me? Please?",
		},
		Accepted = "Thank you so much! The airport is just a quick cab ride -- hurry!",
		Declined = "Oh... okay. Maybe next time, thanks for listening!",
		Nudge = "Did you make it to the airport yet? I'm getting hungry!",
		Returned = "You got my lunch box! I can't believe you did that so fast!",
		Ending = "You really are the kindest person I know. That lunch means the world to me!",
		Fail = "Aww, you didn't make it in time... but I appreciate you trying, friend!",
		Replay = "Thanks again for bringing my lunch back! I couldn't have done it without you!",
	},
	LineHoldSeconds = 4,
	CollectToasts = {
		"Got it! That's my lunch box! 🥪",
	},
	Cutscene = {
		TweenSeconds = 2.5,
		Intro = {
			{ eye = Vector3.new(14, 6, 14), target = Vector3.new(0, 3, 0) },
			{ eye = Vector3.new(7, 4, 9), target = Vector3.new(0, 3, 0) },
		},
		Ending = {
			-- Farewell frames Tim happily holding his lunch box.
			Farewell = {
				Seconds = 3,
				Cam = { eye = Vector3.new(6, 4, 9), target = Vector3.new(0, 3, 0) },
			},
		},
	},
	MissionComplete = {
		Title = "MISSION COMPLETE!",
		Subtitle = "Lunch box recovered safely.",
		RewardSuffix = " Followers   🥪 Lunch Hero",
		ReplayLine = "Thanks again for your kindness, hero!",
	},
}

return Quest
