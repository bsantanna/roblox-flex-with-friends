--!strict
-- Tree01 forest scattered over the Home island's grass (ForestService clones the uploaded mesh --
-- see assets/manifest.json's scatter entry). Layout is deterministic from Seed, and every site is
-- derived from the Terrain.Home grid, so trees keep off roads, walkways, driveways, houses, and the
-- highway ramps by construction.
local Forest = {
	Seed = 7,
	Spacing = 24, -- candidate-site pitch across the green belt
	Jitter = 8, -- random per-site offset, so the grid doesn't read as rows
	ScaleMin = 9, -- mesh is ~1.9 units tall -> trees ~17..25 studs
	ScaleMax = 13,
	RoadMargin = 4, -- extra grass between the walkway edge and the first belt tree
	ShoreMargin = 14, -- keep canopies off the waterline
	RampClearance = 26, -- half-width of the tree-free corridor under each ground-to-highway ramp
	ParkSpacing = 16, -- denser grove on the park square
	ParkInset = 12, -- keeps park sites (incl. their smaller jitter) inside the square's grass
	GardenInset = 23, -- house-garden corner trees: outside the house, clear of the driveway
}

return Forest
