--!strict
-- The farm: a fenced paddock on the Home island's north-east green belt (FarmService builds it). The
-- pen footprint was chosen in Studio to sit on grass, clear of the perimeter road, the elevated ring
-- highway/walkway, and the shoreline; it encloses a few of the belt's scattered trees as pasture
-- shade. Center is Home-relative (grass surface Y=0); Size is the X-by-Z interior. The white
-- post-and-rail fence is built from primitives (like the gym equipment). Animals are cloned from
-- ReplicatedStorage.Shared.FarmModels templates and gently wander inside the rails; until those
-- templates exist the populate step skips, so a pending model never breaks boot.
local Farm = {
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
			{ Kind = "Cow", Count = 2 },
			{ Kind = "Sheep", Count = 2 },
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

return Farm
