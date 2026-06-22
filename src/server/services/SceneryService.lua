--!strict
-- SceneryService: builds the visual scenery models in code from primitives — no Roblox AI / cloud.
-- Each model is parametric (assembled from blocks/cylinders/spheres), placed from Config.Zones plus
-- a per-model offset that mirrors assets/manifest.json (adjusted so nothing covers the spawn/roads).
-- This is the code implementation of the manifest's "buildable" assets; the manifest stays the
-- design spec, and AI-generated models can replace these later without changing placement. Models
-- live under Workspace.Scenery.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SceneryService = {}

local DARKWOOD = Color3.fromRGB(80, 55, 35)
local THATCH = Color3.fromRGB(169, 116, 79)
local WHITE = Color3.fromRGB(245, 245, 245)
local FROND = Color3.fromRGB(62, 142, 65)
local TRUNK = Color3.fromRGB(139, 90, 43)
local CUSHION = Color3.fromRGB(232, 213, 183)
-- Airport colors
local CONCRETE = Color3.fromRGB(185, 185, 190)
local GLASS_AIRPORT = Color3.fromRGB(160, 200, 230)
local YELLOW = Color3.fromRGB(255, 210, 50)

type PartOpts = { material: Enum.Material?, transparency: number?, shape: Enum.PartType? }

local function add(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	if o.shape then
		p.Shape = o.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A vertical cylinder (Cylinder's length is along local X, so rotate X->Y).
-- Used for tree trunks, cabana pillars, etc.
local function pillar(
	parent: Instance,
	base: CFrame,
	x: number,
	y: number,
	z: number,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
)
	add(
		parent,
		base * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, diameter, diameter),
		color,
		{
			shape = Enum.PartType.Cylinder,
			material = material,
		}
	)
end

-- Beach: cabana with palm tree and sun lounger.
local function buildBeachCabana(model: Model, base: CFrame)
	for _, sx in { -8, 8 } do
		for _, sz in { -8, 8 } do
			pillar(model, base, sx, 3.5, sz, 7, 0.8, DARKWOOD, Enum.Material.Wood)
		end
	end
	add(model, base * CFrame.new(0, 7.4, 0), Vector3.new(20, 1.2, 20), THATCH, { material = Enum.Material.Grass })
	add(model, base * CFrame.new(0, 8.4, 0), Vector3.new(13, 1, 13), THATCH, { material = Enum.Material.Grass }) -- tiered peak
	add(model, base * CFrame.new(0, 1.6, -7), Vector3.new(12, 3, 2), DARKWOOD, { material = Enum.Material.Wood }) -- bar counter
	for _, sx in { -8.1, 8.1 } do
		add(
			model,
			base * CFrame.new(sx, 3.5, 0),
			Vector3.new(0.3, 6, 14),
			WHITE,
			{ material = Enum.Material.Fabric, transparency = 0.25 }
		) -- curtains
	end
end

local function buildPalmTree(model: Model, base: CFrame)
	pillar(model, base, 0, 8, 0, 16, 1.6, TRUNK, Enum.Material.Wood) -- trunk
	for i = 0, 5 do
		local a = math.rad(i * 60)
		add(
			model,
			base * CFrame.new(math.cos(a) * 3.5, 15.5, math.sin(a) * 3.5) * CFrame.Angles(math.rad(20), -a, 0),
			Vector3.new(7, 0.4, 2.2),
			FROND,
			{ material = Enum.Material.Grass }
		) -- fronds
	end
	for _, sx in { -0.8, 0.8 } do
		add(model, base * CFrame.new(sx, 15, 0), Vector3.new(1, 1, 1), TRUNK, { shape = Enum.PartType.Ball }) -- coconuts
	end
end

local function buildSunLounger(model: Model, base: CFrame)
	add(model, base * CFrame.new(0, 0.7, 0), Vector3.new(3, 0.4, 7), DARKWOOD, { material = Enum.Material.Wood }) -- frame
	add(
		model,
		base * CFrame.new(0, 0.95, 0.3),
		Vector3.new(2.6, 0.4, 6.4),
		CUSHION,
		{ material = Enum.Material.Fabric }
	) -- cushion
	add(
		model,
		base * CFrame.new(0, 1.6, -3) * CFrame.Angles(math.rad(-35), 0, 0),
		Vector3.new(2.6, 0.4, 3),
		CUSHION,
		{ material = Enum.Material.Fabric }
	) -- backrest
	for _, sx in { -1.3, 1.3 } do
		for _, sz in { -3, 3 } do
			add(
				model,
				base * CFrame.new(sx, 0.25, sz),
				Vector3.new(0.3, 0.5, 0.3),
				DARKWOOD,
				{ material = Enum.Material.Wood }
			) -- legs
		end
	end
	add(model, base * CFrame.new(2.6, 0.75, -2), Vector3.new(1.4, 1.5, 1.4), WHITE) -- side table
	add(
		model,
		base * CFrame.new(2.6, 1.7, -2),
		Vector3.new(0.6, 0.8, 0.6),
		Color3.fromRGB(230, 120, 90),
		{ shape = Enum.PartType.Cylinder }
	) -- drink
end

-- ========== Airport buildings ==========

-- Terminal B: a second terminal building, slightly narrower with green accent.
local function buildAirportTerminalB(model: Model, base: CFrame)
	local GREEN_ACCENT = Color3.fromRGB(45, 150, 80)
	-- Back wall.
	add(model, base * CFrame.new(0, 5, 4), Vector3.new(18, 10, 0.5), CONCRETE, { material = Enum.Material.Concrete })
	-- Side walls.
	add(model, base * CFrame.new(-9, 5, 0), Vector3.new(0.5, 10, 8), CONCRETE, { material = Enum.Material.Concrete })
	add(model, base * CFrame.new(9, 5, 0), Vector3.new(0.5, 10, 8), CONCRETE, { material = Enum.Material.Concrete })
	-- Front wall panels (door in center).
	add(model, base * CFrame.new(-4.5, 5, -4), Vector3.new(4, 10, 0.5), CONCRETE, { material = Enum.Material.Concrete })
	add(model, base * CFrame.new(4.5, 5, -4), Vector3.new(4, 10, 0.5), CONCRETE, { material = Enum.Material.Concrete })
	add(model, base * CFrame.new(0, 8.5, -4), Vector3.new(9, 3, 0.5), CONCRETE, { material = Enum.Material.Concrete }) -- top panel
	add(model, base * CFrame.new(0, 1.5, -4), Vector3.new(3, 4, 0.5), GREEN_ACCENT, { material = Enum.Material.Metal }) -- door
	-- Glass panels.
	for _, xOff in { -3.5, 0, 3.5 } do
		add(
			model,
			base * CFrame.new(xOff, 4.5, -4.1),
			Vector3.new(2.5, 5, 0.1),
			GLASS_AIRPORT,
			{ material = Enum.Material.Glass, transparency = 0.15 }
		)
	end
	-- Roof.
	add(
		model,
		base * CFrame.new(0, 10, 0),
		Vector3.new(18.5, 0.6, 8.5),
		CONCRETE,
		{ material = Enum.Material.Concrete }
	)
	-- "TERMINAL B" sign.
	add(model, base * CFrame.new(0, 11.5, 5), Vector3.new(10, 1.2, 0.5), GREEN_ACCENT)
	local signText = Instance.new("TextLabel")
	signText.Name = "Sign"
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = "TERMINAL B"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = model
	-- Canopy.
	add(
		model,
		base * CFrame.new(0, 3, -5.5),
		Vector3.new(4, 0.4, 2.5),
		GREEN_ACCENT,
		{ material = Enum.Material.Metal }
	)
end

-- Control tower: tall cylindrical tower with glass observation deck and antenna.
local function buildControlTower(model: Model, base: CFrame)
	local METAL = Color3.fromRGB(170, 175, 185)
	-- Tower shaft (main column).
	pillar(model, base, 0, 15, 0, 30, 3, METAL, Enum.Material.SmoothPlastic)
	-- Observation deck (wide cylinder at top).
	pillar(model, base, 0, 31, 0, 4, 6, Color3.fromRGB(130, 140, 150), Enum.Material.SmoothPlastic)
	-- Glass windows around observation deck.
	for i = 0, 7 do
		local a = math.rad(i * 45)
		add(
			model,
			base * CFrame.new(math.cos(a) * 3.5, 31, math.sin(a) * 3.5) * CFrame.Angles(0, -a, 0),
			Vector3.new(1.5, 2.5, 0.2),
			GLASS_AIRPORT,
			{ material = Enum.Material.Glass, transparency = 0.2 }
		)
	end
	-- Antenna/spire on top.
	pillar(model, base, 0, 34, 0, 6, 0.3, Color3.fromRGB(200, 50, 50))
	-- Beacon light on antenna tip.
	add(
		model,
		base * CFrame.new(0, 37, 0),
		Vector3.new(0.8, 0.8, 0.8),
		Color3.fromRGB(255, 200, 50),
		{ material = Enum.Material.Neon, shape = Enum.PartType.Ball }
	)
end

-- Baggage building: large industrial warehouse with hangar doors.
local function buildBaggageBuilding(model: Model, base: CFrame)
	-- Main body (large rectangular box).
	add(
		model,
		base * CFrame.new(0, 5, 0),
		Vector3.new(28, 10, 12),
		Color3.fromRGB(150, 155, 165),
		{ material = Enum.Material.Concrete }
	)
	-- Roof overhang.
	add(model, base * CFrame.new(0, 10, 0), Vector3.new(30, 0.5, 13), Color3.fromRGB(130, 135, 145))
	-- Hangar doors (two large doors at center).
	add(
		model,
		base * CFrame.new(-4, 3, -6.1),
		Vector3.new(5, 6, 0.3),
		Color3.fromRGB(200, 180, 80),
		{ material = Enum.Material.Metal }
	)
	add(
		model,
		base * CFrame.new(4, 3, -6.1),
		Vector3.new(5, 6, 0.3),
		Color3.fromRGB(200, 180, 80),
		{ material = Enum.Material.Metal }
	)
	-- Small office window.
	add(
		model,
		base * CFrame.new(8, 7, -6.1),
		Vector3.new(2, 2, 0.1),
		GLASS_AIRPORT,
		{ material = Enum.Material.Glass, transparency = 0.15 }
	)
	-- Loading dock ramp.
	add(model, base * CFrame.new(0, 1, -10), Vector3.new(8, 2, 4), Color3.fromRGB(160, 160, 165))
	-- "BAGGAGE" sign.
	add(model, base * CFrame.new(0, 9.5, 0.16), Vector3.new(6, 0.8, 0.1), Color3.fromRGB(45, 100, 180))
	local signText = Instance.new("TextLabel")
	signText.Name = "Sign"
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = "BAGGAGE"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = model
end

-- ========== Airport landscaping ==========

-- Deciduous tree: trunk + spherical foliage canopy.
local function buildAirportTree(model: Model, base: CFrame)
	-- Trunk.
	pillar(model, base, 0, 1, 0, 5, 0.8, TRUNK, Enum.Material.Wood)
	-- Canopy layers (3 overlapping spheres for a full shape).
	add(model, base * CFrame.new(0, 5.5, 0), Vector3.new(3, 3, 3), FROND) -- mid layer
	add(model, base * CFrame.new(0, 7, 0), Vector3.new(2.5, 2.5, 2.5), FROND) -- top
	add(model, base * CFrame.new(0, 4.5, 0), Vector3.new(2.8, 2.8, 2.8), FROND) -- bottom
end

-- ========== Airport town buildings (fill the empty airport) ==========

-- Airport hotel: a 3-storey rectangular block with entrance and windows.
local function buildAirportHotel(model: Model, base: CFrame)
	-- Main body.
	add(
		model,
		base * CFrame.new(0, 7.5, 0),
		Vector3.new(24, 15, 18),
		Color3.fromRGB(210, 190, 160),
		{ material = Enum.Material.Concrete }
	)
	-- Roof cornice.
	add(model, base * CFrame.new(0, 15.3, 0), Vector3.new(25, 0.6, 19), Color3.fromRGB(180, 160, 140))
	-- Front doors.
	add(model, base * CFrame.new(0, 2.5, -9.1), Vector3.new(4, 4, 0.3), Color3.fromRGB(80, 50, 30))
	-- Windows row 1.
	for i = -2, 2 do
		add(
			model,
			base * CFrame.new(i * 4, 5, -9.1),
			Vector3.new(2.5, 2.5, 0.1),
			GLASS_AIRPORT,
			{ material = Enum.Material.Glass, transparency = 0.2 }
		)
	end
	-- Windows row 2.
	for i = -2, 2 do
		add(
			model,
			base * CFrame.new(i * 4, 10, -9.1),
			Vector3.new(2.5, 2.5, 0.1),
			GLASS_AIRPORT,
			{ material = Enum.Material.Glass, transparency = 0.2 }
		)
	end
	-- "HOTEL" sign.
	add(model, base * CFrame.new(0, 13, 0.1), Vector3.new(6, 1.2, 0.1), Color3.fromRGB(220, 180, 40))
	local sign = Instance.new("TextLabel")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Text = "HOTEL"
	sign.TextColor3 = Color3.fromRGB(255, 255, 255)
	sign.TextScaled = true
	sign.Font = Enum.Font.GothamBold
	sign.Parent = model
	-- Entrance canopy.
	add(
		model,
		base * CFrame.new(0, 5, -10),
		Vector3.new(5, 0.3, 3),
		Color3.fromRGB(180, 160, 140),
		{ material = Enum.Material.Metal }
	)
end

-- Restaurant / diner: low single-storey with large glass front and sign.
local function buildAirportRestaurant(model: Model, base: CFrame)
	-- Main body.
	add(
		model,
		base * CFrame.new(0, 4.5, 0),
		Vector3.new(18, 9, 14),
		Color3.fromRGB(200, 200, 200),
		{ material = Enum.Material.Concrete }
	)
	-- Accent band.
	add(model, base * CFrame.new(0, 6, 0), Vector3.new(18.5, 1, 14.5), Color3.fromRGB(220, 80, 60))
	-- Large glass front.
	add(
		model,
		base * CFrame.new(0, 3, -7.1),
		Vector3.new(14, 5, 0.1),
		GLASS_AIRPORT,
		{ material = Enum.Material.Glass, transparency = 0.2 }
	)
	-- Entrance.
	add(model, base * CFrame.new(0, 2, -7.2), Vector3.new(3, 3.5, 0.2), Color3.fromRGB(60, 60, 70))
	-- Roof.
	add(model, base * CFrame.new(0, 9.2, 0), Vector3.new(19, 0.5, 15), Color3.fromRGB(170, 170, 170))
	-- "RESTAURANT" sign on roof.
	add(model, base * CFrame.new(0, 11, 0.1), Vector3.new(10, 1.5, 0.1), Color3.fromRGB(220, 80, 60))
	local sign = Instance.new("TextLabel")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Text = "RESTAURANT"
	sign.TextColor3 = Color3.fromRGB(255, 255, 255)
	sign.TextScaled = true
	sign.Font = Enum.Font.GothamBold
	sign.Parent = model
end

-- Car rental / transport center: low wide building with bays.
local function buildCarRental(model: Model, base: CFrame)
	-- Main body.
	add(
		model,
		base * CFrame.new(0, 5, 0),
		Vector3.new(30, 10, 10),
		Color3.fromRGB(180, 200, 220),
		{ material = Enum.Material.Concrete }
	)
	-- Bay doors (open bays for cars).
	for i = -1, 1 do
		add(
			model,
			base * CFrame.new(i * 9, 3, -5.1),
			Vector3.new(6, 6, 0.3),
			Color3.fromRGB(140, 160, 180),
			{ material = Enum.Material.Metal }
		)
	end
	-- Roof.
	add(model, base * CFrame.new(0, 10.2, 0), Vector3.new(31, 0.5, 11), Color3.fromRGB(160, 180, 200))
	-- "CAR RENTAL" sign.
	add(model, base * CFrame.new(0, 8.5, 0.1), Vector3.new(8, 1.2, 0.1), Color3.fromRGB(30, 100, 200))
	local sign = Instance.new("TextLabel")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Text = "CAR RENTAL"
	sign.TextColor3 = Color3.fromRGB(255, 255, 255)
	sign.TextScaled = true
	sign.Font = Enum.Font.GothamBold
	sign.Parent = model
end

-- Cargo warehouse: tall industrial building with loading ramp.
local function buildCargoCenter(model: Model, base: CFrame)
	-- Main body (taller for cargo).
	add(
		model,
		base * CFrame.new(0, 8, 0),
		Vector3.new(20, 16, 20),
		Color3.fromRGB(170, 175, 185),
		{ material = Enum.Material.Concrete }
	)
	-- Roof.
	add(model, base * CFrame.new(0, 16.3, 0), Vector3.new(21, 0.5, 21), Color3.fromRGB(150, 155, 165))
	-- Loading doors.
	add(
		model,
		base * CFrame.new(-4, 5, -10.1),
		Vector3.new(4, 8, 0.3),
		Color3.fromRGB(180, 160, 60),
		{ material = Enum.Material.Metal }
	)
	add(
		model,
		base * CFrame.new(4, 5, -10.1),
		Vector3.new(4, 8, 0.3),
		Color3.fromRGB(180, 160, 60),
		{ material = Enum.Material.Metal }
	)
	-- Loading ramp.
	add(model, base * CFrame.new(0, 2, -14), Vector3.new(8, 4, 6), Color3.fromRGB(160, 160, 165))
	-- Cargo area fence.
	for _, x in { -6, 6 } do
		add(model, base * CFrame.new(x, 2, -14), Vector3.new(0.2, 4, 8), Color3.fromRGB(140, 140, 140))
	end
end

-- Generic office building (for the airport town): 4-storey modern block.
local function buildAirportOffice(model: Model, base: CFrame)
	-- Main body.
	add(
		model,
		base * CFrame.new(0, 10, 0),
		Vector3.new(12, 20, 12),
		Color3.fromRGB(190, 200, 210),
		{ material = Enum.Material.Concrete }
	)
	-- Glass strip (central windows).
	for floor = 1, 4 do
		add(
			model,
			base * CFrame.new(0, 3 + floor * 4, -6.1),
			Vector3.new(4, 3, 0.1),
			GLASS_AIRPORT,
			{ material = Enum.Material.Glass, transparency = 0.2 }
		)
	end
	-- Side windows.
	for floor = 1, 4 do
		for _, sx in { -4.2, 4.2 } do
			add(
				model,
				base * CFrame.new(sx, 3 + floor * 4, 0) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(0.1, 3, 2.5),
				GLASS_AIRPORT,
				{ material = Enum.Material.Glass, transparency = 0.2 }
			)
		end
	end
	-- Entrance.
	add(model, base * CFrame.new(0, 2, -6.2), Vector3.new(3, 4, 0.2), Color3.fromRGB(50, 50, 60))
	-- Roof parapet.
	add(model, base * CFrame.new(0, 20.5, 0), Vector3.new(13, 0.8, 13), Color3.fromRGB(170, 180, 190))
end

-- Jet bridge: the movable walkway connecting the terminal to the apron.
-- Reaches from the terminal face toward the apron/runway area.
local function buildJetBridge(model: Model, base: CFrame)
	-- Main corridor box (rectangular tunnel).
	add(
		model,
		base * CFrame.new(0, 5, 7.5),
		Vector3.new(3, 3.5, 12),
		Color3.fromRGB(200, 200, 210),
		{ material = Enum.Material.Concrete }
	)
	-- Roof ribs (structural bands along the corridor).
	for _, zOff in { -4.5, -1.5, 1.5, 4.5 } do
		add(model, base * CFrame.new(0, 6.8, 7.5 + zOff), Vector3.new(3.2, 0.2, 0.4), Color3.fromRGB(170, 170, 180))
	end
	-- Ceiling lights (glowing panels along top).
	for _, zOff in { -3, 0, 3 } do
		add(
			model,
			base * CFrame.new(0, 6.6, 7.5 + zOff),
			Vector3.new(2.5, 0.1, 1.5),
			Color3.fromRGB(255, 255, 230),
			{ material = Enum.Material.Neon }
		)
	end
	-- End panel (where the plane connects).
	add(model, base * CFrame.new(0, 5, 13.3), Vector3.new(2.5, 3, 0.3), Color3.fromRGB(170, 170, 180))
end

-- Tarmac runway markings: center stripe (long dashed line), boarding line (solid), edge lines.
-- These are taxi lines on the apron surface, guiding planes from the terminal to the runway.
local function buildAirportRunwayMarkings(model: Model, base: CFrame)
	-- Center line: dashed line running from the apron toward the runway.
	local dashLen = 3
	local gapLen = 2
	for i = 0, 14 do
		local zOff = -2 + i * (dashLen + gapLen)
		add(
			model,
			base * CFrame.new(0, 0.05, zOff),
			Vector3.new(0.4, 0.05, dashLen),
			YELLOW,
			{ material = Enum.Material.Neon }
		)
	end
	-- Boarding line (perpendicular line near the jet bridge).
	add(model, base * CFrame.new(0, 0.05, 12), Vector3.new(14, 0.05, 0.6), YELLOW, { material = Enum.Material.Neon })
	-- Edge lines (left and right boundaries).
	for i = -8, 8 do
		add(model, base * CFrame.new(-8, 0.05, i * 3.5), Vector3.new(0.3, 0.05, 2), Color3.fromRGB(220, 220, 225))
		add(model, base * CFrame.new(8, 0.05, i * 3.5), Vector3.new(0.3, 0.05, 2), Color3.fromRGB(220, 220, 225))
	end
end

-- "DEPARTURES" sign: tall signpost with billboard, placed near the terminal.
local function buildDeparturesSign(model: Model, base: CFrame)
	-- Signpost (pole).
	add(model, base * CFrame.new(0, 4, 0), Vector3.new(0.5, 8, 0.5), Color3.fromRGB(120, 120, 130))
	-- Billboard board.
	add(model, base * CFrame.new(0, 9, 0), Vector3.new(8, 3, 0.3), Color3.fromRGB(255, 255, 255))
	-- Blue background.
	add(model, base * CFrame.new(0, 9, 0.16), Vector3.new(7.5, 2.6, 0.05), Color3.fromRGB(30, 30, 200))
	-- Text label.
	local signText = Instance.new("TextLabel")
	signText.Name = "DeparturesSign"
	signText.Size = UDim2.fromScale(0.95, 0.85)
	signText.Position = UDim2.fromOffset(0, 0.2)
	signText.BackgroundTransparency = 1
	signText.Text = "DEPARTURES →"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = model
end

-- Luggage cart: a small rack on wheels, placed near the terminal entrance.
local function buildLuggageCart(model: Model, base: CFrame)
	-- Frame (basket shape).
	add(
		model,
		base * CFrame.new(0, 1, 0),
		Vector3.new(3, 2, 1.5),
		Color3.fromRGB(60, 60, 70),
		{ material = Enum.Material.Metal }
	)
	-- Handle bar.
	add(
		model,
		base * CFrame.new(0, 1.5, -1),
		Vector3.new(2.5, 0.2, 0.2),
		Color3.fromRGB(60, 60, 70),
		{ material = Enum.Material.Metal }
	)
	-- Wheels.
	add(
		model,
		base * CFrame.new(-1.2, 0.2, -0.5),
		Vector3.new(0.4, 0.4, 0.4),
		Color3.fromRGB(30, 30, 30),
		{ shape = Enum.PartType.Ball }
	)
	add(
		model,
		base * CFrame.new(1.2, 0.2, -0.5),
		Vector3.new(0.4, 0.4, 0.4),
		Color3.fromRGB(30, 30, 30),
		{ shape = Enum.PartType.Ball }
	)
end

-- Small shop / kiosk row: a low strip of 3 connected shops with awnings.
local function buildAirportShops(model: Model, base: CFrame)
	-- Main body (long narrow).
	add(
		model,
		base * CFrame.new(0, 4, 0),
		Vector3.new(24, 8, 8),
		Color3.fromRGB(220, 210, 195),
		{ material = Enum.Material.Concrete }
	)
	-- Awning / accent across top.
	add(model, base * CFrame.new(0, 8.3, 0), Vector3.new(25, 0.5, 9), Color3.fromRGB(200, 60, 60))
	-- Three shop fronts with doors.
	for i = -1, 1 do
		add(
			model,
			base * CFrame.new(i * 7, 2, -4.1),
			Vector3.new(4, 4, 0.2),
			Color3.fromRGB(230, 180, 80),
			{ material = Enum.Material.SmoothPlastic }
		)
	end
	-- Shop windows.
	for i = -1, 1 do
		for j = -1, 1 do
			add(
				model,
				base * CFrame.new(i * 7 + j * 1.5, 5, -4.1),
				Vector3.new(1.2, 2, 0.1),
				GLASS_AIRPORT,
				{ material = Enum.Material.Glass, transparency = 0.2 }
			)
		end
	end
	-- Roof.
	add(model, base * CFrame.new(0, 8.5, 0), Vector3.new(25, 0.5, 9), Color3.fromRGB(190, 180, 165))
end

-- Gas station: fuel island, canopy, and small convenience store.
local function buildAirportGasStation(model: Model, base: CFrame)
	-- Convenience store.
	add(
		model,
		base * CFrame.new(-6, 3.5, 0),
		Vector3.new(8, 7, 8),
		Color3.fromRGB(40, 100, 160),
		{ material = Enum.Material.Concrete }
	)
	add(model, base * CFrame.new(-6, 7.3, 0), Vector3.new(9, 0.5, 9), Color3.fromRGB(30, 80, 130))
	-- Canopy.
	add(model, base * CFrame.new(6, 7, 0), Vector3.new(10, 0.4, 6), Color3.fromRGB(40, 100, 160))
	-- Canopy pillars.
	for _, x in { 2, 6, 10 } do
		for _, z in { -2, 2 } do
			add(
				model,
				base * CFrame.new(x, 3.5, z),
				Vector3.new(0.3, 7, 0.3),
				Color3.fromRGB(160, 160, 170),
				{ material = Enum.Material.Metal }
			)
		end
	end
	-- Fuel island.
	add(model, base * CFrame.new(6, 0.5, 4), Vector3.new(3, 1, 2), Color3.fromRGB(160, 160, 170))
	-- Fuel pumps.
	for i = -1, 1 do
		add(
			model,
			base * CFrame.new(6 + i * 0.8, 1.5, 4.5),
			Vector3.new(0.6, 2, 0.6),
			Color3.fromRGB(60, 60, 70),
			{ material = Enum.Material.Metal }
		)
	end
end

-- Security checkpoint: small booth with X-ray conveyor.
local function buildSecurityBooth(model: Model, base: CFrame)
	-- Booth body.
	add(
		model,
		base * CFrame.new(0, 3, 0),
		Vector3.new(12, 6, 6),
		Color3.fromRGB(180, 190, 200),
		{ material = Enum.Material.Concrete }
	)
	-- Roof.
	add(model, base * CFrame.new(0, 6.3, 0), Vector3.new(13, 0.5, 7), Color3.fromRGB(160, 170, 180))
	-- "SECURITY" sign.
	add(model, base * CFrame.new(0, 5, 0.1), Vector3.new(6, 1.2, 0.1), Color3.fromRGB(220, 200, 40))
	local sign = Instance.new("TextLabel")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Text = "SECURITY"
	sign.TextColor3 = Color3.fromRGB(255, 255, 255)
	sign.TextScaled = true
	sign.Font = Enum.Font.GothamBold
	sign.Parent = model
	-- Conveyor belt outline.
	add(model, base * CFrame.new(0, 1, -3.2), Vector3.new(4, 1, 0.3), Color3.fromRGB(60, 60, 70))
end

-- Flagpoles: 3 tall poles with flags, placed near the terminal entrance.
local function buildAirportFlagpoles(model: Model, base: CFrame)
	-- Flagpoles at X=-4, 0, 4 (Z=0).
	for i = -1, 1 do
		local xOff = i * 4
		-- Pole (thin cylinder along Y).
		pillar(model, base, xOff, 12, 0, 24, 0.3, Color3.fromRGB(180, 180, 190), Enum.Material.Metal)
		-- Flag banner (flat plane at top).
		add(model, base * CFrame.new(xOff, 22, 0.3), Vector3.new(4, 2.5, 0.1), Color3.fromRGB(220, 60, 60))
		-- Flag pole top ball.
		add(
			model,
			base * CFrame.new(xOff, 24.5, 0),
			Vector3.new(0.5, 0.5, 0.5),
			Color3.fromRGB(200, 180, 50),
			{ shape = Enum.PartType.Ball }
		)
	end
end

-- Parking garage / car park: multi-level rectangular structure.
local function buildParkingGarage(model: Model, base: CFrame)
	-- Main body with open bays for parking levels.
	add(
		model,
		base * CFrame.new(0, 12, 0),
		Vector3.new(16, 24, 12),
		Color3.fromRGB(190, 195, 200),
		{ material = Enum.Material.Concrete }
	)
	-- Each level line (horizontal band).
	for level = 1, 3 do
		add(model, base * CFrame.new(0, level * 8, 6.1), Vector3.new(16, 0.3, 0.3), Color3.fromRGB(160, 165, 170))
		-- Columns at each corner.
		for _, x in { -7, 7 } do
			for _, z in { -5, 5 } do
				add(model, base * CFrame.new(x, level * 8, z), Vector3.new(0.5, 8, 0.5), Color3.fromRGB(160, 165, 170))
			end
		end
	end
	-- Roof.
	add(model, base * CFrame.new(0, 24.5, 0), Vector3.new(17, 0.5, 13), Color3.fromRGB(170, 175, 180))
	-- "P" sign.
	add(model, base * CFrame.new(0, 23, 0.1), Vector3.new(2, 2, 0.1), Color3.fromRGB(30, 120, 30))
end

-- Panoptic terminal: very long rectangular building behind all other airport buildings.
-- Glass facade facing the apron/driveway for panoramic airport views.
local function buildPanopticTerminal(model: Model, base: CFrame)
	-- Very long body (200 studs wide, 18 studs tall).
	add(model, base * CFrame.new(0, 9, 0), Vector3.new(200, 18, 12), Color3.fromRGB(190, 195, 200))
	-- Glass facade on the front (Z+ side, facing the apron).
	-- Multiple glass panels with dividers.
	local paneWidth = 20
	local paneCount = 8
	for i = 1, paneCount do
		local xOff = (i - (paneCount + 1) / 2) * (paneWidth + 2)
		add(model, base * CFrame.new(xOff, 9, 6.2), Vector3.new(paneWidth, 16, 0.3), GLASS_AIRPORT)
		add(
			model,
			base * CFrame.new(xOff + paneWidth / 2 + 1, 9, 6.2),
			Vector3.new(2, 16, 0.3),
			Color3.fromRGB(180, 185, 190)
		) -- frame divider
	end
	-- Solid back wall (interior).
	add(model, base * CFrame.new(0, 9, -6), Vector3.new(198, 16, 0.5), Color3.fromRGB(170, 175, 180))
	-- Roof overhang.
	add(model, base * CFrame.new(0, 18.5, 0), Vector3.new(204, 1, 16), CONCRETE)
	-- Entrance area (center).
	add(model, base * CFrame.new(0, 3, 6.2), Vector3.new(12, 6, 0.3), Color3.fromRGB(60, 60, 80))
end

type Placement = {
	id: string,
	zone: string,
	offset: Vector3,
	rotationY: number,
	scale: number?,
	build: (Model, CFrame) -> (),
}

-- The player's home is the CentralBuilding mesh on the plaza (assets/manifest.json); the
-- north-center square of the neighborhood grid is a free lot.
local PLACEMENTS: { Placement } = {
	-- Airport zone: terminals, control tower, baggage, commercial buildings, taxiway signs.
	-- Buildings are placed at Z >= 90 to keep clear of the taxi bezier (max Z ≈ 66).
	-- Taxi path: rollout X=220 → turn → park at X=150, Z=65 → taxi back to threshold.
	{
		id = "RunwayMarkings",
		zone = "Airport",
		offset = Vector3.new(0, 0, 40),
		rotationY = 0,
		build = buildAirportRunwayMarkings,
	},
	{ id = "JetBridge", zone = "Airport", offset = Vector3.new(0, 0, 90), rotationY = 0, build = buildJetBridge },
	-- Terminal cluster. The large walk-in arrivals terminal is built separately by TerminalService;
	-- what remains here is Terminal B, the control tower and the outbuildings.
	{
		id = "AirportTerminalB",
		zone = "Airport",
		offset = Vector3.new(200, 0, 100),
		rotationY = 0,
		build = buildAirportTerminalB,
	},
	{
		id = "ControlTower",
		zone = "Airport",
		offset = Vector3.new(250, 0, 130),
		rotationY = 0,
		build = buildControlTower,
	},
	{
		id = "BaggageBuilding",
		zone = "Airport",
		offset = Vector3.new(-200, 0, 100),
		rotationY = 0,
		build = buildBaggageBuilding,
	},
	-- Flagpoles at terminal entrance.
	{
		id = "AirportFlagpoles",
		zone = "Airport",
		offset = Vector3.new(0, 0, 95),
		rotationY = 0,
		build = buildAirportFlagpoles,
	},
	-- Security checkpoint near the terminal.
	{
		id = "SecurityBooth",
		zone = "Airport",
		offset = Vector3.new(-20, 0, 115),
		rotationY = 0,
		build = buildSecurityBooth,
	},
	-- Departures sign.
	{
		id = "DeparturesSign",
		zone = "Airport",
		offset = Vector3.new(-15, 0, 100),
		rotationY = 0,
		build = buildDeparturesSign,
	},
	{ id = "LuggageCart", zone = "Airport", offset = Vector3.new(-10, 0, 95), rotationY = 0, build = buildLuggageCart },
	-- Airport town buildings (Z ≈ 120-145, filling the far side of the apron).
	{
		id = "ParkingGarage",
		zone = "Airport",
		offset = Vector3.new(-250, 0, 120),
		rotationY = 0,
		build = buildParkingGarage,
	},
	{
		id = "AirportHotel",
		zone = "Airport",
		offset = Vector3.new(-250, 0, 145),
		rotationY = 0,
		build = buildAirportHotel,
	},
	{
		id = "AirportOffice",
		zone = "Airport",
		offset = Vector3.new(-220, 0, 110),
		rotationY = 0,
		build = buildAirportOffice,
	},
	{
		id = "CargoCenter",
		zone = "Airport",
		offset = Vector3.new(-140, 0, 120),
		rotationY = 0,
		build = buildCargoCenter,
	},
	{ id = "CarRental", zone = "Airport", offset = Vector3.new(-80, 0, 130), rotationY = 0, build = buildCarRental },
	{
		id = "AirportGasStation",
		zone = "Airport",
		offset = Vector3.new(-80, 0, 155),
		rotationY = 0,
		build = buildAirportGasStation,
	},
	{
		id = "AirportRestaurant",
		zone = "Airport",
		offset = Vector3.new(80, 0, 140),
		rotationY = 0,
		build = buildAirportRestaurant,
	},
	{
		id = "AirportShops",
		zone = "Airport",
		offset = Vector3.new(120, 0, 155),
		rotationY = 0,
		build = buildAirportShops,
	},
	-- Landscaping trees: spaced beside buildings and along the apron edge (Z > 80, away from taxi).
	-- Trees flanking the arrivals-terminal entrance (TerminalService builds it, centred at Z≈150).
	{ id = "Tree1", zone = "Airport", offset = Vector3.new(-56, 0, 118), rotationY = 0, build = buildAirportTree },
	{ id = "Tree2", zone = "Airport", offset = Vector3.new(56, 0, 118), rotationY = 0, build = buildAirportTree },
	-- Left cluster near ParkingGarage, Hotel, Office.
	{ id = "Tree5", zone = "Airport", offset = Vector3.new(-230, 0, 130), rotationY = 0, build = buildAirportTree },
	{ id = "Tree6", zone = "Airport", offset = Vector3.new(-230, 0, 155), rotationY = 0, build = buildAirportTree },
	{ id = "Tree7", zone = "Airport", offset = Vector3.new(-235, 0, 115), rotationY = 0, build = buildAirportTree },
	{ id = "Tree8", zone = "Airport", offset = Vector3.new(-205, 0, 115), rotationY = 0, build = buildAirportTree },
	-- Center cluster near CargoCenter, CarRental, GasStation.
	{ id = "Tree9", zone = "Airport", offset = Vector3.new(-160, 0, 130), rotationY = 0, build = buildAirportTree },
	{ id = "Tree10", zone = "Airport", offset = Vector3.new(-160, 0, 145), rotationY = 0, build = buildAirportTree },
	{ id = "Tree11", zone = "Airport", offset = Vector3.new(-100, 0, 145), rotationY = 0, build = buildAirportTree },
	{ id = "Tree12", zone = "Airport", offset = Vector3.new(-100, 0, 160), rotationY = 0, build = buildAirportTree },
	{ id = "Tree13", zone = "Airport", offset = Vector3.new(-60, 0, 145), rotationY = 0, build = buildAirportTree },
	-- Right cluster near Restaurant, Shops.
	{ id = "Tree14", zone = "Airport", offset = Vector3.new(100, 0, 155), rotationY = 0, build = buildAirportTree },
	{ id = "Tree15", zone = "Airport", offset = Vector3.new(100, 0, 170), rotationY = 0, build = buildAirportTree },
	{ id = "Tree16", zone = "Airport", offset = Vector3.new(140, 0, 155), rotationY = 0, build = buildAirportTree },
	{ id = "Tree17", zone = "Airport", offset = Vector3.new(140, 0, 170), rotationY = 0, build = buildAirportTree },
	-- Far apron edge row (Z ≈ 165).
	{ id = "Tree18", zone = "Airport", offset = Vector3.new(-180, 0, 165), rotationY = 0, build = buildAirportTree },
	{ id = "Tree19", zone = "Airport", offset = Vector3.new(-100, 0, 165), rotationY = 0, build = buildAirportTree },
	-- Panoptic terminal: very long rectangular building behind all existing airport buildings.
	-- Glass facade faces the apron/driveway for panoramic airport views.
	{
		id = "PanopticTerminal",
		zone = "Airport",
		offset = Vector3.new(0, 0, 200),
		rotationY = 0,
		build = buildPanopticTerminal,
	},
	-- Beach zone.
	{ id = "BeachCabana", zone = "Beach", offset = Vector3.new(0, 0, 0), rotationY = 0, build = buildBeachCabana },
	{ id = "PalmTree", zone = "Beach", offset = Vector3.new(-22, 0, 12), rotationY = 0, build = buildPalmTree },
	{ id = "SunLounger", zone = "Beach", offset = Vector3.new(14, 0, 6), rotationY = -90, build = buildSunLounger },
}

function SceneryService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end

	for _, placement in PLACEMENTS do
		local origin = Config.Zones[placement.zone]
		local base = CFrame.new(origin + placement.offset) * CFrame.Angles(0, math.rad(placement.rotationY), 0)
		local model = Instance.new("Model")
		model.Name = placement.id
		placement.build(model, base)
		if placement.scale then
			model:ScaleTo(placement.scale)
			-- ScaleTo grows about the pivot, dropping the base below the floor; reseat it to Y=origin.Y.
			local cf, size = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(0, origin.Y - (cf.Y - size.Y / 2), 0))
		end
		model.Parent = scenery
	end
end

return SceneryService
