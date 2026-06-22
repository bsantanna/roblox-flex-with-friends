--!strict
-- TerminalService: builds the Airport arrivals terminal -- the large enterable hall the cab drops
-- players into and the airport "safe zone". It is a sealed box (solid concrete floor, back wall, two
-- side walls and roof) with a glass facade facing the apron (-Z) so players look out over the
-- airfield. The facade panes are decorative; an invisible collidable barrier behind them seals the
-- front, so the player is contained no matter how the panes tile. The floor slab rests a hair above
-- the apron (Config.Terminal.Lift) so no surfaces sit coplanar (no z-fighting). The interior is purely
-- cosmetic dressing: a retail strip of shops along the back wall, a food-court row of stalls, a central
-- plaza with a bar and bistro tables, a waiting zone of seat rows facing the glass, and boarding-gate
-- desks. None of it is functional. Geometry comes from Config.Terminal (centred at Zones.Airport +
-- Offset); everything is anchored, under Workspace.Scenery. PlaceService spawns arriving players at the
-- terminal centre (+ Config.Terminal.SpawnOffset).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TerminalService = {}

local CONCRETE = Color3.fromRGB(185, 185, 190)
local FLOOR = Color3.fromRGB(150, 152, 158)
local GLASS = Color3.fromRGB(160, 200, 230)
local FRAME = Color3.fromRGB(120, 124, 132)
local ACCENT = Color3.fromRGB(45, 100, 180)
local SEAT = Color3.fromRGB(40, 90, 140)
local METAL = Color3.fromRGB(150, 154, 162)
local COUNTER_TOP = Color3.fromRGB(235, 235, 238)
local SHOP_WALL = Color3.fromRGB(225, 225, 228)
local DARK_BOARD = Color3.fromRGB(22, 24, 34)
local WOOD = Color3.fromRGB(120, 84, 52)
local DARKWOOD = Color3.fromRGB(74, 52, 36)
local SIGN_GOLD = Color3.fromRGB(255, 220, 120)

local function addPart(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	canCollide: boolean?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = if canCollide == nil then true else canCollide
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Big, unstretched text on a sign board's Front face. Three Roblox constraints force the approach:
-- TextScaled is unreliable on bare SurfaceGui labels (it can collapse to ~8px); TextSize is hard-capped
-- at 100; and a label whose em-box is taller than its SurfaceGui canvas renders nothing. So the text
-- gets its own transparent panel, sized taller than the band, with PixelsPerStud chosen so the capped
-- TextSize 100 yields caps ~95% of the *band* height -- the empty ascender/descender padding overflows
-- the band harmlessly (the panel is invisible). TextSize is reduced only if the word would exceed ~95%
-- of the band width, so long phrases fit the width instead of overflowing. SizingMode = PixelsPerStud
-- keeps the canvas aspect equal to the face's, so glyphs are never stretched. Parts below are oriented
-- so their Front points where the text reads.
local function labelFace(part: Part, text: string, color: Color3?)
	local H, W = part.Size.Y, part.Size.X
	local pps = math.clamp(72 / (0.95 * H), 1, 100) -- caps (~0.72 of the em) land at ~95% of the band
	local panel = Instance.new("Part")
	panel.Name = "LabelPanel"
	panel.Anchored = true
	panel.CanCollide = false
	panel.Transparency = 1
	panel.Size = Vector3.new(W, 100 / pps + 0.4, 0.2) -- canvas taller than the em-box so the text renders
	panel.CFrame = part.CFrame * CFrame.new(0, 0, -0.21) -- just in front of the coloured band
	panel.Parent = part

	local ref = game:GetService("TextService"):GetTextSize(text, 100, Enum.Font.GothamBold, Vector2.new(1e6, 1e6))
	local widthTextSize = (0.95 * W * pps) * 100 / math.max(ref.X, 1)
	local textSize = math.clamp(math.min(100, widthTextSize), 1, 100)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId.Front
	gui.Adornee = panel
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = false
	lbl.TextWrapped = false
	lbl.TextSize = textSize
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = gui
	gui.Parent = panel
end

-- A row of bucket seats on a shared rail. `cf` at floor; local +X is the row direction and the seats
-- face local -Z. Collidable so a player can clamber on them, but non-functional (no Seat).
local function seatRow(parent: Instance, cf: CFrame, seats: number)
	local pitch = 2.4
	local width = seats * pitch
	addPart(parent, "SeatRail", cf * CFrame.new(0, 0.6, 0), Vector3.new(width, 0.4, 2), METAL, Enum.Material.Metal)
	for i = 1, seats do
		local x = (i - (seats + 1) / 2) * pitch
		addPart(
			parent,
			"Seat",
			cf * CFrame.new(x, 1.5, 0),
			Vector3.new(pitch - 0.4, 0.4, 2),
			SEAT,
			Enum.Material.Fabric
		)
		addPart(
			parent,
			"SeatBack",
			cf * CFrame.new(x, 2.6, 0.9),
			Vector3.new(pitch - 0.4, 1.8, 0.3),
			SEAT,
			Enum.Material.Fabric
		)
		if i < seats then
			addPart(
				parent,
				"Armrest",
				cf * CFrame.new(x + pitch / 2, 2.0, 0),
				Vector3.new(0.2, 0.7, 1.8),
				METAL,
				Enum.Material.Metal,
				nil,
				false
			)
		end
	end
end

-- A storefront. `cf` at floor; the shop opens toward local -Z, backdrop toward +Z.
local function shop(parent: Instance, cf: CFrame, width: number, name: string, signColor: Color3)
	local H = 8
	addPart(
		parent,
		"ShopBack",
		cf * CFrame.new(0, H / 2, 1.4),
		Vector3.new(width, H, 0.3),
		SHOP_WALL,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	for _, sx in { -1, 1 } do
		addPart(
			parent,
			"ShopSide",
			cf * CFrame.new(sx * width / 2, H / 2, 0.4),
			Vector3.new(0.3, H, 2.4),
			Color3.fromRGB(200, 200, 205),
			Enum.Material.SmoothPlastic,
			nil,
			false
		)
	end
	addPart(
		parent,
		"ShopCounter",
		cf * CFrame.new(0, 1.6, -0.9),
		Vector3.new(width - 2, 3.2, 1.4),
		WOOD,
		Enum.Material.Wood
	)
	addPart(
		parent,
		"ShopCounterTop",
		cf * CFrame.new(0, 3.35, -0.9),
		Vector3.new(width - 1.6, 0.2, 1.6),
		COUNTER_TOP,
		Enum.Material.SmoothPlastic
	)
	for _, sh in { 4.6, 6.0 } do
		addPart(
			parent,
			"ShopShelf",
			cf * CFrame.new(0, sh, 1.1),
			Vector3.new(width - 2.2, 0.2, 0.8),
			Color3.fromRGB(210, 210, 214),
			Enum.Material.SmoothPlastic,
			nil,
			false
		)
	end
	-- Sign band (text faces -Z, into the hall) + awning.
	local sign = addPart(
		parent,
		"ShopSign",
		cf * CFrame.new(0, H + 1.1, -0.1),
		Vector3.new(width - 1, 2.4, 0.3),
		signColor,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(sign, name)
	addPart(
		parent,
		"ShopAwning",
		cf * CFrame.new(0, H - 0.4, -1.7),
		Vector3.new(width, 0.3, 2.2),
		signColor,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
end

-- A food-court kiosk. `cf` at floor; serves toward local -Z, with a canopy and an overhead menu sign.
local function foodStall(parent: Instance, cf: CFrame, width: number, name: string, color: Color3)
	local H = 7
	addPart(
		parent,
		"StallBack",
		cf * CFrame.new(0, H / 2, 1.1),
		Vector3.new(width, H, 0.3),
		color,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	addPart(
		parent,
		"StallCounter",
		cf * CFrame.new(0, 1.5, -0.8),
		Vector3.new(width - 1, 3, 1.2),
		Color3.fromRGB(205, 205, 210),
		Enum.Material.SmoothPlastic
	)
	addPart(
		parent,
		"StallCounterTop",
		cf * CFrame.new(0, 3.1, -0.8),
		Vector3.new(width - 0.6, 0.2, 1.5),
		COUNTER_TOP,
		Enum.Material.SmoothPlastic
	)
	addPart(
		parent,
		"StallCanopy",
		cf * CFrame.new(0, H, -1.1),
		Vector3.new(width + 0.6, 0.3, 2.6),
		color,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	local sign = addPart(
		parent,
		"StallSign",
		cf * CFrame.new(0, H + 1.2, -0.2),
		Vector3.new(width - 1, 2.2, 0.3),
		DARK_BOARD,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(sign, name, SIGN_GOLD)
end

-- A boarding-gate desk with an overhead gate sign. `cf` at floor; the desk front (and sign) face -Z.
local function gateDesk(parent: Instance, cf: CFrame, label: string)
	addPart(parent, "GateDesk", cf * CFrame.new(0, 1.5, 0), Vector3.new(5, 3, 2), ACCENT, Enum.Material.SmoothPlastic)
	addPart(
		parent,
		"GateDeskTop",
		cf * CFrame.new(0, 3.1, 0),
		Vector3.new(5.4, 0.2, 2.4),
		COUNTER_TOP,
		Enum.Material.SmoothPlastic
	)
	addPart(
		parent,
		"GatePost",
		cf * CFrame.new(2.2, 4.6, 0),
		Vector3.new(0.3, 6, 0.3),
		FRAME,
		Enum.Material.Metal,
		nil,
		false
	)
	local board = addPart(
		parent,
		"GateBoard",
		cf * CFrame.new(0, 7.6, 0),
		Vector3.new(6, 2, 0.3),
		DARK_BOARD,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(board, label, Color3.fromRGB(120, 230, 150))
end

-- A bistro table with three chairs -- the food-court / plaza seating. `cf` at floor.
local function bistroTable(parent: Instance, cf: CFrame)
	addPart(parent, "TableLeg", cf * CFrame.new(0, 1.25, 0), Vector3.new(0.5, 2.5, 0.5), METAL, Enum.Material.Metal)
	addPart(
		parent,
		"TableTop",
		cf * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.3, 3.2, 3.2),
		WOOD,
		Enum.Material.Wood,
		nil,
		true,
		Enum.PartType.Cylinder
	)
	for k = 0, 2 do
		local a = k * (2 * math.pi / 3)
		local px, pz = math.cos(a) * 2.4, math.sin(a) * 2.4
		addPart(parent, "Chair", cf * CFrame.new(px, 1.1, pz), Vector3.new(1.2, 0.3, 1.2), SEAT, Enum.Material.Fabric)
		addPart(
			parent,
			"ChairBack",
			cf * CFrame.new(px * 1.35, 1.9, pz * 1.35),
			Vector3.new(1.2, 1.4, 0.2),
			SEAT,
			Enum.Material.Fabric
		)
	end
end

-- The central bar: a square counter (open at the back for "staff"), a top overhang, a back gantry of
-- bottles, stools on the front, and a hanging BAR sign. `cf` at the plaza-floor centre.
local function centralBar(parent: Instance, cf: CFrame)
	-- Plaza floor accent (a polished disc marking the central plaza).
	addPart(
		parent,
		"PlazaFloor",
		cf * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.16, 40, 40),
		Color3.fromRGB(120, 124, 132),
		Enum.Material.Marble,
		nil,
		false,
		Enum.PartType.Cylinder
	)
	local bw, bd, bh = 16, 12, 3.2
	addPart(
		parent,
		"BarFront",
		cf * CFrame.new(0, bh / 2, -bd / 2),
		Vector3.new(bw, bh, 1.2),
		DARKWOOD,
		Enum.Material.Wood
	)
	for _, sx in { -1, 1 } do
		addPart(
			parent,
			"BarSide",
			cf * CFrame.new(sx * bw / 2, bh / 2, 0),
			Vector3.new(1.2, bh, bd),
			DARKWOOD,
			Enum.Material.Wood
		)
	end
	addPart(
		parent,
		"BarTop",
		cf * CFrame.new(0, bh + 0.15, 0),
		Vector3.new(bw + 1.6, 0.3, bd + 1.6),
		COUNTER_TOP,
		Enum.Material.SmoothPlastic
	)
	-- Back gantry with a row of bottles.
	addPart(
		parent,
		"BarGantry",
		cf * CFrame.new(0, 4.6, bd / 2 - 1),
		Vector3.new(bw - 2, 5.2, 0.5),
		Color3.fromRGB(55, 40, 30),
		Enum.Material.Wood,
		nil,
		false
	)
	local bottleColors = {
		Color3.fromRGB(120, 200, 120),
		Color3.fromRGB(200, 120, 120),
		Color3.fromRGB(120, 160, 220),
		Color3.fromRGB(220, 200, 120),
	}
	for i = -3, 3 do
		addPart(
			parent,
			"Bottle",
			cf * CFrame.new(i * 1.9, 3.4, bd / 2 - 1.2),
			Vector3.new(0.5, 1.5, 0.5),
			bottleColors[((i + 3) % #bottleColors) + 1],
			Enum.Material.Glass,
			0.15,
			false
		)
	end
	-- Stools along the front.
	for _, sx in { -6, -2, 2, 6 } do
		addPart(
			parent,
			"Stool",
			cf * CFrame.new(sx, 1.6, -bd / 2 - 1.8) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.2, 1.6, 1.6),
			DARKWOOD,
			Enum.Material.Wood,
			nil,
			true,
			Enum.PartType.Cylinder
		)
	end
	-- Hanging BAR sign over the front.
	addPart(
		parent,
		"BarSignPost",
		cf * CFrame.new(0, 9.5, -bd / 2 - 1),
		Vector3.new(0.3, 4, 0.3),
		FRAME,
		Enum.Material.Metal,
		nil,
		false
	)
	local sign = addPart(
		parent,
		"BarSign",
		cf * CFrame.new(0, 8, -bd / 2 - 1),
		Vector3.new(8, 2.6, 0.4),
		ACCENT,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(sign, "BAR")
end

function TerminalService:Start()
	local scenery = Workspace:FindFirstChild("Scenery")
	if not scenery then
		scenery = Instance.new("Folder")
		scenery.Name = "Scenery"
		scenery.Parent = Workspace
	end

	local model = Instance.new("Model")
	model.Name = "AirportArrivalsTerminal"
	model.Parent = scenery

	local T = Config.Terminal
	local center = Config.Zones.Airport + T.Offset
	local sx, sy, sz = T.Size.X, T.Size.Y, T.Size.Z
	local t = T.WallThickness
	local halfX, halfZ = sx / 2, sz / 2
	local cx, cz = center.X, center.Z
	-- Vertical reference: the floor slab rests `Lift` above the apron; floorTop is the walkable surface.
	local floorTop = center.Y + T.Lift + t

	-- Floor and roof.
	addPart(
		model,
		"Floor",
		CFrame.new(cx, floorTop - t / 2, cz),
		Vector3.new(sx + 2 * t, t, sz + 2 * t),
		FLOOR,
		Enum.Material.Concrete
	)
	addPart(
		model,
		"Roof",
		CFrame.new(cx, floorTop + sy + t / 2, cz),
		Vector3.new(sx + 2 * t, t, sz + 2 * t),
		CONCRETE,
		Enum.Material.Concrete
	)

	-- Back wall (+Z) and two side walls (solid concrete, full height).
	addPart(
		model,
		"BackWall",
		CFrame.new(cx, floorTop + sy / 2, cz + halfZ + t / 2),
		Vector3.new(sx + 2 * t, sy, t),
		CONCRETE,
		Enum.Material.Concrete
	)
	for _, side in { -1, 1 } do
		addPart(
			model,
			"SideWall",
			CFrame.new(cx + side * (halfX + t / 2), floorTop + sy / 2, cz),
			Vector3.new(t, sy, sz),
			CONCRETE,
			Enum.Material.Concrete
		)
	end

	-- Front (-Z): invisible collidable barrier seals the opening; a glass facade in front reads as the
	-- frontage, framed by a concrete base and lintel.
	local frontZ = cz - halfZ - t / 2
	addPart(
		model,
		"SafeZoneBarrier",
		CFrame.new(cx, floorTop + sy / 2, frontZ),
		Vector3.new(sx + 2 * t, sy, t),
		CONCRETE,
		Enum.Material.Concrete,
		1,
		true
	)
	local baseH, lintelH = 2, 2.5
	addPart(
		model,
		"FrontBase",
		CFrame.new(cx, floorTop + baseH / 2, frontZ - t),
		Vector3.new(sx + 2 * t, baseH, t),
		CONCRETE,
		Enum.Material.Concrete,
		nil,
		false
	)
	addPart(
		model,
		"FrontLintel",
		CFrame.new(cx, floorTop + sy - lintelH / 2, frontZ - t),
		Vector3.new(sx + 2 * t, lintelH, t),
		CONCRETE,
		Enum.Material.Concrete,
		nil,
		false
	)

	-- Decorative glass panes + vertical mullions across the front, between base and lintel.
	local glassH = sy - baseH - lintelH
	local glassY = floorTop + baseH + glassH / 2
	local paneCount = 18
	local pitch = sx / paneCount
	for i = 0, paneCount - 1 do
		local px = cx - sx / 2 + pitch * (i + 0.5)
		addPart(
			model,
			"GlassPane",
			CFrame.new(px, glassY, frontZ - t - 0.1),
			Vector3.new(pitch - 0.6, glassH, 0.3),
			GLASS,
			Enum.Material.Glass,
			0.4,
			false
		)
	end
	for i = 0, paneCount do
		local dx = cx - sx / 2 + pitch * i
		addPart(
			model,
			"Mullion",
			CFrame.new(dx, glassY, frontZ - t - 0.1),
			Vector3.new(0.6, glassH, 0.4),
			FRAME,
			Enum.Material.Metal,
			nil,
			false
		)
	end

	-- Exterior "AIRPORT" sign over the entrance, text on its apron-facing (-Z = Front) face.
	local board = addPart(
		model,
		"SignBoard",
		CFrame.new(cx, floorTop + sy + 2.5, frontZ - t),
		Vector3.new(40, 4, 0.5),
		ACCENT,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(board, "AIRPORT")

	-- ===== Cosmetic interior =====
	local floorCF = CFrame.new(cx, floorTop, cz)
	local faceBack = CFrame.Angles(0, math.pi, 0) -- so a part's Front (-Z) instead points +Z

	-- Retail strip: 6 shops along the back wall, opening toward the hall (-Z).
	local shopZ = halfZ - 1.6
	local shopNames = { "CAFÉ", "DUTY FREE", "NEWS", "BOOKS", "FASHION", "GIFTS" }
	local shopColors = {
		Color3.fromRGB(150, 70, 50),
		Color3.fromRGB(110, 70, 150),
		Color3.fromRGB(40, 130, 110),
		Color3.fromRGB(160, 120, 40),
		Color3.fromRGB(170, 60, 110),
		Color3.fromRGB(60, 110, 160),
	}
	for i = 1, 6 do
		local x = (i - 3.5) * 30
		shop(model, floorCF * CFrame.new(x, 0, shopZ), 28, shopNames[i], shopColors[i])
	end

	-- Food court: 4 kiosks in a row in front of the shops, facing the back/spawn (+Z).
	local foodNames = { "PIZZA", "SUSHI", "BURGERS", "NOODLES" }
	local foodColors = {
		Color3.fromRGB(200, 90, 60),
		Color3.fromRGB(70, 140, 170),
		Color3.fromRGB(190, 150, 70),
		Color3.fromRGB(150, 90, 160),
	}
	for i = 1, 4 do
		local x = (i - 2.5) * 30
		foodStall(model, floorCF * CFrame.new(x, 0, 22) * faceBack, 24, foodNames[i], foodColors[i])
	end

	-- Central plaza: the bar at the centre, ringed by bistro tables.
	centralBar(model, floorCF)
	for _, t2 in { Vector3.new(-26, 0, 11), Vector3.new(26, 0, 11), Vector3.new(-26, 0, -11), Vector3.new(26, 0, -11) } do
		bistroTable(model, floorCF * CFrame.new(t2.X, 0, t2.Z))
	end

	-- Waiting zone: two seat rows facing the glass (-Z).
	seatRow(model, floorCF * CFrame.new(0, 0, -26), 16)
	seatRow(model, floorCF * CFrame.new(0, 0, -33), 16)

	-- Boarding-gate desks near the front, facing the hall (+Z).
	for i = 1, 4 do
		local x = (i - 2.5) * 40
		gateDesk(model, floorCF * CFrame.new(x, 0, -halfZ + 5) * faceBack, "GATE " .. i)
	end

	-- Departures board on the left wall, text facing into the hall (+X, so rotate +90 about Y).
	local depBoard = addPart(
		model,
		"DeparturesBoard",
		floorCF * CFrame.new(-halfX + 0.3, 10, 0) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(20, 7, 0.3),
		DARK_BOARD,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(depBoard, "✈ DEPARTURES", Color3.fromRGB(120, 230, 150))
end

return TerminalService
