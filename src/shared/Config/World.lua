--!strict
-- World layout: zone origins, travel destinations, code-generated ground, and ground roads
-- (WorldService, RoadService, IslandService, PlaceService, TravelController).

local World = {}

-- World zone origins. MVP keeps Home/Airport/Beach as zones in one place; "travel"
-- repositions the player between these origins (Airport is the transit waypoint where the
-- boarding minigame runs).
World.Zones = {
	Home = Vector3.new(0, 0, 0),
	Airport = Vector3.new(0, 0, 560),
	Beach = Vector3.new(0, 0, 980), -- pushed out into the lake so it stays a separate island from the
	-- enlarged airport apron (~130 studs of water between them; reached by travel, not on foot)
	Farm = Vector3.new(320, 0, -140), -- zone origin; matches Config.Farm.Center
} :: { [string]: Vector3 }

-- Travel destinations selectable from the Cab picker. A place is travelable only if it is in
-- the player's UnlockedPlaces. Arrival is the follower reward for arriving there.
World.Places = {
	Home = { Zone = World.Zones.Home, Arrival = 0 },
	Beach = { Zone = World.Zones.Beach, Arrival = 50 },
} :: { [string]: { Zone: Vector3, Arrival: number } }

-- Code-generated ground per zone (WorldService paints it at startup). Terrain voxels don't
-- round-trip through Rojo, so the *generating values* live here and the world stays reproducible
-- from src. Lots stay apart so zones don't become walkable-connected (which would bypass the travel
-- system): the Home neighborhood (streets out to +/-228) sits on a grass island ringed by a water moat
-- and then a sheer ~100-stud rock mountain (Ring, below) that reaches out to ~+/-420 and walls the
-- town in. Airport (560 away) +/-60 clears the mountain. The rendered top of each slab sits at the
-- zone floor level (Y=0).
--
-- Home is a 3x3 neighborhood grid: nine CellSize squares on a Pitch (cell + road) lattice, so cell
-- centers sit at (i-1)*Pitch for i in {0,1,2} = {-Pitch, 0, Pitch}. The center square is the spawn
-- plaza; the eight surrounding squares hold one house each (one is left as a park, see ParkCell).
-- Roads run along the gaps between squares (lines at +/-RoadLine on both axes) and around the
-- outside (lines at +/-PerimeterLine), so the streets form a closed grid with no dead ends and cars
-- can drive a full loop. Each house gets a driveway to its facing inner road and the rest of its
-- square stays grass (the garden). Ring describes the island/moat/mountain and the elevated oval
-- highway that circles the town (built by WorldService terrain + IslandService parts).
World.Terrain = {
	Thickness = 8, -- vertical depth of each painted ground slab
	Home = {
		Size = 540, -- grassy lot enclosing the grid + perimeter loop (+/-228) with a small margin
		Ground = Enum.Material.Grass,
		Sidewalk = Enum.Material.Concrete,
		Driveway = Enum.Material.Concrete,
		CellSize = 60, -- side of each square lot
		Pitch = 144, -- cell-center spacing (CellSize + the gap: road 24 + a 30-wide walkway each side)
		RoadLine = 72, -- |coord| of the two internal roads per axis (= Pitch/2, the gaps between squares)
		PerimeterLine = 216, -- |coord| of the outer loop road that closes the grid (= Pitch*1.5, no dead ends)
		RoadWidth = 24, -- two-lane asphalt down the middle of each gap (cars pass both ways)
		DrivewayWidth = 10, -- carway from a house to its facing road
		ParkCell = Vector3.new(0, 0, 144), -- the one perimeter square left as grass (no house); = (0, Pitch)
		-- The island and its surroundings (concentric elliptical bands, semi-axes a=X, b=Z): a grass
		-- Plateau in a wide water lake, with an elevated Oval highway hugging the island and joined to
		-- the perimeter loop by ramps. Lake inner = Plateau, outer = Plateau + Moat.Width; Airport and
		-- Beach sit in the lake as their own islands. Sizes in studs.
		Ring = {
			Plateau = { Ax = 391, Az = 352 }, -- grass island bounding ellipse (contains the town)
			Moat = { Width = 2000, Depth = 45, Material = Enum.Material.Water }, -- ~2km lake (room for future islands)
			Oval = {
				Ax = 456, -- elevated highway ellipse (hugs the island: Plateau + ~65, clearing the wide decks)
				Az = 417,
				Y = 20, -- elevation above ground
				Width = 24, -- two-lane road, matches the streets
				Thickness = 1,
				DeckOverlap = 16, -- studs each deck chord overlaps its neighbours so the curve has no gaps
				Segments = 72, -- chord segments approximating the ellipse
				PillarEvery = 6, -- a support pillar every Nth segment
				PillarDiameter = 6,
				Ramps = 8, -- ground-to-oval links: 4 sides + 4 corners
				WalkwayWidth = 30, -- wide wood-deck promenade flanking each side (room for buildings)
				GuardrailHeight = 9, -- taller than a player + jump apex, so nobody jumps off the deck
				GuardrailThickness = 0.5,
				GuardrailOverlap = 8, -- studs each rail panel overlaps its neighbours; like DeckOverlap, closes
				-- the miter slivers where straight panels offset outward on the curve would otherwise gap (fall-through)
				ViewDeckEvery = 9, -- a panoramic view deck every Nth segment (9 -> one per 45 degrees)
				ViewDeckDepth = 16, -- how far each view deck juts out past the outer guardrail
			},
		},
	},
	Airport = {
		-- The apron is a wide rectangle skewed toward +Z so it sits under the whole airport-town
		-- build-out (terminals, control tower, hotel, cargo, shops, car rental...), which sprawls
		-- X ~ +/-270 and Z ~ +570..+770 in world space -- far beyond the old 120-stud square. Offset
		-- shifts the slab centre north of the zone origin to match where that cluster actually sits.
		SizeX = 560,
		SizeZ = 235,
		Offset = Vector3.new(0, 0, 110),
		Ground = Enum.Material.Asphalt,
	},
	Beach = {
		Size = 120, -- sand, with ocean water painted just beyond the far (+Z) edge
		Ground = Enum.Material.Sand,
		Water = Enum.Material.Water,
		WaterDepth = 60,
	},
}

-- Ground road network (RoadService lays these parts over the grass). The lane geometry derives from
-- the grid lines in Config.Terrain.Home (RoadLine / PerimeterLine / RoadWidth); these are the visual
-- tunables: how thick the asphalt sits over the grass, how much each junction rounds its corners, and
-- the lane-marking / curb dimensions.
World.Roads = {
	Thickness = 0.4, -- asphalt slab height above the grass surface (Y=0)
	Fillet = 10, -- extra radius at each junction so corners curve instead of meeting square; must exceed
	-- ~5 (RoadWidth 24, CurbWidth 30 -> corner tip at sqrt(2)*12) so the disc pokes past the walkway corner
	LaneLineWidth = 0.7, -- width of the dashed centre line
	DashLength = 9, -- length of each centre-line dash
	DashGap = 9, -- gap between dashes
	CurbWidth = 30, -- wide concrete walkway flanking each road edge (room to walk + place buildings)
	CurbHeight = 0.6, -- low enough to step/drive over, high enough to read as a curb
}

return World
