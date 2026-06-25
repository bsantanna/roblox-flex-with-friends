-- Flower cluster placement. Scatters small flower clusters across the
-- Home zone's grass areas: green belt, park square, and house gardens.
-- Each cluster has one solid color chosen at random from a palette.
-- V4: Reduced sizes for better visual balance.

local Flowers = {}

Flowers.Seed = 42

-- Vibrant, high-contrast kid-friendly palette.
Flowers.Palette = {
	Color3.fromRGB(255, 60, 100), -- hot pink
	Color3.fromRGB(255, 120, 30), -- orange
	Color3.fromRGB(255, 220, 40), -- yellow
	Color3.fromRGB(200, 60, 255), -- purple
	Color3.fromRGB(255, 80, 80), -- bright red
	Color3.fromRGB(100, 200, 255), -- sky blue
}

Flowers.StemColor = Color3.fromRGB(60, 180, 50)

-- One cluster every ~8 studs in the green belt.
Flowers.Density = 8

-- Park square gets denser planting.
Flowers.ParkDensity = 5

-- House-garden corner offset from the cell centre (2×2 corners per house).
Flowers.GardenInset = 8

-- Stem tunables — reduced for more delicate look.
Flowers.MinStemHeight = 2.0
Flowers.MaxStemHeight = 3.0

-- Stem thickness — reduced from 0.4.
Flowers.StemWidth = 0.15

-- Head (petal ball) diameter — reduced from 3.0 for better proportions.
Flowers.HeadSize = 0.6

-- Base ring diameter — reduced from 1.5 to match smaller scale.
Flowers.BaseRingSize = 0.5

-- Each cluster gets this many heads (multiple heads = more impact per cluster).
Flowers.HeadsPerCluster = 3

return Flowers
