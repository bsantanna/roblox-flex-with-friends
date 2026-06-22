--!strict
-- TerminalService: builds the Airport arrivals terminal -- the large enterable hall the cab drops
-- players into and the airport "safe zone". It is a sealed box (solid concrete floor, back wall, two
-- side walls and roof) with a glass facade facing the apron (-Z) so players look out over the
-- airfield. The facade panes are decorative; an invisible collidable barrier behind them seals the
-- front, so the player is contained no matter how the panes tile. The floor slab rests a hair above
-- the apron (Config.Terminal.Lift) so no surfaces sit coplanar (no z-fighting). Inside is purely
-- cosmetic dressing -- storefronts along the back wall, a waiting zone of seat rows facing the glass,
-- and two boarding-gate desks -- none of it functional. Geometry comes from Config.Terminal (centred
-- at Zones.Airport + Offset); everything is anchored, under Workspace.Scenery. PlaceService spawns
-- arriving players at the terminal centre (+ Config.Terminal.SpawnOffset).

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

local function addPart(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	canCollide: boolean?
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
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Scaled text on a part's Front face. Parts below are oriented so their Front points where the text
-- should read, so the caller never has to pick a NormalId.
local function labelFace(part: Part, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId.Front
	gui.Adornee = part
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = gui
	gui.Parent = part
end

-- A row of bucket seats on a shared rail. `cf` sits at floor level; local +X is the row direction and
-- the seats face local -Z. Collidable so a player can clamber on them, but non-functional (no Seat).
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

-- A storefront. `cf` at floor; the shop opens toward local -Z (into the hall), backdrop toward +Z.
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
	-- Counter + a couple of backdrop shelves.
	addPart(
		parent,
		"ShopCounter",
		cf * CFrame.new(0, 1.6, -0.9),
		Vector3.new(width - 2, 3.2, 1.4),
		Color3.fromRGB(180, 150, 110),
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
		cf * CFrame.new(0, H + 0.9, -0.1),
		Vector3.new(width - 0.5, 1.6, 0.3),
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

-- A boarding-gate desk with an overhead gate sign. `cf` at floor; the desk front (and sign text)
-- faces local -Z.
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

	-- Floor (slab bottom sits Lift above the apron) and roof.
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

	-- Front (-Z): an invisible collidable barrier seals the opening (the safe-zone wall); a glass
	-- facade in front reads as the frontage, framed by a concrete base and lintel.
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
	local paneCount = 9
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
		CFrame.new(cx, floorTop + sy + 2, frontZ - t),
		Vector3.new(20, 3, 0.5),
		ACCENT,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(board, "AIRPORT")

	-- ===== Cosmetic interior =====
	local floorCF = CFrame.new(cx, floorTop, cz)

	-- Storefronts along the back wall, opening toward the hall (-Z).
	local shopZ = halfZ - 1.6
	shop(model, floorCF * CFrame.new(-28, 0, shopZ), 22, "CAFÉ", Color3.fromRGB(150, 70, 50))
	shop(model, floorCF * CFrame.new(0, 0, shopZ), 22, "DUTY FREE", Color3.fromRGB(110, 70, 150))
	shop(model, floorCF * CFrame.new(28, 0, shopZ), 22, "NEWS", Color3.fromRGB(40, 130, 110))

	-- Waiting zone: two seat rows in the middle, facing the glass (-Z).
	seatRow(model, floorCF * CFrame.new(0, 0, 5), 14)
	seatRow(model, floorCF * CFrame.new(0, 0, -2), 14)

	-- Boarding-gate desks near the front, facing the hall (+Z, so rotate 180 about Y).
	local faceHall = CFrame.Angles(0, math.pi, 0)
	gateDesk(model, floorCF * CFrame.new(-30, 0, -halfZ + 5) * faceHall, "GATE 1")
	gateDesk(model, floorCF * CFrame.new(30, 0, -halfZ + 5) * faceHall, "GATE 2")

	-- Departures board mounted on the left wall, text facing into the hall (+X, so rotate +90 about Y).
	local depBoard = addPart(
		model,
		"DeparturesBoard",
		floorCF * CFrame.new(-halfX + 0.3, 9, 0) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(16, 6, 0.3),
		DARK_BOARD,
		Enum.Material.SmoothPlastic,
		nil,
		false
	)
	labelFace(depBoard, "✈ DEPARTURES", Color3.fromRGB(120, 230, 150))
end

return TerminalService
